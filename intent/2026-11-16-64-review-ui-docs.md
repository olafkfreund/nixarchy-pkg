---
status: approved
issue: 64
author: olafkfreund
---

# Intent: the panel and its manual say what is true, and the ways to open it never fail silently

## Problem

The 2026-11-15 review found a set of smaller faults. Each is checked here on
main (`d3aabd3`). One item is already fixed on the unmerged
`feat/60-truthful-queue` branch, and is dropped from this task (see the end
of this section).

**1. The key binding and the menu row do nothing, and say nothing, when the
plugin is disabled.** `README.md:157` and `docs/manual/getting-started.md:60`
tell users to bind `omarchy-shell shell toggle nixarchy.pkg '{}'`. The menu
row the README and manual tell users to paste in
(`share/omarchy-menu.jsonc:32`, referred to at `README.md:169-170` and
`getting-started.md:63-64`) runs the same command, with no `when` check.
When the plugin is not enabled, the shell only logs
`summon: plugin not enabled`, and the user sees nothing happen. nixarchy
ships `nixarchy-plugin`, which notifies instead. Its own menu uses it for
other plugins (`/etc/nixarchy/omarchy-menu.jsonc:1249`). #60 touches none of
these lines.

**2. Apps and Services rows describe themselves badly.**
- A row with no note shows its raw Nix line as its description.
  `Card.qml:232-233` falls back from `summary`, `note` and `type` to
  `modelData.line`, so the user reads `x.enable = true;`.
- `.settings` rows sit in the Apps list among the apps. They are drawn with
  a different glyph, not a toggle box (`Card.qml:150-156`), and activating
  one explains where to edit it (`PkgModel.qml:368-375`). But they are mixed
  in with things that can be turned on, and are counted and searched as
  such.
- `README.md:21` says the Apps and Services tab shows "the curated
  catalogue by category". The card has no category grouping. Category
  appears only as a description fallback (`Card.qml:233`) and as a search
  field (`PkgModel.qml:152`).

**3. Selection rows show bare names.** A package the user added shows its
attribute only: no version, description or channel. The adapter does read
the channel: `extras_tsv` tags `#@pkg-other` lines as `other`
(`bin/nixarchy-pkg:333`). The QML never shows it. Two limits matter here:

- The search index carries a version (in its preview text) and `unfree`
  and `broken` flags, but no `insecure` flag. The index walk
  (`pkg-index.nix` in nixarchy) emits only attr, version, description,
  homepage, licence, unfree and broken. Marking a package insecure needs a
  change in nixarchy first.
- The index describes this machine's nixpkgs. A package taken from the other
  channel can have a different version and flags there.

**4. A multi-word search is matched as one substring.** `ssh server` matches
only text containing exactly that phrase. The package and option search does
this in `cmd_search`'s awk (`index(name, lq)`, `bin/nixarchy-pkg:407-408`),
and the Apps/Services filter does it in `PkgModel.filtered()`
(`PkgModel.qml:146-153`).

**5. A reindex blocks every panel write for about a minute.**
`PkgModel.reindex()` (`PkgModel.qml:554`) goes through `write()`, which sets
`busy` (`PkgModel.qml:350`). Every toggle, option, flake change or apply
started from the panel is then refused until the reindex ends. The
adapter's `cmd_reindex` (`bin/nixarchy-pkg:1454`) writes only the search
cache and does not take the write lock, so this block exists only in the
panel.

**6. The manual gives wrong advice in five places.**
- `docs/manual/from-a-terminal.md:44-47`: under "Everything unfree in your
  selection" the command is `.packages[].attr`, which lists every package.
  It is still wrong on #60's branch.
- `docs/manual/options.md:56-57` says complex options are written
  "**commented out**". The form shows the example in a text box. If the
  user edits it, the text is written as a live value (`OptionForm.qml:263`,
  `:283`). If they do not, nothing is written (`OptionForm.qml:244`). #60
  does not touch this file.
- "Press `SHIFT+A`" when `a` seems to hang, in
  `docs/manual/troubleshooting.md:56`, `applying.md:36` and
  `getting-started.md:111`. While an apply runs, `applyInTerminal()`
  refuses with "an apply is running" (`PkgModel.qml:643`). While the build
  log is on screen, the key never reaches it: `Menu.qml:190-201` takes every
  key except `ESC` and scrolling. #60 keeps this advice.

