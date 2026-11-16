---
status: draft
issue: 64
intent: intent/2026-11-16-64-review-ui-docs.md
---

# Spec: the panel and its manual say what is true, and the ways to open it never fail silently

## Design

**Decisions from intent approval** (its open questions, taken as
recommended):

1. This task does items 1, 2, 4, 5 and 6, and the `nix flake check` half of
   7. Item 3 (selection metadata and `insecure`) and the Menu, OptionForm
   and Panel tests become their own issues (texts at the end).
2. Category grouping is built.
3. Selection rows (now in the split-out issue): the channel always;
   description or version only when they come from the nixpkgs the package
   does; otherwise nothing extra.
4. Multi-word search: every word must match, in any order.
5. `nix flake check` runs the sections of `tests/adapter.sh` that need
   neither the network nor a catalogue. The flake cases stay in CI.

**Decisions for the owner** (choices this spec makes; overturn them here):

- **Ranking a multi-word query** (left to the spec by decision 4): each
  word gets the existing rank, and the row takes the best (lowest) of
  them. A one-word query ranks exactly as today, and "server ssh" ranks as
  "ssh server" does. (First-word-only was the first draft; it ranked
  `openssh` below every `*-server*` package for "server ssh".)
- **`.settings` rows move to the end of the Apps tab**, under their own
  header "settings — edit in apps.nix", instead of sitting among the apps.
  They keep their glyph and their explanation on RETURN. Hiding them was
  the alternative; they are the only way the panel shows that an app has
  settings at all.
- **A row with no note shows no description.** Not the raw Nix line, and
  not the category, which the new header already shows. On p620's
  selection that is 39 of the 65 apps (measured). Pulling a description
  from the search index's app rows was considered and left out: it couples
  the Apps tab to index freshness.
- **The menu row gets no `when` check.** With one, a disabled plugin hides
  the row, which is silent again. Without, the row is always there and
  `nixarchy-plugin` says why it does nothing. nixarchy's own
  `install.packages` row (with `when`) is unaffected.
- **The unfree example is replaced, not fixed.** `state` does not carry an
  unfree flag for packages (`.packages[]` is `{attr, channel}`), so no
  one-liner can list "everything unfree". The example becomes "every
  package taken from the other channel", which `state` can answer.
- **SHIFT+A advice becomes "before, not after".** No cancel-apply feature
  is added. The manual says to use SHIFT+A instead of `a` on a machine with
  no polkit agent, and that once an apply is running (or stuck), SHIFT+A is
  refused until it ends.
- **The offline switch for the tests is an environment variable,**
  `NIXARCHY_PKG_TEST_OFFLINE=1`, set only by the flake check.

Everything is designed against main plus #60 (PR #70), which merges first.
Line numbers say which: "main :N" or "#60 :N".

### Slice 1 (PR 1): key binding, menu row, manual

**1a. The binding and the row.** Replace
`omarchy-shell shell toggle nixarchy.pkg '{}'` with
`nixarchy-plugin nixarchy.pkg` in:

