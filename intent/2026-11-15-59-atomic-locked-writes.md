---
status: draft
issue: 59
author: olafkfreund
---

# Intent: a write that fails, or races another, leaves the user's files recoverable and says so

## Problem

#39 settled what a *successful* write must preserve: the file's inode, so its
mode, owner and symlink survive. It did that by swapping `mv` for `cp` at every
write site and relying on the backup for safety: "It preserves the one property
(atomicity) that the backup already covers" (`spec/2026-09-24-39-write-integrity.md`).
That left #39 contradicting itself. Its intent requires that "a partial write
must never be visible at the real path", while its spec accepts an in-place `cp`
that truncates first. The backup does not close the gap. A three-way review on
2026-11-15 (Claude, Codex, agy) found four ways a write that does not finish
cleanly still damages or loses the user's configuration. Codex reproduced the
first, second and fourth in `/tmp`.

**1. An interrupted write truncates the file, and its backup is stranded where
nobody will find it.**
`cp "$tmp" "$APPS"` (`bin/nixarchy-pkg:590`, `:680`) and `cp "$tmp" "$file"`
(`:956`, `:1071`) open the live file with `O_TRUNC` and then write it. A full
disk, a quota or a signal between those two leaves `apps.nix` or
`/etc/nixos/flake.nix` empty or cut short. Under `set -e` the script exits at
the failed `cp`, before its restore line. The `RETURN` traps
(`:562`, `:659`, `:930`, `:1061`) do not run when `errexit` or `die` (which
calls `exit`) ends the script; checked: a function that fails under `set -e`
leaves its `mktemp` file behind. So the backup survives, but as an unnamed
`/tmp/tmp.*` file, and the answer is no JSON at all. The user has a truncated
file, a panel that cannot say what happened, and no idea a copy exists.

The same `exit` means every `die` after a backup is taken (a parse refusal, a
lock failure) leaves the backup and temp copies of `apps.nix` or `flake.nix`
in the temp directory. `$tmp` is also missing from the traps in `cmd_opt_set`,
`cmd_opt_replace` and `cmd_flake_add`, so even a successful write leaves one.

**2. Two writes at once lose one of them, even when both succeed.**
Nothing serialises read–modify–write–restore. Two valid writes: A reads
`apps.nix`, B writes its change, A copies its version (built from the old
read) over it, and both answer `ok: true`, but only A's change is in the file.
A failing write is worse: A fails its parse check and restores a backup taken
before B ran, erasing B's change. Two panels, the panel and a terminal, or a
script and the panel are enough. None of the external writers the adapter calls
lock either (`nixarchy-app-enable`, `-service-enable`, `-pkg-add`, `-pkg-remove`,
`-opt-remove`: no `flock`), and `app-enable` and `service-enable` still `mv`
over the file, which is the inode replacement #39 removed here. Only
`nixarchy-apply` holds a lock
(`${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/applied/lock`).

**3. The panel lets you write while an apply is running, and cannot see most
applies.**
`PkgModel.write()` (`PkgModel.qml:346`) and `OptionForm.commit()`
(`OptionForm.qml:278`) refuse while `busy`, but not while `applying`. `ESC`
detaches the build log and leaves `applying` set, after which a toggle, an
option or `flake add` edits `apps.nix`, `flake.nix` or `flake.lock` while
`nixarchy-apply` is copying them or `nh` is evaluating them. Panel state cannot
fix this alone: `applyInTerminal()` (`:637`) launches `nixarchy-apply` in a
terminal without ever setting `applying`, and an apply started from the user's
own terminal is invisible to the panel. When `write()` does refuse, it says
nothing.

**4. A `flake add` or `flake remove` that fails can leave `flake.lock`
changed.**
Whether a lock file existed is recorded before any Nix call (`:906`), but its
*contents* are backed up only after `nix flake metadata` has run (`:932`, then
`:942`; `:1011`, then `:1065`), and that command can rewrite an outdated lock.
Each failure path then misses it in its own way:

- the first `metadata` call failing `die`s with nothing restored;
- `flake remove`'s two refusals (`:1038`, `:1054`) come after `metadata` and
  before any backup;
- `flake remove`'s parse-failure branch (`:1073`) restores `flake.nix` but not
  the lock;
- the lock backup itself is `cp "$lock" "$block" || :` (`:942`, `:1065`), so a
  backup that fails (the low-disk case this task is about) is ignored and the
  write goes ahead without one.

## Proposed outcome

Two kinds of failure, held to different standards, because a killed process
cannot answer:

- **A failure the adapter survives** (write error, full disk, validation
  refusal, lost lock race, a signal it can catch): the live file is restored
  automatically. If restoring also fails, the answer is `{ok:false, error}` and
  names the backup's path.
