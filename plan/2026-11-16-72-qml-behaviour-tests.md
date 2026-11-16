---
status: approved
issue: 72
spec: spec/2026-11-16-72-qml-behaviour-tests.md
coders:
  1: codex   # copy-and-check of 14 small inert stub files; exact content is given, the qmldir and Border edits are the fiddly part
  2: codex   # OptionForm tests: 11 cases around Keys handlers and the scaffold editor, tricky focus and key-order logic
  3: codex   # Panel tests plus the first flake block and the comment rewrite: small, exact, shell-in-Nix quoting
  4: codex   # Menu tests (19 cases on private state, duck-typed lookups, wait(30) timing) plus the guarded flake block
reviewers:
  - codex   # QML focus and key-delivery semantics, and the shell guard in flake.nix, are where this goes wrong
  - agy     # independent read of the diff against this plan and the spec's test list
---

# Plan: behavioural tests for Menu, OptionForm and Panel

Owner direction: Codex implements every step that edits files (through
`agent-run codex`, which needs a clean worktree), so the lead commits after
each step. Steps and reviews not named here are the lead's. The lead's own
steps (0, 5, 6, 7) edit no file except `plan/` for a deviation.

## Decisions (from the approved intent and spec)

This change adds tests, test stubs and two blocks in `flake.nix`.
`Menu.qml`, `OptionForm.qml`, `Panel.qml`, `PkgModel.qml`, `Card.qml` and
`bin/` do not change. `git diff main -- Menu.qml OptionForm.qml Panel.qml
PkgModel.qml Card.qml bin/` must stay empty.

1. **`WlrLayershell` in Menu: a guarded test-time edit of the copy, no change
   to `Menu.qml`.** `Menu.qml` lines naming it are exactly three:
   `    WlrLayershell.namespace: "nixarchy-pkg-menu"`,
   `    WlrLayershell.layer: WlrLayer.Overlay`,
   `    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive`. No QML file
   can provide an attached type of the host's C++ plugin. The check removes
   those three lines from its copy with `grep -Fxv` and fails if the source
   has other than 3 lines naming `WlrLayershell`, or the copy has any left.
   Rejected: a C++ test plugin; a new `LayerWindow.qml` in the shipped plugin.
2. **One branch, one PR, two implementation commits:** commit A = stubs,
   OptionForm tests, Panel tests (steps 1-3); commit B = Menu tests
   (step 4). Codex needs a clean worktree, so the lead commits after each
   step; before the PR the lead squashes steps 1-3 into A (mandatory), so
   the history is exactly A and B after the plan, intent and spec commits.
3. **Panel's badge is not asserted.** The `BarIconButton` stub does not
   instantiate `iconComponent`. The tooltip, `queued`, `queueError` and
   `neverApplied` are asserted.
4. **No test for a line another line already covers.** Not tested on
   purpose, because each was removed from a copy and every test still
   passed: Tab/Backtab forwarded from the search field (Menu `case
   Qt.Key_Tab:` / `case Qt.Key_Backtab:`); `focusList()` after ESC clears
   the query (`if (!pkg.flakeTab) root.focusList()`); the
   `onClosed: Qt.callLater(root.focusList)` when the form closes; ESC in the
   string field and in the scaffold editor of OptionForm. The tests assert
   the end state (the list holds the keyboard; the form closes). Do not add
   tests for these lines and do not "fix" them.
5. **The flake comment above `qml-tests`** (the block that starts
   `# qmllint proves the QML parses.`) is rewritten to say what the check
   covers and does not (step 3).
6. **The live check** is recommended before merge, not a landing condition.
   It runs once in a `nixarchy-desktop` microVM, never razer (owner's
   standing choice), and only when the owner asks; the owner decides
   whether merge waits for it. Step 7 describes it.
7. **The stubs are inert and shaped from how the code uses them.** The
   host's source is not on this machine, so the shapes of `BarWidget`,
   `BarIconButton`, `PanelWindow` and which module the host types live in
   are unverified against the real shell. Only the live check covers that.
