---
status: approved
issue: 103
author: olafkfreund
---

# Intent: follow nixarchy's home owner: detect the home part again, and let check and user scope use apply's decision

## Problem

nixarchy merged #1820 (one home owner per host, closing its #1817). This
repo has not followed it. Line numbers below are nixarchy `origin/main`
(74000e98) for `modules/apps.nix`, and this repo at 16e9664 for
`bin/nixarchy-pkg`. Nothing here has been run on a host; the claims are from
reading both repos. The issue reports a microVM live check of #100 against
nixarchy 6b37fa9c, which this draft has not repeated.

**1. The home part is no longer detected, so everything built on #62 and #100 is dark.**

- `apply_has_home` (`bin/nixarchy-pkg:363-367`) is
  `grep -qE '^for part in .*\bhome\b'` on the installed `nixarchy-apply`.
- #1820 took `home` out of that loop. Before it (`ccf0f98b^`) the loop was
  `for part in apps services advanced flatsnap home; do`; now it is
  `for part in apps services advanced flatsnap; do`
  (`modules/apps.nix:4948`). The grep finds nothing on any nixarchy at or
  after 6b37fa9c.
- Consequences, all in this repo:
  - `user_scope()` (`:372-397`) returns "this nixarchy has no Home Manager
    part" first, so user scope is unavailable on every current nixarchy.
  - `snapshot_selection` (`:1897-1912`, skip at `:1901`) leaves `home.nix`
    out of the snapshot, so `cmd_check` never sees it. The same skip is in
    the pending-changes loop (`:2040`).
  - `cmd_check`'s template fill (`:2515-2520`, merged in #100) runs only when
    the snapshot has `home.nix` (`:2515`), so it never runs on a real host.
- The adapter tests do not notice: they fake `nixarchy-apply` as a script
  containing the old loop word (`tests/adapter.sh:2589`, `:2665`).

**2. Apply picks the home owner; `check` and user scope assume it is the caller.**

Apply reads the owner from the flake's generated `nixarchy-apps.nix`
(`read_owner`, `modules/apps.nix:4790`; `$dest` is
`$base/nixarchy-apps.nix`, `:4648`), classifies the caller's `home.nix`
against the seed (`snapshot_home` `:4763`, `classify_home` `:4775`;
`homeTemplate`, `:400`), and decides with `home_decide` (`:4810-4820`):

| owner | caller | caller's home.nix | decision | what apply does |
|---|---|---|---|---|
| none | any | edited | claim | renders for the caller, copies the caller's file |
| none | any | seed or absent | keep | writes the plain stub, no home import |
| O | O | seed or edited | copy | renders for O, copies the file |
| O | O | absent | keep | renders for O, copies nothing |
| O | C | seed or absent | keep | renders for O, copies nothing, flake's `home.nix` stays O's |
| O | C | edited | refuse | exits 1 before any write |

`render_user` is the caller for `claim` and `copy`, the owner for `keep`
(`:4938-4942`); the template is filled with it at `:5010-5011` and the plain
stub is written otherwise. `cmd_check` does neither: whenever the snapshot has
`home.nix` it fills the template for `$(id -un)` (`bin/nixarchy-pkg:2516-2518`)
and puts the caller's `home.nix` in its copy (the loop at `:2502`, over the flake's own `nixarchy/home.nix` that `:2494` copied). So for the
non-`claim`/`copy` rows:

