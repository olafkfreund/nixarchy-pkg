---
status: approved
issue: 4
author: olafkfreund
---

# Intent: channel selection and unfree acknowledgement when adding a package

## Problem

Adding a package from the panel sends one thing and only one thing.
`PkgModel.qml:227` is `write(["pkg", "add", row.name])` -- the row's
name, nothing else. Everything the row knows, and everything the
adapter can accept, is dropped on the way.

Two capabilities exist on either side of that line and meet nowhere.

**The channel.** `bin/nixarchy-pkg:323` takes `--stable` and
`--unstable` and forwards them to `nixarchy-pkg-add`. That flag is not
a convenience: the two channels share nothing in the store, so pinning
one package to the other channel is a deliberate per-package decision,
and the reason nixarchy exposes it at all. From the panel it cannot be
expressed. A package wanted from the other channel cannot be added
here -- not added wrongly, not added with a warning, simply not added.
The terminal round trip the plugin exists to remove is the only way.

**The unfree refusal.** On a host whose licence policy forbids unfree,
`nixarchy-pkg-add` refuses. That refusal is surfaced -- `run_writer`
captures stderr precisely so a refusal reads as an answer rather than
a crash -- so nothing is silent and nothing is a lie. But it is a dead
end. The panel shows the reason and offers no way to answer it, and
the package is one the person deliberately chose and can see marked
`unfree` on its own row, drawn by `Card.qml:167`.

Nothing currently promises otherwise. The key sheet and the README are
both silent on channel selection, so this is a gap rather than a broken
promise -- which is why it was split out of #2 rather than fixed in it.

One hazard is already in the code and shapes any answer:
`Card.qml:255` -- a stale index carries no `unfree` or `broken` flags
at all, so every package on it reads as free. An acknowledgement step
that trusts the row's flags would, on a stale index, never ask. The
panel already says "index stale -- R to rebuild" in that state; an
acknowledgement flow has to mean it.

## Proposed outcome

RETURN on a search row keeps doing exactly what it does now, and the
two decisions the panel cannot currently express each get a way to be
made -- explicitly, on the row, before the change is queued.

Concretely, when this is done:

- A package can be added from the non-default channel from the panel,
  by a key on the search row that asks which channel rather than by a
  mode or a setting.
- An `unfree` package is acknowledged before it is queued, and the
  acknowledgement is what the person is actually agreeing to, named.
- The acknowledgement is not offered on evidence the panel does not
  have: on a stale index it says so instead of silently not asking.
- A refusal from `nixarchy-pkg-add` still reads as the answer it is;
  the acknowledgement does not become a way to talk the writer out of
  a policy it enforces for a reason.
- The key sheet and the README stop being silent about channels.

Afterwards, what the adapter can already do is reachable from the
panel, and the unfree refusal has somewhere to go.

## Affected users and systems

- `PkgModel.qml` -- `activate()` and whatever the new key reaches.
- `Card.qml` -- the search row, where the flags are already drawn and
  where an acknowledgement has to appear.
- `Menu.qml` -- the key table around lines 187-211, and the `?` sheet.
- `README.md` -- the key documentation.
- Not `bin/nixarchy-pkg`: `pkg add` already takes what is needed. If
  this task grows a change there, that is a finding worth stating, not
  a quiet edit.
- Not the writers in nixarchy. The licence policy is theirs and stays
  theirs.

## Constraints

- **Must not make RETURN riskier.** RETURN on a search row is the
  common path and adding a free package from the default channel must
  stay one keystroke.
- **Must not acknowledge on absent evidence.** A stale index reads as
  all-free (`Card.qml:255`). Never treat "no flag" as "free".
- **Must not defeat the policy.** An acknowledgement answers a question
  the panel asks. It does not override a writer's refusal, and if the
  host forbids unfree the answer stays no.
- **Must not add a mode.** A channel that persists between rows, or a
  panel-wide "allow unfree" toggle, turns a per-package decision into
  a setting that is wrong the next time it is used.
- **Must keep the writers the source of truth.** The panel is told the
  new state; it does not predict it. That does not change here.
- **Must stay inside the existing key discipline.** Keys are single,
  documented, and listed on `?`. A new one joins that table or it does
  not exist.
- No new dependency, and nothing built until the existing apply.

## Open questions

1. **One key or two?** Channel selection and unfree acknowledgement
   are separate decisions that happen to land on the same row. One key
   that opens a small confirm covering both is fewer keys and one flow;
   two keys is simpler per key and more to remember. This is the main
   shape decision.

2. **What does the acknowledgement actually say?** "This package is
   unfree, add it anyway" is a click-through and teaches nothing.
   Naming the licence would be meaningful, but the index carries a flag,
   not a licence name -- so this may be a question about what the index
   stores, which would reach nixarchy.

3. **Is the acknowledgement even reachable?** If the host policy
   forbids unfree, `nixarchy-pkg-add` refuses regardless of what the
   panel asked. Then the honest flow is not an acknowledgement but a
   better refusal -- saying which setting forbids it and where. Whether
   there is a case where acknowledging changes the outcome needs
   settling before designing a dialogue for it.

4. **Does `broken` want the same treatment?** It is drawn beside
   `unfree` on the same row and is arguably the more dangerous flag.
   Same flow, different flow, or explicitly out of scope.

5. **Does channel selection belong on add only?** A package already in
   the selection cannot be moved between channels from the panel
   either. Whether this task covers that, or only the add path the
   issue names.