8. **Tests enter through `menu.open("{}")`, build one `Menu` per test with
   `Component.createObject`, destroy it after, and reach private state by
   duck typing** (no `objectName`, no change to any component):
   - `menu.data` holds the non-visual children: `pkg` has `tabs` and
     `rowAt`; `panel` has `contentItem`.
   - `keys` is the `QQuickFocusScope` under `contentItem` with more than
     three children; `search` is the descendant with `placeholderText`;
     `form` the one with `begin` and `finish`; the log view is the
     `Flickable` that declares `followTail`; the key sheet and detail view
     are the visible plain `Flickable`s under `keys`.
   - `panel.contentItem.parent` is set to the `TestCase` with
     `anchors.fill`, and the `TestCase` needs `visible: true`. A separate
     `Window` (as `tst_card.qml` uses) is wrong: `keyClick` goes to the
     TestCase's own window.
   - Answers are handed through `pkg._reader.deliver(...)` and
     `pkg._writer.deliver(...)`, never `finish()` first.

## Source of the files

The spec's agent left tested candidates in
`/tmp/claude-1000/-mnt-code-Source-home-GitHub-nixarchy-pkg/116b433b-0f15-4334-9947-da57e2715894/scratchpad/wf/q72/`.
Call it `$CAND`. `$CAND/tests-final/qml/` mirrors `tests/qml/` and
`$CAND/flake.nix.final` is the finished `flake.nix`. Step 0 checks them
against the sha256 prefixes below. The files are pre-written; each step
copies its files from there (read-only access to `$CAND`; never write
there) and then makes its checks pass. Prefixes (first 12 hex of sha256):

| file under `tests/qml/` | prefix |
|---|---|
| `imports/qs/Commons/Border.qml` | f676e41b5f91 |
| `imports/qs/Ui/BarIconButton.qml` | f6367e050aa8 |
| `imports/qs/Ui/BarWidget.qml` | 0bb5bc9ef36f |
| `imports/qs/Ui/qmldir` | 3b0db35fd65e |
| `imports/Quickshell/ExclusionMode.qml` | e6bbb5ce2b22 |
| `imports/Quickshell/Hyprland/Hyprland.qml` | 07f641b1204e |
| `imports/Quickshell/Hyprland/qmldir` | aca138487f11 |
| `imports/Quickshell/PanelWindow.qml` | 5d36573cd607 |
| `imports/Quickshell/qmldir` | 21280d67e69b |
| `imports/Quickshell/Quickshell.qml` | 1343886201c4 |
| `imports/Quickshell/Wayland/qmldir` | 8bb8eff2d6ff |
| `imports/Quickshell/Wayland/WlrLayershell.qml` | 8690c2cef027 |
| `tst_optionform.qml` | 9e5acd0e3a20 |
| `tst_panel.qml` | 1838d4e4edae |
| `tst_menu.qml` | eaba9fd09623 |
| `flake.nix.final` (not under tests/) | 4f128e58c1aa |

`tst_card.qml`, `tst_pkgmodel.qml` and `tests/adapter.sh` in `$CAND` are
identical to the worktree's and are not copied. If `$CAND` is gone or a
prefix differs, stop and report; do not rewrite the tests from the spec
without the lead. (The spec's "The tests" section lists every case: 19 in
`tst_menu.qml`, 11 added to `tst_optionform.qml`, 10 in `tst_panel.qml`.)

## Test runner (used by every step)

QML tests must run from a flake-style copy: running `-input` inside
`tests/qml` fails with "Card is not a type" because the components are not
beside the test. Nothing is written to `/tmp` except through `mktemp`.

```bash
QT=$(nix eval --raw nixpkgs#qt6.qtdeclarative.outPath)
run_qml() {   # usage: run_qml tst_x [tst_y ...]   (from the worktree root)
  local d; d=$(mktemp -d) || return 1
  cp Card.qml PkgModel.qml OptionForm.qml Panel.qml "$d"
  cp -r tests/qml/imports "$d"
  # the Menu copy, as the flake builds it (step 4 explains the guard)
  cp Menu.qml "$d/Menu.src"
  grep -Fxv \
    -e '    WlrLayershell.namespace: "nixarchy-pkg-menu"' \
    -e '    WlrLayershell.layer: WlrLayer.Overlay' \
    -e '    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive' \
    "$d/Menu.src" > "$d/Menu.qml"
  local t rc=0
  for t in "$@"; do
    cp "tests/qml/$t.qml" "$d/$t.qml"
    ( cd "$d" && env -u NIXPKGS_QT6_QML_IMPORT_PATH QT_QPA_PLATFORM=offscreen HOME="$d" \
        "$QT/bin/qmltestrunner" -input "$t.qml" -import "$d/imports" -import "$QT/lib/qt-6/qml" ) || rc=1
  done
  rm -rf "$d"
  return $rc
}
```

