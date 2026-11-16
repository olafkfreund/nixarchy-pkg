---
status: draft
issue: 64
spec: spec/2026-11-16-64-review-ui-docs.md
coders:
  1: coder   # three one-line command swaps plus a sentence after each -- small, exact
  2: agy     # five manual passages rewritten from given texts -- bounded docs; fallback: coder
  3: coder   # Card description fallback, catalogueRows, ListView sections, their QML tests
  4: codex   # multi-word search in the adapter awk (best-of-words rank) and in filtered() -- small tricky logic
  5: codex   # reindex on its own Process, answered flag, _absorb take-up -- small tricky QML state
  6: coder   # offline guards in tests/adapter.sh and the adapter flake check -- mechanical, measured
reviewers:
  - codex   # awk, QML Process state, bash guards
  - agy     # independent read of each PR's diff against this plan
---

# Plan: the panel and its manual say what is true, and the ways to open it never fail silently

Branch `fix/64-review-ui-docs`, **three PRs** in this order, each from its
own branch cut from the previous one's merge (or stacked):

| PR | Steps | Its own check |
| --- | --- | --- |
| 1: key binding, menu row, manual | 1, 2 | `rg` checks in step 1-2; `nix flake check` |
| 2: the panel | 3, 4, 5 | `nix flake check` (qml-tests, qml-syntax); `bash tests/adapter.sh`; razer by eye |
| 3: `nix flake check` runs the adapter suite | 6 | `nix flake check` shows the new `adapter` check passing |

Self-contained: a coder reads this file and the files each step names.
**Coders never stage or commit.** The coordinator commits each step as
`fix: … (#64)`, `feat(panel): … (#64)`, `test: … (#64)` or `docs: … (#64)`.

