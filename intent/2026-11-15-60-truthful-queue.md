---
status: draft
issue: 60
author: olafkfreund
---

# Intent: before apply, show what it will copy, and whether the result evaluates

## Problem

The panel's only account of what an apply will change is a number: "4 changes
queued" in the footer and a badge on the bar. That number misses real changes,
the user cannot see what it counts, and nothing between "queued" and "build
and switch" says whether the result will even evaluate.

**How apply decides what to copy** (`nixarchy-apply`, read on 2026-11-15):

- It copies whole files, by content (`diff -q`), from
  `~/.config/nixarchy/{apps,services,advanced,flatsnap}.nix` and every
  `~/.config/nixarchy/packages/*.nix` into the flake, under `$base/nixarchy/`.
  `$base` is the flake root, or `hosts/<hostname>` when that exists.
- It regenerates `$base/nixarchy-apps.nix`, which imports only the part files
  that exist.
- Package copies accumulate; a deleted source is never removed.
- A `packages/*.nix` that was edited in the flake since the last apply makes
  apply exit 1 before anything is built.
- A part file that was edited in the flake is kept aside, then overwritten.

**1. The count misses real changes.**
`pending` (`bin/nixarchy-pkg`: `marked()`, `pending_changes()`) compares only
`apps`, `services` and `advanced`, and in them only active lines that carry a
`#@` marker. So "nothing queued" is reported while apply would still copy:

- any change to `flatsnap.nix` or to a `packages/*.nix` draft;
- a change on an unmarked line, such as the body of a multi-line
  `firefox.settings = { … };` block below an unchanged marked line, or
  unmarked Nix in `advanced.nix`;
- comment-only or whitespace-only edits, which `diff -q` sees and `marked()`
  strips;
- a part file created or deleted, which changes what `nixarchy-apps.nix`
  imports.

**2. The count can merge, or invent, changes.**
`cmd_pending` groups by marker with no file name (`group_by(.marker)`). The
same marker in two files, or twice in one file, collapses into one change. The
merged record can take its file from one side and its line from the other.
Codex reproduced the merge on 2026-11-15.

**3. The user cannot see what is queued.**
`pending` already returns `changes[]`. The panel reads only `count` and
`neverApplied` (`PkgModel.qml:298-299`, `Panel.qml:53-54`), and throws the
list away. Apply then runs `nixarchy-apply --yes --no-preview` (`cmd_apply`),
so the user never looks at the change before the machine switches. Nothing
warns that an edit made in the flake copy will be overwritten, or will stop
the apply.

