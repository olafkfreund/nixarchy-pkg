---
status: approved
issue: 4
spec: spec/2026-09-18-4-channel-unfree.md
---

# Plan: channel selection, and the writer's last word

## The approved decisions, in full

Open question 1 was settled at gate 1 as **(c)**: the panel surfaces
the writer's report properly and lets the commented
`allowUnfreePredicate` scaffold stand. It does not predict the licence
policy (a) and does not change the writer (b). Evidence:
`nixarchy-pkg-add:12-18` bakes `allowunfree` and `haspredicate` in at
build time, `allowunfree=true` is the default, and `:338-341` calls the
opposite "the minority case (#497)".

That makes this issue two halves that depend on each other:

1. **`SHIFT+RETURN` on a search row adds from the other channel.** A
   letter key is impossible -- `Menu.qml:201` gates single letters on
   `!search.activeFocus` and the key is needed *while searching*.
   `Menu.qml:174-176` handles `Return` with no modifier test and no
   focus gate. `SHIFT+A` at `Menu.qml:186-189` already establishes
   `SHIFT+<key>` as the variant idiom.
2. **The message pane stops eliding at three lines.** Under (c) this
   *is* (c): "surface the report properly" is not satisfied by a
   report whose last line cannot be read.

Supporting: `cmd_state` gains `channel`, parsed by copying
`nixarchy-pkg-add:80-88` exactly -- deliberate duplication, because
agreement with the writer that acts on the request is the property
being bought, and `nixarchy-channel` is a different program that
answers only in prose (`:92`).

Arm-then-confirm in the existing message pane, not a dialogue: the
other channel costs a whole duplicate closure
(`nixarchy-doctor:707-711`, vlc at 1.5 GB).

Not done: no flags for the other channel (impossible --
`nixarchy-pkg-add:301-318` `continue`s before the flag block at `:331`,
and the probe at `:246` is the wrong nixpkgs); no moving an existing
package between channels (`:222` treats either marker as present); no
prediction of the licence policy.

## Steps

1. **`bin/nixarchy-pkg`** -- add a `machine_channel()` function beside
   `flake_base()` (near `:517`), copying the parse at
   `nixarchy-pkg-add:80-88` verbatim: read `nixpkgs.url` from
   `${NIXARCHY_FLAKE:-/etc/nixos}/flake.nix` with the same `sed -nE`,
   `case` it against `*nixos-unstable*` and `*nixos-[0-9][0-9].[0-9][0-9]*`,
   print `unstable`, `stable` or `custom`. A comment names the line it
   was copied from and why it is copied rather than asked.
   -> verify by `bin/nixarchy-pkg` sourcing cleanly and the function
   printing `unstable` on this machine.

2. **`bin/nixarchy-pkg` `cmd_state`** (`:651`) -- add
   `--arg channel "$(machine_channel)"` and `channel: $channel` to the
   emitted object, beside `files`.
   -> verify by `bin/nixarchy-pkg state | jq -r .channel` printing
   `unstable`, and `jq -e '.ok == true'` still passing.

3. **`PkgModel.qml`** -- add `property string armedChannel: ""`, and a
   function `addFromOtherChannel()`:
   - returns unless `indexTab && searching && tab === 2` and there is a
     row;
   - the other channel is `state.channel === "unstable" ? "stable" :
     state.channel === "stable" ? "unstable" : ""`;
   - if `armedChannel !== row.name`, set `armedChannel = row.name` and
     write `message` naming the package, the channel (or that it could
     not be determined when `state.channel` is `custom`), the closure
     cost, and that unfree and broken are **not known** for that
     channel. Queue nothing.
   - if already armed for this row, clear `armedChannel` and
     `write(["pkg", "add", "--" + other, row.name])`.
   -> verify by reading; the queue is untouched on the first call.

4. **`PkgModel.qml`** -- clear `armedChannel` wherever the cursor or
   the list moves: in `moveCursor`, `setTab`, `setQuery`, and at the
   top of `activate()`. Arming must not survive the row it was armed
   for.
   -> verify by test 4 below.

