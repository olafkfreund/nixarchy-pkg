---
status: approved
issue: 39
intent: intent/2026-09-24-39-write-integrity.md
---

# Spec: a write either happened as reported, or it did not happen at all

## Design

**Decisions taken at intent approval** (the intent's three open questions;
each is a judgement made here, not by the approver, and gate 2 is where they
can be overturned):

1. **`cp`, not `cat >` and not `install -m`.** See below -- the question
   dissolved once measured.
2. **Yes, `tests/adapter.sh` gains `stat`-based assertions.** Minimal: one
   per write path. Without them this regresses the first time someone
   reaches for `mv` again.
3. **Scope stays at the two defects in the issue.** The three sibling
   false-success bugs get their own issue. Reason in "Alternatives
   rejected".

### 1. `opt set` must confirm what it inserted

`cmd_opt_replace` already solves this at `bin/nixarchy-pkg:637`: after the
rewrite it re-greps for the marker, and on a miss restores the backup and
dies. `cmd_opt_set` gets the identical block, placed between the write and
the existing `nix-instantiate --parse` check:

```bash
if ! grep -q "#@opt ${path//./\\.}\$" "$APPS"; then
  cp "$backup" "$APPS"
  die "could not find where to add $path in $APPS -- its module does not close on a line of its own. Nothing was changed."
fi
```

The message differs from `opt replace`'s deliberately: replace fails because
the option was not found, set fails because the *insertion point* was not
found, and the user's next action is different -- check the closing brace,
not the option name.

This is a copy of an existing, tested pattern rather than a shared helper.
The two functions are 60 lines apart and their surrounding logic differs;
factoring them together is a larger diff than the duplication costs. Noted
as a follow-up in the issue, not done here.

### 2. `mv` becomes `cp` at all three write sites

`bin/nixarchy-pkg:558`, `:635`, `:902`:

```bash
-  mv "$tmp" "$APPS"
+  cp "$tmp" "$APPS"
```

`mv` is `rename(2)`, which replaces the target *inode* with the temp file's
-- taking its `0600` and its owner with it. `cp` onto an existing path opens
and truncates the destination, so the inode survives and with it the mode,
the owner and any symlink. Measured:

| | before | after `mv` | after `cp` |
| --- | --- | --- | --- |
| mode | 644 | **600** | 644 |
| inode | 54929152 | new | 54929152 |
| symlink | symlink | **regular file** | symlink |

This is not a new idiom for this file. `restore_flake:889` and all four
rollback paths already use `cp` onto the live path; only the write paths
used `mv`. The change makes them agree.

`$tmp` stays. The point of writing to a temp file first -- never exposing a
half-built file at the real path -- is unchanged; only the final swap
changes. The `trap ... RETURN` cleanups still remove it.

### 3. `restore_flake` must remove a lock it created

`bin/nixarchy-pkg:887-892`. `[ -f "$lock" ] && cp "$lock" "$block" || :`
leaves `$block` an empty `mktemp` file when there was no lock, and
`[ -s "$block" ]` then skips the restore -- so a `flake.lock` that
`nix flake lock` created during a failed `flake add` is left behind by the
call that reports "nothing was changed". Record the fact rather than infer it
from the backup's size:

```bash
local had_lock=false
[ -f "$lock" ] && { cp "$lock" "$block"; had_lock=true; } || :
restore_flake() {
  cp "$bnix" "$file"
  if $had_lock; then cp "$block" "$lock"; else rm -f "$lock"; fi
}
```

`-s` was never the right test: a legitimately empty pre-existing lock would
also have failed to restore.

## Alternatives rejected

- **`cat "$tmp" > "$file"`.** Identical guarantees to `cp` -- same
  truncate-in-place, same inode. Rejected only because `cp` is already this
  file's idiom for writing onto a live path, so it reads as the same
  operation the rollbacks perform. No behavioural difference.
- **`install -m "$(stat -c %a "$file")" "$tmp" "$file"`.** Keeps `rename`
  atomicity, but reapplies the mode by hand, cannot restore the owner
  without root, and still breaks a symlink. It preserves the one property
  (atomicity) that the backup already covers, at the cost of the two that
  matter.
- **`mktemp` in the target's directory + `chmod --reference` + `mv`.**
  Preserves mode and atomicity, but not owner and not symlinks, because the
  inode is still replaced. Ownership is the security-relevant half -- a
  root-owned `/etc/nixos/flake.nix` becoming user-owned is what makes this
  worth fixing -- and only an in-place write preserves it.
- **Factoring `opt set` and `opt replace` into one rewrite-and-validate
  helper.** Tempting, and Codex recommended it. The two differ in their awk
  program, their failure message and their rollback trigger; the shared part
  is three lines. A helper here is a larger diff and a worse one. Follow-up.
- **Folding in `rows_tsv:104`, `cmd_toggle:317` and `flat_value:527`.** Same
  category -- the adapter reporting something untrue -- but different code
  paths, different tests, and none of them writes to a file. Keeping this
  task to the write path keeps the diff reviewable against one claim: a
  write either happened as reported or it did not. Separate issue.

## Risks

- **`cp` is not atomic.** A kill or ENOSPC between truncate and the last
  byte leaves a truncated `apps.nix` or `flake.nix`, where `mv` could not.
  Mitigated three ways: `$backup` / `$bnix` is already taken before the
  write on every one of these paths; the content is fully materialised in
  `$tmp` first, so the window is a local copy of a few KB; and the
  subsequent `nix-instantiate --parse` catches a truncated file and restores.
  The uncovered case is a kill during the copy itself, which loses a file the
  backup can restore by hand -- strictly better than today's silent mode and
  ownership change, which nothing can detect.
- **Permission-denied no longer truncates first.** Verified: `open(O_TRUNC)`
  fails the permission check before truncating, so a read-only target keeps
  its content and the error surfaces. Tested on a 444 file -- content intact,
  non-zero exit.
- **`opt set`'s new guard could fire on a config it used to "work" on.** By
  design: those are exactly the files where it silently did nothing. A user
  who had a broken-but-quiet setup now gets a refusal naming the cause. This
  is the intended behaviour change and belongs in the PR description.
- **razer only.** No p620.

## Verification

1. `nix flake check -L` -- `shellcheck` still clean across
   `bin/nixarchy-pkg` and `tests/adapter.sh`.
2. `tests/adapter.sh` on razer, existing cases unchanged and green.
3. New cases in `tests/adapter.sh`:
   - `opt set` against an `apps.nix` closing `}  # the end` returns
     `.ok == false`, the error names the closing brace, and the file is
     `md5sum`-identical.
   - `opt set` and `opt replace` on a `chmod 644` `apps.nix`: succeeds, and
     `stat -c %a` is still `644` afterwards.
   - `opt set` on an `apps.nix` that is a symlink into another directory:
     succeeds, `stat -c %F` is still `symbolic link`, and the link target
     contains the new option.
   - `flake add` with an unresolvable ref against a flake that had **no**
     `flake.lock`: returns `.ok == false` and no `flake.lock` exists
     afterwards.
   - `flake add` failure on a `chmod 644` `flake.nix` leaves it `644`.
4. Manual on razer: open the panel, set an option, confirm the panel reports
   it and `apps.nix` actually contains the marker; `stat` the file before and
   after and confirm mode and owner are unchanged.
