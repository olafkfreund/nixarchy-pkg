---
status: approved
issue: 103
spec: spec/2026-11-17-103-follow-home-owner.md
coders:
  1: codex   # tests/fixtures/apply-1820.sh: a new file, verbatim block plus a 40-line stand-in; one Codex run does steps 1-4 in order (agent-run codex refuses a dirty tree and may not commit)
  2: codex   # tests/adapter.sh: anchored edits to existing tests plus one new section; small tricky bash
  3: codex   # bin/nixarchy-pkg: six small anchored edits, bash/jq, each with its trap
  4: codex   # three doc files, exact sentences given
  # Steps 0 and 5-8 stay with the coordinator: baseline, proofs, commits, reviews, the live check, the PR.
reviewers:
  - codex   # bash quoting, the jq validator and the fake's fidelity are where this goes wrong
  - agy     # independent read of the diff against this plan
---

# Plan: follow nixarchy's home owner: detect the home part again, and let check and user scope use apply's decision

Branch `fix/103-follow-home-owner`, worktree
`/mnt/code/Source-home/GitHub/nixarchy-pkg-wt/103-home-owner`. Line numbers
are this worktree at 224d3c4; **find every anchor by its quoted text**, the
numbers drift. This PR is the plugin side only. The nixarchy side is
`olafkfreund/nixarchy#1825`, which carries the contract (spec section 1,
copied below). Until it lands the plugin runs in `blind` mode (user scope off
with a reason, `check` `unknown` for a caller with `home.nix`); in `plan` mode
it is tested against the fake apply of step 1 only.

**Not covered by this PR, and the plan says so on purpose:** the `plan`-mode
live check needs a nixarchy that has #1825 and is deferred (step 7). The
`blind`, `legacy` and `none` live checks run now.

## Decisions (from the approved intent and spec; nothing here is open)

The six "Decisions for the owner" are approved as recommended. The intent's
seven open questions were approved earlier.

1. **The contract for `nixarchy-apply --home-plan --json` is the one in "The
   contract" below.** State word is `absent`, not `missing` (it is what
   `classify_home` already sets). Posted to #1825.
2. **The plugin finds `--home-plan` by reading the installed script** (a `grep`
   for its `case` label), like `searched()` and `apply_has_home` read it. No
   `--capabilities` flag.
3. **Until #1825 lands, `check` answers `unknown` only when the caller has a
   `home.nix`.** A caller with no `home.nix` on a host with an owner gets the
   plain stub from `check`, as every host does today. Accepted interim gap.
4. **`--pin home=<sha>` carries the real hash in every action.** The snapshot
   keeps the caller's `home.nix` for `keep` and `refuse` too, so `pins.home`
   is the real hash; apply exits 4 on any pin that differs from the file, an
   empty pin included (`modules/apps.nix:4716-4731`, nixarchy).
5. **`check` passes `NIXARCHY_FLAKE` (default `/etc/nixos`) to the plan call**,
   so the owner is read from the flake `check` evaluates.
6. **The test fake of the new apply carries nixarchy's own function text**
   (`tests/fixtures/apply-1820.sh`, from `74000e98`), plus a drift check
   against the installed apply when there is one. No nixarchy clone in CI.

### Design (spec sections 2-6, decided)

- **Three modes from one read of the installed script**, first match wins:
  `plan` (`^[[:space:]]*--home-plan\)`), `legacy` (`^for part in .*\bhome\b`,
  today's meaning: the invoking user is the writer, no plan call, #100's
  behaviour), `blind` (`^home_decide\(\)`: a #1820 apply without the plan
  command), else `none`. `apply_has_home` is "mode is not `none`". Measured on
  this host's installed apply
  (`/nix/store/4lw7q8jdhgq93fmsy8rp02rk0asxmhvm-nixarchy-apply`): `blind`.
- **`home_plan` prints one JSON line, always or not at all.** `plan`: runs
  `NIXARCHY_FLAKE=${NIXARCHY_FLAKE:-/etc/nixos} timeout 10 nixarchy-apply --home-plan --json </dev/null 9>&- 8>&-`
  and validates; `blind`: `{"unavailable":"this nixarchy cannot say who owns
  home.nix; update nixarchy"}` and no process; `legacy` and `none`: prints
  nothing, starts nothing. A consumer sees exactly one of three shapes: a
  decision (`.action`), an error (`.error`), or `.unavailable`.
- **The snapshot carries the decision** (`plan` and `blind`): `snapshot_selection`
  keeps copying the caller's `home.nix`, writes `DIR/home-plan.json`, and in
  `plan` with `action == keep` and a non-null `renderUser` copies the flake's
  `$(flake_base)/nixarchy/home.nix` to `DIR/flake-home.nix` (it is what `check`
  evaluates in that row). `fingerprint` hashes `*.nix` and `home-plan.json`.
  `legacy` and `none` write neither file: their fingerprint is byte-identical
  to today's.
- **`home_applies DIR`**: mode `legacy`, or `DIR/home-plan.json` has `.action`
  `claim` or `copy`. `pending` skips `home` (both the `new`/`modified` and the
  `dropped` paths) unless `home_applies`.
- **`check` follows the decision** (table below). **User scope names the
  owner** (user_scope below).
- **Tests**: the fake apply and its `blind` variant; the existing two fakes
  stay as `legacy`; the drift test; the "must fail on main" rows; seven
  mutation proofs.

### The contract (spec section 1, copied so this plan stands alone)

**Invocation.** `nixarchy-apply --home-plan --json`, nothing else on the line.
Any other flag combined with `--home-plan` exits 2 with usage text.
`--home-plan` without `--json` prints one human line and is not a contract.
Environment is apply's: `NIXARCHY_FLAKE`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`,
`HOME`; the caller is `id -un`.

**What it runs.** `base`/`dest`, `snapshot_home`, `classify_home`,
`read_owner`, `home_decide` and the `render_user` rule, in apply's order, and
nothing else. It is read-only: no lock, no directory, no write under `$base`,
`~/.config/nixarchy`, `$applied` or `$XDG_STATE_HOME`; it does not need
`apps.nix`; it needs the flake directory (else exit 1).

**Success: exit 0, one line on stdout, every decision, `refuse` included.**

```json
{"version":1,"owner":"alice","caller":"bob","state":"seed","action":"keep","renderUser":"alice","message":null}
```

| field | type | value |
|---|---|---|
| `version` | number | `1` |
| `owner` | string or `null` | `read_owner`'s owner; `null` when empty |
| `caller` | string | `id -un` |
| `state` | string | `seed`, `edited` or `absent` |
| `action` | string | `claim`, `copy`, `keep` or `refuse` |
| `renderUser` | string or `null` | `claim`/`copy`: the caller; `keep`: the owner (`null` when none); `refuse`: `null` |
| `message` | string or `null` | `refuse`: apply's refusal text exactly as printed (with its `nixarchy-apply: ` prefix, no newline); else `null` |

