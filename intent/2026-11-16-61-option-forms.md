---
status: draft
issue: 61
author: olafkfreund
---

# Intent: the option form can set the options people actually set

## Problem

#28 fixed two gaps in the option form: numeric enums now offer their
numbers, and a set option opens on its value and is changed with `opt
replace`. It left the rest on purpose. Its constraint was that lists,
`null or T` and other types "fall through to the scaffold" rather than
risk wrong configuration (`bin/nixarchy-pkg:586-591`), it noted that a
newline inside `"…"` still becomes a space (`:686-687`), and it deferred
"unset from the form" (`spec/2026-09-21-28-option-form-gaps.md` §7).
Using the form since shows how much is left.

Counted on razer's `options.json` (not read-only, 25,980 options): about
12,080 (nearly half) get no widget, only a raw Nix scaffold. Some cannot be set at all.

**Options with a `<name>` or a quoted key cannot be set.** `opt set` and
`opt replace` refuse any path outside `[a-zA-Z0-9._-]`
(`bin/nixarchy-pkg:729`, `:827`). 5,314 option paths contain `<name>`,
`*` or a quoted key: `users.users.<name>.shell`,
`systemd.services.<name>.serviceConfig`, `services.nginx.virtualHosts.<name>`,
`fileSystems.<name>.device`. The form opens on the template path, offers no
place to say which user or service, and fails on submit. A concrete path
with a plain name (`users.users.alice.shell`) passes the check from the
CLI, but one that needs a quoted key (`fileSystems."/".options`,
`services.nginx.virtualHosts."example.org"`) is refused there too. And a concrete path, once set, cannot be
reopened: `opt describe` looks the literal path up in `options.json`
(`bin/nixarchy-pkg:634-635`), which holds only the `<name>` template,
so it answers "no such option".

**Common types get no widget.** `widget` is `boolean`, `enum`, `integer`,
`string` or `scaffold` (`bin/nixarchy-pkg:652-658`). Everything else is
a scaffold, including 4,105 `null or <scalar>` options, 1,635
`list of string`/`list of int`/`list of port` options (firewall ports,
`extraGroups`) and 1,491 `package` options. The person has to write Nix
for a value that is one word or a list of numbers.

**Integers cannot be set from the keyboard.** For an integer the form
gives focus to itself, not to the number field (`OptionForm.qml:222-224`),
and its key handler has no case for integers (`:305-317`). The field's
bounds are fixed at ±2147483647 (`:444-445`) whatever the type says, so
an `unsigned integer` accepts negatives and a port accepts 70000 (the
rebuild then refuses it, minutes later), while a `32 bit unsigned
integer` above 2147483647 cannot be entered at all.

**Clearing a value keeps it, silently.** An empty value closes the form
without writing (`OptionForm.qml:276`). That is right for an untouched
form, but a person who empties a set string field to remove it sees the
form close and the old value stay, under a placeholder that says
"leave empty to keep the default" (`:453`). The only removal is SPACE on
the list, and an empty string `""` cannot be written from the field.

**Multi-line values are flattened or refused.** `flat_value` turns every
newline into a space (`bin/nixarchy-pkg:705`), including newlines inside
a `"…"` string, which changes the value. It refuses a multi-line value
that also contains `''` or `#` (`:702-703`), so a multi-line
`extraConfig` written as a `''…''` block, the commonest multi-line value,
cannot be written as typed. The one-line rule exists
because `nixarchy-opt-remove` deletes only the line with the marker
(`:674-680`).

**Finding and reading options is harder than it needs to be.** The
Options tab lists the options already set (`PkgModel.qml:96`, state
`options` at `bin/nixarchy-pkg:1530`), but a search result shows one
of summary, note or type, whichever is present first, and never whether
the option is set or its current value (`Card.qml:232-233`), though `opt
describe` already returns it (`bin/nixarchy-pkg:664-667`). On the
Options tab a set option and a commented scaffold draw the same `·`
glyph (`Card.qml:157-159`), so the list does not say which are set.
Descriptions are shown with nixpkgs markup such as ``{option}`foo` ``
left in (`OptionForm.qml:61-68`; 1,167 descriptions have it).

**Secrets go to the world-readable store, with no warning.** A value
written for `*Password`, `*Key`, `*Token` or `*Secret` (170 options)
ends up in `apps.nix`, which the flake copies into `/nix/store`, readable
by every user. Most have a `*File` sibling that takes a runtime path and
keeps the secret out of the store, but only when the path is a quoted
string: an unquoted Nix path literal copies the file into the store
anyway. The form says nothing about any of this.

## Proposed outcome

- Every option the form opens either writes a correct value or says
  plainly why it cannot. None fails on submit after accepting input.
- An option under `<name>` asks for the name, and the concrete path is
  written, can be reopened on its value, changed, and removed again. Quoted keys like `fileSystems."/"`
  can be set from the form and the CLI.
- `null or <scalar>`, lists of strings or numbers, and `package` options
  get a widget a person can fill without writing Nix. Everything else
  keeps the scaffold.
