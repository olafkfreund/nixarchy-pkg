---
status: approved
issue: 45
intent: intent/2026-09-24-45-summary-width.md
---

# Spec: a row's summary elides where the row actually ends

## Design

Both of the intent's questions were decided here, not by the approver.

### The width comes from the children, not a constant

`Card.qml:205` becomes:

```qml
width: Math.max(0, parent.width - name.width - Style.font.heading
                   - flags.width
                   - Style.space(10) * (flags.visible ? 3 : 2))
```

with the flags `Repeater` (`:188`) wrapped in a `Row` that can be measured:

```qml
Row {
  id: flags
  anchors.verticalCenter: parent.verticalCenter
  spacing: Style.space(10)
  visible: (modelData.flags || []).length > 0
  Repeater { ... unchanged ... }
}
```

`visible` is load-bearing, not cosmetic: a `Row` ignores invisible children
when positioning, so with no flags the outer row is back to three children
and two gaps, and the `? 3 : 2` matches. Without it an empty wrapper would
still take a gap and the arithmetic would be wrong again in the other
direction.

**Decision (Q1): wrap only the flags, not the whole leading group.**

The obvious tidier move -- wrap glyph, name *and* flags in one `lead` Row
and write `parent.width - lead.width - Style.space(10)`, with no constants
at all -- **is a binding loop**. `name`'s width is
`Math.min(implicitWidth, parent.width * 0.42)` (`:173-175`); if `parent`
becomes an inner Row whose own width is the sum of its children, then
`name.width` depends on `lead.width` which depends on `name.width`. Qt would
report a loop and draw the row at whatever size it reached first -- the
same failure the comment at `Card.qml:25-29` records for `bodyHeight`. The
flags have no such self-reference, so wrapping them alone is safe.

**Decision: not `RowLayout`.** Converting the row and using
`Layout.fillWidth` on the summary removes the arithmetic entirely and is the
better end state. It also changes how all four children are positioned --
`anchors.verticalCenter` gives way to `Layout.alignment` -- in a file with
no behavioural tests, verified by eye, on a machine where the UI is awkward
to drive. The gain is elegance; the risk is a layout regression nobody would
catch. Recorded as the follow-up if this row is ever touched again.

**Decision (Q2): keep the clamp.** The intent asked whether
`Math.max(0, …)` guards a fiction. Under the *old* expression it did: the
negative case was only reachable on `kind` rows, which draw no summary.
Under the new one it is ordinary arithmetic on real inputs -- `name.width`
is still capped at `parent.width` on those rows (`:174`), so
`parent.width - name.width - …` is still negative there. The clamp now
guards a reachable value rather than an imagined one.

### What is deliberately not changed

The name's width cap, the row height, flag colours and rendering, and
`ListView.clip`. All are deliberate and documented; the defect is the
summary's width expression alone.

## Alternatives rejected

- **A `lead` Row around glyph, name and flags.** Cleanest arithmetic, and a
  binding loop through `name.width`. See above.
- **`RowLayout` + `Layout.fillWidth`.** The right end state, the wrong
  amount of risk for a row verified by eye.
- **Subtracting a bigger constant.** There is no correct constant: the
  current one is 20px too generous with no flags and too mean with any.
- **Leaving the clamp out.** One term, and the value is genuinely reachable.

## Risks

- **`flags.visible` and the `? 3 : 2` must agree.** They encode the same
  fact twice, and a future change to one without the other reintroduces the
  bug quietly. Mitigated by deriving both from the same `modelData.flags`
  and by a comment; not eliminated.
- **No automated coverage.** The QML layer has a syntax gate (#44) and no
  behavioural tests, so this is verified by eye. That is the argument for
  the smaller of the two designs.
- **Wrapping the Repeater adds a level of nesting**, so the flags' `parent`
  changes from the outer Row to the wrapper. Their only parent reference is
  `anchors.verticalCenter: parent.verticalCenter`, which stays correct
  against the wrapper -- checked, not assumed.
- **razer only** for anything live. Never p620.

## Verification

1. `nix flake check -L` passes, including `qml-syntax` (#44).
2. `qmllint` clean on `Card.qml`.
3. No binding-loop warning for `Card.qml` in the shell log after the plugin
   loads -- the specific failure the rejected design would have caused.
4. By eye on razer, against the screenshots taken for #38 as a before-image:
   - an Apps row with one flag (`unfree`) and a long summary ends in a
     visible ellipsis, not a word cut off at the list's edge;
   - a row with two or more flags likewise;
   - a row with no flags is unchanged or very slightly wider, and still
     elides;
   - a Flakes row -- `kind`-carrying, no summary -- draws its label as
     before, which is what the corrected reading of #45 predicts.
