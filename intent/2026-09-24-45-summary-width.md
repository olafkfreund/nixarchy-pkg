---
status: draft
issue: 45
author: olafkfreund
---

# Intent: a row's summary elides where the row actually ends

## Problem

`Card.qml:205` sizes a list row's summary text by subtracting what else is
on the row:

```qml
width: parent.width - name.width - Style.font.heading - Style.space(40)
```

The `Row` (`:140`) has `spacing: Style.space(10)` and margins of
`Style.space(10)` a side. Its children are the state glyph
(`width: Style.font.heading`), `name`, a `Repeater` of flags (`:188`), then
this summary.

With **no** flags there are three children, so two gaps plus two margins is
exactly `Style.space(40)`. The constant is precisely right for that case --
**which means it carries no slack whatsoever**. Every flag then adds one
more gap *and* its own width, and the expression subtracts neither.

So on any row with a flag, the summary `Text` believes it has more room than
the row has. `elide: Text.ElideRight` computes its ellipsis for that wrong
width, and `ListView.clip` (`:117`) cuts the result at the real edge. The
text ends where the list stops drawing rather than at an ellipsis the reader
can recognise as "there is more". `unfree`, `broken` and the
cross-reference flags are ordinary on the Apps tab, so this is the common
case, not an edge one.

**The issue's other claim does not hold, and has been corrected there.**
#45 says the width can go negative on a flake row and the summary silently
disappears. The width can indeed go negative -- `name.width` is capped at
`parent.width` rather than 42% on the `modelData.kind !== undefined` branch
(`:173`) -- but rows carrying `kind` are built at `PkgModel.qml:110-136`
with **only `kind` and `label`**, and the summary draws
`summary || note || type || line || category || ""`. On exactly the rows
that can go negative, that is `""`. Nothing disappears, because nothing was
there.

I also could not verify what Qt does with a negative-width `Text`: three
attempts at a headless `qml` runtime produced no output, so that claim is
not repeated as fact anywhere in this task.

## Proposed outcome

- A row's summary elides at the row's real right edge, with a visible
  ellipsis, whatever flags the row carries.
- The width expression accounts for everything on the row, so adding a
  fourth child later does not silently reintroduce this.
- The expression cannot evaluate to a negative number, regardless of
  whether that is currently reachable.

## Affected users and systems

- Anyone reading the Apps tab, where flags are common. Purely visual; no
  adapter call, no config, no state.
- `Card.qml` only.
- Verification host is **razer**, per repo convention. Never p620. The
  screenshots taken for #38 are a usable before-image.

## Constraints

- Must not reintroduce a hand-maintained constant that is right only for
  one arrangement of children. That is the defect, not the symptom.
- Must not change row height, the name's width cap, or flag rendering.
  Those are deliberate and documented at `:170-175`.
- Must stay within `Card.qml`. The repo has no behavioural QML tests, so a
  change here is verified by eye, and a small diff is what makes that
  honest.
- Proportionate: this is a layout bug on one line, not a redesign.

## Open questions

1. **Subtract the flags, or let a layout do the arithmetic?** Giving the
   `Repeater` a wrapping `Row` with an `id` and subtracting its width is
   small and keeps the current structure. Converting the whole row to a
   `RowLayout` with `Layout.fillWidth` removes the hand-maintained constant
   entirely and is the better end state, but it is a much larger diff in a
   file with no automated coverage.

2. **Is the clamp worth adding at all**, given the negative case is
   unreachable? It is one `Math.max(0, …)` and it stops the question being
   re-litigated the next time someone reads the expression -- but it also
   encodes a guard against something that cannot happen, which is its own
   small lie.
