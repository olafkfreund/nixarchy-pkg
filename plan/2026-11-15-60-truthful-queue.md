---
status: draft
issue: 60
spec: spec/2026-11-15-60-truthful-queue.md
coders:
  1: codex   # shared shell plumbing: on_exit cleanup vars, private copies, record/import helpers
  2: codex   # pending rewrite: row pairing, explained/total, fingerprint -- small, tricky logic
  3: codex   # check: materialise, fidelity guard, setsid/timeout/TERM, error rewrite -- tricky shell
  4: coder   # apply --pin: small and mechanical
  5: coder   # PkgModel: pendingData, queued -1, invalidation, arming state machine, QML tests
  6: coder   # Queue tab, keys, detail view, footer and bar
  7: agy     # docs across four manual pages: mechanical prose from the contracts below
reviewers:
  - codex   # bash semantics and the apply-mirroring rules are where this goes wrong
  - agy     # an independent read of the whole diff against this plan
---

# Plan: before apply, show what it will copy, and whether the result evaluates

Branch `feat/60-truthful-queue`. This file is self-contained: a coder reads
it and the files each step names, and nothing else. **Coders never stage
or commit.** The coordinator commits after each step, as
`feat(adapter): … (#60)`, `feat(panel): … (#60)`, `test: … (#60)` or
`docs: … (#60)`.

Anchors name a function and quote a line. Line numbers drift.

**After every step**, run:
- `bash -n bin/nixarchy-pkg`
- `shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh`
- `bash tests/adapter.sh`

