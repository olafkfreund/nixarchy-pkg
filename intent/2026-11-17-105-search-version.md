---
status: draft
issue: 105
author: olafkfreund
---

# Intent: search rows show the package version

> Every `file:line` below was read on this branch (main at `e1acb1b`) and on
> `origin/main` of nixarchy (`7a3136b8`, which holds #1818) on 2026-11-17. The
> line numbers in the issue text are older and drifted; these are current.
> Paths are in this repo unless prefixed `nixarchy:` (olafkfreund/nixarchy).

## Problem

A Selection row shows a package's version before its summary; a search row for
the same package does not. The preview pane beside a search row names the
version, but only at 760 px and wider (`Card.qml:87`), so at 700 px a search
result has no version anywhere.

- **The index has the version as a sixth field.** nixarchy #1818 appends it
  to every row: `.version` is the last element of the jq array that writes
  `index.tsv` (`nixarchy:modules/apps.nix:3739`); the header comment says
  "six tab-separated fields ... and a package's version (empty otherwise)"
  (`:3655-3659`). It is empty for app, opt, flatpak and new-package rows, and
  for a package whose version is unknown (the preview then says `?`, field 5
  only; `:3729`, checked by `nixarchy:tests/pkg-index.nix:121-130`).
- **Search drops it.** The awk in `cmd_search` prints kind, name, summary,
  field 4, field 5 and the scope (`bin/nixarchy-pkg:707`), and the jq builds
  `kind name summary type flags scope preview` (`:735-751`). No `$6` of an
  index row is read. For an index row the scope is the constant `"system"`
  (`FILENAME == idx`); only rows from the options cache `rows.tsv` use their
  own `$6` as scope (`:707`, filter at `:694`). I ran the adapter on a
  six-field index in a `mktemp` copy: the rows carry no version key.
- **Selection scrapes it from the preview.** `labels_tsv` finds
  `\nversion:  ` in `$5` (`:636-637`, function `:630`); `cmd_state` maps `?` to
  empty (`:2831`) and `Card.qml:388` draws `version + "  " + summary`. That
  expression is generic: any row with a truthy `version` and no `type` is drawn
  with it, so a search row that carried `version` would show it with **no QML
  change**. (In the same `mktemp` copy, adding the key made the row appear in
  the JSON; the QML side is read, not run.)
- **Staleness does not look at row width.** `index_facts` compares the
  stamp with the installed builder's seven inputs (`INDEX_INPUTS`, `:489`;
  compare at `:518`). An index built by an older installed `nixarchy-search`
  has the same inputs now as when it was built, so it is `fresh` and has five
  fields. So five-field indexes exist on fresh state, which is why replacing
  the scrape by `$6` (issue option b) would lose versions there.
- **The contract names the optional fields.** "A `default` package with a
  fresh index entry may also carry `summary`, `version` and `flags`" is about
  `state` rows (`docs/manual/from-a-terminal.md:222-226`); it does not mention
  `search` rows, whose keys the manual does not list.
- **Fixtures are five-field.** `tests/adapter.sh:561` (search ranking),
  `:599`, `:650-659` (state facts, version in the preview), `:1905`, `:2541`,
  `:2745`, `:2749`. None reads `$6`, so they pass unchanged; they are the
  old index shape and become the "older builder" test case.
- **Card tests already cover the display.** Selection rows with a version are
  tested at `tests/qml/tst_card.qml:785-797`; a search row fixture exists
  (`:41-42`, `insecure-search`) but carries no version; the 800/700 px summary
  fit test is `:822` onward.

Split out of #94, which kept the JSON contract unchanged.

## Proposed outcome

- A search result for a package shows its version before the summary, the
  way a Selection row does, when the index has it.
- A five-field index (older builder), an unknown version, and every
  non-package row look exactly as they do today. No row shows `?` or a guess.
- `bin/nixarchy-pkg` reads `$6` in one place (search); the Selection path is
  untouched.
- One adapter test (six-field row gives the key; five-field row does not) and
  one Card test (a search row with a version draws it, at 800 and 700 px with
  the preview). The adapter test also asserts: an empty sixth field gives no
  key, an option row from `rows.tsv` (its `$6` is `system` or `user`,
  `tests/adapter.sh:2555-2556`, `:2733-2735`) never gets `version`, and a
  stale six-field index keeps the version. The manual says search
  rows may carry `version`.

