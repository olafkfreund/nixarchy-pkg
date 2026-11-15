---
status: approved
issue: 60
intent: intent/2026-11-15-60-truthful-queue.md
---

# Spec: before apply, show what it will copy, and whether the result evaluates

*Amended after the Codex and agy review of 2026-11-15. The owner approved
the amendments in advance. "Review fixes" at the end lists what changed and
why.*

## Design

**Decisions from intent approval** (its open questions, taken as recommended):

1. The check evaluates `toplevel.drvPath`. `--dry-run` adds the build and
   download counts, labelled as such. No package diff.
2. `pending` keeps `count` and `changes[]` for marked rows, adds the change
   `modified`, and adds `files[]` and `total`.
3. No per-change drop. A queue row opens its file, or shows its raw lines.
4. Index age and reindex errors: split out (#69).
5. #66 stays separate.

Every rule about *what apply copies* mirrors `nixarchy-apply` as read on
2026-11-15 (cited by line). Where the check cannot reproduce apply's
evaluation faithfully, it says so and gives no verdict.

### 0. Shared rules

- **`flake`, `base`, `host`.** Mirror apply:
  - `flake=${NIXARCHY_FLAKE:-/etc/nixos}`;
  - `host=$(uname -n)`;
  - `base=$flake/hosts/$host` if that directory exists, else `$flake`.
    `flake_base()` already does this. `base-rel` is `hosts/$host` or empty,
    and paths are joined so an empty `base-rel` never yields `//`.
- **Imported parts.** apply regenerates `$base/nixarchy-apps.nix` to import
  `./nixarchy/<part>.nix` for every part whose **source** exists, in the
  order apps, services, advanced, flatsnap (`nixarchy-apply:330-345`,
  `:387-404`). It never deletes `$base/nixarchy/<part>.nix`.
  `imported(part)` is true when the current `$base/nixarchy-apps.nix` exists
  and contains `./nixarchy/<part>.nix`.
- **Records.** For a destination `dst`:
  `rec=${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/applied/$(printf '%s' "$dst" | sha256sum | cut -c1-16)`.
  - apply writes the **full** `sha256sum <"$dst"` output into it.
  - "Edited in the flake" means `rec` exists, and
    `sha256sum <"$dst" | cmp -s - "$rec"` fails.
- **Private copies.** Reads never touch the live files more than once.
  - `pending` copies each source with `cp -L` into
    `$STATE_DIR/pkg-read.XXXXXX` (0700). `pkg-read.*` is never swept by
    `begin_write`, which only sweeps `pkg-work.*`.
  - `check` uses `$STATE_DIR/pkg-check.XXXXXX`.
  - Both are removed by the script's global `on_exit`, through new
    variables `READDIR` and `CHECKDIR`, cleared like `WORK` with
    `chmod -R u+w` first. No command installs its own `EXIT` trap.
- **A write in progress or interrupted.** #59 leaves
  `$STATE_DIR/pkg-recovery/open` from `guard` until `committed`, and leaves
  it behind after a `SIGKILL`. Reads check it without taking any lock, before
  and after their read:
  - `pending` answers with `writing: true` (its numbers may be from a torn
    read);
  - `check` refuses to give a verdict.

  This covers the paused and the interrupted writer, which a before/after
  hash comparison misses. Writes made by external writers outside the
  adapter are not covered until nixarchy#1789 lands.

### 1. `pending`: everything apply copies

For each part `p` in apps, services, advanced, flatsnap, with
`src=$CONFIG_DIR/$p.nix` and `dst=$base/nixarchy/$p.nix`:

- **status:**
  - `src` exists and `!imported(p)`: `new`, even if `dst` already has the
    same bytes, because apply starts importing it;
  - `src` exists, `dst` missing: `new`;
  - `src` exists and differs from `dst` (`cmp`): `modified`;
  - `src` missing and `imported(p)`: `dropped`;
  - otherwise: unchanged. That includes `src` missing with `dst` still
    present, because apply leaves that destination unimported.
- **Marked rows.** Today's `marked()` diff, but rows are paired per file and
  marker, in order. The k-th `-` row of a marker pairs with its k-th `+` row,
  and the pair is `modified`. Unpaired `+` rows are `on` / `added`, and
  unpaired `-` rows are `off` / `removed`. Nothing is merged, so two
  occurrences give two rows. `lineNo` is the row's line in the private copy
  of `src`, or `null` for removals; a `null` line is shown as `(apps.nix)`,
  never `:null`.
- **`unmarked`.** The number of `+`/`-` lines in
  `diff <(grep -v '#@' dst) <(grep -v '#@' src)`, with a missing side as
  `/dev/null`.
- **`hunk`.** `diff -u dst src`, capped at 200 lines. These are the raw
  lines, shown on request.
- **`conflict`.** Only when `src` exists (apply skips absent parts first,
  `nixarchy-apply:342`). It is `overwrite` when `dst` exists, `src` and
  `dst` differ, and `dst` is edited in the flake.

For each `$CONFIG_DIR/packages/<n>.nix`, with
`dst=$base/nixarchy/packages/<n>.nix`:

- **status:** `new` or `modified` as above, `unmarked` and `hunk` the same.
- **conflict:** `blocks` when `src` and `dst` differ and `dst` is edited in
  the flake, because apply exits 1 (`nixarchy-apply:312-326`).
- A `dst` whose source was deleted is kept by apply and is not a change.

**Errors.**
- An unreadable `src` or `dst`, or `cmp` exiting with 2, gives
  `{ok:false, error}`, never a guess.
- So does a failed private copy.

**Answer:**

```json
{
  "ok": true, "neverApplied": false, "base": "...", "writing": false,
  "count": 2,
  "changes": [{"marker": ":brave", "file": "apps", "line": "...", "change": "on", "lineNo": 41}],
  "files": [{"file": "advanced", "path": ".../advanced.nix", "status": "modified",
             "unmarked": 3, "hunk": "...", "conflict": null, "explained": false}],
  "total": 3,
  "fingerprint": "<sha256 over every part and draft copy, names included>",
  "pins": {"apps": "<sha256>", "services": "<sha256>", "advanced": "<sha256>", "flatsnap": ""},
  "unpinned": {"drafts": ["packages/foo.nix"], "flake": true}
}
```

- **`count`** still equals `changes | length` and still counts marked rows.
  The merge bug is fixed, so the number can rise where it used to
  undercount. `modified` is documented in the manual.
- **`files[]`** has one entry for every part or draft whose status is not
  unchanged. `explained` is true only when the status is `modified`,
  `unmarked == 0`, **and** at least one `changes[]` row belongs to that
  file.
- **`total`** is `(changes | length) + (files | map(select(.explained | not)) | length)`.
  So `total == 0` exactly when `files` is empty. A byte change that no row
  explains (whitespace, comments, `#@pkgs-begin`, commented catalogue
  lines) still counts once, and shows as "apps.nix: whitespace or comments
  changed".
- **`fingerprint`** covers everything apply copies, drafts included, and is
  what invalidates a check verdict.
- **`pins`** are what `--expect-sha256` can protect: the four parts, with
  `""` for an absent part ("must be absent", `nixarchy-apply:296-307`).
- **`unpinned`** always says the flake's own files are unpinned, and lists
  **every** existing draft, changed or not, because apply copies drafts
  live.
- `neverApplied` and `base` are unchanged. On a machine that has never
  applied, every existing part is `new`.

### 2. `check`: does it evaluate (read-only)

`nixarchy-pkg check [--dry-run]`. One JSON answer. It never writes the
flake, the selection or #59's lock, never elevates, and never switches.

**Steps:**

1. **Single flight.** `exec 8>"$STATE_DIR/pkg-check.lock"; flock -n 8`. If
   that fails, the answer is `{ok:false, error:"a check is already running"}`.
   Under that lock, sweep stale `pkg-check.*` directories. #59's write lock
   is never touched.
2. **Writes.** If `$TXN/open` exists, answer
   `{ok:true, verdict:"unknown", reason:"a write is in progress or was interrupted -- try again, or run recover"}`.
3. **Snapshot.** `cp -L` each existing part and draft into `$CHECKDIR/snap/`.
   `F1` is the fingerprint of the snapshot, computed as `pending` computes
   it.
4. **Fidelity guard.** Answer `verdict:"unknown"`, with the reason, and
   without evaluating, when the check cannot reproduce what the real rebuild
   evaluates:
   - **Git metadata.** `$flake/.git` exists and the flake's tracked `.nix`
     files mention `self.rev`, `self.shortRev`, `self.dirtyRev`,
     `self.dirtyShortRev`, `self.lastModified` or `self.lastModifiedDate`.
     A `path:` copy would evaluate those differently.
   - **Relative path input.** `flake.lock` has a `"type": "path"` input whose
     `path` is relative.
   - **Submodule.** `git -C "$flake" ls-files -s` lists any gitlink (mode
     `160000`).
5. **Materialise.**
   - **Git work tree** (detected as apply does, with `[ -e "$flake/.git" ]`,
     `nixarchy-apply:413`): copy the tracked entries that still exist,
     without recursing:

     ```bash
     git -C "$flake" ls-files -z | while IFS= read -r -d '' f; do
       [ -e "$flake/$f" ] || [ -L "$flake/$f" ] && printf '%s\0' "$f"
     done | tar -C "$flake" --null --no-recursion -T - -cf - | tar -C "$copy" -xf -
     ```

     Deleted-but-tracked files are skipped, as Nix's own dirty-tree fetch
     skips them. Then copy the whole real `$base/nixarchy/` subtree in as
     well, because apply `git add -A`s it (`nixarchy-apply:417`), retained
     drafts included.
   - **Not a git work tree:** `cp -a "$flake/." "$copy"`. A `path:` flake's
     rebuild copies the whole directory to the store, so the check copies
     the same, nothing more.
6. **Overlay, never through a symlink.**
   - If `$copy/<base-rel>`, `$copy/<base-rel>/nixarchy` or
     `…/nixarchy/packages` is a symlink, answer `verdict:"unknown"`, "the
     flake's nixarchy directory is a symlink -- cannot check without
     writing through it".
   - Each target is `rm -f`'d, then written fresh from `snap/`, so a
     symlinked or read-only target is replaced and never followed.
   - `nixarchy-apps.nix` is written the same way, with the same imports as
     apply.
7. **Store path and host.**
   - `root=$(nix --extra-experimental-features 'nix-command flakes' flake metadata --json "path:$copy" | jq -r .path)`
     gives the exact store path of the copy, used for rewriting errors. A
     failure here is a `fails` verdict with that error, because the flake
     itself does not evaluate.
   - `nix eval … "path:$copy#nixosConfigurations" --apply 'c: builtins.hasAttr "<host>" c'`
     returning `false` gives `{ok:false, error:"this flake has no nixosConfigurations.<host>"}`.
8. **Evaluate.**

   ```bash
   setsid timeout 900 nix --extra-experimental-features 'nix-command flakes' \
     eval --raw "path:$copy#nixosConfigurations.\"$host\".config.system.build.toplevel.drvPath" \
     >"$CHECKDIR/out" 2>"$CHECKDIR/err" 9>&- 8>&- &
   ```

   - `wait` for it.
   - A `TERM`/`INT`/`HUP` trap runs `kill -TERM -- -$pid`, waits, and lets
     `on_exit` clean up. `setsid` wraps `timeout`, so the whole group dies.
   - The flags add no `--impure` and no `--option`.
   - Exit 124 gives `verdict:"unknown"`, "timed out after 15 minutes".
   - Any other non-zero exit gives `verdict:"fails"`.
9. **`--dry-run`**, only after `evaluates`:
   `nix build --dry-run "$(cat out)^*"`. This reuses the evaluated `.drv`,
   so there is no second evaluation. It parses:
   - `will be built` and `will be fetched`, singular and plural;
   - sizes in `B`, `KiB`, `MiB` or `GiB`, converted to MiB.

   Anything unparsed, or a failed dry run, gives `dryRun: null` and
   `dryRunError`, never zeros.
10. **Superseded.** After evaluation, `F2` is the fingerprint of the live
    sources. If `F2 ≠ F1`, or `$TXN/open` exists now, the verdict is
    `superseded`.

**Answer.**
`{ok:true, host, verdict, drvPath?, summary?, error?, at?, dryRun?, dryRunError?, fingerprint:F1, pins, unpinned, blocked, note}`.

- **`verdict`** is `evaluates`, `fails`, `superseded` or `unknown`, and
  `unknown` always comes with a `reason`.
- **`error`** is the full stderr, with exactly two prefixes rewritten:
  - `"$root/"` and `"$copy/"`, followed by `<base-rel>/nixarchy/<p>.nix`,
    become `${XDG_CONFIG_HOME:-~/.config}/nixarchy/<p>.nix`, and the same
    for drafts. A retained draft with no source maps to its flake
    destination instead.
  - Any other path under `$root` or `$copy` becomes `<flake>/…`.

  Other inputs' store paths are left untouched. The text is capped at 200
  lines, keeping the **last** lines, where Nix puts the cause.
- **`summary`** is the last non-empty `error: …` line that has text after
  the colon.
- **`at`** is `{file, line}` from the last selection-file location in the
  rewritten error, as `:<line>:` or as `In '<file>'` with `line: null`. It
  is `null` when there is none. Line numbers are those of the checked
  snapshot ("as checked").
- **`blocked`** lists drafts whose `conflict` is `blocks`. The verdict is
  still given, but the panel says apply will stop before building.
- **`note`** always says this checked evaluation only, not a build or
  activation. When IFD is allowed, it adds that evaluation may have built
  some inputs.
- **`{ok:false}`** only when no check ran: the check lock is busy, there is
  no flake, there is no `nixosConfigurations.<host>`, or the working
  directory or snapshot cannot be made. A failed copy of the flake gives
  `verdict:"unknown"` with the copy error.

### 3. `apply` takes pins

`nixarchy-pkg apply [--pin <part>=<sha256>]…` forwards each pin as
`--expect-sha256 <part>=<sha256>`. `<part>` must be one of the four names,
and `<sha256>` 64 hex characters or empty; anything else is refused before
anything runs.

When the log contains `is not what you checked` (`nixarchy-apply:303`), the
final message is: "a file changed since you reviewed it -- nothing was
copied or built; look at the queue again".

### 4. The panel: a Queue tab

**Model.**
- `PkgModel.tabs` gains `"Queue"` (index 6), with `queueTab: tab === 6`.
- `pendingData` holds the last whole `pending` answer.
- `queued` is the answer's `total`.
- `queueError` holds the last error.
- `checkResult` and `checkRunning` hold the check.

**Invalidation.** It runs in `_pending`'s `onStreamFinished`, not in
`refreshed()`, because `refreshed()` fires before `pending` returns:
- a new `fingerprint` that differs from `checkResult.fingerprint` clears
  `checkResult`;
- a check answer whose `fingerprint` differs from the current
  `pendingData.fingerprint` is shown as superseded.

**Rows**, top to bottom:
1. **The check line**, when a check ran or is running. It is a real row,
   so the cursor can reach it:
   - "checking… (about a minute) -- ESC cancels";
   - "evaluates ✓ -- 12 to build, 40 to fetch (180 MiB)" (counts only with
     `--dry-run`);
   - "fails: <summary> (apps.nix:41, as checked)";
   - "superseded -- press c again";
   - "could not check: <reason>".

   `RETURN` on it opens the full error in a scrollable view
   (`checkErrorOpen`), separate from the apply log. `ESC` closes that view
   and never touches an apply.
2. **Conflicts:**
   - "apps.nix was edited in the flake -- apply will keep a copy and
     overwrite it";
   - "packages/foo.nix was edited in the flake -- apply will stop".
3. **`writing: true`:** "a write is in progress or was interrupted -- the
   queue may be out of date".
4. **Each `changes[]` row**, as "brave on (apps.nix:41)". Labels come from
   the marker (`:brave` → "brave", `opt:services.x` → "services.x").
5. **Each `files[]` entry with `explained: false`:**
   - "advanced.nix: 3 lines changed";
   - "packages/foo.nix: new";
   - "flatsnap.nix: no longer imported";
   - "apps.nix: whitespace or comments changed".
6. **A dim last line:** "not pinned: the flake's own files" + (drafts ? ",
   and drafts: foo.nix…" : "").

**Keys on the Queue tab**, handled before the shared handlers, so tab
handling takes precedence:
- `RETURN`:
  - on a row whose `src` exists, opens it with `omarchy-launch-editor`;
  - on removed, dropped and note rows, and on the check line, opens the
    detail view, which shows the row's `line` or `hunk`.
- `c` runs `check`. `SHIFT+C` runs `check --dry-run`, handled in the
  modifier branch, above the no-modifier block.
- `ESC`:
  - first closes an open detail view;
  - else cancels a running check (`running = false`, which sends TERM);
  - else does what it does on other tabs.
- `r` reloads state and `pending` (`refresh()`). It does not reindex: on
  the Queue tab, `r` is "read the queue again".

**Apply.** Arming freezes what was reviewed.
1. **First `a` or `SHIFT+A`:**
   - If `queued === -1` and `queueError` is set, refuse: "queue unknown --
     press r".
   - Otherwise set `armingState = "reading"`, show "reading the queue…",
     and request `pending`.
2. **When that answer arrives:**
   - `ok:false` or `writing: true` disarms, with the reason.
   - Otherwise `armedPins` and `armedFingerprint` are frozen from **that**
     answer. If a current `evaluates` check has the same fingerprint, its
     pins are used. Then `armingState = "armed"`, with the message "a again
     to rebuild: <total> changes" + conflicts + " -- any other key
     cancels". The timer starts.
3. **A second press while reading** is ignored, and the message says
   "still reading the queue".
4. **Any later `pending` answer** whose fingerprint differs from
   `armedFingerprint` disarms: "the queue changed -- review it again".
5. **The second press while armed:**
   - `a` runs `apply` with `--pin` for each of `armedPins`;
   - `SHIFT+A` runs the terminal command `nixarchy-apply` with
     `--expect-sha256=<part>=<sha>` for each pin, so the terminal route is
     pinned too.

   Either first stops the panel's own running check and waits for it to
   exit, and drops its result. Checks run from other panels or a terminal
   are not stopped. They change nothing that apply builds, and their result
   is superseded by the next fingerprint.

**Footer and bar.**
- `queued` is `-1` until the first answer.
  - With no error yet, the footer says "reading queue…", and the bar shows
    no badge.
  - With `queueError` set, the footer says "queue unknown -- <error>". The
    bar shows a `?` badge, with the error in its tooltip.
- `0` is the only value that means "nothing queued".
- Answers are read with `typeof data.total === "number"`, never
  `data.total || 0`.

## Review fixes (2026-11-15, Codex and agy; owner-approved in advance)

| Finding | Fix |
|---|---|
| A dropped part stayed queued forever, and a re-created identical part was missed | Status uses `imported(p)` from `nixarchy-apps.nix`; conflict needs `src` |
| `total` could be 0 for whitespace, comments or commented catalogue edits | `explained`; every byte change counts at least once |
| Duplicate markers in one file still merged | Rows paired one-to-one per file and marker |
| Arming race; an unknown queue applied unpinned; the terminal route was unpinned | `armingState`, frozen `armedPins`, disarm on change, `SHIFT+A` pinned |
| Deleted-but-tracked files crashed `tar`; submodules leaked; a parent git repo was mistaken for the flake; symlinks wrote through | Existence filter and `--no-recursion`; submodules refused; `[ -e .git ]`; refuse symlinked dirs, `rm -f` targets, `cp -L` sources |
| A `path:` copy could evaluate differently (self.rev, relative inputs) | Fidelity guard gives `unknown` instead of a verdict |
| Before/after hash missed a paused or interrupted write | `pkg-recovery/open` checked before and after; `writing` in `pending` |
| Drafts never invalidated a verdict; invalidation was wired to `refreshed()` | `fingerprint` covers drafts; invalidation happens in `_pending` |
| The rewrite matched every input's `-source`; the first `error:` was empty; Nix puts the cause last | Exact `$root` from `flake metadata`; last `error:`; tail kept |
| Wrong missing-host detection | `hasAttr` probe |
| The dry run re-evaluated the whole system | `nix build --dry-run "<drv>^*"`; unit-aware parser; `null`, never 0 |
| Retained package copies missing from the check | Real `$base/nixarchy/` copied in before the overlay |
| `pending` temp files in `/tmp`, or swept by `begin_write` | `pkg-read.*` in `STATE_DIR`, cleaned by the global `on_exit` |
| Experimental features missing outside a configured `nix.conf` | `--extra-experimental-features` on every call |
| `r` reindexed; `ESC` and `SHIFT+C` precedence; the check line was unreachable | Queue-tab handlers first; the check line is a row; separate detail view |
| `unpinned` named only changed drafts, not the flake | It always names the flake and every draft |

## Alternatives rejected

- **Counting unmarked edits into `count`.** That breaks `count == changes |
  length` for terminal users. `total` carries the honest number.
- **`--override-input`, or an expression overlay.** Neither can replace a
  file inside the flake's own source. A materialised copy can.
- **Copying untracked files of a git flake.** That differs from what the
  rebuild evaluates, and leaks ignored files to the store.
- **Taking #59's lock to read a consistent snapshot.** Reads must never wait
  for writes. `pkg-recovery/open` plus the fingerprint before and after
  detect what a lock would prevent.
- **Running the check automatically.** Cost, and a store copy each time.
  The intent says on demand.
- **Pinning drafts.** apply cannot pin `packages/` today. Reported as
  unpinned; a nixarchy follow-up.
- **Faking a git fetch (`git init` in the copy).** `self.rev` would still
  differ from the real dirty tree. The fidelity guard refuses those flakes
  honestly instead.

## Risks

- **Cost.** About 68 s and some gigabytes per check on p620. It runs on
  demand, single-flight, and is cancellable; an apply stops the panel's
  own check.
- **Store copy.** The tracked tree plus the unapplied selection reaches the
  world-readable store. Apply does the same with the copied selection, so
  the only difference is "before you applied". The manual says so.
- **The fidelity guard is a list of known differences, not a proof.** An
  unknown `path:` versus git difference would still give a wrong verdict.
  The `note` says the check is evidence, not a guarantee, and apply still
  evaluates for real.
- **IFD** can build during evaluation; the `note` says so.
- **External writers** are not detected as in progress until nixarchy#1789.
- **Hosts:** manual checks on razer only, never p620.

## Verification

- **`tests/adapter.sh`**, `pending`, with fixtures and stubs:
  - a `flatsnap.nix` edit;
  - a new draft;
  - an unmarked continuation edit;
  - a whitespace-only edit, giving `total ≥ 1` and `explained: false`;
  - a commented-catalogue edit;
  - the same marker in two files, and twice in one file, giving separate
    rows;
  - a changed marked value, giving `modified`;
  - a dropped part, then the state after an apply-like regeneration of
    `nixarchy-apps.nix` (unchanged, not dropped);
  - a re-created identical part, giving `new`;
  - an in-flake edit with a matching record (`overwrite`), and with a
    deleted `src` (no conflict);
  - a draft conflict (`blocks`);
  - `pins` and `unpinned`;
  - a fingerprint that changes when a draft changes;
  - `writing: true` while `pkg-recovery/open` exists;
  - an unreadable `dst`, giving `ok:false`;
  - a never-applied machine;
  - `count == (changes | length)` and `total == 0` iff `files == []` in
    every case;
  - no `pkg-read.*` left, and nothing in `TMPDIR`.
- **`tests/adapter.sh`**, `check`, on a fixture git flake. Its
  `nixosConfigurations.<this host>` toplevel is a trivial `derivation` whose
  name depends on importing `nixarchy-apps.nix`'s imports and on
  `builtins.pathExists ./untracked`:
  - `evaluates`, with the untracked file not copied;
  - `throw` in `apps.nix` gives `fails`, with
    `at == {file:"apps.nix", line:N}` and `summary` containing the throw
    text;
  - a symlinked `<base>/nixarchy` gives `unknown`, and the real target is
    unchanged;
  - a gitlink in the index gives `unknown`;
  - a deleted-but-tracked file still evaluates;
  - `self.rev` in `flake.nix` gives `unknown`;
  - a stub edits `apps.nix` mid-run, giving `superseded`;
  - `pkg-recovery/open` gives `unknown`;
  - a second concurrent check gives `ok:false`;
  - a missing host gives `ok:false`;
  - a stubbed dry run, singular and plural, with KiB and GiB, parses, and
    an unparsable one gives `null`;
  - `TERM` gives one answer and no leftovers;
  - after every case, the flake's files and `git status` are unchanged.
- **`tests/adapter.sh`**, `apply --pin`: forwarding, refusal of bad pins,
  and the mismatch message from a stubbed `nixarchy-apply` printing "is not
  what you checked".
- **`tests/qml/tst_pkgmodel.qml`:**
  - `queued` is `-1` before the first answer and on `ok:false`;
  - `total === 0` is kept (not `|| 0`);
  - arming waits for the answer, freezes its pins, disarms on a changed
    fingerprint, and refuses on an unknown queue;
  - the second `a` passes the frozen pins;
  - a check result is cleared by a new fingerprint, including a
    draft-only change;
  - a late check answer is marked superseded.
- `nix flake check` and CI pass.
- **Manual, on razer:**
  - an `advanced.nix` edit shows in Queue;
  - `c` on a good selection, then on a wrong-typed option;
  - `a`, an external edit, then `a` disarms;
  - `SHIFT+A` is pinned.
