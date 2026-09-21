---
title: Getting started
---

# Getting started

There are two ways nixarchy ends up on a machine, and they are different
enough to matter here. Find yours first.

## Which one do you have?

```bash
nixarchy channel
```

If that command exists, nixarchy is installed. Now: did you install NixOS
*from the nixarchy ISO*, or did you already have a NixOS configuration and
add nixarchy to it as a flake input?

**Most people are the second one.** If your `flake.nix` has a line like

```nix
nixarchy.url = "github:olafkfreund/nixarchy";
```

in a flake you wrote yourself, that is you.

Both work. The difference shows up in exactly one place —
[what this manages and what it leaves alone](how-it-works) — and it is worth
reading before you wonder where your packages went.

## Install the plugin

In your Home Manager configuration:

```nix
{
  inputs.nixarchy-pkg.url = "github:olafkfreund/nixarchy-pkg";

  programs.nixarchy.plugins.nixarchy-pkg.src =
    inputs.nixarchy-pkg.packages.${pkgs.system}.default;
}
```

Rebuild, then enable it:

```bash
omarchy plugin enable nixarchy.pkg
```

## Give it a key

Nothing binds one for you. Pick a chord that is free —
`omarchy menu keybindings --print` lists what is taken, and `SUPER+SHIFT+N`
is a common clash with nvim.

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + ALT + N", "nixarchy packages",
       "omarchy-shell shell toggle nixarchy.pkg '{}'")
```

There is also a menu row. `share/omarchy-menu.jsonc` in the repository has
two rows to paste into `~/.config/omarchy/extensions/omarchy-menu.jsonc` —
one under **System**, one under **Learn** for the key sheet. Nothing writes
that file for you; nixarchy leaves it alone on purpose, and
`nixarchy doctor` fails a run that finds it symlinked or unwritable.

## The whole loop, in under a minute

<video src="../img/tour.webm" autoplay loop muted playsinline width="620"
       aria-label="The six tabs, a search of nixpkgs, a package queued, and a flake's modules listed">
  <img src="../img/tour.gif" width="620"
       alt="The six tabs, a search of nixpkgs, a package queued, and a flake's modules listed">
</video>

Nothing in that recording was installed. A package was picked, the footer
said *1 change queued*, and that is where it stopped — the rebuild is the
next keystroke and a deliberate one.

## Install one package

Open it. `SUPER+ALT+N`, or the menu row.

1. Press `l` twice, or `→` twice, to reach **Selection**.
2. Press `/` and type `ripgrep`.
3. Press `RETURN` on the row you want.

Nothing has been installed. Look at the bottom of the card: it now says
**1 change queued**, and there is a number in your bar. What happened is
that one line was written into `~/.config/nixarchy/apps.nix`:

```nix
ripgrep  #@pkg ripgrep
```

That is the whole of it. A file you own, one line, with a marker saying who
wrote it.

4. Press `a`, and `a` again. The first press only says what will happen
   -- a rebuild of the whole system -- and any other key cancels it.

Now it builds. The card fills with the build log — this is `nixarchy-apply`,
and it will ask for a password through your polkit agent. When it finishes,
`rg` is on your PATH and the bar is clear.

That is the loop. Everything else in this manual is a variation on it.

## If `a` does nothing useful

Press `SHIFT+A` instead. That runs the same apply in a real terminal, which
is the route for a machine with no polkit agent to answer the password
prompt, and for any build that asks a question the panel cannot show you.
[Applying changes](applying) has the detail.