The adapter suite has **11 pre-existing failures** on a nixarchy machine
(catalogue drift, #68): "toggling on reports enabled", "the file really
changed", "toggling off reports disabled", "services use their own file",
"a toggle counts once", "a package counts once", "one file, one change",
"and it names that file", "two files, two changes", "and both files are
named", "and it recovers once readable". Pass means no failure outside that
list.

The QML steps also need `nix flake check`.

## Decisions (from the approved spec)

**How apply behaves** (`nixarchy-apply`; mirror it, do not reinvent it):
- **Paths:**
  - `flake=${NIXARCHY_FLAKE:-/etc/nixos}`;
  - `host=$(uname -n)`;
  - `base=$flake/hosts/$host` if that directory exists, else `$flake`;
  - `base-rel` is `hosts/$host` or empty, and joins must never produce
    `//`. The adapter's `flake_base()` already computes `base`.
- **Copying:**
  - parts are apps, services, advanced, flatsnap, in that order, from
    `$CONFIG_DIR/<p>.nix` to `$base/nixarchy/<p>.nix`, when the source
    exists and differs;
  - `$base/nixarchy-apps.nix` is regenerated to import `./nixarchy/<p>.nix`
    for each part whose source exists, in that order;
  - a destination is never deleted;
  - drafts are `$CONFIG_DIR/packages/*.nix`, copied to
    `$base/nixarchy/packages/`, and retained when their source is deleted.
- **Records:** `rec=${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/applied/$(printf '%s' "$dst" | sha256sum | cut -c1-16)`.
  The record holds the full `sha256sum <"$dst"` output. "Edited in the
  flake" means `[ -f "$rec" ] && ! sha256sum <"$dst" | cmp -s - "$rec"`.
- **Conflicts:**
  - a part whose source exists, differs from its destination, and whose
    destination is edited in the flake gives `overwrite` (apply keeps a
    copy, then overwrites);
  - a draft in the same situation gives `blocks` (apply exits 1 before
    copying).
- **Pins:** `--expect-sha256 <p>=<hex|"">`, for parts only. An empty hash
  means "must be absent". Drafts cannot be pinned. A mismatch prints
  `is not what you checked`.

**Reads and private copies:**
- `pending` and `check` never take #59's lock and never wait for a write.
- `$STATE_DIR/pkg-recovery/open` existing means a write is in progress or
  was interrupted.
- Private copies use `cp -L` into `$STATE_DIR/pkg-read.XXXXXX` (pending) or
  `$STATE_DIR/pkg-check.XXXXXX` (check), mode 0700. Nothing goes to `/tmp`.
- They are cleaned **only** by the global `on_exit`, through the variables
  `READDIR` and `CHECKDIR`, which are cleared like `WORK` (`chmod -R u+w`,
  then `rm -rf`). No command installs its own `EXIT` trap. `begin_write`
  sweeps only `pkg-work.*`, never these.

**Other:**
- No `--impure` and no `--option` anywhere. Every `nix` call adds
  `--extra-experimental-features 'nix-command flakes'`, and `9>&- 8>&-`.
- Manual checks run on **razer** only, never p620.

## Steps

### 1. Shared plumbing in `bin/nixarchy-pkg`

- **Top-level variables.** After `WORK=""`, add `READDIR=""` and
  `CHECKDIR=""`.
- **`on_exit()`.** After its `WORK` cleanup block, add the same cleanup for
  `READDIR` and `CHECKDIR`. Then, if `CHILD` is set (step 3), use
  `kill -TERM -- "-$CHILD" 2>/dev/null || :`, followed by
  `wait "$CHILD" 2>/dev/null || :`. Add `CHILD=""` to the top-level
  variables.
- **Helpers**, after `flake_base()`:

  ```bash
  NIX=(nix --extra-experimental-features 'nix-command flakes')

  # imported PART BASE -- true when apply's generated import file imports it now.
  imported() { [ -f "$2/nixarchy-apps.nix" ] && grep -qF "./nixarchy/$1.nix" "$2/nixarchy-apps.nix"; }

  # record_for DST -- apply's record file for a flake destination.
  record_for() { printf '%s/applied/%s' "$STATE_DIR" "$(printf '%s' "$1" | sha256sum | cut -c1-16)"; }

  # edited_in_flake DST -- apply's own test: a record exists and no longer matches.
  edited_in_flake() { local r; r=$(record_for "$1"); [ -f "$r" ] && ! sha256sum <"$1" | cmp -s - "$r"; }

  # private_dir VAR PREFIX -- a 0700 directory in STATE_DIR, cleaned by on_exit.
  private_dir() {
    mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"
    local d; d=$(mktemp -d -p "$STATE_DIR" "$2.XXXXXX") || die "cannot create a working directory in $STATE_DIR"
    printf -v "$1" '%s' "$d"
  }

  # fingerprint DIR -- one sha256 over every part and draft copy in DIR, names included.
  fingerprint() {
    ( cd "$1" && find . -type f -name '*.nix' -print0 | sort -z |
        xargs -0r sha256sum ) | sha256sum | cut -d' ' -f1
  }
  ```

  `STATE_DIR` already includes `/nixarchy`, so `record_for` gives
  `…/nixarchy/applied/<16hex>`, which is apply's path.

→ **verify:** the three commands, plus a scratch call of each helper in a
throwaway `XDG_STATE_HOME`.

**Traps:**
- `fingerprint` must give the same answer in `pending` and `check` for the
  same files, so both snapshot into the same layout: `<p>.nix` at the top,
  and drafts in `packages/`.
- `printf -v` sets the caller's variable, so never call `private_dir`
  inside `$(...)`.

### 2. `pending` rewrite

Replace `pending_changes()` and `cmd_pending()`. Keep `marked()`.

**Read.**
1. `private_dir READDIR pkg-read`, then `writing=false`, and set it to true
   if `$TXN/open` exists.
2. `cp -L` each existing `$CONFIG_DIR/<p>.nix` to `$READDIR/<p>.nix`, and
   each `$CONFIG_DIR/packages/*.nix` to `$READDIR/packages/`.
3. Check `$TXN/open` again; if it now exists, `writing=true`.
4. An unreadable source or destination, a failed copy, or `cmp` exiting
   with 2 is `die`, with the path.

**Per part** `p`, with `src=$READDIR/$p.nix` (the private copy) and
`dst=$base/nixarchy/$p.nix`:

| condition | status |
|---|---|
| src exists, `! imported p` | `new` |
| src exists, dst missing | `new` |
| src exists, `! cmp -s src dst` | `modified` |
| src missing, `imported p` | `dropped` |
| otherwise | unchanged (no entry) |

- **`unmarked`:** `diff <(grep -v '#@' "${dst:-/dev/null}") <(grep -v '#@' "${src:-/dev/null}") | grep -c '^[<>]'`,
  with a missing side read as `/dev/null`. Guard the `grep -c`, which exits
  1 on 0, under `pipefail`.
- **`hunk`:** `diff -u` of the two sides, capped at 200 lines.
- **`conflict`:** `overwrite` when src exists, dst exists, they differ, and
  `edited_in_flake "$dst"`; `null` otherwise.

**Marked rows**, per part, from `diff <(marked dst) <(marked src)` as today:
- Pair one-to-one, **per file and marker**: the k-th `-` row of a marker
  and its k-th `+` row become one row, with change `modified`.
- Unpaired `+` rows are `on` (empty type, a catalogue row) or `added`.
  Unpaired `-` rows are `off` or `removed`.
- Each row is `{marker, file, line, change, lineNo}`. `lineNo` is the
  1-based line of `line` in the private `src`, or `null` for `off` /
  `removed`.
- Do the pairing in `jq`, with `group_by([.file, .marker])` followed by
  index pairing. The old `group_by(.marker)` must disappear.

**Drafts:** each `$READDIR/packages/<n>.nix`, against
`dst=$base/nixarchy/packages/<n>.nix`:
- status `new` (dst missing) or `modified`;
- `unmarked` and `hunk` as for parts;
- `conflict: "blocks"` when they differ and `edited_in_flake`.

**Answer** (one `jq -n`):
- **Existing fields:** `ok`, `neverApplied`, `base`, `count`
  (`changes | length`) and `changes`.
- **`writing`.**
- **`files[]`:** `{file, path, status, unmarked, hunk, conflict, explained}`.
  - `file` is `"apps"` for a part, or `"packages/foo.nix"` for a draft.
  - `path` is the **live** source path, or the flake destination when the
    source is gone.
  - `explained` is `status == "modified" and unmarked == 0` and at least
    one `changes[]` row has this `file`.
- **`total`:** `(changes | length) + (files | map(select(.explained | not)) | length)`.
- **`fingerprint`:** `fingerprint "$READDIR"`.
- **`pins`:** for each part, `sha256` of `$READDIR/<p>.nix`, or `""`.
- **`unpinned`:** `{drafts: [every packages/*.nix that exists, changed or not], flake: true}`.

**Tests.** Add to `tests/adapter.sh`, in a new section
`echo "the queue apply will copy (#60)"`, outside `HAVE_CATALOGUE`, with
throwaway `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `NIXARCHY_FLAKE`. Build a
fake applied state by hand: `$flake/nixarchy/*.nix`,
`$flake/nixarchy-apps.nix`, and record files written the way apply writes
them (`sha256sum <dst > rec`). One case each:
1. a `flatsnap.nix` edit;
2. a new draft;
3. an unmarked continuation-line edit under an unchanged marked line;
4. a whitespace-only edit (`total ≥ 1`, `explained: false`);
5. an edit to a commented catalogue line;
6. the same marker in two files, and twice in one file (separate rows);
7. a changed marked value (`modified`, with `lineNo`);
8. a dropped part (`dropped`);
9. after "applying" (regenerating `nixarchy-apps.nix` without that part),
   unchanged;
10. a re-created part identical to the leftover destination (`new`);
11. a record mismatch with `src` present (`overwrite`), and with `src`
    deleted (no conflict);
12. a draft mismatch (`blocks`);
13. `pins` equal to `sha256sum` of each source, and `""` when absent;
14. `unpinned.drafts` listing an unchanged draft;
15. a draft edit that changes `fingerprint` and leaves `pins` the same;
16. `writing: true` while `$XDG_STATE_HOME/nixarchy/pkg-recovery/open`
    exists;
17. an unreadable destination (`ok:false`);
18. a never-applied machine (every part `new`).

In every case, check `count == (changes|length)`, `total == 0` iff
`files == []`, no `pkg-read.*` left, and an empty `TMPDIR`.

→ **verify:** the three commands.

**Traps:**
- The old answer's `count` must keep its meaning; its numbers may rise
  only through the merge fix.
- `diff` exits 1 on differences. Use `|| rc=$?` patterns, as
  `pending_changes` does today.
- Never compare a destination against the **live** source: always use the
  private copy.

### 3. `check`

A new `cmd_check()`. Wire `check)` in `main` and the usage string, and add
`check [--dry-run]` to the header comment. `--dry-run` is the only flag;
anything else is `die`.

**Steps, in order.** Every failure produces exactly one JSON answer.

1. **Single flight.** `mkdir -p "$STATE_DIR"`, then
   `exec 8>"$STATE_DIR/pkg-check.lock"`, then `flock -n 8`, or answer
   `{ok:false, error:"a check is already running"}`. Then remove stale
   `$STATE_DIR/pkg-check.*/` directories, using `chmod -R u+w` first. Never
   remove the `.lock` file.
2. **Writes.** If `$TXN/open` exists: `ok:true`, `verdict:"unknown"`,
   `reason:"a write is in progress or was interrupted -- try again, or run recover"`.
3. **Snapshot.** `private_dir CHECKDIR pkg-check`. Snapshot exactly as step
   2 reads, into `$CHECKDIR/snap`. `F1=$(fingerprint "$CHECKDIR/snap")`,
   and the pins as `pending` computes them.
4. **Fidelity guard.** Each of these gives `verdict:"unknown"` with a
   `reason`:
   - `$flake/.git` exists, and
     `git -C "$flake" grep -lE 'self\.(rev|shortRev|dirtyRev|dirtyShortRev|lastModified|lastModifiedDate)\b' -- '*.nix'`
     matches;
   - `jq -e '[.nodes[]? | .locked? // empty | select(.type=="path" and ((.path // "") | startswith("/") | not))] | length > 0' "$flake/flake.lock"`
     is true;
   - `$flake/.git` exists, and `git -C "$flake" ls-files -s` has any line
     starting `160000`.
5. **Materialise** into `$CHECKDIR/flake`:
   - **When `$flake/.git` exists:**

     ```bash
     git -C "$flake" ls-files -z | while IFS= read -r -d '' f; do
       if [ -e "$flake/$f" ] || [ -L "$flake/$f" ]; then printf '%s\0' "$f"; fi
     done | tar -C "$flake" --null --no-recursion -T - -cf - | tar -C "$CHECKDIR/flake" -xf -
     ```

     Then copy the real `$base/nixarchy/`, if it exists, into the same
     relative place in the copy: `cp -a "$base/nixarchy/." "$copy/<base-rel>/nixarchy/"`.
   - **Otherwise:** `cp -a "$flake/." "$CHECKDIR/flake"`.
   - Any failure gives `verdict:"unknown"`, `reason:"could not copy the flake: <stderr>"`.
6. **Overlay.**
   - If `$copy/<base-rel>`, `$copy/<base-rel>/nixarchy` or
     `$copy/<base-rel>/nixarchy/packages` is a symlink: `verdict:"unknown"`,
     `reason:"the flake's nixarchy directory is a symlink -- the check will not write through it"`.
   - `mkdir -p` those directories.
   - For each snapshot part and draft: `rm -f` the target, then `cp` from
     `snap/`.
   - `rm -f "$copy/<base-rel>/nixarchy-apps.nix"`, then write the same text
     apply generates:
     - the three `#` comment lines;
     - `{`;
     - `  imports = [ ./nixarchy/<p>.nix … ];` for the parts present in the
       snapshot, in order;
     - `}`.
7. **Root and host.**
   - `root=$("${NIX[@]}" flake metadata --json "path:$copy" 9>&- 8>&- 2>"$CHECKDIR/err" | jq -r .path)`.
     On failure: `verdict:"fails"`, with the rewritten error (rule below).
   - `"${NIX[@]}" eval --json "path:$copy#nixosConfigurations" --apply "c: builtins.hasAttr \"$host\" c"`.
     If that prints `false`:
     `{ok:false, error:"this flake has no nixosConfigurations.<host>"}`.
8. **Evaluate.**

   ```bash
   setsid timeout 900 "${NIX[@]}" eval --raw \
     "path:$copy#nixosConfigurations.\"$host\".config.system.build.toplevel.drvPath" \
     >"$CHECKDIR/out" 2>"$CHECKDIR/err" 9>&- 8>&- &
   CHILD=$!
   trap 'exit 143' TERM INT HUP   # already global; on_exit kills -$CHILD
   rc=0; wait "$CHILD" || rc=$?; CHILD=""
   ```

   - `rc == 124`: `verdict:"unknown"`, `reason:"timed out after 15 minutes"`.
   - Any other non-zero `rc`: `verdict:"fails"`.
   - `0`: `verdict:"evaluates"`, with `drvPath=$(cat out)`.
9. **`--dry-run`**, only after `evaluates`:
   `setsid timeout 900 "${NIX[@]}" build --dry-run "$drvPath^*"`, the same
   way, with stderr to `dry`. Parse it with `awk`:
   - `/will be built/` gives the count from `these ([0-9]+) derivations`,
     or 1 when the line says `this derivation`;
   - `/will be fetched/` gives the count the same way (`these N paths` or
     `this path`);
   - the size comes from `\(([0-9.]+) (B|KiB|MiB|GiB) download`, converted
     to MiB with two decimals.

   A failed dry run, or no recognisable lines when the output was not
   empty, gives `dryRun: null` and `dryRunError`. A run with nothing to
   build or fetch gives `{build:0, fetch:0, downloadMiB:0}`.
10. **Superseded.** Snapshot the live sources again, as in step 3, into
    `$CHECKDIR/snap2`, and compute `F2`. If `F2 != F1`, or `$TXN/open`
    exists, the verdict becomes `superseded`.

**Error rewrite** (`fails` only). Read `$CHECKDIR/err` and replace, as
literal strings with no regex:
1. `"$root/<base-rel>/nixarchy/packages/"` and
   `"$copy/<base-rel>/nixarchy/packages/"` become
   `"$CONFIG_DIR/packages/"`. A draft that exists only in the flake maps to
   `"$base/nixarchy/packages/"` instead.
2. `"$root/<base-rel>/nixarchy/"` and `"$copy/<base-rel>/nixarchy/"` become
   `"$CONFIG_DIR/"`.
3. `"$root/"` and `"$copy/"` become `"$flake/"`.

Other store paths are left untouched.

- **`error`:** the last 200 lines.
- **`summary`:** the last line matching `^error: .+`, with the `error: `
  prefix dropped.
- **`at`:** the last occurrence of `$CONFIG_DIR/<x>.nix:<n>:` gives
  `{file:"<x>.nix", line:n}`. Otherwise the last
  `In '$CONFIG_DIR/<x>.nix'` gives `{file, line:null}`. Otherwise `null`.

**Answer:**
`{ok:true, host, verdict, reason?, drvPath?, summary?, error?, at?, dryRun?, dryRunError?, fingerprint:F1, pins, unpinned, blocked, note}`.
- **`blocked`:** the drafts whose `conflict` would be `blocks`, computed as
  in step 2.
- **`note`:** "Checked evaluation only, not a build or a switch." When
  `nix config show allow-import-from-derivation` prints `true`, add " With
  import-from-derivation on, evaluating may have built some inputs."

**Tests** (same section, after step 2's). They build a fixture **git** flake
in a throwaway directory (`git init`, `git add`, no commit needed):
- `flake.nix` with `outputs = { self }: { nixosConfigurations."<host>" = { config.system.build.toplevel = derivation { name = if builtins.pathExists ./untracked then "leak" else "ok-${toString (builtins.length (import ./nixarchy-apps.nix).imports)}"; system = "x86_64-linux"; builder = "/bin/sh"; }; }; };`,
  with `<host>` baked in from `uname -n`;
- `nixarchy-apps.nix` and `nixarchy/apps.nix` as files that evaluate.

To make an import error surface, `toplevel` also forces
`map (f: import f) (import ./nixarchy-apps.nix).imports` through
`builtins.seq`.

Cases:
1. `evaluates`, and `drvPath` matches `-ok-1.drv`, after creating an
   **untracked** file `./untracked` (proves it was not copied);
2. `throw "boom"` in `$CONFIG_DIR/apps.nix` gives `fails`, `summary`
   containing `boom`, and `at.file == "apps.nix"`;
3. `<base>/nixarchy` as a symlink to a scratch directory gives `unknown`,
   and the scratch directory is unchanged;
4. a fake gitlink (`git update-index --add --cacheinfo 160000,<40 hex>,sub`)
   gives `unknown`;
5. a tracked file deleted from the work tree still evaluates;
6. `self.rev` mentioned in `flake.nix` gives `unknown`;
7. a `nix` stub on `PATH` that edits `apps.nix`, then runs the real `nix`,
   gives `superseded`;
8. `pkg-recovery/open` present gives `unknown`;
9. a check run while another holds `pkg-check.lock` (hold it with
   `flock … exec sleep`) gives `ok:false`;
10. no `nixosConfigurations.<host>` gives `ok:false`;
11. a `nix` stub for `build --dry-run`, printing the singular, plural, KiB
    and GiB forms, parses them; garbage gives `dryRun:null`;
12. `kill -TERM` of a check started directly (not through a function; see
    the #59 lesson) gives no leftover `pkg-check.*/` and no live child;
13. after every case, the fixture flake's `git status --porcelain` and file
    hashes are unchanged.

→ **verify:** the three commands. Then remove the `[ -e "$flake/$f" ]`
filter in a scratch copy: case 5 must fail.

**Traps:**
- Never `$(...)` the evaluation. Bash defers the `TERM` trap until a
  command substitution finishes.
- `setsid` wraps `timeout`, not the other way round.
- Kill by the saved pid, never with `pkill -f`.
- Every `nix` call closes fd 8 and fd 9.
- Under `set -e`, every expected non-zero exit uses `|| rc=$?`.

### 4. `apply --pin`

`cmd_apply()`:
- Parse `--pin <p>=<hex>`, repeatable. `<p>` must be one of apps, services,
  advanced or flatsnap, and `<hex>` must match `^[0-9a-f]{64}$` or be empty.
  Anything else is `die` before anything runs.
- Forward each pin as `--expect-sha256 "<p>=<hex>"` to `nixarchy-apply`.
- After the run, if the filtered log contained `is not what you checked`,
  the final `nixarchyPkgApply.message` is "a file changed since you
  reviewed it -- nothing was copied or built; look at the queue again".
  Capture this by having the `awk` filter also `print > "$flag"` on a
  match, in a private file.

**Tests:** extend the existing `run_apply` stub section:
- the stub records its argv, and `--expect-sha256 apps=<h>` must appear;
- `--pin bogus=1` gives `ok:false`;
- a stub printing `apps.nix is not what you checked` and exiting 4 gives
  that message.

→ **verify:** the three commands.

### 5. `PkgModel.qml`

- **Properties:**
  - `pendingData: null`;
  - `queueError: ""`;
  - `queued` starts at `-1`, instead of 0;
  - `checkResult: null`, `checkRunning: false`;
  - `armingState: ""`, which is `""`, `"reading"` or `"armed"`;
  - `armedKind: ""`;
  - `armedPins: ({})`;
  - `armedFingerprint: ""`.
- **`tabs`** gains `"Queue"`; `readonly property bool queueTab: tab === 6`.
- **`_pending` `onStreamFinished`:**
  - Parse the answer. On `ok:true`, set `pendingData`,
    `queued = (typeof data.total === "number") ? data.total : -1`,
    `neverApplied`, and `queueError = ""`.
  - On `ok:false`, or a parse error: `queued = -1`,
    `queueError = data.error || "could not read the queue"`.
  - **Then invalidate:**
    - if `checkResult` is set and its `fingerprint` differs from
      `data.fingerprint`, set `checkResult = null`;
    - if `armingState === "reading"`, freeze: `ok:false` or `writing`
      calls `disarm()` with the reason in `message`; otherwise set
      `armedPins` (taken from `checkResult` when it is `evaluates` and
      fingerprints match, else from `data.pins`) and `armedFingerprint`,
      then `armingState = "armed"`, set the message, and restart the
      timer;
    - if `armingState === "armed"` and the fingerprint differs from
      `armedFingerprint`: `disarm()`, with "the queue changed -- review it
      again".
- **`armApply(kind)`.** It keeps its signature and two-press contract, but:
  - **First press:**
    - with `queued === -1 && queueError` set, refuse with "queue unknown --
      press r";
    - otherwise `armingState = "reading"`, `armedKind = kind`,
      message "reading the queue…", `refreshPending()`, and return
      `false`.
  - **Press while `reading`:** the message is "still reading the queue",
    and it returns `false`.
  - **Press while `armed`** with the same kind: clear the state and return
    `true`.
  - **`disarm()`** also clears `armingState`, `armedPins` and
    `armedFingerprint`.
- **`refreshPending()`.** If `_pending.running`, set `_pendingAgain = true`.
  In `onExited`, if `_pendingAgain`, clear it and run again. This makes sure
  the arming read is a fresh one.
- **`apply()`:** `_apply.command = [script, "apply"]` plus
  `"--pin", p + "=" + armedPins[p]` for each part.
- **`applyInTerminal()`:** `_applyTerm.command` is
  `["omarchy-launch-floating-terminal-with-presentation", "nixarchy-apply"]`
  plus `"--expect-sha256=" + p + "=" + armedPins[p]` for each part.
- **Both:** first, if `checkRunning`, set `_check.running = false`, and
  start the apply in `_check`'s `onExited` (a pending flag), never before.
- **Check:**
  - `_check` is a `Process` running `[script, "check"]`, plus `"--dry-run"`
    when asked.
  - `function check(dry)` refuses while `checkRunning` or `applying`;
    otherwise it sets `checkRunning = true` and `checkResult = null`.
  - On stream finished, parse the answer. If its `fingerprint` is not equal
    to `pendingData.fingerprint`, set `verdict = "superseded"`. Then
    `checkResult = data`.
  - `onExited`: `checkRunning = false`.
  - `cancelCheck()` sets `_check.running = false`.
- **`rows()`** for the Queue tab returns row objects
  `{kind: "check"|"conflict"|"writing"|"change"|"file"|"note", text, path, detail}`,
  built in this order:
  1. the check row, if `checkRunning || checkResult`;
  2. `files[]` with a conflict;
  3. `writing`;
  4. `changes[]`;
  5. `files[]` with `explained:false`;
  6. the unpinned note.

  Texts are as written in the step 6 list. `path` is set only when the live
  source exists; `detail` is the row's `line`, its `hunk`, or the check's
  `error`.

**Tests** in `tests/qml/tst_pkgmodel.qml`, using the existing stub
`Process` (assert on `command` and `running`). Extend `cleanup()` to reset
every new property. Cases:
1. `queued === -1` before any answer;
2. after `ok:false`, `queued` is `-1` and `queueError` is set;
3. a `total: 0` answer keeps 0;
4. arming: the first press sets `reading` and returns false; feeding an
   answer sets `armed` and `armedPins`; a second press returns true;
5. feeding a second answer with another fingerprint while armed disarms;
6. arming refuses when `queued === -1` and `queueError` is set;
7. `apply()` puts `--pin apps=<h>` in `_apply.command`;
8. a `checkResult` is cleared by an answer with another fingerprint, drafts
   only;
9. a check answer whose fingerprint does not match is marked superseded.

→ **verify:** `nix flake check`.

**Traps:**
- `data.total || 0` turns 0 into 0 but also `undefined` into 0. Always use
  `typeof`.
- `_absorb` emits `refreshed()` before `_pending` finishes. Do not hang
  invalidation on `refreshed()`.

### 6. The Queue tab, keys, footer and bar

**`Card.qml`**, drawing Queue rows (`kind` gives the style):
- `check` and `conflict` rows use the warning or dim colour.
- `change` rows read:
  - `<label> <verb> (<file>.nix:<lineNo>)`, or `(<file>.nix)` when
    `lineNo` is null;
  - the label is the marker after its type, so `:brave` gives "brave" and
    `opt:services.x` gives "services.x";
  - the verb is "on", "off", "added", "removed" or "changed".
- `file` rows read:
  - "<file>.nix: N lines changed" for `modified` with `unmarked > 0`;
  - ": new", ": no longer imported" (dropped);
  - ": whitespace or comments changed" for `modified` with `unmarked == 0`.
- The note row is dim.
- **Footer:**
  - `queued === -1`: "queue unknown -- <queueError>" when `queueError` is
    set, else "reading queue…";
  - `0`: "nothing queued";
  - otherwise: "N changes queued".

**`Menu.qml`:**
- **Queue tab first.** Add a Queue-tab block before the shared key handlers,
  and the `SHIFT+C` case in the modifier section, above the no-modifier
  block:
  - `c`: `pkg.check(false)`.
  - `SHIFT+C`: `pkg.check(true)`.
  - `r`: `pkg.refresh()`, not reindex, on this tab only.
  - `RETURN`: `omarchy-launch-editor <path>` (through a `Process`) when the
    row has a `path`; otherwise open the detail view on `detail`.
  - `ESC`: close the detail view if open; else `pkg.cancelCheck()` if
    `checkRunning`; else the existing behaviour.
- **Detail view.** A scrollable plain-text view, shown when
  `pkg.detailText !== ""` (a new model property). It is separate from the
  apply log. It closes on `ESC` or any key but `HOME`/`END`/`PgUp`/`PgDn`,
  and never calls `detachFromLog()`.
- **`SHIFT+A`** keeps `if (pkg.applyInTerminal()) root.close()`.

**`Panel.qml`:**
- `queued` starts at `-1`. On `ok:true`, use
  `queued = (typeof data.total === "number") ? data.total : -1`. On
  `ok:false` or a parse error: `queued = -1`, `queueError = …`.
- **Badge:** `?` when `queued === -1 && queueError`; hidden when
  `queued === 0`, or `-1` with no error; else the number.
- **Tooltip:** the error, when there is one.

**Key sheet (`bin/nixarchy-pkg-keys`):** add Queue-tab lines for `c`,
`SHIFT+C`, `r`, `RETURN` and `ESC`.

**Test:** in `tests/qml/tst_card.qml`, a footer case for each of `-1` with
an error, `-1` without one, and `0`.

→ **verify:** `nix flake check`.

**Traps:**
- `queued` is read in `Card.qml`, `Panel.qml` and the arming message. Grep
  `queued` and handle `-1` at every site.
- The no-modifier block never sees `SHIFT+C`.

### 7. Docs

- **`docs/manual/applying.md`:**
  - the Queue tab: what each row means, `c` / `SHIFT+C`, the check's four
    verdicts;
  - pinning, and what stays unpinned (drafts and the flake's own files);
  - why `a` now says "reading the queue…" first.
- **`docs/manual/from-a-terminal.md`:**
  - `pending`'s new fields (`writing`, `files[]`, `total`, `fingerprint`,
    `pins`, `unpinned`) and the `modified` change;
  - `check [--dry-run]` and its answer;
  - `apply --pin`;
  - fix the old `.changes[].id` example to `.changes[].marker`.
- **`docs/manual/troubleshooting.md`:**
  - "could not check: …", one paragraph per reason;
  - "superseded";
  - "a file changed since you reviewed it";
  - "edited in the flake";
  - "queue unknown".
- **`docs/manual/how-it-works.md`:** one paragraph. The check copies the
  flake's tracked files plus your selection into a private directory and
  evaluates it. That puts it in the store, as apply would. It never
  switches.

→ **verify:** read the pages back. Every command is in a fenced `bash`
block.

### 8. The coordinator: review, CI, PR

- **Review.** A fresh Opus agent gets this plan and `git diff main...HEAD`,
  while Codex and agy review read-only in parallel. Fix what holds up, each
  fix with a test, and record deviations here.
- **Ship.** Push, watch CI, and open the PR, linking intent, spec and plan
  and saying which steps each implementer did.
- **Manual checks on razer**, after the owner's go-ahead to deploy there:
  - an `advanced.nix` edit shows in Queue;
  - `c` on a good selection, then on a wrong-typed option;
  - `a`, an external edit, then `a` disarms;
  - `SHIFT+A` is pinned.

## Tests

```bash
bash -n bin/nixarchy-pkg
shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh
bash tests/adapter.sh       # no failure outside the 11 listed above
nix flake check             # shellcheck, manifest, qml-tests, qml-syntax, style
```

## Rollback

Revert the step commits.
- `pending` is additive: the old fields keep their meaning, so terminal
  scripts are unaffected either way.
- `check` and `--pin` are new.
- Nothing changes on a host until the plugin is rebuilt. `pkg-read.*` and
  `pkg-check.*` are inert directories under the state directory.
