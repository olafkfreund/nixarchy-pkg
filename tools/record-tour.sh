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
readonly GIF_FPS=8
readonly KEY_PAUSE=0.45                # between keystrokes, so a human could
readonly KEY_HOLD=0.05                 # a key is held, not blipped; see play()
readonly SETTLE=2.5                    # after the panel opens, before the first key
readonly MENU_NS=nixarchy-pkg-menu     # the layer, not listPlugins' `active`
readonly PLUGIN=nixarchy.pkg

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
readonly CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy"
readonly WORK="${TMPDIR:-/tmp}/nixarchy-tour.$$"
HOME_WS=""            # the workspace to put back when this is over

# budget<TAB>label<TAB>keys. The keys are tokens: k:<keysym>, K:<keysym> for
# shift+key, t:<text>, and *N on a k: token to repeat it.
#
# Tab order is PkgModel.qml:28 -- Apps Services Selection Options Drafts Flakes.
# The story: I want lazygit, I don't know if it's in nixpkgs, and I don't want
# to open an editor. Scene 7 lands at 41s on purpose: queue-then-apply only
# reads once you know what a queue is.
# budget<TAB>label<TAB>keys. Tokens: k:<name> a key, *N to repeat it, t:<text>
# typed as characters.
#
# Everything is sent with ydotool, through uinput, because wtype attaches a
# virtual keyboard carrying its OWN keymap and this client then resolves only
# raw navigation scancodes: arrows keep working while letters, space, Return
# and Tab go silently dead, and the damage outlives the run. If a panel ever
# stops answering anything but arrow keys, that is what happened, and
# `omarchy-restart-shell` clears it.
#
# Tab order is PkgModel.qml:28 -- Apps Services Selection Options Drafts
# Flakes -- and the tour walks it rightwards with Right. Apps, Services and
# Drafts filter what is already listed; Selection and Options are the search
# tabs (PkgModel.qml:83, `indexTab`), so lazygit is looked for on Selection
# and not on Apps, where the curated list would find nothing.
#
# `/` focuses the field (Menu.qml:235) when the list holds the keyboard, but
# lands as a character when the field holds it already -- which is how the
# last tour ended up searching for "/openssh" and finding nothing. Sending
# BackSpace straight after costs nothing on an empty field and removes the
# stray slash on a focused one, so the same tokens work either way.
#
# The `s:` after a typed query is not padding: the search is debounced
# (Menu.qml:265) and Return on a list that has not been rebuilt yet finds no
# row and quietly does nothing, which reads on the recording as a package that
# was searched for and never queued.
#
# A searched row is queued with Return, not Space: Space only toggles when the
# field does NOT hold the keyboard (Menu.qml:205-208), and after typing a query
# it does, so Space would just type a space. Nor is there a Down first -- the
# exact match is already the cursor row, and moving off it queues the wrong
# package.
#
# The Options scene searches but never presses Return, and that is deliberate:
# the option form is a one-way door for anything driving this from outside.
# Once it has been opened, Escape closes it and then every further Escape is
# still eaten by clearInspection() (Menu.qml:165) -- three of them in a row
# leave the query sitting in the field -- so the tab can never be left and the
# tour ends there. Escape after a search ALONE does clear the query and hand
# the keyboard back, which is what every other scene here relies on. The form
# itself is in the manual already, as docs/img/08 and 09.
#
# Escape is only ever sent where something is open or typed: it closes an
# inspection, then clears the text and hands the keyboard back
# (Menu.qml:161-174), but on an empty field it closes the menu. Two of them in
# a row need a pause between: sent back to back, the second arrives while the
# form is still closing and is swallowed as another clearInspection(), leaving
# the query in the field and every later Right moving a caret instead of a tab.
# `s:` is that pause, in seconds. Left and Right are
# caret moves once the field holds text, so a scene that searched presses
# Escape first: that clears the text AND hands the keyboard back to the list
# (Menu.qml:166-172). Escape on an EMPTY field closes the menu, so it is only
# ever sent after typing. Flakes keeps the keyboard in its field whatever
# happens, so it can only be the last scene.
#
# The story: I want lazygit, I do not know if it is in nixpkgs, and I do not
# want to open an editor.
readonly SCENES=$'3\tApps, the catalogue as it opens\t
4\tServices, one turned on\tk:right k:down*2 k:return
3\tSelection, the service waiting there\tk:right
13\tlazygit, found in nixpkgs and queued\tt:/ k:backspace t:lazygit s:2.5 k:return s:3.0
11\tOptions, 25k of them, searched\tk:escape s:1.5 k:right t:/ k:backspace t:openssh s:2.0
5\tDrafts, what is already set\tk:escape s:1.2 k:right
8\tFlakes, a flakeref and what it carries\tk:right t:github:nix-community/nixvim s:1.0 k:return
6\tand what that flake settles on\ts:2.5 k:down k:return'

