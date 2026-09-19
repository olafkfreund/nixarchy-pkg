---
status: approved
issue: 19
author: olafkfreund
---

# Intent: an atomic `opt replace`, and an apply that actually applies

## Problem

Two defects, filed together because one consumer hit both. They are
otherwise unrelated and the second is much the more serious.

### 1. Changing an option's value is two commands, and can lose it

`cmd_opt_set` refuses an option that is already present —
`"$path is already in $APPS -- remove it first"` — so changing a value
means `opt remove` then `opt set`.

Those are two invocations with two separate backups. The backup taken by
`opt set` covers the set; nothing covers the pair. If the set fails — a
value that will not parse, a disk that fills, a process killed between
them — the removal has already happened and is not rolled back. The
option is simply gone, and what the person asked for was to *change* it.

Nothing in the panel does this today, so nothing in the panel is broken by
it. It is reachable from a terminal, and it is how a consumer of these
writers would naturally edit a value.

### 2. `apply` reports success while applying nothing

This is the one worth stopping on.

`cmd_apply` pipes `printf 'n\ny\n'` into `nixarchy-apply`, with a comment
explaining the two answers: `n` declines "Preview in a VM first?", `y`
accepts "Build and switch now?".

But `nixarchy-apply:193` asks the preview question **conditionally**:

    if command -v nixarchy-preview >/dev/null 2>&1; then
      read -r -p "Preview in a VM first? [y/N] " reply || reply=""
      ...
    fi
    read -r -p "Build and switch now? [y/N] " reply || reply=""

On a machine without `nixarchy-preview` there is only one prompt. The `n`
answers *it*, the switch is declined, and the `y` is never read.

`nixarchy-apply` then exits **0**, because declining is not an error. So
`cmd_apply`'s `{ok: ($rc == 0)}` reports `{"ok": true, "message":
"applied"}`, the panel clears its queue indicator, and **nothing was
built**.

Demonstrated rather than reasoned about, with a stub of the same shape:

| `nixarchy-preview` | prompts | `n\ny\n` does |
| --- | --- | --- |
| present | 2 | skip preview, switch — correct |
| absent | 1 | **declines the switch** |

It is latent on any machine that has `nixarchy-preview`, which is why it
has not been noticed — including the machine this was found on.

## Proposed outcome

- Changing an option's value is one command that either changes it or
  leaves the file exactly as it was.
- Pressing `a` either applies, or says it did not. It never reports
  success for a rebuild that did not happen.

Concretely, when this is done:

- `nixarchy-pkg opt replace <path> <value>` exists: one backup, the marked
  line swapped in place, a parse check, the whole file reverted on any
  failure, one JSON object out. With no arguments it prints a usage error,
  because that is how a caller probes whether the subcommand exists.
- `apply` answers whatever `nixarchy-apply` actually asks, rather than a
  fixed script that assumes a prompt count.
- An apply that did not switch is reported as one.

## Affected users and systems

- `nixarchy.microvm`, which edits
  `programs.nixarchy.services.microvm.machines.<name>` through these
  writers and hides its permanent-VM edit until `opt replace` exists.
  Its design is in that repository's
  `spec/2026-09-18-1-microvm-plugin.md` §11.
- Anybody who presses `a` on a machine without `nixarchy-preview` — which,
  since preview is not universal, is a real population currently being
  told their changes were applied when they were not.
- `bin/nixarchy-pkg`: `cmd_opt_set`'s sibling, and `cmd_apply`.
- `tests/adapter.sh`.
- Not the panel's QML, unless the apply fix changes what a result looks
  like.
- Not `nixarchy-apply` itself. Its behaviour is defensible — a
  non-interactive apply declining to switch is the safe failure, and its
  own comment says so. The fault is this plugin assuming a prompt count.

## Constraints

- **`opt replace` must be atomic or must not have happened.** One backup
  taken before anything is touched, the whole file restored on any
  failure. Not "remove, then set, then hope".
- **Must not weaken the parse check.** A value that would leave the file
  unparseable is refused and nothing changes, with nix's own words.
- **Must not answer a question it was not asked.** Whatever replaces the
  fixed `n\ny\n` must be robust to the number of prompts changing again,
  because it has changed once already.
- **Must not make `apply` riskier.** It elevates and rebuilds a system. A
  fix that made it answer `y` more eagerly would be worse than the bug.
- **Must not report success for a rebuild that did not happen**, which is
  the whole of defect 2.
- The writers belong to nixarchy. If the honest fix needs something from
  `nixarchy-apply`, that is an issue over there, not an edit from here.

## Open questions

1. **How does `apply` stop guessing?** Three shapes: answer `y` to
   everything, which is wrong because it would accept a VM preview nobody
   asked for; detect `nixarchy-preview` the same way `nixarchy-apply` does
   and send the matching script, which duplicates a condition that can
   drift; or ask nixarchy for a non-interactive mode — `--yes`, or reading
   `NIXARCHY_ASSUME_YES` — which is correct and is an upstream change. The
   second is available today and the third is right. Whether to do the
   second now and file the third, or wait, is the main decision.

2. **How does `apply` know it did not switch?** Exit code 0 covers both
   "switched" and "declined". Parsing the log for a phrase is fragile.
   Comparing `pending` before and after is honest but costs a second
   evaluation of the selection files. Something has to distinguish them,
   or the outcome stays unknowable.

3. **Is `opt replace` enough, or should `opt set` learn to overwrite?**
   A separate verb keeps `opt set`'s refusal, which is a useful guard
   against clobbering a line somebody wrote by hand. `--force` on `set`
   would be one fewer subcommand. The consumer asked for `replace`.

4. **Does `opt replace` need to preserve position?** The marked line is
   swapped in place, which keeps it where the person put it. Worth
   confirming that is what "in place" means to the consumer rather than
   assuming it.
