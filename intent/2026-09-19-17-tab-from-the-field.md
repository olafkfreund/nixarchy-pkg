---
status: approved
issue: 17
author: olafkfreund
---

# Intent: let the tab change while the search field has the keyboard

## Problem

Type anything into the search field and you cannot change tabs. `←`, `→`,
`TAB` and `SHIFT+TAB` all fail to, and `h`/`l` are unavailable because the
single-letter keys are gated on the field not having the keyboard — which
is correct, since `h` and `l` are letters somebody is entitled to type.

The only way to another tab is to close the menu and reopen it.

`Menu.qml`'s search field hands the keyboard back for exactly five keys —
`Down`, `Up`, `Return`, `Enter`, `Escape` — under a comment that says
"movement and commitment belong to the list". The comment is right about
what it wants. It just does not count moving between tabs as movement,
and that is the whole of the defect.

## What has already been fixed, and is not this

Since #17 was filed, #3 merged and took two thirds of it with it:

- `Menu.qml:250-256` makes focus a property of the tab: arriving on Flakes
  puts the keyboard in the field, arriving anywhere else puts it in the
  list. So after a tab change, focus is already right.
- `Menu.qml:166-172` hands the keyboard back when `ESCAPE` clears the
  field, so `?` and the single letters stop being unreachable afterwards.

What is left is narrow and specific: **you cannot initiate a tab change
from the field.** Everything that happens after one is already correct.

## Proposed outcome

Somebody who has typed a search can reach another tab without closing the
menu.

Concretely, when this is done:

- A key that is unambiguous about meaning "next tab" does that, from the
  field, on any tab.
- Text editing is not damaged to achieve it. A flakeref is long, and
  moving the caret through one is a real thing a person does.
- The rule for which surface owns which key is stated once, in one place,
  rather than being a list of five cases in one file and a gate on
  `!search.activeFocus` in another.
- The key sheet says so, if the answer adds a key worth saying.

Afterwards, the panel has no state a person can get into and not get out
of except by closing it.

## Affected users and systems

- Anybody who searches and then wants a different tab — which on the
  Selection and Options tabs is the normal way to use them, since `/`
  there searches an index rather than filtering a list.
- `Menu.qml` — the field's `Keys.onPressed`, and possibly the outer
  handler's tab cases.
- `bin/nixarchy-pkg-keys`, if a key changes meaning.
- Not `PkgModel.qml`: `setTab` already does the right thing and is already
  reachable. This is about which keystrokes get to call it.
- Not the writers, not the adapter, nothing that writes.

## Constraints

- **Must not break typing.** Every printable character must still reach
  the field, including `h`, `l` and `/`, which are all legitimate inside a
  query or a flakeref.
- **Must not silently take a key that means something else in a text
  field.** `Left` and `Right` move a caret; a person editing a long
  flakeref will expect that and be right to.
- **Must keep the existing focus rule intact.** #3 made focus a property
  of the tab and that is the right shape. This adds a way to trigger a tab
  change, not a second focus model.
- **Must not add a modifier chord for something this ordinary.** Getting
  to the next tab is not an advanced action.
- **Must leave one list of keys.** `?` is generated from
  `bin/nixarchy-pkg-keys`; the fix must not create a second place where
  key meanings live.

## Open questions

1. **Which key?** The main decision, and there is a genuine trade.
   `TAB`/`SHIFT+TAB` are never meaningful inside a single-line field and
   already mean "next tab" everywhere else in this panel, so handing only
   those back is unambiguous and costs nothing. `←`/`→` would match the
   other tabs' behaviour but collide with caret movement, which matters
   most on exactly the tab — Flakes — where the field is hardest to type
   into. A conditional rule (change tabs only when the caret is at the
   end) is possible and is the sort of cleverness somebody debugs at 3am.
   Recommendation is `TAB`/`SHIFT+TAB` only; the approver should say.

2. **Does `TAB` currently do something?** It is a focus-traversal key in
   Qt, so it may already be consumed by focus handling rather than
   reaching either handler. Whether taking it is free or requires
   disabling traversal is a question for the spec, not an assumption for
   the intent.

3. **Should the letters come back too?** `h`/`l` are gated on the field
   not having the keyboard, which is correct while typing. But it means
   the vim keys work on four tabs and not while searching on any of them.
   Leaving them gated is defensible and asymmetric; there may be no better
   answer than saying so in the sheet.

4. **Is the rule worth extracting?** Which surface owns which key is
   currently spread across the field's five cases, the outer switch, and
   a `!search.activeFocus` gate. One stated rule would be easier to
   reason about; it would also be a refactor riding along with a bug fix,
   which is how a small change becomes a review nobody wants.
