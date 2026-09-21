---
status: approved
issue: 27
intent: intent/2026-09-21-27-field-keeps-keyboard.md
---

# Spec: one way to hand the keyboard back, used everywhere

Reviewed before writing by Codex (`gpt-6-astra`, read-only). It confirmed
the FocusScope diagnosis against Qt's documented focus model, and found a
better explanation for the ESC-after-form symptom, which is used below.

## Design

### 1. The cause, stated once

`keys` is a FocusScope. `keys.forceActiveFocus()` gives active focus to
the scope's **focused child**, not to the scope itself. After the search
field or the option form has held focus, that child is still the field or
the form, so calling `keys.forceActiveFocus()` gives the keyboard straight
back to them. `open()` knows this and clears `search.focus` first
(`Menu.qml:62-67`). Four other call sites do not:

| site | what it meant | what happens |
| --- | --- | --- |
| field handler, `Menu.qml:291` | DOWN/UP/RETURN/ESC hand the keyboard to the list | focus stays in the field |
| ESC clears the field, `:171` | the letters work again | they are still typed |
| `onTabChanged`, `:254` | list-owning tabs take the keyboard | the field keeps it after a search |
| form `onClosed`, `:381` | back to the list after a form | the **hidden form** keeps it |

The last one explains the second symptom (Codex). `OptionForm.finish()`
(`OptionForm.qml:114`) hides the form without clearing its focus. An
invisible Item can keep focus and still receive keys, and the form's
`Keys.onPressed` (`OptionForm.qml:207`) handles ESC without checking
`open`. So every ESC went to the hidden form and called `finish()` again,
while `l`, which the form doesn't handle, propagated up to the menu and
changed the tab. That's the sequence seen on razer.

### 2. The fix: one function, called from all of them

In `Menu.qml`:

    // FocusScope hands focus to its last focused child, so the child has
    // to let go first -- see open().
    function focusList() {
      search.focus = false
      form.focus = false
      keys.forceActiveFocus()
    }

`open()`, the field handler, the ESC branch, `onTabChanged` (non-Flakes)
and the form's `onClosed` all call it instead of `keys.forceActiveFocus()`.
One rule, stated in one place. The focus model is unchanged: #3's "focus
is a property of the tab" stays; this fixes how focus is **moved**.

In `OptionForm.qml`:

- `Keys.onPressed` returns at once when `!root.open`. A closed form
  handles nothing.
- `finish()` clears focus on the scope and on `textField` /
  `scaffoldField`.
- The deferred focus in `seed()` (`OptionForm.qml:144`, `Qt.callLater`)
  does nothing if the form has closed in the meantime. Otherwise a form
  closed quickly would grab the keyboard back after closing (Codex).

### 3. The key sheet scrolls

While `keysOpen`: `j`/DOWN and `k`/UP scroll one line, PgDn/PgUp a page,
Home/End to the ends. Any other key closes the sheet as it does today.
The Flickable resets to the top each time the sheet opens (intent Q2:
scroll rather than two columns; no column layout can guarantee a fit
across fonts, scale and screens).

The same keys scroll the **build log** while it is showing. ESC still
detaches (Codex: the log has the same gap).

### 4. `r` and `R`

`r` with no modifier or with SHIFT alone both reindex. Ctrl/Alt
combinations are not accepted. The copy says `r`: the footer
(`Card.qml:327`, "index stale — r to rebuild") and
`bin/nixarchy-pkg-keys`. Intent Q1: accept both, since that costs one
condition and makes the existing muscle memory right.

### 5. Applying takes two presses

Intent Q3, decided here for the approver to confirm or strike. `a` arms
and does not apply. The footer says `a again to rebuild the system — any
other key cancels`. A second `a` within 5 s applies; anything else, or the
timeout, disarms. SHIFT+A (apply in a terminal) arms the same way. A held
key's auto-repeat does not count as the second press
(`event.isAutoRepeat`).

It reuses the codebase's existing pattern: SHIFT+RETURN's two-press arming
on the other channel (`PkgModel.addFromOtherChannel`). It isn't a new
dialog.

SPACE on Selection/Options (remove a package or option) stays one press.
It only edits a file, is visible in the footer count, and is undone by
adding it again from search. A rebuild is none of those.

## Alternatives rejected

- **`focus: false` on the field without touching the form.** Fixes three
  of the four sites and leaves the ESC-after-form bug.
- **Replacing the FocusScope with a plain Item.** It would stop the
  last-child behaviour, but the scope is what makes `/` → field → list
  work at all. Bigger change, same result.
- **A confirmation dialog for apply.** A second surface and a second
  interaction model; two-press arming already exists here.
- **Two-column key sheet.** Can't guarantee a fit (see §3).

## Risks

- **Focus regressions on the Flakes tab**, where the field owns the
  keyboard by design. `onTabChanged` keeps `search.forceActiveFocus()`
  for Flakes. Only the non-Flakes branch changes.
- **The two-press apply is a behaviour change people will notice.** It is
  §5 alone and can be struck at approval without touching §1–4.
- The build log's new scroll keys must not break following the tail. Any
  scroll key pauses tail-follow; End resumes it.

## Verification

There is no QML test harness in this repo, so the checks are the panel on a
host, by a person or by ai-mirror once its layer-shell typing is fixed:

1. Apps: `/ foot`, DOWN, SPACE → foot toggles (file changes), query
   unchanged.
2. `/ foot`, ESC → field cleared; `l` → tab changes; `?` → sheet opens.
3. Selection: `/ hello`, TAB to Options → `j` moves the cursor, doesn't
   type.
4. Options: open a form, ESC; then ESC with text in the field → the field
   clears. Open a form, write a value; then `?` → sheet opens.
5. `?`, `j` ×20 → the sheet scrolls to "While applying"; `x` → closes.
6. SHIFT+R and `r` → reindex starts; CTRL+R → nothing.
7. `a` → footer asks to confirm, nothing runs; `j` → disarmed. `a`, `a` →
   the apply starts. Held `a` → one arm only.

Plus `nix flake check` (shellcheck on `bin/nixarchy-pkg-keys`) and
`omarchy plugin validate ./result`.
