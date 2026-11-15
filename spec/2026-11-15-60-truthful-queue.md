---
status: approved
issue: 60
intent: intent/2026-11-15-60-truthful-queue.md
---

# Spec: before apply, show what it will copy, and whether the result evaluates

## Design

**Decisions from intent approval** (its open questions, taken as recommended):

1. The check evaluates `toplevel.drvPath`. `--dry-run` additionally reports
   the build and download counts, labelled as such. No package diff.
2. `pending` keeps `count` and `changes[]` for marked rows, adds the change
   `modified`, and adds `files[]` and `total`.
3. No per-change drop. A queue row opens its file.
4. Index age and reindex errors: split out (#69).
5. #66 stays separate.

Five parts:
1. `pending` reads everything apply copies.
2. A new read-only `check`.
3. `apply` takes pins.
4. A Queue tab in the panel.
5. Honest failure states.

Every rule about *what apply copies* is mirrored from `nixarchy-apply` as
read on 2026-11-15 (lines quoted below), not re-invented.

### 1. `pending`: everything apply copies

**What apply does** (`nixarchy-apply`):
- `flake=${NIXARCHY_FLAKE:-/etc/nixos}`. `base=$flake`, or
  `$flake/hosts/$(uname -n)` when that directory exists. The adapter's
  `flake_base()` already matches.
- It copies `{apps,services,advanced,flatsnap}.nix` from
  `~/.config/nixarchy` when the file exists, and only when its content differs
  (`diff -q`).
- It imports in `$base/nixarchy-apps.nix` only the parts whose source exists.
- It copies `packages/*.nix` the same way. A destination whose source is gone
  is kept.
- A destination edited since the last apply is detected through a record
  file, `${XDG_STATE_HOME:-~/.local/state}/nixarchy/applied/<first 16 hex of
  sha256(dst path)>`, which holds `sha256sum` of the destination as last
  written. The outcome depends on the file:
  - for a part, the edit is kept aside and then overwritten;
  - for a package that also differs from its source, apply exits 1 before
    copying anything.

**New `pending_changes`**, in `bin/nixarchy-pkg`:

- Loops `apps services advanced flatsnap`, then every
  `$CONFIG_DIR/packages/*.nix`.
- **For each part**, `src=$CONFIG_DIR/$part.nix`, `dst=$base/nixarchy/$part.nix`:
  - **status:**
    - `new`: `src` exists and `dst` does not;
    - `dropped`: `src` is missing and `dst` exists, so apply stops importing it;
    - `modified`: both exist and `cmp -s` says they differ;
    - unchanged otherwise.
  - **Marked rows:** today's `marked()` diff, emitted with the file. Grouping
    is by **file and marker**, never marker alone. A group with both a `+` and
    a `-` side is `modified`. With only `+` it is `on` / `added`; with only
    `-` it is `off` / `removed`, as today.
  - **`unmarked`:** the number of `+` and `-` lines in
    `diff <(grep -v '#@' dst) <(grep -v '#@' src)`. This counts comments,
    whitespace and unmarked Nix. A missing side is `/dev/null`.
  - **`conflict`:** mirrors apply's test. If `dst` exists, the record exists,
    `src` and `dst` differ, and `sha256(dst)` ≠ the record, then it is
    `overwrite`.
- **For each package** `packages/<n>.nix`: status `new` or `modified` as
  above, with `unmarked` the same diff count. Conflicts use the same test but
  give `blocks`, because apply exits.
- **Pins:** `sha256` of each part's `src`, or `""` when it is missing.
  `nixarchy-apply` treats `part=` with an empty hash as "must be absent"
  (`nixarchy-apply:296-307`). Packages get no pin: apply cannot pin them,
  because the snapshot `cp` has no `packages/` directory.

**`cmd_pending` answer:**

```json
{
  "ok": true, "neverApplied": false, "base": "...",
  "count": 2,
  "changes": [{"marker": ":brave", "file": "apps", "line": "...", "change": "on", "lineNo": 41}],
  "files": [
    {"file": "advanced", "path": ".../advanced.nix", "status": "modified", "unmarked": 3, "conflict": null},
    {"file": "packages/foo.nix", "path": "...", "status": "new", "unmarked": 12, "conflict": null}
  ],
  "total": 4,
  "pins": {"apps": "<sha256>", "services": "<sha256>", "advanced": "<sha256>", "flatsnap": ""},
  "unpinned": ["packages/foo.nix"]
}
```

- `count` still equals `changes | length` and still counts marked rows. The
  merge bug is fixed, so the number can rise where it used to undercount. The
  new `modified` value is documented in the manual.
- `lineNo` is the marker's line in `src`, or `null` for a removal. It lets
  the panel name the line.
- A `files[]` entry is emitted for every part or package whose status is not
  unchanged.
- `total = (changes | length)` plus the number of `files[]` entries whose
  status is `new` or `dropped`, or whose `unmarked > 0`. A part changed only
  by marked rows is already counted in `changes`.
- `neverApplied` and `base` are unchanged. On a machine that has never
  applied, every existing part is `new`. Its marked rows show as `on` /
  `added`, which is today's behaviour.
- On error it answers `{ok:false, error}`, as today.

**Torn reads.** `pending` stays lock-free (#59). It reads each `src` once
into a private copy and diffs the copy, so the diff and the pin hash describe
the same bytes. The panel re-reads on every `refreshed()`, so a torn read is
replaced within one refresh. Apply then pins whatever the user saw (section
3), and a torn copy would fail that pin and refuse, never build.

### 2. `check`: does it evaluate (read-only)

`nixarchy-pkg check [--dry-run]`. One JSON answer. It never writes the
flake, the selection or the lock, and never elevates or switches.

**Steps:**

1. **Single flight.** `exec 8>"$STATE_DIR/pkg-check.lock"; flock -n 8`.
   If that fails: `{ok:false, error:"a check is already running"}`. This lock
   is separate from #59's, so a check never blocks a write and a write never
   blocks a check.
2. **A private working directory.** It is
   `$STATE_DIR/pkg-check.XXXXXX` (0700), and the EXIT trap removes it. Use
   `chmod -R u+w` first, because Nix can leave read-only files behind.
3. **Snapshot the selection.** Copy each existing part and package into
   `snap/`, and record `H1` (one sha256 over the sorted
   `name:sha256(copy)` list).
4. **Materialise the flake as apply would see it.**
   - If `$flake` is a git work tree, copy only the tracked files, as
     they are in the work tree:
     `git -C "$flake" ls-files -z | tar -C "$flake" --null -T - -cf - | tar -C "$copy" -xf -`.
     A flake in git sees only tracked files, and apply `git add`s its own
     copies (`nixarchy-apply:413-417`). Untracked and ignored files never
     reach the store.
   - Otherwise, `cp -a` the directory, which is what a `path:` flake
     evaluates anyway.
5. **Overlay.**
   - Write `snap/<part>.nix` to `$copy/<base-rel>/nixarchy/<part>.nix`, and
     `snap/packages/*` to `…/nixarchy/packages/`.
   - Regenerate `$copy/<base-rel>/nixarchy-apps.nix` the way apply does:
     `imports = [ ./nixarchy/<part>.nix … ];` for the parts whose source
     exists, in the order apps, services, advanced, flatsnap.
6. **Evaluate.**
   - Command:
     `setsid nix eval --raw "path:$copy#nixosConfigurations.\"$(uname -n)\".config.system.build.toplevel.drvPath"`.
   - It runs in the background under `timeout 900`, with `9>&- 8>&-`, and
     its stderr is captured.
   - A `TERM`/`INT` trap kills its process group.
   - No `--impure`, and no added `--option`. Evaluation purity is what
     apply's `nh os switch` gets, nothing more.
7. **`--dry-run`** (only if evaluation passed). Run
   `nix build --dry-run "path:$copy#…toplevel"` the same way, and parse
   stderr's `this derivation will be built` / `these N derivations will be
   built` and `these N paths will be fetched (X MiB download, …)` lines into
   `{build, fetch, downloadMiB}`.
8. **Superseded?** Recompute `H2` over the live sources. If `H2 ≠ H1`, the
   verdict is `superseded`, whatever the evaluation said.

**Answer.** `{ok:true, host, verdict, drvPath?, error?, at?, dryRun?, pins, unpinned, note}`.

- `verdict` is one of `evaluates`, `fails` or `superseded`.
- `pins` are the hashes of the snapshot, so the panel can apply exactly what
  was checked.
- **`error`** is the evaluation's stderr from the first `error:` line,
  capped at 40 lines, with the copy's path rewritten:
  - `/nix/store/<hash>-source/<base-rel>/nixarchy/<part>.nix` becomes
    `~/.config/nixarchy/<part>.nix`, and the same for packages;
  - any other path in the copy becomes `<flake>/…`.
- **`at`** is `{file, line}` when the rewritten error names a selection file
  with `:<line>:`, and `null` otherwise. The copy is byte-identical to the
  source, so its line numbers are the source's.
- **`note`** always says that this checked evaluation only, not a build or
  activation. When IFD is enabled in `nix.conf`, it adds that evaluation may
  have built some inputs.
- **`{ok:false}`** only when no check could run:
  - no flake;
  - no `nixosConfigurations.<host>`, detected from the error text
    `attribute '<host>' missing`;
  - the check lock is busy;
  - the working directory cannot be created.

### 3. `apply` takes pins

`nixarchy-pkg apply [--pin <part>=<sha256>]…` forwards each pin as
`--expect-sha256 <part>=<sha256>` to `nixarchy-apply`. `<part>` must be one
of the four names, and `<sha256>` must be 64 hex characters or empty; anything
else is refused before anything runs. When `nixarchy-apply` exits 4 (a
mismatch), the final `nixarchyPkgApply.message` says: "a file changed since
you reviewed it -- nothing was copied or built; look at the queue again".

### 4. The panel: a Queue tab

- `PkgModel.tabs` gains `"Queue"` as the last tab (index 6), with
  `queueTab: tab === 6`. The list holds the keyboard, like every other tab
  except Flakes.
- **Rows**, from the latest `pending` answer, kept whole in
  `PkgModel.pendingData`:
  1. Conflicts first, in the warning colour:
     - "apps.nix was edited in the flake -- apply will keep a copy and
       overwrite it";
     - "packages/foo.nix was edited in the flake -- apply will stop".
  2. Each `changes[]` entry as one line, "brave on (apps.nix:41)". The label
     comes from the marker (`:brave` → "brave", `opt:services.x` →
     "services.x"), the verb from `change`.
  3. Each `files[]` entry not fully covered by `changes`:
     - "advanced.nix: 3 lines changed";
     - "packages/foo.nix: new";
     - "flatsnap.nix: no longer imported".
  4. When `unpinned` is not empty, a dim last line: "drafts are not pinned:
     an edit to them after you look here is still built".
- **Keys on the Queue tab:**
  - `RETURN` on a row opens its source file with `omarchy-launch-editor`.
    That takes no line number, which is why each row names its line.
  - `c` runs `check`; `SHIFT+C` runs `check --dry-run`.
  - `ESC` while a check runs cancels it (`running = false` sends TERM).
- **The check line**, above the rows:
  - "checking… (about a minute) -- ESC cancels";
  - then "evaluates ✓ -- 12 to build, 40 to fetch (180 MiB)";
  - or "fails: <first error line> (apps.nix:41)", with the full error on
    `RETURN` over that line, drawn like the apply log;
  - or "the selection changed while checking -- press c again".

  A check result is cleared by any later `refreshed()` whose `pins` differ
  from the ones it checked, so a verdict never outlives its selection.
- **Apply.**
  - The first `a` (arming) refreshes `pending`. Its message becomes
    "a again to rebuild: <total> changes" + (conflicts ? " -- <n> edited in
    the flake" : "") + " -- any other key cancels".
  - The second `a` runs `apply` with `--pin` for each of `pendingData.pins`.
    These are the pins from the answer shown when arming, or the checked pins
    when a current `evaluates` verdict exists.
  - `SHIFT+A` (terminal) stays unpinned and says so in its arming message,
    because the terminal runs `nixarchy-apply` itself.
  - Starting an apply kills a running check.
- **Footer and bar** show `total`, not `count`.

### 5. Honest failure states

- **`PkgModel` and `Panel.qml`.** `queued` becomes `-1` ("unknown") on an
  `ok:false` answer, on unparseable output, and before the first answer.
  - The footer shows "queue unknown -- <error>" and keeps the last error
    text.
  - The bar shows `?` on the badge, and its tooltip carries the error.
  - The badge is hidden only when the queue is known to be empty (`0`).
- The Queue tab on `-1` shows the error and a hint to press `r`. `r` reloads
  state and `pending`, as it does today with reindex: it calls `refreshed()`
  as well.

## Alternatives rejected

- **Counting unmarked edits into `count`.** That breaks `count == changes |
  length` for terminal users, which the intent forbids. `total` carries the
  honest number instead.
- **Evaluating the live flake with `--override-input` or an expression
  overlay.** The host imports `./nixarchy-apps.nix` from the flake's own
  source, and neither can replace a file inside it. A materialised copy is
  the only faithful way.
- **Copying the flake whole, including untracked files.** That differs from
  what a git flake evaluates, and sends ignored or secret files to the store.
  Tracked files only.
- **Running the check automatically when the queue settles.** Tens of
  seconds, gigabytes of memory, and a store copy each time. The intent says
  on demand.
- **Taking #59's lock to read a consistent snapshot.** Reads must never wait
  for writes (#59). The hash-before-and-after test (`H1`/`H2`) and the
  per-file private copy detect what a lock would prevent.
- **Pinning drafts by adding them to `--expect-sha256`.** Apply's snapshot
  loop cannot hold `packages/` today. That needs a nixarchy change, so this
  task reports drafts as unpinned instead.
- **Opening the editor at the line.** `omarchy-launch-editor` takes a path
  only. Rows name the line instead.

## Risks

- **Cost.** A check is about 68 s and some gigabytes on p620, and more on a
  laptop. It runs only on `c`, single-flight, and is cancellable. An apply
  kills it.
- **Store copy.** `path:` copies the materialised tracked tree, plus the
  user's unapplied selection, into the world-readable store. Apply already
  does the same with the copied selection, so nothing new is exposed beyond
  "before you applied". The manual says so.
- **`path:` versus git fetcher.**
  - `self.rev` and `self.dirtyRev` are absent.
  - Submodules are copied only if tracked as files.
  - Relative `path:../x` inputs break.

  In each case the check answers `fails` with Nix's own error, and apply may
  still work. The manual lists these.
- **Hostname.** The check uses `uname -n`, like apply. A flake whose
  configuration has another name fails both, and the check says
  "no nixosConfigurations.<host>".
- **IFD.** With import-from-derivation allowed, an evaluation may build. The
  `note` says so.
- **Torn reads.** A queue drawn from a mid-write read is replaced by the
  next refresh. An apply from it fails its pin and refuses, never building
  the torn bytes.
- **Hosts.** Manual checks run on razer only, never p620.

## Verification

- **`tests/adapter.sh`**, new `pending` cases, all with fixtures and stubs:
  - a `flatsnap.nix` edit;
  - a new `packages/foo.nix`;
  - an unmarked continuation-line edit in `apps.nix` (`files[].unmarked > 0`);
  - a comment-only edit;
  - the same marker in two files (two `changes`);
  - a changed marked value (`modified`);
  - a part dropped;
  - an in-flake edit with a matching record file (`conflict: overwrite`) and
    a package one (`blocks`);
  - `pins` equal `sha256sum` of each source, and `""` for an absent part;
  - a never-applied machine;
  - `count == (changes | length)` on every case;
  - `total` as defined.
- **`tests/adapter.sh`**, new `check` cases, on a fixture flake (a git repo,
  so tracked-only can be tested). Its `nixosConfigurations.<this host>` has a
  `config.system.build.toplevel` that is a trivial `derivation` whose name
  depends on importing `nixarchy-apps.nix`'s imports, and on
  `builtins.pathExists ./untracked`:
  - a clean selection gives `evaluates`, with a `drvPath` whose name shows
    the untracked file was **not** copied;
  - `throw "boom"` in `apps.nix` gives `fails`, with
    `at == {file:"apps.nix", line:N}`;
  - a `nix` stub that edits `apps.nix` mid-run gives `superseded`;
  - a second concurrent check gives `ok:false` "already running";
  - a `nix` stub answering `--dry-run` gives parsed counts;
  - `TERM` during evaluation gives one answer, and the working directory is
    gone;
  - the flake's `flake.nix`, `flake.lock` and `git status` are unchanged
    after every case.
- **`tests/adapter.sh`**, `apply --pin`: a stubbed `nixarchy-apply` receives
  `--expect-sha256 apps=<h>`, and a bad pin is refused.
- **`tests/qml/tst_pkgmodel.qml`:**
  - an `ok:false` `pending` sets `queued` to `-1`;
  - Queue rows are built from a canned answer;
  - the second `a` includes `--pin` arguments;
  - a check result is cleared when `pins` change.
- `nix flake check` and CI pass.
- **Manual, on razer:**
  - edit `advanced.nix` and see it in Queue;
  - `c` on a good selection, then on a wrong-typed option;
  - `a` with a file edited after arming is refused.
