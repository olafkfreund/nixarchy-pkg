---
status: draft
issue: 41
intent: intent/2026-09-24-41-truthful-reads.md
---

# Spec: the adapter does not describe a file it could not read

## Design

The intent's three open questions were decided here, not by the approver.
Each is marked; gate 2 is where they can be overturned.

### 1. An unreadable selection file

**The mechanism is not where the issue said it was.** `rows_tsv`'s
`[ -f "$file" ]` is the wrong test, but changing its return value alone
fixes nothing: its only two callers are `cmd_state:1294-1295`, and both go
through **process substitution**, which discards the exit status.
Demonstrated:

```bash
f() { return 7; }; out=$(cat <(f)); echo $?   # -> 0, not 7
```

So `cmd_state` cannot learn that a read failed, no matter what `rows_tsv`
returns. The check has to happen in `cmd_state`, before the `jq`.

**Decision (Q1): report the catalogue it could read, and name the file it
could not, in `message`. `ok` stays `true`.**

The intent's constraint is explicit that one unreadable file must not cost
the user the tabs that were fine -- a broken `apps.nix` should still leave
services visible and the panel usable to fix it. And the question of whether
the panel can *show* such an error turned out to be already answered:
`PkgModel.qml:256` absorbs `data.message` and `Card.qml:282,295` render it
when non-empty. **No QML change is needed**, which was the thing that would
have put this out of scope.

```bash
# Process substitution swallows a callee's exit status, so a read that
# failed inside the jq below cannot be noticed there. Asked here instead,
# where the answer can still reach the object (#41).
local unreadable=()
[ -e "$APPS" ]     && [ ! -r "$APPS" ]     && unreadable+=("$APPS")
[ -e "$SERVICES" ] && [ ! -r "$SERVICES" ] && unreadable+=("$SERVICES")
```

and the resulting message, passed to `jq` as `--arg unreadable`, reads
`could not read <file> -- it exists but is not readable, so what it holds is
not shown here`.

`[ -e ]` before `[ ! -r ]` deliberately: a file that does not exist at all
is the ordinary first-run case and already handled: `rows_tsv` returning
nothing is correct there. Only a file that exists and cannot be read is a
lie.

`rows_tsv` also gets `[ -r "$file" ] || return 1` for its own sake. It
changes nothing today -- both callers discard it -- but it stops the next
caller inheriting the bug, and it makes the function honest on its own
terms.

### 2. A value forging a second marker

**Decision (Q2): refuse `#@` specifically, not every `#`.**

`flat_value` (`:527`) currently refuses a value only when it has a newline
**and** `''` or `#`. A single-line value carrying `#@` passes, and `#@`
opens a Nix comment, so the result parses and `extras_tsv` -- which matches
the **first** marker on a line -- reports an option the user never set while
the one they did set disappears.

```bash
# `#@` is this tool's marker, and a value must not be able to forge one:
# extras_tsv reads the FIRST marker on a line and nixarchy-opt-remove the
# LAST, so a forged one makes the panel name one option and delete another
# (#41).
[[ $v == *'#@'* ]] && return 2
```

`return 2` rather than `1` so the caller can tell "this cannot be written on
one line" from "this forges a marker" and say so; the existing `return 1`
keeps its meaning.

Refusing every `#` was rejected: option values are arbitrary Nix, `#` is a
legal comment, and the function's existing multi-line rule already treats
`#` as merely suspicious rather than forbidden. Making the single-line half
stricter than the multi-line half would leave the two disagreeing about what
`#` means.

### 3. `cmd_toggle` -- hardening, and named as such

**Decision (Q3): reject metacharacters, do not escape them.**

The intent records that this is **not** a false success: the external writer
refuses the id and nothing is changed. What is wrong is that
`cmd_toggle`'s own existence check passes -- `${id//./\\.}` escapes only
dots, so `[a-z]*` matches 54 rows of the template -- and the correctness of
the outcome depends on a tool outside this repository.

The guard `cmd_opt_set` already carries at `:520`:

```bash
case "$id" in
  *[!a-zA-Z0-9._-]* | "" ) die "'$id' is not a $kind id" ;;
esac
```

Escaping the pattern properly would also work and would keep ids with
unusual characters working -- but no such id exists, the ids are
`[a-z0-9-]`, and rejecting what cannot be an id is both smaller and the
thing this file already does elsewhere.

## Alternatives rejected

- **Making `rows_tsv` return non-zero and expecting `cmd_state` to notice.**
  The obvious one-line fix. It cannot work: process substitution discards
  the status, demonstrated above.
- **`state` failing outright when a file is unreadable.** Simple, and it
  costs the user every tab that was fine, plus the panel they would fix it
  from. The intent forbids it.
- **A new field (`unreadable: [...]`) in the state object.** Cleaner to
  consume than prose in `message`, and it is a schema change the panel would
  have to be taught, which this task excludes. `message` already reaches the
  footer.
- **Refusing every `#` in `flat_value`.** Blunter, rejects legitimate Nix,
  and makes the function's two halves disagree.
- **Escaping `cmd_toggle`'s grep pattern.** Correct, larger, and buys
  support for ids that do not exist.
- **Reimplementing the writers' id validation.** Out of bounds: the header
  at `:30-36` is explicit that what an id *means* belongs to the writers.
  Refusing a string that cannot be an id at all is this tool's own business;
  deciding whether it exists is not.

## Risks

- **`ok: true` alongside a failure.** A caller that reads only `ok` learns
  nothing about the unreadable file. Mitigated by the message reaching the
  footer, and by the alternative -- failing the whole read -- being worse.
  Recorded here because it is the weakest part of this design.
- **`flat_value`'s new `return 2` is a third exit status** on a function
  whose callers currently test truthiness. Every caller must be checked, not
  assumed.
- **The `#@` refusal will reject a legitimate value** that happens to
  contain `#@` in a string literal. Judged acceptable: the marker contract
  is worth more than that value, and the refusal says why.
- **`cmd_toggle`'s guard changes a failure's wording**, from the writer's
  message to the adapter's. Anyone matching on the old text sees a change;
  nothing in this repo does.
- **razer only.** Never p620.

## Verification

Tests belong in the catalogue-guarded sections `#44` introduces, so this
lands on top of that branch.

1. `nix flake check -L` passes, including shellcheck and `qml-syntax`.
2. `tests/adapter.sh` on razer: existing cases unchanged and green, and the
   passing-assertion count does not drop.
3. New cases:
   - `chmod 000 apps.nix`, then `state`: services are still listed, `apps`
     is empty, and `message` names the unreadable file. Then `chmod 600` and
     confirm the catalogue comes back and the message clears.
   - `state` with `apps.nix` **absent** rather than unreadable: no message,
     because that is the ordinary first-run case.
   - `opt set my.opt 'true;  #@opt other.thing'` is refused, the refusal
     says a value cannot carry a marker, and `apps.nix` is byte-identical.
   - `opt set` with a legitimate value containing `#` but not `#@` still
     succeeds, so the narrow rule stayed narrow.
   - `toggle app '[a-z]*'` is refused **by the adapter** -- the error is the
     adapter's wording, not the writer's -- and the file is unchanged.
   - `toggle app <a real id>` still works, so the guard did not reject a
     valid id.
4. Each new case fails when its fix is reverted in a scratch copy -- an
   assertion, not smoke.
