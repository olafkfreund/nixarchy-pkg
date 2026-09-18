---
status: approved
issue: 3
intent: intent/2026-09-17-3-flake-input.md
---

# Spec: declare a flake input from the panel

## Design

The feature is **declare, show, remove**. It never writes a module
import. That was the intent's standing recommendation and the
measurements confirmed it: across `nixvim`, `home-manager` and
`sops-nix` the `nixosModules` convention is `default` plus a named
alias, so "exactly one attribute, therefore unambiguous" would fire
almost nowhere, and where it fired it would be firing on the unusual
flakes.

### 1. The write is one appended line, and never touches `inputs { }`

The obvious design -- find the `inputs` attrset, insert inside it --
means matching braces in someone's Nix and is the reason this looked
dangerous. It is unnecessary. Measured:

    $ echo '{ a = { x = 1; }; a.y = 2; }' | nix-instantiate --eval --strict
    { a = { x = 1; y = 2; }; }

A path assignment merges with an existing attrset. So the tool appends
one self-contained top-level line and Nix merges it with whatever
`inputs = { ... }` the flake already has:

    inputs.<name>.url = "<flakeref>";  #@flake-input <name>

Verified end to end on a fixture: a flake with a nested `inputs = {
nixpkgs.url = ...; }` plus an appended `inputs.added.url = ...`
evaluates to inputs `[ "added" "nixpkgs" "self" ]`.

The anchor is the first line that is exactly `{` at column 0 -- the
flake's outer attrset. Present in both shapes that matter: the user's
adopter flake opens at `:1`, the installer template at `:23` after its
comment header. The line goes immediately after it, so the user's own
`inputs` block, formatting and comments are untouched.

The `#@flake-input <name>` marker is not a new mechanism. It is the
convention this project already uses for "a line nixarchy wrote and may
remove" -- `#@pkg`, `#@opt`, `#@draft` -- and it answers the intent's
question of how "added this way" is recorded, using the machinery that
already exists rather than inventing a registry.

### 2. What is shown, and what cannot be

`nix flake show --json <ref>` needs no build: measured at 1.4s local and
10s for a first remote fetch. It is run before anything is written, and
the panel shows what it returns.

What it returns is narrower than the issue assumed. Measured on three
flakes, identically:

    nixosModules        {"default": {"type":"nixos-module"}, "<name>": {...}}
    homeManagerModules  {"type": "unknown"}

`nixosModules` and `packages` enumerate. `homeManagerModules`,
`homeModules`, `darwinModules`, `nixDarwinModules`, `flakeModules` and
`modules` are conventions rather than schema and come back opaque. The
panel therefore says, for those, that the namespace exists and its
contents cannot be read -- never an empty list, which would read as
"this flake offers none".

For `nixosModules` the panel shows the attributes and preselects
`default` in the displayed import line, because `default` is the
flake's own answer to "which one". Displayed, not written.

### 3. The name check, refined from the intent's constraint

**This narrows an approved constraint and says so.** The intent
requires refusing "a shadowed name" and treats nixarchy's 17 inputs as
taken. Measured, that is true of one flake shape and false of the
other:

- The installer template (`:91-95`) builds module `inputs` as
  `self.inputs // nixarchy.inputs // { ... }`. `//` is right-biased, so
  nixarchy's names win silently. Shadowing is real here.
- The adopter flake measured for this issue (`:390-392`) passes
  `inherit inputs` -- the outputs function's own argument, no merge.
  Nothing is shadowed. Refusing `sops-nix` there would block a
  legitimate name to prevent a hazard that machine does not have.

Since adopters are the majority, a blanket refusal is wrong for most
users. So:

- **Refuse** a name the flake already declares. That is not a
  judgement: two definitions of the same input are an error, and the
  feature must not create one.
- **Warn, and proceed**, for a name nixarchy also uses -- naming it,
  saying it is shadowed only if this flake hands nixarchy's inputs to
  its modules, and that the installer template does exactly that.

