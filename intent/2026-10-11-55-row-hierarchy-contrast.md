---
status: approved
issue: 55
author: olafkfreund
---

# Intent: Row hierarchy and light-theme contrast

## Problem

The card is hard to read at a glance, and on a light theme part of it is
wrong.

- **Dim text inverts on light themes.** Secondary text is `Qt.darker(fg)`
  (`Card.qml:18`, and five sites in `OptionForm.qml`). On a dark theme that
  is grey, as meant. On a light theme the foreground is already dark, so
  "dim" comes out near-black: summaries, inactive tabs and the footer read
  stronger than the names they are meant to sit under.
- **Every row is one line of same-size, same-weight text.** Name, flags and
  summary differ only by colour, so the eye has nothing to land on.
- **Flags look like description.** `unfree`, `broken` and the curated note
  are coloured words in the same run as the summary. They are warnings
  about what a rebuild will do, and they do not look like it.
- **Nothing identifies an app.** No icons, even where the desktop already
  has one for the app.
- **A short list leaves the card empty.** Three search results on an
  1100px card leave about 80% of it blank, while the details that would
  help choose a package (version, licence, full description) are not shown
  anywhere.
- **The card feels static.** No hover state, the cursor jumps between rows,
  and work in progress is the single word `working…`.

Comparing with nixdatifier (Muddyblack/nixdatifier) showed that the gap is
structure, not colour: their rows have a hierarchy, flags are pills, and
icons and secondary text give each row a shape.

## Proposed outcome

- On a light theme and a dark theme, secondary text is visibly lighter in
  weight than primary text.
- A row is scannable: the name stands out, the version or attribute reads as
  secondary, and flags read as warnings, distinct from the summary.
- Apps and services with a desktop icon show it.
- The space under a short list tells you about the row under the cursor.
- The cursor and hover respond, and running work is visible as motion, not
  only as a word.
- Optional: tabs show their counts (Selection, queued).

## Affected users and systems

- Everyone using the menu or the bar card, and especially anyone on a light
  Omarchy theme.
- Files: `Card.qml`, `OptionForm.qml`, `Menu.qml`, and possibly `PkgModel.qml`
  and `bin/nixarchy-pkg` if the preview needs fields the rows do not carry.
- `tests/qml/tst_card.qml` (geometry assertions) and the docs screenshots in
  `docs/img/`.

## Constraints

- Every colour stays an Omarchy theme token, so theme switches keep
  working. No hard-coded palette.
- Keyboard-first behaviour does not change: same keys, same focus rules.
- No new dependencies. Icons come from what Quickshell already provides.
- No appearance settings (radius, glow, accent). The theme owns those.
- Summary width stays measured, not guessed (#45 and #53 still apply).
- No new process calls on every cursor move, so the preview stays instant.

## Open questions

Resolved at approval (no answer was given, so the recommended options were taken):

1. Pills: yes, for flags only. Tabs keep their underline.
2. Empty space: a preview pane for the row under the cursor.
3. Tab counts and motion: a follow-up issue, not this task.
