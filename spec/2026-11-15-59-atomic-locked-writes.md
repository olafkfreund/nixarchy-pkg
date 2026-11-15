---
status: approved
issue: 59
intent: intent/2026-11-15-59-atomic-locked-writes.md
---

# Spec: a write that fails, or races another, leaves the user's files recoverable and says so

## Design

**Decisions from intent approval** (the five open questions, taken as
recommended):

1. Writes and applies share one exclusion: `nixarchy-apply`'s existing lock.
   A write waits at most 5 s for it, then refuses.
2. This lands with the narrower guarantee. A nixarchy issue is filed for the
   five external writers.
3. "Recoverable, with a findable backup" is the bar. The in-place `cp` from
   #39 stays.
4. The QML interlock is part of this task.
5. Tests: see section 6. **This changes one intent outcome and needs approval
   here.** So does section 5's limit on the external writers.

Five parts: a lock and a private working directory for writes only; one
recovery transaction for every write; validation of the candidate *before*
the live file is touched; the panel interlock; tests. The four hand-written
backup-and-restore sequences in `bin/nixarchy-pkg` are deleted.

### 1. Writes only: the lock and a private working directory

Top of `bin/nixarchy-pkg`, after `umask 077`:

```bash
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy"
readonly LOCK="$STATE_DIR/applied/lock"   # nixarchy-apply's path, same expression
readonly TXN="$STATE_DIR/pkg-recovery"    # one transaction at a time; see 2
WORK=""
GUARDED=false
```

`STATE_DIR` uses the same default as `nixarchy-apply:246`, so both lock the
same file.

In `main`, each write verb calls `begin_write` before it dispatches. The verbs
are `toggle`, `pkg add|remove`, `draft new|undraft`,
`opt set|replace|remove`, `flake add|remove`, matched in each `cmd_*`
dispatcher rather than by a pattern over `$*`. Reads (`state`, `search`,
`pending`, `opt describe`, `flake show|list`), `reindex` and `apply` take no
lock and get no working directory. `apply` must not lock: `nixarchy-apply`
takes the lock itself.

```bash
begin_write() {
  mkdir -p "$STATE_DIR/applied" ||
    die "cannot create $STATE_DIR (disk full?). Nothing was changed."
  exec 9>"$LOCK" || die "cannot open $LOCK. Nothing was changed."
  flock -w 5 9 ||
    die "another write or an apply is running -- try again when it finishes. Nothing was changed."
  export NIXARCHY_LOCK_HELD=1   # for the nixarchy follow-up: writers we run must not re-take it
  # We hold the lock, so any other working dir belongs to a write that died.
  local d
  for d in "$STATE_DIR"/pkg-work.*; do
    [ -e "$d" ] && { chmod -R u+w "$d"; rm -rf "$d"; } 2>/dev/null || :
  done
  WORK=$(mktemp -d -p "$STATE_DIR" pkg-work.XXXXXX) ||
    die "cannot create a working directory in $STATE_DIR (disk full?). Nothing was changed."
  export TMPDIR=$WORK
  recover_stale   # section 2: refuse, or clear an incomplete record
}
```

- The sweep runs under the lock, so it can only remove the directory of a
  write that died. It never touches an apply, which has no working directory.
- Every `mktemp` in a write, and in the writers it runs, which inherit
  `TMPDIR`, lands in a `0700` directory under the user's state. Nothing goes
  to `/tmp`. The four `trap ... RETURN` lines (`:562`, `:659`, `:930`,
  `:1061`) are deleted: they never ran on `die` or errexit, and `$WORK`
  covers every file they named.
- Children must not keep the lock after the adapter dies. Every `nix` call
  and `run_writer` call gets `9>&-`.
- `flake add`'s and `flake remove`'s Nix calls (`:932`, `:963`, `:968`,
  `:1011`, `:1077`) get the `timeout 120` that `flake show` already has
  (`:832`). Otherwise an offline `flake add` holds the lock indefinitely.

### 2. One recovery transaction per write

Writes are serialised by the lock, so at most one transaction exists. It is a
directory. Every step that publishes or commits it is a `mv` of that
directory, which is atomic. #39's rule against replacing an inode applies to
the user's files, not to recovery data:

| Path | Meaning |
|---|---|
| `$TXN/new/` | being built; the live files are untouched |
| `$TXN/open/` | complete: the live files may now change |
| `$TXN/done/` | committed: safe to delete |

Inside a record, for the i-th guarded file: `i.path` holds its full live
path, and `i.data` holds a copy of it, or `i.absent` marks that it did not
exist. Keying on the index plus the recorded path means two flakes can never
share a record.

