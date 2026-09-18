---
status: approved
issue: 4
author: olafkfreund
---

# Intent: channel selection when adding a package, and the unfree consent the panel currently gives on the user's behalf

## Problem

Adding a package from the panel sends one thing and only one thing.
`PkgModel.qml:227` is `write(["pkg", "add", row.name])` -- the row's
name, nothing else. Everything the row knows, and everything the
adapter accepts, is dropped on the way.

An earlier draft of this intent said the writer *refuses* an unfree
package under a forbidding policy, and that the panel needed a way to
answer that refusal. That is wrong, and reading the installed writer
rather than trusting the issue text shows three different problems in
its place.

### 1. The channel cannot be chosen

`bin/nixarchy-pkg:323` takes `--stable` and `--unstable` and forwards
them. The flag is not a convenience: the two channels share no store
paths, so pinning one package to the other channel is a deliberate
per-package decision costing a whole extra closure, and the reason
nixarchy exposes it. From the panel it cannot be expressed at all.

Two writer behaviours bound what a channel key can mean, both
verified in `nixarchy-pkg-add`:

- **`:112`** -- asking for the channel the machine already follows
  exits 1 and says so. The panel must not offer it.
- **`:222`** -- `grep -qE "#@pkg(-other)? <attr>$"` matches *either*
  marker, so a package already present on either channel reports
  `present` and is skipped. **Re-adding cannot move a package between
  channels.** This is the add path or nothing.

### 2. Choosing the other channel silently drops the safety warnings

This is the finding that should shape the design. In
`nixarchy-pkg-add:301-318`, the other-channel branch writes
`pkgsOther.<attr>  #@pkg-other <attr>` and then `continue`s -- before
the unfree and broken flag block at `:331-348`. An other-channel add
therefore reports **no `unfree` and no `broken` flag at all**, however
unfree or broken the package is.

Nor could the current flags substitute. The probe at `:246` is
`import $nixpkgs`, the system's own nixpkgs -- the channel the machine
already follows, which for an other-channel request is by definition
the wrong one. A row's flags describe a package the user is not
asking for.

So in the writer as it stands, channel selection and the unfree and
broken warnings are mutually exclusive. A panel key that offers the
other channel offers, silently, the unwarned path.

### 3. The panel consents to an unfree grant on the user's behalf

The writer never refuses. It writes the package, then reports one of
three states (`:332-346`): `allowUnfree = true` -- fine here; a
predicate exists -- allowed only if it accepts this package;
`allowUnfree = false` -- the rebuild will refuse it, and the pname is
collected.

For that last case `offer_unfree_grant` (`:399`) writes a *commented*
`allowUnfreePredicate` naming just those packages, marked
`#@unfree-allow`, or grows an existing list in place. The design is
careful and the comment says why: the narrow grant, in the user's own
file, commented, "because changing licence policy is the user's line
to uncomment."

The consent for it is gated on `:417`, `if [ -t 0 ]`. The panel runs
the writer with no tty, so the branch is skipped and the scaffold is
written **without anyone being asked**. A licence-policy edit lands in
`apps.nix` on the say-so of a keystroke that meant "add this package".

The notice that would reveal it is the writer's second line of output.
`run_writer` does capture it -- `out=$("$@" 2>&1)` at
`bin/nixarchy-pkg:264` -- and it reaches the panel as `message`. But
`Card.qml:228` draws the message with `maximumLineCount: 3` and
`elide`, and the report is already a wrapped table row per package. On
a multi-package add the scaffold notice is off the bottom.

### What is not wrong

The key sheet and the README are silent on channel selection, so
nothing promises what is missing. And a refusal, when one happens, is
shown rather than swallowed: `run_writer` captures stderr precisely so
it reads as an answer rather than a crash. The gap is consent and
channel, not honesty.

## Proposed outcome

RETURN on a free, default-channel search row keeps doing exactly what
it does today, one keystroke. Around that:

- A package can be added from the other channel from the panel, by a
  key on the search row. The choice is per package, not a mode.
- That key is not offered when the machine already follows the channel
  in question (`writer:112`), rather than offered and then refused.