# The manual's stills, cut by --stills (plan/2026-09-21-36-pages-refresh.md).
# name<TAB>label<TAB>keys: the row is shot as <name> once its keys are sent,
# and a name of `-` sends the keys without a shot. One pass per list, each
# from a fresh shell, because two surfaces here can only come last: Flakes
# keeps the keyboard in its field (above), and the option form may still eat
# every Escape (above, again) -- so each form shot is a pass of its own.
readonly STILLS_TABS=$'01-apps.png\tApps, as it opens\t
02-apps-filter.png\tApps, filtered\tt:/ k:backspace t:term s:1.0
03-services.png\tServices\tk:escape s:1.2 k:right
04-packages-empty.png\tSelection, empty\tk:right
06-packages-search.png\tSelection, nixpkgs searched\tt:/ k:backspace t:lazygit s:2.5
05-packages-unfree.png\tSelection, an unfree row\tk:escape s:1.2 t:/ k:backspace t:google-chrome s:2.5
07-options-search.png\tOptions, searched\tk:escape s:1.2 k:right t:/ k:backspace t:tailscale s:2.0
12-drafts.png\tDrafts\tk:escape s:1.2 k:right
10-keys.png\tthe key sheet\tt:? s:1.0'
readonly STILLS_FORM_BOOL=$'08-option-form-boolean.png\tthe form, a boolean\tk:right*3 t:/ k:backspace t:services.tailscale.enable s:2.0 k:return s:1.0'
readonly STILLS_FORM_SCAFFOLD=$'09-option-form-scaffold.png\tthe form, a scaffold\tk:right*3 t:/ k:backspace t:services.tailscale.extraUpFlags s:2.0 k:return s:1.0'
# The inspection is a network fetch the first time, hence the long wait.
# `declare` is always the last row (PkgModel.qml:132), and PageDown clamps.
# Return on the `declare` row starts naming (PkgModel.qml:358); in naming,
# Return would DECLARE the input, so the only key sent there is Escape.
readonly STILLS_FLAKES=$'13-flakes.png\tFlakes, a flake inspected\tk:right*5 t:github:nix-community/nixvim s:1.0 k:return s:8.0
14-flake-name-confirm.png\tFlakes, naming the input\tk:pagedown s:0.5 k:return s:1.0
-\tcancel the naming\tk:escape'

# THIS PASS SWITCHES THE SYSTEM. It queues hello and applies it, because the
# build log only exists during a real apply (there is no build-only mode).
# Undo it afterwards: nixarchy-pkg pkg remove hello && nixarchy-pkg apply.
# `a` once arms the apply and shows the confirm; the second applies
# (Menu.qml:206-210, 317-322).
readonly STILLS_APPLY=$'17-queued.png\thello, queued\tk:right*2 t:/ k:backspace t:hello s:2.5 k:return s:1.0
-\thand the list the keyboard\tk:escape s:1.2
15-apply-confirm.png\tapply, armed\tt:a s:0.8
16-apply-log.png\tapply, the log at its end\tt:a s:240'
QUEUE_OK=""           # set by --apply-shots, whose job is to queue

