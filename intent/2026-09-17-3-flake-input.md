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

An earlier draft scoped this to the ISO-installed case on purpose,
because the generated flake is the only one nixarchy wrote and can
predict. That reasoning is sound about *files* and wrong about *people*:
most users today adopt nixarchy as one input among many in a flake they
already had. Confining the feature to the ISO case would refuse it to
the majority of the people who would use it, and its detection question
would become "how do we recognise whom to turn away".

The adopter's flake is genuinely less predictable -- verified on one:
128 files declaring `environment.systemPackages`, hosts under
`hosts/<name>/`, its own overlays, and nixarchy imported through two
intermediate modules. What that rules out is *guessing where an edit
goes*. It does not rule out the feature, because the two halves have
very different requirements:

- **Declaring the input** is an edit to `inputs { }` in the flake's own
  `flake.nix`. Every flake has exactly one, at a known path, with a
  known attribute. This part does not depend on who wrote the file.
- **Wiring the module** means knowing which host, which file and which
  import list. That is the part the installer's layout made answerable
  and an arbitrary flake does not.

So the scope question is not "which users", it is "which half". The
feature is for everyone; the writing is confined to the half that is
the same everywhere.

## Proposed outcome

From the panel: a way to name a flake, see what it offers, and have the
input declared and locked -- with the part that needs judgement handed
back rather than guessed.

Concretely, when this is done:

- A flake URL or a `github:owner/repo` can be added as an input without
  opening an editor.
- Before anything is written, the panel says what the flake actually
  contains, read with `nix flake show`, which needs no build and works
  on a remote flake -- measured at 10s for a first remote fetch and
  1.4s on a local flake.

  What it can say is narrower than an earlier draft promised, and the
  narrowing is measured rather than assumed. Across `nixvim`,
  `home-manager` and `sops-nix`, `nixosModules` comes back enumerated
  and typed -- `{"default": {"type": "nixos-module"}, ...}` -- and
  **every other module namespace comes back as `{"type": "unknown"}`**:
  `homeManagerModules`, `homeModules`, `darwinModules`,
  `nixDarwinModules`, `flakeModules`, `modules`. They are conventions
  rather than schema, and `nix flake show` does not look inside them.

  So the panel can enumerate `nixosModules` and `packages` honestly. For
  the rest it can say a namespace exists and nothing about its contents,
  and it must say that rather than show an empty list that reads as
  "this flake offers none".
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

- People who adopted nixarchy as a flake input into a configuration
  they already had. Most users today, and the ones for whom software
  outside nixpkgs is most likely to be the reason they came.
- People running an ISO-installed nixarchy, where the flake came from
  `installer/template/flake.nix` and the layout is known.
- `$NIXARCHY_FLAKE` (default `/etc/nixos`): `flake.nix`, `flake.lock`,
  and the git index, since a flake in a worktree sees only tracked or
  staged files.
- Not `~/.config/nixarchy/*.nix`. This is a different file with
  different rules, and conflating the two is how one of them gets
  corrupted.
- Both are in scope for declaring an input. Neither is in scope for
  having a module import written for them; see the constraint below.
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
  draft listed twelve. On one real adopter's flake the true list is
  **seventeen**, read from `flake.lock` in milliseconds with no
  evaluation and no network: `disko`, `home-manager`,
  `home-manager-stable`, `hypr-rdp`, `hyprland`, `mcp-servers-nix`,
  `microvm`, `nix-flatpak`, `nix-index-database`, `nixi`,
  `nixos-hardware`, `nixpkgs`, `nixpkgs-stable`, `omarchy`, `sops-nix`,
  `systems`, `zen-browser`.

  The five the hard-coded list missed include **`nixpkgs`** -- the name
  a person is most likely to reach for, and the one whose silent
  shadowing would be hardest to diagnose. That is the argument for
  reading, made concrete: a list maintained by hand was already wrong
  about the most important entry before anyone had used it.
- **Must not guess the module wiring.** Which `nixosModules` attribute
  to import, and whether it belongs in the host or beside it, is a
  judgement. Writing a plausible guess into someone's configuration is
  worse than writing nothing.
- **Must not depend on recognising who wrote the flake.** No
  content-based detection is sound in either direction -- a
  hand-written flake can match the template, and a generated one can
  have been rewritten since. Rather than gate the feature on an
  unanswerable question, the write is confined to what is true of every
  flake: one `inputs { }`, at a known path. What cannot be known
  everywhere is not written anywhere.
- **Must validate the file it is about to edit**, since it cannot rely
  on provenance: the `inputs` attribute is found and unambiguous, or
  the edit does not happen and says why.
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
   unevaluatable expression into a file it does not own.

   The tempting middle case -- "a flake exposing exactly one
   `nixosModules` attribute is unambiguous, so writing it is safe" --
   is not merely weak, it is measurably backwards. Across `nixvim`,
   `home-manager` and `sops-nix` the answer is always **two**:
   `{default, nixvim}`, `{default, home-manager}`, `{default, sops}`.
   The convention is `default` plus a named alias for the same module,
   so a rule keyed on "exactly one" would fire on almost nothing, and
   on the flakes it did fire for it would be firing because they are
   unusual.

   What the convention does give is something worth *showing*:
   `nixosModules.default` is the flake's own answer to "which one",
   and the panel can preselect it in the text it displays. That
   remains free. It is still not permission to write, because knowing
   which attribute removes one choice out of four -- which host,
   whether the module needs arguments, whether an option must be set
   to enable it, and whether it is compatible at all are all untouched
   by cardinality. Preselect, do not write, is the standing
   recommendation; this question is now about whether the approver
   agrees rather than about what the flakes look like.

2. **Where do inputs for packages rather than modules go?** A flake
   offering only `packages` needs no module; it needs its package
   referenced where packages are listed. Same feature or a different
   one.

3. **How does the person get from a declared input to working
   software?** Declaring is the half this can do; wiring is the half it
   will not. On an adopter's flake the panel cannot even name the file
   the import belongs in -- `flake_base` (`bin/nixarchy-pkg:517-522`)
   guesses a *directory* from `uname -n`, which is not the
   `nixosConfigurations` attribute and not an import site. So the
   handover is the feature's real surface: what is shown, how
   copyable it is, and whether the panel can say anything useful about
   where it goes without pretending to know. A handover that reads as
   "here is a line, good luck" leaves the person exactly where they
   were, having also acquired an input.

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

7. **Answered, and it constrains the outcome.** `nix flake show` does
   *not* enumerate what an earlier draft promised. Measured on three
   flakes: `nixosModules` is typed and enumerable; `homeManagerModules`,
   `homeModules`, `darwinModules`, `nixDarwinModules`, `flakeModules`
   and `modules` all return `{"type": "unknown"}`. Only `nixosModules`
   and `packages` can be listed. The remaining question is the small
   one of presentation: how the panel names a namespace it can see
   exists but cannot look inside, without that reading as "empty".
