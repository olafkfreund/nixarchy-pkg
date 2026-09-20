---
status: draft
issue: 24
author: olafkfreund
---

# Intent: pending stops counting at the first file that changed

## Problem

`nixarchy-pkg pending` reports only the changes in the first selection
file that differs. Queue a service and a package and it says one change is
waiting, and names the package. The service is not in `changes` and not in
`count`.

Both files are written correctly -- `diff` on them by hand shows both
changes -- so nothing is lost. What is wrong is the report, and the report
is what the user is shown: `count` is the number the panel's footer draws.
A person looking at *1 change queued* while two things are waiting has been
told something false about what the next rebuild will do, by the one
surface whose whole job is to say what is waiting.

The cause is known and small. `cmd_pending` loops over `apps`, `services`
and `advanced`, piping `diff` into `awk`. `diff` exits 1 when files differ;
`set -euo pipefail` (`bin/nixarchy-pkg:39`) promotes that to the pipeline's
status; the subshell dies on the first differing file. `apps` is first in
the loop, so `apps` is what survives and everything after it is silently
dropped. Each file alone reports correctly, which is why this held up in
every test that queued one kind of thing at a time.

It was found while recording the tour for #22 -- the recording itself shows
a footer reading *1 change queued* after two things were queued -- and was
left alone there because that task was forbidden from touching `bin/`.

## Proposed outcome

- Queueing changes in more than one selection file reports all of them:
  `count` is the number of things actually waiting, and `changes` names
  each one.
- The order of the files in the loop stops mattering to the answer.
- A test covers more than one file at once, so this cannot come back
  quietly. The existing tests pass because each queues one kind of thing.

## Affected users and systems

- Anyone reading the footer, which is everyone who opens the panel: this is
  the count it draws.
- `bin/nixarchy-pkg` only, in `cmd_pending`. No QML change: the panel draws
  whatever `count` says and will draw the right number once it is right.
- `docs/img/tour.gif` and `tour.webm` show the wrong footer. Re-cutting
  them is `tools/record-tour.sh`, but whether that belongs in this task is
  an open question below.

## Constraints

- Must not weaken the error handling around it. `set -e` and `pipefail` are
  there on purpose; the fix is to stop treating "files differ" as a
  failure, not to stop noticing real failures. A bare `|| true` on the
  pipeline would hide a genuinely broken `diff` as easily as a benign exit
  1.
- Must keep what the existing code gets right and documents at length: the
  live-lines-only rule, the `#@pkgs-begin/end` scaffolding exclusion, and
  the marker-keyed collapsing of a toggle's two diff lines into one change.
- `advanced` is in the loop and must be counted too; it is last, so it is
  the file most often lost.
- No change to the JSON shape. The panel and the tests read it.

## Open questions

1. **Does this task re-cut the tour?** The recording shows the wrong
   footer. Re-cutting is one command now, but it is a second thing in a
   bug-fix PR and it will produce a new 2.2 MB binary in the diff. My
   preference is a separate follow-up, so this PR is a small readable fix.
2. **How far does the audit go?** The same shape -- a pipeline whose first
   command exits non-zero on a normal outcome -- may appear elsewhere in
   `bin/nixarchy-pkg`, which uses `diff`, `grep` and `cmp` in several
   places. `grep` exiting 1 on no-match is the same trap. Do you want this
   task to fix the one bug, or to sweep the file for the pattern and fix
   every instance it finds?
