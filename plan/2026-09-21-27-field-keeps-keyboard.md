---
status: approved
issue: 27
spec: spec/2026-09-21-27-field-keeps-keyboard.md
---

# Plan: one way to hand the keyboard back, used everywhere

## The approved decisions, in full

**Cause.** `keys` is a FocusScope, and `keys.forceActiveFocus()` gives
focus to its last focused child: the search field, or the hidden option
form. `open()` clears `search.focus` first; the other sites don't. The
hidden form keeps focus after `finish()` and its `Keys.onPressed` handles
ESC without checking `open`. That is why ESC died after a form while `l`
still worked.

**Fix.** One `focusList()` in `Menu.qml` (`search.focus = false;
form.focus = false; keys.forceActiveFocus()`), called from every site
that means "give the list the keyboard". The sites are `open()` (`:67`),
`onVisibleChanged` (`:103`, found while planning; same call, same
meaning), the ESC branch (`:171`), `onTabChanged` for non-Flakes tabs
(`:254`), the field handler (`:291`) and the form's `onClosed` (`:381`).
Flakes keeps `search.forceActiveFocus()`. The #3 focus model is unchanged.

**OptionForm.** `Keys.onPressed` returns when `!root.open`. `finish()`
clears focus on the scope, `textField` and `scaffoldField`. `seed()`'s
deferred focus does nothing if the form has closed.

**Key sheet.** While open: `j`/DOWN and `k`/UP scroll a line, PgDn/PgUp a
page, Home/End jump to the ends. Anything else closes it. It resets to the
top on open. The build log takes the same scroll keys; ESC still
detaches. Any scroll key pauses tail-follow, and End resumes it.

**`r`.** `r` with no modifier or SHIFT alone reindexes; Ctrl/Alt do not.
The copy says `r` (footer `Card.qml:327`, `bin/nixarchy-pkg-keys:55`).

**Two-press apply.** `a` arms; the footer says `a again to rebuild the
system — any other key cancels`. A second `a` within 5 s applies. Any
other key, or the timeout, disarms. SHIFT+A arms the terminal route the
same way (a second SHIFT+A). Auto-repeat never counts as the second
press. SPACE removal stays one press. This mirrors SHIFT+RETURN's
existing arming (`PkgModel.addFromOtherChannel`) and adds no dialog.

## Steps

1. **`Menu.qml`: add `focusList()`** next to `open()`, with a two-line
   comment pointing at `open()`'s explanation. Replace the
   `keys.forceActiveFocus()` calls at `:67`, `:103`, `:171`, `:254`
   (non-Flakes branch only), `:291` and `:381` with `focusList()`
   (keeping the existing `Qt.callLater` wrappers where present).
   -> verify by `grep -n "keys.forceActiveFocus" Menu.qml` → only inside
   `focusList()`.

2. **`OptionForm.qml`**: `Keys.onPressed` (`:207`) begins
   `if (!root.open) return`. `finish()` (`:114`) sets `textField.focus =
   false; scaffoldField.focus = false; root.focus = false` before
   `closed()`. `seed()`'s `Qt.callLater` body (`:144`) begins
   `if (!root.open) return`.
   -> verify by panel checks 2 and 4 below.

3. **Key sheet scrolling** (`Menu.qml:147-150` and the sheet Flickable at
   `:354`): give the Flickable an `id: keySheetView`. In the
   `keysOpen` branch, J/Down/K/Up/PageDown/PageUp/Home/End adjust
   `keySheetView.contentY`, clamped to
   `[0, contentHeight - height]`, and are accepted; any other key keeps
   today's close behaviour. Set `contentY = 0` where `keysOpen` becomes
   true (`:222`).
   -> verify by panel check 5.

4. **Build log scrolling** (`:152-158`, Flickable `logView` at `:313`):
   the same keys adjust `logView.contentY`. Add `property bool
   followTail: true`. The `onContentHeightChanged` tail-follow (`:323`)
   runs only while `followTail`; a scroll key sets it false, and End sets
   it true and jumps to the bottom. `apply()` resets it to true.
   -> verify by panel check 8.

