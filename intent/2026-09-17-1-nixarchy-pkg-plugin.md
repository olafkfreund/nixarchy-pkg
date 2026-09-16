---
status: draft
issue: 1
author: olafkfreund
---

# Intent: manage packages, services and options from the Omarchy shell

## Problem

Adding software to a nixarchy machine means leaving the desktop. The routes
today are a floating terminal running `nixarchy-search`'s fzf picker, or
opening `~/.config/nixarchy/apps.nix` in an editor and finding the right
commented-out line by hand.

Every other surface on this desktop works the other way round. The Omarchy
menu, `nixarchy.herdr` and `nixi` are all Quickshell panels: a chord, a list,
the keyboard, done. Package and service management is the one daily task that
still opens a terminal, and it is the task a new nixarchy user hits first.

The information a person needs in order to choose is also scattered. Whether
an app is already enabled lives in `apps.nix`; whether a package is unfree or
broken lives in the search index; what a service actually turns on lives in a
note in `/etc/nixarchy/services-template.nix`; what an option accepts lives in
`options.json`. Nothing puts them on one screen.

Configuring something is worse than installing it. A curated app exposes a
`settings` attrset and a service exposes the full upstream option tree, but
there is no path to either short of knowing the option path already and
writing Nix by hand. NixOS publishes the type, description, default and
example of every option, and none of that reaches the person choosing.

## Proposed outcome

A chord opens a pop-out. In it:

- Curated apps and services are listed by category, with their notes, showing
  what is on, what is off and what is queued. Space toggles.
- nixpkgs is searchable across every package, option and app, with unfree and
  broken flagged before anything is queued.
- A NixOS option can be found, read -- type, default, description -- given a
  value through a form built from its declared type, and written back.
- Changes accumulate visibly. Nothing builds until an explicit apply, and the
  build log is readable without leaving the panel.
- The whole thing is keyboard-driven and carries the active Omarchy theme.

Afterwards, installing a package, turning on a service or changing a setting
is something done from the desktop, and the terminal is a choice rather than
the only route.

## Affected users and systems

- Anyone running nixarchy with Omarchy Quattro; the plugin is opt-in and
  installed declaratively through `programs.nixarchy.plugins.<name>.src`.
- `~/.config/nixarchy/{apps,services,advanced}.nix` -- the only files written.
- The existing `nixarchy-*` writers and `nixarchy-apply`, called rather than
  reimplemented.
- The Omarchy shell process, which loads the plugin's QML unsandboxed.
- No change to the nixarchy repository itself is required for v1.

## Constraints

- **Must not reimplement the writers.** `nixarchy-app-enable`,
  `nixarchy-service-enable`, `nixarchy-pkg-add/remove`, `nixarchy-opt-remove`
  and `nixarchy-apply` already handle marker placement, catalogue drift,
  unfree policy, the `pkgsOther` channel escape, backups and parse-checking.
  A second implementation of any of that is a second set of bugs.
- **Must not leave a file unparseable.** Every write follows the existing
  idiom: backup, edit, `nix-instantiate --parse`, restore on failure.
- **Must not write outside `~/.config/nixarchy/`.** Not `/etc/nixos`, and not
  the flake copy under `$flake/nixarchy/`, which is `nixarchy-apply`'s output.
- **Must not build anything implicitly.** A toggle edits a file; only an
  explicit apply rebuilds the system.
- **Must carry the theme.** Colours come from the shell's tokens
  (`Color.menu.*`, `Style`, `BorderSurface`), never literals.
- **Must be usable without a mouse**, including the option forms.
- The plugin runs inside the shared Quickshell process with the user's full
  permissions. It must not start a second Quickshell, and anything it displays
  that came from a package description, a window title or a build log is
  plain text, never markup and never a shell string.
- Omarchy's plugin validator refuses symlinks inside a plugin directory, which
  constrains how the Nix package is built.

## Open questions

1. **Elevation.** `nixarchy-apply` asks two `y/N` questions on stdin and then
   runs `nh os switch`, which elevates itself. A QML `Process` has no tty, so
   a password prompt has nowhere to appear. Either an askpass helper routed to
   the polkit agent works, or applying hands off to a floating terminal. This
   must be settled before the apply path is designed, and it is the one thing
   that could change the shape of the feature.

2. **Where option values are written.** Nothing in nixarchy currently writes a
   *value* for an option -- the picker only adds a bare `#@opt <path>` line.
   `advanced.nix` is a bare NixOS module and exists for exactly this, but it
   means a configured option and a selected one live in different files.

3. **How far the generated forms should go.** NixOS option types are an open
   set. Booleans, strings, integers, enums and lists map cleanly; submodules
   and attribute sets do not, and fall back to a raw Nix field. Whether that
   fallback is acceptable for v1 decides how large this is.
