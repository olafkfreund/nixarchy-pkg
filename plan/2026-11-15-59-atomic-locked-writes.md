---
status: approved
issue: 59
spec: spec/2026-11-15-59-atomic-locked-writes.md
coders:
  1: codex   # the shared helpers: traps, errexit, subshell scope, one-answer contract
  2: coder   # opt set / opt replace onto the step-1 helpers; code is given
  3: coder   # flake add / flake remove, same pattern; order is spelled out
  4: coder   # the run_writer callers; code is given
  5: coder   # three QML guards and two qmltestrunner cases
  6: codex   # fault-injection tests: SIGKILL, stateful PATH stubs, flock races under set -e
  7: coder   # three short doc edits
reviewers:
  - codex   # strongest on bash semantics, where this change can go wrong
  - agy     # independent read of the whole diff against this plan
---

# Plan: a write that fails, or races another, leaves the user's files recoverable and says so

Branch `fix/59-atomic-locked-writes`. This file is self-contained: a coder reads
it and the files each step names, nothing else. **Coders never stage or commit.**
The coordinator (the session that owns this plan) commits after each step, as
`fix(adapter): … (#59)`, `fix(panel): … (#59)`, `test: … (#59)` or
`docs: … (#59)`.

Line numbers drift once step 1 adds code. Anchors below name a function and
quote a line. The `:NNN` numbers are where things are on `main` (`93add27`).

## Decisions (from the approved spec)

- **Lock.** Writes take `nixarchy-apply`'s lock on fd 9:
  `${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/applied/lock`, with
  `flock -w 5`. Reads (`state`, `search`, `pending`, `opt describe`,
  `flake show`, `flake list`), `reindex` and `apply` never lock. `apply` must
  not lock, because `nixarchy-apply` takes the lock itself.
- **Write verbs:** `toggle`, `pkg add|remove`, `draft new|undraft`,
  `opt set|replace|remove`, `flake add|remove`, and the new `recover`. The lock
  is taken after checks that only look at arguments, and before anything reads
  a file to decide what to write.
- **Working dir.** A write gets its own `pkg-work.*` directory under the state
  dir, with `TMPDIR` pointed at it. Under the lock, any other `pkg-work.*` is
  left over from a write that died, and is removed. No write puts anything in
  `/tmp`.
- **Recovery transaction** in `$STATE_DIR/pkg-recovery`:
  - `new/` while the backup is being made, `open/` once it is complete, `done/`
    once committed. Each move between them is one `mv` of the directory.
  - For each file `i`, `i.path` holds its absolute live path, and `i.data` holds
    a copy of it, or `i.absent` says it did not exist.
