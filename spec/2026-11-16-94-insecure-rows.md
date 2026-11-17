---
status: approved
issue: 94
intent: intent/2026-11-16-94-insecure-rows.md
---

# Spec: rows the index flags insecure draw in the urgent tone

## Design

Line numbers are this worktree (main at 16e9664 merged with the approved
intent) for `Card.qml`, `PkgModel.qml`, `tests/qml/tst_card.qml` and
`docs/manual/*`, and nixarchy `origin/main` 74000e98 for `modules/apps.nix`
(#1818 is in it: `:3719-3723` flags, `:3729` preview paragraph, `:3735`
version). The intent's five questions were approved with the recommended
answer; they are settled and not reopened. Q1 urgent, Q2 land it now, Q3 search
rows too, Q4 no summary suffix (nothing to do), Q5 no version change.

### Decisions for the owner

1. **Tone is `Commons.Color.urgent`, the same as `broken`, not a third tone.**
   The intent's Q1 answer. A third colour would need a new `Commons.Color`
   entry in nixarchy's shell, which this plugin cannot add. Recommended: yes.
   The cost: two urgent tags (`broken`, `insecure`) cannot be told apart by
   colour, only by word. They are told apart by the word and by position, which
   is the index's order (`unfree`, `broken`, `insecure`).
2. **The Selection tab test rows are appended, not inserted.** The existing
   tests index `selRows` by position (`tst_card.qml:772-778`, `:794-804`).
   The two new rows go at positions 6 and 7. Recommended: yes. The width test
   (`test_selection_summary_fits_at_800_and_700`) loops over every `selRows`
   row, so the new rows also prove the summary still fits beside the tag.
