---
title: Applying changes
---

# Applying changes

Everything else in this manual edits a file. This is the part that changes
the machine.

## `a`

Press `a`, and then `a` again: the first press says `reading the queue…`,
reads the selection files afresh, and only then arms with what will happen:

```
a again to rebuild: 2 changes -- any other key cancels
```

If any destination file in the flake was edited directly, the prompt says so
too (`-- 1 edited in the flake`). Any other key, or five seconds, cancels.
Pressing `a` again while the read is still running says `still reading the
queue`; if a write is open when the read returns, it disarms with `a write is
in progress -- try again in a moment`; if the queue changed while armed, it
disarms with `the queue changed -- review it again`. The second press starts
the rebuild and fills the card with the build log.

What runs is `nixarchy-apply`: it copies your selection into the flake
directory and rebuilds. It needs a password, and it gets one through your
polkit agent — Omarchy runs one as an always-loaded service, so the prompt
appears on screen in the same shell the panel lives in.

The log is streamed as plain text, because it is somebody else's build output
and nothing here should pretend to understand it. When it finishes, the last
line is the result.

## `SHIFT+A`

The same apply, in a real terminal instead (`SHIFT+A again to rebuild: …`).

That is the route for two situations:

- a machine with **no polkit agent** to answer the password prompt, where `a`
  would sit there waiting for something that cannot happen
- any apply that **asks a question the panel cannot show** — a prompt, a
  confirmation, a conflict

If `a` seems to hang, try `SHIFT+A` before assuming anything is broken.

## The Queue tab

The **Queue** tab lists everything `nixarchy-apply` will copy, not only
marked catalogue lines. Each row is one of six kinds:

| Row | What it means |
| --- | --- |
| `check` | The running check (`checking… (about a minute) -- ESC cancels`) or its verdict |
| `conflict` | A destination file in the flake was edited directly: `<file> was edited in the flake -- apply will keep a copy and overwrite it` for a selection part, or `<file> was edited in the flake -- apply will stop` for a draft |
| `writing` | `a write is in progress or was interrupted -- the queue may be out of date` |
| `change` | A marked line that changed: `<name> on`, `off`, `added`, `removed`, or `changed` (`(<file>.nix:<line>)`, or `(<file>.nix)` for removals) |
| `file` | A file change not already explained by marked rows: `<file>: N lines changed`, `<file>: new`, `<file>: no longer imported`, or `<file>: whitespace or comments changed` |
| `note` | What pinning cannot cover: `not pinned: the flake's own files` (plus `, and drafts: packages/…` when drafts exist) |

The keys on the Queue tab are:

| Key | What it does |
| --- | --- |
| `c` | Check whether the queued selection evaluates |
| `SHIFT+C` | Check, and if it evaluates, run a dry-run build |
| `r` | Read the queue again |
| `RETURN` | Open the live file in your editor, or show the row's diff hunk, line or error |
| `ESC` | Close the detail view, or cancel a running check |

## Checking before you apply

Press `c` on the Queue tab to evaluate this machine's configuration against a
private copy of your flake and selection. Press `SHIFT+C` to follow a
passing evaluation with `nix build --dry-run`.

The check finishes with one of four verdicts:

- `evaluates ✓` — the configuration evaluated. With `SHIFT+C`, the row adds
  `-- B to build, F to fetch (M MiB)` (or `-- dry run: <error>` if the dry
  run failed). If a changed draft was edited in the flake, it adds
  `-- apply will stop: packages/<name>.nix was edited in the flake`.
- `fails: <summary> (<file>:<line>, as checked)` — evaluation failed. Press
  `RETURN` on the row to read the last 200 lines of Nix's error output, with
  store and copy paths rewritten back to your selection and flake files.
- `superseded -- press c again` — a selection file changed while the check was
  running or after it finished.
- `could not check: <reason>` — the check declined to run because a copy
  would not match the real flake or a write is open. Press `RETURN` to see
  the reason, or see [Troubleshooting](troubleshooting).

A passing check is **evidence, not a guarantee**: it checks evaluation only,
not a build or a switch, and `nixarchy-apply` evaluates again for real. If
`allow-import-from-derivation` is on, evaluating may also build some inputs.

## Pinning, and what stays unpinned

When `a` or `SHIFT+A` arms after reading the queue, it freezes the SHA-256
hash of each of the four selection parts — `apps.nix`, `services.nix`,
`advanced.nix`, and `flatsnap.nix` — from the matching `evaluates` check if
there is one, or from the fresh queue read.

Confirming passes those hashes to `nixarchy-apply` (`--expect-sha256`). If
any of the four parts changed on disk after you armed, `nixarchy-apply` stops
before copying or building:

```
a file changed since you reviewed it -- nothing was copied or built; look at the queue again
```

Two things stay **unpinned**: the flake's own files, and drafts in
`packages/*.nix`. `nixarchy-apply` pins only the four selection parts, so the
Queue tab always shows `not pinned: the flake's own files` (and `, and
drafts: …` when you have any).

## `ESCAPE` while it is building

Stops watching the log. **It does not stop the build.**

This is worth being precise about, because the two were once conflated here
and the result was a bug. The build keeps going: it is elevating,
downloading, switching a system. Stopping it half way is never what `ESCAPE`
meant, and a rebuild interrupted mid-switch is a considerably worse place to
be than one you stopped watching.

If you want the build gone, deal with it where it runs, not by closing a
window.

## What "queued" means

The count in the footer and in [the bar](the-bar) is `total` from `pending`:
every marked change, plus every changed or new selection file whose diff is
not already explained by those marked rows. While the queue is being read it
says `reading queue…`; if the read fails it says `queue unknown -- <error>`
(and `a` says `queue unknown -- press r`).

That is asked of the files every time rather than remembered, which is why
two panels open at once cannot disagree, and why editing
`~/.config/nixarchy/apps.nix` in an editor shows up here without anything
being told about it.

**never applied** means the flake-side copy does not exist yet. The first
apply creates it.

## Afterwards

It is a NixOS generation. If the result is wrong, the previous one is still
there and still bootable — that is the property the whole two-step dance buys
you, and it is the reason this plugin queues changes instead of installing
them.
