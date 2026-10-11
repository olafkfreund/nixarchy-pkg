---
status: draft
issue: 55
intent: intent/2026-10-11-55-row-hierarchy-contrast.md
---

# Spec: Row hierarchy and light-theme contrast

Scope is the approved intent's items 1–5. Motion (hover state, cursor
fade, busy edge) and tab counts went to a follow-up at approval (#56), so the
intent's "the cursor and hover respond" outcome is **not** delivered here.

## Design

### 1. Dim by alpha, not by darkening

`Card.qml:18` becomes:

```qml
readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
```

The five `Qt.darker(Color.menu.text, 1.4–1.6)` sites in `OptionForm.qml`
(lines 359, 386, 412, 477, 560) get the same expression. A lower alpha
moves the text toward the surface behind it, whichever way the theme
runs, so secondary text is lighter than primary on both dark and light
themes. A single factor of 0.6 replaces the three slightly different
darkening factors. Nobody chose those differences, and they don't survive
the switch from darkening to alpha anyway.

### 2. Name weight

In the row delegate, the name `Text` (`Card.qml`, `id: name`) gets
`font.weight: Font.Medium`. Sizes don't change: name at
`Style.font.heading`, summary at `Style.font.title`, as now. That gives
two steps (weight, then size plus alpha), which is enough without adding a
third size the theme doesn't define.

### 3. Flags as pills

Each flag in the `flags` Repeater becomes a `Rectangle` holding the
existing `Text`:

- fill `Qt.rgba(tone.r, tone.g, tone.b, 0.15)`, text in `tone`;
- tone `Color.urgent` for `broken`, `Color.accent` for `unfree`, `dim`
  otherwise (the curated note), as now;
- `radius: Style.cornerRadius`, so a square-cornered theme gets square
  tags and nothing is rounded by us;
- padding `Style.space(6)` horizontally, `Style.space(2)` vertically.

The pill is still a child of `id: flags`, so the summary width keeps
subtracting `flags.width` as it does now. Padding changes how wide the
flags are, not how the width is calculated. The comment in `Card.qml`
about pills being "a second surface" gets one line added: flags are the
exception because they are warnings.

### 4. Icons on Apps and Services rows

On tabs 0 and 1 the state glyph column gets an `Image` beside it, with
`source: "image://icon/" + modelData.id`. That's Quickshell's icon
provider, the same thing `Quickshell.iconPath()` returns, so `Card.qml`
needs no new import and the test needs no new stub. The image is
`Style.font.heading` square and only visible at `status === Image.Ready`.
Its column is always reserved on those two tabs, so rows stay aligned
whether or not the theme has the icon. Selection, Options, Drafts and
Flakes rows draw no icon: an attribute path isn't an icon name.

The width this column takes is subtracted in the summary width
expression, as one more measured term (`icon.width` plus one gap when the
column is present), in the same way and for the same reason as #45.

### 5. Preview pane

The list gives up its right side to a pane that describes the row under
the cursor. Each row already carries what the pane needs:

| Row | Source | Already carried |
| --- | --- | --- |
| nixpkgs search (`kind: pkg`) | `preview` | version, licence, homepage, description |
| option search (`kind: opt`) | `preview` | type, default, documentation |
| app search (`kind: app`) | `preview` | label, category, module note |
| Apps / Services | `label`, `category`, `note`, `line` | composed in QML |
| Selection / Drafts / Flakes / option set rows | — | no pane |

`preview` is written by nixarchy's index builder for the fzf picker and is
already unescaped by `cmd_search` (`bin/nixarchy-pkg:269`). Today nothing
draws it, so this costs no adapter change and no process call per cursor
move.

The fzf text names fzf keys (`ctrl-t tries it now, without installing.`).
Those keys don't exist in this card, so lines starting with `ctrl-` are
dropped before drawing. Everything else is shown verbatim as
`Text.PlainText`, because it is external text.

Layout, in `Card.qml`:

- An `Item { id: preview }` anchored at `top: scope.bottom` and
  `bottom: footer.top` (the same as the list) and `right: parent.right`,
  with width `parent.width * 0.38`.
- The list's `right` anchors to `preview.left` when the pane shows, and to
  `parent.right` otherwise.
- The pane shows when the current row has text for it *and*
  `root.width >= Style.space(760)`. A narrow card keeps the full-width
  list.
- It has a 1px rule on its left in `dim` at the footer rule's 0.25
  opacity. That's the one divider the card already uses, so it adds no
  new surface.
- The text sits in a `Flickable`, so long option documentation scrolls
  instead of clipping. It's mouse-wheel only: the keyboard stays on the
  list.

None of this reads `contentHeight` back into the card's size, so the
binding-loop comment at `Card.qml:22` still holds.

## Alternatives rejected

- **Shrink the card to fit the list.** It solves the empty space but adds
  nothing to help choose a package, and a card that changes height while
  you type is worse to read than a fixed one.
- **Version as a column on the row.** It needs one more term in the summary
  width, the measurement that already took #45, #51 and #53 to get right.
  The pane shows the version with no width maths.
- **`Qt.darker` for dark themes and `Qt.lighter` for light themes,** picked
  by luminance. That's two code paths and a threshold to tune. Alpha does
  the right thing on both with one expression.
- **A contrast check like nixdatifier's `textOn()`.** The theme owns its
  colours, and alpha keeps whatever contrast the theme chose.
- **Icons from `.desktop` files via a new adapter field.** It's a process
  and a file walk. The icon provider already resolves names against the
  theme.
- **Pills for tabs too.** The intent kept tabs as an underline.

## Risks

- **Icon names don't match app ids.** For example, the `brave` id against
  the `brave-browser` icon. Those rows show no icon, so this is a
  cosmetic miss, not a failure. Expect a partial hit rate. The pane and the
  hierarchy carry the change without the icons.
- **Summary width.** Pill padding and the icon column change the inputs to
  the width expression that #45 and #53 fixed. `tst_card.qml` measures
  overflow at every flag count, and the plan extends it to the icon
  column.
- **The image provider is missing under `qmltestrunner`.** The `Image`
  goes to `Error` and stays invisible. The reserved column still has its
  width, so the geometry test still measures the real layout.
- **The light-theme fix is unverified on hardware.** The shell's themes
  aren't available under the test runner, so it gets checked once by eye
  on a light Omarchy theme (see Verification).
- **Changing the `preview` text format upstream** (the nixarchy index
  builder) would change what the pane shows. It draws plain text with no
  parsing except the `ctrl-` filter, so a format change degrades the text
  but breaks nothing.

## Verification

- `nix flake check` passes, which covers qmllint, shellcheck, the manifest
  check and the QML tests.
- `tst_card.qml`:
  - The summary still fits its row at 0, 1 and 2 flags, with pills.
  - The same check with the icon column present (an Apps-tab fake model).
  - The pane is hidden below the width threshold and on rows with no
    preview, and shown otherwise.
  - The pane's text contains no line starting with `ctrl-`.
- `dim` has alpha < 1 and the same RGB as `fg`. This is asserted on the
  property, not on a colour value, per #50.
- By eye in the running shell, on one dark and one light Omarchy theme:
  - secondary text is lighter than names;
  - pills read as warnings;
  - the pane fills the space under a short search.

  Then retake `docs/img/06-packages-search.png` and the screenshots of the
  other tabs this changes.
