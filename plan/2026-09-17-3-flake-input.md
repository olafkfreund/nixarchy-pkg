---
status: approved
issue: 3
spec: spec/2026-09-17-3-flake-input.md
---

# Plan: declare a flake input from the panel

## The approved decisions, in full

**Declare, show, remove. Never write a module import.** Measured:
across `nixvim`, `home-manager` and `sops-nix` the `nixosModules`
convention is `default` plus a named alias, so "exactly one attribute,
therefore unambiguous" would fire almost nowhere.

**The write is one appended line.** `{ a = { x = 1; }; a.y = 2; }`
evaluates to `{ a = { x = 1; y = 2; }; }` -- a path assignment merges
with an existing attrset. So the user's `inputs { }` block is never
touched. The line is

    inputs.<name>.url = "<flakeref>";  #@flake-input <name>

placed after the flake's outer `{` (first line that is exactly `{` at
column 0: the adopter flake's `:1`, the template's `:23`). The marker is
the project's existing convention and is how removal finds the line.

**Name checking, as refined and approved at gate 2.** Refuse a name the
flake itself declares -- two definitions of one input is an error either
way. Warn and proceed on a name nixarchy uses, naming the condition:
shadowing is real on the installer template (`self.inputs //
nixarchy.inputs`, its `:91-95`) and absent on the adopter shape
(`inherit inputs`, its `:390-392`). Both lists are read from
`flake.lock`, never hard-coded -- the hard-coded 12 was already missing
`nixpkgs`, where the lock says 17.

**"Still evaluates" is a delta.** `nix flake metadata` before the write
as well as after, so an already-broken flake is not blamed on this.
Not a host build: an unused input cannot break one.

**Nothing is staged.** Both files are tracked, so their working-tree
edits are already visible to evaluation.

**Shown, not written:** `nixosModules` and `packages` enumerate;
`homeManagerModules`, `homeModules`, `darwinModules`,
`nixDarwinModules`, `flakeModules` and `modules` come back
`{"type": "unknown"}` and are named as unreadable, never drawn empty.

**Where it lives:** `bin/nixarchy-pkg`, following `cmd_opt_set`
(`:457-493`), structured so it can move upstream; an upstream issue
proposing `nixarchy flake add` is opened alongside.

## A decision this plan needs, and does not assume

The spec says "the panel shows" without saying where, and there is no
existing surface: the five tabs are lists, and the only text entry is
the search field (`Menu.qml:218`) and the option form's
(`OptionForm.qml:315`). A flakeref has to be typed somewhere.

So the work is split in two, and **phase B is severable**:

- **Phase A, steps 1-8** -- the adapter. Independently useful
  (`nixarchy-pkg flake add|remove|list|show` from a terminal),
  independently testable against throwaway flakes, and the whole of the
  risk, since it is the half that writes.
- **Phase B, steps 9-13** -- a sixth tab. Substantially more work than
  #11 and #4 together, and buys reach rather than capability.

If phase B is cut, the issue's "from the menu" is not yet satisfied and
should stay open with phase A noted as landed. Say so rather than
closing it.

## Steps

### Phase A -- the adapter

1. **`bin/nixarchy-pkg`: `flake_file()`** -- resolve
   `${NIXARCHY_FLAKE:-/etc/nixos}/flake.nix`, and locate the outer
   attrset as the first line matching `^\{$`. **Verify** it found one;
   decline with a reason if not, rather than guessing an anchor.
   -> verify by the fixture tests below, including a flake whose outer
   brace is not at column 0.

2. **`taken_names()`** -- read `flake.lock` with `jq`: the root node's
   `inputs` keys (names the flake declares), and the `nixarchy` node's
   `inputs` keys (names that may shadow). Two lists, both read.
   -> verify by printing 17 for nixarchy on this machine's flake.

3. **`cmd_flake_show <ref>`** -- `nix flake show --json` under a
   timeout, emitting `{nixosModules: [...], packages: [...],
   opaque: [...]}` where `opaque` names each module namespace whose
   value is `{"type":"unknown"}`. A timeout or failure is a reported
   outcome, not a crash.
   -> verify against `github:nix-community/nixvim`: `nixosModules`
   `["default","nixvim"]`, `opaque` containing `homeManagerModules`.