# ydotool speaks Linux keycodes, not keysyms.
keycode() {
  case "$1" in
    escape) printf 1 ;;   return) printf 28 ;;  slash) printf 53 ;;
    backspace) printf 14 ;; pagedown) printf 109 ;;
    space)  printf 57 ;;  up)     printf 103 ;; left)  printf 105 ;;
    right)  printf 106 ;; down)   printf 108 ;;
    *) die "unknown key: $1" ;;
  esac
}

# Hyprland 0.56 parses dispatch arguments as Lua, so `dispatch workspace 13`
# is a syntax error, not a workspace switch -- and one that exits 7 rather
# than saying so. The legacy form is kept for older Hyprlands.
go_workspace() {
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$1\" })" >/dev/null 2>&1 \
    || hyprctl dispatch workspace "$1" >/dev/null 2>&1 \
    || die "could not switch to workspace $1"
  sleep 0.8
}

# The panel stops accepting anything but arrows after a while of being driven
# -- letters, `/`, Return and Space all go quiet, and a take made then is a
# tour of one motionless tab. A restarted shell always accepts them, so every
# take starts from one. It costs the bar and the panels blinking out and back.
fresh_shell() {
  say "restarting the shell, so the panel still takes letters"
  omarchy-restart-shell >/dev/null || die "could not restart the shell"
  sleep 4
}

say() { printf '%s\n' "$*" >&2; }
die() { printf 'record-tour: %s\n' "$*" >&2; exit 1; }

budget_total() { printf '%s\n' "$SCENES" | awk -F'\t' '{s+=$1} END{print s}'; }

panel_open() {
  [ "$(hyprctl layers -j \
       | jq "[to_entries[].value.levels|to_entries[].value[]?|select(.namespace==\"$MENU_NS\")]|length")" != 0 ]
}

toggle_panel() { omarchy-shell -q shell toggle "$PLUGIN" '{}'; }

preconditions() {
  for c in hyprctl jq wl-screenrec ffmpeg ydotool omarchy-shell grim; do
    command -v "$c" >/dev/null || die "$c is not installed"
  done
  ydotool key 0:0 2>/dev/null || die "ydotoold is not reachable; check YDOTOOL_SOCKET"

  # A stale index carries no unfree or broken flags at all, so a tour cut
  # against one contradicts the pages it sits on.
  [ "$("$REPO/bin/nixarchy-pkg" state | jq -r .indexStale)" = false ] \
    || die "the index is stale; run 'nixarchy-pkg reindex' first"

  # The tour queues three things and must be the only thing that queued
  # them, or the closing shot counts wrong.
  local pending
  pending="$("$REPO/bin/nixarchy-pkg" pending | jq -r .count)"
  [ "$pending" = 0 ] || [ -n "$QUEUE_OK" ] \
    || die "$pending change(s) already queued; apply or revert them first"

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
  [ -n "$HOME_WS" ] && go_workspace "$HOME_WS"
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
      t:*) ydotool type --key-delay 45 "${token#t:}" ;;
      s:*) sleep "${token#s:}" ;;
      k:*)
        key="${token#k:}"; n=1
        case "$key" in *\*[0-9]*) n="${key##*\*}"; key="${key%%\**}" ;; esac
        key="$(keycode "$key")"
        while [ "$n" -gt 0 ]; do
          # Press and release as two events with a hold between them. Sent as
          # one batch (`key N:1 N:0`) they share a timestamp and this client
          # drops them at random: a Right that never changes tab, a Return
          # that never queues.
          ydotool key "${key}:1"; sleep "$KEY_HOLD"; ydotool key "${key}:0"
          sleep "$KEY_PAUSE"; n=$((n - 1))
        done ;;
    esac
    sleep "$KEY_PAUSE"
  done
}

record() {
  local mon mw mh mx my w h x y rec_pid start empty
  # The TALLEST monitor with an empty workspace, not whichever happens to be
  # focused. The card is a share of the screen (Menu.qml:120-127), so a take
  # made on a 1080p head is 1100x842 where a 1440p one is 1100x1123: fewer
  # rows, a different shape, and a tour that does not match the stills
  # beside it. The shell restart above can move focus, so "focused" is not a
  # choice anyone made.
  read -r mon mw mh mx my < <(hyprctl monitors -j \
    | jq -r 'sort_by(-.height)|.[0]|"\(.name) \(.width) \(.height) \(.x) \(.y)"')
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$mon\" })" >/dev/null 2>&1 \
    || hyprctl dispatch focusmonitor "$mon" >/dev/null 2>&1 || true
  sleep 0.6

