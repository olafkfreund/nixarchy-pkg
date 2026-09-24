---
status: approved
issue: 51
intent: intent/2026-09-24-51-card-geometry.md
---

# Spec: the harness measures Card's layout, and is trusted to

## Design

Both of the intent's questions were answered by running the thing, not by
reasoning about it.

### 1. A visible `Window` works in the sandbox -- proven

**Decision (Q1).** The intent flagged this as "exactly the kind of thing
this session has been wrong about before". So it was built and run inside
the real `nix build` sandbox -- no devShell, no display, no network:

```
nixarchy-pkg-qml-tests> PASS : CardGeometry::test_summary_fits_its_row_at_every_flag_count()
nixarchy-pkg-qml-tests> Totals: 3 passed, 0 failed
nixarchy-pkg-qml-tests> Totals: 8 passed, 0 failed
```

`QT_QPA_PLATFORM=offscreen` and a `visible: true` `Window` coexist.

**One thing that run surfaced, which reasoning would not have:** the
sandbox prints `Fontconfig error: Cannot load default config file`. It is
not fatal, but it means **text metrics inside the sandbox are not the ones a
desktop produces**. An assertion on a specific width would be brittle across
environments and would eventually be disabled.

That vindicates the shape of the assertion below rather than being a problem
to solve.

### 2. The assertion is a property, not the formula

The test asserts, for each of zero, one and two flags:

```
summary.x + summary.width - row.width <= 0.5      // it fits
summary.width >= 0                                 // and is never negative
```

It does **not** reproduce
`parent.width - name.width - Style.font.heading - flags.width - space(10) * (...)`.
Reproducing it would make the test agree with itself and change in lockstep
with any future error. The property is what #45 was about: the summary must
elide at the row's real edge rather than be clipped past it.

The `0.5` tolerance is for sub-pixel layout, not a fudge for a known
discrepancy -- the measured overflow is `0.0` at every flag count.

### 3. A separate file

**Decision (Q2).** `tests/qml/tst_card.qml`, not folded into
`tst_pkgmodel.qml`. `PkgModel` needs no window and gains nothing from one;
keeping them apart keeps that true and keeps each file's subject obvious.
The `qml-tests` check runs both, which the probe confirmed.

### 4. The `Window` carries a comment that forbids removing it

Not decoration. `Item.visible` is effective visibility, so under a bare
`TestCase` every item reads `false`; `Row` lays out by effective
visibility and skips the flags wrapper, while `Card`'s
`flags.visible ? 3 : 2` reads its binding as `true`. The disagreement is a
phantom 10px overflow at every flag count, which cost most of a session and
was nearly filed as a defect in the #45 fix it actually exonerates.

A future reader deleting the `Window` as redundant scaffolding would
resurrect exactly that. The comment says so.

## Disclosure

Answering Q1 required building and running the real check, so the working
tree already holds a functioning `tests/qml/tst_card.qml` and the
`flake.nix` change. **They are staged and uncommitted**, and nothing lands
until the plan is approved. The probe is verification; it is not permission.

## Alternatives rejected

- **Asserting the width formula.** The test would agree with itself and
  would survive any future arithmetic error that the code and the test made
  together.
- **Asserting measured pixel values** (`sumW=511.2` and so on). Readable,
  and brittle: the sandbox has no fontconfig, so those numbers are not the
  desktop's.
- **Folding into `tst_pkgmodel.qml`.** One fewer file, and it would put a
  `Window` around a subject that does not need one.
- **Making `Card` testable by changing it.** Forbidden by #50's intent, and
  unnecessary -- it was always testable; the harness was wrong.

## Risks

- **The `Window` is load-bearing and looks like scaffolding.** Mitigated by
  the comment; not eliminated. The negative test below is what would catch
  its removal.
- **Sandbox font metrics differ from a desktop's.** Accepted, and the reason
  the assertion is a property. It does mean this check cannot catch a
  *visual* regression -- only a geometric contradiction.
- **Delegate traversal is structural.** `find(..., "QQuickListView")` and
  taking the last elidable `Text` as the summary depend on `Card`'s shape.
  A future reorder of that row breaks the test rather than the product. The
  alternative -- `objectName`s -- means changing `Card.qml`, which #50's
  intent forbids.
- These assert geometry, not appearance. Nothing here would catch a wrong
  colour, a wrong font or an overlap that happens to fit inside the row.

## Verification

1. `nix flake check -L` passes with both suites in `qml-tests`.
2. **Negative:** revert #45's fix in a scratch copy -- restore
   `- Style.space(40)` and drop the flags term -- and confirm
   `test_summary_fits_its_row_at_every_flag_count` **fails**, with the
   flagged rows overflowing.
3. **Negative:** delete the `Window` wrapper in a scratch copy and confirm
   the test fails with the phantom 10px, proving the comment's claim rather
   than asserting it.
4. The suite runs with no display, no `/etc/nixarchy`, no omarchy shell and
   no razer -- already shown, to be re-confirmed on the final tree.
5. `tests/adapter.sh` on razer unchanged.
6. CI green with both suites in the log.
