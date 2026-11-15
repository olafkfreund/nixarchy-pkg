---
title: Troubleshooting
---

# Troubleshooting

Arranged by what you noticed, not by what caused it.

## "I removed it and it is still installed"

The most common one, and it is not a fault.

You removed it from the **selection**. If the package is also declared
somewhere in your own NixOS configuration, that declaration is untouched and
still installs it. See [the boundary](how-it-works#the-boundary).

Check with:

```bash
grep -rn "the-package-name" ~/.config/nixos --include=*.nix
```

## "My packages are not listed"

Same cause, different symptom. The Selection tab lists what nixarchy manages,
which on a machine that had a configuration before nixarchy is a small
fraction of what is installed. [How it works](how-it-works) explains why, and
why making the list longer would be worse.

## "Nothing happened when I pressed the key"

Three likely reasons, in order:

1. **It was queued, not installed.** Look at the footer. If it says *1 change
   queued*, it worked — press `a`.
2. **The row was a `.settings` row** (`≡`). Those configure an app rather
   than being one; the panel says so in the message line.
3. **A writer refused.** The message line above the footer is where that
   appears. It is easy to miss and it is the machine answering you.

## "Everything says it is free"

The index is stale. A search index built before unfree and broken flags
existed carries none of them, so *every* package reads as free.

The panel says **index stale — r to rebuild** when this is the case. Press
`r`. It takes about a minute.

An absent flag is absent evidence, not a "no".

## "`a` seems to hang"

It is probably waiting for a password on a machine with no polkit agent to
show the prompt, or for an answer to a question the panel cannot draw.

Press `SHIFT+A` instead — the same apply, in a real terminal, where you can
see and answer whatever it wants.

## "An earlier write was interrupted"

A write — a toggle, a package, an option, a draft or an input — was cut off
before it finished, and the next one says so:

> an earlier write was interrupted. To put back what was there before, run:
> …/nixarchy-pkg recover. If the files look right as they are, run:
> …/nixarchy-pkg recover --discard. Nothing was changed.

The message names the script's full path. It is the plugin's own script, not
a command on your `PATH`:

```bash
~/.config/omarchy/plugins/nixarchy.pkg/bin/nixarchy-pkg recover            # put back what was there before
~/.config/omarchy/plugins/nixarchy.pkg/bin/nixarchy-pkg recover --discard  # keep the files as they are
```

If the message is instead "another write or an apply is running -- try again
when it finishes", something else holds the lock. Wait for it and try again.

The backup is in `~/.local/state/nixarchy/pkg-recovery/open/` (or under
`XDG_STATE_HOME`). Each file has an `N.path` naming its live file, and an
`N.data` holding its earlier contents (or `N.absent` if it did not exist), for
restoring by hand.

## "I pressed ESCAPE during a build and it kept going"

Correct. `ESCAPE` stops you watching the log; it does not stop the build. See
[Applying changes](applying).

## "It refused an unfree package"

It did not, quite. The writer adds the package and then tells you whether
your machine's licence policy will let the rebuild use it. If `allowUnfree`
is off — which is unusual, and means somebody turned it off deliberately — it
also scaffolds a *commented* `allowUnfreePredicate` naming just that package,
for you to uncomment.

Read the message line. That scaffold is a licence-policy edit sitting in your
`apps.nix`, commented out, waiting for you.

## "Adding from the other channel wants two presses"

Yes. The channels share no store paths, so it brings an entire second
closure — `nixarchy doctor` measures vlc at 1.5 GB. The first press tells you
what it will cost; the second does it. See [Packages](packages#the-other-channel).

## "I want to see what it would do, without a panel"

```bash
nixarchy-pkg pending | jq
```

[From a terminal](from-a-terminal) has the rest.

## "queue unknown"

The footer says `queue unknown -- <error>` (and pressing `a` says `queue
unknown -- press r`) when `pending` failed or could not read a selection or
flake file (falling back to `could not read the queue` if the adapter gave no
error text). Press `r` on the Queue tab to read the queue again, or run:

```bash
nixarchy-pkg pending
```

## "<file> was edited in the flake"

`nixarchy-apply` records the SHA-256 of each file it writes under
`~/.local/state/nixarchy/applied/`. When a destination file in the flake no
longer matches that record and your live file also differs from it, the Queue
tab shows a conflict row:

- `<file> was edited in the flake -- apply will keep a copy and overwrite it`
  for `apps.nix`, `services.nix`, `advanced.nix` and `flatsnap.nix`
- `<file> was edited in the flake -- apply will stop` for a draft in
  `packages/*.nix`

Press `RETURN` on the row to inspect the diff hunk before applying.

## "a file changed since you reviewed it"

When you arm `a` or `SHIFT+A`, the panel pins the SHA-256 of `apps.nix`,
`services.nix`, `advanced.nix` and `flatsnap.nix`. If one of those files
changes before `nixarchy-apply` copies it, the apply stops before copying or
building and reports:

> a file changed since you reviewed it -- nothing was copied or built; look at
> the queue again

Open the Queue tab, check what changed, and press `a` again.

## "superseded -- press c again"

Your selection changed while `c` (`nixarchy-pkg check`) was running, or after
it finished, so the check verdict no longer matches the files on disk. Press
`c` (or `SHIFT+C`) to check the new selection.

## "the check was interrupted"

A running check received a signal (or was cancelled) before it finished and
answered `the check was interrupted (exit <rc>)`. Its temporary directory
under `~/.local/state/nixarchy` was cleaned up; press `c` to run it again.

## "could not check: a write is in progress or was interrupted -- try again, or run recover"

`~/.local/state/nixarchy/pkg-recovery/open` exists, which means a write is
currently running or an earlier write was cut off. Wait a moment and press `c`
again, or run `recover` as shown in [An earlier write was interrupted](#an-earlier-write-was-interrupted).

## "could not check: the flake's nixarchy directory is a symlink -- the check will not write through it"

The flake host base directory, `nixarchy/`, or `nixarchy/packages/` is a
symbolic link. The check refuses to overlay files through a symlink into a
target outside its private copy; replace the symlink with a real directory in
the flake if you want `c` to evaluate it.

## "could not check: this flake reads its own git revision; a copy would evaluate differently"

A tracked `.nix` file in the flake references `self.rev`, `self.shortRev`,
`self.dirtyRev`, `self.dirtyShortRev`, `self.lastModified`, or
`self.lastModifiedDate`. Because `check` evaluates a `path:` copy rather than
the git repository itself, those attributes would not match what a real apply
sees.

## "could not check: this flake has a relative path input; a copy would not resolve it"

`flake.lock` contains a `path` input whose path does not start with `/`. A
copy of the flake under `~/.local/state/nixarchy` would look for that relative
path in the wrong parent directory.

## "could not check: this flake has git submodules; the check does not copy them"

The flake's git index contains submodule entries (`160000`). `check` copies
only the flake's tracked files and does not check out or copy submodules.

## "could not check: could not copy the flake: …" / "git failed: …"

`git`, `tar` or `cp` failed while snapshotting the flake into
`~/.local/state/nixarchy` (for example, unreadable files or a full disk). The
first line of stderr follows the colon; press `RETURN` on the row to read it.

## "could not check: timed out after 15 minutes"

Evaluating the host configuration (or the `--dry-run` step) took longer than
900 seconds and was stopped.

## Still wrong

`nixarchy doctor` checks the machine rather than the panel, and is the right
next step for anything that smells like configuration rather than interface.

If it is the panel, the source is small and commented:
[github.com/olafkfreund/nixarchy-pkg](https://github.com/olafkfreund/nixarchy-pkg).
