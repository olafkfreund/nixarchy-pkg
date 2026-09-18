---
status: approved
issue: 11
spec: spec/2026-09-18-11-selection-not-system.md
---

# Plan: the Packages tab shows a selection, and should say so

## The approved decisions, in full

The Packages tab lists only lines carrying a `#@pkg` or `#@pkg-other`
marker in `~/.config/nixarchy/apps.nix` (`bin/nixarchy-pkg:146`). That
is correct and stays. The defect is that the panel describes it as if
it reported the machine.

Four changes. No new source of rows, no evaluation of the user's
configuration, no change to the marker contract, no change under
`bin/`.

1. Tab `Packages` -> `Selection`, the word the writers already use
   (`nixarchy-pkg-remove:68-69`, "removed from your selection").
2. A caption under the tab strip, on that tab only, visible at **any**
   row count -- because the confusion is a short list, not an empty
   one, and `Card.qml:188` only fires at zero rows.
3. The empty state stops reading "type to search nixpkgs" on that tab.
4. `README.md` states the read boundary beside the write boundary.

Explicitly not done: collision detection (needs the ruled-out
evaluation), `Apps`/`Services` (catalogue-backed, never short, no
misreading to correct), the three-line message cap at `Card.qml:228`
(truncates every writer's output, not this one).

## Steps

1. **`PkgModel.qml:28`** -- in `readonly property var tabs`, replace
   `"Packages"` with `"Selection"`. Position stays third.
   -> verify by `grep -n 'Selection' PkgModel.qml` showing one hit at
   :28, and no remaining `"Packages"` in the file.

2. **`Card.qml`** -- add the caption between the tab strip and the
   list. After the `Row { id: header ... }` block that ends at `:77`,
   insert a `Text { id: scope ... }`:
   - `anchors { top: header.bottom; left: parent.left; right: parent.right }`
   - `visible: root.model && root.model.tab === 2 && !root.model.searching`
   - `height: visible ? implicitHeight + Style.space(6) : 0`
   - `text: "packages nixarchy manages — not everything installed"`
   - `textFormat: Text.PlainText`, `wrapMode: Text.Wrap`
   - `font.family: root.fontFamily`,
     `font.pixelSize: root.px(Style.font.caption)`, `color: root.dim`
     -- the same four properties the footer caption uses at `:249-252`,
     so it inherits the theme rather than choosing a look.
   - The em dash as `—`, matching the escaping convention stated
     at `Card.qml:128-130`.
   -> verify by reading: the block sits after `:77` and before the
   `ListView`.

3. **`Card.qml:83`** -- re-anchor the list under the caption:
   `top: header.bottom` becomes `top: scope.bottom`. `topMargin:
   Style.space(10)` is unchanged. When the caption is hidden its height
   is 0 and `scope.bottom` is `header.bottom`, so the other four tabs
   are pixel-identical to today.
   -> verify by switching to Apps and comparing against a
   before-screenshot: the first row sits at the same height.

4. **`Card.qml:195-197`** -- in the empty-state `text:` expression, add
   a branch before the existing `indexTab` one:

       : root.model.tab === 2 ? "no packages in your nixarchy selection yet — / to search nixpkgs"
       : root.model.indexTab ? "type to search nixpkgs"

   Order matters: `tab === 2` is also an `indexTab`
   (`PkgModel.qml:68`), so the new branch must come first or it is
   unreachable. The `searching` branch stays ahead of both.
   -> verify by the empty-selection test below.

5. **`README.md`** -- after `:45` (the write-boundary sentence, ending
   "never the copy under the flake."), insert a blank line and one
   paragraph, before the `## The option forms, honestly` heading at
   `:47`:

   > It lists the same way. The Selection tab shows the packages
   > nixarchy manages -- the marked lines in that file -- and not what
   > is installed on the machine. Packages you declare elsewhere in
   > your own configuration are neither listed here nor managed here,
   > and removing one here cannot remove one declared there. That
   > boundary is what makes nixarchy removable: the selection hangs off
   > a single import, and taking it out leaves nothing behind.

   -> verify by reading the section end to end: write boundary, then
   read boundary, then the heading.

6. **Check the key sheet contradicts nothing.** `bin/nixarchy-pkg-keys`
   names no tab; `:36` says "RETURN -> Edit an option's value, or add a
   search result", which stays true.
   -> verify by `grep -n 'Packages' bin/nixarchy-pkg-keys` returning
   nothing. If it returns a line, this step becomes an edit and the
   plan is updated in the same commit as the code.

7. **Sweep for other occurrences of the old label** in anything
   user-facing.
   -> verify by `grep -rn '"Packages"\|Packages tab' *.qml README.md
   bin/ manifest.json` returning nothing outside `intent/`, `spec/` and
   `plan/`.

## Tests

Run from the repo root.

    tests/adapter.sh

Expected: passes exactly as before this change. The adapter is not
touched, so any failure here is unrelated and blocks the change until
explained.

    git diff --stat main -- bin/

Expected: empty. No change under `bin/` unless step 6 found a
contradiction, in which case this shows `bin/nixarchy-pkg-keys` alone.

    bin/nixarchy-pkg state | jq -S . > /tmp/state-after.json

Expected: identical to the same command run before the change. The
panel's data contract is unchanged; only its labels move.

Manual, on this host, whose selection is one package (`azure-cli`):

1. Open the panel, go to the third tab. It reads `Selection`, lists
   `azure-cli`, and **carries the caption above the list** -- this is
   the case the empty state could not reach and the reason the caption
   exists. Screenshot it.
2. Press `/` and type. The caption disappears while searching; results
   are not captioned as a selection.
3. Tabs one, two, four and five: no caption, and the first row sits
   where it did before.
4. Comment out the `azure-cli` line in `~/.config/nixarchy/apps.nix` so
   the selection is empty. The Selection tab reads "no packages in your
   nixarchy selection yet -- / to search nixpkgs"; the Options tab
   still reads "type to search nixpkgs". Restore the line.
5. `h`, `l`, arrows and TAB still reach the third tab; `?` still opens
   and lists every key.

## Rollback

`git revert` the implementation commit. Nothing is written to the
user's files, nothing is built, no state is stored and the adapter is
untouched, so reverting the QML and the README restores the previous
behaviour exactly. No migration, no cleanup, nothing to undo on any
machine that ran it.
