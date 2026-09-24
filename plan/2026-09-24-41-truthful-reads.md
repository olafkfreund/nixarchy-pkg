---
status: approved
issue: 41
spec: spec/2026-09-24-41-truthful-reads.md
---

# Plan: the adapter does not describe a file it could not read

## Approved decisions, carried over

Self-contained: everything needed to implement this is below.

**Why:** #39 fixed the write path. The read and validation paths still
report things that are not true. Re-verified on `main` before any of this
was written.

1. **An unreadable selection file is reported as an empty one.** With
   `apps.nix` at mode 000, `state` answers
   `{"ok":true,"apps":[],"services":[...12 rows...]}` at exit 0 -- awk's
   "Permission denied" goes to stderr where the panel never sees it. That
   reads as a fresh install with services available, which is a more
   convincing lie than a broken response.
2. **A value can forge a `#@` marker.** `flat_value` refuses a value only
   when it has a newline **and** `''` or `#`, so a single-line value
   carrying `#@` passes, parses (because `#@` opens a Nix comment), and
   makes `extras_tsv` report an option the user never set while the one they
   did set disappears.
3. **`cmd_toggle` validates nothing** -- **hardening, not a bug**. The
   external writer refuses a bad id and nothing is changed; what is wrong is
   that the adapter's own check passes (`${id//./\\.}` escapes only dots, so
   `[a-z]*` matches 54 template rows) and the outcome's correctness depends
   on a tool outside this repository.

**Decisions:** report what could be read and name what could not, in
`message`, with `ok` staying `true` -- one unreadable file must not cost the
user the tabs that were fine; refuse `#@` specifically rather than every
`#`; reject metacharacters in an id rather than escaping them.

**Two findings that change the implementation, both demonstrated:**

- **`rows_tsv`'s return value cannot reach `cmd_state`.** Its only callers
  are `:1294-1295`, both inside process substitution, which discards the
  exit status: `f() { return 7; }; out=$(cat <(f)); echo $?` prints **0**.
  The check must live in `cmd_state`, before the `jq`.
- **Both `flat_value` callers (`:527`, `:625`) are
  `|| die "$FLAT_REFUSAL"`**, so a new `return 2` would be caught but would
  print the multi-line message for a forged marker -- plainly wrong advice.
  `$?` does survive into a `||` case branch, verified:
  `v=$(fv "$x") || case $? in 2) ...;; *) ...;; esac` dispatches correctly.
  `flat_value` cannot `die` because it runs in `$(...)`, which the comment
  at `:487-488` already records.

**No QML change.** `PkgModel.qml:256` absorbs `data.message` and
`Card.qml:282,295` render it when non-empty.

## Steps

1. `bin/nixarchy-pkg:104` (`rows_tsv`): `[ -f "$file" ] || return 0`
   becomes

   ```bash
   [ -e "$file" ] || return 0
   # A file that exists and cannot be read is not an empty one -- the same
   # rule pending_changes follows at :1146. Both callers below discard this
   # status (process substitution), so cmd_state asks for itself; this is
   # here so the next caller does not inherit the bug (#41).
   [ -r "$file" ] || return 1
   ```

   -> verify by check 3a.

2. `bin/nixarchy-pkg:1289` (`cmd_state`), before the `jq` at `:1293`:
   collect the unreadable files and build the message.

   ```bash
   # Process substitution swallows a callee's exit status, so a read that
   # fails inside the jq below cannot be noticed there. Asked here instead,
   # where the answer can still reach the object (#41).
   local unreadable=()
   [ -e "$APPS" ]     && [ ! -r "$APPS" ]     && unreadable+=("$APPS") || :
   [ -e "$SERVICES" ] && [ ! -r "$SERVICES" ] && unreadable+=("$SERVICES") || :
   local unread_msg=""
   [ ${#unreadable[@]} -gt 0 ] && unread_msg="could not read ${unreadable[*]} -- it exists but is not readable, so what it holds is not shown here"
   ```

   `[ -e ]` before `[ ! -r ]` deliberately: an absent file is the ordinary
   first-run case and `rows_tsv` returning nothing is correct there. `|| :`
   on each line because a false `&&` chain returns 1 and this script runs
   under `set -e`. -> verify by checks 3a and 3b.

