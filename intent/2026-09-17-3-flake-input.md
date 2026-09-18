---
status: draft
issue: 3
author: olafkfreund
---

# Intent: add a flake input from the menu

## Problem

Issue #1 covers everything that is a marked line in a selection file:
nixpkgs packages, the curated apps and services, and NixOS options. That
is most of what anyone installs, and it is all of what the catalogue can
describe.

It cannot reach software that lives in its own flake. A Neovim
distribution, a shell framework, a work module, a tool published on
GitHub with `nixosModules` and no nixpkgs entry -- none of these are a
package to add or an option to set. They are an input to declare, and
declaring one means editing `flake.nix`, which is the one file this
plugin deliberately never touches.

So the panel has a visible edge. Someone searches for the thing they
read about, finds nothing, and the honest answer today is "open the
flake in an editor" -- which is exactly the terminal round trip the
plugin exists to remove. Worse, it is the case where a person is least
likely to know what to type: the input line is easy, and the module
wiring underneath it is not.

On an ISO-installed nixarchy this is a gap rather than a limitation.
The generated flake is built to be extended:

- `installer/template/flake.nix` is written once from a template and
  never regenerated. Its first line says the directory is yours to edit.
- `chown_flake_dir` runs after `nixos-install`, and
  `modules/nixos.nix:886` ships `git safe.directory = [ cfg.flake ]`, so
  the flake is owned by the person using it and needs no elevation to
  change.
- The outputs already merge the user's own inputs into every host:
  `specialArgs = { inputs = self.inputs // nixarchy.inputs // { self = nixarchy; }; }`,
  and the template's own comment says an input declared above "reaches
  your hosts". There is even a worked example in the comments.

The mechanism exists and is documented in the file. What is missing is
a way to use it that does not involve knowing Nix.

This is scoped to the ISO-installed case on purpose. A machine that
already ran NixOS and adopted nixarchy as one input among many has a
flake whose shape nixarchy did not write and cannot predict.

## Proposed outcome

From the panel: a way to name a flake, see what it offers, and have the
input declared and locked -- with the part that needs judgement handed
back rather than guessed.

Concretely, when this is done:

- A flake URL or a `github:owner/repo` can be added as an input without
  opening an editor.
- Before anything is written, the panel says what the flake actually
  contains -- which `nixosModules`, `homeManagerModules` and `packages`
  it exposes -- read with `nix flake show`, which needs no build.
- The input is written into `inputs { }`, staged, and locked, and the
  flake still evaluates afterwards or the change is undone.
- An input whose name would be silently shadowed is refused with the
  reason, not written and forgotten.
- The module line the person still needs is shown exactly as it should
  be pasted, naming the host file it belongs in.
- Declared inputs are listed, and one added this way can be removed
  again.

Afterwards, the panel can declare an input, which is the step that
today requires an editor. It does not thereby install the software:
an input is a dependency, and something still has to import a module
or reference a package before anything is built. Saying otherwise
would promise a completeness this cannot deliver.

## Affected users and systems

- People running an ISO-installed nixarchy, where the flake came from
  `installer/template/flake.nix`.
- `$NIXARCHY_FLAKE` (default `/etc/nixos`): `flake.nix`, `flake.lock`,
  and the git index, since a flake in a worktree sees only tracked or
  staged files.
- Not `~/.config/nixarchy/*.nix`. This is a different file with
  different rules, and conflating the two is how one of them gets
  corrupted.
- Anyone whose flake was not written by the installer is out of scope
  and must be told so rather than have it attempted.
- `cmd_pending` (`bin/nixarchy-pkg:548`) compares only
  `apps.nix`, `services.nix` and `advanced.nix` against their applied
  copies. A `flake.nix` edit is invisible to it, so the panel would
  report "nothing queued" immediately after declaring an input. Either
  the queued count learns about the flake or the feature says plainly
  that this change is not one of the queued ones.
- `flake_base` (`bin/nixarchy-pkg:517-522`) guesses the host directory
  from `uname -n` and falls back to the flake root when it is absent.
  That is adequate for locating an applied copy and is not adequate to
  name the host whose file an import belongs in.

## Constraints

- **Must not break evaluation silently.** A bad input fails the whole
  system, not one line. Every write is followed by a check that the
  flake still evaluates, and a failure restores what was there before
  and says what happened.
- **Must refuse a shadowed name.** `//` is shallow and right-biased,
  so in `self.inputs // nixarchy.inputs` a name nixarchy also uses
  replaces the user's, with no error and no warning. "Ignored" was too
  broad in an earlier draft: the input is still declared, still locked
  and still reachable as `self.inputs.<name>`. What it loses is the
  `inputs` argument the modules actually read, which is the one place
  it was added for.
