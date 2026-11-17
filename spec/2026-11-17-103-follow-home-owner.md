---
status: approved
issue: 103
intent: intent/2026-11-17-103-follow-home-owner.md
---

# Spec: follow nixarchy's home owner: detect the home part again, and let check and user scope use apply's decision

## Design

Line numbers are this repo at cd8ccc3 (`bin/nixarchy-pkg`, `tests/adapter.sh`;
`bin/` is unchanged since 16e9664) and nixarchy `origin/main` 74000e98
(`modules/apps.nix`). The intent's seven open questions were approved with the
recommended answer; they are settled and are not reopened here.

### Decisions for the owner

The intent left these open (or did not see them). Each has a recommended
answer, which this spec assumes.

1. **The JSON contract for `nixarchy-apply --home-plan --json` is section 1
   below, and #1825 is implemented against it.** One point differs from the
   sketch in #1825: the state word is `absent`, not `missing`, because
   `classify_home` (`modules/apps.nix:4775`) already sets
   `home_state=absent` and the plugin must not translate. Recommended: yes;
   paste section 1 into #1825 (this spec does not edit that issue). Say so if
   you want `missing`: nixarchy then maps `absent`, and the contract carries
   a word the apply text never uses.
2. **The plugin finds `--home-plan` by reading the installed script**
   (`grep` for its `case` label), like `searched()` (`:357`) and
   `apply_has_home` do. Not a `--capabilities` flag. Recommended: yes. If
   nixarchy adds a capability marker later, it replaces one line here.
