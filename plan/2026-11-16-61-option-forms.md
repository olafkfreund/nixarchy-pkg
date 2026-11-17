---
status: approved
issue: 61
spec: spec/2026-11-16-61-option-forms.md
coders:
  1: codex   # S1 literal detection, parse-tree comparison, re-emit: small, security-relevant shell
  2: coder   # fixture catalogue and stub nixarchy-search: mechanical test plumbing
  3: coder   # S2 markup stripping, search-row join, glyph: straightforward jq and QML
  4: coder   # QML OptionForm test harness and stubs: follows tst_pkgmodel's pattern
  5: codex   # S3 bounds parsing and literal-only range checks: string arithmetic edge cases
  6: coder   # S3 integer field, unset arming, placeholders: QML state
  7: coder   # S4 sensitive/fileOption and the warning: small
  8: codex   # S5 type grammar and constraint checks: one regex grammar, many edge cases
  9: coder   # S5 list, nullable and package widgets and their seeds: QML
  10: codex  # S6 path grammar, template resolution, marker readers: parsing and string matching
  11: coder  # S6 name fields in the form: QML
  12: agy    # docs per slice from the strings in the code: bounded, mechanical (fallback: coder)
reviewers:
  - codex   # shell quoting, parse/eval safety, marker compatibility are where this goes wrong
  - agy     # independent read of each PR's diff against this plan
---

# Plan: the option form can set the options people actually set

Branch `feat/61-option-forms`. This file is self-contained: a coder reads it
and the files each step names, nothing else. **Coders never stage or
commit.** The lead commits after each step, as `feat(adapter): … (#61)`,
`feat(panel): … (#61)`, `test: … (#61)` or `docs: … (#61)`.

