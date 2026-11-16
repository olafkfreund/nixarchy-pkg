---
status: approved
issue: 62
author: olafkfreund
---

# Intent: user scope (Home Manager) beside system scope, and options from the user's own flake

## Problem

Everything the panel writes is NixOS system configuration. A user who wants
something only for themselves (a CLI tool in their own profile, a
`programs.git` or `services.syncthing` set up the Home Manager way) has no
way to say so. They get the system-wide version or nothing. The option
search also does not know about the modules the user's flake actually loads.

**How a nixarchy machine wires Home Manager today** (read on 2026-11-16 from
the installed nixarchy source and `nixarchy-apply`):

- Home Manager is a NixOS module, not a standalone tool. nixarchy's NixOS
  module imports `home-manager.nixosModules.home-manager` (`modules/nixos.nix:354`).
  The installer writes `home-manager.users.<user>` with `useGlobalPkgs` and
  `useUserPackages` on, and nixarchy's own HM module in `sharedModules`
  (`installer/host.nix:212-220`).
- So one `nh os switch` (`nixarchy-apply:531`) also activates the user's
  Home Manager generation, through `home-manager-<user>.service`. There is no
  separate `home-manager switch` step and no `~/.config/home-manager`.
- Apply copies `apps.nix`, `services.nix`, `advanced.nix` and `flatsnap.nix`
  from `~/.config/nixarchy` into the flake and lists them in a generated
  `nixarchy-apps.nix` (`nixarchy-apply:330-345`, `:390-397`). It copies
  `packages/*.nix` beside them (`:370-383`). All of it lands in the NixOS
  configuration. nixarchy's own HM module says so: `services.nix` "is a
  NixOS file" (`modules/home.nix:626`). None of them is a Home Manager
  module.

**1. There is no user scope.** `pkg add` runs `nixarchy-pkg-add`
(`bin/nixarchy-pkg:536-539`), which writes `environment.systemPackages`
lines. `toggle` runs `nixarchy-app-enable` / `-service-enable` (`:519`).
`opt set` writes into `apps.nix` (`:718-724`). All of it is system scope.
The panel cannot add a `home.packages` entry or a Home Manager
`programs.*` / `services.*` option. The CLI can only by accident: `opt set`
takes any dotted path (`:728-730`), so a user who already knows to type
`home-manager.users.<user>.programs.git.enable` gets it written, unchecked
and unlabelled. There is no supported way to choose a scope, find a user
option, or see which scope something is in.

**2. The option search knows only nixpkgs' NixOS options.** `opt describe`
reads the `options.json` that `nixarchy-search` was built with (`searched`,
`:244`; `:592-596`). That file is `config.system.build.manual.optionsJSON`
(nixarchy `modules/apps.nix:227`). On this machine it has 26,073 options and
none starting with `home-manager` or `home.` (counted with `jq`), because:

- the NixOS manual documents nixpkgs' modules only
  (`documentation.nixos.includeAllModules` is `false` here), so options from
  the user's own modules and from flake inputs (nixarchy's
  `programs.nixarchy.*`, sops-nix, a plugin flake) are missing;
- Home Manager's options are a submodule of `home-manager.users`, which a
  NixOS manual never expands.

nixarchy already ships a second file, `/etc/nixarchy/options.json` (309
`programs.nixarchy.*` options), which the panel does not read. And nixarchy
already reaches more for nixd, from the user's flake: the host's `options`
(`modules/nixos.nix:289`) and the Home Manager submodule's
`options.home-manager.users.type.getSubOptions []` (`:290-294`). That
second set has only what every user shares (`sharedModules`), not modules a
user imports for themselves; nixarchy says as much for its own catalogue
(`:302-303`). Listing the names of the 447 shared Home Manager `programs.*`
options that way took 3.6 s here (a warm evaluation cache). Full
descriptions and types were not measured.

