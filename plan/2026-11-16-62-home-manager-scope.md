---
status: approved
issue: 62
spec: spec/2026-11-16-62-home-manager-scope.md
coders:
  1: codex   # DISCOVER string, `options refresh`: flock, setsid/timeout, private dir, atomic symlink publish -- small, tricky shell
  2: codex   # readers resolve the cache once (search, opt describe, reindex), staleness stamp -- same context as step 1
  3: coder   # slice-1 adapter tests with a stub nix: many cases, following DSTUB's pattern
  4: coder   # panel: optionsSource/Stale/Error, refresh after apply, footer, --scope from OptionForm, QML tests
  5: agy     # manual: where options come from, staleness limits -- bounded docs (fallback: coder)
  6: codex   # user_scope(), home.nix target, --scope on every write/read, `home` part in pins/check -- tricky plumbing
  7: coder   # slice-2 adapter tests against stub writers and a template copy
  8: coder   # panel: (scope, name) identity, user badge, add-in-user-scope key, disabled rows with reason, QML tests
  9: agy     # manual: user scope, its requirement on nixarchy, conflicts note (fallback: coder)
reviewers:
  - codex   # shell locking, publication and scope plumbing are where this goes wrong
  - agy     # independent read of each PR's diff against this plan
---

# Plan: user scope (Home Manager) beside system scope, and options from the user's own flake

## Decisions (from the approved intent and spec)

1. **Two PRs.** PR 1 (slice 1, steps 1-5) discovers options from the user's
   flake. PR 2 (slice 2, steps 6-9) adds user scope. A companion issue in
   nixarchy (section C, below) is filed by the lead before PR 2.
2. **Discovery** is one pure `nix eval` of
   `$flake#nixosConfigurations."$host"` with `--apply "$DISCOVER"`, as follows:
   - flags: `--json --no-write-lock-file`, no `--impure`, no `getFlake`;
   - run under `setsid timeout 300`, with `9>&- 8>&-` on the child;
   - `flake=${NIXARCHY_FLAKE:-/etc/nixos}` and `host=$(uname -n)`, as in
     `cmd_check`;
   - `DISCOVER` is the Nix function in the spec, section A1, verbatim, held as
     a readonly string. `@USER@` is replaced only after `$user` (`id -un`)
     matches `^[a-z_][a-z0-9_-]*$`.
3. **`nixarchy-pkg options refresh`** is a read: no write lock and no
   `begin_write`.
   - It takes `flock -n` on `$STATE_DIR/pkg-options.lock`. When that is
     busy it answers `{ok:false, error:"options are already being read"}`.
   - It refuses while `$TXN/open` exists.
   - It works in a private `$STATE_DIR/pkg-options.XXXXXX` (an `OPTSDIR`
     global, which `on_exit` removes).
   - It builds the cache into `$CACHE_DIR/options.d/<epoch>.<pid>/`, then
     publishes it by
     `ln -s <dir> $CACHE_DIR/options.tmp && mv -T $CACHE_DIR/options.tmp $CACHE_DIR/options`.
   - It keeps only the published generation and the one it replaced.
   - A failure, timeout or interruption never moves the symlink.
4. **Cache files** (spec table): `system.json` and `user.json` (keyed by name,
   in `options.json` shape), `rows.tsv`
   (`opt⇥name⇥summary⇥type⇥preview⇥scope`) and `meta.json`
   (`{builtAt, host, user, flake, homeManager, users, perUser, counts, seconds, stamp}`).
5. **Staleness.** `stamp` is the sha256 of five lines: `readlink -f "$flake"`,
   `host`, `user`, the sha256 of `flake.lock`, and
   `readlink -f /run/current-system`.
   - A different `flake`, `host` or `user` means the cache is not used at
     all, and the answer is `source:"system"`.
   - A changed lock or generation means the cache is used, marked `stale`.
6. **Readers** (`search`, `state`, `opt describe`) resolve
   `$CACHE_DIR/options` once with `readlink -f` and read every file from that
   directory.
   - `search` takes its option rows from `rows.tsv` when it exists, and skips
     `index.tsv`'s `opt` rows.
   - Slice 1 keeps only `scope == "system"` rows.
   - Every row gains `scope`.
   - The answer gains
     `options:{source, stale, builtAt, user, homeManager, perUser}`.
7. **`opt describe [--scope system|user]`** reads `system.json`/`user.json`
   when present, else `searched optionsjson`. `--scope user` with no
   `user.json` refuses, giving the reason from `meta.json`.
8. **`reindex`** runs `options refresh` after `nixarchy-search --reindex`. Its
   answer gains `options:<refresh answer>`, and its own `ok` still means "the
   index is fresh".
