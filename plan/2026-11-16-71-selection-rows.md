---
status: approved
issue: 71
spec: spec/2026-11-16-71-selection-rows.md
coders:
  1: codex   # adapter.sh fixture block: exact jq assertions over a hand-built index, stamp and stub; small and tricky
  2: codex   # one awk clause, a shell-side attr list and a jq rewrite under set -euo pipefail: small tricky logic
  3: codex   # three short manual edits; the wording must match the adapter's rule exactly
  4: codex   # card tests that measure fit and read tag colours through the existing helpers
  5: codex   # four small QML edits in one file; the width sum must not change
reviewers:
  - codex   # pipefail, awk and jq transport are where this goes wrong
  - agy     # independent read of the diff against this plan
---

# Plan: selection rows say what the package is, where that can be known

Owner direction: Codex implements every step that edits files. Codex runs
through `agent-run codex`, which needs a clean worktree, so the lead commits
after each step and Codex never stages or commits. The lead does step 6.

## Decisions (copied from the approved spec; do not open the intent or spec)

Rule, fixed: the channel is on every row. The description and the version
come only from the package's own nixpkgs, so never for an `other` row and
never from a stale index. This is enforced by what the adapter does not look
up, so the panel cannot draw a borrowed fact.

1. **The lookup lives in `cmd_state`**, in one awk pass over the index fused
   with the pass `labels_tsv` already makes for the Apps and Services labels.
   No per-row `search`, no async path in `PkgModel`. Measured 0.12 s to 0.19 s
   for `state`.
2. **The facts ride on the existing `packages` rows** under names `Card.qml`
   already draws: `summary` (the description), `version`, `flags`. A key is
   present only when known. `attr` and `channel` are untouched. Only
   `version` is new to the card.
3. **`flags` from the index are included for a default row.** The summary
   loses its `[unfree]` / `[broken]` suffix when the flag is there, by the
   same rule `cmd_search` uses, so the warning is said once. (If the owner
   drops `flags`, drop it from the awk, the jq and the manual; nothing else
   depends on it.)
4. **The channel is a tag on every row, drawn by the flags box.** `default`
   dim (`root.dim`), `other` in `Commons.Color.accent`, the colour unfree
   uses. The words are the JSON's own, `default` and `other`. No `channel`
   key or `badge` key drawn separately from `flags`; no real channel name.
5. **The version is the front of the second column**: `15.2.0  Utility that
   ...`, two spaces, dim like the summary. Not its own column.
6. **An empty fact is an absent key.** An empty summary, a summary that is
   only the stripped tags, an empty version and the builder's `?` version are
   dropped, not sent as `""` or `"?"`. A package the index lacks gets
   neither key, nor `flags`.
7. **Narrow cards: accepted, not fixed.** A row with three index flags and a
   tag overflows a card narrower than about 620 px (main: 540 px). The width
   sum in `Card.qml` is NOT changed. Tests assert fit at 800 and 700 px.
8. **The version is read from the `version:` line** in the preview text
   (column 5 of an index `pkg` row). The index gets no new column.
9. **No `insecure` field, key or test is added.** That is the follow-up
   after nixarchy carries the flag.
10. **Not changed:** `PkgModel.qml`, any writer, the Selection tab's scope
    line, the preview pane (a selection row has no `preview`), the
    stale-index notice (it stays the one place that says why a row is bare),
    `cmd_search`'s output.
11. **Transport:** `extras` stays `--rawfile` in `cmd_state`. Never capture
    it into a variable and pass it with `--arg`: argv has a size limit
    (about 2,200 option rows exceed it) and an unreadable `apps.nix` would
    end the script under `set -e` with no JSON.
12. **Live check** in a `nixarchy-desktop` microVM, not razer (owner's
    standing choice).
13. **One PR**, with commits in step order (tests before the change they
    test). Companion issues are filed by the lead (below).

## Repo traps (apply to every step that touches them)

- **One JSON answer on every path.** `state` always prints one object and
  exits 0; failure is a value (`ok:false`), never an exit code or silence.
