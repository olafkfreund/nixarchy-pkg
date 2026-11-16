---
status: approved
issue: 63
spec: spec/2026-11-16-63-flake-workflow.md
coders:
  A1: coder   # adapter answer shape and one test; code is given
  A2: codex   # pendingDeclare matching against late and stale answers, setTab ordering
  A3: coder   # armFlake is given verbatim; Menu.qml routing follows the existing letter block
  A4: coder   # one branch deleted, one message changed
  A5: codex   # small, but pipefail/SIGPIPE-sensitive sed and the writer-agreement argument
  A6: coder   # two state fields, one head row, one Card branch
  A7: coder   # QML cases on the existing stub pattern
  A8: agy     # docs and the key sheet, bounded text edits (fallback: coder)
  B1: codex   # jq over flake.lock: follows arrays, original -> flakeref rendering, stale
  B2: coder   # inspect a declared row; mapping is given
  B3: coder   # three jq keys and the row/line table; quoting rule is given
  B4: coder   # one lock call inside the existing transaction, comment rewritten
  B5: coder   # adapter + QML cases for slice B, hand-written fixture lock
  B6: agy     # docs for slice B (fallback: coder)
  C1: codex   # two-pass follows inside #59's transaction, --no-flake first write, notFlake detection
  C2: codex   # flake update: snapshot order, every-node comparison, refusals
  C3: coder   # panel wiring for C1/C2 keys and naming variants
  C4: codex   # failure-injection cases that must leave both files byte-identical
  C5: agy     # docs and key sheet for slice C (fallback: coder)
reviewers:
  - codex   # bash/jq semantics and #59's transaction are where this can go wrong
  - agy     # independent read of each slice's diff against this plan
---

# Plan: the Flakes tab finishes what it starts

Self-contained: a coder reads this file and the files each step names,
nothing else. **Coders never stage, commit, push, build or switch.** The
lead commits after each step (`feat(adapter): … (#63)`, `feat(panel): …
(#63)`, `test: … (#63)`, `docs: … (#63)`), runs the checks, and opens one
PR per slice.

Line numbers are on `main` at `322d021` (#60 merged). They drift once a
step adds code; anchors also name the function and quote a line.

## Decisions (from the approved spec and intent)

- **Three slices, three PRs, in order A → B → C.** Each leaves the tab
  working and carries its own tests. A writes nothing new. B is reads,
  plus one lock call in `remove` (B4). C adds the new writes.
- **Writes stay inside #59's transaction:** `begin_write`, `guard "$file"
  "$lock"` before any Nix call, the baseline `metadata`, validate,
  `cp` (never `mv`, #39), `committed`. A failure leaves `flake.nix` and
  `flake.lock` byte-identical.
- **The panel never edits the user's `inputs { }` block.** It writes only
  top-level `inputs.<name>.*` lines, and every one carries
  `#@flake-input <name>`. It never wires a module, package or overlay into
  a host: those lines are shown, never written.
- **Follows by default** (`inputs.<name>.inputs.nixpkgs.follows =
  "nixpkgs"`) only when the lock shows the user's root has a real
  `nixpkgs` node and the added flake has its own `nixpkgs` input (both
  string entries, not follows arrays). Opt-out per input: `--no-follows`,
  SHIFT+RETURN while naming. `--no-flake` implies `--no-follows`.
- **Flake directory:** `${NIXARCHY_FLAKE:-/etc/nixos}`, as `nixarchy-apply`
  (its line 51). `NH_FLAKE` and `FLAKE` are not read. The tab names the
  directory and says how to change it.
- **Any listed input can be updated**, including ones this tool did not
  write, after a second key press. Only inputs this tool wrote can be
  removed.
- **A declared input can be inspected again**; its lines use the name it
  was declared as.
- **Overlays are shown by name** with the line to use one
  (`nixpkgs.overlays`), never written. (Owner decision 1.)
- **Channel parse:** the writer's exact parse first; the flat
  `inputs.nixpkgs.url` form only when that finds nothing. (Owner decision
  2, relaxes "must stay the same as the writer's".)
- **Tab switches clear the search field**, every tab. (Owner decision 3.)
- **The input list is the lock's root inputs plus every marked name.**
  An input never locked is not listed; a lock older than `flake.nix`
  shows a note. (Owner decision 4.)
- **Flakes-tab keys:** RETURN on a declared input inspects it; SPACE twice
  removes; `u` twice updates; SHIFT+RETURN while naming declares without
  follows. (Owner decision 5.)
- **Nix calls** use the `NIX` array (`bin/nixarchy-pkg:1287`); each slice
  switches the flake calls it touches to `"${NIX[@]}"`. Every call keeps
  `timeout 120` and `9>&-`.

## Corrections to the spec

Re-verified on p620 (Nix 2.35.6, `mktemp` flakes under the session
scratchpad, `HOME` and every `XDG_*` inside it, `path:`/`git+file:`/
`file:` sources only, no network):

1. **Non-flake error text (spec C1).** The spec's second wording, `does
   not contain a '/flake.nix' file`, was not produced by any source type
   tried. Measured:
   - `path:` → `error: path '/nix/store/…-source/flake.nix' does not exist`
   - `file:`/`tarball+file:` → `error: path '«file:///…/plain.tar.gz»/flake.nix' does not exist`
   - `git+file:` → `error: Path 'flake.nix' does not exist in Git repository "…"`

   Detection matches `[Pp]ath '[^']*flake\.nix' does not exist` on the
   `nix_why` line. `github:` is fetched as a tarball and is expected to
   take the second form; the lead confirms it on razer (Tests, manual 4).
