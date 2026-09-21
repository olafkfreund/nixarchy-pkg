---
status: approved
issue: 36
intent: intent/2026-09-21-36-pages-refresh.md
---

# Spec: fresh screenshots, and a front page that stands out

## Answers to the intent's open questions

The intent was approved without answers, so these are the defaults this spec
takes. Say so at review if any is wrong.

1. **Re-cut the tour too: yes.** The worry was ai-mirror, but
   `tools/record-tour.sh` does not use it. It drives the panel with ydotool
   over uinput (`record-tour.sh:35`). Checked on razer today: every tool it
   needs is on PATH and `ydotool key 0:0` reaches ydotoold.
2. **Story: the tour's own.** "I want lazygit, I don't know if it's in
   nixpkgs, and I don't want to open an editor" (`record-tour.sh`, above
   `SCENES`). It is written in the first person with no invented persona, so
   the page tells the same story as the video playing above it.
3. **README too: yes.** `assets/showcase/` is the same set of shots (plus
   `10-keys.png`), so its images are replaced from the same capture run and
   cost nothing more.

## Design

### 1. Capture on razer, from main, not from razer's pinned plugin

razer's installed plugin is **older than main**. It is a Home Manager symlink
to `/nix/store/72fi…-nixarchy-pkg`, built from the `nixarchy-pkg` flake input
in `~/.config/nixos`, and its `Menu.qml` lacks #31's `focusList()`. Shots taken
on it would show pre-#31 behaviour.

So, for the capture only:

- push this branch; on razer `nix build github:olafkfreund/nixarchy-pkg/docs/36-pages-refresh`;
- note the current symlink target, then point
  `~/.config/omarchy/plugins/nixarchy.pkg` at the new build, and
  `omarchy-restart-shell`;
- afterwards put the original symlink target back and restart the shell again.

razer's NixOS config and flake lock are **not** touched. Bumping the input
there is a separate change in another repo, and the next Home Manager
activation would restore the pinned plugin anyway.

`hyprctl` over a bare ssh session has no instance to talk to. The capture
commands export `HYPRLAND_INSTANCE_SIGNATURE` from `/run/user/$UID/hypr`
first.

### 2. Stills: a `--stills` mode on the existing recorder

`record-tour.sh --dry` already does almost all of this. It backs up the
selection files, restarts the shell, drives a scene list with ydotool, grabs
one grim still per scene from the card's rectangle, and restores the files on
exit. `--stills` is the same function run over a second scene list, `STILLS`,
writing named PNGs into `docs/img/`. That is the existing `dry()` loop given
a list and an output name per row, not a second driver.

`STILLS` covers everything the manual already shows (keeping the names
`01`–`11`, so no manual link changes), plus the new ones:

