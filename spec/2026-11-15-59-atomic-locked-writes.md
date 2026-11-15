---
status: draft
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
   five external writers (take the same lock, drop `mv`).
3. "Recoverable, with a findable backup" is the bar. The in-place `cp` from
   #39 stays.
4. The QML interlock is part of this task.
5. Tests: see "Where the tests run" below. This changes one intent outcome
   and needs approval here.

The design replaces four hand-written backup-and-restore sequences with one
shared guard, and adds a lock in `main`. Net effect on `bin/nixarchy-pkg`:
more lines deleted than added.

### 1. One private working directory per call, never the system temp dir

Top of `bin/nixarchy-pkg`, after `umask 077`:

```bash
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy"
readonly RECOVERY="$STATE_DIR/pkg-recovery"
readonly LOCK="$STATE_DIR/applied/lock"     # nixarchy-apply's, same expression
```

In `main`, before dispatch:

```bash
mkdir -p "$STATE_DIR/applied" "$RECOVERY"
# Working copies of the user's config belong with the user, not in /tmp.
# A call killed outright leaves its dir; the next call clears those older than an hour.
find "$STATE_DIR" -maxdepth 1 -name 'pkg-work.*' -mmin +60 -exec rm -rf {} + 2>/dev/null || :
WORK=$(mktemp -d -p "$STATE_DIR" pkg-work.XXXXXX)
export TMPDIR=$WORK
```

Every existing `mktemp` (and every `mktemp` in the external writers, which
inherit `TMPDIR`) now lands in a `0700` directory under the user's state.
The `EXIT` trap (section 3) removes `$WORK`. The four `trap ... RETURN` lines
(`:562`, `:659`, `:930`, `:1061`) are deleted: they never ran on `die` or
errexit, and `$WORK` covers every file they named.

`STATE_DIR` follows `XDG_STATE_HOME` with the same default `nixarchy-apply`
uses (`nixarchy-apply:246`), so both lock the same file.

### 2. The lock, taken in `main` for writes only

```bash
case "$cmd $*" in
  toggle*|pkg*|draft*|"opt set"*|"opt replace"*|"opt remove"*|"flake add"*|"flake remove"*)
    exec 9>"$LOCK"
    flock -w 5 9 || die "another write or an apply is running -- try again when it finishes. Nothing was changed." ;;
esac
```

- Reads (`state`, `search`, `pending`, `opt describe`, `flake show`,
  `flake list`) take no lock and are never refused.
- `apply` takes no lock here. `nixarchy-apply` takes it itself, and the
  adapter holding it would deadlock that.
- `reindex` takes no lock: it writes only the cache.
- The lock is released when the process exits, so a killed call never leaves
  it held.
