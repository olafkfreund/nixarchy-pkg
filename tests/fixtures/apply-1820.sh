#!/usr/bin/env bash
# Test fake of nixarchy-apply at nixarchy 2731c9cc (after #1829) (modules/apps.nix). The block
# from select_home_src() to the end of home_decide() is copied verbatim, and
# tests/adapter.sh diffs it against the installed apply when there is one. The
# part loop, the --release-home label and the --home-plan arm are stand-ins
# (the arm is the contract in spec/2026-11-17-103-follow-home-owner.md, section 1).
# The seed it classifies against comes from NIXARCHY_FAKE_SEED (tests/fixtures/home-seed.nix).
set -o errexit
set -o nounset
set -o pipefail
for part in apps services advanced flatsnap; do :; done
select_home_src() {
  if [ -f "$pinned/home.nix" ]; then
    printf '%s\n' "$pinned/home.nix" || return 1
  else
    local src="$srcdir/home.nix"
    if [ -f "$src" ]; then printf '%s\n' "$src" || return 1; fi
  fi
  return 0
}

snapshot_home() {
  home_snap=""
  home_state=absent
  home_srcmsg="$srcdir/home.nix"
  local src
  src=$(select_home_src) || return 1
  if [ -n "$src" ]; then
    home_snap="$pinned/home.snap"
    cp "$src" "$home_snap" || return 1
  fi
}

classify_home() {
  home_state=absent
  if [ -n "$home_snap" ]; then
    if [ ! -f "$home_snap" ]; then
      echo "nixarchy-apply: cannot compare home.nix with the seed" >&2
      return 1
    fi
    local rc
    if cmp -s "$home_snap" "$1"; then
      home_state=seed
    else
      rc=$?
      if [ "$rc" -eq 1 ]; then
        home_state=edited
      else
        echo "nixarchy-apply: cannot compare home.nix with the seed" >&2
        return 1
      fi
    fi
  fi
}

valid_user() {
  [[ $1 =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

read_owner() {
  owner=""
  [ -f "$dest" ] || return 0
  local candidates exact rc
  rc=0
  candidates=$(grep -cE '^[[:space:]]*home-manager\.users\.' "$dest" 2>/dev/null) || rc=$?
  [ "$rc" -le 1 ] || { echo "nixarchy-apply: cannot read $dest" >&2; return 1; }
  rc=0
  exact=$(grep -cE '^[[:space:]]*home-manager\.users\."[^"]+"\.imports[[:space:]]*=' "$dest" 2>/dev/null) || rc=$?
  [ "$rc" -le 1 ] || { echo "nixarchy-apply: cannot read $dest" >&2; return 1; }
  if [ "$candidates" -eq 0 ]; then
    return 0
  fi
  if [ "$candidates" -eq 1 ] && [ "$exact" -eq 1 ]; then
    owner=$(sed -nE 's/^[[:space:]]*home-manager\.users\."([^"]+)"\.imports[[:space:]]*=.*/\1/p' "$dest") || return 1
    if valid_user "$owner"; then
      return 0
    fi
  fi
  owner=""
  echo "nixarchy-apply: $dest names several home owners (or an unparseable one); fix it by hand" >&2 || return 1
  return 1
}

home_decide() {
  if [ -z "$1" ]; then
    if [ "$3" = edited ]; then printf '%s\n' claim || return 1; else printf '%s\n' keep || return 1; fi
  elif [ "$1" = "$2" ]; then
    if [ "$3" = absent ]; then printf '%s\n' keep || return 1; else printf '%s\n' copy || return 1; fi
  elif [ "$3" = edited ]; then
    printf '%s\n' refuse || return 1
  else
    printf '%s\n' keep || return 1
  fi
}

# NIXARCHY_FAKE_PLAN bends the answer for the malformed-answer tests; unset it is exact.
err_json() { jq -nc --arg e "$1" '{version:1,error:$e}'; }
home_plan_arm() {
  local flake=${NIXARCHY_FLAKE:-/etc/nixos} base caller action render msg
  base=$flake
  [ -d "$flake/hosts/$(uname -n)" ] && base="$flake/hosts/$(uname -n)"
  dest="$base/nixarchy-apps.nix"
  srcdir="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy"
  pinned=$(mktemp -d)
  trap 'rm -rf "$pinned"' EXIT
  [ -d "$flake" ] || { err_json "nixarchy-apply: no flake at $flake"; return 1; }
  msg=""
  caller=$(id -un)
  valid_user "$caller" || { err_json "nixarchy-apply: invalid user name: $caller"; return 1; }
  snapshot_home || { err_json "nixarchy-apply: cannot read $srcdir/home.nix"; return 1; }
  [ -r "${NIXARCHY_FAKE_SEED:?}" ] || { err_json "nixarchy-apply: cannot read the home seed"; return 1; }
  classify_home "$NIXARCHY_FAKE_SEED"
  read_owner 2>"$pinned/err" || { err_json "$(sed -n '1p' "$pinned/err")"; return 1; }
  action=$(home_decide "$owner" "$caller" "$home_state")
  case "$action" in
    claim | copy) render=$caller ;;
    keep) render=$owner ;;
    *) render="" ;;
  esac
  if [ "$action" = refuse ]; then
    msg="nixarchy-apply: home.nix belongs to $owner; $caller has edited theirs. Ask $owner to apply, or run nixarchy-apply --release-home to give the host up."
  fi
  jq -nc --arg o "$owner" --arg c "$caller" --arg s "$home_state" --arg a "$action" --arg r "$render" --arg m "$msg" \
    '{version:1, owner:(if $o=="" then null else $o end), caller:$c, state:$s, action:$a,
      renderUser:(if $r=="" then null else $r end), message:(if $a=="refuse" then $m else null end)}'
}
case "${1-}" in
  --release-home) exit 0 ;;
#HOMEPLAN-BEGIN
  --home-plan)
    [ "$#" = 2 ] && [ "$2" = --json ] || { echo "usage: nixarchy-apply --home-plan [--json]" >&2; exit 2; }
    rc=0; out=$(home_plan_arm) || rc=$?
    case "${NIXARCHY_FAKE_PLAN-}" in
      exit2) exit 2 ;;
      text) echo "not json"; exit 0 ;;
      v2) out=$(jq -c '.version = 2' <<<"$out") ;;
      noowner) out=$(jq -c 'del(.owner)' <<<"$out") ;;
      owner42) out=$(jq -c '.owner = 42' <<<"$out") ;;
      nullmsg) out=$(jq -c '.message = null | .action = "refuse"' <<<"$out") ;;
      twolines) out=$(printf '%s\n%s' "$out" "$out") ;;
      badstate) out=$(jq -c '.state = "weird"' <<<"$out") ;;
      badrender) out=$(jq -c '.renderUser = "mallory"' <<<"$out") ;;
      errkeys) printf '%s\n' '{"version":1,"error":"x","action":"keep"}'; exit 1 ;;
      extra) out=$(jq -c '. + {error:"bad", unavailable:"x", future:1}' <<<"$out") ;;
    esac
    printf '%s\n' "$out"; exit "$rc" ;;
#HOMEPLAN-END
esac
exit 0
