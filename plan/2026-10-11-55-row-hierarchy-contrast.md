---
status: approved
issue: 55
spec: spec/2026-10-11-55-row-hierarchy-contrast.md
---

# Plan: Row hierarchy and light-theme contrast

## Approved decisions (from the spec)

- Secondary text is the foreground at alpha 0.6, never `Qt.darker`. One
  factor everywhere.
- Names are `Font.Medium`. Font sizes don't change.
- Flags become pills: the flag's tone at 0.15 alpha as the fill, text in
  the tone, `radius: Style.cornerRadius`. Tones stay as they are
  (`broken` → `Color.urgent`, `unfree` → `Color.accent`, otherwise dim).
- Icons only on Apps and Services (tabs 0 and 1), from
  `image://icon/<id>`. The column is reserved on those tabs, and the image
  is visible only when `Image.Ready`.
- A preview pane on the right, at 38% of the card's width. It draws the
  row's `preview` (search rows), or composes label, category, note and
  line (Apps/Services rows). It drops lines starting with `ctrl-`. It shows
  only when there is text and the card is `>= Style.space(760)` wide. It
  scrolls by mouse wheel only, and the keyboard stays on the list.
- No adapter change. No version column on rows. Motion and tab counts are
  in #56, not here.

## Repo traps (apply to every step)

- `nix flake check` greps for these, so don't introduce them:
  - **Font sizes:** every `font.pixelSize:` in `Card.qml`, `Menu.qml` and
    `OptionForm.qml` must be a bare `Style.font.<token>` on its own line.
    No arithmetic and no multipliers (`textScale`, `uiScale` and `px(` are
    banned).
  - **Colours:** no `"#rrggbb"` literals in any plugin QML. Colours come
    from `Color.*` or derive from it with `Qt.rgba(...)`.