- **`set -euo pipefail` (`bin/nixarchy-pkg:46`).** A failing pipeline stage or
  an empty `grep` match ends the script. Guard with `|| x=""` / `|| :`.
  Process substitutions swallow their status (see the comment at the top of
  `cmd_state`).
- **SIGPIPE.** No `diff`, `cmp` or `comm` at the head of a pipeline and no
  `| head` in the adapter (an early-exiting reader SIGPIPEs the writer; under
  pipefail that is a failure). Count with `grep -c` or read whole input.
  (`searched()` and `cmd_search` already contain legacy `head`; do not add
  more, and do not touch those.)
- **`9>&- 8>&-` on children** that are started while the adapter holds the
  lock fds. `cmd_state` takes no lock and starts only reads; this step adds no
  new long-lived child, so no redirection is needed, but do not background
  anything.
- **Nothing written to `/tmp` outside `mktemp`.** Tests use `mktemp -d`
  directories and remove them. Never write the user's real `XDG_*` dirs: every
  new adapter case sets its own `XDG_CONFIG_HOME` and `XDG_CACHE_HOME`.
- **QML stub order.** In tests, `deliver()` answers; `finish()` is a death.
  Never call `finish()` first. `Process` stubs are used only if a test goes
  through `PkgModel`; this plan's Card tests use the fake model.
- **QML tests run from a flake-style copy.** `-input` inside `tests/qml` fails
  with "Card is not a type". Use the command in Tests below.
- **shellcheck is a gate** on `bin/nixarchy-pkg` and `tests/adapter.sh`
  (`flake.nix:75`). Quote everything; a `# shellcheck disable=SC2016` needs a
  reason on the line.

## Steps

### 0. Lead: confirm the base

The branch is rebased on main (5a8ca0b). Re-find every anchor below by its
quoted text; line numbers are only a hint and drift.

### 1. Adapter tests (`tests/adapter.sh`) -- codex

Anchor: the end of the existing "search" section, after the line
`check "search words match in either order"` block, i.e. before the next
`echo "` section header. Add a new section `echo "state: what the selection says"`
(find the true end of the "search" block; if the file's order makes another
place cleaner, keep the new block self-contained and before the final
`echo` / `rm -rf "$XDG_STATE_HOME" ...` cleanup lines).

Build the fixture in a block of its own, all under `S=$(mktemp -d)`, and
remove `$S` at the end of the block:

- `$S/config/nixarchy/apps.nix` with `#@pkg`, `#@pkg-other` and `#@opt`
  marker lines (copy the marker shape from `extras_tsv`: `#@pkg <attr>` and
  `#@pkg-other <attr>`, one per line, inside `{ ... }:\n{\n ... \n}`).
- `$S/cache/nixarchy/index.tsv`, tab-separated, `pkg<TAB>attr<TAB>summary<TAB>flags<TAB>preview`
  where the preview has literal backslash-n (the index stores newlines
  escaped): `title\nversion:  1.2.3\nhomepage: x\nlicense: MIT\n\ndesc`.
  Printf the backslashes with `\\n`. Rows:
  `ripgrep` (version `15.2.0`, summary `Utility that combines usability`, no
  flags), `foo` (summary `Foo thing  [unfree]`, flags `unfree`), `novers`
  (preview with `version:  ` and nothing after), `nolineversion` (preview
  without a `version:` line), `qmark` (preview with `version:  ?`), `nosummary`
  (empty summary, flags `unfree broken`, summary field `  [unfree]  [broken]`
  as the builder writes it), `vlc` (a package that `other` also names, with
  a version and summary), `nerd-fonts.blex-mono` and `nerd-fonts.blex`
  (dotted attr; the apps file selects only the first), `ripgrep-all`
  (near name; selected apps file has `ripgrep` only).
- A stub `nixarchy-search` on `PATH` (in `$S/bin`, `chmod +x`) holding the
  seven `name=value` lines `searched` reads, one per variable: `nixpkgs`,
  `walk`, `optionsjson`, `appindex`, `apptable`, `flatpakrows`, `pkgnewrow`,
  e.g. `nixpkgs=/n/a`. The fresh stamp is those seven values joined by
  newlines, written to `$S/cache/nixarchy/stamp` with the same
  `printf '%s\n'` shape `index_stale` uses; a stale case writes a different
  stamp. Check that `index_stale` is false for the fresh one before relying on
  it (`state.indexStale == false`).
