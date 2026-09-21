---
status: draft
issue: 29
spec: spec/2026-09-21-29-flake-names-and-remove.md
---

# Plan: a name you confirm, inputs validated whole, a guard that can't be steered

Depends on #27 (`focusList()`); implement after it merges.

## The approved decisions, in full

**Names.** `flake add` and `flake remove` accept a name only if it
matches `^[A-Za-z_][A-Za-z0-9_-]*$` whole (the pattern `flake list`
already parses), and otherwise die with `'<name>' is not a usable input
name: letters, digits, _ and -, starting with a letter or _`. A
validated name can't steer any grep, awk or sed.

**Refs are data.** A ref is refused unless it is printable ASCII with no
whitespace and none of `"` `\` `$` `` ` ``. The declaration line reaches
awk via `ENVIRON`, not `-v`.

**Suggested, confirmed names.** The suggestion comes from the ref's
structure: github/gitlab/sourcehut → the repo; `git+…`/`https://…` →
the last path segment without `.git`, query or archive suffix; `path:` →
the last directory. Then characters outside `[A-Za-z0-9_-]` become `-`,
and a leading digit gets a `_` prefix. RETURN on *declare this as an
input* enters name mode: the field holds the suggestion, selected, with
placeholder `input name`; RETURN declares, ESC returns to the inspection
with the ref restored. The module hint uses the name via
`importLineFor()`.

**Remove guard.** Whole-identifier match
`(^|[^A-Za-z0-9_'-])NAME([^A-Za-z0-9_'-]|$)` over every `*.nix` under the
flake directory (excluding `.git/` and `result*`), ignoring the
declaration line itself. It stays conservative: strings and comments
still count, and the refusal names file and line. `nix flake metadata`
must pass **before** removal. The success message and README say that
removal proves parse, lock and metadata, not that every host evaluates.
The outcome is "never allowed past a reference the search can see".

**Inspection state.** Editing the ref clears `inspected`. A result for
an old request (after ESC, a tab change or an edit) is dropped. The
process exit clears `inspecting`. `declareInspected` clears the
inspection only if the write started. The empty state shows `looking at
<ref>…` while inspecting. The razer hang is not claimed fixed.

## Steps

1. **`bin/nixarchy-pkg`: `valid_input_name()`**, used at the top of
   `cmd_flake_add` (replacing the `case` at `:760-763`) and
   `cmd_flake_remove` (new, before `:853`):
   `[[ $1 =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || die "…"`.
   -> verify by tests 1 and 3.

2. **`bin/nixarchy-pkg`: ref check** in `cmd_flake_add` after the name
   check: `[[ $ref =~ ^[!-~]+$ ]] && [[ $ref != *[\"\\\$\`]* ]] || die
   "that flakeref has a character a flakeref never needs (quotes,
   backslash, \$, backtick or whitespace); nothing was written"`.
   At `:810`, the awk takes the line from `ENVIRON["NIXARCHY_PKG_LINE"]`,
   not `-v line=`.
   -> verify by test 2.

3. **`bin/nixarchy-pkg`: `cmd_flake_remove`**:
   - After validation, the same baseline check as `add` (`:792-794`,
     reworded for removal).
   - Replace the `used=$(awk …)` at `:864-865` with
     `used=$(find "$dir" -name '*.nix' -not -path '*/.git/*' -not -path '*/result*' -exec awk -v n="$name" 'BEGIN { re = "(^|[^A-Za-z0-9_'"'"'-])" n "([^A-Za-z0-9_'"'"'-]|$)" } $0 ~ re && $0 !~ ("#@flake-input " n "$") { print FILENAME ":" FNR; exit }' {} +)`.
     No pipeline, so the repo's "nothing piped into head" check still
     holds. `-v` is safe here because the name is validated.
   - The refusal names `${used}` (file:line) and says a match inside a
     string or comment also blocks, so the person can remove it by hand
     if it is a false alarm.
   - The success message gains `-- the flake still parses, locks and
     evaluates its metadata; hosts were not evaluated`.
   -> verify by tests 3–6.

