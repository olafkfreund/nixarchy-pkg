---
status: approved
issue: 62
intent: intent/2026-11-16-62-home-manager-scope.md
---

# Spec: user scope (Home Manager) beside system scope, and options from the user's own flake

## Design

Line numbers are on `main` (`bin/nixarchy-pkg` as of `d3aabd3`) unless
marked **#60**, which means the `feat/60-truthful-queue` branch (PR #70).
#60 merges first, so this design is written against main + #60.

### Decisions for the owner

These had no recommendation in the intent. Each is chosen here and can be
overturned at this gate.

1. **User-scope files (intent Q2): a separate `~/.config/nixarchy/home.nix`,
   a Home Manager module.** Apply copies it like the other parts, and the
   generated `nixarchy-apps.nix` imports it under
   `home-manager.users.<user>`. Rejected: one file holding both scopes (see
   Alternatives).
2. **Who writes it (intent Q5): nixarchy's writers, as today.**
   `nixarchy-pkg-add`, `nixarchy-pkg-remove` and `nixarchy-opt-remove` gain a
   `--home` flag that targets `home.nix` and `home.packages`. The adapter
   keeps writing option lines itself (`opt set` / `opt replace`), as it does
   for `apps.nix` now. `pkg-add` alone is 551 lines of channel, unfree and
   broken-package policy. Copying it would give two writers that disagree.
3. **Slice 1 shows system-scope options only.** It discovers both sets and
   caches the Home Manager set, but the panel lists Home Manager options
   only once slice 2 can write them. This avoids a release where they can
   be found but not set.
4. **Discovery evaluates the flake as it stands**, not the pending
   selection. Options declared by a selection file (`advanced.nix`) that has
   not been applied yet appear after the next apply.
5. **Scope applies to packages and options only.** App and service toggles
   stay system scope: nixarchy's catalogue is NixOS modules. This narrows
   the intent's "program, service": Home Manager `programs.*` and
   `services.*` are reached as options (user scope), while the catalogue's
   app and service toggles stay system-only.

### Decisions from intent approval (settled)

- **Q1.** Home Manager as a NixOS module only. On a machine where the
  host's configuration has no `home-manager.users` option, user-scope
  operations are refused with a message saying so; system scope works as
  before.
- **Q3.** The user is whoever runs the panel (`id -un`). User-scope
  operations are refused when that name is not in
  `config.home-manager.users`.
- **Q4.** Measured (below). Discovery evaluates the host's options from the
  user's flake when the index is rebuilt and after a successful apply, and
  caches the result.
- **Q6.** Two PRs, discovery first. Between them, a companion issue in
  nixarchy (section C).

### Measurements (2026-11-16, p620, read-only)

All runs used `nix eval --offline` against nixarchy's own flake in the store
(`nixosConfigurations.reference`, nixpkgs `26.11pre`), with throwaway
`XDG_*` directories. Nothing touched `/etc/nixos`.