```bash
guard() {             # guard FILE...   (all files of one write, in one call)
  local i=0 f
  rm -rf "$TXN/new"; mkdir -p "$TXN/new" || die "cannot create $TXN (disk full?). Nothing was changed."
  for f in "$@"; do
    if [ -e "$f" ]; then cp -p "$f" "$TXN/new/$i.data" || { rm -rf "$TXN/new"; die "could not back up $f (disk full?). Nothing was changed."; }
    else : > "$TXN/new/$i.absent" || { rm -rf "$TXN/new"; die "could not record $f (disk full?). Nothing was changed."; }
    fi
    printf '%s\n' "$f" > "$TXN/new/$i.path" || { rm -rf "$TXN/new"; die "could not record $f (disk full?). Nothing was changed."; }
    i=$((i + 1))
  done
  mv "$TXN/new" "$TXN/open" || { rm -rf "$TXN/new"; die "could not record the backup (disk full?). Nothing was changed."; }
  GUARDED=true        # only now: a failed guard never "restores" an untouched file
}

ROLLBACK_NOTE=""
rollback() {          # called directly, never in $(...)
  local p i f failed=()
  for p in "$TXN/open"/*.path; do
    i=${p%.path}; f=$(cat "$p")
    if [ -e "$i.absent" ]; then rm -f "$f" || failed+=("$f (it did not exist before; delete it)")
    else cp "$i.data" "$f" || failed+=("$f (its earlier contents are in $i.data)"); fi
  done
  GUARDED=false
  if [ ${#failed[@]} -eq 0 ]; then rm -rf "$TXN/open"
  else ROLLBACK_NOTE="Could not put back: ${failed[*]}. Then run: rm -rf $TXN/open"; fi
}

committed() {         # the write is final
  # The commit point. Not `mv && GUARDED=false`: a failed mv there is exempt
  # from errexit, and the EXIT trap would then undo a write already reported.
  mv "$TXN/open" "$TXN/done" ||
    die "could not record that the write finished (disk full?), so it was undone."
  GUARDED=false
  rm -rf "$TXN/done" || :                       # cleanup; never undoes anything
}
```

`committed` is called before `state_with` builds the answer. `state_with`
runs `cmd_state` in `$(...)`, a subshell that inherits neither the trap nor
`GUARDED`.

**Answers.** `die` rolls back in the current shell, then answers once:

