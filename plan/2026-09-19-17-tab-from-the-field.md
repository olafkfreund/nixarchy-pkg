---
status: approved
issue: 17
spec: spec/2026-09-19-17-tab-from-the-field.md
---

# Plan: let the tab change while the search field has the keyboard

## The approved decisions, in full

`Tab` and `Backtab` join the five keys the search field already hands back
to the list. The outer handler has acted on both since before this issue
(`Menu.qml:182-183`); they were unreachable from the field, and that is the
entire defect.

`Left`/`Right` are deliberately **not** included: they move a caret, and the
field that most needs caret movement is the one holding a flakeref.

Focus after the change is already handled — `Menu.qml:250-256` makes it a
property of the destination tab — so this adds a trigger, not a focus model.

No documentation change. `bin/nixarchy-pkg-keys` already reads
`TAB / SHIFT + TAB -> Cycle tabs`, and `docs/manual/the-menu.md` already
lists `TAB` among the ways to change tabs. Both become true in one more
place rather than needing edits, and inventing an edit to look thorough
would make the sheet wrong.

## Steps

1. **`Menu.qml`, the search field's `Keys.onPressed`** — add
   `case Qt.Key_Tab:` and `case Qt.Key_Backtab:` to the existing
   fall-through group, and extend the comment so the next reader knows why
   tab movement counts as movement and caret movement does not.
   -> verify by `grep -n "Key_Tab" Menu.qml` showing it in both the field's
   handler and the outer switch.

2. **Build, install, and observe.** The spec's second check is the whole
   issue and nothing automated can make it: on Selection with a query
   typed, `TAB` reaches Options and `SHIFT+TAB` reaches Drafts.
   -> verify on a running panel, from a screenshot.

3. **If `Tab` never arrives** — Qt focus traversal ate it — set
   `activeFocusOnTab: false` on the field and observe again. Recorded in
   the spec so this is a decision already taken rather than one improvised
   under a failing check.
   -> verify by the same observation.

   **Not needed.** `Tab` reaches the field's `Keys.onPressed` and the
   fall-through hands it on, exactly as the reasoning said. The fallback
   stays written down because the next person to touch this will wonder,
   and "we checked, it arrives" is worth more than silence.

4. **Check what the fix did not break**, in the same session: the keyboard
   lands in the list on an ordinary tab and in the field on Flakes; `h`,
   `l` and `/` still type; `Left`/`Right` still move the caret in a typed
   flakeref.
   -> verify by observation, one screenshot each where it is visible.

## Tests

    bash tests/adapter.sh
    git diff --stat main -- bin/

Expected: passes unchanged, and an empty diff. This change cannot reach the
adapter, so anything here is unrelated and blocks the change until
explained.

Live, on a build of this branch:

1. Selection, `/`, type `ripgrep`, press `TAB` — the tab is Options.
2. `SHIFT+TAB` twice — the tab is Selection again, then Drafts.
3. From Drafts, `TAB` twice onto Flakes — the keyboard is in the field, and
   typing a flakeref works without pressing `/` first.
4. On Selection with a query, press `h` — an `h` appears in the query
   rather than the tab changing.
5. On Flakes with a flakeref typed, `Left` twice — the caret moves, the tab
   does not.
6. `?` opens and still reads `TAB / SHIFT + TAB -> Cycle tabs`.

Restore nothing: this change writes no files and queues nothing, so the
selection files cannot be touched by testing it. Confirm that rather than
assume it — `nixarchy-pkg pending` is 0 at the end.

**All six ran and passed**, on a build of this branch driven from the
keyboard. Worth recording what the third one showed, because it is the
part that could only be seen by doing it: tabbing onto Flakes landed with
the keyboard already in the field, so `github:nix-community/nixvim` typed
straight in — *including its slash*, which on any other tab is the key that
focuses the field. Two features written days apart, composing without
either knowing about the other.

## Rollback

`git revert`. Two keys leave a switch statement and the panel behaves as it
did. Nothing is written, nothing is built, no state is stored, and the
adapter is untouched, so there is nothing else to undo.