3. **Until #1825 lands, `check` answers `unknown` only when the caller has a
   `home.nix`** (the intent's wording). A caller with no `home.nix` on a host
   that has an owner gets the plain stub from `check`, as every host gets
   today; apply would render the owner's import. That is an accepted
   interim gap, not a regression (see Risks). Recommended: yes. The
   stricter alternative, `unknown` for every check on a host with the home
   part, turns every check on every current nixarchy into `unknown`.
4. **`--pin home=<sha>` must carry the real hash in every action.** The panel
   forwards every pin it was given (`PkgModel.qml:1188`, `:1220`; `apply`
   accepts `home=` at `bin/nixarchy-pkg:2598`). Apply compares a pin with the
   file on disk and exits 4 on any difference, an empty pin included
   (`modules/apps.nix:4716-4731`). So the snapshot keeps the caller's
   `home.nix` for `keep` and `refuse` too, even though `check` does not
   evaluate it there. Without this, detection alone makes every apply fail
   for a caller whose `home.nix` is the seed (`pins.home == ""`, file
   present). Recommended: yes; it is a consequence, not a choice.
5. **`check` passes `NIXARCHY_FLAKE` (default `/etc/nixos`) to the plan
   call**, so the owner is read from the flake `check` evaluates, not from
   the flake apply was configured with (`cfg.flake`, `:4474`). Recommended:
   yes. Say no to let apply use its own default; the two can then differ
   when the variable is unset and the flake is not `/etc/nixos`.
6. **The test fake of the new apply carries nixarchy's own function text**
   (`tests/fixtures/apply-1820.sh`, copied from `74000e98`), plus a drift
   check against the installed apply when there is one. No nixarchy clone in
   CI. Recommended: yes (intent Q7's default). Say so if you prefer a CI job
   that checks nixarchy out.

### 1. The contract: `nixarchy-apply --home-plan --json` (intent Q2)

This is what #1825 implements and this plugin consumes. Names below are
nixarchy's own (`modules/apps.nix`).

**Invocation.** `nixarchy-apply --home-plan --json`, and nothing else on the
line. Any other flag combined with `--home-plan` exits 2 with the usage text
(the `*)` arm, `:4454-4463`, extended with
`nixarchy-apply --home-plan [--json]`). `--home-plan` without `--json`
prints one human line and is not a contract, as plain `--status` is not
(`:4461`). The environment is apply's: `NIXARCHY_FLAKE`,
`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `HOME`; the caller is `id -un`.

**What it runs.** The same code apply runs, in the same order, and nothing
else: `base` and `dest` (`:4640-4648`; the flake path is `:4474`), `snapshot_home` (`:4763`),
`classify_home ${homeTemplate}` (`:4775`, `:4919`), `read_owner` (`:4790`,
`:4921`), `home_decide` (`:4810`, `:4932`), and the `render_user` rule
(`:4938-4942`, `:4943-4946`). It therefore stops where apply stops: before
`echo "Enabled apps:"` (`:4657`), before `mkdir -p "$base/nixarchy"`
(`:4663`) and before `exec 9>"$applied/lock"` (`:4671`). The function
definitions `:4753-4820` move above that point, or the branch is a function;
which of the two is nixarchy's call. `pinned` is a private `mktemp -d` with
the same `trap`, so `snapshot_home` has somewhere to put `home.snap`.

**Read-only, as a rule of the contract.** It takes no lock, creates no
directory, writes nothing under `$base`, `~/.config/nixarchy`, `$applied`
or `$XDG_STATE_HOME`, and does not need `apps.nix` to exist (the
`[ -f "$file" ] || ... exit 1` at `:4650` does not apply). It does need the
flake directory (`:4651-4655`): without it, exit 1 with that message.

**Success: exit 0, one line on stdout, for every decision, `refuse` included.**

```json
{"version":1,"owner":"alice","caller":"bob","state":"seed","action":"keep","renderUser":"alice","message":null}
```

| field | type | value |
|---|---|---|
| `version` | number | `1`. A later, incompatible shape changes it. |
| `owner` | string or `null` | `read_owner`'s `owner`; `null` when `""`. |
| `caller` | string | `id -un`. |
| `state` | string | `classify_home`'s `home_state`: `seed`, `edited` or `absent`. |
| `action` | string | `home_decide`'s answer: `claim`, `copy`, `keep` or `refuse`. |
| `renderUser` | string or `null` | `claim`/`copy`: the caller; `keep`: the owner, `null` when there is none; `refuse`: `null`. |
| `message` | string or `null` | `refuse`: apply's refusal text exactly as `:4934` prints it (with its `nixarchy-apply: ` prefix, no newline); otherwise `null`. |

All seven keys are always present. The plugin ignores any other key, so
nixarchy may add some without a `version` bump.

**Error: exit 1, one line on stdout, no other key.**

```json
{"version":1,"error":"nixarchy-apply: /etc/nixos/nixarchy-apps.nix names several home owners (or an unparseable one); fix it by hand"}
```

`error` is the message apply prints on stderr for the same failure, without
the newline. The cases the existing code produces: `read_owner` fails
(`:4800-4807`), an invalid render user (`:4943-4946`; `valid_user`, `:4786`),
`snapshot_home` cannot read or copy (`:4763-4773`), the flake directory is
missing. Two cases it does **not** produce today, which #1825 adds in the
shared code (apply gets them too): `classify_home` (`:4775-4784`) treats
every non-zero `cmp -s` as `edited`, including `cmp` failing to read the seed
(measured: a nonexistent template gives `rc=0 state=edited`), so a `cmp`
exit above 1 must become an error; and `valid_user` is applied to the caller
in every decision, not only to a non-empty `render_user`. An error is never
reported as `action: "keep"`. The same text may also go to stderr.

**Exit codes.** 0 a decision; 1 an error as above; 2 usage (an unknown
combination). Anything else, or exit 0/1 with output that is not exactly
these shapes, is "no usable answer" to the plugin (section 3), never a
decision.

**Measured.** The six rows of the table in the intent, plus the malformed
owner, were run through apply's own functions: `select_home_src` to
`home_decide`, extracted from the installed `nixarchy-apply` (69 lines,
nixarchy at 74000e98's shape) into a `mktemp` directory, wrapped in a
15-line driver that prints the object above. Results (owner / caller /
file: action, renderUser):

| owner | caller | file | state | action | renderUser |
|---|---|---|---|---|---|
| none | bob | edited | edited | claim | bob |
| none | bob | seed | seed | keep | null |
| none | bob | absent | absent | keep | null |
| alice | alice | seed | seed | copy | alice |
| alice | alice | edited | edited | copy | alice |
| alice | alice | absent | absent | keep | alice |
| alice | bob | seed | seed | keep | alice |
| alice | bob | absent | absent | keep | alice |
| alice | bob | edited | edited | refuse | null (message set) |
| two owner lines | bob | seed | | exit 1, `{"version":1,"error":"…several home owners…"}` | |

Ten runs of the driver took 0.106 s wall (about 10 ms each, `jq` included),
so a call per `state` or `search` is affordable. This proves the contract is
implementable from apply's existing functions and that the table in the
intent is what they do; it does not prove #1825's implementation.

### 2. Detection: three modes from one read of the installed script (intent Q1)

`apply_has_home` (`bin/nixarchy-pkg:363-367`) stays the question "does this
apply handle `home.nix` at all", now answered from `home_mode`:

```
home_mode: plan    the script has a `--home-plan)` case label
           legacy  else: the old loop word  ^for part in .*\bhome\b
           blind   else: home_decide() (a #1820 apply without the plan command)
           none    otherwise
```

as three `grep -qE` in that order over `$(command -v nixarchy-apply)`, memoised
in one variable per process. Patterns, against the text nix writes into the
installed script (where the indentation of the `''` string is stripped):
`^[[:space:]]*--home-plan\)`, `^for part in .*\bhome\b`, `^home_decide\(\)`.
`apply_has_home` is `[ "$(home_mode)" != none ]`.

Measured on this host's installed apply
(`/nix/store/4lw7q8jdhgq93fmsy8rp02rk0asxmhvm-nixarchy-apply`, read only):
the existing pattern finds 0 lines (the bug, on a real host, not a fake);
`^home_decide\(\)` finds 1 (`:394`), the loop is `for part in apps services
advanced flatsnap; do` (`:532`), and `--home-plan` is absent. So this host is
`blind` today.

`plan` first, so a nixarchy that renames `home_decide` but ships the command
is still `plan`. `legacy` keeps today's meaning: the invoking user is the
writer, no plan call, #100's behaviour.

### 3. One call to the plan, one helper (intent Q2, Q4)

`home_plan` (new, beside `home_template`, `:369`) prints one JSON line,
always:

- Mode `plan`: runs
  `NIXARCHY_FLAKE=${NIXARCHY_FLAKE:-/etc/nixos} timeout 10 nixarchy-apply --home-plan --json </dev/null 9>&- 8>&-`
  (the fd closes are the file's pattern for children, e.g. `:859`) and
  validates with `jq -e`:
  - exit 0, exactly one JSON object (`jq -es 'length == 1'`), all seven keys
    present with section 1's types, `.version == 1`, `.action` and `.state`
    in their words, and the relations: `claim`/`copy` have `renderUser ==
    caller`; `keep` has `renderUser == owner`; `refuse` has a non-null
    `owner != caller`, `renderUser == null`, and a string `message`; `message`
    is `null` otherwise: the line as apply printed it;
  - exit 1, exactly one object, `.version == 1` and `.error` a string, no
    decision keys: that line;
  - anything else: `{"unavailable":"nixarchy-apply --home-plan gave no usable
    answer (exit N); update nixarchy or nixarchy-pkg"}`.
- Mode `blind`: `{"unavailable":"this nixarchy cannot say who owns home.nix;
  update nixarchy"}` (the intent's sentence), no process started.
- Modes `legacy` and `none`: nothing is printed and no process starts.

So a consumer sees exactly one of three shapes: a decision (`.action`), an
error (`.error`), or `.unavailable`. `renderUser` is checked against
`$USER_RE` (`:77`) at its one use (section 5); apply already validated it,
this repo does not trust a name it substitutes into Nix text.

### 4. The snapshot carries the decision, so every reader agrees (intent Q4, Q5, Q6)

`snapshot_selection DIR` (`:1897-1912`) in modes `plan` and `blind`:

- keeps copying the caller's `home.nix` (loop `:1900`, guard `:1901` is
  `apply_has_home`, now broader). Decision 4 is why.
- writes `DIR/home-plan.json` from `home_plan`.
- in `plan` mode with `action == keep` and a non-null `renderUser`, copies
  the flake's `$(flake_base)/nixarchy/home.nix` (when it exists) to
  `DIR/flake-home.nix`. It is what `check` evaluates in that row, so it
  belongs in the fingerprint; in `claim`/`copy` the flake's file is
  overwritten and is not an input.

`fingerprint` (`:1915-1918`) hashes `*.nix` and `home-plan.json`:
`find . -type f \( -name '*.nix' -o -name home-plan.json \)`. One function,
used by `cmd_pending` (`:2115`) and `cmd_check` (`:2435`, `:2557`), so the
panel's comparison (`PkgModel.qml:628`, `:641`, `:719`) stays equal, and
`snap2` re-runs the plan, so an owner change during a long `check` that
reaches the end gives `superseded` (the early failure answers are a Risk). A host in `legacy` or `none` writes neither file: its
fingerprint is byte-identical to today's. `pins_json` (`:1921`) is unchanged;
`pins.home` is now the real hash on a `blind` or `plan` host (Decision 4).
`PkgModel.qml` and the QML tests need no change: the fingerprint is an opaque
string to them (verified by running them, Verification 5).

One helper decides whether `home.nix` takes part in what apply will change:
`home_applies DIR`: mode `legacy`, or `DIR/home-plan.json` has `.action` in
`claim`, `copy`. Not `keep`, `refuse`, an error or `unavailable`.

- **Pending loop** (`cmd_pending`, `:2039-2040`): the guard becomes
  `[ "$p" != home ] || home_applies "$READDIR" || continue`. Both the
  `new`/`modified` and the `dropped` status paths for `home` are then
  skipped for `keep` and `refuse`, so no change apply will not make is shown
  (intent Q5). `legacy` still reports `dropped` as before.
- **`user_scope`** and **`check`**: section 5.

### 5. `check` follows the decision (intent Q4)

`cmd_check` (`:2406`), after the fingerprint and pins (`:2435-2436`) and
before anything is copied. Read `DIR=$CHECKDIR/snap`:

| plan | verdict | where |
|---|---|---|
| `.error` | `fails`, `error` = the message | answered at once, before the flake is copied |
| `.action == refuse` | `fails`, `error` = `.message` | the same; apply stops before any write |
| `.unavailable` and the caller has `home.nix` | `unknown`, `reason` = that text | the same |
| `.unavailable`, no `home.nix` | continues: plain stub, as today | |
| `claim`, `copy` | continues; render user is `.renderUser` (the caller) | caller's `home.nix` copied over the flake's, as #100 |
| `keep`, owner | continues; render user is `.renderUser` (the owner) | the flake's own `nixarchy/home.nix` is not overwritten |
| `keep`, no owner | continues; plain stub, no home import | the flake's `nixarchy/home.nix` stays in the copy, unimported |
| mode `legacy` | as #100: render user `id -un` when the snapshot has `home.nix` | |
| mode `none` | plain stub | |

Code, in `cmd_check`:

- A local `render_user`: `.renderUser // ""` in `plan` mode; `id -un` in
  `legacy` when `snap/home.nix` exists; `""` otherwise. The template
  guard (`:2437-2441`, today `[ -f snap/home.nix ]`) becomes
  `[ -n "$render_user" ]`: the template is needed when an import is rendered,
  which includes `keep` with an owner (the caller may have no `home.nix` at
  all). The fill (`:2515-2520`, `home_user=$(id -un)` at `:2516`) uses
  `$render_user` and still dies on `$USER_RE`.
- The copy loop (`:2502-2508`) skips `home` unless `home_applies "$CHECKDIR/snap"`
  (it rm's and copies the file at `:2504-2506`). For `keep` with an owner the
  evaluated `nixarchy/home.nix` is **materialised from `snap/flake-home.nix`**
  (`rm -f` the copy's file, then `cp` the snapshot's file; no snapshot file
  means no file), not left as the live `cp -a` of `:2494` made it: that read
  is a second, unsynchronised one, and the fingerprint must describe the bytes
  that were evaluated. For no-owner `keep` the plain stub plus the flake's
  unimported file is what apply leaves, and nothing is evaluated from it.
  `$imports` already skips `home` (`:2507`).
- `refuse` and `.error` skip all nix work: apply stops first (`:4933-4936`).
  `check_answer` (`:2139`) already prints `error` when it is set.

### 6. User scope names the owner (intent Q3)

`user_scope` (`:372-397`), after the apply and template tests and before the
options cache (the plan does not depend on the flake's options):

1. `apply_has_home` false: unchanged.
2. Template missing: unchanged (`NO_HOME_TEMPLATE`, `:378`). A template
   only matters when an import is rendered; user scope renders one in every
   available case, so it stays here.
3. Mode `plan` or `blind`, from `home_plan` (no snapshot exists here):
   - `.unavailable`: that text. (`blind` always; `plan` when the call gave no
     usable answer.)
   - `.error`: the text, so a malformed owner file shows as the reason.
   - `.owner` non-null and `!= .caller`:
     `home.nix belongs to <owner>; ask <owner> to apply, or run
     nixarchy-apply --release-home to give the host up`, whatever
     `.state` is. This is apply's own wording (`:4934`) minus the `has
     edited theirs` clause, which is not always true here.
   - otherwise: continue.
4. The options-cache tests, unchanged.

`user_scope_note` (`:399-405`) adds, in `plan` mode when `.owner` is null,
`the first apply with an edited home.nix makes you the owner`, joined to the
existing cache note with `; ` when both apply. `scope_args` (`:407-422`),
`cmd_search` (`:629`) and `cmd_state` (`:2687`) call `user_scope` already,
so the panel shows the reason and `pkg add --scope user` dies with it before
a transaction opens. The plugin never offers `--release-home`; the reason
only names it.

`legacy`: step 3 is skipped. This is today's behaviour on a pre-#1820 host.

### 7. Tests (intent Q7)

Fakes, in `tests/fixtures/` and `tests/adapter.sh`:

- **`tests/fixtures/apply-1820.sh`**: a script shaped like the installed
  nixarchy-apply at `74000e98`: the loop without `home`
  (`for part in apps services advanced flatsnap; do`), the `--release-home)`
  case line, `home_decide` and its neighbours **copied verbatim**
  (`select_home_src` to `home_decide`, with a header naming the commit),
  and a `--home-plan` arm that is the 15-line driver of section 1, driven by
  real files: `XDG_CONFIG_HOME`, `NIXARCHY_FLAKE`, and
  `NIXARCHY_HOME_TEMPLATE` (the same fixture used elsewhere) as the seed.
  The `--home-plan` arm and the usage line are the only text that is not a
  copy, and the header says so.
- **`tests/fixtures/apply-1820-blind.sh`**: the same file with the
  `--home-plan` arm removed (`sed '/--home-plan/,…d'` at test time, so one
  copy serves both).
- The two existing fakes (`tests/adapter.sh:2589`, `:2665`: `for part in
  apps services advanced flatsnap home`) stay as the `legacy` case.
- **Drift:** when `command -v nixarchy-apply` exists and has `home_decide`,
  the fixture's `select_home_src` to `home_decide` block must equal the
  installed one byte for byte (`diff` of two `awk` extracts); otherwise
  skipped with a printed note, as the template drift test is
  (`tests/adapter.sh:2699-2702`). It runs on this host.
- `nix` stub `capture` mode (`:2502-2506`) also copies the copy's
  `nixarchy/home.nix` to `generated-home.nix`, so a test can say which
  `home.nix` was evaluated.

**Must fail on main** (each: new test, `bin/nixarchy-pkg` as on main, in a
`mktemp` copy, failure recorded in the plan):

1. `blind`: `state`'s `userScope.reason` contains `cannot say who owns`
   (main: `no Home Manager part`).
2. `plan`, owner = caller: `userScope.available` is true, no note
   (main: false).
3. `plan`, owner alice, caller bob, seed: unavailable, reason contains
   `belongs to alice` and `--release-home` (main: wrong reason); the same
   with an edited file; `pkg add --scope user` dies with it, no transaction.
4. `plan`, no owner: available, note contains `makes you the owner`.
5. `plan`, `keep` with owner alice, caller bob seed: `check`'s generated
   file imports `home-manager.users."alice"`, and `generated-home.nix` is
   the flake's, not bob's (main with this fake: the plain stub, because the
   home part is not detected).
   Variants: bob has no `home.nix` at all (the template guard must still
   require the template, since an import is rendered); and only the flake's
   `home.nix` changes between two runs: `pending`'s and `check`'s
   `fingerprint` both change (the `flake-home.nix` input).
6. `plan`, `refuse`: `check` answers `fails` with `.error` containing
   `belongs to alice`, and `nix.calls` has no flake call (the `config show`
   idiom of `tests/adapter.sh:2766-2767`).
7. `plan`, malformed owner file: `check` `fails` with the `several home
   owners` text; `userScope.reason` is that text.
8. `blind` with a caller `home.nix`: `check` `unknown` with the intent's
   sentence, no flake call.
9. `pins.home` is the 64-digit hash of the caller's `home.nix` in `keep`
   and `refuse` (main with the new fake: `""`). The real exit 4 for an
   empty pin is apply's own code (`modules/apps.nix:4716-4731`; the fake
   in `tests/adapter.sh:2669` exits 1 on a mismatch), so it is a required
   live check (Verification 6), not a fake's.
10. Fingerprint: with the snapshot fixed, rewriting the owner line in the
    flake's `nixarchy-apps.nix` changes `pending`'s and `check`'s
    `fingerprint`, and the two stay equal to each other.
11. A fake whose `--home-plan` exits 2, prints text, prints `"version":2`,
    omits `owner`, gives `owner: 42`, or gives `refuse` with a null
    `message`: `check` `unknown` for a caller with `home.nix`, user scope
    shows the reason; and `blind`'s reason is the same sentence.
12. `check` with the owner changing between the two snapshots
    (`NIX_MODE=change-owner`, rewriting the flake's `nixarchy-apps.nix`
    while the nix stub's final eval runs, as `change-lock` does) answers
    `superseded`; and with the flake's `home.nix` changing while the copy is
    made but restored before the second snapshot, the evaluated file is the
    snapshot's (the `generated-home.nix` capture), not the live read.
13. `hosts/<host>` layout: the owner and `home.nix` are read from
    `hosts/<host>/`, not from a root-level `nixarchy-apps.nix` that names
    someone else (the fake and `flake_base` must agree).
14. Owner `keep`, owner has a seed file, caller `bob` has **no** `home.nix`:
    `check` renders alice's import and requires the template.

**Preservation: pass on main with the new fake, and must keep passing**
(they guard the fix, not prove it; on main they pass because the home part
is not detected at all):
- `plan`, `keep` with no owner, caller seed: the plain stub, no
  `home-manager`; the flake's `nixarchy/home.nix` unchanged on disk.
- `plan`, `keep` or `refuse`: `pending` has no `home` file and no `home`
  change although the caller's `home.nix` differs from the flake's. It fails
  against a detection-only fix, which is what the first mutation below
  catches.

**Pass on main with the legacy fake and must keep passing:** all of #62 and
#100's tests, including a `claim`/`copy` check byte-equal to the filled
fixture (with the new-shape fake this one fails on main). Also `none` (no
`home.nix` snapshot, no plan call: the fake logs its argv and the test
asserts `--home-plan` was never run), and the fingerprint of a `legacy` or
`none` host unchanged (a recorded value compared with a computed one).

Mutation proofs, in `mktemp` copies only, `( cd "$d" || exit 1; ... )`:
broaden `apply_has_home` and skip `home_applies` (the preservation `pending`
case, and rows 5 and 14 on `generated-home.nix`, must fail); drop
`home-plan.json` from the `fingerprint` find (row 10 must fail); drop the
`flake-home.nix` copy (row 5's second variant must fail); drop the `blind`
branch of `home_mode` (rows 1 and 8 must fail); change one character of the
fixture's `home_decide` copy (the drift test must fail where the installed
apply exists).

### 8. Docs

`docs/manual/packages.md:119` and `docs/manual/options.md:129` (the paragraph
that describes `check`'s user-scope evaluation) gain: one user owns
`home.nix` per host, user scope is for that user (or for whoever applies an
edited one first), another user sees the owner's name, and a nixarchy that
cannot say who owns it leaves user scope off and `check` `unknown`.
`docs/manual/from-a-terminal.md:119` and `:142` (`fingerprint`) become "every
`.nix` file in the selection snapshot, plus, on a host whose nixarchy handles
`home.nix`, apply's home decision, names included". The `state` row for
`userScope` in the same file gets the new reasons if it lists them.

## Alternatives rejected

- **Re-implement `home_decide` here** (Q2 a): a second copy that #1820
  already showed changes. The drift test would only run in CI against a
  nixarchy checkout.
- **Detect by `/etc/nixarchy/home-apps-template.nix`** (Q1 b): says nothing
  about which apply is installed.
- **Detect only #1820 and later**: drops the loop word; a pinned plugin on a
  lagging host (`74000e98` pin, #1816) would lose user scope for no gain.
- **Read the owner here with the three `grep` rules** (the "small owner
  read"): the `read_owner` copy by another name.
- **Drop `home.nix` from the snapshot for `keep`/`refuse`** (a smaller
  diff): empties `pins.home` and makes every apply exit 4 (Decision 4).
- **Always include the flake's `home.nix` in the fingerprint**: spurious
  `superseded` in `claim`/`copy`, where it is overwritten.
- **A state file or a `--capabilities` flag as the only detection**:
  needs a nixarchy that does not have it; the grep works on the installed
  text and a flag can replace it later.
- **`unknown` for every check without a plan command**: see Decision 3.

## Risks

- **Heuristic detection.** A rename of `home_decide`, of `--home-plan` or of
  the loop makes a host `none` and switches user scope off silently, which
  is what the loop-word rename did. Mitigations: the order (`plan` first),
  three independent markers, the drift test against the installed text, and
  the contract written down for #1825.
- **Interim gap (Decision 3).** On a host with the home part and no
  `--home-plan`, a caller with no `home.nix` and an owner present gets a
  `check` of the plain stub where apply renders the owner's import. `check`
  can say `evaluates` for a flake apply would fail on, or the reverse.
  Unchanged from before this issue (where it was every host).
- **The plan call reads the live files** a moment before or after the
  snapshot copies them, and the owner is read by `nixarchy-apply` separately
  from the flake's `home.nix` the snapshot copies; no lock spans the pair.
  A change in between shows as `superseded` for an answer that reaches the
  second snapshot (it re-runs the plan; the evaluated `home.nix` comes from
  the snapshot, section 5). Not covered, and not new: `check`'s failure
  answers for `flake metadata` and the host query (`:2531`, `:2541`) return
  before the second snapshot for every part, not only `home.nix`. Moving the
  comparison in front of those answers is out of this issue.
- **NIXARCHY_FLAKE mismatch (Decision 5).** If the plugin's default
  (`/etc/nixos`) is not the flake the user applies, the check was already
  evaluating the wrong flake; the plan now reads the same wrong flake
  consistently.
- **Cost.** One extra process per `state`, `search` and `check`, about
  10 ms measured for the driver; the real `nixarchy-apply` start-up parses
  flags first and exits, and is not measured here.
- **Fingerprint changes** on a host with the home part (the file list
  grows), once, on upgrade: an armed key or a completed check from the older
  plugin becomes `superseded`. Intended.
- **Not verified on a real host.** What is measured above is the installed
  script's text (this host, `blind`) and apply's functions in a scratch
  directory. The live checks below have not run, and `--home-plan` exists
  only in this spec.
- **Work on nixarchy (#1825) is a separate PR** this repo cannot land; the
  `plan` rows are tested against a fake that is a copy of apply's functions
  plus the section 1 driver, not against nixarchy's implementation.

## Verification

1. `bash tests/adapter.sh` green, including the new cases; the "Must fail
   on main" list recorded as failing against main's `bin/nixarchy-pkg` in a
   `mktemp` copy; the mutation proofs fail as stated.
2. `shellcheck bin/nixarchy-pkg tests/adapter.sh` clean (the CI check,
   `flake.nix:71-75`; fixtures that are scripts are not in that list, so
   run it on them by hand and say so in the plan).
3. Drift: `diff` of the fixture's copied block against the installed
   `nixarchy-apply` (here) and against
   `git -C /mnt/code/Source-home/GitHub/nixarchy show origin/main:modules/apps.nix`
   `:4753-4820` after removing the 18 leading spaces and undoing the `''${`
   escapes (both normalisations; checked to give equal text).
4. The contract: run section 1's driver (in a `mktemp` directory) and compare
   its output with the table above; and, once #1825 has an implementation,
   run the same ten cases against the real `nixarchy-apply --home-plan
   --json` (in the microVM) and compare field by field.
5. The QML tests (`tests/qml`, flake check `qml`) pass unchanged.
6. **Live, in a `nixarchy-desktop` microVM** (the owner's standing choice;
   not razer; nothing on the real host): on a flake with Home Manager and two
   users, with the real installed `nixarchy-apply`:
   - `blind` (today's nixarchy): `state` shows the new reason; `check` with a
     `home.nix` is `unknown`; `pending` shows no `home.nix` row; an
     `apply --pin home=<real hash>` is not refused with exit 4.
   - After #1825: owner alice applies; as bob (seed): user scope unavailable
     naming alice; `check` evaluates alice's import and the flake's
     `home.nix`; bob edits his file: `check` `fails` with the refusal and
     real `nixarchy-apply` exits 1 with the same text; alice runs
     `--release-home`: user scope becomes available with the note.
   - Compare `check`'s generated `nixarchy-apps.nix` with the one real apply
     writes, byte for byte, in each row (`diff`).
   A guest-only shim that restores the old loop word is not the final check.
7. Owner's review of the Decisions above, and of section 1 as the text for
   #1825, before the plan is written.
