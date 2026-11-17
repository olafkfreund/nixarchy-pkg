---
status: draft
issue: 110
intent: intent/2026-11-17-110-home-plan-followups.md
---

# Spec: follow-ups from #103's `--home-plan` review

## Design

Line numbers are this worktree (main at 08be59b plus the approved intent).
The intent's five questions were approved with the recommended answer and are
settled: (1) `unknown`, `plan` mode only; (2) a global `HOME_PLAN` read with
`${HOME_PLAN-$(home_plan)}`, set in `cmd_state` and `cmd_search`; (3) a real
seed fixture, `tplguard` gone, a drift row; (4) item 4 documented, not fixed;
(5) three small rows. Everything below was run in `mktemp` copies of this
tree (the intent's file edits applied with sed, the rows below added,
`tests/adapter.sh` run whole). Baseline on main: 49 `FAIL`, all in "fixture
options".

### 1. `check` after an unusable plan answer (`bin/nixarchy-pkg:2518`)

One condition:

```
-        if [ -f "$CHECKDIR/snap/home.nix" ]; then reason=$(jq -r .unavailable <<<"$plan"); check_answer; fi
+        if [ "$HOME_MODE" = plan ] || [ -f "$CHECKDIR/snap/home.nix" ]; then reason=$(jq -r .unavailable <<<"$plan"); check_answer; fi
```

`HOME_MODE` is already set by `home_mode` at `:2507`. `blind` still falls
through to the stub when the caller has no `home.nix` (its `unavailable` is
the permanent "cannot say who owns", pinned by `tests/adapter.sh:3041`).
`legacy` and `none` never produce `unavailable`. The reason text is
unchanged.

### 2. One `--home-plan` call in `state` and `search`

```
 user_scope()      :419   plan=$(home_plan)                 -> plan=${HOME_PLAN-$(home_plan)}
 user_scope_note() :453   ... && home_plan | jq ...         -> ... && printf '%s' "${HOME_PLAN-$(home_plan)}" | jq ...
 cmd_search        :682   (before user_reason=$(user_scope)) +  HOME_PLAN=$(home_plan)
 cmd_state         :2776  (before user_reason=$(user_scope)) +  HOME_PLAN=$(home_plan)
 top of script     :47    after set -euo pipefail           +  unset HOME_PLAN
```

The `unset` matters: `${HOME_PLAN-...}` is suppressed by any inherited value,
even an empty one, so an exported `HOME_PLAN` would hand a writer a plan
apply never gave and skip its live ownership check (Codex review, confirmed
by reading `scope_args` `:473`). `HOME_PLAN=$(home_plan)` was run under
`set -euo pipefail` in all four modes and cannot fail: `home_plan` ends in
`jq -nc` or a bare `return`.
`${VAR-word}` runs `home_plan` only when `HOME_PLAN` is unset, so `scope_args`
(`:473`, the writers) and `snapshot_selection` (`:1963`, `check`/`pending`)
still make their own fresh call: `check` keeps two (snapshot and race probe),
`pending` one. `HOME_PLAN` is set in the command's own shell, before the two
`$(...)` subshells, so both read it. In `legacy`/`none`/`blind-without-plan`
modes `home_plan` prints nothing or the blind constant; `user_scope` only
reads it for `plan|blind` and the note only for `plan`, so an empty value
changes nothing.

Known trade (intent Q2, accepted): on a host with no apply `--home-plan`
support nothing changes; on a host with a missing home template `state` now
makes one call before `user_scope` returns the template reason. The count
below shows the saving is real only for an unowned or own-owned host (the
other-owner case already returned before the note, so it was one call).

### 3. The fake classifies "seed" against the real seed

- `tests/fixtures/home-seed.nix` (new): a byte copy of
  `/etc/nixarchy/home-template.nix` (nixarchy's `homeTemplate`, 5 lines, here
  `cmp`-identical). Mode 644; the copy from `/etc` is 444 and must be
  `chmod`ed.
- `tests/fixtures/apply-1820.sh:110-111`: `NIXARCHY_HOME_TEMPLATE` becomes
  `NIXARCHY_FAKE_SEED` in the readability check and in
  `classify_home "$NIXARCHY_FAKE_SEED"`. Outside the verbatim block
  (`select_home_src`..`home_decide`), so the drift test is unaffected. The
  header comment (`:95`) gains one line saying the seed comes from
  `NIXARCHY_FAKE_SEED`.
