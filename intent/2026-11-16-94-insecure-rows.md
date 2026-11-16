---
status: draft
issue: 94
author: olafkfreund
---

# Intent: selection rows mark an insecure package

## Problem

A package with a known vulnerability looks the same as a safe one on the
Selection tab. Nothing tells the user before it is built.

- The panel draws a row's tags from `flags` plus the channel
  (`tagsOf`, `Card.qml:56-60`). Each tag's tone is one expression:
  `broken` is `Commons.Color.urgent`, `unfree` and `other` are
  `Commons.Color.accent`, anything else is dim (`Card.qml:342-344`). Any
  other word in `flags` already draws, in dim.
- A default Selection row gets its `flags` from the index. `labels_tsv`
  copies the index's flags column and the version for a default package
  (`bin/nixarchy-pkg:504-516`); `cmd_state` splits it into `flags`
  (`:2531-2538`) and `cmd_search` does the same for search rows
  (`:600-614`). Neither adapter path names `unfree` or `broken`, so a new
  flag word needs no adapter change. The one exception is `untag`
  (`:79-83`), which strips a `[unfree]` or `[broken]` suffix from the summary;
  it knows no `insecure`.
- The index does not carry the flag. The panel's own text says so
  (`Card.qml:576-578`, `bin/nixarchy-pkg:361-365`, `:2442-2444`), and nothing
  in the code mentions `insecure`; only the #64 and #71 artifacts do. The
  index builder, `pkg-index.nix` in nixarchy, emits only attr, version,
  description, homepage, licence, unfree and broken. Adding it is
  olafkfreund/nixarchy#1814, which is open and has no linked fix.
- An index is called stale by `index_facts` (`:388`) when its stamp differs
  from the installed builder's inputs, and `cmd_state` reports that as
  `indexStale` (`:2485`, `:2542`). So an old index turns stale once the
  installed `nixarchy-search` carries the new builder, not when #1814 merges
  upstream. `cmd_state` gives a selection row no facts from a stale index
  (`:2506`); `cmd_search` still returns flags from it. The footer says "index
  stale" and the key to rebuild (`PkgModel.qml:1070-1081`); it does not say
  that flags may be missing (that is only a code comment, `Card.qml:576-578`).
- An `other` row carries no flags, by the #64 rule: the index describes this
  machine's nixpkgs, not the other channel's (`PkgModel.qml:842-846`). So an `other` row can never be marked.
- The tests cover the existing tones (`tests/qml/tst_card.qml:786-796`), with
  no insecure row in the fixtures (`:19-38`), and the manual says a default
  package "may also carry `summary`, `version` and `flags`"
  (`docs/manual/from-a-terminal.md:190-194`) without naming any flag.

Split out of #71, which left it undone because nixarchy cannot supply the flag.

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
- Files: `Card.qml` (the tone expression), `tests/qml/tst_card.qml` (a
  fixture row and one test), `docs/manual/from-a-terminal.md`; maybe
  `bin/nixarchy-pkg` (`UNTAG_JQ`, and `tests/adapter.sh`, if the index writes
  an `[insecure]` suffix into the summary); the other-channel confirmation,
  which says only "unfree and broken are not known" (`PkgModel.qml:873-875`);
  `docs/manual/packages.md`, which lists "three things a row can be marked
  with" (`:52`) and repeats the other-channel note (`:93`).
- Outside this repo: nixarchy's `pkg-index.nix` (#1814), which this waits on.

## Constraints

- No new runtime dependency, no evaluation of nixpkgs, no writer changed. The
  panel stays a viewer.
- The adapter's JSON contract may gain nothing and lose nothing: `insecure`
  is a word inside `flags`, not a new field (`docs/manual/from-a-terminal.md`).
- Do not guess. A package gets the tag only because the index says so, never
  from its name, its version or a list kept here.
- The decided rule from #64 holds for Selection rows: no flag for an `other`
  row, none from a stale index. Search rows keep their present behaviour,
  which shows whatever flags the index has.
- No code is merged that nothing can reach. See question 2.
- Live check in a `nixarchy-desktop` microVM: the owner's standing choice.

## Open questions

The exact flag word and where the tag sits are design. They go to the spec.

1. **Which tone: urgent like `broken`, or accent like `unfree`?**
   Recommended: urgent. `unfree` is a licence choice the user already made;
   `broken` and a known vulnerability are the two that can hurt the machine.
   Accent would make an insecure package look as harmless as an unfree one.
2. **Land the panel side now, behind fixtures, while nixarchy#1814 is open?**
   Recommended: no; keep the issue open, and start when #1814 lands. The
   change is one line, one test and one manual sentence, so waiting costs
   little. Merging now adds a tone nothing on a real index can reach, and
   the first real index would be the first test of it (the dead-code reasoning
   of #71, question 2). If the owner prefers to land now, the fixtures prove
   the tone, and the live check waits.
3. **Do search rows mark it too?**
   Recommended: yes, and it costs nothing extra. Search rows already draw
   `flags` through the same `tagsOf` and tone expression (`Card.qml:56-60`,
   `:342`),
   and #1814 asks for "a search row and a selection row" both. The test then
   covers both a search and a selection row.
4. **Does the index also write `[insecure]` into the summary?**
   It does for `[unfree]` and `[broken]`, and `untag` strips them so the
   flag is not said twice (`:79-83`). Recommended: ask when #1814 lands, and
   extend `untag` only if the builder does it. Not decidable before then.
