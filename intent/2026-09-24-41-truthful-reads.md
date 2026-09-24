---
status: draft
issue: 41
author: olafkfreund
---

# Intent: the adapter does not describe a file it could not read

## Problem

#39 fixed the write path: a write now either happens as reported or is
reported as not happening. The read and validation paths still have the same
class of defect, and all of it was re-verified on `main` at `7dce7f8`
before this was written -- one of the three claims in #41 did not survive
that, and is corrected below.

**1. An unreadable selection file is reported as an empty one.**
`rows_tsv` (`bin/nixarchy-pkg:104`) guards `[ -f "$file" ]`, not
`[ -r ]`, and awk's failure goes to stderr where the panel never sees it.

```
$ chmod 000 apps.nix && nixarchy-pkg state
awk: fatal: cannot open file '.../apps.nix' for reading: Permission denied
{ "ok": true, "apps": [], "services": [ ...12 rows... ] }     exit 0
```

The panel receives a well-formed success object: Apps empty, Services
populated. That reads as a fresh install with services available, which is
a more convincing lie than a broken response would be. A user who has just
broken the permissions on their own selection is shown an empty catalogue
and no reason.

`pending_changes` gets this exactly right at `:1146` and says why in a
comment above it -- "A file that exists and cannot be read is not an empty
one". `rows_tsv` never got the same treatment.

**2. An option value can forge a second marker and make the panel name the
wrong option.** `flat_value` (`:527`) refuses a value only when it contains
a newline **and** `''` or `#`. A single-line value carrying `#@` passes.

```
$ nixarchy-pkg opt set my.opt 'true;  #@opt services.openssh.settings.PermitRootLogin'
{"ok":true}
```

writes

```nix
  my.opt = true;  #@opt services.openssh.settings.PermitRootLogin;  #@opt my.opt
```

which parses, because `#@` opens a Nix comment. `extras_tsv` matches the
**first** marker, so `state` then reports

```json
[{"path":"services.openssh.settings.PermitRootLogin;","set":true,"line":"  my.opt = true;"}]
```

-- an option the user never set, while the one they did set disappears from
the panel. `nixarchy-opt-remove` keys on the **last** marker, so "remove
PermitRootLogin" in the panel would delete a different line than the one it
names.

Option values are arbitrary Nix by design, so this is not an injection
boundary and the realistic vector is a snippet pasted from a forum. But the
marker contract belongs to this tool, and a value must not be able to forge
one.

**3. `cmd_toggle` validates nothing -- and this is hardening, not a bug.**
#41 filed this as a false success. **It is not**, and the issue has been
corrected. `toggle app '[a-z]*'` returns
`{"ok":false,"message":"nixarchy: '[a-z]*' is not an app id"}` and changes
nothing. That message is not in this repo: the adapter's own existence
check **passes** -- the pattern matches 54 rows in the template, because
`${id//./\\.}` escapes only dots -- and the external writer is what refuses
the id.

So the outcome is correct today, for a reason outside this file. What is
wrong is the layering: the adapter accepts a regex where an id is required,
and depends on another tool's validation to be right. A value that both
matched a different row and satisfied the writer would toggle the wrong
thing. Real ids are `[a-z0-9-]`, so it is not reachable.

## Proposed outcome

- A file the adapter cannot read is reported as unreadable, never as empty.
  The distinction between "you have nothing selected" and "I could not look"
  reaches the user.
- No value a user can type can forge a `#@` marker, so every marker in the
  file was written by this tool and the panel names the option that is
  actually set.
- `toggle` refuses an id that is not an id, on its own, without depending on
  a writer outside this repository to do it.
- Each of the three is covered by a test that fails if the behaviour
  regresses.

## Affected users and systems

- Anyone whose selection files become unreadable -- a bad `chmod`, a
  half-finished restore, a Home Manager symlink pointing at something gone.
- Anyone pasting a Nix snippet containing `#@` into an option value.
- `bin/nixarchy-pkg` only: `rows_tsv`, `flat_value`, `cmd_toggle`. No QML,
  no config format, no JSON schema change -- the objects gain truthful
  values, not new shapes.
- `tests/adapter.sh`. These cases need the catalogue, so they belong in the
  guarded sections that #44 introduced; this work should land on top of it.
- Verification host is **razer**, per repo convention. Never p620.

## Constraints

- Must not change the JSON contract. The panel parses these answers; they
  get truthful, not different.
- Must keep `ok: false` meaning "nothing was changed". An unreadable file on
  a read is not a failed write.
- Must not reimplement validation that belongs to the external writers. The
  header comment at `:30-36` is explicit that marker placement, unfree
  policy and the channel escape live there and are never duplicated here.
  Refusing a syntactically impossible id is this tool's own business;
  deciding whether an id exists is not.
- Must not make `state` fail outright when one file of several is
  unreadable. A user with a broken `apps.nix` should still see services and
  still be able to fix it from the panel.

## Open questions

1. **What does `state` do when one file is unreadable?** Refusing the whole
   object is simple and loses the tabs that were fine. Reporting the
   catalogue it could read plus a named error keeps the panel usable but
   means `ok: true` alongside a failure -- and the panel would have to be
   taught to show it, which is a QML change this task has excluded.

2. **Is `#@` enough, or should `flat_value` refuse every `#`?** Refusing
   `#@` is narrow and exactly matches the contract being protected.
   Refusing any `#` in a single-line value is blunter, would reject
   legitimate Nix, and the existing multi-line rule already treats `#` as
   dangerous -- so the two halves of the function would then disagree about
   what `#` means.

3. **Does `cmd_toggle`'s regex get escaped, or replaced?** The `case` guard
   from `:520` rejects metacharacters before the grep ever runs, which makes
   the escaping question moot. Escaping the pattern properly instead would
   keep ids with unusual characters working -- but no such id exists, and
   the guard is one line.
