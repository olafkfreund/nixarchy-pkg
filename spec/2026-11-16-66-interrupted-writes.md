---
status: approved
issue: 66
also: 67
intent: intent/2026-11-16-66-interrupted-writes.md
---

# Spec: an interrupted write stops apply, and leaves nothing running behind it

## Design

Designed against `main` plus #60 (PR #70, `feat/60-truthful-queue`), which
merges first. Line numbers are `main`, with #60's in brackets where they
differ.

**Decisions from intent approval** (the four open questions, as recommended):

1. A write or `recover` that finds a leftover process from a killed write
   **refuses** until it exits. Nothing is ever killed.
2. The panel is covered here (`a` and `SHIFT+A`). The remaining gaps (an
   apply from the user's terminal, and the moment between the panel's check
   and `nixarchy-apply` taking its lock) are closed by a nixarchy companion
   issue (section 6).
3. The external writers get the same guarantee as the Nix calls. One
   mechanism covers both (section 1).
4. `opt describe` and the flake inputs in `state` keep answering. Only apply
   and the queue count refuse.

**Decisions for the owner** (no recommendation in the intent; chosen here,
overturn at this gate):

- **A. An interrupted write is told apart from a running one by probing the
  write lock.** Readers check `pkg-recovery/open` only when it exists, and
  then take the lock **shared** with `flock -s -n` for a moment, looking at
  `open/` while they hold it (section 2). Why: it is the only signal that
  separates the two without changing how writes record themselves. Shared, so
  readers never block each other. Cost: about 7 ms, paid only while `open/`
  exists. The probe can make a concurrent `nixarchy-apply --yes` fail with
  "another apply is running" if both land in the same few milliseconds
  (Risks).
- **B. The panel learns about it from `pending`, not from a new view.**
  `pending` answers `ok:false` with the recover hint, so #60's existing
  "queue unknown" footer, bar tooltip and arming refusal all show it with no
  new QML surface. `state` adds the same hint to its existing `message`, plus
  a structured `recovery` field for scripts.
- **C. A refused apply is still an apply record:**
  `{"nixarchyPkgApply": {"ok": false, "exit": null, "message": …}}`.
  `exit: null` says `nixarchy-apply` never ran. The panel already handles
  `ok:false` records, so it needs no change.
- **D. `timeout -k 10 120`** for every Nix call a write makes, so a Nix
  process that ignores `SIGTERM` is killed 10 s later. Why: the intent found
  the 120 s bound holds only if Nix exits on `SIGTERM`.
- **E. One PR, three commits** in this order: #67 (section 1), #66
  (sections 2–4), docs (section 5). #67 goes first because it is self-contained
  and #66's tests rely on its refusal message for one case.

### 1. #67: children hold a second lock, and the next write waits for it

A new lock file, `$STATE_DIR/pkg-children.lock`, is held for as long as
anything a write started is alive. Children inherit it; nobody records a pid.

- In `begin_write` (`:113` [`:138`]), after `flock -w 5 9` (`:119` [`:144`])
  and **before** the `pkg-work.*` cleanup loop (`:123` [`:148`]):

  ```bash
  exec 7>>"$STATE_DIR/pkg-children.lock" || die "cannot open … Nothing was changed."
  flock -w 1 7 ||
    die "something an interrupted write started is still running. Try again when it has finished. Nothing was changed."
  ```

  No duration is promised. The Nix calls are bounded by `timeout`, but
  `run_writer`'s writers and `nix-instantiate --parse` are not, and a
  descendant that ignores `SIGTERM` can outlive its `timeout` (Codex, review
  of this spec: `timeout -k 0.1 0.1` returned after 0.1 s while a grandchild
  ignoring `SIGTERM` lived on).

- fd 7 is **not** closed for children, unlike fd 9. `timeout`, `nix`,
  `nix-instantiate` and `run_writer`'s writers (`:460` [`:485`]) all inherit
  it. A `flock` lock belongs to the open file description, so it stays held
  until the last process holding that description exits, even if the
  adapter is killed first. Checked on 2026-11-16: a `bash` that took
  `flock -n 7`, started `sleep 30` and was `SIGKILL`ed left the lock held
  until the `sleep` was killed, then free.