- **The summary width in `Card.qml:227-229` is measured, term by term**
  (#45, #51, #53). Every new item in the row `Row` needs its own width and
  gap in that expression. Inside a `Row`, an invisible child takes no
  space and no gap, so the gap count must follow the same `visible`
  conditions.
- **`modelData` is shadowed** inside the flags `Repeater` (`Card.qml:194-196`).
  Bindings that need the *row* stay outside it.
- **Don't read `list.contentHeight` into the card's size**
  (`Card.qml:22-25`). It causes a binding loop.
- **Only `Card.qml` is copied into the QML test sandbox** (`flake.nix:104`).
  Card must not import anything the stubs in `tests/qml/imports` don't
  provide. `image://icon/` needs no import, so it is fine.
- Keep comment density and the `\u` escapes for glyphs, matching the file.

## Steps

1. **`Card.qml:18` and `OptionForm.qml:359,386,412,477,560`: dim by alpha.**
   - `Card.qml:18` becomes
     `readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)`, with a
     one-line comment explaining why (darkening inverts on light themes).
   - In `OptionForm.qml`, add the same `dim` property beside
     `fontFamily` at `OptionForm.qml:52`, and point the five `color:` lines at
     `root.dim`.
   - Verify: `grep -n "Qt.darker" Card.qml OptionForm.qml` prints nothing,
     and `nix flake check` passes.

2. **`Card.qml:165-217`: name weight and flag pills.**
   - Add `font.weight: Font.Medium` to `id: name` (`Card.qml:165-183`).
   - Replace the Repeater's `Text` delegate (`Card.qml:205-215`) with a
     `Rectangle` that:
     - keeps `required property string modelData`;
     - computes `readonly property color tone` with the existing ternary;
     - sets `color: Qt.rgba(tone.r, tone.g, tone.b, 0.15)` and
       `radius: Style.cornerRadius`;
     - has `width: tag.implicitWidth + Style.space(12)` and
       `height: tag.implicitHeight + Style.space(4)`;
     - is vertically centred, holding the old `Text` (`id: tag`) centred
       and coloured `tone`.
   - Add one line to the "a pill is a second surface" comment
     (`Card.qml:69-70`): flags are the exception, because they are warnings.
   - Verify: `nix flake check`. `tst_card` must still pass unchanged.

3. **`Card.qml:141-163,227-229`: icon column on Apps and Services.**
   - Add `readonly property bool showIcons: root.model && root.model.tab <= 1`
     on `root`.
   - After the state glyph `Text` (ending `Card.qml:163`), add
     `Image { id: icon }`:
     - `visible: root.showIcons`, vertically centred;
     - `width`/`height: Style.font.heading`, with `sourceSize` the same
       size;
     - `source: root.showIcons && modelData.id ? "image://icon/" + modelData.id : ""`;
     - `opacity: status === Image.Ready ? 1 : 0`, so the column stays
       reserved while the picture stays hidden;
     - `asynchronous: true`.
   - In the summary width (`Card.qml:227-229`), subtract
     `(icon.visible ? icon.width : 0)`. The gap count becomes
     `(flags.visible ? 3 : 2) + (icon.visible ? 1 : 0)`. Extend the #45
     comment to name the icon.
   - Verify: `nix flake check`. The existing fake model is `tab: 0`, so the
     existing overflow test now runs with the icon column.

4. **`Card.qml:104-110` and a new `Item` before the footer: preview pane.**
   - Add on `root`:
     - `readonly property var currentRow`, which is
       `list.currentItem ? list.currentItem.modelData : null`. A delegate's
       `required property var modelData` is readable from outside. If it
       isn't, read `root.model.rows()[root.model.cursor]` with bounds
       checks.
     - `readonly property string previewText`, built as:
       - if the row has a `preview` string, that string split on `"\n"`,
         filtered to drop lines whose trimmed start is `ctrl-`, then
         re-joined;
       - else, on tab 0 or 1, `[label, category, "", note, "", line]` with
         empty parts filtered out and joined by `"\n"`;
       - else `""`.
     - `readonly property bool showPreview`, which is
       `previewText.length > 0 && width >= Style.space(760)`.
   - Add `Item { id: preview }`:
     - anchored `top: scope.bottom` (topMargin `Style.space(10)`),
       `bottom: footer.top` (bottomMargin `Style.space(8)`) and
       `right: parent.right`;
     - `width: Math.round(parent.width * 0.38)` and
       `visible: root.showPreview`;
     - containing a 1px `Rectangle` rule on its left edge in `root.dim`
       at `opacity: 0.25`;
     - and a `Flickable`, inset `Style.space(14)` from the rule, with
       `clip: true`, `contentHeight` from the text, and
       `boundsBehavior: Flickable.StopAtBounds`. Inside it, a `Text` with:
       - `width` the Flickable's width, `wrapMode: Text.Wrap`,
         `textFormat: Text.PlainText`;
       - `font.family: root.fontFamily` and
         `font.pixelSize: Style.font.title`;
       - `color: root.fg`;
       - `text: root.previewText`.
     - The Flickable must never take focus: no `focus`, and no
       `activeFocusOnTab`.
   - Change the list's `right` anchor (`Card.qml:108`) to
     `root.showPreview ? preview.left : parent.right`, with
     `rightMargin: root.showPreview ? Style.space(14) : 0`.
   - Verify: `nix flake check`. Then the step 5 tests.

5. **`tests/qml/tst_card.qml`: tests for steps 1, 3 and 4.**
   - Make `fakeModel.tab` a property the tests can set (it is `tab: 0`
     now), and reset it in `init()`.
   - Add a `preview` field to the `steam` row, containing a
     `"ctrl-t tries it now"` line and a `"version:  1.0"` line.
   - New tests. Each one asserts a property, never a colour value or a
     formula (#50, #51):
     - `test_dim_is_fg_at_lower_alpha`: `card.dim` has the same r, g and b
       as `card.fg`, and `card.dim.a < 1`.
     - `test_summary_fits_with_and_without_icons`: run the existing
       overflow check at `tab: 0` and again at `tab: 2`.
     - `test_preview_shows_and_filters`: put the cursor on `steam`. The
       pane is visible, its text contains `version:`, and it does not
       contain `ctrl-`.
     - `test_preview_hidden_when_narrow`: set `win.width` to
       `Style.space(700)`, and the pane is not visible. Restore it
       afterwards.
     - `test_preview_hidden_without_text`: put the cursor on a row with no
       preview, at `tab: 2`. The pane is not visible.
   - Leave the `Window` and its comment exactly as they are (#51).
   - Verify: `nix flake check` passes with all old and new tests.

6. **By eye, then screenshots (done by the session model with the user,
   not the coder).**
   - Install the branch build and open the menu on one dark and one light
     Omarchy theme.
   - Check that dim text is lighter than names, pills read as warnings,
     the pane fills the space beside a short search, and Apps rows show
     icons where the theme has them.
   - Retake `docs/img/01-apps.png`, `03-services.png`,
     `05-packages-unfree.png`, `06-packages-search.png` and
     `07-options-search.png`. The README hero screenshot is
     `assets/screenshot.png`.
   - Verify: the screenshots are committed, and the PR description links
     the intent, spec and plan and says which steps the coder did.

## Tests

- `nix flake check`: all checks green (shellcheck, manifest, qml-syntax,
  qml-tests, no-text-multiplier, no-hardcoded-colours).
- `grep -n "Qt.darker" *.qml`: no output.
- Step 6 by eye on both themes.

## Rollback

All the changes are on `fix/55-row-hierarchy-contrast`, so revert the merge
commit. There's no data, config or adapter change, so a revert is
complete. `apps.nix` and `services.nix` aren't touched by any step.
