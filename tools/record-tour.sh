#!/usr/bin/env bash
# Cuts docs/img/tour.webm and docs/img/tour.gif: one take, one story, under a
# minute. See plan/2026-09-20-22-faster-tour.md.
#
# The last tour was driven by hand and took five attempts. What that cost is
# spent here as preconditions this script refuses to start without, so the
# next re-cut does not pay for it again.
set -euo pipefail

readonly LIMIT=60                      # seconds; the whole point of the task
readonly OUT_W=620                     # matches the asset being replaced
readonly GIF_FPS=12
readonly KEY_PAUSE=0.28                # between keystrokes, so a human could
readonly MENU_NS=nixarchy-pkg-menu     # the layer, not listPlugins' `active`
readonly PLUGIN=nixarchy.pkg

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy"
readonly WORK="${TMPDIR:-/tmp}/nixarchy-tour.$$"

# budget<TAB>label<TAB>keys. The keys are tokens: k:<keysym>, K:<keysym> for
# shift+key, t:<text>, and *N on a k: token to repeat it.
#
# Tab order is PkgModel.qml:28 -- Apps Services Selection Options Drafts Flakes.
# The story: I want lazygit, I don't know if it's in nixpkgs, and I don't want
# to open an editor. Scene 7 lands at 41s on purpose: queue-then-apply only
# reads once you know what a queue is.
readonly SCENES=$'4\tApps, already listed\t
5\tServices, one turned on\tk:Tab k:Down*3 k:space
5\tSelection, the toggle waiting\tk:Tab
9\tOptions, a search and its form\tk:Tab t:/ t:openssh k:Down k:Return
5\tDrafts, the option waiting\tk:Escape k:Tab
8\tFlakes, a flakeref and its packages\tk:Tab t:github:nix-community/nixvim k:Return
10\tApps, lazygit, queued\tK:Tab*5 t:/ t:lazygit k:space
6\tSelection, three queued, none built\tk:Tab*2'

say() { printf '%s\n' "$*" >&2; }
die() { printf 'record-tour: %s\n' "$*" >&2; exit 1; }

budget_total() { printf '%s\n' "$SCENES" | awk -F'\t' '{s+=$1} END{print s}'; }

panel_open() {
  [ "$(hyprctl layers -j \
       | jq "[to_entries[].value.levels|to_entries[].value[]?|select(.namespace==\"$MENU_NS\")]|length")" != 0 ]
}

toggle_panel() { omarchy-shell -q shell toggle "$PLUGIN" '{}'; }

preconditions() {
  for c in hyprctl jq wl-screenrec ffmpeg wtype omarchy-shell grim; do
    command -v "$c" >/dev/null || die "$c is not installed"
  done

  # A stale index carries no unfree or broken flags at all, so a tour cut
  # against one contradicts the pages it sits on.
  [ "$("$REPO/bin/nixarchy-pkg" state | jq -r .indexStale)" = false ] \
    || die "the index is stale; run 'nixarchy-pkg reindex' first"

  # The tour queues three things and must be the only thing that queued
  # them, or the closing shot counts wrong.
  local pending
  pending="$("$REPO/bin/nixarchy-pkg" pending | jq -r .count)"
  [ "$pending" = 0 ] || die "$pending change(s) already queued; apply or revert them first"

  # SUPER+ALT+N is a toggle, so a tour can open by closing. Never guess.
  ! panel_open || die "the panel is already open; close it and run again"

  local total; total="$(budget_total)"
  [ "$total" -lt "$LIMIT" ] || die "scene budget is ${total}s, over the ${LIMIT}s limit"
  say "budget: ${total}s over $(printf '%s\n' "$SCENES" | wc -l) scenes, limit ${LIMIT}s"
}

# The selection is restored whatever happens, and the copies survive an
# uncatchable kill so it can be put back by hand.
backup() {
  mkdir -p "$WORK"
  cp "$CONFIG/apps.nix" "$WORK/apps.nix"
  cp "$CONFIG/services.nix" "$WORK/services.nix"
  say "selection saved to $WORK"
}

restore() {
  [ -f "$WORK/apps.nix" ] || return 0
  cp "$WORK/apps.nix" "$CONFIG/apps.nix"
  cp "$WORK/services.nix" "$CONFIG/services.nix"
  panel_open && toggle_panel || true
  say "selection restored"
}

# Only wtype and sleep run between the first keystroke and the last: any other
# call risks raising the window that launched this, which is what ruined the
# last capture. Run the whole thing detached and do not touch the desktop
# while it works.
play() {
  local token key n
  for token in $1; do
    case "$token" in
      t:*) wtype -- "${token#t:}" ;;
      k:*|K:*)
        key="${token#?:}"; n=1
        case "$key" in *\*[0-9]*) n="${key##*\*}"; key="${key%%\**}" ;; esac
        while [ "$n" -gt 0 ]; do
          if [ "${token:0:1}" = K ]; then wtype -M shift -k "$key" -m shift
          else wtype -k "$key"; fi
          sleep "$KEY_PAUSE"; n=$((n - 1))
        done ;;
    esac
    sleep "$KEY_PAUSE"
  done
}