`NIXPKGS_QT6_QML_IMPORT_PATH` is unset because the host shell exports the
real quickshell QML directory, which would let real types load instead of
the stubs. The subshell `cd` keeps the caller in the worktree.
`qmltestrunner` exits non-zero on a failure; `run_qml` returns non-zero.

## Steps

### 0. Lead: preconditions

- `git status` is clean (only `plan/` may be new) and current `main` is an
  ancestor of `HEAD`. Main has moved past 5a8ca0b: it is at 79bf9f7 or later
  and has an `adapter` flake check that `$CAND/flake.nix.final` lacks. Run
  `git rebase main`, keep every check main has, and re-find anchors by their
  quoted text (line numbers drift). `Menu.qml`, `OptionForm.qml`,
  `Panel.qml` and `tests/qml/` are unchanged by that move (verify with
  `git diff 5a8ca0b main -- Menu.qml OptionForm.qml Panel.qml tests/qml`;
  if not empty, stop and tell the owner).
- Check the sha256 prefixes of `$CAND` against the table
  (`sha256sum "$f" | cut -c1-12`).
- New files are invisible to a Git flake until tracked: before any `nix
  eval` or `nix build` on `.#`, the lead runs `git add -N <new files>`
  (intent-to-add; not a commit) or uses `path:$PWD#...`.
- Run the baseline: `run_qml tst_card tst_pkgmodel tst_optionform` passes
  (on main: Card 33, PkgModel 41, OptionForm 4; record the totals) before
  anything is added.
- Commit this plan as a draft (`docs(plan): ...`); after approval, flip it
  to approved in its own commit (`docs(plan): approve <slug> (#72)`), then
  start step 1. No implementation edit before that commit.

### 1. Stubs: `tests/qml/imports/` -- codex

Create or replace exactly these files by copying from
`$CAND/tests-final/qml/imports/` (same relative path under
`tests/qml/imports/`). Create:
`Quickshell/ExclusionMode.qml`, `Quickshell/PanelWindow.qml`,
`Quickshell/Hyprland/qmldir`, `Quickshell/Hyprland/Hyprland.qml`,
`Quickshell/Wayland/qmldir`, `Quickshell/Wayland/WlrLayershell.qml`,
`qs/Ui/BarWidget.qml`, `qs/Ui/BarIconButton.qml`. Replace:
`Quickshell/Quickshell.qml` (adds `property var screens: []` to the
singleton), `Quickshell/qmldir` (adds the `ExclusionMode` singleton and the
`PanelWindow` type), `qs/Ui/qmldir` (adds `BarWidget` and `BarIconButton`),
`qs/Commons/Border.qml` (adds
`function controlSpec(a, b, c) { return ({}) }` after `surfaceSpec`). Do not
touch the other stub files.

Content that must hold (the copies already do; verify):
- `Quickshell/Hyprland/Hyprland.qml` and `Wayland/WlrLayershell.qml` are
  `pragma Singleton` and listed in their `qmldir` as `singleton`. A module
  whose `qmldir` lists no type is "not installed" and fails to load. Hyprland
  has `property var focusedMonitor: null`; WlrLayershell is empty.
- `Quickshell/ExclusionMode.qml`: a `pragma Singleton` `QtObject` with
  `enum Mode { Ignore, Normal, Auto }` (a QML property cannot start
  upper-case, so `ExclusionMode.Ignore` needs an enum).
- `Quickshell/PanelWindow.qml`: a `QtObject`, not an `Item` (an `Item` fails
  with `Cannot override FINAL property` on `anchors`), with
  `default property alias data: content.data` onto an inner `Item` exposed as
  `contentItem` (`visible: win.visible`), `anchors` typed by an inline
  `component Edges: QtObject { property bool top ... }` (an untyped one fails
  with `Cannot assign to non-existent property "right"`), and `visible`,
  `screen`, `color`, `exclusionMode`, `width`/`height` read off
  `contentItem`. About 16 lines.
- `qs/Ui/BarWidget.qml` has `moduleName` and `bar`; `BarIconButton.qml` has
  `bar`, `text`, `tooltipText`, `foreground`, `iconComponent` and
  `signal pressed(int buttonCode)`. `iconComponent` is never instantiated
  (decision 3).
- Every new or changed stub carries a comment saying what it carries and
  what it does not, as the existing stubs do. The candidates have none, so
  after copying add it: `//` lines under the `import`/`pragma` lines in a
  `.qml` stub (`pragma Singleton` must stay first), `#` lines under the
  `module` line in a `qmldir`. The table's hashes are of the candidates as
  they are, so the check below compares with comment lines removed.