- `tests/adapter.sh`: `own103` (`:2969`) and `race103` (`:3090`) export
  `NIXARCHY_FAKE_SEED="$HERE/tests/fixtures/home-seed.nix"`; `scene103 seed`
  (`:2974`) copies `home-seed.nix`; the `tplguard` block (`:3004-3013`) is
  deleted and its row calls `TPL103="$O62/none.nix" own103 plan check`.
  `NIXARCHY_HOME_TEMPLATE` stays the plugin's apps template, so the plugin
  still sees a missing template while the fake reads its own seed.
- Drift row, just before `A103=` (`:2955`), skipped when absent like the
  existing one: `cmp -s tests/fixtures/home-seed.nix
  /etc/nixarchy/home-template.nix` (it reads `$TEMPLATES`, the variable the
  rest of the file uses).

### 4. Item 4: documented only

A comment above `snapshot_selection` (`:1950`):

```
# shortcut: apply reads the live home.nix, the snapshot copy is earlier, so an edit between them can give a
# wrong refuse that check answers before the probe; the panel drops it as stale, upgrade if that stops being enough.
```

and one line in the plan's "Left as is" (the plan stage writes it). No test.

### 5. Docs

`docs/manual/packages.md:126` and `docs/manual/options.md:127`, the same
sentence in both: "and `check` `unknown` when you have a `home.nix`" becomes
"and `check` `unknown` when you have a `home.nix` (or, with any nixarchy that
has `--home-plan`, when its answer is unusable)".

### 6. Tests (new rows in the "home owner (#103)" section)

After the malformed loop (`:3030-3034`), before the `extra` row:

1. Owner `alice`, no caller `home.nix` (`scene103 alice absent`),
   `NIXARCHY_FAKE_PLAN=exit2 NIX_MODE=capture`: `check` is `unknown` with
   `no usable answer`, and the lines `nix.calls` gained are only
   ` config show ` (same shape as `refuse avoids flake work`, `:3017`).
2. A counting fake: `sed '1a [ "${1-}" != --home-plan ] || echo x >>"$A103/count.log"'`
   of the plan fake into `$A103/count/` (the line is outside the verbatim
   block, and the file keeps the `HOMEPLAN` marker that `home_mode` greps, so
   it still reads as `plan`; a shell wrapper would not). `plancalls CMD`
   truncates the log, runs `NIX_MODE=pass own103 count CMD`, prints the line
   count. Rows: `state` = 1 and `search git` = 1 and `pending` = 1 for owner
   `alice` (another user), `bob` (the caller; the caller-owned case the intent
   names) and unowned; `check` = 2 on an unowned edited scene. `check`
   needs `NIX_MODE=pass`: with `capture` the nix fake fails the evaluation
   and `check` answers before the second snapshot (1 call).
3. `HOME_PLAN='{}' own103 plan pkg add --scope user git` on `scene103 alice
   seed` is still refused with `belongs to alice` (guards the `unset`).
4. Row (iii) needs no new row: `scene103 seed` now copies the real seed, so
   the existing `keep renders owner`, `keep imports owner`, `keep uses flake
   home`, `keep does not use caller home`, `pending and check agree`, and the
   race rows only pass when the fake says `seed`.

### Which tests must fail on main

Measured: new tests and fixtures with one piece of the change reverted at a
time; every run's `FAIL` list diffed against the 49-row baseline.

| Reverted piece | New `FAIL` rows |
|---|---|
| all of `bin/nixarchy-pkg` | row 1 (both), `state` and `search` 1 call for `bob` and for unowned (4) |
| the `unset HOME_PLAN` line only | the inherited-`HOME_PLAN` row |
| item 1 condition only | row 1 (both) |
| item 2 `HOME_PLAN=` lines only | `state`/`search` 1 call (unowned; `bob` likewise on main) |
| fake (`apply-1820.sh` at main) | 11: `keep imports owner`, `keep uses flake home`, `owner keep requires template`, `flake home changes fingerprint`, both `supersedes` rows, both `racing` rows, `host layout` x2, `unowned seed renders stub` |

With the whole change: the same 49 baseline rows, no more; shellcheck on
`bin/nixarchy-pkg` and `tests/adapter.sh` is clean.

The `alice` count rows and the `check` = 2 row pass on main: they guard that
the fix keeps the other-owner early return (1 call) and the race probe
(2 calls). The `bob` and unowned `state`/`search` rows are red there (main
calls twice).

### Mutation ideas (run in `mktemp` copies; build a mutated copy with
`path:$d#attr`, not `.#`)

- Make the item-1 condition `true` (blind too): `blind without caller home
  renders stub` fails (measured).
