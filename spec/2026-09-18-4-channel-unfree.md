---
status: draft
issue: 4
intent: intent/2026-09-18-4-channel-unfree.md
---

# Spec: channel selection when adding a package, and the writer's last word

## Design

The approved intent settled open question 1 as **(c)**: the panel
surfaces the writer's report properly and lets the commented
`allowUnfreePredicate` scaffold stand, rather than predicting the case
or changing the writer. The evidence is `nixarchy-pkg-add:12-18` --
`allowunfree` and `haspredicate` are literals baked in at build time,
`allowunfree=true` is the default, and the writer's own comment at
`:338-341` calls the opposite "the minority case (#497) ... somebody
turned it off on purpose".

That decision makes this issue two things: a channel key, and making
the writer's output legible. They are the same issue because (c) is
only honest if the report can actually be read.

### 1. `SHIFT+RETURN` on a search row adds from the other channel

A letter key cannot do this. `Menu.qml:201` gates single letters on
`!search.activeFocus`, and adding a package happens *while searching* --
the search field has the keyboard at exactly the moment the key is
needed. `Menu.qml:174-176` handles `Return` with no modifier test and
no focus gate, so `SHIFT+RETURN` is both free and reachable there.

It is also the panel's existing idiom rather than a new one:
`Menu.qml:186-189` already reads `SHIFT+A` as the variant of `a` --
apply, but in a terminal. `SHIFT+RETURN` is add, but from the other
channel.

`Menu.qml:174` gains a modifier test ahead of the plain case. The
common path -- RETURN on a free, default-channel row -- is untouched.

### 2. A confirmation in the message pane, not a dialogue

The other channel costs a whole duplicate closure, and the cost is
invisible: `nixarchy-doctor:707-711` measures btop at 0 shared paths
and 51 MB duplicated, vlc at 1.5 GB. That deserves a second look, and
the intent forbids a mode.

First `SHIFT+RETURN` arms; second commits. No dialogue component, no
new surface, no state beyond one property: the message pane that
`Card.qml:222` already draws says what is about to happen, and the
next key either confirms it or is anything else, which disarms.

The armed message names the channel, the cost, and what is not known:

    btop from stable -- its own closure, no store paths shared with
    the channel you are on. unfree and broken are not known for that
    channel. SHIFT+RETURN again to add it.

### 3. The panel learns which channel the machine follows

Needed so the message can name the other channel, and so the key is
not offered where `nixarchy-pkg-add:112` would exit 1 -- the intent
requires "not offered ... rather than offered and then refused".

`cmd_state` gains a `channel` field, read by reproducing the four-line
parse at `nixarchy-pkg-add:80-88` exactly: `nixpkgs.url` out of
`$NIXARCHY_FLAKE/flake.nix`, matched against `nixos-unstable` and
`nixos-NN.NN`, defaulting to `custom`.

This is deliberate duplication and the reason matters.
`nixarchy-channel` exists on `PATH` and would answer, but only as prose
(`nixarchy-channel:92`, "This machine follows: ...") with no
machine-readable mode, and prose can drift. What must not drift is
agreement with **the specific writer that will act on the request**.
Copying `nixarchy-pkg-add`'s own parse guarantees the panel offers
exactly what that writer accepts; asking a different program cannot.
The parse is already duplicated upstream in `nixarchy-channel:77`, the
doctor and `nixarchy-pkg-add:85`, so a fourth copy follows an existing
precedent rather than setting one.

When the parse yields `custom` the key is still offered, mirroring
`nixarchy-pkg-add:103-109`, which warns and proceeds rather than
refusing -- "refusing would block a legitimate request on a flake this
tool merely cannot parse". The armed message says the channel could
not be determined instead of naming one.

### 4. The message pane stops eliding the writer's last word

`Card.qml:228` caps the writer's output at `maximumLineCount: 3` with
elide. The writer's report is one wrapped table row per package plus,
in the scaffold case, the line that says a licence-policy comment was
written. On a multi-package add that line is off the bottom.

Under decision (c) this is not a separate nicety -- it *is* (c). "Let
the scaffold stand and surface the report properly" is not satisfied
by a report whose last line cannot be read.

The cap is raised and the pane scrolls rather than eliding. The
footer's own caption and the queued count are unaffected.

### What the channel key deliberately does not do

**It does not show flags for the other channel.** It cannot. The
other-channel branch at `nixarchy-pkg-add:301-318` `continue`s before
the unfree and broken block at `:331`, and the probe at `:246` is
`import $nixpkgs` -- the channel the machine already follows, by
definition the wrong one. The message says the flags are not known
rather than showing flags about a different package. This resolves
open question 3 as the honest, cheap option, and open question 4 with
it: `broken` is dropped by the same `continue`, so it is named in the
same sentence at no extra cost.