2. **Same `narHash`, new `rev` (spec C2).** Measured with a `git+file:`
   input and an empty commit: `nix flake update gs` rewrites `flake.lock`
   (`rev` changes, `narHash` identical). The spec's "already up to date"
   would then be said over a file that changed. C2 answers `changed:
   false, lockChanged: true` and says `<name>: a newer revision with the
   same contents -- nothing to rebuild`.
3. **No write-verb list in `main` (spec C2).** On `322d021`, `main()`
   (`:1990`) dispatches only; every write calls `begin_write` itself
   (`cmd_flake_add` `:1108`). `cmd_flake_update` does the same, and
   `cmd_flake` (`:1979-1987`) gains `update`.
4. **`--no-flake` goes in the first candidate (spec C1).** Locking a URL
   line without `flake = false` makes Nix read the source's `flake.nix`
   and fail (correction 1). Both marked lines are written before the
   first lock.

Confirmed as the spec says: `nix flake lock` prunes a removed input and
its own dependencies (`Removed input 'tool'`, `Removed input
'tool/nixpkgs'`); a follows for an input the added flake lacks locks rc 0
and warns `input 'nonix' has an override for a non-existent input
'nixpkgs'` on every evaluation; a follows to an input the user's flake
lacks fails `error: input 'tool/nixpkgs' follows a non-existent input
'nope'`; `beginNaming` is at `PkgModel.qml:732`; the channel fallback is
safe, because `nixarchy-pkg-add` refuses only when its own parse finds
the channel asked for (`if [ "$mine" = "$want_channel" ]`), and `custom`
warns and proceeds. Also checked: the spec's `!search.activeFocus` gate
for SPACE and `u` is reachable on the Flakes tab, because Down/Up in the
field call `root.focusList()` (`Menu.qml:384-409`).

## Traps (apply to every step)

- **One JSON answer on every path.** `die` answers once; nothing else
  prints to stdout before or after. Nix's stderr goes to `$err`, never
  stdout.
- **errexit/pipefail.** No `cmd | head`, no `grep | head`, no
  `diff`/`cmp`/`comm` at the head of a pipeline: SIGPIPE or a no-match
  exit kills the script without an answer. Use one `awk` (exits 0
  either way) or `sed -n '/re/{s//\1/p;q}'`. `|| true` only where a
  failure is truly the same as "nothing".
- **Children never keep the lock:** `9>&- 8>&-` on every Nix call and
  every child in a write path.
- **Nothing written to `/tmp` by a write.** After `begin_write`, `mktemp`
  lands in `$WORK` (TMPDIR). Read verbs (`show`, `list`) may not create
  files at all, except the existing `cmd_flake_show` `$err`.
- **QML stubs:** `Process.deliver(text)` feeds the collector, *then*
  sets `running = false`; `finish(code)` emits `exited` without an
  answer. A real `Process` ignores `running = true` while it is already
  running, so a test that writes twice must `deliver` or `finish` in
  between.
- **`awk -v` processes escapes**: pass data through `ENVIRON`, as the
  existing writers do.
- **Input names** stay `valid_input_name` (`:1076-1079`), checked whole
  before they reach grep, awk or sed.

## Steps

### 0. Rebase and re-check (lead)

`git rebase main` on `feat/63-flake-workflow` (main is `322d021` or
later). Re-check every anchor below with:

```
grep -n '^cmd_flake_\|^machine_channel\|^flake_names\|^cmd_state\|^cmd_flake()\|^NIX=' bin/nixarchy-pkg
grep -n 'function flakeRows\|function disarm\|function setTab\|function _absorb\|function activate\|function addFromOtherChannel\|function inspect\|function beginNaming\|function declareAs\|function cancelNaming' PkgModel.qml
grep -n 'onTabChanged\|case Qt.Key_Space\|case Qt.Key_Return\|Single letters' Menu.qml
```

If any moved more than a few lines, update the numbers in this file in
the same commit as step A1.

---

### PR A: say what is true (no new writes)

**A1. `flake add` stops guessing the import** — `bin/nixarchy-pkg`
`cmd_flake_add`, the final `jq -nc` (`:1170-1174`).
Drop `import` and `importNote`. `message` becomes
`"declared <name> and locked it -- run 'nixarchy-pkg flake show <ref>'
to see what it offers"` (plus the existing ` -- <warn>`). Rewrite the
comment above it (`:1163-1169`): the answer no longer names a module,
because the adapter has not looked. In `tests/adapter.sh:156-159`,
replace the two `import`/`importNote` checks with
`check "does not guess an import" jq -e 'has("import") | not'`.
Check: `bash tests/adapter.sh 2>&1 | grep -E 'FAIL' | grep -iv catalogue`
prints nothing new.

**A2. The import line after a declare, and tab switches clear** —
`PkgModel.qml`.
- New `property var pendingDeclare: null`.
- `declareAs` (`:742-752`): before `invalidateInspection()`, save
  `pendingDeclare = {name: String(name), ref: namingRef, offers:
  inspected, nonFlake: namingNonFlake}` (the `namingNonFlake` field
  arrives in C3; until then `false`). On a refused `write`, do not set it.