All seven keys are always present; extra keys are ignored.

**Error: exit 1, one line, no other key.**
`{"version":1,"error":"nixarchy-apply: <dest> names several home owners (or an unparseable one); fix it by hand"}`.
Anything else (other exit, other shape) is "no usable answer", never a
decision. Measured decisions (owner / caller / file: action, renderUser):
none/bob/edited claim,bob; none/bob/seed keep,null; none/bob/absent keep,null;
alice/alice/seed copy,alice; alice/alice/absent keep,alice; alice/bob/seed
keep,alice; alice/bob/edited refuse,null (message set); two owner lines: exit 1
error.

### `check` follows the decision (spec section 5)

| plan | verdict | where |
|---|---|---|
| `.error` | `fails`, `error` = the message | answered at once, before the flake is copied |
| `.action == refuse` | `fails`, `error` = `.message` | the same |
| `.unavailable` and the caller has `home.nix` | `unknown`, `reason` = that text | the same |
| `.unavailable`, no `home.nix` | continues: plain stub, as today | |
| `claim`, `copy` | continues; render user `.renderUser` (the caller) | caller's `home.nix` copied over the flake's |
| `keep`, owner | continues; render user `.renderUser` (the owner) | evaluated `nixarchy/home.nix` is **materialised from `snap/flake-home.nix`** |
| `keep`, no owner | continues; plain stub, no home import | the flake's `nixarchy/home.nix` stays in the copy, unimported |
| mode `legacy` | as #100: render user `id -un` when the snapshot has `home.nix` | |
| mode `none` | plain stub | |

The template is required when a user is rendered (`[ -n "$render_user" ]`),
which includes `keep` with an owner and a caller with no `home.nix`.

### User scope (spec section 6)

After the apply and template tests, before the options cache: in `plan` or
`blind`, from `home_plan`: `.unavailable` -> that text; `.error` -> that text;
`.owner` non-null and `!= .caller` -> `home.nix belongs to <owner>; ask
<owner> to apply, or run nixarchy-apply --release-home to give the host up`
(whatever `.state` is); else continue. `legacy`: skipped. `user_scope_note`
adds, in `plan` when `.owner` is null, `the first apply with an edited
home.nix makes you the owner`, joined to the cache note with `; `.

## Order and why (test-first)

Tests first (steps 1-2), code after (step 3), docs (step 4). All four
file-editing steps are one Codex run on a clean tree, in that order. The
coordinator then proves the new tests fail on main's `bin/nixarchy-pkg`, runs
the mutation proofs, and commits tests and code separately (step 5). The
approval of this `plan/` is its own commit first.

## Steps

### 0. Coordinator: baseline

`git status` clean on `fix/103-follow-home-owner`. Record
`bash tests/adapter.sh </dev/null | tail -3` (ends `all passed`), and
`shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh` (clean).
QML tests, from a flake-style `mktemp` copy (as `flake.nix` `qml-tests`
does): `d=$(mktemp -d); cp *.qml tests/qml/tst_*.qml "$d"; cp -r tests/qml/imports "$d"/;`
then in `( cd "$d" || exit 1; ... )` for each `tst_*.qml`: `QT_QPA_PLATFORM=offscreen HOME=$PWD qmltestrunner -input tst_X.qml -import "$PWD/imports" -import <qtdeclarative>/lib/qt-6/qml`
(`Menu.qml` needs the three-line `WlrLayershell` strip from `flake.nix`, so
`nix flake check` is the authority for `tst_menu`; run the other four by
hand). Record the same later (step 5). Gate: this plan is `status: approved` in its own commit before anything else
here. Hand Codex a clean tree, the worktree
path, this plan's path and "steps 1-4, in order; do not stage or commit".

### 1. Fixture (`tests/fixtures/apply-1820.sh`) -- codex

Create the file (new, `chmod +x`). Layout: the header below, then **the verbatim
block**, then the stand-in tail.

*Header* (exactly):

```bash
#!/usr/bin/env bash
# Test fake of nixarchy-apply at nixarchy 74000e98 (modules/apps.nix). The block
# from select_home_src() to the end of home_decide() is copied verbatim, and
# tests/adapter.sh diffs it against the installed apply when there is one. The
# part loop, the --release-home label and the --home-plan arm are stand-ins
# (the arm is the contract in spec/2026-11-17-103-follow-home-owner.md, section 1).
set -o errexit
set -o nounset
set -o pipefail
for part in apps services advanced flatsnap; do :; done
```

