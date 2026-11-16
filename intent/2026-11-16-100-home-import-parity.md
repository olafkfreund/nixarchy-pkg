---
status: approved
issue: 100
author: olafkfreund
---

# Intent: check builds the home import the way apply does, and user scope needs useGlobalPkgs

## Problem

nixarchy merged its Home Manager part (nixarchy#1815, closing #1809). Two
things in the user scope added by #62 do not match it. Line numbers below are
nixarchy `origin/main` (d5f58434) for `modules/apps.nix`, and this repo at
44eb7d4 for `bin/nixarchy-pkg`.

**1. `check` renders a different home import from the one apply writes.**

- When the selection has a `home.nix`, `cmd_check` (`bin/nixarchy-pkg:2385`)
  writes its own `nixarchy-apps.nix`: a header, `imports = [...]`, and one
  line, `home-manager.users."<u>".imports = [ ./nixarchy/home.nix ];`
  (`:2490-2497`). The fixture the tests compare it to is the same shape
  (`tests/fixtures/nixarchy-apps-home.nix`, `tests/adapter.sh:2748-2749`).
- Apply does not write that. It fills `homeAppsTemplateText`
  (`modules/apps.nix:407-430`) with `sed -e "s|@USER@|$user|g" -e
  "s|@IMPORTS@|$imports|g"` (`modules/apps.nix:4829`), and only when a home
  part exists; otherwise it writes the plain `imports` stub
  (`:4831-4837`). The template differs from check's stub in three ways:
  - the module is a function, `{ config, options, lib, ... }:` with a `let
    configuredElsewhere` (`:411-416`);
  - the user's imports list starts with `{ _module.args.pkgsOther = ... }`
    before `./nixarchy/home.nix` (`:419-423`);
  - it adds three assertions: `home-manager.useGlobalPkgs`, the user is
    `isNormalUser`, and the user has a Home Manager configuration from some
    other file (`:424-428`).
- `check` evaluates `config.system.build.toplevel.drvPath`
  (`bin/nixarchy-pkg:2521-2523`), which includes failed assertions. So with
  the stub, `check` answers `evaluates` for a flake where apply's assertions
  fail. The reverse is possible too: the default `home.nix` only declares
  `pkgsOther` (`modules/apps.nix:400-406`), which is lazy, so it evaluates
  without the stub providing it; but a `home.nix` that uses `pkgsOther` would
  fail under `check` and build under apply, because the stub never sets
  `_module.args.pkgsOther`.
- The two sides also check the user name differently. Apply accepts
  `^[a-z_][a-z0-9_-]*[$]?$` (`modules/apps.nix:4750-4752`); check accepts
  `^[a-z_][a-z0-9_-]*$` (`bin/nixarchy-pkg:2496`).
- The template is installed as `/etc/nixarchy/home-apps-template.nix`
  (`environment.etc."nixarchy/home-apps-template.nix".text`,
  `modules/apps.nix:1676`). Nothing in this repo reads it
  (`grep home-apps-template` finds no hit in `bin/`, `tests/`, `tools/`).

**2. User scope does not require `home-manager.useGlobalPkgs`.**

- nixarchy asserts it (`modules/apps.nix:425`), and its three home writers
  refuse without it: `nixarchy-pkg-remove` (`:2637-2639`), `nixarchy-opt-remove`
  (`:2869-2871`) and `nixarchy-pkg-add` (`:2990`, `:3060`), each from a
  `homeScope` baked in from the running system's config.
- `user_scope()` (`bin/nixarchy-pkg:365-386`) checks four things: apply has a
  home part (`apply_has_home`, `:358-362`, a grep of the installed
  `nixarchy-apply`), the discovery cache exists, Home Manager is present,
  and the user is in `home-manager.users`. It never looks at `useGlobalPkgs`.
- The discovery expression (`DISCOVER`, `:86-107`) and the cache's
  `meta.json` (`:2360-2362`) record `homeManager`, `users` and `perUser`, not
  `useGlobalPkgs`.
- So on a flake with `useGlobalPkgs` off, `state` reports user scope as
  available (`:2663-2665`), the user can stage a `home.nix` selection, and the
  refusal arrives late: from the writer at the moment of the write, which
  reads the running system rather than the flake, or from apply's assertion
  at rebuild. The panel gives no reason up front, as it does for the other
  three missing prerequisites.

Found while writing the spec for nixarchy#1809, which turned out to be done
already.

## Proposed outcome

- `check` builds the home import from the same text apply does. For the same
  selection, user and imports, the file `check` evaluates is byte-for-byte
  the file `apply` would write. A selection that apply cannot build, because
  of an assertion in the template, is reported by `check` as a failure with
  that assertion's message, not as `evaluates`.
- A test fails when the two drift: if nixarchy changes the template, this
  repo's test notices.
- With `useGlobalPkgs` off, user scope is unavailable in `state` with the
  reason `home-manager.useGlobalPkgs is off; user-scope packages need it`,
  and `scope_args` refuses the same way (`die`, before any write).
- The options discovery records the setting, so the reason is available
  without evaluating the flake again.
- A host whose nixarchy has no home part behaves as it does today: no user
  scope, `check` without a home import. A host with a home part but no
  template is never answered `evaluates` for a selection that has a
  `home.nix` (see question 3).

## Affected users and systems

- Anyone using user scope (`--scope user`, the panel's user tabs) on a
  nixarchy with the Home Manager part (nixarchy#1815 or later).
- Files in this repo: `bin/nixarchy-pkg` (`cmd_check`, `user_scope`,
  `DISCOVER`, the `meta.json` writer), `tests/adapter.sh` and
  `tests/fixtures/nixarchy-apps-home.nix`, `docs/manual/options.md` and
  `docs/manual/packages.md` where they describe check and user scope.
- No change to nixarchy is needed unless the open questions below choose to
  ask for one.

## Constraints

- No second copy of apply's logic that can drift unnoticed. If text is
  duplicated, a test must compare it to the source of truth.
- `check` still writes only inside its own temp copy; it must not touch the
  user's flake or `~/.config/nixarchy`.
- The check evaluates the user's own flake, so `useGlobalPkgs` must come from
  that flake's configuration (what apply will build), not only from the
  running system.
- An older nixarchy keeps working: no new hard requirement on hosts that have
  no Home Manager part.
- Live checks run in a `nixarchy-desktop` microVM: the owner's standing
  choice over razer. Nothing here is verified yet on a real host; the claims
  above are from reading both repos at the commits named.

## Open questions

1. **Read the installed template at check time, or vendor a copy here with a
   drift test?** (a) `check` reads `/etc/nixarchy/home-apps-template.nix`,
   fills it with `sed` as apply does, and the adapter test fills the same
   file; (b) this repo keeps its own copy and a test compares it to
   nixarchy's. Recommended: (a). It is the same text apply uses on that machine,
   so there is nothing to keep in step (apply reads the same text from the
   store, `modules/apps.nix:431,4829`; `/etc` exports it, `:1676`). The
   adapter test then needs a template to read, and a copy taken once from
   nixarchy would not by itself notice upstream drift: say how upstream
   changes are caught (the spec decides; for example a test in nixarchy that
   this repo's fixture must match). A vendored copy (b) would be wrong the
   day nixarchy updates and this plugin has not.
2. **How does check/`user_scope` learn `useGlobalPkgs`: the discovery
   `meta.json`, or the installed writer's baked `homeScope`?** (a) add
   `useGlobalPkgs = c.config.home-manager.useGlobalPkgs or false` to
   `DISCOVER` (guarded by `hm != null`) and store it in `meta.json`;
   (b) grep `homeScope=` out of an installed writer, as `searched()` does for
   other values (`:350-356`). Recommended: (a). It reads the flake apply is
   about to build, where (b) reports the running system, which differs right
   after a flake edit. Caveats: the cache can be stale (`options_resolve` only marks it
   stale, `:2290-2293`), and an older cache lacks the field. Recommended for a
   missing field: user scope stays available with a note to run options
   refresh (no new refusal from an unknown), and `check` still catches a real
   `false` through the template assertion; a recorded `false` refuses.
3. **What does `check` do when the template is missing?** This only happens
   on a host whose nixarchy has the home part but not the file (a broken or
   partial install). On an older nixarchy with no home part nothing changes:
   `apply_has_home` is false and `snapshot_selection` skips `home.nix`
   (`:1880`). Options: fall back to today's stub, return `unknown` with a
   reason, or refuse user scope. Recommended: `check` returns `unknown` with
   "nixarchy's home template is not installed
   (`/etc/nixarchy/home-apps-template.nix`); update nixarchy", and
   `user_scope()` gives the same reason. Do not fold the file into
   `apply_has_home`: that would make `snapshot_selection` drop `home.nix`, and
   `check` would then say `evaluates` without the selection. A fallback to
   the stub would bring back the false `evaluates` too.
4. **Should `check` accept the same user names apply does** (the trailing
   `$`)? Recommended: yes, by using one regex; it is a one-character
   difference and costs nothing. Say no if you want this issue kept to the two
   points in the title.
5. **Where is the useGlobalPkgs reason raised?** Only in `user_scope()`,
   which `scope_args`, `cmd_search` and `cmd_state` call (`:400`, `:609`,
   `:2663`)?
   Recommended: yes, one place; no extra check in `cmd_check`, since the
   template's own assertion reports it there.