- `TextField.qml` stays the inert `TextInput` stub. The
  `QtQuick.Controls.Basic.TextField` variant is the fallback only if a real
  field difference ever shows; do not switch.

→ **Check:** `git status --short` lists only the paths above, all under
`tests/qml/imports/`; for each of the 12 files `f` (the table's
`imports/...` rows), `grep -vE '^[[:space:]]*(//|#)' "tests/qml/$f" | sha256sum`
equals the same command on `$CAND/tests-final/qml/$f`, and each file has at
least one comment line; `run_qml tst_card tst_pkgmodel
tst_optionform` still passes with the same totals as step 0 (the stubs must
not change any existing test); `qmllint` is not required here.

Traps: nothing outside `tests/qml/imports/` changes; no stub spawns a
process or decides anything; do not edit the shipped `.qml` files; nothing
written to `/tmp` except through `mktemp`; the Process stub order
(`deliver()` answers, `finish()` is a death) is unchanged.

**Lead after step 1:** review the diff, run the check, commit
(`test(stubs): inert Quickshell, Hyprland, Wayland and Bar stubs (#72)`).

### 2. OptionForm tests: `tests/qml/tst_optionform.qml` -- codex

Replace `tests/qml/tst_optionform.qml` with
`$CAND/tests-final/qml/tst_optionform.qml` (sha prefix 9e5acd0e3a20). It keeps
the two #76 tests and adds 11 (the existing file is the base; the diff must
only add lines except for the harness changes below). Required content, in
case the copy needs repair:

- the harness gains `writeProc()` beside `describeProc()` and `init()` resets
  `applying`, `busy` and the writer;
- 11 tests: untouched writes nothing and closes (`if (!touched) return ""`);
  touched boolean writes `set`; a held value writes `replace`
  (`var verb = (current.state === "set" || current.state === "scaffold") ?
  "replace" : "set"`); a scaffold line writes `replace`; a held value the
  widget cannot take (`lib.mkDefault 5` for an integer) opens the scaffold
  with that text (`if (!held) { forceScaffold = true; scaffoldField.text = v }`);
  a held value that fits stays on its widget; the three refusals (the
  `readOnly === true` one, `an apply is running`, `still writing`) each show
  their reason, keep the form open and spawn no writer; the enum's
  Down/J/K/Up wrap and the chosen value is the one written; a string is
  quoted, escaped, `${` neutralised (`.replace(/\$\{/g, "\\${")`),
  already-quoted text passes through, empty writes nothing; in the string
  field RETURN writes and ESC closes with no write; in the scaffold plain
  RETURN is a newline and writes nothing, CTRL+RETURN writes with `replace`,
  ESC closes.

→ **Check:** `run_qml tst_optionform` passes; the totals are the old 4
plus the 11 added (15, measured with the candidate files; record any
difference and say why). `git diff main -- OptionForm.qml` is empty. Run
three times for stability: `(for i in 1 2 3; do run_qml tst_optionform ||
exit 1; done)`.

Traps: tests only, no shipped file; one JSON answer on every path does not
apply here, but the stub `deliver()`/`finish()` order does: a write leaves
`busy` true until `deliver()`; never `finish()` first. `keyClick` goes to the
TestCase's own window (see the existing comment in the file); do not wrap in
a `Window`. Never assert on a closed form's focus.

**Lead after step 2:** review, run, commit
(`test(optionform): behaviour tests for writes, refusals, enum and fields (#72)`).

### 3. Panel tests, first flake block and comment: `tests/qml/tst_panel.qml`, `flake.nix` -- codex

(a) Create `tests/qml/tst_panel.qml` from
`$CAND/tests-final/qml/tst_panel.qml` (sha prefix 1838d4e4edae): 10 tests:
the unknown state and its tooltip; `ok` with a total, plural and singular,
with and without `neverApplied`; zero; `ok` with no numeric total stays
unknown (`typeof data.total === "number"`); `ok:false` with an error, with
none and with an empty one gets "could not read the queue"
(`data.error || "could not read the queue"`); malformed text (the `catch`);
a failure after a good count forgets the count; recovery clears the error; a
left press starts the summon process only, a middle press refreshes only, a
right press does nothing (`onPressed: function (buttonCode)`).

