---
status: approved
issue: 51
spec: spec/2026-09-24-51-card-geometry.md
---

# Plan: the harness measures Card's layout, and is trusted to

## Approved decisions, carried over

Self-contained: everything needed to implement this is below.

**Why:** #50's harness covers `PkgModel`. `Card` was in its approved plan as
step 4 and was dropped on a diagnosis since disproved -- the wrapper `Row`
was always created; logging from a `ListView` delegate simply is not routed
to `qmltestrunner`, and `visible` read `false` because `Item.visible` is
*effective* visibility and a bare `TestCase` item is not on a shown window.

That also produced a phantom 10px overflow at every flag count, because
`Row` lays out by effective visibility and skipped the flags wrapper while
`Card`'s `flags.visible ? 3 : 2` read its binding as `true`. It was very
nearly filed as a defect in the #45 fix it actually exonerates.

**Decisions:**

1. **A visible `Window` wraps the subject** -- proven to coexist with
   `QT_QPA_PLATFORM=offscreen` inside the real `nix build` sandbox, not
   assumed.
2. **The assertion is a property, not the formula**:
   `summary.x + summary.width - row.width <= 0.5` and
   `summary.width >= 0`, at zero, one and two flags. Reproducing the width
   expression would make the test agree with itself.
3. **A separate file**, `tests/qml/tst_card.qml`. `PkgModel` needs no window.
4. **The `Window` carries a comment forbidding its removal**, because it
   looks like scaffolding and is load-bearing.

**Measured, not assumed:** the sandbox prints `Fontconfig error: Cannot load
default config file`. Not fatal, and it means **text metrics there are not a
desktop's** -- so an assertion on specific widths would be brittle across
environments. This is why the assertion is a property.

**State on entering implementation:** answering the spec's Q1 required
building and running the real check, so `tests/qml/tst_card.qml` and the
`flake.nix` change already exist **uncommitted** in the working tree. They
were briefly committed by accident along with the spec and were split back
out. They land with the implementation commit and not before.

## Steps

1. `tests/qml/tst_card.qml` -- the test, already written and passing:
   a `Window { visible: true }` around `Card`, a plain fake model whose
   `rows` is a **function** (`Card` binds `root.model.rows()`), three rows
   at zero, one and two flags, and the two property assertions above.
   Traversal is structural -- `find(..., "QQuickListView")` and the last
   elidable `Text` as the summary -- because `objectName`s would mean
   editing `Card.qml`, which #50's intent forbids. -> verify by check 1.

2. `flake.nix` -- the existing `qml-tests` check copies `Card.qml` and
   `tst_card.qml` alongside, and runs `qmltestrunner` on it before the
   `PkgModel` suite. Both share the stub imports and the Qt import path.
   -> verify by checks 1 and 4.

## Tests

`nix flake check -L` locally and in CI. Nothing needs razer, a display,
`/etc/nixarchy` or the omarchy shell.

1. `nix flake check -L` passes with **both** suites inside `qml-tests`.
2. **Negative -- the fix.** In a scratch copy, revert #45: restore
   `width: parent.width - name.width - Style.font.heading - Style.space(40)`
   in `Card.qml`. `test_summary_fits_its_row_at_every_flag_count` must
   **fail**, and the failure message must name the overflowing flag count.
   An assertion that survives this is worthless -- #41 produced one, and
   #50's suite exists partly because of it.
3. **Negative -- the `Window`.** In a scratch copy, remove the `Window`
   wrapper and parent `Card` directly to the `TestCase`. The test must
   **fail** with the phantom 10px. This proves the comment's claim rather
   than asserting it, and is the only thing that would catch a future reader
   deleting the `Window` as redundant.
4. The suite runs with no display, no `/etc/nixarchy`, no omarchy shell and
   no razer -- re-confirmed on the final tree inside `nix build`.
5. `tests/adapter.sh` on razer still passes, unchanged.
6. CI green with both suites in the log.

## Verification results

Both steps applied. No deviation.

| check | result |
| ----- | ------ |
| 1. `nix flake check -L`, both suites in `qml-tests` | **passes** |
| 2. **negative -- revert #45's fix** | **FAILS**, exit 1: *"2 flag(s): the summary must fit its row -- overflows by 163.6"* |
| 3. **negative -- remove the `Window`** | **FAILS**, exit 1: *"overflows by 10.0"* -- the phantom, on demand |
| 4. runs with no display, no `/etc/nixarchy`, no shell, no razer | **yes**, inside `nix build` |
| 5. `tests/adapter.sh` on razer | **187 assertions, 0 failures**, unchanged |
| 6. CI | pending the pull request |

**Check 2 is worth reading twice.** Reverted, the two-flag row overflows by
**163.6px** -- which is the flags row's width plus its gap, the term the old
expression never subtracted at all. That is an independent confirmation of
#45's analysis, arrived at from the opposite direction: #45 reasoned about
the arithmetic and checked it by eye, and this measures the consequence.

**Check 3 turns a session's worth of confusion into a guard rail.** The
`Window` is not scaffolding, and the comment above it now makes a claim the
suite enforces: delete it and the phantom 10px returns and the build fails.
Nobody has to rediscover why it is there.

## Rollback

One new test file and a few lines of `flake.nix`. **No change to any of the
five QML files**, so a revert cannot affect the shipped plugin.

If delegate traversal proves too brittle -- the spec's named risk, since
reordering that row breaks the test rather than the product -- the recorded
successor is `objectName`s on the row's children, which requires relaxing
#50's constraint against editing the subject. That is a decision for the
approver, not a quiet fix.