- Run `state` as
  `XDG_CONFIG_HOME="$S/config" XDG_CACHE_HOME="$S/cache" PATH="$S/bin:$PATH" "$ADAPTER" state`.

The apps file has a default row for each package above, an `other` row for
`vlc`, a default row for `vlc` in a second apps file for the dual-selection
case, and a default row `nosuchpkg` the index lacks.

**Must fail on main** (each key is absent there). Name each check by its
claim:
- the fresh default `ripgrep` row has `summary == "Utility that combines
  usability"`, `version == "15.2.0"` and `flags == []`;
- `foo` has `summary == "Foo thing"` (no `[unfree]`) and `flags == ["unfree"]`;
- `nosummary` has `flags == ["unfree","broken"]` and no `summary` key;
- the `summary` of `foo` equals the `.rows[0].summary` that `search` gives
  for it (`XDG_CACHE_HOME="$S/cache" "$ADAPTER" search -- foo`);
- (also must fail on main, because main never enriches) the default `vlc`
  row of the dual selection has `version`, and `nerd-fonts.blex-mono` has its
  `version` and `summary`;
- absence cases, each asserting a positive fact in the same row so it fails
  on main for that reason: `novers` has `flags == []` and no `version` key;
  `nolineversion` the same; `qmark` the same, no `"?"`.

**Pass on main, kept as guards:**
- the `other` row for `vlc` is exactly `{attr, channel}` (jq `keys ==
  ["attr","channel"]`) though the index has the package;
- a stale stamp: every row has exactly `attr` and `channel`, `indexStale` is
  true;
- `nosuchpkg` has exactly `attr` and `channel`;
- an unreadable `apps.nix` (`chmod 000`; skip with a message if running as
  root): `ok == true`, the message names it, exit status 0;
- a selection with 2,200 `#@opt` rows still answers (`ok == true`, `.options
  | length == 2200`);
- the same attr as default and as other (`#@pkg vlc` and `#@pkg-other vlc`
  in one file): the other row is exactly `attr` and `channel`;
- `nerd-fonts.blex` is not a row when only `nerd-fonts.blex-mono` is
  selected, and `ripgrep-all` is not enriched when only `ripgrep` is;
- no index file at all: `ok == true`, rows are exactly `attr` and `channel`;
- `attr` and `channel` unchanged for every row, `packages` order is the file
  order, and the Apps and Services `label` still come from the index (add one
  `app` row to the index fixture and an app marker to the apps file).

Traps: fixtures only under `mktemp -d`; the real `$HOME`, `XDG_*` untouched;
no `diff`/`cmp`/`comm` at a pipeline head and no `| head`; use
`jq -e ... <<<"$out"` as the existing checks do; keep `shellcheck` clean
(`$other`-style jq variables need `# shellcheck disable=SC2016  # <reason>`).

→ **Verify:** `bash tests/adapter.sh` on this branch (no fix yet) fails
exactly the "must fail on main" checks and passes every guard and every older
check. Report each by name. Also
`ADAPTER_OVERRIDE=<(git show main:bin/nixarchy-pkg)` is NOT used; instead copy
main's adapter to a file under `mktemp -d` and point `ADAPTER_OVERRIDE` at it
to record the same failures. `shellcheck tests/adapter.sh`.

**Lead after step 1:** review, run, commit (`test(adapter): ...`).

### 2. The adapter (`bin/nixarchy-pkg`) -- codex

Three edits. All under `set -euo pipefail`.

**2a. One shared summary clean-up.** Anchor: in `cmd_search`'s jq, the lines
`summary: ((.[2] // "")` through
`| if ($f | index("broken")) then gsub(" \\[broken\\]"; "") else . end),`.
Define once near the top of the file, with the other constants (after the
`readonly STAMP=` line), a shell variable holding the jq function:

