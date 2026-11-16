---
status: draft
issue: 100
intent: intent/2026-11-16-100-home-import-parity.md
---

# Spec: check fills nixarchy's home template, and user scope needs useGlobalPkgs

## Design

Line numbers are this repo at 44eb7d4 (`bin/nixarchy-pkg`, `tests/adapter.sh`)
and nixarchy `origin/main` d5f58434 (`modules/apps.nix`). The intent's five
open questions were approved with the recommended answer; they are settled
and are not reopened here.

### 1. `check` fills the template apply fills (intent Q1, Q3, Q4)

The text apply writes is `homeAppsTemplateText` (`modules/apps.nix:407-430`),
filled by

```
sed -e "s|@USER@|$user|g" -e "s|@IMPORTS@|$imports|g" ${homeAppsTemplate}
```

(`:4829`) and exported as `/etc/nixarchy/home-apps-template.nix` (`:1676`).
`check` now runs the same two `sed` expressions over the same file.

`cmd_check` (`bin/nixarchy-pkg:2385`), where it writes `nixarchy-apps.nix`
(`:2488-2499`):

- With `$CHECKDIR/snap/home.nix`: `sed -e "s|@USER@|$home_user|g" -e
  "s|@IMPORTS@|$imports|g" "$tpl" >"$cb/nixarchy-apps.nix"`. `$imports` is
  already what apply passes: the loop at `:2481` skips `home`, as apply's
  list does, because the template imports `./nixarchy/home.nix` itself.
- Without it: the plain stub that apply's else-branch writes
  (`modules/apps.nix:4831-4837`). Its header names four files, so the `parts`
  variable (`:2489-2490`) goes: the two `printf` calls collapse to one fixed
  stub, and the home line (`:2493-2498`) is gone.
- `$tpl` is `${NIXARCHY_HOME_TEMPLATE:-/etc/nixarchy/home-apps-template.nix}`.
  The variable is new and exists so the adapter test can point at a fixture
  (as `NIXARCHY_FLAKE` already lets it point at a flake). A user never sets it.
- Missing template (Q3): right after the fingerprint and pins are computed
  (`:2414-2415`), when `$CHECKDIR/snap/home.nix` exists and `$tpl` is not a
  readable file, `reason='nixarchy'"'"'s home template is not installed
  (/etc/nixarchy/home-apps-template.nix); update nixarchy'; check_answer`.
  That is `verdict: "unknown"` with the reason, before any copy. It does not
  go into `apply_has_home`: that would make `snapshot_selection` (`:1880`)
  drop `home.nix`, and `check` would answer `evaluates` without the selection.
  No fallback to the old stub.
- The old test-visible effect: an assertion failing in the template now fails
  `config.system.build.toplevel.drvPath` (`:2521-2523`), and `check_failure`
  (`:2155`) returns `verdict: "fails"` with nix's message in `error`.

Measured, not assumed (scratch dirs from `mktemp`, nothing under either
checkout): the template extracted from `origin/main` and filled with `sed` for
user `alice` parses with `nix-instantiate --parse`. Evaluated with a stub
module set (the file as `nixarchy-apps.nix`, one `home-manager.users.alice`
definition from elsewhere), the three assertions behave as the template says:
all true gives `[]`; `useGlobalPkgs = false` gives only
`nixarchy: home.nix needs home-manager.useGlobalPkgs = true`; `isNormalUser =
false` gives `nixarchy: alice is not a normal user on this machine`; no
other definition gives `nixarchy: alice has no Home Manager configuration of
their own; ...`. The same stub is the basis for the adapter test below.

### 2. One user-name regex (Q4)

`bin/nixarchy-pkg` gets `readonly USER_RE='^[a-z_][a-z0-9_-]*[$]?$'`, apply's
pattern (`modules/apps.nix:4750-4752`), near `HOME_NIX` (`:75`). It replaces
the two copies: `cmd_check` (`:2496`) and `cmd_options_refresh` (`:2303`).
Using it at `:2303` as well matters: refresh substitutes the name into
`DISCOVER`, so the two must agree, and a `$` ahead of `"` or at the end of a
Nix string is not an interpolation (only `${` is).

### 3. `useGlobalPkgs` in discovery and `user_scope` (Q2, Q5)

