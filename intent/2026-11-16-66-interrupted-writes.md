---
status: draft
issue: 66
also: 67
author: olafkfreund
---

# Intent: an interrupted write stops apply, and leaves nothing running behind it

## Problem

#59 made a write that dies recoverable. Before it touches a file, a write
copies it into `~/.local/state/nixarchy/pkg-recovery/open/`
(`bin/nixarchy-pkg:163`), and the next write refuses until the user runs
`recover` or `recover --discard` (`:134`). #59's plan left two gaps open
("Left for follow-ups", `plan/2026-11-15-59-atomic-locked-writes.md`). Both
are about a write that is killed outright (`SIGKILL`, an OOM kill), which runs
no trap.

**1. Only a write looks for an interrupted write (#66).**
`pkg-recovery/open` is checked in one place, `begin_write` (`:134`). Nothing
that reads the selection or the flake looks at it:

- `cmd_apply` (`:1427`) runs `nixarchy-apply` straight away. A killed write
  can leave `apps.nix`, `services.nix` (a service toggle guards both, `:518`)
  or `flake.nix` cut short, so pressing `a` can rebuild the machine from the
  truncated file before anything has asked the user to recover.
- `cmd_state` (`:1469`) does not report it. The panel draws the truncated
  files as the truth, including the flake inputs it reads through
  `cmd_flake_list` (`:1494`), and shows no sign that a backup is waiting.
- `cmd_pending` (`:1353`) counts changes from the truncated file, so the
  queue shows a "change" the user never made.
- `opt describe` (`:598`) opens an option form on the value in the truncated
  `apps.nix`.
- `SHIFT+A` (`PkgModel.qml:637`, `:642`) and an apply from the user's own
  terminal run `nixarchy-apply` directly, not through the adapter. A check in
  `cmd_apply` alone does not cover them. Even for `a`, a check made before
  `nixarchy-apply` takes its lock can be overtaken by a write that starts and
  dies in between.

`pkg-recovery/open` also exists during every healthy write, from `guard`
(`:163`) until `committed` (`:201`), and after an undo that failed (`:193`).
A write checks it only once it holds the lock, where an open backup can only
be left over. A reader that does not take the lock cannot tell "a write is
running now" from "a write was interrupted".

**2. A killed flake write leaves a Nix process running without the lock
(#67).**
`flake add` and `flake remove` run `timeout 120 nix flake lock` and
`timeout 120 nix flake metadata` with fd 9 closed (`:1109`, `:1128`, `:1132`,
`:1173`, `:1230`), so that Nix does not hold the write lock. Both can rewrite
`flake.lock`. Checked on 2026-11-16 with GNU coreutils 9.12 and a stand-in
child (`timeout 120 sleep 3 9>&-`):

- `timeout` makes itself the leader of a new process group, so a signal sent
  to the adapter or its process group does not reach it or its child.
- When the adapter alone is killed with `SIGKILL`, `timeout` and its child
  keep running. The adapter's fd 9 closes at once, so the lock is free while
  `nix` may still be writing `flake.lock`. `timeout` sends `SIGTERM` at 120 s
  and has no `-k`, so the bound holds only if `nix` exits on `SIGTERM`.
- The next `begin_write` deletes every `pkg-work.*` directory (`:123`),
  including the one the orphan uses as `TMPDIR`. A `recover` can restore
  `flake.lock` and then have the orphan overwrite it.
- A caught `SIGTERM` is different: bash waits for the running child before
  its trap runs, so the undo waits up to 120 s but does not race.
- Not checked: a logout or a session that ends by stopping its whole systemd
  scope, which would kill the orphan too.

Other children also run with fd 9 closed. `run_writer` (`:460`) starts the
external `nixarchy-*` writers, which change the selection files and have no
`timeout`. `nix-instantiate --parse` (`:784`, `:868`, `:1123`, `:1226`) only
reads a working copy, so it can outlive the adapter but cannot damage a
protected file.

## Proposed outcome

- While an interrupted write is open, an apply started from the panel, by `a`
  or `SHIFT+A`, is refused with the same recover hint the write refusal
  gives.
- The panel shows an interrupted write for as long as it is open, with the
  files it backs up, not only when the user next writes.
- A healthy write that is still running is never reported as interrupted.
- The queue is not shown as a count built from a file an interrupted write
  may have truncated. It reads as unknown until the user recovers.
- After an adapter is killed, nothing it started changes `flake.nix`,
  `flake.lock` or the selection under a later write, `recover` or apply. A
  later write or `recover` that finds such a process still running refuses
  and says what is running and to try again.
- Tests reproduce both: an apply refused while a recovery is open, and a
  killed `flake add` whose leftover process is not raced by the next write.

## Affected users and systems

- Anyone whose write was killed: the panel crashed mid-write, an OOM kill, a
  `kill -9` from a terminal.
- `bin/nixarchy-pkg`: `begin_write`, `cmd_apply`, `cmd_state`,
  `cmd_pending`, `cmd_opt` (`describe`), `cmd_flake_add`,
  `cmd_flake_remove`, `run_writer`.
- `PkgModel.qml` (`apply`, `applyInTerminal`), and where the panel shows a
  waiting recovery (`Card.qml`, `Panel.qml`).
- `tests/adapter.sh`, `tests/qml/`, `docs/manual/troubleshooting.md`.
- Outside this repo: `nixarchy-apply` does not know about `pkg-recovery`.
  Refusing an apply from the user's own terminal, or closing the gap between
  the panel's check and `nixarchy-apply`'s lock, needs a nixarchy change
  (open question 2).
- Verification host is **razer**, per repo convention. Never p620.

## Constraints

- Everything #59 guarantees still holds: the lock, the backup in the user's
  state directory, `recover` and `recover --discard`, and #39's inode, mode,
  owner and symlink.
- Never touches the user's files to "fix" them. Only `recover` restores, and
  only when the user runs it.
- `state`, `pending` and `opt describe` stay reads: they never wait for a
  write.
- No root, no elevation. Apply stays the only thing that rebuilds.
- No new runtime dependency.
- Each command keeps its response contract. Writes and reads answer
  `{ok:false, error}` on failure; `apply` answers inside its own
  `nixarchyPkgApply` record (`:1441`, read by `PkgModel.qml:576`), so a
  refused apply must still end the panel's log with a result.
- Must not deadlock against `nixarchy-apply`'s lock, and must not hold the
  panel for long. A write that finds a leftover process refuses rather than
  waiting out its `timeout`.
- Must not kill a process the adapter did not start. A recorded pid can be
  reused by something else after the orphan exits.
- #60 (`feat/60-truthful-queue`, not merged) rewrites `cmd_pending` and
  `cmd_apply`, and adds an unknown queue state (`queued: -1`). This task lands
  after it, or is rebased onto it.

## Open questions

1. **Wait or kill?** When a write finds a leftover process from a killed
   write, it can refuse until that process exits, or end it. Recommended:
   refuse. It is bounded by `timeout` for the Nix calls, and it never risks
   killing something else. Ending it is a spec option only if the process can
   be identified safely.
2. **How strong is the apply refusal?** The adapter can refuse `a` and the
   panel can refuse `SHIFT+A`, but only `nixarchy-apply`, under its own lock,
   can refuse every apply, including one from a terminal and one that a
   write overtakes. Recommended: cover the panel here, accept that narrow gap,
   and file a nixarchy issue for `nixarchy-apply` to refuse while
   `pkg-recovery/open` exists, as a linked follow-up.
3. **The external writers.** `run_writer`'s writers have no `timeout`, and
   are not Nix calls. Recommended: hold them to the same outcome (nothing a
   killed adapter started races a later write), even if the mechanism
   differs from the flake calls'.
4. **The other readers.** `opt describe` and the flake inputs in `state` read
   files a killed write may have truncated. Recommended: they keep answering,
   and the panel's interrupted-write notice covers them; only apply and the
   queue count refuse.
