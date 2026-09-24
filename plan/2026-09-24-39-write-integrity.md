---
status: approved
issue: 39
spec: spec/2026-09-24-39-write-integrity.md
---

# Plan: a write either happened as reported, or it did not happen at all

## Approved decisions, carried over

Self-contained: everything needed to implement this is below.

1. **`cp`, not `mv`, at every site that writes onto a live config path.**
   `mv` is `rename(2)`: it replaces the target *inode*, taking the temp
   file's `0600` and its owner with it. `cp` onto an existing path truncates
   in place, so inode, mode, owner and symlink all survive. Measured:

   | | before | after `mv` | after `cp` |
   | --- | --- | --- | --- |
   | mode | 644 | **600** | 644 |
   | inode | 54929152 | new | 54929152 |
   | symlink | symlink | **regular file** | symlink |

   This is not a new idiom. `restore_flake:890`, `:1008`, `:1012` and the
   rollbacks at `:567`, `:638`, `:644` already use `cp` onto the live path.
   Only the write paths used `mv`.

2. **`cp` over `cat >` and over `install -m`.** `cat >` is identical in
   behaviour; `cp` is chosen because it is already this file's idiom.
   `install -m` keeps `rename` atomicity but reapplies mode by hand, cannot
   restore the owner without root, and still breaks symlinks -- it preserves
   the one property the backup already covers and loses the two that matter.

3. **`cp` is not atomic, and that is accepted.** A kill or ENOSPC mid-copy
   can truncate where `mv` could not. Mitigated: a backup is taken before
   every one of these writes; the content is fully materialised in `$tmp`
   first, so the window is a few-KB local copy; and the `nix-instantiate
   --parse` that follows catches a truncated file and restores it. Verified
   separately that `open(O_TRUNC)` fails the permission check *before*
   truncating, so a read-only target keeps its content.

4. **`opt set` gets the marker check `opt replace` already has** at `:637`,
   copied rather than factored into a shared helper. The two functions
   differ in their awk program, failure message and rollback trigger; the
   shared part is three lines, so a helper is a larger and worse diff.

5. **Tests gain `stat`-based assertions**, one per write path. Without them
   the next person to reach for `mv` regresses this silently.

6. **Scope is the write path only.** `rows_tsv:104`, `cmd_toggle:317` and
   `flat_value:527` are the same category -- the adapter reporting something
   untrue -- but no code overlap and none writes a file. Separate issue.

