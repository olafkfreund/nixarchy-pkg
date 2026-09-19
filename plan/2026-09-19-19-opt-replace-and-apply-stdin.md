---
status: approved
issue: 19
spec: spec/2026-09-19-19-opt-replace-and-apply-stdin.md
---

# Plan: an atomic `opt replace`, and an apply that applies

## The approved decisions, in full

**`opt replace <path> <value>`** — a sibling of `cmd_opt_set`, not a
`--force` flag on it, because `opt set`'s refusal guards a hand-written
line and the consumer asked for `replace`. Atomicity comes from **one
backup taken before anything is touched**, which is the thing
remove-then-set cannot have. Refuses an option that is not present. With
no arguments, prints a usage error, because that is how a caller probes
for the subcommand.

**`apply` stops guessing the prompt count**, in two parts on purpose:

- *Braces* — build the answers from the same
  `command -v nixarchy-preview` condition `nixarchy-apply:193` gates on.
  No single stdin is correct both ways: one script declines when there is
  one prompt, the other boots a VM preview when there are two.
- *Belt* — look for `Not switching.` in the output already captured and
  report `ok: false` when it appears. `nixarchy-apply:225` prints it and
  then exits 0, which is why exit status has never distinguished
  "switched" from "declined".

**`nixarchy-apply` is not changed.** An upstream issue asking for a
non-interactive mode is filed alongside; when it lands, both halves above
collapse into using it.

**`apply` is never run against the real `nixarchy-apply` in tests.** It
elevates and rebuilds a machine.

## Steps

1. **`bin/nixarchy-pkg`: `cmd_opt_replace`**, beside `cmd_opt_set`. Same
   path validation, same one-physical-line collapse and the same reason
   for it. Then: refuse if the marker is absent; `mktemp` backup **first**;
   swap the marked line in place with awk keyed on the marker rather than
   on position; `nix-instantiate --parse`; restore the whole file and
   report `nix_why` on failure; one JSON object.
   -> verify by the four `opt replace` cases in the tests below.

2. **Route it.** `cmd_opt`'s `case` gains `replace) cmd_opt_replace "$@" ;;`
   and the usage string in `cmd_opt`'s `*)` branch names it.
   -> verify by `bin/nixarchy-pkg opt replace` printing a usage error and
   `bin/nixarchy-pkg opt` naming `replace`.

3. **`cmd_apply`: build the answers.** Replace the fixed `printf 'n\ny\n'`
   with the conditional above. The comment cites `nixarchy-apply:193` as
   the condition being duplicated, says the two must agree, and links the
   upstream issue from step 6.
   -> verify by the stub tests below.

4. **`cmd_apply`: notice a decline.** The output is already captured for
   the message. If it contains `Not switching.`, emit `ok: false` with a
   message saying the rebuild was declined and nothing was applied. Cite
   `nixarchy-apply:225`.
   -> verify by the stub test below.

5. **`tests/adapter.sh`** — an `opt replace` block using the existing
   `fresh_config`, and an `apply` block driving a **stub**
   `nixarchy-apply` on `PATH`, never the real one.
   -> verify by `tests/adapter.sh` passing.

6. **File the upstream issue** on `olafkfreund/nixarchy`: a
   non-interactive mode for `nixarchy-apply` (`--yes`, or
   `NIXARCHY_ASSUME_YES`), explaining that a caller currently has to
   duplicate the `command -v nixarchy-preview` condition to know how many
   answers to send, and that declining exits 0 so a caller cannot tell a
   decline from a switch.
   -> verify by the issue existing and its URL appearing in the code
   comment from step 3.

## Tests

    bash tests/adapter.sh

Expected: passes, including the new blocks.

New cases, all against throwaway state:

**`opt replace`**, on a fresh config:

1. `opt replace` with no arguments exits non-zero with a usage error.
2. `opt set` an option, then `opt replace` it — the value changes, the
   marker survives, and the line keeps its position in the file.
3. `opt replace` an option that is **not** present is refused, and the
   file is byte-identical afterwards.
4. `opt replace` with a value that will not parse leaves the file
   **byte-identical** and reports nix's own words.

**`apply`**, against a stub on `PATH` that mimics `nixarchy-apply`'s
shape and prints what it was asked:

5. Stub with a preview binary present: two prompts, answered `n` then `y`.
6. Stub with it absent: one prompt, answered `y` — **the regression this
   issue is about.**
7. Stub that prints `Not switching.` and exits 0: `cmd_apply` reports
   `ok: false`, and the message is not `"applied"`.

The real `nixarchy-apply` is never invoked. If a test ever needs it, that
test is wrong.

## Deviations found while implementing

Recorded here in the same commit as the code. All four are faults in the
tests rather than in the change, and every one of them produced a **false
pass** before it was caught -- which is the only reason they are worth
writing down.

1. **`check "..." ! cmd` does not negate.** `check` runs `"$@"`, so the `!`
   is looked up as a command, is not one, and the assertion fails whatever
   the code did. A `not()` function is added, because a function *can* be
   found on `$@` where a shell keyword cannot.

2. **`opt replace` with no arguments exits 0, and should.** The first test
   asserted a non-zero status. This adapter reports failure as a value and
   exits 0 throughout -- the existing "unknown command" cases assert exactly
   that -- so a caller probing for the subcommand reads the object, not the
   status. The test was wrong about the design, not the design about itself.

3. **Deleting the stub `nixarchy-preview` does not hide the real one.** The
   first attempt stripped every `PATH` entry that provided one; on this
   machine that also removed the entry providing `jq`, the adapter died
   before asking anything, and the assertion "no preview prompt appeared"
   passed on an error message. Replaced with a minimal `PATH` containing
   exactly the tools `apply` needs.

4. **`env PATH=... command -v x` can never work.** `command` is a shell
   builtin, so `env` looks for a binary of that name and does not find one.
   Both guard checks using it were passing or failing for reasons unrelated
   to `PATH`. Replaced with file tests.

   And a fifth that followed from the fourth: the minimal `PATH` needs
   `bash` and `env` in it, because the adapter's own shebang is
   `#!/usr/bin/env bash`. Without them it cannot start, which surfaced as
   `env: 'bash': No such file or directory` and read as a fault in the code
   under test.

The pattern is worth naming: every one of these made a test agree with me.
The regression case -- one prompt, answered `y` -- only became a real check
after the fourth fix.

## Rollback

`git revert`. `cmd_opt_replace` is additive — a new function and one new
`case` arm — so reverting removes a subcommand nothing else calls. The
`cmd_apply` change restores the previous fixed answers, which reinstates
the bug; that is the correct meaning of reverting this commit, and the
issue would be reopened rather than the revert quietly left.

No machine state is touched. Every test writes to a throwaway
`XDG_CONFIG_HOME` or a stub on `PATH`, so the selection files cannot be
reached; confirm with `nixarchy-pkg pending` at the end rather than
assuming it.
