---
status: draft
issue: 59
author: olafkfreund
---

# Intent: a write that fails, or races another, leaves the user's files as they were

## Problem

#39 settled what a *successful* write must preserve: the file's inode, so its
mode, owner and symlink survive. It did that by swapping `mv` for `cp` at every
write site and relying on the backup for safety: "It preserves the one property
(atomicity) that the backup already covers" (`spec/2026-09-24-39-write-integrity.md`).
The backup does not cover it. A three-way review on 2026-11-15 (Claude, Codex,
agy) found four ways a write that does not finish cleanly still damages or
loses the user's configuration. Codex reproduced the first, second and fourth
in `/tmp`.

**1. An interrupted write truncates the file and deletes the backup.**
`cp "$tmp" "$APPS"` (`bin/nixarchy-pkg:590`, `:680`) and `cp "$tmp" "$file"`
(`:956`, `:1071`) open the live file with `O_TRUNC` and then write it. A full
disk, a quota or a signal (the shell restarting) between those two leaves
`apps.nix` or `/etc/nixos/flake.nix` empty or cut short. Under `set -e` the
function exits before its restore line runs, and the `RETURN` trap
(`:562`, `:659`, `:930`) deletes the backup on the way out. The answer is no
JSON at all, so the panel cannot say what happened.

**2. Two writes at once lose one of them.**
Nothing serialises read–modify–write–restore. Writer B succeeds; writer A then
fails its parse check and restores the backup it took *before* B ran, erasing
B's change. Both callers were told what happened to their own write, and
neither was told that B's is gone. Two panels, the panel and a terminal, or a
script and the panel are enough. None of the external writers this adapter
calls lock either (`nixarchy-app-enable`, `-service-enable`, `-pkg-add`,
`-pkg-remove`, `-opt-remove`: no `flock`), and `app-enable` and
`service-enable` still `mv` over the file, which is the inode replacement #39
removed here. Only `nixarchy-apply` holds a lock
(`~/.local/state/nixarchy/applied/lock`).

**3. The panel lets you write while an apply is running.**
`PkgModel.write()` (`PkgModel.qml:346`) and `OptionForm.commit()`
(`OptionForm.qml:278`) refuse while `busy`, but not while `applying`. `ESC`
detaches the build log and leaves `applying` set, after which a toggle, an
option or `flake add` edits `apps.nix`, `flake.nix` or `flake.lock` while
`nixarchy-apply` is copying them or `nh` is evaluating them.
`applyInTerminal()` (`:637`) starts an apply without checking `busy`.

**4. "Nothing was changed" can be false after `flake add` and `flake remove`.**
Whether a lock file existed is recorded before any Nix call (`:906`). Its
*contents* are backed up only after `nix flake metadata` has run (`:932`,
then `:942`; `:1011`, then `:1065`), and that command can rewrite an outdated
lock. A later failure then "restores" the rewritten lock. When that first
`metadata` call fails, the function `die`s without restoring anything, so a
lock it just created stays behind.

Also: `$tmp` is missing from the `RETURN` trap in `cmd_opt_set`,
`cmd_opt_replace` and `cmd_flake_add`, so every write leaves a full copy of
`apps.nix` or `flake.nix` in `/tmp`. This is a leak, not a corruption, but it
copies the user's config out of a `0700` directory on every write.

## Proposed outcome

- A write that does not finish, for whatever reason, leaves the file exactly
  as it was, or leaves a backup that survives the failure and is named in the
  answer. Never a truncated file with no way back.
- Two writes to the same file, from any mix of panel, terminal and script, run
  one after the other. Neither erases the other, and a write that has to wait
  says so instead of hanging silently.
- While an apply is running, the panel refuses writes and says why, whether or
  not the log is on screen. It refuses to start an apply while a write is in
  progress.
- `flake add` and `flake remove` that answer "nothing was changed" leave
  `flake.nix` and `flake.lock` byte-identical to before the call, including
  when the first Nix call is what fails.
- No copy of the user's config is left in `/tmp` after any call.
- Everything #39 guarantees still holds after a successful write: same
  inode, mode, owner and symlink.
- `tests/adapter.sh` fails if any of the above regresses, and
  `nix flake check` runs it, which it does not today.

## Affected users and systems

- Everyone who writes through the panel or the `nixarchy-pkg` CLI. Most
  exposed: anyone low on disk, anyone with the panel open on two monitors,
  anyone who scripts `nixarchy-pkg` while the panel is up, anyone who presses
  `ESC` during an apply.
- `bin/nixarchy-pkg`: `cmd_opt_set`, `cmd_opt_replace`, `cmd_flake_add`,
  `cmd_flake_remove`, `run_writer`.
- `PkgModel.qml` (`write`, `applyInTerminal`), `OptionForm.qml` (`commit`).
- `tests/adapter.sh`, `flake.nix` checks.
- Outside this repo, in nixarchy: the five external writers and
  `nixarchy-apply`'s lock. This intent cannot change them, but a lock only
  works if every writer takes it.
- Verification host is **razer**, per repo convention. Never p620.

## Constraints

- Must keep every #39 guarantee: the live file's inode, mode, owner and
  symlink survive a successful write. Going back to `mv` is not a fix.
- Must not require root or elevate. Elevation stays with `nixarchy-apply`.
- Must not change the adapter's JSON contract. A new failure is reported as
  `{ok:false, error}` like every other.
- Must never block the panel indefinitely. A write that cannot get the lock
  answers within a bounded time.
- Must not deadlock against `nixarchy-apply`, which holds its lock through
  interactive prompts (#1276 in nixarchy).
- No new runtime dependency beyond what the adapter or nixarchy already ships
  (`flock` is in util-linux, which `nixarchy-apply` already puts on its PATH).
- A backup kept for recovery must not be more readable than the file it
  backs up.

## Open questions

1. **Which lock?** Share `nixarchy-apply`'s existing lock file, so writes and
   applies exclude each other in one place, or add a separate selection lock?
   Sharing gives the "no write during apply" rule for free across panel, CLI
   and terminal, but makes every write wait for, or refuse during, an apply
   sitting at a prompt.
2. **Scope across repos.** The external writers do not lock, and two still use
   `mv`. Fix the adapter now and file a nixarchy issue for the writers, or hold
   this until both land together? The adapter alone closes the panel-vs-panel
   race, not panel-vs-`nixarchy-app-enable`-from-a-terminal.
3. **How to survive an interrupted write without giving up the inode.** Either
   keep a backup that outlives a failure (in `~/.local/state/nixarchy/`, not
   `/tmp`, removed only on success), or write a temp file beside the target,
   `fsync` it, and copy it over the live file. That narrows the window but
   does not close it. Which guarantee is enough: "never truncated", or
   "truncated only with a named backup to restore from"?
4. **Fold in the UI interlock, or a separate PR?** Item 3 is QML, the rest is
   the adapter. They share one claim, "a write never collides with another
   write or an apply", which argues for one task.