- **Must read the taken names rather than hard-code them.** An earlier
  draft listed twelve. That list is a property of whichever nixarchy
  revision the target flake pins, not of this repository, and it will
  drift the first time nixarchy gains an input. Read it from the
  pinned dependency and from the flake's own existing inputs.
- **Must not guess the module wiring.** Which `nixosModules` attribute
  to import, and whether it belongs in the host or beside it, is a
  judgement. Writing a plausible guess into someone's configuration is
  worse than writing nothing.
- **Must not edit `flake.nix` on a machine the installer did not set
  up.** Detect it and decline.
- **Must get the git interaction right, which is narrower than "stage
  everything".** An *untracked* file is invisible to a git flake; a
  *tracked* file's working-tree edits are seen without staging. Since
  `flake.nix` and `flake.lock` are already tracked, blanket `git add`
  would be unnecessary and would sweep unrelated edits of the user's
  into the index. What is needed is: the files are tracked, both are
  restorable together on failure, and the user's index and working
  tree are no more disturbed than the change requires.
- **Must treat this as a supply-chain action.** Adding an input means
  running someone else's build code. It needs more friction than
  toggling a package, not less: the flake is named in full, what it
  exposes is shown before anything is written, and it is never a single
  keystroke from a search result.
- **Must not require sudo**, and must not silently acquire it.
- Locking needs network. An unreachable flake is an ordinary outcome and
  must read as one.
- **Must not build while inspecting.** `nix flake show` is advertised
  here as needing no build, and for ordinary flakes it does not. A
  flake using import-from-derivation can make evaluation build
  anyway; the inspection has to be bounded so "just looking" cannot
  become a compile.
- **Must pin what it inspects.** What is shown and what is locked have
  to be the same revision, or the confirmation described one flake and
  the write recorded another.
- Nothing is built until the existing apply, as everywhere else here.

## Open questions

1. **How far does the wiring go?** Showing the line to paste leaves the
   judgement with the person; writing it into `hosts/<name>/default.nix`
   is what they actually want, and is also how a plugin puts an
   unevaluatable expression into a file it does not own. The tempting
   middle case -- a flake exposing exactly one `nixosModules` attribute
   -- is weaker than it looks: knowing *which* attribute removes one
   choice out of four. Which host, whether the module needs arguments,
   whether an option must be set to enable it, and whether it is
   compatible at all are all still open. Cardinality is not consent.
   Preselecting the attribute in the instructions is free; treating it
   as permission to write is not. This is still the main decision.

2. **Where do inputs for packages rather than modules go?** A flake
   offering only `packages` needs no module; it needs its package
   referenced where packages are listed. Same feature or a different
   one.

3. **How is the ISO-installed case detected?** The template leaves no
   marker, and no detection from file content is sound in both
   directions: a hand-written flake can match the template, and an
   ISO-installed one can have been rewritten since. Layout, comments
   and ownership prove neither provenance nor edit safety, and
   `git safe.directory` grants no write permission -- it only stops git
   refusing the directory. So the realistic choices are to refuse
   anything ambiguous, or to ask nixarchy for a versioned marker, which
   is a change in the other repository. Note also that a marker would
   only establish origin, not that the file is still shaped the way the
   writer expects.

4. **Does removing an input mean unlocking it?** Taking the line out
   leaves a stale `flake.lock` entry, harmless but untidy, and
   `nix flake lock` does not prune on its own. And removal has a harder
   half: how is "added this way" recorded, and what happens when the
   person has since pasted the import, or a later input `follows` this
   one? Removing a declaration something else depends on breaks
   evaluation exactly the way the first constraint forbids.

5. **Is this repository the right home**, or does adding a flake input
   belong in nixarchy proper as a `nixarchy flake add`, with this
   plugin as one caller? The writers for everything in #1 live there,
   and template compatibility, locking, validation and rollback are all
   things a CLI caller would want too. One correction to the argument
   as it was first put: it is *not* true that every write here goes
   through a writer -- `cmd_opt_set` (`bin/nixarchy-pkg:457-480`)
   rewrites `apps.nix` directly, with its own backup and parse check.
   So there is precedent for writing from this repo. The precedent is
   for a file this project's own config owns, though, not for the
   system flake, which makes it weak support rather than none.

6. **What does "still evaluates" actually check?** The constraint names
   no target. Evaluating the flake's outputs proves the file parses and
   the input resolves; it does not prove any host still builds, and an
   unused input can be added to a flake whose hosts were already
   broken, which would then look like this feature's fault. The spec
   needs a named check and a baseline taken before the write.

7. **Does `nix flake show` enumerate what is promised?** Listing
   `nixosModules` and `packages` is safe to assume; `homeManagerModules`
   is a community convention rather than a schema, and the supported
   Nix version's output format is worth confirming before the outcome
   promises to display it.
