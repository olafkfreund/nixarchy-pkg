---
status: draft
issue: 27
author: olafkfreund
---

# Intent: the search field never gives the keyboard back

## Problem

Once anything has been typed into the search field, the keyboard stays in
the field until the menu is closed. Driven on razer:

1. Apps, `/`, type `foot`.
2. `DOWN`. The caret disappears, which reads as "the list has it now".
3. `SPACE` types a space into the query. It is now `"foot  "` and matches
   nothing, when the space was meant to toggle the row. `j` types a `j`.
4. `ESCAPE` clears the field. Then `l` is typed into it as well.

After that, every single-letter key (`h j k l a r ?`) is text until the
menu is reopened. RETURN, TAB and the arrows still work, but only because
the field forwards them. Filter-then-toggle, the most ordinary thing to do
on the Apps tab, needs RETURN, and nothing on screen says so.

The likely cause: `keys.forceActiveFocus()` on a FocusScope gives focus to
whichever child held it last, which is the field. `open()` already knows
this and clears `search.focus` first (`Menu.qml:62-67`). The field's own
handler (`Menu.qml:291`) and the ESC branch (`Menu.qml:171`) do not. So
the behaviour #17's intent describes as already fixed ("ESCAPE hands the
keyboard back") is not in effect.

Three more defects share this surface:

- **ESC stopped clearing the field after an option form.** After setting
  an option and closing the form, four `ESCAPE` presses did nothing while
  `l` still changed tabs. Root cause not isolated; it may be the same
  focus trap, with the invisible form as the child that last held focus.
- **The key sheet cannot be read by keyboard.** At 1080p it is taller than
  the card, and any key closes it (`Menu.qml:147-150`), so the Act,
  Option form and While applying sections can be reached only with a
  mouse wheel. That is the sheet describing `a`, SHIFT+A and `r`.
- **`R` is advertised and does not work.** The footer ("index stale — R
  to rebuild") and the sheet both say `R`. SHIFT+R does nothing; only
  plain `r` works (`Menu.qml:239`, gated on `NoModifier`).

## Proposed outcome

- After `DOWN`, `ESCAPE` or RETURN from the field, the list really has the
  keyboard: SPACE toggles, `j`/`k` move, `?` opens the sheet.
- No sequence of keys leaves the menu deaf to a key it advertises, short of
  closing it. This is the outcome #17 set out; it should actually hold.
- The whole key sheet is readable from the keyboard.
- The key the footer names is the key that works.

## Affected users and systems

- Everyone who searches or filters, which on Selection and Options is the
  only way to use the tab.
- `Menu.qml`: the field's `Keys.onPressed`, the ESC branch, `onClosed`
  from the form, the key-sheet handler.
- `bin/nixarchy-pkg-keys` and the footer text, for `R`.
- Not the adapter.

## Constraints

- Every printable character must still reach the field while it is being
  typed into, including `h`, `l`, `/` and space.
- One focus rule, not two. #3 made focus a property of the tab; this fixes
  how focus is moved, not where it belongs.
- One list of keys: the sheet stays generated from `bin/nixarchy-pkg-keys`.

## Open questions

1. **`R` or `r`?** Accept both, or change the copy to `r`. Both fix it;
   accepting both costs one condition.
2. **Scroll the sheet, or make it fit?** `j`/`k`/PgUp/PgDn could scroll
   it (any other key still closes it), or it could be split into two
   columns. Scrolling is the smaller change.
3. **Single keys that act on the machine.** Found in the same session: a
   stray `a`, typed while the keyboard was not where it looked, requested
   a full system apply. It was refused only because a reindex happened to
   be running. SPACE on Selection or Options removes a package or option
   with no confirmation. With the focus bug fixed, keys land where they
   look like they will, but is one keystroke still enough for `a`? This is
   a design decision for the approver. It could be split into its own
   issue.