9. **Panel, slice 1.**
   - `optionsSource`, `optionsStale` and `optionsError` are kept like
     `indexStale`.
   - `options refresh` runs on its own `Process` after a successful apply,
     and once per session when the cache is found stale on opening.
   - The footer shows "options: system manual" or "options: reading your
     flake…", or the error.
   - `OptionForm` passes `--scope`.
10. **User scope** applies to packages and options only. App and service
    toggles stay system scope. The user is `id -un`, and user scope needs
    Home Manager as a NixOS module.
11. **`user_scope()`** returns a reason, or empty when user scope works:
    - the installed `nixarchy-apply`'s part loop names `home`;
    - `meta.homeManager` is true;
    - `$user` is in `meta.users`.

    `state` and `search` report it as `userScope:{available, reason}`. A
    user-scope request is refused with that reason, before `begin_write`. It
    is never redirected to system scope.
12. **The user-scope file** is `$CONFIG_DIR/home.nix`, seeded from
    `/etc/nixarchy/home-template.nix` (nixarchy C).
    - `pkg add|remove --scope user` runs nixarchy's writer with `--home`.
    - `opt set|replace --scope user` uses the existing code with
      `TARGET=$HOME_NIX`.
    - `opt remove --scope user` runs `nixarchy-opt-remove --home`.
    - `opt describe --scope user` reads `home.nix`.
13. **A row's identity is `(scope, name)`.** Every add, remove, describe, set
    and replace passes `--scope`, and late answers match on both.
14. **The `home` part** joins `snapshot_selection`, `pins_json`, `cmd_pending`
    and `cmd_check`, and the `--pin` validator becomes
    `^(apps|services|advanced|flatsnap|home)=…`. `check`'s generated
    `nixarchy-apps.nix` mirrors nixarchy C's form byte for byte. There is no
    conflict detector of our own: `check`'s evaluation reports real ones.
15. **Live checks** run in a `nixarchy-desktop` microVM (the owner's standing
    choice), not on razer. Inside the guest anything goes, including apply
    and switch.

## Steps

### 0. Coordinator: rebase and re-check

`git rebase main`. Main has moved a lot since the spec: #55, #56, #60, #64,
#66/67, #68, #69, #75 and #76. Every anchor below is a **quoted text** to
find, not a line number. If one is gone, stop and re-plan that step.

## PR 1: options discovered from the flake

### 1. `DISCOVER` and `options refresh` (`bin/nixarchy-pkg`) -- codex

- Beside the other readonly globals: `readonly DISCOVER='…'`, the spec's A1
  function verbatim, with `@USER@` as the placeholder. Add `OPTSDIR=""` beside
  `CHECKDIR=""`, and add `"$OPTSDIR"` to `on_exit`'s cleanup loop
  (`for d in "$WORK" "$READDIR" "$CHECKDIR" "$APPLYDIR"`).
- `cmd_options()`: dispatch `refresh`; anything else dies with usage. Route
  `options) cmd_options "$@" ;;` in `main()`, beside `check)`.
- `cmd_options_refresh()`, shaped like `cmd_check()` (copy its flake/host
  resolution and its "this flake has no nixosConfigurations.<host>" test):
  1. Validate `user=$(id -un)` against the regex; die if it does not match.
  2. `exec 6>>"$STATE_DIR/pkg-options.lock"; flock -n 6 || die "options are already being read"`.
  3. `[ -e "$TXN/open" ] && die "<check's refusal text>"`.
  4. `private_dir OPTSDIR pkg-options`.
  5. Run the eval as the spec's A1 block shows, in the background, `wait` on
     it, and keep its exit code. On 124, die "timed out after 5 minutes". On
     any other failure, die with `nix_why`'s first line.
  6. Build `system.json`, `user.json` (only when `home != null`), `rows.tsv`
     and `meta.json` with jq from `out.json`, into
     `gen=$CACHE_DIR/options.d/$(date +%s).$$`. The `rows.tsv` preview
     follows `nixarchy-search`'s option preview (read the installed script).
  7. Publish with the `ln -s` + `mv -T` pair, then delete every other entry
     in `options.d/` except `$gen` and the previous target.
  8. Answer as the spec shows:
     `{ok, source:"flake", host, user, homeManager, perUser, counts, seconds, message}`.

→ **Verify:** `bash -n`, `shellcheck bin/nixarchy-pkg`, and
`bash tests/adapter.sh` all pass.

Traps:
- One JSON answer on every path.
- `x=$(f) || rc=$?` under `set -e`.
- No `| head`, and no diff/cmp/comm at a pipeline head.
- `9>&- 8>&-` on the `nix` child.
- Nothing written under `/tmp`.
- The cache directory must be on `$CACHE_DIR`'s filesystem, so the `mv` is
  a rename.
