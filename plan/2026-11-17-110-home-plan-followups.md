---
status: draft
issue: 110
spec: spec/2026-11-17-110-home-plan-followups.md
coders:
  1: codex   # one Codex run does steps 1-4 in order (agent-run codex refuses a dirty tree and may not commit)
  2: codex   # tests/fixtures/apply-1820.sh, tests/fixtures/home-seed.nix, tests/adapter.sh: fake reads a real seed, new rows
  3: codex   # bin/nixarchy-pkg: one condition, four HOME_PLAN lines, one unset, one comment
  4: codex   # docs/manual/packages.md and options.md: one sentence each
  # Steps 0 and 5-10 stay with the coordinator: baseline, proofs, commits, reviews, the live check, the PR.
reviewers:
  - codex   # reads the diff against this plan, looking for tests that cannot fail
  - agy     # independent read of the diff against this plan
---

# Plan: follow-ups from #103's `--home-plan` review

Branch `fix/110-home-plan-followups` (worktree `nixarchy-pkg-wt/110-home-plan`).
Line numbers are this worktree (08be59b plus intent and spec; main has moved
to 3200c0d but only `README.md` and `assets/showcase/README.md` differ, so no
rebase is needed to implement). **Find every anchor by its quoted text**, the
numbers drift.

## Decisions (from the approved intent and spec; nothing here is open)

1. **`check` after an unusable plan answer.** In `plan` mode only, an
   `unavailable` answer gives verdict `unknown` even when the caller has no
   `home.nix`. `blind` keeps the stub when there is no caller `home.nix`;
   `legacy` and `none` never produce `unavailable`. Reason text unchanged.
2. **One `--home-plan` call in `state` and `search`.** A global `HOME_PLAN`,
   read as `${HOME_PLAN-$(home_plan)}`, set in `cmd_state` and `cmd_search`
   before `user_scope` runs, and `unset` at script start (an inherited value,
   even empty, would skip the live ownership check of the writers). Writers
   (`scope_args`) and `snapshot_selection` (`check`, `pending`) still make
   their own fresh calls; `check` keeps two (snapshot and race probe).
3. **A real seed in the fake.** `tests/fixtures/home-seed.nix` is a byte copy of
   `/etc/nixarchy/home-template.nix`; the fake reads it through
   `NIXARCHY_FAKE_SEED`; the `tplguard` wrapper is deleted; a drift row
   compares the copy with the installed template.
4. **Item 4 (apply reads the live `home.nix`, the snapshot is earlier) is
   documented, not fixed:** a comment above `snapshot_selection` and a line
   under "Left as is" below. No test.
5. **Docs:** both manual pages say `check` is `unknown` also when `--home-plan`'s
   answer is unusable.
6. **Roles.** Codex implements steps 1-4 in one run on a clean tree; the
   coordinator stages, commits, runs proofs and builds, reviews. **One PR**, two
   commits: tests (step 2's files), then the fix (steps 3-4's files).
   Alternatives rejected (spec): cache inside `home_plan`; pass the plan as an
   argument; cache in `check`/`pending`; `fails` for an unusable answer; fix
   item 4; inline the seed with `printf`; a real 10 s hang test.
7. **Live check** in a `nixarchy-desktop` microVM, not razer, against the real
   `--home-plan` from nixarchy main (the installed apply on this host may be
   older). It has not run yet.

## Order and why (test-first)

Fixture and tests first (steps 1-2), code after (steps 3-4), docs last, all in
one Codex run. The coordinator then proves in `mktemp` copies that the new
tests fail against main's `bin/nixarchy-pkg` (step 5) and commits tests and fix
separately (step 6). Baseline on main: 49 `FAIL`, all in "fixture options"
(not this change; the same 49 must remain, no more).

## Steps

### 0. Coordinator: baseline