| file | shows |
| --- | --- |
| `12-drafts.png` | the Drafts tab |
| `13-flakes.png` | the Flakes tab with an input and its modules listed |
| `14-flake-add-confirm.png` | #34's "named from the repo, confirm" prompt (Escape, never Return) |
| `15-apply-confirm.png` | #31's ask-twice-before-rebuild prompt (Escape, never confirmed) |
| `16-apply-log.png` | the streamed apply log and how it ended (#32); see Risks |
| `08`, `09` | re-taken: the option form now shows the current value (#33) |

The option-form scenes run **last**. `record-tour.sh:65-72` records that,
before #31, the form ate every Escape and the tab could never be left. #31
may have fixed that. If `--dry` shows the form can now be left, the order
doesn't matter. If it can't, it stays last and a note says why.

### 3. The tour

The same script and the same 60-second limit. The only story change is that
Flakes now names its input (#34), so that scene's keys are rechecked with
`--dry` before recording. `tour.webm` and `tour.gif` are overwritten in place.

### 4. The home page

The layout follows Nixi's page. The look is this site's own: dark, JetBrains
Mono, the wordmark, the `--accent` green.

- **Hero:** masthead (logo and tagline, unchanged), a one-sentence lede, then
  the tour video full content width (max 980px) with `controls`, the gif as
  fallback and a poster frame. Below it, a row of links: Install · Manual ·
  Source.
- **"Getting lazygit without opening an editor":** six numbered scenes, each
  a `<section class="scene">` holding a screenshot beside 2–4 sentences:
  1. Find it: search nixpkgs on Selection (`06`)
  2. Queue it: the row flagged, unfree/broken explained (`05`)
  3. Set an option: the form built from the option's type, showing what's set (`08`)
  4. See what's waiting: Drafts (`12`)
  5. Apply, asked twice: confirm prompt, then the log (`15`, `16`)
  6. Roll back: it's a generation. Text only, linking the manual's
     Applying page.
- **"Everything else":** a three-column grid of figures with captions: Apps
  (`01`), Services (`03`), Flakes (`13`), flake confirm (`14`), bar widget
  (`11`), filtering (`02`).
- **"What it writes":** the existing two paragraphs (one marked line per
  change, through nixarchy's own scripts; it manages a selection), kept as they are.
- **Footer:** Source · nixarchy's manual.

Files:

- `docs/_layouts/home.html`: widen `main`, add the video element and a
  poster, and load `home.css`.
- `docs/index.md`: the content above. The scenes and grid are raw HTML
  inside the markdown, as the current `<video>` already is.
- `docs/assets/home.css`: **new**, loaded only by the home layout.
  `style.css` stays untouched, because its header promises it is
  byte-identical to nixarchy's except one marked value, and home-only rules
  would break that.
- `docs/img/tour-poster.png`: the tour's first scene frame, which
  `--frames` already extracts.

Grid and scene layout use CSS grid and drop to one column below 760px, with
16px gutters. Images get `loading="lazy"`, width/height attributes (no layout
shift) and real alt text.

Dark only, like the manual. The site has no light theme and this page does
not introduce one.

### 5. README

The files in `assets/showcase/*.png` are replaced from the same run, and
`assets/showcase/README.md` gets sections for 12–16. `assets/screenshot.png`
(the README's hero image) is replaced with the new `01-apps.png`.

## Alternatives rejected

- **Bump `nixarchy-pkg` in razer's NixOS flake and rebuild, then capture.**
  That is the durable way to get main onto razer, but it is a change to
  another repo and a rebuild of razer, well beyond "update the screenshots".
  Pointing the plugin at a build for the duration of the capture is fully
  reversible.
- **Capture locally.** The standing rule is razer, and the tour's sizing is
  tuned to a real monitor (`record-tour.sh:319`).
- **A separate stills script.** It would duplicate `preconditions`, `backup`,
  `restore`, `play` and the panel geometry. `dry()` is already a stills
  loop.
- **A static-site framework or a theme for the new page.** `_config.yml`
  promises the layouts and CSS are the whole site. One page doesn't justify
  a build step.
- **Putting home rules in `style.css`.** That breaks its "fork, one marked
  change" contract with nixarchy's copy.
- **A light theme / `prefers-color-scheme`.** The site is dark by design
  (nixarchy's look), and one page switching theme would read as a bug.

## Risks

- **The apply-log shot needs a real apply, which conflicts with the intent's
  "nothing applied" rule.** There is no build-only apply mode
  (`bin/nixarchy-pkg:1325` goes straight to `cmd_apply`). Decision needed at
  review:
  - **A (proposed):** one exception. Queue `hello`, apply, capture `16`, then
    remove `hello` and apply again. The selection files end byte-identical
    (checked by checksum as now). razer gains two throwaway generations.
    Caveat from the #30 intent: razer's running generation was once switched
    from another machine on a different nixpkgs, so an apply from razer
    switches it to razer's own config. That is expected, but it's worth
    knowing.
  - **B:** no live apply. Drop `16`, show only the confirm prompt (`15`), and
    describe the log in text.
- **The option form may still be a one-way door** (above). Mitigated by
  running it last.
- **The ydotool keymap trap** (`record-tour.sh:35-40`). If letters go dead,
  `omarchy-restart-shell` clears it. The script already restarts the shell
  first.
- **Card size depends on the monitor.** razer has one head today, eDP-1 at
  1920×1080, so every shot comes out the same shape as last time.
- **Page weight.** The tour gif is 2.1 MB and is only loaded as the
  fallback. The new stills add roughly 1.5 MB, lazy-loaded. The hero poster
  is one PNG.
- **razer left on the branch build** if the capture aborts. The restore step
  prints the original target first, so it can be put back by hand.

## Verification

- `tools/record-tour.sh --check` passes on razer.
- `--dry` then `--stills`: every file in the table exists, and each is looked
  at (read back as an image) before commit. No "THE PANEL IS GONE" lines.
- Selection files checksummed before and after: identical. With option A,
  that is checked after the second apply.
- The tour is ≤ 60s (the script enforces it).
- After the run, razer's plugin symlink points at the original store path
  again.
- `nix flake check` passes.
- Pages CI (`.github/workflows/pages.yml`) passes: nav complete, every
  referenced image exists. Its image check greps only `docs/manual/*.md`, so
  the home page's images get a manual `ls` check in the plan.
- The built site served locally (`jekyll serve` or the Pages preview) and
  looked at at 1280px and 375px widths: no horizontal scroll, the scenes
  stack, the video plays.