Both lists are read, never hard-coded. The flake's own inputs come from
its `flake.lock` root node; nixarchy's come from its node in the same
file. Measured: 17 names, in milliseconds, offline. The hard-coded list
of 12 in the first draft was already missing `nixpkgs`, the name most
likely to be reached for.

### 4. Writing safely, and what "still evaluates" means

The sequence, matching the discipline `cmd_opt_set`
(`bin/nixarchy-pkg:457-480`) already uses for `apps.nix` -- backup,
write, validate, restore on failure -- with a step added for the lock:

1. **Baseline first.** `nix flake metadata` on the flake *before*
   writing. If it already fails, say so and change nothing: an input
   added to an already-broken flake would otherwise look like this
   feature's fault. This answers the intent's question about what
   "still evaluates" checks -- it checks a *delta*, not an absolute.
2. Copy `flake.nix` and `flake.lock` aside.
3. Append the marked line.
4. `nix-instantiate --parse flake.nix` -- catches a malformed flakeref
   that broke the syntax.
5. `nix flake lock` -- resolves and pins the new input. This needs
   network and an unreachable flake is an ordinary outcome, reported as
   one.
6. `nix flake metadata` again. Any failure at 4, 5 or 6 restores both
   files from the copies and reports what happened.

The check is deliberately `metadata`, not a host build. Evaluating a
host proves far more and costs far more, and an unused input cannot
break one. What it does prove is that the file parses, the flakeref
resolves and the lock is coherent -- which is the whole of what
declaring an input can affect.

**Git:** both files are already tracked in every flake this can run on,
and a tracked file's working-tree edits are visible to evaluation
without staging. So nothing is staged. The earlier draft's "must stage
what it writes" was a misreading: staging is needed for *untracked*
files, and a blanket `git add` would sweep the user's unrelated edits
into their index.

### 5. Removal

`#@flake-input <name>` identifies the line, exactly as `#@pkg`
identifies a package for `nixarchy-pkg-remove`. Removal deletes that
line and runs the same validate-or-restore sequence.

It **refuses** when the lock shows another input `follows` this one, or
when the name appears anywhere else in the flake -- an import the
person pasted, a `specialArgs` reference. Removing a declaration
something depends on breaks evaluation, which the intent's first
constraint forbids. Better to refuse and name the reason than to
succeed and hand back a broken system.

Stale `flake.lock` entries are left alone. `nix flake lock` does not
prune, the entry is inert, and pruning is a second write for tidiness.

### 6. Where this lives

Implemented in `bin/nixarchy-pkg`, following the `cmd_opt_set`
precedent of writing directly with backup and validation, and
structured as one command so it can move upstream unchanged.

The intent's open question 5 asked whether this belongs in nixarchy as
`nixarchy flake add`. On the merits it does: a CLI caller wants the
same locking, validation and rollback. But the argument that put the
other writers there was that they encode *policy* -- licence rules,
catalogue drift, marker placement. This encodes none: it appends a line
Nix merges, and validates. The recommendation is to build it here,
where it can be shipped and used, and to open an upstream issue
proposing `nixarchy flake add` with this as the reference
implementation. Recorded so the decision is visible rather than
defaulted.

### What this does not do

- **No module import is written.** Measured justification in §2.
- **No detection of who wrote the flake.** The intent dropped it: no
  content test is sound in either direction. The write is confined to
  what is true of every flake -- one outer attrset, one `inputs`
  attribute, one `flake.lock`.
