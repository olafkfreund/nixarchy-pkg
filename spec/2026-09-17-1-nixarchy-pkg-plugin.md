---
status: approved
issue: 1
intent: intent/2026-09-17-1-nixarchy-pkg-plugin.md
---

# Spec: nixarchy.pkg, an Omarchy plugin for packages, services and options

## Design

An Omarchy Quattro plugin, `nixarchy.pkg`, with two entry points and a bash
adapter. The plugin is a **front-end**: it owns presentation and keyboard
handling, and every write goes through a `nixarchy-*` script that already
exists.

### Shape

```
manifest.json    id "nixarchy.pkg", kinds ["menu","bar-widget"], keepLoaded true
Menu.qml         entryPoints.menu      -- summoned by a chord, keyboard-exclusive
Panel.qml        entryPoints.barWidget -- the same card as a bar dropdown
Card.qml         tabs, list, cursor, footer -- shared by both
PkgModel.qml     state, Process calls, polling
OptionForm.qml   the option editor
bin/nixarchy-pkg      the JSON adapter
bin/nixarchy-pkg-keys the key sheet
```

Modelled on `nixarchy.herdr`, which is the same two-entry-point shape with a
bash JSON backend, and whose conventions this follows deliberately rather
than inventing new ones.

### Why QML and not a TUI

Omarchy Quattro plugin kinds are `bar-widget`, `panel`, `overlay`, `menu`,
`service` and `bar`; all are QML loaded into the shared Quickshell process.
There is no terminal-UI kind, so a TUI can only ever be something a plugin
*launches*, not something it *is*. QML is also what makes the theming
requirement free: the shell exposes `Color.menu.*`, `Style` and
`BorderSurface` / `Border.surfaceSpec`, so a card with no literal colours in
it follows every installed theme, including ones written after this ships.

### The adapter, `bin/nixarchy-pkg`

Bash, `set -euo pipefail`, JSON built with `jq` and never with `sed`. Each
subcommand prints exactly one object. Failure prints
`{"ok":false,"error":"..."}` and **exits 0**, so the panel always has
something to draw rather than an empty card and no explanation.

| subcommand | delegates to | notes |
|---|---|---|
| `state` | reads `apps.nix`, `services.nix`, `/etc/nixarchy/*-template.nix` | catalogue rows: `id, label, category, note, enabled`; plus `#@pkg`, `#@opt`, `#@draft` lines |
| `search <q> [--kind] [--limit]` | `grep` over `index.tsv` | 137,875 rows, 5 TSV fields; `--limit` always applied |
| `toggle app\|service <id>` | `nixarchy-app-enable/-disable`, `nixarchy-service-enable/-disable` | |
| `pkg add\|remove <attr>` | `nixarchy-pkg-add/-remove` | `--stable` / `--unstable` pass through |
| `opt describe <path>` | `jq` over `options.json` | returns `type, description, default, example, widget` |
| `opt set <path> <value>` | writes `apps.nix` | see below |
| `opt remove <path>` | `nixarchy-opt-remove` | |
| `draft new\|undraft` | `nixarchy-pkg-new/-undraft` | |
| `pending` | diffs user files against `$XDG_STATE_HOME/nixarchy/applied/` | the queued-changes count |
| `apply` | `nixarchy-apply` | see below |
| `reindex` | `nixarchy-search --reindex` | |

### Resolved: elevation (intent question 1)

`nixarchy-apply` asks two `y/N` questions on stdin (lines 166 and 172) and
then runs `nh os switch "$flake"` (line 184), which elevates itself. A QML
`Process` has no tty.

**Resolution, verified on this machine:**

- `nh` 4.4.2 takes `-e / --elevation-strategy`, env `NH_ELEVATION_STRATEGY`,
  and accepts `pkexec` as a strategy.
- Omarchy ships a polkit **authentication agent** as an always-loaded
  first-party service plugin: `$OMARCHY_PATH/shell/plugins/polkit/`,
  `PolkitAgent.qml`, registered at `/org/omarchy/PolkitAgent`.
- `pkexec` is present at `/run/wrappers/bin/pkexec`.

So the adapter runs `nixarchy-apply` with `NH_ELEVATION_STRATEGY=pkexec` and
feeds stdin `n\ny\n` -- decline the VM preview, confirm the switch. The
password is collected by Omarchy's own themed polkit dialog, drawn by the
same shell process the panel lives in. No askpass helper, no tty.