3. **The other-channel confirmation says "unfree, broken and insecure are not
   known"** (`PkgModel.qml:888`). It is the intent's named file. Recommended:
   yes; the claim is exact for the same reason it is for the other two (the
   index describes this channel's build).
4. **Three comments and one troubleshooting sentence are left alone, and one
   of them is not strictly accurate.** `bin/nixarchy-pkg:430` and `:2642`
   and `docs/manual/troubleshooting.md:43` speak of an index built before
   #493, which stays true. `tools/record-tour.sh:183` says a stale index
   "carries no unfree or broken flags at all", a generalisation that is false
   for search rows; it is a comment in a recording script, not shipped text.
   The intent names only `Card.qml:580-582` and `docs/manual/packages.md:71`.
   Recommended: leave all four, and fix `record-tour.sh:183` only if you want
   it in this change (one comment line). Say if you want any widened.
5. **The follow-up issue for showing the version on search rows is written
   here, not filed.** Filing needs your go-ahead (text below). Recommended:
   file it after this spec is approved so the number goes into the PR.
6. **The live check has not run.** It needs a guest whose `nixarchy-search`
   carries #1818 (see Verification 4). Recommended: run it after the plan is
   approved; nothing in the design depends on its result, because the QML
   tone is covered by a real test (measured below).

### 1. The tone (`Card.qml:346-348`)

Today:

```
readonly property color tone: modelData === "broken" ? Commons.Color.urgent
                            : (modelData === "unfree" || modelData === "other") ? Commons.Color.accent
                            : root.dim
```

After, one condition changes:

```
readonly property color tone: (modelData === "broken" || modelData === "insecure") ? Commons.Color.urgent
                            : (modelData === "unfree" || modelData === "other") ? Commons.Color.accent
                            : root.dim
```

`tagsOf` (`Card.qml:59-62`) is untouched: it already draws every word in
`row.flags`. That is one expression for both kinds of row, because search rows
and Selection rows are drawn by the same delegate on tab 2 (`Card.qml:176`,
`:337-345`); a search row is a row with `flags` and no `channel`. Nothing else
changes in the delegate, so the summary width formula
(`Card.qml:377-381`, `flags.width` is already a term) needs no edit.

Output shapes, for a row from the index:

- Selection row, `flags: ["unfree","insecure"]`, `channel: "default"`: tags
  `unfree` (accent), `insecure` (urgent), `default` (dim), in that order.
- Search row, `flags: ["insecure"]`, no channel: one tag, `insecure` (urgent).
- `other` row: `other` (accent) only, because `cmd_state` gives it no flags
  (`bin/nixarchy-pkg:2781-2783`, `PkgModel.qml:855-859`).
- Stale or missing index, or a package it does not know: no `flags` on a
  Selection row, so no tag, exactly as today (`bin/nixarchy-pkg:2710`).

No change to `bin/nixarchy-pkg`: `labels_tsv` (`:577-588`), `cmd_state`
(`:2735-2745`) and `cmd_search` (`:677-683`) pass the flags word through, and
`UNTAG_JQ` (`:83-87`) has no suffix to strip (#1818 writes none). The JSON
contract gains nothing: `insecure` is a word inside `flags`
(`docs/manual/from-a-terminal.md:222-226`, which names no flag, stays as it
is).

### 2. Text corrections

- `Card.qml:580-582` (the comment above `indexAge`). Today: "A stale index has
  no unfree or broken flags in it at all, so every package reads as free."
  That is true of Selection rows and false of search rows, which keep the flags
  of the cached index (`cmd_search` ignores staleness). After:

  ```
  // A stale index may be missing flags (unfree, broken, insecure), or carry
  // outdated ones: a Selection row gets none from it, a search row keeps
  // what it cached. Either way an unmarked package is not known to be safe.
  // Said plainly, with the key that fixes it, rather than left for the user to
  // discover after a rebuild.
  ```
- `docs/manual/packages.md:52`: "Three things a row can be marked with" becomes
  "Four things". A new paragraph after `broken` (`:61-62`):

  ```
  **`insecure`** — nixpkgs lists a known vulnerability for this package, or
  marks it insecure. You can still add it, and it will usually refuse to
  build until you permit it by name. The detail pane beside the row says
  "Marked INSECURE in nixpkgs."
  ```

  (The "refuse to build" sentence is nixpkgs's documented behaviour for
  `meta.knownVulnerabilities`; the implementer checks the wording against the
  nixpkgs manual before keeping it, and drops the clause if unsure.)
- `docs/manual/packages.md:71-76` (the stale-index section): "it carries **no
  flags at all**, and every package reads as free" becomes "a **Selection** row
  carries no flags at all, so every package reads as free, and a **search**
  row can show flags that are outdated, or missing one such as `insecure`". The
  footer sentence and the `r` instruction stay.
- `docs/manual/packages.md:93`: "`unfree` and `broken` are **not known**"
  becomes "`unfree`, `broken` and `insecure` are **not known**".
- `PkgModel.qml:888`: same change inside the message string.

### 3. Tests (`tests/qml/tst_card.qml`)

One new function and two appended fixture rows. A row is only a plain object, so
nothing else is needed.

```
{ attr: "openssl_1_1", channel: "default", summary: "an insecure package",
  version: "1.1.1w", flags: ["unfree", "insecure"] },      // selRows[6]
{ attr: "insecure-search", flags: ["insecure"],
  summary: "a search row, no channel" }                    // selRows[7]
```

```
function test_insecure_tag_is_urgent() {
  useRows(selRows, 2)
  var lv = find(card, "QQuickListView")
  var sel = tagsIn(lv.itemAtIndex(6))
  var srch = tagsIn(lv.itemAtIndex(7))
  compare(sel.map(t => t.text), ["unfree", "insecure", "default"])
  verify(Qt.colorEqual(sel[1].color, Commons.Color.urgent), "insecure selection row is urgent")
  compare(srch.map(t => t.text), ["insecure"])
  verify(Qt.colorEqual(srch[0].color, Commons.Color.urgent), "insecure search row is urgent")
}
```

It sits beside `test_channel_tag_tones` (`:794-804`), whose assertions about
`unfree`, `broken` and the dim default stay as they are (they are what proves
`insecure` did not shift the other tones).

**Measured** (scratch copy from `mktemp`, `qmltestrunner` 6.12.0 from
`nixpkgs#qt6.qtdeclarative`, offscreen, with the files copied as
`flake.nix:102-114` copies them; nothing under the worktree touched):

| Card.qml | tst_card.qml | Result |
|---|---|---|
| main | main | passes (baseline, 47 tests) |
| main | with the two rows and the test | **fails**: `'insecure selection row is urgent' returned FALSE` (`tst_card.qml:816` in the copy) |
| with the one-condition change | with the two rows and the test | 48 passed, 0 failed, including the 800 and 700 width test over the new rows |

So the test fails on main for the right reason and passes with the change.
The other four QML test files are not touched.

**Must fail on main** (the plan records it again, with the final text):
`test_insecure_tag_is_urgent`. **Pass on main, must keep passing:** every
existing test in `tst_card.qml`, including the width test, and
`tests/adapter.sh` (no `bin/nixarchy-pkg` change, so it is not rerun beyond
the gate).

Mutation proof, `mktemp` copy only, `( cd "$d" || exit 1; ... )`: change
`"insecure"` in the new condition to `"insecur"`; the new test must fail.

No test is added for the docs or for `PkgModel.qml:888`: no test reads that
string (`grep "not known" tests` finds none), and adding one here would test a
sentence rather than a behaviour.

### 4. The follow-up issue (not filed)

Title: **Panel: show the version on search rows (the index's sixth field)**

Body, for the owner to file or amend:

> nixarchy#1818 gave every index row a sixth field, the version (empty on app,
> opt, flatpak and new-package rows). Selection rows already show a version
> (`Card.qml:388`), scraped from the preview by `labels_tsv`
> (`bin/nixarchy-pkg:577-588`). Search rows show none; the preview pane beside
> them does. Decide: (a) add a `version` key to `cmd_search` rows, a change to
> the JSON contract (`docs/manual/from-a-terminal.md:222-226`), and show it;
> (b) replace the preview scrape with `$6`, which saves three lines but drops
> versions from a fresh index built by an older installed builder (five fields;
> staleness compares the builder's inputs, `bin/nixarchy-pkg:463-465`, not row
> width), so it needs a fallback or a minimum builder version, and the
> `tests/adapter.sh` fixtures (five-field rows at `:561`, `:599`, `:650-660`,
> `:2525`, `:2728-2732`) move to six. Raised by #94 and out of its scope.

## Alternatives rejected

- **A third tone for `insecure`** (a deeper red, or a filled tag). Needs a
  colour this plugin does not own, and the contrast work was settled in #55.
  Urgent is the colour for "can hurt the machine", which is the intent's Q1.
- **Decide the tone in `bin/nixarchy-pkg`** (a `tone` field on each row).
  Widens the JSON contract for a presentation detail; the panel already owns
  the tone, one line for every other flag.
- **A list of tones in a map** (`{broken: urgent, insecure: urgent, ...}`).
  More code than one extra `||` for a three-way expression; revisit when a
  fourth flag arrives.
- **Detect insecure from the preview text** ("Marked INSECURE in nixpkgs.").
  The intent's constraint: the tag comes from the flags word, never a scrape.
- **Fix the three #493-history comments** (Decision 4). Not wrong, and not the
  intent's scope.

## Risks

- **Old index, no flag.** Until the user's installed `nixarchy-search` carries
  #1818 and the index is rebuilt (about a minute), nothing is marked. The
  walk is in the stamp (`bin/nixarchy-pkg:463-465`), so one rebuild prompt
  appears when the installed nixarchy updates. An unmarked package is not a safe
  package; the corrected comment and manual say so. Not fixable here.
- **Two urgent tags look alike.** A package both `broken` and `insecure` draws
  two red tags side by side, told apart by the word. Accepted (Decision 1).
- **Width.** An insecure tag adds about the width of `broken`, a word of 8
  characters. The summary column's formula already subtracts `flags.width`;
  measured by the width test above at 800 and 700.
- **`flags` word set is nixarchy's.** If nixarchy renames the word (it has
  said `insecure`, #1818), rows go dim, not wrong. The shape is covered by
  nixarchy's own golden test (`tests/pkg-index.nix`), not here.
- **Not verified on a real index.** Rows in the test are hand-written; the
  live check below has not run.

## Verification

1. `qmltestrunner` on `tst_card.qml` (the flake's `qml-tests` check,
   `flake.nix:102-114`): green, 48 tests; the new test recorded as failing
   against main's `Card.qml` in a `mktemp` copy; the mutation proof fails as
   stated. Already measured above on the spec's text; the plan repeats it on
   the real diff.
2. `nix flake check`: `qmllint` on `Card.qml` and `PkgModel.qml` and `shellcheck` unchanged. The
   nixarchy-side `qml-color-qualified` check reads comments as code (#101,
   #102): keep new comment text free of `Color.` fragments.
3. Text corrections: `grep -n "unfree and broken\|unfree or broken" Card.qml
   PkgModel.qml docs/manual/packages.md` finds nothing (exit 1 is the pass;
   the sentences Decision 4 leaves alone are in other files), and
   `packages.md` says "Four things".
4. **Live, in a `nixarchy-desktop` microVM** (the owner's standing choice; not
   razer). The guest needs a nixarchy at or after #1818 (merge commit in
   `origin/main`; the pin in the guest's flake must be to a nixarchy that has
   it, 74000e98 does). Inside the guest only: `nixarchy-pkg reindex`
   (about a minute); `nixarchy-pkg search <name of an insecure package>`
   shows `insecure` in `flags`; the panel's Selection tab on a selection that
   holds one, and the search results for it, draw the tag in the urgent colour
   (screenshot from the guest); the preview paragraph reads "Marked INSECURE in
   nixpkgs."; an `other` row for the same package has no insecure tag; with
   the index made stale (guest only), the Selection row loses the tag and the
   footer asks for a rebuild. The intent measured 123 flagged packages on the
   nixpkgs #1818 was tested against; the guest's count is recorded, not
   assumed.
5. Owner's review of Decisions 1-6 before the plan is written.
