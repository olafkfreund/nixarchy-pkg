---
status: approved
issue: 17
intent: intent/2026-09-19-17-tab-from-the-field.md
---

# Spec: let the tab change while the search field has the keyboard

## Design

Two keys are added to a list of five. That is the whole change.

`Menu.qml`'s search field hands the keyboard back for `Down`, `Up`,
`Return`, `Enter` and `Escape`, under a comment saying "movement and
commitment belong to the list". `Tab` and `Backtab` join them, because
moving between tabs is movement and the comment was already right.

    case Qt.Key_Down:
    case Qt.Key_Up:
    case Qt.Key_Tab:        // added
    case Qt.Key_Backtab:    // added
    case Qt.Key_Return:
    case Qt.Key_Enter:
    case Qt.Key_Escape:
      keys.forceActiveFocus()
      event.accepted = false
      return

**No new behaviour is written.** The outer handler already acts on both
keys — `Menu.qml:182-183`, `Key_Tab` is `setTab(tab + 1)` and
`Key_Backtab` is `setTab(tab - 1)` — and has since before this issue. They
were simply unreachable from the field. The fix makes an existing path
reachable rather than adding a path.

### Why `Tab` and not `Left`/`Right`

Settled at gate 1. `Tab` is never meaningful inside a single-line field, so
taking it costs nothing a person can notice. `Left` and `Right` move a
caret, and the tab whose field is hardest to type into — Flakes, holding a
flakeref — is exactly the one where caret movement matters most. A rule
that changed tabs only when the caret sat at the end would work and would
be a thing somebody has to reconstruct from first principles at 3am.

### What composes correctly, and is worth stating

After `setTab` runs, `Menu.qml:250-256` fires: focus becomes a property of
the destination tab — the field on Flakes, the list everywhere else. So
`keys.forceActiveFocus()` in the field's handler is not the final word on
focus and does not need to be. Tabbing from a search on Selection lands
with the keyboard in the list; tabbing onto Flakes lands with it in the
field, ready for a flakeref. That is the behaviour #3 established and this
change inherits it rather than competing with it.

The query text is not cleared by a tab change. That is existing behaviour —
`setTab` has never cleared it, and `Left`/`Right` have always carried a
query across — and changing it is not this issue.

### The one thing that must be tested rather than reasoned about

The intent's second open question: whether `Tab` reaches the field's
`Keys.onPressed` at all, or is consumed first by Qt's focus traversal.

The reasoning says it reaches: an attached `Keys` handler sees a key before
the item's own handling, and traversal is the item's own handling. But
"the reasoning says" is how this project has shipped two defects already in
this session, both of which passed every automated check. It is listed
under Verification as something to observe on a running panel, and if
traversal does eat it, the fallback is `activeFocusOnTab: false` on the
field — recorded here so the implementation is not improvising.

### Documentation

`bin/nixarchy-pkg-keys` already lists `TAB / SHIFT + TAB -> Cycle tabs`
under Move. That line becomes true in one more place rather than needing to
change, which is the shape a good fix has.

`docs/manual/the-menu.md` says tabs are reached by "`h` and `l`, or `←` and
`→`, or `TAB`". Also already true, and now true while searching. No
documentation change is required, and none should be invented to look
thorough.

## Alternatives rejected

**`Left`/`Right` as well.** Collides with caret movement on the field that
most needs it.

**A conditional rule** — tab movement only when the caret is at the end of
the text. Works, and is unreconstructable six months later.

**Ungating the single letters** so `h`/`l` work while typing. They are
letters. A query containing an `h` is not a request to change tabs.

**A modifier chord.** Reaching the next tab is not an advanced action and
should not acquire a chord.

**Extracting a single "which surface owns which key" rule.** The intent's
fourth open question. It would genuinely read better than five cases in one
file plus a `!search.activeFocus` gate in another — and it is a refactor
riding along with a two-line bug fix, which turns a reviewable change into
one nobody wants to read. Worth its own issue if it is worth doing.

## Risks

- **`Tab` might be eaten by focus traversal**, in which case the two-line
  change does nothing and the panel looks unfixed. Caught by the live check
  below rather than by the automated suite, which cannot see it.
- **Tabbing away from a half-typed query keeps the query.** Existing
  behaviour, now reachable by one more key, so slightly more likely to be
  met. It is also the behaviour somebody wants when they typed a name and
  picked the wrong tab first.
- No host is affected differently. Nothing is written, nothing is built,
  the adapter is untouched.

## Verification

1. `tests/adapter.sh` passes unchanged, and `git diff --stat main -- bin/`
   is empty. This change cannot affect the adapter, so anything here is
   unrelated and blocks the change until explained.
2. **On a running panel, on Selection with a query typed:** `TAB` moves to
   Options and `SHIFT+TAB` back to Drafts. This is the check the whole
   issue is about and the one nothing automated can make.
3. **The keyboard lands in the right place:** tabbing onto Flakes puts it
   in the field; tabbing anywhere else puts it in the list, so the single
   letters and `?` work immediately on arrival.
4. **Typing is undamaged:** `h`, `l` and `/` still reach the field, and a
   query containing them is unaffected.
5. **`Left` and `Right` still move the caret** inside a typed flakeref
   rather than changing tabs.
6. `?` still lists `TAB / SHIFT + TAB -> Cycle tabs`, which was already
   true and is now true everywhere.
