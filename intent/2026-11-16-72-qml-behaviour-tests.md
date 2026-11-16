---
status: draft
issue: 72
author: olafkfreund
---

# Intent: behavioural tests for Menu, OptionForm and Panel

## Problem

`nix flake check` runs three QML test files through the `qml-tests` check
(`flake.nix:104-128`): `tst_card.qml`, `tst_pkgmodel.qml` and
`tst_optionform.qml`. The key handling, focus rules and form commit logic
that past defects lived in are mostly not covered. The issue text is out of
date in two places, so this states what is true on main (098ed16).

- `Menu.qml` has no test, and the harness cannot load it. It imports
  `Quickshell.Hyprland` and `Quickshell.Wayland` (`Menu.qml:4-5`) and builds a
  `PanelWindow` with `ExclusionMode` and the `WlrLayershell` attached
  properties (`Menu.qml:145-149`); `focusedScreen()` reads `Quickshell.screens`
  (`:36`), which the `Quickshell` stub lacks. The
  stubs under `tests/qml/imports` provide only `Quickshell`,
  `Quickshell.Io` and `qs.Commons` / `qs.Ui` (their `qmldir` files). So
  "against the existing inert stubs" does not hold for this file.
- What Menu does that is worth testing is in one handler,
  `Keys.onPressed` (`Menu.qml:193-355`): a key does nothing while the form is
  open (`:194`), the key sheet and detail view swallow keys (`:196-209`), the
  log view takes ESC and the scroll keys (`:210-221`), an armed apply is
  cancelled by any key except `A` and a bare modifier (`:225-231`), and only
  after the form, key sheet, detail and log branches have not taken the key, naming takes RETURN and ESC
  (`:235-245`), and `focusList()` decides who holds the keyboard (`:67-70`). The same
  rules also live outside that handler: the tab-dependent focus (`:366-370`),
  the search field's own `Keys.onPressed`, which forwards Tab, arrows, RETURN
  and ESC (`:385-409`), and the focus handed back when the log process closes
  (`:527`).
  #43 was in this kind of logic; nothing guards it.
- `OptionForm.qml` has a test file, but it holds two tests, both for #76
  (ESC after a failed describe; `tst_optionform.qml`). The issue says it has
  none. Not covered: untouched forms writing nothing (`nixValue()` returns ""
  while `touched` is false, `OptionForm.qml:244-251`, and `commit()` then just
  closes, `:282`); the verb, `replace` for a line that is already set or a
  scaffold and `set` otherwise (`:289`); the scaffold fallback when a held
  value does not fit the widget (`:217`); the refusals for read-only, an
  apply running and a write in progress (`:274-288`); and the form's own
  keys (`:301-324`).
- `Panel.qml` has no test, and the harness cannot load it either. It extends
  `BarWidget` and uses `BarIconButton` (`Panel.qml:27`, `:95`), host types
  that no stub defines (grep of `tests/qml/imports` finds neither). What it
  does: parse the `pending` answer into `queued`, `queueError` and
  `neverApplied` (`:47-68`), and word the tooltip and badge from them
  (`:102-109`, badge `:150`, `:171`). A left press starts the summon process,
  a middle press refreshes (`:111-114`).
- The comment above the check (`flake.nix:88-103`) still says Card is not
  covered. `tst_card.qml` is run (`flake.nix:116`) and has 30-odd tests. The
  comment is stale and would mislead whoever reads it for what is tested. It
  is not evidence for any constraint here.

Where `tst_card.qml` already reaches the model with real writes (#75), that
stays as it is.

## Proposed outcome

- A QML test for each of the three components that runs in the `qml-tests`
  check, fails on a regression in the behaviour listed above, and passes on
  main.
- Menu: the key rules in `Keys.onPressed`, the search field's key forwarding,
  and the focus rules (`focusList()`, tab-dependent focus, focus after the log
  closes) are asserted, including that an open form owns the keyboard and that the log
  view's ESC detaches without stopping the build.
- OptionForm: untouched writes nothing; touched writes with the right verb; a
  value that does not fit its widget opens the scaffold; the three refusals
  show their reason and write nothing; the form's keys do what the code says.
  The two #76 tests stay.
- Panel: each `pending` answer (ok with a total, ok:false, malformed text)
  gives the `queued`, `queueError` and tooltip text the code says, and the
  press buttons do what they say.
- The stale comment at `flake.nix:88-103` is brought in line with what the
  check now covers.
- Nothing in the shipped panel behaves differently.

## Affected users and systems

- Nobody on a running desktop. This adds tests and, at most, test stubs under
  `tests/qml/imports`.
- Files: new `tests/qml/tst_menu.qml` and `tests/qml/tst_panel.qml`; additions to
  `tests/qml/tst_optionform.qml`; `flake.nix` (the check and its comment);
  possibly new stub types under `tests/qml/imports`.
- The `qml-tests` check gets longer. It runs in a sandbox with no host shell,
  so a stub that is wrong passes in the sandbox and tells nothing about the
  real shell.

## Constraints

- `tst_optionform.qml` is extended, not replaced; the two #76 tests stay.
- Tests assert what the model, the form and the widget do, not how they
  draw. a measurement the harness cannot make faithfully is worse than none.
- The stubs stay inert: they spawn nothing and decide nothing, as
  `Process.qml` says. A test hands the component an answer or a death.
- No change to `Menu.qml`, `OptionForm.qml` or `Panel.qml` unless a test cannot
  be written without it. A change there is its own decision (see Open
  questions) and not made quietly.
- Each new test fails when the behaviour it names is broken. A test that
  passes against a deliberately broken copy proves nothing, so the spec says
  how each is checked.
- The check must still run in the Nix sandbox with only `qtdeclarative`.
- A live check, if one is wanted, is done in a `nixarchy-desktop` microVM: the
  owner's standing choice over razer.

## Open questions

1. How does Menu get loaded under test? (a) Add stubs for `Quickshell.Hyprland`,
   `Quickshell.Wayland`, `PanelWindow` and `WlrLayershell`, and load the real
   `Menu.qml`. (b) Test only the pieces that need no window, by loading
   `PkgModel` and `OptionForm` and leaving the key handler uncovered.
   Recommended: (a). The key handler is the part the issue names, and (b)
   leaves it out. The cost is real: `WlrLayershell` is an attached type that a plain QML
   stub cannot supply, so the mechanism (a C++ test plugin, a stub `Menu`
   wrapper, or a small change to `Menu.qml`) is for the spec to settle. Not
   a handful of types.
2. How does Panel get loaded? (a) Add inert `BarWidget` and `BarIconButton`
   stubs. (b) Skip Panel and say so. Recommended: (a), for the `pending`
   parsing and tooltip wording, which is real logic. The icon drawing stays
   unasserted.
3. Where does a test reach private state it needs (the key sheet, the log
   view, `describeProc`-style lookups)? (a) Through the item tree and
   `objectName`s that the QML already has or that tests find by type, as
   `tst_optionform.qml` does. (b) Add `objectName` properties to the
   components. Recommended: (a) first, and (b) only where (a) is not possible,
   each one named in the spec.
4. Should this be one change or three (one per component)? Recommended: one
   branch for OptionForm and Panel, and Menu as a separate branch if its
   stubs turn out large, so each PR reads on its own. The spec decides once
   the stub size is known.
