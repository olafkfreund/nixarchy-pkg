---
status: draft
issue: 61
intent: intent/2026-11-16-61-option-forms.md
---

# Spec: the option form can set the options people actually set

## Design

### Decisions for the owner

The intent's questions 1 to 4 had no recommendation. These are my choices;
each can be overturned at this gate.

1. **Multi-line values: no marked block in this task.** A value is still
   written on one line, but never with a changed meaning. Section S1 does
   it with two checks Nix itself answers: a flattened value is accepted only
   if `nix-instantiate --parse` gives the same tree for it as for the value
   as typed, and a value that is one string literal (the `extraConfig`
   case) is rewritten as an equivalent one-line `"…"` string with `\n`
   escapes. That meets the intent's outcome ("written without changing its
   meaning, and removable by the same tools") with no change to
   `nixarchy-opt-remove`, `checks.options` or #60's queue. The cost is
   readability: a ten-line `extraConfig` reads as one long line in
   `apps.nix`. The `#@opt-begin` / `#@opt-end` block is a follow-up issue
   (companion issue C2), not this task.
2. **`null`: offered on every nullable widget.** An explicit `null` is
   not the same as unset even when the documented default is `null`:
   another module's `lib.mkDefault` shows through when the panel's line is
   absent, and an explicit `null` overrides it (Codex review). Unset stays
   "write nothing" / remove.
3. **Package widget: exact attribute from the index, default channel
   only.** It writes `pkgs.<attr>`. Anything else (an override, the other
   channel, `lib.mkForce`) stays a scaffold. The widget is offered only when
   `apps.nix`'s header binds `pkgs`. Otherwise the form says why and opens
   the scaffold.
