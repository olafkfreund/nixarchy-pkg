---
status: draft
issue: 75
intent: intent/2026-11-16-75-cursor-desync.md
---

# Spec: the row you see selected is the row a key acts on

## Design

The model's `cursor` is the only selection; this was decided at the intent
gate. The list, the highlight and the preview all follow it, and the model
keeps it in range.

### The trigger, now established

The intent left the trigger open. An experiment settles it. It uses the real
`PkgModel` and the real `Card` (a scratch `qmltestrunner` file, Qt 6.12
offscreen):

1. A state with six apps, then `cursor = 2`; the list shows 2.
2. `write(["toggle", "app", "a2"])`, then `_writer.deliver(<state with the
   same six apps, a2 enabled>)`.
3. After the answer, `cursor` is 2, `list.currentIndex` is 0, and the count is
   still 6.

So **any** new rows array resets `ListView.currentIndex` to 0, even one of the
same length. A write's answer always produces one (`_absorb` assigns `state`,
`PkgModel.qml:400`, and `rows()` builds a fresh array from it). agy's first
finding at the intent review said exactly this. The intent's claim that a
same-length replacement "does *not* reproduce the bug" came from a fake-model
test whose rows binding never re-ran, and it is wrong. The rest of the intent
stands.

The binding `currentIndex: root.model.cursor` (`Card.qml:193`) is not broken
by this, because the reset is internal to `ListView`. But it only re-runs when
`cursor` changes, and after most writes it does not.

### Changes

1. **`Card.qml`, the list (~line 192).** When its model changes, the list puts
   `currentIndex` back on the model's cursor at once:

   ```qml
   currentIndex: root.model ? root.model.cursor : 0
   // Any new rows array resets ListView's own currentIndex to 0, and the
   // binding above only re-runs when cursor changes (#75).
   onModelChanged: currentIndex = Qt.binding(function () { return root.model ? root.model.cursor : 0 })
   ```

   Re-assigning the binding evaluates it immediately, so this is synchronous
   and there is no frame where row 0 is highlighted. It is measured: the
   same-count write case and the shrink case both pass with it.

2. **`Card.qml`, the preview (line 59).** `currentRow` reads the model, not
   the delegate:
   `readonly property var currentRow: root.model ? root.model.rowAt(root.model.cursor) : null`.
   `rowAt` reads `rows()` (`PkgModel.qml:264-267`), so the binding follows both
   the cursor and the rows. A row scrolled out of the delegate buffer still
   shows its preview.

3. **`Card.qml`, the highlight (line 205).** It stays
   `index === list.currentIndex`. After change 1 the two are equal whenever a
   key can act, so this needs no change. It also keeps one fewer dependency
   per delegate.

4. **`PkgModel.qml`, the cursor stays in range.** One handler on the existing
   `readonly property int count: rows().length` (`:269`):

   ```qml
   // Whatever shrank the rows -- a cancelled check, naming, a filter -- the
   // cursor must still name a row (#75).
   onCountChanged: if (cursor > Math.max(0, count - 1)) cursor = Math.max(0, count - 1)
   ```

   This covers the Queue check row going away (`cancelCheck`, `:531-535`, and
   invalidation, `:432-434`) and Flakes naming (`beginNaming`, `:739-744`;
   `flakeRows`, `:146-150`), without a clamp at each site. `_absorb`'s own
   clamp (`:404`) stays and becomes a no-op. On the ordering trap agy named
   (`state` changes before that clamp): Qt does not order the list's
   `onModelChanged` against the model's `onCountChanged`, and neither order
   matters. If the list re-binds first while `cursor` is past the end,
   `ListView` holds its index in range, and the clamp's change to `cursor`
   then re-fires the binding onto the right row. The shrink test checks the
   end state, not the order.

5. **Unchanged:** `setTab`, `setQuery` and search answers keep setting
   `cursor = 0` (`:327`, `:553`, `:388`). Change 1 makes the list follow even
   when `cursor` was already 0. That is the intent's "the list follows even
   when the cursor was already 0".

The intent's approved answers, settled: the model owns the selection; a
removed row keeps the same index, clamped; and an answer keeps the index
current when it arrives, never the row that was acted on.

### Decisions for the owner

None. Every open question was settled at the intent gate. Two choices are
mine, below under alternatives.

### Tests

`tests/qml/tst_card.qml` gains a section that uses the **real** `PkgModel` (a
second `Card` bound to a `PkgModel` instance). The fake model's rows binding
is what hid the trigger, so these tests must not use it.

- A write answer with the same count keeps `currentIndex` and `currentRow` on
  `cursor`.
- A write answer that shrinks below the cursor clamps it, and the list
  follows.
- Rows that empty and refill.
- A tab change and a new query land on row 0 even when `cursor` was 0 and the
  list was elsewhere.
- The preview survives the selected row scrolling out: `cursor = count - 1` on
  a long list, `positionViewAtBeginning()`, then `currentRow.id` is the last
  row.

`tests/qml/tst_pkgmodel.qml`:
- `cancelCheck()` with the cursor on the last Queue row clamps it.
- `beginNaming()` with the cursor past 0 clamps it to the note row.

Every new test is shown to fail on main (lead runs them against
`git show main:Card.qml` / `PkgModel.qml`) and pass with the change.

**Live:** in a `nixarchy-desktop` microVM. Move to row 2 on Apps, press
`SPACE`, and the highlight and preview stay on row 2. Then press `DOWN` three
times and land on row 5. Cancel a check on Queue with the cursor on the last
row, then press `SPACE`/`RETURN`.

### Companion issues

None. This is panel-only.

## Alternatives rejected

- **`Qt.callLater` re-sync.** It also passes, but for one frame the list shows
  row 0. The synchronous re-bind has no such frame.
- **The highlight reads `model.cursor` directly** (`index === root.model.cursor`).
  The highlight would be right even when the list is not, but the list's
  scroll position (`highlightRangeMode`) still follows `currentIndex`, so the
  view could scroll to a row other than the highlighted one. Fixing the sync
  at its source covers both.
- **A clamp at every call site** that changes rows. Easy to miss the next
  one; `onCountChanged` sees them all.
- **A `ListModel` instead of a JS array**, so rows update in place and the
  view never resets. It is the "proper" Qt answer, but it rewrites how every
  tab builds its rows. Out of proportion for this bug.

## Risks

- `onModelChanged` re-binding also runs on the first model assignment. That
  is harmless: it evaluates to the cursor, as the binding would.
- `onCountChanged` changes `cursor` from inside a binding update. QML allows
  it, and a write to `cursor` triggers no further `count` change, so there is
  no loop. The QML suite runs with `failOnWarning` for binding loops in
  `tst_card`, so a loop would fail CI.
- The preview now reads `rowAt` (a function binding). Its dependencies are
  `cursor` and whatever `rows()` reads, the same set the list already tracks.

## Verification

- `nix flake check`: all QML tests pass, and the new ones fail on main.
- The live microVM check above.