record() {
  local mon mw mh w h x y rec_pid start
  read -r mon mw mh < <(hyprctl monitors -j | jq -r '.[]|select(.focused)|"\(.name) \(.width) \(.height)"')

  # The card, from Menu.qml:120-127: min(1100, 72% of the width) wide, 78% of
  # the height, centred. It is opaque, so cropping to it is also what keeps
  # the desktop behind it out of the recording.
  w=$(( 1100 < mw * 72 / 100 ? 1100 : mw * 72 / 100 )); h=$(( mh * 78 / 100 ))
  x=$(( (mw - w) / 2 )); y=$(( (mh - h) / 2 ))
  say "recording $mon, card ${w}x${h}+${x}+${y}"

  wl-screenrec -o "$mon" -g "$x,$y ${w}x${h}" -f "$WORK/take.mp4" --codec auto &
  rec_pid=$!
  sleep 1.2

  toggle_panel
  sleep 1.2
  panel_open || { kill "$rec_pid" 2>/dev/null; die "the panel did not open; nothing was recorded"; }

  start=$SECONDS
  while IFS=$'\t' read -r budget label keys; do
    local t0=$SECONDS
    [ -n "$keys" ] && play "$keys"
    # the rest of the scene's budget is dwell, so the frame can be read
    local spent=$((SECONDS - t0))
    [ "$spent" -lt "$budget" ] && sleep $((budget - spent))
  done < <(printf '%s\n' "$SCENES")

  sleep 0.8
  kill -INT "$rec_pid" 2>/dev/null || true
  wait "$rec_pid" 2>/dev/null || true
  say "take: $((SECONDS - start))s of scenes"
  panel_open || say "WARNING: the panel closed during the take -- check the frames"
}

encode() {
  local src="$WORK/take.mp4"
  ffmpeg -y -v error -i "$src" -vf "scale=${OUT_W}:-2:flags=lanczos" \
    -c:v libvpx-vp9 -b:v 0 -crf 34 -an "$REPO/docs/img/tour.webm"
  ffmpeg -y -v error -i "$src" \
    -vf "fps=${GIF_FPS},scale=${OUT_W}:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
    "$REPO/docs/img/tour.gif"
  ls -l "$REPO/docs/img/tour.webm" "$REPO/docs/img/tour.gif" >&2
}

# One frame per scene, to be looked at before anything is committed. A take
# that reads wrong is discarded, not published -- the last pass only caught a
# bad capture by reading the saved file.
frames() {
  local at=0 i=1
  rm -f "$WORK"/scene-*.png
  while IFS=$'\t' read -r budget label _; do
    ffmpeg -y -v error -ss $((at + budget - 1)) -i "$WORK/take.mp4" \
      -frames:v 1 "$WORK/$(printf 'scene-%d.png' "$i")"
    at=$((at + budget)); i=$((i + 1))
  done < <(printf '%s\n' "$SCENES")
  say "frames in $WORK"
}

case "${1:-}" in
  --check)  preconditions ;;
  --frames) frames ;;
  "")       preconditions; backup; trap restore EXIT; record; encode; frames ;;
  *)        die "usage: record-tour.sh [--check|--frames]" ;;
esac