**7. Tests that do not run where they could, and parts that have none.**
CI runs `bash tests/adapter.sh` (`.github/workflows/ci.yml:28`), but
`nix flake check` only shellchecks it (`flake.nix:63`). #59's approved
intent asked for `nix flake check` to run it, and main still does not.
Running it in the Nix sandbox is not just a matter of adding a check: its
flake cases lock a `github:nixos/nixpkgs` input (`fresh_flake`,
`tests/adapter.sh:137-144`), which needs the network, and it needs `git`,
`flock` and `nix` too. The QML checks run `tst_pkgmodel.qml` and
`tst_card.qml` (`flake.nix:98-109`). `Menu.qml`, `OptionForm.qml` and
`Panel.qml` have no behavioural tests.

**Already fixed by #60, dropped here.** `from-a-terminal.md:41` uses
`.changes[].id`, which has no such field. `feat/60-truthful-queue` changes it
to `.changes[].marker`. #60 also rewrites the `getting-started.md` apply step
and adds troubleshooting sections. This task must build on those edits, not
redo them.

## Proposed outcome

For the items Open question 1 keeps in this task:

- Pressing the bound key, or choosing the menu row, with the plugin disabled
  tells the user so, the way nixarchy's own plugin keys do. The README, the
  manual and `share/omarchy-menu.jsonc` give that command.
- Every Apps and Services row has a readable description, or none. No raw
  Nix line is shown as a description. `.settings` rows are not mixed in
  with the apps a user can turn on. The catalogue is grouped by category, as
  the README says, or the README stops saying so.
- A selection row shows its channel, and whatever else the adapter can know
  about it truthfully. It never shows metadata from one channel for a
  package taken from the other.
- A search for several words finds rows that contain all of them, in any
  order.
- A reindex never stops the user from writing their selection.
- Every passage listed in item 6 is corrected. Every command the manual
  shows does what its heading says.
- `nix flake check` runs the parts of `tests/adapter.sh` that can run
  without a network or a catalogue.

## Affected users and systems

- Everyone who uses the panel, and everyone who copies the key binding or
  menu row from the README.
- `Card.qml`, `PkgModel.qml`, `Menu.qml`, `bin/nixarchy-pkg` (`cmd_search`,
  `extras_tsv`, possibly `cmd_state`), `share/omarchy-menu.jsonc`,
  `README.md`,
  `docs/manual/{getting-started,from-a-terminal,options,troubleshooting,applying}.md`,
  `flake.nix` checks, `tests/`.
- Overlaps `feat/60-truthful-queue` in `from-a-terminal.md`,
  `getting-started.md`, `troubleshooting.md`, `applying.md` and
  `PkgModel.qml`. This task should land after #60 merges, or be rebased
  onto it.
- Outside this repo: marking insecure packages needs nixarchy's index walk
  to carry the flag.
- Verification host is **razer**, per repo convention.

## Constraints

- Selection edits stay in the user's own Nix files and need no elevation.
  Only an explicit apply rebuilds, and only it elevates (through
  `nixarchy-apply`). The writers' existing safeguards stay as they are.
- The adapter's JSON contract (`docs/manual/from-a-terminal.md`, "What is
  stable") may gain fields but must not lose or rename one.
- A reindex must stay safe beside a write. It updates only the user's cache,
  and must keep doing so if it stops going through the panel's writer.
- No new runtime dependency. The panel must not evaluate nixpkgs to show a
  selection row.
- The documented binding and menu row must work on a stock nixarchy machine
  (`nixarchy-plugin` is in `/run/current-system/sw/bin`).

## Open questions

1. **One task or several?** These seven items touch different files and
   carry different risk. The docs, the key binding and the menu row are
   small. Multi-word search, selection metadata and the QML tests are each a
   real change. Recommended: keep 1, 2, 4, 5 and 6, and the `nix flake check`
   half of 7, here. Split 3 (selection metadata, with the nixarchy change
   for `insecure`) and the Menu/OptionForm/Panel tests into their own
   issues.
2. **Category grouping: build it, or stop promising it?** Recommended:
   build it. The adapter already sends `category` with each row.
3. **What may a selection row show when the index cannot vouch for it?**
   (A package from the other channel, or a stale index.) Recommended: the
   channel always, and description or version only when they come from the
   same nixpkgs the package does; otherwise nothing extra.
4. **Multi-word search: must every word match?** Recommended: yes, every
   word, in any order. Ranking is left to the spec.
5. **How much of `tests/adapter.sh` must `nix flake check` run?**
   Recommended: the sections that need neither network nor catalogue, with
   the flake cases kept to CI, rather than reworking them to run offline in
   this task.
