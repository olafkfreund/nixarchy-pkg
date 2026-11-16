---
status: approved
issue: 100
spec: spec/2026-11-16-100-home-import-parity.md
coders:
  1: codex   # one Codex run does steps 1-4 in order (owner's routing: agent-run codex refuses a dirty tree and may not commit)
  2: codex   # tests/adapter.sh: many small anchored edits plus one nix module fixture measured below
  3: codex   # bin/nixarchy-pkg: small, tricky bash/jq edits, each anchored
  4: codex   # two doc paragraphs
  # Steps 0 and 5-8 stay with the coordinator: runs, mutation proofs, commits, the live check, the PRs.
reviewers:
  - codex   # bash quoting and the sed fill are where this goes wrong
  - agy     # independent read of the diff against this plan
---

# Plan: check fills nixarchy's home template, and user scope needs useGlobalPkgs

Branch `fix/100-home-import-parity`. Line numbers are this worktree at
2c5b2a7; **find every anchor by its quoted text**, the numbers drift.

## Decisions (from the approved intent and spec; nothing here is open)

1. **`check` fills the template apply fills.** Apply writes the text of
   `homeAppsTemplateText` (nixarchy `modules/apps.nix`, exported as
   `/etc/nixarchy/home-apps-template.nix`) after
   `sed -e "s|@USER@|$user|g" -e "s|@IMPORTS@|$imports|g"`. `cmd_check` runs
   the same two expressions over the same file. `$imports` is what it already
   builds: the loop skips `home` because the template imports
   `./nixarchy/home.nix` itself.
2. **No `home.nix` selected:** `check` writes the plain stub apply's else
   branch writes (one fixed header naming four files, `imports = [...];`, `}`).
   The `parts` variable and the home line go.
3. **Template path** is `${NIXARCHY_HOME_TEMPLATE:-/etc/nixarchy/home-apps-template.nix}`.
   **The env var is new (owner decision 1: yes)**; it exists so the adapter
   test can point at a fixture, like `NIXARCHY_FLAKE`. Users never set it.
4. **Missing template** with a `home.nix` selection: `verdict: "unknown"`
   with reason `nixarchy's home template is not installed
   (/etc/nixarchy/home-apps-template.nix); update nixarchy`, before any copy,
   and the same sentence from `user_scope()`. Not in `apply_has_home` (that
   would make `snapshot_selection` drop `home.nix` and `check` answer
   `evaluates`). No fallback to the old stub.
5. **One regex.** `readonly USER_RE='^[a-z_][a-z0-9_-]*[$]?$'` replaces the
   copies in `cmd_check` and `cmd_options_refresh`. (`$` ahead of `"` or at the
   end of a Nix string is not an interpolation; only `${` is.)
6. **`useGlobalPkgs` is discovered and recorded.** `DISCOVER` gains
   `useGlobalPkgs = hm != null && (c.config.home-manager.useGlobalPkgs or false);`.
   The refresh's `meta.json` and its answer carry it. `OPT_JSON` is unchanged.
   `user_scope()` order: no home part (unchanged) -> template missing (new,
   before the cache) -> no cache / `homeManager` not true / user not in `users`
   (unchanged) -> `.useGlobalPkgs == false` (new) with
   `home-manager.useGlobalPkgs is off; user-scope packages need it`.
   A cache with no field leaves user scope available (`jq -e '.useGlobalPkgs ==
   false'` is false for null) and `state`/`search` add `userScope.note`
   `options were read before useGlobalPkgs was recorded; run options refresh`.
   Only `user_scope()` raises the refusal; `cmd_check` has no check of its
   own (the template's assertion says it).
7. **Tests.** `tests/fixtures/home-apps-template.nix` = the exact installed
   template text (below), still carrying `@USER@` and `@IMPORTS@`.
   **`tests/fixtures/nixarchy-apps-home.nix` is deleted (owner decision 3:
   yes).** The adapter compares the fixture with
   `/etc/nixarchy/home-apps-template.nix` when it exists and skips with a
   printed note when not.
8. **The nixarchy drift-check PR is part of done for #100 (owner decision 2:
   yes).** It is the last section of this plan, ships after this PR merges and
   the pin is bumped, and needs its own approval of its diff.