`git status` clean except the plan-approval commits. Record
`bash tests/adapter.sh </dev/null | tail -3`, the `FAIL` list (49 rows, all in
"fixture options") and `shellcheck bin/nixarchy-pkg tests/adapter.sh` (clean).
Hand Codex a clean tree.

### 1. Fixture (`tests/fixtures/home-seed.nix`, `tests/fixtures/apply-1820.sh`) -- codex

a. Create `tests/fixtures/home-seed.nix`:
`cp -L /etc/nixarchy/home-template.nix tests/fixtures/home-seed.nix &&
chmod 644 tests/fixtures/home-seed.nix`. Content must be exactly (5 lines):

```
{ pkgs, pkgsOther, ... }:
{
  home.packages = with pkgs; [  #@pkgs-begin
  ];  #@pkgs-end
}
```

b. `apply-1820.sh`, anchor (in `home_plan_arm`):
`[ -r "${NIXARCHY_HOME_TEMPLATE:?}" ] || { err_json "nixarchy-apply: cannot read the home seed"; return 1; }`
followed by `classify_home "$NIXARCHY_HOME_TEMPLATE"`. Replace both
`NIXARCHY_HOME_TEMPLATE` with `NIXARCHY_FAKE_SEED` (keep `:?`). In the header
comment (line 2-6, ends `(the arm is the contract in spec/...)`), add one line:
`# The seed it classifies against comes from NIXARCHY_FAKE_SEED (tests/fixtures/home-seed.nix).`

Check: `cmp -s tests/fixtures/home-seed.nix /etc/nixarchy/home-template.nix`
exits 0 (where the file exists); `grep -c NIXARCHY_HOME_TEMPLATE
tests/fixtures/apply-1820.sh` prints 0.
Traps: `/etc/nixarchy/home-template.nix` is a symlink into `/etc/static`, mode
444 after copy, hence `cp -L` and `chmod`; the edit is outside the verbatim
block (`select_home_src` .. `home_decide`) so the drift row at `blk103` is
untouched; do not stage.

### 2. Tests (`tests/adapter.sh`, "home owner (#103)") -- codex

All anchors in the section starting `echo "home owner (#103)"`.

a. **Drift row.** Directly before the line `A103=$O62/a103; export A103`, add:

```
if [ -r "$TEMPLATES/home-template.nix" ]; then
  check "fixture's home seed equals the installed home template" cmp -s "$HERE/tests/fixtures/home-seed.nix" "$TEMPLATES/home-template.nix"
else
  echo "  skip  home seed drift (no installed home template here)"
fi
```

b. **Seed variable.** In `own103()` add
`NIXARCHY_FAKE_SEED="$HERE/tests/fixtures/home-seed.nix"` to the `env ...`
assignments (next to `NIXARCHY_FLAKE=`); in `race103()` likewise (next to
`NIXARCHY_HOME_TEMPLATE=`). Leave `NIXARCHY_HOME_TEMPLATE` as it is: it is the
plugin's apps template, so the plugin still reads its own template while the
fake reads its own seed.

c. **`scene103`.** In the `seed)` case, change the copy source from
`home-apps-template.nix` to `home-seed.nix`.

d. **`tplguard`.** Delete the block from `mkdir -p "$A103/tplguard"` through
`chmod +x "$A103/tplguard/nixarchy-apply"`. Change the row that follows to

```
check "owner keep requires template" jq -e '.verdict == "unknown" and (.reason | contains("home template is not installed"))' <<<"$(TPL103="$O62/none.nix" own103 plan check)"
```

e. **New rows.** After the `for malformed in ...; done` loop (its last line is
`done` after the `malformed $malformed disables scope` check) and before
`scene103 "" edited` / `NIXARCHY_FAKE_PLAN=extra`, add:

