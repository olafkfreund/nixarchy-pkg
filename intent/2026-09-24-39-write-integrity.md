---
status: draft
issue: 39
author: olafkfreund
---

# Intent: a write either happened as reported, or it did not happen at all

## Problem

The adapter's answer is the only thing the panel knows about a write. Two
defects break that contract in opposite directions: one reports a write that
did not happen, the other makes changes during a call that reports no change.

**1. `opt set` can report success while writing nothing.**
`bin/nixarchy-pkg:550` inserts the option line before a closing brace matched
as `^}[[:space:]]*$`. Whether it matched is recorded in `ins` and never read
again, and `:579` returns `state_with true "set $path = $value"`
unconditionally. An `apps.nix` whose module closes `}  # the end` -- hand
edited, or reformatted -- is copied through unchanged, parses fine because it
is unchanged, and produces
`{"ok":true,"message":"set ...","options":[]}`: an answer that claims the
write and simultaneously reports an empty option list.

`cmd_opt_replace:637` already gets this right by re-grepping for the marker
and rolling back when it is absent. `opt set` was never given the same check.

**2. Every rewrite resets the target file's mode and owner, including on the
failure path.**
`:558`, `:635` and `:902` end with `mv "$tmp" "$file"`, where
`tmp=$(mktemp)` under `umask 077`. `rename(2)` replaces the target inode
with the temp file's, so the destination takes on the temp file's `0600` and
the invoking user as owner. Reproduced on a single filesystem: `644` before,
`600` after. This is not a cross-filesystem edge case; it happens on every
write.

Three things follow from it:

- A root-owned `/etc/nixos/flake.nix` edited through a writable `/etc/nixos`
  becomes user-owned, and that file is what `nixos-rebuild` evaluates as
  root.
- It also fires on the rollback path. A `flake add` that fails at
  `nix flake lock` answers `{"ok":false,"error":"... so nothing was
  changed"}` while leaving `flake.nix` at 600 and a `flake.lock` that did
  not exist before. `restore_flake:889-892` copies the content back but
  cannot recover the mode, and its `[ -s "$block" ]` guard skips removing a
  lock file it created.
- A symlinked `apps.nix` -- someone keeping it in a dotfiles repo -- is
  replaced by a regular file. Reproduced: the symlink becomes a real file and
  the tracked original receives none of the change, while the call reports
  success.

Neither defect is reachable by an attacker. Both are reachable by an ordinary
user with a slightly unusual config, and both fail silently.

## Proposed outcome

- Every write path either makes the change it reports, or reports that it did
  not. No answer both claims a write and shows no evidence of it.
- A call that says "nothing was changed" has changed nothing: not the
  content, not the mode, not the owner, and no file created that was absent
  before.
- A file that was a symlink is still a symlink afterwards, and the change
  reaches whatever it points at.
- A file that was mode 644 root-owned is mode 644 root-owned afterwards.
- `tests/adapter.sh` fails if any of the above regresses.

## Affected users and systems

- Anyone whose `apps.nix` does not close on a bare `}` line, or who symlinks
  it into a dotfiles repo, or whose `/etc/nixos` files are root-owned with a
  mode the adapter would otherwise strip -- which is the default layout.
- `bin/nixarchy-pkg` only: `cmd_opt_set`, `cmd_opt_replace`, `cmd_flake_add`,
  `cmd_flake_remove`, `restore_flake`. No QML change.
- `tests/adapter.sh`, which currently asserts on file *content* only and so
  cannot see a mode or ownership change at all. That blind spot is why these
  went unnoticed.
- Verification host is **razer**, per repo convention. Never p620.

## Constraints

- Must not weaken the existing backup-and-restore discipline. These paths are
  careful about content already; the fix adds to that, it does not replace
  it.
- Must not require the adapter to run as root or to elevate. Elevation stays
  delegated to `nixarchy-apply`.
- Must preserve the reason `mktemp` is used at all -- a partial write must
  never be visible at the real path. Whatever replaces `mv` keeps
  write-to-temp-then-swap semantics.
- `umask 077` on the temp file stays. The fix is that the temp file's
  permissions must not become the target's, not that the temp file should be
  laxer.
- Must not change the adapter's JSON contract. The panel parses these
  answers; the answers get *truthful*, not different in shape.

## Open questions

1. **`cat > "$file"` versus `install -m "$(stat -c %a "$file")"`.** `cat`
   keeps the inode, so mode, owner and symlink all survive for free, and it
   is one word. But it truncates before writing, so an ENOSPC or a kill
   mid-write leaves the file truncated where `mv` was atomic. `install`
   keeps atomicity but must read back and reapply mode, owner and symlink
   target by hand, and still loses the inode. Which trade?

2. **Should the mode/ownership guarantee be tested, or asserted once and
   trusted?** Adding `stat`-based assertions to `tests/adapter.sh` is the
   only way this stays fixed, but it means the suite starts caring about
   filesystem metadata, which it has deliberately never done.

3. **Scope.** The same review found three further false-success defects of
   the same shape -- `rows_tsv:104` reports an unreadable `apps.nix` as an
   empty one (`{"ok":true,"apps":0}`), `cmd_toggle:317` reports success for
   an id it never validated, and `flat_value:527` lets an option value
   smuggle a second `#@opt` marker so the panel names the wrong option. They
   are the same category -- "the adapter said something that is not true" --
   but a different code path. Fold them in, or a second issue?
