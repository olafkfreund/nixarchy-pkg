---
title: Applying changes
---

# Applying changes

Everything else in this manual edits a file. This is the part that changes
the machine.

## `a`

Press `a`, and then `a` again: the first press says what will happen and
waits, because this rebuilds the whole system. Any other key, or five
seconds, cancels. The card then fills with a build log.

What runs is `nixarchy-apply`: it copies your selection into the flake
directory and rebuilds. It needs a password, and it gets one through your
polkit agent — Omarchy runs one as an always-loaded service, so the prompt
appears on screen in the same shell the panel lives in.

The log is streamed as plain text, because it is somebody else's build output
and nothing here should pretend to understand it. When it finishes, the last
line is the result.

## `SHIFT+A`

The same apply, in a real terminal instead.

That is the route for two situations:

- a machine with **no polkit agent** to answer the password prompt, where `a`
  would sit there waiting for something that cannot happen
- any apply that **asks a question the panel cannot show** — a prompt, a
  confirmation, a conflict

If `a` seems to hang, try `SHIFT+A` before assuming anything is broken.

## `ESCAPE` while it is building

Stops watching the log. **It does not stop the build.**

This is worth being precise about, because the two were once conflated here
and the result was a bug. The build keeps going: it is elevating,
downloading, switching a system. Stopping it half way is never what `ESCAPE`
meant, and a rebuild interrupted mid-switch is a considerably worse place to
be than one you stopped watching.

If you want the build gone, deal with it where it runs, not by closing a
window.

## What "queued" meant

The count in the footer and in [the bar](the-bar) is the difference between
your selection files and the copy the flake actually reads.

That is asked of the files every time rather than remembered, which is why
two panels open at once cannot disagree, and why editing
`~/.config/nixarchy/apps.nix` in an editor shows up here without anything
being told about it.

**never applied** means the flake-side copy does not exist yet. The first
apply creates it.

## Afterwards

It is a NixOS generation. If the result is wrong, the previous one is still
there and still bootable — that is the property the whole two-step dance buys
you, and it is the reason this plugin queues changes instead of installing
them.