9. **Docs:** `docs/manual/packages.md` (User scope) and
   `docs/manual/options.md` (User scope, and the `check` paragraph) list
   `home-manager.useGlobalPkgs = true` and the installed home template.
10. **Live check** in a `nixarchy-desktop` microVM, not razer (owner's
    standing choice). **Roles:** Codex implements steps 1-4 in one run;
    everything that stages, commits, runs mutation proofs or builds is the
    coordinator's. **One PR**, two commits: tests, then the fix.

## Order and why (test-first)

The tests are written first (steps 1-2), the code after (step 3). All four
file-editing steps are one Codex run on a clean tree, in that order; the
coordinator then commits tests and code separately (step 5). The new tests
must fail against main's `bin/nixarchy-pkg`; step 5 proves it in a `mktemp`
copy and records the failing check names in the PR.

## Steps

### 0. Coordinator: baseline

`git status` clean on `fix/100-home-import-parity`. Record
`bash tests/adapter.sh </dev/null | tail -3` (ends `all passed`), plus
`shellcheck bin/nixarchy-pkg tests/adapter.sh` (clean). Confirm the fixture
text in step 1 equals nixarchy `origin/main:modules/apps.nix` `homeAppsTemplateText`:
extract in a `mktemp` dir with
`git -C /mnt/code/Source-home/GitHub/nixarchy show origin/main:modules/apps.nix | awk '/^  homeAppsTemplateText = .. *$/{f=1;next} f&&/^  \x27\x27;$/{exit} f' | sed 's/^    //'`
(the first 21 lines are the file; line 22+ is not part of it, check the awk
output ends at the line `}`). Hand Codex a clean tree.

### 1. Fixture (`tests/fixtures/`) -- codex

- Create `tests/fixtures/home-apps-template.nix` with exactly this text (21
  lines, trailing newline, no other change):

```nix
# Generated by nixarchy-apply. Do not edit -- your files
# are ~/.config/nixarchy/{apps,services,advanced,flatsnap,home}.nix and
# this is regenerated from them on every apply.
{ config, options, lib, ... }:
let
  configuredElsewhere = lib.any (d: d.file != __curPos.file && d.value ? "@USER@")
    options.home-manager.users.definitionsWithLocations;
in
{
  imports = [@IMPORTS@ ];
  home-manager.users."@USER@".imports = [
    { _module.args.pkgsOther = if config.programs.nixarchy.otherChannel.flake != null
        then config._module.args.pkgsOther else null; }
    ./nixarchy/home.nix
  ];
  assertions = [
    { assertion = config.home-manager.useGlobalPkgs; message = "nixarchy: home.nix needs home-manager.useGlobalPkgs = true"; }
    { assertion = config.users.users."@USER@".isNormalUser or false; message = "nixarchy: @USER@ is not a normal user on this machine"; }
    { assertion = configuredElsewhere; message = "nixarchy: @USER@ has no Home Manager configuration of their own; home.nix adds to one, it does not create one"; }
  ];
}
```
- `git rm tests/fixtures/nixarchy-apps-home.nix` (a plain `rm`; the
  coordinator stages). Check: `grep -rn nixarchy-apps-home .` finds only this
  plan and the spec/intent.

Traps: the file must not be re-indented or reformatted (the drift test is a
byte comparison). Do not stage.

### 2. Tests (`tests/adapter.sh`) -- codex

Anchors are in the `#62` section (`echo "options discovered from the flake (#62)"`).
Do not change the no-home case (`check omits the home import without the
installed apply part` stays as is; it must pass on main and after).

a. **Stub nix, `"$O62/bin/nix"` heredoc.** In the `nohm)` line change
   `"perUser":false,"home":null` to `"perUser":false,"useGlobalPkgs":false,"home":null`;
   in the default JSON (` "homeManager":true,"users":[...],"perUser":true,`)
   add `"useGlobalPkgs":true,`.
a2. **Existing synthetic cache.** The line
   `jq --arg u "$(id -un)" '.homeManager = true | .users = [$u]' "$cache62/meta.json"`
   (before `the user cache has no user.json`) must also set `.useGlobalPkgs = true`.
   Otherwise the new refusal (cache false from the `nohm` run) preempts the
   test `describe --scope user with no user.json refuses, saying why`
   (Codex reproduced that failure in scratch). Any other test that edits
   `meta.json` to make user scope available sets it the same way.