- External writers run under `run_writer` while the adapter holds the lock.
  That serialises every write that goes through `nixarchy-pkg`, and writes
  made directly by the external writers remain the nixarchy follow-up (#2).

The `flake add` and `flake remove` Nix calls (`nix flake metadata`,
`nix flake lock`; `:932`, `:963`, `:968`, `:1011`, `:1077`) get the
`timeout 120` that `flake show` already uses (`:832`). Without it, an
offline `flake add` holds the lock indefinitely.

### 3. One guard for every file the adapter itself rewrites

Three functions and two traps:

```bash
GUARDED=()   # live paths this call may change

# Copy each file into $RECOVERY before anything touches it. A missing file
# is recorded as absent, so rolling back removes what the call created.
guard() {
  local f b
  for f in "$@"; do
    b="$RECOVERY/${f##*/}"
    [ -e "$b" ] || [ -e "$b.absent" ] && die "an earlier write to $f was interrupted. What it held before is in $b. Copy it back if $f looks wrong, then delete $b. Nothing was changed."
    if [ -e "$f" ]; then cp -p "$f" "$b" || { rm -f "$b"; die "could not back up $f (disk full?). Nothing was changed."; }
    else : > "$b.absent"; fi
    printf '%s\n' "$f" > "$b.path"
    GUARDED+=("$f")
  done
}

# Put every guarded file back. Prints the backups it could NOT restore from.
rollback() {
  local f b left=()
  for f in "${GUARDED[@]}"; do
    b="$RECOVERY/${f##*/}"
    if [ -e "$b.absent" ]; then rm -f "$f" && rm -f "$b.absent" "$b.path" || left+=("$f")
    elif cp "$b" "$f"; then rm -f "$b" "$b.path"
    else left+=("$b"); fi
  done
  GUARDED=()
  [ ${#left[@]} -eq 0 ] || printf ' Could not put it back; what it held before is in %s.' "${left[@]}"
}

# The write is final: drop the backups.
committed() {
  local f
  for f in "${GUARDED[@]}"; do rm -f "$RECOVERY/${f##*/}"{,.absent,.path}; done
  GUARDED=()
}
```

`die` rolls back first, then answers, so a failed restore is named in the
same answer:

```bash
die() {
  local e=$1
  [ ${#GUARDED[@]} -eq 0 ] || e+=$(rollback)
  jq -nc --arg e "$e" '{ok: false, error: $e}'
  exit 0
}
```

The `EXIT` trap catches what `die` does not see: errexit (a failed `cp`, for
example on a full disk) and caught signals. It runs only while a write is
unfinished, and only then answers, because nothing has been printed yet:

```bash
on_exit() {
  local rc=$?
  if [ ${#GUARDED[@]} -gt 0 ]; then
    jq -nc --arg e "the write was interrupted (exit $rc).$(rollback)" '{ok: false, error: $e}'
  fi
  rm -rf "$WORK"
}
trap on_exit EXIT
trap 'exit 143' TERM INT HUP
```

`SIGKILL` runs nothing. The backup then stays at
`$RECOVERY/<name>` with the original path in `<name>.path`, and the next
write to that file refuses with the message in `guard`, naming both. That is
the "fixed, documented path". The manual's troubleshooting page gets the
same text.

**Callers.** Each of the four write functions loses its own backup,
`restore_flake`, `had_lock` and trap, and gains one `guard` and one
`committed`:

| Function | `guard` before | `committed` after |
|---|---|---|
| `cmd_opt_set` | `"$APPS"`, before the awk rewrite | the parse check passes |
| `cmd_opt_replace` | `"$APPS"` | the parse check passes |
| `cmd_flake_add` | `"$file" "$lock"`, **before the first `nix flake metadata`** | the final `metadata` passes |
| `cmd_flake_remove` | `"$file" "$lock"`, **before the first `nix flake metadata`** | the final `metadata` passes |

Every existing failure branch in those four keeps its `die` message and
loses its `cp "$backup" ...` line, because `die` now restores. That fixes
intent problem 4 at its root: the lock is copied before any Nix call can
change it, the `|| :` that hid a failed lock backup is gone (`guard` dies
instead), and the three `flake remove` paths that restored nothing or only
`flake.nix` now restore both.

`cp -p` into `$RECOVERY` keeps the backup's mode no wider than the original.
The restore is `cp "$b" "$f"` onto the live path, as #39 requires: same
inode, mode, owner and symlink.

### 4. The panel

- `PkgModel.write()` (`PkgModel.qml:346`): refuse while `applying`, and say
  so: `message = "an apply is running — wait for it to finish"`.
- `PkgModel.applyInTerminal()` (`:637`): refuse while `busy` as well as
  `applying`.
- `OptionForm.commit()` (`OptionForm.qml:278`): refuse while
  `model.applying`, with the same text in `root.error`.
- Applies the panel did not start (its own terminal, the user's terminal)
  are caught by the adapter's lock. The refusal comes back as `data.error`,
  which `_absorb` already shows. No QML tracking of the terminal process is
  needed.

### 5. Where the tests run (changes one intent outcome)

The intent says "`nix flake check` runs them". It cannot. `tests/adapter.sh`
calls `nix flake metadata` and `nix flake lock` on local fixture flakes, and
the check sandbox has no Nix daemon. The script already runs on every pull
request (`.github/workflows/ci.yml:28`), which gives what the outcome was
for: no regression merges untested. So: **CI stays the runner, and
`nix flake check` is not extended.** Approving this spec approves that
change.

New cases in `tests/adapter.sh`, in the stub-based part that runs without a
nixarchy catalogue. Each builds a minimal `apps.nix` (`{ ... }:\n{\n}\n`)
or a local fixture flake, with `XDG_STATE_HOME` and `TMPDIR` pointed at
throwaway directories:

1. **Full disk mid-write.** A `cp` stub on `PATH` truncates the destination
   and exits 1 the first time its target is `apps.nix`, then delegates to the
   real `cp`. `opt set` answers `ok: false`; `apps.nix` is byte-identical;
   `$RECOVERY` is empty.
2. **Killed mid-write.** A `nix-instantiate` stub `kill -9`s the adapter
   (`$PPID`) after the rewrite. The recovery backup equals the original, and
   `.path` names `apps.nix`. The next `opt set` answers `ok: false` naming
   the backup and changes nothing.
3. **Two writes at once.** A `nix-instantiate` stub sleeps 1 s and then runs
   the real one. Two `opt set` calls with different paths start together.
   Both answer `ok: true` and both lines are in `apps.nix`.
4. **Lock held by an apply.** A background `flock` holds `$LOCK` for 10 s.
   `opt set` answers `ok: false` with "another write or an apply" within
   about 6 s, and `apps.nix` is unchanged.
5. **`flake add`: the first `metadata` rewrites the lock and fails.** A
   `nix` stub appends to `flake.lock` and exits 1 on the first
   `flake metadata`, then delegates. `flake.nix` and `flake.lock` are
   byte-identical.
6. **`flake remove` refused after `metadata` rewrote the lock** (the name is
   still referenced). `flake.lock` is byte-identical.
7. **No config in the temp directory.** After every case above, `$TMPDIR`
   is empty and no `pkg-work.*` dir is left in `$XDG_STATE_HOME/nixarchy`
   (except after case 2, which is cleared by the next call's sweep).
8. The existing #39 mode, owner and symlink cases pass unchanged.

`tests/qml/tst_pkgmodel.qml`: `write()` while `applying` returns `false`
and sets `message`; `applyInTerminal()` while `busy` does not start the
process. `OptionForm` has no harness (`flake.nix` covers `PkgModel` and
`Card` only); its one-line guard is checked by reading it in review.

### 6. Outside this repo

A nixarchy issue for the five external writers: take
`${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/applied/lock` when not
already inside `nixarchy-pkg` (which holds it), and replace `mv` with `cp`
in `app-enable` and `service-enable` for #39's reasons. Linked from #59 and
from the PR.

## Alternatives rejected

- **A separate selection lock.** It would serialise adapter writes, but the
  panel still could not see an apply started from a terminal (intent problem
  3), so writes during an apply stay possible. Sharing `nixarchy-apply`'s
  lock fixes both with one `flock`.
- **Waiting for the lock without a bound.** `nixarchy-apply` holds it
  through prompts and a whole build. A panel write would hang for minutes
  with "working…". 5 s, then a refusal that says why.
- **`rename(2)` from a temp file beside the target.** Atomic, but breaks
  #39 (owner, symlink) and fails in a `/etc/nixos` the user cannot write to.
  Ruled out by the intent.
- **Keeping the per-function backups and fixing each.** That is four copies
  of the same logic, which is how three of them came to differ (intent
  problem 4). One guard is less code and one place to test.
- **Reporting interrupted-write backups in `state`.** The panel would show
  the message, but the user could still write over it. Refusing the next
  write to that file cannot be missed and needs no QML change.
- **Guarding files the external writers change.** Each already keeps its own
  backup. Their crash safety belongs in the nixarchy follow-up, not a second
  copy here.
- **Extending `nix flake check` to run `tests/adapter.sh`.** No Nix daemon
  in the sandbox. CI already runs it.

## Risks

- **`TMPDIR` now points under `~/.local/state`.** Nix commands the adapter
  starts (`nix flake lock`, `nix-instantiate`) put their temp files there too.
  On a machine whose home is nearly full and `/tmp` is not, a write that
  worked before may now fail. It then fails cleanly and restores, which is
  the point, but the cause is new. Mitigation: the message for a failed
  backup says "disk full?".
- **A write is refused for the whole of an apply,** including one sitting at
  a terminal prompt. That is the intent's chosen rule. The refusal says what
  to do.
- **`nixarchy-apply --yes` started while a write holds the lock** fails fast
  with "another apply is running". The panel's own apply already waits for
  `busy` to clear, so this reaches only scripts. The message is misleading
  there; fixing its text is in nixarchy.
- **A leftover recovery backup blocks writes to that file** until the user
  acts. Intended. The message says exactly what to copy and what to delete.
- **External writers inherit the held lock fd 9.** None starts a long-lived
  process, so the lock is released with the adapter. A future writer that
  daemonises would hold it. Noted in the nixarchy issue.
- Hosts: verification on **razer** only. p620 is not touched.

## Verification

- `bash tests/adapter.sh` passes on razer and in CI, including cases 1–8.
- `nix flake check` passes (shellcheck covers the new code; QML tests cover
  the `PkgModel` guards).
- Manual, on razer with the panel:
  1. Start an apply, press `ESC`, press `SPACE` on an app: refused with
     "an apply is running".
  2. Run `nixarchy-apply` in a terminal, then toggle in the panel: refused
     with "another write or an apply is running".
  3. `ls "${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy"` after a few writes:
     no `pkg-work.*`, empty `pkg-recovery`. No new `/tmp/tmp.*` files.
