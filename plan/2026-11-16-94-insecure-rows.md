---
status: approved
issue: 94
spec: spec/2026-11-16-94-insecure-rows.md
coders:
  1: codex   # one Codex run does steps 1-4 in order (owner's routing: agent-run codex refuses a dirty tree and may not commit)
  2: codex   # Card.qml: one condition and one comment
  3: codex   # PkgModel.qml: one string
  4: codex   # docs/manual/packages.md: four small edits
  # Steps 0 and 5-9 stay with the coordinator: baseline, proofs, commits, reviews, the live check, the PR.
reviewers:
  - codex   # reads the diff against this plan and the QML test for tests that cannot fail
  - agy     # independent read of the diff against this plan
---

# Plan: rows the index flags insecure draw in the urgent tone

Branch `feat/94-insecure-rows`. Line numbers are this worktree (df0c796);
**find every anchor by its quoted text**, the numbers drift.

## Decisions (from the approved intent and spec; nothing here is open)

1. **Tone is `Commons.Color.urgent`, the same as `broken`; no third tone.**
   A new colour would need a `Commons.Color` entry in nixarchy's shell, which
   this plugin cannot add. Two urgent tags are told apart by word and by the
   index's order (`unfree`, `broken`, `insecure`).
2. **Search rows too.** One delegate draws Selection rows and search rows
   (a search row is a row with `flags` and no `channel`), so one expression
   covers both. `tagsOf` and the summary-width formula are untouched.
3. **No change to `bin/nixarchy-pkg`.** `labels_tsv`, `cmd_state` and
   `cmd_search` already pass the flags word through; `UNTAG_JQ` has nothing to
   strip. The JSON contract gains nothing (`insecure` is a word inside
   `flags`). No summary suffix. **No version change** (the plugin's
   `manifest.json` stays).
4. **Selection-tab test rows are appended, not inserted** (positions 6 and 7),
   because existing tests index `selRows` by position. The 800/700 width test
   loops over all rows, so it covers the new rows for free.
5. **The other-channel confirmation says "unfree, broken and insecure are not
   known"** (`PkgModel.qml`, and the same sentence in `packages.md`).