- **Abrupt termination** (`SIGKILL`, the shell dying, power loss): a complete
  copy of the file as it was before the write survives at a fixed, documented
  path the user can find and restore from. Power loss is covered only as far
  as the filesystem keeps what was flushed.

And in both cases, and on success:

- Writes made through `nixarchy-pkg` (panel or CLI) and applies made through
  `nixarchy-apply` never run at the same time. A write that cannot start within
  a short bound is refused with a message saying what holds it. It never
  silently queues or hangs. Writes made by the external `nixarchy-*` writers
  outside this adapter are not covered until those writers take the same lock.
- The panel refuses writes while any apply holds that exclusion, whether
  started from the panel, its terminal, or the user's own terminal, and says
  why. It refuses to start an apply while a write is in progress.
- Any `flake add` or `flake remove` that answers `ok: false` leaves `flake.nix`
  and `flake.lock` byte-identical to before the call, or names the backup it
  could not restore from.
- No copy of the user's config is ever written to the system temp directory.
  Any working or backup copy lives in a user-private state directory and is
  removed once it is no longer needed.
- After a successful write, everything #39 guarantees still holds: same
  inode, mode, owner and symlink.
- Tests fail if any of the above regresses, and `nix flake check` runs them,
  which it does not run `tests/adapter.sh` today.

## Affected users and systems

- Everyone who writes through the panel or the `nixarchy-pkg` CLI. Most
  exposed: anyone low on disk, anyone with the panel open on two monitors,
  anyone who scripts `nixarchy-pkg` while the panel is up, anyone who presses
  `ESC` during an apply or uses `SHIFT+A`.
- `bin/nixarchy-pkg`: `cmd_opt_set`, `cmd_opt_replace`, `cmd_flake_add`,
  `cmd_flake_remove`, `run_writer`, `die`.
- `PkgModel.qml` (`write`, `apply`, `applyInTerminal`), `OptionForm.qml`
  (`commit`).
- `tests/adapter.sh`, `flake.nix` checks.
- Outside this repo, in nixarchy: the five external writers (no lock, two
  `mv`) and `nixarchy-apply`'s lock. This task does not change them; it needs
  a companion nixarchy issue for the writers.
- Verification host is **razer**, per repo convention. Never p620.

## Constraints

- Must keep #39's guarantees for a successful write: the live file's inode,
  mode, owner and symlink survive. Going back to `mv`/`rename` is not a fix.
  This task replaces #39's mistaken assurance ("the backup already covers"
  atomicity) with recovery that works. It does not reintroduce atomic
  visibility, which is not possible in place without root.
- Must not create working or backup files beside the target. `/etc/nixos` may
  be a directory the user cannot write, `apps.nix` may be a symlink into a
  dotfiles repo, and `flake remove` searches the flake for `*.nix` files.
- Must not require root or elevate. Elevation stays with `nixarchy-apply`.
- Must not change the adapter's JSON contract. Every new failure is
  `{ok:false, error}` like every other.
- Must never block the panel indefinitely, and must not deadlock against
  `nixarchy-apply`, which holds its lock through interactive prompts
  (nixarchy #1276).
- Any shared lock or state path must follow `XDG_STATE_HOME` exactly as
  `nixarchy-apply` does, or the two lock different files.
- No new runtime dependency beyond what the adapter or nixarchy already ships
  (`flock` is util-linux, already on `nixarchy-apply`'s PATH).
- A backup must be no more readable than the file it backs up.

## Open questions

1. **What may a write wait for?** Recommended (Codex, agy, Claude): writes and
   applies share one exclusion, `nixarchy-apply`'s existing lock. A write
   waits a few seconds at most, then refuses with "an apply is running". Cost:
   a write is refused for as long as an apply sits at a prompt, which is the
   same rule `nixarchy-apply --yes` already follows.
2. **Ship before the external writers lock?** Recommended: yes. Land this
   with the limited guarantee stated above, and file a nixarchy issue for the
   five writers (lock, and drop `mv`) as a linked dependency. Holding this back
   would leave four reproduced data-loss bugs open to close a rarer race.
3. **Is "recoverable, with a findable backup" enough?** Recommended: yes.
   "Never truncated" cannot be had in place without `rename`, which #39
   ruled out. If the answer is no, #39's inode decision has to be reopened
   first.
4. **One task with the UI interlock?** Recommended: yes. The QML guard and
   the lock enforce the same rule the user sees, and the panel needs the
   lock to know about applies it did not start.
5. **Can `nix flake check` run the adapter tests?** Parts of
   `tests/adapter.sh` call `nix flake lock`, which may not work inside the
   build sandbox. If not, `nix flake check` runs the parts that can, and the
   rest stay a documented manual step on razer.