```
# an unusable --home-plan answer is unknown even with no caller home.nix (#110)
scene103 alice absent
before=$(wc -l <"$O62/nix.calls")
check "unusable plan without caller home is unknown" jq -e '.verdict == "unknown" and (.reason | contains("no usable answer"))' <<<"$(NIXARCHY_FAKE_PLAN=exit2 NIX_MODE=capture own103 plan check)"
check "unusable plan avoids flake work" not grep -qvE ' config show ' <(sed -n "$((before + 1)),\$p" "$O62/nix.calls")
# one --home-plan call per command: a copy of the plan fake that counts them
mkdir -p "$A103/count"
sed '1a [ "${1-}" != --home-plan ] || echo x >>"$A103/count.log"' "$A103/plan/nixarchy-apply" >"$A103/count/nixarchy-apply"
chmod +x "$A103/count/nixarchy-apply"
plancalls() { : >"$A103/count.log"; NIX_MODE=pass own103 count "$@" >/dev/null; wc -l <"$A103/count.log"; }
for who in alice bob ""; do
  scene103 "$who" edited
  check "state makes one plan call (owner '$who')" test "$(plancalls state)" = 1
  check "search makes one plan call (owner '$who')" test "$(plancalls search git)" = 1
  check "pending makes one plan call (owner '$who')" test "$(plancalls pending)" = 1
done
scene103 "" edited
check "check makes two plan calls" test "$(plancalls check)" = 2
# an inherited HOME_PLAN must not stand in for the live answer
scene103 alice seed
check "inherited HOME_PLAN does not skip the owner check" jq -e '.ok == false and (.error | contains("belongs to alice"))' <<<"$(HOME_PLAN='{}' own103 plan pkg add --scope user git)"
```

Check (after step 3): `bash tests/adapter.sh </dev/null`: the 49 baseline `FAIL`s in "fixture options" that main already has remain
(compare the `FAIL` list, not the tail; the new rows all print `ok`).
Traps: `sed '1a ...'` inserts after the shebang line, outside the verbatim
block, and keeps the `--home-plan)` arm that `home_mode` greps, so the copy
still reads as `plan` (a shell wrapper would read as `none`); the `1a` text
needs the single quotes exactly as written (`$A103` expands in the fake at run
time, and `A103` is exported); `check` needs `NIX_MODE=pass` (with `capture`
the nix fake fails the evaluation and `check` answers before the second
snapshot: 1 call); `scene103 bob` is the caller-owned case (`CALLER103`
defaults to `bob`); keep `shellcheck` clean (quote everything; the `1a` line
may need `# shellcheck disable=SC2016` above it, as the file already does for
single-quoted scripts); do not edit existing rows other than those named; do
not stage.

### 3. Adapter (`bin/nixarchy-pkg`) -- codex

a. **Item 1.** Anchor
`if [ -f "$CHECKDIR/snap/home.nix" ]; then reason=$(jq -r .unavailable <<<"$plan"); check_answer; fi`
(inside `elif [ "$(jq -r 'has("unavailable")' <<<"$plan")" = true ]; then`).
Change the condition to
`if [ "$HOME_MODE" = plan ] || [ -f "$CHECKDIR/snap/home.nix" ]; then ...; fi`
(rest unchanged).

b. **`user_scope`.** Anchor `plan=$(home_plan)` (in the `case "$HOME_MODE" in`
`plan|blind)` arm, line ~419): `plan=${HOME_PLAN-$(home_plan)}`.

c. **`user_scope_note`.** Anchor
`if [ "$HOME_MODE" = plan ] && home_plan | jq -e '.owner == null and has("action")' >/dev/null 2>&1; then`:
replace `home_plan | jq` with `printf '%s' "${HOME_PLAN-$(home_plan)}" | jq`.

d. **`cmd_search`.** Directly before its `user_reason=$(user_scope)` line add
`HOME_PLAN=$(home_plan)`. Same in **`cmd_state`**, before its
`user_reason=$(user_scope)`.

e. **Unset.** Directly after `set -euo pipefail` (top of the script; the next
line is `umask 077`) add `unset HOME_PLAN`.

