---
status: draft
issue: 110
author: olafkfreund
---

# Intent: follow-ups from #103's `--home-plan` review

> Every `file:line` below was read on this branch (main at `08be59b`) and on
> `origin/main` of nixarchy (`52b0943d`, which holds #1829) on 2026-11-17.
> Paths are in this repo unless prefixed `nixarchy:` (olafkfreund/nixarchy).
> Counts and behaviours marked "measured" come from runs of
> `tests/adapter.sh` in `mktemp` copies of this branch with a log line added
> to `home_plan`; nothing in the checkout was edited.

## Problem

Four low findings from #103's review (PR #107), recorded in
`plan/2026-11-17-103-follow-home-owner.md:835-839` ("Left as is") and in
`spec/2026-11-17-103-follow-home-owner.md:466-474`. Real
`nixarchy-apply --home-plan` now exists (nixarchy #1829), so each can be
fixed against it. All four hold on today's code; none is a regression.

1. **A malformed answer can make `check` evaluate the wrong file.**
   `home_plan` turns a timeout, a bad exit or a bad shape into
   `{unavailable: ...}` (`bin/nixarchy-pkg:403-406`). `cmd_check` answers
   `unknown` for that only when the caller has a `home.nix`
   (`:2517-2518`, `[ -f "$CHECKDIR/snap/home.nix" ]`); without one it falls
   through with `render_user=""` and renders the plain stub (`:2605-2607`
   is skipped). Measured on a scene with owner `alice` and no caller
   `home.nix`: with `NIXARCHY_FAKE_PLAN=exit2` the check rendered a
   `generated.nix` with no `home-manager.users` line; with a good plan the
   same scene rendered `home-manager.users."alice"`. Real apply would
   `keep` and import the owner, so `evaluates` there would speak for a file
   apply never writes. Only `plan` mode is in scope: `blind` has no plan
   command by design, and "caller with no `home.nix` gets the stub" is the
   recorded interim gap of #103's Decision 3 (`spec:461-465`), pinned by
   `tests/adapter.sh:3041` (`blind without caller home renders stub`).
2. **`--home-plan` runs more than once per command.** Measured, on a host
   where the caller may use user scope (owner is the caller, or unowned):
   - `state`: 2 calls (`user_scope` `:419`, `user_scope_note` `:453`);
   - `search`: 2 calls, the same pair (`:682-683`; the issue names only
     `state`, but `cmd_search` has the identical two lines);
   - `check`: 2 calls (`snapshot_selection` `:1963`, from `:2503` and
     `:2645`); `pending`: 1 (`:2095`).
   The issue's "a hung apply makes `state` take about 20 s" does not hold:
   when the answer is `unavailable`, `error` or names another owner,
   `user_scope` returns a reason (`:419-422`) and the note is skipped
   (`:683`, `:2777`), so a hang costs one 10 s timeout (`:387`), not two.
   The second call happens only after a good answer, so the cost it adds is
   one extra `nixarchy-apply` process (a mktemp, a copy, a `cmp`) per
   `state` and `search`, not a hang. The two `check` calls are not a defect: the second snapshot
   is the race probe that marks a result `superseded` (`:2645-2649`), so it
   must read live. Only `state` and `search` double up for no reason.
3. **The test fake checks "seed" against the wrong template.**
   `tests/fixtures/apply-1820.sh:110-111` runs
   `classify_home "$NIXARCHY_HOME_TEMPLATE"`. In the tests that variable is
   `tests/fixtures/home-apps-template.nix` (`tests/adapter.sh:2969`), the
   plugin's apps template with `@USER@`/`@IMPORTS@`. Real apply compares
   with `${homeTemplate}` (`nixarchy:modules/apps.nix:4791`, `:5004`), which
   is the `nixarchy-home.nix` text at `:400-406`
   (`{ pkgs, pkgsOther, ... }: { home.packages = with pkgs; [ #@pkgs-begin ]; #@pkgs-end }`)
   and is installed as `/etc/nixarchy/home-template.nix` (`:1675`). Measured:
   a caller `home.nix` equal to the real seed text makes the fake answer
   `state:"edited", action:"claim"`; real apply says `seed`. So row 5(i)
   works only because `scene103 seed` copies the apps template
   (`tests/adapter.sh:2974`), and `owner keep requires template` needs the
   test-only `tplguard` wrapper (`:3004-3013`) to give the fake a template
   while the plugin sees a missing one. The plugin is unaffected; only the
   fake differs from apply. The `select_home_src`..`home_decide` block that
   the drift test diffs against the installed apply (`:2948-2951`) is not
   involved: line 111 is outside it.
4. **Snapshot and plan read `home.nix` at different moments.**
   `snapshot_selection` copies the caller's `home.nix` (`:1951-1960`), then
   `home_plan` makes apply read the live file (`:1963`). Measured with a
   wrapper that edits `home.nix` just before `--home-plan` answers
   (owner `alice`, caller's file `seed` then `edited`): `check` answered
   `fails` (apply's `refuse`) at `:2515-2516`, before the second snapshot
   can mark it `superseded`, and its fingerprint differed from the next
   `pending`'s. The panel then drops the stale result
   (`PkgModel.qml:628-629`), so it heals on its own. #103's spec already
   names the family: the failure answers return before the second snapshot
   "for every part" and moving the comparison "is out of this issue"
   (`spec:466-474`).

## Proposed outcome

- In `plan` mode, a plan answer of `unavailable` makes `check` answer
  `unknown` with apply's reason whether or not the caller has a `home.nix`.
  `blind`, `legacy` and `none` are unchanged.
- `state` and `search` call `--home-plan` once. `check` keeps two (snapshot
  and probe); `pending` one. `state` and `search` start one `nixarchy-apply` process less.
- The fake classifies "seed" against the real seed text, in the tests and
  in `scene103`; `tplguard` is gone and its row calls the plugin directly.
  A drift check ties the new seed fixture to `/etc/nixarchy/home-template.nix`
  when that file exists.
- Item 4 is left as behaviour, with a one-line `shortcut:` comment at
  `snapshot_selection` naming the limit and its self-recovery, and a line in
  the plan's "Left as is".

## Affected users and systems

- Anyone on a nixarchy with `--home-plan`: `check` after a failing or
  timed-out plan call, and the speed of `state`/`search` when apply hangs.
- Files: `bin/nixarchy-pkg` (`:2517-2518`; `state`/`search` call sites
  `:682`, `:2776`; `user_scope` `:419`, `user_scope_note` `:453`;
  a comment at `:1951`), `tests/fixtures/apply-1820.sh` (`:110-111`),
  `tests/fixtures/home-seed.nix` (new), `tests/adapter.sh` (`scene103`
  `:2970-2979`, `own103`/`race103` env `:2969`, `:3090`, `tplguard`
  `:3004-3013`, malformed rows `:3030-3034`, drift check `:2948-2953`), and
  the "older nixarchy" sentence in `docs/manual/packages.md:126` and
  `docs/manual/options.md:127` ("`check` `unknown` when you have a
  `home.nix`" becomes "or when `--home-plan` gives no usable answer").
- **Not touched:** the verbatim block of the fake, `home_plan`'s
  validator, `snapshot_selection`'s behaviour, `PkgModel.qml`, the
  writers, nixarchy itself.

## Constraints

- No new dependency; `check` stays evaluation only, user scope stays a
  viewer of apply's answer. The plugin never decides ownership itself.
- Do not weaken #103's rows: `blind without caller home renders stub`
  (`:3041`), the ten `malformed` rows (`:3030-3034`) and
  `owner keep requires template` (`:3013`) keep passing, the last one
  without `tplguard`.
- The JSON contract does not change (`docs/manual/from-a-terminal.md`);
  `check` already has `unknown` with a `reason`.
- Offline checks run in `mktemp` copies. The installed apply here has
  `--home-plan` (4 matches) and the drift test passes against it, so the
  fixed fake can be compared with the real arm on this host. No deploy,
  no host change.
- Baseline on this branch: `tests/adapter.sh` has 49 `FAIL` rows, all in
  the "fixture options" section (`t.bool ... t.attrs`, refusals), none in
  "home owner (#103)". They are not part of this issue; the change must
  not add to them.

## Open questions

1. **Item 1: `unknown` or `fails` for a malformed answer in `plan` mode,
   and what about `blind`?**
   Recommended: **`unknown`, `plan` mode only.** `fails` says the flake is
   wrong; here the plugin cannot tell what apply would render, so
   `unknown` is the honest verdict and already what the caller-has-a-file
   case says. One condition changes (`[ "$HOME_MODE" = plan ] || [ -f
   ... ]` at `:2518`); the reason text is unchanged. Leave `blind` alone:
   its "cannot say who owns" answer is permanent, not an error, and
   #103 accepted the stub for it (Decision 3, row `:3041`). Revisit when a
   `blind` apply stops being a supported case.
2. **Item 2: how to call `--home-plan` once per command?**
   Recommended: **a global `HOME_PLAN`, set once in `cmd_state` and
   `cmd_search` before `user_scope`; `user_scope` and `user_scope_note`
   read `plan=${HOME_PLAN-$(home_plan)}`.** Not a cache inside
   `home_plan`: `user_scope` is called as `reason=$(user_scope)` and the
   note as `$(user_scope_note)`, two subshells, so a variable set inside
   one is lost to the other (the reason the call is repeated today). The
   `${var-$(cmd)}` form runs `home_plan` only when `HOME_PLAN` is unset, so
   `scope_args` (`:473`, the writers) keeps its single fresh call.
   Do not cache in `check`/`pending`: the second snapshot must read live.
   Value: small (one process, no hang; see item 2), so this is the
   smallest change, not a fix for a slowness. Cost: on a host with a missing
   template, `user_scope` used to return before calling apply; now `state`
   makes one call first (10 s worst case if apply hangs there), accepted
   rather than adding a guard ahead of the call. If that trade is not
   wanted, the alternative is to close item 2 as "not needed". Include `search` (same two lines); say so in
   the PR since the issue lists only `state` and `check`.
3. **Item 3: fix the fake's seed template now and drop `tplguard`?**
   Recommended: **yes, now.** Add `tests/fixtures/home-seed.nix` (the
   `homeTemplate` text, 5 lines); the fake reads it through a
   `NIXARCHY_FAKE_SEED` variable that `own103` and `race103` export (the
   fake is copied into `$A103/plan/`, so it cannot find a sibling file);
   `scene103 seed` copies the same file; delete `tplguard` and call
   `TPL103=... own103 plan check` for the template row. Add a drift check
   `cmp -s tests/fixtures/home-seed.nix /etc/nixarchy/home-template.nix`,
   skipped when that file is absent, like the existing one (`:2948-2953`;
   on this host the two files match). Cheaper alternatives (inline the
   text in the fake with `printf`) still need the same text in `scene103`,
   so one shared file is smaller.
4. **Item 4: fix the snapshot race or document it?**
   Recommended: **document, do not fix.** It heals on its own (measured;
   the panel discards a result whose fingerprint no longer matches
   `pending`), it needs an edit of `home.nix` inside a window of a few
   milliseconds, and #103's spec already accepted the whole class
   (`spec:466-474`). Both real fixes cost more than the defect: pointing
   apply at the snapshot (`XDG_CONFIG_HOME` for the call) ties the plugin
   to apply's `srcdir` internals, and probing before the failure answers
   adds an apply call, up to 10 s, to every failing `check`. A
   `shortcut:` comment at `snapshot_selection` names the limit; no test.
5. **Tests to add.**
   Recommended: three small rows, each failing on the old code.
   (i) owner `alice`, no caller `home.nix`, `NIXARCHY_FAKE_PLAN=exit2`:
   `check` is `unknown` with `no usable answer`, and no `nix` evaluation
   ran (the `nix.calls` check used by `refuse avoids flake work`, `:3017`).
   (ii) a counting wrapper (like the measuring one): `state` and `search`
   make exactly one `--home-plan` call on an owned and on an unowned
   scene, `check` two, `pending` one; and a hanging wrapper is not needed,
   the count is the evidence. (iii) a caller `home.nix` equal to the real
   seed gives `state:"seed"` from the fake, and `owner keep` renders the
   owner's import (the existing keep rows, now through the real seed).
   Not recommended: a timing test with a real 10 s hang (slow, flaky).