b. **Env var in the three env wrappers.** Add
   `NIXARCHY_HOME_TEMPLATE="$HERE/tests/fixtures/home-apps-template.nix"` (a
   quoted literal assignment) to the `env ...` list of `opt62()`, `scope62()`
   and `check62()`, next to `NIXARCHY_FLAKE=`.
c. **Drift test (this repo), before the first `scope62` call.** If
   `/etc/nixarchy/home-apps-template.nix` exists: `check "template fixture
   equals the installed template" cmp -s "$HERE/tests/fixtures/home-apps-template.nix" /etc/nixarchy/home-apps-template.nix`;
   else `echo "  skip  template fixture vs /etc (no /etc/nixarchy/home-apps-template.nix here)"`.
   Same style as the `HAVE_CATALOGUE` skip note near the top.
d. **Replace** the `check includes the home import with the installed apply
   part` line (`grep -q 'home-manager.users.*home.nix'`) with: `grep -qF
   ./nixarchy/home.nix "$O62/generated.nix"` (same description).
e. **Replace** the expected-file lines
   `sed "s/@USER@/$(id -un)/" "$HERE/tests/fixtures/nixarchy-apps-home.nix" >"$O62/expected.nix"`
   with the same `sed` the code uses over the new fixture:
   `sed -e "s|@USER@|$(id -un)|g" -e 's|@IMPORTS@| ./nixarchy/apps.nix|g' "$HERE/tests/fixtures/home-apps-template.nix" >"$O62/expected.nix"`
   and keep `check "check generates the C import form" cmp -s ...`. (`apps.nix`
   is the only selection file that test config has: the old fixture's imports
   were exactly `[ ./nixarchy/apps.nix ]`; if more files exist the expected
   string must list the same ones in apply's order: apps services advanced
   flatsnap.)
f. **New cases in the same section** (each `check "<description>" ...`):
   1. *Missing template with a home selection.* `NIXARCHY_HOME_TEMPLATE=$O62/none.nix`
      with `NIX_MODE=capture`: `check` returns `.verdict == "unknown"` and
      `.reason` containing `home template is not installed`; no `generated.nix`
      written for that run (`rm -f` it first) and no nix call (the `nix.calls`
      count is unchanged). `state` under the same env var: `.userScope.available
      == false` and `.userScope.reason` contains the same words. Run through
      `env` with the var overridden after `scope62`'s own (the later assignment
      wins), or a local wrapper.
   2. *No home selection reads no template.* Move `home.nix` aside (or use a
      config without it), `NIXARCHY_HOME_TEMPLATE=$O62/none.nix`: `check`
      with `NIX_MODE=capture` writes the plain stub: `generated.nix` has no
      `home-manager.users`, no `@`, and the header line `{apps,services,advanced,flatsnap}.nix`.
      Must pass on main too.
   3. *`useGlobalPkgs` recorded false.* `jq '.homeManager = true | .users = ["<id -un>"] | .useGlobalPkgs = false'`
      on `$OC/options/meta.json` (the file the refusal tests below already
      edit with the `mv` pattern). `state`: `.userScope.available == false` and
      `.userScope.reason` contains `useGlobalPkgs`. `scope62 pkg add --scope
      user git`: `.ok == false`, `.error` contains `useGlobalPkgs`, and
      `"$O62/state/nixarchy/pkg-recovery/open"` does not exist (no transaction),
      `home.nix` unchanged.
   4. *Old cache, no field.* `del(.useGlobalPkgs)`: `state` has
      `.userScope.available == true` and `.userScope.note` containing
      `run options refresh`; `search hm --kind opt` has the same note.
   5. *User ending in `$`.* A PATH shim dir `$O62/idbin/id` that prints
      `svc$` for `-un` (and otherwise execs the real binary, whose path is captured as `real_id=$(command -v id)` **before** the shim dir is put on `PATH`; `command id` from inside the shim would find the shim again and recurse), prepended to
      `PATH` for these two calls: (i) `options refresh` returns `.ok == true`
      (main: `invalid user name`); (ii) `check` in `NIX_MODE=capture` does not
      die and `generated.nix` contains `home-manager.users."svc$"`. Do not
      let this shim reach other tests.
   6. *Refresh records it.* After `opt62 options refresh`: `.useGlobalPkgs ==
      true` in `"$OC/options/meta.json"` (via the `options` symlink path the
      other tests already use) and in the refresh answer; the `nohm` run's
      answer has `.useGlobalPkgs == false`.
