---
status: approved
issue: 45
spec: spec/2026-09-24-45-summary-width.md
---

# Plan: a row's summary elides where the row actually ends

## Approved decisions, carried over

Self-contained: everything needed to implement this is below.

**Why:** `Card.qml:205` sizes the summary by subtracting a constant that is
right for no arrangement of the row.

```qml
width: parent.width - name.width - Style.font.heading - Style.space(40)
```

The `Row` (`:140`) is anchored **with** `leftMargin`/`rightMargin`, so
`parent.width` already excludes the margins and subtracting them again
double-counts. With N flags of widths `Fi`, children number 3+N and gaps
(2+N):

```
needed = name.width + Style.font.heading + (2+N)*space(10) + sum(Fi)
actual = name.width + Style.font.heading + 4*space(10)
actual - needed = (2 - N)*space(10) - sum(Fi)
```

| flags | result |
| ----- | ------ |
| 0 | `+space(20)` -- 20px narrower than it could be; elides slightly early, harmless |
| 1 | `space(10) - F1` -- negative for any real flag, so the Text is wider than its row |
| 2+ | worse |

When the Text is wider than the row, `elide: Text.ElideRight` computes its
ellipsis against a width the row does not have and `ListView.clip` (`:117`)
cuts the result at the real edge -- the text stops mid-word instead of at a
recognisable ellipsis. `unfree` and `broken` are ordinary on the Apps tab.

