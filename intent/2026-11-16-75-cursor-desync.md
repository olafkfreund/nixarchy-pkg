---
status: draft
issue: 75
author: olafkfreund
---

# Intent: the row you see selected is the row a key acts on

## Problem

The menu keeps track of the selected row in two places, and they can stop
matching.

- The model holds `cursor`. Row actions and selection movement use it:
  `SPACE` and `RETURN` act on `rowAt(cursor)` (what they do depends on the
  tab: toggle, add, remove, undraft, open the form; `Menu.qml:536-553`,
  `PkgModel.qml:580-617`), a click sets it (`Card.qml:222`), and the arrows
  move it (`PkgModel.qml:311-316`).
- The list draws its own `currentIndex`, and that is the highlighted row
  (`Card.qml:205`).
- The preview reads a third thing, `list.currentItem` (`Card.qml:59`). It
  goes null when the selected row's delegate is scrolled out of the list's
  buffer, even while `currentIndex` matches `cursor`: the preview blanks while
  `SPACE` still acts on the row out of sight.

`currentIndex` is bound to `model.cursor` (`Card.qml:193`). If `ListView`
moves its own `currentIndex` while `cursor` stays the same, the binding never
runs again, and the two stay apart until the cursor next changes. One way to
cause that is shown below; the exact trigger in the live case is not yet
pinned down. A write's answer replaces `state` directly
(`PkgModel.qml:400`) and does not clear it first, and a QML test that replaces
the rows with a same-length array does *not* reproduce the bug. Finding the
real trigger is part of the spec.

A second, related way to act on the wrong row is a cursor that is out of
range for the rows it indexes:

- On the Queue tab, `queueRows()` puts the check's result row first
  (`PkgModel.qml:184-187`). Cancelling the check (`cancelCheck`, `:531-535`)
  or invalidating its result removes that row without clamping `cursor`.
- On the Flakes tab, `beginNaming()` (`:739-744`) swaps the inspection for a
  single note row (`flakeRows`, `:146-150`) and leaves `cursor` where it was.

`rowAt()` then returns null, so a key silently does nothing while the list
shows something else.

Seen live in a `nixarchy-desktop` microVM on main (ac67db8). On the Apps tab,
move to Bitwarden (row 2) and press `SPACE`. Bitwarden is enabled, and the
highlight and preview jump to 1Password (row 0). Three presses of `DOWN` then
land on ONCE (row 5), not Dropbox (row 3). It happened again after a mouse
click toggled Dropbox. A `SPACE` in that state would toggle Bitwarden again
while 1Password is highlighted: a write to a row the user did not choose.

A QML test reproduces the desync one way: set `cursor = 2`, empty the rows,
restore them, and `currentIndex` is 0 while `cursor` is 2. The same binding is in v1.0.0
(`Card.qml:113` there), so this is older than the work that found it.

## Proposed outcome

- Whenever the rows change, the highlighted row, the preview and the row the
  next key acts on are the same row, and that row exists.
- When a write's answer arrives, the selection keeps the index it has *at
  that moment*, clamped to the new count. The user may have moved on while
  the write ran, and that choice wins. It does not jump to the top.
- A tab change, a new query and new search results select the first row,
  as today, and the list follows even when the cursor was already 0.
- The preview shows the selected row whether or not it is scrolled into view.
- QML tests fail on today's code and pass after the fix. They cover rows that
  empty and refill, the Queue check row going away, Flakes naming, and the
  tab and search resets. Replacement with the same count and a list that
  shrinks below the cursor already re-sync today (the clamp at `:404` changes
  `cursor`); they are kept as regression tests. Note for the spec: `state`
  changes (`:400`) before that clamp, so a fix that reacts to the rows
  changing sees the old `cursor` first.

## Affected users and systems

- Everyone using the menu, on any host. `Menu.qml` owns both the model and the
  card (`:129`, `:416`). The bar panel only opens that menu (`Panel.qml:70-73`),
  so bar users are affected through it.
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
   truth; the list, its highlight and the preview always follow it. (b) The
   list's `currentIndex` becomes the truth, and keys act on it.
   Recommended: (a). Every key handler and the adapter calls already use
   `cursor`, and (b) would move logic into the view.
2. After a write that removes the selected row (for example a package removed
   from Selection), should the cursor stay at the same index, now the next row,
   or move to the row above? Recommended: the same index, clamped. That is what
   `_absorb` already does with `Math.min(cursor, count - 1)` (`:404`).
3. Is restoring the row the user *acted on* ever wanted, rather than the
   current index? Recommended: no. If they moved during the write, they meant
   to.
