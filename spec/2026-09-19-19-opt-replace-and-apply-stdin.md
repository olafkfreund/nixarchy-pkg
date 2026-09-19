---
status: draft
issue: 19
intent: intent/2026-09-19-19-opt-replace-and-apply-stdin.md
---

# Spec: an atomic `opt replace`, and an apply that applies

## Design

### 1. `opt replace <path> <value>`

A sibling of `cmd_opt_set`, not a flag on it. `opt set`'s refusal of an
existing option is a useful guard against clobbering a line somebody wrote
by hand, and keeping a separate verb keeps that guard while giving the
consumer the operation they asked for.

The written line's shape is known, because this plugin writes it
(`cmd_opt_set`'s awk):

    <path> = <value>;  #@opt <path>

So replacing it is a substitution of one physical line, found by its
marker, and the sequence is `cmd_opt_set`'s discipline with the backup
moved to the front where it belongs:

1. validate the path the same way `opt set` does, and collapse the value
   to one physical line for the same reason — `nixarchy-opt-remove`
   deletes the single line carrying the marker, so a multi-line value
   would leave orphans that make the file unparseable and the option
   unremovable
2. refuse if the option is **not** present, because replacing something
   that is not there is a different mistake from setting it
3. **one backup, taken before anything is touched**
4. swap the marked line in place, preserving its position — the person
   may have moved it, and the marker is what finds it, not the position
5. `nix-instantiate --parse`; on failure restore the whole file and report
   nix's own words
6. one JSON object

`opt replace` with no arguments prints a usage error and exits, which is
how a caller probes whether the subcommand exists. That is behaviour, not
an accident, and it gets a test.

### 2. `apply` stops guessing how many prompts there are

Two changes, and they are belt and braces on purpose.

**The braces: build the answers from the same condition.** There is no
single stdin that is correct both ways — `n\ny\n` declines when there is
one prompt, and `y\n` launches a VM preview when there are two. So
`cmd_apply` asks the same question `nixarchy-apply:193` asks:

    if command -v nixarchy-preview >/dev/null 2>&1; then
      answers=$'n\ny\n'   # decline the preview, accept the switch
    else
      answers=$'y\n'      # there is only the switch to accept
    fi

This duplicates a condition that lives upstream, which is a real cost and
is why the belt exists as well. The comment says where it is duplicated
from and that the two must agree.

**The belt: notice when the assumption breaks.** `nixarchy-apply:225`
prints `Not switching.` followed by the command to run, when the switch is
declined, and then exits 0 — which is why exit status alone has never been
able to tell "switched" from "declined".

So `cmd_apply` looks for that phrase in the output it already captures. If
it is there, the result is `ok: false` with a message saying the rebuild
was declined and nothing was applied, rather than `{"ok": true, "message":
"applied"}`.

After the first change that should never happen. The point is that if the
prompts change again — they have changed once — the panel says something
true instead of something reassuring. A silent false success is the worst
outcome available here and this makes it unreachable.

### Why not just answer `y` to everything

Because the first prompt is "Preview in a VM first?", and answering it
yes builds and boots a VM. An apply that did that unasked would be worse
than the bug.

### What is not changed

`nixarchy-apply` itself. Its behaviour is defensible and its own comment
argues for it: a piped or non-interactive apply that declines to switch is
the safe failure, not a bug. The fault is this plugin assuming a prompt
count. An upstream issue asking for `--yes` or `NIXARCHY_ASSUME_YES` is
filed alongside this work, and when it lands both halves of the fix above
collapse into using it.

## Alternatives rejected

**`--force` on `opt set`.** One fewer subcommand, and it removes the guard
that stops a caller clobbering a hand-written line by accident. The
consumer asked for `replace`.

**Remove-then-set inside one command.** Still two writes; the atomicity
comes from one backup taken first, not from the order of the parts.

**Answering `y` to everything.** Boots a VM preview nobody asked for.

**Parsing the log to decide what to answer**, rather than to check what
happened. That is an expect-style dialogue with somebody else's program,
and far more fragile than the condition it would replace.

**Waiting for the upstream flag.** Defect 2 currently tells people a
rebuild happened when it did not. Filing the request and shipping the
local fix is not a compromise; the local fix is also the thing that
detects the upstream behaviour changing.

## Risks

- **The duplicated condition can drift.** If `nixarchy-apply` stops
  gating on `command -v nixarchy-preview`, the answers are wrong again —
  but the `Not switching.` check then reports it instead of hiding it.
  That is the whole reason for having both.
- **The phrase can change.** It is a string in somebody else's program.
  If it changes, the detector stops detecting and the behaviour is no
  worse than today's. Cited by file and line so a reader can check it.
- **`opt replace` writes to the selection**, like every other writer here.
  Same backup-and-parse discipline, with the backup earlier than `opt set`
  takes it.
- No change to what the panel draws, and no change to any QML.

## Verification

1. `tests/adapter.sh` passes, extended with:
   - `opt replace` with no arguments exits with a usage error
   - replacing a present option changes the value and keeps the line's
     position
   - replacing an **absent** option is refused and nothing is written
   - a value that will not parse leaves the file **byte-identical**
2. **The apply answers, both ways**, tested against a stub of
   `nixarchy-apply`'s shape rather than the real one, because the real one
   rebuilds a machine: with the stub reporting a preview binary present,
   two prompts get `n` then `y`; with it absent, one prompt gets `y`.
3. **The declined-detector**, against the same stub made to print
   `Not switching.`: `cmd_apply` reports `ok: false` and a message naming
   the decline, not `"applied"`.
4. `bin/nixarchy-pkg apply` is **not** run against the real
   `nixarchy-apply` during testing. It elevates and rebuilds; a test that
   did it would be a test that changed the machine.
5. The upstream issue exists and is linked from the code comment.