```bash
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

`die` is never called inside `$(...)` on a write path. Today none is, and the
plan's checks include grepping for it.

The `EXIT` trap catches what `die` does not see: errexit (a `cp` that fails
on a full disk) and caught signals. It ignores further signals, answers only
while a write is open (nothing has been printed then), and keeps the
exit-0-with-JSON contract:

```bash
on_exit() {
  local rc=$?
  trap '' TERM INT HUP
  if $GUARDED; then
    rollback
    jq -nc --arg e "the write was interrupted (exit $rc). ${ROLLBACK_NOTE:-Your files were put back.}" '{ok: false, error: $e}'
    rc=0
  fi
  [ -z "$WORK" ] || { chmod -R u+w "$WORK"; rm -rf "$WORK"; } 2>/dev/null || :
  exit "$rc"
}
trap on_exit EXIT
trap 'exit 143' TERM INT HUP
```

**After a `SIGKILL`** nothing runs. On the next write, `recover_stale` in
`begin_write`, under the lock, finds:

- `$TXN/new` or `$TXN/done`: the live files were not changed, or the write
  was final. It removes them and the write continues.
- `$TXN/open`: a write was interrupted mid-change. It refuses:
  *"an earlier write was interrupted. To put back what was there before, run
  `nixarchy-pkg recover`. If the files look right as they are, run
  `nixarchy-pkg recover --discard`. Nothing was changed."*

`recover` is a new write verb of about ten lines. It takes the lock, then
calls the same `rollback` (or `rm -rf "$TXN/open"` for `--discard`), and
answers what it restored. It replaces hand-written `cp` instructions, which
the reviews showed are easy to get wrong (for example, the "absent" case).
`docs/manual/troubleshooting.md` gets the same text.

### 3. Validate the candidate, then touch the live file

The live file changes only after the candidate has been built and checked
inside `$WORK`. This also fixes a pre-existing bug: `awk ... > "$tmp" && cp`
(`:956`, `:1071`) is exempt from errexit, so a failed write to `$tmp` skipped
the `cp` and the call answered `ok: true` with nothing written.

| Function | `guard` | build `$tmp`, then check it | `cp "$tmp"` to live | after |
|---|---|---|---|---|
| `cmd_opt_set` | `"$APPS"` | awk; marker grep; `nix-instantiate --parse "$tmp"` | yes | `committed` |
| `cmd_opt_replace` | `"$APPS"` | same | yes | `committed` |
| `cmd_flake_add` | `"$file" "$lock"`, right after the `-w` check (`:908`), before any Nix call | awk; `--parse "$tmp"` | yes | `nix flake lock`, `metadata`; then `committed` |
| `cmd_flake_remove` | `"$file" "$lock"`, before the first `metadata` (`:1011`) | sed; `--parse "$tmp"` | yes | `metadata`; then `committed` |
| `run_writer` callers (`toggle`, `pkg`, `opt remove`, `draft`) | `"$APPS"`, plus `"$SERVICES"` for a service toggle | the writer's own | the writer's own | `committed` if the writer exited 0, else `rollback` |

Each `> "$tmp"` stands on its own line, with no `&&`, so a failed build is
errexit and the trap handles it. Every existing failure branch keeps its
message and loses its `cp "$backup" ...` restore, because `die` now restores.
`restore_flake` and `had_lock` are deleted. Guarding before the first Nix
call fixes intent problem 4 at its root. It also covers `flake remove`'s
refusals at `:1038` and `:1054` and its parse branch at `:1073`.

Guarding around `run_writer` gives toggles and package changes the same
crash recovery. It does not fix the external writers' own `mv` (see 5).

### 4. The panel

- `PkgModel.write()` (`PkgModel.qml:346`): refuse while `applying`, and set
  `message = "an apply is running — wait for it to finish"`.
- `PkgModel.applyInTerminal()` (`:637`): refuse while `busy` or `applying`,
  and set `message` to say which.
- `OptionForm.commit()` (`OptionForm.qml:278`): refuse while
  `model.applying`, with the same text in `root.error`.
- Applies the panel did not start (its terminal, the user's terminal) are
  refused by the adapter's lock, and the refusal arrives as `data.error`,
  which `_absorb` already shows.

### 5. What this does not cover (narrows two intent outcomes; approve here)

- **The external writers' `mv`.** `nixarchy-app-enable` and
  `nixarchy-service-enable` still replace the inode when the adapter runs
  them. So a toggle still breaks a symlinked `apps.nix`, and the intent's
  "after a successful write, #39's guarantees hold" is not met for toggles
  until the nixarchy issue lands. Crash recovery for toggles is met
  (section 3).
- **Direct callers of the external writers** (a terminal running
  `nixarchy-app-enable`) are not serialised until those writers take the
  lock when `NIXARCHY_LOCK_HELD` is unset.

The nixarchy issue, filed by the plan: take the lock unless
`NIXARCHY_LOCK_HELD=1`, and replace `mv` with `cp` in `app-enable` and
`service-enable`.

### 6. Tests (changes one intent outcome; approve here)

The intent says "`nix flake check` runs them". This spec keeps CI as the
runner instead. `tests/adapter.sh` already runs on every pull request
(`.github/workflows/ci.yml:28`), and its flake cases need a Nix daemon, which
the check sandbox does not have. Splitting the stub-only cases into a
sandbox check is possible, and is a follow-up if wanted.

`tests/adapter.sh` first exports `XDG_STATE_HOME` to a throwaway directory,
so no case ever touches the real lock or recovery directory. New cases, in
the part that runs without a nixarchy catalogue, using a minimal `apps.nix`
(`{ ... }:\n{\n}\n`) or a local fixture flake:

1. **Full disk on the live write.** A `cp` stub truncates its destination
   and exits 1 when the destination is exactly `$APPS`, the first time only,
   then delegates to the real `cp`. Asserts: one JSON line; `ok: false`;
   `apps.nix` byte-identical; no `$TXN/open`.
2. **Full disk on the candidate.** `TMPDIR` cannot be written (a stub `awk`
   that exits 1). Asserts: one JSON line, `ok: false` (today: `ok: true`),
   file unchanged.
3. **Killed mid-write.** The same `cp` stub `kill -9 "$PPID"` after
   truncating. The `cp` is a direct child of the adapter, so `$PPID` is the
   adapter. Asserts: `$TXN/open` holds the original. The next `opt set` (a
   different path) answers `ok: false` naming `nixarchy-pkg recover`.
   `recover` restores `apps.nix` byte-identical and clears `$TXN`.
4. **Undo fails too.** The `cp` stub fails both the live write and the
   restore. Asserts: one JSON line naming the `i.data` file and
   `rm -rf …/open`.
5. **Two writes at once.** A `nix-instantiate` stub sleeps 1 s, then runs
   the real one. Two `opt set` calls with different paths start together.
   Both answer `ok: true`; both lines are in `apps.nix`.
6. **Lock held by an apply.** A background `flock` holds `$LOCK` and
   touches a ready file. Once that exists, `opt set` answers `ok: false`
   with "another write or an apply" in under 10 s; `apps.nix` unchanged.
7. **`flake add`: the first `metadata` rewrites the lock and fails.** A `nix`
   stub appends to `flake.lock` and exits 1 on the first `flake metadata`,
   then delegates. Asserts: `flake.nix` and `flake.lock` byte-identical, one
   JSON line.
8. **`flake remove` refused after `metadata` rewrote the lock** (the name is
   still referenced). `flake.lock` byte-identical.
9. **Nothing left behind.** After cases 1, 2, 4–8, the test's `TMPDIR` is
   empty and `$XDG_STATE_HOME/nixarchy` holds no `pkg-work.*` and no
   `pkg-recovery/open`. After case 3, the next write removes the dead
   `pkg-work.*`.
10. The existing #39 mode, owner and symlink cases pass unchanged.

`tests/qml/tst_pkgmodel.qml`: `write()` while `applying` returns `false`
and sets `message`; `applyInTerminal()` while `busy` does not start the
process and sets `message`. `OptionForm` has no harness (`flake.nix`
covers `PkgModel` and `Card` only); its one-line guard is checked in review.

## Alternatives rejected

- **A separate selection lock.** It serialises adapter writes, but the panel
  still cannot see an apply started from a terminal. Sharing
  `nixarchy-apply`'s lock fixes both.
- **Waiting for the lock without a bound.** `nixarchy-apply` holds it through
  prompts and a whole build.
- **`rename(2)` from a temp file beside the target.** Breaks #39 (owner,
  symlink) and fails in a `/etc/nixos` the user cannot write to.
- **Per-file backups keyed by basename** (the first draft). Two flakes
  collide, a half-copied backup looks complete, and removing the backups is
  not one step. One transaction directory, published and committed by
  `mv`, has none of these problems.
- **Hand-written restore instructions in the refusal.** The "absent" case
  and multi-file transactions make them error-prone. `recover` reuses the
  rollback the adapter already trusts.
- **An age-based sweep of working directories on every call.** It can
  delete the directory of a live call. Sweeping under the lock cannot.
- **Fixing the external writers' `mv` here.** Different repository; done in
  the nixarchy issue.

## Risks

- **`TMPDIR` for writes is under `~/.local/state`.** Nix commands started by
  a write put their temp files there. On a machine whose home is nearly full
  but `/tmp` is not, a write that worked before may now fail. It fails cleanly
  and says "disk full?".
- **An apply refuses while a write holds the lock.** `nixarchy-apply --yes`
  uses `flock -n` (`nixarchy-apply:252`). So pressing `a` in one panel while
  a second panel or the CLI is mid-write fails at once with "another apply
  is running", which is the wrong cause. The write holds the lock only for
  seconds (`flake add` up to 120 s). Fixing that message is in the nixarchy
  issue. The panel's own write and apply already exclude each other through
  `busy`.
- **Every write is refused for the whole of an apply,** including one
  waiting at a prompt. This is the intent's chosen rule; the message says
  what to do.
- **An interrupted write blocks writes until `recover`.** Intended. The
  refusal names the command.
- **Reads are not locked.** `state` or `pending` can see a half-written file
  during a write's `cp`, or a candidate `flake.nix` during `nix flake lock`,
  which may then be rolled back. The next refresh is correct. Locking reads
  would freeze the panel during every apply.
- Hosts: verification on **razer** only. p620 is not touched.

## Verification

- `bash tests/adapter.sh` passes on razer and in CI, including cases 1–10.
- `nix flake check` passes (shellcheck on the new code; QML tests on the
  `PkgModel` guards).
- `grep -n 'die' bin/nixarchy-pkg` shows no `die` inside `$(...)` on a write
  path.
- Manual, on razer with the panel:
  1. Start an apply, press `ESC`, press `SPACE` on an app: refused with
     "an apply is running".
  2. Run `nixarchy-apply` in a terminal, then toggle in the panel: refused
     with "another write or an apply is running".
  3. After a few writes, `ls "${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy"`
     shows no `pkg-work.*` and no `pkg-recovery/open`, and there are no new
     `/tmp/tmp.*` files.
