---
status: approved
issue: 94
author: olafkfreund
---

# Intent: selection rows mark an insecure package

> **Revised 2026-11-17.** The earlier approval assumed a nixarchy #1814
> design that did not land. What landed is olafkfreund/nixarchy#1818
> (merged, closes #1814): the flag word is `insecure`, in the flags column
> after `unfree` and `broken`; the preview gains a "Marked INSECURE in
> nixpkgs." paragraph; there is **no** `[insecure]` summary suffix; and
> every index row gains a sixth tab field, the version (empty on app, opt,
> flatpak and new-package rows). So question 4 is answered, question 2's
> blocker is gone, `untag` needs no change, and a new question 5 asks
> whether the panel should use the version field. Every `file:line` below
> was re-read on this branch (merged with main) and on `origin/main` of
> nixarchy on 2026-11-17. Status is back to `draft` for re-approval.

## Problem

A package with a known vulnerability is not marked with any emphasis on the
Selection tab. Since nixarchy#1818 the index puts the word `insecure` in the
row's flags, so the panel already draws it, but in the dim default tone, the
same as any unknown word; the preview pane says "Marked INSECURE" in plain
text. Nothing makes the row stand out before it is built.

Paths are in this repo unless prefixed `nixarchy:` (olafkfreund/nixarchy,
`origin/main` after #1818).

- The panel draws a row's tags from `flags` plus the channel and scope
  (`tagsOf`, `Card.qml:59-62`). Each tag's tone is one expression:
  `broken` is `Commons.Color.urgent`, `unfree` and `other` are
  `Commons.Color.accent`, anything else is dim (`Card.qml:346-348`). Any
  other word in `flags` already draws, in dim.
- A default Selection row gets its `flags` from the index. `labels_tsv`
  copies the index's flags column ($4) and scrapes the version out of the
  preview ($5) for a default package (`bin/nixarchy-pkg:577-588`);
  `cmd_state` splits it into `flags` and `version` (`:2735-2745`, fed by
  `--rawfile labels` at `:2718`) and `cmd_search` splits $4 the same way for
  search rows (`:677-683`). Neither path names `unfree` or `broken`, so a
  new flag word needs no adapter change. The one exception is `untag`
  (`UNTAG_JQ`, `:83-87`), which strips a `[unfree]` or `[broken]` suffix
  from the summary; it knows no `insecure`.
- **The index now carries the flag** (nixarchy#1818). The walk computes a
  boolean `insecure`, true when `meta.insecure == true` or
  `meta.knownVulnerabilities` is a non-empty list, each behind its own
  `try` (`nixarchy:modules/pkg-index.nix:67-80`). The index jq appends
  `insecure` to the flags column after `unfree` and `broken`
  (`nixarchy:modules/apps.nix:3719-3723`, space-separated) and adds the
  paragraph "Marked INSECURE in nixpkgs." to the preview (`:3729`). It does
  **not** write `[insecure]` into the summary: the summary expression adds
  only `[unfree]` and `[broken]` (`:3715-3718`), and #1818's description
  says so. Nothing in this repo mentions `insecure` yet.
- **The index now has six fields**, not five: kind, name, summary, flags or
  type, preview, and a sixth, the version (`.version`, `:3735`; the
  builder's own comment, `:3651-3655`). `pkg` rows carry the version; `app`,
  `opt`, flatpak and new-package rows carry an empty sixth field. Fields 1-5
  keep their positions (appended, never inserted), and #1818 checks both:
  a golden of fields 1-5 of app, opt and pkg rows
  (`nixarchy:tests/pkg-index.nix:148-160`, `tests/fixtures/pkg-index.golden.tsv`)
  and separate assertions of six fields on every row kind and of the version
  value (`:118-131`).
- Every reader of index rows in this repo, checked for a sixth field. None
  breaks. I also ran `nixarchy-pkg search` and `state` against a six-field
  index in a `mktemp` directory, and the `labels_tsv` awk on its own; all
  gave the same rows as five fields.

  | Reader | Reads | Six fields |
  |---|---|---|
  | `labels_tsv` (`bin/nixarchy-pkg:577-588`) | `awk -F'\t'`, `$1`-`$5` only; version scraped from `$5`'s `\nversion:  ` line | harmless; `$6` ignored |
  | `cmd_search` awk (`:636-656`) | `$1`-`$5` by name, prints them with the scope; for index rows the scope is the constant `"system"` (`FILENAME == idx`), never `$6` | harmless. The `$6` of an index row is not the scope, so the `FILENAME != idx && $6 != "system"` filter cannot see it; only `rows.tsv` rows (options, six fields by design) reach it |
  | `cmd_search` tail (`:656`) | `sort -k1,1n -k2,2n \| cut -f3-` over the awk's own output, not over the index | harmless |
  | `cmd_search` jq (`:677-698`) | `split("\t")`, `.[0]`-`.[4]`, `.[5]` read as scope of the awk's output | harmless: the awk output is rebuilt, so `.[5]` is still the scope |
  | `cmd_state` facts (`:2735-2745`) | `split("\t")` of `labels_tsv`'s own five columns | harmless; `labels_tsv` emits its own shape |
  | `UNTAG_JQ` (`:83-87`) | the summary string and the flag list | harmless |
  | `extras_tsv`, `rows_tsv`, `$OPT_DIR/rows.tsv` (`:547`, `:495-541`, `tests/adapter.sh:2540`) | the selection files and the options cache, not the index | not index readers; `NF != 6` at `tests/adapter.sh:2540` is the options file and stays right |
  | `index_facts`, `index_recognised`, `INDEX_INPUTS` (`:436-473`) | the stamp, not rows | the walk is already an input (`'*-pkg-index.nix'`), so an installed nixarchy with #1818 makes the old index `stale` once; no change |

  Fixtures in `tests/adapter.sh` write five-field rows (`:561`, `:599`,
  `:650-660`, `:2525`, `:2728-2732`). They still pass as they are, because no
  reader looks past `$5`; they are the **old** index shape, and the one
  that will matter is `state` reading a version. They do not need a sixth
  field unless the panel starts to read it (question 5).
- An index is called stale by `index_facts` (`:457`) when its stamp differs
  from the installed builder's inputs, and `cmd_state` reports that as
  `indexStale` (`:2748`). Because the walk's store path is in the stamp, an
  installed `nixarchy-search` carrying #1818 makes every existing index stale
  once, and the first rebuild (about a minute) brings the flag in, not the
  merge itself. `cmd_state` gives a selection row no facts from a stale
  index (`if ! $stale`, `:2710`); `cmd_search` still returns flags from it.
  The footer normally reads "index built <ago> -- r to rebuild" with what
  changed, and "index stale" only when it has no build time
  (`PkgModel.qml:1084-1094`); it does not say that flags may be missing.
  Two texts say a stale index "has no flags at all" (`Card.qml:580-582`,
  `docs/manual/packages.md:71`). That is true of Selection rows
  and false of search rows, which keep the cached flags (`cmd_search` ignores
  staleness for them), so a stale search row can show flags that are outdated
  or, for `insecure`, absent. The change should correct both texts to say so
  and name `insecure`.
- An `other` row carries no flags, by the #64 rule: the index describes this
  machine's nixpkgs, not the other channel's (`bin/nixarchy-pkg:2781-2783`,
  `PkgModel.qml:855-859`). So an `other` row can never be marked.
- The version is already on screen for a Selection row. `cmd_state` returns
  `version` from the preview scrape and `Card.qml:388` draws it before the
  summary. A search row carries no version: `cmd_search` builds `summary`,
  `type`, `flags`, `scope` and `preview` and never a version (`:677-698`),
  and drops `$6`. The preview pane beside a search row does name the version
  and, after #1818, the "Marked INSECURE" paragraph, so the detail pane says
  it before the list tag does.
- The tests cover the existing tones (`tests/qml/tst_card.qml:794-804`), with
  no insecure row in the fixtures (`:19-38`), and the manual says a default
  package "may also carry `summary`, `version` and `flags`"
  (`docs/manual/from-a-terminal.md:222-226`) without naming any flag.

Split out of #71, which left it undone because nixarchy could not supply the
flag. It now can.

## Proposed outcome

- When the index flags a default package `insecure`, its Selection row draws
  an `insecure` tag, in a tone that stands out from the dim default.
- A package that is not flagged, an `other` package, and a package the stale
  or missing index does not know, all look as they do today. No row claims
  safety it cannot know.
- The tag is covered by one test in `tests/qml/tst_card.qml`, and the manual
  names the flag.
- The summary column still fits beside the new tag at the widths the card
  supports.

## Affected users and systems

- Everyone who adds packages through the panel, on any host.
- Files: `Card.qml` (the tone expression, `:346-348`), `tests/qml/tst_card.qml`
  (a fixture row and one test), `docs/manual/from-a-terminal.md`; the
  other-channel confirmation, which says only "unfree and broken are not
  known" (`PkgModel.qml:888`); `docs/manual/packages.md`, which lists "three
  things a row can be marked with" (`:52`) and repeats the other-channel
  note (`:93`). The `Card.qml:580-582` comment names "unfree or broken" and
  should say insecure too.
- **Not** touched, now known: `bin/nixarchy-pkg` (`UNTAG_JQ`, because there
  is no `[insecure]` suffix) and `tests/adapter.sh`, unless question 5 is
  answered yes.
- Outside this repo: nothing waits. nixarchy#1818 is merged; the flag
  reaches a user only once their installed `nixarchy-search` has it and the
  index is rebuilt.

## Constraints

- No new runtime dependency, no evaluation of nixpkgs, no writer changed. The
  panel stays a viewer.
- The adapter's JSON contract may gain nothing and lose nothing: `insecure`
  is a word inside `flags`, not a new field (`docs/manual/from-a-terminal.md`).
  This is why question 5 recommends against a `version` change to search
  rows.
- Do not guess. A package gets the tag only because the index says so, never
  from its name, its version or a list kept here.
- The decided rule from #64 holds for Selection rows: no flag for an `other`
  row, none from a stale index. Search rows keep their present behaviour,
  which shows whatever flags the index has.
- No code is merged that nothing can reach. After #1818 a real index can
  reach it (question 2).
- Live check in a `nixarchy-desktop` microVM: the owner's standing choice.
  It needs a guest whose `nixarchy-search` carries #1818, then a reindex; 123
  packages are flagged on the nixpkgs #1818 was measured against.

## Open questions

The exact flag word is settled (`insecure`, by #1818). Where the tag sits is
design, and goes to the spec.

1. **Which tone: urgent like `broken`, or accent like `unfree`?**
   Recommended: urgent. `unfree` is a licence choice the user already made;
   `broken` and a known vulnerability are the two that can hurt the machine.
   Accent would make an insecure package look as harmless as an unfree one.
2. **Land the panel side now?** Changed by #1818: the blocker is gone.
   Recommended: yes, start the spec now. The change is one line, one test
   and a few manual sentences, and a real index can now reach it, so it is
   not dead code. The live check needs the #1818 builder in the guest.
3. **Do search rows mark it too?**
   Recommended: yes, and it costs nothing extra. Search rows already draw
   `flags` through the same `tagsOf` and tone expression (`Card.qml:59-62`,
   `:346`), and #1814 asked for "a search row and a selection row" both.
   The test then covers both a search and a selection row.
4. **Does the index also write `[insecure]` into the summary?**
   Answered by #1818: no. `untag` stays as it is, and there is no suffix to
   duplicate the tag. Nothing to decide; the spec need not mention it.
5. **Should the panel show the version now that the index has a field for
   it?** Selection rows already show it (`Card.qml:388`), scraped from the
   preview by `labels_tsv`; search rows do not, and their preview pane does.
   Recommended: **no, not in this issue.** Three reasons. It is not what
   #94 is about, and the JSON contract may gain nothing here. A search row
   showing a version would add a `version` key to `cmd_search`, a contract
   change that wants its own issue and its own decision (a row of 50 search
   results would also grow wider for a field the preview already gives).
   And replacing the preview scrape with `$6` (three lines gone in
   `labels_tsv`) saves little, drops versions from an old five-field index.
   That index is not necessarily stale: staleness compares the installed
   builder's inputs (`bin/nixarchy-pkg:463-465`), not row width, so an older
   installed builder keeps a fresh five-field index and `cmd_state` still
   reads facts from it (`:2710-2718`). It would need a fallback or a minimum
   builder version, and would need the `tests/adapter.sh` fixtures
   moved to six fields. Worth a follow-up issue; the owner may prefer to
   fold the `labels_tsv` cleanup in, in which case the spec adds it and the
   fixtures change.
