---
status: draft
issue: 72
intent: intent/2026-11-16-72-qml-behaviour-tests.md
---

# Spec: behavioural tests for Menu, OptionForm and Panel

## Design

This change adds tests and test stubs. `Menu.qml`, `OptionForm.qml`,
`Panel.qml`, `PkgModel.qml`, `Card.qml` and `bin/` do not change. In
`flake.nix` the `qml-tests` check gains two blocks and its comment is
rewritten. The intent's open questions were answered at the intent gate and
are decided below. What the intent left to the spec is under "Decisions for
the owner", and the loading mechanism for Menu was settled by experiment.

The intent was written against 098ed16. `main` is now 5a8ca0b (#64 2/3, #66,
#67 landed). `Menu.qml`, `OptionForm.qml`, `Panel.qml`, `flake.nix`,
`tests/qml/imports` and `tests/qml/tst_optionform.qml` are identical on both,
so every line number below holds. `PkgModel.qml`, `Card.qml`, `tst_card.qml`
and `tst_pkgmodel.qml` changed; Menu loads the real `PkgModel`, so the
experiments ran against main's. The branch must be rebased onto main before
the plan is executed.

### Decisions for the owner

1. **`WlrLayershell` in Menu: a guarded test-time edit of the copy, no change
   to `Menu.qml`.** `WlrLayershell.namespace/layer/keyboardFocus`
   (`Menu.qml:147-149`) are attached properties of a C++ type in the host.
   Experiment: with every other stub in place, the real `Menu.qml` fails to
   load with `Menu.qml:147,5: Non-existent attached object`, and no QML file
   can provide an attached type. So the check removes exactly those three
   lines from its copy, matched whole (`grep -Fxv` on the three lines), and
   fails if the source has other than 3 lines naming `WlrLayershell`, or the
   copy has any left. A fourth use, or one of the three given trailing
   content, fails the build (both tried; both fail). The three lines carry no
   logic, so what is lost is that they are not exercised. Rejected: a C++
   test plugin (needs a compiler and Qt headers; the intent says the check
   runs with only `qtdeclarative`), and moving the three lines into a new
   `LayerWindow.qml` that Menu instantiates and the tests replace (a
   shipped-file change for a test's benefit; the cleaner fidelity, which the
   owner may prefer, at the cost of one new file in the plugin).
2. **One branch and one PR, in two commits** (stubs, OptionForm and Panel
   tests; then Menu). The intent said to split if Menu's stubs turned out
   large. Measured: Menu's stubs are about 30 lines in 6 small files, Panel's
   21 in 2. One PR reads fine.
3. **Panel's badge is not asserted.** The `BarIconButton` stub does not
   instantiate `iconComponent`, so the mark, the badge visibility
   (`Panel.qml:150`) and its "?" text (`:171`) are not tested. The tooltip,
   `queued`, `queueError` and `neverApplied` carry the same logic and are
   asserted. Instantiating the icon needs `Image`, `MultiEffect`, `Screen`
   and the SVG in the sandbox, which is drawing, which the intent excludes.
4. **No test for a line that another line already covers.** Five handlers
   cannot fail today because a second piece of code does the same job:
   Tab and Backtab forwarded from the search field (`Menu.qml:389-390`: the
   key still reaches the list handler, which changes tab, and `onTabChanged`
   hands the keyboard over); `focusList()` after ESC clears the query
   (`:258`: the field's own ESC case, `:393-409`, has done it); the
   `callLater(focusList)` when the form closes (`:527`: `finish()` releases
   focus and the scope falls back to the list); ESC in the string field
   (`OptionForm.qml:462-467`) and in the scaffold editor (`:521-529`), which
   the form's own ESC case catches when the key propagates. Each was removed
   from a copy and every test still passed. The tests assert the end state
   (the list holds the keyboard; the form closes), which catches the cases
   where *all* of them break, and a wrong replacement of `:527` is caught
   (mutant M24). They do not claim to guard each redundant line. If the
   owner wants those lines gone, that is a separate change.
5. **The flake comment** (`flake.nix:92-103`) is rewritten to say what the
   check covers and does not (see "The check"). The text is mine.
6. **The live check is recommended before merge, not a landing condition.**
   The intent says "if one is wanted". The sandbox can pass while the real
   shell differs in the three host-type stubs and in the compositor's
   keyboard hand-off (Risks). One pass in a `nixarchy-desktop` microVM
   (below) closes that; the spec does not run it. The owner decides whether
   merge waits for it.

### Corrections to the intent

- Intent: "the focus handed back when the log process closes (`:527`)".
  `Menu.qml:527` is `OptionForm`'s `onClosed: Qt.callLater(root.focusList)`:
  the focus after the **form** closes. The log has no focus rule. The tests
  assert what `:527` does.
- Intent: the stale comment is `flake.nix:88-103`. It is `:92-103`; `:88-90`
  belong to the manifest check.

### How Menu loads (experiment)

Done in a mktemp copy with main's files, `qmltestrunner` from
`nixpkgs#qt6.qtdeclarative` (6.12.0 here, 6.11.2 in the flake's pin), env
scrubbed (`env -i`, `QT_QPA_PLATFORM=offscreen`, throwaway `HOME`). Nothing
outside the mktemp directory was read or written. The host shell exports
`NIXPKGS_QT6_QML_IMPORT_PATH`, which contains the real quickshell QML
directory; the sandbox does not, and the experiments unset it, so what loaded
is the stubs.

| Needed | Result |
|---|---|
| `Quickshell.Hyprland`, `Quickshell.Wayland` modules | A module whose `qmldir` lists no type is "not installed". One singleton each: `Hyprland` (`focusedMonitor: null`) and `WlrLayershell` (empty, so the module resolves). |
| `Quickshell.screens` (`Menu.qml:36`) | One property, `screens: []`, on the existing singleton stub. |
| `ExclusionMode.Ignore` (`:145`) | A QML property cannot start upper-case. A singleton with a QML `enum` (`enum Mode { Ignore, Normal, Auto }`) works. |
| `PanelWindow` as an `Item` | Fails: `Cannot override FINAL property` (`Item.anchors`). |
| `PanelWindow` as a `QtObject` | Works, with `default property alias data: content.data` onto an inner `Item` (`contentItem`, `visible: win.visible`), an `anchors` property typed by an inline `component Edges: QtObject { property bool top ... }` (untyped, it fails: `Cannot assign to non-existent property "right"`), and `visible`, `screen`, `color`, `exclusionMode`, with `width`/`height` read off `contentItem`. 16 lines. |
| `WlrLayershell.*` attached assignments | Does not load; decision 1. |
| `Border.controlSpec` | `OptionForm.qml:499` warns `controlSpec is not a function` once the form lives inside Menu. One line added to the `Border` stub. |
| Where the panel's items live | In `contentItem`, which no window owns. The test sets `panel.contentItem.parent = <TestCase>` and `anchors.fill`. |
| Visibility | The TestCase needs `visible: true`. Without it every item reads effective `visible === false` (the #51 trap) and visible-flickable lookups find nothing. A separate `Window`, as `tst_card.qml` uses, is wrong here: `keyClick` goes to the TestCase's own window (see the comment in `tst_optionform.qml`). |
| The search field | The existing `qs.Ui.TextField` stub is a bare `TextInput`. The test run was repeated with it replaced by `QtQuick.Controls.Basic.TextField` (in `qtdeclarative`, so available in the sandbox): same results, and the Tab-forwarding mutant is still equivalent. The inert stub stays; the Controls one is the fallback if a real-field difference ever shows. |

Result: the real, otherwise unmodified `Menu.qml` and the real `PkgModel`
load, take real key events through `keyClick`, and run their real focus
rules. The stub processes spawn nothing; the tests hand answers through
`pkg._reader.deliver(...)` as `tst_card.qml` does.

Reaching private state (open question 3): (a) holds, no `objectName` and no
change to any component. The tests find things by duck typing:

- `menu.data` holds the non-visual children: `pkg` is the one with `tabs` and
  `rowAt`; `panel` is the one with `contentItem`.
- `keys` is the `QQuickFocusScope` under `contentItem` with more than three
  children; `search` is the descendant with `placeholderText`; `form` the one
  with `begin` and `finish`; the log view the `Flickable` that declares
  `followTail` (a QML-declared type, distinct from the other two); the key
  sheet and the detail view are the visible plain `Flickable`s under `keys`
  (only one is visible at a time).

One `Menu` is built per test (`Component.createObject`) and destroyed after,
so no test inherits another's state. Tests enter through `menu.open("{}")`,
the entry the host uses.

### The tests

None can fail on main, because nothing in the shipped panel changes: they
describe it. "Fails first" is therefore shown the other way round, by
mutation: each rule is broken in a copy and the test that names it must go
red. The mutants and their results are measured (below) and the plan repeats
them as a step.

**`tests/qml/tst_menu.qml`** (19 tests; a state of three apps unless noted):

- the open form owns the keyboard: with `form.open`, Down, J, Right, `?` and
  SHIFT+A change no cursor, tab, key sheet or arming; ESC closes it and the
  list holds the keyboard (`:194`, `:527`).
- the key sheet: a scroll key keeps it open, any other key closes it, neither
  moves the cursor (`:195-200`); with long `keyText`, Down, Up, End and Home
  move its `contentY` and clamp it (`:77-92`).
- the detail view: a bare modifier and a scroll key keep it, another key
  clears `detailText` (`:202-209`); with long text, J, PageDown and Home scroll
  it and leave `detailText` and the cursor alone.
- the log view: it swallows the cursor keys; End sets `followTail`, Down clears
  it; ESC sets `logDetached`, leaves `applying` and `_apply.running` true and
  `showingLog` false (`:210-221`).
- an armed apply: SHIFT does not disarm, Down does, `a` confirms and the apply
  starts (`:225-231`, `:350-355`); and `/` and `?`, which do not move the
  cursor and so cannot disarm through `moveCursor()`, disarm both `armedApply`
  and `armingState === "reading"`.
- naming: Flakes puts the keyboard in the field (`:366-370`); RETURN with a
  write refused (`busy`) keeps the name in the field and stays naming; RETURN
  accepted clears the field and sends `flake add <name> <ref>`; ESC leaves
  naming and puts the flakeref back (`:234-244`).
- the search field: `/` takes the keyboard, `l` is typed and not read as a tab;
  Down, Up, RETURN and keypad Enter each hand the keyboard back and then act
  on the list (cursor moves; the toggle write starts) (`:385-409`).
- tab-dependent focus: Flakes puts the keyboard in the field, Apps in the list
  (`:366-370`, `:67-70`).
- the ESC ladder in full: a running check is cancelled first, then the
  inspection is cleared, then the field is cleared with the list holding the
  keyboard, then the menu closes (`:246-261`).
- `close()` while the form is open finishes the form (`:110`).
- reopening is fresh: after a tab change and a typed query, `close()` then
  `open("{}")` gives tab 0, an empty field, no key sheet, and the list holding
  the keyboard (`:48-59`).

**`tests/qml/tst_optionform.qml`** (11 added; the two #76 tests stay):
untouched writes nothing and closes (`:250`, `:282`); touched boolean writes
`set`; a held value writes `replace`; a scaffold line writes `replace`
(`:289`); a held value the widget cannot take (`lib.mkDefault 5` for an
integer) opens the scaffold with that text (`:217`); a held value that fits
stays on its widget; the three refusals each show their reason, keep the form
open and spawn no writer (`:277`, `:285`, `:286`); the enum's Down/J/K/Up wrap
and the chosen value is the one written (`:315-324`); a string is quoted,
escaped, `${` neutralised, already-quoted text passes through, empty writes
nothing (`:255-267`); in the string field RETURN writes and ESC closes with no
write (`:462-467`); in the scaffold plain RETURN is a newline and writes
nothing, CTRL+RETURN writes with `replace` (`:521-529`), ESC closes. The
harness gains a `writeProc()` finder next to `describeProc()`, and `init()`
resets `applying`, `busy` and the writer.

**`tests/qml/tst_panel.qml`** (10 tests): the unknown state and its tooltip;
`ok` with a total, plural and singular, with and without `neverApplied`
(`:55-57`, `:102-109`); zero; `ok` with no numeric total stays unknown;
`ok:false` with an error, with no error and with an empty one gets "could not
read the queue" (`:60`); malformed text (`:62-65`); a failure after a good
count forgets the count (`:59`, `:63`); recovery clears the error; a left
press starts the summon process only, a middle press refreshes only, a right
press does nothing (`:111-114`).

### The stubs (all under `tests/qml/imports`, all inert)

`Quickshell/Quickshell.qml` (+`screens`), `Quickshell/ExclusionMode.qml`,
`Quickshell/PanelWindow.qml`, `Quickshell/qmldir` (+2 lines),
`Quickshell/Hyprland/{qmldir,Hyprland.qml}`,
`Quickshell/Wayland/{qmldir,WlrLayershell.qml}`, `qs/Commons/Border.qml`
(+`controlSpec`), `qs/Ui/BarWidget.qml`, `qs/Ui/BarIconButton.qml`,
`qs/Ui/qmldir` (+2 lines). Each starts with a comment saying what it carries
and what it does not, as the existing ones do.

`BarWidget` and `BarIconButton` are shaped from how `Panel.qml` uses them
(`moduleName`, `bar`; `bar`, `text`, `tooltipText`, `foreground`,
`iconComponent`, and a `pressed(int buttonCode)` signal). The host's source is
not on this machine, so those shapes, and which module the host types live in,
are unverified against the real shell. This is the one place the sandbox can
pass and the shell differ; it is what the live check covers.

### The check (`flake.nix`)

Two blocks added after the OptionForm run and before `touch "$out"` (`:127`),
in the existing style: Panel, then Menu. The Menu block:

```sh
cp ${./Menu.qml} Menu.src
# WlrLayershell is an attached type of the host's C++ plugin and no QML file
# can stand in for one. Remove exactly its three known assignments, which
# carry no logic; any other use, or a changed line, fails here rather than
# passing unseen. (`! grep` would not: set -e ignores a negated command.)
[ "$(grep -c WlrLayershell Menu.src)" = 3 ]
grep -Fxv \
  -e '    WlrLayershell.namespace: "nixarchy-pkg-menu"' \
  -e '    WlrLayershell.layer: WlrLayer.Overlay' \
  -e '    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive' \
  Menu.src > Menu.qml
[ "$(grep -c WlrLayershell Menu.qml)" = 0 ]
cp ${./tests/qml/tst_menu.qml} tst_menu.qml
qmltestrunner -input tst_menu.qml -import "$PWD/imports" -import "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml"
```

The comment above the check (`:92-103`) is rewritten to say: qmllint proves
the files parse; these tests assert what PkgModel, Card, OptionForm, Panel and
Menu do through inert stubs; Menu runs with `PanelWindow` as plain items and
three layer-shell lines removed; the drawing, the host types' real behaviour
and the compositor are not covered. The sentence "Card is not covered" goes.

Measured, by building the flake's `qml-tests` check in a mktemp copy of main
with these changes: it passes (`qmltestrunner` totals, which include its init
and cleanup: Card 33, PkgModel 41, OptionForm 15, Panel 12, Menu 21). The new
runs take 0.9 s (Menu), 0.3 s (OptionForm, whole file) and 6 ms (Panel); the
existing Card run is 1.4 s. The derivation builds in about 8 s. The Menu file
ran 20 times in a scrubbed environment: 20 passes.

### Mutation results (measured)

Each mutant is one edit to a copy of the shipped file, run against the new
tests. Red means a named test fails.

- **Menu, 29 mutants, 26 red.** Red: delete `if (form.open) return`; key
  sheet never closes; key sheet or detail view never scrolls, or scrolls the
  wrong way; log ESC also stops the build; log ESC does not detach; a bare
  SHIFT disarms; `a` disarms; the disarm line removed; tab focus always goes
  to the list; `focusList()` forgets `search.focus = false`; naming ESC does
  not restore the flakeref; naming RETURN clears the field whether or not the
  declare started, or never clears it; `close()` leaves the form open; ESC
  never clears the field; the ladder skips the running check, or the
  inspection; the detail view closes on a modifier or on a scroll key; open
  does not reset the tab; Down, Up, RETURN or Enter not forwarded from the
  search field; form close hands the keyboard to the search field. Not red,
  and equivalent (decision 4): Tab/Backtab not forwarded from the field; no
  `focusList()` after the form closes; no `focusList()` after ESC clears the
  field.
- **OptionForm, 19 mutants, 17 red:** no `touched` guard; verb always `set`;
  verb ignores `scaffold`; unfit value does not open the scaffold; each of the
  three refusals removed; empty value does not close; enum does not wrap; SPACE
  does not mark `touched`; the quote pass-through removed; `${` not escaped;
  the read-only wording changed; ESC does not close (the two #76 tests);
  string RETURN does not write; scaffold plain RETURN writes; scaffold
  CTRL+RETURN does not write. Equivalent (decision 4): ESC removed from the
  string field; ESC removed from the scaffold editor.
- **Panel, 8 mutants, 8 red:** a non-number total accepted; the default error
  text removed; no plural; `neverApplied` ignored; left and middle swapped;
  the catch keeps the old count; `ok:false` keeps the old count; zero worded
  as a count.

Mutants that survived the first draft of the tests were fixed by a test, not
an exemption: `ok:false` with an empty error (the `or` default is otherwise
hidden by the `catch`, which produces the same text for `undefined`); a
failure after a good count (a fresh model is already `-1`); a scroll key
that does not scroll (empty sheet content); Down cancelling an armed apply
(`moveCursor()` disarms by itself, so only `/` or `?` isolate the handler's
own rule); a refused naming RETURN (the first attempt used `applying`, which
puts up the log view and swallows the key before naming sees it).

### Live check

In a `nixarchy-desktop` microVM, never razer. It exists to find drift in the
host stubs and the compositor hand-off, not to repeat the tests: summon the
menu with the keybind and confirm the keyboard is held (a letter does not
reach the window underneath), press Tab in the search field, open an option
form and press `j`, start an apply and press ESC (the build keeps running),
close and summon again (fresh), and look at the bar widget's tooltip with one
change queued and with the queue unreadable. Not run for this spec.

### Companion issues

One, in nixarchy, for the owner to file or drop: **"Give plugin test stubs a
checkable source for the shell's host types (BarWidget, BarIconButton,
PanelWindow)."** Plugins that run QML tests (this one; others in the fleet)
each hand-write inert stubs for `BarWidget`, `BarIconButton`, `PanelWindow` and
the `Quickshell.*` modules, from how their own code uses them, and nothing
tells them when the shell changes a property or a signal name. A derivation in
nixarchy that lists the host types' public properties and signals from the
omarchy-shell source it already pins would let each plugin diff its stubs
against it in its own check. Until then drift is only found by the live check
above. Not needed for this change to land.

## Alternatives rejected

- **Test only the pieces that need no window (intent option (b)).** Leaves
  `Keys.onPressed`, the part #43 and #27 lived in, uncovered.
- **A C++ plugin supplying `WlrLayershell`.** The only way to a faithful
  attached type; needs a compiler and Qt headers in the sandbox, against the
  constraint that the check run with only `qtdeclarative`.
- **Pointing the check at the real `quickshell` package.** It would load the
  real types, but `PanelWindow` needs a Wayland display, and the real shell is
  exactly what the sandbox is not.
- **`objectName`s on Menu's children (open question 3b).** Not needed: the
  duck-typed lookups find every part the tests use.
- **A `Window` wrapping the Menu test (as `tst_card.qml` does).** `keyClick`
  goes to the TestCase's own window, so keys would never arrive.
- **`! grep -q` as the guard.** Bash's `set -e` ignores a negated command, so
  it cannot fail the build. The guard counts instead.
- **Mutation testing in the check itself.** It would double the check's work
  to prove what a reviewer proves once; the plan runs the mutants by hand.

## Risks

- **A stub that is wrong passes here and tells nothing about the shell.** The
  intent names this. Mitigations: the stubs are shaped from the code under
  test, each says what it carries, and the live check is the audit.
- **A hidden menu still takes keys in the test.** An invisible item that holds
  active focus keeps receiving key events (the #27 behaviour), and the stub's
  `contentItem` is only hidden, not a closed window. In the shell the layer
  window is hidden or unmapped and gets no keys. The tests therefore do not
  assert that a closed menu is deaf; they assert that reopening resets it.
- **The `PanelWindow` stub has no counterpart in the shell.** Key delivery and
  focus inside the panel are the same QtQuick code; whether the compositor
  hands the layer window the keyboard (`keyboardFocus: Exclusive`) is exactly
  what is not tested. The live check is where that shows.
- **The guard couples the check to three lines of Menu's source.** If one is
  reworded, reindented or joined with another property, or a fourth
  `WlrLayershell` use is added, the check fails loudly and the owner updates
  the three patterns, which is the intent. A different layer-shell type would
  fail at load, also loudly.
- **Menu's tests depend on `PkgModel` internals** (`_reader`, `_writer`,
  `_apply`, `_check`, `armedApply`, `armingState`). `tst_card.qml` and
  `tst_pkgmodel.qml` already do. A rename there breaks the tests at the one
  assignment, which is the right place.
- **Focus tests depend on QtQuick's focus rules** under the offscreen
  platform; 20 consecutive passes in a scrubbed environment, and the tests
  `wait(30)` for the `Qt.callLater` the code uses and nothing longer.
- **Qt version.** The flake pins 6.11.2; the experiments ran 6.12.0 and the
  flake's own build ran 6.11.2. Both pass.

## Verification

- `nix flake check`: `qml-tests` passes with the new files; `shellcheck`,
  `manifest` and `qml-syntax` unchanged.
- The mutants above, each run against the new tests on a copy of the shipped
  file, red or documented as equivalent. The plan lists each edit.
- Both guard failures (a fourth `WlrLayershell` use; trailing content on one of
  the three lines) fail the build.
- `git diff main -- Menu.qml OptionForm.qml Panel.qml PkgModel.qml Card.qml
  bin/` is empty: nothing in the shipped panel changed.
- The live check above, in a `nixarchy-desktop` microVM, if the owner makes
  it a condition (decision 6).