- **keep with owner O** (O is not the caller): apply writes O's import and
  leaves O's `nixarchy/home.nix` in the flake. `check` evaluates the caller's
  import and the caller's file instead. It can fail on the template's
  assertions for the caller (for instance "no Home Manager configuration of
  their own") for a run apply completes, or pass for a file apply will never
  copy.
- **keep with no owner** (the unedited seed): apply writes the plain stub.
  `check` fills the template and adds the three assertions; it can report
  `fails` where apply succeeds.
- **refuse**: apply exits 1 with a message naming the owner. `check` can
  answer `evaluates`.

The pending-changes loop (`bin/nixarchy-pkg:2040`) has the same blind spot: it
compares the caller's `home.nix` with the flake's copy, which apply does not
update in the `keep` rows.

**3. User scope does not say who owns `home.nix`.**

`user_scope()` checks the apply, the template, the cache, Home Manager, the
user in `home-manager.users` and `useGlobalPkgs` (`:372-397`). It has no
owner. A non-owner who stages a user package edits `~/.config/nixarchy/home.nix`
(the file the nixarchy writers touch, `nixarchy-pkg-add` and friends); a later
apply either ignores it (`keep`, if the file is still the seed it never was
edited) or refuses (`edited`). Either way the panel offered a scope that does
not work for that user and said nothing up front.

**4. What apply exposes to a consumer today: nothing for this.**

- `nixarchy-apply` flags (`modules/apps.nix:4429-4453`): `--yes`,
  `--no-preview`, `--detach`, `--release-home`, `--status`, `--json`, `--log`,
  `--follow`, `--invocation`, `--expect-sha256`. There is no dry run and no
  flag that prints the home decision. `--json` is only valid with `--status`
  and carries `{state, result, exit, invocation}` (`:4536-4545`); the usage
  text calls it the stable contract (`:4461`).
- No state file records the decision or the owner. The owner exists only as
  the `home-manager.users."<x>".imports =` line in the flake's
  `nixarchy-apps.nix`.
- `/etc/nixarchy/home-template.nix` (the seed, `:1675`) and
  `/etc/nixarchy/home-apps-template.nix` (`:1676`) are installed; both pre-date
  #1820.
- nixarchy's #1817 intent, spec and plan (`intent|spec|plan/2026-11-16-1817-home-multiuser.md`
  on origin/main) say nothing about consumers: `grep -i` for `nixarchy-pkg`,
  `plugin`, `consumer` and `panel` finds no hit in any of the three. The
  contract nixarchy intended is the one for users of `nixarchy-apply` and the
  manual, not for another program. The spec's own verification uses
  extracted functions (`home_decide`, `read_owner`) as test seams, which a
  consumer cannot call.

## Proposed outcome