g. **Nix-gated block** (`if np62=$(nix eval --raw nixpkgs#path ...`). Extend,
   do not duplicate; keep its skip line. Facts measured in a `mktemp` dir with
   the real fixture filled for the real user: with the stub modules below, the
   three failing assertion messages and the all-true `[]` are exactly as the
   spec says, and the imports list the template gives has 2 entries (the
   inline `pkgsOther` module, then `./nixarchy/home.nix`).

   In the generated `$O62/check-flake/flake.nix`, the `selection`
   `evalModules` gets these stub modules ahead of `./nixarchy-apps.nix` (the
   attribute names are what the template reads), with the knobs read from a
   `knobs.nix` file the test rewrites per case (like `handwritten.nix`), so the
   one flake serves every case:

   ```nix
   ({ lib, ... }: let k = import ./knobs.nix; in {
     options.home-manager.useGlobalPkgs = lib.mkOption { type = lib.types.bool; };
     options.home-manager.users = lib.mkOption { default = {}; type = lib.types.attrsOf (lib.types.submodule {
       options.imports = lib.mkOption { type = lib.types.listOf lib.types.raw; default = []; }; }); };
     options.users.users = lib.mkOption { default = {}; type = lib.types.attrsOf lib.types.raw; };
     options.assertions = lib.mkOption { type = lib.types.listOf lib.types.raw; default = []; };
     options.programs.nixarchy.otherChannel.flake = lib.mkOption { default = null; };
     options._module.args = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.raw; };
     config.home-manager.useGlobalPkgs = k.useGlobalPkgs;
     config.users.users."$user62".isNormalUser = k.isNormalUser;
     config.home-manager.users = lib.mkIf k.configuredElsewhere { "$user62".imports = []; };
   })
   ```
   (`raw` for `imports` keeps the stub from evaluating the entries; the
   existing `evaluated` below evaluates them for real.) `knobs.nix` is
   `{ useGlobalPkgs = true; isNormalUser = true; configuredElsewhere = true; }`
   with one value flipped per case. Because the stub `imports` option is
   `raw` and the home user already has a definition from `mkIf`, the template's
   own definition of the user is excluded by its `__curPos.file` test, exactly
   as on a real host.

   Replace `(builtins.head selection.config.home-manager.users."$user62".imports)`
   with `] ++ selection.config.home-manager.users."$user62".imports ++ [` style
   concatenation so **the whole list is evaluated** (inline module +
   `home.nix`); keep `./handwritten.nix` and the two existing cases
   (`check evaluates merged list definitions`, `check reports a boolean
   conflict`) unchanged in their expectations. The `drvPath` becomes:
   `let failed = lib.filter (a: !a.assertion) selection.config.assertions;
   in if failed != [] then throw (builtins.head failed).message else <old
   expression>`. Write the heredoc `EOF` carefully: it is unquoted, so `$user62`
   and `$host62` expand and every Nix `${` must be written `\${` (the existing
   body has none).

   New nix-gated cases, each `check "<d>" jq -e '.verdict == "fails" and (.error
   | contains("<message>"))'` after rewriting `knobs.nix`:
   - `useGlobalPkgs = false` -> `home.nix needs home-manager.useGlobalPkgs = true`
   - `isNormalUser = false` -> `is not a normal user on this machine`
   - `configuredElsewhere = false` -> `has no Home Manager configuration of their own`
   - all true -> `.verdict == "evaluates"` (restore the knobs; this is also
     what the two existing cases run under).
   - `pkgsOther` supplied, on and off. Two more knobs in `knobs.nix`,
     `otherFlake` (default `null`) and the stub module gets
     `config.programs.nixarchy.otherChannel.flake = k.otherFlake;` and
     `config._module.args = lib.mkIf (k.otherFlake != null) { pkgsOther = { sentinel = true; }; };`.
     The flake's `drvPath` expression becomes the comma-joined list
     (`lib.concatStringsSep "," evaluated.config.demo.list`) so the answer's
     `.drvPath` shows what `home.nix` saw (the existing two cases only read
     `.verdict`/`.error`; `check` accepts any string there). `check-config/nixarchy/home.nix`
     becomes `{ pkgsOther, ... }: { demo.flag = true; demo.list = [ (if pkgsOther == null then "off" else "on") ]; }`.
     Off (`otherFlake = null`): `.verdict == "evaluates"` and `.drvPath`
     contains `off`. On (`otherFlake = "x"`): `.drvPath` contains `on`
     (Codex measured `[ "a" "off" ]` and `[ "a" "on" ]` with the sentinel).
     On main the stub import never sets the argument, so the case fails there
     with `called without required argument`. This is the only evaluation of
     the generated module's `pkgsOther` argument: nixarchy's
     `tests/home-selection.nix` compares bytes, it does not evaluate it.
     Restore `home.nix` and the knobs afterwards.
   Keep the `else` skip line.

