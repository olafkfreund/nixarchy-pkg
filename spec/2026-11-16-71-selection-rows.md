---
status: approved
issue: 71
intent: intent/2026-11-16-71-selection-rows.md
---

# Spec: selection rows say what the package is, where that can be known

## Design

Line numbers are current `main` (5a8ca0b). This branch was cut earlier, at
098ed16, and must be rebased before the plan is written.

The facts come from the index the adapter already reads, in a pass it already
makes, and only for a package whose own nixpkgs is this machine's. The rest of
the rule is enforced by what the adapter does not look up, so the panel cannot
draw a borrowed fact because none reaches it.

The intent's settled answers, stated as decided:

- The version is read from the `version:` line in the preview text (column 5).
  The index gets no new column in this task. The nixarchy issue mentions one.
- This task is done when channel, description, version and the index's own
  flags ship and the nixarchy issue is filed. Marking `insecure` is a
  follow-up in this repo after nixarchy carries the flag. No `insecure` field,
  key or test is added now.
- The decided rule is fixed: channel always; description and version only
  from the package's own nixpkgs, so never for an `other` row and never from a
  stale index.

### Decisions for the owner

These are the points the intent left to the spec. Each is my choice, with the
reason. Say so at review if one should go the other way.

1. **The lookup lives in `cmd_state`, not in a per-row `search`.** One awk
   pass over the index, fused with the pass `labels_tsv` already makes for
   the Apps and Services labels. Measured: `state` goes from 0.12 s to 0.19 s
   (five selected packages, 113,370 package rows, 59.8 MB index, scratch XDG
   dirs); the awk pass alone is 0.06 s for labels only, 0.13 s fused, and 0.14 s
   for fifty selected attrs, so it barely grows with the selection. A
   per-row `search` would be N more scans of the same file and N more
   processes, and would need an async path in `PkgModel`. A stale index, or
   no `default` rows, costs nothing extra.
2. **The facts ride on the existing `packages` rows, under names `Card.qml`
   already draws.** `summary` (the description), `version`, and `flags`. A
   key is present only when known. `summary` is the name the second column
   already reads (`Card.qml:369`), and `flags` the one the tag box already
   reads (`Card.qml:326`), so the description and the unfree/broken/curated
   tags need no new drawing. Only `version` is new to the card.
3. **`flags` from the index are included for a default row.** The intent names
   description and version, but its `other` line says "no description,
   version or flag is borrowed", which only means something if a default row
   has them. They come from the same fresh index and mean the same as on a
   search row. The summary loses its `[unfree]` / `[broken]` suffix when the
   flag is there, by the same rule `cmd_search` uses (`:505-507`), so the
   warning is said once. If you would rather ship description and version
   only, drop `flags` from the awk, the jq and the manual; nothing else
   depends on it.
4. **The channel is a tag on every row, drawn by the flags box.** `default`
   dim, `other` in the accent colour (the colour unfree already uses). A
   default row has the tag too, so "every row says its channel" is literally
   true, and dim is as quiet as the existing tags get. The words are the
   JSON's own (`default`, `other`), the same ones the manual and the
   `#@pkg-other` marker use. The alternatives are under Alternatives rejected.
5. **The version is the front of the second column**: `15.2.0  Utility that
   ...`, two spaces, dim like the summary. It is not its own column, because
   every term in that row's width sum was a defect once (#45, #51) and a new
   one buys nothing the string does not.
6. **An empty fact is an absent key.** An empty summary (10,413 package rows
   have none), a summary that is only the stripped tags, an empty version
   (5, all `tests.testers.*`) and the builder's `?` version are dropped from
   the row, not sent as `""` or `"?"`. A package the index does not have gets neither
   key, nor `flags`.

7. **Narrow cards: accepted, not fixed.** See the width paragraph under the
   card. A row with three index flags and a tag overflows a card narrower than
   about 620 px, where main overflowed below about 540 px. Fixing it means
   letting the name column yield to the tags, which is a layout change to
   every tab and its own issue. Say so at review if you want it here.

