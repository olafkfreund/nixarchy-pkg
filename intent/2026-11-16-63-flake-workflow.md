---
status: draft
issue: 63
author: olafkfreund
---

# Intent: the Flakes tab finishes what it starts

## Problem

#3 gave the panel a Flakes tab: inspect a flakeref, declare it as an
input with one marked top-level `inputs.<name>.url` line that Nix merges
into the user's own `inputs` (which it never edits,
`bin/nixarchy-pkg:909-914`), lock it, and show the import line instead of
guessing which host file it belongs in
(`intent/2026-09-17-3-flake-input.md`). #29 fixed input names and made
removal refuse an input something depends on
(`intent/2026-09-21-29-flake-names-and-remove.md`). Both kept the write
to what is the same in every flake, and that rule still stands. Within it, the tab stops short of what a person needs
to finish the job, and some of what it does show is wrong.

**The input it writes is not the input best practice writes.**
`flake add` writes one `inputs.<name>.url = "…";` line
(`bin/nixarchy-pkg:1116`). It never writes
`inputs.<name>.inputs.nixpkgs.follows = "nixpkgs";`, so an input that
depends on nixpkgs locks its own copy. That can mean a second nixpkgs to
fetch and evaluate, and modules built against a different nixpkgs than
the host. It cannot
declare a non-flake source (`flake = false`), and there is no way to
update one input (`nix flake update <name>`) without a terminal.

**It shows that a flake has packages, but not which, and nothing about
overlays.** The adapter reads the package names, merged across every
system the flake builds for (`bin/nixarchy-pkg:1032-1033`), but the tab
shows only a count (`PkgModel.qml:128`). Overlays are not read at all. A person who wants
one package from a flake learns that there are some, and must go to a
terminal to find its attribute and the line to write.

**The import line it promises is never shown after a declare.**
`flake add` answers with `import` and `importNote`
(`bin/nixarchy-pkg:1144-1149`), and the manual says "It shows you the
import line" (`docs/manual/flakes.md:94-100`). `PkgModel._absorb` reads
only `message` from an answer without `apps` and drops the rest
(`PkgModel.qml:279-283`). The hint exists only on an inspected module
row before declaring (`:391-394`). The answer itself is unconditional:
it always names `inputs.<name>.nixosModules.default`
(`bin/nixarchy-pkg:1148`), even for a flake that has no such module.

**The tab lists only inputs this tool declared.** `flake list` matches
lines ending in `#@flake-input <name>` (`bin/nixarchy-pkg:1242-1247`).
An input written by hand, by the installer, or as a block
(`home-manager = { url = …; inputs.nixpkgs.follows = …; };`) does not
appear, so the tab says "no inputs" on a flake that has ten. A declared
input is removed on one key with no confirmation (`PkgModel.qml:389`),
which rewrites `flake.nix` at once and runs `nix flake metadata`
(`bin/nixarchy-pkg:1224-1230`).

**The search box is shared across tabs.** `setTab` keeps `query`
(`PkgModel.qml:202-212`), and on the Flakes tab `RETURN` inspects
whatever the box holds (`:444-448`). An Options query such as
`services.openssh` arrives on Flakes as a flakeref to fetch, and a
flakeref typed on Flakes is searched as a package when switching back
(`:212`).

**Smaller gaps.**

- `machine_channel` reads only `nixpkgs.url = "…"` inside a block
  (`bin/nixarchy-pkg:1281-1282`). The flat form
  `inputs.nixpkgs.url = "…"` lands on `custom`. It copies
  `nixarchy-pkg-add`'s parse on purpose (`:1264-1271`), so the writer
  has the same blind spot, and says so (`nixarchy-pkg-add`, its
  comment at about line 94: "the equally valid flat form … does not
  match").
- When the channel is `custom`, "add from the other channel" says it
  cannot tell which channel this would come from, and on the second
  `SHIFT+RETURN` does an ordinary `pkg add` (`PkgModel.qml:425`,
warning at `:431-437`).
  The person asked for the other channel and gets this one.
- The flake directory is `${NIXARCHY_FLAKE:-/etc/nixos}` everywhere
  (`bin/nixarchy-pkg:949`, `:1085`, `:1162`, `:1243`, `:1256`, `:1279`),
  and `NH_FLAKE`/`FLAKE` are ignored. That matches `nixarchy-apply`,
  which reads the same variable (its line 51) and ignores `NH_FLAKE` on
  purpose, because people export it at whatever flake they happen to
  work on (its comment at about line 520). The gap is that the panel
  never says which directory it is using, so a user whose flake lives
  elsewhere and has not set `NIXARCHY_FLAKE` in the session the panel
  runs in sees an empty tab, or a stale `/etc/nixos` one, with no hint
  why.

## Proposed outcome

- A declared input can follow the machine's `nixpkgs`, when both the
  user's flake and the added flake have a `nixpkgs` input (the default
  is open question 1). A non-flake source can be declared, including one
  that `nix flake show` cannot read. One input can be updated from the
  panel, and the panel says what moved in the lock, or that nothing did.