| What | Result |
|---|---|
| NixOS options with type, description, default, example, declarations | 26,434, 2.5 s, 616 MB peak RSS, 10 MB JSON |
| Home Manager options for one user (shared + that user's own imports) | 5,513, 1.1 s |
| Both in one evaluation (the design below) | 3.15 s and 3.20 s (two runs), 650 MB peak RSS, 14 MB JSON |
| jq: list → object keyed by name (26,434) | 0.66 s |
| Of the NixOS set: `programs.nixarchy.*` | 331. None are in today's index |
| Of the HM set: `programs.*` / `services.*` / `home.*` | 3,192 / 1,126 / 67 |
| Today's index (`nixarchy-search`): option rows | 25,918, NixOS manual only |
| Real host, names only (intent stage, warm cache) | 3.6 s |

The real host has more modules than `reference`. Its full cost is
unmeasured, because measuring it would mean pointing at `/etc/nixos`. The
plan measures it on razer. The design does not depend on it being fast: it
runs in the background with a 300 s bound.

**Per-user imports are reachable.** `options.home-manager.users.valueMeta.attrs.<user>.configuration.options`
is that user's own evaluated option set, including their imports. Checked:
`perUser = true`, 5,513 options for `omarchy` on `reference`. `valueMeta` is
newer nixpkgs `lib`. Where it is absent, discovery falls back to
`options.home-manager.users.type.getSubOptions []` (shared modules only) and
says `perUser: false`. Whether nixos-26.05 has `valueMeta` is not verified.

### A. Slice 1 (PR 1): options discovered from the flake

**A1. The evaluation.** One `nix eval`, pure, with no `--impure` and no
`getFlake`:

```bash
setsid timeout 300 nix eval --json --no-write-lock-file \
  "$flake#nixosConfigurations.\"$host\"" --apply "$DISCOVER" \
  >"$dir/out.json" 2>"$dir/err" 9>&- 8>&- &
```

- `flake`, `host` and `base` are the same as apply's and `check`'s
  (#60 `cmd_check`: `flake=${NIXARCHY_FLAKE:-/etc/nixos}`, `host=$(uname -n)`).
  `$flake` is passed as it is, so Nix reads a git flake's tracked files,
  exactly as `nh os switch "$flake"` does (`nixarchy-apply:531`).
- `--no-write-lock-file`: a read never writes `flake.lock`. An outdated
  lock is resolved in memory, which may fetch, inside the timeout.
- `DISCOVER` is a Nix function held in the adapter as a readonly string.
  `$user` is checked against `^[a-z_][a-z0-9_-]*$` before it is
  interpolated. Verified on `reference`:

```nix
c: let
  lib = c.pkgs.lib;
  user = "@USER@";
  doc = prefix: opts: map (o: {
      name = lib.removePrefix prefix o.name;
      type = o.type or ""; description = o.description or "";
      default = o.default or null; example = o.example or null;
      declarations = map toString (o.declarations or [ ]);
      readOnly = o.readOnly or false;
    }) (builtins.filter (o: (o.visible or true) == true && !(o.internal or false))
         (lib.optionAttrSetToDocList opts));
  hm = c.options.home-manager.users or null;
  perUser = hm != null && (hm.valueMeta.attrs or { }) ? ${user};
in {
  nixos = doc "" c.options;
  homeManager = hm != null;
  users = if hm == null then [ ] else builtins.attrNames c.config.home-manager.users;
  inherit perUser;
  home = if hm == null then null
    else if perUser then doc "home-manager.users.${user}." hm.valueMeta.attrs.${user}.configuration.options
    else doc "<name>." (hm.type.getSubOptions [ ]);
}
```

The fallback prefix is `<name>.`: checked on `reference`, where
`getSubOptions []` names begin `<name>.accounts…`. With `perUser: false`,
the panel says "Home Manager options shared by all users only — your own
imports are missing" wherever user options are listed, so an incomplete
list is never shown as complete.

`default` and `example` keep the `{_type, text}` shape that `options.json`
has, so `opt describe`'s `literal` (**#60** `:654`) reads both unchanged.

**A2. New verb: `nixarchy-pkg options refresh`.** It is a read: no write
lock and no `begin_write`. It is shaped like #60's `cmd_check`:

- Its own `flock -n` on `$STATE_DIR/pkg-options.lock`. A refresh already
  running answers `{ok:false, error:"options are already being read"}`.
- It refuses while `$TXN/open` exists, as `check` does.
- It works in a private directory `$STATE_DIR/pkg-options.XXXXXX`, removed
  by the global `on_exit` through a new `OPTSDIR` variable, like
  `READDIR`/`CHECKDIR`. It uses `setsid`, `CHILD` and `9>&- 8>&-` on every
  child.
- On success, jq turns `out.json` into the cache files in a new directory
  `$CACHE_DIR/options.d/<builtAt-epoch>.<pid>/`. It is built on the cache's
  own filesystem, never under `STATE_DIR`. It is published by one atomic
  rename of a symlink: `ln -s <dir> $CACHE_DIR/options.tmp && mv -T
  $CACHE_DIR/options.tmp $CACHE_DIR/options`. Older directories in
  `options.d/` are deleted afterwards, keeping only the one just published
  and the one it replaced.
- A failed, timed-out or interrupted refresh never changes the symlink, so
  the previous cache stays published.
- Readers (`search`, `state`, `opt describe`) resolve `$CACHE_DIR/options`
  once with `readlink -f` at the start, and read every file from that
  directory. So one answer never mixes two generations, and a published
  directory is never deleted under a reader that started on it (only the
  generation before last is removed).

Cache: `$CACHE_DIR/options` → a directory beside `index.tsv` holding:

| File | Content |
|---|---|
| `system.json` | NixOS options, an object keyed by name (`options.json` shape) |
| `user.json` | Home Manager options for `$user`, same shape, or absent |
| `rows.tsv` | Search rows: `opt⇥name⇥summary⇥type⇥preview⇥scope`. The first five columns use `index.tsv`'s opt-row format; the preview is built as `nixarchy-search:70` builds it |
| `meta.json` | `{builtAt, host, user, homeManager, users, perUser, counts:{system,user}, seconds, stamp}` |

Answer:

```json
{"ok":true,"source":"flake","host":"razer","user":"olaf","homeManager":true,
 "perUser":true,"counts":{"system":26434,"user":5513},"seconds":3.2,
 "message":"read 26434 system and 5513 user options from /etc/nixos"}
```

On failure: `{ok:false, error}`, where `error` is `nix_why`'s first line
(#60 `:995`), or "timed out after 5 minutes", or "this flake has no
nixosConfigurations.<host>" (the same test as `check`).

**A3. Staleness.** `stamp` is the sha256 of five lines: `readlink -f
"$flake"`, `host`, `user`, the sha256 of `$flake/flake.lock`, and
`readlink -f /run/current-system`. `meta.json` also stores `flake`
(canonical). A cache whose `flake`, `host` or `user` differs from the
current one is not used at all, neither its rows nor its Home Manager
facts: the answer is `source: "system"`, as with no cache. A cache that
only has a changed lock or generation is used and marked `stale`.
A changed generation or lock makes the cache stale. Editing a module without
applying does not, and this limit is stated in the manual. The check is
cheap enough to run on every `search` and `state`.

**A4. `search`.** **#60** `cmd_search` (`:399`):

- When `$CACHE_DIR/options/rows.tsv` exists, option rows come from it, and
  `index.tsv`'s `opt` rows are skipped (`$1 == "opt" { next }` for that
  file). Package and app rows still come from `index.tsv`.
- Slice 1 keeps only `scope == "system"` rows. Slice 2 lifts that filter
  when user scope is available (B5).
- Every row gains `scope`: `"system"` or `"user"`. Rows from `index.tsv`
  are `"system"`.
- The answer gains one object:

```json
"options": {"source": "flake" | "system", "stale": false,
            "builtAt": "2026-11-16T07:57:00Z", "user": "olaf",
            "homeManager": true, "perUser": true}
```

  `source: "system"` means no cache, which is today's behaviour. The panel
  says "options from the system manual — not your flake's".

**A5. `opt describe [--scope system|user] <path>`.** **#60** `:617-622`:
the file read is `options/system.json` (or `user.json` for `--scope user`)
when present, else `searched optionsjson` as today. The answer gains
`scope` and `source`. `--scope user` with no `user.json` answers
`{ok:false, error:"no Home Manager options for <user> -- …"}`, giving the
reason from `meta.json`.

**A6. `reindex`** (**#60** `:1889`) runs `options refresh` after
`nixarchy-search --reindex`. Its answer gains `options: <refresh answer>`.
Its own `ok` still means "the index is fresh", so an options failure is
reported beside it, never as the index failing.

**A7. Panel.**

- `PkgModel` keeps `optionsSource`, `optionsStale` and `optionsError` from
  `search`, `state` and `reindex`, the same way as `indexStale` (**#60**
  `PkgModel.qml:380`, `:394`).
- After an apply that succeeded (`_applyDone` with `ok`, **#60** `:801`), it
  runs `options refresh` in its own `Process`, so the panel is not blocked.
  A stale cache found on opening does the same, at most once per panel
  session.
- The footer (**#60** `Card.qml:370`, beside "index stale") shows
  "options: system manual" or "options: reading your flake…" when
  `source != "flake"` or a refresh is running. On failure it shows the
  error, and the full error is in the detail view.
- `OptionForm.qml:152` passes `--scope` from the row.

### B. Slice 2 (PR 2): user scope

PR 2 works only with a nixarchy that has section C.

**B1. Capability.** A new `user_scope()` returns a reason string, or empty
when user scope is available:

1. the installed `nixarchy-apply`'s part loop names `home`
   (`grep -qE '^for part in .*\bhome\b'`, read like `searched` reads
   `nixarchy-search`);
2. `options/meta.json` has `homeManager: true`;
3. `$user` is in `meta.users`.

Each failure gives its own sentence. `state` and `search` report it as
`userScope: {available: bool, reason}`.

**B2. The file.** `$CONFIG_DIR/home.nix`, a Home Manager module that
nixarchy seeds from `/etc/nixarchy/home-template.nix` (C). Shape:

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [  #@pkgs-begin
  ];  #@pkgs-end
}
```

The marker and line formats are byte-identical to `apps.nix`'s, so
`opt-remove`'s walk and the `#@opt` rules apply unchanged. `#@pkgs-end` is
required: `nixarchy-pkg-add`'s `ensure_block` tests for it (`:153`) and
inserts before it (`:311`, `:323`). Without it, the writer adds a second
`home.packages` block and evaluation fails with "already defined".

**B3. Writes.**

- `pkg add|remove --scope user <attr>`: runs the writer with `--home`.
  `--scope system` (the default) runs it exactly as today.
- `opt set|replace --scope user <path> <value>`: the same code with
  `TARGET=$HOME_NIX` in place of `$APPS`. `guard`, `committed`, the parse
  check and the refusals are unchanged (#59).
- `opt remove --scope user`: `nixarchy-opt-remove --home`.
- `opt describe --scope user` reads the current value from `home.nix`,
  not `apps.nix`. Today the file is fixed to `$APPS` (**#60** `:629`). It
  becomes the scope's target.
- Each refuses with `user_scope`'s reason when it is not empty, before
  `begin_write`. A user-scope request is never redirected to system scope.
- **Scope travels with every operation.** A row's identity in the panel is
  `(scope, name)`, not `name`. Every call that acts on a row passes
  `--scope`: add, remove (**#60** `PkgModel.qml:596`, and the row removals
  beside it), describe, set and replace. A late answer is matched on
  `(scope, name)` as well. So `git` in both scopes, or `programs.foo` set in
  both files, can never open, change or remove the other one.

**B4. State and queue.**

- `cmd_state` lists `home.nix`'s packages and options with `scope: "user"`.
  Existing rows gain `scope: "system"`. A package in both scopes is two
  rows. That is legal (`modules/home.nix:1108-1109`) and both are shown.
- #60's part lists add `home`: **#60** `:1315` (`snapshot_selection`),
  `:1337` (`pins_json`), `:1440` (`cmd_pending`), `:1764` (`cmd_check`).
  So does `cmd_apply`'s pin validator (**#60** `:1852`): its pattern
  becomes `^(apps|services|advanced|flatsnap|home)=…`, with the error text
  to match. Without that, the panel's own `home=` pin makes every apply
  refuse.
- `check`'s generated `nixarchy-apps.nix` (**#60** `:1777`) mirrors C's new
  form byte for byte, so `check` still evaluates what apply will build.
- **Conflicts.** #60's `check` reports incompatible definitions: two
  different values for a single-valued option fail evaluation and are
  named there. Nix merges lists, accepts equal values and resolves
  priorities (`mkDefault`, `mkForce`), so those are not conflicts, and the
  panel does not claim they are. The manual says that removing a panel
  selection can leave a declaration elsewhere in effect. No second
  detector.

**B5. Panel.**

- Search rows show a `user` badge (`Card.qml`).
- Option rows carry their scope from discovery, so there is nothing to
  pick.
- On the Packages tab, `RETURN` adds in system scope as today. A new key
  adds in user scope; the plan picks it from `bin/nixarchy-pkg-keys`.
- When `userScope.available` is false, that key and the user-scope rows
  are shown disabled, with the reason.

### C. Companion issue in nixarchy

**Title:** "Home Manager part for selection files: apply copies and imports
`~/.config/nixarchy/home.nix`; writers take `--home`"

**Body:** nixarchy-pkg #62 adds a user scope. It needs nixarchy to:

- treat `~/.config/nixarchy/home.nix` as a fifth selection part, copied like
  the others (`nixarchy-apply:330-345`), pinned by `--expect-sha256 home=…`,
  and imported, only when the source exists, by the generated
  `nixarchy-apps.nix` as
  `home-manager.users."<id -un>".imports = [ ./nixarchy/home.nix ];`
  beside the existing `imports`;
- seed it from a new `/etc/nixarchy/home-template.nix`;
- give `nixarchy-pkg-add`, `nixarchy-pkg-remove` and `nixarchy-opt-remove`
  a `--home` flag that targets that file and its `home.packages` block with
  the same markers (`#@pkgs-begin` / `#@pkgs-end`);
- define what `pkg-add --home` does where its policy assumes the system:
  - a curated app name such as `firefox`, which today is refused in
    favour of `nixarchy-app-enable` (`:214-219`): proposed, still refused,
    with the same message, because the app is a system toggle;
  - the other channel (`pkgsOther`, `:33-43`, `:311`): the Home Manager
    module needs `pkgsOther` too, so nixarchy passes it to it, through
    `home-manager.extraSpecialArgs` or `_module.args`;
  - unfree packages: with `useGlobalPkgs = true` (the installer's
    setting), the system's `allowUnfree` and `allowUnfreePredicate`
    already apply. The `--home` hint names the system setting, not a
    Home Manager one;
- keep the `checks.options` byte-format assertions covering the new file.

Apply's current behaviour is unchanged for anyone without `home.nix`.

### D. Tests

- `tests/adapter.sh`, slice 1, with a stub `nix` on `PATH` (the pattern
  `DSTUB` uses at `tests/adapter.sh:713`) that prints canned `out.json`, or
  fails, or sleeps. All under throwaway `XDG_*`. Cases:
  - refresh builds all four cache files, and `rows.tsv` has five columns
    plus scope;
  - a failed refresh, and a timed-out one (`timeout` stubbed), leave the
    old cache byte-identical and answer `ok:false`;
  - `search` uses discovered rows and skips index opt rows; with no cache it
    falls back with `source: "system"`;
  - a changed `flake.lock` makes the cache stale;
  - `opt describe` reads `system.json`, and `--scope user` with no
    `user.json` refuses;
  - an invalid user name is refused before any `nix` call;
  - a second refresh while one runs is refused;
  - publication: a refresh killed between building and the rename leaves
    the old cache published; a reader started before a publish answers
    entirely from the old generation;
  - a cache built for another flake (`NIXARCHY_FLAKE` switched between two
    fixture flakes with identical `flake.lock`) is not used;
  - `perUser: false` fallback names start at the option (no `<name>.`).
- A real-`nix` test of `DISCOVER` itself, by hand on razer (CI has no Home
  Manager input to evaluate). It uses a fixture flake in `mktemp`, with
  `nixpkgs` and `home-manager` overridden to the store paths in nixarchy's
  lock and `--offline`. The fixture has two users, one of whom imports a
  module declaring `programs.fixtureOnly.enable`. Expected: that option is
  in that user's set and not in the other's, `perUser: true`.
- Slice 2:
  - writes with `--scope user` against stub writers, which assert `--home`;
  - against a real writer copy, run on `home-template.nix`: one
    `home.packages` block after two adds, and the file parses;
  - refusals for each `user_scope` reason;
  - `state` and `pending` rows carry `scope`;
  - the same package and the same option path in both scopes: describe,
    replace and remove touch only the scope asked for (adapter and
    `tst_pkgmodel`);
  - `apply --pin home=<sha>` is accepted, and a `home.nix` changed after
    the pin is refused before anything is copied (stub `nixarchy-apply`
    asserting the flag);
  - `check`'s generated `nixarchy-apps.nix` is compared with a fixture of
    C's format;
  - `check` on a fixture where `home.nix` and a hand-written module give
    one boolean two values: verdict fails. With a list option in both:
    verdict evaluates.
- `tests/qml/tst_pkgmodel.qml`: `optionsSource`, `optionsStale` and
  `userScope` from fake answers; the footer text; the badge.

## Alternatives rejected

- **Read `/etc/nixarchy/options.json` as well.** Cheap, but it has only
  nixarchy's 331 options, and none of the user's own or Home Manager's.
  Discovery covers it.
- **Have nixarchy build a fuller `options.json` into the system**
  (`documentation.nixos.includeAllModules` plus the HM set). It is only as
  fresh as the last apply and missing before the first. It adds a
  documentation build to every rebuild, which fails on any module with a
  bad description. And it needs a nixarchy change for what a 3 s evaluation
  gives directly.
- **Evaluate a private copy of the flake with the pending selection**, as
  `check` does. It would also see options from unapplied selection files,
  which is rare. The cost is a full flake copy for every refresh.
- **`builtins.getFlake` with `--impure`.** `--apply` on the flake attribute
  is pure and handles the lock flags.
- **One file holding both scopes** (a `home-manager.users.<u>` block inside
  `apps.nix`). The `#@opt <path>` markers become ambiguous between scopes.
  The user's name would be hard-coded into a shared file. And
  `opt-remove`'s walk would have to learn nesting.
- **The adapter writing `home.packages` itself.** It would duplicate
  `nixarchy-pkg-add`'s channel, unfree and broken policy (551 lines), which
  then drifts.
- **Standalone Home Manager.** Ruled out at the intent gate (Q1).

## Risks

- **Memory and time.** About 650 MB and 3 s on `reference`. A large real
  flake could be several times that. It runs in the background, bounded at
  300 s, one at a time. Its cost on p510-class hosts is unmeasured.
- **Git flakes see tracked files only.** A module the user has not
  `git add`ed is invisible, as it is to `nh`. Discovery then fails or misses
  it, the same way the rebuild would.
- **Network.** An outdated lock may fetch inside the timeout. Nothing is
  written to the flake.
- **Nix's own eval cache** under `~/.cache/nix` is written by `nix eval`, as
  it is by every rebuild. Not ours to avoid.
- **The cache misses edits to modules** until the next apply or reindex
  (A3). Stated in the manual.
- **`valueMeta` missing** on an older nixpkgs gives shared-only Home Manager
  options, labelled `perUser: false`.
- **Slice 2 depends on nixarchy C.** Without it, user scope is unavailable
  and says why. Slice 1 has no nixarchy dependency.
- **`check` mirroring apply's new `nixarchy-apps.nix`.** If the two forms
  drift, `check` evaluates something apply does not build. A fixture test
  pins C's format.

## Verification

- On both PRs: `nix flake check` passes (shellcheck, manifest, QML tests)
  and so does `bash tests/adapter.sh`. The adapter tests are not a flake
  check: CI runs them directly (`.github/workflows/ci.yml:28`).
- On **razer**:
  - `options refresh` on the real flake: time, RSS and counts recorded in
    the PR, including NixOS options from the user's own modules and
    `programs.nixarchy.*`;
  - search finds an option that today's index lacks, and `opt set` writes
    it.
- Slice 2, on razer with nixarchy C:
  - add a package and set `programs.git.enable` in user scope;
  - `check` evaluates; apply switches; the package is in `~/.nix-profile`
    or `/etc/profiles/per-user/$USER`, not in `/run/current-system/sw`;
  - with C absent, user scope is refused with its reason.
