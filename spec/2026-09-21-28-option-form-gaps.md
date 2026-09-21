---
status: draft
issue: 28
intent: intent/2026-09-21-28-option-form-gaps.md
---

# Spec: the form offers what it can write, shows what is set, and changes it

Reviewed before writing by Codex (`gpt-6-astra`, read-only). It confirmed
both headline diagnoses, and found three more problems that wiring in
`replace` would make worse. All three are in scope here: §4 value
fidelity, §5 response handling, §6 concurrency.

## Design

### 1. `opt describe` reports what is set

`cmd_opt_describe` adds one field, read from `$APPS` by the same
end-of-line marker rule the writers use (`#@opt <path>` at end of line,
string comparison, never a regex):

    "current": { "state": "absent" }
    "current": { "state": "scaffold" }                 # "# <path> = ;  #@opt <path>"
    "current": { "state": "set", "value": "<raw nix>" } # "<path> = <value>;  #@opt <path>"

`value` is the text between `<path> = ` and `;  #@opt <path>`, verbatim.
Intent Q2: it comes from `describe`, which the form already runs, so there
is no second process and search rows are covered too (they carry no
`state.options` line; Codex).

It is labelled in the form as **"set in apps.nix"**: the local expression,
not the evaluated NixOS value. `lib.mkDefault true` is shown as that text,
never coerced to a boolean (Codex).

### 2. The form opens on the current value when it can represent it

`seed()` takes `current` into account:

| state | widget seeded with |
| --- | --- |
| absent | the default, as today |
| scaffold | the default, as today; the note says a scaffold exists |
| set, and the widget can hold it exactly (`true`/`false`; an integer literal; a quoted enum choice; a plain `"…"` string with no escapes or `${`) | that value |
| set, anything else | the **scaffold editor**, pre-filled with the raw expression, whatever the type's widget would have been |

"An untouched field writes nothing" still holds: `touched` is cleared
after seeding, so opening and closing a set option rewrites nothing.

### 3. Writing: `set` when absent, `replace` when present

`commit()` sends `opt set` for `absent` and `opt replace` for `set` or
`scaffold`. `replace` already exists (#19), is atomic, and keeps the
byte-exact line.

Scaffold → value: `replace` turns the marked scaffold line into a set line.
`nixarchy-opt-remove` removes a set line cleanly, but it takes the
scaffold's comment block only while the line is still exactly
`# <path> = ;  #@opt <path>` (read from the installed remover). So after
replace-then-remove, the doc comments stay behind as plain comments. They
parse, and nothing reads them. Accepted and documented rather than
teaching `replace` to rewrite another tool's comment block.

### 4. Values are written as typed

Both writers flatten the value with `tr '\n' ' ' | tr -s ' '`
(`bin/nixarchy-pkg:450`, `:535`). `tr -s` collapses **every** run of
spaces, including inside strings: `"a  b"` is written as `"a b"`, which
parses and is wrong (Codex; confirmed from the code).

- `tr -s ' '` goes. Nix doesn't care about repeated spaces outside
  strings, so collapsing them never helped.
- Newline → space stays, because the one-physical-line rule is what lets
  `nixarchy-opt-remove` find the line. But a multi-line value is
  **refused** (nothing written, reason shown) when flattening would
  change its meaning: when it contains `''` (indented strings are
  newline-significant) or `#` (a comment would swallow the rest of the
  flattened line).
- Known remaining gap, stated not solved: a raw newline inside a `"…"`
  string becomes a space. Detecting that needs a Nix lexer.
- The string widget's automatic quoting also escapes `${` as `\${`
  (`OptionForm.qml:174`). Today a typed `${HOME}` becomes an
  interpolation (Codex).

### 5. Enum choices: all or none

`choices` is filled only when **every** alternative after `one of ` is a
quoted string (escapes allowed) or an integer literal, i.e. the whole type
string matches

    ^one of ("([^"\\]|\\.)*"|-?[0-9]+)(, ("([^"\\]|\\.)*"|-?[0-9]+))*$

Otherwise the widget is `scaffold` and `describe` adds
`"choicesUnavailable": true`. The form then says "this type's
alternatives are not listed in a form this can offer — write a Nix
expression" (intent Q1: scaffold, not refusal). Mixed lists like
`one of "foo", 7`, which today yield a partial dropdown, go to all or
nothing too (Codex).

Integer choices are written unquoted (`8`), string choices quoted as today.

### 6. Responses are checked, and one write at a time

- `writeProc` and `describe` treat null or unparseable output as an error
  (today: success, and the form closes). `ok:false` shows `error`, falling
  back to `message` (`OptionForm.qml:86`).
- A form write sets `model.busy` for its duration, so `a` cannot start an
  apply while an option is being written (Codex: `OptionForm.qml:198` runs
  its own process and bypasses the guard at `PkgModel.qml:458`).
- Each `describe`/write response carries the path it was for. A late
  response for a form that has since closed, or opened on another
  option, is dropped.

### 7. Unset from the form: not now

Intent Q3: deferred. Removal from the list (SPACE) works. An "unset"
control in the form is easy to confuse with `null`, `false` or an empty
string.

## Alternatives rejected

- **Read the current value from `state.options[].line` in QML.** Search
  rows don't carry it, and it duplicates the marker parsing in JS.
- **Parse prose enums** (`hardware.nvidia.branch`). There is no list to
  parse; inventing one would write plausible, wrong configuration.
- **Keep `tr -s` and accept the damage.** It rewrites strings silently.
  A writer must not change a value that parses.
- **Teach `replace` to delete a scaffold's comment block.** That's another
  tool's format; comments left behind are harmless.

## Risks

- **Multi-line refusals.** A value that was accepted before (flattened,
  sometimes wrongly) is now refused if it has `''` or `#`. The message
  says why and what to do (put it on one line).
- **`describe` reading `apps.nix`** adds a file read to every form open.
  It's small and local.
- The enum regex is anchored and has no nested quantifiers over the same
  text, so no catastrophic backtracking.

## Verification

`tests/adapter.sh`, on the throwaway config:

1. `opt describe security.pam.oath.digits` → `widget: enum`,
   `choices: ["6","7","8"]`.
2. A prose `one of the …` type and a mixed `one of "a", 7` type →
   `widget: scaffold`, `choicesUnavailable: true` (options.json stub via
   `searched optionsjson`, or two real options found by jq in the test).
3. `current`: absent → `absent`; after `opt set X true` → `set`/`true`;
   on a scaffold line → `scaffold`.
4. `opt set X '"a  b"'` → the file contains `"a  b"` (double space kept).
5. A multi-line value with `''` → refused, file unchanged; the same with
   `#` → refused; a multi-line attrset with neither → one line, parses.
6. `opt replace` on a scaffold → a set line; then `opt remove` → the line
   goes and the file parses.

Panel: open a set boolean → shows its value; flip, write → `replace`,
file updated, no "remove it first". `security.pam.oath.digits` → `j`
chooses `7`, writes `= 7;`. `hardware.nvidia.branch` → the scaffold with
the explanation.