Because `nixarchy-apply` uses `read ... || reply=""` throughout, a closed
stdin declines the switch rather than crashing, which is the safe failure.

A second key hands off to
`omarchy-launch-floating-terminal-with-presentation nixarchy-apply` instead.
This is not a lesser fallback: it is the route for any apply that asks
something unexpected, and it stays in the key sheet permanently.

### Resolved: where option values are written (intent question 2)

**`apps.nix`, not `advanced.nix`.** The intent guessed `advanced.nix`; that
was wrong. `nixarchy-search` writes option lines to
`${XDG_CONFIG_HOME}/nixarchy/apps.nix` (line 8) and `nixarchy-opt-remove`
reads them from the same file (line 8). A value written to `advanced.nix`
would be a line `nixarchy-opt-remove` could never find.

### Resolved: how far the forms go (intent question 3)

`nixarchy-search`'s `add_option` **already implements the type mapping**. This
plugin is a second front-end onto the same rules, not a new rule set:

| `options.json` type | `add_option` today | `OptionForm.qml` |
|---|---|---|
| `boolean` | two-item fzf | checkbox |
| `one of "a", "b", ...` | fzf over the quoted alternatives | radio / cycle |
| `signed integer`, `unsigned integer`, `N bit unsigned integer`, `positive integer` | prompt, default shown | numeric field |
| `string`, `path`, `absolute path` (whole-string anchored) | prompt, auto-quoted | text field, auto-quoted |
| everything else -- lists, `null or T`, attrsets, submodules, functions | seeded scaffold, commented out | seeded scaffold + "edit in $EDITOR" |

Three behaviours of `add_option` are **requirements, not accidents**:

1. **An untouched field writes nothing.** Empty input keeps the default. A
   copied-out default is a line that reads as a choice and is not one.
2. **The written line is byte-exact.** A set value is
   `  <path> = <value>;  #@opt <path>`. A scaffold is a comment block above a
   line with the exact bytes `  # <path> = ;  #@opt <path>`.
   `nixarchy-opt-remove` keys its comment-block walk on those bytes and
   nixarchy's `checks.options` asserts them, seed included.
3. **The scaffold is seeded from the option's own `example`, falling back to
   `default`**, read structurally from `options.json` -- both fields may be
   `{_type: literalExpression, text: ...}` -- never re-parsed out of the
   index's flattened preview text.

So "generated forms" honestly means: real widgets for booleans, enums and
scalars; a seeded, commented scaffold for everything else. Pretending
otherwise would write plausible-looking wrong configuration.

### Keys

```
type / or any letter  search        j k up down   move        h l left right  tab
SPACE   toggle          RETURN   details / edit value
s       stable/unstable for this attr           u  acknowledge unfree
a       apply           A        apply in a terminal
R       reindex         ESC      clear search, then close
```

Shipped as `bin/nixarchy-pkg-keys`, printed through `omarchy-menu-select` in
Omarchy's own `KEY -> description` sheet format, because keys that live only
while a menu holds the keyboard cannot appear in Hyprland's keybinding list.

### Packaging

A flake exposing `packages.default`, consumed as
`programs.nixarchy.plugins.nixarchy-pkg.src`. Two constraints from nixarchy's
`validatedPlugins` (`modules/home.nix:327-390`):

- `omarchy-plugin-validate` refuses **any symlink** inside the plugin
  directory, so the derivation is `runCommand` + `cp -r`, never
  `symlinkJoin` and never a wrapped binary.
- Every `.qml/.js/.sh/.bash` is grepped for `pacman`/`yay` and a hit fails
  the rebuild -- including inside a comment.

Nix installs the plugin; enabling it stays runtime state in `shell.json`,
deliberately, per `modules/AGENTS.md`.

## Alternatives rejected

**A terminal TUI (bash + gum + fzf) in a floating window.** This was the
original request. Rejected because Omarchy has no TUI plugin kind, so it
could not be a plugin at all; because theming would mean parsing
`gum_env.lua` and re-exporting ~120 variables that do not refresh on a theme
switch, where QML gets the tokens for free; and because it would be a second
UI over `nixarchy-search`, which is already exactly that.

**Reimplementing the writers inside the adapter.** Rejected: marker
placement, catalogue drift, unfree policy, the `pkgsOther` channel escape,
backup/restore and the parse check are all already correct in the existing
scripts. A second implementation is a second set of bugs, and the byte-exact
`#@opt` contract means a near-miss silently breaks `nixarchy-opt-remove`.