- Append a newline to `home-seed.nix`: only the drift row fails (measured;
  the file is still a valid seed, so this is what the drift row is for).
- Delete one `HOME_PLAN=` line: that command's unowned count row fails
  (measured by the `item2` run).
- Make `user_scope_note` call `home_plan` unconditionally again: the unowned
  `state` and `search` rows fail.

## Alternatives rejected

- **Cache inside `home_plan`.** `user_scope` and its note run in two
  subshells, so a variable set in one is lost to the other, which is why the
  call repeats.
- **Pass the plan as an argument** (`user_scope "$plan"`). Equivalent and no
  global; rejected only because the intent settled on `HOME_PLAN` and this
  file is the one place the writers' `scope_args` would also change
  signature. Cost of switching later: three call sites.
- **Cache in `check`/`pending`.** The second snapshot must read live.
- **`fails` for an unusable answer.** It says the flake is wrong; the plugin
  cannot tell (intent Q1).
- **Fix item 4** by pointing apply at the snapshot or probing before the
  failure answers: ties the plugin to apply's `srcdir` or adds an up to 10 s
  call to every failing `check` (intent Q4).
- **Inline the seed in the fake** with `printf`: `scene103` still needs the
  text, so one shared file is smaller (intent Q3).
- **A timing test with a real 10 s hang.** Slow, flaky; the count is the
  evidence.

## Review

Codex (read-only, 2026-11-17): no high findings, three medium and one low,
all confirmed and fixed above: the inherited `HOME_PLAN` (now `unset`, one
guard row), the missing caller-owned count case (`bob` rows, red on main),
the live count method (arguments traced; marker caveat), and two line
numbers (`:2507`, `:2955`). It checked in memory that `HOME_PLAN=$(home_plan)`
survives `set -euo pipefail` in all four modes and that the item-1 condition
leaves blind/legacy/none alone. Not verified by it: the baseline and the
mutation results (mine, above).

## Risks

- **An inherited `HOME_PLAN`** would skip the live check; the `unset` at
  startup and its row close it.
- **Stale `HOME_PLAN` within one command.** It is read for the scope reason
  and note only; the writers and `check`/`pending` make their own calls.
  A `home.nix` edit between the call and the reply is the same window as
  item 4.
- **`state` now spends one call earlier on a host with no template**, up to
  10 s if apply hangs there (intent Q2, accepted).
- **`home-seed.nix` can drift from nixarchy.** The drift row catches it on a
  host with `/etc/nixarchy/home-template.nix`; in the flake sandbox it is
  skipped, as the existing one is.
- **Item 1 changes a verdict**: a `plan` host with a failing apply and no
  caller `home.nix` went from a rendered stub (`evaluates`/`fails`) to
  `unknown`. That is the point; the panel already shows `unknown`.
- **Not run:** the live panel and a real hanging apply.

## Verification

1. `tests/adapter.sh`: no new `FAIL` against the 49-row baseline; the rows
   above fail on main as the table says.
2. `nix flake check` (`shellcheck` on `bin/nixarchy-pkg`,
   `tests/adapter.sh`).
3. On this host, with the installed apply: the seed drift row and the
   existing `home_decide` drift row both run and pass.
4. Live, in a `nixarchy-desktop` microVM (not razer): `nixarchy-pkg state`
   and `search git` on an unowned host make one `--home-plan` call, counted
   with `strace -f -e trace=execve -s 200 -o log` and `grep -c -- --home-plan`
   (the arguments show; a PATH wrapper would have to keep apply's `HOMEPLAN`
   marker or `home_mode` reads it as `none`); a guest apply whose
   `--home-plan` exits 2 (same marker caveat) gives `check` `unknown` with
   no `home.nix`.

## Decisions for the owner

1. **Item 2 as a global `HOME_PLAN`, or as an argument to `user_scope` /
   `user_scope_note`?** Both give one call. Recommended: the global (settled
   in the intent); the argument form is a three-call-site change if you
   prefer no global.
2. **The count rows use a sed-patched copy of the fake.** Recommended: yes;
   it keeps the `HOMEPLAN` marker, which a shell wrapper loses.
3. **The `alice` count rows and `check` = 2 pass on main.** Recommended: keep
   them as guards; the red rows are the unowned `state`/`search` ones and
   the unknown row.
4. **The docs sentence** (both manual pages) gains "(or, with any nixarchy
   that has `--home-plan`, when its answer is unusable)". Recommended: yes.
5. **The live check has not run.** Recommended: run it after the plan is
   approved; nothing in the design depends on it.
