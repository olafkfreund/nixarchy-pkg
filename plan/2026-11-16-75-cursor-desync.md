---
status: approved
issue: 75
spec: spec/2026-11-16-75-cursor-desync.md
coders:
  1: coder   # the real-model test section and the model clamp tests: several cases, follows tst_card/tst_pkgmodel patterns
  2: codex   # three small, tricky QML lines: Qt.binding re-assignment, a function binding, a clamp inside a count change
reviewers:
  - codex   # QML binding and ListView semantics are where this goes wrong
  - agy     # independent read of the diff against this plan
---

# Plan: the row you see selected is the row a key acts on

## Decisions (from the approved intent and spec)

1. **The model's `cursor` is the only selection.** The list, the highlight
   and the preview follow it, and keys act on it.
2. **The trigger:** any new rows array resets `ListView.currentIndex` to 0,
   even one of the same length. A write's answer always produces one
   (`_absorb` assigns `state`). The binding
   `currentIndex: root.model.cursor` only re-runs when `cursor` changes.
3. **Fix 1, `Card.qml`:** the list re-binds `currentIndex` to the cursor in
   `onModelChanged`. This is synchronous, with no frame on row 0.
4. **Fix 2, `Card.qml`:** the preview reads
   `root.model.rowAt(root.model.cursor)`, not `list.currentItem`.
5. **Fix 3, `PkgModel.qml`:** `onCountChanged` clamps `cursor` into
   `[0, count - 1]`. This covers the Queue check row going away and Flakes
   naming without a clamp at each site. `_absorb`'s clamp stays.
6. **Behaviour:**
   - A removed row keeps the same index, clamped.
   - A write's answer keeps the index current when it arrives, never the row
     that was acted on.
   - Tab, query and search changes still go to row 0.
   - The highlight (`index === list.currentIndex`) is unchanged.
7. **Tests use the real `PkgModel`**, never the fake one: the fake's rows
   binding hid the trigger. Six must fail on main; three are regression
   tests. The preview-scrolled-out test is kept only if it can be shown to
   fail on main.
8. **Live check** in a `nixarchy-desktop` microVM, not razer (owner's
   standing choice).
9. **One PR**, two commits: tests, then the fix.

## Steps

### 0. Coordinator: rebase and re-check

`git rebase main` on `fix/75-cursor-desync`. Re-find the anchors below by
their quoted text (the numbers are main at 9bc38c2/a9806a1).

### 1. Tests (`tests/qml/tst_card.qml`, `tests/qml/tst_pkgmodel.qml`) -- coder

**`tst_card.qml`.** Add a second subject at the bottom of the TestCase,
beside the existing `fakeModel` card. Do not change the existing tests.

```qml
PkgModel { id: realModel }
Card { id: realCard; width: 800; height: 400; model: realModel; visible: false }
```

Put it inside the existing `win` Window, like `card`. It is **hidden by
default**: a visible second card on top would take the pointer from the
existing hover tests (`tst_card.qml:253`, `:272`). Each new test sets
`realCard.visible = true` first and `false` in a `try/finally`.

The fake model gains `function rowAt(i) { return (i >= 0 && i < theRows.length) ? theRows[i] : null }`
beside `rows()` (`tst_card.qml:35`): after fix 2, every Card calls
`model.rowAt()`, and the fake would otherwise throw.

Helpers:
- `realList()` = `find(realCard, "QQuickListView")`.
- `st(n, onIndex, extra)` builds the state JSON: `n` apps with ids
  `a0..a{n-1}`, `label`, `category: "Utility"`, `kind: "app"`, and
  `enabled: i === onIndex`. Plus `services: []`, `packages: []`,
  `options: []`, `drafts: []`, and `ok: true`.
- Start each new test with `realModel.busy = false`, `realModel.setTab(0)`,
  then `realModel._reader.deliver(st(6, -1))` and
  `tryCompare(realList(), "count", 6)`.

A write is `verify(realModel.write(["toggle", "app", "a2"]))` followed by
`realModel._writer.deliver(st(...))`. That is the stub's `deliver()`; never
call `finish()` first (Process stub order). Use `wait(50)` after a deliver.