f. **Item 4 comment.** Directly above `# snapshot_selection DIR -- cp -L every existing part ...`
add (two lines; the anchor is the full line
`# snapshot_selection DIR -- cp -L every existing part to DIR/<p>.nix and draft to DIR/packages/.`):

```
# shortcut: apply reads the live home.nix, the snapshot copy is earlier, so an edit between them can give a
# wrong refuse that check answers before the probe; the panel drops it as stale, upgrade if that stops being enough.
```

Check: `shellcheck bin/nixarchy-pkg` clean; `grep -c 'HOME_PLAN' bin/nixarchy-pkg`
prints 5 (`unset`, `user_scope`, `user_scope_note`, `cmd_search`, `cmd_state`;
it is 0 now); `bash tests/adapter.sh </dev/null` FAIL list equals the 49 baseline rows.
Traps: `HOME_PLAN=$(home_plan)` is a plain assignment, safe under `set -e`
because `home_plan` ends in `jq -nc` or a bare `return`; set it in the command's
own shell, not inside a `$(...)`, or the subshells will not see it; do not
touch `scope_args` or `snapshot_selection`'s own `home_plan` calls; do not
change `blind` behaviour; do not add a `check` that reads `HOME_PLAN`.

### 4. Manual (`docs/manual/packages.md`, `docs/manual/options.md`) -- codex

Both files, section `## User scope`, the sentence ending
``and `check` `unknown` when you have a `home.nix`.`` becomes
``and `check` `unknown` when you have a `home.nix` (or, with any nixarchy that has `--home-plan`, when its answer is unusable).``

Check: `grep -c 'when its answer is unusable' docs/manual/packages.md docs/manual/options.md`
prints 1 for each. Traps: edit those two sentences only; keep backtick style;
do not stage.

### 5. Coordinator: proofs (`mktemp` copies only)

Every experiment: `d=$(mktemp -d); cp -a <tree> "$d/t"; ( cd "$d/t" || exit 1; ... )`.
Nix builds of a mutated copy use `path:$d/t#attr`, never `.#` (a plain `.#`
build of a `cp -a` copy can silently build the unmutated tree). Run
`bash tests/adapter.sh </dev/null` and diff each `FAIL` list against the
49-row baseline.

a. **Fails on main.** New tests and fixtures with `bin/nixarchy-pkg` from
`git show main:bin/nixarchy-pkg`: new `FAIL` rows are exactly "unusable plan
without caller home is unknown", "unusable plan avoids flake work" (main falls
through to the flake evaluation and logs it), `state`/`search makes one plan call` for
owner `bob` and for `""` (4 rows), nothing else.
b. **One piece reverted at a time** (new rows added to the baseline):

| Reverted piece | New `FAIL` rows |
|---|---|
| the `unset HOME_PLAN` line only | "inherited HOME_PLAN does not skip the owner check" |
| item 1 condition only | "unusable plan without caller home is unknown" and "unusable plan avoids flake work" |
| `HOME_PLAN=` lines only (cmd_search, cmd_state) | the unowned and `bob` `state`/`search` one-call rows |
| the fake's `apply-1820.sh` at main (no `NIXARCHY_FAKE_SEED`) | 11 rows: `keep imports owner`, `keep uses flake home`, `owner keep requires template`, `flake home changes fingerprint`, both `supersedes` rows, both `racing` rows, `host layout` x2, `unowned seed renders stub` |