4. **Names: plain names and quoted keys, spaces allowed.** The installed
   `nixarchy-opt-remove` already compares the marker as a string, suffix
   match, so a quoted key with spaces is removable today (checked: its
   `remove_one`). The readers that split at whitespace are this repo's own
   (`extras_tsv`, #60's `pending` marker), and S6 fixes them. Refused inside
   a name: `"`, `\`, `$`, a newline, a tab and `#@`. `\` is refused because
   the remover passes the path through `awk -v`, which processes escapes.

### Decisions from intent approval

5. One intent, delivered as six slices that ship one by one, in the order
   below. Each slice is one PR against main after #60 (PR #70) has merged.

### Correction to the intent

The intent says most secret-like options have a `*File` sibling. Measured
on razer's `options.json` (2026-11-16): of 195 settable string options
named `*password`, `*secret`, `*token`, `*apiKey`, `*privateKey`,
`*presharedKey` or `*psk`, **34** have a sibling `<name>File`. S4 therefore
names the sibling only when it exists, and warns either way.

### Measured

On razer's `options.json` (11.8 MB, 25,980 settable options), this host:

| | today | after S5 |
|---|---|---|
| options with a widget | ~13,900 | ~22,000 (85%) |
| `null or <scalar>` | scaffold | 4,218 widgeted |
| `list of` string, integer or port | scaffold | 1,835 widgeted |
| `package` / `null or package` | scaffold | 1,507 widgeted |
| `strings concatenated with "\n"` (`lines`) | scaffold | 549, multi-line text |
| templates with `<name>` or `*` | unsettable | 5,314 settable by name |

- `jq` lookup of one option: 0.24 s. Scanning all templates for a concrete
  path: 0.36 s. Both run once per form open.
- `nix-instantiate --parse` of a value: 0.027 s. S1 adds two per write.
- Descriptions with nixpkgs role markup (`{option}`, `{manpage}`, `{file}`,
  `{command}`, `{var}`, `{env}` and six rarer roles): 2,466. With
  `::: {.note}` / `{.warning}` blocks: 330.
- Integer types: 841 are `16 bit unsigned integer; between 0 and 65535`,
  474 `signed integer`, 142 `unsigned integer, meaning >=0`, 88 `positive
  integer, meaning >0`, 33 `integer between 300 and 399`, 13 `32 bit
  unsigned integer` (max 4294967295, above QML's `int`).

### Against main + #60

#60 (branch `feat/60-truthful-queue`) rewrites `pending` and moves line
numbers. Where they differ, this spec cites main and then #60:
`extras_tsv` main `:330` / #60 `:355`; `cmd_search` `:374` / `:399`;
`cmd_opt_describe` `:592` / `:617`; `flat_value` `:695` / `:720`;
`cmd_opt_set` `:724` / `:749`; `cmd_opt_replace` `:821` / `:846`; the
`pending` marker `def marker` exists only in #60 (`:1470`). #60 counts
`unmarked` changed lines per file; because S1 keeps every option on its
marked line, this task adds no unmarked lines to that count.

---

### S1. A multi-line value keeps its meaning

`flat_value` (main `bin/nixarchy-pkg:695-706`) is replaced. It still
refuses `#@` (status 2). The rest moves into the writers, which can see the
file:

1. **One string literal.** Decided by Nix's own parser, not by looking
   at the ends: `nix-instantiate --parse -E "($value)"` must print only
   string literals joined by ` + `, matching
   `^\(?"(?:[^"\\]|\\.)*"(?: \+ "(?:[^"\\]|\\.)*")*\)?$`. That
   rejects `"a" + builtins.getEnv "X" + ""` (it prints a call) and any live
   interpolation, including `"\\${x}"`, whose escaped backslash leaves
   `${x}` live (it prints a variable, or fails on an unbound one).
   Measured: a `''…''` block with `''${` prints as
   `("a \"q\" \\\\ #c\n" + "$" + "{x} $y\n")`, all literal. Only then is it
   decoded with `nix-instantiate --eval --strict --json --readonly-mode
   --option pure-eval true --option restrict-eval true -E "$value"` (a
   literal has nothing to evaluate) and re-emitted as one Nix `"…"`
   literal: `\` → `\\`,
   `"` → `\"`, newline → `\n`, tab → `\t`, CR → `\r`, `${` → `\${`. Any other
   control character refuses. The `#@` check runs again on the emitted
   literal: Nix decodes `"#\@pkg x"` to `#@pkg x` (Codex reproduced it),
   so a marker can be forged through an escape. Measured: a nine-line
   `''…''` block with `#`, quotes and `''${` comes back exact in 0.026 s.
2. **Anything else with a newline.** Newlines become spaces, as today. The
   candidate file is built twice, once with the value as typed and once
   flattened, and both go through `nix-instantiate --parse` with the user's
   own header. If the two printed trees differ, the write is refused with
   "that value changes meaning on one line -- … Nothing was changed."
   Measured: `[ 1⏎ 2 ]` is accepted; `[ "a⏎b" ]`, `{ a = 1; # c⏎ b = 2; }`
   and `''⏎x⏎''` (not via rule 1) are refused.
3. A value with no newline is unchanged.

`FLAT_REFUSAL` (main `:693`) is reworded to name rule 2's case. The
scaffold field keeps its multi-line editor (`OptionForm.qml`, the
`scaffoldField`), and the `lines` type opens it too (S5).

### S2. Reading: markup, search rows, set vs scaffold

- **Descriptions.** `reflow` (`OptionForm.qml:61-68`) also turns
  `` {role}`text` `` into `text` for any lower-case role, and a line
  `::: {.note}` / `::: {.warning}` into `Note:` / `Warning:`, dropping the
  closing `:::`. The `Text` stays `textFormat: Text.PlainText`
  (`:364-371`).
- **Search rows.** `cmd_search` adds, for `kind == "opt"` rows only, `set`
  (`true | false | null`, null when absent) and `current` (the expression
  as written, or `null`), joined from `extras_tsv` by exact path. Option
  rows draw `type` beside the summary instead of falling back to it
  (`Card.qml:232-233`), and a set row draws its current value.
- **Options tab.** `state.options` rows already carry `set`
  (main `:1530-1532`). `Card.qml:157-159` draws `■` for `set: true` and
  `□` for a scaffold on option rows, as catalogue rows already do with
  `enabled`.

### S3. Integers, and taking a value out

- **Integer widget.** `cmd_opt_describe` returns `min` and `max` as
  strings (or `null`) parsed from the type: `positive integer` → `"1"`,
  `unsigned integer` → `"0"`, `N bit unsigned integer; between A and B`
  and `integer between A and B` → `A`, `B`; plain `signed integer` → both
  `null`. The widget becomes a `TextField` taking an optional `-` and
  digits with no leading zero, with Up/Down stepping by one. It gets the keyboard on open
  (`OptionForm.qml:222-224` gains `integer`). The range is checked in QML
  by string comparison (length, then lexical), not `Number`, because
  64-bit bounds exceed JavaScript's exact range, and checked again in the
  adapter: `opt set` and `opt replace` read the option's type from
  `options.json` (the same lookup as describe) and refuse an out-of-range
  integer before `guard`. Types with no stated bound (`signed integer`,
  `unsigned integer`) are still bounded by Nix's 64-bit integer, so
  `max` is `"9223372036854775807"` and `min` `"-9223372036854775808"`
  for them. `NumberField`
  (`:442-447`) is removed; its `int` caps at 2147483647.
- **Unset from the form.** A form opened on a set option gets `DEL`:
  "remove this from apps.nix". It arms first, as `SHIFT+RETURN` does for
  the other channel (`PkgModel.qml:419-437`): the first press says what
  will happen, the second runs `opt remove`. Known limit: the installed
  `nixarchy-opt-remove` ends with `mv "$tmp" "$file"`, which replaces a
  symlinked `apps.nix` with a regular file. That is one of the five
  external writers #59 left to its nixarchy follow-up; the unset action
  inherits it until that lands, and the panel's existing SPACE removal has
  the same limit today. Emptying a set string field
  and pressing RETURN arms the same removal instead of closing silently.
  An untouched form still writes nothing.
- **`""`.** Typing `""` writes an empty string; the field already passes
  input starting with `"` through (`OptionForm.qml:254`). The placeholder
  (`:453`) and the help line (`:557-558`) say "empty keeps the current
  value" when the option is set, and "empty keeps the default" when not.

### S4. Secrets

`cmd_opt_describe` adds `sensitive: true` when the last path component
matches `(?i)(password|passwd|secret|token|apikey|privatekey|presharedkey|psk)$`
and the type contains `string`, and `fileOption`: the path with `File`
appended to the last component, when that key exists in `options.json`,
else `null`. The form shows, above the field:

> This value is copied into the Nix store, which every user on this
> machine can read. *(If `fileOption`:)* `<fileOption>` reads it from a
> file at run time instead -- give it the path as a quoted string,
> `"/run/secrets/…"`, so the file itself is not copied into the store.

It is a warning; the write goes ahead. Path-typed options already get a
quoted string from the string widget (`OptionForm.qml:257-261`), so a
`*File` value written through it is never a path literal.

### S5. Widgets for the common types

`cmd_opt_describe`'s `widget` (main `:652-658`) is rebuilt from one scalar
grammar, matched whole:

- scalar: `boolean`; a listed enum (unchanged); the integer types in S3;
  `string`, `path`, `strings concatenated with "\n"` (multi-line), and
  three constrained strings, each with its check returned as
  `constraint` and enforced in the form and again in the adapter before
  `guard`: `non-empty string` (`nonEmpty`), `absolute path` (`absolute`:
  starts with `/`), `string, not containing newlines or colons`
  (`noNewlineColon`). The checks apply to list items too. `string
  matching the pattern …` stays a scaffold: the form cannot check the
  pattern.
- **Where the adapter checks.** The range and `constraint` checks in
  `opt set` / `opt replace` run only on a value that parses as a literal
  of the expected kind: an integer literal, a single string literal
  (checked on its decoded text, so `"/etc/foo"` is absolute and `"a\nb"`
  contains a newline), or a list of those. `null` passes on a nullable
  option. Any other expression (`lib.mkForce 80`, `pkgs.foo + "/bin"`) is
  the scaffold's business and is not checked. With no `options.json`, or
  an option it does not list (a custom module's), the CLI writes as it
  does today, unchecked.
- `null or <scalar>`, parenthesised or not → the scalar's widget with
  `nullable: true`.
- `list of <string or integer scalar>` → `widget: "list"`, `item:
  "string" | "integer"`, `min`/`max` for the item. A multi-line field
  with **one item per line**, written as `[ "a" "b" ]` / `[ 80 443 ]`.
  Not split on spaces or commas: `boot.kernelParams` items like
  `console=ttyS0,115200n8` hold both. Each string line is escaped as the
  string widget escapes (`\`, `"`, `${`). The field containing exactly
  `[ ]` writes an empty list; an empty field writes nothing.
- `package` / `null or package` → `widget: "package"`, only when the
  header binds `pkgs` (decision 3): the search field over the package
  index the panel already has (`PkgModel.runSearch`), writing
  `pkgs.<attr>`.

A value already set that the widget cannot hold exactly still opens as the
raw expression (`OptionForm.qml:190-211`, unchanged). The QML seed gains
cases for `list` (parse `[ … ]` of simple literals only) and `package`
(`pkgs.<attr>` only); anything else forces the scaffold.

Response, additive (every field present on every answer):

```json
{"ok": true, "path": "services.openssh.ports", "type": "list of 16 bit unsigned integer; …",
 "widget": "list", "item": "integer", "nullable": false, "min": "0", "max": "65535",
 "choices": [], "choicesUnavailable": false, "sensitive": false, "fileOption": null,
 "template": null, "names": [], "current": {"state": "absent"}, "…": "existing fields"}
```

### S6. Options under `<name>` and quoted keys

- **Path grammar.** Replaces the `*[!a-zA-Z0-9._-]*` check in
  `cmd_opt_set` and `cmd_opt_replace` (main `:729`, `:827`): one or more
  components joined by `.`; a component is a Nix identifier
  `[A-Za-z_][A-Za-z0-9_'-]*` that is not a keyword (`if then else assert
  with let in rec inherit or`), or a `"…"` with none of decision 4's
  refused characters. Codex confirmed `services.123.enable`,
  `services.'a.enable` and `services.if.enable` do not parse bare. `<name>` and `*` are
  refused here: a template is never written.
- **Describe a concrete path.** When `.[$p]` is null (main `:634-635`),
  `cmd_opt_describe` splits the path into components (quotes respected)
  and looks for the template with the same number of components where each
  is equal or is `<name>` / `*`. An exact key wins; then the template with
  the fewest placeholders. The answer is that template's, with `path` the
  concrete one, `template` the key, `names` the filled-in components, and
  `current` read for the concrete path.
- **Open a template.** A search row whose path has placeholders opens the
  form with one name field per placeholder above the widget. A name is
  written bare when it is a non-keyword identifier as above, otherwise
  quoted (`"123"`, `"if"`, `"/mnt/usb drive"`). RETURN is refused until every name is filled.
- **Readers.** The marker is everything after `#@opt ` to the end of the
  line, trailing whitespace trimmed. That changes `extras_tsv`'s
  `/#@opt [^ \t]+/` (main `:339`), and in #60's `pending`, `def marker`
  (#60 `:1470`) takes the rest of the line when the type is `opt` and the
  first token otherwise (catalogue rows keep a note after their marker).
- **Matching.** Every `grep -q "#@opt ${path//./\\.}\$"` (main `:744`,
  `:774`, `:837`, `:863`) becomes the awk end-of-line string comparison
  `cmd_opt_describe` already uses (`:604-606`), so a quoted key's `*` or
  `[` is not a pattern.

---

## Alternatives rejected

- **Marked multi-line blocks now.** Needs `nixarchy-opt-remove`,
  `checks.options` and nixarchy-search's picker changed first, and #60
  would count the block's inner lines as unmarked edits. Deferred (C2).
- **`nix-instantiate --parse` output as the written value.** One line,
  but it rewrites the user's expression (`${x}` becomes `"…" + x`, paths
  become absolute: measured) and is not readable.
- **Keep `NumberField` and raise its bounds.** Its `int` properties stop at
  2147483647 and cannot hold `32 bit unsigned` or 64-bit values.
- **Refuse names with spaces.** The remover handles them; only our own
  readers did not, and those are fixed in S6.
- **A secret refusal.** The intent made the warning advice only.
- **Resolve templates in QML.** The adapter already owns `options.json`;
  one lookup there keeps CLI and panel in agreement.

## Risks

- **S1 parse comparison is stricter than needed.** A value whose meaning
  survives flattening but whose printed tree differs (none found) would be
  refused, not corrupted. Refusal is the safe direction.
- **S1 evaluation of user input.** Only for a whole string literal with no
  live interpolation, under `pure-eval`, `restrict-eval` and
  `--readonly-mode`: no file reads, no store writes, no environment.
- **S6 changes the marker readers.** A line written today has no space in
  its path, so the old and new readers agree on every existing file; tests
  pin that. nixarchy-search's own duplicate check is a regex (nixarchy
  `modules/apps.nix:2894`) and may misjudge a quoted key the panel wrote;
  companion issue C1.
- **Template ambiguity.** Two templates can match one concrete path; the
  exact-then-fewest-placeholders rule picks one. The form shows the
  template it used.
- **Package widget and the header.** Checked by parsing the header's
  formals; a header that binds `pkgs` some other way (`args@{…}`) falls
  back to the scaffold, which still works.
- Host: none of this touches a rebuild. Verification on razer.

## Verification

- **Fixture catalogue.** A small `tests/fixtures/options.json` with one
  option per family below, served through a stub `nixarchy-search` on
  `PATH` whose `optionsjson=` line points at it (the adapter reads the
  path from that line, `bin/nixarchy-pkg:244-248`). These tests run
  everywhere, CI included. The existing real-catalogue checks
  (`tests/adapter.sh:311-361`) stay as integration coverage.
- **`tests/adapter.sh`**, one block per slice:
  - S1: the four measured cases above; a `''…''` with `''${` round-trips
    (written line evaluates to the same string); `"a" + builtins.getEnv
    "X" + ""` and `"\\${x}"` are not treated as literals; `"#\@pkg x"`
    is refused by both `set` and `replace`; a refused value leaves
    `apps.nix` byte-identical.
  - S2: `search` option rows carry `set`/`current`; a scaffold row has
    `set: false`.
  - S3: describe gives `min`/`max` for each integer family; `opt set` of
    `70000` on a port and `-1` on an unsigned refuses, and so does `opt
    replace`; `4294967295` on a 32-bit unsigned writes; signed comparison
    (`-10` < `-9`) and leading zeros (`007`, refused as ambiguous) are
    pinned.
  - S4: `users.users.<name>.hashedPassword` is `sensitive` with its
    `…File`; `services.openssh.enable` is not.
  - S5: widget, `item`, `nullable`, `constraint` for one option of each
    family; `""` refused on a non-empty string, `relative/path` on an
    absolute path, also as a list item; a quoted list item with a space
    round-trips; `package` falls back with a `{ ... }:` header.
  - S6: `opt set 'fileSystems."/mnt/usb drive".options' '[ "nofail" ]'`
    writes, `state` lists the full path, `opt describe` reopens it,
    `opt replace` changes it, and the installed `nixarchy-opt-remove`
    removes it; a path with `\`, `$` or `#@` is refused; a template path
    is refused; `"123"` and `"if"` names are written quoted and parse.
- **QML** (`tests/qml/`): new `tst_optionform.qml` with stub `TextField`
  and `Toggle` under `tests/qml/imports/qs/Ui/`: integer focus and
  Up/Down, range refusal, `DEL` arming, emptying a set field arms removal,
  name fields block RETURN until filled, markup stripping.
- **Manual on razer:** set `services.openssh.ports`, a user's shell by
  name, a multi-line `extraConfig`; rebuild with `nixarchy-apply`; remove
  each from the panel.
- `nix flake check` (shellcheck) stays clean.

## Companion nixarchy issues

**C1. nixarchy-search: find `#@opt` lines by string, not regex.**
`add_option`'s duplicate check is `grep -q "#@opt $path\$"`
(`modules/apps.nix:2894`). nixarchy-pkg now writes option paths with quoted
keys (`fileSystems."/mnt/usb drive".options`), where `.` and other
characters are regex metacharacters. The check can then match the wrong
line, or miss the right one and add a duplicate. Compare the marker as a
string at end of line, as `nixarchy-opt-remove` already does.

**C2. A marked multi-line option block (`#@opt-begin` / `#@opt-end`).**
Today every option is one line, so a multi-line `extraConfig` is stored as
one long escaped string. A block form would keep `apps.nix` readable and
diffs small. It needs `nixarchy-opt-remove` to delete the whole block,
`checks.options` to assert the new form, and nixarchy-search's picker to
list it. nixarchy-pkg's #60 queue would also need to count the block as
one change. Filed as a follow-up to nixarchy-pkg #61.