Check: `bash tests/adapter.sh </dev/null` (**against the old code the new
cases fail; against step 3 it ends `all passed`**), `shellcheck tests/adapter.sh`.
Traps: (1) the static-source tests near `heads_a_pipeline` and
`renames_onto_a_config` grep `bin/nixarchy-pkg`: no `sed -i`, no `mv "..."` onto
a user file, nothing piped into `head`, no `diff|cmp ... | head`. (2) `shellcheck`
runs on the whole file in the flake check; a `$user62` in a single-quoted
`jq` program needs `--arg`. (3) An unquoted heredoc: escape every `${`. (4)
`bash tests/adapter.sh </dev/null` (stdin matters: some tests read it). (5) Do
not run anything against `/etc/nixos`, `~/.config` or the real cache: the file
already uses `XDG_*` scratch dirs; keep it so.

### 3. Code (`bin/nixarchy-pkg`) -- codex

a. **`USER_RE`.** After `readonly HOME_NIX="$CONFIG_DIR/home.nix"` add:
   ```bash
   # shellcheck disable=SC2016  # the $ is a regex anchor, not an expansion
   readonly USER_RE='^[a-z_][a-z0-9_-]*[$]?$'
   ```
   In `cmd_options_refresh`, `[[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || die "invalid user name: $user"`
   becomes `[[ $user =~ $USER_RE ]] || ...`; same in `cmd_check`
   (`[[ $home_user =~ ^[a-z_][a-z0-9_-]*$ ]]`, inside the home branch that
   step 3f rewrites). Unquoted `$USER_RE` on the right of `=~` is a regex.
b. **`home_template()` and the message.** Beside `user_scope()`:
   ```bash
   home_template() { printf '%s' "${NIXARCHY_HOME_TEMPLATE:-/etc/nixarchy/home-apps-template.nix}"; }
   readonly NO_HOME_TEMPLATE="nixarchy's home template is not installed (/etc/nixarchy/home-apps-template.nix); update nixarchy"
   ```
   (Define both before first use; `readonly` at top level with the others is
   fine.)
c. **`DISCOVER`.** After the line `perUser = hm != null && (hm.valueMeta.attrs or { }) ? ${user};`
   add `useGlobalPkgs = hm != null && (c.config.home-manager.useGlobalPkgs or false);`
   and after `inherit perUser;` add `inherit useGlobalPkgs;`. It is a
   single-quoted bash string: no `'` may appear in what you add.
d. **Refresh.** In `cmd_options_refresh`: the projection
   `jq -c '{homeManager,users,perUser}'` becomes `'{homeManager,users,perUser,useGlobalPkgs}'`;
   the object after `'{builtAt:$builtAt,host:...,perUser:$data.perUser,counts:...'`
   gains `useGlobalPkgs:$data.useGlobalPkgs`; the answer's projection
   `jq -c '{homeManager,perUser}'` becomes `'{homeManager,perUser,useGlobalPkgs}'` and its
   object gains `useGlobalPkgs:$data.useGlobalPkgs`. `OPT_JSON` (in
   `options_resolve`) does not change. A nix output without the field
   (`nohm` has it, but a real older nix cannot lack it since DISCOVER sets it)
   would give `null`: fine.
