---
title: Troubleshooting
---

# Troubleshooting

Arranged by what you noticed, not by what caused it.

## "I removed it and it is still installed"

The most common one, and it is not a fault.

You removed it from the **selection**. If the package is also declared
somewhere in your own NixOS configuration, that declaration is untouched and
still installs it. See [the boundary](how-it-works#the-boundary).

Check with:

```bash
grep -rn "the-package-name" ~/.config/nixos --include=*.nix
```

## "My packages are not listed"

Same cause, different symptom. The Selection tab lists what nixarchy manages,
which on a machine that had a configuration before nixarchy is a small
fraction of what is installed. [How it works](how-it-works) explains why, and
why making the list longer would be worse.

## "Nothing happened when I pressed the key"

Three likely reasons, in order:

1. **It was queued, not installed.** Look at the footer. If it says *1 change
   queued*, it worked — press `a`.
2. **The row was a `.settings` row** (`≡`). Those configure an app rather
   than being one; the panel says so in the message line.
3. **A writer refused.** The message line above the footer is where that
   appears. It is easy to miss and it is the machine answering you.

## "Everything says it is free"

The index is stale. A search index built before unfree and broken flags
existed carries none of them, so *every* package reads as free.

The panel says **index stale — r to rebuild** when this is the case. Press
`r`. It takes about a minute.

An absent flag is absent evidence, not a "no".

## "`a` seems to hang"

It is probably waiting for a password on a machine with no polkit agent to
show the prompt, or for an answer to a question the panel cannot draw.

Press `SHIFT+A` instead — the same apply, in a real terminal, where you can
see and answer whatever it wants.

## "I pressed ESCAPE during a build and it kept going"

Correct. `ESCAPE` stops you watching the log; it does not stop the build. See
[Applying changes](applying).

## "It refused an unfree package"

It did not, quite. The writer adds the package and then tells you whether
your machine's licence policy will let the rebuild use it. If `allowUnfree`
is off — which is unusual, and means somebody turned it off deliberately — it
also scaffolds a *commented* `allowUnfreePredicate` naming just that package,
for you to uncomment.

Read the message line. That scaffold is a licence-policy edit sitting in your
`apps.nix`, commented out, waiting for you.

## "Adding from the other channel wants two presses"

Yes. The channels share no store paths, so it brings an entire second
closure — `nixarchy doctor` measures vlc at 1.5 GB. The first press tells you
what it will cost; the second does it. See [Packages](packages#the-other-channel).

## "I want to see what it would do, without a panel"

```bash
nixarchy-pkg pending | jq
```

[From a terminal](from-a-terminal) has the rest.

## Still wrong

`nixarchy doctor` checks the machine rather than the panel, and is the right
next step for anything that smells like configuration rather than interface.

If it is the panel, the source is small and commented:
[github.com/olafkfreund/nixarchy-pkg](https://github.com/olafkfreund/nixarchy-pkg).