**4. "Accepted" does not mean "evaluates".**
A value is checked only with `nix-instantiate --parse`. A wrong type, a
nonexistent option, a failed assertion or a conflict with the user's own
modules is queued without complaint. It fails only when apply evaluates the
system: on this machine that is 68 s in (measured by evaluating
`nixosConfigurations.p620`'s `toplevel.drvPath`). The error then names a
module or the flake's copy, not the edit the user made.

**5. A failed `pending` looks like "nothing queued".**
- `Panel.qml`:
  - unparseable output sets `queued = 0` (`:58`);
  - an `ok:false` answer leaves the previous count up, unmarked (`:52`);
  - at startup the count is 0 (`:32`), so an early failure reads as
    "nothing queued".
- `PkgModel.qml:295-302` has the same two gaps, so the footer
  (`Card.qml:340`) says "nothing queued" too.

**6. Apply does not pin what was reviewed.**
`nixarchy-apply --expect-sha256 <part>=<sha256>` refuses to build a selection
part that changed after the caller checked it. The panel never passes it. The
pin also covers only the selection parts as they stand. It does not cover
`packages/*.nix`, which apply copies straight from the source, nor the
flake's own files.

## Proposed outcome

- **The queue is honest about the selection.** "Nothing queued" means apply
  would copy nothing new from `~/.config/nixarchy`. Every file apply would
  copy, create or stop importing is accounted for: the four part files, every
  draft, and unmarked and comment-only edits. Distinct changes are never
  merged into one, and no record mixes two files.
- **The user can read the queue.** Each change has a plain description:
  - marked rows as a selection: "brave on", "services.openssh.ports changed";
  - everything else as a file change: "advanced.nix: 3 lines changed",
    "packages/foo.nix: new".

  The raw lines are available on request.
- **Conflicts in the flake are shown before apply, not during it.** An edit
  made in the flake copy that apply would overwrite is shown, and so is one
  that would stop the apply.
- **"Does it evaluate" can be asked before switching, and without one.** On
  request, the real host is evaluated with the files apply would produce. The
  answer is exactly one of:
  - "evaluates";
  - the error, naming the queued file and line where it can be traced there;
  - "superseded": the selection changed while it ran.

  It never switches, never elevates, and never writes the flake. A result is
  shown only for the selection it checked.
- **The parts apply can pin are the parts that were reviewed.** An apply from
  the panel passes `--expect-sha256` for the selection parts the user saw, so
  a part edited since then is refused, not built. Whatever stays unpinned
  (drafts, the flake's own files) is said plainly in the panel.
- **A failed `pending` is visible.** The bar and the footer show that the
  count is unknown, never 0 or a stale number.
- **Existing `pending` users do not break.** The answer stays one JSON object.
  Existing fields keep their meaning for marked rows. What they cannot express
  is added alongside them (see open question 2).

Scope: this task is about what an **apply** will copy from
`~/.config/nixarchy`. Changes `flake add` and `flake remove` make directly in
the flake are not "queued": they are in the flake already, and are shown by
the Flakes tab.

## Affected users and systems

- Everyone who applies from the panel, and anyone who uses
  `nixarchy-pkg pending` from a terminal.
- `bin/nixarchy-pkg`: `marked`, `pending_changes`, `cmd_pending`, `cmd_apply`,
  and a new read-only check.
- `PkgModel.qml`, the menu and footer (`Menu.qml`, `Card.qml`), `Panel.qml`.
- `tests/adapter.sh`, `tests/qml/`.
- Outside this repo: `nixarchy-apply`'s copy rules and `--expect-sha256`, used
  as they stand. Pinning drafts would need a nixarchy change, to be filed if
  the spec wants it.
- Verification host is **razer**. Never p620; p620's 68 s was a single
  read-only `nix eval`.

## Constraints

- **The check never switches, never elevates, and never writes the flake or
  the user's selection.** It may evaluate. Anything more (a dry run, a build)
  is labelled as what it is.
- **It runs only when asked.** It never runs per edit or on its own.
  Evaluating a full host is tens of seconds and gigabytes of memory, and it
  copies source into the world-readable store. At most one runs at a time, it
  is cancellable, it never blocks a write, and an apply cancels it.
- **Unreviewed or untracked files never reach the store.** The check
  evaluates the flake's tracked files plus the selection apply would copy,
  nothing else. This matches what apply builds.
- **Evaluation purity matches apply.** No `--impure`, and nothing added to
  make the check pass.
- **#59 still holds.** The check and `pending` are reads: they take no lock
  and never wait for a write. #59's in-place writes are not atomic, so a read
  can catch a file mid-write. A result taken from a selection that was
  incomplete, or changed during the check, must never be shown as current.
  Any working copy lives in the user's private state directory, and is
  removed afterwards.
- **No secrets leak beyond what apply already does.** The queue view and
  error excerpts can show values the user typed. They stay in the panel and
  the user's terminal, and reach no log or service.
- **It must work when there is nothing to compare against**: a machine that
  has never applied, or a missing `$base/nixarchy`. And when the flake is not
  at `/etc/nixos`.

## Open questions

1. **Evaluate only, or also a dry run?**
   - Evaluating `toplevel.drvPath` answers "does it evaluate".
   - `nix build --dry-run` adds what would be downloaded or built.
   - A package diff (`nvd`-style) needs the closure realised, which is a
     full build.

   Recommended: evaluation, plus the dry-run counts, clearly labelled. Leave
   package diffs to apply, which `nh` already prints.
2. **How does `pending` show what its fields cannot?** Today `count` equals
   `changes | length`, and `changes[].change` is one of
   on/off/added/removed. Recommended: keep `changes[]` for marked rows, and
   add `modified` for a marked line whose value changed. Add a separate
   `files[]` for whole-file changes, and a `total` that counts both.
   `count` keeps its meaning for marked rows. Alternatively, `count` becomes
   the total, which is a contract change for terminal users.
3. **Dropping one change from the queue.** "Revert to the applied copy" has
   no safe baseline when the flake copy was edited, or the machine never
   applied. Recommended: leave it to a follow-up. This task shows the queue,
   and opens the file at the line.
4. **Stale search index.** Showing its age and surfacing real `reindex`
   errors is a separate problem from apply truthfulness. Note that the picker
   exits non-zero even after a good reindex. Recommended: split it into its
   own issue.
5. **#66** (apply refuses while an interrupted write is open) touches
   `cmd_apply` too, but depends on #59's recovery state, not on this queue.
   Recommended: keep it separate.
