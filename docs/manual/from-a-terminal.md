---
title: From a terminal
---

# From a terminal

The panel does not talk to your machine directly. Everything it does goes
through one script — `bin/nixarchy-pkg` in the plugin directory — and that
script is perfectly usable on its own.

```bash
~/.config/omarchy/plugins/nixarchy.pkg/bin/nixarchy-pkg state
```

Every command prints one JSON object and exits 0. A refusal is a value, not a
crash: `{"ok": false, "error": "..."}` with exit status 0, because a writer
declining to do something is an answer.

## The commands

| | |
| --- | --- |
| `state` | Everything the panel draws: apps, services, packages, options, drafts |
| `search <query> --kind pkg\|opt [--limit N]` | The index, ranked |
| `toggle app\|service <id>` | What `SPACE` does |
| `pkg add <attr> [--stable\|--unstable]` | What `RETURN` and `SHIFT+RETURN` do |
| `pkg remove <attr>` | |
| `opt describe <path>` | An option's type, default, example and docs |
| `opt set <path> <value>` / `opt remove <path>` | |
| `opt replace <path> <value>` | Change an option already marked in `apps.nix` |
| `draft new <url>` / `draft undraft <name>` | See [Drafts](drafts) |
| `flake show <ref>` / `flake list` | Inspect a source or list locked inputs |
| `flake add [--no-follows] [--no-flake] <name> <ref>` | Declare and lock an input; `--no-flake` also disables follows |
| `flake update <name>` / `flake remove <name>` | Update a locked input, or remove one this tool declared |
| `recover [--discard]` | Put back what an interrupted write changed, or keep the files as they are. See [Troubleshooting](troubleshooting) |
| `pending` | What would change on the next apply |
| `check [--dry-run]` | Evaluate a private copy of the flake with the queued selection |
| `apply [--pin <part>=<sha256>]` | The rebuild. Streams a log, then one JSON object |
| `reindex` | Rebuild the search index. About a minute |

## Option values

Pass a Nix expression as one shell argument. For example:

```bash
nixarchy-pkg opt set services.openssh.ports '[ 80 443 ]'
nixarchy-pkg opt replace services.openssh.ports '[ 22 ]'
```

`opt describe` reports `widget`, `item`, `nullable`, `multiline`,
`constraint`, and integer `min`/`max` bounds. Lists of strings or integers
have a list widget; a `null or` type can take `null`. A package type gets a
package widget only if `apps.nix` takes `pkgs`.

`opt set` and `opt replace` refuse a literal integer outside its bounds.
They also refuse a single string literal, or a list of string literals, that
breaks the declared non-empty, absolute-path, or no-newline-and-colon rule.
Other Nix expressions are left to the usual parse check. A refusal leaves
`apps.nix` unchanged.

## A worked example

Quote a path for the shell when a key contains spaces or punctuation:

```bash
nixarchy-pkg opt set 'fileSystems."/mnt/usb drive".options' '[ "nofail" ]'
nixarchy-pkg opt replace 'fileSystems."/mnt/usb drive".options' '[ "nofail" "noauto" ]'
```

`opt set` refuses a path already marked in `apps.nix`; `opt replace` requires
one. Both refuse invalid paths, including an unfilled `<name>` or `*`, and
reject values that would make the file fail Nix's parse check.

`flake add` answers with `name`, `url`, `follows`, and `message`. It does not
return an `import` field: inspect the source with `flake show` to see its
modules. `flake list` returns `dir`, `stale`, and `inputs`. Each input has
`name`, `url`, `mine`, `locked`, `follows`, `flake`, and `inspectable`; a
marked input missing from the lock sets `stale`. `flake update` reports
`moved` and `removed` node keys, `changed`, `lockChanged`, and the named
input's `from` and `to` modification dates when available.

What is queued, as a list of markers:

```bash
nixarchy-pkg pending | jq -r '.changes[].marker'
```

Every package taken from the other channel:

```bash
nixarchy-pkg state | jq -r '.packages[] | select(.channel == "other") | .attr'
```

Whether this machine follows stable or unstable:

```bash
nixarchy-pkg state | jq -r '.channel'
```

## `pending`

`pending` snapshots your selection into a private directory under
`~/.local/state/nixarchy` and compares it against the flake's copy:

```bash
nixarchy-pkg pending | jq
```

Its object carries:

| Field | Meaning |
| --- | --- |
| `ok`, `neverApplied`, `base` | Whether the read succeeded, whether `$base/nixarchy` exists yet, and the flake base path |
| `writing` | `true` if a write was in progress or interrupted (`pkg-recovery/open` existed) during the read |
| `count` | `changes | length` — the number of marked-line changes |
| `changes[]` | `{marker, file, line, change, lineNo}` where `change` is `on`, `off`, `added`, `removed`, or `modified` (a marked value changed in place), and `lineNo` is the line number in the live file (or `null` for `off` and `removed`) |
| `files[]` | `{file, label, path, status, unmarked, hunk, conflict, explained}` for each changed part or draft. `status` is `new`, `modified`, or `dropped`; `conflict` is `overwrite`, `blocks`, or `null`; `explained` is `true` when `status` is `modified`, `unmarked` is `0`, and at least one `changes[]` row belongs to this file |
| `total` | `count` plus the number of `files[]` entries with `explained: false` |
| `fingerprint` | One 64-digit SHA-256 over every `.nix` file in the selection snapshot, names included |
| `pins` | `{apps, services, advanced, flatsnap}` — each file's 64-digit SHA-256, or `""` when absent |
| `sources` | `{apps, services, advanced, flatsnap}` — each live path in `~/.config/nixarchy`, or `null` when absent |
| `unpinned` | `{drafts: ["packages/<name>.nix", …], flake: true}` |