  # The card, from Menu.qml:120-127: min(1100, 72% of the width) wide, 78% of
  # the height, centred. It is opaque, so cropping to it is also what keeps
  # the desktop behind it out of the recording.
  w=$(( 1100 < mw * 72 / 100 ? 1100 : mw * 72 / 100 )); h=$(( mh * 78 / 100 ))
  # global compositor coordinates: wl-screenrec takes a geometry OR an
  # output, never both, and a geometry already says which output it is on.
  x=$(( mx + (mw - w) / 2 )); y=$(( my + (mh - h) / 2 ))
  # An empty workspace, so the tour carries none of whoever's desktop this
  # is. The card is opaque and the crop is to the card, so this is about what
  # a stray notification or a wide window edge could put in frame, and about
  # not filming somebody's screen to document a package manager.
  HOME_WS="$(hyprctl activeworkspace -j | jq -r .id)"
  empty="$(hyprctl workspaces -j \
    | jq -r --arg m "$mon" '[.[]|select(.monitor==$m and .windows==0 and .id>0)]|first|.id // empty')"
  [ -n "$empty" ] || die "no empty workspace on $mon to record on"
  say "recording $mon on empty workspace $empty, card ${w}x${h}+${x}+${y}"
  go_workspace "$empty"

  wl-screenrec -g "$x,$y ${w}x${h}" -f "$WORK/take.mp4" &
  rec_pid=$!
  # Frame offsets are measured from HERE, the first frame of the video, not
  # from the first keystroke. ffmpeg's -ss counts from the start of the
  # file, so offsets taken after the panel had opened pointed a whole short
  # scene earlier than the scene they named -- and a verification that
  # reads the wrong frame is worse than none.
  local video_start=$SECONDS
  sleep 1.5
  # a dead recorder means the next 52 seconds record nothing at all
  kill -0 "$rec_pid" 2>/dev/null || die "wl-screenrec died on startup; nothing was recorded"

  toggle_panel
  sleep "$SETTLE"
  panel_open || { kill "$rec_pid" 2>/dev/null; die "the panel did not open; nothing was recorded"; }

  start=$SECONDS
  : > "$WORK/offsets"
  while IFS=$'\t' read -r budget label keys; do
    local t0=$SECONDS
    [ -n "$keys" ] && play "$keys"
    # the rest of the scene's budget is dwell, so the frame can be read
    local spent=$((SECONDS - t0))
    [ "$spent" -lt "$budget" ] && sleep $((budget - spent))
    # where this scene actually ended. Scenes overrun their budget, so
    # frames taken at the budget SUMS drift further out of step with every
    # scene -- which had me reading scene 6 and calling it scene 5.
    printf '%s\t%s\n' "$((SECONDS - video_start))" "$label" >> "$WORK/offsets"
  done < <(printf '%s\n' "$SCENES")

  sleep 0.8
  # What the tour actually queued, read before the selection is put back. The
  # closing shot claims a number; this is that number, from the tool itself.
  say "queued by the tour: $("$REPO/bin/nixarchy-pkg" pending | jq -r .count)"
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
    -vf "fps=${GIF_FPS},scale=${OUT_W}:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=48[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
    "$REPO/docs/img/tour.gif"
  ls -l "$REPO/docs/img/tour.webm" "$REPO/docs/img/tour.gif" >&2
}

