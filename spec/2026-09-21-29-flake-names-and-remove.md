---
status: draft
issue: 29
intent: intent/2026-09-21-29-flake-names-and-remove.md
---

# Spec: a name you confirm, inputs validated whole, a guard that can't be steered

Reviewed before writing by Codex (`gpt-6-astra`, read-only), which rated
two findings here P1: the remove guard's bypass (the intent's), and a
flakeref injection into the system flake (new). Both are in scope. Codex
also pointed out that the intent's "refused only for a real reference"
promises more than a text search can deliver; §4 says what it does
promise.

## Design

### 1. One rule for a name, in both commands

`cmd_flake_add` and `cmd_flake_remove` accept a name only if it matches,
whole,

    ^[A-Za-z_][A-Za-z0-9_-]*$

and otherwise `die` with `'<name>' is not a usable input name: letters,
digits, _ and -, starting with a letter or _`. Today `add` checks one
character (`bin/nixarchy-pkg:760`, `[A-Za-z_]*`) and `remove` checks
nothing (`:846`). It is the same pattern `flake list` already parses
(`:916`), so anything this tool declares, it also lists (intent Q2;
dropping Nix's `'` costs nothing real).

Once validated, the name contains no regex metacharacters, so the
`grep -E`, awk and `sed` uses at `:773`, `:853`, `:865`, `:894` can no
longer be steered. `flake remove 'sub$'` is refused before any of them
run.

### 2. The flakeref is data, never Nix source

`:808` places the ref inside Nix quotes, and `:810` passes the whole line
through `awk -v`, which interprets backslash escapes. A ref containing
`"`, `\`, `${` or a newline can therefore write Nix that parses and means
something else. The parse and lock checks don't catch valid-but-unintended
source (Codex).

- The ref is refused unless it is printable ASCII with no whitespace and
  none of `"` `\` `$` `` ` ``. No real flakeref needs them; URL-encoding
  exists for the rare one that would.
- The line reaches awk through `ENVIRON`, as `cmd_opt_set` already does
  for the same reason, not through `-v`.

### 3. The name is suggested, shown, and editable before anything is written

`declareInspected` (`PkgModel.qml:402`) is replaced by a suggestion plus
a confirmation (intent Q1).

**Suggestion**, from the ref's structure rather than its last segment:

| ref | suggested |
| --- | --- |
| `github:` / `gitlab:` / `sourcehut:` `owner/repo[/ref][?…]` | `repo` |
| `git+https://…/repo.git[?…]`, `https://…/repo[.tar.gz]` | `repo` |
| `path:/…/dir/` | `dir` |
| anything else | the last non-empty path segment |

It then drops a trailing `.git`, maps any other character outside
`[A-Za-z0-9_-]` to `-`, and prefixes `_` if it starts with a digit. The
intent's table becomes `home-manager`, `nixpkgs`, `bar`, `bar`, `repo`,
`thing`.

**Confirmation.** RETURN on *declare this as an input* puts the field into
name mode: the placeholder reads `input name`, the field is pre-filled
with the suggestion and selected, and the Flakes rows show
`declare <ref> as inputs.<name>`. RETURN declares with whatever the field
holds; ESC goes back to the inspection with the flakeref restored. The
adapter's validation (§1) is the gate; the panel only pre-fills.

**The module hint** (`PkgModel.qml:320`) uses the suggested (or confirmed)
name instead of the literal `<name>`, via the existing, currently unused
`importLineFor()`.

### 4. The remove guard: conservative, wider, and honest about its limits

- **Boundaries.** A reference is the name bounded by anything that
  cannot be part of a Nix identifier: `(^|[^A-Za-z0-9_'-])NAME([^A-Za-z0-9_'-]|$)`.
  `sub-projects` no longer counts as `sub`; `inputs.sub` still does.
- **Wider.** It searches every `*.nix` under the flake directory, not
  just `flake.nix`. A host module that receives `inputs` through
  `specialArgs` and uses `inputs.<name>` is the case that matters, and a
  flake-only search misses it (Codex).
- **Still conservative, and it says so.** The name inside a string or a
  comment (`description = "sub"`) still refuses removal. The refusal
  names file and line, so the person can see it is a false alarm and
  remove the input by hand. Intent Q3: whole-identifier matching now,
  and no parser. Ignoring strings would be wrong anyway, since strings
  can interpolate and `follows` values are strings (Codex).
- **Baseline first.** `nix flake metadata` must pass **before** removal,
  as `add` already requires. Today a flake that was already broken
  gets blamed on the removal.
- **Stated limit, in the success message and the README:**
  removal proves the flake still parses, locks and evaluates its metadata.
  It does not evaluate hosts. The existing comment at `:754` explains
  why that is a minutes-long cost.

The intent's outcome "refused only for a real reference" is amended to
"never allowed past a reference the search can see, and the refusal says
where".

### 5. Inspection state that can't go stale

Codex found adjacent defects; all are small and all are fixed here:

- Editing the flakeref clears `inspected`, so RETURN always acts on what
  is in the field.
- Each `flake show` carries the ref it was for. A result arriving after
  ESC, a tab change or an edit is dropped.
- `_inspector` resets `inspecting` when the process exits, including a
  failed start. The unexplained "looking at…" hang seen on razer is
  **not** claimed fixed, because its cause was not found. This removes
  every path Codex and I could see for it to stick.
- `declareInspected` clears the inspection only when `write()` actually
  started. Today it clears it even when `write()` refused because busy.
- The Flakes empty state says `looking at <ref>…` while `inspecting`,
  not `RETURN to see what …`.

## Alternatives rejected

- **Encode the ref as a Nix string** (escape `"`, `\`, `${`). Correct, but
  a refusal is simpler, and no legitimate flakeref contains those.
- **Always ask for the name with no suggestion.** A good suggestion makes
  RETURN the common path.
- **A Nix parser for the reference check.** Out of proportion. The
  whole-identifier rule fixes what was seen, and the stated limit covers
  the rest.

## Risks

- **Stricter names** refuse `'` in input names, which this tool never
  listed anyway.
- **Searching all `*.nix`** under `/etc/nixos` could hit a large vendored
  tree. It's bounded by the flake directory, excludes `.git` and
  `result*`, and uses one grep.
- **Name mode** adds one state to the Flakes tab's keyboard handling,
  which #27 has just made reliable. It must use #27's `focusList()`.
  Order: #27 merges first.

## Verification

`tests/adapter.sh`, against a throwaway `NIXARCHY_FLAKE`, never
`/etc/nixos`:

1. `flake add 'foo.bar' …`, `'foo bar'`, `'1x'` → refused by name
   validation, with no nix call (check the file's mtime).
2. `flake add x 'path:/tmp/a"; y = 1; z = "'` → refused; file unchanged.
   A ref with `\` or `${` → refused.
3. `flake remove 'sub$'`, `'.*'` → refused by validation, with `sub`
   still declared.
4. `description = "see sub-projects";` → `flake remove sub` succeeds.
5. `inputs.sub` used in `hosts/x/default.nix` → `flake remove sub`
   refused, naming that file and line.
6. A broken flake → `flake remove` refused before touching anything.

The suggestion function is plain JS; its table (§3) is checked in the
panel by typing each ref and reading the pre-filled name. Panel:
`github:nix-community/home-manager/release-25.05` → RETURN, RETURN on
declare → field shows `home-manager` → RETURN (against a test flake via
`NIXARCHY_FLAKE` in the shell's environment, not the real one).