- Because the other-channel path reports no flags and the row's flags
  describe the wrong channel, choosing the other channel says plainly
  that the licence and broken status are not known for it -- rather
  than showing flags that are about a different package.
- An add that will cause a licence-policy scaffold says so before it
  happens, and the person agrees to it. The panel stops answering
  `[ -t 0 ]`'s question by not being a terminal.
- The writer's last word is readable when it matters, rather than
  elided at three lines.
- `bin/nixarchy-pkg-keys` and `README.md` document the channel key.

Afterwards, the panel can express the per-package channel decision the
adapter already accepts, and no longer edits licence policy without
being asked.

## Affected users and systems

- `PkgModel.qml` -- `activate()` at `:223`, and whatever a channel key
  reaches. Note `Menu.qml:174-177` reaches activation from RETURN
  *and* SPACE, and `Card.qml:110` from a click; a gate on one of three
  is not a gate.
- `Card.qml` -- the search row and its flags (`:155-175`), and the
  message pane's three-line cap (`:222-233`).
- `Menu.qml` -- the key table at `:199-211`.
- `bin/nixarchy-pkg-keys:33-41` -- the actual `?` sheet, which an
  earlier draft of this intent missed.
- `README.md`.
- `bin/nixarchy-pkg` only if the state object must carry a fact it
  does not carry today (see open question 2).
- Not the writers in nixarchy: the licence policy is theirs and stays
  theirs. If this task concludes a writer must change, that is a
  finding to report upstream, not an edit to make here.

## Constraints

- **Must not make the common path riskier or slower.** A free package
  from the default channel stays one keystroke.
- **Must gate every route to activation**, not just RETURN.
- **Must not claim knowledge it does not have.** The other-channel
  path yields no flags and the probe is against the wrong nixpkgs.
  Absence of a flag is not evidence of freeness -- also true of a
  stale index, where `bin/nixarchy-pkg:70-83` records that an index
  built before nixarchy #493 "reports every package as free" and that
  "the panel must be able to say so rather than quietly dropping the
  warning".
- **Must not defeat or reimplement the licence policy.** The aim is
  that the user is asked, not that the answer changes.
- **Must not add a mode.** A channel that persists between rows, or a
  panel-wide allow-unfree toggle, turns a per-package decision into a
  setting that is wrong the next time it is used.
- **Must keep the writers the source of truth.** The panel is told the
  new state; it does not predict it.
- **Must stay inside the existing key discipline.** Letters act only
  outside search focus; a new key joins `bin/nixarchy-pkg-keys` or it
  does not exist.
- No new dependency; nothing built until the existing apply.

## Open questions

1. **Can the scaffold consent be asked at all from here?** Three
   shapes, and this is the main decision:
   (a) the panel predicts the case and asks first -- but predicting
   requires knowing `allowUnfree` and the predicate, which is the
   writer's knowledge, and a panel that predicts wrongly asks a
   question about nothing;
   (b) the panel stops the scaffold happening unasked by making the
   writer's non-tty path not fire, which means a writer change and so
   an upstream issue;
   (c) the panel shows the writer's report properly and lets the
   scaffold stand, on the grounds that a commented line is inert.
   (c) is much the smallest and may be enough -- a commented line
   changes no behaviour until uncommented. Whether "inert" is an
   adequate answer to "edited the licence policy without asking" is
   the judgement.

2. **Does the panel need to know the licence policy at all?** If the
   answer to 1 is (a), the state object must carry `allowUnfree` and
   `haspredicate`, which it does not today. That is adapter work and
   arguably the writer's business leaking into the panel.

3. **What does the channel key do about the missing flags?** Say "not
   known for that channel" and proceed, or evaluate the other channel
   first and be slow and possibly offline, or refuse the other channel
   for a package flagged unfree or broken on the channel we can see.
   The first is honest and cheap; the third is over-cautious using
   evidence about the wrong package.

4. **Does `broken` want treatment too?** It is drawn beside `unfree`
   on the same row, is arguably the more dangerous flag, and is
   dropped by the same `continue` at `:318`. Same flow, or explicitly
   out of scope.

5. **Is the three-line message cap a separate issue?** It also elides
   any other writer's last word, so fixing it here fixes something
   wider than #4. Split it out, or take it as part of this.
