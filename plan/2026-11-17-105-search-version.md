---
status: approved
issue: 105
spec: spec/2026-11-17-105-search-version.md
coders:
  1: codex   # one Codex run does steps 1-4 in order (agent-run codex refuses a dirty tree and may not commit)
  2: codex   # bin/nixarchy-pkg: one awk field, one jq term
  3: codex   # docs/manual/from-a-terminal.md: one paragraph
  4: codex   # tests: the adapter block plus one assertion, and the Card test (written first, step 1)
  # Steps 0 and 5-10 stay with the coordinator: baseline, proofs, commits, reviews, the live check, the PR.
reviewers:
  - codex   # reads the diff against this plan, looking for tests that cannot fail
  - agy     # independent read of the diff against this plan
---

# Plan: search rows show the package version

Branch `feat/105-search-version`. Line numbers are this worktree (main at
e1acb1b plus the intent and spec); **find every anchor by its quoted text**,
the numbers drift.

## Decisions (from the approved intent and spec; nothing here is open)

1. **Add a `version` key to `cmd_search` rows, read from the index's sixth
   field** (option (a)). No replacement of the preview scrape, no fallback that
   scrapes the fifth field, no second source in this command.
2. **Key only when non-empty.** A five-field index row, an empty sixth field,
   and every `app`, `opt` and flatpak row carry no `version` key (never
   `version: ""`). A `rows.tsv` option row has none either.
3. **One guard, in awk.** awk prints `$6` as a ninth field only for an index
   `pkg` row (`FILENAME == idx && $1 == "pkg"`); jq tests only `(.[6] // "") != ""`
   and does not repeat the kind test.
4. **`Selection` is untouched.** It keeps scraping the preview. Two sources of
   the version until five-field indexes cannot occur: accepted.
5. **A stale index still shows the version**, like the row's summary and flags;
   the footer already says the index is old.
6. **No change to `Card.qml`** (line 388 already draws `version + "  " +
   summary` for a truthy `version` and no `type`; a search row has `type: ""`),
   **nor `PkgModel.qml`, `labels_tsv`, `cmd_state`, `index_facts`.** No width
   term, no new item: the summary Text owns the width and elides as before. No
   version change (`manifest.json` stays).
7. **The Card test is a regression guard, not a red test** (it passes on main).
   The red tests are the two adapter checks that read the version.
8. **Card fixture is a separate property** `versionedSearch`, not appended to
   `selRows` (`selRows` is Selection-shaped and tested by position).
9. **Adapter fixture is a new six-field block with its own cache dir**; the
   old five-field fixtures stay untouched as the "older builder" case.
10. **Roles.** Codex implements steps 1-4 in one run on a clean tree; the
    coordinator does everything that stages, commits, runs proofs, builds or
    reviews. **One PR**, two commits: tests, then the fix (`bin/nixarchy-pkg`,
    manual).
11. **Live check** in a `nixarchy-desktop` microVM, not razer; the guest's
    `nixarchy-search` must carry nixarchy #1818. It has not run yet.

## Order and why (test-first)

Tests first (steps 1-2), code after (steps 3-4), all in one Codex run. The
coordinator then proves in `mktemp` copies that the new adapter checks fail
against main's `bin/nixarchy-pkg` (step 5) and commits tests and fix
separately (step 6). Exactly two adapter checks fail on main (the two that read
the version); the rest, and the Card test, pass on main and after.

## Steps

### 0. Coordinator: baseline

`git status` clean on the branch. Record `bash tests/adapter.sh </dev/null |
tail -3` (ends `all passed`), `shellcheck bin/nixarchy-pkg tests/adapter.sh`
(clean) and the QML baseline (48 tests pass) from a copy:

```
d=$(mktemp -d); cp Card.qml PkgModel.qml tests/qml/tst_card.qml "$d"; cp -r tests/qml/imports "$d/imports"
Q=$(nix eval --raw nixpkgs#qt6.qtdeclarative)/lib/qt-6/qml
( cd "$d" || exit 1; QT_QPA_PLATFORM=offscreen HOME=$PWD nix shell nixpkgs#qt6.qtdeclarative -c qmltestrunner -input tst_card.qml -import "$PWD/imports" -import "$Q" )
```

Hand Codex a clean tree.

### 1. Adapter test (`tests/adapter.sh`) -- codex

Anchor `check "a blank search is refused" jq -e '.ok == false' <<<"$(stub_search -- "   ")"`,
which is directly followed by `SEARCHCFG=$(mktemp -d)`. Insert between them
(the later option block appends to `STUBCACHE`, so this block must use its own
cache dir):

