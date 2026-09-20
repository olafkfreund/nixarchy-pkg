---
status: approved
issue: 24
spec: spec/2026-09-20-24-pending-stops-at-first-change.md
---

# Plan: pending stops counting at the first file that changed

## The approved decisions, carried

`nixarchy-pkg pending` reports only the first selection file that differs.
Queue a service and a package: `count` is 1 and names the package. Both
files are written correctly; the report is wrong, and `count` is the number
the panel's footer draws.

`set -euo pipefail` (`bin/nixarchy-pkg:39`) is right and stays. The bug is
pipelines whose **first** command exits non-zero on a **normal** outcome, so
a normal outcome is read as a failure. Fix the class, not the report. Re-cut
the tour in this task, because it shows the wrong footer.

Two failure modes, both reproduced:

    $ bash -c 'set -euo pipefail; w=$(printf "boom\n" | grep -E "^error:" | head -1); echo unreachable'
    exit 1, "unreachable" never printed

    $ bash -c 'set -euo pipefail; w=$(yes "error: x" | head -100000 | grep -E "^error:" | head -1)'
    exit 141

The second is worse: `head -1` closes the pipe, `grep` takes SIGPIPE, and
the pipeline fails *although it matched*. It comes and goes with the size of
the output.

### The five sites

| line | now | becomes |
| --- | --- | --- |
| 967 | `diff <(…) <(…) \| awk …` | `diff` run alone, status read deliberately |
| 491 | `why=$(printf … \| grep -E "^error:" \| head -1)` | `awk` on a here-string |
| 565 | the same line again | the same |
| 606 | `n=$(grep -n '^{$' "$file" \| head -1 \| cut -d: -f1 \|\| true)` | one `awk` |
| 654 | `nix_why`'s two `grep … \| head -1 \|\| true` pipelines | one `awk` each |

606 and 654 already carry `|| true`, so they survive no-match. They are in
because `|| true` also swallows a `grep` that failed for a real reason and a
SIGPIPE that lost a match -- `flake_anchor` returning empty means "this
flake is declined", so a lost match declines a valid flake -- and because
with them converted the source check in step 6 needs no allowlist at all.

`nix_why` is where this was already known: its comment says an empty match
"would otherwise take the whole script down in the middle of a write, with
no message at all". The knowledge was in the file and was applied in one
place; 491 and 565 are the two it missed.

### The shapes to use

The `diff`, whose three exit codes mean three different things -- 0 no
differences, 1 differences, 2+ could not do the job:

    local out rc=0
    out=$(diff <(…) <(…)) || rc=$?
    [ "$rc" -le 1 ] || die "could not compare $part.nix with the applied copy"
    printf '%s\n' "$out" | awk …

A broken `diff` is still an error and still stops the command; "the files
differ" stops being one. `|| true` would have deleted that distinction,
which the intent forbids.

The greps, replaced by one `awk` with no pipeline left to have a status:

    why=$(awk '/^error:/ { print; exit }' <<<"$why")
    n=$(awk '/^\{$/ { print NR; exit }' "$file")

`awk` exits 0 whether or not it matched, which is what every `${why:-…}`
fallback beside these lines already assumed.

## Steps

1. `bin/nixarchy-pkg:967`: the `diff` in `cmd_pending`, run alone with its
   status read, `die` on 2 or more → verify by queueing a service toggle
   and an app toggle against a throwaway selection and reading
   `pending`; expect `count: 2` with both files named.
2. `bin/nixarchy-pkg:491` and `:565`: `awk` on a here-string → verify by
   `opt set` with a value nix refuses; expect JSON carrying a reason and an
   unchanged file, not a silent exit.
3. `bin/nixarchy-pkg:606`, `flake_anchor`: one `awk` → verify by
   `flake add` on a throwaway flake, and by a flake whose outer brace is
   indented still being declined.
4. `bin/nixarchy-pkg:654`, `nix_why`: one `awk` per branch, keeping both the
   `error:`-first rule and the first-non-empty-line fallback → verify by
   `flake add` against an unparseable flake; expect nix's words in the JSON.
5. `tests/adapter.sh`: a `pending` block. A throwaway `NIXARCHY_FLAKE` whose
   `nixarchy/` copies start identical to the selection, then: nothing
   queued is 0; a service toggle alone is 1 naming `services`; an app
   toggle as well is **2** naming both. Catalogue toggles rather than the
   spec's `pkg add`, because `pkg add` needs the nixpkgs index and a test
   must not depend on it; the two files are what the bug is about, not
   which command wrote them → verify by running the suite.