## `check [--dry-run]`

`check` materialises the flake's tracked files and your selection into a
private directory under `~/.local/state/nixarchy` and evaluates this machine's
`nixosConfigurations.<host>.config.system.build.toplevel.drvPath`. With
`--dry-run`, a passing evaluation also runs `nix build --dry-run`.

```bash
nixarchy-pkg check
nixarchy-pkg check --dry-run
```

When `ok` is `true`, the answer always carries:

| Field | Meaning |
| --- | --- |
| `host` | `uname -n` |
| `verdict` | `evaluates`, `fails`, `superseded`, or `unknown` |
| `fingerprint` | The selection snapshot's 64-digit SHA-256 |
| `pins` | `{apps, services, advanced, flatsnap}` hashes from the checked snapshot |
| `unpinned` | `{drafts: […], flake: true}` |
| `blocked` | Drafts edited in the flake: `[{label, conflict: "blocks"}, …]` |
| `note` | `"Checked evaluation only, not a build or a switch. This is evidence, not a guarantee: apply evaluates again for real."` (plus `" With import-from-derivation on, evaluating may have built some inputs."` when `allow-import-from-derivation` is `true`) |

Additional fields appear when set:

| Field | When present |
| --- | --- |
| `reason` | On `verdict: "unknown"`, why the check declined or timed out |
| `drvPath` | After a successful evaluation (kept if the verdict then becomes `superseded`), the evaluated system `.drv` path |
| `summary`, `error`, `at` | On `verdict: "fails"`, when Nix printed them: the one-line summary, the last 200 lines of rewritten error output, and `{file, line}` (or `null`) in `~/.config/nixarchy` |
| `dryRun`, `dryRunError` | With `--dry-run` after `evaluates`: `{build, fetch, downloadMiB}` (or `null`), and the error string when the dry run failed |

## `apply [--pin <part>=<sha256>]`

`apply` accepts repeatable `--pin <part>=<sha256>` flags, where `<part>` is
`apps`, `services`, `advanced`, or `flatsnap`, and `<sha256>` is 64 lowercase
hex digits (or empty when the file must be absent):

```bash
nixarchy-pkg apply --pin apps=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef --pin flatsnap=
```

Each `--pin` is forwarded to `nixarchy-apply` as `--expect-sha256
<part>=<sha256>`. If a file changed on disk since it was hashed, `apply` exits
without copying or building and sets `nixarchyPkgApply.message` to:

```
a file changed since you reviewed it -- nothing was copied or built; look at the queue again
```

## The search index

`state`, `search` and `reindex` carry an `index` object next to `indexStale`:

| Field | Meaning |
| --- | --- |
| `status` | `fresh`, `stale` or `missing` |
| `builtAt` | When `index.tsv` was last written, in Unix seconds; `null` when `status` is `missing` or the file's time cannot be read |
| `changed` | The names of what changed since the index was built, or `null` when not known |

`indexStale` is `true` whenever `status` is not `fresh`. `changed` is a list
only when the index is stale, `nixarchy-search` is on `PATH`, and the stamp
and the current inputs are both recognised. The names, in this order and
without duplicates, are:

| Name | Input |
| --- | --- |
| `nixpkgs` | the nixpkgs source |
| `index builder` | the script that walks nixpkgs |
| `options` | `options.json` |
| `app list` | the app index or the app table |
| `flatpaks` | the Flatpak rows |
| `new-package row` | the new-package row |

`reindex` answers one object either way. On success:

```json
{"ok": true, "indexStale": false, "index": {"status": "fresh", ...}, "message": "index rebuilt"}
```

When the index is still stale afterwards, `ok` is `false`, `error` is one line
(`the search index is still stale: <reason> -- see <cache>/index-errors.log`),
and `detail` is an array of the last lines `nixarchy-search` wrote, up to 8,
without its progress messages and evaluation warnings.

## What is stable and what is not

This page makes the output an interface, so it should say which parts.

**Relied on:** `ok` on every object, and `error` when `ok` is false (a
failed `reindex` included). The
top-level keys of `state` — `apps`, `services`, `packages`, `options`,
`drafts`, `files`, `channel`, `indexStale`, `index`. The `count`, `total`, `changes`,
`files`, `fingerprint`, `pins`, `sources` and `unpinned` of `pending`, and the
`verdict`, `fingerprint`, `pins`, `unpinned`, `blocked` and `note` of `check`.
Those are the shape, and changing them would be a breaking change.

A `packages` row carries `attr` and `channel`. A `default` package with a
fresh index entry may also carry `summary`, `version` and `flags`. These
optional fields are omitted when the index is stale or missing, when it lacks
the package, and for every `other` package; they are not part of the relied-on
shape. An indexed package with no flags carries `flags: []`.

**Not relied on:** the exact wording of any `message` or `error` string.
Those are a writer's own words, passed through unaltered, and the writers
belong to nixarchy rather than to this plugin — they will improve their
messages and this will pass the improvements along.

**Not an interface at all:** the log lines `apply` streams before its final
object. That is a build's output. Parse the last line, which is JSON, and
treat the rest as text for a human.

## The one thing to know about `apply`

It is the only command here that changes the machine, and it asks for
elevation. From a terminal you will get an ordinary password prompt; from the
panel it goes through polkit. If you are scripting, think about which of
those you want before you wire it into something unattended.