### The adapter, `bin/nixarchy-pkg`

`cmd_state` (`:1975`) passes `labels_tsv` the list of attrs it may look up:

```bash
local want=""
if ! $stale; then
  want=$(extras_tsv | awk -F'\t' '$1 == "pkg" && $3 == "default" { printf "%s ", $2 }') || want=""
fi
```

The `|| want=""` keeps the answer partial rather than fatal when the
selection file cannot be read (`set -euo pipefail`, `:46`). The list is empty
when `index_stale` (`:324`) is true, and holds only
`default` rows when it is not. That is the whole rule: an `other` attr, or any
attr on a stale or missing index, is not looked up, so no code after this
point can leak a fact for it. (An attr selected both ways is looked up for
its default row, and the row-level test in the jq below keeps the `other`
row bare.) `extras` stays a `--rawfile` (`:1999`). It is not captured into a variable
and passed with `--arg`: that puts it in argv, which has a size limit, and
the unreadable-file case would then end the script (see Risks). The attr list
is made by a second, cheap read of the selection file instead.

`labels_tsv` (`:424`) takes that list and writes one stream with a kind in
column 1, so one scan serves both:

```
app<TAB>id<TAB>label
pkg<TAB>attr<TAB>summary<TAB>flags<TAB>version
```

The `pkg` clause is `n && $1 == "pkg" && ($2 in w)`. The leading `n` keeps the
no-selection case at today's cost. The version is cut out of column 5 between
the literal `\nversion:  ` and the next literal `\n` (the index stores its
newlines escaped; `cmd_search` unescapes them later, `:516`). If the line is
absent the version is empty. The builder writes `version:  ?` for a package
with no version (`nixarchy-search:192`), so `?` is an absent version too.
Neither field is decoded: `@tsv` escapes a backslash in a description, and
the summary is copied as `cmd_search` copies it today, so a state row and a
search row for the same package read the same. The first occurrence is the header's: the
description comes after the licence and homepage lines.

The jq in `cmd_state` (`:1930-1971`) splits that stream on column 1. The old
`$label` map keeps its shape; a `$fact` map is built from the `pkg` lines with
the suffix strip (the same two `gsub`s as `:505-507`, widened to eat the two spaces the builder
writes before each tag, and followed by a trim, kept in one definition
shared by both commands so they cannot drift). `packages` becomes:

```jq
packages: ($extras | cols | map(select(.[0] == "pkg") | {
  attr: .[1], channel: (.[2] // "default")
} + (if .[2] == "default" and $fact[.[1]]
     then $fact[.[1]] | with_entries(select(.value != "")) else {} end)))
```

Before that filter the `$fact` build maps a version of `?` to `""` and trims the
summary, so a blank result is dropped like any other empty one. `flags` is an array, so `select(.value != "")` keeps it, `[]` included: an
empty `flags` on a found row says "the index lists none". The `$stale` flag
needs no change; `indexStale` is already in the answer and drives the notice.

### The JSON shape

`state.packages[]` before and after:

```jsonc
// default, fresh index, found
{ "attr": "ripgrep", "channel": "default",
  "summary": "Utility that combines the usability of ...",
  "flags": [], "version": "15.2.0" }
// firefox: flags are the index's own
{ "attr": "firefox", "channel": "default", "summary": "Web browser built from Firefox source tree",
  "flags": ["curated:firefox"], "version": "159.0" }
// default, not in the index; or the index is stale or missing
{ "attr": "nosuchpkg", "channel": "default" }
// other channel, always
{ "attr": "vlc", "channel": "other" }
```

These samples are from a prototype run against a scratch copy of this
machine's index. `attr` and `channel` are untouched; nothing is renamed or
removed (`docs/manual/from-a-terminal.md:135-141`). `summary`, `version` and
`flags` are additive and optional, and the manual says so (below).

### The card, `Card.qml`