- After inspecting a flake, the person can see its packages for this
  machine's system by name and get the exact reference to use one, the
  way the import line is shown today. Overlays are open question 4.
- After a declare, the import line and its note are shown, as the manual
  says, but only for a module the flake was seen to offer. No line is
  shown for a module that does not exist.
- The tab lists every input the flake declares, marked by whether this
  tool wrote it. Only inputs this tool wrote can be removed from the
  panel, and removing one asks first.
- Switching tabs never carries a query from one tab into another tab's
  meaning. A flakeref is never fetched because of text typed elsewhere.
- The flat `inputs.nixpkgs.url` form is recognised as a channel, by this
  panel and by the writer it mirrors. "From the other channel" with an
  unknown channel refuses instead of adding from this one.
- The panel uses the same flake directory as `nixarchy-apply`, says
  which one it is, and says how to change it.
- Tests cover each of these.

## Affected users and systems

- Anyone adding a flake input from the panel or with `nixarchy-pkg
  flake`. Most exposed: people whose flake has its own inputs block
  layout, or lives outside `/etc/nixos`.
- `bin/nixarchy-pkg`: `cmd_flake_add`, `cmd_flake_remove`,
  `cmd_flake_list`, `cmd_flake_show`, `machine_channel`, `flake_base`,
  the flake directory, a new update command.
- `PkgModel.qml` (`_absorb`, `flakeRows`, `setTab`, `addFromOtherChannel`,
  remove), `Card.qml`, `Panel.qml` (confirm, detail).
- Outside this repo: `nixarchy-pkg-add`'s channel parse
  (`nixarchy-pkg-add:80-88`) and `nixarchy-apply`'s flake directory,
  which must agree with this panel. That may need a companion nixarchy
  issue.
- `tests/adapter.sh`, `tests/qml/`, `docs/manual/flakes.md`.
- Verification host is razer, per repo convention.

## Constraints

- The panel never edits the user's own `inputs { }` block. It writes
  only top-level `inputs.<name>.*` lines it marks as its own, every line
  for an input carries that input's marker (so `list`, `remove` and the
  dependency check all agree on what it owns), and it never wires a
  module or package into a host. #3's rule
  holds: what cannot be known everywhere is not written anywhere. The
  package and overlay lines are shown, not written.
- It never edits or removes the declaration of an input it did not
  write. Updating that input's lock entry is open question 3.
- `follows` is written only when the user's flake has the target input
  and the added flake is a flake that has the input being overridden;
  otherwise Nix fails or warns.
- No root and no `sudo`. Apply is the only thing that rebuilds. An
  update rewrites `flake.lock` and nothing else, and does not build.
- #59's write discipline (lock against apply, backup, restore, recover,
  `flake.nix` and `flake.lock` byte-identical on failure) covers every
  new write, `nix flake update <name>` included.
- The channel parse must stay the same as the writer's. Changing one
  without the other is the disagreement `machine_channel`'s comment
  warns about.
- Network calls stay bounded (`timeout 120` as today) and are never made
  for text the person did not mean as a flakeref.

## Open questions

1. **`follows` by default?** Recommended: yes when both flakes have a
   `nixpkgs` input, with a way to opt out per input. Cost: a flake that
   needs its own pinned nixpkgs breaks or misbehaves until the person
   opts out. Alternative: offer it, default off.
2. **Honour `NH_FLAKE`/`FLAKE` at all?** Recommended: no.
   `nixarchy-apply` ignores them deliberately, and a panel that wrote
   one flake while apply built another is worse than an empty tab. The
   panel names the directory it uses and points to `NIXARCHY_FLAKE`
   instead. Reading them would need the same change in nixarchy first.
3. **Update inputs this tool did not write?** `nix flake update
   <name>` touches only `flake.lock`, so it could apply to every listed
   input, `nixpkgs` and `nixarchy` included. Recommended: yes, with a
   confirmation, since updating `nixpkgs` changes the whole system on the
   next apply. Alternative: only inputs this tool wrote.
4. **Overlays.** `nix flake show` lists overlay names but not what they
   change. Show names only, with the line to add one, or leave overlays
   out of this task?
5. **Channel parse in `nixarchy-pkg-add`.** Fix the writer upstream
   first, or here first with a companion issue? Fixing only the panel
   breaks the "same parse" rule.
6. **Must a declared input be inspectable again?** Today the inspected
   outputs are dropped when the input is declared, and listed inputs have
   no inspect action. Recommended: yes, so the module, package and
   overlay lines can be shown with the name actually declared.