# One frame per scene, to be looked at before anything is committed. A take
# that reads wrong is discarded, not published -- the last pass only caught a
# bad capture by reading the saved file.
frames() {
  local at label i=1
  [ -f "$WORK/offsets" ] || die "no scene offsets; run a take first"
  rm -f "$WORK"/scene-*.png
  while IFS=$'\t' read -r at label; do
    # a second before the scene ended, while its dwell is still on screen
    ffmpeg -nostdin -y -v error -ss "$((at - 1))" -i "$WORK/take.mp4" \
      -frames:v 1 "$WORK/$(printf 'scene-%d.png' "$i")"
    printf '  %d  %ss  %s\n' "$i" "$at" "$label" >&2
    i=$((i + 1))
  done < "$WORK/offsets"
  say "frames in $WORK"
}

# Drives a scene list (the tour by default) without recording and leaves one
# screenshot per scene, so a broken key sequence costs seconds instead of a
# whole take. Given an output dir, it is --stills: each row is shot under the
# name in its first field, and `-` rows are not shot.
dry() {
  local list="${1:-$SCENES}" out="${2:-}"
  local mon mw mh mx my w h x y empty name shot i=1
  # The TALLEST monitor with an empty workspace, not whichever happens to be
  # focused. The card is a share of the screen (Menu.qml:120-127), so a take
  # made on a 1080p head is 1100x842 where a 1440p one is 1100x1123: fewer
  # rows, a different shape, and a tour that does not match the stills
  # beside it. The shell restart above can move focus, so "focused" is not a
  # choice anyone made.
  read -r mon mw mh mx my < <(hyprctl monitors -j \
    | jq -r 'sort_by(-.height)|.[0]|"\(.name) \(.width) \(.height) \(.x) \(.y)"')
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$mon\" })" >/dev/null 2>&1 \
    || hyprctl dispatch focusmonitor "$mon" >/dev/null 2>&1 || true
  sleep 0.6
  w=$(( 1100 < mw * 72 / 100 ? 1100 : mw * 72 / 100 )); h=$(( mh * 78 / 100 ))
  x=$(( mx + (mw - w) / 2 )); y=$(( my + (mh - h) / 2 ))
  HOME_WS="$(hyprctl activeworkspace -j | jq -r .id)"
  empty="$(hyprctl workspaces -j \
    | jq -r --arg m "$mon" '[.[]|select(.monitor==$m and .windows==0 and .id>0)]|first|.id // empty')"
  [ -n "$empty" ] || die "no empty workspace on $mon"
  go_workspace "$empty"
  toggle_panel; sleep "$SETTLE"
  panel_open || die "the panel did not open"
  while IFS=$'\t' read -r name label keys; do
    [ -n "$keys" ] && play "$keys"
    sleep 0.6
    shot="$WORK/$(printf 'dry-%d.png' "$i")"
    [ -n "$out" ] && shot="$out/$name"
    [ -n "$out" ] && [ "$name" = - ] || grim -g "$x,$y ${w}x${h}" "$shot"
    panel_open || say "scene $i ($label): THE PANEL IS GONE"
    i=$((i + 1))
  done < <(printf '%s\n' "$list")
  say "dry frames in ${out:-$WORK}"
}

# Every pass from a fresh shell and a closed panel, back on the workspace it
# started from, so one pass's leftovers are never the next one's first frame.
stills() {
  local pass
  mkdir -p "$WORK/stills"
  for pass in "$@"; do
    fresh_shell
    dry "$pass" "$WORK/stills"
    if panel_open; then toggle_panel; fi
    go_workspace "$HOME_WS"
  done
}

case "${1:-}" in
  --check)  preconditions ;;
  --dry)    preconditions; backup; trap restore EXIT; mkdir -p "$WORK"; fresh_shell; dry ;;
  --frames) frames ;;
  --stills) preconditions; backup; trap restore EXIT
            stills "$STILLS_TABS" "$STILLS_FORM_BOOL" "$STILLS_FORM_SCAFFOLD" "$STILLS_FLAKES" ;;
  --apply-shots)
            QUEUE_OK=1; preconditions; backup; trap restore EXIT; stills "$STILLS_APPLY" ;;
  "")       preconditions; backup; trap restore EXIT; fresh_shell; record; encode; frames ;;
  *)        die "usage: record-tour.sh [--check|--dry|--frames|--stills|--apply-shots]" ;;
esac
