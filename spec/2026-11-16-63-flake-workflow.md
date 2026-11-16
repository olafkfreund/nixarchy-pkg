---
status: draft
issue: 63
intent: intent/2026-11-16-63-flake-workflow.md
---

# Spec: the Flakes tab finishes what it starts

## Design

**Decisions for the owner** (open questions the intent left without a
recommendation, chosen here; overturn any of them at this gate):

1. **Overlays: shown by name, with the line to use one, never written.**
   `nix flake show --json` enumerates `overlays` as typed leaves
   (`{"default": {"type": "nixpkgs-overlay"}}`, measured below), so the
   panel can list them as honestly as `nixosModules`. Showing them costs
   one `jq` key and one row kind, and leaving them out would leave the
   issue's second bullet half done. What an overlay *changes* is not
   knowable without evaluating nixpkgs with it, so the row says only its
   name and where the line goes (`nixpkgs.overlays`).
2. **Channel parse: the panel first, the writer by companion issue.
   This relaxes an intent constraint** ("the channel parse must stay the
   same as the writer's") and needs approval here. The panel's copy
   exists so it never offers a request the writer would refuse
   (`bin/nixarchy-pkg:1264-1271`). The writer refuses only when its parse
   finds the *same* channel as the one asked for (`nixarchy-pkg-add`, the
   `mine = want_channel` branch after the `custom` warning). So the panel
   runs the writer's exact parse first, and reads the flat
   `inputs.nixpkgs.url` form **only when the writer's parse finds
   nothing**. Whenever the writer's parse finds a line, both agree, line
   for line. When it finds none the writer answers `custom`, which warns
   and proceeds and never refuses; the panel can then name the channel
   correctly at no risk. (A parse that read either form, first match
   wins, would not be safe: a flat line followed by a block-shaped line
   inside `outputs` would make the two disagree, and the writer would
   refuse what the panel offered.) The cost of not waiting for nixarchy:
   the writer's "cannot tell" warning still prints in the log for flat-form
   flakes until the companion issue lands.
3. **Tab switches clear the search field, on every tab.** The intent
   requires that no query carries into another tab's meaning. Every tab
   gives the field a different meaning (a filter, an index search, an
   option search, a flakeref), so clearing on every switch is the only
   rule that holds everywhere, and it is one line. The cost: a search is
   lost when glancing at another tab. The alternative, one remembered
   query per tab, is more state for a convenience nobody asked for.
4. **The input list reads the lock, plus the marked lines. This narrows
   an intent outcome** ("lists every input the flake declares") and
   needs approval here. An input written by hand and never locked is
   not listed; a lock older than `flake.nix` may still list one already
   deleted. Listing those exactly means parsing somebody else's Nix,
   which #3 refused, or running `nix flake lock`, which writes. Instead
   the list is the lock's root inputs plus every `#@flake-input` name in
   `flake.nix`, and when `flake.lock` is missing or older than
   `flake.nix` the tab says so: `flake.lock is older than flake.nix, so
   this list may be out of date -- the next apply locks it`.

5. **Flakes-tab keys.** RETURN on a declared input now inspects it
   (it used to remove it); SPACE twice removes; `u` twice updates;
   SHIFT+RETURN while naming declares without `follows`. RETURN keeps
   meaning "look" on this tab, as it does on a flakeref, and SPACE is
   "turn this row off" on every other tab. The cost: muscle memory from
   RETURN-removes, which is the one-key removal the intent asked to end.

**Decisions from intent approval** (taken as recommended):

- Q1: a declared input follows the machine's `nixpkgs` by default, when
  both flakes have a `nixpkgs` input, with a per-input opt-out.
- Q2: `NH_FLAKE` and `FLAKE` are not read. The panel uses
  `${NIXARCHY_FLAKE:-/etc/nixos}` exactly as `nixarchy-apply` does (its
  line 51), names the directory, and says how to change it.
- Q3: any listed input can be updated, inputs this tool did not write
  included, after a confirming second key press.
- Q6: a declared input can be inspected again, and the lines it offers
  are shown with the name it was actually declared as.

Three slices, each its own PR, in this order. Each leaves the tab
working and adds its own tests. Slice A changes no flake write. Slice B
adds one lock step to `remove` (B4). Slice C adds the new writes.

### Rebase on #60

#60 (PR #70) merges first. It does not touch any `cmd_flake_*` function,
but it moves them: on `feat/60-truthful-queue` `cmd_flake_add` starts at
`:1095`, `cmd_flake_remove` at `:1180`, `cmd_flake_list` at `:1267`,
`machine_channel` at `:1359` (main: `:1070`, `:1155`, `:1242`, `:1277`).
In `PkgModel.qml` it rewrites the arming (`disarm`, `armApply`,
`armedKind`; `:264-300` there) and moves `setTab` to `:311`, `_absorb`
to `:364`, `activate`'s flake case to `:603`, `inspect` to `:657` and
`declareAs` to `:742`. It adds `NIX=(nix --extra-experimental-features
'nix-command flakes')`; new Nix calls here use `"${NIX[@]}"`, and the
existing flake calls are switched to it in the same slice that touches
them. Line numbers below are main's unless marked "#60".

### Measured

On p620, Nix 2.35.6, in a `mktemp` directory with `HOME` and every
`XDG_*` pointed inside it, using local `path:` flakes (no network):

| What | Result |
| --- | --- |
| `nix flake show --json` on a flake with packages, overlay, module | 0.04 s; `overlays` comes back `{"default":{"type":"nixpkgs-overlay"}}`, `packages` keyed by system (`x86_64-linux: [hello]`, `aarch64-darwin: [maconly]`) |
| `nix flake show` on a directory with no `flake.nix` | fails: `error: path '/nix/store/…-source/flake.nix' does not exist` |
| `nix flake lock` adding an input, then adding a `follows` line and locking again | 0.04 s each; second lock prints `Updated input 'tool/nixpkgs': … → follows 'nixpkgs'`; the lock then has `"nixpkgs": ["nixpkgs"]` and one nixpkgs node instead of two |
| `follows` for an input the added flake does not have | locks, rc 0; every later evaluation warns `input 'nonix' has an override for a non-existent input 'nixpkgs'` |
| `follows` to an input the user's flake does not have | `error: input 'tool/nixpkgs' follows a non-existent input 'nope'` |
| `flake = false` input | locks in 0.04 s; lock node carries `"flake": false` |
| `nix flake update tool` after the source changed | 0.04 s; prints `'…narHash=A…' → '…narHash=B…'`; only that node's `locked` changes |
| `nix flake lock` after deleting an input's lines | prunes it (`Removed input 'tool'`, `Removed input 'tool/nixpkgs'`) |

Local timings are lower bounds. #3 measured a first remote `show` at
10 s, and the existing `timeout 120` stays on every call.

The last row matters to `remove`: its comment says "`nix flake lock` does
not prune" (`bin/nixarchy-pkg:1235-1237`). On this Nix it does, and
`remove` must now use that (B4).

---

### Slice A: say what is true (no new writes)

**A1. The import hint after a declare.** Today `flake add` always answers
`import: "inputs.<name>.nixosModules.default"` (`bin/nixarchy-pkg:1148`)
and `_absorb` drops it (`PkgModel.qml:279-283`). Both change:

- The adapter stops guessing. `cmd_flake_add`'s answer loses `import` and
  `importNote`, and `message` gains: `-- run 'nixarchy-pkg flake show
  <ref>' to see what it offers`. The CLI user is pointed at the truth
  rather than handed a line that may not exist.
- The panel already knows what the flake offers: the inspection the
  declare started from. `declareAs` (`PkgModel.qml:528-537`, #60 `:742`)
  saves it, before `invalidateInspection()`, as `pendingDeclare =
  {name, ref, offers}`. There is one shared writer callback (`_absorb`,
  #60 `:364`), so the answer is routed there: an answer that has `name`
  and `url` and no `apps` (the `flake add` shape) and whose `name` and
  `url` equal `pendingDeclare`'s restores `offers` as the inspection with
  `declaredAs: <name>` (see B2), so every module, package and overlay row
  carries the real name. The message line names the import directly
when the inspection listed modules: `declared <name>. To use it, add
inputs.<name>.nixosModules.default to the imports of the host that
should have it -- this tool does not know which file that is` (the
first module, `default` when there is one), so the intent's "import
line shown after a declare" needs no further key. The adapter's
`flake show` hint in `message` is replaced by this panel text. Any other answer, `setTab` or ESC clears
  `pendingDeclare`; a late answer for a cleared one is shown as a message
  only. No row is drawn for a module the inspection did not list.

**A2. Tab switches clear the query.** Decision 3. The model owns it:
`setTab` (`PkgModel.qml:202-212`, #60 `:311`) sets `query = ""` and
`results = []` after dropping naming and the inspection, and its
`runSearch()` for a carried query (`:212`) goes. The view only follows:
`Menu.qml`'s `onTabChanged` (`:333-336`) sets `search.text = ""` before
focusing, so the field and the model cannot disagree.

**A3. Removal asks first.** `activate` begins with `disarm()`
(`PkgModel.qml:360`, also on #60), so a confirmation cannot pass through
it. A new `armFlake(kind)` handles both removal (SPACE) and update (`u`,
C2) on the Flakes tab, and Menu.qml calls it before `activate`:

```js
function armFlake(kind) {            // "remove" | "update"
  var row = rowAt(cursor)
  if (!row || row.kind !== "declared") return false
  var key = kind + ":" + row.name
  if (armedFlake === key) { armedFlake = ""; message = ""
    return write(kind === "remove" ? ["flake", "remove", row.name]
                                   : ["flake", "update", row.name]) }
  disarm()
  if (kind === "update" && (row.follows || row.locked === false)) {
    message = row.name + (row.follows ? " follows " + row.follows + "; update that one"
                                      : " is not locked yet; the next apply locks it")
    return false }
  if (kind === "remove" && !row.mine) {
    message = row.name + " was not declared by this tool -- edit flake.nix to remove it"
    return false }
  armedFlake = key
  message = kind === "remove" ? "remove " + row.name + " from flake.nix? SPACE again removes it, any other key cancels" : …
  return true
}
```

`disarm()` clears `armedFlake` beside `armedChannel` (#60 `:264-269`).
Menu.qml routes SPACE and `u` on the Flakes tab to `armFlake` only when
the search field does not have the keyboard (`!search.activeFocus`, the
same gate every single-letter key already has), so a `u` typed in
`github:…` is a letter. It ignores `event.isAutoRepeat` for both (as #60
does for `a`), and its existing
"any other key cancels" path calls `disarm()`, which now covers
`armedFlake`. Removal moves from RETURN to SPACE (SPACE is "turn the row
off" everywhere else); RETURN on a declared row becomes "inspect it"
(B2).

**A4. Unknown channel refuses.** `addFromOtherChannel`
(`PkgModel.qml:412-438`): when `other === ""`, the first press says
`cannot tell which channel this machine follows from <dir>/flake.nix, so
there is no "other" channel to add from -- RETURN adds it from this one`
and does not arm. The second-press path that wrote a plain `pkg add`
(`:425-426`) is deleted.

**A5. The flat channel form.** `machine_channel`
(`bin/nixarchy-pkg:1277-1290`) keeps the writer's parse unchanged and
falls back to the flat form only when it found nothing (Decision 2):

```bash
u=$(sed -nE "s/^[[:space:]]*nixpkgs\.url[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" \
  "$flakedir/flake.nix" | head -1)           # the writer's parse, verbatim
[ -n "$u" ] || u=$(sed -nE "s/^[[:space:]]*inputs\.nixpkgs\.url[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" \
  "$flakedir/flake.nix" | head -1)           # only where the writer says custom
```

The comment is rewritten to say why the fallback can never make the
panel offer what the writer refuses, and to name the companion issue.

**A6. The directory is named.** `cmd_state` adds two fields:

```json
"flakeDir": "/etc/nixos", "flakeFound": true
```

`flakeFound` is `[ -r "$dir/flake.nix" ]`. The Flakes tab's first row is
a `head` row `flake: <flakeDir>`. When `flakeFound` is false it is
followed by a note: `no flake.nix here. The panel and nixarchy-apply both
use NIXARCHY_FLAKE (programs.nixarchy.flake sets it); it must be set in
the session the shell runs in, not only in a terminal.` The empty-state
text (`Card.qml:256-258`) defers to these rows.

### Slice B: every input, and what each offers (reads only)

**B1. `flake list` reads the lock.** It answers every input the flake
has locked, and marks the ones this tool wrote:

```json
{"ok": true, "dir": "/etc/nixos",
 "inputs": [
   {"name": "nixpkgs", "url": "github:NixOS/nixpkgs/nixos-unstable",
    "mine": false, "flake": true, "follows": null,
    "lastModified": 1794815771},
   {"name": "tool", "url": "path:/…/tool", "mine": true, "flake": true,
    "follows": null, "lastModified": 1794815771}
 ]}
```

- Names: `.nodes[.root].inputs | keys` from `flake.lock`, read with `jq`
  and no Nix call, as `flake_names` already does (`:948-960`), plus
  every `#@flake-input <name>` in `flake.nix` (Decision 4). A marked
  name the lock does not have is listed with `locked: false`.
- `stale`: top-level `true` when `flake.lock` is missing or older than
  `flake.nix`; the tab then shows Decision 4's note.
- `mine`: the name has a `#@flake-input <name>` line in `flake.nix`.
- `url`: for `mine`, the URL from its marked line (today's parse,
  `:1245-1246`); otherwise rendered from the lock node's `original`
  into a flakeref Nix accepts: `github:`, `gitlab:` and `sourcehut:`
  as `<type>:<owner>/<repo>[/<ref>]`; `git` as `git+<url>`; `tarball`
  and `file` as their `url`; `indirect` as its `id`; `path` resolved
  against the flake directory when relative. `rev`, `ref` and `dir`
  carry over as query parameters. Any other type gets `url: null` and
  `inspectable: false`, and its row says `cannot inspect a <type> input
  from here`.
- `follows`: when the root entry is an array (`inputs.x.follows = "y"`),
  the path joined with `/`; such an input has no lock node of its own.

`state.flakes` (`:1514`) passes `inputs` through unchanged, so the new
fields reach the panel. `flakeRows` (`PkgModel.qml:139-143`) maps them to
`declared` rows carrying `mine`; rows not `mine` are drawn dimmed with
`(not written by this tool)` in place of the second column.

**B4. `remove` prunes the lock.** Today `remove` leaves the input's
lock entry (`:1235-1237`). Once the list reads the lock (B1), a removed
input would stay on screen as "not written by this tool", and re-adding
it would be refused, because `add` checks names against the lock
(`flake_names own`, `:1097-1099`). That last part is a bug today too.
So `remove` runs `timeout 120 nix flake lock "$dir"` after writing
`flake.nix` and before its final `metadata` check, inside the same
transaction; the measured prune drops the input and its own
dependencies. The comment is rewritten to match. This is a write change
inside slice B, which is otherwise read-only, because B1 is wrong
without it.

**B2. Inspect a declared input again.** RETURN on a `declared` row with
`inspectable` runs `flake show <url>` and stores the answer with `declaredAs: <name>`.
`flakeRows` then shows the inspection with a head row `inputs.<name> =
<url>` and, instead of `declare this as an input`, nothing (it is
declared). A `flake: false` input says `not a flake: nothing to inspect`
and runs nothing. An input that only `follows` another says `follows
<path>: inspect that one`.

**B3. Packages for this system, overlays by name.** `cmd_flake_show`
(`:1005-1043`) changes two keys and adds one:

```jq
packages: (($f.packages // {})[$sys] // {} | keys),
overlays: (($f.overlays // {}) | if has("type") then [] else keys end),
otherCount: (($f.packages // {}) | if has("type") then 0 else
              to_entries | map(select(.key != $sys) | .value | length) | add // 0 end),
```

`$sys` is `$(uname -m)-linux`, passed with `--arg`. Shortcut: this
adapter only runs on NixOS (Linux); a Darwin host would need
`builtins.currentSystem`. `otherCount` lets the row say `12 packages
for other systems, none for x86_64-linux` instead of an empty list; an
opaque `packages` leaf (one carrying `type`) counts as none, and the
`packages` line above guards the same way.

`flakeRows` draws each as a row the way modules are drawn today
(`PkgModel.qml:119-123`), and RETURN on one shows its line, never writes
it. With `N` = `declaredAs` or the suggested name:

| Row | Line shown | Where it goes |
| --- | --- | --- |
| `module` | `inputs.N.nixosModules.<m>` | the host's `imports` |
| `package` | `inputs.N.packages.${pkgs.stdenv.hostPlatform.system}.<p>` | `environment.systemPackages` |
| `overlay` | `inputs.N.overlays.<o>` | `nixpkgs.overlays` |

An output name that is not a plain Nix identifier
(`[A-Za-z_][A-Za-z0-9_'-]*`) is quoted, with `"` and `\` escaped and `${`
written as `\${`: a package `foo.bar` is shown as
`packages.${…}."foo.bar"`, never `.foo.bar`. The package count row
(`:128`) goes. Every message keeps the existing
tail `-- this tool does not know which file that is`.

### Slice C: the new writes

All three go through #59's transaction: `begin_write`, `guard "$file"
"$lock"` before any Nix call, the baseline `metadata` check, validate,
`committed`. A failure leaves `flake.nix` and `flake.lock` byte-identical
(#59's guarantee, extended to the new verb).

**C1. `flake add` gains flags.**

```
nixarchy-pkg flake add [--no-follows] [--no-flake] <name> <flakeref>
```

- `--no-flake` writes a second marked line, `inputs.<name>.flake = false;
  #@flake-input <name>`, and implies `--no-follows`.
- Follows, by default. After the existing lock (`:1128`), read the lock.
  Eligible only when the root's `nixpkgs` entry is a string (a real
  node, not itself a follows array) and the new node
  (`.nodes[.nodes[.root].inputs[$name]]`) has an input called `nixpkgs`
  whose entry is a string (its own nixpkgs, not already following
  something). Then insert
  `inputs.<name>.inputs.nixpkgs.follows = "nixpkgs";  #@flake-input
  <name>` after the URL line, parse, lock again, then run the existing
  final `metadata` check. Reading the lock instead of guessing is what
  keeps the measured warning (`override for a non-existent input`) from
  ever being written. The answer adds `"follows": true|false` and the
  message says `-- follows this flake's nixpkgs` or nothing.
- Every line carries the marker, so `flake list` (one URL line per
  input), `remove` (deletes every marked line, `:1224`) and its
  dependency check (ignores marked lines, `:1195`) need no change.

Panel: in naming mode RETURN declares with follows; SHIFT+RETURN
declares with `--no-follows`, and the naming row says so. An inspection
that failed because the ref has no `flake.nix` answers `{ok: false, notFlake:
true, …}`, and `flakeRows` offers `declare this as a non-flake source`.
Detection is on the Nix error text, and Nix words it by source type:
`path '…/flake.nix' does not exist` was measured for `path:`; a fetched
source says `does not contain a '/flake.nix' file`. Both are matched;
the adapter test covers the first, and the second is checked on razer
with a real `github:` repository that has no `flake.nix`. Any other
failure stays a plain failure: guessing "not a flake" from an unknown
error would declare a typo.
`beginNaming` (`PkgModel.qml:518-524`, #60 `:732`) rejects every
`ok: false` inspection today; it accepts this one case and sets
`namingNonFlake = true`, which `cancelNaming`, `setTab` and the next
`beginNaming` reset. `declareAs` then sends `--no-flake`. After a
non-flake declare there is no inspection to restore (A1): the message
says `declared <name> as a non-flake source -- use it as inputs.<name>
(a path)`.

**C2. `flake update <name>`.**

```
nixarchy-pkg flake update <name>
→ {"ok": true, "name": "nixpkgs", "changed": true,
   "from": 1794000000, "to": 1794815771,
   "message": "updated nixpkgs: 2026-11-06 -> 2026-11-16. Nothing is built until you apply."}
```

`valid_input_name`, then a refusal unless `.nodes[.root].inputs[$name]`
exists in the lock, `begin_write`, `guard`, a snapshot of the lock's
nodes, baseline `metadata`, then
`timeout 120 "${NIX[@]}" flake update "$name"` in the flake directory,
then `metadata` again. `changed` compares every lock node's `locked.narHash`
in the snapshot taken *before* the baseline (which can itself lock an
unlocked input) against the end state, not only the named one: an update can move a
transitive dependency while the input itself stays put. The answer adds
`"moved": ["tool", "tool/nixpkgs"]` (node keys whose hash changed or
that were added; nodes pruned away are listed as `"removed"`). A same
`narHash` with a new `rev` or `lastModified` is the same source and does
not count. When
nothing moved the message is `<name> is already up to date` and `changed`
is false; when only dependencies moved it says so. An input whose root entry is a
`follows` is refused: `<name> follows <path>; update that one`. The
dispatcher (`:1537-1546`) gains `update`; `main`'s write-verb list
gains it for `begin_write`.

Panel: `u` on any `declared` row arms (`armedFlake = "update:<name>"`):
`update <name>? It changes what the next apply builds` and, for
`nixpkgs` and `nixarchy`, `-- the whole system`. `u` again on the same
row runs it. `u` is unused today; it is added to `nixarchy-pkg-keys`.


### Docs

`docs/manual/flakes.md` (inspect, declare, remove, the new update and
non-flake paths, follows and its opt-out, the directory row),
`docs/manual/from-a-terminal.md` (`flake add` flags, `flake update`,
the `flake list` fields, the dropped `import` key) and
`bin/nixarchy-pkg-keys` (the key changes in Decision 5) change in the
slice that changes the behaviour.

### Companion nixarchy issues

**1. `nixarchy-pkg-add` reads only the block form of `nixpkgs.url`.**
Its channel parse (`sed -nE 's/^[[:space:]]*nixpkgs\.url…'`, about line
80) misses the flat `inputs.nixpkgs.url = "…";`, so a machine whose flake
uses that form is reported as `custom`, and `--stable`/`--unstable`
print "cannot tell which channel this machine follows" every time. Read
the block form first and the flat form only when it finds none, as
nixarchy-pkg's `machine_channel` will after #63 (first-match-of-either
would let a flat line and a later block-shaped line disagree). The comment beside the parse already names the gap.

**2. Session-wide `NIXARCHY_FLAKE`.** Only if verification shows
`programs.nixarchy.flake` does not export `NIXARCHY_FLAKE` into the
graphical session (so the shell, and this panel, never see it): export
it there, so the panel and `nixarchy-apply` cannot disagree about which
flake they use. Checked during slice A; filed only if needed.

### Tests

`tests/adapter.sh` already builds throwaway flakes from local `path:`
inputs (`:123-191`), so every new case is offline:

- A5: `machine_channel` on a flat-form flake answers `unstable`; on a
  flake with a flat line and a later block-shaped line, it answers the
  block-shaped line's channel, as the writer does.
- A6: `state` answers `flakeDir` and `flakeFound` for a present and a
  missing flake.
- A1: `flake add`'s answer has no `import` key.
- B1: `flake list` on a flake with a hand-written block input lists it
  with `mine: false`; a follows-only root input has `follows` set.
- B3: `flake show` on the fixture lists `hello` and not `maconly`,
  `overlays: ["default"]`, `otherCount: 1`; on a
  directory without `flake.nix` answers `notFlake: true`.
- C1: with a fixture `lib` that has a `nixpkgs` input, `flake add` writes
  the follows line and the lock has `["nixpkgs"]`; with one that has
  none, no follows line is written and `nix flake metadata` prints no
  `non-existent input` warning; `--no-follows` writes none;
  `--no-flake` locks `"flake": false`; `remove` deletes all of an
  input's lines.
- C1 failures: make the second lock fail (an unreadable fixture after
  the first lock) and the final `metadata` fail; both leave `flake.nix`
  and `flake.lock` byte-identical, including a flake that had no lock
  before the call. A root whose `nixpkgs` is a follows array, and an
  added flake whose `nixpkgs` already follows something, get no follows
  line. A package named `foo.bar` is shown quoted.
- C2: `update` after the fixture changes answers `changed: true`; again
  answers `changed: false`; changing only the fixture's own `nixpkgs`
  answers `changed: true` with `moved` naming the dependency; a forced
  failure (unreadable source) leaves both files byte-identical (#59's
  existing md5 pattern, `:175-179`).
- B1: a marked line that is not in the lock lists `locked: false`; a
  lock older than `flake.nix` answers `stale: true`; a non-`mine`
  `github:` and a relative `path:` entry render to refs `flake show`
  accepts (fixture lock written by hand, no network).
- B4: `remove` then `flake list` no longer lists the input; `add` of the
  same name then succeeds.
- C2: `update` of a name not in the lock, and of a follows-only root
  input, refuse with nothing changed.

`tests/qml/tst_pkgmodel.qml`: `armFlake("remove")` arms and a second
call on the same row writes; a call on another row re-arms rather than
writes; `disarm` clears it; a row that is not `mine` refuses removal but
arms update; a failed inspection with `notFlake` can be named and the
declare sends `--no-flake`; `addFromOtherChannel` with `channel: "custom"`
never writes; `setTab` with a query leaves it empty; RETURN on a
`declared` row starts an inspection with `declaredAs`; a successful
declare shows the saved inspection under the declared name, and a
declare answer after `setTab` does not. Key routing (SPACE and `u`
reaching `armFlake`, autorepeat ignored) is checked by hand on razer:
`tst_pkgmodel` has no Menu.qml harness.

## Alternatives rejected

- **Write `follows` unconditionally.** One lock instead of two, but the
  measured warning then prints on every evaluation for any flake without
  a `nixpkgs` input, forever. The second local lock costs 0.04 s.
- **Learn the added flake's inputs from `nix flake metadata --json
  <ref>` before writing.** Another network call with its own failure
  modes, to learn what the lock tells us after the first lock (at the
  cost noted under Risks for a remote flake with no lock of its own).
- **Keep `import` in the adapter and run `flake show` inside `add`.**
  Correct, but a second evaluation of somebody else's flake on every
  declare, to repeat an answer the panel already holds. The CLI is
  pointed at `flake show` instead.
- **Parse `flake.nix` to list inputs.** The lock already names every
  input and needs no Nix call; parsing somebody else's Nix for block
  forms is what #3 refused to do.
- **Honour `NH_FLAKE`.** Settled by Q2: apply ignores it on purpose.
- **Per-tab remembered queries.** Decision 3.

## Risks

- **`follows` breaks a flake that needs its own nixpkgs** (an input
  pinned to an older nixpkgs for a reason). It still locks and evaluates
  metadata, so the check passes and the breakage shows only at build
  time. Mitigated by the opt-out, by the message saying it follows, and
  by `remove` + re-add with SHIFT+RETURN, which B4 makes possible.
- **Updating `nixpkgs` from the panel** changes the whole next apply.
  The second key press and the explicit "the whole system" text are the
  mitigation; nothing builds until apply.
- **Two-pass follows on a remote flake with no `flake.lock` of its
  own**: the first lock resolves and fetches that flake's own `nixpkgs`,
  which the second lock then discards. A cost (one nixpkgs fetch, once),
  not a correctness problem; the alternative is guessing, which writes
  the warning measured above.
- **`uname -m`-linux** is wrong on a non-Linux host. The adapter does not
  run on one today; a shortcut comment marks it.
- **Lock-based listing misses unlocked inputs.** Said in a note row; the
  next apply locks them.
- **Rebase drift with #60** in `PkgModel.qml`'s arming. A3 and C2 join
  #60's `disarm` rather than adding a parallel mechanism.

All writes are to the user's flake, which is `/etc/nixos` by default:
verification of slices A6 and C on a real flake happens on razer only,
never p620.

## Verification

- `tests/adapter.sh` and `tests/qml` pass, with the new cases above, and
  `nix flake check` passes (shellcheck included).
- On razer, with `NIXARCHY_FLAKE` pointing at a scratch copy of its
  flake: inspect `github:nix-community/home-manager`; declare it; check
  `flake.nix` has the URL and follows lines and `flake.lock` has
  `"nixpkgs": ["nixpkgs"]` for it; the module row shows
  `inputs.home-manager.nixosModules.default`; `u` twice on it reports
  changed or up to date; SPACE twice removes both lines; switching from
  Options with a query to Flakes leaves the field empty.
- Each slice's PR description states which intent outcomes it meets.
