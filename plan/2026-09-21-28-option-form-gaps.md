---
status: approved
issue: 28
spec: spec/2026-09-21-28-option-form-gaps.md
---

# Plan: the form offers what it can write, shows what is set, and changes it

## The approved decisions, in full

**`opt describe` reports `current`**: `{state:"absent"}`,
`{state:"scaffold"}` for a line `# <path> = ;  #@opt <path>`, or
`{state:"set", value:"<raw nix>"}` for `<path> = <value>;  #@opt <path>`,
with `value` verbatim. It is found by the same end-of-line marker rule as
the writers (string comparison, never a regex). The form labels it "set
in apps.nix": the local expression, never the evaluated value, never
coerced.

**Seeding.** Absent and scaffold seed the default as today (a scaffold
also gets a note). A set value the widget can hold exactly seeds the
widget: `true`/`false`; an integer literal; one of the enum's choice
tokens; a `"…"` string with no `\` and no `${`, shown unquoted. Any other
set value opens the scaffold editor with the raw expression. `touched` is
cleared after seeding, so an untouched form writes nothing.

**Writing.** `opt set` when absent, `opt replace` when set or scaffold.
Scaffold → value → later remove leaves the scaffold's doc comments behind
as plain comments. That's accepted, because `nixarchy-opt-remove` takes
the comment block only for the exact scaffold line.

**Fidelity.** Both writers drop `tr -s ' '`. Newline → space stays (the
one-line rule), but a multi-line value containing `''` or `#` is refused
with the reason. A raw newline inside `"…"` still becomes a space; that
is a known, stated gap. The string widget escapes `${` as `\${`.

**Enums: all or none.** `choices` is filled only when the whole type
matches
`^one of ("([^"\\]|\\.)*"|-?[0-9]+)(, ("([^"\\]|\\.)*"|-?[0-9]+))*$`.
Otherwise the widget is `scaffold` with `choicesUnavailable: true`, and
the form says "this type's alternatives are not listed in a form this can
offer — write a Nix expression". Choice tokens are written verbatim:
integers unquoted, strings quoted.

**Responses and concurrency.** Null or unparseable output from
`describe` or a write is an error, never success. `ok:false` shows
`error`, else `message`. A form write holds `model.busy`, so `a` can't
apply mid-write. Responses for a form that has closed, or that belong to
another path, are dropped.

**Not now:** unset from the form.

## Steps

1. **`bin/nixarchy-pkg`: one flattening helper.** Add
   `flat_value() { … }`, used by `cmd_opt_set` (`:450`) and
   `cmd_opt_replace` (`:535`) in place of their `tr` pipelines. It dies
   with `a multi-line value with '' or # cannot be written on one line
   without changing its meaning -- put it on one line yourself` when the
   value has a newline and contains `''` or `#`. Otherwise it maps
   `\n` → space and prints the value. No `tr -s`.
   -> verify by tests 4–5.

2. **`bin/nixarchy-pkg`: enum choices** (`:395-407`). In the jq, replace
   the `scan` with: if `$t` matches the anchored regex above, `choices` =
   the tokens (via `scan("\"([^\"\\\\]|\\\\.)*\"|-?[0-9]+")`) and
   `widget` = `enum`. If `$t` starts with `one of ` but does not match,
   `widget` = `scaffold` and `choicesUnavailable` = true.
   -> verify by tests 1–2.

3. **`bin/nixarchy-pkg`: `current`** in `cmd_opt_describe`. Before the
   jq, run one awk over `$APPS` with the path via `ENVIRON`. It finds the
   first line ending in `#@opt <path>` and prints `scaffold` if the
   left-trimmed line equals `# <path> = ;  #@opt <path>`, or `set` plus
   the text between `<path> = ` and `;  #@opt <path>`; nothing if absent.
   The result is passed to jq with `--arg` and emitted as `current`. A
   missing `$APPS` means `absent`.
   -> verify by test 3.

4. **`OptionForm.qml`: seeding** (`seed()` `:124`, `widget` `:44`). Add
   `property bool forceScaffold: false`, and make `widget` bind
   `forceScaffold ? "scaffold" : (option.widget || "")`. In `seed()`,
   with `current = option.current || {state:"absent"}`:
   - `set`: try the exact representations above for the widget. On a hit,
     seed it. On a miss, set `forceScaffold = true` and
     `scaffoldField.text = current.value`.
   - Otherwise as today.
   - Then `touched = false`. `begin()` resets `forceScaffold = false`.
   Add a caption line under the default: `set in apps.nix: <value>` for
   `set`, `a scaffold for this is in apps.nix` for `scaffold`, and the
   `choicesUnavailable` sentence when true.
   -> verify by panel checks 1 and 3.

5. **`OptionForm.qml`: writing** (`commit()` `:198`, `nixValue()`
   `:174`). The verb is `replace` when `option.current.state` is `set` or
   `scaffold`, else `set`. In the string case, after escaping `\` and `"`,
   also `.replace(/\$\{/g, "\\${")`.
   -> verify by panel check 1, and by writing `${HOME}` into a string
   option giving `"\${HOME}"` in apps.nix.

6. **`OptionForm.qml`: responses and concurrency.**
   - Add `property string pendingPath`. `begin()` sets it for `describe`,
     and `commit()` sets it for the write.
   - Both `onStreamFinished` return at once if `!root.open ||
     root.pendingPath !== root.path`.
   - `describe`: unparseable → error "could not read that option" (as
     today).
   - `writeProc`: `data === null` → `root.error = "the adapter gave no
     answer; nothing is known to be written"` and stay open. `ok:false` →
     `error || message`.
   - `commit()` sets `root.model.busy = true` before starting.
     `writeProc`'s finish handler sets it false as its **first**
     statement, before the `open`/`pendingPath` early return, or a form
     closed mid-write would leave the panel busy forever. `commit()` does
     nothing while `model.busy`.
   -> verify by panel check 4.

7. **`tests/adapter.sh`**, in the `options` section, using
   `fresh_config`:
   1. `opt describe security.pam.oath.digits` → `.widget == "enum" and
      .choices == ["6","7","8"]`. Skip with a note if the option is
      absent from this system's options.json.
   2. The first option whose type starts `one of ` and fails the regex
      (found with jq over options.json in the test) → `.widget ==
      "scaffold" and .choicesUnavailable`.
   3. `current`: before → `absent`; after `opt set programs.mtr.enable
      true` → `set`/`true`; a hand-written scaffold line → `scaffold`.
   4. `opt set services.x.y '"a  b"'` (a string option) → apps.nix
      contains `"a  b"`.
   5. A value `"{\n  a = ''x'';\n}"` → `ok:false`, file byte-identical; the
      same with `# c` → refused; `"{\n  a = 1;\n}"` → written as one line
      and parses.
   6. `opt replace` on a scaffold line → a set line; `opt remove` → gone,
      file parses.
   -> verify by `bash tests/adapter.sh` → `all passed`.

## Found while implementing

- **Step 1: `flat_value` returns 1, the caller dies.** It runs inside
  `$(...)`, where `die`'s JSON would become the value and the subshell's
  exit would be 0.
- **Step 6: two guards, not one `pendingPath`.** A single property set by
  both `begin()` and `commit()` would let a late write for option A close a
  form just opened on option B. `describe` responses are matched on the
  `path` they carry; writes on a separate `writingPath`.
- **Step 7: the scaffold fixture goes inside the module.** Appended to the
  end of the template, it sat after the module's closing brace, and
  `replace` was right to refuse the result. `add_scaffold` inserts it where
  nixarchy-search does.
- **Docs.** The README's option-form section and `docs/manual/options.md`
  said the form always shows the default. The manual also said RETURN
  removes a set option; it is SPACE, and RETURN now changes it.

## Tests

    nix flake check
    bash tests/adapter.sh
    nix build .#default && omarchy plugin validate ./result

Panel, by a person:

1. Set `programs.mtr.enable = true`; open it again → toggle shows on,
   caption `set in apps.nix: true`. SPACE, RETURN → apps.nix says
   `false`, no "remove it first".
2. `security.pam.oath.digits` → dropdown 6/7/8; `j`, RETURN → `= 7;`.
3. `hardware.nvidia.branch` → the scaffold editor with the "not listed"
   sentence; ESC writes nothing.
4. Write a value and press ESC before it returns; `a` → "still writing";
   the form doesn't reopen or close something else when the write lands.

## Rollback

`git revert` the implementation commit. The line format is unchanged, so
files written by the new code are read by the old. The only behavioural
loss on revert is the multi-line refusal.