Line numbers are on `feat/60-truthful-queue` (PR #70), which merges before
this work starts. Anchors quote a line; numbers drift.

After every step, run:
- `bash -n bin/nixarchy-pkg`
- `shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh`
- `bash tests/adapter.sh`
- QML steps also: `nix flake check`

`tests/adapter.sh` has **11 pre-existing failures** on a nixarchy machine
(catalogue drift, fixed only by #68): "toggling on reports enabled", "the
file really changed", "toggling off reports disabled", "services use their
own file", "a toggle counts once", "a package counts once", "one file, one
change", "and it names that file", "two files, two changes", "and both files
are named", "and it recovers once readable". Pass means no failure outside
that list.

## Decisions (from the approved spec)

**Delivery.** Six slices, one PR each, in this order: S1 multi-line, S2
reading, S3 integers and unset, S4 secrets, S5 widgets, S6 names. Each PR
leaves the panel working and carries its own tests and docs.

**Multi-line values (S1).** No marked block in this task. A value is still
written on one marked line, and never with a changed meaning:
1. *One string literal.* `nix-instantiate --parse -E "($value)"` must print
   only string literals joined by ` + `, matching
   `^\(?"(?:[^"\\]|\\.)*"(?: \+ "(?:[^"\\]|\\.)*")*\)?$`. Then decode with
   `nix-instantiate --eval --strict --json --readonly-mode --option pure-eval true --option restrict-eval true -E "$value"`
   and re-emit one Nix `"…"` literal: `\`→`\\`, `"`→`\"`, newline→`\n`,
   tab→`\t`, CR→`\r`, `${`→`\${`; any other control character refuses. Run
   the `#@` refusal again on the emitted text (`"#\@pkg x"` decodes to
   `#@pkg x`).
2. *Anything else with a newline.* Newlines become spaces. Build the
   candidate file twice (value as typed, value flattened); both through
   `nix-instantiate --parse` with the user's header; refuse if the printed
   trees differ.
3. No newline: unchanged.

**`null`.** Offered on every nullable widget; writes `null`. Unset stays
"write nothing" or remove.

**Package widget.** Exact attribute from the package index, default channel
only, written `pkgs.<attr>`, offered only when `apps.nix`'s header binds
`pkgs`; otherwise the scaffold, with the reason.

**Names (S6).** Plain names and quoted keys, spaces allowed. A component is a
Nix identifier `[A-Za-z_][A-Za-z0-9_'-]*` that is not a keyword (`if then
else assert with let in rec inherit or`), or `"…"` containing none of `"`,
`\`, `$`, newline, tab, `#@`. `<name>` and `*` are never written.

**Secrets (S4).** Only 34 of 195 secret-like options have a `*File`
sibling, so name it only when it exists. Warning only; never refuses.

**Unset (S3).** `DEL` in a form on a set option arms; a second `DEL` runs
`opt remove`. Emptying a set text field and pressing RETURN arms the same.
Known limit: the installed `nixarchy-opt-remove` ends with `mv`, which
replaces a symlinked `apps.nix` (one of #59's external writers); the panel's
SPACE removal has the same limit today.

**Adapter checks** (range, constraint) run only on a literal of the expected
kind (integer, single string literal checked on its decoded text, or a list
of those). `null` passes on a nullable option. Any other expression is
unchecked. No `options.json`, or an option it does not list: unchecked, as
today.

**describe answer**, additive; every field on every answer:

```json
{"ok": true, "path": "…", "type": "…", "widget": "boolean|enum|integer|string|list|package|scaffold",
 "item": "string|integer|null", "nullable": false, "multiline": false,
 "min": "0|null", "max": "65535|null", "constraint": "nonEmpty|absolute|noNewlineColon|null",
 "choices": [], "choicesUnavailable": false, "sensitive": false, "fileOption": null,
 "template": null, "names": [], "current": {"state": "absent"},
 "description": "…", "readOnly": false, "declarations": [], "default": "…", "example": "…"}
```

**Search rows** for `kind == "opt"` gain `set` (`true|false|null`) and
`current` (string or `null`).

## Steps

### 0. Rebase and re-anchor (lead)

`git rebase main` after #60 has merged. Re-check every anchor below with
`grep -n`; update numbers in this file in the same commit if they moved.
→ **Verify:** `bash tests/adapter.sh` at the rebased tip, the 11 known
failures only.

## PR 1 — S1: a multi-line value keeps its meaning

### 1. `flat_value` becomes `one_line` (`bin/nixarchy-pkg:718-747`, callers `:757`, `:855`)

- Keep `MARKER_REFUSAL` (`:718`). Reword `FLAT_REFUSAL` (`:719`) to:
  `"that value changes meaning when written on one line -- a newline inside a string or after a # matters. Write it on one line, or as one string. Nothing was changed."`
- `flat_value` keeps only the `#@` check (status 2) and moves out of
  `$(...)` dependence on files: in `cmd_opt_set` and `cmd_opt_replace`, call
  it **before** `begin_write` as today, then, **after** `begin_write` and
  the `[ -f "$APPS" ]` check, call a new `one_line VAR` that rewrites the
  named variable in place (`printf -v`), never inside `$(...)`, so `die`
  answers once:

  ```bash
  # Kept in a variable: an inline =~ pattern with quotes and spaces is
  # misparsed by bash. Tested 2026-11-16 against the three Verify cases.
  readonly LITERAL_RE='^\(?"([^"\\]|\\.)*"( \+ "([^"\\]|\\.)*")*\)?$'

  # one_line VAR -- rewrite the value in VAR to one line without changing its meaning, or die.
  one_line() {
    local v=${!1} p lit out
    [[ $v == *$'\n'* ]] || return 0
    p=$(nix-instantiate --parse -E "($v)" 2>/dev/null 9>&- 8>&-) || p=""
    if [[ $p =~ $LITERAL_RE ]]; then
      lit=$(nix-instantiate --eval --strict --json --readonly-mode \
            --option pure-eval true --option restrict-eval true -E "$v" 2>/dev/null 9>&- 8>&-) ||
        die "$FLAT_REFUSAL"
      out=$(jq -r 'if type != "string" then error("not a string") else . end
        | if test("[\u0000-\u0008\u000b\u000c\u000e-\u001f]") then error("control") else . end
        | gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\n"; "\\n")
        | gsub("\t"; "\\t") | gsub("\r"; "\\r") | gsub("\\$\\{"; "\\${")
        | "\"" + . + "\""' <<<"$lit") || die "$FLAT_REFUSAL"
      [[ $out == *'#@'* ]] && die "$MARKER_REFUSAL"
    else
      out=${v//$'\n'/ }
      same_tree "$v" "$out" || die "$FLAT_REFUSAL"
    fi
    printf -v "$1" '%s' "$out"
  }
  ```

- `same_tree A B`: write two candidate copies of `$APPS` into `$WORK` (set
  by `begin_write`), each with a marker-free probe line
  `  __nixarchy_probe = <value>;` inserted before the closing `}` with the
  same awk `cmd_opt_set` uses (`:776-786`), run `nix-instantiate --parse`
  on each (`9>&- 8>&-`, output to files in `$WORK`), and compare the two
  output files with `cmp -s` (not in a pipeline). A parse error on the
  typed value dies with Nix's first `error:` line, as `:809-818` does.
- `opt set`'s "kept the default" check (`:762`) stays before
  `begin_write`; it reads the raw value, which is unaffected.

→ **Verify:** in a throwaway `XDG_CONFIG_HOME` with `apps.nix` =
`{ ... }:\n{\n}\n`: `opt set x.y $'[ 1\n 2 ]'` writes `x.y = [ 1  2 ];`;
`$'[ "a\nb" ]'` and `$'{ a = 1; # c\n b = 2; }'` refuse with the file
byte-identical; `$'\'\'\n  a "q"\n  \'\'${x}\n\'\''` writes
`x.y = "a \"q\"\n\${x}\n";` and `nix-instantiate --eval` of that literal
equals the original's; `'"a" + builtins.getEnv "X" + ""'` with a newline
added is not treated as a literal; `$'"#\\@pkg x\n"'` refuses with
`MARKER_REFUSAL`.

**Existing tests that change (same step).** On #60's `tests/adapter.sh`:
`:373-374` (`{⏎ a = ''x'';⏎}`) now writes (its flattened tree is the
same): assert it is written as one line. `:375-376` (`{ # c⏎ a = 1;⏎}`)
stays refused. `:1102-1104` (`''a⏎b''`) is now a literal written as
`"a\nb"`: assert that, and keep a separate case that still gets
`FLAT_REFUSAL` (`[ "a⏎b" ]`), checking the error names the one-line rule.

**Tests (same step).** Add the five Verify cases to `tests/adapter.sh`,
each also through `opt replace`, each refused case asserting `apps.nix`
unchanged (`md5sum` before and after). These need no `options.json`.

**Traps.**
- Never call `one_line` or anything that can `die` inside `$(...)`: `die`'s
  JSON would become the value. One JSON answer on every path.
- `set -euo pipefail`: no `grep -q` at the end of a pipeline whose head can
  get SIGPIPE; no `| head`; no `diff`/`cmp`/`comm` at a pipeline head (the
  source-shape checks in `tests/adapter.sh` enforce this).
- Nothing in `/tmp`: every file goes in `$WORK`.
- Every `nix-instantiate` closes `9>&- 8>&-`.
- No `--impure`. The `--option` flags here are the spec's and are the only
  exception to #60's "no --option" rule, which applies to `check`.
- `jq`'s `\u0000` range must be written so jq, not bash, sees it.

### 2. Fixture catalogue (`tests/fixtures/options.json`, `tests/adapter.sh`)

- New `tests/fixtures/options.json`: one option per family the later PRs
  test (keys and types exactly):
  `t.bool` `boolean`; `t.enum` `one of "a", "b"`; `t.port`
  `16 bit unsigned integer; between 0 and 65535 (both inclusive)`;
  `t.u32` `32 bit unsigned integer; between 0 and 4294967295 (both inclusive)`;
  `t.uint` `unsigned integer, meaning >=0`; `t.pos`
  `positive integer, meaning >0`; `t.int` `signed integer`; `t.range`
  `integer between 300 and 399 (both inclusive)`; `t.neg`
  `integer between -9 and 0 (both inclusive)`; `t.str` `string`;
  `t.nonEmpty` `non-empty string`; `t.abs` `absolute path`; `t.noColon`
  `string, not containing newlines or colons`; `t.lines`
  `strings concatenated with "\n"`; `t.pattern`
  `string matching the pattern [a-z]+`; `t.nullStr` `null or string`;
  `t.nullPort` `null or 16 bit unsigned integer; between 0 and 65535 (both inclusive)`;
  `t.ports` `list of 16 bit unsigned integer; between 0 and 65535 (both inclusive)`;
  `t.strs` `list of string`; `t.absList` `list of absolute path`; `t.pkg` `package`; `t.nullPkg`
  `null or package`; `t.attrs` `attribute set of string`;
  `users.users.<name>.shell` `null or package`;
  `users.users.<name>.hashedPassword` `null or (string, not containing newlines or colons)`;
  `users.users.<name>.hashedPasswordFile` `null or string`;
  `fileSystems.<name>.options` `list of string`;
  `t.ro` `boolean` with `readOnly: true`. Each has `description`
  (one with ``{option}`t.bool` `` and a `::: {.note}` block), `default`.
- In `tests/adapter.sh`, a `FIXSTUB` dir with a `nixarchy-search` script
  whose only content is `#!/bin/sh` and `optionsjson=<abs path to the
  fixture>` (the adapter reads that line, `searched()` `:269-273`), and a
  helper `fx() { PATH="$FIXSTUB:$PATH" "$ADAPTER" "$@"; }`. These checks
  run unconditionally; the real-catalogue checks (`:310-361`) stay as they
  are.

→ **Verify:** `fx opt describe t.bool` answers `ok: true`, `widget:
"boolean"`.

**Traps.** The stub must not be executable as a real search; the adapter
only `sed`s it. The fixture lives in the repo (Nix flake check copies
`tests/`).

**PR 1 check:** the commands above; the S1 tests pass. Docs: step 12.

## PR 2 — S2: reading

### 3. Reading: markup, search rows, glyph

**3a. Markup** (`OptionForm.qml:61-68`, `reflow`)

Before the paragraph split, apply:
`.replace(/\{[a-z]+\}`([^`]*)`/g, "$1")`, and line-wise turn
`^::: \{\.note\}$` into `Note:`, `^::: \{\.warning\}$` into `Warning:`, and
drop a line that is exactly `:::`. `textFormat` stays `Text.PlainText`
(`:371`). → **Verify:** QML test in step 4.

**3b. Search rows** (`bin/nixarchy-pkg:399-470`, `cmd_search`)

Pass `--rawfile extras <(extras_tsv)` into the `jq -n` (`:425`-ish), build
a map path → `{set, line}` from the `opt` rows, and for each row with
`.[0] == "opt"` add `set: (if $m[name] == null then null else $m[name].set end)`
(not `// null`, which turns `false` into `null`) and
`current: (if $m[name] == null then null else $m[name].line end)`; for other kinds add neither.
→ **Verify:** in a throwaway config with `x.y = true;  #@opt x.y` and a
scaffold for `x.z`, a stubbed index row for each gives `set: true,
current: "x.y = true"` and `set: false`.

**3c. Card** (`Card.qml:168-170`, `:243-244`)

- Glyph: before the `enabled` branch, `modelData.set === true ? "■"
  : modelData.set === false ? "□"`.
- Text: for option rows (`modelData.type !== undefined && modelData.type
  !== ""`), show `summary` followed by `  ·  ` and `type`, and when
  `current` is a string, `  =  ` and the current value; others unchanged.

→ **Verify:** `tests/qml/tst_card.qml` gains a set and a scaffold option
row and asserts the glyphs and that type is drawn beside a summary.

**Traps.** Card text stays `Text.PlainText`. `extras_tsv` reads `$APPS`,
which may be absent: it returns 0 with no output (`:356`).

### 4. OptionForm test harness (`tests/qml/`)

(Deviation, 2026-11-16: the harness, stubs and flake wiring already existed; this step adds only the behavior tests, using the existing `describeProc()` test helper and no process aliases.)

- Stubs under `tests/qml/imports/qs/Ui/`, shape only, registered in
  `qmldir`: `Toggle` (`checked`, `label`, `clicked` signal), `Dropdown`
  (`value`, `options`, `changed` signal), `TextField` (`text`,
  `placeholderText`, `foreground`, `validator`, `textChanged`,
  `forceActiveFocus()`), `NumberField` (until step 6 removes its use:
  `value`, `from`, `to`, `label`, `modified`). Read `OptionForm.qml` for
  every property and signal it touches on each and stub exactly those.
- `tests/qml/imports/qs/Commons/Border.qml` gains `controlSpec()` if
  OptionForm's widgets reach it through the stubs (they should not; check).
- `OptionForm.qml`: expose the two private processes for tests as
  `readonly property alias describeProc: describe` and
  `readonly property alias writeProcess: writeProc` (aliases, no behaviour).
- `tests/qml/tst_optionform.qml`, modelled on `tst_pkgmodel.qml`: a
  `PkgModel`-shaped stub model (`script`, `busy`, `applying`), an
  `OptionForm`, drive `begin(row)`, then `form.describeProc.deliver(json)`.
  First tests: the form opens and seeds a boolean; then markup stripping
  (3a) and read-only refusal.
- `flake.nix:98-110`: copy **both** `OptionForm.qml` and
  `tst_optionform.qml` into the test directory and run it like the others.

→ **Verify:** `nix flake check`; first prove the harness with the
"opens and seeds" test alone before adding behaviour tests.

**Traps.** Stub `Process`: `deliver()` feeds stdout then sets
`running = false`; `finish()` emits `exited` without output. Call them in
that order, as the real process would. A `Process` whose `running` is
already true ignores a restart: tests must deliver before beginning
another describe.

**PR 2 check:** commands above, `nix flake check`.

## PR 3 — S3: integers and taking a value out

### 5. Bounds and range checks (`bin/nixarchy-pkg:617-716`)

- In `cmd_opt_describe`'s jq, add `def bounds:` returning `[min, max]` as
  strings: `positive integer` → `["1", I64MAX]`; `unsigned integer` →
  `["0", I64MAX]`; `N bit unsigned integer; between A and B` and
  `integer between A and B` → `[A, B]`; `signed integer` →
  `[I64MIN, I64MAX]`; `I64MAX = "9223372036854775807"`,
  `I64MIN = "-9223372036854775808"`. Applied to the type with any leading
  `null or ` / `list of ` and parentheses removed. Emit `min`, `max`
  (`null` when not an integer type).
- Factor the option lookup into `opt_meta PATH` printing the describe JSON
  (no `current`), used by describe and by the checks below. It never dies:
  no `options.json` or unknown option prints `null`. Step 10 adds template
  resolution **inside `opt_meta`**, so describe and the writers' checks see
  the same option for a concrete path.
- New `check_literal PATH VALUE`: with `m=$(opt_meta PATH)` non-null and
  an integer `widget` (or `item: "integer"`), if VALUE is `null` and
  `nullable`, pass; if VALUE matches `^-?(0|[1-9][0-9]*)$`, compare with
  `min`/`max` by sign, then length, then lexical order; out of range dies
  `"$PATH takes $min to $max; $VALUE is outside that. Nothing was changed."`.
  A leading zero (`007`) dies `"write $PATH as a plain number, without leading zeros. Nothing was changed."`.
  Any other VALUE: pass. For a list item type, apply to each element of a
  `[ … ]` of integer literals.
- Call `check_literal "$path" "$value"` in `cmd_opt_set` and
  `cmd_opt_replace` after `one_line`, before `guard`.

→ **Verify:** fixture: `fx opt describe t.port` gives `min "0" max
"65535"`; `t.int` gives the I64 pair; `fx opt set t.port 70000` and
`opt replace` of `-1` on `t.uint` refuse, file unchanged;
`4294967295` on `t.u32` writes; `-10` on `t.neg` refuses and `-9` writes; `007`
refuses; `lib.mkForce 80` on `t.port` writes.

(Deviation, the installed `apps-template.nix` starts with `{ ... }:` and does not bind `lib`, so its Nix parser refuses `lib.mkForce 80`; the fixture verifies the same expression bypass with `builtins.toString 80`.)

**Traps.** Bash arithmetic overflows past int64 and is signed: compare as
strings, never `(( ))`. `opt_meta` runs in `$(...)`: it must not `die`.

### 6. Integer field, unset, placeholders (`OptionForm.qml`)

- Remove `NumberField` (`:440-447`). For `widget === "integer"`, reuse a
  `TextField` (`integerField`) with `validator: RegularExpressionValidator
  { regularExpression: /-?(0|[1-9][0-9]*)?/ }`; `Keys` Up/Down step by one
  with a decimal-string helper `stepDecimal(text, +1|-1)` (digit-by-digit
  carry and borrow, sign handled, never `Number`/`parseInt`), clamped to
  `min`/`max`; RETURN commits; `nixValue()` returns the text.
- Seeds: replace both `numberField.value` writes in `seed()` (`:177`, the
  default; `:200`, a set value) with `integerField.text = …` using the
  string as written (`/^-?(0|[1-9][0-9]*)$/` to hold it, else
  `forceScaffold`), and `:248` with the field's text. No `parseInt`
  anywhere. Focus: `:222-224` gains
  `else if (root.widget === "integer") integerField.forceActiveFocus()`.
  Range check in QML with the same sign/length/lexical rule as step 5;
  out of range sets `root.error` and does not commit.
- Unset: `property bool armedRemove`. In `Keys.onPressed` (`:295`), when
  `current.state === "set"` and `event.key === Qt.Key_Delete`: first press
  sets `armedRemove` and `error = "DEL again removes " + path + " from apps.nix; ESC keeps it"`;
  second press runs `writeProc` with `["opt", "remove", path]`. In
  `commit()` (`:267`), when `touched` is true, the field is empty,
  `current.state === "set"` and the widget is a text widget, arm the same
  instead of `finish()`. An untouched form (`nixValue()` returns "" because
  `touched` is false) still just closes.
  Any other key disarms.
- Placeholder (`:453`) and help lines (`:557-558`): "empty keeps the
  current value" when `current.state === "set"`, else as today. Help line
  gains "DEL removes" when set.

→ **Verify:** `tst_optionform.qml`: integer field has focus after describe;
Up on `"65535"` with max 65535 stays; Up on `"9007199254740993"`
gives `"9007199254740994"`; Down on `"0"` with min `"-9223372036854775808"`
gives `"-1"`; `70000` sets `error` and no
`writeProc.command`; DEL once arms, twice sets
`writeProc.command[1..2] == ["opt","remove"]`; emptying a set string and
RETURN arms; RETURN on an untouched form opened on a set string neither
arms nor writes.

**Traps.** The form's `busy`/`applying` guard (`:276-281`) applies to the
remove too. `writingPath` must be set for the remove so a stale answer is
ignored (#43).

**PR 3 check:** commands above, `nix flake check`.

## PR 4 — S4: secrets

### 7. `sensitive`, `fileOption`, warning

- describe jq: `sensitive: (($p | split(".") | last) | test("(?i)(password|passwd|secret|token|apikey|privatekey|presharedkey|psk)$")) and ($t | test("string"))`;
  `fileOption: (($p | sub("(?<l>[^.]+)$"; "\(.l)File")) as $f | if $all[$f] != null then $f else null end)`
  where `$all` is the whole `options.json` (bind it before `.[$p]`).
- `OptionForm.qml`: a `Text` above the widget, visible when
  `option.sensitive === true`: the spec's wording —
  "This value is copied into the Nix store, which every user on this machine can read."
  plus, when `fileOption`, " " + fileOption + " reads it from a file at run time instead -- give it the path as a quoted string, \"/run/secrets/…\", so the file itself is not copied into the store."
  `Text.PlainText`. Never blocks commit.

→ **Verify:** `fx opt describe users.users.<name>.hashedPassword` →
`sensitive: true`, `fileOption: "users.users.<name>.hashedPasswordFile"`;
`t.bool` → `false`, `null`. QML test: the warning shows and RETURN still
commits.

**PR 4 check:** commands above.

(Deviation, PR 4: fixture options `t.password`, `t.passwordFile`, `t.token` added for the tests; `tst_optionform.qml` gained `visible: true` on the TestCase so the warning's `visible` can be asserted; the warning Text carries `objectName: "secretWarning"`.)

## PR 5 — S5: widgets for the common types

### 8. Type grammar and constraint checks (`bin/nixarchy-pkg:677-683`)

- Replace the `widget:` chain with one grammar, anchored whole:
  - `scal`: `boolean` | listed enum (`$listed`, unchanged) | integer types
    (step 5) | `string` | `path` | `strings concatenated with "\n"`
    (`multiline: true`) | `non-empty string` (`constraint: "nonEmpty"`) |
    `absolute path` (`"absolute"`) |
    `string, not containing newlines or colons` (`"noNewlineColon"`).
    `string matching the pattern …` is not in `scal`.
  - `null or (scal)` / `null or scal` → that widget, `nullable: true`.
  - `list of (scal)` where scal is a string or integer type →
    `widget: "list"`, `item`, and the item's `min`/`max`/`constraint`.
  - `package` / `null or package` → `widget: "package"` (nullable for the
    second) only when the header binds `pkgs`: the adapter asks Nix:
    `nix-instantiate --eval --readonly-mode -E "builtins.hasAttr \"pkgs\" (builtins.functionArgs (import $APPS))"`
    (`9>&- 8>&-`, path passed through a variable, not spliced unquoted).
    This only imports the file's top-level lambda; nothing is called.
    Measured: `{ config,⏎ pkgs, ... }:` → `true`; `{ other ? "pkgs", ... }:`
    → `false`. A failure counts as `false`. Pass `--argjson hasPkgs`; otherwise `widget: "scaffold"` and
    `packageNote: "apps.nix does not take pkgs, so a package is written as Nix here"`.
  - else `scaffold`.
- `check_literal` (step 5) also enforces `constraint` on a single string
  literal (decode with the same pure eval as step 1, which a one-line
  literal also passes) and on each element of a list of string literals:
  `nonEmpty` → not `""`; `absolute` → starts with `/`; `noNewlineColon` →
  no `\n`, no `:`. Dies `"$PATH needs <rule>. Nothing was changed."`.

→ **Verify:** fixture: each `t.*` gives its expected `widget`, `item`,
`nullable`, `multiline`, `constraint`; `t.pattern` and `t.attrs` are
`scaffold`; `fx opt set t.nonEmpty '""'` and `t.abs '"rel/x"'` and
`t.absList '[ "/ok" "rel" ]'` refuse; with a
`{ ... }:` header `t.pkg` is `scaffold` with `packageNote`. Update #60's `tests/adapter.sh:314`
("a list falls through to a scaffold", `services.openssh.ports`) to
expect `widget: "list"`, `item: "integer"`, in this step.

**Traps.** jq regexes are Oniguruma: escape `(` and `)` in type text. The
header check reads `$APPS` only if it exists.

(Deviation, PR 5: the host catalogue declares `networking.hostName` as a pattern string, so its old string-widget test now expects a scaffold.)

### 9. Widgets and seeds (`OptionForm.qml`)

- `nullable`: an extra choice / toggle "null" beside the widget; when
  chosen, `nixValue()` returns `null`.
- `list`: the multi-line `scaffoldField`-style field, one item per line;
  `nixValue()` builds `[ "a" "b" ]` (each line escaped like the string
  widget, `:254-261`) or `[ 80 443 ]` (integer lines validated as step 6);
  a field that is exactly `[ ]` returns `[ ]`; empty returns "".
- `multiline` string: the multi-line field; `nixValue()` returns one
  `"…"` literal with `\n` escapes (escaped as the string widget does), so
  the value is already one line and S1 has nothing to do.
- `package`: a `TextField` that runs `pkg.runSearch`-style
  `[script, "search", "--kind", "pkg", "--limit", "20", "--", text]` on
  RETURN-less typing (debounced 300 ms), a `j`/`k` list of results, RETURN
  writes `pkgs.<attr>`.
- `constraint` checked in `commit()` with the step 8 rules before writing.
- Seeds (`seed()`, `:175-226`): `list` parses `[ … ]` of string or integer
  literals only; `package` accepts `pkgs.<attr>` only; `null` selects the
  null choice; anything else sets `forceScaffold` as today.

→ **Verify:** `tst_optionform.qml`: each widget's `nixValue()` for typed
input; seeds for `[ "a" "b" ]`, `pkgs.hello`, `null`, and
`lib.mkForce [ 1 ]` (forces scaffold); `console=ttyS0,115200n8` on one
line stays one item.

**Traps.** The package search reuses the adapter's `search` verb; do not
add a second process type. `Process` restart while running is a no-op: set
`running = false` before reassigning `command`, or skip when running.

**PR 5 check:** commands above, `nix flake check`.

## PR 6 — S6: options under `<name>` and quoted keys

### 10. Path grammar, templates, readers (`bin/nixarchy-pkg`)

- `valid_path PATH` (new, near `valid_input_name`): splits on `.` outside
  quotes (awk or a bash loop; no `eval`), accepts the component grammar in
  Decisions, rejects `<name>`, `*`, empty components, an unterminated
  quote. Replace the `case` at `:754` and `:852` with
  `valid_path "$path" || die "'$path' is not an option path …"`.
- In `opt_meta` (step 5; used by `cmd_opt_describe` and `check_literal`):
  when `.[$p] == null`, find the template:
  same component count, each component equal or `<name>` / `*`; prefer an
  exact key, then fewest placeholders. Answer with the template's fields,
  `path` = the concrete path, `template`, `names` = the filled
  components. `fileOption` (step 7) is looked up on the template path and
  returned with the concrete names substituted back in. Components are compared unquoted (`"/"` matches the user's
  `"/"`).
- `extras_tsv` (`:364`): `match($0, /#@opt .*$/)`, path =
  `substr($0, RSTART + 6)` with trailing whitespace trimmed.
- #60's `pending` `def marker` (`:1470`): for `.t == "opt"`, capture the
  rest of the line (`#@opt[ \t]+(?<n>.*[^ \t])[ \t]*$`); other types keep
  the first token.
- String matching: replace `grep -q "#@opt ${path//./\\.}\$"` at `:769`,
  `:799`, `:862`, `:888` with a helper `has_opt FILE PATH` using the awk
  end-of-line comparison of `cmd_opt_describe` (`:629-633`), through
  `ENVIRON`, never `awk -v`.

→ **Verify:** fixture:
`fx opt set 'fileSystems."/mnt/usb drive".options' '[ "nofail" ]'` writes;
`fx state` lists that exact path with `set: true`; `fx opt describe` of it
answers `template: "fileSystems.<name>.options"`, `names:
["\"/mnt/usb drive\""]`, `current.state: "set"`; `opt replace` changes it;
`nixarchy-opt-remove` (installed) removes it, file parses; `pending` after
apply-copy shows one change named with the full path; paths with `\`, `$`,
`#@`, `<name>`, `services.123.x`, `services.if.x` refuse;
`users.users.alice.shell` resolves to its template; existing one-word
paths behave exactly as before (the existing tests pass).

**Traps.** `awk -v` processes escapes; the path is passed through
`ENVIRON` everywhere in this repo. A quoted key may contain `.`; never
split with `${path//./ }`. The remover matches by suffix: a path that is a
suffix of another option's marker cannot collide because the marker
includes `#@opt `.

### 11. Name fields (`OptionForm.qml`, `Menu.qml:536-541`)

- When `option.template === null` and the row's path contains `<name>` or
  `*` (an opened template), show one `TextField` per placeholder above the
  widget, focused first; TAB moves between them. RETURN refuses with
  "name every <name> first" until all are filled. On commit, build the
  concrete path: a name that is a non-keyword identifier is bare, else
  quoted; refuse a name with `"`, `\`, `$`, tab, newline or `#@`.
- **Before dispatch**, once every name is filled: set `root.path` to the
  concrete path, set `writingPath` to it, and run `opt describe` on it
  (`describeProc`) to learn its `current`; `commit()` waits for that
  answer and then picks `set` or `replace` from the concrete path's
  `current.state`, as it does today. The response handler's
  `writingPath === root.path` check then compares concrete paths.

→ **Verify:** `tst_optionform.qml`: template row shows one name field;
RETURN with it empty sets `error`; `alice` builds `users.users.alice.shell`;
a name whose concrete path is already set dispatches `replace`, not `set`;
`/mnt/usb drive` builds `fileSystems."/mnt/usb drive".options`; `if`
builds `"if"`.

**PR 6 check:** commands above, `nix flake check`.

### 12. Docs, per PR (agy; fallback: coder)

With each PR, from the strings in the code: `docs/manual/options.md`
(what gets a widget, multi-line rule, integers and bounds, DEL, secrets,
names), `docs/manual/from-a-terminal.md` (`opt set`/`replace` refusals,
quoted paths), `bin/nixarchy-pkg-keys` (DEL in the form). No claims the
code does not make.

→ **Verify:** every quoted message exists verbatim in the code (`grep -F`).

## Tests

- `bash -n bin/nixarchy-pkg && shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh`: clean.
- `bash tests/adapter.sh`: all new checks pass; failures only from the 11
  listed above.
- `nix flake check`: shellcheck and the three QML suites
  (`tst_card`, `tst_pkgmodel`, `tst_optionform`) pass.
- **Manual on razer** (the lead; never writes `/etc/nixos`, never switches
  without the owner): set `services.openssh.ports` from the panel, a user's
  shell by name, a multi-line `services.nginx.virtualHosts."x".extraConfig`
  scaffold value; check `nixarchy-pkg pending`; with the owner's OK run
  `nixarchy-apply`; then remove each with DEL from the form. Watch for a
  secret warning on `users.users.<name>.hashedPassword`.

## Rollback

Each PR reverts on its own (`git revert` of its merge). Nothing migrates
data: every line written stays in the one-line `#@opt` form older code
reads. Lines with quoted keys written by PR 6 are still removed by
`nixarchy-opt-remove`; after reverting PR 6 they show in `state` with a
path cut at the first space, and remain removable by hand or by the
remover's fzf picker.

## Companion issues

**nixarchy-search: find `#@opt` lines by string, not regex.**
`add_option`'s duplicate check is `grep -q "#@opt $path\$"`
(`modules/apps.nix:2894`). nixarchy-pkg now writes option paths with quoted
keys, for example `fileSystems."/mnt/usb drive".options`, where `.` and
other characters are regex metacharacters. The check can then match the
wrong line, or miss the right one and add a duplicate. Compare the marker
as a string at the end of the line, as `nixarchy-opt-remove` already does.

**A marked multi-line option block (`#@opt-begin` / `#@opt-end`).**
Every option is one line today, so a multi-line `extraConfig` is stored as
one long escaped string (nixarchy-pkg #61). A block form would keep
`apps.nix` readable and diffs small. It needs `nixarchy-opt-remove` to
delete the whole block, `checks.options` to assert the form, and
nixarchy-search's picker to list it; nixarchy-pkg's queue (#60) would also
count the block as one change.

(Workflow run 2026-11-16: the steps of this PR were implemented in one parallel workflow pass and committed together as one commit, because agent-run codex will not start on a worktree with uncommitted changes and the implementing agents may not commit. The PR names which steps Codex wrote and which the coordinating agent wrote; each agent verified every step with the adapter suite, shellcheck, the QML suites and nix flake check, and the lead re-ran the adapter suite and nix flake check before committing.)

(Review fixes, round 2: refuse flattened values when the probe cannot be inserted; keep jq errors out of the JSON response; cover missing insertion, control-character refusal, and tab/CR escapes in the adapter tests.)

(Review fixes, PR 2: a search row draws "= <value>" only when set is true, and `current` carries the value alone; a successful option write re-runs the active Options search; OptionForm reflow turns every `::: {.x}` / `:::{.x}` opening line, indented or not, into a capitalised label.)

(Review fixes, PR 3: Delete inside a text editor edits text and arms removal only from the form root; disarming clears the "DEL again removes" message; a lone "-" in the integer field is refused with a message; `null or <integer>` options get the range check.)

(Review fixes, PR 4: removal keys ignore auto-repeat so a held Delete never arms and removes; the sensitive heuristic is tested against a *File sibling and a non-string secret-named option.)

(Review fixes, PR 5: null writes bypass field constraints and integer-list validation; seeded packages neither search nor write on untouched RETURN; nullable integer defaults of null stay in the integer widget; lists drop blank lines; package results use arrow keys while plain j/k type; stale searches are ignored; CTRL+N toggles null with a hint; forced multiline scaffolds show the scaffold hint; the manual shows one backslash in the newline code span.)

(Review fixes, PR 6: name-field Tab and Shift+Tab reach the value and return; RETURN waits for concrete describe, failed describes discard the held value and restore the template path; quoted keys refuse control characters; name placeholders identify their position and path segment.)