3. `bin/nixarchy-pkg:1293` (`cmd_state`'s `jq`): pass
   `--arg unreadable "$unread_msg"` and emit it as `message` when non-empty,
   leaving `ok: true` (`:1310`) alone. The field must be **absent or empty**
   when everything read, so a normal state does not carry a message. ->
   verify by check 3b.

4. `bin/nixarchy-pkg:489`: add a second constant beside `FLAT_REFUSAL`.

   ```bash
   readonly MARKER_REFUSAL="a value cannot contain '#@' -- that is how this tool marks the options it wrote, and a value carrying one would make the panel name a different option than the one it changes. Nothing was changed."
   ```

   -> verify by check 3c.

5. `bin/nixarchy-pkg:490` (`flat_value`): refuse a forged marker, before the
   existing multi-line rule.

   ```bash
   # `#@` is this tool's marker and a value must not be able to forge one:
   # extras_tsv reads the FIRST marker on a line and nixarchy-opt-remove the
   # LAST, so a forged one makes the panel name one option and delete
   # another (#41). 2, not 1, so the caller can say which refusal it is.
   [[ $v == *'#@'* ]] && return 2
   ```

   -> verify by checks 3c and 3d.

6. `bin/nixarchy-pkg:527` and `:625`: both callers distinguish the two
   refusals.

   ```bash
   value=$(flat_value "$value") || case $? in
     2) die "$MARKER_REFUSAL" ;;
     *) die "$FLAT_REFUSAL" ;;
   esac
   ```

   -> verify by check 3c, and by 3d showing the multi-line message is still
   reachable.

7. `bin/nixarchy-pkg:306` (`cmd_toggle`), beside the existing `kind` check:

   ```bash
   # The grep below escapes only dots, so a metacharacter matches rows it
   # was never meant to. The outcome is right today only because the writer
   # refuses the id -- correctness that lives outside this repository (#41).
   case "$id" in
     *[!a-zA-Z0-9._-]* | "" ) die "'$id' is not a $kind id" ;;
   esac
   ```

   -> verify by checks 3e and 3f.

8. `tests/adapter.sh`: the new cases below, inside the catalogue-guarded
   section `#44` introduces. -> verify by checks 2 and 3.

## Tests

**Base this branch on `fix/44-ci-gates` (PR #47)**, not on `main`: these
cases need the catalogue, so they belong inside the guard that PR adds, and
writing them against `main` guarantees a conflict.

`nix flake check -L` locally; the suite on **razer**, never p620. No
text-size sweep -- nothing here needs one.

1. `nix flake check -L` passes, including shellcheck and `qml-syntax`.
2. `tests/adapter.sh` on razer: existing cases green, passing-assertion
   count not lower than before.
3. New cases:

   | # | Do | Expect |
   | - | -- | ------ |
   | 3a | `chmod 000 apps.nix`, then `state` | services still listed, `apps` empty, `message` names the file; then `chmod 600` and the catalogue returns with no message |
   | 3b | `state` with `apps.nix` **absent** | no message -- the ordinary first-run case is not an error |
   | 3c | `opt set my.opt 'true;  #@opt other.thing'` | refused, the refusal is the **marker** wording, `apps.nix` byte-identical |
   | 3d | `opt set` a multi-line value containing `''` | refused with the **multi-line** wording -- proves step 6 did not collapse the two |
   | 3e | `toggle app '[a-z]*'` | refused by the **adapter** (its wording, not the writer's), file unchanged |
   | 3f | `toggle app <a real id>` | still works -- the guard did not reject a valid id |
   | 3g | `opt set` a value containing `#` but not `#@` | still succeeds -- the narrow rule stayed narrow |

4. Each new case fails when its fix is reverted in a scratch copy, so they
   are assertions rather than smoke.

## Rollback

`bin/nixarchy-pkg` and `tests/adapter.sh` only. No QML, no config format, no
JSON schema change -- the state object gains a truthful `message`, a field
it already has. `git revert` restores the previous behaviour with nothing to
migrate.

If `ok: true` alongside an unreadable file proves to be the wrong call --
the spec records it as the weakest part of this design -- the fallback is a
dedicated `unreadable` array in the state object plus the QML to show it,
which is a larger change and a schema addition this task excluded.