5. **`Menu.qml:174-176`** -- ahead of the plain `Key_Return` case, add
   a case for `Return`/`Enter` carrying `Qt.ShiftModifier` that calls
   `pkg.addFromOtherChannel()` and accepts the event. It must branch in
   `PkgModel`, **not** in `activateRow()` -- `activateRow`
   (`Menu.qml:332-340`) routes tab 3 into the option form first, and a
   channel key hung there would inherit that detour.
   -> verify by `SHIFT+RETURN` on the Options tab doing nothing rather
   than opening a form.

6. **`Card.qml:222-233`** -- the message pane: remove
   `maximumLineCount: 3` and `elide`, put the `Text` in a `Flickable`
   bounded to a maximum height so a long report scrolls instead of
   growing the card. The footer's queued count and caption are
   untouched.
   -> verify by test 8 below.

7. **`bin/nixarchy-pkg-keys`** -- in the `-- Act -` section after the
   `RETURN` line at `:35`, add:

       SHIFT + RETURN             -> Add a search result from the OTHER channel.
                                     It brings its own closure: the two channels
                                     share no store paths. Press it twice --
                                     once to see what it will do, once to do it

   -> verify by `?` in the panel showing it under Act.

8. **`README.md`** -- **this step's original condition was wrong.** It
   said "one line in the key list, if the README lists keys; otherwise
   no change". The README does not list keys -- `:33` says "`?` shows
   every key" -- so that branch would have made no change at all, while
   the approved intent (`:112`) requires that "`bin/nixarchy-pkg-keys`
   **and `README.md`** document the channel key". The intent outranks
   the plan, so the README gets a short "The other channel" section.

   Placed immediately after `:33` rather than in the feature bullet,
   because PR #12 (issue #11) rewrites that bullet; putting it there
   would manufacture a merge conflict for no gain.
   -> verify by `grep -n 'SHIFT+RETURN' README.md` returning the new
   section.

9. **`tests/adapter.sh`** -- in the `state` block after the
   `indexStale` check (`:47`), add:

       check "reports the machine channel" \
         jq -e '.channel | test("^(stable|unstable|custom)$")' <<<"$state"

   -> verify by `tests/adapter.sh` passing.

## Tests

    tests/adapter.sh

Expected: all pass, including the new channel case.

    bin/nixarchy-pkg state | jq -r .channel
    nixarchy channel

Expected: `unstable`, and "This machine follows: unstable". The two
must agree; a disagreement means the copied parse has drifted from the
writer's and blocks the change.

Manual, against a local build of the branch:

1. **The common path is unchanged.** RETURN on a free, default-channel
   search row queues it in one keystroke, no armed message.
2. **First `SHIFT+RETURN` arms only.** The message names the package,
   `stable`, the closure cost and that unfree and broken are not known
   for that channel. `bin/nixarchy-pkg pending` count is unchanged.
3. **Second `SHIFT+RETURN` adds it.** `apps.nix` gains
   `pkgsOther.<attr>  #@pkg-other <attr>`; the Selection row reports
   `channel: "other"`.
4. **Any other key disarms.** Arm, press `DOWN`, then `RETURN`: the
   line written is `#@pkg`, not `#@pkg-other`.
5. **`SHIFT+RETURN` does nothing on the Options tab** -- no form, no
   message.
6. **The channel already followed is never offered.** The armed
   message says `stable` on this machine; nothing sends `--unstable`.
7. **A `custom` flake warns rather than names.** With
   `NIXARCHY_FLAKE` pointed at a fixture whose `nixpkgs.url` the parse
   cannot read, the armed message says the channel could not be
   determined, and the add still works.
8. **The writer's last line is readable.** A multi-package add's report
   is shown to its end rather than cut at three lines.

Restore `~/.config/nixarchy/apps.nix` from a backup after tests 3 and
4, and confirm `pending` returns to 0.

Not verifiable on this machine, and not to be faked: the unfree
scaffold path needs `allowUnfree = false`, which is the minority case
and is not this host. Do not turn off a real machine's licence policy
to test it.

## Rollback

`git revert` the implementation commit. The adapter change is additive
(one new field, one new function) and no writer is touched, so a
reverted panel talks to the same writers in the same way. Any package
added from the other channel during testing is removed with
`nixarchy-pkg pkg remove <attr>`, which matches either marker
(`nixarchy-pkg-remove:46`), or by restoring the backed-up `apps.nix`.
