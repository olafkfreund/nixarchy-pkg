---
status: draft
issue: 29
author: olafkfreund
---

# Intent: inputs named after the branch, and a remove guard that can be bypassed

## Problem

**The panel chooses the input name, and often chooses badly.**
`declareInspected` (`PkgModel.qml:803`) strips the scheme, keeps whatever
follows the last `/`, and deletes anything not `[A-Za-z0-9_-]`. The person
is never asked. Run over ordinary flakerefs:

| flakeref | input name |
| --- | --- |
| `github:nix-community/nixvim` | `nixvim` ✓ |
| `github:nix-community/home-manager/release-25.05` | `release-2505` |
| `github:NixOS/nixpkgs/nixos-unstable` | `nixos-unstable` |
| `gitlab:foo/bar/v1.2` | `v12` |
| `git+https://github.com/foo/bar.git` | `bargit` |
| `github:owner/repo?dir=sub` | `repodirsub` |
| `path:/home/me/src/thing/` | `""`, refused |

Pinning a branch is the normal way to follow a release, so the common case
names `home-manager` "release-2505". That name is then written into the
system flake, where it has to be typed in every import. The module row's
hint says `inputs.<name>.nixosModules.default` instead of the name the
panel will actually use.

**`flake remove` can skip its own safety check.** The guard that refuses
removing an input something still refers to exists because a wrong removal
breaks evaluation of the whole machine. Two faults in it, reproduced
against a throwaway flake:

- The name is not validated, and it goes into `grep -E`, `sed` and awk as
  a regex. `flake remove 'sub$'` removed the input `sub` and **skipped the
  reference check**, which had just refused a plain `sub`.
- The check matches words, and `-` counts as a word boundary, so `sub` is
  refused because a description string says `sub-projects`. That's the
  safe direction, but it leaves an input the tool can't remove.

**Smaller, same tab:**

- The first `flake show` of a remote ref left the panel on "looking at …"
  after the process had exited; a second RETURN showed the result.
- `flake add` checks only the first character of a name. `foo.bar` is
  caught by the lock step and rolled back, but reported as nix's
  "attribute 'bar' is a thunk".

## Proposed outcome

- The input name is one a person would choose, and they can see it, and
  change it, before anything is written.
- The hint shows that same name.
- `flake add` and `flake remove` accept only a valid input name and say so
  in plain words otherwise. No name can alter what the guard checks.
- Removal is refused only for a real reference.
- An inspection always ends in a result or an error on screen.

## Affected users and systems

- Anyone declaring a flake input from the Flakes tab, and the system flake
  it writes to (`/etc/nixos/flake.nix` or `NIXARCHY_FLAKE`).
- `PkgModel.qml` (`declareInspected`, the module hint, the inspector).
- `bin/nixarchy-pkg` `cmd_flake_add`, `cmd_flake_remove`.
- `tests/adapter.sh`, against a throwaway flake, never the real one.

## Constraints

- Writes to the system flake keep their discipline: baseline, backup,
  parse, lock, restore on failure.
- The rule "do not write the import line" stands.
- A name that passes validation must also match `flake list`'s pattern, so
  anything this tool declares is also something it lists.

## Open questions

1. **Derive better, or ask?** Take the repo segment (`home-manager`),
   never the ref, and let the person edit it in the field before
   declaring? Or always ask? Deriving from the repo is right for almost
   every github/gitlab ref; asking handles the rest.
2. **Validate against Nix's identifier rule, or something stricter?**
   `[A-Za-z_][A-Za-z0-9_'-]*` is what Nix accepts. `flake list` already
   assumes `[A-Za-z_][A-Za-z0-9_-]*`, which is simpler and drops only `'`.
3. **The reference check.** Compare whole identifiers (`[^A-Za-z0-9_'-]`
   as boundaries), or only look outside strings and comments? The first
   is a regex; the second is a parser. The first fixes what was actually
   seen.