7. **Found while planning, folded in** (completes the approved outcome "no
   file created that was absent before, and a symlink is still a symlink"):
   - `cmd_flake_remove` has its **own** copy of the lock-restore bug at
     `:1003`/`:1013`, not just `cmd_flake_add` at `:888`/`:891`.
   - `cmd_flake_remove:1005` writes with `sed -i`, a fourth write site the
     spec did not examine. Measured: it *preserves* mode (644 -> 644) but
     replaces the inode (54929669 -> 54929670), so ownership and symlinks
     are still lost.

## Steps

1. `bin/nixarchy-pkg:558` (`cmd_opt_set`): `mv "$tmp" "$APPS"` ->
   `cp "$tmp" "$APPS"` -> verify by `grep -n 'mv "' bin/nixarchy-pkg` no
   longer listing 558.

2. `bin/nixarchy-pkg:558`, immediately after the copy and *before* the
   existing `nix-instantiate --parse` block: add the insertion guard.

   ```bash
   if ! grep -q "#@opt ${path//./\\.}\$" "$APPS"; then
     cp "$backup" "$APPS"
     die "could not find where to add $path in $APPS -- its module does not close on a line of its own. Nothing was changed."
   fi
   ```

   The wording differs from `opt replace`'s at `:639` deliberately: replace
   fails because the option was not found, set fails because the *insertion
   point* was not found, and the user's next action differs -- check the
   closing brace, not the option name. -> verify by the new test in step 8.

3. `bin/nixarchy-pkg:635` (`cmd_opt_replace`): `mv` -> `cp`. Its marker
   check at `:637` already exists and is unchanged. -> verify by `grep -n`.

4. `bin/nixarchy-pkg:902` (`cmd_flake_add`): `... "$file" > "$tmp" && mv
   "$tmp" "$file"` -> `... "$file" > "$tmp" && cp "$tmp" "$file"` -> verify
   by `grep -n 'mv "' bin/nixarchy-pkg` returning nothing at all.

5. `bin/nixarchy-pkg:888-892` (`cmd_flake_add`): record whether the lock
   existed rather than inferring it from the backup's size.

   ```bash
   local had_lock=false
   [ -f "$lock" ] && { cp "$lock" "$block"; had_lock=true; } || :
   restore_flake() {
     cp "$bnix" "$file"
     if $had_lock; then cp "$block" "$lock"; else rm -f "$lock"; fi
   }
   ```

   `-s` was never the right test: a legitimately empty pre-existing lock
   would also have failed to restore. -> verify by the new test in step 8.

6. `bin/nixarchy-pkg:1003` and `:1013` (`cmd_flake_remove`): the same
   `had_lock` treatment. This function has no `restore_flake` helper -- its
   restore is inline at `:1012-1013` -- so apply it there. -> verify by
   `grep -n '\[ -s "\$block" \]' bin/nixarchy-pkg` returning nothing.

7. `bin/nixarchy-pkg:1005` (`cmd_flake_remove`): replace the in-place
   `sed -i -E "/#@flake-input ${name}\$/d" "$file"` with the
   write-to-temp-then-`cp` shape the other three sites now use, so the
   inode survives:

   ```bash
   sed -E "/#@flake-input ${name}\$/d" "$file" > "$tmp" && cp "$tmp" "$file"
   ```

   Needs a `local tmp; tmp=$(mktemp)` and its addition to the existing
   `trap ... RETURN` at `:1001`. -> verify by `grep -n 'sed -i'
   bin/nixarchy-pkg` returning nothing.

8. `tests/adapter.sh`: add the cases below, following the file's existing
   `check "..."` / `md5sum` idiom (`:98`, `:156`, `:352`). -> verify by
   running the suite on razer.

## Deviations found during implementation

Recorded in the same commit as the code, per the workflow.

**Step 5/6 were insufficient, and the reason was upstream of them.** The
`had_lock` flag was being recorded *after* `cmd_flake_add`'s baseline
`nix flake metadata "$dir"` check -- and that check **writes the lock file it
reads** when the flake has none. So `had_lock` came out `true` on a flake
that had no lock when the user asked, the restore dutifully put back a
`flake.lock` this very call had caused to exist, and the approved outcome
("no file created that was absent before") was still not met. Caught by the
new test, which failed on the first run against razer.

Rejected fix: `--no-update-lock-file` on the baseline check. It reads as the
obvious answer -- "does it evaluate *as it stands*" is exactly what the flag
means -- but a flake with no lock cannot produce metadata without locking,
so it turned away the flakes the check exists to accept. Six existing tests
failed. Reverted.

Applied fix: capture the boolean where `lock` is defined, before any `nix`
call, in both `cmd_flake_add` (`:878`) and `cmd_flake_remove` (`:980`); the
backup copy stays where it was, now guarded by the flag
(`$had_lock && cp "$lock" "$block" || :`). Two lines each.

**One planned test was invalid and was replaced.** "flake remove leaves a
symlinked flake.nix a symlink" asserts an unreachable state: `nix flake
metadata` refuses a flake whose `flake.nix` is a symlink out of the git
repo (*"Path ... does not exist in Git repository"*), so the baseline check
turns it away before any adapter code runs. The spec already recorded that
symlinked `flake.nix` is blocked upstream; the test contradicted it.
Replaced with the reachable half -- `flake remove` keeps the file's mode --
and the reason is a comment in the suite so nobody writes it again.

## Tests

Run on **razer** over ssh, never locally, never p620.

```
nix flake check -L                      # shellcheck still clean
bash tests/adapter.sh                   # all existing cases green
```

New cases, with the expected result:

| Case | Expect |
| ---- | ------ |
| `opt set` on an `apps.nix` closing `}  # the end` | `.ok == false`, error names the closing brace, `md5sum` unchanged |
| `opt set` on a `chmod 644` `apps.nix` | `.ok == true`, `stat -c %a` still `644` |
| `opt replace` on a `chmod 644` `apps.nix` | `.ok == true`, `stat -c %a` still `644` |
| `opt set` where `apps.nix` is a symlink into another dir | `.ok == true`, `stat -c %F` still `symbolic link`, link target contains the new marker |
| `flake add` with an unresolvable ref, flake had **no** `flake.lock` | `.ok == false`, no `flake.lock` exists afterwards |
| `flake add` failure on a `chmod 644` `flake.nix` | `stat -c %a` still `644` |
| `flake remove` where `flake.nix` is a symlink | `.ok == true`, `stat -c %F` still `symbolic link` |

Manual on razer: open the panel, `stat` `apps.nix`, set an option, confirm
the panel reports it, `apps.nix` actually contains the marker, and mode and
owner are unchanged.

## Rollback

Every change is confined to `bin/nixarchy-pkg` and `tests/adapter.sh`; no
config format, no JSON contract and no QML changes, so reverting is a plain
`git revert` of the implementation commit with nothing to migrate.

If the non-atomicity of `cp` proves to be a real problem in use, the
fallback is `tmp=$(mktemp "$file.XXXXXX")` in the target's own directory +
`chmod --reference="$file" "$tmp"` + `mv`. That restores atomicity and
mode, but not owner and not symlinks -- so it is a partial retreat, not a
return to the current behaviour.

## Note for the PR description

`opt set` will now **refuse** configs it previously reported success on.
That is the point -- those are exactly the files where it silently did
nothing -- but it is a visible behaviour change and a user may read it as a
new bug.
