---
title: What this is
---

# nixarchy.pkg

A menu for the thing NixOS is good at and awkward about: **changing what is
installed**.

On Arch you type `pacman -S ripgrep` and it is there. On NixOS you edit a
file, then rebuild, and *then* it is there. That second step is the whole
point — it is why you can roll the change back, why the machine is
reproducible, and why nothing drifts. It is also why "install ripgrep"
stopped being one action and became two.

This plugin is the first of those two, on screen. It searches nixpkgs, turns
curated apps and services on and off, sets NixOS options with a form built
from each option's declared type, and shows you what is waiting. Then you
press `a` and the second step happens.

It writes nothing you cannot read. Every change is one marked line in a file
you own, and every write goes through a script nixarchy already ships.

## Start here

**[Getting started](getting-started)** — which of the two installs you have,
and one package installed by the end of it.

Then the surface you are looking at:

| | |
| --- | --- |
| [The menu](the-menu) | Tabs, the list, the message line, the queue |
| [The bar widget](the-bar) | The number in your bar, and why it exists |
| [Apps and services](apps-and-services) | The curated catalogue, and `SPACE` |
| [Packages](packages) | Searching nixpkgs, and what "Selection" means |
| [NixOS options](options) | 25,000 options, and why some get a comment instead of a widget |
| [Drafts](drafts) | Software nixpkgs does not carry |
| [Flakes](flakes) | Software that is not in nixpkgs and ships its own flake |
| [Applying changes](applying) | `a`, `SHIFT+A`, and the build log |
| [From a terminal](from-a-terminal) | The same commands, without the panel |
| [How it works](how-it-works) | Selection files, markers, and what is *not* managed |
| [Troubleshooting](troubleshooting) | It said no. Nothing happened. It is still installed. |

## What it is not

A package manager. It is a front end to
[nixarchy](https://olafkfreund.github.io/nixarchy/manual/)'s own writers —
`nixarchy-app-enable`, `nixarchy-pkg-add`, `nixarchy-opt-remove`,
`nixarchy-apply` — which already handle marker placement, catalogue drift,
unfree policy, the stable/unstable channel escape, backups and the parse
check. This is the part you look at.

It also manages **a selection**, not your machine. If you already had a NixOS
configuration before you met nixarchy, the packages you declare there are not
listed here and are not touched here. That boundary is deliberate and it is
what makes nixarchy removable. [How it works](how-it-works) explains it
properly, because it is the single thing people misread.
