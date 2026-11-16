---
status: draft
issue: 71
author: olafkfreund
---

# Intent: selection rows say what the package is, where that can be known

## Problem

A package the user added shows only its attribute on the Selection tab.
Nothing else says what it is, which channel it comes from, or whether it is
safe to keep.

- The adapter's state gives each selection row two fields: `attr` and
  `channel` (`bin/nixarchy-pkg:1969-1971`). `channel` is `other` for a
  `#@pkg-other` line and `default` for a `#@pkg` line
  (`extras_tsv`, `:358-363`).
- The panel never shows `channel`. The row's name is `modelData.attr`
  (`Card.qml:285`). The second column is `summary || note || type || line ||
  category` (`Card.qml:353`), and a selection row has none of those, so it is
  empty. The flags box reads `modelData.flags` (`Card.qml:310`), which a
  selection row does not have.
- The facts are not on the row. `cmd_state` reads the index only for the
  Apps and Services labels (`labels_tsv`, `:384`, used at `:1930`); it looks
  up no package metadata. `cmd_search` is the only place that does
  (`:399`). So a description and a version for a selected package need a
  lookup the adapter does not make today.
- The index has no version column. Its columns are kind, name, summary,
  flags and preview (`:396-398`, `:445-470`), and the version exists only as
  a line inside the preview text (`version:  15.2.0`, seen in the live
  `~/.cache/nixarchy/index.tsv`).
- The index describes this machine's nixpkgs, not the one an `other` package
  comes from. The panel's own comment says the licence and broken status of
  an other-channel request are not known, because the writer's probe is of
  the system's nixpkgs and its other-channel branch returns before the flag
  block (`PkgModel.qml:633-636`). The same holds for a description or
  version taken from this machine's index.
- A stale index can lack whole fields (`:276-281`). `index_stale` calls an
  index stale when it is missing or empty, or when its stamp differs from the
  nixpkgs and builder inputs of the installed `nixarchy-search`
  (`:282-291`). `cmd_state` already reports it as `indexStale` (`:1913`,
  `:1945`). A row drawn from it would repeat that lack as fact.
- `insecure` is not in the index at all. The index walk (`pkg-index.nix` in
  nixarchy) emits only attr, version, description, homepage, licence, unfree
  and broken. The panel cannot mark an insecure package until nixarchy
  carries the flag. Nothing in this repo's code mentions `insecure`; only #64's
  artifacts do.

Split out of #64, item 3. #64's intent decided the rule: show the channel
always; show description or version only when they come from the nixpkgs the
package does; otherwise nothing extra.

## Proposed outcome

- Every row on the Selection tab says its channel. A package from the other
  channel says so; a default one need not shout.
- A default-channel row also shows its description, and its version, taken
  from the index, but only when the index is fresh and has the package.
- An `other` row shows the channel and nothing else extra. No description,
  version or flag is borrowed from this machine's index for it.
- On a stale index, a default row shows the channel only, and the existing
  "index stale" notice stays the one place that says why.
- A package the index does not have shows the channel only. The row is never
  blank where a fact would have been guessed.
- No row claims a package is or is not insecure until nixarchy carries the
  flag. See question 2 for when this task counts as done.
- Tests cover a default row, an `other` row, a stale index and a package
  missing from the index, in the adapter and in the card.

## Affected users and systems

- Everyone who adds packages through the panel, on any host.
- Files: `bin/nixarchy-pkg` (`cmd_state` and the `packages` output),
  `Card.qml` (the row), maybe `PkgModel.qml`, `tests/adapter.sh`,
  `tests/qml/tst_card.qml`, and the manual page that lists the state fields
  (`docs/manual/from-a-terminal.md`, "What is stable").
- Outside this repo: nixarchy's `pkg-index.nix`, for `insecure`. It needs its
  own issue: "pkg-index: carry meta.insecure / knownVulnerabilities as an
  index flag".

## Constraints

- No new runtime dependency, and the panel must not evaluate nixpkgs to show
  a selection row. The facts come from the existing index file or not at all.
- The adapter's JSON contract may gain fields but must not lose or rename
  one (`docs/manual/from-a-terminal.md`).
- The panel stays a viewer: no change to any writer, and no write on this
  path.
- `state` runs on every refresh. A package lookup must not make it slow, and
  must not fail the whole answer when the index is missing or unreadable.
- The decided rule is fixed, not reopened here: channel always; description
  and version only from the package's own nixpkgs, so never for an `other`
  row and never from a stale index.
- Do not guess. An absent fact is absent, not an empty string drawn as if it
  were an answer.
- Live check in a `nixarchy-desktop` microVM: the owner's standing choice.

## Open questions

The lookup's home (adapter state or a per-row search), how the version is
parsed, and how the channel is drawn are design. They go to the spec.

1. **The version has no column in the index.** It exists only as a
   `version:` line in the preview text. Read it from there, or ask nixarchy
   to add a column? Recommended: read the preview line now, and mention the
   column in the nixarchy issue. It works on today's index, and the version
   stays absent when the line is not there.
2. **When is this task done, given `insecure` waits on nixarchy?**
   (a) Done once channel, description and version ship and the nixarchy
   issue is filed; marking insecure is a follow-up in this repo when
   nixarchy lands. (b) Stays open until marking ships. Recommended: (a). The
   rest of the issue is useful now, and a flag nobody writes would be dead
   code that looks like a feature.
