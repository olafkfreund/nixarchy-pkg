---
status: approved
issue: 1
spec: spec/2026-09-17-1-nixarchy-pkg-plugin.md
---

# Plan: nixarchy.pkg, an Omarchy plugin for packages, services and options

## The approved decisions, in full

Everything needed to implement this is below; the intent and spec need not be
opened.

**What it is.** An Omarchy Quattro plugin, id `nixarchy.pkg`, kinds
`["menu","bar-widget"]`, `keepLoaded: true`. QML, because Quattro has no
terminal-UI plugin kind and because the shell's theme tokens are what make
"follows every Omarchy theme" free.

**What it is not.** A package manager. Every write goes through an existing
`nixarchy-*` script. The plugin owns presentation and keys only.

**Files written, ever:** `~/.config/nixarchy/apps.nix` and
`~/.config/nixarchy/services.nix`. Never `/etc/nixos`, never `$flake/nixarchy/`
(that is `nixarchy-apply`'s output), never `advanced.nix`.

**Elevation.** `nixarchy-apply` asks two `y/N` questions on stdin (lines 166,
172) then runs `nh os switch` (line 184), which elevates itself. The adapter
runs it with `NH_ELEVATION_STRATEGY=pkexec` and stdin `n\ny\n` — decline the
VM preview, confirm the switch. `nh` 4.4.2 accepts `pkexec`; Omarchy ships an
always-loaded polkit agent (`$OMARCHY_PATH/shell/plugins/polkit/`, registered
at `/org/omarchy/PolkitAgent`), so the password dialog is drawn by the same
shell process. `pkexec` lives at `/run/wrappers/bin/pkexec`.

**Option values go to `apps.nix`** — `nixarchy-search` writes them there
(line 8) and `nixarchy-opt-remove` reads them from there (line 8).

**The `#@opt` line format is byte-exact**, because `nixarchy-opt-remove` walks
the comment block keyed on those bytes and nixarchy's `checks.options` asserts
them:

```
  <path> = <value>;  #@opt <path>          a set value
  # <path> = ;  #@opt <path>               a scaffold's marked line, exactly
```

A scaffold is that marked line preceded by a comment block: the index preview
text, then the option's `example` (or `default` when there is no example),
each line prefixed `  # `, with the first seed line rewritten to `<path> = ...`.

**Three behaviours copied from `add_option` in `nixarchy-search`:**

1. An untouched field writes **nothing**. Empty input keeps the default; a
   copied-out default reads as a choice and is not one.
2. Strings and paths are auto-quoted unless already quoted.
3. `example` and `default` are read structurally from `options.json`, handling
   the `{_type: literalExpression, text: ...}` shape — never re-parsed out of
   the index's flattened preview text.

**Type → widget** (patterns anchored exactly as `add_option` anchors them, so
`list of string` and `null or path` deliberately fall through):

| type | widget |
|---|---|
| `boolean` | checkbox |
| `one of "a", "b", …` | radio / cycle over the quoted alternatives |
| `signed integer`, `unsigned integer`, `N bit unsigned integer`, `positive integer` | numeric field, default shown |
| `string`, `string,…`, `string …`, `path`, `path,…`, `absolute path` | text field, auto-quoted |
| everything else | seeded scaffold + "edit in $EDITOR" |

**Queue, then apply.** A toggle edits a file. Nothing builds until the apply
key. The footer shows the queued count from `pending`.

**Search** is a `grep` over `~/.cache/nixarchy/index.tsv` (137,875 rows, 5 TSV
fields: kind, name, summary, flags/type, escaped preview) with a hard
`--limit`. The TSV is never loaded into QML.

**Packaging.** A flake exposing `packages.default`, consumed as
`programs.nixarchy.plugins.nixarchy-pkg.src`. The derivation is `runCommand` +
`cp -r`: `omarchy-plugin-validate` refuses any symlink inside the plugin
directory, so no `symlinkJoin` and no wrapped binaries. Nixarchy's
`validatedPlugins` greps every `.qml/.js/.sh/.bash` for `pacman`/`yay` and
fails the rebuild on a hit, including inside a comment.

**Safety rules that hold everywhere.** Adapter failures print
`{"ok":false,"error":"..."}` and **exit 0**. JSON is built with `jq`, never
`sed`. Every `Text` showing a package description, option doc or build log is
`textFormat: Text.PlainText`, and nothing read from those is interpolated into
a shell string.

## Steps

1. `bin/nixarchy-pkg` — skeleton: arg parsing, `die()` emitting
   `{"ok":false,...}` and exiting 0, path resolution for `apps.nix`,
   `services.nix`, `index.tsv`, `options.json` (read from `nixarchy-search`'s
   baked store path), `$XDG_STATE_HOME/nixarchy/applied/`.
   → verify by `bin/nixarchy-pkg nosuchcmd | jq -e '.ok == false'`

2. `bin/nixarchy-pkg state` — parse `#@ <id>` rows out of the two user files
   and the two `/etc/nixarchy/*-template.nix` catalogues; join label, category
   and note; mark `enabled` by whether the marked line is uncommented; collect
   `#@pkg`, `#@opt`, `#@draft` lines.
   → verify by `state | jq -e '.apps|length > 0 and .services|length > 0'`
   against a throwaway `XDG_CONFIG_HOME`

3. `bin/nixarchy-pkg search` — `grep` over `index.tsv`, `--kind`, `--limit`,
   flags split out of field 4.
   → verify by `search ripgrep --kind pkg --limit 5 | jq -e '.rows|length > 0'`

4. `bin/nixarchy-pkg toggle` / `pkg add|remove` / `draft` — delegate to
   `nixarchy-app-enable/-disable`, `nixarchy-service-enable/-disable`,
   `nixarchy-pkg-add/-remove`, `nixarchy-pkg-new/-undraft`; return fresh
   `state`.
   → verify by `toggle app brave | jq -e '.apps[]|select(.id=="brave").enabled'`

5. `bin/nixarchy-pkg opt describe` — `jq` over `options.json`, returning
   `type, description, default, example` plus a `widget` field resolved by the
   table above.
   → verify by `opt describe services.openssh.ports | jq -e '.type'`

6. `bin/nixarchy-pkg opt set` — backup, insert before the file's final `}`,
   `nix-instantiate --parse`, restore on failure. Byte-exact lines.
   → verify by the round trip in Tests below

7. `bin/nixarchy-pkg pending` / `apply` — `pending` diffs the user files
   against `$XDG_STATE_HOME/nixarchy/applied/`; `apply` runs `nixarchy-apply`
   with `NH_ELEVATION_STRATEGY=pkexec` and stdin `n\ny\n`, streaming plain
   lines then a final JSON object.
   → verify by `pending | jq -e '.count >= 0'`; apply is verified by hand

8. `tests/adapter.sh` — bash asserts, no framework. Every subcommand's JSON
   shape; a name containing a quote surviving the round trip; both `#@opt`
   forms byte-exact; a deliberately broken `opt set` restoring the backup and
   returning `ok:false`.
   → verify by `bash tests/adapter.sh` green and `shellcheck bin/nixarchy-pkg`
   clean

9. `manifest.json` — `schemaVersion: 1`, id `nixarchy.pkg`, kinds, entry
   points, `keepLoaded: true`, `barWidget.defaultSection: "right"`.
   → verify by `omarchy plugin validate ./`

10. `PkgModel.qml` — `Process` calls into the adapter, JSON into list models,
    a settle `Timer` after writes, polling only while open.
    → verify by `qmllint`

11. `Card.qml` — tabs Apps · Services · Packages · Options · Drafts, search
    line, flat list with cursor, per-row state glyph and `unfree`/`broken`
    flags, footer with the queued count. No literal colours.
    → verify by `grep -nE '#[0-9a-fA-F]{6}' *.qml` returning nothing

12. `Menu.qml` — `PanelWindow` on the focused Hyprland output,
    `WlrLayershell.layer = Overlay`, `keyboardFocus = Exclusive`, scrim
    `Color.menu.scrim`, card a `BorderSurface` with `Color.menu.background`
    and `Border.surfaceSpec("menu","border",…)`. `open(payloadJson)`,
    `close()`, `toggle()`.
    → verify by `omarchy-shell shell toggle nixarchy.pkg '{}'` drawing

13. `Panel.qml` — the same `Card` as a bar dropdown, badge = queued count.
    → verify by the widget appearing in the bar

14. `OptionForm.qml` — widgets per the table; serialise to Nix; untouched
    fields write nothing; scaffold path offers "edit in $EDITOR".
    → verify by setting a boolean, an enum and a string and removing each with
    `nixarchy-opt-remove`

15. Apply UI — the card becomes a plain-text log pane; `ESC` detaches from the
    log without killing the build; a second key hands off to
    `omarchy-launch-floating-terminal-with-presentation nixarchy-apply`.
    → verify by hand, once, with the user present

16. `bin/nixarchy-pkg-keys` — the key sheet through `omarchy-menu-select`, in
    Omarchy's `KEY → description` format.
    → verify by running it

17. `flake.nix` — `packages.default` via `runCommand` + `cp -r`; README with
    the `programs.nixarchy.plugins` snippet; `preview.png`.
    → verify by `nix build .#default` then `omarchy plugin validate ./result`

18. CI — a workflow running `shellcheck`, `tests/adapter.sh` and
    `omarchy plugin validate`.
    → verify by a green run on the PR

## Tests

Against a throwaway config, so nothing on the machine is touched:

```bash
export XDG_CONFIG_HOME=$(mktemp -d); mkdir -p "$XDG_CONFIG_HOME/nixarchy"
for p in apps services advanced; do
  install -m600 /etc/nixarchy/$p-template.nix "$XDG_CONFIG_HOME/nixarchy/$p.nix"
done

bin/nixarchy-pkg state                               | jq -e '.ok'
bin/nixarchy-pkg toggle app brave                    | jq -e '.apps[]|select(.id=="brave").enabled'
bin/nixarchy-pkg search ripgrep --kind pkg --limit 5 | jq -e '.rows|length > 0'
bin/nixarchy-pkg opt describe services.openssh.ports | jq -e '.type'
bin/nixarchy-pkg opt set services.openssh.settings.PermitRootLogin '"no"'
grep -q '^  services\.openssh\.settings\.PermitRootLogin = "no";  #@opt services\.openssh\.settings\.PermitRootLogin$' \
  "$XDG_CONFIG_HOME/nixarchy/apps.nix"
nixarchy-opt-remove services.openssh.settings.PermitRootLogin
nix-instantiate --parse "$XDG_CONFIG_HOME/nixarchy/apps.nix"
```

Expected: every `jq -e` exits 0, the `grep -q` matches, removal reports
success, and the file parses before and after. This round trip has already
been run by hand and passes.

```bash
bash tests/adapter.sh          # all asserts pass
shellcheck bin/nixarchy-pkg    # no output
omarchy plugin validate ./     # valid
qmllint -I "$OMARCHY_PATH/shell" *.qml
grep -nE '#[0-9a-fA-F]{6}' *.qml   # no output: no hardcoded colours
```

Runtime, on this machine:

```bash
omarchy-shell shell rescanPlugins
omarchy-shell shell toggle nixarchy.pkg '{}'
qs log -p "$OMARCHY_PATH/shell" --tail 100    # no QML warnings
omarchy theme set <a light theme>              # panel re-themes live
```

End to end, deliberately and with the user present: queue `ripgrep`, confirm
the footer counts it and `apps.nix` carries the `#@pkg` line, apply, confirm
the polkit dialog appears, the log streams, and `rg` is on `PATH` afterwards;
then remove it and apply again.

## Rollback

- **Before apply:** nothing has been built. `git checkout` the branch away, or
  `nixarchy-app-disable` / `nixarchy-pkg-remove` / `nixarchy-opt-remove` each
  queued change. The user files are plain text under the user's own control.
- **A bad write:** the adapter restores its `mktemp` backup and reports
  `ok:false`; the file is unchanged. `/etc/nixarchy/*-template.nix` is the
  pristine catalogue if a file must be rebuilt from scratch.
- **After apply:** `nixarchy-rollback`, or `nh os switch` to the previous
  generation. Standard NixOS generations; this plugin adds no new failure mode.
- **The plugin itself:** `omarchy plugin remove nixarchy.pkg`, or drop the
  `programs.nixarchy.plugins.nixarchy-pkg` line and rebuild. It is opt-in and
  installs nothing outside `~/.config/omarchy/plugins/`.
- **A QML error degrading the shell:** `omarchy-restart-shell`. Keeping all
  fallible logic in the adapter is what makes this rare.
