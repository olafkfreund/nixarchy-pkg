---
status: draft
issue: 60
author: olafkfreund
---

# Intent: before apply, show what it will really do, and whether it will build

## Problem

The panel's only account of what an apply will change is a number: "4 changes
queued" in the footer and a badge on the bar. That number is often wrong, the
user cannot see what it counts, and nothing between "queued" and "build and
switch" tells them whether the result will even evaluate.

**1. The count misses real changes.**
`pending` diffs only lines carrying a `#@` marker (`bin/nixarchy-pkg`,
`marked()` and `pending_changes()`). Changes it never sees, all of which apply
does copy into the flake:

- an edit inside a multi-line `firefox.settings = { … };` block (the panel
  itself tells users to edit `apps.nix` for these);
- anything in `advanced.nix`, which exists to hold unmarked Nix;
- a hand edit to a marked line's value that keeps its marker (it shows as a
  change only if the marked line's text differs; a change on the next line
  does not).

All of these report "nothing queued", and apply then rebuilds anyway.

**2. The count can merge changes that are different.**
Changes are grouped by marker without the file name (`cmd_pending`'s
`group_by(.marker)`). The same marker in two files collapses into one change.
Codex reproduced this on 2026-11-15.

**3. The user cannot see what is queued.**
`pending` already returns a `changes` array (marker, file, line, on/off/added/
removed). The panel reads only `count` (`PkgModel.qml:298`, `Panel.qml:53`)
and throws the list away. The apply then runs with `--yes --no-preview`
(`cmd_apply`), so there is no point at which the user looks at the change
before the machine switches.

**4. "Accepted" does not mean "will build".**
A value is checked only with `nix-instantiate --parse`. A wrong type
(`services.openssh.ports = "22"`), an option that does not exist, a failed
assertion or a conflict with the user's own modules is accepted, queued, and
fails only when apply evaluates the system. On this machine that is 68 s into
the apply (measured: evaluating `nixosConfigurations.p620`'s toplevel). The
error then names a line in the flake's copy, not the edit the user made.

**5. Errors look like "all clear".**
- When `pending` fails, the bar is wrong either way. Output it cannot parse
  shows 0 queued (`Panel.qml:58`). An `ok:false` answer leaves the previous
  count up, with no sign that it is stale (`Panel.qml:52`).
- `reindex` throws away its error (`cmd_reindex` sends everything to
  `/dev/null` and reports only "still stale").
- The search index goes stale silently. On this machine it was 13 days old,
  with every input changed, and nothing rebuilt it until the user pressed `r`.

**6. Apply does not pin what was reviewed.**
`nixarchy-apply` can refuse to build files that changed after the caller
checked them (`--expect-sha256 <part>=<sha256>`, #979 in nixarchy). The panel
never passes it, so a file edited after the user looked (by hand, a script, or
a second panel) is built anyway.

## Proposed outcome

- **The count is honest.** "Nothing queued" means apply would copy nothing
  new. Every change apply would copy is counted, including unmarked edits and
  `advanced.nix`, and two changes are never merged into one.
- **The user can read the queue.** It lists each change in plain words
  ("brave on", "services.openssh.ports set", "advanced.nix: 3 lines
  changed"), shows the raw lines on request, and lets them drop one change
  before applying.
- **"Will it build" is answered before the switch, and without one.** The
  user can ask for a check, or it runs on its own when cheap enough. It
  evaluates the real host with the queued files and reports either "builds"
  or the error, naming the queued line it comes from where that can be
  worked out. It never switches and never needs root.
- **What was reviewed is what is built.** Apply from the panel passes the
  hashes of the files the user saw. A file that changed since then is
  refused with a message, not built.
- **Failures are visible.** When `pending` or `reindex` fails, the panel says
  so instead of showing 0 or "stale". A stale index says how old it is.
- `nixarchy-pkg pending` stays one JSON object; its existing fields keep
  their meaning, so terminal users and scripts do not break.

## Affected users and systems

- Everyone who applies from the panel, and anyone using `nixarchy-pkg pending`
  from a terminal.
- `bin/nixarchy-pkg`: `pending_changes`, `cmd_pending`, `cmd_apply`,
  `cmd_reindex`, and a new read-only check.
- `PkgModel.qml`, `Card.qml`/`Menu.qml` (a queue view), `Panel.qml` (bar
  count and its error state).
- `tests/adapter.sh`, `tests/qml/`.
- Outside this repo: `nixarchy-apply`'s `--expect-sha256` contract, used
  as it stands, and the flake layout it copies into (`hosts/<host>/nixarchy/`).
- Verification host is **razer**. Never p620. (p620's 68 s was a one-off
  read-only `nix eval`.)

## Constraints

- **Never switch, never elevate, never write the flake** from the new check.
  It may evaluate, and may build in the user's store if the spec chooses that.
  It must not activate anything.
- Must not slow the panel: no evaluation on every keystroke or toggle. An
  evaluation is tens of seconds and must run in the background, be
  cancellable, and never block a write.
- Must not change the meaning of existing `pending` fields
  (`count`, `changes[].marker/file/line/change`, `neverApplied`, `base`).
- Must work when the machine has never applied (`neverApplied: true`), and
  when the flake is not at `/etc/nixos`.
- Must hold the #59 guarantees: the check is a read, takes no lock, and
  ignores a write in progress rather than waiting for it.
- No secrets in the output. A diff of `apps.nix` can contain a value the user
  typed, so the queue view shows the user's own lines and nothing reaches a
  log or an external service.

## Open questions

1. **What does the check evaluate, and against what?** Evaluate the host's
   toplevel `drvPath` with the queued files overlaid on a copy of the flake
   (exact, about 68 s here), or only the user's module against the option
   declarations (fast, but misses conflicts with other modules)? Recommended:
   the real host, run on demand and when the queue settles, never per edit.
2. **Should it also build** (`nix build --dry-run`, or a real build without
   switching, with an `nvd`-style package diff)? It is far more useful
   ("firefox 132 → 133, +2 packages, 1.4 GB to download") and far slower.
   Recommended: dry-run size and package diff in this task, full build left
   to apply.
3. **Drop one change from the queue:** revert that one line in
   `~/.config/nixarchy/*.nix` to the applied copy, or only offer to open the
   file? Reverting is a write under #59's lock and guard. Recommended: revert
   for marked rows, open-in-editor for unmarked hunks.
4. **Scope:** the stale index (part of problem 5) could be its own small
   task. Fold it in or split it out? Recommended: keep the "say how old"
   message here, and split automatic reindexing into its own task.
5. **#66 overlap:** `apply` should refuse while an interrupted write is open
   (#66). It touches the same `cmd_apply`. Fold #66 in? Recommended: yes,
   it is three lines on the same path.
