---
title: Apps and services
---

# Apps and services

The first two tabs are a catalogue: about 64 apps and a set of services that
nixarchy knows how to install *properly*, rather than as a bare binary.

![Apps, by category](../img/01-apps.png)

## Why a catalogue at all

Because "install Firefox" and "install the `firefox` package" are not the
same thing on NixOS.

The package gets you a binary. The NixOS module gets you the binary plus its
policies, its defaults, and whatever integration the module author wrote —
for Firefox that means enterprise policies and declarative extensions. Same
name, different outcome, and the better one is not the one you would guess.

So the catalogue maps each row to how NixOS actually installs that thing.
Some rows are plain nixpkgs packages, some are NixOS modules, some are built
by nixarchy because nixpkgs does not carry them at all, and a couple have no
NixOS equivalent and say so in the row rather than pretending.

Each row shows the line it will write. That is not decoration — it is how you
tell a module row from a package row before you pick it.

## Turning one on

`SPACE`, on the row under the cursor.

Nothing is installed. One line in `~/.config/nixarchy/apps.nix` (or
`services.nix`) stops being a comment and starts being configuration. `SPACE`
again comments it back out.

The state you see is read from the file every time, not remembered. Two
panels open at once cannot disagree about which way the toggle goes.

## Filtering

![Filtering the catalogue](../img/02-apps-filter.png)

`/` here filters what is already listed, instantly, and keeps the on/off
state. That is different from Selection and Options, where `/` searches an
index of a hundred thousand things and replaces the list.

The difference is deliberate: a catalogue of sixty-odd rows is something you
can read, so narrowing it should not cost you the information you came for.

## Services

![Services](../img/03-services.png)

The same idea, for daemons. Some rows are nixarchy bundles — a service plus
the handful of options that make it useful — and some are the plain upstream
option. The line beside each row tells you which.

A service that is *not* in this catalogue is not missing. It is just options,
and [the Options tab](options) is how you reach it. There are over 2,000
`services.*.enable` options in nixpkgs and a curated list was never going to
be all of them.

## `.settings` rows

A row drawn with `≡` is not an app. It is the attrset that configures one —
`firefox.settings` next to `firefox`.

`SPACE` and `RETURN` on it do nothing except tell you so, and point you at
the file. That is on purpose: the writer would refuse it, correctly, and a
refusal on screen reads like something broke. Answering the question here
instead is the honest version.