6. `tests/adapter.sh`: the source check. No line in `bin/nixarchy-pkg` may
   have `diff`, `comm` or `cmp` at the head of a pipeline, and none may pipe
   `grep`/`diff`/`comm` into `head`. After steps 1-4 both patterns find
   nothing, so there is no allowlist → verify by running it, and by
   temporarily re-introducing one such line and watching it fail.
7. `tools/record-tour.sh`: re-cut the tour, now that the footer counts
   right → verify from the frames, as #22 did: the closing footer reads the
   number the tour queued, under 60s, no larger than the GIF it replaces.
8. Commit, open the PR linking all three artifacts, and say in it that
   `advanced` has been uncounted for as long as this has existed.

## Tests

    # the suite, including the new pending block and the source check
    tests/adapter.sh
    # expect: no FAIL lines, exit 0

    # the bug itself, by hand against a throwaway selection
    # expect: 0 with nothing queued; 1 for one file; 2 for two files
    # and each file named in .changes[].file

    # a real failure is still a failure
    # make a selection file unreadable and run `pending`
    # expect: a non-zero exit and a message, not a silent empty report

    shellcheck bin/nixarchy-pkg      # expect: clean, as it is today
    nix flake check --print-build-logs

    # the re-cut tour
    ffprobe -v error -show_entries format=duration -of csv=p=0 docs/img/tour.webm
    ls -l docs/img/tour.gif
    # expect: under 60s, and no larger than 2 264 595 bytes

    # nothing outside the two files and the recording moved
    git diff --stat main -- '*.qml'
    # expect: empty

## Rollback

`git revert` the merge. `bin/nixarchy-pkg` returns to under-reporting,
`tests/` loses two blocks, and `docs/img/tour.*` returns to the take that
shows the wrong footer. Nothing else changes: no QML, no flake, no machine
state.

The machine needs no rollback. Every test builds its own selection under a
temporary `XDG_CONFIG_HOME` and its own flake under `NIXARCHY_FLAKE`, as the
suite already does, and the re-cut restores the selection on exit and
applies nothing.

## Deviations found while implementing

1. **Nothing inside a process substitution can stop the command reading it,
   so step 1's shape did not work as written.** The plan put the `die` on
   `rc >= 2` inside the `<(…)` that feeds `jq`. When it fires the subshell
   exits, its end of the pipe closes, and `jq` carries on and prints
   `{"ok": true, …}` built from however much arrived. The collection moved
   out into `pending_changes()`, which **returns** a status that
   `cmd_pending` reads in the main shell. That is the only place a failure
   here can be acted on.

2. **The plan's unreadable-file test asserted a behaviour that did not
   exist, and finding that out found a second defect.** An unreadable
   selection file was not an error: `marked()` sends its errors to
   `/dev/null`, the file read as empty, and every live line in the applied
   copy was reported as **removed** -- `count: 3` and `ok: true`, a
   confident list of changes nobody made. Fixed with a `[ -r "$src" ]`
   guard in the same loop, and covered by a test.

3. **A fourth site, found by the check rather than by reading.**
   `flake remove` had `used=$(grep -nE … | grep -v … | head -1 || true)`.
   An empty answer there means "nothing else refers to this input, go ahead
   and remove it", so a match lost to SIGPIPE removes a declaration
   something still uses. One `awk` now.

4. **The check needed two refinements to be usable.** It has to strip
   comments first, or it trips on the comments explaining why these shapes
   are gone; and it needs whitespace after the command name, or `comm`
   matches inside `command -v`. Proven on four cases: clean on the fixed
   file, catches a reintroduced `grep | head`, catches a `diff` at a
   pipeline head, and does not fire on `command -v`.

5. **A comment that began with the linter's name became a directive and
   failed CI.** `# shellcheck does not see this…` parses as a malformed
   directive (SC1073/SC1072) and `nix flake check` refused the build.
   Reworded.

6. **`tools/record-tour.sh` had a latent stdin bug (SC2095).** `frames()`
   calls `ffmpeg` inside a `while read` loop, and `ffmpeg` reads stdin, so
   it can swallow the loop's input and stop the extraction after one frame.
   It happened to work; `-nostdin` makes it reliable. SC2155 on `REPO`
   fixed in the same pass. Both are from #22 and are the same family of
   failure as this issue: something that works until it quietly does not.

7. **There was already a `pending` block in the suite**, covering one file
   at a time -- which is precisely how this survived. The new block is
   headed "pending across more than one file" rather than renaming theirs.