e. **`user_scope()`.** After the `apply_has_home` block and before
   `options_resolve`, add:
   ```bash
   [ -f "$(home_template)" ] && [ -r "$(home_template)" ] || { printf '%s' "$NO_HOME_TEMPLATE"; return; }
   ```
   and after the "user is not in home-manager.users" test add (inside the same
   function, only reached when the earlier tests passed):
   ```bash
   if jq -e '.useGlobalPkgs == false' "$meta" >/dev/null 2>&1; then
     printf '%s' 'home-manager.useGlobalPkgs is off; user-scope packages need it'
   fi
   ```
   The existing last `if` prints for the missing user; restructure as `if ...
   then printf ...; return; fi` so the new test follows it. Add
   `user_scope_note()` (prints nothing unless the cache exists, `.homeManager ==
   true`, and `has("useGlobalPkgs") | not`):
   `options were read before useGlobalPkgs was recorded; run options refresh`.
   It reads `$OPT_DIR/meta.json` after `options_resolve` (call
   `options_resolve` itself; it is idempotent).
f. **`cmd_check`.**
   1. After `pins=$(pins_json "$CHECKDIR/snap")`, add:
      `tpl=$(home_template)` and
      `if [ -f "$CHECKDIR/snap/home.nix" ] && [ ! -r "$tpl" -o ! -f "$tpl" ]; then reason=$NO_HOME_TEMPLATE; check_answer; fi`
      (write the test as two `[ ]` joined with `||`, not `-o`; shellcheck
      flags `-o`). `check_answer` exits, as at the "a write is in progress"
      use above. Declare `tpl` `local` with the others.
   2. Replace the block from `local parts=apps,services,advanced,flatsnap`
      through `printf '}\n' >>"$cb/nixarchy-apps.nix"` with:
      ```bash
      if [ -f "$CHECKDIR/snap/home.nix" ]; then
        local home_user
        home_user=$(id -un)
        [[ $home_user =~ $USER_RE ]] || die "invalid user name: $home_user"
        sed -e "s|@USER@|$home_user|g" -e "s|@IMPORTS@|$imports|g" "$tpl" >"$cb/nixarchy-apps.nix" \
          || die "cannot write $cb/nixarchy-apps.nix"
      else
        printf '# Generated by nixarchy-apply. Do not edit -- your files\n# are ~/.config/nixarchy/{apps,services,advanced,flatsnap}.nix and\n# this is regenerated from them on every apply.\n{\n  imports = [%s ];\n}\n' \
          "$imports" >"$cb/nixarchy-apps.nix" || die "cannot write $cb/nixarchy-apps.nix"
      fi
      ```
      The `rm -f "$cb/nixarchy-apps.nix"` above it stays. The plain stub must
      equal what apply's else-branch writes (nixarchy `modules/apps.nix`, the
      `printf` in the `else` of the `sed` fill; compare once by eye).
g. **State and search note.** In `cmd_state` and `cmd_search`, beside
   `user_reason=$(user_scope)` add `user_note=""`; `[ -z "$user_reason" ] &&
   user_note=$(user_scope_note)` (if/then form, `set -e` safe); add
   `--arg userNote "$user_note"` to the `jq` call and `note:$userNote` to
   `userScope: {available:$userAvailable, reason:$userReason}` in both.
   `local` the new variable in both functions (their `local facts stale
   user_reason user_available=false` lines).