**3. An option the panel does not know cannot be set through it.** `opt
describe` answers "no such option" for anything outside that file
(`:634-635`), so the form will not open for an option from the user's own
module or from Home Manager. The only way round it is `opt set` from the
CLI, which writes the path unchecked. A typo or a wrong scope then fails
only when apply evaluates the machine (see #60, problem 4).

## Proposed outcome

- Every package, program, service and option the panel writes has a
  visible scope: **system** (as today) or **user** (Home Manager, for the
  desktop user). The panel shows which one each is in, and the user picks it
  when adding something that can live in either. Flake inputs stay outside
  this split.
- A package added in user scope lands in that user's `home.packages`, and a
  Home Manager `programs.*` / `services.*` option can be set, through
  declarative files the panel owns and the user can read.
- Apply stays the only thing that rebuilds. One apply switches both scopes,
  as one `nh os switch` already does today.
- The option search covers what the target flake and host actually load:
  NixOS options from nixpkgs, from flake inputs and from the user's own
  modules, plus Home Manager options for the desktop user, including
  modules that user imports for themselves. Each result says which scope it
  belongs to.
- Where that discovery is slow or fails (no flake, a flake that does not
  evaluate, no Home Manager), the panel says so and falls back to what it
  has today. It never shows a short list as if it were complete, and a write
  the user asked for in user scope is refused, never quietly made in system
  scope instead.
- System-scope behaviour, file formats and the `#@` marker contract are
  unchanged for existing users. Nothing they have selected moves scope on
  its own.

## Affected users and systems

- Every nixarchy user, and especially anyone who wants per-user tools or
  dotfile-managed programs (`programs.git`, `programs.zsh`, `services.*`
  user units).
- `bin/nixarchy-pkg`: `cmd_pkg`, `cmd_toggle`, `cmd_opt_*`, `cmd_search`,
  `cmd_pending`, `cmd_reindex`, `flake_base`.
- `PkgModel.qml`, `Panel.qml`, `Card.qml`, `OptionForm.qml`.
- `tests/adapter.sh`, QML tests, `docs/manual`.
- Outside this repo, in nixarchy: the writers (`nixarchy-pkg-add`,
  `nixarchy-opt-remove`, …), `nixarchy-search`'s index, and
  `nixarchy-apply` (which part files it copies, and what imports them).
  A user-scope file needs something on the nixarchy side to import it under
  `home-manager.users.<user>`; that is a companion nixarchy issue.
- Verification host is **razer**, per repo convention. Never p620.

## Constraints

- Declarative only. The panel writes Nix files the user owns and can read;
  it never edits outside its own files without the user, and never touches
  the user's hand-written Home Manager configuration.
- No root, no elevation. Apply is the only thing that rebuilds or switches;
  the panel never runs `home-manager switch` or activates anything itself.
- Must keep #59's guarantees: every write is locked, recoverable and
  answers `{ok:false, error}` on failure. Must not change the JSON contract
  for existing commands.
- Must work on the layouts nixarchy supports: flake root or
  `hosts/<hostname>` (`flake_base`, `:1254-1258`), flake in `/etc/nixos` or
  wherever `NIXARCHY_FLAKE` points.
- Must leave the user's hand-written declarations alone, say which scope
  every write went to, and report a conflict it detects (the same option set
  in two places). The same package in both `environment.systemPackages` and
  `home.packages` is legal (two profiles, `modules/home.nix:1108-1109`), so
  it is shown, not refused.
- Option discovery must not make the panel hang. Anything that evaluates the
  flake is bounded, cached and invalidated honestly, like the index (#41).
- Never evaluates or builds on p510 without the owner's OK.

## Open questions

1. **Home Manager as a NixOS module only, or standalone too?** The
   installer sets up the NixOS module (`installer/host.nix:212-220`), so one
   `nh os switch` covers both scopes. nixarchy's HM module also supports
   standalone use (`modules/home.nix:3-6`), so such machines may exist.
   Supporting them means a second switch command, a second flake output to
   find, and a scope applied without root. Recommended, as a scope decision
   for this issue: NixOS module only; on a standalone setup, refuse
   user-scope operations with a clear message and keep system scope working.
2. **Where do user-scope files live, and who imports them?** For example a
   `~/.config/nixarchy/home.nix` that apply copies like the others, and that
   nixarchy imports under `home-manager.users.<user>` (needs nixarchy's
   `nixarchy-apps.nix` generation to change). Or one file with both scopes
   in it. Separate file is simpler to reason about; it is also a new file in
   the user's flake.
3. **Which user?** `programs.nixarchy.user`, the user running the panel, or
   any user in `home-manager.users`? Recommended: the user running the panel,
   and refuse if they are not in `home-manager.users`.
4. **How are options discovered, and at what cost?** Choices: evaluate the
   host's `options` (and the HM submodule's) from the user's flake at
   reindex time and cache the result (sees edits before apply, costs an
   evaluation); ask nixarchy to build fuller documentation from the host's
   evaluated options into the system (cheap to read, only as fresh as the
   last apply, missing before the first); or read nixarchy's existing
   `/etc/nixarchy/options.json` as well (cheap, nixarchy's options only).
   Either of the first two can see the user's own modules; per-user HM
   imports need extra work in both. The fork is freshness, cost and
   availability before apply. Full-documentation cost is unmeasured (names
   alone: 3.6 s warm). Recommended: measure first, in the spec.
5. **Do the writers stay in nixarchy?** Today every package and toggle write
   goes through a nixarchy writer. User scope either needs new nixarchy
   writers (companion issue, slower), or the adapter writes the new file
   itself as it already does for `opt set`. Recommended: decide in the spec,
   after the file layout.
6. **Split the issue?** Scope (writes) and discovery (search) are separable,
   and discovery helps system scope on its own. Recommended: one intent, two
   specs or two PRs, discovery first.
