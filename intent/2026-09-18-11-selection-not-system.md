---
status: approved
issue: 11
author: olafkfreund
---

# Intent: the Packages tab shows a selection, and should say so

## Problem

On a machine that adopted nixarchy as a flake input -- which is most
people using this today, rather than the ISO install the design
assumed -- the Packages tab lists one package. The machine has 965 in
`environment.systemPackages`, declared across 128 files of the user's
own configuration. The obvious reading is that the panel has failed to
find the real NixOS config.

It has not. `/etc/nixos` on that host is a symlink to
`~/.config/nixos`, `flake_base` (`bin/nixarchy-pkg:517-522`) resolves
`hosts/<host>` correctly, and the applied copy is where it belongs. The
panel never looks: `extras_tsv` (`bin/nixarchy-pkg:146`) reads one file,
`~/.config/nixarchy/apps.nix`, and only lines carrying `#@pkg` or
`#@pkg-other`.

That is the design and the design is right. The marker is an editing
contract with four consumers -- `nixarchy-pkg-add` writes it,
`nixarchy-pkg-remove:46` deletes by it, `nixarchy-doctor:712` counts
`#@pkg-other` to report duplicated closures, and the Search picker
reads it. A row with no marker is a row nothing can act on. Confining
writes to files nixarchy owns is also what makes removal clean: on that
host the whole selection hangs off one import line in
`hosts/<host>/configuration.nix`, and deleting it orphans nothing.

So the defect is not the scope. It is that the panel describes the
scope inaccurately, and one word does most of the damage.

Every writer already uses the honest vocabulary.
`nixarchy-pkg-remove:68-69` notifies "<pkg> removed from your selection"
and "N extra package(s) still selected" -- a selection, never a system.
`PkgModel.qml:28` names the tab `Packages`, which is a claim about the
machine.

The gap between those two has a consequence worse than confusion. On
that host the single nixarchy-managed package is `azure-cli`, and the
user's own config declares it too, at `modules/cloud/packages.nix:37`
and `modules/packages/sets.nix:168`; evaluated, it is in
`systemPackages` twice. Removing it in the panel deletes the marked
line, reports success truthfully, queues a change, rebuilds -- and
leaves `azure-cli` installed. A false success, reachable today, on the
only row the panel has.

Detecting that collision would require evaluating the user's
configuration, which is the thing this issue argues against doing. The
answer is not to detect it. It is to stop implying it cannot happen.

The documentation has the same shape of gap. `README.md:44-45`
documents the write boundary exactly -- "It writes to
`~/.config/nixarchy/apps.nix` and `services.nix` and nowhere else". No
line anywhere documents the read boundary: what the tab lists, and what
it therefore does not.

## Proposed outcome

A new user, on the flake-adopter path, understands within one screen
that this panel manages a selection of its own rather than reporting
the machine -- without reading the README first.

Concretely, when this is done:

- The panel names what it lists as nixarchy's selection, in the tab and
  wherever a count is drawn, rather than as the machine's packages.
- A selection with few or no rows reads as an empty selection rather
  than as a failed scan. This is the moment the flake adopter currently
  misreads.
- Removing a package is worded so that it stays true when the same
  package is declared elsewhere in the user's configuration. The
  writers' wording already is; the panel's should match it rather than
  invent a second vocabulary.
- The README states the read boundary beside the write boundary it
  already states, and says plainly that packages declared elsewhere are
  neither listed nor managed, and that this is what makes uninstalling
  nixarchy clean.
- `bin/nixarchy-pkg-keys` does not contradict any of it.

Afterwards, the `azure-cli` outcome is still possible and is no longer
a surprise, because nothing promised otherwise.

## Affected users and systems

- Primarily people who adopted nixarchy as a flake input into a
  pre-existing configuration. They have a large config the panel does
  not describe, so they have the most to misread.
- ISO-installed users, where the selection is closer to the whole of
  what is installed and the wording is merely accurate rather than
  corrective.
- `PkgModel.qml:28` -- the tab names.
- `Card.qml` -- the counts and the message pane.
- `README.md`.
- `bin/nixarchy-pkg-keys`.
- Not `bin/nixarchy-pkg` and not the writers: no new source of rows, no
  change to the marker contract, nothing evaluated.

## Constraints

- **Must not widen what is listed.** Listing the user's own packages
  means evaluating their configuration -- measured at 3.3s warm on the
  host above, against a panel that opens instantly -- and
  `config.environment.systemPackages` is a merged list, so those rows
  would carry no file and no line and could never be acted on. That is
  a different feature with a worse trade, and it is explicitly out of
  scope here.
- **Must not widen what is written.** The marker contract and its four
  consumers stay as they are.
- **Must not promise collision detection.** The panel cannot know that
  a package is also declared elsewhere without the evaluation ruled out
  above. The wording must be true without that knowledge.
- **Must not become a wall of text.** This is a panel; the correction
  is a few words in the right places, not an explanatory paragraph on
  open.
- **Must not contradict the writers.** They already say "selection".
  Where the panel restates a writer's outcome it follows that wording.
- No new dependency, no new state, nothing built.

## Open questions

1. **What is the tab actually called?** `Packages` is the overclaim,
   but the alternatives trade off. Something explicit is unambiguous
   and long for a tab that sits beside `Apps` and `Services`; leaving
   `Packages` and carrying the correction entirely in the empty state
   and the counts is cheaper and relies on the user hitting that state.
   This is the main decision.

2. **Do `Apps` and `Services` have the same problem?** They are drawn
   from the same selection files by `rows_tsv`, so strictly yes. They
   are also catalogue-backed -- the row exists whether or not it is
   enabled -- so the "where are my things" misreading is much weaker.
   Whether to correct all three for consistency, or only the tab where
   the confusion actually happens.

3. **Does the empty state need to name the flake-adopter case?**
   Saying "packages you declare elsewhere are not listed here" is
   useful to an adopter and noise to an ISO user who has no elsewhere.
   Whether the panel can tell the two apart cheaply, and whether it
   should bother.

4. **Is the README the right home for the longer explanation**, or
   does the uninstall-is-clean argument belong with nixarchy's own
   documentation, where someone deciding whether to adopt would find
   it?

5. **Does this issue also carry the three-line message cap?**
   `Card.qml:228` elides the writer's output at three lines, which is
   how the honest wording the writers already produce gets truncated
   before it is read. #4 raises the same line for its own reasons. It
   belongs to one of them or to neither.