- `DISCOVER` (`:86-107`) gains `useGlobalPkgs = hm != null &&
  (c.config.home-manager.useGlobalPkgs or false);` beside `inherit perUser`.
  It reads the flake apply is about to build (the `c` the refresh evaluates),
  not the running system, so it is right after a flake edit, which a baked
  `homeScope=` in an installed writer is not.
- The refresh's `meta.json` writer (`:2358-2362`) adds it to the `jq -c
  '{homeManager,users,perUser}'` projection and to the object it builds; the
  answer of `options refresh` (`:2375-2377`) adds it too, so a caller sees what
  was recorded. `OPT_JSON` (`:2293`) does not change: `state` reports user
  scope through `userScope`, not through the raw meta.
- `user_scope()` (`:365-386`), in this order:
  1. `apply_has_home` false: unchanged.
  2. The template is not a readable file: the Q3 sentence above. It sits here,
     before the options cache, because it does not depend on the flake; it is
     the same check `cmd_check` makes, written once as a helper
     `home_template()` that prints the path and `user_scope` and `cmd_check`
     both call.
  3. No cache, `homeManager` not true, user not in `users`: unchanged.
  4. `.useGlobalPkgs == false` (a recorded false only):
     `home-manager.useGlobalPkgs is off; user-scope packages need it`.
  A cache from before this change has no field: `jq -e '.useGlobalPkgs ==
  false'` is false for `null`, so user scope stays available, with the
  refresh note from section 4 (the intent's approved answer). A stale cache is
  possible (`options_resolve` only marks it stale, `:2290-2293`); `check` then
  still catches a real `false` through the template's own assertion.
- Only `user_scope()` raises it (Q5). `scope_args` (`:400`), `cmd_search`
  (`:609`) and `cmd_state` (`:2663`) already call it, so the panel shows the
  reason and `scope_args` `die`s before any write. `cmd_check` has no extra
  check of its own.

### 4. Tests, and how upstream drift is caught (Q1)

- **Fixture.** `tests/fixtures/home-apps-template.nix` is a copy of the file
  `/etc/nixarchy/home-apps-template.nix` holds (the exact text of
  `homeAppsTemplateText`, still carrying `@USER@` and `@IMPORTS@`, so one copy
  serves every user). The adapter tests set `NIXARCHY_HOME_TEMPLATE` to it in
  `scope62` and `check62` (`tests/adapter.sh:2693-2694`, `:2787-2788`) and in the
  `opt62` call the user-scope tests use (`:2523`). Without that, every
  user-scope test would now hit the "template not installed" refusal.
- **`tests/fixtures/nixarchy-apps-home.nix` is deleted.** The expected file is
  the fixture filled by the same `sed` in the test (`:2748`), so no second
  hand-written shape remains.
- **Drift: two checks, no extra copy of apply's logic.**
  1. In this repo, `tests/adapter.sh` compares the fixture with
     `/etc/nixarchy/home-apps-template.nix` when that file exists, and skips
     with a printed note when it does not (as the `$TEMPLATES` sections do,
     `:102-103`). On a nixarchy machine with the Home Manager part, and on any
     CI that has it, an out-of-date fixture fails here.
  2. In nixarchy, `tests/home-selection.nix` (`origin/main:30-41`) already
     builds the template text from `config.environment.etc` as
     `homeAppsTemplate`. A new case compares it with the fixture of the pinned
     plugin: `inputs.nixarchy-pkg` (`flake.nix:208-211`) is a flake input, so
     `"${inputs.nixarchy-pkg}/tests/fixtures/home-apps-template.nix"` is
     readable in the build. It fails with the diff when a nixarchy change to
     the template reaches the pin, or a pin bump brings an older fixture. It
     is skipped (`builtins.pathExists`) while the pin predates the fixture, so
     it cannot break the current pin. This is a change to nixarchy and is
     a separate PR there, which needs the owner's go-ahead (see below); this
     repo's own check (1) works without it.
- **Template filled the way apply fills it.** One test fills the fixture for
  the test user with a stub-selection `imports` and compares with the file
  `check` produced (`generated.nix`, captured by the existing `NIX_MODE=capture`
  stub, `:2502-2506`) byte for byte.
- **Real evaluation of the assertions.** The existing nix-gated block
  (`:2757-2796`) is adapted, not duplicated: its flake evaluates only
  `builtins.head` of the user's imports (`:2780`), which with the template is
  the inline `pkgsOther` module, not `home.nix`, and it lacks the options the
  template reads. It gets the stub options measured below, and evaluates the
  whole imports list, so the merge and conflict cases (`:2792-2796`) keep
  running. The same flake evaluates the filled file with the stub modules
  measured above and a `toplevel.drvPath` that throws the first failed
  assertion message. Three cases: `useGlobalPkgs = false`, user not
  `isNormalUser`, no other definition; each must give `verdict: "fails"` and
  an `error` containing that assertion's message. The case with everything
  true gives `evaluates`. The nix-gated block skips when there is no usable
  nix, as it does now.
- **Existing assertions that must change.** `tests/adapter.sh:2705` greps
  `home-manager.users.*home.nix` on one line; the template puts the user and
  `./nixarchy/home.nix` on separate lines, so it is replaced by the byte
  comparison (and a `grep -qF ./nixarchy/home.nix`). The no-home case (`:2701`)
  is unchanged.
- **`pkgsOther` is supplied.** One passing case: `home.nix` consumes
  `pkgsOther` (a stub `{ pkgsOther, ... }:` that reads it) with the other
  channel on and off; the flake supplies `_module.args.pkgsOther` as nixarchy
  does. It must fail on main, where the stub import never sets the argument.
- **Old cache note.** A cache with no `useGlobalPkgs` field leaves
  `userScope.available` true and adds `userScope.note` (`options were read
  before useGlobalPkgs was recorded; run options refresh`), set in `cmd_state`
  beside `user_reason` in `cmd_state` (`:2728`) and `cmd_search` (`:654`). It is a note, not a reason: `user_scope()` still
  prints nothing. Tested with a cache lacking the field.
- **`useGlobalPkgs` refusals.** `nix` stub's refresh output (`:2515-2518`) gets
  `"useGlobalPkgs":true`; `nohm` (`:2512`) gets `false`.

**Must fail on main** (each run with the test changed and `bin/nixarchy-pkg`
as on main, in a `mktemp` copy, failure recorded in the plan):
- The generated file equals the filled fixture (main writes the one-line stub).
- The `useGlobalPkgs = false`, non-normal-user and no-HM-config cases return
  `fails` (main returns `evaluates`: the stub has no assertions).
- A cache with `"useGlobalPkgs": false`: `state`'s `userScope.available` is
  false with the stated reason, and `pkg add --scope user` dies with it before
  a transaction opens (main: available, the write goes ahead).
- A user name ending in `$` is accepted by check and by refresh (main dies
  `invalid user name`).
- A missing template with a `home.nix` selection: `verdict: "unknown"` with
  the reason (main: `evaluates`, because the stub does not read it); and
  `userScope.reason` is that sentence.

**Pass on main and must keep passing:** a cache with no `useGlobalPkgs` field
leaves user scope available; no `home.nix`, or an apply without a home part,
leaves `check` writing the plain stub with no template read at all (the
template env var points at a missing path in that test, so reading it fails
loudly); the existing system-scope cases.

Mutation proofs, in `mktemp` copies only, `( cd "$d" || exit 1; ... )`: change
one character of the fixture (the drift test must fail); drop the `useGlobalPkgs`
test from `user_scope` (the refusal tests must fail); revert the filling in
`cmd_check` to the old printf (the byte-equality and assertion tests must
fail).

### 5. Docs

`docs/manual/packages.md:119` (user scope needs Home Manager, your account in
`home-manager.users`, a nixarchy with the Home Manager part) gains
`home-manager.useGlobalPkgs = true` and the installed home template. The
section of `docs/manual/options.md` that describes `check` (`:127`) lists the
same prerequisites and says that for user
scope it evaluates the same file apply will write.

### Decisions for the owner

1. **A new env var, `NIXARCHY_HOME_TEMPLATE`, read by `bin/nixarchy-pkg`**, so
   the adapter test can use the fixture. Recommended: yes; it follows
   `NIXARCHY_FLAKE`. The alternative, a test-only `PATH`/chroot trick, cannot
   stand in for `/etc`.
2. **The upstream drift check lives in nixarchy** (`tests/home-selection.nix`,
   a new case comparing `inputs.nixarchy-pkg`'s fixture), in addition to the
   check in this repo that needs `/etc/nixarchy`. Recommended: yes, and it is part of
   done for #100, not optional: the nixarchy PR follows this one's merge and
   the pin bump. This repo's own flake check (a sandbox, no `/etc/nixarchy`)
   skips the `/etc` comparison, so only the nixarchy case fails CI when the
   fixture or the template changes; the drift mutation proof is run there.
   Pins that predate the fixture skip it on purpose. Say no, or later, to
   keep this issue to this repo; the drift is then caught only on a machine
   with nixarchy installed.
3. **`nixarchy-apps-home.nix` is removed**, replaced by the fixture template
   plus `sed`. Recommended: yes (nothing left to drift). Keep both only if you
   want the old file as a golden for today's apply output.

## Alternatives rejected

- **Vendor the template here without a drift check** (Q1 b): wrong the day
  nixarchy changes it, and silently so.
- **Read the template from the nixarchy flake input** instead of `/etc`:
  the user's flake need not name that input, and the file on the host is the
  one the installed apply reads.
- **Fall back to the old stub when the template is missing** (Q3): brings
  back the false `evaluates`.
- **`homeScope=` grepped from an installed writer** (Q2 b): reports the
  running system, not the flake apply is about to build.
- **Check `useGlobalPkgs` in `cmd_check` too** (Q5): the template's
  assertion already says it, with nix's own message.
- **Treat a missing `useGlobalPkgs` field as off**: would disable user scope
  for every existing cache until a refresh, for a value the template still
  verifies at check time.

## Risks

- **Stale cache** says on while the flake now says off (or the reverse): user
  scope is offered or refused on old facts until `options refresh`. `check`
  and apply's assertion are the backstop for the first; a refresh fixes the
  second. `state` already shows the cache as stale (`:2290-2293`).
- **Template and `sed` drift in the other direction**: if apply's `sed` line
  changes (`modules/apps.nix:4829`), `check` is wrong until updated. The
  byte-equality test cannot see that (it uses this repo's `sed`); the Decision 2
  nixarchy check compares the template, not the fill. Accepted: the fill is two
  expressions, and the live check below runs real `nixarchy-apply` against
  real `check`.
- **A host with the home part and no template** now gets `unknown` and no
  user scope, where it previously got `evaluates` and a working user scope.
  That is a broken install; the sentence says what to do.
- **Intent claim to correct:** the intent says check's regex lacks the
  trailing `$`; it also lives in `cmd_options_refresh` (`:2303`), fixed here.
- **Not verified on a real host.** The above is read from both repos and the
  scratch measurement; the live check below has not run.

## Verification

1. `bash tests/adapter.sh` green, including the new cases; the "Must fail on
   main" list recorded as failing against main's `bin/nixarchy-pkg` in a
   `mktemp` copy; the mutation proofs above fail as stated.
2. `shellcheck bin/nixarchy-pkg tests/adapter.sh` clean (the CI check,
   `flake.nix:71-75`).
3. Fixture equals `modules/apps.nix`'s text: `git -C /mnt/code/Source-home/GitHub/nixarchy show
   origin/main:modules/apps.nix` extracted and compared in a scratch dir, and
   the adapter's drift test on a host that has the installed file.
4. **Live, in a `nixarchy-desktop` microVM** (the owner's standing choice; not
   razer): on a flake with Home Manager and `useGlobalPkgs = true`, run
   `nixarchy-pkg check` with and without a `home.nix` selection and compare
   `generated` file with the one `nixarchy-apply` writes (`diff` of the two
   `nixarchy-apps.nix`, byte for byte). Then set `useGlobalPkgs = false` in the
   flake, `options refresh`: `state` shows the reason and `pkg add --scope
   user` refuses; `check` with a `home.nix` returns `fails` naming the
   assertion. Then `mv` the installed template aside (in the VM only): `check`
   answers `unknown` and user scope shows the reason.
5. Owner's review of the Decisions above before the plan is written.
