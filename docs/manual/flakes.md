---
title: Flakes
---

# Flakes

Some software is not in nixpkgs and never will be. A Neovim distribution, a
shell framework, a work module on a private GitHub — these ship their own
flake, and installing one is not adding a package. It is **declaring an
input**, which means editing `flake.nix`: the one file this plugin otherwise
never touches.

The sixth tab does that.

## Looking before you leap

Type a flakeref into the field — `github:owner/repo` — and press `RETURN`.

Nothing is written. `nix flake show` needs no build, and this step exists
precisely so you can look at what you are about to run somebody else's build
code for. It takes about a second on a local flake and ten on a first remote
fetch.

What comes back is a list of what the flake exposes:

```
· github:nix-community/nixvim
· nixosModules.default
· nixosModules.nixvim
· 7 packages
· homeManagerModules — exists, contents cannot be read
· homeModules — exists, contents cannot be read
· declare this as an input
```

## "contents cannot be read" is not "empty"

Those two lines are the honest part, and they are worth explaining because
they look like a failure and are not.

`nix flake show` understands `nixosModules`: it comes back typed and
enumerated, which is why you can see both `default` and `nixvim` above.
Every other module namespace — `homeManagerModules`, `homeModules`,
`darwinModules`, `nixDarwinModules`, `flakeModules`, `modules` — is a
community convention rather than anything Nix has a schema for, and `flake
show` returns them as a single opaque value.

So the panel can tell you the namespace exists and nothing about what is in
it. It says exactly that, rather than drawing an empty list — because "this
flake offers none" and "I cannot tell" are different statements and only one
of them is true.

## Declaring it

`RETURN` on *declare this as an input*. One line is appended to your
`flake.nix`:

```nix
inputs.nixvim.url = "github:nix-community/nixvim";  #@flake-input nixvim
```

Your own `inputs { }` block is not touched. It does not need to be: in Nix, a
path assignment merges with an attrset that already exists, so the line is
appended at the top level and Nix does the joining. That is why this can edit
the most important file on your machine without reformatting a single line
you wrote.

Then it locks it, and checks:

1. the flake **already evaluated** before the write — if it did not, nothing
   is written and you are told the flake was broken already, rather than
   having this blamed on whatever was added last
2. the file still parses
3. `nix flake lock` resolves the input
4. the flake still evaluates

Any failure at 2, 3 or 4 puts **both** `flake.nix` and `flake.lock` back
exactly as they were, and reports nix's own words rather than a guess at them.

What it does not do is build a host. An input that nothing imports cannot
break one, and evaluating a host costs minutes to prove more than is at stake.

## The part it will not do for you

It shows you the import line:

```
inputs.nixvim.nixosModules.default
```

and tells you, plainly, that it does not know which file that belongs in.

That is deliberate and it is the main design decision in this feature.
`default` is a good guess at *which module* — across `nixvim`,
`home-manager` and `sops-nix` the convention is always `default` beside a
named alias — but knowing the attribute settles one choice out of four.
**Which host** wants it, whether the module **takes arguments**, and whether
an **option must be set** to enable it are all still open, and the panel
cannot even name the host file: it derives a directory from your hostname,
which is neither a `nixosConfigurations` attribute nor an import site.

Writing a plausible guess into your configuration would be worse than writing
nothing, because a bad line there fails the evaluation of your whole system
rather than one package. So it hands you the line and says what it does not
know.

## Two refusals

**A name your flake already uses.** Two definitions of one input is an error,
so it is refused outright and nothing is written.

**Removing an input something still depends on.** If another input `follows`
it, or the name appears anywhere else in your flake — an import you pasted, a
`specialArgs` reference — removal declines and names what depends on it.
Succeeding would break evaluation, which is the one thing this must never do
quietly.

## One warning, which is not a refusal

If you pick a name that nixarchy also uses — `nixpkgs`, `home-manager`,
`sops-nix` and about fourteen others — you get a warning rather than a
refusal, and the distinction is measured rather than cautious.

On a machine installed from the nixarchy ISO, the generated flake hands its
modules `self.inputs // nixarchy.inputs`. That merge is right-biased, so a
colliding name locks perfectly and is then **silently ignored** by every
module. On a flake you wrote yourself and added nixarchy to, the inputs
usually pass straight through and nothing is shadowed at all.

Since the second is most people, refusing everyone would block a legitimate
name to prevent a hazard their machine does not have. So it tells you the
condition and lets you decide. The list of taken names is read from your
`flake.lock` rather than hard-coded — a hand-written list was already wrong
about `nixpkgs`, the name you are most likely to reach for.

## From a terminal

```bash
nixarchy-pkg flake show github:nix-community/nixvim
nixarchy-pkg flake add nixvim github:nix-community/nixvim
nixarchy-pkg flake list
nixarchy-pkg flake remove nixvim
```

Same commands, same output. See [From a terminal](from-a-terminal).

## What this is not

A package manager for flakes. It declares an input and hands you back the
wiring, which is the half a tool can do safely. [How it works](how-it-works)
explains the general version of that boundary.