A prototype in a scratch copy, run with `qmltestrunner` (Qt 6.12, offscreen):
the 32 existing tests still pass, selection rows draw their tags, and the
summary fits its row at all four shapes (default with facts, other, default
bare, default with unfree and curated).

- A function `tagsOf(row)` (near `rowColor`, `:46`):
  `(row.flags || []).concat(row.channel ? [row.channel] : [])`. Only
  selection rows have a `channel`, so Apps, Services, search and Queue rows
  draw exactly what they do now. A search row shown on the Selection tab
  while a query is typed has none.
- `:326` and `:329` read `root.tagsOf(modelData)` instead of
  `modelData.flags || []`. The wrapper's `visible` and the width sum
  (`flags.visible ? 3 : 2`, `flags.width`) already count the tags, so no layout term
  changes. They do not make room: see the width paragraph below.
- `:333`: `other` joins `unfree` in `Commons.Color.accent`; every other
  unlisted tag, `default` among them, stays `root.dim`.
- `:369`: the second column is
  `(modelData.version ? modelData.version + "  " : "") + (modelData.summary || modelData.note || modelData.type || "")`.
  A row with neither is empty, as a bare row is today. No guess fills it.

**Width.** The tag costs about 82 px (measured: a row with `unfree`, `broken`
and `curated:...` leaves a 366 px summary at a 900 px card without it, 284 px
with it). The summary fits at 900, 760 and 700 px either way. A row carrying
three flags already overflows on main below about 540 px (34 px at 500, 134 px
at 400); with the tag it overflows below about 620 px (16 px at 600, 116 px at
500). The overflow is the existing one: the name and tags keep their widths
and only the summary yields (`Card.qml:367`). A card is the lesser of 1100
scaled px and 72% of the panel (`Menu.qml:168`), so 600 px is a small screen,
and a three-flag selection row is rare. I accept that, and do not change the
width sum here (decision 7). The tests assert fit at 800 and 700 px.

