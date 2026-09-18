---
layout: home
---

A menu for the thing NixOS is good at and awkward about: **changing what is
installed**.

It searches nixpkgs, turns curated apps and services on and off, sets NixOS
options with a form built from each option's declared type, and shows you
what is waiting. Nothing is built until you press `a` — and what comes out is
a NixOS generation, so it rolls back.

![A tour of the menu: the five tabs, searching nixpkgs, and one package queued](img/tour.gif)

**[Read the manual →](manual/)**

---

It writes nothing you cannot read: every change is one marked line in a file
you own, and every write goes through a script
[nixarchy](https://olafkfreund.github.io/nixarchy/manual/) already ships.

It manages a *selection* rather than your machine, which is the one thing
worth knowing before you start — [why that is, and what it
buys you](manual/how-it-works).

[Source](https://github.com/olafkfreund/nixarchy-pkg) ·
[nixarchy's manual](https://olafkfreund.github.io/nixarchy/manual/)
