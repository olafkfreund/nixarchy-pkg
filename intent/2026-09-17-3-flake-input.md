---
status: approved
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

Afterwards, the panel covers the whole of what a nixarchy machine can
install, rather than the part that fits a catalogue.

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

## Constraints

- **Must not break evaluation silently.** A bad input fails the whole
  system, not one line. Every write is followed by a check that the
  flake still evaluates, and a failure restores what was there before
  and says what happened.
- **Must refuse a shadowed name.** `self.inputs // nixarchy.inputs`
  means nixarchy's names win, with no error and no warning. These are
  taken: `disko`, `home-manager`, `home-manager-stable`, `hypr-rdp`,
  `mcp-servers-nix`, `microvm`, `nixi`, `nix-index-database`,
  `nixos-hardware`, `omarchy`, `sops-nix`, `zen-browser`. An input by
  one of those names would be accepted by Nix and then ignored, which is
  the worst kind of failure.
- **Must not guess the module wiring.** Which `nixosModules` attribute
  to import, and whether it belongs in the host or beside it, is a
  judgement. Writing a plausible guess into someone's configuration is
  worse than writing nothing.
- **Must not edit `flake.nix` on a machine the installer did not set
  up.** Detect it and decline.
- **Must stage what it writes.** An untracked `flake.nix` change is
  invisible to evaluation and the error says the path does not exist.
- **Must treat this as a supply-chain action.** Adding an input means
  running someone else's build code. It needs more friction than
  toggling a package, not less: the flake is named in full, what it
  exposes is shown before anything is written, and it is never a single
  keystroke from a search result.
- **Must not require sudo**, and must not silently acquire it.
- Locking needs network. An unreachable flake is an ordinary outcome and
  must read as one.
- Nothing is built until the existing apply, as everywhere else here.

## Open questions

1. **How far does the wiring go?** Showing the line to paste is safe and
   leaves the judgement with the person. Writing it into
   `hosts/<name>/default.nix` is what they actually want, and is also
   how a plugin puts an unevaluatable expression into a file it does not
   own. Somewhere between the two there may be a case that is safe
   because it is unambiguous -- a flake exposing exactly one
   `nixosModules` attribute, say. Whether to take it is the main
   decision in this task.

2. **Where do inputs for packages rather than modules go?** A flake
   offering only `packages` needs no module at all; it needs its package
   referenced where packages are listed. That may be the same feature or
   a different one.

3. **How is the ISO-installed case detected?** The template leaves no
   marker. Matching on the generated structure is possible but
   fragile, and asking nixarchy for a marker is a change in the other
   repository.

4. **Does removing an input mean unlocking it?** Taking the line out
   leaves a stale `flake.lock` entry, which is harmless but untidy, and
   `nix flake lock` does not prune on its own.

5. **Is this repository the right home**, or does adding a flake input
   belong in nixarchy proper as a `nixarchy flake add` command, with
   this plugin as one caller? The writers for everything else in #1 live
   in nixarchy for exactly that reason, and the argument that put them
   there applies here too.
