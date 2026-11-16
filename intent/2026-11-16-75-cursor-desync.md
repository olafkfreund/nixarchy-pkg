---
status: draft
issue: 75
author: olafkfreund
---

# Intent: the row you see selected is the row a key acts on

## Problem

The menu keeps track of the selected row in two places, and they can stop
matching.

- The model holds `cursor`. Every key acts on it: `SPACE` toggles
  `rowAt(cursor)`, `RETURN` opens it, and the arrows move it
  (`PkgModel.qml:311-316`, `Menu.qml` key handler).
- The list draws its own `currentIndex`. That is what the user sees: the
  highlighted row (`Card.qml:205`) and the preview (`Card.qml:59`, which reads
  `list.currentItem`).

`currentIndex` is bound to `model.cursor` (`Card.qml:193`). When the list's
rows go empty for a moment and come back, `ListView` resets its own
`currentIndex` to 0. `cursor` has not changed, so the binding never runs again,
and the two stay apart until the cursor next moves.

Seen live in a `nixarchy-desktop` microVM on main (ac67db8). On the Apps tab,
move to Bitwarden (row 2) and press `SPACE`. Bitwarden is enabled, and the
highlight and preview jump to 1Password (row 0). Three presses of `DOWN` then
land on ONCE (row 5), not Dropbox (row 3). It happened again after a mouse
click toggled Dropbox. A `SPACE` in that state would toggle Bitwarden again
while 1Password is highlighted: a write to a row the user did not choose.

A QML test reproduces it. Set `cursor = 2`, empty the rows, restore them, and
`currentIndex` is 0 while `cursor` is 2. The same binding is in v1.0.0
(`Card.qml:113` there), so this is older than the work that found it.

## Proposed outcome

- After any refresh, write, tab change or search, the highlighted row, the
  preview and the row the next key acts on are the same row.
- After a write, that row is the one the user acted on, clamped to the new
  count. It does not jump to the top.
- A QML test fails on today's code and passes after the fix. It covers rows
  that empty and refill, a write's state refresh, and a list that gets shorter
  than the cursor.

## Affected users and systems

- Everyone using the menu or the bar panel, on any host. The model and the
  list are shared by `Menu.qml` and `Panel.qml`.
- Files: `Card.qml`, maybe `PkgModel.qml`, and `tests/qml/tst_card.qml` /
  `tst_pkgmodel.qml`.

## Constraints

- One source of truth for the selection. The fix must not add a second
  cursor that can drift in turn.
- Nothing visible changes except that the highlight stays put: no new
  animation, and `highlightMoveDuration: 0` stays (#56).
- No adapter change. This is a panel bug.
- Live check in a `nixarchy-desktop` microVM: the owner's standing choice over
  razer.

## Open questions

1. Which side should own the selection? (a) The model's `cursor` stays the
   truth, and the list is pushed back to it whenever its rows change.
   (b) The list's `currentIndex` becomes the truth, and keys act on it.
   Recommended: (a). Every key handler and the adapter calls already use
   `cursor`, and (b) would move logic into the view.
2. After a write that removes the selected row (for example a package removed
   from Selection), should the cursor stay at the same index, now the next row,
   or move to the row above? Recommended: the same index, clamped. That is what
   `_absorb` already does with `Math.min(cursor, count - 1)`.