**The issue's other claim was corrected, not implemented.** #45 says the
width can go negative on a flake row and the summary disappears. It can go
negative, but only on `modelData.kind !== undefined` rows (`:174`), and
those are built at `PkgModel.qml:110-136` carrying **only `kind` and
`label`** -- the summary's `summary || note || type || line || category ||
""` is `""` there. Nothing disappears because nothing is drawn.

**Decisions:**

1. **Wrap only the flags `Repeater`**, and derive the width from it. The
   tidier design -- one `lead` Row around glyph, name and flags, needing no
   constants -- **is a binding loop**: `name.width` is
   `Math.min(implicitWidth, parent.width * 0.42)`, so making `parent` an
   inner Row whose width sums its children makes `name.width` depend on
   itself. `Card.qml:25-29` already records that exact failure for
   `bodyHeight`.
2. **Not `RowLayout`.** The better end state, and it repositions all four
   children in a file with no behavioural tests, verified by eye. Follow-up
   if this row is touched again.
3. **Keep the clamp.** Under the old expression a negative value was only
   reachable on rows that draw no summary; under the new one it is ordinary
   arithmetic on real inputs, because `name.width` is still capped at
   `parent.width` on `kind` rows.

## Steps

1. `Card.qml:188`: wrap the flags `Repeater` in a measurable `Row`, leaving
   the `Repeater` and its delegate **unchanged**.

   ```qml
   // Wrapped so the summary below can subtract what the flags actually
   // take. `visible` is load-bearing, not cosmetic: a Row ignores an
   // invisible child when positioning, so with no flags the outer row is
   // back to three children and two gaps, which is what the `? 3 : 2`
   // below counts (#45).
   //
   // `modelData` here is the ROW, not a flag: the Repeater's delegate
   // declares `required property string modelData`, which shadows it one
   // level further in. Do not move this binding inside.
   Row {
     id: flags
     anchors.verticalCenter: parent.verticalCenter
     spacing: Style.space(10)
     visible: (modelData.flags || []).length > 0

     Repeater {
       ... unchanged ...
     }
   }
   ```

   -> verify by check 2 (`qmllint`) and check 3 (no binding loop).

2. `Card.qml:205`: derive the width instead of guessing it.

   ```qml
   // Every term is something on this row: the name, the state glyph, the
   // flags, and one gap per boundary between them. The old Style.space(40)
   // was right for no arrangement of this row -- 20px too generous with no
   // flags, too mean with any -- because the Row's anchors already exclude
   // its margins (#45).
   width: Math.max(0, parent.width - name.width - Style.font.heading
                      - flags.width
                      - Style.space(10) * (flags.visible ? 3 : 2))
   ```

   -> verify by check 4.

## Tests

`nix flake check -L` and `qmllint` locally. Anything live on **razer**,
never p620, and with **no text-size change** -- `omarchy display text size`
segfaults quickshell on this host (nixarchy#847).

1. `nix flake check -L` passes, including `qml-syntax` and
   `no-text-multiplier`.
2. `qmllint Card.qml` reports no syntax error.
3. **No binding loop.** After the plugin loads, the shell journal has no
   `Binding loop detected` mentioning `Card.qml`. This is the specific
   failure the rejected `lead` design would have caused, so it is checked
   explicitly rather than assumed absent.
4. By eye on razer, with the #38 screenshots as the before-image:

   | row | expect |
   | --- | ------ |
   | Apps row, one flag (`unfree`), long summary | ends in a visible ellipsis, not a word cut at the list edge |
   | Apps row, two or more flags | same |
   | row with no flags | unchanged or very slightly wider, still elides |
   | Flakes row (`kind`, no summary) | label drawn as before -- what the corrected reading predicts |

5. `tests/adapter.sh` on razer still passes: it exercises
   `bin/nixarchy-pkg`, untouched here, so it proves nothing broke beside
   this.

## Verification results

Steps 1 and 2 applied as written. No design change.

| check | result |
| ----- | ------ |
| 1. `nix flake check -L` | **passes**, including `qml-syntax` and `no-text-multiplier` |
| 2. `qmllint Card.qml` | no syntax error |
| 3. no binding loop for `Card.qml` | **passes** -- 0 lines, and no warning at all from any of the four files |
| 4. the rows, by eye | **passes** -- N=0, N=1 and N=2 all checked |
| 5. `tests/adapter.sh` | **passes** |

Checks 3-5 need razer's desktop. Another Claude session has been working on
the same machine today, and we collided twice -- once badly enough to
invalidate a verification run for #43 and to leave a wrong `shell.toml` in
place. I told that session I would ask before using razer again rather than
announce it afterwards, so this is held until it answers. razer was quiet
when checked read-only (background and bar only, one shell generation, the
plugin symlink intact), but "looks free" is not the same as "was asked".

The other session handed razer over explicitly, so checks 3-5 ran after all.

**Check 3, the one that could not be inferred:** zero `Binding loop
detected` lines mentioning `Card.qml`, and no warning from any of the four
QML files. That is the exact failure the rejected `lead` Row design would
have produced.

**Check 4 needed correcting before it could be run.** The Apps tab shows
"unfree" in its rows, so it looked like the N>=1 case. It is not: catalogue
rows carry `["category","enabled","id","label","line","note","settings"]`
and **no `flags` key at all** -- that "unfree" is part of the note text.
Only *search* rows carry flags (`steam` -> `["unfree","curated:steam"]`).
So the plan's "Apps row, one flag" case does not exist, and the flagged
cases had to be reached through a search on the Selection tab.

Checked, at base-size 12:

- **N=0** (Apps tab). The summary is ~20px wider than before -- `progr...`
  became `program...` against the #38 before-image. That is exactly the
  `+space(20)` the corrected arithmetic predicted for the no-flag case, so
  the observation confirms the model rather than merely looking fine.
- **N=1** (`steamcmd unfree ...`, `steam-unwrapped unfree ...`) and **N=2**
  (`steam unfree curated:steam Digital distribution platform`): flags and
  summary sit in sequence with even gaps, nothing overlapping or cut.

**One row was nearly recorded as a defect.** `steam-play-none` ends
"...`programs.steam.ex" with no ellipsis, which looked like the clipping
this task exists to fix -- on a row with no flags, where the new expression
is exact. Cropping it showed a gap between the text and the border, so
nothing was being clipped, and the adapter confirmed it: its own output ends
at that string. The summary is truncated in the index, upstream of any
rendering. Layout was never involved.

razer was returned to baseline afterwards: plugin symlink restored, no
`shell.toml`, text size 12 default, one shell generation, no leftover layer.

## Rollback

One commit touching `Card.qml` only. No adapter change, no config format,
no JSON contract, no `flake.nix` change. `git revert` restores the previous
behaviour with nothing to migrate.

If the paired `flags.visible` and `? 3 : 2` prove fragile -- they encode the
same fact twice, which the spec records as the accepted risk -- the recorded
successor is the `RowLayout` conversion, which removes the arithmetic
entirely.