*Verbatim block*: do not retype it; append the output of
`awk '/^select_home_src\(\) \{/{f=1} f{print} f&&/^home_decide\(\) \{/{h=1} h&&/^}/{exit}' /nix/store/4lw7q8jdhgq93fmsy8rp02rk0asxmhvm-nixarchy-apply/bin/nixarchy-apply`
(68 lines; the spec's "69" counted a blank line). If that path is gone, take
`git -C /mnt/code/Source-home/GitHub/nixarchy show origin/main:modules/apps.nix`
`:4753-4820` with the same awk after `sed 's/^ \{18\}//; s/'"''"'\${/${/g'`
(measured: both give the same 68 lines). The block defines `select_home_src`,
`snapshot_home`, `classify_home`, `valid_user`, `read_owner`, `home_decide`;
it reads `$pinned`, `$srcdir`, `$dest`, `$home_snap`, `$home_state`, `$owner`.

*Stand-in tail* (exactly; this ran in a `mktemp` directory against the ten
cases below and gave the table above):

```bash

# NIXARCHY_FAKE_PLAN bends the answer for the malformed-answer tests; unset it is exact.
err_json() { jq -nc --arg e "$1" '{version:1,error:$e}'; }
home_plan_arm() {
  local flake=${NIXARCHY_FLAKE:-/etc/nixos} base caller action render msg
  base=$flake
  [ -d "$flake/hosts/$(uname -n)" ] && base="$flake/hosts/$(uname -n)"
  dest="$base/nixarchy-apps.nix"
  srcdir="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy"
  pinned=$(mktemp -d)
  trap 'rm -rf "$pinned"' EXIT
  [ -d "$flake" ] || { err_json "nixarchy-apply: no flake at $flake"; return 1; }
  msg=""
  caller=$(id -un)
  valid_user "$caller" || { err_json "nixarchy-apply: invalid user name: $caller"; return 1; }
  snapshot_home || { err_json "nixarchy-apply: cannot read $srcdir/home.nix"; return 1; }
  [ -r "${NIXARCHY_HOME_TEMPLATE:?}" ] || { err_json "nixarchy-apply: cannot read the home seed"; return 1; }
  classify_home "$NIXARCHY_HOME_TEMPLATE"
  read_owner 2>"$pinned/err" || { err_json "$(sed -n '1p' "$pinned/err")"; return 1; }
  action=$(home_decide "$owner" "$caller" "$home_state")
  case "$action" in
    claim | copy) render=$caller ;;
    keep) render=$owner ;;
    *) render="" ;;
  esac
  if [ "$action" = refuse ]; then
    msg="nixarchy-apply: home.nix belongs to $owner; $caller has edited theirs. Ask $owner to apply, or run nixarchy-apply --release-home to give the host up."
  fi
  jq -nc --arg o "$owner" --arg c "$caller" --arg s "$home_state" --arg a "$action" --arg r "$render" --arg m "$msg" \
    '{version:1, owner:(if $o=="" then null else $o end), caller:$c, state:$s, action:$a,
      renderUser:(if $r=="" then null else $r end), message:(if $a=="refuse" then $m else null end)}'
}
case "${1-}" in
  --release-home) exit 0 ;;
#HOMEPLAN-BEGIN
  --home-plan)
    [ "$#" = 2 ] && [ "$2" = --json ] || { echo "usage: nixarchy-apply --home-plan [--json]" >&2; exit 2; }
    rc=0; out=$(home_plan_arm) || rc=$?
    case "${NIXARCHY_FAKE_PLAN-}" in
      exit2) exit 2 ;;
      text) echo "not json"; exit 0 ;;
      v2) out=$(jq -c '.version = 2' <<<"$out") ;;
      noowner) out=$(jq -c 'del(.owner)' <<<"$out") ;;
      owner42) out=$(jq -c '.owner = 42' <<<"$out") ;;
      nullmsg) out=$(jq -c '.message = null | .action = "refuse"' <<<"$out") ;;
      twolines) out=$(printf '%s\n%s' "$out" "$out") ;;
      badstate) out=$(jq -c '.state = "weird"' <<<"$out") ;;
      badrender) out=$(jq -c '.renderUser = "mallory"' <<<"$out") ;;
      errkeys) printf '%s\n' '{"version":1,"error":"x","action":"keep"}'; exit 1 ;;
      extra) out=$(jq -c '. + {error:"bad", unavailable:"x", future:1}' <<<"$out") ;;
    esac
    printf '%s\n' "$out"; exit "$rc" ;;
#HOMEPLAN-END
esac
exit 0
```

The `blind` variant is made at test time:
`sed '/^#HOMEPLAN-BEGIN$/,/^#HOMEPLAN-END$/d' tests/fixtures/apply-1820.sh`
(measured: it keeps `^home_decide\(\)` and drops `--home-plan)`; the full
file has `--home-plan)` once and no `for part in .*home`). The tail also
carries the contract's error cases, which the verbatim 74000e98 code does not
produce (spec section 1: #1825 adds them to the shared code): a missing flake
directory, an invalid caller, an unreadable `home.nix` or seed, and
`read_owner`'s failure each give `{"version":1,"error":...}` and exit 1.
Measured in a `mktemp` directory: the ten decision cases, those error cases,
and the `NIXARCHY_FAKE_PLAN` knobs `twolines badstate badrender errkeys extra v2`
(`extra` is a valid decision with extra keys `error`, `unavailable`, `future`).

Check: `bash -n tests/fixtures/apply-1820.sh`;
`shellcheck tests/fixtures/apply-1820.sh` (fixtures are not in the CI list,
`flake.nix` `shellcheck`: run by hand; two SC2034 warnings (`part`, and `home_srcmsg` inside the verbatim block) are expected and
are not fixed because the block is verbatim; say so in the PR).
Traps: the verbatim block must not be re-indented or reformatted (the drift
test is a byte comparison); `NIXARCHY_FAKE_PLAN` is test-only.

### 2. Tests (`tests/adapter.sh`) -- codex

Anchors are in the `#62` sections. Existing tests keep their expectations
unless stated. **Callers and fixtures this change breaks** (a host with the
real installed `nixarchy-apply` is `blind` after the change, and this host is
one): a, b, c below.

a. **Hermetic "no apply" cases.** Three existing tests assert
   `no Home Manager part` and so need a `none` apply first on their PATH
   (`$O62/bin` is first in `opt62`/`scope62`'s PATH). Define once, before the
   first of them (`check "user describe refuses while nixarchy C is absent"`):
   ```bash
   printf '#!/bin/sh\nexit 0\n' >"$O62/bin/nixarchy-apply"; chmod +x "$O62/bin/nixarchy-apply"
   ```
   (a stub with none of the three markers: mode `none`). That serves
   `user describe refuses while nixarchy C is absent` and `search hides user
   options while C is absent`. The later `cat >"$O62/bin/nixarchy-apply"`
   (after `# The installed apply supports home here`) overwrites it, as now.
   The third, `missing C refuses before a transaction` (anchor
   `mv "$O62/bin/nixarchy-apply" "$O62/bin/nixarchy-apply.saved"`), replaces
   that `mv` with `cp "$O62/bin/nixarchy-apply" "$O62/bin/nixarchy-apply.saved"`
   then the same `none` stub write, and its restore `mv` stays. Without this
   the tests pass in CI (no apply installed) and fail on a nixarchy host.
b. **`nix` stub** (`"$O62/bin/nix"` heredoc, quoted `NEOF`, so every `$` is
   the stub's own). In the `capture)` arm, after the `cp ... generated.nix`:
   make `generated.nix` work for the `hosts/<host>` layout and capture the
   evaluated `home.nix`:
   ```bash
   path:*) grab; break ;;
   ```
   (Replace the one-line `path:*) cp ... break ;;`) and define `grab` at the top
   of the stub, after the `echo "run $*"` line. It picks the same base as
   `flake_base`, never "whichever copy succeeds" (row 13 has both files):
   ```bash
   grab() { local p=${arg#path:} b
     b=$p/hosts/$(uname -n); [ -d "$b" ] || b=$p
     cp "$b/nixarchy-apps.nix" "$O62/generated.nix"
     [ ! -f "$b/nixarchy/home.nix" ] || cp "$b/nixarchy/home.nix" "$O62/generated-home.nix"; }
   ```
   Add one new arm before `fail)`, for a `check` that reaches its end (modes
   `pass`, `change-owner`, `change-home`; it also grabs the generated files at
   the `metadata` call, so a completed run can be inspected):
   ```bash
   pass|change-owner|change-home)
     case "$*" in
       *"config show"*) exit 0 ;;
       *metadata*) for arg in "$@"; do case "$arg" in path:*) grab; break ;; esac; done; echo '{"path":"/nonexistent"}' ;;
       *--apply*) echo true ;;
       *--raw*)
         [ ! -f "$O62/a103/home.orig" ] || cp "$O62/a103/home.orig" "$O62/a103/fl/nixarchy/home.nix"
         [ "$NIX_MODE" = change-owner ] && printf 'home-manager.users."mallory".imports = [\n];\n' >"$O62/a103/fl/nixarchy-apps.nix"
         [ "$NIX_MODE" = change-home ] && echo '# changed during eval' >"$O62/a103/fl/nixarchy/home.nix"
         echo /nix/store/x.drv ;;
     esac
     exit 0 ;;
   ```
   (`set -e` is not on in the stub; the `[ ... ] && ...` lines are inert when
   false. `home.orig`, when a test writes it, is restored just before the
   verdict, for row 12's completed-run race.)
c. **Drift test**, at the top of the new section (step 2d), before
   `PATH` is touched (the global `PATH` is the real one, so `command -v` finds
   the installed apply, not a fake):
   ```bash
   blk103() { awk '/^select_home_src\(\) \{/{f=1} f{print} f&&/^home_decide\(\) \{/{h=1} h&&/^}/{exit}' "$1"; }
   if apply103=$(command -v nixarchy-apply) && grep -q '^home_decide()' "$apply103"; then
     check "fixture's home_decide block equals the installed apply's" cmp -s <(blk103 "$HERE/tests/fixtures/apply-1820.sh") <(blk103 "$apply103")
   else
     echo "  skip  fixture drift (no installed nixarchy-apply with home_decide here)"
   fi
   ```
d. **The new section**, `echo "home owner (#103)"`, inserted immediately
   before the single line `rm -rf "$O62"` (it follows `check "user absent from
   home-manager.users has its own refusal"`; this is after every test that
   depends on `$O62/cache`'s published options, and uses its own cache).
   Setup (shellcheck: the `printf` format with `$1` needs
   `# shellcheck disable=SC2016 # the stub's own script`, as the file does):
   ```bash
   A103=$O62/a103; export A103
   mkdir -p "$A103"/{plan,blind,legacy,none,idbin,cache/nixarchy,fl/nixarchy,cfg/nixarchy}
   touch "$A103/fl/flake.nix"; echo lock-one >"$A103/fl/flake.lock"
   cp "$OC/index.tsv" "$A103/cache/nixarchy/"
   cp "$HERE/tests/fixtures/apply-1820.sh" "$A103/plan/nixarchy-apply"
   sed '/^#HOMEPLAN-BEGIN$/,/^#HOMEPLAN-END$/d' "$HERE/tests/fixtures/apply-1820.sh" >"$A103/blind/nixarchy-apply"
   cp "$O62/apply-with-home" "$A103/legacy/nixarchy-apply"
   sed 's/ flatsnap home;/ flatsnap;/' "$O62/apply-with-home" >"$A103/none/nixarchy-apply"
   chmod +x "$A103"/{plan,blind,legacy,none}/nixarchy-apply
   printf '#!/bin/sh\n[ "$1" = -un ] && { echo "$CALLER103"; exit 0; }\nexec %s "$@"\n' "$(command -v id)" >"$A103/idbin/id"; chmod +x "$A103/idbin/id"
   own103() { local mode=$1; shift
     env PATH="$A103/$mode:$A103/idbin:$O62/bin:$FIXSTUB:$PATH" CALLER103="${CALLER103:-bob}" \
       XDG_CONFIG_HOME="$A103/cfg" XDG_STATE_HOME="$O62/state" XDG_CACHE_HOME="$A103/cache" \
       NIXARCHY_FLAKE="${FLAKE103:-$A103/fl}" NIXARCHY_HOME_TEMPLATE="${TPL103:-$HERE/tests/fixtures/home-apps-template.nix}" "$ADAPTER" "$@"; }
   scene103() { # OWNER (name or "") FILE (seed|edited|absent)
     rm -f "$A103/fl/nixarchy-apps.nix" "$A103/cfg/nixarchy/home.nix"
     [ -z "$1" ] || printf '{ ... }: {\n  home-manager.users."%s".imports = [\n    ./nixarchy/home.nix\n  ];\n}\n' "$1" >"$A103/fl/nixarchy-apps.nix"
     case $2 in
       seed) cp "$HERE/tests/fixtures/home-apps-template.nix" "$A103/cfg/nixarchy/home.nix" ;;
       edited) printf '# edited by the caller\n{ pkgs, ... }: { home.packages = with pkgs; [ ]; }\n' >"$A103/cfg/nixarchy/home.nix" ;;
     esac
     printf '{ ... }: { }\n' >"$A103/cfg/nixarchy/apps.nix"
     printf '# the flake home.nix\n{ ... }: { }\n' >"$A103/fl/nixarchy/home.nix"; }
   ```
   The `id` shim makes the caller `bob` (or `$CALLER103`); the nix stub's
   canned options JSON prints `command id -un`, which also finds the shim, so
   `users` contains the caller. Refresh once per caller before the rows that
   need user scope available: `own103 plan options refresh >/dev/null`
   (and `CALLER103=alice own103 plan options refresh` before an alice row).
   Then the rows. Each is a `check "<description>" ...`. `before=$(wc -l
   <"$O62/nix.calls")` and `not grep -qvE ' config show ' <(sed -n "$((before + 1)),\$p" "$O62/nix.calls")`
   is the "no flake work" idiom (as `missing home template skips flake
   evaluation` does). `NIX_MODE=capture own103 plan check` writes
   `$O62/generated.nix` and `$O62/generated-home.nix` (`rm -f` both first).

   **Must fail on main** (numbers are the spec's; main = `bin/nixarchy-pkg` as
   on main with these tests):
   1. `blind`, `scene103 "" edited`: `own103 blind state` -> `.userScope.available == false`
      and `.userScope.reason` contains `cannot say who owns`.
   2. `plan`, `scene103 bob seed`, caller bob: `.userScope.available == true`,
      `.userScope.note == ""`.
   3. `plan`, `scene103 alice seed` and `scene103 alice edited`, caller bob:
      `.userScope.available == false`, reason contains `belongs to alice` and
      `--release-home`; `own103 plan pkg add --scope user git` -> `.ok == false`,
      `.error` contains `belongs to alice`, and `test ! -e "$O62/state/nixarchy/pkg-recovery/open"`.
   4. `plan`, `scene103 "" seed` and `"" edited`: available, `.userScope.note`
      contains `makes you the owner`.
   5. `plan`, `scene103 alice seed`, caller bob, `NIX_MODE=capture check`:
      `generated.nix` contains `home-manager.users."alice"`; `cmp -s
      generated-home.nix "$A103/fl/nixarchy/home.nix"`; `not cmp -s
      generated-home.nix "$A103/cfg/nixarchy/home.nix"`. Variants: (i)
      `scene103 alice absent` (bob has no `home.nix`): the same imports line;
      then `TPL103=$O62/none.nix` -> `.verdict == "unknown"` and `.reason`
      contains `home template is not installed` (the template guard is
      `[ -n "$render_user" ]`); (ii) rerun `pending` and `check` (capture),
      record both `.fingerprint`; rewrite only `$A103/fl/nixarchy/home.nix`;
      both fingerprints change, and `pending`'s equals `check`'s each time.
   6. `plan`, `scene103 alice edited`, caller bob, capture: `.verdict == "fails"`,
      `.error` contains `belongs to alice`; the no-flake-work idiom.
   7. `plan`, owner file with two `home-manager.users."x".imports =` lines:
      `check` `fails` with `.error` containing `several home owners`;
      `state`'s `.userScope.reason` contains the same.
   8. `blind`, `scene103 "" edited`: `check` `.verdict == "unknown"`, `.reason`
      contains `cannot say who owns`; the no-flake-work idiom.
   9. `plan`, `scene103 alice seed` and `scene103 alice edited` (keep, refuse),
      caller bob: `pending` `.pins.home` equals `$(sha256sum <"$A103/cfg/nixarchy/home.nix" | cut -d' ' -f1)`
      (64 digits; the `-` suffix of `sha256sum` is cut); main with the new fake gives `""`.
   10. `plan`, `scene103 alice seed`: `pending` and `check` fingerprints; then
       rewrite the owner line in `$A103/fl/nixarchy-apps.nix` to `carol` and
       repeat: both change, and the two are equal to each other each time.
   11. For each of `exit2 text v2 noowner owner42 nullmsg twolines badstate badrender errkeys`,
       `scene103 alice edited`, `NIXARCHY_FAKE_PLAN=$x`: `check` `.verdict == "unknown"` and
       `.reason` contains `no usable answer`; `state` `.userScope.reason`
       contains `no usable answer`. (For `blind`, row 1 and 8 assert its own
       sentence.) With `NIXARCHY_FAKE_PLAN=extra` (a valid decision with the extra
       keys `error`, `unavailable`, `future`), `scene103 "" edited`, caller bob:
       the decision is used: `check` capture's `generated.nix` is the filled
       fixture (byte-equal as in the `claim` row), `state`'s `.userScope.reason` is
       `""` after a refresh. (Fails on main: the home part is not detected.)
   12. `NIX_MODE=change-owner`, `scene103 alice seed`, `own103 plan check`:
       `.verdict == "superseded"`. And `NIX_MODE=change-home` likewise
       superseded. Race variant for the evaluated file, on a **completed** run:
       a `git` shim first on PATH, `$A103/gitshim/git`, used with a flake that has `.git`
       (`mkdir "$A103/fl/.git"`, removed afterwards): for `grep` exit 1 with
       no output; for `ls-files -s` exit 0 with no output; for `ls-files -z`
       first `echo '# racing' >"$A103/fl/nixarchy/home.nix"`, then print
       `flake.nix\0` and exit 0. Save the pre-race bytes to `$A103/home.orig` first, run
       `NIX_MODE=pass own103 plan check` (the stub's `--raw` arm restores
       `home.nix` from `home.orig` before the verdict, so the second snapshot
       equals the first): `.verdict == "evaluates"` (not `superseded`), and
       `generated-home.nix` equals `home.orig`, not `# racing`. (`ls-files -z`
       runs after the snapshot and before `cp -a` of `nixarchy/`.) `rm` `home.orig`,
       the `.git` directory and the shim after.
   13. `hosts/<host>` layout: `mkdir -p "$A103/fl/hosts/$(uname -n)/nixarchy"`;
       put `nixarchy-apps.nix` (owner `alice`) and a `home.nix` there, and a
       root-level `nixarchy-apps.nix` naming `mallory`: `plan`, caller bob,
       `state` reason names alice, capture `generated.nix` imports `alice`,
       `generated-home.nix` equals the hosts file. Remove `hosts/` afterwards.
   14. `scene103 alice seed` then remove bob's `home.nix`: `check` (capture)
       imports alice, template required (covered by 5(i)); add a distinct
       `check "owner keep with no caller home.nix renders the owner's import"`.

   15. Contract errors (plan): `CALLER103='Bad;User'`, `scene103 "" edited`:
       `state` `.userScope.reason` contains `invalid user name`; `check`
       `.verdict == "fails"` with `.error` containing `invalid user name`.
       `FLAKE103=$O62/nonexistent`: `state` reason contains `no flake at`.
   16. Detection order, from `state` in `scene103 alice edited`, caller bob, each
       needs `plan` to win: (i) the plan fake with every `home_decide` renamed
       (`sed 's/home_decide/home_pick/g'`, in `$A103/prec/nixarchy-apply`, run with
       `own103 prec ...`): reason contains `belongs to alice` (`plan`, not
       `blind`, though `^home_decide\(\)` no longer exists); (ii) the plan fake
       plus a line `for part in apps services advanced flatsnap home; do :; done`
       (`$A103/prec2`): the same reason (not `legacy`).
   17. `plan`, `copy`: `CALLER103=alice`, `scene103 alice seed`, capture `check`:
       `generated.nix` byte-equal to the template filled for `alice` with
       ` ./nixarchy/apps.nix` imports; and `generated-home.nix` equals alice's
       `cfg/nixarchy/home.nix` (the caller's file overwrites the flake's).

   **Preservation (pass on main with the new fake, must keep passing):**
   - `plan`, `scene103 "" seed`, caller bob, capture: `generated.nix` has no
     `home-manager`; `fl/nixarchy/home.nix` bytes unchanged (compare a saved hash).
   - `plan`, no caller file, flake already imports it (`scene103 alice absent`; the
     owner file lists `./nixarchy/home.nix`, so `imported home` is true and the
     status would be `dropped`): `pending` `.files | all(.file != "home")` (the
     `dropped` path, Design 4).
   - `blind` with no caller `home.nix` (`scene103 "" absent`): capture `check`
     writes the plain stub (no `home-manager`), not `unknown` (Decision 3).
   - joined notes: `plan`, `scene103 "" seed`, after `jq 'del(.useGlobalPkgs)'` on
     the cache's `meta.json` (as the existing old-cache test does): `state`
     `.userScope.note` contains both `run options refresh` and `makes you the
     owner`, joined by `; `. (Row 4 covers the second alone.)
   - `plan`, `keep` and `refuse` (`scene103 alice seed`, `alice edited`):
     `pending` `.files | all(.file != "home")` and `.changes | all(.file != "home")`
     although the caller's `home.nix` differs from the flake's. This fails
     against a detection-only fix (mutation M1).
   - `claim` (`scene103 "" edited`, caller bob): `pending` has a `home` file;
     capture `generated.nix` is byte-equal to
     `sed -e "s|@USER@|bob|g" -e 's|@IMPORTS@| ./nixarchy/apps.nix|g' tests/fixtures/home-apps-template.nix`
     (passes only with the fix on the new-shape fake; fails on main).
   - `legacy` (`own103 legacy ...`, `scene103 "" edited`): capture check byte-equal
     to the filled fixture for `bob`; `none` (`own103 none`): plain stub.
     `rm -f "$O62/apply.args"` first; after `state`, `pending` and a capture
     `check` in `none` and `legacy`: `not grep -q -- --home-plan "$O62/apply.args"`
     (the legacy fake logs every argument it is run with).
   - Fingerprint unchanged for `legacy` and `none`: compute independently
     `exp=$( cd "$d" && find . -type f -name '*.nix' -print0 | sort -z | xargs -0r sha256sum | sha256sum | cut -d' ' -f1 )`
     over a `mktemp` directory `d` holding copies of the selection files
     (`apps.nix`, plus `home.nix` for `legacy`) and compare with `pending`'s
     `.fingerprint`.

Check: `bash tests/adapter.sh </dev/null` (**against main's `bin/nixarchy-pkg`
the "must fail" rows fail; against step 3 it ends `all passed`**),
`shellcheck tests/adapter.sh`.
Traps: (1) the static-source tests near `heads_a_pipeline` and
`renames_onto_a_config` grep `bin/nixarchy-pkg`: no `sed -i`, no `mv "..."`
onto a user file, nothing piped into `head`. (2) `shellcheck` runs on the
whole file in the flake check: a `$user` in a single-quoted `jq` program needs
`--arg`; SC2016 comments as the file does. (3) `bash tests/adapter.sh
</dev/null` (stdin matters). (4) Nothing against `/etc/nixos`, `~/.config` or
the real cache; the section uses `$O62`. (5) The nix stub heredoc is quoted:
write `$O62` and `$NIX_MODE` bare. (6) `capture` exits 1: `check` then answers
`fails` after `flake metadata`; only the generated files matter in those rows.
(7) Each `scene103` rewrites all four files; do not rely on state from the
previous row. (8) `NIXARCHY_FAKE_PLAN=... own103 ...` works because a prefix
assignment on a shell function is exported to its children.

### 3. Code (`bin/nixarchy-pkg`) -- codex

a. **Mode.** After the line `SETTLE_FAILED=false` add `HOME_MODE=""`. Replace the
   function `apply_has_home() { ... }` (anchor
   `grep -qE '^for part in .*\bhome\b' "$apply"`) with:
   ```bash
   # home_mode -- sets HOME_MODE from the text of the installed apply: plan
   # (has --home-plan), legacy (home in the part loop), blind (has home_decide
   # but no plan command), none. First match wins.
   home_mode() {
     local apply
     [ -z "$HOME_MODE" ] || return 0
     HOME_MODE=none
     apply=$(command -v nixarchy-apply 2>/dev/null) || return 0
     if grep -qE '^[[:space:]]*--home-plan\)' "$apply"; then HOME_MODE=plan
     elif grep -qE '^for part in .*\bhome\b' "$apply"; then HOME_MODE=legacy
     elif grep -qE '^home_decide\(\)' "$apply"; then HOME_MODE=blind
     fi
   }
   apply_has_home() { home_mode; [ "$HOME_MODE" != none ]; }
   ```
   Call `home_mode` directly, never as `$(home_mode)`: a subshell loses the
   variable (callers inside `$(user_scope)` just re-detect, three greps).
b. **`home_plan`.** After `home_template() { ... }` add `home_plan` per the
   Design (blind sentence; `plan` runs the command; else prints nothing).
   Validate with `jq` over the slurped output and print the **normalised** line:
   a decision as `.[0] | {version,owner,caller,state,action,renderUser,message}`
   (the seven keys only, so an accepted extra key such as `error` or
   `unavailable` can never be read as an error or an unavailable answer by the
   consumers), an error as `.[0] | {version,error}`:
   - decision, exit 0:
     ```
     length == 1 and (.[0] |
       .version == 1 and (.caller | type == "string")
       and (.state | IN("seed","edited","absent")) and (.action | IN("claim","copy","keep","refuse"))
       and has("owner") and has("renderUser") and has("message")
       and (.owner == null or (.owner | type == "string"))
       and (.renderUser == null or (.renderUser | type == "string"))
       and (.message == null or (.message | type == "string"))
       and (if .action == "claim" or .action == "copy" then .renderUser == .caller and .message == null
            elif .action == "keep" then .renderUser == .owner and .message == null
            else (.owner | type == "string") and .owner != .caller and .renderUser == null and (.message | type == "string") end))
     ```
   - error, exit 1: `length == 1 and (.[0] | .version == 1 and (.error | type == "string") and ((keys | sort) == ["error","version"]))`.
   - anything else (including `timeout`'s 124 and a bad shape):
     `{"unavailable":"nixarchy-apply --home-plan gave no usable answer (exit N); update nixarchy or nixarchy-pkg"}`
     built with `jq -nc --arg ...`; for a bad shape on exit 0, N is `0`.
   Use `--arg`/`--argjson`, never string-built JSON. The call is
   `NIXARCHY_FLAKE=${NIXARCHY_FLAKE:-/etc/nixos} timeout 10 nixarchy-apply --home-plan --json </dev/null 9>&- 8>&- 2>/dev/null`
   with `rc` captured as `out=$(...) || rc=$?` (the file's pattern).
c. **Snapshot, fingerprint, `home_applies`.** In `snapshot_selection` (anchor
   `# snapshot_selection DIR -- cp -L every existing part`), after the first
   `for` loop add: `home_mode`; in `plan` or `blind`:
   `home_plan >"$1/home-plan.json" || die "cannot write $1/home-plan.json"`; and in
   `plan` when `jq -e '.action == "keep" and .renderUser != null' "$1/home-plan.json"`
   and `[ -f "$(flake_base)/nixarchy/home.nix" ]`:
   `cp -L "$(flake_base)/nixarchy/home.nix" "$1/flake-home.nix" 9>&- 8>&- || die "could not copy the flake's home.nix"`.
   Keep the guard `[ "$p" != home ] || apply_has_home || continue` in that
   loop. In `fingerprint` (anchor `find . -type f -name '*.nix' -print0`)
   become `find . -type f \( -name '*.nix' -o -name home-plan.json \) -print0`.
   Add after `fingerprint`:
   ```bash
   # home_applies DIR -- does home.nix take part in what apply will change?
   home_applies() {
     home_mode
     [ "$HOME_MODE" = legacy ] && return 0
     jq -e '.action == "claim" or .action == "copy"' "$1/home-plan.json" >/dev/null 2>&1
   }
   ```
   `pins_json` is unchanged (it hashes the snapshot's `home.nix`, now present
   for `keep` and `refuse`).
d. **`cmd_pending`.** In the loop after `: >"$READDIR/lines.jsonl"` (the
   *second* occurrence of `[ "$p" != home ] || apply_has_home || continue`, the
   one followed by `src=$READDIR/$p.nix`) replace the guard with
   `[ "$p" != home ] || home_applies "$READDIR" || continue`.
e. **`user_scope` and `user_scope_note`.** In `user_scope`, after the line
   `[ -f "$(home_template)" ] && [ -r "$(home_template)" ] || { printf '%s' "$NO_HOME_TEMPLATE"; return; }`
   and before `options_resolve`, add this (add `plan text` to the function's `local meta user`):
   ```bash
   case "$HOME_MODE" in
     plan|blind)
       plan=$(home_plan)
       text=$(jq -r '.unavailable // .error // (select(.owner != null and .owner != .caller)
         | "home.nix belongs to \(.owner); ask \(.owner) to apply, or run nixarchy-apply --release-home to give the host up") // empty' <<<"$plan")
       if [ -n "$text" ]; then printf '%s' "$text"; return; fi ;;
   esac
   ```
   (`apply_has_home` above already ran `home_mode` in this subshell.) In
   `user_scope_note` call `home_mode` first (it runs in its own `$(...)`, so
   `user_scope`'s detection is not visible to it), build the old cache note and, in `plan` when
   `home_plan | jq -e '.owner == null and has("action")'`, the note
   `the first apply with an edited home.nix makes you the owner`; print them
   joined with `; ` (loop `out=${out:+$out; }$n`). It must still print nothing
   when neither applies and must still call `options_resolve` first.
f. **`cmd_check`.** Declarations: `tpl home_user` becomes `tpl render_user plan`.
   Replace the block from `tpl=$(home_template)` through its `check_answer`
   `fi` (anchor `if [ -f "$CHECKDIR/snap/home.nix" ] && { [ ! -f "$tpl" ] || [ ! -r "$tpl" ]; }; then`) with:
   ```bash
   tpl=$(home_template)
   home_mode
   render_user=""
   case "$HOME_MODE" in
     legacy) [ ! -f "$CHECKDIR/snap/home.nix" ] || render_user=$(id -un) ;;
     plan|blind)
       plan=$(cat "$CHECKDIR/snap/home-plan.json")
       if [ "$(jq -r 'has("error")' <<<"$plan")" = true ]; then
         verdict=fails; error=$(jq -r .error <<<"$plan"); check_answer
       elif [ "$(jq -r '.action == "refuse"' <<<"$plan")" = true ]; then
         verdict=fails; error=$(jq -r .message <<<"$plan"); check_answer
       elif [ "$(jq -r 'has("unavailable")' <<<"$plan")" = true ]; then
         if [ -f "$CHECKDIR/snap/home.nix" ]; then reason=$(jq -r .unavailable <<<"$plan"); check_answer; fi
       else render_user=$(jq -r '.renderUser // ""' <<<"$plan"); fi ;;
   esac
   if [ -n "$render_user" ] && { [ ! -f "$tpl" ] || [ ! -r "$tpl" ]; }; then
     reason=$NO_HOME_TEMPLATE
     check_answer
   fi
   ```
   (`verdict` defaults `unknown`; `check_answer` ends the run.) In the part
   loop (anchor `[ "$p" = home ] || imports="$imports ./nixarchy/$p.nix"`),
   before `rm -f "$cb/nixarchy/$p.nix"` add
   `[ "$p" != home ] || home_applies "$CHECKDIR/snap" || continue`. After that
   loop, add the materialisation for `keep` with an owner:
   ```bash
   if [ "$HOME_MODE" = plan ] && [ -n "$render_user" ] && ! home_applies "$CHECKDIR/snap"; then
     rm -f "$cb/nixarchy/home.nix" || die "cannot replace $cb/nixarchy/home.nix"
     if [ -f "$CHECKDIR/snap/flake-home.nix" ]; then
       cp "$CHECKDIR/snap/flake-home.nix" "$cb/nixarchy/home.nix" 9>&- 8>&- || die "cannot copy the flake's home.nix"
     fi
   fi
   ```
   In the fill (anchor `home_user=$(id -un)`), replace the guard
   `if [ -f "$CHECKDIR/snap/home.nix" ]; then` with `if [ -n "$render_user" ]; then`,
   delete the `home_user=$(id -un)` line, and use `$render_user` in the
   `USER_RE` test, the `die` text and the `sed -e "s|@USER@|$render_user|g"`.
g. State and search need no edit: they already call `user_scope` and
   `user_scope_note`.

Check: `bash tests/adapter.sh </dev/null` ends `all passed`;
`shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh` clean; the
QML tests from step 0; `nix flake check`.
Traps: (1) `set -e`: declare then assign, never `local x=$(cmd)`; every `grep`
in `home_mode` is inside `if`/`elif`. (2) `$(user_scope)` and `$(home_plan)` are
subshells: they cannot set `HOME_MODE` for the caller, which is why
`cmd_check` and `snapshot_selection` call `home_mode` themselves. (3)
`check_answer` ends the run; the first `check_answer` is before the template
test, which is intended. (4) The `jq` `IN(...)` needs jq 1.6+ (installed 1.8.2).
(5) Do not echo the plan JSON to stderr. (6) `home_plan`'s exit status is 0
always (it prints `unavailable` instead), or the `$(home_plan)` in a `set -e`
caller kills the run. (7) The bash string `HOME_MODE` must be one of four
words: nothing else reads it. (8) `snapshot_selection` is also called for
`snap2` and `READDIR`; it must not assume the first call.

### 4. Docs -- codex

- `docs/manual/packages.md`, after the sentence `The panel shows the reason
  when it is unavailable.` append: ` One user owns `home.nix` on a host: user
  scope is for that user (or for whoever applies an edited `home.nix` first).
  Another user sees the owner's name as the reason, and a nixarchy that cannot
  say who owns it leaves user scope off and `check` `unknown`.`
- `docs/manual/options.md`, after `A disabled row shows the reason.` append the
  same two sentences; and at the end of the paragraph that ends `is reported
  with nix's message.` append: ` `check` follows `nixarchy-apply`'s decision
  about `home.nix` (who owns it, and whether your file is copied), so it
  evaluates what apply will write; if apply would refuse, `check` fails with
  the same text.`
- `docs/manual/from-a-terminal.md`: row `| `fingerprint` | One 64-digit SHA-256
  over every `.nix` file in the selection snapshot, names included |` becomes
  `... over every `.nix` file in the selection snapshot, plus, on a host whose
  nixarchy handles `home.nix`, apply's home decision, names included |`; row
  `| `fingerprint` | The selection snapshot's 64-digit SHA-256 |` becomes
  `| `fingerprint` | The selection snapshot's 64-digit SHA-256, built as `pending`'s is |`.
  The doc has no `userScope` rows to extend.
Check: `grep -n 'who owns\|home decision' docs/manual/*.md` finds all four.
Traps: no other doc edit; keep line endings and the table pipes.

### 5. Coordinator: verify, prove, commit

1. `bash tests/adapter.sh </dev/null` ends `all passed`; `shellcheck bin/nixarchy-pkg
   bin/nixarchy-pkg-keys tests/adapter.sh` and, by hand,
   `shellcheck tests/fixtures/apply-1820.sh` (the SC2034s of the verbatim
   block only); the QML tests from step 0; `nix flake check`.
2. **Must fail on main.** In a `mktemp` copy `d` (worktree copied; tests and
   fixtures new): `( cd "$d" || exit 1; git show main:bin/nixarchy-pkg > bin/nixarchy-pkg;
   bash tests/adapter.sh </dev/null | grep FAIL )`. Expected failing by
   description: rows 1-14 except the parts listed as passing, and the `claim`
   byte-equality; the preservation rows other than `claim` must **pass** on
   main (they are guards). A row expected to fail that passes on main is a bad
   test: fix it. Record the list in the PR.
3. **Mutation proofs**, each in its own `mktemp` copy `( cd "$d" || exit 1; ... )`
   of the finished tree (never the worktree):
   - M1 `home_applies` becomes `return 0`: the `keep`/`refuse`/`dropped` `pending`
     preservation rows and row 5 (`generated-home.nix` would be bob's) fail.
     (The spec expects row 14 to fail here too; it cannot, because with no
     caller file there is nothing to overwrite the owner's with. Row 14 is
     M7's proof. Recorded as a deviation from the spec.)
   - M2 drop `-o -name home-plan.json` from `fingerprint`: row 10 fails.
   - M3 drop the `flake-home.nix` copy: row 5 variant (ii) fails.
   - M4 drop the `blind` branch of `home_mode`: rows 1 and 8 fail.
   - M5 change one character of the fixture's `home_decide` copy: the drift
     test fails (this host has the installed apply).
   - M6 delete the materialisation block in `cmd_check`: row 12's race variant fails.
   - M7 template guard back to `[ -f "$CHECKDIR/snap/home.nix" ]`: row 5(i) and row 14 fail.
   Each must fail the named test and no unrelated one; record in the PR.
4. Commits (the coordinator; Codex never commits; the plan's approval commit
   `docs(plan): approve 2026-11-17-103-follow-home-owner (#103)` came first,
   before Codex started): `test(home): follow nixarchy's home owner, tests first (#103)`
   with `tests/` only, then `fix(home): detect the home part again and follow
   apply's owner decision (#103)` with `bin/` and `docs/`. Commit messages end
   with the attribution lines the session gives. If implementation deviates,
   `plan/` is updated in the same commit as the code.

### 6. Review

`git diff main` against this plan by a fresh `model: "opus"` agent given only
the plan path and the diff, plus Codex and agy read-only (`reviewers:`).
Findings are classified confirmed / refuted / unverified; confirmed ones are
fixed before the PR. Provider failures are reported verbatim.

### 7. Live check, in a `nixarchy-desktop` microVM (not razer)

Everything in the guest, nothing on the host's real config; use the
`live-test-in-microvm` choice. Never restart the shell from the agent.
Runs now (the guest has today's nixarchy, `blind`):
1. `state`: `userScope.reason` is `this nixarchy cannot say who owns home.nix;
   update nixarchy`. `check` with a `home.nix` in the selection: `unknown`
   with that text and no flake work. `pending`: no `home` row. `apply --pin
   home=<real hash of the caller's home.nix>`: not refused with exit 4.
2. A guest-only shim restoring the old loop word (`legacy`) is **not** the final
   check but runs: user scope available, `check` byte-equal to apply's
   `nixarchy-apps.nix` (as #100's step 7: guest `nix` wrapper that copies
   `$copy/nixarchy-apps.nix`, then `diff`).
3. `none`: a guest apply without either marker: plain stub, no plan call.

**Deferred until nixarchy has #1825** (stated in the PR as not done): owner
alice applies; as bob (seed): user scope unavailable naming alice, `check`
evaluates alice's import and the flake's `home.nix`; bob edits his file:
`check` `fails` with the refusal and real `nixarchy-apply` exits 1 with the same
text; alice runs `--release-home`: user scope available with the note;
byte-compare `check`'s generated file with apply's in each row; then run the
ten cases of the contract against the real `--home-plan --json` and compare
field by field.

### 8. PR

Title `fix(home): detect the home part again and follow apply's owner decision (#103)`.
Body links `intent/`, `spec/`, `plan/`, lists the steps Codex did (1-4) and the
coordinator did (0, 5-8), the main-failing list, the mutation results, the
live-check results, and says the `plan`-mode live check is deferred to #1825.
Do not merge without the owner.

## Deviations from the spec (found while planning)

- The spec says the copied block is 69 lines; it is 68 (measured against the
  installed apply and nixarchy `origin/main`, equal).
- The spec expects mutation M1 to fail row 14; it cannot (no caller file to
  overwrite with). M1's overwrite proof is row 5; row 14 is M7's.
- The spec's row 12 race variant "restored before the second snapshot" needs a
  `check` that reaches its end; a new `pass` mode of the nix stub does that,
  `capture` exits at `flake metadata`.
- The fixture tail adds the contract's error cases (invalid caller, missing
  flake, unreadable file), and tests rows 15-17 and the validator knobs, which
  the spec's section 7 listed less completely.

## Tests (summary)

- `bash tests/adapter.sh </dev/null` ends `all passed` (new: drift, 14 rows,
  preservation rows, legacy/none guards; three existing tests made hermetic).
- `shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh` clean;
  the fixture by hand.
- QML tests pass unchanged; `nix flake check` green.
- Against main's `bin/nixarchy-pkg` the "must fail" list fails (step 5.2).
- Mutations M1-M7 fail the named tests (step 5.3).
- Spec Verification 3 (drift against nixarchy `origin/main`): step 1's two
  extraction routes agree, recorded in the PR.

### Deviations found while implementing (2026-11-17)

- **Row 5(i):** `TPL103=$O62/none.nix` alone gives `fails`, not `unknown`,
  because the fake apply checks the template itself. A test-only `tplguard`
  wrapper gives the fake a valid template for `--home-plan` while `check`
  sees the missing one.
- **Fixture lock:** `fl/flake.lock` is `{"nodes":{}}`, not `lock-one`. Harmless.
- **M7 is two mutations.** Reverting the template guard fails row 5(i) only;
  reverting the fill guard (M7b) fails row 14 and `unowned seed renders stub`.
- **M1, M2, M3** also fail related supersede, race and host-layout tests, as
  expected from fingerprint-based checks.
- **Three row-5 assertions** (`keep uses flake home`, `keep does not use caller
  home`, `check sees changed flake home`) pass on main vacuously; the row's
  failing assertion on main is `keep imports owner`, and M1/M3 make them bite.
- `nix flake check` in a fresh git-init copy ran no build checks; each check
  (`shellcheck`, `qml-tests`, `qml-syntax`, `manifest`, `no-text-multiplier`,
  `no-hardcoded-colours`, `adapter`) was built explicitly instead: all rc 0.

## Rollback

Nothing is applied by this change: `check`, `state` and `pending` are
read-only and the writers are untouched. Revert the PR (`git revert` of the
commits). The new snapshot files (`home-plan.json`, `flake-home.nix`) live in
`mktemp` directories under `$XDG_STATE_HOME` that the commands delete on exit;
a fingerprint taken by the new plugin is `superseded` by the old one once, then
the panel re-checks. Reverting returns a `blind` host to "no Home Manager part"
(today's behaviour).
