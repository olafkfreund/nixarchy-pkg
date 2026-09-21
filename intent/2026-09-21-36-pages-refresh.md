---
status: draft
issue: 36
author: olafkfreund
---

# Intent: fresh screenshots, and a front page that stands out

## Problem

1. **The pictures show a menu that no longer exists.** Every image in
   `docs/img/` was captured on 18 Sep, and `tour.webm`/`tour.gif` on
   20 Sep. Since then #31–#35 changed what is on screen: the option form
   offers what it can write and shows the current value (#33), the apply
   log streams as plain text and shows how it ended (#32), flake inputs
   are named from the repo and confirmed (#34), tabs are clickable and the
   Options copy is fixed (#35). A reader who installs it sees something
   different from the site.
2. **Some things have no picture at all.** Flakes, the apply log, the
   Drafts tab and the confirm-before-rebuild prompt are not shown anywhere.
3. **The front page undersells it.** `docs/index.md` is 32 lines of
   centred prose with one video. It does not show, at a glance, what the
   menu does. The Nixi page (https://olafkfreund.github.io/nixi-nixarchy/)
   does this well: a big demo video at the top, then one real session told
   as numbered scenes, each a screenshot beside a short explanation, then
   a grid of the remaining shots.

## Proposed outcome

- Every screenshot and the tour on the site show the current release, taken
  on a real machine, with nothing applied (same rule as the existing
  showcase: selection files byte-identical before and after).
- Flakes, the apply log and Drafts each have at least one shot.
- The home page is a story: hero tour video, then numbered scenes (find a
  package → queue it → set an option → see what's waiting → apply → roll
  back), then a grid of the other shots, then links to the manual and
  source. It reads well on a phone and in dark mode.
- The manual pages that reference images still resolve (the Pages CI image
  check stays green).

## Affected users and systems

- `docs/index.md`, `docs/_layouts/home.html`, `docs/assets/style.css`.
- `docs/img/*` (replaced and added) and the `assets/showcase/` copies used
  by the README.
- `tools/record-tour.sh` if the tour's story needs the new tabs.
- razer: every capture runs there, never locally.

## Constraints

- Captures come from razer over ssh; nothing is applied during capture.
- Keep the site's look family with nixarchy's docs (JetBrains Mono, logo);
  borrow Nixi's layout, not its palette wholesale.
- No theme gem or JS framework: the layouts and `style.css` stay the whole
  site, as `_config.yml` promises.
- Manual pages keep their layout; only the home page is redesigned.
- Images stay reasonably small (the current tour.gif is 2.1 MB; don't grow
  the page much past that).

## Open questions

1. **Re-cut the tour too, or only the stills?** The tour is 20 Sep and
   shows Flakes before #34. Re-cutting uses `tools/record-tour.sh`, which
   needs ai-mirror key input to layer-shell surfaces. The #30 intent notes
   that ai-mirror 2.0.0 broke exactly this. If it's still broken, the
   stills can be done and the tour kept.
2. **Whose story?** Nixi uses a persona ("Sam's first session"). Do the
   same here (e.g. "I want lazygit and I don't want to open an editor",
   the tour's existing story), or plain feature sections?
3. **README too?** Refresh `assets/showcase/` and the README screenshot in
   the same task, or only the Pages site?