- `_absorb` (`:364-408`), in the `data.apps === undefined` branch, before
  showing `message`: if `pendingDeclare` and `data.ok === true` and
  `data.name === pendingDeclare.name` and `data.url === pendingDeclare.ref`:
  - if `offers` is not null and `offers.ok !== false`: set `inspected =
    Object.assign({}, offers, {declaredAs: data.name})`, `cursor = 0`;
    and when `offers.nixosModules` is non-empty, `message = "declared " +
    name + ". To use it, add inputs." + name + ".nixosModules." +
    attrName(m) + " to the imports of the host that should have it -- this tool does not
    know which file that is"` with `m` = `"default"` when listed, else
    the first;
  - `attrName(s)` is added here (B3 reuses it): `s` when it matches
    `^[A-Za-z_][A-Za-z0-9_'-]*$`, else `"` + `s` with `\` → `\\`,
    `"` → `\"`, `${` → `\${` + `"`.
  - if `nonFlake`: `message = "declared " + name + " as a non-flake
    source -- use it as inputs." + name + " (a path)"`;
  - then `pendingDeclare = null`. Only a **write** answer
    (`isWrite === true`) that does not match clears it, never a read:
    `_reader`, `_searcher` and `_writer` all call `_absorb`
    (`:328-350`), and a state read finishing mid-declare must not drop
    the saved inspection. `setTab`, `clearInspection` and `cancelNaming`
    also clear it; an answer that arrives after that shows `data.message`
    only.
- `setTab` (`:311-321`): after the `if (naming) …` line, set `query =
  ""`, `results = []`, `pendingDeclare = null`; delete
  `if (indexTab && searching) runSearch()`.
- `Menu.qml` `onTabChanged` (`:368-371`): first line `search.text = ""`.
Traps: `setQuery` also runs from `onTextChanged`; setting `search.text`
re-enters it with `""`, which must not re-arm anything (it calls
`disarm()`; fine). The answer match is on name *and* url, so a declare
from a terminal while the panel waits is not mistaken for this one.
Check: QML cases in A7.

**A3. Removal asks first** — `PkgModel.qml` and `Menu.qml`.
- New `property string armedFlake: ""`. `disarm()` (`:264-270`) gains
  `if (armedFlake !== "") { armedFlake = ""; message = "" }`.
- New function, after `addFromOtherChannel`:

```js
function armFlake(kind) {            // "remove" | "update"
  var row = rowAt(cursor)
  if (!flakeTab || !row || row.kind !== "declared") return false
  var key = kind + ":" + row.name
  if (armedFlake === key) {
    armedFlake = ""; message = ""
    return write(kind === "remove" ? ["flake", "remove", row.name]
                                   : ["flake", "update", row.name])
  }
  disarm()
  if (kind === "update" && (row.follows || row.locked === false)) {
    message = row.name + (row.follows ? " follows " + row.follows + "; update that one"
                                      : " is not locked yet; the next apply locks it")
    return false
  }
  if (kind === "remove" && row.mine === false) {
    message = row.name + " was not declared by this tool -- edit flake.nix to remove it"
    return false
  }
  armedFlake = key
  message = kind === "remove"
    ? "remove " + row.name + " from flake.nix? SPACE again removes it, any other key cancels"
    : "update " + row.name + "? It changes what the next apply builds"
      + ((row.name === "nixpkgs" || row.name === "nixarchy") ? " -- the whole system" : "")
      + ". u again updates it, any other key cancels"
  return true
}
```

  (`row.mine === false`, not `!row.mine`: until B1, rows carry no `mine`
  and every listed row is this tool's.)
- `activate` (`:573-624`), `case 5`: a `declared` row no longer writes
  `flake remove`. In slice A it sets `message = "SPACE twice removes "
  + row.name` (B2 replaces this with inspect).
- `Menu.qml`: `case Qt.Key_Space` (`:292-296`): when `pkg.flakeTab &&
  !search.activeFocus`, call `if (!event.isAutoRepeat)
  pkg.armFlake("remove")`, accept, return; otherwise as today. In the
  "any other key cancels" path near `:223-231`, also call `pkg.disarm()`
  when `pkg.armedFlake !== ""` and the key is not SPACE, `U`, or a bare
  modifier.
Check: A7.

**A4. Unknown channel refuses** — `PkgModel.qml` `addFromOtherChannel`
(`:626-655`). When `other === ""`: do not arm; `message = row.name + " --
cannot tell which channel this machine follows from " + (state.flakeDir
|| "the flake") + "/flake.nix, so there is no \"other\" channel to add
from -- RETURN adds it from this one"`; return. Delete the `other === ""`
branch of the second-press `write` (always `["pkg", "add", "--" + other,
row.name]`). Check: A7.

**A5. The flat channel form** — `bin/nixarchy-pkg` `machine_channel`
(`:1359-1370`) and its comment (`:1343-1358`).

```bash
u=$(sed -nE '/^[[:space:]]*nixpkgs\.url[[:space:]]*=[[:space:]]*"([^"]+)".*/{s//\1/p;q}' "$flakedir/flake.nix")
[ -n "$u" ] || u=$(sed -nE '/^[[:space:]]*inputs\.nixpkgs\.url[[:space:]]*=[[:space:]]*"([^"]+)".*/{s//\1/p;q}' "$flakedir/flake.nix")
```

The first line is the writer's regex (`nixarchy-pkg-add`, its
`sed -nE "s/^[[:space:]]*nixpkgs\.url…/p" | head -1`), without the pipe.
Comment: the fallback runs only where the writer's parse found nothing,
which is exactly where the writer says `custom`, warns and proceeds; so
the panel can never offer a channel the writer refuses. Name companion
issue 1. Traps: `| head -1` is replaced, not kept (SIGPIPE under
pipefail). Check: B5's A5 cases (added in A7's adapter part, below).

