#!/usr/bin/env bash
# tests/adapter.sh -- the adapter against a throwaway selection, never yours.
#
# Every case builds a fresh XDG_CONFIG_HOME from the catalogue templates, so
# a failing test cannot leave the machine's own apps.nix edited.

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ADAPTER="$HERE/bin/nixarchy-pkg"
readonly TEMPLATES=/etc/nixarchy

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

check() {
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}

# A selection of this machine's own catalogue, in a directory that is thrown
# away afterwards.
fresh_config() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/nixarchy"
  local part
  for part in apps services advanced; do
    install -m600 "$TEMPLATES/$part-template.nix" "$dir/nixarchy/$part.nix"
  done
  printf '%s' "$dir"
}

[ -d "$TEMPLATES" ] || { echo "skip: $TEMPLATES not present (not a nixarchy machine)"; exit 0; }

echo "state"
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
state=$("$ADAPTER" state)
check "reports ok"                 jq -e '.ok == true'            <<<"$state"
check "finds catalogue apps"       jq -e '.apps     | length > 0' <<<"$state"
check "finds catalogue services"   jq -e '.services | length > 0' <<<"$state"
check "every app has an id"        jq -e '.apps     | all(.id     | length > 0)' <<<"$state"
check "every app has a category"   jq -e '.apps     | all(.category | length > 0)' <<<"$state"
check "nothing enabled in a fresh catalogue" \
                                   jq -e '.apps | map(select(.enabled)) | length == 0' <<<"$state"
check "settings rows are marked"   jq -e '.apps | map(select(.settings)) | length > 0' <<<"$state"
check "reports index staleness"    jq -e '.indexStale | type == "boolean"' <<<"$state"
rm -rf "$CONFIG"

echo "failure is a value, not an exit code"
out=$("$ADAPTER" nosuchcommand); rc=$?
check "exits 0 on an unknown command" test "$rc" = 0
check "says so in the object"         jq -e '.ok == false and (.error | length > 0)' <<<"$out"

echo
if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