Must fail on main. Each asserts `realList().currentIndex === realModel.cursor`
and that the preview shows the row at the cursor:
`compare(JSON.stringify(realCard.currentRow), JSON.stringify(realModel.rowAt(realModel.cursor)))`.
Queue and Flakes rows have no `id`, so compare whole rows, not ids. Each also
checks its own expectation:
1. `test_real_write_same_count`: `cursor = 2`, write, deliver
   `st(6, 2)`. `cursor` is 2, the list is 2, and `currentRow.enabled` is true
   (the new content).
2. `test_real_write_shrinks_without_crossing`: `cursor = 2`, write, deliver
   `st(4, 2)`. The list is 2.
3. `test_real_move_during_write`: `cursor = 2`, write, then `cursor = 4`,
   then deliver `st(6, 2)`. The selection is 4.
4. `test_real_queue_check_row_goes`: `setTab(6)`. Deliver a pending answer
   through `realModel._pending.deliver(...)` with a few rows, in the shape
   `tst_pkgmodel`'s `pend()` helper builds (copy that helper). Two
   separate setups, each with `cursor = realModel.count - 1`.
   *Cancel:* `checkResult = null`, `checkRunning = true` (the running row),
   then `cancelCheck()` **and**
   `realModel._check.finish(143)`. Only the check's exit clears `checkRunning`
   (`PkgModel.qml:495`), and the stub emits `exited` only from `finish()`, so
   without it the row never goes. `cursor` is less than `count`, and the list
   and preview agree. *Invalidate:*
   `checkRunning = false`, `checkResult = { verdict: "evaluates",
   fingerprint: "f1" }` (the result row), then deliver a pending answer with
   `fingerprint: "f2"`
   (`PkgModel.qml`, `checkResult.fingerprint !== data.fingerprint`).
5. `test_real_naming_shrinks_flakes`: `setTab(5)`, set
   `realModel.inspected` to an object with `ok: true`, a `ref` and enough
   outputs for 3 or more rows. Read `flakeRows()` for the shape it needs, and
   take the fields from `tst_pkgmodel`'s inspection tests. Set
   `cursor = realModel.count - 1` (the "declare" row) and
   `verify(realModel.cursor >= 2)`, then `beginNaming()`. `cursor` is 0, and the list and preview agree.
6. `test_real_preview_scrolled_out`: deliver `st(200, -1)`, set
   `cursor = 199`, `realList().positionViewAtBeginning()`, `wait(50)`.
   **First** assert `realList().currentItem === null`. If that does not hold
   on main, Qt kept the delegate, so delete this test and report it (spec:
   do not keep a test that cannot fail). Then fix 2 has no automated test.
   The PR says so, and the live check covers it. Then `currentRow.id === "a199"`.

Regression tests (they pass on main and must keep passing):
7. `test_real_shrink_below_cursor`: `cursor = 5`, write, deliver `st(4, -1)`.
   `cursor` is 3, and the list is 3.
8. `test_real_empty_and_refill`: `cursor = 2`, `_reader.deliver(st(0, -1))`,
   then `st(6, -1)`. `cursor` is 0, and the list and preview agree.
9. `test_real_tab_change_resets`: `cursor = 3`, `setTab(1)`, `setTab(0)`.
   `cursor` is 0, and the list is 0.

**`tst_pkgmodel.qml`**, the clamp without a view:
- `test_cancel_check_clamps_cursor`: the same setup as 4 on `m`, then
  `cancelCheck()` and `m._check.finish(143)`. `m.cursor <= m.count - 1`.
- `test_naming_clamps_cursor`: the same setup as 5, then `beginNaming()`.
  `m.cursor === 0`.
- Reset anything new in `cleanup()`: `inspected`, `checkResult` and
  `checkRunning` are already reset there; add `naming` if needed.

**Run** (from a flake-style copy, because `-input` in `tests/qml` fails with
"Card is not a type"):