5. **`r`** (`:239`): take `Qt.Key_R` out of the NoModifier switch and
   handle it before that block, like `?` is: `!search.activeFocus &&
   event.key === Qt.Key_R && (event.modifiers === Qt.NoModifier ||
   event.modifiers === Qt.ShiftModifier)` → `pkg.reindex()`.
   `Card.qml:327`: `"index stale — r to rebuild"`.
   -> verify by panel check 6.

6. **Two-press apply**, in `PkgModel.qml`:
   `property string armedApply: ""` (`""`, `"here"`, `"terminal"`) and a
   5 s single-shot `Timer` that clears it and `message`.
   `function armApply(kind)`: if `armedApply === kind` → clear, return
   true; else set it, set `message` to the prompt (`"a again to rebuild
   the system — any other key cancels"`, or the SHIFT+A variant), start
   the timer, return false. `disarm()` also clears `armedApply`.
   In `Menu.qml`: the SHIFT+A branch (`:215`) and `Key_A` (`:238`) call
   `pkg.armApply(...)` and act only on `true`; both ignore
   `event.isAutoRepeat`. At the top of the key handler, after the
   form/sheet/log early returns, any key other than `A` while
   `pkg.armedApply !== ""` calls `pkg.disarm()` (and is then handled
   normally).
   -> verify by panel check 7.

7. **`bin/nixarchy-pkg-keys`**: `a` → "Press twice: apply the queued
   changes and rebuild"; `SHIFT + A` → "Press twice: …in a terminal";
   `R` → `r  /  SHIFT + R`; under `?` add "j / k, PAGE UP / DOWN,
   HOME / END scroll this sheet and the build log".
   -> verify by `bin/nixarchy-pkg-keys --print` and `nix flake check`.

## Found while implementing

- **Step 6: a bare modifier does not disarm.** "Any other key cancels"
  would count SHIFT's own key-down, which arrives before the `A` of a
  second SHIFT+A, and cancel the terminal route every time. Shift, Ctrl,
  Alt, Meta and Super key-downs are ignored by the disarm check.
- **Step 7 reaches the manual.** `docs/manual/getting-started.md`,
  `applying.md` (two-press `a`), `troubleshooting.md` and `packages.md`
  (`R` → `r`) said the old keys.
- **Step 4 resets `followTail`** where `a` starts the apply in `Menu.qml`,
  since the log view lives there, not in `PkgModel.apply()`.

## Tests

    nix flake check
    bash tests/adapter.sh        # unchanged; must still pass
    nix build .#default && omarchy plugin validate ./result

Panel, by a person (or ai-mirror once it can type into layer surfaces):

1. Apps: `/ foot`, DOWN, SPACE → foot toggles (apps.nix changes); query
   stays `foot`.
2. `/ foot`, ESC → field empty; `l` → next tab; `?` → sheet.
3. Selection: `/ hello`, TAB → Options; `j` moves, doesn't type.
4. Options: open a form, ESC; type in the field, ESC → the field
   clears. Open a form, write a value, then `?` → sheet opens.
5. `?`, `j` ×20 → "While applying" visible; `x` → sheet closes; `?`
   again → back at the top.
6. `r` → reindex; SHIFT+R → reindex; CTRL+R → nothing.
7. `a` → footer prompt, nothing runs; `j` → disarmed. `a`, `a` → apply
   starts. Hold `a` → armed only. `a`, wait 6 s, `a` → armed again, not
   applied.
8. During an apply: `k` scrolls up and the tail stops following; End
   follows again; ESC detaches.

## Rollback

`git revert` the implementation commit: QML and the key sheet only, no
adapter or file-format change. Step 6 (two-press apply) is self-contained
and can be reverted alone if it proves unwelcome.