Required addition to the candidate: in `test_not_ok`, also deliver
`{ ok: false }` (no `error` key at all) and assert `queueError` is "could
not read the queue" (the spec lists "with an error, with no error and with
an empty one"; the candidate lacks the omitted case). Totals unchanged.

(b) `flake.nix`, in the `qml-tests` derivation. Find
`qmltestrunner -input tst_optionform.qml \` and the three lines after it
(`-import "$PWD/imports" \`, `-import "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml"`),
then `touch "$out"`. Insert, after that qmltestrunner command and before
`touch "$out"`, exactly (same 16-space indent as the neighbours):

```sh
cp ${./Panel.qml} Panel.qml
cp ${./tests/qml/tst_panel.qml} tst_panel.qml
qmltestrunner -input tst_panel.qml \
  -import "$PWD/imports" \
  -import "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml"
```

(c) Rewrite the comment above `qml-tests` (from `# qmllint proves the QML
parses.` to the line before `qml-tests =`) to say: qmllint proves the files
parse; these tests assert what PkgModel, Card, OptionForm, Panel and Menu
do, through inert stubs that spawn nothing and decide nothing (the tests
hand a canned answer or a death); Menu runs with `PanelWindow` as plain
items and three layer-shell lines removed; what is not covered is the
drawing, the host types' real behaviour and the compositor. Keep the #43 and
#50 history sentence. Delete the sentence `Card is not covered`. Keep every
line of the comment at most 72 columns.

→ **Check:** `run_qml tst_panel` passes (12 per the spec's count with
init/cleanup); `git diff main -- Panel.qml` is empty; `git add -N tests/qml/tst_panel.qml` then `nix eval
.#checks.x86_64-linux.qml-tests.drvPath` evaluates (the flake still parses);
`! grep -q "Card is not covered" flake.nix` run in an interactive shell
without `set -e` (or `[ "$(grep -c 'Card is not covered' flake.nix)" = 0 ]`).

Traps: the new block is shell inside a Nix `''` string: `${./x}` and
`${pkgs...}` are Nix interpolation and must stay; any `$VAR` the shell must
see is `$VAR`, and `''${` would be needed only for a literal `${` (none
here). Under `set -e` a failing `qmltestrunner` fails the build, so each
runner command stands alone and is not negated, piped or followed by `||`.
Do not put `| head` or a pipe in the block (SIGPIPE under pipefail). Nothing
is written to `/tmp`; the sandbox has only `$PWD`. Do not touch the other
checks (`shellcheck`, `manifest`, `qml-syntax`).

**Lead after step 3:** review, run, commit
(`test(panel): queue badge state and press routing; flake runs them (#72)`).
This ends commit A.

### 4. Menu tests and the guarded flake block: `tests/qml/tst_menu.qml`, `flake.nix` -- codex

(a) Create `tests/qml/tst_menu.qml` from
`$CAND/tests-final/qml/tst_menu.qml` (sha prefix eaba9fd09623), then make
two additions the candidate lacks. First, a `cleanup()` that does what
`fresh()` does at its start for the previous instance
(`panel.contentItem.parent = null; menu.destroy()`, then clears `menu`,
`pkg`, `panel`, `keys`, `search`, `form`), so each test destroys its Menu
after itself (decision 8); keep the guard in `fresh()` so a test that never
built a menu still works. Second, in the search-field RETURN test, after the
keyboard check, assert that RETURN acted on the list: the spec says each of
Down, Up, RETURN and keypad Enter hands the keyboard back "and then acts on
the list" (cursor moves; the toggle write starts), and the candidate checks
focus only for RETURN. The totals must stay 21 (qmltestrunner counts `cleanup`
once, as `init` and `cleanup` are already in the 21; if it counts differently,
record the new total). The 19 tests, on a state of three apps unless noted:

- the open form owns the keyboard: Down, J, Right, `?` and SHIFT+A change no
  cursor, tab, key sheet or arming; ESC closes it and the list holds the
  keyboard (`if (form.open) return` ...);
- the key sheet: a scroll key keeps it open, any other key closes it, neither
  moves the cursor; with long `keyText`, Down, Up, End and Home move its
  `contentY` and clamp it (`function scrollView(view, key)`);
- the detail view: a bare modifier and a scroll key keep it, another key
  clears `detailText`; with long text, J, PageDown and Home scroll it and
  leave `detailText` and the cursor alone;
- the log view: it swallows the cursor keys; End sets `followTail`, Down
  clears it; ESC sets `logDetached` and leaves `applying` and
  `_apply.running` true and `showingLog` false;