6. **Left alone, on purpose (owner decision on Spec Decision 4):**
   `bin/nixarchy-pkg:430` and `:2642`, `docs/manual/troubleshooting.md:43`
   (all about an index built before nixarchy #493, still true) and
   `tools/record-tour.sh:183` (a recording-script comment; **do not widen to
   it**). No step touches those four. Also untouched: `Card.qml:324` ("unfree,
   broken, and the curated cross-reference" describes the raw-pick tags).
7. **The version-on-search-rows follow-up is filed as #105**; cite it in the PR
   and do not implement any of it here.
8. **No test for the docs or for the `PkgModel.qml` string**: no test reads
   that sentence and one would test prose, not behaviour.
9. **Roles.** Codex implements steps 1-4 in one run on a clean tree; the
   coordinator does everything that stages, commits, runs proofs, builds or
   reviews. **One PR**, two commits: tests, then the fix (Card, PkgModel,
   docs).
10. **Live check** in a `nixarchy-desktop` microVM, not razer. The guest needs a
    `nixarchy-search` carrying nixarchy #1818 (nixarchy `origin/main` has it).

## Order and why (test-first)

The test is written first (step 1), the code after (steps 2-4), all in one
Codex run. The coordinator then proves in a `mktemp` copy that the new test
fails against main's `Card.qml` (step 5) and commits the test and the fix
separately (step 6). The only test that must fail on main is
`test_insecure_tag_is_urgent`; every existing test, including the 800/700
width test over the two new rows, passes on main and after.

## Steps

### 0. Coordinator: baseline

`git status` clean on `feat/94-insecure-rows`. Record
`bash tests/adapter.sh </dev/null | tail -3` (ends `all passed`),
`shellcheck bin/nixarchy-pkg tests/adapter.sh` (clean), and the QML baseline
(47 tests pass) from a flake-style copy:

```
d=$(mktemp -d); cp Card.qml PkgModel.qml tests/qml/tst_*.qml "$d"; cp -r tests/qml/imports "$d/imports"
( cd "$d" || exit 1; QT_QPA_PLATFORM=offscreen HOME=$PWD nix shell nixpkgs#qt6.qtdeclarative -c qmltestrunner -input tst_card.qml -import "$PWD/imports" )
```

(For `-import` of Qt's own modules use `$(nix eval --raw nixpkgs#qt6.qtdeclarative)/lib/qt-6/qml`
as `flake.nix:102-114` does.) Hand Codex a clean tree.

### 1. Test (`tests/qml/tst_card.qml`) -- codex

a. In `property var selRows: [`, the last row is
`{ attr: "version-only", channel: "default", version: "2.0", flags: [] }`.
Add a trailing comma to it and append two rows after it (positions 6 and 7):

```
    { attr: "openssl_1_1", channel: "default", summary: "an insecure package",
      version: "1.1.1w", flags: ["unfree", "insecure"] },
    { attr: "insecure-search", flags: ["insecure"],
      summary: "a search row, no channel" }
```

b. Add this function directly after `function test_channel_tag_tones() { ... }`
(which ends with `verify(Qt.colorEqual(steam[3].color, card.dim), "default stays dim")`
and a closing brace):

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

Check (after step 2, step 5 runs it): 48 tests, 0 failed.
Traps: do not reorder or insert rows (tests at `itemAtIndex(0..5)` and
`second(5)` depend on positions); do not edit any other test; the width test
needs no edit. Do not stage.

### 2. Tone and comment (`Card.qml`) -- codex

a. Anchor `readonly property color tone: modelData === "broken" ? Commons.Color.urgent`
(inside the tag `Rectangle`, with the next line
`: (modelData === "unfree" || modelData === "other") ? Commons.Color.accent`).
Change only the first line to
`readonly property color tone: (modelData === "broken" || modelData === "insecure") ? Commons.Color.urgent`
and keep the two continuation lines and their alignment as they are.

b. Anchor the comment above `id: indexAge`:

```
      // A stale index has no unfree or broken flags in it at all, so every
      // package on it reads as free. Said plainly, with the key that fixes
      // it, rather than left for the user to discover after a rebuild.
```

Replace with

```
      // A stale index may be missing flags (unfree, broken, insecure), or carry
      // outdated ones: a Selection row gets none from it, a search row keeps
      // what it cached. Either way an unmarked package is not known to be safe.
      // Said plainly, with the key that fixes it, rather than left for the user to
      // discover after a rebuild.
```

Check: `grep -n 'unfree or broken' Card.qml` finds nothing; the QML tests
(step 1 check).
Traps: **no `Color.` fragment in new comment text** (nixarchy's
`qml-color-qualified` check reads comments as code, #101 and #102); the
comment above is clean. Do not touch `tagsOf` (`flags` loop) or the width
formula.

### 3. Message (`PkgModel.qml`) -- codex

Anchor `+ " even at the same version. unfree and broken are not known for that"`
(the line before `+ " channel. SHIFT+RETURN again to add it."`). Change
`unfree and broken are not known` to `unfree, broken and insecure are not known`
in that one line.

Check: `grep -n 'unfree and broken' PkgModel.qml` finds nothing; `tst_pkgmodel.qml`
reads no such string (`grep -rn "not known" tests` finds none).
Traps: keep the string concatenation shape; do not rewrap other lines.

### 4. Manual (`docs/manual/packages.md`) -- codex

a. Anchor `Three things a row can be marked with, all shown before anything is queued:`
becomes `Four things a row can be marked with, all shown before anything is queued:`.

b. After the `broken` paragraph (ends `it. It will still not build.`) and before
`**`curated: <name>`**`, insert (blank line either side):

```
**`insecure`** — nixpkgs lists a known vulnerability for this package, or
marks it insecure. You can still add it, and it will usually refuse to
build until you permit it by name. The detail pane beside the row says
"Marked INSECURE in nixpkgs."
```

The "refuse to build ... by name" clause is nixpkgs's `meta.knownVulnerabilities`
behaviour; Codex checks the wording against the nixpkgs manual and drops the
clause if unsure (report which).

c. Anchor (two lines, in "A flag you do not see is not a no"):
`If the search index is stale, it carries **no flags at all**, and every`
`package reads as free. The footer says when the index was built and what`. Change the first sentence to
read: "If the search index is stale, a **Selection** row carries no flags at
all, so every package reads as free, and a **search** row can show flags that
are outdated, or missing one such as `insecure`." The rest of the paragraph
(footer example, `r`, 45 seconds) stays unchanged, as does the "absence of
evidence" line.

d. Anchor ``It also tells you that `unfree` and `broken` are **not known** for that``
becomes ``It also tells you that `unfree`, `broken` and `insecure` are **not known** for that``.

Check: `grep -n 'Four things' docs/manual/packages.md` finds one line;
`grep -n -e 'unfree and broken' -e 'unfree or broken' -e '`unfree` and `broken`' Card.qml PkgModel.qml docs/manual/packages.md`
exits 1 (the four sentences left alone in step "Decisions 6" are in other
files).
Also check: `grep -c 'Marked INSECURE in nixpkgs' docs/manual/packages.md` prints 1 and `grep -n 'no flags at all' docs/manual/packages.md` finds only the new Selection-row sentence (the old "it carries **no flags at all**" wording is gone).
Traps: do not touch `troubleshooting.md`, `from-a-terminal.md`, or the image
alt text on line 50; keep the em dash style of the neighbouring paragraphs.

### 5. Coordinator: proofs (`mktemp` copies only)

Every experiment in a copy: `d=$(mktemp -d); ...; ( cd "$d" || exit 1; ... )`.
a. **New test fails on main.** Copy main's `Card.qml` (`git show main:Card.qml`)
beside the new `tst_card.qml`: `test_insecure_tag_is_urgent` fails with
`insecure selection row is urgent`; all other tests pass. Record the line.
b. **Passes with the fix:** 48 passed, 0 failed (includes the 800/700 width test).
c. **Mutation:** in the copy change `"insecure"` in the new condition to
`"insecur"`; the new test must fail.
d. `bash tests/adapter.sh </dev/null | tail -3` ends `all passed`;
`shellcheck bin/nixarchy-pkg tests/adapter.sh` clean (no `bin` change expected;
`git diff --stat` shows only the four files).
e. `nix flake check` green (this flake's checks only; the `qml-color-qualified` check is nixarchy's, so also read the new Card.qml comment by eye: no `Color.` fragment).

### 6. Coordinator: commits

Commit 1 (tests): `tests/qml/tst_card.qml` only, `test(card): insecure tags draw urgent (#94)`.
Commit 2 (fix): `Card.qml`, `PkgModel.qml`, `docs/manual/packages.md`,
`fix(card): rows the index flags insecure draw in the urgent tone (#94)`.
Plan approval is its own commit (`docs(plan): approve ... (#94)`) before step 1.

### 7. Reviews

Fresh `model: "opus"` agent given only this plan path and `git diff main`;
read-only Codex and agy via `second-opinion`. Findings classified confirmed,
refuted or unverified; confirmed ones fixed; their output approves nothing.

### 8. Coordinator: live check (microVM, not razer)

In a `nixarchy-desktop` guest whose `nixarchy-search` carries #1818, inside
the guest only: `nixarchy-pkg reindex` (about a minute);
`nixarchy-pkg search <an insecure package>` shows `insecure` in `flags`;
Selection tab and the search result draw the tag urgent (screenshot from the
guest); preview reads "Marked INSECURE in nixpkgs."; an `other` row for the
same package has no insecure tag; with the index made stale (guest only), the
Selection row loses the tag and the footer asks for a rebuild. Record the
guest's count of flagged packages (the intent measured 123). Never restart the
Omarchy shell from the agent.

### 9. Coordinator: PR

Links intent, spec and this plan, cites #94 and the follow-up #105, says which
steps Codex did (1-4), lists the failing-on-main line from step 5a.

## Tests

- `bash tests/adapter.sh </dev/null` ends `all passed` (unchanged).
- `shellcheck bin/nixarchy-pkg tests/adapter.sh` clean.
- QML from a flake-style copy (step 0 command): 48 passed, 0 failed.
- `nix flake check` green.
- Proof of failure on main and mutation proof: step 5.

## Deviations (after review)

- Review (Opus, agy) found four sentences the plan missed, all fixed:
  `README.md:44` (the other-channel confirmation now lists `insecure`, as
  `PkgModel.qml:888` does); `packages.md:66` (the detail pane shows the
  INSECURE line on a search result only, since Selection rows carry no
  preview); "permit it by name and version" (`permittedInsecurePackages`
  takes `name-version`); and the comment above `addFromOtherChannel()`.
- Commit subjects differ in wording from step 6; order and file split match.
- Left alone, owner's call: `README.md:23-24` and `assets/showcase/README.md:44`
  ("`unfree` and `broken` flagged", incomplete rather than false).

## Rollback

Plain edits to four files and no state: `git revert` the fix commit (the test
then fails on main's `Card.qml`, so revert the test commit with it). Nothing
is written outside the worktree; no version bump to undo.