- Never point anything at the real `/etc/nixos` in tests.

### 2. Readers use the cache (`bin/nixarchy-pkg`) -- codex

- `options_dir()` prints `readlink -f "$CACHE_DIR/options"`, or nothing when
  there is no cache. `options_meta_usable()` compares `meta.json`'s `flake`,
  `host` and `user` with the current ones, then computes `stamp` to decide
  `stale`.
- `cmd_search`: resolve the directory once. With a usable `rows.tsv`, the
  awk reads `rows.tsv` for opt rows and skips `$1 == "opt"` in `index.tsv`.
  Keep `scope == "system"` only. Add `scope` to every row and the `options`
  object to the answer.
- `cmd_opt_describe`: parse `--scope system|user`. Read from the resolved
  directory's `system.json`/`user.json`, falling back to
  `searched optionsjson`. Add `scope` and `source` to the answer.
- `cmd_state`: add the same `options` object.
- `cmd_reindex`: after the index rebuild, run `options refresh` in a subshell
  and attach its answer as `options`. Its failure never flips reindex's `ok`.

→ **Verify:** as step 1.

Traps: the same as step 1. Also, the multi-word search from #64 must keep
working over `rows.tsv`: re-read `cmd_search`'s awk after rebasing.

### 3. Slice-1 adapter tests (`tests/adapter.sh`) -- coder

Every case in the spec's D, slice 1. Use a stub `nix` on `PATH` (follow the
existing `DSTUB` pattern; find it by `DSTUB=`) that prints a canned
`out.json`, fails, or sleeps, all under throwaway `XDG_*`:
- the build;
- failure and timeout leave the old cache byte-identical;
- search with and without a cache;
- a changed `flake.lock` makes the cache stale;
- describe, and `--scope user` refusing;
- an invalid user name is refused before any `nix` call;
- a concurrent refresh is refused;
- a kill between build and rename;
- a reader that starts before a publish;
- a foreign flake's cache is not used;
- the `perUser:false` name prefix.

→ **Verify:** `bash tests/adapter.sh` ends "all passed", and each new case
fails if its behaviour is reverted (report which).

### 4. Panel, slice 1 (`PkgModel.qml`, `Card.qml`, `OptionForm.qml`, QML tests) -- coder

Decision 9. In `PkgModel`:
- add `optionsSource`, `optionsStale` and `optionsError`, set where
  `indexStale` is set;
- add an `_optionsRefresh` `Process`, started after a successful apply (where
  `_applyDone = true`) and once per session on a stale cache.

In `Card.qml`, add the footer text beside "index stale — r to rebuild". In
`OptionForm.qml`, `describe.command` gains `"--scope", row.scope || "system"`.
Add tests in `tst_pkgmodel.qml` (from fake answers) and `tst_optionform.qml`
(the `--scope` argument).

→ **Verify:** the QML suites from a flake-style copy, and `nix flake check`.

### 5. Manual (`docs/manual/options.md`, `troubleshooting.md`) -- agy (fallback: coder)

A short section, "Where the options come from":
- they come from your flake, read when the index is rebuilt and after each
  apply;
- the footer says "system manual" until that has happened;
- editing a module without applying is not seen until the next apply or
  reindex;
- a git flake's untracked files are invisible, as they are to the rebuild.

Plus one troubleshooting entry for "options: <error>".

### 6. Coordinator: PR 1

`nix flake check`, the adapter suite, and the Codex, agy and fresh Opus
reviews. Live check in the microVM: point `NIXARCHY_FLAKE` at a throwaway
copy of a real flake in the guest. The guest has none at `/etc/nixos`, so
seed one there; inside the guest that is allowed. Then:
1. run `options refresh` and record its time, RSS and counts;
2. search finds a `programs.nixarchy.*` option, which today's index lacks;
3. `opt set` writes it.

Then the PR. After merge, file companion issue C (below) in nixarchy.

## PR 2: user scope

### 7. User scope in the adapter (`bin/nixarchy-pkg`) -- codex

Decisions 10-14.
- `HOME_NIX="$CONFIG_DIR/home.nix"`, and `user_scope()` as decision 11.
- `--scope` parsing on `pkg add|remove` and on
  `opt set|replace|remove|describe`. User scope refuses before `begin_write`
  when `user_scope` gives a reason.
- `opt set|replace` take `TARGET`, so `$APPS` becomes the system default.
- The `home` part goes in `snapshot_selection`, `pins_json`, `cmd_pending`,
  `cmd_check` and the `--pin` validator (find
  `^(apps|services|advanced|flatsnap)=`).