Line numbers are on `main` at `322d021` (#60 merged). Anchors quote the
line; numbers drift.

After every step, run:
- `bash -n bin/nixarchy-pkg`
- `shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh`
- `bash tests/adapter.sh`

The suite has **11 pre-existing failures** on a nixarchy machine with sshd
on, fixed only by #68: "toggling on reports enabled", "the file really
changed", "toggling off reports disabled", "services use their own file", "a
toggle counts once", "a package counts once", "one file, one change", "and
it names that file", "two files, two changes", "and both files are named",
"and it recovers once readable". Pass means no failure outside that list.
QML steps also run `nix flake check`.

## Decisions (from the approved spec)

- **Scope.** Items 1, 2, 4, 5, 6 of #64 and the `nix flake check` half of
  item 7. Selection-row metadata is #71; Menu/OptionForm/Panel tests are
  #72. Neither is touched here.
- **Opening the panel.** The key binding and the menu row run
  `nixarchy-plugin nixarchy.pkg`, which toggles the panel when the plugin
  is enabled and otherwise sends a notification ("nixarchy.pkg is turned
  off — Turn it on in Setup > Plugins, or run: omarchy plugin enable
  nixarchy.pkg", or "… is not installed on this machine"). **No `when`
  check** on the menu row: with one, a disabled plugin hides the row, which
  is silent again.
- **Descriptions.** A row shows `summary || note || type || ""`. Never the
  raw Nix `line`, never the `category` (the header shows it). On p620, 39 of
  65 apps then show no description.
- **Category headers** via `ListView` sections (measured: they work on the
  panel's JS-array model in Qt 6.12 and take no model index). Rows grouped
  by category in first-seen order, file order within a group.
- **`.settings` rows** go last, under the header
  `settings — edit in apps.nix` (Services: `services.nix`). They keep their
  glyph and their RETURN explanation.
- **Multi-word search**: every word must occur (in name or summary for the
  index; in id, label or category for Apps/Services), any order. Rank = the
  best (lowest) existing rank over the words. A one-word query is unchanged.
  Blank queries do nothing. Measured: "server ssh" 0 → 21 rows, "rust
  formatter" 0 → 3.
- **Reindex never blocks a write.** It gets its own `Process` and
  `reindexing` flag; `busy` is for writes only. Its answer sets
  `indexStale` itself (no state read, which would race on `_reader`). A
  death without an answer is reported. Measured: a reindex takes 44.5 s and
  5.0 GB.
- **Manual.** The unfree example becomes "every package taken from the
  other channel" (`state` has no unfree flag for packages). Options: the
  example is in a text box; edited, it is written live; untouched, nothing
  is written. SHIFT+A is advice for *before* an apply on a machine with no
  polkit agent; once an apply runs, SHIFT+A is refused until it ends. No
  cancel-apply feature.
- **Offline test switch**: `NIXARCHY_PKG_TEST_OFFLINE=1`, set only by the
  new flake check.

### Deviations from the spec, measured while planning (need plan approval)

The spec said slice 3 skips the "flake" section (main :123-251) and the
FKW/FKS cases, and that real `nix` is used only for `nix-instantiate
--parse`. Running main's suite inside a throwaway `runCommand` on p620
(2026-11-16, lead's OK) showed more:

1. `nix-instantiate --parse` works in the build sandbox (rc 0 good, rc 1
   bad). Without `NIX_STATE_DIR` it prints `"/nix/var/nix" does not exist,
   so Nix will use … as a chroot store` on stderr; with
   `NIX_STATE_DIR=$TMPDIR/nix-state` it is silent. `git`, `setsid`, `flock`
   are available.
2. **20 stubs written at run time start `#!/usr/bin/env bash`**, and the
   sandbox has no `/usr/bin/env`: ~45 checks failed for that alone. The
   check rewrites that line in its own copy of the suite (`sed`), not the
   source.
3. Any `nix flake` operation on a local `path:` flake fails (no writable
   store), so three ranges skip, not two: main :153-247 (flake add/remove/
   show), :1129-1152 (FKW/FKS), and **:1352-1404** (#59's flake add/remove
   recovery cases, which start with `nix flake lock "$W59/fk"`).
4. With those: **366 checks pass, rc 0, 19 s** in the sandbox.

## Steps

### 0. Coordinator: rebase and re-check

Rebase onto current `main`. `grep -n` every anchor below; fix numbers here
if they moved (not a deviation). If #69 merged first, `_absorb` already
takes `indexStale`/`index` at its top: step 5's `_absorb` change is then
already done; keep the rest of step 5.

---

## PR 1: key binding, menu row, manual

### 1. The command that opens the panel (coder)

Replace `"omarchy-shell shell toggle nixarchy.pkg '{}'"` with
`"nixarchy-plugin nixarchy.pkg"` in:

- `README.md:157` (inside the `o.bind(…)` lua snippet);
- `docs/manual/getting-started.md:60` (same snippet);
- `share/omarchy-menu.jsonc:32`: `"action": "nixarchy-plugin nixarchy.pkg"`.

After each of the two lua snippets (README after :158's closing fence,
getting-started after :61's), add one sentence:

> With the plugin turned off, the key shows a notification saying so and
> how to turn it on, instead of doing nothing.

In `share/omarchy-menu.jsonc`, extend the header comment (:1-18) with one
line: `// The action is nixarchy-plugin, not omarchy-shell: with the plugin
off it says so instead of doing nothing. No "when", for the same reason.`

Check: `rg -n "shell toggle nixarchy.pkg" README.md docs share` → nothing.
`jq` cannot parse jsonc; check it with
`sed 's,//.*,,' share/omarchy-menu.jsonc | jq -e 'type == "object"'`… only if
the file has no `//` inside strings (it has none today; verify with
`rg -n '"[^"]*//' share/omarchy-menu.jsonc`).

Traps: leave `learn.nixarchy-pkg-keybindings` (`…/bin/nixarchy-pkg-keys`)
as it is; it does not need the plugin enabled.

### 2. The manual (agy; fallback: coder)

Exact texts. Keep surrounding paragraphs.

- `docs/manual/from-a-terminal.md:44-48`: replace the heading line
  `Everything unfree in your selection:` and its code block with:

  ````
  Every package taken from the other channel:

  ```bash
  nixarchy-pkg state | jq -r '.packages[] | select(.channel == "other") | .attr'
  ```
  ````

- `docs/manual/options.md:56-58` ("They get the option's own example — or
  its default — written **commented out**, … to edit."): replace with
  "They get the option's own example — or its default — in a text box, with
  its type and documentation beside it. Edit it and RETURN writes it as a
  live value; leave it untouched and nothing is written."

- `docs/manual/troubleshooting.md:51-57` (section `## "\`a\` seems to
  hang"`): keep the heading and the first paragraph ("It is probably
  waiting …"). Replace the "Press `SHIFT+A` instead …" paragraph with:
  "ESC leaves the log; the build keeps running. `SHIFT+A` is refused while
  it runs (the footer says *an apply is running*), so wait for it to end.
  Next time on this machine, use `SHIFT+A` instead of `a` from the start."

- `docs/manual/applying.md:46` ("If `a` seems to hang, try `SHIFT+A`
  before assuming anything is broken."): replace with "On a machine with no
  polkit agent, use `SHIFT+A` instead of `a`. Once an apply is running,
  `SHIFT+A` is refused until it ends."

- `docs/manual/getting-started.md:110-114`: heading becomes
  `## If you have no polkit agent`; body: "Use `SHIFT+A` instead of `a`.
  It runs the same apply in a real terminal, where a password prompt or a
  question can be answered. Once an apply is running, `SHIFT+A` waits its
  turn: it is refused until that apply ends. [Applying changes](applying)
  has the detail."

Check: `rg -n "SHIFT\+A" docs/manual` shows no "if `a` hangs, press
SHIFT+A" advice left; `rg -n "commented\s*$" docs/manual/options.md` and
`rg -n "Everything unfree" docs` find nothing.

Traps: do not touch the sections #60 added (Queue tab, check, pins). No
new claims beyond these texts.

---

## PR 2: the panel

### 3. Descriptions, category headers, settings rows (coder)

**`Card.qml`**
- :243-244, the description `text:` becomes
  `text: modelData.summary || modelData.note || modelData.type || ""`
  (drop `|| modelData.line || modelData.category`).
- `ListView` (:116-131), add:

  ```qml
  // Category headers on Apps and Services. A section takes no model index,
  // so cursor, rowAt and count are unaffected.
  section.property: root.model && root.model.tab < 2 ? "section" : ""
  section.delegate: Text {
    required property string section
    width: ListView.view ? ListView.view.width : 0
    height: Math.round(Style.font.title * 2)
    verticalAlignment: Text.AlignBottom
    leftPadding: Style.space(10)
    text: section
    textFormat: Text.PlainText
    elide: Text.ElideRight
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
    color: root.dim
  }
  ```

**`PkgModel.qml`**
- `rows()` (:120-131): `case 0: return catalogueRows(state.apps || [], "apps.nix")`
  and `case 1: return catalogueRows(state.services || [], "services.nix")`.
- After `filtered()` (:247-255), add:

  ```js
  // Each row gains `section`, the header it is drawn under. Grouped by
  // category in first-seen order, file order within a group: a ListView
  // section is drawn at every change of value, so headers A, B, A would
  // otherwise show A twice. Settings rows go last: they configure an app
  // and cannot be turned on themselves.
  function catalogueRows(list, file) {
    // Object.create(null): a category called "constructor" must not find
    // Object.prototype's.
    var f = filtered(list), order = [], groups = Object.create(null), conf = []
    f.forEach(function (r) {
      if (r.settings === true) {
        conf.push(Object.assign({}, r, { section: "settings \u2014 edit in " + file }))
        return
      }
      var c = r.category || "other"
      if (!groups[c]) { groups[c] = []; order.push(c) }
      groups[c].push(Object.assign({}, r, { section: c }))
    })
    var out = []
    order.forEach(function (c) { out = out.concat(groups[c]) })
    return out.concat(conf)
  }
  ```

**Tests**
- `tests/qml/tst_pkgmodel.qml`, new `test_catalogue_rows_group_and_settings_last`:
  state apps `[{id:"a",category:"A"},{id:"b",category:"B"},{id:"c",category:"A"},{id:"s.settings",category:"A",settings:true}]`
  on tab 0 → `rows().map(r => r.id)` is `["a","c","b","s.settings"]`,
  sections `["A","A","B","settings — edit in apps.nix"]`; `rowAt(3).settings === true`;
  `activate()` with `cursor = 3` sets the "configures …" message and starts
  no write (`busy` stays false). A second case with categories
  `"constructor"` and `"__proto__"` groups them like any other name.
- `tests/qml/tst_card.qml`: give `theRows` a `section` each; new
  `test_sections_on_catalogue_tabs_only`: with `tab: 0` the list's
  `contentItem` has section header items (count `Text` items whose `text`
  equals a section name), with `tab: 2` it has none; switch 0 → 2 → 0 and
  the header is back. The existing geometry test must still pass.

Check: `nix flake check`; on razer, Apps tab shows category headers and
the settings group last; the cursor moves over rows only; RETURN on a row
under a header toggles that row.

Traps:
- `rowAt`/`count`/`activate` all go through `rows()`; never index
  `state.apps` by cursor.
- `Object.assign({}, r, {...})`: the computed `section` wins.
- `—` escapes, not the glyph (the files' own rule).
- If the first header sits above the view when a tab opens (ApplyRange,
  `clip: true`), call `list.positionViewAtBeginning()` on tab change; check
  on razer.

### 4. Multi-word search (codex)

**Adapter** `bin/nixarchy-pkg`, `cmd_search`:
- Before the `[ -n "$query" ]` check (:416), trim:
  `query="${query#"${query%%[![:space:]]*}"}"; query="${query%"${query##*[![:space:]]}"}"`.
  A blank query is then refused by the existing check.
- The awk program (:424-436) becomes:

  ```awk
  BEGIN { n = split(tolower(q), w, " ") }
  want != "" && $1 != want { next }
  {
    name = tolower($2); sum = tolower($3); best = 9
    for (i = 1; i <= n; i++) {
      if      (name == w[i])          r = 0
      else if (index(name, w[i]) == 1) r = 1
      else if (index(name, w[i]))     r = 2
      else if (index(sum, w[i]))      r = 3
      else next
      if (r < best) best = r
    }
    # Shorter names first within a rank: "git" beats "gitAndTools.git-extras"
    print best, length($2), $1, $2, $3, $4, $5
  }
  ```

  (awk's `split(s, a, " ")` drops leading, trailing and repeated blanks.)
  Everything after the awk (`sort`, `head -n "$limit"`, `cut`) unchanged.

**Panel** `PkgModel.qml`:
- :115 `readonly property bool searching: query.length > 0` →
  `readonly property bool searching: query.trim().length > 0`.
- `filtered()` (:247-255) body:

  ```js
  if (!searching) return list
  var words = query.trim().toLowerCase().split(/\s+/)
  return list.filter(function (r) {
    var hay = (String(r.id || "") + " " + String(r.label || "") + " "
               + String(r.category || "")).toLowerCase()
    return words.every(function (w) { return hay.indexOf(w) >= 0 })
  })
  ```

- `runSearch()` sends `query` as typed; the adapter trims.

**Tests**
- `tests/adapter.sh`, in the stub-index search block (main :259-272, whose
  `printf` writes `$STUBCACHE/nixarchy/index.tsv`): add to that `printf`
  the rows
  `pkg\topenssh\tSecure SHell server …` and
  `pkg\tdropbear\tsmall ssh server`, then:
  - `stub_search -- "server ssh"` and `"ssh server"` return the same names
    in the same order, both containing `openssh` and `dropbear`;
  - `stub_search -- "  ssh  "` ranks as `ssh`;
  - `stub_search -- "ssh nothinglikethis"` → `.rows | length == 0`;
  - truncation: a second stub index of 5000 matching rows
    (`for i in $(seq 5000); do printf 'pkg\tssh%s\tssh tool\t\t\n' "$i"; done`)
    with `--limit 1` returns valid JSON with `.ok == true` and one row.
    (`sort` may take SIGPIPE when `head` stops; the pipeline runs inside
    `--rawfile rows <(…)`, whose status bash does not check, so errexit and
    pipefail do not apply. This case pins that.)
  - the existing one-word checks unchanged.
- `tests/qml/tst_pkgmodel.qml`: `filtered` with `"b a"` keeps a row whose
  id has `a` and label has `b`; `"   "` is not searching and filters
  nothing.

Check: `bash tests/adapter.sh`; on p620/razer
`bin/nixarchy-pkg search "server ssh" --kind pkg --limit 200 | jq '.rows|length'`
→ 21 (with p620's index of 2026-11-02; any non-zero on razer), and the same
names in the same order for "ssh server" (both measured with this awk on
p620's index while planning).

Traps:
- `set -euo pipefail`: no new pipe stages; the awk is still one pass.
- The trim must not use `xargs`/`sed` on the query (it may hold quotes);
  parameter expansion only.
- The awk keeps printing the same seven columns; `cut -f3-` depends on it.

### 5. Reindex on its own Process (codex)

`PkgModel.qml`:
- Beside `property bool busy: false` (:77): `property bool reindexing: false`
  and `property bool _reindexAnswered: false`.
- After `_writer` (:346-361), add:

  ```qml
  // A reindex writes only the search cache and takes ~45 s; on the writer
  // it blocked every toggle meanwhile (#64). Its answer carries indexStale,
  // so no state read follows -- a refresh() here would race on _reader,
  // which ignores a start while running (#43).
  property Process _reindexer: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.length > 0) root._reindexAnswered = true
        root._absorb(text, false)
      }
    }
    onExited: function (code, status) {
      root.reindexing = false
      if (code !== 0 && !root._reindexAnswered)
        root.message = "the index rebuild ended without answering (exit " + code + ")"
    }
  }
  ```

- `reindex()` (:768-770):

  ```js
  function reindex() {
    if (reindexing) { message = "already rebuilding the index"; return false }
    reindexing = true
    _reindexAnswered = false
    message = "rebuilding the search index (about 45 s)"
    _reindexer.command = [script, "reindex"]
    _reindexer.running = true
    return true
  }
  ```

- `write()` (:560-569): delete the `&& args[0] !== "reindex"` exception
  (the line becomes `if (applying) { message = …; return false }`).
- `_absorb` non-state branch (:388-392): add
  `if (data.indexStale !== undefined) root.indexStale = data.indexStale`
  before `if (data.message) …`. (Skip if #69 already took it at the top.)

**Tests** `tests/qml/tst_pkgmodel.qml`:
- `cleanup()`: `m.reindexing = false; m._reindexAnswered = false; m._reindexer.running = false`.
- Rewrite `test_reindex_not_refused_while_applying` (:69-74): with
  `applying = true`, `reindex()` returns true and sets `reindexing`, and
  `busy` stays false.
- `test_write_during_reindex_starts`: after `reindex()`, `write(["toggle","app","x"])`
  returns true.
- `test_second_reindex_refused`: second `reindex()` returns false, message
  `already rebuilding the index`.
- `test_reindex_answer_sets_index_stale`: `m.indexStale = true`;
  `m._absorb(JSON.stringify({ok:true, indexStale:false, message:"index rebuilt"}), false)`
  → `indexStale` false; no state read is started (`m._reader.running`
  false).
- `test_reindex_death_is_reported`: `m.reindex()`, then
  `m._reindexer.finish(1)` with no `deliver()` first (the stub API in
  `tests/qml/imports/Quickshell/Io/Process.qml`: `deliver(text)`,
  `finish(code)`) → `reindexing` false and message contains
  `ended without answering`, although "rebuilding…" was showing.
- `test_reindex_answer_unblocks`: `m.reindex()`, then
  `m._reindexer.deliver(JSON.stringify({ok:true, indexStale:false, message:"index rebuilt"}))`
  then `m._reindexer.finish(0)` → `reindexing` false, `indexStale` false,
  no death message.

Check: `nix flake check`; on razer, press `r` and toggle an app during
the rebuild: the toggle goes through.

Traps:
- Process restart is a no-op while running: `reindex()` refuses instead of
  restarting.
- Stub order in QML tests: deliver output before finish/exit, as the
  existing writer tests do; for the death case, exit without delivering.
- Menu's `r` key (`Menu.qml` :291-294, :315-323) keeps calling
  `pkg.reindex()`; no change there.

---

## PR 3: `nix flake check` runs the adapter suite

### 6. Offline guards and the `adapter` check (coder)

**`tests/adapter.sh`** — wrap three ranges, without re-indenting bodies
(the file's rule, main :50-52):

```bash
if [ "${NIXARCHY_PKG_TEST_OFFLINE:-0}" != 1 ]; then
…unchanged lines…
else echo "  skip: needs a writable nix store or the network (flake inputs)"; fi
```

1. From `FK=$(fresh_flake)` (main :153) through
   `check "reports opaque namespaces as a list" …` (:247). Keep :124-152
   (FLAKE_TMP, the `lib` fixture, `fresh_flake`, the merge check) and
   :248-250 ("says so when a flake cannot be read") outside.
2. From the comment `# "nothing was changed" has to mean it.` (:1129)
   through `check "and keeps flake.nix's mode" … "$FKS/flake.nix"` (:1152).
3. From `mkdir -p "$W59/fk" "$W59/dep"` (:1352) through
   `left_nothing "read-only lock"` (:1404).

Add a comment above the first guard: why (no network, no writable store in
the build sandbox; CI and a developer machine run them).

**`flake.nix`** `checks` (main :56): add after `qml-tests` (:94-118):

```nix
# The adapter suite, minus what needs the network or a writable nix store
# (NIXARCHY_PKG_TEST_OFFLINE). Measured: 366 checks, about 20 s.
adapter = pkgs.runCommand "nixarchy-pkg-adapter-tests"
  { nativeBuildInputs = with pkgs; [ bash jq nix git util-linux gawk gnused
      gnugrep coreutils diffutils findutils gnutar procps which ]; }
  ''
    export HOME=$TMPDIR NIX_STATE_DIR=$TMPDIR/nix-state NIXARCHY_PKG_TEST_OFFLINE=1
    cp -r ${./.} repo; chmod -R u+w repo; cd repo
    patchShebangs bin tests >/dev/null
    # Stubs written at run time start #!/usr/bin/env, which the sandbox lacks.
    sed -i "s|#!/usr/bin/env bash|#!$(command -v bash)|g" tests/adapter.sh
    bash tests/adapter.sh
    touch "$out"
  '';
```

Check:
- `bash tests/adapter.sh` (no variable) still runs every section.
- `NIXARCHY_PKG_TEST_OFFLINE=1 bash tests/adapter.sh` prints the three skip
  lines and passes outside the 11 (#68).
- `nix flake check` passes, its log shows `all passed`.

Traps:
- `${./.}` copies the whole repo into the store; fine for a check, but
  keep `.git` out (flakes already exclude it).
- In the Nix string, `$TMPDIR` and `$(command -v bash)` are shell, not Nix
  antiquotation; `${./.}` is Nix. Do not write `${TMPDIR}`.
- The sed edits the check's copy only; the source keeps `#!/usr/bin/env bash`.

---

### 7. Coordinator, per PR: verify, review, PR

- PR 1: `rg` checks; `nix flake check`; Codex + agy review of the diff.
  On razer: with the plugin **enabled**, the bound key and the menu row
  open and close the panel; with it **disabled**, each shows the "turned
  off" notification. The new other-channel command, run against a scratch
  selection (`XDG_CONFIG_HOME=$(mktemp -d)` holding an `apps.nix` with one
  `#@pkg-other x` line), prints `x`.
- PR 2: `nix flake check`; `bash tests/adapter.sh`; razer: headers,
  settings group, "server ssh", toggle during `r`, footer after `r`.
- PR 3: `nix flake check` (new `adapter` check), CI green.
- Each PR description links intent, spec and plan, and says which steps
  which coder did.

## Tests

| Command | Expected |
| --- | --- |
| `bash -n bin/nixarchy-pkg` | exit 0 |
| `shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh` | no output |
| `bash tests/adapter.sh` (razer/p620) | no failure outside the 11 (#68); new search checks pass |
| `NIXARCHY_PKG_TEST_OFFLINE=1 bash tests/adapter.sh` | three skip lines; same pass rule |
| `nix flake check` | passes; after PR 3 includes `adapter` (≈20 s, 366+ checks) |
| razer manual (lead) | key/menu row with plugin off → notification; Apps headers and settings last; search "server ssh"; toggle during reindex |

## Rollback

Revert the PR concerned. PRs are independent at run time: PR 1 is docs and
a command string, PR 2 is panel and search (the JSON contract is unchanged),
PR 3 is test-only.

## Companion issues

None. #71 (selection rows) carries the nixarchy dependency it needs:
"pkg-index: carry meta.insecure / knownVulnerabilities as an index flag".