**A6. The directory is named** — `bin/nixarchy-pkg` `cmd_state`
(`:1911-1976`): `--arg flakeDir "${NIXARCHY_FLAKE:-/etc/nixos}"` and
`--argjson flakeFound "$([ -r "${NIXARCHY_FLAKE:-/etc/nixos}/flake.nix" ] && echo true || echo false)"`,
emitted as `flakeDir`, `flakeFound` beside `channel`.
`PkgModel.qml` `flakeRows` (`:139-180`), the declared-list branch: first
row `{kind: "head", label: "flake: " + state.flakeDir}`; when
`state.flakeFound === false`, then `{kind: "note", label: "no flake.nix
here. The panel and nixarchy-apply both use NIXARCHY_FLAKE
(programs.nixarchy.flake sets it); it must be set in the session the
shell runs in, not only in a terminal."}`. `Card.qml:254-269` draws its empty-state text only when
`list.count === 0`, which the head row now prevents; so when the flake
is found and has no inputs, `flakeRows` adds a note row `no flake inputs
declared here yet` itself. Traps: `rowAt`/`cursor` now start on a head row; `activate`
and `armFlake` already ignore non-`declared` rows.
Check: A7.

**A7. Tests for slice A.**
`tests/adapter.sh`, beside the flake block (`:137-231`):
- A5: a `fresh_flake` variant whose `flake.nix` has only
  `inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";` →
  `state` answers `channel: "unstable"`; a flake with a flat
  `nixos-25.05` line and a later block-shaped `nixpkgs.url =
  "…nixos-unstable"` line → `unstable` (the writer's line wins).
- A6: `state` with `NIXARCHY_FLAKE="$FK"` → `flakeDir == $FK`,
  `flakeFound == true`; with a missing dir → `false`.
`tests/qml/tst_pkgmodel.qml` (add `pendingDeclare`, `armedFlake`,
`inspected = null` to `cleanup()`):
- `setTab` with `query = "x"` leaves `query == ""` and `results == []`.
- declare round trip: set `inspected` to `{ok: true, ref: "path:/r",
  nixosModules: ["default"]}`, `beginNaming()`, `declareAs("r")`,
  `m._writer.deliver('{"ok":true,"name":"r","url":"path:/r","message":"x"}')`
  → `inspected.declaredAs == "r"` and `message` contains
  `inputs.r.nixosModules.default`.
- the same with `setTab(5)` before `deliver` → `inspected == null`,
  `message == "x"`.
- `armFlake("remove")` on a `declared` row arms; a second call writes
  `["flake","remove",…]` (`m._writer.command`); a call after moving to
  another declared row re-arms instead; `disarm()` clears it.
- `addFromOtherChannel` with `state.channel` `"custom"` on tab 2 with a
  search row: two calls, `_writer.running` stays false.
Check: `nix flake check` (runs both QML files, `flake.nix:95-113`).

**A8. Docs for slice A** — `docs/manual/flakes.md` "The part it will
not do for you" (`:92-115`): the import line is shown after a declare
when the inspection listed a module; the CLI points at `flake show`.
"Declaring it" and the removal text: SPACE twice removes; RETURN on a
declared input says so (until PR B). The directory row and the
`NIXARCHY_FLAKE` note. `bin/nixarchy-pkg-keys` Flakes block (`:33-43`):
"On a declared input, remove it" → `SPACE twice on a declared input
removes it`. Docs only; no code.
Fallback: coder, if agy fails or times out.

**PR A check (lead):** `nix flake check`; `bash tests/adapter.sh` (11
pre-existing catalogue failures remain until #68; no other FAIL);
manual 1-2 on razer.

---

### PR B: every input, and what each offers (reads, plus B4)

**B1. `flake list` reads the lock** — `bin/nixarchy-pkg`
`cmd_flake_list` (`:1267-1273`), rewritten.

Answer (`dir` and `stale` are new top-level keys; `state.flakes` at
`:1956` keeps passing `.inputs` through; beside it add
`flakesStale: (($flakes | fromjson).stale // false)` -- `$flakes` is the
`--rawfile`, the jq input there is null):

```json
{"ok": true, "dir": "/etc/nixos", "stale": false,
 "inputs": [{"name": "nixpkgs", "url": "github:NixOS/nixpkgs/nixos-unstable",
             "mine": false, "flake": true, "follows": null, "locked": true,
             "inspectable": true, "lastModified": 1794815771}]}
```

- Marked lines: one `awk` over `flake.nix` printing `name\turl` for
  `inputs.<n>.url = "<u>";  #@flake-input <n>` lines (today's regex,
  `:1270`, without the `grep | sed` pipe) and `name\t` for any other
  `#@flake-input <n>` line. An input has several marked lines after C1
  (URL, follows, `flake = false`), so jq groups by name and keeps the
  non-empty URL; a later `name\t` never overwrites it.
- Lock: `jq` with `--rawfile marks <(that awk)` over `flake.lock` when
  readable, else `{}`:
  - names = `(.nodes[.root].inputs // {} | keys)` ∪ marked names,
    sorted (a lock with no root inputs, or `{}` for a missing lock, has
    no `.inputs`, and `null | keys` errors);
  - `entry = .nodes[.root].inputs[name]`; every `.nodes[…]` lookup is
    guarded by `(entry | type) == "string"`: an unlocked mark has no
    entry and a follows entry is an array, and indexing `.nodes` with
    either errors;
  - `follows`: root entry is an array → `join("/")`; no lock node;
  - `locked`: name in root inputs;
  - `mine`: name in marks; `url`: the mark's URL when mine, else rendered
    from `.nodes[node].original`: `github|gitlab|sourcehut` →
    `<type>:<owner>/<repo>[/<ref>]`; `git` → `git+<url>`;
    `tarball`/`file` → `.url`; `indirect` → `.id`; `path` → `path:` +
    (absolute, or joined to `dir` when relative). `indirect` with a
    `ref` → `<id>/<ref>`. Forge types keep a non-default `host` as
    `?host=`. Query parameters (`rev`, `ref` for `git`, `dir`, `host`)
    are joined with `?` or `&` depending on whether the URL already has a
    `?`; a forge `ref` containing `/`, or a `ref` together with `rev`,
    goes as `?ref=` rather than a path segment. Other types: `url: null,
    inspectable: false`. The B5 hand-written lock covers each branch.
  - `flake`: `.nodes[node].flake != false`.
- `stale`: `true` when `flake.lock` is missing or `[ flake.lock -ot
  flake.nix ]`.
Traps: a missing `flake.nix` still answers `{ok: true, dir, stale: false,
inputs: []}`; `jq` failure → `die`, not an empty list. `<(…)` swallows the
awk status, as `cmd_state` notes at `:1915-1919`: check `[ -r "$file" ]`
first.
Check: B5.

**B2. Inspect a declared input again** — `PkgModel.qml`.
- `flakeRows` declared branch: map each input to `{kind: "declared",
  label: f.name, name: f.name, url: f.url, mine: f.mine, follows:
  f.follows, locked: f.locked, flake: f.flake, inspectable:
  f.inspectable}`; when `state.flakesStale`, a note row `flake.lock is
  older than flake.nix, so this list may be out of date -- the next apply
  locks it`. `Card.qml` draws a `declared` row with `mine === false`
  dimmed (`dim` colour, as `note` rows, `Card.qml:29`) and `(not written by this
  tool)` as its second column.
- New `inspectRow(row)`: `flake: false` → message `not a flake: nothing
  to inspect`; `follows` → `follows <path>: inspect that one`;
  `inspectable === false` → `cannot inspect this kind of input from
  here`; `_inspector.running` → `still reading the last flake -- try
  again in a moment` (a real `Process` ignores `running = true` while it
  runs, and `invalidateInspection()` (`:672-676`) does not stop it, so a
  second start would label the first answer with the new name). `inspect()`
  gets the same guard. Else the body of `inspect()` (`:657-665`) with `row.url` in place
  of `query`, and the answer stored with `declaredAs: row.name` (set it in
  `_inspector`'s handler from a `_inspectAs` property captured at start).
- `activate` `case 5`: `declared` → `inspectRow(row)` (replaces A3's
  placeholder).
- `flakeRows` inspected branch: when `inspected.declaredAs`, the head row
  is `inputs.<declaredAs> = <ref>` and the `declare` row is omitted.
- `setQuery` (`:538-546`) invalidates an inspection whose `ref` differs
  from the field: guard it with `&& !inspected.declaredAs`, or typing
  into the empty field would drop it.
Check: B5.

**B3. Packages for this system, overlays by name** — `bin/nixarchy-pkg`
`cmd_flake_show` (`:1030-1068`), the success `jq`:

```jq
packages:   (($f.packages // {}) | if has("type") then [] else (.[$sys] // {} | keys) end),
overlays:   (($f.overlays // {}) | if has("type") then [] else keys end),
otherCount: (($f.packages // {}) | if has("type") then 0 else
              (to_entries | map(select(.key != $sys) | .value | length) | add // 0) end),
```

with `--arg sys "$(uname -m)-linux"` and a comment
`# shortcut: Linux only (uname -m)-linux; a Darwin host needs builtins.currentSystem`.
`PkgModel.qml` `flakeRows` inspected branch: replace the package-count
note (`:158-159`) with one `package` row per name, one `overlay` row per
name, and when `packages` is empty and `otherCount > 0` a note
`<otherCount> packages for other systems, none for this one`.
`activate` `case 5`: `module`, `package`, `overlay` rows set `message` to
the line and where it goes, with `N = inspected.declaredAs ||
suggestInputName(inspected.ref)`:

| Row | Line | Goes in |
| --- | --- | --- |
| `module` | `inputs.N.nixosModules.<m>` | the host's `imports` |
| `package` | `inputs.N.packages.${pkgs.stdenv.hostPlatform.system}.<p>` | `environment.systemPackages` |
| `overlay` | `inputs.N.overlays.<o>` | `nixpkgs.overlays` |

followed by ` -- this tool does not know which file that is`. An output
name not matching `^[A-Za-z_][A-Za-z0-9_'-]*$` is quoted: `"` + name with
`\` → `\\`, `"` → `\"`, `${` → `\${` + `"`, via `attrName(s)` from A2.
Check: B5.

**B4. `remove` prunes the lock** — `bin/nixarchy-pkg` `cmd_flake_remove`
(`:1180-1264`). After `cp "$tmp" "$file"` (`:1254`) and before the final
`metadata` (`:1255`):

```bash
if ! timeout 120 "${NIX[@]}" flake lock "$dir" >/dev/null 2>"$err" 9>&- 8>&-; then
  die "could not lock the flake without '$name', so nothing was changed: $(nix_why "$err")"
fi
```

Replace the comment at `:1260-1262` with: `nix flake lock` prunes the
removed input and its own dependencies (measured on Nix 2.35.6), and the
list reads the lock, so leaving the entry would keep the input on screen
and make re-adding it fail `flake_names own`. Switch this function's other
`nix` calls to `"${NIX[@]}"`. Traps: inside the existing transaction; a
failure rolls back both files.
Check: B5.

**B5. Tests for slice B.** `tests/adapter.sh`:
- B1: a `fresh_flake` with a hand-written block input (`tool = { url =
  "path:…"; };`) and `nix flake lock` run once → `flake list` has it with
  `mine: false`, `url` that `flake show` accepts; a root
  `inputs.x.follows = "nixpkgs";` → `follows == "nixpkgs"`; a marked
  line not in the lock → `locked: false`; `touch -d '1 hour ago'
  flake.lock` → `stale: true`; a hand-written lock with a `github`
  node (`owner`, `repo`, `ref`) and a relative `path` node → the rendered
  refs equal `github:o/r/ref` and `path:<dir>/sub` (no Nix call).
- B3: a fixture flake whose `outputs` has `packages.x86_64-linux.hello`,
  `packages.aarch64-darwin.maconly`, `overlays.default`,
  `nixosModules.default` → `packages == ["hello"]` (on x86_64),
  `overlays == ["default"]`, `otherCount == 1`.
- B4: add, `remove`, `flake list` no longer lists it, `add` of the same
  name succeeds; `flake.lock` has no node for it.
- Replace the existing `check "lists nothing afterwards"` at
  `tests/adapter.sh:192` (`.inputs | length == 0`): `fresh_flake`
  declares `nixpkgs` (`:139`), which the list now shows. Assert
  `(.inputs | map(.name) | index("lib")) == null` and that `nixpkgs` is
  listed with `mine: false`.
`tests/qml/tst_pkgmodel.qml`:
- RETURN path: on tab 5 with `state.flakes = [{name: "t", url: "path:/t",
  mine: true, locked: true, inspectable: true, flake: true}]`,
  `activate()` on that row sets `_inspector.command` to `[script, "flake",
  "show", "path:/t"]`; delivering `{ok: true, ref: "path:/t",
  nixosModules: []}` gives `inspected.declaredAs == "t"`.
- a `follows` row: `armFlake("update")` refuses with the follows message.
- inspect A, `clearInspection()`, then `activate()` on declared row B
  while `_inspector.running` is still true: refused with the message, and
  `_inspector.command` still names A.
- a state answer (`m._reader.deliver(…apps…)`) between `declareAs("r")`
  and the writer's answer leaves `pendingDeclare` set; the declare then
  restores the inspection.
- a module named `foo.bar`: the post-declare message contains
  `nixosModules."foo.bar"`.
- a `mine: false` row: `armFlake("remove")` refuses; `armFlake("update")`
  arms.
- `attrName("foo.bar")` is `"\"foo.bar\""`; `attrName("hello")` is
  `hello`.
Check: `nix flake check`; `bash tests/adapter.sh`.

**B6. Docs for slice B** — `docs/manual/flakes.md`: the list shows every
locked input, marked when this tool wrote it; the stale note; RETURN on
a declared input inspects it; packages for this system and overlays,
shown never written; remove now updates the lock. `bin/nixarchy-pkg-keys`
Flakes block: `RETURN on a declared input -> inspect it again`.
Fallback: coder.

**PR B check (lead):** as PR A, plus manual 3.

---

### PR C: the new writes

**C1. `flake add [--no-follows] [--no-flake] <name> <ref>`** —
`bin/nixarchy-pkg` `cmd_flake_add` (`:1095-1175`).
- Flags parsed before the usage check; `--no-flake` sets `nofollows=1`.
  Any other `-*` argument, or more than two positionals
  (`flake add n ref --no-flake`), dies with the usage line: a flag after
  the ref must not be silently ignored.
- First candidate: the URL line, and when `--no-flake` a second line
  `  inputs.${name}.flake = false;  #@flake-input ${name}` (correction 4),
  both inserted at the anchor through `ENVIRON` as today. Parse, `cp`,
  lock, as today.
- Follows (unless `nofollows`): after the first lock,
  `jq -e --arg n "$name" '(.nodes[.root].inputs.nixpkgs | type) ==
  "string" and ((.nodes[.root].inputs[$n]) as $k | ($k | type) ==
  "string" and ((.nodes[$k].inputs.nixpkgs // null) | type) ==
  "string")' "$lock" >/dev/null` decides eligibility. If eligible: insert
  `  inputs.${name}.inputs.nixpkgs.follows = "nixpkgs";  #@flake-input
  ${name}` at `NR == at + 1` (right after the URL line the first pass
  wrote; never a regex containing `$ref`), through `ENVIRON`, into a
  fresh `$tmp`; parse, `cp`, lock again; then the existing final
  `metadata`.
- Answer adds `follows: true|false`; message gains ` -- follows this
  flake's nixpkgs` when true.
- Nix calls in this function switch to `"${NIX[@]}"`, and every Nix and
  `nix-instantiate` call in `add` and `remove` gets `9>&- 8>&-` (today
  only `9>&-`; fd 8 is the check lock, `:1694`).
- `cmd_flake_show`'s failure answer gains `notFlake: true` when
  `nix_why "$err"` matches `[Pp]ath '[^']*flake\.nix' does not exist`
  (correction 1); any other failure stays plain.
Traps: the `jq -e` runs under errexit inside `if`; a missing lock (first
lock failed) never reaches it because that already `die`d. `remove`
deletes every marked line (`:1249`) and its reference check ignores
marked lines (`:1220`), so follows and `flake = false` lines need no
change there; `flake list`'s URL regex matches only `.url` lines.
Check: C4.

**C2. `flake update <name>`** — new `cmd_flake_update` after
`cmd_flake_remove`; `cmd_flake` (`:1979-1987`) gains `update)
cmd_flake_update "$@" ;;` and its error text lists `update`.

```
usage (exactly one positional), valid_input_name, need nix
begin_write                                    # before ANY read of the lock
dir/file/lock
[ -r "$lock" ] || die "no flake.lock in $dir -- nothing is locked yet. Nothing was changed."
[ -w "$lock" ] && [ -w "$dir" ] || die "cannot write $lock. Nothing was changed."
key=$(jq -r --arg n "$name" '.nodes[.root].inputs[$n] // empty | if type == "array" then "follows:" + join("/") else . end' "$lock") \
  || die "cannot read $lock. Nothing was changed."
  empty     → die "'$name' is not an input of this flake's lock. Nothing was changed."
  follows:… → die "$name follows <path>; update that one. Nothing was changed."
guard "$file" "$lock"
snap=$(mktemp); cp "$lock" "$snap"            # BEFORE the baseline, which can lock
baseline metadata (as add)
(cd "$dir" && timeout 120 "${NIX[@]}" flake update "$name") >/dev/null 2>"$err" 9>&- 8>&- || die "could not update $name, so nothing was changed: $(nix_why "$err")"
final metadata (as add)
ans=$(jq … as below) || die "could not read the updated lock. Nothing was changed."
committed
printf '%s\n' "$ans"
```

Answer: `jq -n --slurpfile a "$snap" --slurpfile b "$lock"` computing
`moved` (node keys whose `locked.narHash` differs or that are new),
`removed` (keys gone), `changed: (moved|length) > 0`, `lockChanged:`
`if cmp -s "$snap" "$lock"; then lc=false; else lc=true; fi` (an `if`,
so cmp's "different" exit 1 survives errexit), `from`/`to` = the named
node's `locked.lastModified // null`. The answer is built **before**
`committed`, so a jq failure still rolls back. The named input's node
is `.nodes[.root].inputs[$name]` read separately in `$snap` and in
`$lock` (node keys can be suffixed, `nixpkgs_2`, and can change on
update); `moved`/`removed` compare by node key, and "only dependencies
moved" means the named input's own key is not in `moved`. Dates go through
`if . == null then "an unknown date" else todate[:10] end`
(`jq 'null | todate'` fails: `strftime/1 requires parsed datetime
inputs`; `lastModified` is optional for some source types).
Message: changed → `updated <name>: <from date> -> <to date>. Nothing is
built until you apply.`, and when only
dependencies moved, `updated <name>'s dependencies (<moved>)…`; not
changed but `lockChanged` → correction 2's text; neither → `<name> is
already up to date`.
Traps: one answer; `cd` in a subshell only; `$snap` lives in `$WORK`.
Check: C4.

**C3. Panel wiring** — `PkgModel.qml`, `Menu.qml`, `Card.qml`.
- `beginNaming` (`:732-740`): accept `inspected.ok === false &&
  inspected.notFlake === true`, setting `namingNonFlake = true`; every
  other `ok: false` still returns null. New `property bool
  namingNonFlake: false`, reset by `cancelNaming`, `setTab`, and at the
  start of `beginNaming`. `flakeRows`: a `notFlake` inspection gets the
  row `{kind: "declare", label: "declare this as a non-flake source"}`.
- `declareAs(name, noFollows)`: args `["flake", "add"]` + (`namingNonFlake`
  ? `["--no-flake"]` : `noFollows ? ["--no-follows"] : []`) + `[name,
  namingRef]`. The naming note row says `RETURN declares (following this
  flake's nixpkgs), SHIFT+RETURN without, ESC goes back`, or for a
  non-flake `RETURN declares it as a non-flake source`.
- `Menu.qml` naming block (`:233-243`): RETURN with `ShiftModifier` →
  `pkg.declareAs(search.text, true)`.
- `Menu.qml` single-letter block (`:337-360`): `case Qt.Key_U: if
  (!pkg.flakeTab) break; if (!event.isAutoRepeat) pkg.armFlake("update");
  event.accepted = true; return`. The cancel path from A3 already spares
  `U`.
- A2's `_absorb` branch already handles `nonFlake`.
Check: C4 QML part.

**C4. Tests for slice C.** `tests/adapter.sh` (fixtures are local
`path:` flakes under `$FLAKE_TMP`; a fixture `np` flake stands in for
nixpkgs so nothing is fetched):
- follows written: user flake with `inputs.nixpkgs.url = "path:$np"`,
  added `lib2` flake with its own `nixpkgs` input → a follows line with the
  marker; `jq '.nodes[.nodes.root.inputs.lib2].inputs.nixpkgs'` is
  `["nixpkgs"]`; answer `follows: true`.
- not written: an added flake with no `nixpkgs` input → no follows line;
  `nix flake metadata` stderr has no `non-existent input`; a root whose
  `nixpkgs` is a follows array, and an added flake whose `nixpkgs`
  already follows something → no follows line.
- `--no-follows` → none; `--no-flake` on a directory with no `flake.nix`
  → locks, the node has `"flake": false`; `remove` then deletes both lines.
- `flake show` on a dir with no `flake.nix` → `notFlake: true`; on an
  unresolvable path → no `notFlake`.
- failures, both files byte-identical (md5 pattern, `:175-179`), driven
  by a `nix` wrapper first on `PATH` (the adapter's `NIX` array calls
  `nix` by name): it counts calls in a file under `$FLAKE_TMP` and exits 1
  on the Nth `flake lock` or `flake metadata`, else `exec`s the real
  `nix`. Cases: the second `flake lock` (follows pass) fails; the final
  `metadata` fails; `flake update` fails; each also on a flake with no
  `flake.lock` before the call (absent again after). A `chmod 000` on a
  fixture is not used: the second lock replaces that input with a
  follows and may never read it, and fetched sources are cached.
- update: change the fixture source → `changed: true`, `moved` contains
  the name; again → `changed: false, lockChanged: false`; change only the
  fixture's own nixpkgs → `changed: true`, `moved` names the dependency
  node; a `git+file:` fixture with an empty commit → `changed: false,
  lockChanged: true`; a name not in the lock and a follows-only root input
  → refused, both files unchanged.
`tests/qml/tst_pkgmodel.qml`:
- `notFlake` inspection: `beginNaming()` returns the suggestion,
  `declareAs("x")` sends `--no-flake`; an ordinary `ok: false` inspection
  returns null.
- `declareAs("x", true)` sends `--no-follows`.
- `armFlake("update")` twice on a locked row writes `["flake","update",
  "t"]`.
Check: `nix flake check`; `bash tests/adapter.sh`.

**C5. Docs for slice C** — `docs/manual/flakes.md`: follows and its
opt-out, non-flake sources, `u` twice updates, the nixpkgs warning.
`docs/manual/from-a-terminal.md`: the `flake add` flags, `flake update`,
the `flake list` fields and that `flake add` no longer answers `import`.
`bin/nixarchy-pkg-keys` Flakes block: `SPACE twice`, `u twice`,
`SHIFT + RETURN while naming`. Fallback: coder.

**PR C check (lead):** as PR A, plus manual 4-6.

## Tests

Run from the worktree, as the lead:

| Command | Expected |
| --- | --- |
| `nix flake check --print-build-logs` | passes: shellcheck of `bin/nixarchy-pkg`, `bin/nixarchy-pkg-keys`, `tests/adapter.sh`; `qmltestrunner` on `tst_card.qml` and `tst_pkgmodel.qml` |
| `bash tests/adapter.sh` | every flake case passes; the summary shows the 11 pre-existing catalogue failures that only #68 fixes, and no other `FAIL` |
| `nix build .#default` | builds (CI does the same) |

Manual, on razer, by the lead, with `NIXARCHY_FLAKE` pointing at a
scratch copy of razer's flake (never `/etc/nixos`, no switch without the
owner):

1. (A) Options tab, type a query, switch to Flakes: the field is empty
   and nothing is fetched. The head row names the scratch directory.
2. (A) Declare a local flake with a module: the message names
   `inputs.<name>.nixosModules.default`; SPACE once arms, SPACE again
   removes; any other key cancels.
3. (B) The list shows razer's real inputs (`nixpkgs`, `nixarchy`, …)
   dimmed as not written by this tool; RETURN on `home-manager` (if
   present) inspects it under its declared name; SPACE on it refuses.
4. (C) `flake show github:<a real repo with no flake.nix>` answers
   `notFlake: true` (confirms correction 1 for `github:`).
5. (C) Declare `github:nix-community/home-manager`: `flake.nix` has the
   URL and follows lines; `flake.lock` has `"nixpkgs": ["nixpkgs"]` for
   it; `u` twice reports changed or up to date.
6. (C) Session check: is `NIXARCHY_FLAKE` in the shell's environment
   (`cat /proc/$(pgrep -f omarchy-shell | head -1)/environ | tr '\0' '\n'
   | grep NIXARCHY_FLAKE`)? If not, file companion issue 2.

## Rollback

Each slice is one PR; revert it. PR A and B change no file format. PR C
adds marked lines; a reverted adapter still removes them, because
`remove` deletes every `#@flake-input <name>` line. A user's flake is
never left half-written: every write is inside #59's transaction.

## Companion issues

Filed by the lead in nixarchy.

**1. `nixarchy-pkg-add` reads only the block form of `nixpkgs.url`**

> Its channel parse (`sed -nE 's/^[[:space:]]*nixpkgs\.url…'`, beside the
> comment that already names this gap) misses the flat
> `inputs.nixpkgs.url = "…";`. A machine whose flake uses that form is
> reported as `custom`, and every `--stable` / `--unstable` prints
> "cannot tell which channel this machine follows". Read the block form
> first and the flat form only when it finds none, exactly as
> nixarchy-pkg's `machine_channel` does after nixarchy-pkg #63.
> Reading either form, first match wins, is not equivalent: a flat line
> followed by a block-shaped line would make the two disagree. While
> there, replace `| head -1` with `sed -n '/re/{s//\1/p;q}'`.

**2. Export `NIXARCHY_FLAKE` into the graphical session** (file only if
manual check 6 shows it missing)

> `programs.nixarchy.flake` is read by `nixarchy-apply` through
> `NIXARCHY_FLAKE`. If the variable is set only for login shells, the
> Omarchy shell (and the nixarchy-pkg panel inside it) falls back to
> `/etc/nixos` while `nixarchy-apply` run from a terminal uses the
> configured flake, so the panel can declare inputs into one flake while
> apply builds another. Export it into the graphical session
> (systemd user environment) so every caller agrees.

(Workflow run 2026-11-16: the steps of this PR were implemented in one parallel workflow pass and committed together as one commit, because agent-run codex will not start on a worktree with uncommitted changes and the implementing agents may not commit. The PR names which steps Codex wrote and which the coordinating agent wrote; each agent verified every step with the adapter suite, shellcheck, the QML suites and nix flake check, and the lead re-ran the adapter suite and nix flake check before committing.)

(Review fixes, round 2: setTab clears query/results only when the tab changes, matching Menu's onTabChanged; inspect() drops pendingDeclare, and a declared inspection shows inputs.<name>.nixosModules rows without the "declare" row; any key but SPACE cancels an armed removal (PkgModel.keyCancelsFlakeArm); a busy second press in armFlake says so; SPACE on non-declared Flakes rows goes back to activate(); the Flakes empty-state hint shows when only the head row exists, so the "no flake inputs declared here yet" note row was dropped. Tests added in tst_pkgmodel.qml and tst_card.qml.)

(Review fixes, PR B: assign declared inspection data before notifying QML bindings; give remove-time lock a kill deadline and cover all six write-time calls; derive stale from marked inputs missing in the lock root; clear declared inspection when a new ref is typed; distinguish package and overlay labels while keeping bare names for activation; quote input names in suggested lines; run hand-written lock tests offline. Updated model, adapter, manual and tests.)