```bash
QT=$(nix eval --raw nixpkgs#qt6.qtdeclarative.outPath)
d=$(mktemp -d) && cp *.qml tests/qml/tst_*.qml "$d" && cp -r tests/qml/imports "$d"
( cd "$d" && for t in tst_card tst_pkgmodel; do
    QT_QPA_PLATFORM=offscreen HOME=$PWD "$QT/bin/qmltestrunner" -input $t.qml -import imports -import "$QT/lib/qt-6/qml"; done )
rm -rf "$d"   # the subshell keeps you in the worktree
```

→ **Verify:** on this branch (no fix yet), tests 1-6 and the two
`tst_pkgmodel` clamp tests **fail**, tests 7-9 pass, and every older test
still passes. Report each result by name.

Traps:
- Never write `list.currentIndex` from a test: it destroys the binding
  (spec, Risks).
- Process stub order: `deliver()` answers, `finish()` is a death; a write
  leaves `busy` true until its answer.
- `tst_card` runs with `failOnWarning` on binding loops in some tests. Do
  not suppress warnings.
- Nothing written to `/tmp` except through `mktemp`.
- Test 8: never assert `currentIndex === cursor` while the list is empty
  (`ListView` holds -1 there and the model 0); assert only after the refill.

**Coordinator after step 1:** review the diff, run the commands, and commit
the tests (`test(card): …`) before step 2 starts, so step 3 can revert each
fix against committed tests.

### 2. The fix (`Card.qml`, `PkgModel.qml`) -- codex

1. `Card.qml:59`: replace
   `readonly property var currentRow: list.currentItem ? list.currentItem.modelData : null`
   with
   `readonly property var currentRow: root.model ? root.model.rowAt(root.model.cursor) : null`.
2. `Card.qml:193`: after
   `currentIndex: root.model ? root.model.cursor : 0`, add:

   ```qml
   // Any new rows array resets ListView's own currentIndex to 0, and the
   // binding above only re-runs when cursor changes (#75).
   onModelChanged: currentIndex = Qt.binding(function () { return root.model ? root.model.cursor : 0 })
   ```
3. `PkgModel.qml:269`: after `readonly property int count: rows().length`,
   add:

   ```qml
   // Whatever shrank the rows -- a cancelled check, naming, a filter -- the
   // cursor must still name a row (#75).
   onCountChanged: if (cursor > Math.max(0, count - 1)) cursor = Math.max(0, count - 1)
   ```

→ **Verify:** the step 1 commands. All tests pass, with no QWARN. Then
`nix flake check` passes.

**Coordinator after step 2:** review the diff, run the commands, and commit
the fix (`fix(card): …`).

Traps:
- `rows()` must not read `cursor`, or fix 3 loops. Check that it does not.
- The highlight line (`index === list.currentIndex`) stays as it is.
- No `Qt.callLater`: the spec chose the synchronous re-bind.

### 3. Coordinator: verify, live, review, PR

- Mutation: revert each fix alone and confirm a named test fails:
  - fix 1 → tests 1-3;
  - fix 2 → test 6, if kept;
  - fix 3 → tests 4-5 and the `tst_pkgmodel` clamps.
- `nix flake check`.
- Live in a `nixarchy-desktop` microVM:
  1. On Apps, `DOWN DOWN` then `SPACE`: the highlight and preview stay on
     row 2.
  2. `DOWN` ×3 lands on row 5.
  3. Queue: put the cursor on the last row, run `c`, then ESC to cancel. The
     highlight is on a real row, and `SPACE`/`RETURN` act on it.
- Reviews: Codex and agy, read-only, on `git diff main` against this plan.
  Fresh Opus review with the plan path and the diff.
- PR linking intent, spec and plan; it says which steps coder and Codex did.

## Tests

- `nix flake check`: all checks pass (tst_card, tst_pkgmodel,
  tst_optionform, the adapter suite where CI runs it).
- The new tests fail on main as listed, and pass on the branch.
- The live microVM steps above.

## Rollback

Revert the PR. Both changes are local to `Card.qml` and one handler in
`PkgModel.qml`; no data or file format changes.