- an armed apply: SHIFT does not disarm, Down does, `a` confirms and the
  apply starts; `/` and `?` disarm both `armedApply` and
  `armingState === "reading"`;
- naming: Flakes puts the keyboard in the field; RETURN with a write refused
  (`busy`) keeps the name in the field and stays naming; RETURN accepted
  clears the field and sends `flake add <name> <ref>`; ESC leaves naming and
  puts the flakeref back;
- the search field: `/` takes the keyboard, `l` is typed and not read as a
  tab; Down, Up, RETURN and keypad Enter each hand the keyboard back and then
  act on the list;
- tab-dependent focus: Flakes puts the keyboard in the field, Apps in the
  list;
- the ESC ladder: a running check is cancelled first, then the inspection is
  cleared, then the field is cleared with the list holding the keyboard, then
  the menu closes;
- `close()` while the form is open finishes the form (`if (form.open)
  form.finish()`);
- reopening is fresh: after a tab change and a typed query, `close()` then
  `open("{}")` gives tab 0, an empty field, no key sheet, and the list
  holding the keyboard.

(b) `flake.nix`: after the Panel block added in step 3 and before
`touch "$out"`, insert exactly:

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
qmltestrunner -input tst_menu.qml \
  -import "$PWD/imports" \
  -import "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml"
```

`$CAND/flake.nix.final` (prefix 4f128e58c1aa) is the finished `flake.nix`
on the old main. After the rebase it lacks main's `adapter` check, so do not
copy it over. Instead `diff flake.nix $CAND/flake.nix.final` shows only
(i) main's own newer checks and (ii) the comment text, and nothing inside the
`qml-tests` derivation; the lead reviews the comment.

→ **Check:** `run_qml tst_menu` passes (21 per the spec's count) and 5 times
in a row (`(for i in 1 2 3 4 5; do run_qml tst_menu || exit 1; done)`);
`git diff main -- Menu.qml` is empty;
`git add -N tests/qml/tst_menu.qml` (the lead does this), then
`nix build .#checks.x86_64-linux.qml-tests --no-link` passes (the derivation
takes about 8 s of its own, plus the runs); then
`nix flake check` passes with `shellcheck`, `manifest` and `qml-syntax`
unchanged.

Traps:
- `grep -c` exits 1 when the count is 0 but `[ "$(grep -c ...)" = 0 ]` runs
  inside `$(...)` whose failure the `[` ignores; that is why the guard
  compares text. Do not "simplify" to `! grep`, `grep -q`, `|| true`, or a
  pipeline: `set -e` ignores a negated command and a pipe hides the first
  failure.
- `grep -Fxv` matches whole lines literally; the three patterns include the
  four leading spaces. If `Menu.qml` is edited in future, the check fails
  loudly. That is the intent.
- Stub `Process`: `deliver()` answers, `finish()` is a death; never call
  `finish()` first. The tests hand answers with `pkg._reader.deliver(...)`.
