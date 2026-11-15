---
status: draft
issue: 59
spec: spec/2026-11-15-59-atomic-locked-writes.md
coders:
  1: codex   # small, tricky shell: traps, errexit, subshell scope, one-answer contract
  2: coder   # mechanical conversion of two functions to the step-1 helpers
  3: coder   # same pattern on the flake writers; ordering matters but is spelled out
  4: coder   # dispatch wiring and three one-line guards
  5: coder   # QML guards plus two qmltestrunner cases in the existing style
  6: agy     # large, mechanical test additions in tests/adapter.sh's existing stub style
  7: coder   # three short doc edits
reviewers:
  - codex   # strongest on bash semantics, which is where this change can go wrong
  - agy     # independent read of the whole diff against this plan
---

# Plan: a write that fails, or races another, leaves the user's files recoverable and says so

Branch `fix/59-atomic-locked-writes`. Everything below is decided. Read only this
file, the files each step names, and `bin/nixarchy-pkg` itself.

## Decisions (from the approved spec)

- **Lock.** Writes take `nixarchy-apply`'s lock,
  `${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/applied/lock`, on fd 9 with
  `flock -w 5`. On timeout they refuse: "another write or an apply is running
  -- try again when it finishes. Nothing was changed." Reads (`state`,
  `search`, `pending`, `opt describe`, `flake show`, `flake list`), `reindex`
  and `apply` never lock. `apply` must not lock: `nixarchy-apply` takes the
  lock itself.
- **Write verbs:** `toggle`, `pkg add|remove`, `draft new|undraft`,
  `opt set|replace|remove`, `flake add|remove`, and the new `recover`.
- **Working dir.** Each write gets `WORK=$(mktemp -d -p "$STATE_DIR" pkg-work.XXXXXX)`,
  with `export TMPDIR=$WORK`. Under the lock, other `pkg-work.*` dirs are
  removed (`chmod -R u+w` first: Nix leaves read-only dirs). No config copy
  ever goes to `/tmp`.
- **Recovery transaction** in `$STATE_DIR/pkg-recovery`:
  - `new/` while the backup is being built, `open/` once it is complete, then
    `done/` on commit. Each change of stage is a `mv` of the directory.
  - In a record, file `i` has `i.path` (its full live path) and either
    `i.data` (a copy, made with `cp -p`) or `i.absent`.
  - `GUARDED=true` is set only after `mv new open`.
