---
status: approved
issue: 66
also: 67
spec: spec/2026-11-16-66-interrupted-writes.md
coders:
  1: codex   # children lock, settle, rollback/commit/on_exit paths -- small, tricky shell
  2: codex   # #67 tests: SIGKILL, orphan and grandchild fixtures -- same context as step 1
  3: codex   # interrupted() probe and the three readers -- lock semantics, set -e traps
  4: coder   # #66 adapter tests: fixtures and assertions, following existing patterns
  5: coder   # PkgModel arming fixes, Queue error row, QML tests
  6: agy     # docs: one manual page, bounded prose from the code's strings (fallback: coder)
reviewers:
  - codex   # flock/fd inheritance and errexit are where this goes wrong
  - agy     # independent read of the diff against this plan
---

# Plan: an interrupted write stops apply, and leaves nothing running behind it

Branch `fix/66-67-interrupted-writes`. This file is self-contained. A coder
reads it and the files each step names, nothing else. **Coders never stage or
commit.** The coordinator checks each step and commits per the approved
decision of **three commits** (spec decision E): steps 1-2 as
`fix(adapter): hold writes off while a killed write's children live (#67)`,
steps 3-5 as `fix: an interrupted write stops apply and shows in the panel
(#66)`, step 6 as `docs: interrupted writes and leftover children (#66)`.
Between steps inside a group the coordinator keeps the work uncommitted (or
amends the group's commit).

Line numbers are from `feat/60-truthful-queue` (PR #70), which merges before
this starts. Anchors also quote a line; trust the quote over the number.

After every step, run:
- `bash -n bin/nixarchy-pkg`
- `shellcheck bin/nixarchy-pkg tests/adapter.sh`
- `bash tests/adapter.sh`

The adapter suite has **11 pre-existing failures** on a nixarchy machine
(catalogue drift, fixed only by #68):

- "toggling on reports enabled"
- "the file really changed"
- "toggling off reports disabled"
- "services use their own file"
- "a toggle counts once"
- "a package counts once"
- "one file, one change"
- "and it names that file"
- "two files, two changes"
- "and both files are named"
- "and it recovers once readable"

Pass means no failure outside that list. Step 5 also runs the QML tests
directly: with `QT=$(nix eval --raw nixpkgs#qt6.qtdeclarative.outPath)` and
`QT_QPA_PLATFORM=offscreen`, `"$QT/bin/qmltestrunner" -input
tests/qml/tst_pkgmodel.qml -import tests/qml/imports -import
"$QT/lib/qt-6/qml"`. `nix flake check` is a build, so the coordinator runs
it after committing each step.

## Decisions (from the approved spec)

**What is wrong today.**
- A killed write leaves `~/.local/state/nixarchy/pkg-recovery/open/`.
  Only `begin_write` checks it. `apply`, `state` and `pending` read the
  possibly truncated files, so `a` can rebuild from them.
- `open/` also exists during every healthy write, so a reader cannot tell
  "running" from "interrupted" by looking at it.
- `flake add`/`remove` run `timeout 120 nix …` with fd 9 (the write lock)
  closed. `timeout` makes its own process group. If the adapter is
  `SIGKILL`ed, `timeout` and `nix` keep running without the lock, and the
  next `begin_write` deletes their `pkg-work.*` directory. A `recover` can be
  overwritten by them. The external writers (`run_writer`) and
  `nix-instantiate --parse` also run with fd 9 closed.

**Settled.**
1. **#67, children lock.** `$STATE_DIR/pkg-children.lock` on **fd 7**.
   `begin_write` takes it (after fd 9, before the `pkg-work.*` cleanup)
   with `flock -w 1 7`. fd 7 is **never** closed for children, so
   `timeout`, `nix`, `nix-instantiate` and the writers all inherit it. A
   `flock` lock belongs to the open file description and stays held until
   the last process holding it exits, even after a `SIGKILL` of the adapter
   (checked 2026-11-16). If it cannot be taken: refuse, nothing is ever
   killed, no pid is recorded.
2. **#67, settle.** Before every rollback and every commit, the adapter
   closes its own fd 7 and tries the same file from a fresh open with
   `flock -w 5`. A fresh open is a new open file description, so it is
   blocked exactly while a descendant still holds the inherited one
   (checked 2026-11-16). If still held after 5 s: neither undo nor commit;
   `open/` and `WORK` are kept; the answer says to run `recover` when it
   has finished.
3. **#67, `timeout -k 10 120`** on the five write-time Nix calls. Not on
   `flake show` (a read, under no lock).
4. **No time promise** in any message: the writers and `nix-instantiate`
   have no limit.
5. **#66, probe.** `interrupted()`: only when `open/` exists, open
   `applied/lock` **read-only** (never create it) and take it **shared**
   with `flock -s -n`; read `open/*.path` inside that hold. Return 0 and
   print the paths when left over; 1 when nothing is open; 2 when the lock
   is held or missing ("cannot tell"). Readers never block each other. Cost
   about 7 ms, only while `open/` exists.
6. **#66, answers.**
   - `pending`: 0 → `{ok:false, error:<message>}`; 2 → `writing: true`
     (as #60 today).
   - `state`: 0 → `ok:true`, `<message>` in `message` (joined to the
     unreadable-file message with ` -- `), and `recovery: {files:[…]}`;
     otherwise no `recovery` key.
   - `apply`: 0 → only `{"nixarchyPkgApply":{"ok":false,"exit":null,
     "message":<message>}}`; 2 → the same record with "a write is in
     progress or was interrupted -- try again in a moment". `nixarchy-apply`
     is not run in either case.
   - `check`, `opt describe`, `flake list`: unchanged.
7. **Message**, one helper, also used by `begin_write`'s refusal:
   `an earlier write was interrupted (<paths, comma-separated>). To put back what was there before, run: <SELF> recover. If the files look right as they are, run: <SELF> recover --discard.`
   `begin_write` adds ` Nothing was changed.` as today.
8. **Panel.** #60's unknown-queue path carries the hint to the footer, bar
   tooltip and arming, for `a` and `SHIFT+A`. Three QML changes: delete
   `armApply`'s early refusal; disarm on `ok:false`/`writing` when already
   armed; while `queueError` is set, the Queue tab is one `note` row.
9. **One PR, three commits** in this order: #67 (steps 1-2), #66 (steps
   3-5), docs (step 6).
10. **Companion nixarchy issue** (below) closes the terminal-apply gap.

## Steps

### 0. Coordinator: rebase and re-check

- `git rebase main` once PR #70 has merged. The branch has only docs
  commits, so it should apply cleanly.
- Re-check every anchor this plan quotes with `grep -n` against the rebased
  `bin/nixarchy-pkg` and `PkgModel.qml`. If one moved, fix the number here
  in the same commit as step 1.

### 1. Children lock, settle, `timeout -k` (`bin/nixarchy-pkg`)

**Globals** (near `WRITING=false # true from begin_write on`, ~line 63):
`readonly CHILDREN="$STATE_DIR/pkg-children.lock"` (put it beside `TXN`,
~line 51) and `SETTLE_FAILED=false`.

**`begin_write`** (~line 138). After
`export NIXARCHY_LOCK_HELD=1` and **before** the loop
`for d in "$STATE_DIR"/pkg-work.*; do`:

```bash
  exec 7>>"$CHILDREN" || die "cannot open $CHILDREN. Nothing was changed."
  # Children inherit fd 7; a write killed outright leaves them holding it.
  flock -w 1 7 ||
    die "something an interrupted write started is still running. Try again when it has finished. Nothing was changed."
```

**`settle`**, new, after `committed()`:

```bash
# Let go of our own fd 7, then see whether anything this write started still
# holds it (a fresh open is a separate lock; checked 2026-11-16).
settle() {
  exec 7>&-
  if ( flock -w 5 6 ) 6>>"$CHILDREN"; then return 0; fi
  SETTLE_FAILED=true
  return 1
}
readonly SETTLE_NOTE="something this write started is still running, so nothing was undone. Your backup is kept: run $SELF recover when it has finished."
```

`SETTLE_NOTE` uses `$SELF`, so define it after `SELF`.

**`rollback`** (~line 195). First lines of the body:

```bash
  if ! settle; then GUARDED=false; ROLLBACK_NOTE=$SETTLE_NOTE; return 0; fi
```

`open/` is not removed on that path. Every caller already appends
`ROLLBACK_NOTE` (`die`: "-- but the undo failed. …"; `on_exit`;
`writer_finished`; `cmd_recover`).

**`committed`** (~line 225). First lines:

```bash
  if ! settle; then
    GUARDED=false   # keep open/: neither committed nor undone
    die "something this write started is still running, so the write was neither kept nor undone. Your backup is kept: run $SELF recover when it has finished."
  fi
```

**`on_exit`** (~line 95). In the cleanup loop
`for d in "$WORK" "$READDIR" "$CHECKDIR" "$APPLYDIR"; do`, skip `$WORK`
when `$SETTLE_FAILED`:
`[ "$d" = "$WORK" ] && $SETTLE_FAILED && continue`.

**`timeout -k 10 120`** on exactly these five lines (quote, then change
`timeout 120` to `timeout -k 10 120`):
- `cmd_flake_add`: `if ! timeout 120 nix flake metadata "$dir" >/dev/null 2>"$err" 9>&-; then` (~1134, the first one)
- `cmd_flake_add`: `if ! timeout 120 nix flake lock "$dir" …` (~1153)
- `cmd_flake_add`: the second `nix flake metadata` (~1157)
- `cmd_flake_remove`: the two `nix flake metadata` (~1198, ~1255)

Leave `cmd_flake_show`'s `timeout 120 nix flake show` (~1041) alone.

**Traps.**
- **Never** add `7>&-` to a child. Existing `9>&-` and `8>&-` stay.
- `settle` is called directly, never in `$(...)`: it changes
  `SETTLE_FAILED` and closes fd 7 in this shell.
- `( flock -w 5 6 ) 6>>…`: the redirect on the subshell, so fd 6 closes when
  it ends. Not `exec 6>>…`.
- `cmd_recover` passes through `begin_write recover` (refuses on a held fd
  7) and then `rollback` (settles trivially: it started no children).
- One JSON answer on every path: the `committed` path above `die`s with
  `GUARDED=false`, so `die` does not roll back and prints once.
- A `die` inside `begin_write` before fd 7 is open never reaches `settle`
  (`GUARDED` is still false).

→ **Verify:** the three commands. `grep -c 'timeout -k 10 120 nix flake'`
is 5; `grep -c 'timeout 120 nix flake \(metadata\|lock\)'` is 0.

### 2. #67 tests (`tests/adapter.sh`)

New section after the #59 section (`echo "a write that fails or races
leaves the files recoverable (#59)"`), titled
`echo "a killed write leaves nothing to race the next one (#67)"`.
Throwaway `XDG_STATE_HOME`/`XDG_CONFIG_HOME` like every case. Reuse the #59
helpers (`run59`, `st`, `one_json`) where they fit.

Fixture prerequisites:
- **Flake:** build it as the #59 section does (~line 1345-1354): a flake
  with a `flake.nix`, `git init`/`add`, and a **seeded `flake.lock`**
  (`fresh_flake` creates none, and Nix writes none for a flake without
  inputs). Record `md5sum` of both before the add.
- **Apps:** `apps.nix` needs one marked, commented row so `toggle` reaches
  the stub writer, e.g. `printf '{ ... }:\n{\n  # foo.enable = true;  #@ foo\n}\n'`
  (`reset_apps` writes an empty set, against which `toggle` refuses before
  any writer runs). `toggle foo` then calls `nixarchy-app-enable foo`.
- **Waiting for a stub that is not the test shell's child:** `wait "$pid"`
  cannot reap it. Kill it, then poll until `kill -0 "$pid"` fails, then
  until `flock -n "$(st)/pkg-children.lock" true` succeeds (100 × 0.05 s).

1. **Killed `flake add`.** Stub `nix` on `PATH`: for `flake lock`, write its
   pid to `$STUB/nix.pid` and `exec sleep 30`; everything else succeeds as
   the existing flake stubs do. Start `flake add foo github:a/b` in the
   background; wait for `nix.pid` (loop of 100 × 0.01 s, as at ~line 629);
   `kill -9` the adapter. Then:
   - `toggle` (any id) → `ok == false` and error contains `still running`;
   - a `pkg-work.*` directory still exists under `$(st)`;
   - `recover` → `ok == false`, error contains `still running`;
   - kill the stub and poll as above; `recover` → `ok == true`, and
     `flake.nix` and `flake.lock` match their bytes from before the add
     (`md5sum`, as at ~line 1279).
2. **A writer counts.** A stub `nixarchy-app-enable` that writes its pid
   and `exec sleep 30`; `toggle` in the background; `kill -9` the adapter;
   the next `toggle` → `still running`; kill the stub; `recover` → `ok`.
3. **A short-lived grandchild is waited for (rollback path).** A stub
   writer that starts
   `( sleep 1; printf 'x\n' >>"$APPS"; touch "$STUB/gc.done" ) >/dev/null 2>&1 &`
   and exits 1 at once. `toggle` → `ok == false` (the writer failed). Then
   assert `$STUB/gc.done` **already exists** when `toggle` returns (proving
   the adapter waited), `apps.nix` equals its original bytes (the undo ran
   after the append), and no `pkg-recovery/open`.
3b. **The commit path waits too.** The same grandchild, but the stub writer
   makes its change and exits 0. `toggle` → `ok == true`; `gc.done` exists
   when it returns; `apps.nix` contains both the writer's change and `x`
   (the commit came after the grandchild); no `pkg-recovery/open`.
3c. **The `on_exit` path waits too.** The same grandchild with `sleep 7`,
   writer exits 0 but then the adapter is sent `SIGTERM` while settling
   (send it once `gc` has started, e.g. after 1 s). Exactly one JSON answer
   (`one_json`), `ok == false`, containing `still running`;
   `pkg-recovery/open` and a `pkg-work.*` directory still exist. Wait for
   `gc.done`; `recover` → `ok == true`.
4. **A long-lived grandchild keeps the backup.** The same with `sleep 7`
   (longer than `settle`'s 5 s). `toggle` → `ok == false`, error contains
   `still running` and `recover`; `pkg-recovery/open` still exists. Wait
   for the grandchild; `recover` → `ok == true`; `apps.nix` equals its
   original bytes.
5. **`timeout -k`:** the two `grep -c` checks from step 1, as `check`s.

**Traps.**
- A stub's background grandchild must redirect its output
  (`( … ) >/dev/null 2>&1 &`). `run_writer` reads the writer's output with
  `$(…)`, which waits until every holder of the pipe has closed it; a
  grandchild holding stdout would make the adapter wait for it there, and
  the case would not test `settle`.
- Every background process gets killed and waited for in the case
  itself, so the suite never leaves a `sleep 30` behind. Nothing under `/tmp`
except via `mktemp -d` the suite already uses. No `| head`, no `diff`/`cmp`
at a pipeline head.

→ **Verify:** the three commands.

(Deviation, step 2: the TERM fixture's grandchild sleeps 12 s, not 7, because
bash runs the TERM trap only after `settle`'s 5-second `flock` wait returns;
the short-lived grandchild sleeps 2 s so its marker cannot race the check. The
killed-child cases test fd 7 acquisition in `begin_write`, so they pass even
with `settle` disabled; the rollback, commit, TERM and long-grandchild cases
fail without it.)

### 3. `interrupted()` and the three readers (`bin/nixarchy-pkg`)

**Helpers**, beside `begin_write`:

```bash
# Prints the guarded paths and returns 0 when pkg-recovery/open is left over
# from a write that is not running. 1: nothing open. 2: a write or an apply
# holds the lock, or it is missing, so it cannot be told.
interrupted() {
  [ -e "$TXN/open" ] || return 1           # the common case: no fork, no lock
  [ -e "$LOCK" ] || return 2               # never create it from a reader
  ( exec 6<"$LOCK" || exit 2
    flock -s -n 6 || exit 2
    [ -d "$TXN/open" ] || exit 1
    cat "$TXN/open"/*.path 2>/dev/null; exit 0
  )
}

# recovery_message PATHS  -- newline-separated, as interrupted prints them.
recovery_message() {
  local list=${1%$'\n'}
  list=${list//$'\n'/, }
  printf 'an earlier write was interrupted (%s). To put back what was there before, run: %s recover. If the files look right as they are, run: %s recover --discard.' \
    "$list" "$SELF" "$SELF"
}
```

`begin_write`'s refusal (`if [ -e "$TXN/open" ] && [ "$mode" != recover ]`,
~line 159) becomes, keeping the condition:

```bash
    local paths=""
    for p in "$TXN/open"/*.path; do [ -e "$p" ] && paths+=$(cat "$p")$'\n'; done
    die "$(recovery_message "$paths") Nothing was changed."
```

(`begin_write` holds fd 9 exclusively, so it must not call `interrupted`.)

**`cmd_pending`** (~line 1425). Replace the first
`[ -e "$TXN/open" ] && writing=true` (before `snapshot_selection`) with:

```bash
  local rpaths rrc=0
  rpaths=$(interrupted) || rrc=$?
  case $rrc in 0) die "$(recovery_message "$rpaths")" ;; 2) writing=true ;; esac
```

and the second one (after `snapshot_selection`) with:

```bash
  if [ -e "$TXN/open" ]; then
    rrc=0; rpaths=$(interrupted) || rrc=$?
    case $rrc in
      0) die "$(recovery_message "$rpaths")" ;;
      *) writing=true ;;   # 1: a live write committed during the probe
    esac
  fi
```

**`cmd_state`** (~line 1904). After the `unread_msg` lines:

```bash
  local rpaths rrc=0 rfiles='[]'
  rpaths=$(interrupted) || rrc=$?
  if [ "$rrc" = 0 ]; then
    unread_msg=${unread_msg:+$unread_msg -- }$(recovery_message "$rpaths")
    rfiles=$(printf '%s' "$rpaths" | jq -Rsc 'split("\n") | map(select(length > 0))')
  fi
```

Pass `--argjson rfiles "$rfiles"` and, after the `message` addition in the
filter, add
`+ (if $rfiles == [] then {} else { recovery: { files: $rfiles } } end)`.
`ok` stays `true`.

**`cmd_apply`** (~line 1845). After the `--pin` parsing loop, before
`private_dir APPLYDIR pkg-apply`:

```bash
  local rpaths rrc=0 refuse=""
  rpaths=$(interrupted) || rrc=$?
  case $rrc in
    0) refuse=$(recovery_message "$rpaths") ;;
    2) refuse="a write is in progress or was interrupted -- try again in a moment" ;;
  esac
  if [ -n "$refuse" ]; then
    jq -nc --arg m "$refuse" '{nixarchyPkgApply: {ok: false, exit: null, message: $m}}'
    return 0
  fi
```

**Traps.**
- `x=$(f) || rc=$?` everywhere: a bare `$(interrupted)` under `set -e`
  would exit on 1 or 2.
- `printf '%s' "$rpaths" | jq …` is a pipeline whose head cannot fail
  (`printf`), so `pipefail` is safe.
- `begin_write`'s `local` line gains `p` for the new loop.
- Paths come only from `interrupted`'s output, never from `open/` again, so
  a `recover` that runs in between cannot make a reader fail.
- The probe opens `$LOCK` with `<`, never `>`/`>>`: a reader must not create
  `applied/lock`.
- `apply`'s refusal is its only output line, and it is the record the panel
  parses (it requires only a boolean `ok`; `exit: null` is fine).

→ **Verify:** the three commands.

### 4. #66 adapter tests (`tests/adapter.sh`)

New section `echo "an interrupted write stops apply (#66)"`. Fixture
helper: `mkdir -p "$S/state/nixarchy/applied" "$S/state/nixarchy/pkg-recovery/open"`,
`: >"$S/state/nixarchy/applied/lock"`, one `0.path` naming the fixture
`apps.nix`, one `0.data`. Always create `applied/` (as `begin_write` does).

1. **Interrupted** (lock free):
   - `pending` → `ok == false`, error contains `recover` and the path;
   - `state` → `ok == true`, `.recovery.files == [<path>]`, `.message`
     contains `recover`;
   - `apply` with #60's stub `nixarchy-apply` (`run_apply`, ~line 933) →
     the only line is a record with `ok == false and exit == null`; the
     stub's `argv` file does not exist.
2. **Running, not interrupted:** the same fixture plus a background
   `( flock 9; touch "$S/ready"; exec sleep 20 ) 9>"$S/state/nixarchy/applied/lock"`
   holder (the pattern at ~line 817):
   - `pending` → `ok == true and writing == true`;
   - `state` → no `recovery` key;
   - `apply` → record `ok == false`, message contains `in progress`; stub
     not run.
   Kill and wait for the holder.
3. **Readers do not block each other:** the interrupted fixture plus a
   background holder of a **shared** lock (`flock -s 9`). `apply` still
   refuses with the recover message; stub not run.
4. **Missing lock:** `open/` present, `applied/lock` absent → `pending`
   answers `writing == true`, never `ok == false`; `applied/lock` still
   does not exist afterwards.
5. **One message:** a `toggle` against the interrupted fixture and
   `pending` both contain `an earlier write was interrupted (` and the
   path.
6. **Changed #60 test:** "open recovery marks queue as writing" (~line
   610-612) creates `open/` with no lock holder, which is now an
   interrupted write. Give it the step 4.2 holder, so it still asserts
   `writing == true`.

→ **Verify:** the three commands.

(Deviation, step 4: `run_apply`'s stub directory is gone by the time this
section runs, so the section has its own `nixarchy-apply` stub that records
its argv; "was not run" checks that file is absent.)

### 5. Panel (`PkgModel.qml`, `tests/qml/tst_pkgmodel.qml`)

1. **`armApply`** (~line 286): delete the line
   `if (queued === -1 && queueError) { message = "queue unknown -- open the Queue tab and press r"; return false }`.
   Arming always reads afresh; an `ok:false` answer refuses with its own
   error in `_absorbPending` (`message = queueError`, ~line 432).
2. **`_absorbPending`** (~line 410). After the `ok`/`else` block that sets
   `queued`/`queueError`, before the `armingState === "reading"` block:

   ```qml
   if (armingState === "armed" && (data.ok !== true || data.writing === true)) {
     disarm()
     message = data.ok !== true ? queueError : "a write is in progress -- try again in a moment"
   }
   ```
3. **`queueRows()`** (~line 178). First statement after `var out = []`:

   ```qml
   if (queueError) {
     out.push({ kind: "note", text: queueError, path: null, detail: "" })
     return out
   }
   ```
4. **Tests** in `tst_pkgmodel.qml`:
   - replace `test_arming_refused_when_queue_unknown` (~line 212): after an
     `ok:false` answer, `armApply("here")` returns `false` and
     `armingState` is `"reading"`; delivering another
     `{ok:false, error:"an earlier write was interrupted (x)"}` leaves
     `armingState == ""` and that error in `message`;
   - armed, then `{ok:false, error:"an earlier write was interrupted (x)"}`:
     `armingState == ""` **and** `message` is that error, not "the queue
     changed" (without the fix the fingerprint branch disarms with the
     wrong message, so `armingState` alone would pass);
   - armed, then `pend({ writing: true })`: `armingState == ""`;
   - deliver a good `pend({})` with at least one change, set a
     `checkResult`, then an `ok:false` answer: `queueRows()` is exactly one
     row, of kind `note`, with that text (the stale changes and the check
     row are gone).

**Traps.**
- Stubs: `deliver()` feeds and sets `running = false`; `finish(code)` ends
  without an answer. A second read is only started once the first was
  absorbed (`refreshPending` sets `_pendingAgain` while one is in flight),
  so tests deliver in order.
- `Process` restart is a no-op while running; never rely on re-setting
  `running = true`.
- `pend({…})` (~line 46) builds an `ok:true` answer; use raw
  `JSON.stringify({ok:false, …})` for failures.

→ **Verify:** the three commands and the QML tests; the coordinator runs
`nix flake check`.

### 6. Docs (agy; fallback coder)

`docs/manual/troubleshooting.md`, section "An earlier write was
interrupted". Read the strings from `bin/nixarchy-pkg`
(`recovery_message`, `begin_write`, `settle`'s note) so the prose matches.

- The panel now shows the message in the footer and in the bar's tooltip,
  and refuses `a` and `SHIFT+A` until `recover` or `recover --discard`.
  After recovering in a terminal, press `r` (or reopen the menu).
- New paragraph, "Something an interrupted write started is still
  running": what it means; there is no fixed limit (a Nix call is stopped
  after about two minutes, but a writer, or something either of them
  started, can run longer); nothing needs killing unless it never ends; to
  see what holds it:

  ```bash
  fuser -v ~/.local/state/nixarchy/pkg-children.lock
  ```
- New paragraph for "nothing was undone. Your backup is kept": run
  `recover` once it has finished.

Every command in a fenced `bash` block. Do not touch other pages.

→ **Verify:** read the page back against the strings in the code.

### 7. Coordinator: review, CI, PR, razer

- **Review.** A fresh Opus agent gets this plan and `git diff main...HEAD`.
  Codex and agy review read-only as **separate background jobs**. Fix what
  holds up, each fix with a test, and record any deviation here.
- **Ship.** Push, watch CI, open the PR linking intent, spec and plan, and
  saying which steps each implementer did.
- **File the companion issue** (below) in nixarchy and link it from the PR.
- **Manual on razer** (the lead runs it; throwaway `XDG_STATE_HOME`,
  `XDG_CONFIG_HOME` and a scratch `NIXARCHY_FLAKE`; never `/etc/nixos`):
  - `kill -9` a real `flake add` during `nix flake lock`; the next `toggle`
    refuses with "still running" until the Nix call ends;
  - with a recovery open, the panel's footer and bar show the message, and
    `a` and `SHIFT+A` refuse; `recover` in a terminal, `r`, and both work.

## Companion issues

**nixarchy: `nixarchy-apply: refuse while a nixarchy-pkg write is interrupted`**

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

## Review fixes to the plan draft (Codex `gpt-6.1-sol`; 2026-11-16)

agy's review was not obtained: "print timeout after 10m0s with the turn
still in progress; the response is partial" (`DEADLINE_EXCEEDED`).

| Finding | Fix |
|---|---|
| Short-lived grandchild test passed without waiting | `gc.done` must exist when `toggle` returns |
| Commit and `on_exit` paths had no descendant test | Cases 3b (successful writer) and 3c (TERM while settling) |
| QML: `ok:false` already disarms via the fingerprint branch; empty Queue test | Assert the message; seed changes and a check first |
| Fixture lacked `flake.lock`, a marked app row, and a way to wait for a non-child | Seeded lock, `#@ foo` row, poll `kill -0` and the lock |
| Per-step commits contradicted the approved three commits | Three commit groups |
| Docs still implied a two-minute limit | "No fixed limit" wording |

## Tests

```bash
bash -n bin/nixarchy-pkg
shellcheck bin/nixarchy-pkg tests/adapter.sh
bash tests/adapter.sh       # no failure outside the 11 listed above
nix flake check             # shellcheck, manifest, qml-tests, qml-syntax, style
```

Expected: the new #66 and #67 sections pass; the changed #60 case passes;
QML tests pass with no new QWARN.

## Rollback

Revert the step commits.
- The JSON changes are additive (`recovery`) or use existing shapes
  (`ok:false`, an apply record).
- `pkg-children.lock` is an empty file; left behind, it is inert.
- Nothing changes on a host until the plugin is rebuilt.