**Loading `index.tsv` into a QML model.** Rejected: 137,875 rows. Search
stays a `grep` in the adapter with a hard `--limit`.

**Applying immediately on each toggle.** Rejected: every toggle would cost a
full `nixos-rebuild switch`. Queue-then-apply also matches how nixarchy
already works -- nothing is built until `nixarchy-apply`.

**Writing option values to `advanced.nix`.** Rejected on evidence: see above.

**A custom askpass helper for elevation.** Unnecessary once `pkexec` plus
Omarchy's own polkit agent was confirmed.

## Risks

- **A wrong byte in an `#@opt` line** silently breaks `nixarchy-opt-remove`
  and nixarchy's `checks.options`. Mitigated by a round-trip test that
  writes a value and then has `nixarchy-opt-remove` remove it.
- **The plugin runs unsandboxed inside the shell.** A QML error can degrade
  the whole desktop, not just this panel. Mitigated by `qmllint` in CI and by
  keeping all logic that can fail in the adapter, where a bad exit is one
  `{"ok":false}` object.
- **Untrusted text on screen.** Package descriptions, option docs and build
  logs are external. Every such `Text` is `textFormat: Text.PlainText`, and
  nothing read from them is ever interpolated into a shell string.
- **A partial write leaving a file unparseable.** Mitigated by the existing
  idiom, which the adapter follows for its own writes: `mktemp` backup, edit,
  `nix-instantiate --parse`, restore and report on failure.
- **`pkexec` policy varies by host.** If a host has no polkit agent running,
  apply will appear to hang. Mitigated by the terminal handoff key and by
  the adapter reporting when no agent is reachable.
- **Applying is the one genuinely destructive action here**, and it rebuilds
  the system. It happens only on an explicit key, never on a toggle.

## Verification

**Adapter, against a throwaway config** -- the reason it is a separate
program:

```bash
export XDG_CONFIG_HOME=$(mktemp -d); mkdir -p "$XDG_CONFIG_HOME/nixarchy"
for p in apps services advanced; do
  install -m600 /etc/nixarchy/$p-template.nix "$XDG_CONFIG_HOME/nixarchy/$p.nix"
done
bin/nixarchy-pkg state                  | jq -e '.ok'
bin/nixarchy-pkg toggle app brave       | jq -e '.apps[]|select(.id=="brave").enabled'
bin/nixarchy-pkg search ripgrep --kind pkg --limit 5 | jq -e '.rows|length > 0'
bin/nixarchy-pkg opt describe services.openssh.ports | jq -e '.type'
bin/nixarchy-pkg opt set services.openssh.settings.PermitRootLogin '"no"'
nixarchy-opt-remove services.openssh.settings.PermitRootLogin
nix-instantiate --parse "$XDG_CONFIG_HOME/nixarchy/apps.nix"
```

That round trip is already proven by hand: the line was written at the right
place, the file parsed, `nixarchy-opt-remove` found and removed it, and the
file parsed again.

`tests/adapter.sh` -- bash, asserts, no framework -- covers every
subcommand's JSON shape, a package name containing a quote surviving the
round trip, the byte-exactness of both `#@opt` forms, and a deliberately
broken `opt set` restoring the backup and returning `ok:false`.
`shellcheck bin/nixarchy-pkg` clean.

**Plugin:**

```bash
omarchy plugin validate ./
qmllint -I "$OMARCHY_PATH/shell" *.qml
omarchy-shell shell rescanPlugins && omarchy-shell shell toggle nixarchy.pkg '{}'
qs log -p "$OMARCHY_PATH/shell" --tail 100     # no QML warnings
```

**Elevation, once, deliberately, with the user at the keyboard:** queue
`ripgrep`, press apply, confirm Omarchy's polkit dialog appears and the
build log streams into the card. This is the one check that cannot be done
unattended.

**End to end:** queue `ripgrep`, confirm the footer counts it and `apps.nix`
carries the `#@pkg` line, apply, confirm `rg` is on `PATH`; then remove it
and apply again, proving the reverse path.

**Themes:** with the panel open, `omarchy theme set` between a light and a
dark theme. A missed literal colour shows immediately.

## Out of scope for v1

Editing the flake itself, other hosts, rollback and generations, flatpaks,
and the `box` / `vm` / `devenv` catalogues. Each is a later tab against the
same adapter.
