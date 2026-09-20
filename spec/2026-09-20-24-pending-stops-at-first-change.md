---
status: approved
issue: 24
intent: intent/2026-09-20-24-pending-stops-at-first-change.md
---

# Spec: pending stops counting at the first file that changed

Both of the intent's open questions were answered yes: this task **re-cuts
the tour**, and it **fixes the whole class** rather than the one report.

## What the audit found

The bug is not one site. `set -euo pipefail` (`bin/nixarchy-pkg:39`) is
correct and stays; what is wrong is three pipelines whose first command
exits non-zero on a *normal* outcome, so a normal outcome is read as a
failure.

| line | shape | what goes wrong |
| --- | --- | --- |
| 967 | `diff … \| awk …` | `diff` exits 1 when files differ, which is the case the loop exists to handle. The subshell dies on the first file that has a change, so `apps` is reported and `services` and `advanced` are dropped. |
| 491 | `why=$(printf … \| grep -E "^error:" \| head -1)` | `grep` exits 1 when the error text has no `error:` line, killing the function *before* the `die` that was about to report it. |
| 565 | the same line again | the same. |

Both failure modes were reproduced rather than reasoned about:

    $ bash -c 'set -euo pipefail; w=$(printf "boom\n" | grep -E "^error:" | head -1); echo unreachable'
    exit 1, "unreachable" never printed

    $ bash -c 'set -euo pipefail; w=$(yes "error: x" | head -100000 | grep -E "^error:" | head -1)'
    exit 141

The second is the nastier one: `head -1` closes the pipe, `grep` takes
SIGPIPE, and the pipeline fails *even though it matched*. It depends on how
much output arrives before `head` leaves, so it appears and disappears with
the size of the error.

The `${why:-nix could not parse the result}` fallback sitting on the very
next line at both 491 and 565 is the proof that no-match was meant to be
survivable. It is unreachable today.

## Design

### 1. The report: `cmd_pending`, line 967

Run `diff` on its own and read its status deliberately, because `diff`'s
exit codes mean three different things and only one of them is a failure:
0 no differences, 1 differences, 2 or more it could not do the job.

    local out rc=0
    out=$(diff <(…) <(…)) || rc=$?
    [ "$rc" -le 1 ] || die "could not compare $part.nix with the applied copy"
    printf '%s\n' "$out" | awk …

This keeps what the intent required: a broken `diff` -- an unreadable file,
a missing one -- is still an error and still stops the command, while
"the files differ" stops being one. A bare `|| true` on the pipeline would
have fixed the symptom by deleting that distinction.

### 2. The two error paths: lines 491 and 565

Replace the pipeline with one command and no pipe at all:

    why=$(awk '/^error:/ { print; exit }' <<<"$why")

`awk` exits 0 whether or not it matched, which is what the fallback beside
it always assumed. A here-string rather than `printf … |` means there is no
pipeline left to have a status, so neither `pipefail` nor SIGPIPE applies.
Two processes become one.

### 3. So that it does not come back

Three things, because no one of them is enough:

- **A test with changes in two files at once.** Every existing case in
  `tests/adapter.sh` queues one kind of thing, which is exactly why a bug
  this size survived: each file alone reports correctly. The new case
  toggles a service *and* adds a package and asserts `count == 2` with both
  files named.
- **A test for the refused value.** `opt set` with something nix will not
  parse must answer with JSON rather than dying silently, which is what
  491 does today.
- **A source check in `tests/adapter.sh`.** `diff`, `grep`, `comm` and
  `cmp` at the head of a pipeline in `bin/nixarchy-pkg`, with a named
  allowlist for the ones that are deliberately guarded. It is a blunt
  instrument and it is the only thing that catches the *next* one before it
  ships rather than after.

shellcheck is already run by `nix flake check` and passes clean on this
file. It only reaches line 967, and only under `-o all` as `SC2312`; it
does not flag 491 or 565 at all. Turning `-o all` on repo-wide would add 32
`SC2312` hits and 267 `SC2250` style hits to fix while still missing two of
this bug's three sites, so it is not the guard.

### 4. The tour

`docs/img/tour.gif` and `tour.webm` show a footer reading *1 change queued*
after the tour queued two things. Once the count is right the recording
contradicts the tool, so it is re-cut with `tools/record-tour.sh` in this
task. That is one command now, which is why it belongs here rather than in
a follow-up.

## Alternatives rejected

- **`|| true` on the pipeline.** One character-for-character smaller and it
  makes an unreadable file, a missing file and a permissions error
  indistinguishable from a file that merely differs. The intent forbids it
  explicitly.
- **`set +o pipefail` around the loop, or dropping `pipefail` from the
  script.** Fixes these three by giving up the protection everywhere else,
  which is backwards: `pipefail` is not the bug, the pipelines are.
- **Keeping `grep … | head -1` and guarding it with `|| true`.** Survives
  no-match and SIGPIPE, and also survives `grep` failing for a real reason.
  `awk` needs no guard because it does not fail.
- **Reordering the loop so the important file comes first.** Would have
  made the reported symptom go away on this machine and left `advanced`
  broken for everyone.
- **shellcheck `-o all` as the guard.** Misses 491 and 565, and brings 299
  unrelated findings.
- **Leaving the tour.** The recording would then be a video of the tool
  getting its own count wrong, published on the front page of the docs.

## Risks

- **The source check will annoy someone.** It greps the implementation, so
  a legitimate new `grep |` has to be added to its allowlist. That is the
  cost of the check working at all, and the allowlist entry is one line
  with a reason next to it.
- **The re-cut needs this desktop**, the shell restart that
  `tools/record-tour.sh` performs, and a fresh index. It cannot run in CI.
  If the take is wrong the artifacts are not committed, as in #22.
- **The new count changes what the panel draws.** It will now say *2
  changes queued* where it said *1*. That is the fix, but anyone who
  learned the old number will see a change they did not make.
- **`advanced` has been uncounted for as long as this has existed.** A
  machine with queued advanced changes will start reporting them, which may
  look like new changes appearing from nowhere. Worth a line in the PR.

## Verification

- `tests/adapter.sh` passes, including the two new cases and the source
  check.
- By hand, against a throwaway selection: a service toggle plus a package
  add reports `count: 2` and names `services` and `apps`; each alone still
  reports 1; nothing queued still reports 0.
- `opt set` with a value nix refuses returns JSON carrying the reason, and
  the file is unchanged.
- A deliberately unreadable selection file makes `pending` fail loudly
  rather than silently reporting nothing.
- `shellcheck bin/nixarchy-pkg` stays clean, and `nix flake check` passes.
- The re-cut tour: under 60s, no larger than the GIF it replaces, and its
  closing footer reads the number the tour actually queued.
