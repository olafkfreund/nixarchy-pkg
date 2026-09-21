---
status: draft
issue: 28
author: olafkfreund
---

# Intent: numeric enums cannot be set, and a set option cannot be changed

## Problem

Two gaps in the option form, both found by using it on razer.

**An enum whose alternatives are not quoted strings gets an empty form.**
`opt describe` decides `widget: "enum"` from a type starting `one of `,
then collects the choices by scanning for quoted strings
(`bin/nixarchy-pkg:406`). `security.pam.oath.digits` is `one of 6, 7, 8`,
so it comes back with `choices: []`. The form draws an empty dropdown,
`j`/`k` do nothing, and RETURN closes it without a word. Nothing is
written and nothing says why. razer's options include 12 of these, among
them `hardware.nvidia.branch` (`one of the available driver branches in
…`), which is prose rather than a list and exactly the option an NVIDIA
laptop owner might come looking for.

**An option that is already set cannot be changed from the panel.**

1. Set `programs.mtr.enable = true` from the form. It works.
2. Open it again. The form shows **false**, the option's default, not
   the `true` in `apps.nix`.
3. Flip it and write. The result is `programs.mtr.enable is already in
   …/apps.nix -- remove it first`.

#19 added `opt replace` to the adapter for exactly this case, as one
command that changes a value or leaves the file untouched. Nothing in the
QML calls it: `OptionForm.qml:198` always sends `opt set`. So the path
the panel offers is remove, then set: two keypresses on two surfaces with
no backup covering the pair, which is the gap `replace` was written to
close.

## Proposed outcome

- Every option the form opens either offers a real control that can write
  a value, or says plainly that it cannot and why. It never closes
  silently with nothing written.
- A numeric enum offers its numbers.
- Opening a set option shows its current value, and writing a different
  one changes it in place.

## Affected users and systems

- Anyone setting NixOS options from the panel.
- `bin/nixarchy-pkg` `cmd_opt_describe` (the choices), possibly returning
  the current value.
- `OptionForm.qml`: the seed, the commit path (set vs replace), and the
  message when there is nothing to offer.
- `tests/adapter.sh`.

## Constraints

- The byte-exact `#@opt` line format is untouched. `replace` already
  writes it; this only wires it in.
- "An untouched field writes nothing" still holds. Showing the current
  value must not make an untouched form rewrite the same line.
- A prose enum like `hardware.nvidia.branch` has no machine-readable list.
  The form must not invent one.

## Open questions

1. **Prose enums: scaffold or refusal?** Fall back to the free-text
   scaffold with the option's example, or say "this type's choices are not
   listed" and offer nothing. The scaffold is more useful and is what the
   form already does for other types it can't widget.
2. **Where does the current value come from?** The `line` field `state`
   already returns for each option (`programs.mtr.enable = true;`), parsed
   in QML, or a new field from `opt describe`. The existing field avoids a
   second read.
3. **Should removing an option be reachable from the form too**, as an
   "unset" choice, instead of only via SPACE on the list?