- The home part is detected again on a nixarchy before #1820 (loop word) and at
  or after it. User scope is available once the owner can be known: on a
  pre-#1820 host (the invoking user is the writer, as before), and on a
  current nixarchy once it can say who owns `home.nix` (question 2; until then
  user scope and `check` for a `home.nix` say so rather than guess). A host with neither (before #1815) stays as today: no user scope,
  `check` without a home import.
- For the same selection, caller and flake state, the `nixarchy-apps.nix` and
  `nixarchy/home.nix` that `check` evaluates are what apply would leave in the
  flake, for every row of the table above:
  - `claim`/`copy`: the template for the caller with the caller's `home.nix`
    (as #100 built);
  - `keep` with an owner: the template for the owner, and the flake's own
    `nixarchy/home.nix`, not the caller's;
  - `keep` without an owner: the plain stub with no home import; an existing
    `nixarchy/home.nix` in the flake is left alone, as apply leaves it (only
    `--release-home` removes it);
  - `refuse`: `check` answers `fails` with apply's refusal message, not
    `evaluates`.
- The decision comes from nixarchy, not from a second copy of `home_decide`
  in this repo (see question 2).
- User scope names the owner when it is someone else, and says what to do.
  When the caller owns the host, or no one does, it says so
  (a first edited apply claims it) and stays available.
- The panel's pending-changes list for `home.nix` does not show a change that
  apply will not make.
- The adapter tests fake the new nixarchy shape as well as the old one, so
  this regression cannot hide again.

## Affected users and systems

- Anyone using user scope (`--scope user`, the panel's user tabs) or `check`
  on a nixarchy with the home part: today on every current nixarchy it is
  switched off; after the detection fix it must be right on a host with more
  than one Home Manager user.
- Hosts with one Home Manager user: after detection, the `claim`/`copy` rows
  match #100's. The seed and absent rows still differ there (an unowned seed
  writes the plain stub; an owner with no file keeps their import), so a
  one-user host is not unchanged by this issue.
- Files in this repo: `bin/nixarchy-pkg` (`apply_has_home`, `user_scope`,
  `snapshot_selection`, the pending loop at `:2040`, `cmd_check`'s fill,
  `fingerprint`), `tests/adapter.sh` and `tests/fixtures/`, and the user-scope
  paragraphs of `docs/manual/options.md` and `docs/manual/packages.md`.
- nixarchy, if question 2 chooses to ask for the decision: one companion
  issue on `olafkfreund/nixarchy` (a read-only command in `nixarchy-apply`).
  This repo cannot land that part.

## Constraints

- No second copy of apply's logic that can drift unnoticed (carried over from
  #100). If the plugin cannot ask nixarchy, any copy needs a test that compares
  it with nixarchy's own text, and the intent says so rather than hiding it.
- Pre-#1820 hosts with the home part keep working. A host with no home part
  keeps behaving as today.
- `check` writes only inside its own temp copy; it reads the real flake and
  `~/.config/nixarchy` and changes neither.
- A read of the owner is a read of the real `$base/nixarchy-apps.nix`, not of
  `check`'s copy, which `check` overwrites. The pair `nixarchy-apps.nix` and
  `nixarchy/home.nix` must be taken from one moment: another user's apply can
  change the owner while `check` runs, so the owner belongs in `check`'s
  fingerprint (`superseded`) or the race stays open (question 6).
- Scope is a truthful read, not access control: this repo does not release,
  claim or hand over ownership. `nixarchy-apply --release-home` is nixarchy's
  command and stays there; the plugin may name it in a message.
- Live checks run in a `nixarchy-desktop` microVM, the owner's standing choice
  over razer. Guest-only shims are acceptable there to reproduce a state, but a
  shim that restores the old loop word proves nothing about detection and must
  not be the final check.

## Open questions

1. **How does the plugin detect the home part, and do pre-#1820 hosts stay
   supported?** Candidates: (a) keep the loop-word grep and add a second marker
   in the installed script that only #1820 and later have, such as
   `home_decide()` (`modules/apps.nix:4810`) or the `--release-home` usage line
   (`:4457`); (b) the existence of `/etc/nixarchy/home-apps-template.nix`
   (installed since #1815, so it also covers old and new); (c) a
   `nixarchy-apply --capabilities` (or a version file) that nixarchy would add.
   Recommended: (a), and yes, pre-#1820 stays supported. The loop-word grep
   stays as one alternative of a single `grep -E`, so a nixarchy before #1820
   needs no change; the marker covers the rest. It is the same kind of
   text read the plugin already does (`searched()`, `bin/nixarchy-pkg:357`), and costs one
   pattern. (b) is wrong as the only test: the template says nothing about
   which `nixarchy-apply` is installed, and #100's question 3 already decided that
   a missing template must not decide whether `home.nix` is in the snapshot. (c) is the
   right long-term shape but needs nixarchy to add it; fold it into the
   companion issue of question 2 and switch to it when it exists, keeping (a)
   as the fallback for older installs. The text grep is a heuristic: a rename
   of `home_decide` would break it silently, which is what happened to the loop
   word, so the adapter test must fake the real new shape (copied from nixarchy
   at a named commit) rather than a hand-written marker. Say if you would rather
   support only #1820 and later (drop the loop word): it simplifies the grep and
   costs nobody who updates nixarchy, but the plugin is pinned from nixarchy
   (`74000e98`, #1816), so a lagging host is plausible.

2. **Does the plugin re-implement `home_decide`, or does nixarchy expose the
   decision?** (a) re-implement: read `$base/nixarchy-apps.nix` with the same
   three `grep` rules as `read_owner`, `cmp` the caller's file with
   `/etc/nixarchy/home-template.nix`, and apply the table; (b) nixarchy adds a
   read-only `nixarchy-apply --home-plan [--json]` that runs the same
   `snapshot_home`, `classify_home`, `read_owner` and `home_decide`, takes no
   lock, changes nothing in the flake, the config or the applied records (a
   private temp snapshot is fine), and prints
   `{owner, caller, state, action, renderUser}` (and the refusal text), with
   exit 0 for every decision, `refuse` included, so the caller reads `action`.
   Recommended: (b), with a companion issue on nixarchy, because (a) is the
   second copy #100's constraint forbids, and the table above would change whenever
   `home_decide` does (it was rewritten once already, by #1820). Order of work: ask nixarchy for the plan command first; this repo's detection
   fix and owner-following ship together, because detection alone turns the
   wrong template and the wrong `home.nix` on for a non-owner (an owner Alice
   and a seeded Bob get a Bob import from `check` where apply keeps Alice's).
   When the installed nixarchy has the home part but no plan command (every
   nixarchy until the companion lands), the safe interim is: `check` answers
   `unknown` for a selection that has a `home.nix`, with the reason "this
   nixarchy cannot say who owns home.nix; update nixarchy", and user scope is
   unavailable with the same reason. That trades today's false `evaluates` for
   an honest `unknown`, at the price of user scope staying off until nixarchy
   ships the command. Say so if you prefer detection alone with a note (a
   wrong answer on multi-user hosts) or a small owner read here (the copy (a)
   avoids). The command must not take the apply lock, and a malformed owner
   state (`read_owner` fails, `modules/apps.nix:4794-4807`) must come back as
   an error the plugin can show, not as `action: keep`. Say if you would rather ship (a) with a drift
   test now: it is a day's work here against a wait on nixarchy, but the test
   can only compare against a nixarchy checkout, not against the installed
   apply, so it catches drift only in CI.

3. **What does user scope show when another user owns `home.nix`?** Per the
   table, a non-owner with the seed gets `keep` (their `home.nix` is not
   copied) and a non-owner with an edit gets `refuse`, so staging a user package
   can never take effect for them. Recommended: unavailable, with the reason
   `home.nix belongs to <owner>; ask <owner> to apply, or run nixarchy-apply
   --release-home to give the host up`, whatever state the caller's file is in
   (mirrors apply's refusal text, `:4934`). When the caller is the owner:
   available, no note. When no one owns it: available with the note "the first
   apply with an edited home.nix makes you the owner". `scope_args` refuses with
   the same reason (`die`, before any write), as it does for the other
   prerequisites. The plugin does not offer to release: that is a destructive
   host-wide write and stays a command the user runs. This reason comes from
   question 2's plan output; on a nixarchy without it, user scope shows
   question 2's interim reason instead.

4. **What does `check` do for each decision?** Recommended: `claim`/`copy` as
   #100; `keep` with an owner evaluates the flake's existing `nixarchy/home.nix`
   with the template filled for the owner, so `snapshot_selection` must not
   copy the caller's `home.nix` over it; `keep` with no owner writes the plain
   stub and no home import, leaving any flake `nixarchy/home.nix` as it is; `refuse` answers `fails` with apply's message and
   skips the evaluation (apply would stop before any write); a malformed owner
   state (duplicate import lines, an unparseable one, an invalid name: apply
   exits before `home_decide`, `:4794-4807`, `:4921`) answers `fails` with the
   same message and user scope shows it as the reason, never `evaluates`. Say if you want
   `refuse` to be `unknown` instead: `fails` is what a user sees as "this will
   not go through", and the other verdicts mean nix evaluated or could not.

5. **What does the pending-changes loop (`:2040`) do for `home.nix`?**
   Recommended: follow the same decision: for `keep` and `refuse` it reports no
   change for `home.nix`, since apply will not copy it. The alternative is to
   leave it comparing the caller's file, which shows a change apply will never
   make.

6. **Does the owner go into the fingerprint?** `fingerprint`
   (`bin/nixarchy-pkg:1915`) hashes the snapshot only, and `pending` computes
   the same value (`:2114`); the panel compares the two and turns a completed
   check into `superseded` when they differ (`PkgModel.qml:254`,
   `tests/qml/tst_pkgmodel.qml:473`). Another user's apply during a long `check`
   can change the owner and the flake's `home.nix` without moving it, so
   `check` would answer `evaluates` for a flake that no longer matches.
   Recommended: yes, and the same extra input goes into `pending`'s fingerprint
   (one function, both callers), so the panel's comparison stays equal; the QML
   tests and the fingerprint rows in `docs/manual/from-a-terminal.md` (`:119`,
   `:142`) are then in scope. The extra input is the plan output plus the
   flake's `nixarchy/home.nix`. Say no if you accept the race for the same
   reason #1817 does (concurrent applies are out of its scope).

7. **Detection test seam.** The adapter tests fake `nixarchy-apply` with
   `for part in ... home` (`tests/adapter.sh:2589`, `:2665`). Recommended: keep
   one case for the old shape and add the new shape as a script text copied from
   nixarchy `74000e98` (loop without `home`, `home_decide`, `--release-home`).
   If you would rather test against nixarchy's real script in CI, say so; the
   repo does not clone nixarchy today.
