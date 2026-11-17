---
status: draft
issue: 105
intent: intent/2026-11-17-105-search-version.md
---

# Spec: search rows show the package version

## Design

Line numbers are this worktree (main at e1acb1b plus the approved intent).
The intent's seven questions were approved with the recommended answer and are
settled: (a) add a `version` key, five-field index gives no key, Selection
untouched, key only when non-empty, version first in the second column, stale
index still shows it, `pkg` rows only.

### 1. `cmd_search` (`bin/nixarchy-pkg`), two edits, nothing else

awk, `:707`, one more printed field:

```
print best, length($2), $1, $2, $3, $4, $5, (FILENAME == idx ? "system" : $6), (FILENAME == idx && $1 == "pkg" ? $6 : "")
```

`cut -f3-` keeps it: nine fields leave awk, seven reach jq (indexes 0-6, the
version is `.[6]`). A five-field index row prints an empty field 9; an `app`, `opt`
or flatpak row prints empty by the `pkg` guard; a `rows.tsv` row prints empty
because `FILENAME != idx`.

jq, after the `preview:` line (`:750`, the object closes at `:751`), one more object term joined to the
existing `+`:

```
} + (if (.[6] // "") != "" then {version: .[6]} else {} end)
  + (if .[0] == "opt" then
```

The awk already guarantees `.[6]` is empty for every non-`pkg` row, so jq does
not repeat the kind test (one guard, one place). Key only when non-empty, like
`summary` on `state` rows.

No change to `Card.qml`: line 388 draws `version + "  " + summary` for any row
with a truthy `version` and no `type`; a search row has `type: ""`. No change
to `labels_tsv`, `cmd_state`, `index_facts`.

Output shapes: index `pkg` row with `$6 = 1.2.3` gives
`{..., "version": "1.2.3"}`; same row with empty or missing `$6` gives no
`version` key; `app`, `opt`, flatpak rows never get one.

### 2. Adapter test (`tests/adapter.sh`)

A new block after the "a blank search is refused" check (`:583`), before the
option block that appends to `STUBCACHE` (`:584`). It uses its own cache dir so
the later fixtures are untouched:

```
VCACHE=$(mktemp -d); mkdir -p "$VCACHE/nixarchy"
printf 'pkg\tvfoo\tFoo\tunfree\tprev\t1.2.3\npkg\tvbar\tBar\t\tprev\t\npkg\tvold\tOld five\t\tprev\napp\tvapp\tApp\t\tprev\tLEAK\nopt\tvopt.enable\tOpt\tboolean\tprev\tLEAK\n' \
  > "$VCACHE/nixarchy/index.tsv"
out=$(XDG_CACHE_HOME="$VCACHE" "$ADAPTER" search -- v)
check "a six-field package row carries its version" \
  jq -e '.rows | map(select(.name == "vfoo"))[0].version == "1.2.3"' <<<"$out"
check "an empty sixth field gives no version key" \
  jq -e '.rows | map(select(.name == "vbar"))[0] | has("version") | not' <<<"$out"
check "a five-field row gives no version key" \
  jq -e '.rows | map(select(.name == "vold"))[0] | has("version") | not' <<<"$out"
check "an app or option index row never gets a version, whatever its sixth field" \
  jq -e '.rows | map(select(.kind != "pkg")) | length == 2 and all(has("version") | not)' <<<"$out"
check "a stale index keeps the version (a stamp that cannot match)" \
  jq -e '.indexStale == true and (.rows | map(select(.name == "vfoo"))[0].version == "1.2.3")' <<<"$out"
rm -rf "$VCACHE"
```

The fixture writes a stamp that cannot match. A missing stamp is not enough:
with no `nixarchy-search` on `PATH` (the flake sandbox) it compares equal to
the empty key and the index reads fresh (`index_facts`). Corrected after the
plan review; the plan carries the fixture.
One more assertion in the options block, after `:2562`, on the existing
`opt62 search git --kind opt` output `$out`: a `rows.tsv` option row (its `$6`
is `system`) has no `version`:

```
check "an option row from the cache never carries a version" \
  jq -e '.rows | all(has("version") | not)' <<<"$out"
```

The existing five-field fixtures (`:561`, `:599`, `:650-659`, `:1905`, `:2541`,
`:2745`, `:2749`) pass unchanged and are the "older builder" case.

### 3. Card test (`tests/qml/tst_card.qml`)

A fixture shaped like `cmd_search` output (`kind`, `name`, `type: ""`, `scope`,
`preview`, `version`) beside `selRows` (not appended to it, so the positional
tests on `selRows` and the all-rows width test are untouched), and one test:

```
property var versionedSearch: [
  { kind: "pkg", name: "ripgrep", summary: "Utility that combines usability", type: "",
    flags: ["unfree"], scope: "system", version: "15.2.0",
    preview: "ripgrep  15.2.0\nctrl-t tries it now\nversion:  15.2.0" }
]

function test_search_row_shows_its_version() {
  failOnWarning(/Binding loop detected/)
  useRows(versionedSearch, 2)
  var pane = byName(card, "preview")
  var lv = find(card, "QQuickListView")
  for (var width of [800, 700]) {
    win.width = width
    tryCompare(pane, "visible", width >= 760); wait(150)
    var delegate = lv.itemAtIndex(0)
    var row = find(delegate, "QQuickRow")
    var ts = elidables(delegate, [])
    var summary = ts[ts.length - 1]
    compare(summary.text, "15.2.0  Utility that combines usability")
    verify(summary.x + summary.width - row.width <= 0.5, "row fits at " + width + " px")
  }
}
```

The `wait(150)` is needed: without it the first pass at 800 read a stale
layout and failed the fit check (summary right edge 26 px past the row); the
existing width test waits for the same reason. The test therefore covers the
case the old fit test (`:822`) cannot, the 800 px list narrowed by the pane.

### 4. Manual (`docs/manual/from-a-terminal.md`)

After the `packages` paragraph (`:222-226`), one paragraph:

```
A `search` row for a package may also carry `version`, from the index. It is
omitted when the index has none (an index written by an older `nixarchy-search`,
an unknown version) and on every `opt` and `app` row. It is not part of the
relied-on shape.
```

### Which tests must fail on main

Measured in `mktemp` copies (main's `bin/nixarchy-pkg` against the new
fixture; `qmltestrunner` 6.12.0 from `nixpkgs#qt6.qtdeclarative`, offscreen):

| Test | main | with the change |
|---|---|---|
| adapter: six-field row carries version, stale index keeps it | **fails** (`version` is null) | passes |
| adapter: empty, five-field, app/opt rows have no key; cache option row has none | passes (guards, must keep passing) | passes |
| Card `test_search_row_shows_its_version` | **passes** (no QML change) | passes, 49 tests |

The Card test is a regression guard, not a red test: `Card.qml:388` already
draws the version, which is the intent's claim. Mutation proof (`mktemp`
copy only): replace `(modelData.version ? modelData.version + "  " : "")` with
`""`; the new test fails ("Expected 15.2.0  Utility ...") together with
`test_version_leads_the_second_column`. For the adapter, change the awk guard
`$1 == "pkg"` to `1` and the "app or option row never gets a version" check
must fail (the `app` fixture row has `LEAK` in `$6`); drop the jq `!= ""` test
and the empty-sixth-field check must fail.

## Alternatives rejected

- **(b) Replace the preview scrape with `$6`.** Drops versions on a fresh
  five-field index; moves fixtures for no visible gain (intent Q1).
- **Fall back to scraping `$5` in `cmd_search`.** A second source of one fact
  in one command (intent Q2).
- **Always emit `version: ""`.** Not "may carry"; no visible gain (Q4).
- **A width term or new item for the version.** The summary Text already owns
  the width; it elides as before (Q5).
- **A `kind` test in jq as well as awk.** Same guard twice.

## Risks

- **Two sources of the version** (Selection scrapes `$5`, search reads `$6`)
  until five-field indexes cannot occur. Accepted (intent Q3).
- **Long version eats the summary.** A date or hash version elides inside the
  summary; no readability promise (Q5).
- **Stale index shows an old version.** Same as the row's summary and flags;
  the footer already says the index is old (Q6).
- **Not verified on a real index or in the panel.** Fixtures are hand-written;
  the live check below has not run.

## Verification

1. `tests/adapter.sh`: the new checks pass; on main's `bin/nixarchy-pkg`
   exactly the two "carries its version" checks fail.
2. `qmltestrunner` on `tst_card.qml` (the flake's `qml-tests`): 49 tests pass;
   mutation proof above fails as stated.
3. `nix flake check`: `shellcheck` on `bin/nixarchy-pkg` and `qmllint` unchanged.
4. Live, in a `nixarchy-desktop` microVM (not razer), guest `nixarchy-search`
   at or after nixarchy #1818, then `nixarchy-pkg reindex`:
   `nixarchy-pkg search ripgrep | jq '.rows[0].version'` is a string; the
   panel's package search row shows it before the summary at 800 px (pane
   visible) and 700 px; an `app` row and an `opt` row show none. Screenshot
   from the guest.

## Decisions for the owner

1. **Adapter fixture is a new six-field block, not edits to the old
   five-field ones.** The old fixtures stay as the "older builder" case.
   Recommended: yes.
2. **The Card fixture is a separate property, not appended to `selRows`.**
   `selRows` is Selection-shaped (`attr`, `channel`, no `kind`/`name`/`scope`)
   and tested by position; a `cmd_search`-shaped row beside it keeps both
   honest. Recommended: separate property.
3. **The Card test passes on main.** It guards the contract that the intent
   proved (no QML change), and cannot be a red test. Recommended: keep it as a
   guard; the red tests are the adapter ones.
4. **The live check has not run.** Recommended: run it after the plan is
   approved; nothing in the design depends on it.
