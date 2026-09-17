# nixarchy.pkg

Search nixpkgs, turn apps and services on, set NixOS options, and apply —
from the Omarchy shell, on the keyboard.

An [Omarchy](https://omarchy.org) plugin for
[nixarchy](https://github.com/olafkfreund/nixarchy). Installing software on
nixarchy otherwise means a floating terminal and an fzf picker, or editing
`~/.config/nixarchy/apps.nix` by hand and finding the right commented-out
line. Every other surface on the desktop — the menu, herdr, nixi — is a
chord and a list. This makes package management one too.

![the menu](assets/screenshot.png)

**[See every surface →](assets/showcase/)** — Apps, Services, nixpkgs search with
unfree and curated flags, the NixOS option forms, the key sheet and the bar
widget, all driven from the keyboard on a real machine.

## What it does

- **Apps and Services** — the curated catalogue by category, with each entry's
  note, showing what is on, off and queued. `SPACE` toggles.
- **Packages** — the whole nixpkgs index, with `unfree` and `broken` flagged
  before anything is queued, and a warning when the curated app list already
  covers a name (the app row gets you the module; the bare package gets you a
  binary).
- **Options** — every NixOS option, with its type, default and documentation,
  and a form built from the declared type.
- **Drafts** — derivations for software nixpkgs does not carry.
- **Queue, then apply.** A toggle edits a file. Nothing is built until you
  press `a`.

`?` shows every key.

## What it is not

A package manager. Every write goes through a script nixarchy already ships —
`nixarchy-app-enable`, `nixarchy-service-enable`, `nixarchy-pkg-add`,
`nixarchy-opt-remove`, `nixarchy-apply` — which already handle marker
placement, catalogue drift, unfree policy, the stable/unstable channel
escape, backups and the parse check. This plugin is a front-end, and
`bin/nixarchy-pkg` is the whole of its contact with the machine.

It writes to `~/.config/nixarchy/apps.nix` and `services.nix` and nowhere
else — never `/etc/nixos`, never the copy under the flake.

## The option forms, honestly

Booleans, enums, integers and simple strings get a real widget. Lists,
`null or T`, attribute sets, submodules and functions do not: an option's
value is arbitrary Nix, and a form that pretended otherwise would write
plausible-looking wrong configuration. Those show the option's own example
as a starting shape to edit.

**A field you do not touch writes nothing.** The value shown is the option's
default; leaving it alone keeps the default, because a copied-out default is
a line that reads as a decision and is not one.

## Install

```nix
{
  inputs.nixarchy-pkg.url = "github:olafkfreund/nixarchy-pkg";

  # in your Home Manager configuration:
  programs.nixarchy.plugins.nixarchy-pkg.src =
    inputs.nixarchy-pkg.packages.${pkgs.system}.default;
}
```

Then enable it and bind a key:

```bash
omarchy plugin enable nixarchy.pkg
```

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + SHIFT + N", "nixarchy packages",
       "omarchy-shell shell toggle nixarchy.pkg '{}'")
```

Nix installs the plugin; enabling it stays runtime state in `shell.json`,
deliberately.

## Applying

`nixarchy-apply` asks two questions on stdin and then runs `nh os switch`,
which elevates itself — and a QML process has no terminal for a password.
The adapter runs it with `NH_ELEVATION_STRATEGY=pkexec`, so the prompt is
drawn by Omarchy's own polkit agent, in the same shell the panel lives in.

`ESC` while a build is running stops watching the log. It does not stop the
build: it is elevating, downloading and switching a system, and stopping half
way is never what reaching for `ESC` meant.

## Development

```bash
nix build .#default                     # the plugin, as the shell sees it
omarchy plugin validate ./result
nix flake check                          # shellcheck, manifest, no hex colours
bash tests/adapter.sh                    # the adapter, on a throwaway config
```

`tests/adapter.sh` builds a fresh `XDG_CONFIG_HOME` from
`/etc/nixarchy/*-template.nix` for every case, so a failing test cannot leave
your own selection edited.

Two things that will cost you an afternoon otherwise:

- `omarchy plugin validate` **refuses any symlink inside a plugin folder**,
  so the derivation is `runCommand` + `cp`, never `symlinkJoin` or a wrapped
  binary — and a plugin installed as a symlink for development will not
  validate either.
- `omarchy-shell shell rescanPlugins` does **not** reload a plugin reached
  through a symlink. Install it as a real directory and use
  `omarchy-restart-shell`.

## Licence

MIT.