- `-w 1`, not `-n`: only a holder of fd 9 probes fd 7, and readers never touch
  fd 7, so in practice the only holder is a leftover child. The second is
  slack, not a wait anyone feels.
- The `pkg-work.*` cleanup now runs only when no leftover child is alive, so
  a running orphan's `TMPDIR` is never deleted.
- `recover` and `recover --discard` pass through `begin_write`, so they
  refuse too. A restored `flake.lock` cannot be overwritten by an orphan.
- **The adapter's own undo and commit wait for its descendants too.** A
  child can exit and leave a descendant still writing, while the adapter is
  alive. So before `rollback` and before `committed` (every caller: `die`,
  `on_exit`, `writer_finished`, `cmd_recover`, and each write's `committed`),
  a new `settle` step runs:

  ```bash
  # Our own fd 7 holds the lock for every descendant; let go of ours and see
  # whether anyone else still holds it.
  settle() {
    exec 7>&-
    ( flock -w 5 6 ) 6>>"$STATE_DIR/pkg-children.lock"
  }
  ```

  A separate open of the same file is a separate open file description, so
  it conflicts with the descendants' inherited lock and not with nothing.
  Checked on 2026-11-16: with a child holding the inherited lock, a fresh
  `flock -n` failed; once the child exited, it succeeded; with no child it
  succeeded at once. If `settle` fails after 5 s, the adapter neither rolls
  back nor commits: `open/` and the working directory stay, and the answer is
  `{ok:false}` with "something this write started is still running, so
  nothing was undone. Your backup is kept: run <SELF> recover when it has
  finished." The next write refuses until then (above), and `on_exit` skips
  removing `WORK` when `settle` failed.
- Every `timeout 120` a write runs (`:1109`, `:1128`, `:1132`, `:1173`,
  `:1230` [`:1134`, `:1153`, `:1157`, `:1198`, `:1255`]) becomes
  `timeout -k 10 120` (decision D). `flake show` (`:1016` [`:1041`]) is a read
  under no lock, and is left alone.

Why this holds: every child is started after `guard` (`:518`, `:747`, `:841`,
`:1089`, `:1168` and the `cmd_pkg`/`cmd_draft` guards), so a killed write that
leaves a child also leaves `pkg-recovery/open`. A leftover child therefore
always meets a recovery the user must answer, and that answer goes through
`begin_write`.

### 2. #66: telling an interrupted write from a running one

A new helper, `interrupted`, in `bin/nixarchy-pkg` beside `begin_write`:

```bash
# Prints the guarded paths and returns 0 when pkg-recovery/open is left over
# from a write that is not running. 1: nothing open. 2: a write or an apply
# holds the lock, so it cannot be told.
interrupted() {
  [ -e "$TXN/open" ] || return 1           # the common case: no fork, no lock
  [ -e "$LOCK" ] || return 2               # never create it from a reader
  ( exec 6<"$LOCK" || exit 2
    flock -s -n 6 || exit 2
    [ -d "$TXN/open" ] || exit 1
    cat "$TXN/open"/*.path 2>/dev/null; exit 0
  )
}
```

- A live write holds fd 9 exclusively from before `guard` until after
  `committed`. While a reader holds the shared lock, no write can, so an
  `open/` seen inside the subshell is left over. No inode comparison is
  needed (an earlier draft compared inodes; inode numbers can be reused).
- Readers take it shared, so two readers never make each other answer
  "cannot be told".
- Return 2 is conservative in every caller: `pending` answers `writing:
  true` as #60 does today; `state` adds nothing; `apply` **refuses** with "a
  write is in progress or was interrupted -- try again in a moment". Going
  ahead and relying on `nixarchy-apply`'s own `flock -n 9`
  (`nixarchy-apply:252-256`) would leave a window: a refused write holds the
  lock for up to a second while it probes fd 7, and releases it just as
  `nixarchy-apply` starts (agy review). An apply is never wanted while a
  write is open anyway. An interrupted write seen while an apply holds the
  lock is reported once the apply ends.
- Paths are read inside the lock and printed by the helper; callers use that
  output, never `open/` again, so a `recover` that runs straight after
  cannot make a reader fail under `set -e` or print an empty list.
- In `pending`, the second check after the snapshot (#60 `[:1434]`) is
  written so a live write that commits during the probe still marks the
  answer `writing` (test `[ -e open ]` first, then call `interrupted`).
- The helper reads the paths from `open/*.path` for the message. Message,
  shared by every reader, built once:
  `an earlier write was interrupted (<paths>). To put back what was there before, run: <SELF> recover. If the files look right as they are, run: <SELF> recover --discard.`
  This is `begin_write`'s refusal text (`:135` [`:160`]) with the paths added.
  A second helper, `recovery_message`, builds it, and `begin_write` uses it
  for its own refusal, so the two cannot drift. `begin_write` does not call
  `interrupted`: it already holds fd 9 exclusively, so a shared `flock -s -n`
  on the same file from a new descriptor would fail with 2.

### 3. #66: what each command answers

| Command | Interrupted (`interrupted` true) | Otherwise |
| --- | --- | --- |
| `pending` [`:1425`] | `{ok:false, error: <message>}`. Checked before the snapshot and again after it, where #60 already checks `open/` (`[:1432]`, `[:1434]`). | unchanged; `writing: true` while `open/` exists and the lock is held |
| `state` (`:1469` [`:1904`]) | `ok: true`, the usual catalogue; `message` gets `<message>` (joined with the unreadable-file message by ` -- ` if both); new `recovery: {files: [<paths>]}` | no `recovery` key |
| `apply` (`:1427` [`:1845`]) | prints only `{"nixarchyPkgApply":{"ok":false,"exit":null,"message":<message>}}`; `nixarchy-apply` is not run | the same refusal while the probe cannot tell (return 2); otherwise unchanged |
| `check` [`:1676`] | unchanged: #60 already refuses while `open/` exists (`[:1698]`) | unchanged |
| `opt describe`, `flake list` | unchanged (decision 4) | unchanged |
| writes, `recover` | unchanged except section 1 | unchanged |

`state` keeps `ok: true` for the same reason #41 gave for an unreadable file:
the user must still be able to reach the panel they recover from.

### 4. #66: the panel

The panel already does almost all of it, through #60:

- `pending` failing sets `queued = -1` and `queueError`
  (`PkgModel.qml` [`:421-422`], `Panel.qml` [`:59-60`]). The footer shows
  `queue unknown -- <message>` (`Card.qml` [`:352`]) and the bar's tooltip
  `queue unknown: <message>` (`Panel.qml` [`:102-104`]), for as long as the
  recovery is open.
- `a` and `SHIFT+A` both arm through a fresh `pending` read
  (`armApply`, `PkgModel.qml` [`:286-300`]). An `ok:false` answer disarms and
  puts `queueError` in the footer (`[:430-432]`). So both keys refuse, with
  the hint, before anything is launched.
- `state`'s `message` lands in the footer message line through `_absorb`
  (`PkgModel.qml:280`, `:286`), as the unreadable-file message does today.

Three QML changes:

1. `armApply`'s early refusal (`PkgModel.qml` [`:292`]) is **deleted**. It
   refused from the last answer without reading again, so after a `recover`
   in a terminal `a` kept refusing with an old message (agy review). Arming
   always reads `pending` afresh; an `ok:false` answer refuses with its own
   error (`[:430-432]`).
2. `_absorbPending` disarms on any `ok:false` or `writing:true` answer when
   `armingState === "armed"`, not only while `"reading"` (`[:429]`).
   Otherwise a background read that finds an interrupted write leaves the
   confirming press of `SHIFT+A` free to launch the terminal (agy review).
3. The Queue tab keeps showing the last good `pendingData` after a failed
   read. While `queueError` is set, its rows are replaced by one `note` row
   carrying `queueError`, so the tab never lists a queue built from before
   the interruption. (#60's rule: an unknown count is shown as unknown.)

### 5. Docs

`docs/manual/troubleshooting.md` ("An earlier write was interrupted",
`:57-82` on `main`):

- the panel now shows the hint in the footer and the bar, and refuses `a` and
  `SHIFT+A` until `recover` or `recover --discard`;
- a new paragraph for the "still running" refusal: what it means, that a Nix
  call ends within about two minutes but a writer has no limit, and how to
  see what is running (`fuser ~/.local/state/nixarchy/pkg-children.lock`).

### 6. Companion issue in nixarchy

**Title:** `nixarchy-apply: refuse while a nixarchy-pkg write is interrupted`

> nixarchy-pkg keeps a backup of every file a write is about to change in
> `${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/pkg-recovery/open/`, and
> removes it when the write finishes. Writes take the same lock as
> `nixarchy-apply` (`applied/lock`), so any `pkg-recovery/open` that
> `nixarchy-apply` sees *after* taking its lock is left over from a write that
> was killed, and the selection may be truncated. nixarchy-pkg's panel
> refuses to start an apply in that state (nixarchy-pkg #66), but an apply
> from a terminal, or one that starts just after the panel checked, does not
> know. Ask: once `flock 9` succeeds, if `pkg-recovery/open` exists, exit 1
> with "an earlier nixarchy-pkg write was interrupted -- run
> `nixarchy-pkg recover` (or `recover --discard`) first", for both `--yes`
> and interactive runs. Read-only; no new dependency.

### 7. Tests

`tests/adapter.sh`, in throwaway `XDG_*` dirs like every existing case.

#67:

- **A killed `flake add` leaves its child, and the next write waits for it.**
  Stub `nix` so `flake lock` writes its pid and `exec sleep 30` (the pattern
  at [`:615-633`]). Start `flake add` in the background, wait for the pid,
  `kill -9` the adapter. Then:
  - `toggle` answers `ok:false` containing `still running`;
  - the orphan's `pkg-work.*` directory still exists;
  - `recover` answers `ok:false` containing `still running`;
  - after killing the stub, `recover` answers `ok:true` and restores the
    original `flake.nix` and `flake.lock` bytes.
- **A writer counts as a child.** The same with a stub writer that sleeps,
  killed during `toggle`.
- **A descendant outlives its child while the adapter lives.** A stub writer
  that starts a background grandchild (which sleeps, then appends to
  `apps.nix`) and exits non-zero at once. The adapter's answer is `ok:false`
  with "still running", `open/` and the original bytes are kept, and after
  the grandchild ends, `recover` restores the original bytes.
- **`timeout -k`**: `grep -c 'timeout -k 10 120'` in the adapter equals the
  number of write-time Nix calls (5), and `grep -c 'timeout 120 nix flake
  metadata\|timeout 120 nix flake lock'` is 0.

#66:

- **Interrupted:** `open/` with one `0.path` / `0.data`, lock free.
  - `pending` → `ok:false`, error contains `recover` and the path.
  - `state` → `ok:true`, `.recovery.files == [<path>]`, `.message` contains
    `recover`.
  - `apply` with #60's stub `nixarchy-apply` [`:916`] → the only line is a
    record with `ok == false and exit == null`, and the stub's `argv` file
    was never written.
- **Running, not interrupted:** the same `open/`, but a background
  `flock 9` holder on `applied/lock` (the pattern at [`:817`]).
  - `pending` → `ok:true, writing:true`.
  - `state` → no `recovery`.
- **QML:** armed, then a `pending` answer with `ok:false` arrives:
  `armingState` is `""`. With `queued = -1` and a `queueError`, `armApply`
  starts a read rather than refusing from the old error.
- **Fixtures create `applied/`** next to `pkg-recovery/open`, as
  `begin_write` does; a test of a missing `applied/lock` expects
  "cannot be told" (`writing: true`), never "nothing open".
- **Readers do not block each other:** a background holder of a *shared*
  lock on `applied/lock`, with an interrupted `open/`; `apply` still refuses
  and the stub `nixarchy-apply` is never run.
- **Changed #60 test:** "open recovery marks queue as writing" [`:610-612`]
  creates `open/` with the lock free, which is now an interrupted write. It
  gains the lock holder, so it still tests `writing`.
- **One message:** the write refusal and `pending`'s error carry the same
  sentence (`contains` on both).

`tests/qml/tst_pkgmodel.qml`:

- `armApply` with `queued = -1` and a `queueError` starts a fresh read
  (`armingState === "reading"`); when that read answers `ok:false`, the
  error is in `message` and nothing is armed.
- With `queueError` set, the Queue tab's rows are one `note` with that text.

## Alternatives rejected

- **Record the child's pid and check `kill -0`.** The pid can be reused after
  the orphan exits, so a later write could wait on, or worse kill, an
  unrelated process. The intent's constraint forbids it.
- **Run Nix in the adapter's process group and kill the group on exit.**
  `SIGKILL` runs no exit path, which is the whole case. And `timeout` moves
  itself to its own group anyway.
- **`setsid`/cgroups to tie children to the adapter.** Needs systemd scopes or
  more processes, and still cannot act after a `SIGKILL`.
- **Comparing `open/`'s inode before and after an unlocked probe.** The
  first draft did this. Inode numbers are reused, so a new write's `open/`
  could look like the old one (Codex review). Looking inside the shared lock
  needs no comparison.
- **A marker file inside `open/` naming the writing pid.** Same pid-reuse
  problem, and it changes #59's recovery layout.
- **A new `recovery` view or banner in the panel.** #60's unknown-queue path
  already reaches the footer, the bar and both apply keys.
- **`pending` keeps `ok:true` with a flag.** A count from a truncated file
  would still be drawn as a number, against #60's rule and decision 3 of the
  intent's `pending` question.
- **Checking in `PkgModel` before `SHIFT+A` launches a terminal.** The arming
  read already does it; a second read adds a race, not coverage.

## Risks

- **The probe takes the write lock, shared, for a moment.** A `nixarchy-apply --yes`
  that starts in those few milliseconds exits 1 with "another apply is
  running". It happens only while `open/` exists (a write in progress or an
  interrupted one), and the panel shows the failure in the apply log. A
  concurrent write is unaffected: it waits up to 5 s.
- **A descendant that never ends** keeps every write refused, and its
  backup kept, until the user finds and stops it. That is the safe side: the
  alternative is a write raced by it.
- **A user who deletes `open/` by hand** loses the apply refusal, but writes
  still wait for any leftover child (section 1 does not need `open/`).
- **A child that closes inherited fds** (none found: `timeout`, `nix`,
  `nix-instantiate`, the bash writers keep them) would not hold the lock. The
  test with the stub writer would not catch that; the `flake add` test with
  real `timeout` would for `timeout` itself.
- **A stale panel.** After `recover` from a terminal, the footer keeps the
  hint until the next `pending` (menu open, any write, `r`).
- **Merge with #60.** Every QML change sits on #60's code. Implementation
  starts after PR #70 merges.

## Verification

- `bash tests/adapter.sh` passes, with the new cases and the changed #60 case.
- `qmltestrunner` for `tests/qml/` passes.
- `shellcheck bin/nixarchy-pkg tests/adapter.sh` is clean.
- On **razer**, with throwaway `XDG_STATE_HOME`/`XDG_CONFIG_HOME` and a
  scratch `NIXARCHY_FLAKE`:
  - `kill -9` a real `flake add` during `nix flake lock`; the next `toggle`
    refuses with "still running", and within two minutes plus 10 s it no
    longer does;
  - with the recovery open, open the menu: the footer and the bar show the
    hint, `a` and `SHIFT+A` refuse; `recover` from a terminal, press `r`, and
    both work.
- Never on p620; never against `/etc/nixos` or the real state directory.