```
VCACHE=$(mktemp -d); mkdir -p "$VCACHE/nixarchy"
printf 'pkg\tvfoo\tFoo\tunfree\tprev\t1.2.3\npkg\tvbar\tBar\t\tprev\t\npkg\tvold\tOld five\t\tprev\napp\tvapp\tApp\t\tprev\tLEAK\nopt\tvopt.enable\tOpt\tboolean\tprev\tLEAK\n' \
  > "$VCACHE/nixarchy/index.tsv"
printf 'no-such-stamp\n' > "$VCACHE/nixarchy/stamp"
out=$(XDG_CACHE_HOME="$VCACHE" "$ADAPTER" search -- v)
check "a six-field package row carries its version" \
  jq -e '.rows | map(select(.name == "vfoo"))[0].version == "1.2.3"' <<<"$out"
check "an empty sixth field gives no version key" \
  jq -e '.rows | map(select(.name == "vbar")) | length == 1 and (.[0] | has("version") | not)' <<<"$out"
check "a five-field row gives no version key" \
  jq -e '.rows | map(select(.name == "vold")) | length == 1 and (.[0] | has("version") | not)' <<<"$out"
check "an app or option index row never gets a version, whatever its sixth field" \
  jq -e '.rows | map(select(.kind != "pkg")) | length == 2 and all(has("version") | not)' <<<"$out"
check "a stale index keeps the version (a stamp that cannot match, so stale)" \
  jq -e '.indexStale == true and (.rows | map(select(.name == "vfoo"))[0].version == "1.2.3")' <<<"$out"
rm -rf "$VCACHE"
```

Second edit, anchor the existing test
`check "search takes option rows from the cache, not the index" \` with its
following `jq -e '.options.source == "flake" ...` line (ends `<<<"$out"`).
Directly after that two-line check (before
`check "state reports where the options came from"`), add, using the same
`$out`:

```
check "an option row from the cache never carries a version" \
  jq -e '.rows | all(has("version") | not)' <<<"$out"
```

Check (after step 3): `bash tests/adapter.sh </dev/null | tail -3` ends
`all passed`; the six new lines print `ok`.
The `stamp` file matters: with no `nixarchy-search` on PATH (the flake's
sandbox) every index input reads empty and a missing stamp compares equal, so
the index would read fresh (the "kept corner case" check near `index.status ==
"fresh"`); a stamp that cannot match makes it stale in both places. The `app`
fixture row stands for flatpak rows too (the index writes them as `app`).
Traps: tabs inside `printf` are `\t`, keep them; do not edit any existing
fixture or check; `shellcheck` must stay clean (quote `"$VCACHE"`); do not stage.

### 2. Card test (`tests/qml/tst_card.qml`) -- codex

a. Anchor: the `selRows` property ends with
```
    { attr: "insecure-search", flags: ["insecure"],
      summary: "a search row, no channel" }
  ]
```
Directly after that `]` (before the `// A QtObject, so a test can set tab and cursor` comment), add:

```
  property var versionedSearch: [
    { kind: "pkg", name: "ripgrep", summary: "Utility that combines usability", type: "",
      flags: ["unfree"], scope: "system", version: "15.2.0",
      preview: "ripgrep  15.2.0\nctrl-t tries it now\nversion:  15.2.0" }
  ]
```

b. Anchor `function test_channel_tag_tones() {`. Add this function directly
before it (after `test_version_leads_the_second_column`, whose last line is
`compare(second(3), "")` and closing brace):

```
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

Check: 49 tests, 0 failed, on the fixed tree and on main's `bin/nixarchy-pkg`
(it is a guard; see Decision 7).
Traps: keep the `wait(150)` (without it the first pass at 800 px read a stale
layout and failed the fit check); do not append to `selRows`, reorder it, or
touch the all-rows width test; `win`, `card`, `byName`, `find`, `elidables`
already exist in the file; do not stage.

### 3. Adapter (`bin/nixarchy-pkg`, `cmd_search`) -- codex

a. awk. Anchor `print best, length($2), $1, $2, $3, $4, $5, (FILENAME == idx ? "system" : $6)`
(the line just above the closing `' "$INDEX" ...` of the awk program). Change to

```
print best, length($2), $1, $2, $3, $4, $5, (FILENAME == idx ? "system" : $6), (FILENAME == idx && $1 == "pkg" ? $6 : "")
```

Leave `cut -f3-` as it is: nine fields leave awk, seven reach jq (`.[6]` is the
version).

b. jq. Anchor the two lines

```
        preview: ((.[4] // "") | gsub("\\\\n"; "\n"))
      } + (if .[0] == "opt" then
```

Change the second to

```
      } + (if (.[6] // "") != "" then {version: .[6]} else {} end)
        + (if .[0] == "opt" then
```

keeping the `{set: ...}` and `else {} end)))` lines after it exactly as they are
(same paren count).