- `README.md:157` and `docs/manual/getting-started.md:60` (both unchanged
  by #60);
- `share/omarchy-menu.jsonc:32` (the `system.nixarchy-packages` row).

`nixarchy-plugin` (in `/run/current-system/sw/bin`) toggles the plugin when
it is enabled. Otherwise it sends a notification: "<id> is turned off — Turn
it on in Setup > Plugins, or run: omarchy plugin enable <id>", or "<id> is
not installed on this machine". Checked on p620:
`~/.config/omarchy/plugins/nixarchy.pkg` exists (a Nix store link), so the
installed check passes for a Nix-installed plugin. A sentence after each
snippet says what happens when the plugin is off.

**1b. The manual** (texts as they stand after #60):

| Where | Change |
| --- | --- |
| `from-a-terminal.md` #60 :44-48 | Heading and command become "Every package taken from the other channel:" `nixarchy-pkg state \| jq -r '.packages[] \| select(.channel == "other") \| .attr'` |
| `options.md` :56-59 | "They get the option's own example — or its default — in a text box, with its type and documentation beside it. Edit it and RETURN writes it as a live value; leave it untouched and nothing is written." |
| `troubleshooting.md` #60 :51-57 | "`a` seems to hang": it is probably waiting for a password with no polkit agent, or at a question the panel cannot draw. ESC leaves the log and the build keeps running. SHIFT+A is refused while it runs (it says "an apply is running"), so wait for it to end. Next time on this machine, use SHIFT+A instead of `a` from the start. |
| `applying.md` #60 :46 | "If `a` seems to hang …" becomes "On a machine with no polkit agent, use `SHIFT+A` instead of `a`. Once an apply is running, `SHIFT+A` is refused until it ends." |
| `getting-started.md` #60 :110-114 | Section renamed "If you have no polkit agent", with the same "instead of, not after" wording and the link to Applying. |

### Slice 2 (PR 2): the panel

**2a. Descriptions.** `Card.qml` main :232-233 / #60 :243-244: the text
becomes `modelData.summary || modelData.note || modelData.type || ""`.
`line` and `category` are no longer used as descriptions. `summary` and
`type` are for search and option rows, which are unaffected.

**2b. Category headers and `.settings` rows.** Measured: a QML `ListView`
section works with the panel's plain JS-array model (Qt 6.12 qmltestrunner,
offscreen: a three-row array with two categories drew two section headers).
Sections take no model index, so the cursor, `rowAt`, `count` and every
key keep working unchanged.

- `PkgModel.qml` `rows()` (#60 :120-131): tabs 0 and 1 return
  `catalogueRows(list, file)` instead of `filtered(list)`:

  ```js
  // Each row gains `section`, the header it is drawn under. Rows are
  // grouped by category in first-seen order, file order within a group,
  // because a ListView section is drawn at every change of value: a file
  // whose headers go A, B, A would otherwise show A twice. Settings rows
  // go last: they configure an app and cannot be turned on themselves.
  function catalogueRows(list, file) {
    var f = filtered(list), order = [], groups = {}, conf = []
    f.forEach(function (r) {
      if (r.settings === true) {
        conf.push(Object.assign({}, r, { section: "settings \u2014 edit in " + file }))
        return
      }
      var c = r.category || "other"
      if (!groups[c]) { groups[c] = []; order.push(c) }
      groups[c].push(Object.assign({}, r, { section: c }))
    })
    var out = []
    order.forEach(function (c) { out = out.concat(groups[c]) })
    return out.concat(conf)
  }
  ```

  Tab 0 passes `"apps.nix"`, tab 1 `"services.nix"` (no service row has
  `settings: true` today; measured 0 on p620). A category is the most
  recent `── Name ──` header (`bin/nixarchy-pkg:295`); on p620's selection
  the 9 app categories already form 9 contiguous blocks, so the grouping
  changes nothing there.
- `Card.qml` `ListView` (#60 :116-131): `section.property` is `"section"`
  on tabs 0 and 1 and `""` otherwise. `section.delegate` is one line of
  text in the dim colour, `Style.font.title`, with the header's height
  derived from the font like `rowHeight`. The card's own height is not
  derived from the list (#60 :35-38), so the extra lines only scroll.
- The header text is the category as the file names it. That includes
  "Added by nixarchy-catalogue-diff, 2026-09-17", which is what p620's
  selection carries (measured). It is the truth about the file, so it is
  shown as is.

**2c. Multi-word search.**

- Adapter, `cmd_search`'s awk (main :402-412, #60 :424-434):
  `n = split(lq, w, " ")` (awk's default splitting, which drops leading,
  trailing and repeated blanks). A row is kept only when every word occurs
  in `tolower($2)` or `tolower($3)`. Its rank is the lowest of the existing
  rule applied to each word. The shell already refuses an empty query
  (`[ -n "$query" ]`, main :391); the query is trimmed before that check,
  so a blank one is refused too and `n` is never 0.
- Panel, `PkgModel.filtered()` (#60 :247-254): words are
  `query.trim().toLowerCase().split(/\s+/)`; every word must occur in
  `id + " " + label + " " + category`. `searching` (#60 :115) becomes
  `query.trim().length > 0`, so a blank query filters nothing and starts
  no search.

Measured on p620's index (113,370 package rows, 0.49-0.53 s per search
today): "ssh server" finds 10 rows today, "server ssh" 0,
"openssh server" 0 and "rust formatter" 0. With every-word matching,
"server ssh" finds 21 and "rust formatter" 3. The extra `split` and loop
cost one pass per word over a field already in memory; the search
stays one `awk` pass over the index.

**2d. A reindex never blocks a write.**

- `PkgModel.qml`: a new `property bool reindexing`, a private
  `_reindexAnswered`, and a new `Process _reindexer`.
  - Its answer is absorbed with `_absorb(text, false)`: a reindex changes
    nothing in the selection, so no state read follows. `_absorb`'s
    non-state branch (#60 :386-392) gains
    `if (data.indexStale !== undefined) root.indexStale = data.indexStale`,
    so the footer is set from the reindex's own answer. Calling `refresh()`
    instead would race: `_reader` ignores a start while it is running
    (#60 :334-339, `refresh()` at #60 :472-476), so a write finishing just
    before the reindex would leave the footer stale (#43's failure again).
  - `onStreamFinished` sets `_reindexAnswered = true` when the text is not
    empty. `onExited` clears `reindexing`; when `code !== 0` and
    `!_reindexAnswered` it sets `message = "the index rebuild ended without
    answering (exit N)"`. `_writer`'s `message === ""` guard is not reused:
    the reindex's own "rebuilding…" message would always defeat it.
  - #69 (index age) later moves the `indexStale` take-up to the top of
    `_absorb`; the two changes agree.
- `reindex()` (#60 :768-770) no longer calls `write()`. It refuses only a
  second reindex ("already rebuilding the index"). It sets
  `message = "rebuilding the search index (about 45 s)"`. A write started
  meanwhile clears that message at once (`write()` sets `message = ""`,
  #60 :565); the footer's stale line stays until the reindex answers.
- `write()` (#60 :560-569) drops its `args[0] !== "reindex"` exception,
  which no longer has a caller.
- Writes and applies may run during a reindex. The adapter's `cmd_reindex`
  takes no lock and writes only the cache (main :1454-1466). The one shared
  file it reads is `apps.nix`, in `nixarchy-search`'s picker status, after
  indexing, and that run's picker fails without a terminal anyway.

Measured (#69's spec, p620): a reindex takes 44.5 s and peaks at 5.0 GB.

### Slice 3 (PR 3): `nix flake check` runs `tests/adapter.sh`

- `tests/adapter.sh`: `OFFLINE=${NIXARCHY_PKG_TEST_OFFLINE:-0}`. When it is
  `1`, the two parts that lock a `github:` input print
  `skip: needs the network (flake inputs)` and do not run: the "flake"
  section (#60 :123-251, `fresh_flake` at :137-144) and the
  `FKW`/`FKS` cases (#60 :1126-1146). Everything else runs.
  The catalogue sections already skip without `/etc/nixarchy`.
- `flake.nix` `checks`: a new `adapter` check, a `runCommand` with
  `nativeBuildInputs` of `bash jq nix git util-linux gawk gnused gnugrep
  coreutils diffutils findutils`, `HOME=$TMPDIR`,
  `NIX_STATE_DIR=$TMPDIR/nix-state`, `NIXARCHY_PKG_TEST_OFFLINE=1`, running
  `bash ${./tests/adapter.sh}` with the repo copied in, failing on any
  `FAIL`. Real `nix` is used only for `nix-instantiate --parse`; the
  `nix eval`, `build` and `flake metadata` calls in #60's sections already
  go through stubs (#60 :797-884).

### Not in this task

- No cancel-apply key. No change to `nixarchy-apply`.
- No metadata on selection rows (split issue A), no Menu, OptionForm or
  Panel tests (split issue B).

### Split-out issues (texts for the team lead to file)

**A. "Selection rows: show channel, description and version where they can
be known, and mark insecure packages"**

> Split out of #64 (item 3). A package the user added shows only its
> attribute. The adapter already reads its channel (`extras_tsv` tags
> `#@pkg-other` lines as `other`, `bin/nixarchy-pkg:333`), but the panel
> never shows it. Decided at #64's intent: show the channel always; show
> description or version only when they come from the nixpkgs the package
> does (the search index describes this machine's nixpkgs, so not for an
> other-channel package, and not from a stale index); otherwise nothing
> extra. Marking a package `insecure` needs nixarchy first: its index walk
> (`pkg-index.nix`) emits only attr, version, description, homepage,
> licence, unfree and broken. Needs a companion nixarchy issue: "pkg-index:
> carry meta.insecure / knownVulnerabilities as an index flag".

**B. "Behavioural tests for Menu.qml, OptionForm.qml and Panel.qml"**

> Split out of #64 (item 7). `nix flake check` runs `tst_pkgmodel.qml` and
> `tst_card.qml` (`flake.nix:98-109`). Menu (keys, focus, the log view's
> key handling), OptionForm (touched/untouched commit, verb choice, scaffold
> fallback) and Panel have no behavioural tests. Several past defects
> (#43, #50) were in exactly this kind of behaviour. Scope: one test file
> per component against the existing inert stubs in `tests/qml/imports`,
> run by the `qml-tests` check.

### Companion nixarchy issues

None for this task. Split issue A carries the one it needs.

## Alternatives rejected

- **Header rows in the model (`kind: "head"`, as the Flakes tab does).**
  They take cursor positions, so every key, `rowAt` and `count` would have
  to learn to skip them. `ListView` sections do not.
- **Sorting rows by category.** They are already grouped in file order,
  which is the user's own order.
- **A `when` check on the menu row.** Silent again (see Decisions).
- **Showing `line` but prettier** (for example "enables bitwarden"). It
  says nothing the name does not.
- **Ranking multi-word results by how many words hit the name**, or by
  the first word only. The first adds rules for little gain; the second
  makes word order change the ranking. Best-of-words rank does neither,
  and keeps one-word queries identical.
- **Running every test section in the sandbox** by rewriting the flake
  cases to use local `path:` inputs. Decided against at intent approval.

## Risks

- **`nix-instantiate --parse` in the build sandbox** may want a writable
  state or store directory beyond `NIX_STATE_DIR`. Not verified here (this
  host must not build). Verified first on razer with the owner's OK; if it
  fails, the check also sets `NIX_STORE_DIR`/`NIX_REMOTE` to a local store
  under `$TMPDIR`.
- **Other sections may reach the network** in ways the inventory missed.
  The sandbox will say so on first run: a failure, not a silent pass.
- **The first section header may be scrolled out of view**: with
  `clip: true` and `highlightRangeMode: ListView.ApplyRange`
  (#60 :123-131) the first header can sit above `contentY` when the list
  opens. If razer shows that, `positionViewAtBeginning()` on tab change
  fixes it. Checked by eye on razer; `tst_card.qml` switches tabs 0 → 2 → 0
  and checks the header is back.
- **Footer messages**: a write during a reindex replaces the
  "rebuilding…" message. Acceptable: the stale line shows the index is
  not ready, and the reindex's answer sets it.

## Verification

- Slice 1: `rg "shell toggle nixarchy.pkg"` finds nothing in README, docs or
  `share/`. On razer, with the plugin disabled, the bound key and the menu
  row each show the "turned off" notification; enabled, they open the panel.
  Each changed manual command is run against a scratch selection and does
  what its heading says.
- Slice 2: `tst_pkgmodel.qml` gains: `catalogueRows` puts settings rows last
  with their own section, and keeps order otherwise; multi-word `filtered`
  (all words, any order, one word unchanged); `reindex()` sets
  `reindexing`, not `busy`, and a `write()` during it starts; a second
  `reindex()` is refused; a reindex answer `{ok:true, indexStale:false}`
  clears `indexStale` without a state read; a reindex that exits 1 with no
  output says so although its "rebuilding…" message was showing;
  categories A, B, A come out as A, A, B; a blank query filters nothing. `tst_pkgmodel`'s existing
  `test_reindex_not_refused_while_applying` is updated to `reindexing`.
  `tst_card.qml` gains a check that tab 0 draws section headers and tab 2
  does not. `tests/adapter.sh` gains: "server ssh" on the stub index finds
  a row with both words in either order; one word ranks as before; a word
  that matches nothing returns nothing.
- Slice 3: on razer, `nix flake check` passes with the new `adapter` check,
  and its log shows the network skip line and no catalogue section.
  `bash tests/adapter.sh` without the variable still runs every section.