```bash
# One rule for "drop the tag the flag already says", used by search and state.
# shellcheck disable=SC2016  # $f is a jq parameter, not a shell expansion.
readonly UNTAG_JQ='def untag($f):
  (if ($f | index("unfree")) then gsub(" *\\[unfree\\]"; "") else . end)
  | (if ($f | index("broken")) then gsub(" *\\[broken\\]"; "") else . end)
  | gsub("^ +| +$"; "");'
```

Use it in `cmd_search` as `"$UNTAG_JQ"'...'` (prepend to the jq program) and
`summary: ((.[2] // "") | untag($f)),`. The existing "index without the flag
keeps its only warning" behaviour (no flag, no strip) must be unchanged.
`cmd_search` output must be byte-identical for the existing fixtures except
for the two-space eaten/trim (the builder's `"  [unfree]"`).

**2b. `labels_tsv` takes the attr list.** Anchor: the function
`labels_tsv() {` and its body `awk -F'\t' '$1 == "app" { print $2 "\t" $3 }' "$INDEX"`.
Replace with one pass writing a kind in column 1:

```bash
labels_tsv() {
  [ -s "$INDEX" ] || return 0
  awk -F'\t' -v want="${1-}" '
    BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) w[a[i]] = 1 }
    $1 == "app" { print "app\t" $2 "\t" $3; next }
    n && $1 == "pkg" && ($2 in w) {
      v = ""; i = index($5, "\\nversion:  ")
      if (i) { v = substr($5, i + 12); j = index(v, "\\n"); if (j) v = substr(v, 1, j - 1) }
      print "pkg\t" $2 "\t" $3 "\t" $4 "\t" v
    }
  ' "$INDEX"
}
```

(`"\\nversion:  "` in awk is backslash, `n`, `version:`, two spaces: 12
characters, hence `i + 12`. The first occurrence is the header's.) Update the
comment above it to say the stream has a kind column. Do not decode the
fields (no backslash-unescaping): the summary is copied as `cmd_search`
copies it.

**2c. `cmd_state`.** Anchors: the line `--rawfile labels <(labels_tsv) \`, the
`($labels | cols | map({key: .[0], value: .[1]}) | from_entries) as $label |`
line, and the `packages: ($extras | cols | map(select(.[0] == "pkg") | {`
block.

1. Before the `jq -n` call add:

   ```bash
   local want=""
   if ! $stale; then
     want=$(extras_tsv | awk -F'\t' '$1 == "pkg" && $3 == "default" { printf "%s ", $2 }') || want=""
   fi
   ```

   (`$stale` is the existing local; an unreadable or missing selection file
   gives an empty list and the answer stays partial, never fatal.)
2. `--rawfile labels <(labels_tsv "$want") \`. Keep `--rawfile extras
   <(extras_tsv)` exactly as it is.
3. Prepend `"$UNTAG_JQ"` to the program (it is `'...'` today; write
   `"$UNTAG_JQ"'...'`) and replace the `$label` line with:

   ```jq
   ($labels | cols) as $lab |
   ($lab | map(select(.[0] == "app") | {key: .[1], value: .[2]}) | from_entries) as $label |
   ($lab | map(select(.[0] == "pkg")
       | ((.[3] // "") | split(" ") | map(select(length > 0))) as $f
       | { key: .[1], value: {
             summary: ((.[2] // "") | untag($f)),
             flags: $f,
             version: (if (.[4] // "") == "?" then "" else (.[4] // "") end) } })
     | from_entries) as $fact |
   ```

4. `packages` becomes:

   ```jq
   packages: ($extras | cols | map(select(.[0] == "pkg") | {
     attr: .[1], channel: (.[2] // "default")
   } + (if .[2] == "default" and $fact[.[1]]
        then $fact[.[1]] | with_entries(select(.value != "")) else {} end))),
   ```

   `select(.value != "")` keeps `flags: []` (an array is not `""`).

Do not change the `apps` or `services` mapping, `rows_tsv`, `index_stale`,
`extras_tsv` or any writer.

→ **Verify:** `bash tests/adapter.sh` passes in full (every step 1 check now
passes); `shellcheck bin/nixarchy-pkg tests/adapter.sh`; and
`state` on this machine's real index (scratch `XDG_STATE_HOME`, never write
the real selection) still prints one object with `ok: true`. Time `state`
before and after on the scratch dirs and report both (spec: about 0.12 s and
0.19 s).

Traps: no `| head`; `labels_tsv` may be called with no argument (`${1-}`);
the stream's new first column must not break the Apps/Services labels (the
step 1 guard covers it); an unreadable index inside `<(labels_tsv ...)`
yields an empty stream, not a failure.

**Lead after step 2:** review, run, commit (`feat(adapter): selection rows carry
summary, version and flags from a fresh index (#71)`).

### 3. The manual (`docs/manual/from-a-terminal.md`) -- codex

Two edits, no other change:

1. Anchor: the `Relied on:` paragraph under `## What is stable and what is
   not` (the one beginning `**Relied on:** \`ok\` on every object`). After
   it, add a sentence: a `packages` row carries `attr` and `channel`; on a
   `default` package whose own index is fresh it may also carry `summary`,
   `version` and `flags`; they are left out, never empty, when the index is
   stale or missing or does not have the package, and for every `other`
   package; optional fields are not part of the relied-on shape.
2. Anchor: the table row `| \`state\` | Everything the panel draws: apps,
   services, packages, options, drafts |`. Leave it. (Spec's `:23` area is
   this row; no change needed beyond edit 1.) Do not add anything to the
   "Every package taken from the other channel" example.

→ **Verify:** read it. Nothing checks the manual (spec), so the lead reads
the diff against the adapter rule.

**Lead after step 3:** commit (`docs(manual): ...`).

### 4. Card tests (`tests/qml/tst_card.qml`) -- codex

Anchors: the `property var theRows:` block and `function checkSummaries()`;
tests go at the bottom of the existing `TestCase`, after the last test.
Do not change any existing test. The Window and the fake model stay.

Add a separate row set (do not mutate `theRows`; the existing tests count 3
rows):

```qml
property var selRows: [
  { attr: "ripgrep", channel: "default", summary: "Utility that combines usability",
    version: "15.2.0", flags: [] },
  { attr: "vlc", channel: "other" },
  { attr: "steam", channel: "default", summary: "A very long summary " ... , version: "1.0",
    flags: ["unfree", "broken", "curated:steam"] },
  { attr: "nosuchpkg", channel: "default" },
  { attr: "searchrow", flags: ["unfree"], summary: "no channel on a search row" }
]
```

Add a helper `useRows(rows, tab)` that sets `theRows = rows`,
`fakeModel.count = rows.length`, `fakeModel.tab = tab` and waits for the
list's `count`. `init()` must restore `theRows`, `fakeModel.count = 3` and
`tab = 0` (add those lines to `init()`). Tag lookup: the tags are the
`Rectangle` children of the delegate's flags `Row` whose `Text` child holds
the tag; write `tagsIn(delegate)` that walks the delegate for `Text`s whose
parent has a `tone` property and returns `{text, color: parent.tone}`.

**Must fail on main:**
- `test_selection_rows_draw_a_channel_tag`: on tab 2 a `default` row draws a
  `default` tag and an `other` row an `other` tag; a row with
  `["unfree","broken","curated:steam"]` and a channel draws four tags with
  the channel last;
- `test_version_leads_the_second_column`: `textOf` of the second column for
  `ripgrep` is `"15.2.0  Utility that combines usability"`; for a row with a
  version and no summary it is the version and two spaces; for `vlc` and
  `nosuchpkg` it is `""`;
- `test_channel_tag_tones`: the `other` tag colour equals
  `Commons.Color.accent`, `default` equals `card.dim`, `broken` stays
  `Commons.Color.urgent`, `unfree` stays accent (compare with `Qt.colorEqual`).

**Pass on main, kept as guards:**
- `test_selection_summary_fits_at_800_and_700`: at `win.width` 800 and 700,
  every `selRows` delegate's last elidable text satisfies
  `summary.x + summary.width - row.width <= 0.5` and `summary.width >= 0`
  (the #45/#51 property, measured; copy the shape of
  `test_summary_fits_its_row_at_every_flag_count`). Rows: channel tag alone,
  all tags with a version and a long summary, and no facts at all. Set
  `failOnWarning(/Binding loop detected/)` first.
- `test_search_row_on_selection_has_no_channel_tag`: the `searchrow` draws
  `unfree` and no `default` or `other`; Apps rows (tab 0, the original
  `theRows`) draw no channel tag and the same flags they did.
- `test_bare_row_is_quiet`: a bare row's second column is empty and no
  warning is logged (use `failOnWarning(/.?/)`: on Qt 6.12 `failOnWarning()` with no argument registers an empty string and enforces nothing).

Traps: use the Window (never remove it); hidden cards do not take the pointer
(this plan adds no second Card); `wait(150)` before measuring, as the existing
tests do; do not suppress warnings.

Run from a flake-style copy (see Tests).

→ **Verify:** on this branch before step 5, the three "must fail" tests fail
and the three guards and every older test pass. Report each by name.

**Lead after step 4:** review, run, commit (`test(card): selection rows ...`).

### 5. The card (`Card.qml`) -- codex

Five edits, in this file only. **Do not touch the width expression**
(`width: Math.max(0, parent.width - name.width ...` and its
`(flags.visible ? 3 : 2)` term).

1. After `function rowColor(row) {` ... its closing `}`, add:

   ```qml
   // The tags a row draws: its own flags, then its channel when it has one.
   // Only Selection rows carry a channel, so no other tab's rows change (#71).
   function tagsOf(row) {
     return (row.flags || []).concat(row.channel ? [row.channel] : [])
   }
   ```

2. Anchor `visible: (modelData.flags || []).length > 0` becomes
   `visible: root.tagsOf(modelData).length > 0`.
3. Anchor `model: modelData.flags || []` (the Repeater in that Row) becomes
   `model: root.tagsOf(modelData)`.
4. Anchor the `tone` property
   (`readonly property color tone: modelData === "broken" ? Commons.Color.urgent`
   ...): change `modelData === "unfree" ? Commons.Color.accent` to
   `(modelData === "unfree" || modelData === "other") ? Commons.Color.accent`.
   Every other tag, `default` included, stays `root.dim`.
5. Anchor `text: modelData.summary || modelData.note || modelData.type || ""`
   becomes

   ```qml
   text: (modelData.version ? modelData.version + "  " : "")
         + (modelData.summary || modelData.note || modelData.type || "")
   ```

   Keep it a single `text:` binding; `textFormat: Text.PlainText` stays.

→ **Verify:** step 4's commands: all Card tests pass (the three that failed
now pass), no QWARN; then `nix flake check` passes (shellcheck, QML tests,
the adapter suite where CI runs it).

Traps: `modelData` in the flags Row is the ROW, not a flag (see the existing
comment above the Row); the delegate's own `modelData` is the tag one level
in. Do not move the `visible` binding inside. The highlight line
(`index === list.currentIndex`) stays.

**Lead after step 5:** review, run, commit (`feat(card): selection rows draw
their channel and version (#71)`).

### 6. Lead: verify, live, review, PR

- Mutation: revert step 5 alone and confirm the step 4 must-fail tests fail;
  revert step 2 alone and confirm the step 1 must-fail checks fail.
- Run the step 1 checks against `git show main:bin/nixarchy-pkg` (copied to a
  `mktemp` file as `ADAPTER_OVERRIDE`) and record the failures in the PR.
- `nix flake check`.
- Time `state` before and after in scratch dirs; put both numbers in the PR.
- Live, in a `nixarchy-desktop` microVM (owner's standing choice), not razer:
  1. Add `ripgrep` (default) and one package from the other channel with
     `SHIFT+RETURN`. Before the index is built, both rows show a tag and
     nothing else, and the "index stale" notice says why.
  2. Reindex (about a minute in a microVM). The default row now shows its
     version and description, the other row is unchanged, and a package the
     index does not have is still bare.
  3. Selection tab at a normal card width: tag, version and description do
     not overlap the name or run off the row.
- Reviews: Codex and agy, read-only, on `git diff main` against this plan; a
  fresh Opus review with the plan path and the diff.
- File the companion issues (below), then the PR linking intent, spec and
  plan; it says all five file-editing steps were done by Codex.

## Tests

Adapter suite (host tools only, no catalogue needed for the new block):

```bash
bash tests/adapter.sh          # expect: all passed (exit 0)
shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh   # expect: no output
```

Against main, the step 1 "must fail" checks fail:

```bash
m=$(mktemp -d) && git show main:bin/nixarchy-pkg > "$m/nixarchy-pkg" && chmod +x "$m/nixarchy-pkg"
ADAPTER_OVERRIDE="$m/nixarchy-pkg" bash tests/adapter.sh   # expect: FAIL on the named checks only
rm -rf "$m"
```

QML (from a flake-style copy, because `-input` in `tests/qml` fails with
"Card is not a type"):

```bash
QT=$(nix eval --raw nixpkgs#qt6.qtdeclarative.outPath)
d=$(mktemp -d) && cp *.qml tests/qml/tst_*.qml "$d" && cp -r tests/qml/imports "$d"
rc=0
( cd "$d" && for t in tst_card tst_pkgmodel; do
    QT_QPA_PLATFORM=offscreen HOME=$PWD "$QT/bin/qmltestrunner" -input $t.qml -import imports -import "$QT/lib/qt-6/qml" || exit 1; done ) || rc=1
rm -rf "$d"; echo "rc=$rc"   # expect rc=0
```

Expected: every test passes, `tst_pkgmodel` unchanged, no QWARN. On the
branch before step 5, only the three step 4 "must fail" tests fail.

Whole check: `nix flake check` passes.

Manual: read by eye (nothing checks it).

Live: the three microVM steps in step 6.

## Rollback

Revert the PR. The adapter change adds optional keys and a wider `labels_tsv`
stream that only `cmd_state` reads; the card change ignores absent keys.
No file format, writer or selection file changes. An older card on a newer
adapter, and the reverse, both degrade to today's rows.

## Companion issues (for the lead to file)

**nixarchy: "pkg-index: carry meta.insecure / knownVulnerabilities as an index flag"**

> The nixarchy-pkg panel marks `broken` and `unfree` from the index's flags
> column, but nothing marks an insecure package, because `pkg-index.nix` emits
> only attr, version, description, homepage, licence, unfree and broken.
>
> Please add `insecure` to the walk (`meta.insecure` or a non-empty
> `meta.knownVulnerabilities`) and write it into the flags column of the `pkg`
> rows, beside `unfree` and `broken`, so a search row and a selection row can
> both warn on it.
>
> Also consider a `version` column. Today the version exists only as a
> `version:` line inside the preview text, and nixarchy-pkg reads it from
> there (nixarchy-pkg #71). A column would make that parse unnecessary; nothing
> there waits for it.
>
> Adding the flag changes what the index is built from, so `index_stale` will
> call old indexes stale, which is correct.
>
> Needed by: nixarchy-pkg "Selection rows: mark an insecure package".

**nixarchy-pkg: "Selection rows: mark an insecure package"** (blocked on the
nixarchy issue above)

> Selection rows (#71) show a default package's channel, version, description
> and the index's own flags. They cannot mark an insecure package yet because
> the index does not carry the flag.
>
> When nixarchy adds `insecure` to the flags column, a default row's `flags`
> carries it with no adapter change. The work here is `Card.qml`'s tone for it
> (one line in the tag's `tone` expression, probably `Commons.Color.urgent`
> like `broken`, or accent like `unfree`: decide at that time), plus one test
> in `tests/qml/tst_card.qml` and a line in the manual.
>
> Blocked on: the nixarchy "pkg-index: carry meta.insecure ..." issue. Opened
> so the follow-up is tracked rather than remembered. Out of scope for #71:
> no `insecure` field, key or test is added there.