**It does not move an existing package between channels.**
`nixarchy-pkg-add:222` matches `#@pkg(-other)? <attr>$`, so a package
present on either channel reports `present` and is skipped. This is
the add path or nothing; the key is offered only on search rows, which
are by definition not yet in the selection.

**It does not predict or alter the licence policy.** Decision (c).

## Alternatives rejected

**A letter key (`o` for other, `c` for channel).** Unreachable: single
letters are gated on `!search.activeFocus` (`Menu.qml:201`) and the key
is needed while searching. Ungating one letter would make it untypable
in a query.

**A dialogue asking which channel.** Two channels exist and the
machine is on one of them, so "which" has exactly one answer. A picker
for a question with one answer is a keystroke pretending to be a
choice.

**Parsing `nixarchy-channel` output.** Prose, no machine-readable mode,
and -- the real objection -- it is a different program from the one
that will accept or refuse the request. Agreement with
`nixarchy-pkg-add` is the property being bought.

**Asking the adapter to evaluate the other channel for flags.** Slow,
needs the other nixpkgs present, and buys certainty about a package
the user has not committed to. The intent forbids it.

**Letting the writer refuse a same-channel request and showing that.**
The refusal at `nixarchy-pkg-add:112` is well written, but the intent
requires the key not be offered where it cannot work.

**Predicting the unfree scaffold case in the panel (option (a)).**
Rejected at gate 1: it needs `allowunfree` and `haspredicate` in the
state object, which is the writer's business leaking into the panel,
and a wrong prediction asks a question about nothing.

**Changing the writer's `[ -t 0 ]` path (option (b)).** Rejected at
gate 1 as an upstream change. Worth an issue against nixarchy on its
own merits; not this one.

## Risks

- **`SHIFT+RETURN` is invisible until documented.** Mitigated by
  `bin/nixarchy-pkg-keys`, which is the sheet `?` shows and where
  `SHIFT+A` is already listed. A key not on that sheet does not exist.
- **The arm/confirm pattern is new to this panel.** Nothing else here
  is two-press. The mitigation is that the armed state is *visible* --
  it is the message pane, not a hidden mode -- and that any other key
  disarms, so the failure mode is "nothing happened".
- **Duplicated channel parse can drift from the writer's.** Real, and
  accepted with its eyes open: the copy is small, it is pinned to a
  cited line, and the alternative (asking a different program) has the
  same drift risk without the guarantee of agreement. A verification
  step below compares the two on this machine.
- **Raising the message cap lets a long writer report push the list.**
  Bounded by scrolling rather than growth.
- **The scaffold case cannot be tested on a machine with
  `allowUnfree = true`**, which is the default and is this machine.
  Verifying that half needs a host with the option turned off, or a
  throwaway config; it must not be verified by turning off a real
  machine's licence policy.
- Hosts: no host is affected differently by the channel key. A host
  whose flake the parse cannot read (`custom`) gets the warning path
  rather than a name.

## Verification

1. **The parse agrees with the writer.** On this machine,
   `bin/nixarchy-pkg state | jq -r .channel` is `unstable`, matching
   `nixarchy channel` ("This machine follows: unstable") and the
   writer's own computation from `flake.nix:40`.
2. **The common path is unchanged.** RETURN on a free, default-channel
   search row queues it exactly as before, in one keystroke, with no
   armed state and no extra message.
3. **`SHIFT+RETURN` arms, and only arms.** The first press writes the
   message and queues nothing: `bin/nixarchy-pkg pending` count is
   unchanged.
4. **Any other key disarms.** Arm, press `DOWN`, then `RETURN`: the row
   is added to the default channel, not the other one. The marker
   written is `#@pkg`, not `#@pkg-other`.
5. **The second press adds from the other channel.** The line written
   to `apps.nix` is `pkgsOther.<attr>  #@pkg-other <attr>`, and the
   panel's row for it reports `channel: "other"`.
6. **The key is not offered for the channel already followed.** With
   `mine = unstable`, the armed message names `stable`; there is no
   path by which the panel sends `--unstable`.
7. **A `custom` flake warns rather than names.** With `NIXARCHY_FLAKE`
   pointed at a fixture whose `nixpkgs.url` the parse cannot read, the
   armed message says the channel could not be determined and the add
   still works.
8. **The writer's last line is readable.** A multi-package add's report
   is shown to its end rather than elided at three lines.
9. `tests/adapter.sh` passes, extended with a case for the new
   `channel` field.
10. Unverifiable here and stated as such: the scaffold path, which
    needs `allowUnfree = false`.