- Integers can be typed and stepped from the keyboard, within the bounds
  their type declares.
- Emptying a set value never silently keeps it: the person can remove
  the option from the form, knowingly. An untouched form still writes
  nothing.
- A multi-line value is written without changing its meaning, and can be
  removed again by the same tools that remove a one-line value.
- Search results show an option's type, whether it is set, and its
  current value as written in `apps.nix`. The Options tab tells a set
  option from a scaffold.
  Descriptions read as prose, without markup.
- Setting a secret-like option warns that the value lands in the
  world-readable store, and points to the `*File` option when there is
  one, with its value as a quoted runtime path.
- Tests cover each of these.

## Affected users and systems

- Anyone setting NixOS options from the panel or with `nixarchy-pkg opt`.
- `bin/nixarchy-pkg`: `cmd_opt_describe` (widgets, bounds, sibling
  `*File`), `cmd_opt_set`, `cmd_opt_replace`, `flat_value`, the path
  check, `extras_tsv`, search rows.
- `OptionForm.qml` (widgets, focus, clear, warnings, description),
  `Card.qml` (result rows), `PkgModel.qml`.
- Outside this repo: `nixarchy-opt-remove`, `nixarchy-search` and
  nixarchy's `checks.options`, which read the same `#@opt` lines. A new
  line or marker form needs them to agree, which may need a companion
  nixarchy change.
- `tests/adapter.sh`, `tests/qml/`, `docs/manual/options.md`, README.
- Verification host is razer, per repo convention.

## Constraints

- The panel writes only its own marked lines in `apps.nix`. It never
  edits a line it did not write, and never needs root. Apply is the only
  thing that rebuilds.
- The existing one-line `#@opt` format keeps working: lines written today
  are still read, replaced and removed. Any new form is additive.
- Every option written, all of its lines and any quoted path, must stay
  removable by the `nixarchy-opt-remove` installed on that machine, and
  stay visible to this adapter's own readers (`extras_tsv`, `marked`,
  `pending`, which today split a marker at the first space). A new line
  shape is never written where the installed remover cannot remove it.
  A line nothing can remove again is the failure #28 and #41 guarded
  against.
- A path is matched as a string, never as a pattern: a quoted key can
  carry regex metacharacters (today's `grep "#@opt ${path//./\\.}$"`,
  `bin/nixarchy-pkg:744`, would misread one).
- Option text from nixpkgs stays `Text.PlainText`. Removing markup must
  not switch to rich text (`OptionForm.qml:364-371`).
- A widget's value must parse in the user's `apps.nix` as it is, without
  editing its header: `pkgs.foo` fails in a file whose header is
  `{ ... }:` (`bin/nixarchy-pkg:778-782`).
- "An untouched field writes nothing" still holds.
- No widget may write a value the type does not accept. When a type
  cannot be represented exactly, it stays a scaffold.
- A value already in `apps.nix` that a new widget cannot hold exactly
  (`lib.mkDefault pkgs.foo`, a conditional) still opens as the raw
  expression and is never reduced to what the widget can show, as #28
  settled (`OptionForm.qml:190-211`).
- For `null or T`, setting `null` explicitly and leaving the option
  unset stay two different things, because the default is not always
  `null`.
- A path from a typed name must not be able to forge a marker or escape
  the attribute it names (the `#@` rule from #41 applies to names too).
- #39's and #59's write discipline (in-place copy keeping inode, mode
  and symlink; backup, lock, restore, recover) applies to any new write
  path.
- The secret warning is advice. It does not refuse the write, and the
  panel does not manage secrets itself.

## Open questions

1. **Is real multi-line support in scope?** Writing a multi-line value
   as typed needs a marked block (the issue suggests `#@opt-begin` /
   `#@opt-end`), which `nixarchy-opt-remove` and `checks.options` do not
   know, so nixarchy changes first. The smaller alternative is to keep
   one line and refuse, rather than corrupt, a value whose newline sits
   inside `"…"`. If the owner picks the smaller one, the multi-line
   outcome above is deferred to its own issue.
2. **Is `null` worth a control?** The constraint above keeps "null" and
   "unset" apart. Is offering an explicit `null` needed now, or is "leave
   it unset" enough for this task?
3. **Package widget scope.** Pick from the existing package index (exact
   attribute only, `pkgs.<attr>`), or also allow an expression? The
   index knows one channel only.
4. **Which `<name>` families must work?** Users, groups and systemd
   units take plain names. File systems, virtual hosts and many others
   need quoted keys. Supporting only plain names is smaller but leaves
   the quoted-key outcome above unmet; the owner decides which. If
   quoted keys are in, may they hold spaces? A space breaks today's
   marker readers.
5. **One issue or several?** This is seven separate gaps. Recommended:
   one intent, and the spec splits delivery into independent slices
   (paths, widgets, integers/clear, multi-line, search and reading,
   secrets) that can ship one by one.
