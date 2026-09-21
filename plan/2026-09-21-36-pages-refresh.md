---
status: approved
issue: 36
spec: spec/2026-09-21-36-pages-refresh.md
---

# Plan: fresh screenshots, and a front page that stands out

## Approved decisions (from the spec)

- **Everything is captured on razer, from this branch's build.** razer's
  installed plugin is older than main (a Home Manager symlink to
  `/nix/store/72fi…-nixarchy-pkg` from the pinned flake input). For the capture
  only, the symlink points at a build of this branch, then goes back. razer's
  NixOS config and lock are not touched.
- **Stills come from a `--stills` mode on `tools/record-tour.sh`**, reusing
  `dry()`. No second driver. The names `01`–`11` are kept, so no manual links
  change. New: `12-drafts`, `13-flakes`, `14-flake-name-confirm`,
  `15-apply-confirm`, `16-apply-log`. `08` and `09` are re-taken.
- **The tour is re-cut** with the same script and limit. The Flakes scene is
  rechecked for #34.
- **Apply-log exception, option A** (the spec's proposal, approved with it):
  queue `hello`, apply, capture, then remove `hello` and apply again. The
  selection files end byte-identical, and razer gains two throwaway
  generations.
- **Home page:** hero tour video, six numbered scenes ("getting lazygit
  without opening an editor"), a grid of the other shots, then "what it
  writes" and a footer. The rules go in a **new `docs/assets/home.css`**;
  `style.css` is untouched. Dark only, one column below 760px, 16px gutters,
  lazy images with width/height and alt text.
- **README:** `assets/showcase/*.png` is replaced from the same run and
  `assets/showcase/README.md` gains sections for 12–16. `assets/screenshot.png`
  becomes the new `01`.

## Facts the steps rely on (checked in `Menu.qml` / `PkgModel.qml`)

- `a` once **arms** an apply (the confirm, #31). A second `a` applies. Any
  other key disarms (`Menu.qml:206-210`). So Escape after one `a` is safe.
- On Flakes, Return with a flakeref in the field inspects it
  (`Menu.qml:266`). Return on the `declare` row starts naming
  (`PkgModel.qml:358` → `Menu.qml:100`). In naming, Return **declares** and
  Escape cancels (`Menu.qml:214-223`). The flake shot therefore only ever
  sends Escape there.
- Flakes keeps the keyboard in its field, so it can only be the last scene of
  a pass (`record-tour.sh:84`). The option form may trap Escape
  (`record-tour.sh:65-72`), so each form shot is the last scene of its own
  pass.
- `?` and `a` are sent with `t:` (`ydotool type`), so `keycode()` needs no
  new keys.
- `backup()`/`restore()` only cover `apps.nix` and `services.nix`. The
  checksum check in step 5 covers every `*.nix` in `~/.config/nixarchy`.

## Steps

1. **`tools/record-tour.sh`: stills mode.**
   - `dry()` takes the scene list as `$1` and an optional output dir as
     `$2`. Without `$2` it behaves exactly as today (`dry-N.png`). With it,
     a row whose first field ends in `.png` is saved as `$2/<field>`, and a
     row whose first field is `-` moves on without a shot.
   - Add pass lists. Every row is `name<TAB>label<TAB>keys`:
     - `STILLS_TABS`:
       - `01-apps.png`: nothing
       - `02-apps-filter.png`: `t:/ k:backspace t:term s:1.0`
       - `03-services.png`: `k:escape s:1.2 k:right`
       - `04-packages-empty.png`: `k:right`
       - `06-packages-search.png`: `t:/ k:backspace t:lazygit s:2.5`
       - `05-packages-unfree.png`: `k:escape s:1.2 t:/ k:backspace t:google-chrome s:2.5`
       - `07-options-search.png`: `k:escape s:1.2 k:right t:/ k:backspace t:tailscale s:2.0`
       - `12-drafts.png`: `k:escape s:1.2 k:right`
       - `10-keys.png`: `t:? s:1.0`
     - `STILLS_FORM_BOOL`: `08-option-form-boolean.png` = `k:right*3 t:/ k:backspace t:services.tailscale.enable s:2.0 k:return s:1.0`
     - `STILLS_FORM_SCAFFOLD`: `09-option-form-scaffold.png`, the same with `services.tailscale.extraUpFlags`
     - `STILLS_FLAKES`:
       - `13-flakes.png`: `k:right*5 t:github:nix-community/nixvim s:1.0 k:return s:3.0`
       - `14-flake-name-confirm.png`: cursor to the `declare` row + `k:return s:1.0` (the row's position is read off `13` in the dry run)
       - `-`: `k:escape`
   - `--stills`: `preconditions`, `backup`, `trap restore EXIT`, then for
     each pass: `fresh_shell`, `dry "$pass" "$WORK/stills"`, close the panel
     if it is open. The shots land in `$WORK/stills`. They are not written
     into `docs/img`, because they get looked at first (as `frames()` does).
   - `--apply-shots`: its own flag, with a comment saying it **switches the
     system**. `STILLS_APPLY`:
     - `-`: `k:right*2 t:/ k:backspace t:hello s:2.5 k:return s:1.0 k:escape s:1.2`
     - `15-apply-confirm.png`: `t:a s:0.8`
     - `16-apply-log.png`: `t:a s:240`
     It skips the `pending = 0` precondition, because queuing is its job.
   - Usage line updated.
   → verify by `bash -n` and `shellcheck tools/record-tour.sh` clean, and `nix flake check` passes.
2. **Push the branch and put its build on razer.** Push, then on razer:
   `nix build github:olafkfreund/nixarchy-pkg/docs/36-pages-refresh -o ~/tmp/pkg-36`.
   Record `readlink ~/.config/omarchy/plugins/nixarchy.pkg` to
   `~/tmp/pkg-36.orig`. Then `ln -sfn` the new build into place and run
   `omarchy-restart-shell`. Clone the branch to `~/tmp/pkg-36-src` for the
   script. Every ssh command exports `HYPRLAND_INSTANCE_SIGNATURE` from
   `/run/user/$UID/hypr`.
   → verify by `sha1sum Menu.qml` on razer's plugin matching the branch, and `record-tour.sh --check` passing.
3. **Checksum the selection:** `sha1sum ~/.config/nixarchy/*.nix >
   ~/tmp/pkg-36.sums` on razer.
   → verify by the file existing with every `.nix` listed.
4. **Stills:** `record-tour.sh --dry "$STILLS_…"` per pass if a pass's keys
   are in doubt, then `--stills`. scp `$WORK/stills/*.png` back and **read
   every one**. Anything wrong (wrong row, panel gone, a stray character in
   a field) is fixed in the pass's keys and re-run.
   → verify by all 13 files present, each showing what its row names, and no "THE PANEL IS GONE" line.
5. **Apply shots (option A):** run `--apply-shots` and read `15` and `16`.
   `16` must show the log's end state (#32). If the build was still running
   at 240s, re-take with a longer `s:`. Then `nixarchy-pkg pkg remove hello
   && nixarchy-pkg apply` on razer, and wait for it to finish.
   → verify by `sha1sum -c ~/tmp/pkg-36.sums` passing, `nixarchy-pkg pending` count 0, and `command -v hello` empty on razer.
6. **Tour:** `record-tour.sh --dry` and read the frames. If the Flakes
   scenes (`SCENES` rows 7–8) read wrong after #34, fix their keys (and the
   comment). Then `record-tour.sh`, read the frames `--frames` leaves, and
   scale scene 1's frame to 620px wide as `docs/img/tour-poster.png`.
   → verify by the take being ≤ 60s, every frame showing its label's scene, and the selection restored (`sha1sum -c`).
7. **Put razer back:** `ln -sfn "$(cat ~/tmp/pkg-36.orig)"
   ~/.config/omarchy/plugins/nixarchy.pkg && omarchy-restart-shell`, and
   remove `~/tmp/pkg-36*`.
   → verify by `readlink` equalling the recorded path.
8. **Images into the repo:** copy the stills to `docs/img/` and
   `assets/showcase/` (`10-keys.png` is showcase-only, as now), copy `01` to
   `assets/screenshot.png`, and commit the tour files. Any PNG over 400 KB
   goes through `oxipng -o 4` if it's on PATH. No new tool is added for this.
   → verify by `ls -l`, and by every `img/…` in `docs/manual/*.md` still existing.
9. **`docs/assets/home.css`** (new): `main` max 980px with 16px side
   padding; `.hero video` 100% wide with rounded corners and a `--rule`
   border; `.links` a flex row; `.scene` a two-column grid (1.15fr/1fr) with
   an `--accent` step label; `.grid3` three columns of figures with dim
   captions. Below 760px, `.scene` and `.grid3` go to one column. `img`
   gets `max-width:100%; height:auto`. Colours come only from `style.css`'s
   tokens: no hex values, which `nix flake check` forbids for QML and this
   file keeps to as well.
   → verify by no `#` colour literals in the file.
10. **`docs/_layouts/home.html`:** load `home.css` after `style.css`, and put
    the masthead first. `content--centred` moves to the text-only sections
    so the scenes can be wide.
    → verify by the Pages build (step 13).
11. **`docs/index.md`:** lede, hero `<video controls autoplay loop muted
    playsinline poster="img/tour-poster.png">` with the webm and a gif
    fallback, then links (Install → README#install, Manual, Source). Then
    "Getting lazygit without opening an editor" with scenes 1–6 as the spec
    lists them (`06`, `05`, `08`, `12`, `15`+`16`, text-only rollback
    linking `manual/applying`). Then "Everything else" (`01`, `03`, `13`,
    `14`, `11`, `02`, captioned), then the two "what it writes" paragraphs
    as they are, then the footer. Every `<img>` gets real alt text,
    `loading="lazy"` (except the poster), and width/height from the file.
    The claims in the scene text are checked against the manual pages they
    summarise.
    → verify by `grep -o 'img/[^"]*' docs/index.md | xargs -I{} test -f docs/{}` succeeding.
12. **`assets/showcase/README.md`:** add sections for 12–16 in its existing
    voice. Change the "nothing was applied" sentence to say what the
    apply-log shot needed (step 5) and that the selection still checksummed
    identical.
    → verify by every image it names existing.
13. **Check the site:** build it on razer with `nix shell nixpkgs#jekyll -c
    jekyll build -s docs -d ~/tmp/site-36`, serve it on razer, and look at
    it from Chrome at 1280px and 375px wide.
    → verify by no horizontal scroll at 375, scenes stacking, the video playing, no broken images, and the manual pages unchanged in look.
14. **Commit, PR:** one commit for the script, one for the images, one for
    the page and README. The PR links intent, spec and plan and closes #36.
    → verify by Pages CI green on the PR.

## Tests

- `shellcheck tools/record-tour.sh`: clean.
- `nix flake check`: passes (shellcheck, manifest, no hex colours).
- `bash tests/adapter.sh`: passes. The script change doesn't touch the
  adapter, but it's cheap.
- On razer: `sha1sum -c ~/tmp/pkg-36.sums` after steps 4, 5 and 6: `OK` for every file.
- Pages CI on the PR: `reachable` and `build` jobs green.
- Step 13's visual check at two widths.

## Rollback

- Page and images: revert the PR. The old `docs/img/*` come back from git.
- razer mid-capture: `ln -sfn "$(cat ~/tmp/pkg-36.orig)"
  ~/.config/omarchy/plugins/nixarchy.pkg && omarchy-restart-shell`. The
  selection files are in `$WORK` (printed by `backup()`).
- The two apply generations: `nixarchy-pkg pkg remove hello && nixarchy-pkg
  apply` is already part of step 5. If the second apply fails, roll back to
  the generation before the first with `sudo nixos-rebuild switch
  --rollback`, run twice.

## Deviations found while implementing

- **Session environment for ssh.** `omarchy-shell` found no shell over ssh
  ("omarchy-shell is not running", hidden by `-q`): since nixarchy #220 the
  shell runs from a store tree named by `OMARCHY_PATH`. Every capture command
  sources `~/tmp/pkg-36.env`, written from the running quickshell's
  `/proc/<pid>/environ` (`OMARCHY_PATH`, `XDG_RUNTIME_DIR`,
  `WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`).
- **A pending change was already on razer** (`hello` removed at 18:10, never
  applied). With the user's go-ahead it was applied first: built, checked
  (same nixpkgs, same nvidia 610.57.04, closure diff only `hello` removed),
  switched with `switch-to-configuration`, since `nixarchy-pkg apply` over
  ssh has no polkit agent for nh's pkexec.
- **Any switch restores the pinned plugin link** (Home Manager is restarted
  by it). The branch build is re-linked after every apply, including the two
  in step 5, before the next capture.
- **13 caught the flake still loading** at 3s: the wait is 8s. **14** needs
  the cursor on `declare`, which is always the last row
  (`PkgModel.qml:132`): PageDown (keycode 109, added to `keycode()`) gets
  there.
- **Drafts is empty on razer**, so `12` reads "nothing here yet" and stays a
  grid shot only. Scene 4 ("see what's waiting") uses a new
  **`17-queued.png`**, taken in the apply pass the moment `hello` is queued.
- **No apply-log shot (option B, decided by the user).** The first
  `--apply-shots` run did switch razer, but the panel closed during the
  build (nh then aborted on a closed stderr pipe, after activating), so `16`
  shows the desktop. The switch it made was a nixpkgs and nvidia bump
  (610 → 615) under the loaded 610 module. razer was rebooted into it at the
  user's request. After that, `/etc/nixos` on razer builds an *older*
  system than the running one, so any further apply would have been a
  downgrade. Scene 5 shows `15` and describes the log in text.
  `--apply-shots` stays in the script for a machine where an apply is safe.
- **The home grid uses `07` (Options searched) instead of `11`** (the bar
  widget, a 2.6 KB crop of the bar that reads as a blank tile at a third of
  the page width). `11` stays on the manual's bar page.
- **The tour was taken twice.** The first take lost the panel to an
  ai-mirror control request that appeared on razer mid-take. The pointer is
  parked in the screen corner before recording.