Check: `shellcheck bin/nixarchy-pkg` clean; `bash tests/adapter.sh </dev/null | tail -3`
ends `all passed`; by hand in a `mktemp` cache:
`XDG_CACHE_HOME=$d bin/nixarchy-pkg search -- v | jq '.rows[0].version'`.
Traps: the awk program is inside single quotes in a heredoc-ish bash block, so
`"pkg"` needs no escaping but no `'` may enter it; **do not add a `kind` test in
jq** (Decision 3); do not change the sort keys or `head`; do not touch
`labels_tsv`, `cmd_state`, `index_facts`.

### 4. Manual (`docs/manual/from-a-terminal.md`) -- codex

Anchor the end of the `packages` paragraph: the line
`shape. An indexed package with no flags carries `flags: []`.` (it starts with
```A `packages` row carries `attr` and `channel`.```). After it, blank line, then:

```
A `search` row for a package may also carry `version`, from the index. It is
omitted when the index has none (an index written by an older `nixarchy-search`,
an unknown version) and on every `opt` and `app` row. It is not part of the
relied-on shape.
```

then a blank line before `**Not relied on:**`.

Check: `grep -c 'A `search` row for a package may also carry' docs/manual/from-a-terminal.md` prints 1.
Traps: touch no other doc; keep the backtick style of the neighbouring paragraph.

### 5. Coordinator: proofs (`mktemp` copies only)

Every experiment in a copy: `d=$(mktemp -d); ...; ( cd "$d" || exit 1; ... )`.

a. **Adapter checks fail on main.** Copy the new `tests/adapter.sh` with
`git show main:bin/nixarchy-pkg` as the adapter (`ADAPTER_OVERRIDE`, or copy
into a `bin/` layout in the temp dir): exactly the two checks "a six-field
package row carries its version" and "a stale index keeps the version" fail
(`version` is null); the other new checks pass. Record the lines.
b. **Passes with the fix:** the same run with the branch adapter ends `all passed`.
c. **Mutation, adapter** (copy only): change `$1 == "pkg"` in the awk guard to `1`;
"an app or option index row never gets a version" must fail. Drop the jq `!= ""`
test (always emit `{version: .[6]}`); "an empty sixth field gives no version key"
must fail.
d. **QML:** step 0 command with the branch files: 49 passed, 0 failed.
**Mutation, QML** (copy only): in `Card.qml` replace
`(modelData.version ? modelData.version + "  " : "")` with `""`;
`test_search_row_shows_its_version` and `test_version_leads_the_second_column`
must both fail.
e. `shellcheck bin/nixarchy-pkg tests/adapter.sh` clean; `git diff --stat` shows
only `bin/nixarchy-pkg`, `tests/adapter.sh`, `tests/qml/tst_card.qml`,
`docs/manual/from-a-terminal.md`, and `plan/`.
f. `nix flake check` green (shellcheck, qmllint, `qml-tests`).

### 6. Coordinator: commits

Plan approval is its own commit (`docs(plan): approve ... (#105)`) before step 1.
Commit 1 (tests): `tests/adapter.sh`, `tests/qml/tst_card.qml`,
`test(search): a package row carries its version (#105)`.
Commit 2 (fix): `bin/nixarchy-pkg`, `docs/manual/from-a-terminal.md`,
`feat(search): package rows carry the index's version (#105)`.
Both with the attribution trailers.

### 7. Reviews

Fresh `model: "opus"` agent given only this plan path and `git diff main`;
read-only Codex and agy via `second-opinion`. Findings classified confirmed,
refuted or unverified; confirmed ones fixed (a deviation updates `plan/` in the
same commit as the code); their output approves nothing.

### 8. Coordinator: live check (microVM, not razer)

In a `nixarchy-desktop` guest whose `nixarchy-search` carries #1818, inside the
guest only: `nixarchy-pkg reindex`; `nixarchy-pkg search ripgrep | jq '.rows[0].version'`
is a string; the panel's package search row shows it before the summary at
800 px (pane visible) and 700 px; an `app` row and an `opt` row show none.
Screenshot from the guest. Never restart the Omarchy shell from the agent.

### 9. Coordinator: PR

Links intent, spec and this plan, cites #105, says Codex did steps 1-4, lists
the failing-on-main lines from step 5a, and says the live check result (or that
it did not run).

## Tests

- `bash tests/adapter.sh </dev/null` ends `all passed` (six new checks).
- `shellcheck bin/nixarchy-pkg tests/adapter.sh` clean.
- QML (step 0 command): 49 passed, 0 failed.
- `nix flake check` green.
- Proof of failure on main and the three mutations: step 5.

## Rollback

Plain edits to four files and no state: `git revert` the fix commit (the two
adapter version checks then fail on main's adapter, so revert the test commit
with it). Nothing is written outside the worktree; no version bump to undo.
