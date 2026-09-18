---
title: How it works
---

# How it works

Three files, a marker, and a boundary. Worth ten minutes once, because it
answers most of the questions people arrive with.

## The three files

```
~/.config/nixarchy/apps.nix        packages, apps, options, drafts
~/.config/nixarchy/services.nix    services
~/.config/nixarchy/advanced.nix    the rest
```

They are yours. They are ordinary NixOS modules, fully populated with every
app and every service, almost all of it commented out. Turning something on
uncomments a line; adding a package inserts one.

You can edit them in a text editor and the panel will show your edit next
time it reads them. Nothing is cached, nothing is remembered.

## The marker

Every line this tool writes carries one:

```nix
ripgrep  #@pkg ripgrep
pkgsOther.btop  #@pkg-other btop
services.tailscale.enable = true;  #@ tailscale
```

The marker is a contract, and four separate programs depend on it:
`nixarchy-pkg-add` writes it, `nixarchy-pkg-remove` deletes by it,
`nixarchy doctor` counts `#@pkg-other` to report what the other channel is
costing you, and the search picker reads it.

Its practical effect: **this tool only ever removes lines it wrote**. Move a
marked line somewhere else in the file and removal still finds it. Delete the
marker and the line becomes yours — the panel stops listing it and stops
being able to touch it.

## The boundary

This is the part that surprises people, so here it is plainly.

**The panel manages a selection. It does not manage your machine.**

If you had a NixOS configuration before nixarchy — and if you adopted
nixarchy as a flake input rather than installing from the ISO, you did — then
your own `environment.systemPackages`, your own modules, your own overlays
are none of this tool's business. They are not listed, not counted, not
touched.

One real machine: 965 packages declared across 128 files of its owner's
configuration, and one package in the selection. The Selection tab shows one
row. It is right.

### Why it is like that

Because the alternative is worse in two directions.

**Listing them** would mean evaluating your whole configuration — measured at
about three seconds on that machine, against a panel that opens instantly —
and `environment.systemPackages` is a merged list by the time anything can
read it, so those rows would carry no file and no line. They would be rows
nothing could act on, sitting in a list where every other row acts.

**Managing them** would mean this tool writing into files it did not create,
in a configuration whose shape it cannot predict, where a bad edit fails the
evaluation of the entire system rather than one line.

### What it buys you

Clean removal. The whole selection hangs off a single import line in your
host configuration. Take that line out and everything nixarchy added goes
with it, and nothing is orphaned anywhere else in your config.

That is a real property, and it is the one the boundary is protecting.

### The trap it leaves

If a package is in your own configuration **and** in the selection, removing
it here removes it from the selection and it stays installed. The panel
reports the removal truthfully. It removed what it manages.

Nothing detects this, because detecting it needs the evaluation ruled out
above. Knowing about it is the mitigation.

## What applying actually does

`nixarchy-apply` copies the three files into your flake directory — to
`hosts/<hostname>/nixarchy/` if that exists, beside the flake otherwise — and
rebuilds.

The copy exists because a flake cannot read a file outside its own tree.
Comparing your files against that copy is what produces the queued count, and
it is an honest answer to "what would apply change?" rather than something
this tool remembers.

## Where the writing happens

Nowhere in this plugin, with one exception.

`nixarchy-app-enable`, `nixarchy-pkg-add`, `nixarchy-opt-remove`,
`nixarchy-apply` and the rest ship with nixarchy. They own marker placement,
catalogue drift, unfree policy, the channel escape, backups and the parse
check. This plugin calls them and draws the result — and it is told the new
state rather than predicting it, because a panel that assumed success would
sooner or later draw a lie.

The exception is setting an option's value, which this plugin writes itself,
with its own backup and its own parse check.