- **No package wiring** (intent's open question 2). A flake offering
  only `packages` still needs its package referenced where packages are
  listed. Out of scope, and worth its own issue.
- **No host build.** §4.

### The handover

The intent's open question 3 -- how the person gets from a declared
input to working software -- is the feature's real surface, and the
honest answer is bounded. The panel cannot name the file the import
belongs in: `flake_base` (`bin/nixarchy-pkg:517-522`) guesses a
*directory* from `uname -n`, which is neither the `nixosConfigurations`
attribute nor an import site.

So it shows the line, exactly as it should be pasted, with `default`
preselected:

    inputs.<name>.nixosModules.default

and says plainly that it goes in the `imports` list of the host that
should have it, and that the panel does not know which file that is.
"Here is a line, and here is precisely what we do not know" is a worse
outcome than writing it and a better one than pretending.

## Alternatives rejected

**Insert into the existing `inputs { }` block.** Requires matching
braces in arbitrary Nix and rewriting a region the user owns. The
merge-on-append behaviour makes it unnecessary.

**Write the module import when `nixosModules` has one attribute.**
Measured to fire almost never (the convention is two), and cardinality
does not answer which host, which arguments, which enabling option, or
whether it is compatible.

**Refuse every name nixarchy uses.** Wrong for the majority: the
adopter shape does not merge nixarchy's inputs, so nothing is shadowed.

**Hard-code the shadow list.** Already wrong before use -- 12 names
where the lock says 17, missing `nixpkgs`.

**Evaluate a host to prove nothing broke.** Slow, and an unused input
cannot break one. A baseline-then-delta `nix flake metadata` proves
what is actually at stake.

**Stage the changes.** Both files are tracked; staging would only
disturb the user's index.

**Block on an upstream `nixarchy flake add`.** Correct on the merits
and ships nothing. Build here, propose upstream.

## Risks

- **This writes to the system flake**, the highest-stakes file the
  panel has touched. Mitigated by appending rather than editing, a
  before-baseline, and restore-on-any-failure. The residual risk is a
  flake whose outer attrset is not the first `{` at column 0; the
  anchor must verify rather than assume, and decline when it cannot
  find it.
- **`nix flake lock` needs network.** An ordinary outcome, reported as
  one, with both files restored.
- **`nix flake show` can build** on a flake using
  import-from-derivation. Bounded by a timeout, and reported as "could
  not inspect" rather than left hanging.
- **The shadow warning is advice, not enforcement.** Someone who
  ignores it on a template-shaped flake gets an input that locks and is
  silently ignored by their modules. Accepted: the alternative refuses
  the majority to protect a minority who have been told.
- **A `custom`-shaped flake** with no recognisable outer attrset is
  declined rather than guessed at.
- Hosts: the same write on every host. An ISO-installed machine gets
  the shadow warning more often, since its template merges.

## Verification

1. **The merge behaviour, first.** A fixture flake with a nested
   `inputs = { ... }` plus an appended `inputs.added.url` evaluates to
   inputs including both. If this fails, the whole design is void.
2. **Baseline refusal.** Against a flake that already fails
   `nix flake metadata`, the command changes nothing and says the flake
   was already broken.
3. **Round trip.** Add an input to a throwaway flake; `flake.nix` gains
   exactly one marked line; `flake.lock` gains the node; metadata
   passes. Remove it; the line is gone and metadata still passes.
4. **Restore on failure.** Add a syntactically valid but unresolvable
   flakeref. Both files come back byte-identical to their pre-write
   state.
5. **Refusal on an own-name collision.** Adding `nixpkgs` to a flake
   that declares `nixpkgs` is refused, and nothing is written.
6. **Warning on a nixarchy name.** Adding `sops-nix` warns, names the
   condition, and proceeds.
7. **Removal refuses a dependency.** With another input `follows`-ing
   it, removal declines and names the follower.
8. **What is shown.** For a flake with opaque `homeManagerModules`, the
   panel says the namespace cannot be read rather than showing it
   empty.
9. **Nothing staged.** After a successful add, `git status` shows both
   files modified and unstaged, and the user's pre-existing index is
   unchanged.
10. Every write test runs against a throwaway flake in a temporary
    directory, never the machine's own -- the same discipline
    `tests/adapter.sh` already uses for `apps.nix`.