- **Rollback** is called directly, never in `$(...)`. It sets `GUARDED=false`,
  and puts a note in `ROLLBACK_NOTE` when a restore fails. Restoring is a
  `cp` onto the live path (#39: same inode, mode, owner and symlink), or an
  `rm` for an absent file.
- **`committed`:** `mv open done || die "...so it was undone."`, then
  `GUARDED=false`, then `rm -rf done`. Never `mv && GUARDED=false`.
- **`die`** rolls back first when a write is open, then prints one JSON object
  and exits 0.
- **`EXIT` trap:**
  1. ignores further `TERM`/`INT`/`HUP`;
  2. if `GUARDED`, rolls back and prints one `{ok:false}` object, then sets
     the exit status to 0;
  3. removes `$WORK`.

  `TERM`, `INT` and `HUP` map to `exit 143`.
- **`recover_stale`**, under the lock in `begin_write`:
  - `new/` or `done/` left over: remove it and continue.
  - `open/` left over: refuse with "an earlier write was interrupted. To put
    back what was there before, run `nixarchy-pkg recover`. If the files look
    right as they are, run `nixarchy-pkg recover --discard`. Nothing was
    changed."
- **`recover [--discard]`** is a write verb. It runs the same `rollback`, or
  `rm -rf open` with `--discard`, then answers state. It does not call
  `recover_stale` on itself.
- **Candidate first.** The new content is built into `$tmp` on its own line
  (no `&&`) and checked on `$tmp` (marker `grep`, `nix-instantiate --parse`).
  Only then is it `cp`'d onto the live file.
- **Guard placement:**
  - `opt set` and `opt replace`: `guard "$APPS"`.
  - `flake add`: `guard "$file" "$lock"` right after the `-w` check, before
    any Nix call.
  - `flake remove`: the same guard, before its first `nix flake metadata`.
  - `run_writer` callers: `guard "$APPS"` (plus `"$SERVICES"` for a service
    toggle). Commit if the writer exits 0, otherwise roll back.
- **Children never keep the lock.** Every `nix` call and every `run_writer`
  call gets `9>&-`. Every `nix flake metadata` and `nix flake lock` in
  `flake add` and `flake remove` gets `timeout 120`. Writes export
  `NIXARCHY_LOCK_HELD=1`.
- **Panel:**
  - `PkgModel.write()` refuses while `applying`, with `message`.
  - `applyInTerminal()` refuses while `busy` or `applying`, with `message`.
  - `OptionForm.commit()` refuses while `model.applying`, with `error`.
- **Not in scope:** the external writers' `mv`, and serialising direct
  callers of the external writers. Both go to a nixarchy issue filed here.
- **Tests** run in CI (`ci.yml:28`), not `nix flake check`. `tests/adapter.sh`
  isolates `XDG_STATE_HOME`.
- **Verification.** Automated tests run in CI and locally; they write only to
  throwaway dirs. Manual panel checks run on **razer** only, never p620.

## Steps

Each step is one commit, `fix(adapter): …` / `fix(panel): …` /
`test: …` / `docs: …`, ending `(#59)`. After every step:
`bash -n bin/nixarchy-pkg && shellcheck bin/nixarchy-pkg tests/adapter.sh`.

1. **`bin/nixarchy-pkg:43-57`: the shared helpers.**
   - After `umask 077` (`:43`), add `STATE_DIR`, `LOCK`, `TXN` (readonly), and
     `WORK=""`, `GUARDED=false`, `ROLLBACK_NOTE=""`.
   - Replace `die` (`:54-57`) with the rolling-back version.
   - Add `begin_write`, `recover_stale`, `guard`, `rollback`, `committed`,
     `on_exit`, and the two `trap` lines, as written in spec sections 1 and 2,
     with the `committed` from the spec's final text.
   - Add `cmd_recover` (≈10 lines): `begin_write` without `recover_stale`; if
     no `open/`, answer `ok:true` "nothing to recover"; `--discard` →
     `rm -rf "$TXN/open"`; otherwise set `GUARDED=true` and call `rollback`;
     answer with `state_with` (ok when `ROLLBACK_NOTE` is empty).

   Nothing calls the new helpers yet, so behaviour is unchanged.

   In the same commit, `tests/adapter.sh:743` `renames_onto_a_config` must
   exempt the recovery directory's own renames, and nothing else:
   `code | grep -E '\bmv[[:space:]]+"' | grep -qvE '\bmv[[:space:]]+"\$TXN/'`.
   Update its comment to say why. Recovery data is the adapter's, not the
   user's; #39 is about the user's files.

   → verify: `bash -n`, shellcheck clean, `bash tests/adapter.sh` still passes
   (including "no mv onto a file the adapter owns").

   Traps:
   - `set -u` is on, so every variable `on_exit` reads must be initialised
     at top level.
   - Do not put `local` on `WORK`, `GUARDED` or `ROLLBACK_NOTE`.
   - `$GUARDED` is run as a command (`true`/`false`); keep it to those two
     values.

2. **`cmd_opt_set` (`:536-635`), `cmd_opt_replace` (`:637-702`).**
   - After the existing argument and refusal checks (before `:559` and
     `:656`), call `guard "$APPS"`.
   - Delete the `backup` `mktemp`, its `cp`, the `trap … RETURN` (`:559-562`,
     `:656-659`) and every `cp "$backup" "$APPS"`.
   - Build into `$tmp` on its own line.
   - Run the marker `grep` and `nix-instantiate --parse "$tmp" 9>&-` on
     `$tmp`, then `cp "$tmp" "$APPS"`.
   - Call `committed` before `state_with`.
   - Keep every `die` message as it is.

   → verify: `bash tests/adapter.sh`, which exercises `opt set`/`replace` and
   #39's mode and symlink cases (`:553-565`).

   Traps:
   - The "kept the default -- nothing written" early return must come
     **before** `guard`, or it leaves `open/`.
   - Keep the `cp` onto the live file (`tests/adapter.sh:739` greps the
     source against `mv`/`sed -i`).

3. **`cmd_flake_add` (`:886-989`), `cmd_flake_remove` (`:991-1088`).**
   - `flake add`: `guard "$file" "$lock"` right after `[ -w "$file" ]`
     (`:908`).
   - `flake remove`: the same guard right after the `#@flake-input` grep
     (`:1007`) and before `nix flake metadata` (`:1011`). Add a
     `[ -w "$file" ]` check before it, matching `flake add`.
   - Delete:
     - `had_lock`, `bnix`, `block`, `restore_flake`;
     - the `trap … RETURN` lines (`:929-930`, `:1060-1061`);
     - every manual restore (`cp "$bnix"`, `cp "$block"`, `rm -f "$lock"`
       inside failure branches);
     - the `rm -f "$err0"` dance.
   - Split `awk … > "$tmp" && cp` (`:954-956`) and `sed … > "$tmp" && cp`
     (`:1071`) into two lines. Run `nix-instantiate --parse "$tmp"` before the
     `cp`.
   - Prefix every `nix flake metadata` and `nix flake lock` with
     `timeout 120` and add `9>&-`.
   - Call `committed` before the final `jq` answer.

   → verify: `bash tests/adapter.sh` (the flake sections build local fixture
   flakes: "restores flake.nix byte for byte", "restores flake.lock byte for
   byte").

   Traps:
   - The lock may not exist. `guard` must record `i.absent`, and rollback must
     delete a lock the call created.
   - `flake remove`'s refusal messages at `:1038` and `:1054` must stay word
     for word.

4. **Dispatch and the writer callers.**
   - In `cmd_toggle` (before `run_writer`, `:341`), `cmd_pkg` (`add`/`remove`
     branches), `cmd_draft` (`new`/`undraft`), `cmd_opt` (`set`, `replace`,
     `remove`) and `cmd_flake` (`add`, `remove`), call `begin_write` after
     argument validation and before any file is read for writing.
     Validation-only `die`s must not wait for the lock.
   - In each `run_writer` caller, call `guard "$APPS"` (plus `"$SERVICES"`
     when `kind=service`) before `run_writer`. After it: `committed` if
     `WRITER_RC=0`, otherwise `rollback`. Then `emit_state`.
   - `run_writer` (`:282-288`): run `"$@" 9>&-`.
   - `main` (`:1396-1414`): add `recover) cmd_recover "$@" ;;` and add
     `recover` to the usage string. Add `opt replace`, `flake …` and
     `recover` to the header comment at `:9-24`.

   → verify: `bash tests/adapter.sh`. By hand, in a throwaway
   `XDG_STATE_HOME`: `flock "$XDG_STATE_HOME/nixarchy/applied/lock" sleep 8 &`
   followed by `bin/nixarchy-pkg toggle app x` answers the lock refusal within
   about 5 s.

   Traps:
   - Do not lock `opt describe`, `flake show` or `flake list`. They share
     dispatchers with write verbs.

5. **The panel.**
   - `PkgModel.qml:346` `write()`: before the `busy` check, add
     `if (applying) { message = "an apply is running — wait for it to finish"; return false }`.
   - `:637` `applyInTerminal()`: refuse when `busy` (message "still writing —
     try again in a moment") or `applying` (the apply message).
   - `OptionForm.qml:278`: before the `busy` check, add
     `if (root.model.applying) { root.error = "an apply is running — wait for it to finish"; return }`.
   - `tests/qml/tst_pkgmodel.qml`: two cases in the existing style
     (`:92-104`): `write()` while `applying` returns false and sets `message`;
     `applyInTerminal()` while `busy` leaves `_applyTerm.running` false and
     sets `message`.

   → verify: `nix flake check` (`qml-tests`, `qml-syntax`).

   Traps: the stubs under `tests/qml/imports` spawn nothing, so `_applyTerm`
   must be checked through its `running` property, not a real terminal.

6. **`tests/adapter.sh`: isolation and the ten cases.**
   - Near the top (after `:16`):
     `export XDG_STATE_HOME; XDG_STATE_HOME=$(mktemp -d)` and
     `export TMPDIR; TMPDIR=$(mktemp -d)`.
   - Add one new section, outside the `HAVE_CATALOGUE` guard, implementing
     spec section 6 cases 1–10 with `PATH` stubs in the style of `:441-459`
     and `:680`.
   - Every case asserts exactly one JSON line:
     `test "$(printf '%s\n' "$out" | grep -c '^{')" = 1`.
   - The `cp` stub matches its destination **exactly** against `$APPS`, never
     a suffix. It kills with `kill -9 "$PPID"`.
   - Case 6 waits for a ready file before calling the adapter and allows
     10 s.
   - Clean up the stub dirs and fixtures at the end of the section.

   → verify: `bash tests/adapter.sh` passes. Then break `committed`
   (temporarily `mv … && GUARDED=false`) and confirm case 4 or 9 fails, then
   restore it.

   Traps:
   - The harness runs `set -euo pipefail`. Wrap every adapter call whose exit
     may be non-zero (`kill -9`) in `out=$(…) || true`.
   - Do not touch the real `~/.local/state`.

7. **Docs.**
   - `docs/manual/troubleshooting.md`: a section "An earlier write was
     interrupted", with the refusal text and the `recover` /
     `recover --discard` commands in fenced blocks.
   - `docs/manual/from-a-terminal.md`: add `recover` to the command table.
   - `docs/manual/how-it-works.md`: one paragraph on the lock (writes wait up
     to 5 s, refuse during an apply) and that nothing goes to `/tmp`.

   → verify: `nix flake check` (the docs style greps).

8. **Mine: the nixarchy issue, CI and the PR.**
   - File a nixarchy issue: the five external writers take the lock unless
     `NIXARCHY_LOCK_HELD=1`; `app-enable` and `service-enable` use `cp`, not
     `mv`; `nixarchy-apply --yes` says "a write is in progress" when the lock
     is held by `nixarchy-pkg`. Link it from #59.
   - Push the branch and watch CI.
   - Open the PR linking intent, spec and plan, and saying which steps each
     coder did.
   - Manual checks on razer (spec, Verification 1–3), only after the owner's
     go-ahead to deploy there.

## Tests

```bash
bash -n bin/nixarchy-pkg
shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh
bash tests/adapter.sh          # all ok, 0 FAIL, including the ten new cases
nix flake check                # shellcheck, manifest, qml-tests, qml-syntax, style
grep -n 'die' bin/nixarchy-pkg # no die inside $(...) on a write path
```

## Rollback

Revert the step commits, which are independent of everything outside this
repo. Nothing changes on any host until the plugin is rebuilt, and the
recovery dir and lock are inert once the old adapter is back. A user left
with `~/.local/state/nixarchy/pkg-recovery/open/` after a revert restores by
hand from its `i.data` and `i.path` files. Step 7's docs describe that
layout.