## Affected users and systems

- Anyone using the Packages search; they see one more short token per row.
- Files: `bin/nixarchy-pkg` (awk `:707`, jq `:745`), `tests/adapter.sh` (a
  new six-field fixture beside `:561`), `tests/qml/tst_card.qml` (give
  `insecure-search` or a new row a `version`, one assertion),
  `docs/manual/from-a-terminal.md` (the `search` row keys).
- **Not touched:** `Card.qml` (the expression at `:388` already draws it),
  `labels_tsv`, `cmd_state`, the other index readers, the stamp logic.
- Outside this repo: nothing. The index already has the field (nixarchy
  #1818, merged).

## Constraints

- No new dependency; the panel stays a viewer, no nixpkgs evaluation.
- Do not guess: a version shows only because field 6 of the row says so,
  and only for `pkg` rows (an `opt` row from `rows.tsv` has its scope in
  `$6`, which must never be read as a version).
- The JSON contract may gain an optional key, never lose or rename one
  (`docs/manual/from-a-terminal.md:222-230`); `state` is unchanged.
- A five-field index must keep working with no error and no wrong text.
- Live check in a `nixarchy-desktop` microVM (the owner's standing choice),
  with a guest whose `nixarchy-search` carries #1818 and a reindex. Offline
  checks run in `mktemp` copies.

## Open questions

1. **(a) Add a `version` key to search rows, or (b) replace the preview scrape
   with `$6`?**
   Recommended: **(a), and not (b).** (a) is two lines in `cmd_search` and
   needs no QML change. (b) saves three lines in `labels_tsv` but drops
   versions on a fresh five-field index (the older-builder case above) and
   moves fixtures `:650-659`, `:2745`, `:2749` to six fields for no visible
   gain. Revisit (b) when the minimum installed builder is #1818.
2. **What does a five-field index show?**
   Recommended: no version on search rows (the key is absent), the same as
   today. `.[6] // ""` in jq and an empty awk field make this fall out; no
   fallback to scraping `$5` for search, because that would be a second
   source of the same fact in one command. Selection rows keep scraping, so
   an older index still shows versions there.
3. **Should Selection rows switch to field 6?**
   Recommended: no (see 1). Two sources for one fact is a small cost, and it
   goes away only when five-field indexes cannot occur; that is a follow-up,
   not this change.
4. **Key shape: always `version: ""`, or present only when non-empty?**
   Recommended: only when non-empty, like `summary` on state rows
   (`docs/manual/from-a-terminal.md:222-226`) and so the "may carry"
   wording holds; `Card.qml:388` treats both the same.
5. **Where does the version sit, and what does it cost in width?**
   Recommended: where Selection puts it, first in the second column
   (`version  summary`, `Card.qml:388`). No new item and no new width term:
   the summary Text already has the elide width (`:377-381`), so a search
   row's summary loses `len(version) + 2` characters and elides as it does
   now. The tightest case is 800 px with the preview pane (the pane shows
   from 760 px, `Card.qml:87`); at 700 px the list is full width. The
   existing fit test (`tst_card.qml:822`) uses `selRows`, which have no
   preview, so the list is full width at both sizes and the 800 px pane case
   is not exercised. The new Card test therefore uses a realistic search row
   (`kind "pkg"`, `type ""`, `version`, `summary`, `flags`, `preview`), asserts
   the pane is visible at 800 and hidden at 700, then checks the version text
   and that the row fits. A very long version (a date or hash) elides inside
   the summary; the summary can already reach zero width with a long name and
   several tags, so no readability promise is made.
6. **Search rows from a stale index?**
   Recommended: show the version anyway. `cmd_search` already returns
   summary and flags from a stale index (`:678-680` read staleness, nothing filters rows by it), so the version is as
   current as they are; the footer already says the index is old. Hiding it
   would make search differ from its own other fields.
7. **Restrict to `pkg` rows in the awk?**
   Recommended: yes (`$1 == "pkg" && FILENAME == idx ? $6 : ""`). The index
   contract says non-package rows have an empty `$6`
   (`nixarchy:tests/pkg-index.nix:123`), but the guard costs nothing and
   protects against a future kind using the column differently. A `mktemp`
   run with a hand-made app row that had a non-empty `$6` showed what an
   unguarded read would print.
