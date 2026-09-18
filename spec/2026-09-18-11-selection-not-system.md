---
status: approved
issue: 11
intent: intent/2026-09-18-11-selection-not-system.md
---

# Spec: the Packages tab shows a selection, and should say so

## Design

Four changes, none of which adds a source of rows, evaluates anything,
or touches the marker contract.

### 1. The tab is renamed `Selection`

`PkgModel.qml:28` becomes
`["Apps", "Services", "Selection", "Options", "Drafts"]`.

`Packages` is the overclaim. Beside `Apps`, `Services`, `Options` and
`Drafts` -- all of which name a *kind of thing the panel manages* --
`Packages` is the only label that reads as a report on the machine.
`Selection` names the same thing the writers already name:
`nixarchy-pkg-remove:68` says "removed from your selection",
`:69` says "N extra package(s) still selected". The panel adopts the
vocabulary its own backend has used all along, rather than inventing a
third.

It is also one character shorter than `Packages`, so the tab strip
(`Card.qml:47-77`, a `Row` of `implicitWidth` labels) does not grow.

### 2. A persistent subtitle under the tab strip, on this tab only

This is the load-bearing change, and reading the code moved it from
"maybe" to "required".

The intent proposed carrying the correction in the empty state. That
does not work. `Card.qml:188-197` shows its text only when
`list.count === 0`, and on the machine in the intent `list.count` is 1
-- so nothing is shown. Worse, Packages is an `indexTab`
(`PkgModel.qml:68`), so its genuinely-empty text is currently "type to
search nixpkgs", which says nothing about a selection either.

The confusion is not caused by an empty list. It is caused by a *short*
list that looks like a failed scan. A correction that only appears at
zero rows misses precisely the case it exists for.

So: one line of caption text between the tab strip and the list, drawn
only when `tab === 2` and not searching:

    packages nixarchy manages -- not everything installed

Always visible on that tab, whatever the row count. It is the first
thing under the tab the user just selected, at the moment they are
counting rows and finding too few.

### 3. The empty state stops advertising search as the only answer

`Card.qml:195-197` gains a Selection-specific branch. When the tab is
Packages, not searching and empty:

    no packages in your nixarchy selection yet -- / to search nixpkgs

rather than the bare "type to search nixpkgs". The existing `indexTab`
branch continues to serve Options unchanged.

### 4. `README.md` states the read boundary beside the write boundary

The "What it is not" section already ends with the write boundary
(`README.md:44-45`: "It writes to `~/.config/nixarchy/apps.nix` and
`services.nix` and nowhere else"). It gains the matching sentence about
what is listed: the Selection tab shows the packages nixarchy manages,
packages declared elsewhere in your own configuration are neither
listed nor managed, and that boundary is what makes removing nixarchy
clean -- the selection hangs off one import and leaves nothing behind.

`bin/nixarchy-pkg-keys:36` reads "RETURN -> Edit an option's value, or
add a search result", which stays true and needs no change. No other
line in the sheet names the tab.

### What is deliberately not done

No collision detection. The panel cannot know that `azure-cli` is also
declared at `modules/cloud/packages.nix:37` without evaluating the
user's configuration, which the intent rules out. The wording above is
true whether or not a collision exists, which is why it can be said
without the knowledge.

No change to `Apps` or `Services`. They draw from the same selection
files via `rows_tsv`, so the same technicality applies -- but they are
catalogue-backed: the row exists whether or not it is enabled, so the
list is never short and never reads as a failed scan. Correcting a
misreading that does not occur costs two more labels and buys nothing.

No change to the three-line message cap at `Card.qml:228`. It truncates
every writer's output, not this one, and belongs to #4 or to an issue
of its own.

## Alternatives rejected

**Leave the tab as `Packages` and carry it all in the empty state.**
The cheapest option and the one the intent leaned toward. Rejected on
evidence: `Card.qml:188` gates on `list.count === 0`, which is false in
the reported case. It would ship a fix that does not fire.

**A longer, fully explicit tab name (`nixarchy packages`, `Managed`).**
`Managed` is ambiguous about by-what. `nixarchy packages` repeats a
word already on the panel and widens the `Row`. `Selection` is exact,
matches the writers, and fits.

**List the user's own packages, read-only, from `nix eval`.** Ruled out
in the approved intent: 3.3s warm against a panel that opens instantly,
rows with no file and no line that no key could act on, and a host key
that `flake_base:517-522` can only guess from `uname -n`. Recorded here
because it is the request a reader will arrive with.

**Warn on add when the package is already declared elsewhere.** Needs
the same evaluation. Rejected with it.

**Documentation only.** The intent's own finding: a README cannot fix a
panel that reports a removal which did not happen. It is necessary and
not sufficient.

## Risks

- **A renamed tab is a renamed tab.** Anyone with `Packages` in muscle
  memory, and any screenshot or write-up referring to it, is now
  slightly wrong. The tab keeps its position (third) and its key
  (`h`/`l`, arrows, TAB are positional, `Menu.qml:203-206`), so nothing
  breaks; only prose ages. Low, and the alternative is keeping a label
  that is untrue.
- **The subtitle costs vertical space** on a panel with a fixed row
  height, so one fewer row is visible on the Selection tab. It is a
  caption-sized line, and the trade is one row against the misreading
  the whole issue is about.
- **`Selection` may read as "the row I have selected"** rather than
  "the set nixarchy manages" -- the word is overloaded in a list UI
  where a cursor also selects. The subtitle immediately under it
  disambiguates, which is another reason the two changes ship together
  rather than separately.
- No host is affected differently: this changes no behaviour, no file
  the panel writes and nothing that is built. An ISO-installed machine
  sees the same accurate wording, where it is merely accurate rather
  than corrective.

## Verification

Behaviour must be unchanged, so verification is mostly that nothing
moved.

1. **Adapter untouched.** `tests/adapter.sh` passes unchanged, and the
   diff contains no change under `bin/`. The adapter emits the same
   JSON before and after: `bin/nixarchy-pkg state` output is identical.
2. **Rows unchanged.** With the machine's real selection, the Selection
   tab lists exactly what the Packages tab listed -- on the host in the
   intent, `azure-cli` and nothing else.
3. **The subtitle is present at a non-zero row count.** This is the
   case the empty state could not reach and the reason the change
   exists; a screenshot of the Selection tab with one row must carry
   the line.
4. **The subtitle is absent while searching**, so a search result list
   is not captioned as a selection, and absent on the other four tabs.
5. **The empty state.** With an empty `#@pkgs` block, the Selection tab
   reads "no packages in your nixarchy selection yet"; the Options tab
   still reads "type to search nixpkgs".
6. **Keys unaffected.** `h`/`l`, arrows and TAB reach the third tab as
   before; `?` still lists every key and contradicts nothing.
7. **README.** The read boundary appears beside the write boundary, and
   no sentence in it claims the panel reports installed software.