The `alice` count rows and `check makes two plan calls` pass on main: they
guard the other-owner early return (1 call) and the race probe (2 calls).
c. **Mutations (copies only).** Item-1 condition made `true` (blind too):
"blind without caller home renders stub" fails. Append a newline to
`home-seed.nix`: only the drift row fails. Delete one `HOME_PLAN=` line: that
command's unowned count row fails. Make `user_scope_note` call `home_plan`
unconditionally again: the unowned `state` and `search` rows fail.
d. **With the whole change:** same 49 baseline `FAIL` rows, no more;
`shellcheck bin/nixarchy-pkg tests/adapter.sh` clean; `git diff --stat` shows
only the files named in steps 1-4 and `plan/`, `spec/`, `intent/`.
e. `nix flake check` green (shellcheck on `bin/nixarchy-pkg`,
`tests/adapter.sh`), run on the committed tree.
f. On this host: the seed drift row and the existing `fixture's home_decide
block equals the installed apply's` row both run (no `skip`) and pass; if the
installed apply is older and the second skips, say so in the PR.

### 6. Coordinator: commits

Plan approval is its own commit (`docs(plan): approve 2026-11-17-110-home-plan-followups (#110)`)
before step 1; intent and spec approvals are theirs already or are committed
first, each alone. Commit 1 (tests): `tests/fixtures/home-seed.nix`,
`tests/fixtures/apply-1820.sh`, `tests/adapter.sh`,
`test(home): the fake reads a real seed, and plan calls and unusable answers are counted (#110)`.
Commit 2 (fix): `bin/nixarchy-pkg`, `docs/manual/packages.md`,
`docs/manual/options.md`,
`fix(home): check says unknown after an unusable plan; state and search ask apply once (#110)`.
Both with the attribution trailers.

### 7. Reviews

Fresh `model: "opus"` agent given only this plan path and `git diff main`;
read-only Codex and agy via `second-opinion`. Findings classified confirmed,
refuted or unverified; confirmed ones fixed (a deviation updates `plan/` in the
same commit as the code); their output approves nothing.

### 8. Coordinator: live check (microVM, not razer)

In a `nixarchy-desktop` guest whose `nixarchy-apply` is the real one from
nixarchy main (it has `--home-plan`), inside the guest only: with an unowned
host, `strace -f -e trace=execve -s 200 -o log nixarchy-pkg state` then count only
the successful execs of apply itself,
`grep 'execve(".*nixarchy-apply".*--home-plan' log | grep -vc ENOENT`, prints 1
(a bare `grep -c -- --home-plan` also counts the `timeout` launch and failed
PATH lookups, `home_plan` runs `timeout 10 nixarchy-apply --home-plan`); the same for `search git`. A guest
apply whose `--home-plan` exits 2 (keep apply's `HOMEPLAN` marker, or
`home_mode` reads it as `none`) gives `check` `unknown` with no `home.nix`.
Never restart the Omarchy shell from the agent; nothing runs on razer.

### 9. Coordinator: PR

Links intent, spec and this plan, cites #110, says Codex did steps 1-4, lists
the failing-on-main rows from step 5a, the live-check result (or that it did
not run), and the reviews with their classified findings.

## Tests

- `bash tests/adapter.sh </dev/null`: the 49 baseline `FAIL` rows and no more;
  every new row prints `ok`.
- `shellcheck bin/nixarchy-pkg tests/adapter.sh` clean.
- `nix flake check` green.
- Proof of failure on main, the four single reverts and the four mutations: step 5.

## Left as is

- **Item 4.** apply reads the live `home.nix`; the plugin's snapshot is
  earlier, so an edit between them can give a wrong `refuse` that `check`
  answers before the probe. Documented by the comment above
  `snapshot_selection`; the panel drops the answer as stale. Fixing it would tie
  the plugin to apply's `srcdir` or add an up to 10 s call to every failing
  `check`.
- `state` now spends one `--home-plan` call before `user_scope` returns the
  missing-template reason on a host with no template (up to 10 s if apply
  hangs there). Accepted.

## Rollback

Plain edits to six files and a new fixture, no state: `git revert` the fix
commit (the new count and `unknown` rows then fail on main's adapter, so revert
the test commit with it). Nothing is written outside the worktree; no version
bump to undo.