- **Candidate first.** New content is built into `$tmp` on a line of its own
  and checked there. Only then is it `cp`'d onto the live file, which keeps the
  same inode, mode, owner and symlink (#39).
- **Children never keep the lock.** Every `nix` / `nix-instantiate` call in a
  write path, and every `run_writer`, gets `9>&-`. Every `nix flake metadata`
  and `nix flake lock` in `flake add` / `flake remove` gets `timeout 120`.
- **Panel.** The panel refuses writes while an apply runs, and refuses a
  terminal apply while a write runs. Both say why.
- **Out of scope:** the external writers' `mv`, and serialising people who
  call those writers directly. Both go to a nixarchy issue (step 8).
- **Tests** run in CI (`.github/workflows/ci.yml:28`), not `nix flake check`.
- **Hosts.** Automated tests run in CI and locally, against throwaway dirs.
  Manual panel checks run on **razer** only, never p620.

## Steps

After every step: `bash -n bin/nixarchy-pkg`,
`shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh`,
`bash tests/adapter.sh` (0 FAIL). Step 5 also needs `nix flake check`.

### 1. Shared helpers, `recover`, test isolation

**`bin/nixarchy-pkg`**, directly after `umask 077` (`:43`), add:

```bash
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy"
readonly LOCK="$STATE_DIR/applied/lock"   # nixarchy-apply's lock, same expression
readonly TXN="$STATE_DIR/pkg-recovery"    # one write at a time, under the lock
WORK=""
GUARDED=false        # true only while pkg-recovery/open belongs to this call
ROLLBACK_NOTE=""
```

Replace `die()` (`:54-57`) with:

```bash
# A write that is still open is undone first, so the one answer says what is
# true afterwards.
die() {
  local e=$1
  if $GUARDED; then
    rollback
    [ -z "$ROLLBACK_NOTE" ] || e="$1 -- but the undo failed. $ROLLBACK_NOTE"
  fi
  jq -nc --arg e "$e" '{ok: false, error: $e}'
  exit 0
}
```

Below `need()`, add the following, verbatim apart from comments. Every message
is plain text; **no backticks anywhere in these strings**, because inside
double quotes they would run the command.

```bash
# errexit and signals bypass die. Undo an open write and still answer once,
# with exit 0 like every other answer.
on_exit() {
  local rc=$?
  trap '' TERM INT HUP
  if $GUARDED; then
    rollback
    jq -nc --arg e "the write was interrupted (exit $rc). ${ROLLBACK_NOTE:-Your files were put back.}" \
      '{ok: false, error: $e}'
    rc=0
  fi
  if [ -n "$WORK" ]; then
    chmod -R u+w "$WORK" 2>/dev/null || :   # nix leaves read-only dirs behind
    rm -rf "$WORK" 2>/dev/null || :
  fi
  exit "$rc"
}
trap on_exit EXIT
trap 'exit 143' TERM INT HUP

# Every write starts here, after its argument-only checks.
# begin_write recover  -- the one caller allowed past an interrupted write.
begin_write() {
  local mode=${1-} d
  mkdir -p "$STATE_DIR/applied" "$TXN" ||
    die "cannot create $STATE_DIR (disk full?). Nothing was changed."
  exec 9>"$LOCK" || die "cannot open $LOCK. Nothing was changed."
  flock -w 5 9 ||
    die "another write or an apply is running -- try again when it finishes. Nothing was changed."
  export NIXARCHY_LOCK_HELD=1
  # We hold the lock: any other working dir is from a write that died.
  for d in "$STATE_DIR"/pkg-work.*; do
    [ -e "$d" ] || continue
    chmod -R u+w "$d" 2>/dev/null || :
    rm -rf "$d" 2>/dev/null || :
  done
  WORK=$(mktemp -d -p "$STATE_DIR" pkg-work.XXXXXX) ||
    die "cannot create a working directory in $STATE_DIR (disk full?). Nothing was changed."
  export TMPDIR=$WORK
  # new/: died before the live files were touched. done/: died after the
  # write was final. Neither needs anything from the user.
  rm -rf "$TXN/new" "$TXN/done" 2>/dev/null || :
  if [ -e "$TXN/open" ] && [ "$mode" != recover ]; then
    die "an earlier write was interrupted. To put back what was there before, run: nixarchy-pkg recover. If the files look right as they are, run: nixarchy-pkg recover --discard. Nothing was changed."
  fi
}

# guard FILE...  -- every file one write may change, in one call.
guard() {
  local i=0 f
  rm -rf "$TXN/new" 2>/dev/null || :
  mkdir -p "$TXN/new" || die "cannot create $TXN (disk full?). Nothing was changed."
  for f in "$@"; do
    case $f in /*) ;; *) f=$PWD/$f ;; esac   # recover may run from elsewhere
    if [ -e "$f" ]; then
      cp -p "$f" "$TXN/new/$i.data" ||
        { rm -rf "$TXN/new"; die "could not back up $f (disk full?). Nothing was changed."; }
    else
      : > "$TXN/new/$i.absent" ||
        { rm -rf "$TXN/new"; die "could not record $f (disk full?). Nothing was changed."; }
    fi
    printf '%s\n' "$f" > "$TXN/new/$i.path" ||
      { rm -rf "$TXN/new"; die "could not record $f (disk full?). Nothing was changed."; }
    i=$((i + 1))
  done
  mv "$TXN/new" "$TXN/open" ||
    { rm -rf "$TXN/new"; die "could not record the backup (disk full?). Nothing was changed."; }
  GUARDED=true   # only now: a guard that failed never "restores" an untouched file
}

# Put every guarded file back. Called directly, never inside $(...), so that
# GUARDED changes in this shell.
rollback() {
  local p i f failed=()
  for p in "$TXN/open"/*.path; do
    [ -e "$p" ] || continue
    i=${p%.path}
    f=$(cat "$p") || { failed+=("$p (unreadable)"); continue; }
    if [ -e "$i.absent" ]; then
      rm -f "$f" || failed+=("$f (it did not exist before; delete it)")
    else
      cp "$i.data" "$f" || failed+=("$f (its earlier contents are in $i.data)")
    fi
  done
  GUARDED=false
  if [ ${#failed[@]} -eq 0 ]; then
    ROLLBACK_NOTE=""
    rm -rf "$TXN/open" 2>/dev/null || :
  else
    ROLLBACK_NOTE="Could not put back: ${failed[*]}. Then run: nixarchy-pkg recover (to try again) or nixarchy-pkg recover --discard (to keep things as they are)."
  fi
}

# The write is final. The mv is the commit point; it is not `mv && GUARDED=false`,
# because a failed mv in an && list is exempt from errexit and the EXIT trap
# would then undo a write already reported as done.
committed() {
  mv "$TXN/open" "$TXN/done" ||
    die "could not record that the write finished (disk full?), so it was undone."
  GUARDED=false
  rm -rf "$TXN/done" 2>/dev/null || :
}

# After run_writer: keep the writer's change, or undo it, and answer.
writer_finished() {
  if [ "$WRITER_RC" = 0 ]; then
    committed
  else
    rollback
    [ -z "$ROLLBACK_NOTE" ] || WRITER_OUT="$WRITER_OUT -- but the undo failed. $ROLLBACK_NOTE"
  fi
  emit_state
}

cmd_recover() {
  local discard=false p paths=()
  case "${1-}" in
    "") ;;
    --discard) discard=true ;;
    *) die "recover takes nothing or --discard, not '$1'" ;;
  esac
  begin_write recover
  [ -d "$TXN/open" ] || { state_with true "nothing to recover"; return 0; }
  for p in "$TXN/open"/*.path; do [ -e "$p" ] && paths+=("$(cat "$p")"); done
  if $discard; then
    rm -rf "$TXN/open" || die "could not remove $TXN/open"
    state_with true "kept ${paths[*]} as they are and dropped the backup"
    return 0
  fi
  GUARDED=true
  rollback
  if [ -z "$ROLLBACK_NOTE" ]; then state_with true "put back ${paths[*]}"
  else state_with false "$ROLLBACK_NOTE"; fi
}
```

`writer_finished` and `cmd_recover` call `emit_state` and `state_with`, which are
defined later in the file. That is fine in bash, because a function name is
looked up when the function runs.

In `main()`, add `recover) cmd_recover "$@" ;;` and add `recover` to the usage
string. In the header comment (`:9-24`), add `opt replace`, `flake show|add|remove|list`
and `recover [--discard]`.

**`tests/adapter.sh`**: two changes.

1. After `not() { ! "$@"; }` (`:25`), add:

   ```bash
   # The adapter keeps its lock and recovery data under XDG_STATE_HOME. Never
   # the real one.
   XDG_STATE_HOME=$(mktemp -d); export XDG_STATE_HOME
   ```

   Directly before the final `echo` / `if [ "$fails" -gt 0 ]` lines, add
   `rm -rf "$XDG_STATE_HOME"`. Do **not** export `TMPDIR` for the harness.
2. The check at `:742`, `renames_onto_a_config`, must still catch any `mv`
   onto a user's file, and exempt only the recovery directory's own stage
   changes (`new`→`open`, `open`→`done`). Replace it with:

   ```bash
   renames_onto_a_config() {
     local n
     n=$(code | grep -E '\bmv[[:space:]]+"' |
           grep -cvE '\bmv[[:space:]]+"\$TXN/(new|open)"[[:space:]]+"\$TXN/(open|done)"' || true)
     [ "$n" -gt 0 ]
   }
   ```

   *Deviation (step 1):* the plan first had `grep -qvE` here. With `-q`, or
   with `>/dev/null`, which GNU grep treats the same, the last grep stops at
   its first match. That SIGPIPEs the grep before it, and under `pipefail`
   the bad `mv` is missed. This was verified against a copy of the adapter
   with an `mv "$tmp" "$APPS"` added. A count reads all of the input.

   Update its comment: recovery data is the adapter's own, while #39 is about
   the user's files.

Nothing calls `begin_write`, `guard` or `committed` yet. Behaviour is unchanged
apart from the new `recover` verb.

→ verify: the three commands above, plus
`bin/nixarchy-pkg recover --typo` (`ok:false`) and `bin/nixarchy-pkg recover`
(`ok:true`, "nothing to recover"), both with `XDG_STATE_HOME=$(mktemp -d)`.

Traps:
- `set -u` is on, so `WORK`, `GUARDED` and `ROLLBACK_NOTE` must be set at top
  level. Never `local` them.
- `$GUARDED` is run as a command, so it may only ever be `true` or `false`.
- Do not call `die`, `rollback` or `guard` inside `$(...)`.

### 2. `cmd_opt_set` and `cmd_opt_replace`

Reorder each function to this shape. `die` messages are unchanged, word for
word.

1. Argument-only checks stay first:
   - the usage check;
   - `case "$path" in *[!a-zA-Z0-9._-]* …`;
   - `value=$(flat_value "$value") || case …`;
   - in `opt set` only, the empty-value early return
     ("kept the default for $path -- nothing written").
2. `begin_write`.
3. The checks that read `apps.nix`, moved below `begin_write`:
   - `[ -f "$APPS" ] || die "no $APPS …"`;
   - `opt set`'s "already in $APPS -- remove it first" grep;
   - `opt replace`'s "is not in $APPS" grep.
4. `guard "$APPS"`.
5. Build the candidate with the existing awk, but write
   `… ' "$APPS" > "$tmp"` as a line of its own, with no `&&`.
6. Check the candidate, not the live file:
   - the marker grep `grep -q "#@opt ${path//./\\.}\$" "$tmp" || die "<existing message>"`;
   - `why=$(nix-instantiate --parse "$tmp" 2>&1 >/dev/null 9>&-)`, with the
     existing `if ! … then … die` around it.
7. `cp "$tmp" "$APPS"` (keep `cp`; keep the `# not mv … (#39)` comment).
8. `committed`.
9. The existing `state_with true …` answer.

Delete:
- `local backup; backup=$(mktemp)`, `cp "$APPS" "$backup"`, and the
  `trap "rm -f '$backup'" RETURN` with its shellcheck comment (`:559-562`,
  `:656-659`);
- every `cp "$backup" "$APPS"` in failure branches (`die` now restores).

`tmp=$(mktemp)` stays, and now lands in `$WORK`.

→ verify: the three commands. `tests/adapter.sh`'s `opt set` / `opt replace`
cases include "an unparseable value is refused" / "and the file is
byte-identical". Also `ls "$XDG_STATE_HOME"/nixarchy` after a manual
`opt set` in a throwaway config: no `pkg-work.*`, no `pkg-recovery/open`.

Traps:
- The empty-value early return must stay **before** `begin_write`.
- `tests/adapter.sh:739-746` fails on any `mv "` onto a user's file, or
  `sed -i`.

### 3. `cmd_flake_add` and `cmd_flake_remove`

**`cmd_flake_add`**, in order:

1. The usage check, `valid_input_name "$name"`, the flakeref character check,
   and `need nix` stay first.
2. `begin_write`.
3. `dir`, `file`, `lock` as now, then `[ -w "$file" ] || die …`.
4. `guard "$file" "$lock"`. It goes **here**, before `flake_anchor`, the
   name greps, and every Nix call.
5. The rest, as now, except that:
   - the comment block and `had_lock` lines (`:902-907`) are deleted;
   - the baseline `nix flake metadata "$dir"` becomes
     `timeout 120 nix flake metadata "$dir" >/dev/null 2>"$err" 9>&-`;
   - `local bnix`, `local block`, the `trap … RETURN` (`:929-930`),
     `cp "$file" "$bnix"`, `$had_lock && cp "$lock" "$block" || :` and
     `restore_flake() { … }` are deleted;
   - the awk at `:954-956` writes `> "$tmp"` as a line of its own. Then:

     ```bash
     if ! nix-instantiate --parse "$tmp" >/dev/null 2>"$err" 9>&-; then
       die "that would have left $file unparseable, so nothing was changed: $(nix_why "$err")"
     fi
     cp "$tmp" "$file"   # not mv; see cmd_opt_set (#39)
     ```

     The old `--parse "$file"` check is replaced by this one.
   - `nix flake lock` and the final `nix flake metadata` get `timeout 120 …
     9>&-`. Each failure branch keeps its `die` message and loses its
     `restore_flake` call.
6. `committed` before the final `jq -nc … '{ok: true, name: …'`.

**`cmd_flake_remove`**, in order:

1. The usage check, `valid_input_name "$name"` and `need nix` stay first.
2. `begin_write`.
3. `dir`, `file`, `lock` as now. Add `[ -w "$file" ] || die "cannot write $file"`
   (`flake add` has it; `flake remove` never did). Then the
   `#@flake-input` grep refusal, unchanged.
4. `guard "$file" "$lock"`, before the baseline `nix flake metadata`.
5. The rest, as now, except that:
   - the comment and `had_lock` lines (`:999-1004`) are deleted;
   - `err0` and its `rm -f "$err0"` lines are replaced by a plain
     `local err; err=$(mktemp)` before the baseline, and the baseline becomes
     `timeout 120 nix flake metadata "$dir" >/dev/null 2>"$err" 9>&-`;
   - the "still referred to" (`:1038`) and "follows" (`:1054`) refusals are
     unchanged (`die` now restores the lock);
   - `bnix`, `block`, the `trap … RETURN` (`:1060-1061`), the two backup `cp`s
     and every manual restore in failure branches are deleted;
   - `sed … > "$tmp" && cp "$tmp" "$file"` (`:1071`) becomes `sed … > "$tmp"`
     on its own line, then the same `--parse "$tmp" … 9>&-` check as `flake add`
     with the existing message, then `cp "$tmp" "$file"`;
   - the final `nix flake metadata` gets `timeout 120 … 9>&-`.
6. `committed` before the final `jq -nc … '{ok: true, name: …'`.

→ verify: the three commands. The flake sections include "refuses an
unresolvable input", "restores flake.nix byte for byte", "restores flake.lock
byte for byte", "refuses to remove an input still referred to", and
"and keeps flake.nix's mode".

Traps:
- The lock may not exist yet. `guard` records `i.absent`, and an undo deletes
  a lock this call created.
- Both functions must reach `committed` before answering `ok: true`, or the
  EXIT trap undoes them.

### 4. The `run_writer` callers

- `run_writer()` (`:282-288`): the call becomes `out=$("$@" 9>&- 2>&1) || rc=$?`.
- **`cmd_toggle`**: after the id check
  (`case "$id" in *[!a-zA-Z0-9._-]* …`), call `begin_write`. Then the
  existing `file=` selection, the `[ -f "$file" ]` check, and the
  enabled/disabled greps run under the lock. After `need "nixarchy-$kind-$verb"`:

  ```bash
  if [ "$kind" = service ]; then guard "$SERVICES" "$APPS"; else guard "$APPS"; fi
  run_writer "nixarchy-$kind-$verb" "$id"
  writer_finished
  ```

  This replaces `run_writer …; emit_state`.
- **`cmd_pkg`** `add` and `remove`: after the branch's own argument checks
  and `need`, call `begin_write`, then `guard "$APPS"`, then `run_writer`.
  Replace the trailing `emit_state` with `writer_finished`. The unknown-action
  `die` still returns before any of this.
- **`cmd_draft`** `new` and `undraft`: the same as `cmd_pkg`.
- **`cmd_opt`** `remove`: after its usage check and `need`, call `begin_write`,
  then `guard "$APPS"`, then `run_writer`, then `writer_finished`.
  `describe`, `set` and `replace` are untouched here. `set` and `replace` lock
  inside their own functions (step 2).
- `cmd_flake` dispatch is untouched. `show` and `list` stay lock-free.

→ verify: the three commands, plus:

```bash
export XDG_STATE_HOME=$(mktemp -d)
mkdir -p "$XDG_STATE_HOME/nixarchy/applied"
flock "$XDG_STATE_HOME/nixarchy/applied/lock" sleep 8 &
sleep 0.5
time bin/nixarchy-pkg toggle app x   # lock refusal, about 5 s
```

Traps: `opt describe`, `flake show`, `flake list`, `state`, `search`, `pending`,
`apply` and `reindex` must never reach `begin_write`.

### 5. The panel

- `PkgModel.qml`, `function write(args)` (`:346`): as its first line, add
  `if (applying) { message = "an apply is running — wait for it to finish"; return false }`.
- `function applyInTerminal()` (`:637`): replace `if (applying) return` with:

  ```qml
  if (applying) { message = "an apply is running — wait for it to finish"; return }
  if (busy) { message = "still writing — try again in a moment"; return }
  ```
- `OptionForm.qml`, `commit()`, directly above
  `if (root.model.busy) { root.error = "still writing …` (`:278`), add
  `if (root.model.applying) { root.error = "an apply is running — wait for it to finish"; return }`.
- `tests/qml/tst_pkgmodel.qml`:
  - In `cleanup()`, also reset `m.applying = false`, `m.message = ""` and
    `m._applyTerm.running = false`.
  - Add `test_write_refused_while_applying`: set `m.applying = true`; check
    that `m.write(["toggle","app","x"])` returns `false`, that `m.message`
    contains "apply is running", and that `m.busy` is `false`.
  - Add `test_terminal_apply_refused_while_busy`: set `m.busy = true`, call
    `m.applyInTerminal()`, then check that `m._applyTerm.running` is `false`
    and `m.message` contains "still writing".

→ verify: `nix flake check` (`qml-tests`, `qml-syntax`).

Traps: the `Process` stubs under `tests/qml/imports` spawn nothing. Assert on
`running`, never on a real terminal.

### 6. Fault-injection tests in `tests/adapter.sh`

Add one section, `echo "a write that fails or races leaves the files recoverable (#59)"`,
directly before the `echo "the shape that caused it"` section, **outside**
`HAVE_CATALOGUE`.

Setup:

```bash
REAL_CP=$(command -v cp); REAL_MV=$(command -v mv); REAL_NIX=$(command -v nix)
REAL_NI=$(command -v nix-instantiate)
W59=$(mktemp -d)                         # stubs, fixtures, config
ADAPTER_TMP=$(mktemp -d)                 # TMPDIR for adapter calls only
mkdir -p "$W59/cfg/nixarchy" "$W59/stub"
A59="$W59/cfg/nixarchy/apps.nix"
reset_apps() { printf '{ ... }:\n{\n}\n' > "$A59"; }
st() { printf '%s' "$XDG_STATE_HOME/nixarchy"; }
# one answer: exactly one line that starts with {
one_json() { test "$(printf '%s\n' "$1" | grep -c '^{')" = 1; }
run59() { TMPDIR="$ADAPTER_TMP" XDG_CONFIG_HOME="$W59/cfg" PATH="$W59/stub:$PATH" "$ADAPTER" "$@"; }
```

Each stub is a small script written into `$W59/stub` with `cat > … <<EOF` and
`chmod +x`, and removed after its case. Stubs delegate to the real tool through
`$REAL_*`, baked in when the stub is written. Every adapter call whose process
may die is `out=$(run59 …) || true`.

Cases. Each case starts with `reset_apps` and `before=$(md5sum < "$A59")`.

1. **Live write fails (disk full).**
   - Stub `cp`: if its last argument is exactly `$A59` and `$W59/once` does
     not exist, `touch "$W59/once"`, truncate `$A59` (`: > "$A59"`), and
     `exit 1`. Otherwise `exec "$REAL_CP" "$@"`.
   - Call `opt set services.x.enable true`.
   - Check: `one_json`; `.ok == false`; `md5sum` equals `before`;
     `! test -e "$(st)/pkg-recovery/open"`.
2. **Candidate cannot be written.**
   - Stub `awk`: if `NIXARCHY_PKG_VALUE` is set, `exit 1`. Otherwise
     `exec` the real awk.
   - Call `opt set services.x.enable true`.
   - Check: `one_json`; `.ok == false` (today it answers `true`); file
     unchanged.
3. **Killed mid-write.**
   - Stub `cp`: as in case 1, but instead of `exit 1` it does
     `kill -9 "$PPID"`. The `cp` onto the live file is a direct child of the
     adapter, so `$PPID` is the adapter.
   - Call `opt set services.x.enable true`.
   - Check:
     - `test -d "$(st)/pkg-recovery/open"`;
     - `cmp "$(st)/pkg-recovery/open/0.data"` against a copy of the original
       taken before the call;
     - `grep -qx "$A59" "$(st)/pkg-recovery/open/0.path"`.
     - Remove the stub. Then `out=$(run59 opt set services.y.enable true)`:
       `one_json`, `.ok == false`, `.error` contains "nixarchy-pkg recover",
       the file is still truncated.
     - `out=$(run59 recover)`: `one_json`, `.ok == true`, the file equals the
       original, `! test -e …/open`, and no `pkg-work.*` under `$(st)`.
4. **The undo fails too.**
   - Stub `cp`: whenever its last argument is exactly `$A59`, truncate it and
     `exit 1`.
   - Call `opt set services.x.enable true`.
   - Check: `one_json`; `.ok == false`; `.error` contains `0.data` and
     `nixarchy-pkg recover`; `test -d …/open` (the backup is kept, as
     designed).
   - Remove the stub. `run59 recover`: the file equals the original, and
     `open` is gone.
5. **The commit step fails.**
   - Stub `mv`: if its last argument ends in `/pkg-recovery/done`, `exit 1`.
     Otherwise `exec "$REAL_MV" "$@"`.
   - Call `opt set services.x.enable true`.
   - Check: `one_json`; `.ok == false`; `.error` contains "so it was undone";
     the file equals the original; `! test -e …/open`.
   - This is the case that fails if `committed` is ever written as
     `mv … && GUARDED=false`.
6. **Two writes at once.**
   - Stub `nix-instantiate`: `sleep 1; exec "$REAL_NI" "$@"`.
   - Start `run59 opt set services.a.enable true > "$W59/a" &` and
     `run59 opt set services.b.enable true > "$W59/b" &`, then `wait`.
   - Check: both outputs `.ok == true`; both `#@opt services.a.enable` and
     `#@opt services.b.enable` lines are in `$A59`.
7. **Lock held by an apply.**
   - `mkdir -p "$(st)/applied"`, then
     `( flock 9; touch "$W59/held"; sleep 15 ) 9>"$(st)/applied/lock" &`.
   - Loop until `$W59/held` exists (at most 5 s).
   - `SECONDS=0; out=$(run59 opt set services.c.enable true)`.
   - Check: `one_json`; `.ok == false`; `.error` contains
     "another write or an apply"; `[ "$SECONDS" -le 10 ]`; file unchanged.
   - `kill %%` (or the saved pid) and `wait`.
8. **`flake add`: the first `metadata` rewrites the lock and fails.**
   - Fixture: build `$W59/fk` (a flake whose `flake.nix` has an outer `{` on
     its own line and no inputs) and `$W59/dep` (a local flake to declare),
     the same way the existing flake section builds `$FK`. Then
     `nix flake lock "$W59/fk"`.
   - Stub `nix`: if `$1 $2` is `flake metadata` and `$W59/once` does not
     exist, `touch "$W59/once"`, append a line to `$W59/fk/flake.lock`, and
     `exit 1`. Otherwise `exec "$REAL_NIX" "$@"`.
   - `NIXARCHY_FLAKE="$W59/fk" run59 flake add dep "path:$W59/dep"`.
   - Check: `one_json`; `.ok == false`; `flake.nix` and `flake.lock` are both
     byte-identical to before.
9. **`flake remove` refused after `metadata` rewrote the lock.**
   - Without stubs, `flake add dep "path:$W59/dep"` (expect `ok`). Add a
     `.nix` file in `$W59/fk` that mentions `dep`. Snapshot both files.
   - Stub `nix`: on `flake metadata`, append a line to the lock, then
     `exec "$REAL_NIX" "$@"`.
   - `flake remove dep`.
   - Check: `one_json`; `.ok == false`; `.error` contains "still referred to";
     both files are byte-identical to the snapshot.
10. **Nothing left behind.** After every case above (except mid-case 3/4,
    before `recover`):
    - `test -z "$(ls -A "$ADAPTER_TMP")"`;
    - `! compgen -G "$(st)/pkg-work.*"`;
    - `! test -e "$(st)/pkg-recovery/open"`.

    Run these as a `left_nothing` helper called at the end of each case.

The #39 mode and symlink cases already in the file must still pass, unchanged.

Teardown: `rm -rf "$W59" "$ADAPTER_TMP"`, and `rm -f "$W59/once"` between
cases.

→ verify: `bash tests/adapter.sh` passes with all of these. Then check that
the tests can fail:
1. In a scratch copy of `bin/nixarchy-pkg`, change `committed` to
   `mv … && GUARDED=false`. Case 5 must fail.
2. Remove `guard "$file" "$lock"` from `cmd_flake_add`. Case 8 must fail.

Throw the scratch copies away.

Traps:
- The harness runs under `set -euo pipefail`. Every `jq -e` goes through
  `check`, and a call that can die is `|| true`.
- Match the stub's target **exactly** against `$A59`. The backup is also
  named `….data`, inside `pkg-recovery`, and must not be hit.
- Nothing here may touch the real `~/.local/state` or `/etc/nixos`.

### 7. Docs

- `docs/manual/troubleshooting.md`: a section "An earlier write was
  interrupted". Quote the refusal text. Give the two commands in a fenced
  `bash` block:

  ```bash
  nixarchy-pkg recover            # put back what was there before
  nixarchy-pkg recover --discard  # keep the files as they are
  ```

  Then a sentence on where the data is:
  `~/.local/state/nixarchy/pkg-recovery/open/` (or under `XDG_STATE_HOME`).
  Each file has an `N.path` naming its live file, and an `N.data` holding its
  earlier contents (or `N.absent` if it did not exist), for restoring by hand.
- `docs/manual/from-a-terminal.md`: add `recover [--discard]` to the command
  table.
- `docs/manual/how-it-works.md`: one paragraph. A write waits up to 5 s for
  another write or an apply, then refuses and says why. While writing, it
  keeps a backup it can always restore from, and it puts nothing in `/tmp`.

→ verify: read the three pages back. No `nix flake check` target covers
`docs/`.

### 8. The coordinator: issue, CI, review, PR

- File the nixarchy issue. It asks for three changes and links #59:
  - the five external writers take the lock unless `NIXARCHY_LOCK_HELD=1`;
  - `nixarchy-app-enable` and `nixarchy-service-enable` use `cp`, not `mv`;
  - `nixarchy-apply --yes` says "a write is in progress" when the lock is
    held.
- Review: a fresh Opus agent gets this plan and `git diff main`, and Codex and
  agy review read-only in parallel. Weigh their findings and fix them.
- Push the branch. Watch CI (`nix flake check`, `bash tests/adapter.sh`).
- Open the PR. It links intent, spec and plan, says which steps codex, coder
  and the coordinator did, and lists any deviation recorded here.
- Manual checks on **razer**, after the owner's go-ahead to deploy there:
  1. Start an apply, press `ESC`, press `SPACE` on an app. Expect the refusal
     "an apply is running".
  2. Run `nixarchy-apply` in a terminal, then toggle in the panel. Expect the
     refusal "another write or an apply is running".
  3. After a few writes, run
     `ls "${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy"`. Expect no
     `pkg-work.*` and no `pkg-recovery/open`, and no new `/tmp/tmp.*` files.

## Tests

```bash
bash -n bin/nixarchy-pkg
shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh
bash tests/adapter.sh            # 0 FAIL, including the #59 section
nix flake check                  # shellcheck, manifest, qml-tests, qml-syntax, style
grep -nE '\$\((die|rollback|guard)' bin/nixarchy-pkg   # expect nothing
```

## Rollback

Revert the step commits. Nothing outside this repo changes, and no host
changes until the plugin is rebuilt. After a revert, the lock file and
`pkg-recovery/` are inert. A user left with `pkg-recovery/open/` restores by
hand from its `N.path` and `N.data` files, as step 7's troubleshooting page
describes.