Check: `bash tests/adapter.sh </dev/null` ends `all passed`;
`shellcheck bin/nixarchy-pkg tests/adapter.sh` clean; `nix flake check` (the
flake's `shellcheck` and adapter checks).
Traps: (1) `set -e` and `local`: do not write `local x=$(cmd)`; the repo
declares then assigns. (2) `readonly` with a regex containing `$`: SC2016 needs
the disable comment on the line before. (3) `sed` replacement `|` delimiter:
`$imports` and the user (now matching `USER_RE`) contain no `|` or `&`; keep
the validation before the `sed`. (4) `check_answer` ends the run; code after
it is unreachable on that branch (the same idiom is used at the "write in
progress" test). (5) The subshell `$(user_scope)` cannot set variables for its
caller. (6) `jq -e` exits 1 on null/false and 4 on bad input: the
`.useGlobalPkgs == false` test depends on null giving `false`. (7) Do not
touch `snapshot_selection` or `apply_has_home`.

### 4. Docs -- codex

- `docs/manual/packages.md`, the paragraph after `## User scope`: after "needs
  Home Manager as a NixOS module, your account in `home-manager.users`" add
  "`home-manager.useGlobalPkgs = true`", and keep "a nixarchy version with
  the Home Manager part" adding "and its installed home template
  (`/etc/nixarchy/home-apps-template.nix`)".
- `docs/manual/options.md`, `## User scope`: the same additions; in the
  paragraph that begins "Removing a selection can leave a declaration
  elsewhere" append "For user scope `check` evaluates the same file
  `nixarchy-apply` will write (filled from that template), so a failed
  assertion (`useGlobalPkgs`, a non-normal user, no Home Manager configuration
  of your own) is reported with nix's message."
No other doc changes. Check: `grep -n useGlobalPkgs docs/manual/*.md` finds both.

### 5. Coordinator: verify, prove, commit

1. `bash tests/adapter.sh </dev/null` ends `all passed`; `shellcheck bin/nixarchy-pkg
   bin/nixarchy-pkg-keys tests/adapter.sh`; `nix flake check`.
2. **Must fail on main.** In a `mktemp` copy `d`:
   `( cd "$d" || exit 1; git show main:bin/nixarchy-pkg > bin/nixarchy-pkg;
   bash tests/adapter.sh </dev/null | grep -i 'FAIL' )` after copying the
   worktree (tests and fixtures new, code old). Expected failing checks, by
   description: the generated-file equality (`check generates the C import
   form`), the `./nixarchy/home.nix` grep is expected to **pass** on main (the
   old stub also names it; it is a regression guard, not a failing test), the
   three assertion cases, the `pkgsOther` case, the `useGlobalPkgs` state and
   `pkg add` refusal, the `$`-user refresh and check cases, the missing-template
   `unknown` and `state` reason, the `.useGlobalPkgs` in the refresh answer.
   These stay passing on main: the no-`useGlobalPkgs`-field availability, the
   no-home plain stub. Paste the actual list in the PR; a case expected to fail
   that passes on main is a bad test: fix it.
3. **Mutation proofs**, each in its own `mktemp` copy, `( cd "$d" || exit 1; ... )`:
   - change one character of `tests/fixtures/home-apps-template.nix`: the
     drift test fails (needs `/etc/nixarchy/...`; on a host without it prove it
     with a temporary copy of the fixture at a scratch path and a one-off
     `cmp`, and say so in the PR; the real proof is the nixarchy case);
   - delete the `.useGlobalPkgs == false` block from `user_scope`: the
     refusal tests fail;
   - restore the old `printf` fill in `cmd_check`: byte-equality and the three
     assertion tests fail.
4. Commits (the coordinator; Codex never commits): first `test(check): the
   home template check and useGlobalPkgs (#100)` containing `tests/` only,
   second `fix(check): fill nixarchy's home template, record useGlobalPkgs
   (#100)` containing `bin/` and `docs/`. Commit messages end with the
   attribution lines the session gives. Approve `plan/` in its own commit
   first (`docs(plan): approve ... (#100)`), before any of this.

### 6. Review

`git diff main` against this plan by a fresh `model: "opus"` agent given only
the plan path and the diff, plus Codex and agy read-only (`reviewers:`).
Findings are classified confirmed / refuted / unverified; confirmed ones are
fixed before the PR. Provider failures are reported verbatim.

### 7. Live check, in a `nixarchy-desktop` microVM (not razer)

Everything in the guest, nothing on the host's real config. Needs the Home
Manager part installed and a flake with `home-manager.useGlobalPkgs = true`.
1. `nixarchy-pkg check` with a `home.nix` selection, and `nixarchy-apply`
   with the same: `diff` of the `nixarchy-apps.nix` each writes (check's copy
   from the capture directory, apply's from the flake): byte-identical.
   Without a `home.nix`: the plain stub, also identical.
2. Set `useGlobalPkgs = false` in the guest flake; `nixarchy-pkg options
   refresh`; `state` shows the reason; `pkg add --scope user` refuses with it;
   `check` with a `home.nix` returns `fails` naming the assertion.
3. In the guest only, `mv /etc/nixarchy/home-apps-template.nix` aside: `check`
   answers `unknown` and `state` shows the template reason; move it back.
4. Repeat once with a user name ending in `$` if the guest can create one;
   otherwise note it was covered by the adapter test only.
Record the results in the PR. Do not run any of this on the host.

### 8. PR

Title `fix(check): fill nixarchy's home template, require useGlobalPkgs (#100)`.
Body links `intent/`, `spec/`, `plan/`, lists the steps Codex did (1-4) and
the coordinator did (0, 5-8), the main-failing list, the mutation results and
the live-check results, and says the nixarchy drift-check PR (below) follows.
Do not merge without the owner.

## Tests (summary)

- `bash tests/adapter.sh </dev/null` ends `all passed` (new cases: byte
  equality, missing template, no-home plain stub, `useGlobalPkgs` false, old
  cache note, `$` user, refresh record, and four nix-gated evaluation cases
  plus `pkgsOther`).
- `shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh` clean.
- `nix flake check` green.
- Against main's `bin/nixarchy-pkg` the "must fail" list fails (step 5.2).
- The three mutations fail the named tests (step 5.3).

## Rollback

Nothing is applied by this change: `check` is read-only and the writers are
untouched. Revert the PR (`git revert` of the two commits). A user who already
refreshed gets a `meta.json` with a `useGlobalPkgs` field that the reverted
code ignores; `options refresh` rewrites it. `NIXARCHY_HOME_TEMPLATE` is read
by no other code. The fixture rename is undone by the revert.

## Follow-up PR in nixarchy: the drift check (part of done for #100)

Separate PR in `/mnt/code/Source-home/GitHub/nixarchy` (a new worktree and
branch there; **not** in this repo, and never `main` or `~/.config/nixos`).
Ships **after** this PR merges and the `nixarchy-pkg` pin in nixarchy
`flake.nix` (`inputs.nixarchy-pkg.url = "github:olafkfreund/nixarchy-pkg/<sha>"`)
is bumped to a commit that contains `tests/fixtures/home-apps-template.nix`
(the pin moves the way `docs/internals/flake.md#the-package-manager-panel-on-by-default-766`
says). It needs its own artifact set or an explicit owner waiver, and the
owner's go-ahead before any build on p510.

F1. **Pin.** Bump `nixarchy-pkg` to the merge commit of this PR (coordinator;
`nix flake lock --update-input nixarchy-pkg` in a scratch copy first, read the
diff of `flake.lock`: only that input moves).

F2. **The case.** `tests/home-selection.nix` already has
`homeAppsTemplate = pkgs.writeText "home-apps-template.nix"
(configWith { }).environment.etc."nixarchy/home-apps-template.nix".text;`. Add,
next to the check at `sed ... ${homeAppsTemplate} >home.expected` (the
`bad()`/`fails` idiom):
```nix
pluginFixture = "${inputs.nixarchy-pkg}/tests/fixtures/home-apps-template.nix";
```
and in the shell body
```bash
${if builtins.pathExists pluginFixture then ''
  cmp -s ${homeAppsTemplate} ${pluginFixture} \
    || bad "home template drift" "nixarchy's home template differs from the nixarchy-pkg fixture ($(diff ${homeAppsTemplate} ${pluginFixture} | head -20))"
'' else ''
  echo "skip: the pinned nixarchy-pkg predates tests/fixtures/home-apps-template.nix"
''}
```
`bad` is the file's existing failure recorder; `diff` is not in the current
`nativeBuildInputs` (bash coreutils gnugrep gnused nix util-linux): add `diffutils`. `pathExists` on a
flake-input path is evaluated at eval time; it is `false` for a pin that
predates the fixture, so the current pin cannot break.
Check: the file's own build (`nix build .#checks.x86_64-linux.home-selection`
or the repo's name for it), `nix flake check`; on p510 only with the owner's OK.

F3. **Mutation proof** (the spec's Decision 2): in a `mktemp` copy `( cd "$d" ||
exit 1; ... )`, change one character of the template in `modules/apps.nix`: the
case fails with the diff; change one character of the fixture in the pinned
input path (a local override `--override-input nixarchy-pkg path:<scratch
copy>`): fails; restore: passes; pin predating the fixture: the skip line
prints and nothing fails.

F4. **PR** `test(home): the home template matches the nixarchy-pkg fixture
(#100)`, linking this plan; says the bump and the case are one change. Owner
merges.

Traps for F: the pin bump and the test must land together (a test against a
pin without the fixture skips, so it is not red but is also not a check; say so
in the PR); never edit `modules/apps.nix`'s template in the same PR (that
would be the drift the test is meant to catch, reviewed separately); nixarchy's
own CLAUDE.md workflow (intent/spec/plan) applies to that repo.