Not changed: `PkgModel.qml` (it passes the rows through; nothing there reads
a selection row's fields except `attr`), any writer, the Selection tab's
scope line (`:162-`), the preview pane (a selection row has no `preview`,
so it still draws no pane; giving it one is a separate decision), and the
stale-index notice (`:560`), which stays the one place that says why a row is
bare.

### The manual, `docs/manual/from-a-terminal.md`

- The "Every package taken from the other channel" example stays.
- One line in the `packages` description (`:23` area, and the stable list at
  `:135-141`): a package row carries `attr` and `channel`; on a default
  package whose own index is fresh it may also carry `summary`, `version` and
  `flags`; they are left out, never empty, when the index is stale, missing,
  or does not have the package, and for every `other` package. Optional
  fields are not part of the "relied on" shape.

### Companion issues

**nixarchy: "pkg-index: carry meta.insecure / knownVulnerabilities as an index flag"**
(filed with this task; this is what lets the task be done). The panel marks
`broken` and `unfree` from the index's flags column, but nothing marks an
insecure package, because `pkg-index.nix` emits only attr, version,
description, homepage, licence, unfree and broken. Add `insecure` to the walk
and write it into the flags column of the `pkg` rows, beside `unfree` and
`broken`, so a search row and a selection row can both warn on it. Also
consider a `version` column: today it exists only as a `version:` line inside
the preview text, and this repo reads it from there (#71). A column would
make that parse unnecessary, but nothing here waits for it. Adding the flag
changes what the index is built from, so `index_stale` will call old indexes
stale, which is correct.

**nixarchy-pkg: "Selection rows: mark an insecure package"** (this repo, opened
now, blocked on the nixarchy issue). When the flag arrives, a default row's
`flags` carries `insecure` with no adapter change beyond the existing flags
column, and `Card.qml`'s tone for it is the work: one line, plus a test.
Open it so the follow-up is tracked rather than remembered.

## Alternatives rejected

- **A per-row `search --kind pkg` from the panel.** N scans of a 60 MB file and
  an async path for each row. The state already scans it once, for labels.
- **A separate awk in `cmd_state` for the facts.** A second pass costs the
  same 0.06 s again. One fused pass is a smaller diff than it sounds: the
  function is the same, with one more clause.
- **Reading the facts for an `other` row and hiding them in the panel.** The
  rule is that they are not known, and a borrowed fact hidden in the JSON is
  one `jq` call from being quoted as fact. Not looked up is the strongest form.
- **Showing facts from a stale index, with a warning.** The intent fixed this:
  a stale index can lack whole fields, so a row drawn from it would repeat the
  lack as fact. The notice stays the one place that says why.
- **A tag only on `other` rows.** Quieter, but then a default row says nothing
  and "every row says its channel" is true by inference. The dim tag costs
  one short word of width per row on a tab that holds a handful of rows.
- **Naming the real channel on the tag** (`unstable` instead of `other`). It
  needs the machine channel in the card, and `custom` has no answer
  (`PkgModel.qml:641-646` already handles that case with a message). The
  JSON's own words are enough and match the manual.
- **A `channel` or `badge` key the card draws separately from `flags`.** A
  second tag path, and a second place for the `#45` width sum to be wrong.
- **A version column in the adapter's own index.** The index is nixarchy's
  file. See the companion issue.
- **Showing the version as a tag.** A tag is a state word; a version is data
  and reads better as text before the description.

## Risks

- **The live index on this machine is stale today**: its stamp differs from
  the installed `nixarchy-search` (`indexStale` is true in a scratch run).
  The panel will therefore show channel tags only until the user reindexes,
  which is the rule working, but it means a live check needs a fresh index
  built first, and in a microVM that is a full build (about a minute, per the
  manual).
- **The version parse depends on a line format nixarchy owns**
  (`version:  X`, two spaces, after the title block). On 113,370 package rows
  today none lacks it; five are empty; two carry spaces
  (`3.5.0+2.004 (6.4.0)`) and show whole. If nixarchy changes the preview
  layout, versions silently disappear (absent, never wrong), and the test on
  a fixture index will not catch it. A nixarchy-side column would. That is in
  the companion issue.
- **`state` is 0.07 s slower with a fresh index and default packages** (0.12 s
  to 0.19 s here, five attrs). It runs on every refresh. Scales with the index
  size, not the number of attrs. If the index grows several-fold, the lookup
  is the first thing to move behind a cache keyed on the stamp.
- **Transport.** The review found that capturing `extras` and passing it with
  `--arg` breaks two things that work on main: an unreadable `apps.nix` ends
  the script with no JSON (the capture runs under `set -e`), and about 2,200
  option rows exceed the argument limit (exit 126). The design keeps
  `--rawfile` for that reason.
- **The awk list is space-separated.** Attrs come from `#@pkg [^ \t]+`, so no
  attr holds a space or tab, and a duplicate attr is a duplicate list entry
  that matches the same rows once. Dotted attrs (`nerd-fonts.blex-mono`)
  match as whole names.
- **An unreadable index** fails inside a process substitution, whose status is
  swallowed (the comment at the top of `cmd_state`). The result is an empty stream: channel-only rows,
  `ok` true, the same as a missing index. That is the intended degrade.
- **`flags` on a default row includes `curated:<id>`** (firefox above), which
  draws as a dim tag on the Selection tab. It is true and useful on a raw
  package; if it reads as noise, filter it in the jq. Decision 3 covers drop.
- **The adapter and the card must ship together.** An older card ignores the
  new keys and a newer card on an older adapter sees no keys; both degrade to
  today's rows. They live in one repo, so this is only a note.

## Verification

Tests. The adapter checks run against `ADAPTER_OVERRIDE`, so the lead runs the
"fail on main" ones against `git show main:bin/nixarchy-pkg` and records the
failure.

`tests/adapter.sh`, a new block in "state" that needs no catalogue (its own
throwaway `XDG_CONFIG_HOME` with an `apps.nix`, `XDG_CACHE_HOME` with a small
`index.tsv`, and a stub `nixarchy-search` on `PATH` holding the seven
`name=value` lines `searched` reads, plus a `stamp` equal to those values, so
the index is fresh; a stamp that differs makes it stale). The index fixture
has: a package with a version line, a description and no flags; one with the
`unfree` flag and `[unfree]` in its summary; one with an empty version line;
one with no `version:` line; one with an empty summary; and a package that
`other` also names. The apps file has a default row for each of these, an
`other` row for the one the index has, and a default row the index lacks.

Must fail on main (each key is absent there):
- a fresh default row carries `summary`, `version` and `flags`;
- the unfree row's summary has no `[unfree]` and its `flags` has `unfree`;
- an empty-description package that has both flags (the builder writes
  `  [unfree]  [broken]` after an empty description) has no `summary` key;
- a state row's `summary` equals the `search` row's for the same package.

Absence cases. Main also omits these keys, so each one asserts a positive fact
in the same row (its `flags`, or its `summary`) and fails on main for that
reason, not for the absence: an empty version line, a missing version line,
and the builder's `?`, each gives no `version` key; an empty description gives
no `summary` key.

Pass on main, kept as guards (they hold the rule, not the feature):
- an `other` row has exactly `attr` and `channel`, though the index has the
  package and a description for it;
- on a stale index (same fixture, a different stamp) every row has exactly
  `attr` and `channel`, and `indexStale` is true;
- a package the index lacks has exactly `attr` and `channel`;
- an unreadable `apps.nix`: `ok` is true, the unreadable-file message is
  there, and the exit status is 0 (a captured `extras` would lose this);
- a selection with many option rows (2,200, about 300 KB of `state`) still
  answers;
- the same attr selected as default and as other: the default row is enriched
  and the other row is bare;
- dotted and dashed attrs match whole names, not near ones;
- no index file at all: `ok` is true, rows are `attr` and `channel`, and the
  answer still comes;
- `attr` and `channel` are unchanged for every row, `packages` keeps its
  order, and the Apps and Services labels still come out (the stream's new
  first column must not have broken them).

`tests/qml/tst_card.qml`, through the existing fake model, Selection tab
(`tab = 2`), rows with `channel`, `version`, `summary` and `flags`:
- must fail on main: a default row draws a `default` tag and an `other` row
  an `other` tag; the second column of a row with a version starts with it;
  a row with `unfree` and a `channel` draws both tags, flags first;
- the summary fits its row (the `#45`/`#51` property, measured, at 800 px and
  at 700 px) with a channel tag alone, with all tags and a version
  and a long summary, and with no facts at all;
- the `other` tag is in `Commons.Color.accent` and `default` in `root.dim`
  (read from the tag's `color`), and a broken flag stays urgent;
- a bare row (`attr` and `channel` only) has an empty second column and no
  warning on the console;
- a search row on the Selection tab, which has `flags` and no `channel`,
  draws its flags and no channel tag; Apps rows draw no channel tag.

`tests/qml/tst_pkgmodel.qml`: no change. The model does not read the new keys.

Other checks:
- `nix flake check` passes: shellcheck on the adapter and `adapter.sh`, and the
  QML tests. Nothing in it checks the manual, so the manual edit is read by
  eye.
- `shellcheck` is clean for the changed function: the `if ! $stale` block and the
  `extras_tsv | awk` pipeline are the places to look.
- Time `state` in the scratch dirs before and after and say the numbers in the
  PR. Measured here at 0.12 s before, 0.19 s after, 0.12 s stale.

Live, in a `nixarchy-desktop` microVM (the owner's standing choice), not on
this machine:
1. Add `ripgrep` (default) and one package from the other channel with
   `SHIFT+RETURN`. Before the index is built, both rows show a tag and
   nothing else, and the "index stale" notice says why.
2. Reindex. The default row now shows its version and description, the other
   row is unchanged, and a package the index does not have is still bare.
3. Look at the Selection tab at a normal card width: the tag, version and
   description do not overlap the name or run off the row.