4. **`PkgModel.qml`: suggestion and name mode.**
   - `function suggestInputName(ref)` implements the table above and
     returns `""` when nothing is left.
   - `write(args)` returns `true` when it started, `false` when busy.
   - `property bool naming: false`, `property string namingRef: ""`.
   - `beginNaming()`: requires a successful `inspected`; sets `naming`,
     `namingRef = inspected.ref`, and returns the suggestion.
   - `declareAs(name)`: `if (write(["flake","add",name,namingRef]))
     { naming = false; inspected = null }`.
   - `cancelNaming()`: `naming = false`; returns `namingRef`.
   - In `activate()`'s case 5, the `declare` row calls the host's
     `beginNaming` path (below) instead of `declareInspected()`, which is
     deleted.
   - The module row message uses `importLineFor(suggestInputName(
     inspected.ref))`.
   -> verify by panel checks 1–3.

5. **`Menu.qml`: name mode keys.**
   - RETURN on the `declare` row → `var s = pkg.beginNaming(); search.text
     = s; search.selectAll(); search.forceActiveFocus()`.
   - While `pkg.naming`, RETURN → `pkg.declareAs(search.text)`, and ESC →
     `search.text = pkg.cancelNaming()`. Both are checked before the
     existing Flakes RETURN/ESC branches (`:162-173`, `:201`).
   - The placeholder (`:263`) is `input name` while naming.
   - `Card.qml`: while naming, the Flakes rows show one line, `declare
     <namingRef> as inputs.<field text>`.
   -> verify by panel checks 1–2.

6. **`PkgModel.qml`: inspection state.**
   - `property int _inspectToken: 0`. `inspect()` stores the token in the
     request. `setQuery()` on the Flakes tab (when not naming),
     `clearInspection()` and `setTab()` do `inspected = null;
     inspecting = false; _inspectToken++`.
   - `_inspector.onStreamFinished` returns unless the token still
     matches.
   - `_inspector` gets `onExited: Qt.callLater(function () { if
     (root.inspecting) { root.inspecting = false; root.message = "could
     not read what that flake exposes" } })`.
   - `Card.qml:229-231`: while `model.inspecting`, the empty state is
     `looking at “<query>”…`.
   -> verify by panel check 4.

7. **Docs.** `README.md`'s Flakes section: the name prompt and the
   remove guard's stated limit. `bin/nixarchy-pkg-keys` Flakes block:
   "RETURN on declare → edit the input name; RETURN declares, ESC goes
   back".
   -> verify by `bin/nixarchy-pkg-keys --print` and reading.

8. **`tests/adapter.sh`** `flake` section, reusing `fresh_flake`:
   1. `flake add 'foo.bar' …`, `'foo bar'`, `'1x'` → `ok:false`, and
      flake.nix's checksum unchanged.
   2. `flake add x 'path:/tmp/a"; y = 1; z = "'` → refused; a ref with
      `\` and one with `${` → refused; checksum unchanged.
   3. `flake remove 'sub$'` and `'.*'` → refused by validation; a
      declared `sub` is still listed.
   4. `description = "see sub-projects";` in flake.nix → `flake remove
      sub` succeeds.
   5. `inputs.sub` in `hosts/x/default.nix` → refused, error names
      `hosts/x/default.nix:1`.
   6. A flake made unparseable after declaring → `flake remove`
      refused, both files unchanged.
   -> verify by `bash tests/adapter.sh` → `all passed`, including the
   existing "shape" checks.

## Tests

    nix flake check
    bash tests/adapter.sh
    nix build .#default && omarchy plugin validate ./result

Panel, by a person, with the shell's `NIXARCHY_FLAKE` pointed at a
throwaway flake, never `/etc/nixos`:

1. `github:nix-community/home-manager/release-25.05`, RETURN, RETURN on
   declare → field shows `home-manager` selected; RETURN → declared as
   `home-manager`.
2. Same, then type `hm`, RETURN → declared as `hm`; ESC instead →
   back at the inspection with the ref in the field.
3. The module row's hint names the suggested input, not `<name>`.
4. RETURN on a slow remote ref, then ESC before it answers → no result
   reappears; edit the ref after inspecting → RETURN inspects the new
   ref.

## Rollback

`git revert` the implementation commit. Inputs already declared use the
same `#@flake-input` line format, so the old code still lists and removes
them.
