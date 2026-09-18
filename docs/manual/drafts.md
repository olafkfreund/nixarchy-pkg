---
title: Drafts
---

# Drafts

The fifth tab is for software that is in **no repository at all** — not in
nixpkgs, not in the catalogue, just a URL to a release or a source tree.

On Arch this is where you would reach for the AUR. There is no AUR here, and
the honest equivalent is: somebody has to write a derivation. A draft is the
machine's first attempt at one.

## Drafting

From a terminal:

```bash
nixarchy-pkg draft new https://example.com/thing-1.2.tar.gz
```

`nix-init` does the work, headless. It fetches the source, guesses the
builder, guesses the dependencies and guesses the licence, and writes the
result into your selection.

**Its authors call the output a draft, and so does everything here.** Those
guesses are for a person to review. They are frequently close and they are
not a package.

## What "kept on failure" means

The draft is built once, immediately, and a build failure is reported as one.

The draft is **kept** anyway. A derivation that does not build yet is still a
much better starting point than an empty file, and deleting it would throw
away the part that was right along with the part that was wrong.

So a failed draft is a normal outcome, not an error to clear. Open it, fix
the guess, build again.

## Undrafting

`RETURN` on a draft row, once you have reviewed it and it builds. That
promotes it out of draft state — you are saying the guesses have been checked
by someone who can check them.

Nothing verifies that claim, because nothing can. It is a claim about
attention.

## When to use something else

If the software *is* in nixpkgs, use [Packages](packages). If it ships its
own flake — a Neovim distribution, a shell framework, a module published on
GitHub — a draft is the wrong tool; that is an input to declare rather than a
derivation to write.