- The TestCase must be `visible: true`, or every item reads effective
  `visible === false` (the #51 trap) and visible-flickable lookups find
  nothing. `wait(30)` is the longest wait, for `Qt.callLater`.
- A hidden menu still takes keys in the test (an invisible item holding
  active focus still gets them); tests must not assert a closed menu is
  deaf, only that reopening resets it.
- `NIXPKGS_QT6_QML_IMPORT_PATH` unset (the sandbox does not have it; the
  host does, and it contains the real quickshell QML directory).

**Lead after step 4:** review, run, commit
(`test(menu): behaviour tests for keys, focus, naming, ESC ladder; flake runs them (#72)`).
This is commit B.

### 5. Lead: mutation, guard failures, scope -- no file edits in the tree

Each mutant is ONE edit to a copy, never the worktree: `d=$(mktemp -d)`;
copy as `run_qml` does but mutate `$d/<File>.qml` with `sed`/an editor, run
`qmltestrunner` for the named test file in `$d`, expect red, `rm -rf "$d"`.
`git status` stays clean throughout.

- **Menu (tst_menu), 29 mutants, 26 must be red.** Red: delete `if
  (form.open) return`; the key sheet never closes; the key sheet or detail
  view never scrolls, or scrolls the wrong way (`scrollView`); log ESC also
  stops the build; log ESC does not detach; a bare SHIFT disarms; `a`
  disarms; the disarm line removed; tab focus always goes to the list (the
  `Connections` that ends `else root.focusList()`); `focusList()` forgets
  `search.focus = false`; naming ESC does not restore the flakeref; naming
  RETURN clears the field whether or not the declare started, or never
  clears it; `close()` leaves the form open; ESC never clears the field; the
  ladder skips the running check, or the inspection; the detail view closes
  on a modifier or on a scroll key; `open` does not reset the tab; Down, Up,
  RETURN or Enter not forwarded from the search field; form close hands the
  keyboard to the search field. **Must stay green (equivalent, decision 4):**
  Tab/Backtab not forwarded from the field; no `focusList()` after the form
  closes (`onClosed: Qt.callLater(root.focusList)`); no `focusList()` after
  ESC clears the field (`if (!pkg.flakeTab) root.focusList()`). Also M24: a
  wrong replacement of `onClosed: Qt.callLater(root.focusList)` (for
  example `Qt.callLater(function () { search.forceActiveFocus() })`) is red.
- **OptionForm (tst_optionform), 19 mutants, 17 red:** no `touched` guard;
  verb always `set`; verb ignores `scaffold`; unfit value does not open the
  scaffold; each of the three refusals removed; empty value does not close;
  enum does not wrap; SPACE does not mark `touched`; the quote
  pass-through removed; `${` not escaped; the read-only wording changed; ESC
  does not close the form; string RETURN does not write; scaffold plain
  RETURN writes; scaffold CTRL+RETURN does not write. **Green (equivalent):**
  ESC removed from the string field; ESC removed from the scaffold editor.
- **Panel (tst_panel), 8 mutants, 8 red:** a non-number total accepted; the
  default error text removed; no plural; `neverApplied` ignored; left and
  middle swapped; the `catch` keeps the old count; `ok:false` keeps the old
  count; zero worded as a count.
- **Guard failures (both must fail the build):** in a mktemp copy of the
  worktree, (i) add a fourth line naming `WlrLayershell` to `Menu.qml`;
  (ii) append a trailing space to one of the three lines. In each,
  `nix build .#checks.x86_64-linux.qml-tests --no-link` fails at the
  `[ ... = 3 ]` or `[ ... = 0 ]` test, not at a QML error. Make the copy
  with `cp -r` and `git -C` free commands; never edit the worktree.
- **Scope:** `git diff main -- Menu.qml OptionForm.qml Panel.qml PkgModel.qml
  Card.qml bin/` is empty; `git diff --stat main` lists only `plan/`,
  `intent/`, `spec/`, `flake.nix` and `tests/qml/`.

The lead picks each exact replacement from the quoted anchor and the
description (for instance `if (form.open) return` deleted, or `return`
replaced by nothing) and lists the 56 results (mutant, edit, red test or
green) in the PR; M24 is the form-close focus replacement already listed
under Menu, not a 30th Menu mutant.

A mutant that is not red when it should be is a test defect: send it back to
Codex (re-run step 2, 3 or 4) with the mutant text; do not exempt it.

### 6. Lead: whole-check and reviews

- `nix flake check` passes; record the `qmltestrunner` totals (Card 33,
  PkgModel 41, OptionForm 15, Panel 12, Menu 21 per the spec; Card and
  PkgModel may differ with main, say so).
- Reviews, read-only: Codex and agy on `git diff main` against this plan
  (`reviewers:`), then a fresh Opus agent given only this plan's path and the
  diff. A provider that fails or is out of quota is reported verbatim; its
  output never approves anything.
- PR: links intent, spec and plan; says that Codex did steps 1-4 and the
  lead 0, 5, 6, 7; describes the commit split (A: steps 1-3; B: step 4); says
  the live check ran or did not.

### 7. Lead: live check in a nixarchy-desktop microVM (not razer)

Load the `ai-mirror` skill first; it asks for the microVM. Not run by the
tests; it finds drift in the host stubs and the compositor hand-off. In the
microVM with the plugin built from this branch: summon the menu with its
keybind and confirm the keyboard is held (a letter does not reach the window
underneath); press Tab in the search field; open an option form and press
`j`; start an apply and press ESC (the build keeps running); close and
summon again (the menu is fresh: tab 0, empty field); look at the bar
widget's tooltip with one change queued and with the queue unreadable.
Report each as seen or not seen. Optional until the owner asks: the plan
does not run it on its own.

Traps (lead steps): never restart the Omarchy shell from the agent (ask the
owner); p510 and razer need the owner's OK before any build or deploy;
announce on the agent bus before disrupting a shared host.

## Tests

From the worktree root, with `run_qml` defined as above:

| Command | Expected |
|---|---|
| `run_qml tst_card tst_pkgmodel` | pass, unchanged from step 0 |
| `run_qml tst_optionform` | pass; 15 per the spec (the 2 #76 tests stay) |
| `run_qml tst_panel` | pass; 12 |
| `run_qml tst_menu` | pass, 5 runs in a row; 21 |
| `nix build .#checks.x86_64-linux.qml-tests --no-link` | builds, about 8 s of its own |
| `nix flake check` | `qml-tests`, `shellcheck`, `manifest`, `qml-syntax` pass |
| `git diff main -- Menu.qml OptionForm.qml Panel.qml PkgModel.qml Card.qml bin/` | empty |
| mutants (step 5) | Menu 26 of 29 red, OptionForm 17 of 19, Panel 8 of 8; the 5 named equivalents green |
| both guard failures | the build fails at the guard |
| live check (step 7) | as listed there, in a nixarchy-desktop microVM |

The tests cannot fail on main: nothing in the shipped panel changes, they
describe it. "Fails first" is shown by the mutants.

## Rollback

Revert the PR. It adds test files, stubs and two blocks in `flake.nix`; no
shipped file, data or format changes. Dropping only `tst_menu.qml` means
removing the Menu block in `flake.nix` (from `cp ${./Menu.qml} Menu.src`
through its `qmltestrunner` command) and the file, leaving commit A in
place.

## Companion issues (for the lead to file; not part of this PR)

Only 1 is in the approved spec. 2 and 3 are follow-ups the spec's decisions
1 and 4 point at; the owner files or drops each.

1. Repo: nixarchy. Title: **Give plugin test stubs a checkable source for
   the shell's host types (BarWidget, BarIconButton, PanelWindow)**. Body:
   Plugins that run QML tests (nixarchy-pkg, #72, and others in the fleet)
   each hand-write inert stubs for `BarWidget`, `BarIconButton`,
   `PanelWindow` and the `Quickshell.*` modules, from how their own code
   uses them. Nothing tells them when the shell changes a property or a
   signal name, so a stub can pass in the sandbox while the shell differs;
   today the only audit is a manual run in a nixarchy-desktop microVM.
   Proposal: a derivation in nixarchy that lists the host types' public
   properties and signals from the omarchy-shell source it already pins, so
   each plugin can diff its stubs against it in its own check. Not blocking
   nixarchy-pkg#72. Acceptance: one plugin's check fails when a stubbed
   property is renamed in the pinned shell.
2. Repo: nixarchy-pkg. Title: **Test the Menu's WlrLayershell lines instead
   of removing them in the check**. Body: #72's `qml-tests` check removes
   `Menu.qml`'s three `WlrLayershell.*` assignments from its copy because
   no QML file can supply an attached type of the host's C++ plugin. The
   three lines carry no logic but are never exercised. Option: move them
   into a `LayerWindow.qml` that Menu instantiates and the tests replace
   with a stub (one new shipped file, no sandbox hack). Decide if the
   fidelity is worth a shipped-file change. Not blocking.
3. Repo: nixarchy-pkg. Title: **Remove the redundant focus handlers #72
   found, or write down why they stay**. Body: #72 removed each of these
   from a copy and every test still passed, because a second piece of code
   does the same job: Tab/Backtab forwarded from the search field
   (`Menu.qml` `case Qt.Key_Tab:`/`Qt.Key_Backtab:`); `focusList()` after
   ESC clears the query (`if (!pkg.flakeTab) root.focusList()`); the
   `onClosed: Qt.callLater(root.focusList)` after the form closes; ESC in
   the string field and the scaffold editor of `OptionForm.qml`. Decide per
   line: delete it, or keep it as a deliberate belt-and-braces and add a
   comment. Separate change, with its own tests. Not blocking.

(Deviation, step 0-4: main moved past the plan. Menu.qml gained `keyCancelsFlakeArm`, Space arming on a declared flake row and `search.text = ""` in `onTabChanged` (#63 A), yet all 21 Menu tests pass unchanged. Baseline totals are Card 36 and PkgModel 54, not 33 and 41. `tst_panel.qml` gained the `{ ok: false }` no-error case, `tst_menu.qml` gained `cleanup()` and the RETURN-acts-on-list assertion, as the plan required. Main moved again to 20816d5 (#88) after the rebase and changed `tst_optionform.qml`, so the branch needs another rebase.)