4. **`cmd_flake_add <name> <ref>`** -- the sequence, following
   `cmd_opt_set`'s idiom exactly (`mktemp` backup, `trap ... RETURN`,
   restore with `cp`, and report **Nix's own error text** grepped for
   `^error:`, per the comment at `:482-487`):
   a. refuse if `<name>` is in the flake's own inputs;
   b. warn if `<name>` is in nixarchy's, naming the condition;
   c. `nix flake metadata` **baseline** -- if it already fails, change
      nothing and say the flake was already broken;
   d. copy `flake.nix` and `flake.lock` aside;
   e. append the marked line after the outer `{`;
   f. `nix-instantiate --parse flake.nix`;
   g. `nix flake lock`;
   h. `nix flake metadata` again;
   i. any failure at f, g or h restores **both** files and reports why.
   -> verify by tests 2, 3 and 4 below.

5. **`cmd_flake_remove <name>`** -- delete the `#@flake-input <name>`
   line and run the same validate-or-restore. **Refuse** when the lock
   shows another input `follows` this one, or when the name appears
   elsewhere in the flake (a pasted import, a `specialArgs` reference),
   naming what depends on it.
   -> verify by test 7.

6. **`cmd_flake_list`** -- the marked lines, as JSON, so the panel and a
   terminal see the same thing.
   -> verify by a round trip: add, list shows it, remove, list is empty.

7. **`main()`** -- route `flake add|remove|list|show`, and extend the
   usage text.
   -> verify by `bin/nixarchy-pkg flake` printing usage and exiting 0,
   the way an unknown command already does.

8. **`tests/adapter.sh`** -- a `flake` block building a **throwaway**
   flake in a temp dir, never the machine's own, the same discipline
   `fresh_config()` already uses. Covers: merge behaviour, baseline
   refusal, round trip, restore-on-failure, own-name refusal, nixarchy
   -name warning, removal refusal, nothing staged.
   -> verify by `tests/adapter.sh` passing.

### Phase B -- the panel (severable)

9. **`PkgModel.qml`** -- a sixth tab `Flakes`; `rows()` case returning
   `state.flakes`; `activate()` on a row does nothing destructive.
10. **A flakeref entry.** Reuse the shell's `TextField`, as
    `OptionForm.qml:315` does; do not build a new widget.
11. **The show result**, drawn as rows: `nixosModules` attributes,
    `packages`, and each opaque namespace named as unreadable.
12. **The import line**, with `default` preselected, shown exactly as it
    should be pasted, beside the sentence saying the panel does not know
    which host file it belongs in.
13. **`bin/nixarchy-pkg-keys` and `README.md`** -- the new tab and its
    keys.

## Tests

    tests/adapter.sh

Expected: passes, including the new `flake` block. Every write test runs
against a throwaway flake in a temp dir.

The ten checks from the spec, as adapter-level cases:

1. **Merge behaviour first.** A fixture with nested `inputs = { ... }`
   plus an appended `inputs.added.url` evaluates to inputs including
   both. **If this fails the whole design is void** -- run it first.
2. **Baseline refusal.** Against an already-failing flake, nothing is
   written and the message says it was already broken.
3. **Round trip.** Add; `flake.nix` gains exactly one marked line,
   `flake.lock` gains the node, metadata passes. Remove; the line is
   gone and metadata still passes.
4. **Restore on failure.** A valid-but-unresolvable flakeref leaves both
   files **byte-identical** to their pre-write state.
5. **Own-name refusal.** Adding `nixpkgs` to a flake declaring
   `nixpkgs` is refused and nothing is written.
6. **nixarchy-name warning.** Adding `sops-nix` warns, names the
   condition, and proceeds.
7. **Removal refuses a dependency.** With another input `follows`-ing
   it, removal declines and names the follower.
8. **Opaque namespaces.** A flake with `homeManagerModules` reports it
   as unreadable, not as empty.
9. **Nothing staged.** After a successful add, `git status` shows both
   files modified and unstaged, and a pre-existing staged change is
   still staged and unaltered.
10. **No anchor.** A flake whose outer brace is not the first `^\{$`
    is declined with a reason, not guessed at.

Manual, only if phase B is built: the panel drives the same commands and
shows the same results; the import line is selectable; the tab is on
`?`.

## Rollback

`git revert` the implementation commit. The adapter change is additive
-- new functions, a new subcommand, no existing path altered -- so a
revert leaves the panel talking to the writers exactly as before.

A flake edited during testing is restored by `nixarchy-pkg flake remove
<name>`, or by the backup the command itself leaves. **No test touches
the machine's own flake**; if one is ever made to, that is a bug in the
test, not a rollback step.

An upstream `nixarchy flake add` landing later supersedes phase A: the
adapter command becomes a caller, which is why it is one command with
one entry point rather than logic spread through the adapter.
