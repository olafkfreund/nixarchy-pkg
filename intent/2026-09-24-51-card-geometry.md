---
status: approved
issue: 51
author: olafkfreund
---

# Intent: the harness measures Card's layout, and is trusted to

## Problem

#50 built a headless QML harness and covered `PkgModel`. `Card.qml` was in
its approved plan as step 4 and was **dropped during implementation**, on a
diagnosis that has since been disproved.

What I concluded then: the flags wrapper `Row` inside `Card`'s delegate "is
never instantiated", inferred from `Component.onCompleted` producing no
output with either `console.log` or `console.warn`.

What is actually true, established since:

1. **Logging from inside a `ListView` delegate is not routed to
   `qmltestrunner`'s output.** Counting creations with a property instead
   gives `rootCreated=1 nestedCreated=1` -- both handlers ran, and the
   wrapper was always created. The conclusion came from *absence of output*,
   which was never evidence.

2. **`visible` read `false` because the whole tree was effectively
   invisible**, not because of `modelData` or scoping. The expression's
   inputs were correct in that scope (`lenBare=2`), while every ancestor
   read false:

   ```
   TestCase item visible=false
   ListView      visible=false
   delegate      visible=false
   flagsRow      visible=false   (its own binding says true)
   ```

   `Item.visible` is **effective** visibility, and a bare `TestCase` item is
   not on a shown window.

That explains the 10px overflow the harness reported, and which I nearly
filed as a defect in #45's fix: `Row` positions children by **effective**
visibility, so the invisible wrapper was skipped in layout, while
`Card`'s `Style.space(10) * (flags.visible ? 3 : 2)` read the *binding* as
true and subtracted three gaps where layout used two. One `Style.space(10)`
-- which is why it was suspiciously constant at every flag count.

With the subject in a visible `Window`, the same measurement gives
**overflow 0.0 at every flag count**. #45's fix is correct, as the razer
screenshots said.

So `Card` is testable, the blocker was a one-line omission in my harness,
and the suite is currently one `Window` short of covering the layout bug it
was partly built for.

## Proposed outcome

- `Card`'s summary-width behaviour is asserted by the suite, at zero, one
  and two flags.
- The assertion is a **property** -- the summary fits inside its row -- not
  a transcription of the width expression, which would only assert my copy
  of it.
- The `Window` wrapper carries a comment saying why it is not optional, so
  nobody removes it and rediscovers a 10px ghost.
- #51 is closed with its wrong diagnosis corrected in the thread rather than
  quietly superseded.

## Affected users and systems

- Contributors only. No runtime behaviour changes.
- `tests/qml/` (a new test file), `flake.nix` (the existing `qml-tests`
  check learns about it). **No change to `Card.qml`** -- the #50 intent
  forbids changing the subject to make it testable, and that still holds.

## Constraints

- Must not assert the width formula. The property is "the summary's right
  edge does not pass the row's right edge"; reproducing the arithmetic would
  make the test agree with itself.
- Must not assert stub values, per #50.
- Must keep the suite runnable with no display, no `/etc/nixarchy`, no
  omarchy shell and no razer.
- Must fail when the fix it guards is reverted -- the check that #41 taught
  and #50 formalised.

## Open questions

1. **Does a visible `Window` still count as headless?** It passed under
   `QT_QPA_PLATFORM=offscreen` here, but that is one machine; whether it
   holds in the nix sandbox and on a CI runner is exactly the kind of thing
   this session has been wrong about before, and is worth proving rather
   than assuming.

2. **Does the `Window` belong in the existing `tst_pkgmodel.qml` or a
   separate file?** `PkgModel` needs no window and gains nothing from one;
   a second file keeps that true but means two subjects to copy into the
   check.