- `check`'s generated `nixarchy-apps.nix` gains the C import form, only when
  `home.nix` exists.
- `cmd_state` lists `home.nix` rows with `scope:"user"`, and every other row
  gets `scope:"system"`.
- `search` lifts the system-only filter when user scope is available.

→ **Verify:** as step 1.

Traps: the same as step 1. Also:
- never redirect a user-scope request to system scope;
- `(scope, name)` must be the identity everywhere a row is acted on.

### 8. Slice-2 adapter tests (`tests/adapter.sh`) -- coder

The spec's D, slice 2:
- stub writers that assert `--home`;
- a real writer copy against `home-template.nix`: one `home.packages` block
  after two adds, and the file parses;
- each refusal reason;
- `scope` on `state` and `pending` rows;
- the same package and option in both scopes touch only the scope asked for;
- `--pin home=` accepted, and a changed `home.nix` refused;
- `check`'s generated file matches a fixture of C's format;
- the boolean conflict fails while the list option evaluates.

Where nixarchy C is not installed (CI, p620), the writer-backed cases use
fixtures. Say so in the test.

### 9. Panel and manual for user scope -- coder (panel), agy (manual; fallback: coder)

- Panel:
  - a `(scope, name)` row identity in every call and late-answer match
    (`PkgModel.qml`);
  - a `user` badge (`Card.qml`);
  - a new key for "add in user scope" on Packages, picked from
    `bin/nixarchy-pkg-keys` (add it there, with its sheet line);
  - disabled user-scope rows and that key showing the reason when
    `userScope.available` is false;
  - QML tests.
- Manual:
  - what user scope is, and that it needs Home Manager as a NixOS module and
    a nixarchy with the Home Manager part (C);
  - removing a selection may leave a declaration elsewhere in effect;
  - conflicts surface in `check`.

### 10. Coordinator: PR 2

`nix flake check`, the adapter suite, and the three reviews. Live in the
microVM: with nixarchy C absent, user scope is refused with its reason, and
system scope is unchanged. The full user-scope live check (a package in
`/etc/profiles/per-user/$USER`, not `/run/current-system/sw`) waits for
nixarchy C, and the PR says so. Then the PR.

## Tests

- `nix flake check` and `bash tests/adapter.sh` pass on both PRs. The
  adapter suite is part of CI, and since #64 PR 3 it is also a flake check.
- The new adapter cases fail when their behaviour is reverted.
- The live microVM checks in steps 6 and 10. The real-`nix` `DISCOVER` test
  (spec D: a fixture flake with two users and `programs.fixtureOnly.enable`)
  runs in the microVM instead of razer.

## Rollback

Revert the PR. PR 1 adds a cache under `~/.cache/nixarchy/options*`, and
removing it restores today's index-only behaviour. PR 2 adds `home.nix`
handling; without nixarchy C nothing ever writes that file.

## Companion issues

**nixarchy:** "Home Manager part for selection files: apply copies and
imports `~/.config/nixarchy/home.nix`; writers take `--home`". The body is
the spec's section C, verbatim. The lead files it after PR 1 merges.

(Workflow run 2026-11-16: the steps of this PR were implemented in one parallel workflow pass and committed together as one commit, because agent-run codex will not start on a worktree with uncommitted changes and the implementing agents may not commit. The PR names which steps Codex wrote and which the coordinating agent wrote; each agent verified every step with the adapter suite, shellcheck, the QML suites and nix flake check, and the lead re-ran the adapter suite and nix flake check before committing.)

Deviation: state reports cache provenance as `optionsInfo` because its existing
`options` key holds selected option rows. Search and reindex still report it
under `options`.

(Review fixes, round 2: the options staleness stamp is taken before the flake eval starts; a failed options refresh's error stays until a later successful refresh; a successful background refresh re-runs the visible option search; refresh, options refresh and search queue one rerun instead of dropping a request while running; the footer lays out queue status, index-stale text, options status and hints without overlap; generation pruning resolves symlinked cache dirs; reindex shows "reading your flake" and no longer promises 45 s. Codex wrote the edits; the lead verified them.)

(Review fixes, PR 2: home selection follows the installed apply part; user packages receive index facts; option search keeps scope-specific values; Ctrl+Return adds in user scope only on Packages search; describe refusal reaches the cache metadata reasons (the test sets a home-capable meta.json without user.json, because scope_args gates the other cases first); state scopes home drafts and lists home.nix; the manual intro and Menu placeholder retain their original facts.)

(Deviation, nixarchy C is not installed: slice-2 writer tests use stub writers and a home-template fixture; the generated import is compared with a fixture of spec C's form.)
