#!/usr/bin/env bash
# tests/adapter.sh -- the adapter against a throwaway selection, never yours.
#
# Every case builds a fresh XDG_CONFIG_HOME from the catalogue templates, so
# a failing test cannot leave the machine's own apps.nix edited.

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly ADAPTER="${ADAPTER_OVERRIDE:-$HERE/bin/nixarchy-pkg}"
readonly TEMPLATES=/etc/nixarchy

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

check() {
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}

# `check "..." ! grep ...` does not work: check runs "$@", so the `!` is
# looked up as a command and is not one. A function can be, so negation gets
# one rather than every negative assertion silently failing.
not() { ! "$@"; }

# The adapter keeps its lock and recovery data under XDG_STATE_HOME. Never
# the real one.
XDG_STATE_HOME=$(mktemp -d); export XDG_STATE_HOME
# A HOME for catalogue toggles only (ctoggle), so no writer reaches ~.
THOME=$(mktemp -d)
# The writers announce every toggle on the desktop. A test run is not news:
# silent stand-ins first on PATH, or each run floods the user's real
# notification centre with "queued -- not installed yet".
QUIET=$(mktemp -d)
for n in omarchy-notification-send notify-send; do
  printf '#!/bin/sh\nexit 0\n' >"$QUIET/$n"; chmod +x "$QUIET/$n"
done
PATH="$QUIET:$PATH"; export PATH
# A catalogue of our own: the adapter only reads the `optionsjson=` line of
# nixarchy-search, so the option-form checks need no real index (#61).
FIXSTUB=$(mktemp -d)
printf '#!/bin/sh\noptionsjson=%s\n' "$HERE/tests/fixtures/options.json" >"$FIXSTUB/nixarchy-search"
chmod +x "$FIXSTUB/nixarchy-search"
fx() { PATH="$FIXSTUB:$PATH" "$ADAPTER" "$@"; }

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

# Host-gated services: toggling one can prompt, or write outside the
# throwaway dirs (openssh: ~/.ssh/authorized_keys). Never toggled here.
# Add any service whose nixarchy-service-enable branch has a gate.
readonly GATED_SERVICES=" openssh "

# The first app that round-trips: an id the writers accept ([a-z0-9_-],
# nixarchy-app-enable:23), written off as `# <id>.enable = true;` -- so
# neither a `.settings` row nor an on-by-default app (`# <id>.enable =
# false;`, which toggles off to a live `false`). LC_ALL=C: template notes
# carry UTF-8 that `.` will not match in every locale. `q`, not `| head`:
# under pipefail a reader that stops early can kill the script.
pick_app() {
  LC_ALL=C sed -nE '/^[[:space:]]*#[[:space:]]*(programs\.nixarchy\.apps\.)?([a-z0-9_-]+)\.enable = true;[[:space:]]+#@ \2([[:space:]].*)?$/{s//\2/p;q;}' "$1"
}

# Services name their own options (virtualisation.podman.enable,
# hardware.graphics.enable32Bit, ...), so any `# <option> = true;  #@ <id>`.
pick_service() {
  local id
  LC_ALL=C sed -nE 's/^[[:space:]]*#[[:space:]]*[A-Za-z0-9_.-]+ = true;[[:space:]]+#@ ([a-z0-9_-]+)([[:space:]].*)?$/\1/p' "$1" |
    { while read -r id; do
        case "$GATED_SERVICES" in *" $id "*) continue ;; esac
        printf '%s\n' "$id"; break
      done
      cat >/dev/null; }   # drain, so sed never writes to a closed pipe
}

# A catalogue toggle: no terminal to prompt on, and a HOME of its own.
# A prefix assignment (XDG_CONFIG_HOME=... ctoggle ...) reaches the adapter:
# bash exports it for the duration of the function call.
ctoggle() { HOME="$THOME" setsid -w "$ADAPTER" toggle "$@" </dev/null; }

# The catalogue sections build from this machine's own templates, so they
# only run on a nixarchy box. The rest -- flake, search, apply, the mode and
# symlink checks, and the source-shape greps -- build their own fixtures or
# stub the writer, so they run anywhere. In CI they are the only protection
# the adapter has on a pull request (#44).
#
# The bodies below are NOT re-indented inside their guards, deliberately:
# bash does not care, and it keeps this diff to the guard lines instead of a
# 350-line reformat that would bury what actually changed.
HAVE_CATALOGUE=true
[ -d "$TEMPLATES" ] || { HAVE_CATALOGUE=false
  echo "note: $TEMPLATES not present; catalogue sections will be skipped"; }

# The ids the catalogue cases toggle, chosen from this catalogue, never
# named here: a named one (brave) vanished from the catalogue and took
# eleven checks with it (#68).
APP="" SVC="" CAN_TOGGLE=false
if $HAVE_CATALOGUE; then
  probe=$(fresh_config)
  APP=$(pick_app "$probe/nixarchy/apps.nix")
  SVC=$(pick_service "$probe/nixarchy/services.nix")
  rm -rf "$probe"
  echo "note: catalogue cases use app '${APP:-none}', service '${SVC:-none}'; never toggled:$GATED_SERVICES"
  CAN_TOGGLE=true
  [ -n "$APP" ] || { fail "no app row the tests can round-trip (every row is a settings row, on by default, or not in the '# <id>.enable = true;  #@ <id>' shape)"; CAN_TOGGLE=false; }
  [ -n "$SVC" ] || { fail "no service row the tests can round-trip (every row is gated, or not in the '# <option> = true;  #@ <id>' shape)"; CAN_TOGGLE=false; }
fi

if $HAVE_CATALOGUE; then
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
# The panel offers the other channel by name, so a wrong answer here offers
# the channel the machine is already on -- which nixarchy-pkg-add:112
# refuses. `custom` is a legitimate answer, not a failure.
check "reports the machine channel" \
                                   jq -e '.channel | test("^(stable|unstable|custom)$")' <<<"$state"
rm -rf "$CONFIG"

# The system flake. Every case here builds a throwaway flake in a temp
# directory and points NIXARCHY_FLAKE at it, so a failing test cannot edit
# the machine's own -- the same rule fresh_config() follows for apps.nix.
#
# The input being declared is a LOCAL flake, so none of this needs network.
# Changing an option's value in one command.
#
# The point of `opt replace` is atomicity: `opt set` refuses a path that is
# already present, so changing a value used to mean remove-then-set, and a
# set that failed after a successful remove lost the option outright.
echo "opt replace"
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"

# Not a non-zero exit: this adapter reports failure as a value and exits 0
# throughout, which the "unknown command" cases below also assert. A caller
# probing for the subcommand reads the object.
check "opt replace with no arguments is a usage error" \
  jq -e '.ok == false and (.error | startswith("usage:"))' \
  <<<"$("$ADAPTER" opt replace 2>&1 || true)"

out=$("$ADAPTER" opt replace services.openssh.enable true 2>&1 || true)
check "refuses an option that is not set"  jq -e '.ok == false' <<<"$out"

"$ADAPTER" opt set services.openssh.ports "[ 22 ]" >/dev/null 2>&1 || true
check "opt set put it there" grep -q '#@opt services.openssh.ports$' "$APPSNIX"
before_line=$(grep -n '#@opt services.openssh.ports$' "$APPSNIX" | cut -d: -f1)

out=$("$ADAPTER" opt replace services.openssh.ports "[ 2222 ]" 2>&1 || true)
check "replaces a present option"          jq -e '.ok == true' <<<"$out"
check "the new value is in the file"       grep -q '2222' "$APPSNIX"
check "the old value is gone"              not grep -q '\[ 22 \]' "$APPSNIX"
check "the marker survived"                grep -q '#@opt services.openssh.ports$' "$APPSNIX"
check "the line kept its position" \
  test "$(grep -n '#@opt services.openssh.ports$' "$APPSNIX" | cut -d: -f1)" = "$before_line"

# A refused value must leave the file untouched, not half-written.
before=$(md5sum < "$APPSNIX")
out=$("$ADAPTER" opt replace services.openssh.ports 'pkgs.nonexistent-thing' 2>&1 || true)
check "an unparseable value is refused"    jq -e '.ok == false' <<<"$out"
check "and the file is byte-identical"     test "$(md5sum < "$APPSNIX")" = "$before"
rm -rf "$CONFIG"

else
  echo "skip: needs $TEMPLATES (not a nixarchy machine)"
fi
echo "flake"
FLAKE_TMP=$(mktemp -d)
cleanup_flake() { chmod -R u+w "$FLAKE_TMP" 2>/dev/null || true; rm -rf "$FLAKE_TMP"; }
trap cleanup_flake EXIT

# Something to declare: two nixosModules, the `default` + alias shape every
# real flake measured for this uses.
mkdir -p "$FLAKE_TMP/lib"
printf '{\n  outputs = { self }: { nixosModules.default = { }; nixosModules.thing = { }; };\n}\n' \
  > "$FLAKE_TMP/lib/flake.nix"
git -C "$FLAKE_TMP/lib" init -q .
git -C "$FLAKE_TMP/lib" add -A
git -C "$FLAKE_TMP/lib" -c user.email=t@t -c user.name=t commit -qm fixture

fresh_flake() {
  local d; d=$(mktemp -d -p "$FLAKE_TMP")
  printf '{\n  description = "throwaway";\n\n  inputs = {\n    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";\n  };\n\n  outputs = { self, ... }@inputs: { names = builtins.attrNames inputs; };\n}\n' \
    > "$d/flake.nix"
  git -C "$d" init -q .
  git -C "$d" add -A
  printf '%s' "$d"
}

# The machine channel. The flat `inputs.nixpkgs.url` form is read only where
# the writer's own parse (the block-shaped line) finds nothing (#63 A5).
FK=$(fresh_flake)
printf '{\n  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";\n  outputs = _: {};\n}\n' > "$FK/flake.nix"
check "a flat nixpkgs url names the channel" \
  jq -e '.channel == "unstable"' <<<"$(NIXARCHY_FLAKE="$FK" "$ADAPTER" state)"
printf '{\n  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";\n  inputs = {\n    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";\n  };\n}\n' > "$FK/flake.nix"
check "the writer's line wins over a flat one" \
  jq -e '.channel == "unstable"' <<<"$(NIXARCHY_FLAKE="$FK" "$ADAPTER" state)"

# The panel names the directory it reads (#63 A6).
FK=$(fresh_flake)
out=$(NIXARCHY_FLAKE="$FK" "$ADAPTER" state)
# shellcheck disable=SC2016
check "state names the flake directory" \
  jq -e --arg d "$FK" '.flakeDir == $d and .flakeFound == true' <<<"$out"
out=$(NIXARCHY_FLAKE="$FLAKE_TMP/missing" "$ADAPTER" state)
check "state says when there is no flake.nix" \
  jq -e '.flakeFound == false' <<<"$out"

# FIRST, because the whole design rests on it: a path assignment merges
# with an attrset that already exists, so an input can be declared by
# appending one top-level line rather than editing the inputs block.
merged=$(printf '{ a = { x = 1; }; a.y = 2; }' | nix-instantiate --eval --strict - 2>/dev/null || true)
check "a path assignment merges with an existing attrset" \
  test "$merged" = '{ a = { x = 1; y = 2; }; }'

# The build sandbox has no network or writable nix store; CI and developer machines run these.
if [ "${NIXARCHY_PKG_TEST_OFFLINE:-0}" != 1 ]; then
FK=$(fresh_flake)
out=$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake add lib "path:$FLAKE_TMP/lib" 2>&1 || true)
check "declares an input"            jq -e '.ok == true'          <<<"$out"
check "does not guess an import" jq -e 'has("import") | not' <<<"$out"
check "writes exactly one marked line" \
  test "$(grep -c '#@flake-input lib$' "$FK/flake.nix")" = 1
check "leaves the existing inputs block alone" \
  grep -q 'nixpkgs.url' "$FK/flake.nix"
check "the flake still evaluates"    nix flake metadata "$FK" --no-update-lock-file
check "lists what it declared" \
  jq -e '.inputs | map(.name) | index("lib")' <<<"$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake list)"

# A name the flake already has is an error either way, so it is refused.
out=$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake add nixpkgs "path:$FLAKE_TMP/lib" 2>&1 || true)
check "refuses a name the flake already declares" jq -e '.ok == false' <<<"$out"
check "and refuses it again for the tool's own"  \
  jq -e '.ok == false' <<<"$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake add lib "path:$FLAKE_TMP/lib" 2>&1 || true)"

# Nothing survives a failure: both files come back byte for byte.
before_nix=$(md5sum < "$FK/flake.nix"); before_lock=$(md5sum < "$FK/flake.lock")
out=$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake add nope "path:$FLAKE_TMP/does-not-exist" 2>&1 || true)
check "refuses an unresolvable input"      jq -e '.ok == false' <<<"$out"
check "restores flake.nix byte for byte"   test "$(md5sum < "$FK/flake.nix")" = "$before_nix"
check "restores flake.lock byte for byte"  test "$(md5sum < "$FK/flake.lock")" = "$before_lock"

# Removal is refused while anything still names it, because succeeding
# would break evaluation.
printf '  # inputs.lib.nixosModules.default\n' >> "$FK/flake.nix"
check "refuses to remove an input still referred to" \
  jq -e '.ok == false' <<<"$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake remove lib 2>&1 || true)"
sed -i '/# inputs.lib.nixosModules.default/d' "$FK/flake.nix"

out=$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake remove lib 2>&1 || true)
check "removes it"                   jq -e '.ok == true' <<<"$out"
check "takes the line out"           test "$(grep -c '#@flake-input lib$' "$FK/flake.nix" || true)" = 0
check "and still evaluates"          nix flake metadata "$FK" --no-update-lock-file
check "lists nothing afterwards"     jq -e '.inputs | length == 0' <<<"$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake list)"

# Names are checked whole, refs are data, and the remove guard can be
# neither steered nor fooled by a hyphen -- and it looks past flake.nix (#29).
FK=$(fresh_flake)
fsum() { md5sum < "$FK/flake.nix"; }
fl() { NIXARCHY_FLAKE="$FK" "$ADAPTER" flake "$@" 2>&1 || true; }
before=$(fsum)
for bad in 'foo.bar' 'foo bar' '1x'; do
  check "add refuses the input name '$bad'" jq -e '.ok == false' <<<"$(fl add "$bad" "path:$FLAKE_TMP/lib")"
done
# shellcheck disable=SC2016  # a literal ${x} is the input under test
for bad in 'path:/tmp/a"; y = 1; z = "' 'path:/tmp/a\b' 'path:/tmp/${x}' 'path:/tmp/a b'; do
  check "add refuses the flakeref $bad" jq -e '.ok == false' <<<"$(fl add x "$bad")"
done
check "and flake.nix is untouched" test "$(fsum)" = "$before"

fl add sub "path:$FLAKE_TMP/lib" >/dev/null
for bad in 'sub$' '.*'; do
  check "remove refuses the name '$bad'" jq -e '.ok == false' <<<"$(fl remove "$bad")"
done
check "and sub is still declared" grep -q '#@flake-input sub$' "$FK/flake.nix"

mkdir -p "$FK/hosts/x"
printf '{ inputs, ... }: {\n  imports = [ inputs.sub.nixosModules.default ];\n}\n' > "$FK/hosts/x/default.nix"
out=$(fl remove sub)
check "a reference in a host file blocks removal" jq -e '.ok == false' <<<"$out"
check "and the refusal says where" jq -e '.error | contains("hosts/x/default.nix:2")' <<<"$out"
rm -r "$FK/hosts"

sed -i 's/description = "throwaway";/description = "see sub-projects";/' "$FK/flake.nix"
out=$(fl remove sub)
check "sub-projects is not a reference to sub" jq -e '.ok == true' <<<"$out"
check "and success says what was not checked" jq -e '.message | contains("hosts were not evaluated")' <<<"$out"

fl add sub "path:$FLAKE_TMP/lib" >/dev/null
printf '{\n' >> "$FK/flake.nix"
before=$(fsum)
check "remove refuses a flake already broken" jq -e '.ok == false and (.error | contains("as it stands"))' <<<"$(fl remove sub)"
check "and leaves it as it was" test "$(fsum)" = "$before"

# A flake whose outer brace is not a line of its own is declined rather
# than guessed at: appending to the wrong scope parses and means something
# else, which is worse than refusing.
NA=$(mktemp -d -p "$FLAKE_TMP")
printf 'rec {\n  outputs = { self }: { };\n}\n' > "$NA/flake.nix"
check "declines a flake it cannot find the top of" \
  jq -e '.ok == false' <<<"$(NIXARCHY_FLAKE="$NA" "$ADAPTER" flake add x "path:$FLAKE_TMP/lib" 2>&1 || true)"

# What a flake exposes. nixosModules enumerates; the other module
# namespaces are conventions rather than schema and come back opaque, and
# must be NAMED as unreadable rather than drawn as an empty list.
out=$("$ADAPTER" flake show "path:$FLAKE_TMP/lib" 2>&1 || true)
check "enumerates nixosModules"      jq -e '.nixosModules | index("default")' <<<"$out"
check "sees the alias too"           jq -e '.nixosModules | index("thing")'   <<<"$out"
check "reports opaque namespaces as a list" jq -e '.opaque | type == "array"' <<<"$out"
else echo "  skip: needs a writable nix store or the network (flake inputs)"; fi
check "says so when a flake cannot be read" \
  jq -e '.ok == false and (.message | length > 0)' \
  <<<"$("$ADAPTER" flake show "path:$FLAKE_TMP/nowhere" 2>&1 || true)"

echo "search"
# These need no real index, so they always run (#30).
out=$("$ADAPTER" search git --limit); rc=$?
check "a flag without its value is a value, not silence" \
  jq -e '.ok == false and (.error | contains("--limit"))' <<<"$out"
check "and exits 0" test "$rc" = 0
check "the same for --kind" jq -e '.ok == false' <<<"$("$ADAPTER" search git --kind)"
STUBCACHE=$(mktemp -d); mkdir -p "$STUBCACHE/nixarchy"
printf 'pkg\tfoo\tFoo thing [unfree]\tunfree\t\npkg\tbar\tBar thing [unfree]\t\t\npkg\tbaz\tBaz [broken]\tbroken\t\npkg\t-dash\tA dash\t\t\npkg\topenssh\tSecure SHell server\t\t\npkg\tdropbear\tsmall ssh server\t\t\n' \
  > "$STUBCACHE/nixarchy/index.tsv"
stub_search() { XDG_CACHE_HOME="$STUBCACHE" "$ADAPTER" search "$@"; }
check "a query after -- may start with a dash" \
  jq -e '.rows[0].name == "-dash"' <<<"$(stub_search -- -dash)"
out=$(stub_search -- thing)
check "unfree is said once, by the flag" \
  jq -e '.rows | map(select(.name == "foo"))[0].summary == "Foo thing"' <<<"$out"
check "an index without the flag keeps its only warning" \
  jq -e '.rows | map(select(.name == "bar"))[0].summary == "Bar thing [unfree]"' <<<"$out"
check "broken is said once too" \
  jq -e '.rows[0].summary == "Baz"' <<<"$(stub_search -- baz)"
server_ssh=$(stub_search -- "server ssh")
ssh_server=$(stub_search -- "ssh server")
# shellcheck disable=SC2016  # $other is jq's variable.
check "search words match in either order" jq -e --argjson other "$ssh_server" \
  '.rows | map(.name) == ($other.rows | map(.name)) and (map(.name) | index("openssh") != null and index("dropbear") != null)' <<<"$server_ssh"
# shellcheck disable=SC2016  # $other is jq's variable.
check "spaces around a word keep its ranking" jq -e --argjson other "$(stub_search -- ssh)" \
  '.rows | map(.name) == ($other.rows | map(.name))' <<<"$(stub_search -- "  ssh  ")"
check "all search words must match" jq -e '.rows | length == 0' \
  <<<"$(stub_search -- "ssh nothinglikethis")"
check "a blank search is refused" jq -e '.ok == false' <<<"$(stub_search -- "   ")"
SEARCHCFG=$(mktemp -d)
mkdir -p "$SEARCHCFG/nixarchy"
printf '{ ... }:\n{\n  x.y = true;  #@opt x.y\n  # x.z = ;  #@opt x.z\n}\n' >"$SEARCHCFG/nixarchy/apps.nix"
printf 'opt\tx.y\tSet option\tboolean\t\nopt\tx.z\tScaffold option\tstring\t\nopt\tx.a\tAbsent option\tboolean\t\n' \
  >>"$STUBCACHE/nixarchy/index.tsv"
out=$(XDG_CONFIG_HOME="$SEARCHCFG" stub_search --kind opt -- x.)
check "search joins a set option to its current line" jq -e \
  '.rows | map(select(.name == "x.y"))[0] | .set == true and .current == "true"' <<<"$out"
check "search keeps a scaffold distinct from a set option" jq -e \
  '.rows | map(select(.name == "x.z"))[0] | .set == false and (.current | contains("x.z = ;"))' <<<"$out"
check "search leaves an absent option's state unknown" jq -e \
  '.rows | map(select(.name == "x.a"))[0] | .set == null and .current == null' <<<"$out"
check "non-option search rows have no option state" jq -e \
  '.rows | map(select(.kind == "pkg"))[0] | has("set") | not' <<<"$(stub_search -- foo)"
rm -rf "$SEARCHCFG"
for i in $(seq 5000); do printf 'pkg\tssh%s\tssh tool\t\t\n' "$i"; done > "$STUBCACHE/nixarchy/index.tsv"
check "a truncated search still answers once in JSON" jq -e '.ok == true and (.rows | length == 1)' \
  <<<"$(stub_search --limit 1 -- ssh)"
rm -rf "$STUBCACHE"

if [ -s "${XDG_CACHE_HOME:-$HOME/.cache}/nixarchy/index.tsv" ]; then
  hits=$("$ADAPTER" search ripgrep --kind pkg --limit 5)
  check "finds a package"            jq -e '.rows | length > 0'      <<<"$hits"
  check "ranks the exact name first" jq -e '.rows[0].name == "ripgrep"' <<<"$hits"
  check "honours --limit"            jq -e '.rows | length <= 5'     <<<"$hits"
  check "package rows carry no type" jq -e '.rows | all(.type == "")' <<<"$hits"
  opts=$("$ADAPTER" search openssh.ports --kind opt --limit 3)
  check "option rows carry a type"   jq -e '.rows[0].type | length > 0' <<<"$opts"
  check "preview is unescaped"       jq -e '.rows[0].preview | contains("\n")' <<<"$hits"
  check "a bad --limit is a value"   jq -e '.ok == false' <<<"$("$ADAPTER" search x --limit abc)"
  check "a bad --kind is a value"    jq -e '.ok == false' <<<"$("$ADAPTER" search x --kind nope)"
else
  echo "  skip (no search index; run nixarchy-pkg reindex)"
fi

if $HAVE_CATALOGUE; then
echo "writers"
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
check "an unknown id is a value"    jq -e '.ok == false' <<<"$("$ADAPTER" toggle app nosuchapp)"
# shellcheck disable=SC2016  # $id is jq's, bound by --arg
if $CAN_TOGGLE; then
on=$(ctoggle app "$APP")
check "toggling on reports enabled" jq -e --arg id "$APP" '.apps[] | select(.id==$id) | .enabled' <<<"$on"
# $APP is [a-z0-9_-]+ (pick_app), so it is safe inside a regex.
check "the file really changed"     grep -qE "^[[:space:]]*(programs\.nixarchy\.apps\.)?$APP\.enable = true;[[:space:]]+#@ $APP([[:space:]]|\$)" "$CONFIG/nixarchy/apps.nix"
off=$(ctoggle app "$APP")
check "toggling off reports disabled" jq -e --arg id "$APP" '.apps[] | select(.id==$id) | .enabled | not' <<<"$off"
svc=$(ctoggle service "$SVC")
check "services use their own file" jq -e --arg id "$SVC" '.services[] | select(.id==$id) | .enabled' <<<"$svc"
check "an unknown kind is a value"  jq -e '.ok == false' <<<"$(ctoggle widget "$APP")"
fi

added=$("$ADAPTER" pkg add ripgrep)
check "pkg add lands in the list"   jq -e '.packages | map(.attr) | index("ripgrep")' <<<"$added"
removed=$("$ADAPTER" pkg remove ripgrep)
check "pkg remove takes it out"     jq -e '.packages | map(.attr) | index("ripgrep") | not' <<<"$removed"
check "apps.nix still parses"       nix-instantiate --parse "$CONFIG/nixarchy/apps.nix"
rm -rf "$CONFIG"

echo "fixture options"
check "the fixture catalogue answers a boolean" \
  jq -e '.ok == true and .widget == "boolean"' <<<"$(fx opt describe t.bool)"
check "and says so for an option it lacks" \
  jq -e '.ok == false' <<<"$(fx opt describe t.nope)"
check "port bounds are strings" jq -e '.min == "0" and .max == "65535"' <<<"$(fx opt describe t.port)"
check "signed integer bounds are strings" jq -e '.min == "-9223372036854775808" and .max == "9223372036854775807"' <<<"$(fx opt describe t.int)"

CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"
before=$(sha256sum "$APPSNIX")
check "out-of-range port is refused" jq -e '.ok == false and (.error | contains("outside"))' <<<"$(fx opt set t.port 70000)"
check "refused port leaves file untouched" test "$before" = "$(sha256sum "$APPSNIX")"
check "leading zeros are refused" jq -e '.ok == false and (.error | contains("leading zeros"))' <<<"$(fx opt set t.port 007)"
check "large unsigned literal writes" jq -e '.ok' <<<"$(fx opt set t.u32 4294967295)"
check "negative range lower bound refuses -10" jq -e '.ok == false' <<<"$(fx opt set t.neg -10)"
check "negative range lower bound accepts -9" jq -e '.ok' <<<"$(fx opt set t.neg -9)"
check "out-of-range list item is refused" jq -e '.ok == false and (.error | contains("outside"))' <<<"$(fx opt set t.ports '[ 0 70000 ]')"
check "integer list accepts its bounds" jq -e '.ok' <<<"$(fx opt set t.ports '[ 0 65535 ]')"
check "nullable integer accepts null" jq -e '.ok' <<<"$(fx opt set t.nullPort null)"
check "Nix expression passes literal check" jq -e '.ok' <<<"$(fx opt set t.port 'builtins.toString 80')"
check "unsigned literal can be set" jq -e '.ok' <<<"$(fx opt set t.uint 0)"
before=$(sha256sum "$APPSNIX")
check "replace refuses negative unsigned literal" jq -e '.ok == false and (.error | contains("outside"))' <<<"$(fx opt replace t.uint -1)"
check "refused replace leaves file untouched" test "$before" = "$(sha256sum "$APPSNIX")"
rm -rf "$CONFIG"

echo "options"
if [ -n "$(command -v nixarchy-search)" ]; then
  d=$("$ADAPTER" opt describe services.openssh.enable)
  check "boolean maps to a checkbox"  jq -e '.widget == "boolean"' <<<"$d"
  d=$("$ADAPTER" opt describe services.openssh.ports)
  check "a list falls through to a scaffold" jq -e '.widget == "scaffold"' <<<"$d"
  check "literalExpression is unwrapped"     jq -e '.default | contains("22")' <<<"$d"
  d=$("$ADAPTER" opt describe networking.hostName)
  check "a string maps to a field"    jq -e '.widget == "string"' <<<"$d"
  d=$("$ADAPTER" opt describe boot.binfmt.registrations.\<name\>.recognitionType)
  check "an enum offers its choices"  jq -e '.widget == "enum" and (.choices | length == 2)' <<<"$d"
  check "an unknown option is a value" jq -e '.ok == false' <<<"$("$ADAPTER" opt describe not.a.real.option)"

  # All the alternatives or none (#28). A numeric enum offers its numbers;
  # a type whose list is prose or mixed goes to the scaffold, and says so.
  d=$("$ADAPTER" opt describe security.pam.oath.digits)
  if jq -e '.ok' <<<"$d" >/dev/null; then
    check "a numeric enum offers its numbers" jq -e '.widget == "enum" and .choices == ["6","7","8"]' <<<"$d"
  else
    echo "  skip (no security.pam.oath.digits on this system)"
  fi
  oj=$(sed -n 's/^optionsjson=\(.*\)$/\1/p' "$(command -v nixarchy-search)" | head -1)
  unlisted=$(jq -r 'to_entries | map(select(.value.type | startswith("one of ")))
    | map(select(.value.type | test("^one of (?:\"(?:[^\"\\\\]|\\\\.)*\"|-?[0-9]+)(?:, (?:\"(?:[^\"\\\\]|\\\\.)*\"|-?[0-9]+))*$") | not))
    | .[0].key // empty' "$oj")
  if [ -n "$unlisted" ]; then
    d=$("$ADAPTER" opt describe "$unlisted")
    check "an unlisted enum is a scaffold, and says so" \
      jq -e '.widget == "scaffold" and .choicesUnavailable == true and .choices == []' <<<"$d"
  fi
fi

# A scaffold's marked line, where nixarchy-search puts one: inside the
# module, before its closing brace. Appended to the end of the file it would
# sit after the module, and anything that turned it into a value would be
# refused, rightly, as a syntax error.
add_scaffold() {
  local tmp; tmp=$(mktemp)
  awk -v p="$1" '!ins && /^}[[:space:]]*$/ { printf "\n  # %s = ;  #@opt %s\n", p, p; ins = 1 } { print }' "$2" > "$tmp"
  mv "$tmp" "$2"
}

# What apps.nix already says, reported to the form (#28).
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
if [ -n "$(command -v nixarchy-search)" ]; then
  check "an option not in apps.nix is absent" \
    jq -e '.current.state == "absent"' <<<"$("$ADAPTER" opt describe programs.mtr.enable)"
  "$ADAPTER" opt set programs.mtr.enable true >/dev/null
  check "a set option reports its value" \
    jq -e '.current == {state: "set", value: "true"}' <<<"$("$ADAPTER" opt describe programs.mtr.enable)"
  add_scaffold programs.htop.enable "$CONFIG/nixarchy/apps.nix"
  check "a scaffold line is a scaffold" \
    jq -e '.current.state == "scaffold"' <<<"$("$ADAPTER" opt describe programs.htop.enable)"
fi
rm -rf "$CONFIG"

# Values are written as typed (#28). The writers used to squeeze every run
# of spaces, strings included, and to flatten lines whose newlines mean
# something.
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"
"$ADAPTER" opt set networking.hostName '"a  b"' >/dev/null
check "spaces inside a string survive" grep -qF 'networking.hostName = "a  b";' "$APPSNIX"
before=$(md5sum < "$APPSNIX")
out=$("$ADAPTER" opt set environment.etc.x.text $'{\n  a = \x27\x27x\x27\x27;\n}')
check "a multi-line attrset with a string is written" jq -e '.ok == true' <<<"$out"
check "its value is on one line" grep -qF "environment.etc.x.text = {   a = ''x''; };" "$APPSNIX"
before=$(md5sum < "$APPSNIX")
out=$("$ADAPTER" opt set environment.etc.y.text $'{ # c\n  a = 1;\n}')
check "a multi-line value with # is refused" jq -e '.ok == false' <<<"$out"
check "and the file is untouched"          test "$(md5sum < "$APPSNIX")" = "$before"
"$ADAPTER" opt set nix.settings $'{\n  cores = 2;\n}' >/dev/null
check "a plain multi-line value is one line" grep -qF 'nix.settings = {   cores = 2; };' "$APPSNIX"
check "and parses"                         nix-instantiate --parse "$APPSNIX"
# replace on a scaffold: the marked line becomes a value, and stays removable.
add_scaffold programs.htop.enable "$APPSNIX"
check "replace turns a scaffold into a value" \
  jq -e '.ok' <<<"$("$ADAPTER" opt replace programs.htop.enable true)"
check "the value line is byte-exact" \
  grep -qx '  programs.htop.enable = true;  #@opt programs.htop.enable' "$APPSNIX"
"$ADAPTER" opt remove programs.htop.enable >/dev/null
check "and it can still be removed" not grep -q '#@opt programs.htop.enable' "$APPSNIX"
check "leaving a file that parses"  nix-instantiate --parse "$APPSNIX"
rm -rf "$CONFIG"

# Multi-line values are either re-emitted as one string, flattened with the
# same Nix tree, or refused without touching apps.nix.
check_one_line() {
  local mode=$1 name=$2 value=$3 expected=$4 out before
  CONFIG=$(mktemp -d); export XDG_CONFIG_HOME="$CONFIG"
  mkdir -p "$CONFIG/nixarchy"
  APPSNIX="$CONFIG/nixarchy/apps.nix"
  printf '{ ... }:\n{\n}\n' > "$APPSNIX"
  if [ "$mode" = replace ]; then
    "$ADAPTER" opt set x.y true >/dev/null
  fi
  before=$(md5sum < "$APPSNIX")
  out=$("$ADAPTER" opt "$mode" x.y "$value" 2>&1)
  if [ "$expected" = refused ]; then
    check "$mode $name refuses once" jq -se 'length == 1 and .[0].ok == false and (.[0].error | type == "string")' <<<"$out"
    if [ "$name" = 'decoded marker' ]; then
      check "$mode $name names the marker" jq -e '.error | contains("#@")' <<<"$out"
    fi
    check "$mode $name leaves apps.nix unchanged" test "$(md5sum < "$APPSNIX")" = "$before"
  else
    check "$mode $name succeeds" jq -e '.ok == true' <<<"$out"
    check "$mode $name writes one line" grep -qF "x.y = $expected;" "$APPSNIX"
  fi
  rm -rf "$CONFIG"
}

literal=$'\x27\x27\n  a "q"\n  \x27\x27${x}\n\x27\x27'
# shellcheck disable=SC2016 # ${x} belongs to Nix, not bash.
expected_literal='"a \"q\"\n\${x}\n"'
for mode in set replace; do
  check_one_line "$mode" 'list whitespace' $'[ 1\n 2 ]' '[ 1  2 ]'
  check_one_line "$mode" 'newline in list string' $'[ "a\nb" ]' refused
  check_one_line "$mode" 'comment in attrset' $'{ a = 1; # c\n b = 2; }' refused
  check_one_line "$mode" 'indented string literal' "$literal" "$expected_literal"
  check_one_line "$mode" 'expression with getEnv' $'"a" +\n builtins.getEnv "X" + ""' '"a" +  builtins.getEnv "X" + ""'
  check_one_line "$mode" 'decoded marker' $'"#\\@pkg x\n"' refused
  check_one_line "$mode" 'control character' $'"a\nb\001"' refused
  check_one_line "$mode" 'tab escape' $'"a\n\tb"' '"a\n\tb"'
  check_one_line "$mode" 'carriage return escape' $'"a\n\\rb"' '"a\n\rb"'
done
for mode in set replace; do
  CONFIG=$(mktemp -d); export XDG_CONFIG_HOME="$CONFIG"
  mkdir -p "$CONFIG/nixarchy"
  APPSNIX="$CONFIG/nixarchy/apps.nix"
  if [ "$mode" = replace ]; then
    printf '{ ... }:\n{ x.y = true;  #@opt x.y\n} # end\n' > "$APPSNIX"
  else
    printf '{ ... }:\n{ } # end\n' > "$APPSNIX"
  fi
  before=$(md5sum < "$APPSNIX")
  out=$("$ADAPTER" opt "$mode" x.y $'[ 1\n 2 ]' 2>&1)
  check "$mode missing probe insertion refuses once" jq -se 'length == 1 and .[0].ok == false and (.[0].error | type == "string")' <<<"$out"
  check "$mode missing probe insertion gives the one-line refusal" jq -se '.[0].error | contains("on one line")' <<<"$out"
  check "$mode missing probe insertion leaves apps.nix unchanged" test "$(md5sum < "$APPSNIX")" = "$before"
  rm -rf "$CONFIG"
done
check "literal evaluation matches re-emitted value" test \
  "$(nix-instantiate --eval --strict --json -E "$literal" 9>&- 8>&-)" = \
  "$(nix-instantiate --eval --strict --json -E "$expected_literal" 9>&- 8>&-)"

CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
set_out=$("$ADAPTER" opt set services.openssh.settings.PermitRootLogin '"no"')
check "opt set reports ok" jq -e '.ok' <<<"$set_out"
# The bytes nixarchy-opt-remove walks and checks.options asserts. A near
# miss here is a line nothing can ever remove again.
check "the line is byte-exact" \
  grep -qx '  services.openssh.settings.PermitRootLogin = "no";  #@opt services.openssh.settings.PermitRootLogin' \
  "$CONFIG/nixarchy/apps.nix"
check "the file still parses" nix-instantiate --parse "$CONFIG/nixarchy/apps.nix"
# awk -v would process escapes in the value; ENVIRON does not.
"$ADAPTER" opt set networking.hostName '"a\"b"' >/dev/null
check "a backslash in the value survives" \
  grep -qx '  networking.hostName = "a\\"b";  #@opt networking.hostName' "$CONFIG/nixarchy/apps.nix"
rm_out=$("$ADAPTER" opt remove services.openssh.settings.PermitRootLogin)
check "nixarchy-opt-remove finds what we wrote" \
  jq -e '.options | map(.path) | index("services.openssh.settings.PermitRootLogin") | not' <<<"$rm_out"
check "an empty value writes nothing" \
  jq -e '.message | contains("kept the default")' <<<"$("$ADAPTER" opt set services.journald.storage '')"
broken=$("$ADAPTER" opt set boot.kernelParams '[ "quiet"')
check "a broken value is refused"      jq -e '.ok == false' <<<"$broken"
check "and the backup is restored"     nix-instantiate --parse "$CONFIG/nixarchy/apps.nix"
check "a duplicate path is refused"    jq -e '.ok == false' <<<"$("$ADAPTER" opt set networking.hostName '"z"')"
rm -rf "$CONFIG"

echo "pending"
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
FLAKE=$(mktemp -d); export NIXARCHY_FLAKE="$FLAKE"
check "a machine that never applied says so" jq -e '.neverApplied' <<<"$("$ADAPTER" pending)"
mkdir -p "$FLAKE/nixarchy"
for part in apps services advanced; do cp "$CONFIG/nixarchy/$part.nix" "$FLAKE/nixarchy/$part.nix"; done
check "a matching flake has nothing queued" jq -e '.count == 0' <<<"$("$ADAPTER" pending)"
if $CAN_TOGGLE; then
ctoggle app "$APP" >/dev/null
# A toggle is one choice, though the diff sees a line leave and a line arrive.
check "a toggle counts once"   jq -e '.count == 1 and .changes[0].change == "on"' <<<"$("$ADAPTER" pending)"
"$ADAPTER" pkg add ripgrep >/dev/null
# #@pkgs-begin / #@pkgs-end are scaffolding pkg-add creates, not choices.
check "a package counts once"  jq -e '.count == 2' <<<"$("$ADAPTER" pending)"
ctoggle app "$APP" >/dev/null
check "toggling back drops it" jq -e '.count == 1' <<<"$("$ADAPTER" pending)"
# A row that is commented out on both sides is not a queued change, however
# much its text moved. Topping a catalogue up appends commented rows, and
# counting those reported sixteen things waiting to be built when the answer
# was none.
printf '\n    # newthing.enable = true;  #@ newthing\n' >> "$CONFIG/nixarchy/apps.nix"
check "a commented row is not a change" jq -e '.count == 1' <<<"$("$ADAPTER" pending)"
fi
rm -rf "$CONFIG" "$FLAKE"; unset NIXARCHY_FLAKE

else
  echo "skip: needs $TEMPLATES (not a nixarchy machine)"
fi

echo "the queue apply will copy (#60)"
Q=""
q_imports() {
  local p imports=""
  for p in "$@"; do imports="$imports ./nixarchy/$p.nix"; done
  printf '# Generated by nixarchy-apply. Do not edit -- your files\n# are ~/.config/nixarchy/{apps,services,advanced,flatsnap}.nix and\n# this is regenerated from them on every apply.\n{\n  imports = [%s ];\n}\n' \
    "$imports" >"$Q/flake/nixarchy-apps.nix"
}
q_record() {
  local dst=$1 hash
  hash=$(printf '%s' "$dst" | sha256sum | cut -c1-16)
  sha256sum <"$dst" >"$Q/state/nixarchy/applied/$hash"
}
q_reset() {
  [ -z "$Q" ] || rm -rf "$Q"
  Q=$(mktemp -d)
  mkdir -p "$Q/config/nixarchy/packages" "$Q/state/nixarchy/applied" "$Q/flake/nixarchy/packages" "$Q/tmp"
  printf '{\n  x = true; #@ x\n  y = true; #@ y\n}\n' >"$Q/config/nixarchy/apps.nix"
  printf '{\n  s = true; #@ s\n}\n' >"$Q/config/nixarchy/services.nix"
  printf '{\n  a = true; #@opt a\n}\n' >"$Q/config/nixarchy/advanced.nix"
  printf '{\n  f = true; #@ f\n}\n' >"$Q/config/nixarchy/flatsnap.nix"
  cp "$Q/config/nixarchy"/*.nix "$Q/flake/nixarchy/"
  q_imports apps services advanced flatsnap
  local p
  for p in apps services advanced flatsnap; do q_record "$Q/flake/nixarchy/$p.nix"; done
}
q_pending() {
  XDG_CONFIG_HOME="$Q/config" XDG_STATE_HOME="$Q/state" NIXARCHY_FLAKE="$Q/flake" \
    TMPDIR="$Q/tmp" "$ADAPTER" pending
}
q_answer() {
  local name=$1
  QOUT=$(q_pending)
  check "$name: count matches changes" jq -e 'if .ok then .count == (.changes|length) else true end' <<<"$QOUT"
  check "$name: total matches files" jq -e 'if .ok then (.total == 0) == (.files == []) else true end' <<<"$QOUT"
  check "$name: private reads cleaned" test -z "$(find "$Q/state/nixarchy" -maxdepth 1 -name 'pkg-read.*' -print -quit)"
  check "$name: TMPDIR empty" test -z "$(find "$Q/tmp" -mindepth 1 -print -quit)"
}

q_reset
printf 'more\n' >>"$Q/config/nixarchy/flatsnap.nix"
q_answer flatsnap
check 'flatsnap edit is queued' jq -e '[.files[] | select(.file == "flatsnap" and .status == "modified")] | length == 1' <<<"$QOUT"

q_reset
printf '{ draft = true; }\n' >"$Q/config/nixarchy/packages/foo.nix"
q_answer draft
check 'new draft is queued' jq -e '[.files[] | select(.file == "packages/foo.nix" and .status == "new")] | length == 1' <<<"$QOUT"

q_reset
sed -i '/x = true/a\  continuation = true;' "$Q/config/nixarchy/apps.nix"
q_answer continuation
check 'unmarked continuation is counted' jq -e '.count == 0 and .total == 1 and .files[0].unmarked > 0' <<<"$QOUT"

q_reset
sed -i 's/^  x =/    x =/' "$Q/config/nixarchy/apps.nix"
q_answer whitespace
check 'whitespace edit is unexplained' jq -e '.total >= 1 and .files[0].explained == false' <<<"$QOUT"

q_reset
printf '  # old = true; #@ old\n' >>"$Q/config/nixarchy/apps.nix"
printf '  # old = true; #@ old\n' >>"$Q/flake/nixarchy/apps.nix"
sed -i 's/# old = true/# old = false/' "$Q/config/nixarchy/apps.nix"
q_answer comment
check 'commented catalogue edit is a file edit' jq -e '.count == 0 and .total == 1 and .files[0].explained == false' <<<"$QOUT"

q_reset
sed -i '/^}/i\  dup = true; #@ dup\n  dup = true; #@ dup' "$Q/config/nixarchy/apps.nix"
sed -i '/^}/i\  dup = true; #@ dup' "$Q/config/nixarchy/services.nix"
q_answer duplicates
# shellcheck disable=SC2016  # jq variables are literal in its filter.
check 'duplicate markers stay separate by file and occurrence' jq -e '
  [.changes[] | select(.marker == ":dup")] as $d |
  ($d|length) == 3 and ([ $d[].file ] | sort) == ["apps","apps","services"] and
  ([ $d[] | select(.file == "apps") | .lineNo ] | unique | length) == 2' <<<"$QOUT"

q_reset
sed -i 's/x = true/x = false/' "$Q/config/nixarchy/apps.nix"
q_answer marked
check 'changed marked value is paired and located' jq -e '.changes == [{marker:":x",file:"apps",line:"x = false; #@ x",change:"modified",lineNo:2}] and .files[0].explained' <<<"$QOUT"

q_reset
sed -i '2i\  dup = true; #@ dup' "$Q/flake/nixarchy/apps.nix"
sed -i '2i\  dup = true; #@ dup' "$Q/config/nixarchy/apps.nix"
sed -i '5i\  dup = true; #@ dup' "$Q/config/nixarchy/apps.nix"
q_answer unchanged_duplicate
check 'new duplicate points to its new source line' jq -e '[.changes[] | select(.marker == ":dup") | .lineNo] == [5]' <<<"$QOUT"

q_reset
for i in {1..150}; do printf '  toggle%d = true; #@ toggle%d\n' "$i" "$i" >>"$Q/config/nixarchy/apps.nix"; done
start=$(date +%s%N)
q_answer many_toggles
elapsed_ms=$(( ($(date +%s%N) - start) / 1000000 ))
check '150 toggles finish pending under one second' test "$elapsed_ms" -lt 1000
check '150 toggles retain all rows' jq -e '.count == 150' <<<"$QOUT"

q_reset
printf 'unmarked change\n' >>"$Q/config/nixarchy/apps.nix"
q_answer hunk_label
check 'hunk names stable logical files' jq -e '.files[0].hunk | contains("apps.nix (applied)") and contains("apps.nix (yours)")' <<<"$QOUT"

q_reset
printf 'unmarked change\n' >>"$Q/config/nixarchy/apps.nix"
mkdir "$Q/stub"
cat >"$Q/stub/grep" <<'STUBEOF'
#!/usr/bin/env bash
if [ "${1-}" = -c ]; then exit 2; fi
exec "$REAL_GREP" "$@"
STUBEOF
chmod +x "$Q/stub/grep"
REAL_GREP=$(command -v grep)
QOUT=$(REAL_GREP="$REAL_GREP" PATH="$Q/stub:$PATH" q_pending || :)
check 'grep count failure gives one queue error' jq -es 'length == 1 and .[0].ok == false' <<<"$QOUT"

q_reset
rm "$Q/config/nixarchy/apps.nix"
q_answer dropped
check 'dropped import is queued' jq -e '.files[0].status == "dropped" and .files[0].path == null' <<<"$QOUT"
q_imports services advanced flatsnap
q_answer detached
check 'absent and no longer imported has no entries' jq -e '.files == [] and .changes == []' <<<"$QOUT"
cp "$Q/flake/nixarchy/apps.nix" "$Q/config/nixarchy/apps.nix"
q_answer recreated
check 'recreated source is new despite leftover destination' jq -e '.files[0].status == "new"' <<<"$QOUT"

q_reset
printf 'flake edit\n' >>"$Q/flake/nixarchy/apps.nix"
printf 'source edit\n' >>"$Q/config/nixarchy/apps.nix"
q_answer overwrite
check 'part edited in flake will be overwritten' jq -e '.files[0].conflict == "overwrite"' <<<"$QOUT"
rm "$Q/config/nixarchy/apps.nix"
q_answer no_overwrite
check 'dropped part does not conflict' jq -e '.files[0].conflict == null' <<<"$QOUT"

q_reset
printf 'draft\n' >"$Q/config/nixarchy/packages/foo.nix"
cp "$Q/config/nixarchy/packages/foo.nix" "$Q/flake/nixarchy/packages/foo.nix"
q_record "$Q/flake/nixarchy/packages/foo.nix"
printf 'flake edit\n' >>"$Q/flake/nixarchy/packages/foo.nix"
printf 'source edit\n' >>"$Q/config/nixarchy/packages/foo.nix"
q_answer blocks
check 'draft edited in flake blocks apply' jq -e '.files[0].conflict == "blocks"' <<<"$QOUT"

q_reset
rm "$Q/config/nixarchy/services.nix"
q_answer pins
# shellcheck disable=SC2016  # jq variables are literal in its filter.
check 'pins hash present sources and leave absent source empty' jq -e \
  --arg apps "$(sha256sum <"$Q/config/nixarchy/apps.nix" | cut -d' ' -f1)" \
  --arg advanced "$(sha256sum <"$Q/config/nixarchy/advanced.nix" | cut -d' ' -f1)" \
  --arg flatsnap "$(sha256sum <"$Q/config/nixarchy/flatsnap.nix" | cut -d' ' -f1)" \
  '.pins == {apps:$apps,services:"",advanced:$advanced,flatsnap:$flatsnap} and .sources.services == null' <<<"$QOUT"

q_reset
printf 'draft\n' >"$Q/config/nixarchy/packages/foo.nix"
cp "$Q/config/nixarchy/packages/foo.nix" "$Q/flake/nixarchy/packages/foo.nix"
q_record "$Q/flake/nixarchy/packages/foo.nix"
q_answer unchanged_draft
check 'unchanged draft is listed as unpinned' jq -e '.files == [] and .unpinned.drafts == ["packages/foo.nix"]' <<<"$QOUT"
old_fingerprint=$(jq -r '.fingerprint' <<<"$QOUT")
old_pins=$(jq -c '.pins' <<<"$QOUT")
printf 'edit\n' >>"$Q/config/nixarchy/packages/foo.nix"
q_answer draft_fingerprint
# shellcheck disable=SC2016  # jq variables are literal in its filter.
check 'draft changes fingerprint but not part pins' jq -e --arg old "$old_fingerprint" --argjson pins "$old_pins" '.fingerprint != $old and .pins == $pins' <<<"$QOUT"

q_reset
mkdir -p "$Q/state/nixarchy/pkg-recovery/open"
# A live writer holds the lock; without one this is an interrupted write (#66).
: >"$Q/state/nixarchy/applied/lock"
( flock 9; touch "$Q/ready"; exec sleep 20 ) 9>"$Q/state/nixarchy/applied/lock" & qholder=$!
for ((i = 0; i < 100; i++)); do [ -e "$Q/ready" ] && break; sleep 0.05; done
q_answer writing
kill "$qholder" 2>/dev/null || :; wait "$qholder" 2>/dev/null || :
check 'open recovery marks queue as writing' jq -e '.writing == true' <<<"$QOUT"

q_reset
mkdir -p "$Q/stub"
cat >"$Q/stub/cp" <<'STUBEOF'
#!/usr/bin/env bash
if [[ " $* " == *" $XDG_CONFIG_HOME/"* ]]; then
  printf '%s\n' "$TMPDIR" >"$XDG_STATE_HOME/cp-tmpdir"
  printf '%s\n' "$$" >"$XDG_STATE_HOME/cp.pid"
  exec sleep 30
fi
exec "$REAL_CP" "$@"
STUBEOF
chmod +x "$Q/stub/cp"
REAL_CP=$(command -v cp)
REAL_CP="$REAL_CP" PATH="$Q/stub:$PATH" XDG_CONFIG_HOME="$Q/config" XDG_STATE_HOME="$Q/state" \
  NIXARCHY_FLAKE="$Q/flake" TMPDIR="$Q/tmp" "$ADAPTER" pending >"$Q/term.out" & adapter=$!
for i in {1..100}; do [ -s "$Q/state/cp.pid" ] && break; sleep 0.01; done
check 'pending TERM fixture reached snapshot copy' test -s "$Q/state/cp.pid"
kill -TERM "$adapter" 2>/dev/null || :
sleep 0.1
if kill -0 "$adapter" 2>/dev/null; then kill -TERM "$(cat "$Q/state/cp.pid")" 2>/dev/null || :; fi
wait "$adapter" 2>/dev/null || :
QOUT=$(cat "$Q/term.out")
check 'pending TERM gives one error answer' jq -es 'length == 1 and .[0].ok == false' <<<"$QOUT"
check 'pending snapshot children inherit private TMPDIR' grep -qF "$Q/state/nixarchy/pkg-read." "$Q/state/cp-tmpdir"
check 'pending TERM leaves no private directory' test -z "$(find "$Q/state/nixarchy" -maxdepth 1 -name 'pkg-read.*' -print -quit)"

q_reset
chmod 000 "$Q/flake/nixarchy/apps.nix"
printf 'changed\n' >>"$Q/config/nixarchy/apps.nix"
q_answer unreadable
if [ "$(id -u)" = 0 ]; then
  # Root can read mode 000; use a directory to exercise cmp's error status.
  chmod 600 "$Q/flake/nixarchy/apps.nix"
  mv "$Q/flake/nixarchy/apps.nix" "$Q/flake/nixarchy/apps.saved"
  mkdir "$Q/flake/nixarchy/apps.nix"
  q_answer unreadable
fi
check 'unreadable destination gives an error' jq -e '.ok == false' <<<"$QOUT"

q_reset
rm -rf "$Q/flake/nixarchy"
rm "$Q/flake/nixarchy-apps.nix"
q_answer never_applied
check 'never-applied machine queues every part as new' jq -e '.neverApplied and ([.files[] | select(.status == "new")] | length) == 4' <<<"$QOUT"
rm -rf "$Q"

echo "the queued flake evaluates as checked (#60)"
REAL_NIX=$(command -v nix)
C=""
c_reset() {
  [ -z "$C" ] || rm -rf "$C"
  C=$(mktemp -d)
  mkdir -p "$C/flake/nixarchy" "$C/config/nixarchy" "$C/state" "$C/tmp" "$C/stub"
  local host; host=$(uname -n)
  cat >"$C/flake/flake.nix" <<EOF
{
  outputs = { self }: {
    nixosConfigurations."$host" = {
      config.system.build.toplevel =
        let mods = map (f: import f) (import ./nixarchy-apps.nix).imports;
        in builtins.deepSeq mods (derivation {
          name = if builtins.pathExists ./untracked then "leak"
                 else "ok-\${toString (builtins.length mods)}";
          system = "x86_64-linux"; builder = "/bin/sh";
        });
    };
  };
}
EOF
  printf '{ imports = [ ./nixarchy/apps.nix ]; }\n' >"$C/flake/nixarchy-apps.nix"
  printf '{ a = 1; }\n' >"$C/flake/nixarchy/apps.nix"
  printf '{ a = 1; }\n' >"$C/config/nixarchy/apps.nix"
  git -C "$C/flake" init -q
  git -C "$C/flake" add -A
}
c_hashes() {
  find "$C/flake" "$C/config" -type f ! -path '*/.git/*' -print0 |
    sort -z | xargs -0r sha256sum
}
c_before() {
  C_STATUS=$(git -C "$C/flake" status --porcelain)
  C_HASHES=$(c_hashes)
}
c_after() {
  local name=$1
  check "$name: one JSON answer" jq -es 'length == 1' <<<"$C_OUT"
  check "$name: one output line" test "$(printf '%s\n' "$C_OUT" | wc -l)" = 1
  check "$name: private check cleaned" test -z "$(find "$C/state" -maxdepth 2 -type d -name 'pkg-check.*' -print -quit)"
  check "$name: TMPDIR empty" test -z "$(find "$C/tmp" -mindepth 1 -print -quit)"
  check "$name: git status unchanged" test "$(git -C "$C/flake" status --porcelain)" = "$C_STATUS"
  check "$name: file hashes unchanged" test "$(c_hashes)" = "$C_HASHES"
}
c_run() {
  local name=$1; shift
  c_before
  C_OUT=$(REAL_NIX="$REAL_NIX" STUB_MODE="${C_MODE-}" STUB_PID_FILE="$C/stub.pid" \
    PATH="$C/stub:$PATH" XDG_CONFIG_HOME="$C/config" XDG_STATE_HOME="$C/state" \
    NIXARCHY_FLAKE="$C/flake" TMPDIR="$C/tmp" "$ADAPTER" check "$@")
  c_after "$name"
}

c_reset
mkdir "$C/no-nix"
ln -s "$(command -v bash)" "$C/no-nix/bash"
ln -s "$(command -v jq)" "$C/no-nix/jq"
C_OUT=$(PATH="$C/no-nix" XDG_CONFIG_HOME="$C/config" XDG_STATE_HOME="$C/state" \
  NIXARCHY_FLAKE="$C/flake" "$ADAPTER" check || :)
check 'missing nix gives one check error' jq -es 'length == 1 and .[0].error == "nix is not on PATH"' <<<"$C_OUT"

c_reset
touch "$C/flake/untracked"
c_run untracked
check 'untracked file is excluded from evaluation' jq -e '.verdict == "evaluates" and (.drvPath | endswith("-ok-1.drv"))' <<<"$C_OUT"

c_reset
printf '{ a = throw "boom"; }\n' >"$C/config/nixarchy/apps.nix"
c_run throw
check 'throw reports its summary and checked source line' jq -e \
  '.verdict == "fails" and (.summary | contains("boom")) and .at == {file:"apps.nix",line:1}' <<<"$C_OUT"

c_reset
mkdir "$C/outside"
printf 'untouched\n' >"$C/outside/proof"
outside_hash=$(sha256sum <"$C/outside/proof")
rm "$C/flake/nixarchy/apps.nix"
rmdir "$C/flake/nixarchy"
ln -s "$C/outside" "$C/flake/nixarchy"
c_run symlink
check 'real flake symlink refuses the check' jq -e '.verdict == "unknown" and (.reason | contains("symlink"))' <<<"$C_OUT"
check 'symlink target is byte-identical' test "$(sha256sum <"$C/outside/proof")" = "$outside_hash"

c_reset
mkdir -p "$C/outside/$(uname -n)"
printf 'untouched\n' >"$C/outside/$(uname -n)/proof"
ln -s "$C/outside" "$C/flake/hosts"
git -C "$C/flake" add hosts
outside_before=$(find "$C/outside" -type f -print0 | sort -z | xargs -0 sha256sum)
c_run ancestor_symlink
check 'host ancestor symlink refuses the check' jq -e '.verdict == "unknown" and (.reason | contains("symlink"))' <<<"$C_OUT"
check 'host ancestor target stays byte-identical' test "$(find "$C/outside" -type f -print0 | sort -z | xargs -0 sha256sum)" = "$outside_before"
check 'host ancestor target has no nixarchy directory' test ! -e "$C/outside/$(uname -n)/nixarchy"

c_reset
git -C "$C/flake" update-index --add --cacheinfo "160000,$(printf '1%.0s' {1..40}),sub"
c_run gitlink
check 'git submodule refuses the check' jq -e '.verdict == "unknown" and (.reason | contains("submodules"))' <<<"$C_OUT"

c_reset
printf '{}\n' >"$C/flake/extra.nix"
git -C "$C/flake" add -A
rm "$C/flake/extra.nix"
c_run deleted_tracked
check 'deleted tracked file is skipped' jq -e '.verdict == "evaluates"' <<<"$C_OUT"

c_reset
printf '# self.rev\n' >>"$C/flake/flake.nix"
c_run self_rev
check 'self.rev still lets a good selection evaluate' jq -e '.verdict == "evaluates"' <<<"$C_OUT"

c_reset
printf '# self.rev\n' >>"$C/flake/flake.nix"
printf '{ a = throw "boom"; }\n' >"$C/config/nixarchy/apps.nix"
c_run self_rev_fails
check 'self.rev turns a failure into could-not-check' jq -e \
  '.verdict == "unknown" and (.reason | contains("own git revision")) and (.summary | contains("boom"))' <<<"$C_OUT"

c_reset
for tool in git tar cp; do
  cat >"$C/stub/$tool" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" >>"$FD_CALLS"
if [ -e /proc/self/fd/8 ]; then printf '%s\n' "${0##*/}" >>"$FD_LEAKS"; fi
case ${0##*/} in
  git) exec "$REAL_GIT" "$@" ;;
  tar) exec "$REAL_TAR" "$@" ;;
  cp) exec "$REAL_CP" "$@" ;;
esac
STUBEOF
  chmod +x "$C/stub/$tool"
done
REAL_GIT=$(command -v git); REAL_TAR=$(command -v tar); REAL_CP=$(command -v cp)
export REAL_GIT REAL_TAR REAL_CP
export FD_CALLS="$C/fd.calls" FD_LEAKS="$C/fd.leaks"
c_run child_fds
check 'check invokes git tar and cp stubs' test "$(sort -u "$FD_CALLS" | tr '\n' ' ')" = 'cp git tar '
check 'check closes lock fd in git tar and cp' test ! -s "$FD_LEAKS"

c_reset
cat >"$C/stub/nix" <<'STUBEOF'
#!/usr/bin/env bash
if [ "$3" = eval ] && [ "$4" = --raw ]; then
  printf '# changed during check\n' >>"$XDG_CONFIG_HOME/nixarchy/apps.nix"
fi
exec "$REAL_NIX" "$@"
STUBEOF
chmod +x "$C/stub/nix"
c_before
C_OUT=$(REAL_NIX="$REAL_NIX" PATH="$C/stub:$PATH" XDG_CONFIG_HOME="$C/config" \
  XDG_STATE_HOME="$C/state" NIXARCHY_FLAKE="$C/flake" TMPDIR="$C/tmp" "$ADAPTER" check)
printf '{ a = 1; }\n' >"$C/config/nixarchy/apps.nix"
c_after superseded
check 'changed source supersedes the verdict' jq -e '.verdict == "superseded"' <<<"$C_OUT"

c_reset
mkdir -p "$C/state/nixarchy/pkg-recovery/open"
c_run open_write
check 'open recovery refuses the check' jq -e '.verdict == "unknown" and (.reason | contains("write is in progress"))' <<<"$C_OUT"

c_reset
mkdir -p "$C/state/nixarchy"
( flock 8; touch "$C/ready"; exec sleep 20 ) 8>"$C/state/nixarchy/pkg-check.lock" & holder=$!
for i in {1..100}; do [ -e "$C/ready" ] && break; sleep 0.1; done
check 'check lock holder started' test -e "$C/ready"
c_run locked
check 'busy check lock is one error' jq -e '.ok == false and (.error | contains("already running"))' <<<"$C_OUT"
kill "$holder" 2>/dev/null || :
wait "$holder" 2>/dev/null || :

c_reset
sed -i "s/nixosConfigurations.\"$(uname -n)\"/nixosConfigurations.\"other-host\"/" "$C/flake/flake.nix"
c_run wrong_host
check 'missing host is one error' jq -e '.ok == false and (.error | contains("no nixosConfigurations"))' <<<"$C_OUT"

for C_MODE in plural singular garbage; do
  c_reset
  cat >"$C/stub/nix" <<'STUBEOF'
#!/usr/bin/env bash
if [ "$3" = build ] && [ "$4" = --dry-run ]; then
  case "$STUB_MODE" in
    plural) printf 'these 2 derivations will be built\nthese 3 paths will be fetched (1.5 GiB download, unknown unpacked)\n' >&2 ;;
    singular) printf 'this derivation will be built\nthis path will be fetched (512 KiB download, unknown unpacked)\n' >&2 ;;
    garbage) printf 'garbage\n' >&2 ;;
  esac
  exit 0
fi
exec "$REAL_NIX" "$@"
STUBEOF
  chmod +x "$C/stub/nix"
  c_run "dry_run_$C_MODE" --dry-run
  case "$C_MODE" in
    plural) check 'plural dry run counts and converts GiB' jq -e '.dryRun == {build:2,fetch:3,downloadMiB:1536}' <<<"$C_OUT" ;;
    singular) check 'singular dry run counts and converts KiB' jq -e '.dryRun == {build:1,fetch:1,downloadMiB:0.5}' <<<"$C_OUT" ;;
    garbage) check 'unparsed dry run is unknown' jq -e '.dryRun == null and (.dryRunError | contains("garbage"))' <<<"$C_OUT" ;;
  esac
done
unset C_MODE

c_reset
cat >"$C/stub/nix" <<'STUBEOF'
#!/usr/bin/env bash
if [ "$3" = eval ] && [ "$4" = --raw ]; then
  printf '%s\n' "$$" >"$STUB_PID_FILE"
  exec sleep 30
fi
exec "$REAL_NIX" "$@"
STUBEOF
chmod +x "$C/stub/nix"
c_before
REAL_NIX="$REAL_NIX" STUB_PID_FILE="$C/stub.pid" PATH="$C/stub:$PATH" \
  XDG_CONFIG_HOME="$C/config" XDG_STATE_HOME="$C/state" NIXARCHY_FLAKE="$C/flake" \
  TMPDIR="$C/tmp" "$ADAPTER" check >"$C/term.out" & adapter=$!
for i in {1..100}; do [ -s "$C/stub.pid" ] && break; sleep 0.1; done
check 'TERM fixture reached evaluation' test -s "$C/stub.pid"
kill -TERM "$adapter" 2>/dev/null || :
wait "$adapter" 2>/dev/null || :
C_OUT=$(cat "$C/term.out")
c_after term
check 'TERM gives one interruption answer' jq -e '.ok == false and (.error | contains("the check was interrupted"))' <<<"$C_OUT"
check 'TERM stops the evaluation child' not kill -0 "$(cat "$C/stub.pid")"

c_reset
cat >"$C/stub/nix" <<'STUBEOF'
#!/usr/bin/env bash
if [ "$3" = flake ] && [ "$4" = metadata ]; then
  printf '%s\n' "$$" >"$STUB_PID_FILE"
  printf '%s\n' "$TMPDIR" >"$STUB_TMPDIR_FILE"
  exec sleep 30
fi
exec "$REAL_NIX" "$@"
STUBEOF
chmod +x "$C/stub/nix"
c_before
REAL_NIX="$REAL_NIX" STUB_PID_FILE="$C/stub.pid" STUB_TMPDIR_FILE="$C/stub.tmpdir" \
  PATH="$C/stub:$PATH" XDG_CONFIG_HOME="$C/config" XDG_STATE_HOME="$C/state" \
  NIXARCHY_FLAKE="$C/flake" "$ADAPTER" check >"$C/term.out" & adapter=$!
for i in {1..100}; do [ -s "$C/stub.pid" ] && break; sleep 0.01; done
check 'metadata TERM fixture reached metadata' test -s "$C/stub.pid"
kill -TERM "$adapter" 2>/dev/null || :
for i in {1..50}; do kill -0 "$adapter" 2>/dev/null || break; sleep 0.01; done
if kill -0 "$adapter" 2>/dev/null; then
  fail 'metadata TERM returns without waiting for nix'
  kill -TERM "$(cat "$C/stub.pid")" 2>/dev/null || :
else
  pass 'metadata TERM returns without waiting for nix'
fi
wait "$adapter" 2>/dev/null || :
C_OUT=$(cat "$C/term.out")
c_after metadata_term
check 'metadata TERM gives one error answer' jq -es 'length == 1 and .[0].ok == false' <<<"$C_OUT"
check 'metadata TERM stops nix child' not kill -0 "$(cat "$C/stub.pid")"
check 'check children inherit private TMPDIR' grep -qF "$C/state/nixarchy/pkg-check." "$C/stub.tmpdir"
rm -rf "$C"

echo "apply"
# Driven against a STUB of nixarchy-apply, never the real one: the real one
# elevates and rebuilds a machine, so a test that invoked it would be a test
# that changed the machine. The stub records how it was called, then prints
# whatever the mode asks for.
STUB=$(mktemp -d)
cat > "$STUB/nixarchy-apply" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_DIR/argv"
printf '%s\n' "$TMPDIR" > "$STUB_DIR/tmpdir"
cat > "$STUB_DIR/stdin"
echo "elevation=${NH_ELEVATION_STRATEGY:-unset}"
case "${STUB_MODE-}" in
  stream)    echo early; sleep 1; echo late ;;
  escapes)   printf '\033[1mADDED\033[0m\n50%%\r100%%\n' ;;
  fail)      echo "error: build failed"; exit 3 ;;
  nonewline) printf 'last' ;;
  fakejson)  echo '{"ok":true,"exit":0}'; echo after ;;
  mismatch)  echo "apps.nix is not what you checked"; exit 4 ;;
esac
exit 0
STUBEOF
chmod +x "$STUB/nixarchy-apply"
run_apply() { STUB_DIR="$STUB" STUB_MODE=$1 PATH="$STUB:$PATH" env -u TMPDIR "$ADAPTER" apply "${@:2}"; }
record() { jq -e "$1" <<<"$(tail -1 <<<"$2")"; }

# Streaming is a property of WHEN lines arrive, so it is timed: a test that
# captures the finished output cannot tell a stream from a buffer (#26).
start=$(date +%s%N); early_ms=""
while IFS= read -r line; do
  [ "$line" = early ] && [ -z "$early_ms" ] && early_ms=$(( ($(date +%s%N) - start) / 1000000 ))
done < <(run_apply stream)
check "the log streams: a line arrives before the build ends" test "${early_ms:-9999}" -lt 700

out=$(run_apply "")
check "apply asks for pkexec elevation"      grep -q 'elevation=pkexec' <<<"$out"
check "apply passes --yes --no-preview"      test "$(cat "$STUB/argv")" = "--yes --no-preview"
check "and sends nothing on stdin"           test ! -s "$STUB/stdin"
check "the last line is the apply record"    record '.nixarchyPkgApply.ok == true and .nixarchyPkgApply.exit == 0' "$out"
check 'apply children inherit private TMPDIR' grep -qF "$XDG_STATE_HOME/nixarchy/pkg-apply." "$STUB/tmpdir"

out=$(run_apply escapes)
check "colour escapes are stripped"          not grep -q $'\033' <<<"$out"
check "the text survives them"               grep -qx 'ADDED' <<<"$out"
check "a progress line keeps its last redraw" grep -qx '100%' <<<"$out"

out=$(run_apply fail)
check "a failing apply is reported"          record '.nixarchyPkgApply.ok == false and .nixarchyPkgApply.exit == 3' "$out"

out=$(run_apply nonewline)
check "an unterminated last line stays its own line" grep -qx 'last' <<<"$out"
check "and the record still parses"          record '.nixarchyPkgApply.ok == true' "$out"

out=$(run_apply fakejson)
check "build output shaped like a result is only log" grep -qx 'after' <<<"$out"
check "and the record is still the last line" record '.nixarchyPkgApply.ok == true' "$out"

H=$(printf 'a%.0s' {1..64})
out=$(run_apply "" --pin "apps=$H" --pin "flatsnap=")
check "a pin is forwarded to nixarchy-apply" grep -qF -- "--expect-sha256 apps=$H --expect-sha256 flatsnap=" "$STUB/argv"
check "and the apply still succeeds"         record '.nixarchyPkgApply.ok == true' "$out"
rm -f "$STUB/argv"
out=$(run_apply "" --pin bogus=1)
check "a bad pin is refused"                 jq -e '.ok == false' <<<"$out"
check "and nothing ran"                      test ! -e "$STUB/argv"
out=$(run_apply mismatch --pin "apps=$H")
check "a mismatch says the file changed"     record '.nixarchyPkgApply.ok == false and .nixarchyPkgApply.exit == 4 and (.nixarchyPkgApply.message | contains("changed since you reviewed"))' "$out"
check "no apply directory is left behind"    test -z "$(find "$XDG_STATE_HOME" -name 'pkg-apply.*')"
rm -rf "$STUB"

# What is queued, across more than one file at once.
#
# Every other case here queues one kind of thing, which is exactly how
# `pending` came to report only the first file that differed: apps alone was
# right, services alone was right, and the two together lost one of them.
# Anything queued in `advanced` had never been counted at all.
if $HAVE_CATALOGUE; then
echo "pending across more than one file"
PCFG=$(fresh_config)
PBASE=$(mktemp -d); mkdir -p "$PBASE/nixarchy"
# The applied copy starts as the selection does, so nothing is queued yet.
cp "$PCFG/nixarchy"/*.nix "$PBASE/nixarchy/"
pending() { XDG_CONFIG_HOME="$PCFG" NIXARCHY_FLAKE="$PBASE" "$ADAPTER" pending; }

check "nothing queued is nothing"   jq -e '.count == 0' <<<"$(pending)"
if $CAN_TOGGLE; then
XDG_CONFIG_HOME="$PCFG" ctoggle service "$SVC" >/dev/null
check "one file, one change"        jq -e '.count == 1' <<<"$(pending)"
check "and it names that file"      jq -e '[.changes[].file] == ["services"]' <<<"$(pending)"
XDG_CONFIG_HOME="$PCFG" ctoggle app "$APP" >/dev/null
check "two files, two changes"      jq -e '.count == 2' <<<"$(pending)"
check "and both files are named"    jq -e '[.changes[].file] | sort == ["apps", "services"]' <<<"$(pending)"
# A file that exists and cannot be read is not an empty one: it used to be
# reported as every line in the applied copy having been removed.
chmod 000 "$PCFG/nixarchy/services.nix"
check "an unreadable file is an error, not an empty file" \
                                    jq -e '.ok == false' <<<"$(pending)"
chmod 600 "$PCFG/nixarchy/services.nix"
check "and it recovers once readable" jq -e '.ok == true and .count == 2' <<<"$(pending)"
fi
rm -rf "$PCFG" "$PBASE"

# The shape that caused it, so the next one is caught before it ships.
#
# The adapter's answer is all the panel knows about a write. These cases
# assert the two halves of that contract: a reported write really happened,
# and a call that reports nothing changed really changed nothing -- content,
# mode, owner and symlink alike (#39).
echo "a write keeps the file it wrote to"
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"

# awk inserts before a line that is exactly `}`. A module closing any other
# way used to be copied through unchanged, pass --parse BECAUSE it was
# unchanged, and be reported as written.
before=$(md5sum < "$APPSNIX")
sed -i -E 's/^\}[[:space:]]*$/}  # the end/' "$APPSNIX"
edited=$(md5sum < "$APPSNIX")
check "the fixture really does close differently" not test "$edited" = "$before"
out=$("$ADAPTER" opt set services.openssh.enable true 2>&1 || true)
check "refuses a module it cannot find the end of" jq -e '.ok == false' <<<"$out"
check "and says which brace it means" \
  jq -e '.error | contains("does not close on a line of its own")' <<<"$out"
check "and the file is byte-identical" test "$(md5sum < "$APPSNIX")" = "$edited"
rm -rf "$CONFIG"

# mv is rename(2): it replaces the target inode, so the file comes out with
# the 0600 mktemp gave the temp file and the invoking user as its owner.
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"
chmod 644 "$APPSNIX"
"$ADAPTER" opt set services.openssh.ports "[ 22 ]" >/dev/null 2>&1 || true
check "opt set keeps the file's mode" test "$(stat -c %a "$APPSNIX")" = 644
"$ADAPTER" opt replace services.openssh.ports "[ 2222 ]" >/dev/null 2>&1 || true
check "opt replace keeps the file's mode" test "$(stat -c %a "$APPSNIX")" = 644
rm -rf "$CONFIG"

# Someone keeping apps.nix in a dotfiles repo: the write must reach what the
# link points at, not replace the link with a regular file.
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"
REAL=$(mktemp -d)/apps.nix
mv "$APPSNIX" "$REAL"; ln -s "$REAL" "$APPSNIX"
"$ADAPTER" opt set services.openssh.enable true >/dev/null 2>&1 || true
check "opt set leaves a symlinked apps.nix a symlink" test -L "$APPSNIX"
check "and the option reached the file it points at" \
  grep -q '#@opt services.openssh.enable$' "$REAL"
rm -rf "$CONFIG" "$(dirname "$REAL")"

# #39 made a write either happen as reported or be reported as not
# happening. These are the read and validation paths, which had the same
# defect: an unreadable file described as an empty one, and a value able to
# forge the marker the panel reads (#41).
echo "a read says what it could not read"
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"

check "a readable catalogue carries no message" \
  jq -e '.message == null' <<<"$("$ADAPTER" state 2>/dev/null)"

chmod 000 "$APPSNIX"
out=$("$ADAPTER" state 2>/dev/null)
check "an unreadable apps.nix still lists services" jq -e '.services | length > 0' <<<"$out"
check "but reports no apps"                        jq -e '.apps | length == 0' <<<"$out"
check "and says which file it could not read" \
  jq -e '.message | contains("could not read") and contains("apps.nix")' <<<"$out"
chmod 600 "$APPSNIX"
out=$("$ADAPTER" state 2>/dev/null)
check "and the catalogue comes back once readable" jq -e '.apps | length > 0' <<<"$out"
check "with the message gone"                      jq -e '.message == null' <<<"$out"

# An absent file is the ordinary first run, not an error.
rm -f "$APPSNIX"
check "an absent apps.nix is not reported as unreadable" \
  jq -e '.message == null' <<<"$("$ADAPTER" state 2>/dev/null)"
rm -rf "$CONFIG"

CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"
before=$(md5sum < "$APPSNIX")
out=$("$ADAPTER" opt set my.opt 'true;  #@opt other.thing' 2>&1 || true)
check "a value forging a marker is refused"  jq -e '.ok == false' <<<"$out"
check "and the refusal says why"             jq -e '.error | contains("#@")' <<<"$out"
check "and the file is byte-identical"       test "$(md5sum < "$APPSNIX")" = "$before"

# The two refusals must stay distinct: telling someone who forged a marker to
# put their value on one line is wrong advice.
out=$("$ADAPTER" opt set my.opt "$(printf "''a\nb''")" 2>&1 || true)
check "a multi-line string is written" jq -e '.ok == true' <<<"$out"
check "its newline is escaped" grep -qF 'my.opt = "a\nb";' "$APPSNIX"
before=$(md5sum < "$APPSNIX")
out=$("$ADAPTER" opt set my.list $'[ "a\nb" ]' 2>&1 || true)
check "a nonliteral multiline string is refused" jq -e '.error | contains("one line")' <<<"$out"
check "that refusal leaves the file unchanged" test "$(md5sum < "$APPSNIX")" = "$before"

# Narrow on purpose: a # inside a string is legitimate Nix, and a hex colour
# is the commonest option value there is.
check "a # inside a string is still allowed" \
  jq -e '.ok == true' <<<"$("$ADAPTER" opt set my.colour '"#ff0000"' 2>&1 || true)"
check "and it was written verbatim" grep -q 'my.colour = "#ff0000";' "$APPSNIX"
rm -rf "$CONFIG"

CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
APPSNIX="$CONFIG/nixarchy/apps.nix"
before=$(md5sum < "$APPSNIX")
out=$("$ADAPTER" toggle app '[a-z]*' 2>&1 || true)
check "a regex where an id belongs is refused here" jq -e '.ok == false' <<<"$out"
check "by this tool, in its own words" \
  jq -e '.error | contains("is not a valid app id")' <<<"$out"
check "and nothing was toggled"  test "$(md5sum < "$APPSNIX")" = "$before"
if $CAN_TOGGLE; then
realid=$APP   # $APPSNIX is a fresh copy of the same template the probe read
check "a real id still toggles" \
  jq -e '.ok == true' <<<"$(ctoggle app "$realid" 2>&1 || true)"
fi
rm -rf "$CONFIG"

else
  echo "skip: needs $TEMPLATES (not a nixarchy machine)"
fi

if [ "${NIXARCHY_PKG_TEST_OFFLINE:-0}" != 1 ]; then
# "nothing was changed" has to mean it. A failed add used to leave behind
# both a mode change and a flake.lock that nix created on its way to
# failing.
FKW=$(fresh_flake)
chmod 644 "$FKW/flake.nix"
check "the fixture starts without a lock" not test -e "$FKW/flake.lock"
out=$(NIXARCHY_FLAKE="$FKW" "$ADAPTER" flake add nope "path:$FLAKE_TMP/does-not-exist" 2>&1 || true)
check "a failed add is reported as a failure" jq -e '.ok == false' <<<"$out"
check "and leaves no flake.lock behind"       not test -e "$FKW/flake.lock"
check "and keeps flake.nix's mode"            test "$(stat -c %a "$FKW/flake.nix")" = 644

# Removal writes too, and used to do it with sed -i -- which copies the mode
# across but still replaces the inode, losing the owner. Not tested through a
# symlink: `nix flake metadata` refuses a flake whose flake.nix is a symlink
# out of the git repo, so the baseline check turns it away before any of this
# runs. Mode is the half that is reachable.
FKS=$(fresh_flake)
NIXARCHY_FLAKE="$FKS" "$ADAPTER" flake add lib "path:$FLAKE_TMP/lib" >/dev/null 2>&1 || true
chmod 644 "$FKS/flake.nix"
NIXARCHY_FLAKE="$FKS" "$ADAPTER" flake remove lib >/dev/null 2>&1 || true
check "flake remove takes the line out"   \
  test "$(grep -c '#@flake-input lib$' "$FKS/flake.nix" || true)" = 0
check "and keeps flake.nix's mode"        test "$(stat -c %a "$FKS/flake.nix")" = 644
else echo "  skip: needs a writable nix store or the network (flake inputs)"; fi

# draft and reindex had no test at all, though draft calls writers that
# create and mutate package files -- the same risk class as `pkg add` and
# `flake add`, both of which are covered. Stub-driven and fixture-free, so
# they run anywhere, including CI (#44).
echo "draft and reindex"
DSTUB=$(mktemp -d)
DCFG=$(mktemp -d); mkdir -p "$DCFG/nixarchy"
: > "$DCFG/nixarchy/apps.nix"; : > "$DCFG/nixarchy/services.nix"
: > "$DCFG/nixarchy/advanced.nix"

for w in nixarchy-pkg-new nixarchy-pkg-undraft; do
  cat > "$DSTUB/$w" <<'WEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_DIR/argv-$(basename "$0")"
[ "${WRITER_MODE-}" = "fail" ] && { echo "the writer refused it" >&2; exit 4; }
echo "wrote it"
WEOF
  chmod +x "$DSTUB/$w"
done

draft() { PATH="$DSTUB:$PATH" STUB_DIR="$DSTUB" XDG_CONFIG_HOME="$DCFG" "$ADAPTER" draft "$@"; }

out=$(draft new https://example.invalid/thing.tar.gz 2>&1 || true)
check "draft new reports ok"       jq -e '.ok == true' <<<"$out"
check "and forwards its argument"  \
  test "$(cat "$DSTUB/argv-nixarchy-pkg-new")" = "https://example.invalid/thing.tar.gz"

out=$(draft undraft thing 2>&1 || true)
check "draft undraft reports ok"   jq -e '.ok == true' <<<"$out"
check "and forwards its argument"  \
  test "$(cat "$DSTUB/argv-nixarchy-pkg-undraft")" = "thing"

# A writer that refuses must be surfaced, not swallowed.
out=$(WRITER_MODE=fail draft new https://example.invalid/x.tar.gz 2>&1 || true)
check "a refusing writer is a failure"  jq -e '.ok == false' <<<"$out"
check "and its words are carried out"   \
  jq -e '(.error // .message) | contains("the writer refused it")' <<<"$out"

check "draft with no action is a usage error" \
  jq -e '.ok == false and (.error | contains("new or undraft"))' <<<"$(draft 2>&1 || true)"
check "draft with an unknown action too" \
  jq -e '.ok == false' <<<"$(draft sideways thing 2>&1 || true)"
check "pkg with an unknown action too" \
  jq -e '.ok == false and (.error | contains("add or remove"))' \
  <<<"$(PATH="$DSTUB:$PATH" XDG_CONFIG_HOME="$DCFG" "$ADAPTER" pkg sideways thing 2>&1 || true)"

# reindex: a search tool that does nothing leaves the index stale, and the
# adapter must say so rather than claim it rebuilt. A review of #39 read
# this the other way round, so it is worth pinning.
cat > "$DSTUB/nixarchy-search" <<'SEOF'
#!/usr/bin/env bash
exit 0
SEOF
chmod +x "$DSTUB/nixarchy-search"
RCACHE=$(mktemp -d)
out=$(PATH="$DSTUB:$PATH" XDG_CACHE_HOME="$RCACHE" XDG_CONFIG_HOME="$DCFG" NIXARCHY_FLAKE="$RCACHE/no-flake" \
      "$ADAPTER" reindex 2>&1 || true)
check "reindex over a no-op search reports failure" jq -e '.ok == false' <<<"$out"
check "and says the index is still stale"           jq -e '.indexStale == true' <<<"$out"
# The index object (#69): how old, and what changed.
# stub_search_vars DIR NIXPKGS -- a nixarchy-search the adapter can read
# inputs from; it does nothing when run.
stub_search_vars() {
  cat > "$1/nixarchy-search" <<SEOF
#!/usr/bin/env bash
nixpkgs=$2
walk=/nix/store/w-pkg-index.nix
optionsjson=/nix/store/o-options.json/share/doc/nixos/options.json
appindex=/nix/store/a-nixarchy-app-index.tsv
apptable=/nix/store/t-nixarchy-app-attrs.tsv
flatpakrows=/nix/store/f-nixarchy-flatpak-rows.tsv
pkgnewrow=/nix/store/n-nixarchy-pkg-new-row.tsv
exit 0
SEOF
  chmod +x "$1/nixarchy-search"
}
# stamp_of NIXPKGS [WALK] -- the seven stamp lines; the rest match the stub.
stamp_of() {
  printf '%s\n' "$1" "${2:-/nix/store/w-pkg-index.nix}" \
    /nix/store/o-options.json/share/doc/nixos/options.json \
    /nix/store/a-nixarchy-app-index.tsv /nix/store/t-nixarchy-app-attrs.tsv \
    /nix/store/f-nixarchy-flatpak-rows.tsv /nix/store/n-nixarchy-pkg-new-row.tsv
}
NOSEARCH=$(mktemp -d)
IFS=: read -ra _dirs <<<"$PATH"
for _d in "${_dirs[@]}"; do
  for _f in "$_d"/*; do
    [ -e "$_f" ] || continue
    _n=${_f##*/}
    [ "$_n" = nixarchy-search ] || [ -e "$NOSEARCH/$_n" ] || ln -s "$_f" "$NOSEARCH/$_n"
  done
done
check "the no-search PATH really has none" \
  not env PATH="$NOSEARCH" bash -c 'command -v nixarchy-search'

ISTUB=$(mktemp -d); stub_search_vars "$ISTUB" /nix/store/n1-n1-source
# icase NAME SEARCHPATH -- a fresh cache dir in $IC, with an index row.
icase() { IC=$(mktemp -d); mkdir -p "$IC/nixarchy"; printf 'pkg\tfoo\tFoo thing\t\t\n' > "$IC/nixarchy/index.tsv"; }
istate() { PATH="$1:$PATH" XDG_CACHE_HOME="$IC" XDG_CONFIG_HOME="$DCFG" "$ADAPTER" state; }
istate_ns() { PATH="$NOSEARCH" XDG_CACHE_HOME="$IC" XDG_CONFIG_HOME="$DCFG" "$ADAPTER" state; }

IC=$(mktemp -d)
out=$(istate "$ISTUB")
check "no index: status missing, no builtAt" \
  jq -e '.index.status == "missing" and .index.builtAt == null and .indexStale' <<<"$out"
mkdir -p "$IC/nixarchy"; : > "$IC/nixarchy/index.tsv"
out=$(istate "$ISTUB")
check "a 0-byte index is missing too" \
  jq -e '.index.status == "missing" and .index.builtAt == null and .indexStale' <<<"$out"
rm -rf "$IC"

icase; stamp_of /nix/store/n1-n1-source > "$IC/nixarchy/stamp"; out=$(istate "$ISTUB")
check "a matching stamp is fresh" \
  jq -e '.index.status == "fresh" and .index.changed == null and (.indexStale | not)' <<<"$out"
rm -rf "$IC"

icase; stamp_of /nix/store/n0-n0-source /nix/store/w0-pkg-index.nix > "$IC/nixarchy/stamp"; out=$(istate "$ISTUB")
check "two inputs differ: both named, in order" \
  jq -e '.index.changed == ["nixpkgs", "index builder"] and .indexStale' <<<"$out"
rm -rf "$IC"

icase
{ stamp_of /nix/store/n1-n1-source | sed -e '4s/a-/b-/' -e '5s/t-/u-/'; } > "$IC/nixarchy/stamp"; out=$(istate "$ISTUB")
check "the two app inputs are one name" \
  jq -e '.index.changed == ["app list"]' <<<"$out"
rm -rf "$IC"

icase; out=$(istate "$ISTUB")
check "an index with no stamp is stale, with a builtAt and no names" \
  jq -e '.index.status == "stale" and .index.changed == null and (.index.builtAt | type == "number")' <<<"$out"
rm -rf "$IC"

icase; stamp_of /nix/store/n0-n0-source | head -6 > "$IC/nixarchy/stamp"; out=$(istate "$ISTUB")
check "a six-line stamp names nothing" jq -e '.index.changed == null and .indexStale' <<<"$out"
rm -rf "$IC"

icase; stamp_of /nix/store/n0-n0-source /nix/store/x-other.nix > "$IC/nixarchy/stamp"; out=$(istate "$ISTUB")
check "an unrecognised stamp line names nothing" jq -e '.index.changed == null and .indexStale' <<<"$out"
rm -rf "$IC"

OSTUB=$(mktemp -d); stub_search_vars "$OSTUB" /nix/store/n1-n1-source
sed -i 's|^optionsjson=.*|optionsjson=|' "$OSTUB/nixarchy-search"
icase; stamp_of /nix/store/n1-n1-source | sed '3s|.*||' > "$IC/nixarchy/stamp"; out=$(istate "$OSTUB")
check "an empty options line is fresh when it matches" jq -e '.index.status == "fresh"' <<<"$out"
stamp_of /nix/store/n0-n0-source | sed '3s|.*||' > "$IC/nixarchy/stamp"; out=$(istate "$OSTUB")
check "an empty options line still names a changed nixpkgs" \
  jq -e '.index.status == "stale" and .index.changed == ["nixpkgs"]' <<<"$out"
rm -rf "$IC" "$OSTUB"

icase; stamp_of /nix/store/n0-n0-source > "$IC/nixarchy/stamp"; out=$(istate_ns)
check "no nixarchy-search: stale, no names" jq -e '.index.status == "stale" and .index.changed == null' <<<"$out"
rm -rf "$IC"

icase; out=$(istate_ns)
check "no nixarchy-search and no stamp reads fresh (kept corner case)" jq -e '.index.status == "fresh"' <<<"$out"
rm -rf "$IC"

icase; stamp_of /nix/store/n1-n1-source > "$IC/nixarchy/stamp"
out=$(PATH="$ISTUB:$PATH" XDG_CACHE_HOME="$IC" XDG_CONFIG_HOME="$DCFG" "$ADAPTER" search foo)
check "search carries the index object" jq -e '.index.status == "fresh"' <<<"$out"
rm -rf "$IC" "$ISTUB"

# reindex: the reason a failed rebuild gives, minus the builder's noise.
# rstub STDERR_TEXT EXIT -- a nixarchy-search that writes no index.
rstub() {
  printf '#!/usr/bin/env bash\ncat >&2 <<'"'"'EOT'"'"'\n%s\nEOT\nexit %s\n' "$1" "$2" > "$DSTUB/nixarchy-search"
  chmod +x "$DSTUB/nixarchy-search"
}
rre() { IC=$(mktemp -d); PATH="$DSTUB:$PATH" XDG_CACHE_HOME="$IC" XDG_CONFIG_HOME="$DCFG" "$ADAPTER" reindex 2>&1 || true; rm -rf "$IC"; }

rstub "" 0; out=$(rre)
check "a silent no-op: error names the log" jq -e '.ok == false and (.error | contains("index-errors.log")) and .detail == []' <<<"$out"

rstub 'Building the search index. This happens when nixpkgs changes.
  indexing nixpkgs (this takes about a minute)...
inappropriate ioctl for device' 0; out=$(rre)
check "progress and picker noise leave no detail" \
  jq -e '.detail == [] and (.error | contains("nixarchy-search gave no reason"))' <<<"$out"

rstub '  indexing nixpkgs failed; the end of /x/index-errors.log:
boom' 1; out=$(rre)
check "the builder's own reason is the error" \
  jq -e '(.error | contains("boom")) and .detail == ["indexing nixpkgs failed; the end of /x/index-errors.log:", "boom"]' <<<"$out"

rstub '  indexing nixpkgs failed; the end of /x/index-errors.log:
evaluation warning: x
evaluation warning: x
evaluation warning: x
evaluation warning: x
evaluation warning: x' 1; out=$(rre)
check "evaluation warnings are dropped" \
  jq -e '.detail == ["indexing nixpkgs failed; the end of /x/index-errors.log:"] and (.error | contains("gave no reason"))' <<<"$out"
cat > "$DSTUB/nixarchy-search" <<'SEOF'
#!/usr/bin/env bash
head -c 200000 /dev/zero | tr '\0' x >&2
printf '\nfinal failure\n' >&2
exit 1
SEOF
chmod +x "$DSTUB/nixarchy-search"
out=$(rre)
check "oversized stderr still produces a JSON answer" \
  jq -e '.ok == false and (.error | contains("final failure")) and .detail[-1] == "final failure"' <<<"$out"
rm -rf "$NOSEARCH"
rm -rf "$DSTUB" "$DCFG" "$RCACHE"

echo "a write that fails or races leaves the files recoverable (#59)"
REAL_CP=$(command -v cp); REAL_MV=$(command -v mv); REAL_NIX=$(command -v nix)
REAL_NI=$(command -v nix-instantiate); REAL_AWK=$(command -v awk)
W59=$(mktemp -d)
ADAPTER_TMP=$(mktemp -d)
mkdir -p "$W59/cfg/nixarchy" "$W59/stub"
A59="$W59/cfg/nixarchy/apps.nix"
reset_apps() { printf '{ ... }:\n{\n}\n' > "$A59"; }
st() { printf '%s' "$XDG_STATE_HOME/nixarchy"; }
one_json() { test "$(printf '%s\n' "$1" | grep -c '^{')" = 1; }
run59() { TMPDIR="$ADAPTER_TMP" XDG_CONFIG_HOME="$W59/cfg" PATH="$W59/stub:$PATH" "$ADAPTER" "$@"; }
left_nothing() {
  check "$1: adapter TMPDIR is empty" test -z "$(ls -A "$ADAPTER_TMP")"
  check "$1: no working directory remains" not compgen -G "$(st)/pkg-work.*"
  check "$1: no recovery is open" not test -e "$(st)/pkg-recovery/open"
}

# A failed live copy must be undone from the recovery data.
reset_apps; before=$(md5sum < "$A59")
cat > "$W59/stub/cp" <<EOF
#!/usr/bin/env bash
if [ "\${!#}" = "$A59" ] && [ ! -e "$W59/once" ]; then
  touch "$W59/once"; : > "$A59"; exit 1
fi
exec "$REAL_CP" "\$@"
EOF
chmod +x "$W59/stub/cp"
out=$(run59 opt set services.x.enable true) || true
check "failed copy gives one answer" one_json "$out"
check "failed copy reports failure" jq -e '.ok == false' <<<"$out"
check "failed copy restores the file" test "$(md5sum < "$A59")" = "$before"
rm -f "$W59/stub/cp" "$W59/once"
left_nothing "failed copy"

reset_apps; before=$(md5sum < "$A59"); touch -d '2000-01-01' "$A59"; stamp=$(stat -c %Y.%i "$A59")
cat > "$W59/stub/awk" <<EOF
#!/usr/bin/env bash
if [ -n "\${NIXARCHY_PKG_VALUE-}" ]; then exit 1; fi
exec "$REAL_AWK" "\$@"
EOF
chmod +x "$W59/stub/awk"
out=$(run59 opt set services.x.enable true) || true
check "failed candidate gives one answer" one_json "$out"
check "failed candidate reports failure" jq -e '.ok == false' <<<"$out"
check "failed candidate leaves the file" test "$(md5sum < "$A59")" = "$before"
check "failed candidate does not rewrite it" test "$(stat -c %Y.%i "$A59")" = "$stamp"
rm -f "$W59/stub/awk"
left_nothing "failed candidate"

# SIGKILL leaves the complete backup for an explicit recovery.
reset_apps; before=$(md5sum < "$A59"); cp "$A59" "$W59/original"
cat > "$W59/stub/cp" <<EOF
#!/usr/bin/env bash
if [ "\${!#}" = "$A59" ] && [ ! -e "$W59/once" ]; then
  touch "$W59/once"; : > "$A59"; kill -9 "\$PPID"; exit 1
fi
exec "$REAL_CP" "\$@"
EOF
chmod +x "$W59/stub/cp"
out=$(run59 opt set services.x.enable true) || true
check "killed write keeps recovery open" test -d "$(st)/pkg-recovery/open"
check "killed write keeps original bytes" cmp -s "$(st)/pkg-recovery/open/0.data" "$W59/original"
check "killed write records the path" grep -qx "$A59" "$(st)/pkg-recovery/open/0.path"
rm -f "$W59/stub/cp" "$W59/once"
out=$(run59 opt set services.y.enable true) || true
check "next write gives one answer" one_json "$out"
check "next write requests recovery" jq -e '.ok == false and (.error | contains("nixarchy-pkg recover"))' <<<"$out"
check "next write leaves the damaged file" test ! -s "$A59"
out=$(run59 recover) || true
check "recovery gives one answer" one_json "$out"
check "recovery succeeds" jq -e '.ok == true' <<<"$out"
check "recovery restores original bytes" test "$(md5sum < "$A59")" = "$before"
left_nothing "killed write recovered"

reset_apps; before=$(md5sum < "$A59")
cat > "$W59/stub/cp" <<EOF
#!/usr/bin/env bash
if [ "\${!#}" = "$A59" ]; then : > "$A59"; exit 1; fi
exec "$REAL_CP" "\$@"
EOF
chmod +x "$W59/stub/cp"
out=$(run59 opt set services.x.enable true) || true
check "failed undo gives one answer" one_json "$out"
check "failed undo reports its backup" jq -e '.ok == false and (.error | contains("0.data") and contains("nixarchy-pkg recover"))' <<<"$out"
check "failed undo keeps recovery open" test -d "$(st)/pkg-recovery/open"
rm -f "$W59/stub/cp"
out=$(run59 recover) || true
check "retrying undo succeeds" jq -e '.ok == true' <<<"$out"
check "retrying undo restores the file" test "$(md5sum < "$A59")" = "$before"
left_nothing "failed undo recovered"

reset_apps; before=$(md5sum < "$A59")
cat > "$W59/stub/mv" <<EOF
#!/usr/bin/env bash
if [[ \${!#} == */pkg-recovery/done ]]; then exit 1; fi
exec "$REAL_MV" "\$@"
EOF
chmod +x "$W59/stub/mv"
out=$(run59 opt set services.x.enable true) || true
check "failed commit gives one answer" one_json "$out"
check "failed commit reports undo" jq -e '.ok == false and (.error | contains("so it was undone"))' <<<"$out"
check "failed commit restores the file" test "$(md5sum < "$A59")" = "$before"
rm -f "$W59/stub/mv"
left_nothing "failed commit"

reset_apps; before=$(md5sum < "$A59")
cat > "$W59/stub/nix-instantiate" <<EOF
#!/usr/bin/env bash
sleep 1
exec "$REAL_NI" "\$@"
EOF
chmod +x "$W59/stub/nix-instantiate"
run59 opt set services.a.enable true > "$W59/a" & pida=$!
run59 opt set services.b.enable true > "$W59/b" & pidb=$!
wait "$pida" || true; wait "$pidb" || true
check "first simultaneous write succeeds" jq -e '.ok == true' < "$W59/a"
check "second simultaneous write succeeds" jq -e '.ok == true' < "$W59/b"
check "first line survives the race" grep -q '#@opt services.a.enable$' "$A59"
check "second line survives the race" grep -q '#@opt services.b.enable$' "$A59"
rm -f "$W59/stub/nix-instantiate"
left_nothing "simultaneous writes"

reset_apps; before=$(md5sum < "$A59")
mkdir -p "$(st)/applied"
( flock 9; touch "$W59/held"; exec sleep 15 ) 9>"$(st)/applied/lock" & lockpid=$!
i=0
while [ ! -e "$W59/held" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
check "apply holds the lock" test -e "$W59/held"
SECONDS=0; out=$(run59 opt set services.c.enable true) || true; elapsed=$SECONDS
check "locked write gives one answer" one_json "$out"
check "locked write names the holder" jq -e '.ok == false and (.error | contains("another write or an apply"))' <<<"$out"
check "locked write times out promptly" test "$elapsed" -le 10
check "locked write leaves the file" test "$(md5sum < "$A59")" = "$before"
kill "$lockpid" 2>/dev/null || true; wait "$lockpid" 2>/dev/null || true
rm -f "$W59/held"
left_nothing "apply lock"

if [ "${NIXARCHY_PKG_TEST_OFFLINE:-0}" != 1 ]; then
mkdir -p "$W59/fk" "$W59/dep"
printf '{\n  outputs = { self }: { };\n}\n' > "$W59/fk/flake.nix"
printf '{\n  outputs = { self }: { nixosModules.default = { }; };\n}\n' > "$W59/dep/flake.nix"
for d in "$W59/fk" "$W59/dep"; do git -C "$d" init -q .; git -C "$d" add -A; done
nix flake lock "$W59/fk" >/dev/null 2>&1
# Nix does not create a lock file for a flake with no inputs.
[ -e "$W59/fk/flake.lock" ] || printf '{"nodes":{"root":{}},"root":"root","version":7}\n' > "$W59/fk/flake.lock"
reset_apps; before=$(md5sum < "$A59")
before_nix=$(md5sum < "$W59/fk/flake.nix"); before_lock=$(md5sum < "$W59/fk/flake.lock")
cat > "$W59/stub/nix" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = 'flake metadata' ] && [ ! -e "$W59/once" ]; then
  touch "$W59/once"; printf 'damage\n' >> "$W59/fk/flake.lock"; exit 1
fi
exec "$REAL_NIX" "\$@"
EOF
chmod +x "$W59/stub/nix"
out=$(NIXARCHY_FLAKE="$W59/fk" run59 flake add dep "path:$W59/dep") || true
check "failed metadata gives one answer" one_json "$out"
check "failed metadata reports failure" jq -e '.ok == false' <<<"$out"
check "failed metadata restores flake.nix" test "$(md5sum < "$W59/fk/flake.nix")" = "$before_nix"
check "failed metadata restores flake.lock" test "$(md5sum < "$W59/fk/flake.lock")" = "$before_lock"
rm -f "$W59/stub/nix" "$W59/once"
left_nothing "failed add metadata"

reset_apps; before=$(md5sum < "$A59")
out=$(NIXARCHY_FLAKE="$W59/fk" run59 flake add dep "path:$W59/dep") || true
check "fixture add succeeds" jq -e '.ok == true' <<<"$out"
printf 'inputs.dep.nixosModules.default\n' > "$W59/fk/referred.nix"
before_nix=$(md5sum < "$W59/fk/flake.nix"); before_lock=$(md5sum < "$W59/fk/flake.lock")
cat > "$W59/stub/nix" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = 'flake metadata' ]; then printf '\n' >> "$W59/fk/flake.lock"; fi
exec "$REAL_NIX" "\$@"
EOF
chmod +x "$W59/stub/nix"
out=$(NIXARCHY_FLAKE="$W59/fk" run59 flake remove dep) || true
check "refused remove gives one answer" one_json "$out"
check "refused remove names the reference" jq -e '.ok == false and (.error | contains("still referred to"))' <<<"$out"
check "refused remove restores flake.nix" test "$(md5sum < "$W59/fk/flake.nix")" = "$before_nix"
check "refused remove restores flake.lock" test "$(md5sum < "$W59/fk/flake.lock")" = "$before_lock"
rm -f "$W59/stub/nix" "$W59/once"
left_nothing "refused remove metadata"

# A refusal must not need to write a file it never changed: a read-only
# flake.lock used to fail the undo and wedge every later write.
chmod 444 "$W59/fk/flake.lock"; before_lock=$(md5sum < "$W59/fk/flake.lock")
out=$(NIXARCHY_FLAKE="$W59/fk" run59 flake add dep "path:$W59/dep") || true
check "read-only lock: one answer" one_json "$out"
check "read-only lock: refused, no failed undo" jq -e '.ok == false and (.error | contains("undo failed") | not)' <<<"$out"
check "read-only lock: unchanged" test "$(md5sum < "$W59/fk/flake.lock")" = "$before_lock"
chmod 644 "$W59/fk/flake.lock"
left_nothing "read-only lock"
else echo "  skip: needs a writable nix store or the network (flake inputs)"; fi

# A dangling symlink is refused, never recorded as absent and deleted.
reset_apps; mv "$A59" "$W59/real.nix"; ln -s "$W59/gone.nix" "$A59"
out=$(run59 opt set services.d.enable true) || true
check "dangling symlink: one answer" one_json "$out"
check "dangling symlink: refused" jq -e '.ok == false' <<<"$out"
check "dangling symlink: still a symlink" test -L "$A59"
rm -f "$A59"; mv "$W59/real.nix" "$A59"
left_nothing "dangling symlink"

# Killed while an external writer runs: the lock must die with the adapter,
# not live on in the $(...) subshell that waits for the writer.
reset_apps
cat > "$W59/stub/nixarchy-opt-remove" <<EOF
#!/usr/bin/env bash
echo \$\$ > "$W59/writer"; exec sleep 20   # exec keeps the pid
EOF
chmod +x "$W59/stub/nixarchy-opt-remove"
# Not through run59: a backgrounded function is a forked subshell, so $!
# would be that shell and kill -9 would miss the adapter.
TMPDIR="$ADAPTER_TMP" XDG_CONFIG_HOME="$W59/cfg" PATH="$W59/stub:$PATH" \
  "$ADAPTER" opt remove services.x.enable > /dev/null 2>&1 & adapter=$!
i=0; while [ ! -s "$W59/writer" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
kill -9 "$adapter" 2>/dev/null || true; wait "$adapter" 2>/dev/null || true
check "killed during a writer: lock is free" flock -n "$(st)/applied/lock" true
kill "$(cat "$W59/writer")" 2>/dev/null || true   # never pkill -f: it can match the caller
rm -f "$W59/stub/nixarchy-opt-remove" "$W59/writer"
out=$(run59 recover --discard) || true
check "recover --discard gives one answer" one_json "$out"
check "recover --discard keeps the files" jq -e '.ok == true' <<<"$out"
left_nothing "killed during a writer"
rm -rf "$W59" "$ADAPTER_TMP"

echo "a killed write leaves nothing to race the next one (#67)"
rm -rf "$XDG_STATE_HOME"
XDG_STATE_HOME=$(mktemp -d); export XDG_STATE_HOME
W67=$(mktemp -d)
mkdir -p "$W67/cfg/nixarchy" "$W67/stub" "$W67/fk"
A67="$W67/cfg/nixarchy/apps.nix"
printf '{ ... }:\n{\n  # foo.enable = true;  #@ foo\n}\n' > "$A67"
printf '{ ... }:\n{\n}\n' > "$W67/cfg/nixarchy/services.nix"
run67() { XDG_CONFIG_HOME="$W67/cfg" PATH="$W67/stub:$PATH" "$ADAPTER" "$@"; }
wait67_file() {
  local i
  for ((i = 0; i < 100; i++)); do
    [ -s "$1" ] && break
    sleep 0.01
  done
  test -s "$1"
}
wait67_done() {
  local i
  for ((i = 0; i < 300; i++)); do
    [ -s "$1" ] && break
    sleep 0.05
  done
  test -s "$1"
}
wait67_child() {
  local pid=$1 i
  kill "$pid" 2>/dev/null || :
  for ((i = 0; i < 100; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  for ((i = 0; i < 100; i++)); do
    flock -n "$(st)/pkg-children.lock" true && return 0
    sleep 0.05
  done
  return 1
}

# A killed adapter must leave its Nix child holding fd 7 until it exits.
printf '{\n  outputs = { self }: { };\n}\n' > "$W67/fk/flake.nix"
git -C "$W67/fk" init -q .
git -C "$W67/fk" add flake.nix
printf '{"nodes":{"root":{}},"root":"root","version":7}\n' > "$W67/fk/flake.lock"
before_nix=$(md5sum < "$W67/fk/flake.nix"); before_lock=$(md5sum < "$W67/fk/flake.lock")
cat > "$W67/stub/nix" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = 'flake lock' ]; then
  echo $$ > "$STUB67/nix.pid"
  exec sleep 30
fi
exit 0
EOF
chmod +x "$W67/stub/nix"
STUB67="$W67" NIXARCHY_FLAKE="$W67/fk" XDG_CONFIG_HOME="$W67/cfg" PATH="$W67/stub:$PATH" \
  "$ADAPTER" flake add foo github:a/b > "$W67/add.out" 2>&1 & adapter=$!
check "killed flake add reaches nix" wait67_file "$W67/nix.pid"
kill -9 "$adapter" 2>/dev/null || :; wait "$adapter" 2>/dev/null || :
out=$(run67 toggle app foo)
check "nix child blocks the next write" jq -e '.ok == false and (.error | contains("still running"))' <<<"$out"
check "nix child keeps its working directory" compgen -G "$(st)/pkg-work.*"
out=$(run67 recover)
check "nix child blocks recovery" jq -e '.ok == false and (.error | contains("still running"))' <<<"$out"
check "killed nix child releases its lock" wait67_child "$(cat "$W67/nix.pid")"
out=$(run67 recover)
check "nix child recovery succeeds" jq -e '.ok == true' <<<"$out"
check "nix child recovery restores flake.nix" test "$(md5sum < "$W67/fk/flake.nix")" = "$before_nix"
check "nix child recovery restores flake.lock" test "$(md5sum < "$W67/fk/flake.lock")" = "$before_lock"
rm -f "$W67/stub/nix"

# The external writers inherit the same lock.
cat > "$W67/stub/nixarchy-app-enable" <<'EOF'
#!/usr/bin/env bash
echo $$ > "$STUB67/writer.pid"
exec sleep 30
EOF
chmod +x "$W67/stub/nixarchy-app-enable"
STUB67="$W67" XDG_CONFIG_HOME="$W67/cfg" PATH="$W67/stub:$PATH" \
  "$ADAPTER" toggle app foo > "$W67/toggle.out" 2>&1 & adapter=$!
check "killed writer starts" wait67_file "$W67/writer.pid"
kill -9 "$adapter" 2>/dev/null || :; wait "$adapter" 2>/dev/null || :
out=$(run67 toggle app foo)
check "writer child blocks the next write" jq -e '.ok == false and (.error | contains("still running"))' <<<"$out"
check "killed writer releases its lock" wait67_child "$(cat "$W67/writer.pid")"
out=$(run67 recover)
check "writer child recovery succeeds" jq -e '.ok == true' <<<"$out"
rm -f "$W67/stub/nixarchy-app-enable"

# The writer exits first; its background child keeps fd 7 and edits later.
before=$(md5sum < "$A67")
STUB67=$W67; APPS67=$A67; export STUB67 APPS67
GC_DELAY67=2; export GC_DELAY67
cat > "$W67/stub/nixarchy-app-enable" <<'EOF'
#!/usr/bin/env bash
( printf 'started\n' > "$STUB67/gc.started"; sleep "${GC_DELAY67:-1}"; printf 'x\n' >> "$APPS67"; printf 'done\n' > "$STUB67/gc.done" ) >/dev/null 2>&1 &
exit "${WRITER_RC67:-1}"
EOF
chmod +x "$W67/stub/nixarchy-app-enable"
out=$(run67 toggle app foo)
check "rollback waits for a grandchild" test -e "$W67/gc.done"
check "failed writer reports failure" jq -e '.ok == false' <<<"$out"
check "rollback follows the grandchild edit" test "$(md5sum < "$A67")" = "$before"
check "rollback closes recovery" not test -e "$(st)/pkg-recovery/open"
check "rollback grandchild finishes" wait67_done "$W67/gc.done"
check "rollback leaves original bytes" test "$(md5sum < "$A67")" = "$before"
rm -f "$W67/gc.done" "$W67/gc.started"

WRITER_RC67=0; export WRITER_RC67
out=$(run67 toggle app foo)
check "commit waits for a grandchild" test -e "$W67/gc.done"
check "successful writer reports success" jq -e '.ok == true' <<<"$out"
check "commit keeps the grandchild edit" grep -qx 'x' "$A67"
check "commit closes recovery" not test -e "$(st)/pkg-recovery/open"
check "commit grandchild finishes" wait67_done "$W67/gc.done"
rm -f "$W67/gc.done" "$W67/gc.started"

# TERM during settle must answer once and keep both the backup and WORK.
# Bash handles TERM after flock's wait; the child must outlast both waits.
GC_DELAY67=12; export GC_DELAY67
XDG_CONFIG_HOME="$W67/cfg" PATH="$W67/stub:$PATH" \
  "$ADAPTER" toggle app foo > "$W67/term.out" 2>&1 & adapter=$!
check "TERM fixture starts grandchild" wait67_file "$W67/gc.started"
sleep 1
kill -TERM "$adapter" 2>/dev/null || :; wait "$adapter" 2>/dev/null || :
out=$(cat "$W67/term.out")
check "TERM while settling gives one answer" one_json "$out"
check "TERM while settling reports the child" jq -e '.ok == false and (.error | contains("still running"))' <<<"$out"
check "TERM keeps recovery open" test -e "$(st)/pkg-recovery/open"
check "TERM keeps its working directory" compgen -G "$(st)/pkg-work.*"
check "TERM grandchild finishes" wait67_done "$W67/gc.done"
out=$(run67 recover)
check "TERM recovery succeeds" jq -e '.ok == true' <<<"$out"
rm -f "$W67/gc.done" "$W67/gc.started"

# A child that runs beyond settle's five seconds must keep the backup.
before=$(md5sum < "$A67")
WRITER_RC67=1
GC_DELAY67=7
out=$(run67 toggle app foo)
check "long grandchild reports an unfinished write" jq -e '.ok == false and (.message | contains("still running") and contains("recover"))' <<<"$out"
check "long grandchild keeps recovery open" test -e "$(st)/pkg-recovery/open"
check "long grandchild finishes" wait67_done "$W67/gc.done"
out=$(run67 recover)
check "long grandchild recovery succeeds" jq -e '.ok == true' <<<"$out"
check "long grandchild recovery restores apps.nix" test "$(md5sum < "$A67")" = "$before"
check "timeout -k covers five write-time calls" test "$(grep -c 'timeout -k 10 120 nix flake' "$ADAPTER")" = 5
check "no write-time call has the old timeout" test "$(grep -c 'timeout 120 nix flake \(metadata\|lock\)' "$ADAPTER" || :)" = 0
rm -rf "$W67"

echo "an interrupted write stops apply (#66)"
rm -rf "$XDG_STATE_HOME"
XDG_STATE_HOME=$(mktemp -d); export XDG_STATE_HOME
W66=$(mktemp -d)
mkdir -p "$W66/cfg/nixarchy" "$W66/stub" "$W66/tmp"
A66="$W66/cfg/nixarchy/apps.nix"
printf '{ ... }:\n{\n  # foo.enable = true;  #@ foo\n}\n' > "$A66"
printf '{ ... }:\n{\n}\n' > "$W66/cfg/nixarchy/services.nix"
# shellcheck disable=SC2016  # the stub expands STUB_DIR itself.
printf '#!/usr/bin/env bash\necho ran > "$STUB_DIR/argv"\n' >"$W66/stub/nixarchy-apply"; chmod +x "$W66/stub/nixarchy-apply"
run66() { XDG_CONFIG_HOME="$W66/cfg" NIXARCHY_FLAKE="$W66/fk" TMPDIR="$W66/tmp" PATH="$W66/stub:$PATH" STUB_DIR="$W66/stub" STUB_MODE="" "$ADAPTER" "$@"; }
# A killed write: open/ with a guarded path, and a lock nobody holds.
fixture66() {
  rm -rf "$XDG_STATE_HOME/nixarchy" "$W66/stub/argv"
  mkdir -p "$XDG_STATE_HOME/nixarchy/applied" "$XDG_STATE_HOME/nixarchy/pkg-recovery/open"
  : >"$XDG_STATE_HOME/nixarchy/applied/lock"
  printf '%s' "$A66" >"$XDG_STATE_HOME/nixarchy/pkg-recovery/open/0.path"
  printf 'old\n' >"$XDG_STATE_HOME/nixarchy/pkg-recovery/open/0.data"
}
holder66=""
hold66() {   # hold66 [-s]: hold the apply lock from a background process
  rm -f "$W66/ready"
  ( flock "$@" 9; touch "$W66/ready"; exec sleep 20 ) 9>"$XDG_STATE_HOME/nixarchy/applied/lock" & holder66=$!
  wait67_file "$W66/ready" || :
}
release66() { kill "$holder66" 2>/dev/null || :; wait "$holder66" 2>/dev/null || :; holder66=""; }

fixture66
out=$(run66 pending)
# shellcheck disable=SC2016  # jq variables are literal in its filter.
check "interrupted: pending is an error naming recover and the file" jq -e --arg p "$A66" '.ok == false and (.error | contains("recover") and contains($p))' <<<"$out"
out=$(run66 state)
# shellcheck disable=SC2016  # jq variables are literal in its filter.
check "interrupted: state keeps ok and lists the files" jq -e --arg p "$A66" '.ok == true and .recovery.files == [$p] and (.message | contains("recover"))' <<<"$out"
out=$(run66 apply)
check "interrupted: apply is one refusal record" jq -e '.nixarchyPkgApply | .ok == false and .exit == null and (.message | contains("recover"))' <<<"$out"
check "interrupted: apply is the only line" test "$(wc -l <<<"$out")" = 1
check "interrupted: nixarchy-apply was not run" not test -e "$W66/stub/argv"

fixture66
hold66
out=$(run66 pending)
check "running: pending says writing" jq -e '.ok == true and .writing == true' <<<"$out"
out=$(run66 state)
check "running: state has no recovery key" jq -e 'has("recovery") | not' <<<"$out"
out=$(run66 apply)
check "running: apply says in progress" jq -e '.nixarchyPkgApply | .ok == false and (.message | contains("in progress"))' <<<"$out"
check "running: nixarchy-apply was not run" not test -e "$W66/stub/argv"
release66

fixture66
hold66 -s
out=$(run66 apply)
check "a shared holder does not hide the interruption" jq -e '.nixarchyPkgApply | .ok == false and (.message | contains("an earlier write was interrupted"))' <<<"$out"
check "shared holder: nixarchy-apply was not run" not test -e "$W66/stub/argv"
release66

fixture66
rm -f "$XDG_STATE_HOME/nixarchy/applied/lock"
out=$(run66 pending)
check "missing lock: pending says writing" jq -e '.writing == true and .ok != false' <<<"$out"
check "missing lock: the probe did not create it" not test -e "$XDG_STATE_HOME/nixarchy/applied/lock"

fixture66
tout=$(run66 toggle app foo)
pout=$(run66 pending)
# shellcheck disable=SC2016  # jq variables are literal in its filter.
check "toggle refuses with the one message" jq -e --arg p "$A66" '.ok == false and (.error | contains("an earlier write was interrupted (" + $p))' <<<"$tout"
# shellcheck disable=SC2016  # jq variables are literal in its filter.
check "pending uses the same message" jq -e --arg p "$A66" '.ok == false and (.error | contains("an earlier write was interrupted (" + $p))' <<<"$pout"
rm -rf "$W66"

# A pipeline whose FIRST command exits non-zero on a normal outcome --
# `diff` finding differences, `grep` finding nothing, `head` closing the pipe
# under it -- is a failure under `set -euo pipefail` (bin/nixarchy-pkg:39).
# No linter catches this for us: the checker is clean on this file, and even
# with its optional rules on it reaches only the `diff` and misses both
# `grep | head`s. (Naming that tool at the start of a comment turns the line
# into a directive it then fails to parse, which is its own small lesson.)
echo "the shape that caused it"
# Comments are stripped first, or this trips on the comments explaining
# why these shapes are gone. Requiring whitespace after the name keeps
# `comm` from matching inside `command -v`.
code() { grep -vE '^[[:space:]]*#' "$ADAPTER"; }
heads_a_pipeline() { code | grep -qE '^[[:space:]]*(diff|comm|cmp)[[:space:]][^|]*\|'; }
pipes_into_head() { code | grep -qE '(grep|diff|comm|cmp)[[:space:]][^|]*\|[[:space:]]*head([[:space:]]|$)'; }
check "no diff, comm or cmp at the head of a pipeline" not heads_a_pipeline
check "nothing is piped into head"                     not pipes_into_head

# And the shape that caused #39: mv onto a user's file replaces the inode,
# taking the mode, the owner and any symlink with it. Recovery data is the
# adapter's own, so its stage changes are allowed.
renames_onto_a_config() {
  # Counted, not -q (or >/dev/null, which GNU grep treats the same): stopping
  # at the first match SIGPIPEs the grep before it, and under pipefail that
  # hides the very mv this looks for.
  local n
  # shellcheck disable=SC2016  # match literal $TXN text in source
  n=$(code | grep -E '\bmv[[:space:]]+"' |
        grep -cvE '\bmv[[:space:]]+"\$TXN/(new|open)"[[:space:]]+"\$TXN/(open|done)"' || true)
  [ "$n" -gt 0 ]
}
edits_in_place() { code | grep -qE '\bsed[[:space:]]+-i\b'; }
check "no mv onto a file the adapter owns" not renames_onto_a_config
check "no sed -i"                          not edits_in_place

echo "options discovered from the flake (#62)"
# A stub nix that prints a canned `out.json`, so no real flake is ever
# evaluated: NIXARCHY_FLAKE points at a throwaway directory, never /etc/nixos.
O62=$(mktemp -d); mkdir -p "$O62/bin" "$O62/fl" "$O62/fl2" "$O62/cache" "$O62/state"
touch "$O62/fl/flake.nix" "$O62/fl2/flake.nix"
echo lock-one >"$O62/fl/flake.lock"; echo lock-one >"$O62/fl2/flake.lock"
cat >"$O62/bin/nix" <<'NEOF'
#!/usr/bin/env bash
echo run >>"$O62/nix.calls"
case "${NIX_MODE-ok}" in
  change-lock) echo lock-during-eval >"$O62/fl/flake.lock" ;;
  fail)  echo "error: attribute 'x' missing" >&2; exit 1 ;;
  nohost) echo "error: flake does not provide attribute 'nixosConfigurations.\"h\"'" >&2; exit 1 ;;
  sleep) sleep 5 ;;
  nohm)  echo '{"nixos":[{"name":"programs.git.enable","type":"boolean","description":"","default":null,"example":null,"declarations":[],"readOnly":false}],"homeManager":false,"users":[],"perUser":false,"home":null}'; exit 0 ;;
esac
cat <<JSON
{"nixos":[{"name":"programs.git.enable","type":"boolean","description":"Whether to\nenable git","default":{"_type":"literalExpression","text":"false"},"example":null,"declarations":["/m.nix"],"readOnly":false}],
 "homeManager":true,"users":["$(command id -un)"],"perUser":true,
 "home":[{"name":"programs.hm.enable","type":"boolean","description":"hm","default":null,"example":null,"declarations":[],"readOnly":false}]}
JSON
NEOF
chmod +x "$O62/bin/nix"
export O62
opt62() { env PATH="$O62/bin:$PATH" XDG_STATE_HOME="$O62/state" XDG_CACHE_HOME="${CACHE62:-$O62/cache}" \
  NIXARCHY_FLAKE="${FLAKE62:-$O62/fl}" "$ADAPTER" "$@"; }
mkdir -p "$O62/cache/nixarchy"
printf 'pkg\tgit\tthe git\tflags\tprev\nopt\tprograms.git.enable\tstale row\tboolean\tOLD\n' >"$O62/cache/nixarchy/index.tsv"
OC=$O62/cache/nixarchy

out=$(opt62 search git --kind opt)
check "without a cache, search says source system and keeps the index rows" \
  jq -e '.options.source == "system" and .rows[0].summary == "stale row" and .rows[0].scope == "system"' <<<"$out"

out=$(opt62 options refresh)
check "refresh answers ok from the flake" jq -e '.ok and .source == "flake" and .counts.system == 1 and .counts.user == 1 and .homeManager' <<<"$out"
check "it publishes system.json, user.json, rows.tsv and meta.json" \
  test -f "$OC/options/system.json" -a -f "$OC/options/user.json" -a -f "$OC/options/rows.tsv" -a -f "$OC/options/meta.json"
# shellcheck disable=SC2016 # awk program, not shell
check "rows.tsv rows have six columns, the last the scope" \
  awk -F'\t' 'NF != 6 || ($6 != "system" && $6 != "user") { exit 1 }' "$OC/options/rows.tsv"
check "meta.json carries the stamp, flake, host and user" \
  jq -e '(.stamp | length == 64) and .flake == "'"$O62"'/fl" and .host != null and .user != null' "$OC/options/meta.json"

out=$(opt62 search git --kind opt)
check "search takes option rows from the cache, not the index" \
  jq -e '.options.source == "flake" and (.rows | length == 1) and .rows[0].summary == "Whether to enable git" and .rows[0].scope == "system"' <<<"$out"
check "state reports where the options came from" \
  jq -e '.optionsInfo.source == "flake" and .optionsInfo.stale == false' <<<"$(opt62 state)"
out=$(NIX_MODE=change-lock opt62 options refresh)
check "refresh succeeds when the lock changes during eval" jq -e '.ok == true' <<<"$out"
check "a lock changed during eval leaves state options stale" \
  jq -e '.optionsInfo.source == "flake" and .optionsInfo.stale == true' <<<"$(opt62 state)"
echo lock-one >"$O62/fl/flake.lock"
opt62 options refresh >/dev/null
check "describe reads the cached system.json" \
  jq -e '.ok and .source == "flake" and .scope == "system" and .default == "false"' <<<"$(opt62 opt describe programs.git.enable)"
check "describe --scope user reads user.json" \
  jq -e '.ok and .scope == "user" and .path == "programs.hm.enable"' <<<"$(opt62 opt describe --scope user programs.hm.enable)"

# A changed lock makes the cache stale, not unusable.
echo lock-two >"$O62/fl/flake.lock"
check "a changed flake.lock marks the cache stale" \
  jq -e '.options.source == "flake" and .options.stale == true' <<<"$(opt62 search git)"
echo lock-one >"$O62/fl/flake.lock"

# Another flake with the identical lock must not borrow this cache.
out=$(FLAKE62=$O62/fl2 opt62 search git --kind opt)
check "a cache built for another flake is not used" \
  jq -e '.options.source == "system" and .rows[0].summary == "stale row"' <<<"$out"

# Failure and timeout leave the published cache byte-identical.
before=$(readlink "$OC/options"; cat "$OC/options"/*)
out=$(NIX_MODE=fail opt62 options refresh)
check "a failed refresh answers ok:false with nix's words" jq -e '.ok == false and (.error | contains("attribute"))' <<<"$out"
printf '#!/bin/sh\nexit 124\n' >"$O62/bin/timeout"; chmod +x "$O62/bin/timeout"
out=$(opt62 options refresh)
check "a timed-out refresh answers ok:false" jq -e '.ok == false and (.error | contains("timed out"))' <<<"$out"
rm "$O62/bin/timeout"
check "neither moves the published cache" test "$before" = "$(readlink "$OC/options"; cat "$OC/options"/*)"
out=$(NIX_MODE=nohost opt62 options refresh)
check "a flake without the host is named" jq -e '.ok == false and (.error | contains("nixosConfigurations"))' <<<"$out"
mkdir -p "$O62/fl3"; touch "$O62/fl3/flake.nix"
FLAKE62=$O62/fl3 NIX_MODE=nohm opt62 options refresh >/dev/null
check "describe --scope user with no user.json refuses, saying why" \
  jq -e '.ok == false and (.error | contains("no Home Manager"))' <<<"$(FLAKE62=$O62/fl3 opt62 opt describe --scope user programs.git.enable)"
check "and still describes the system scope from that cache" \
  jq -e '.ok and .source == "flake"' <<<"$(FLAKE62=$O62/fl3 opt62 opt describe programs.git.enable)"

# An invalid user name is refused before nix runs.
# shellcheck disable=SC2016 # the stub's own script
printf '#!/bin/sh\n[ "$1" = -un ] && { echo "Bad;User"; exit 0; }\nexec /usr/bin/env id "$@"\n' >"$O62/bin/id"; chmod +x "$O62/bin/id"
: >"$O62/nix.calls"
out=$(opt62 options refresh)
check "an invalid user name is refused" jq -e '.ok == false and (.error | contains("invalid user"))' <<<"$out"
check "and nix was never called" test ! -s "$O62/nix.calls"
rm "$O62/bin/id"

# A second refresh while one runs is refused.
NIX_MODE="sleep" opt62 options refresh >"$O62/first.out" &
first=$!
for _ in $(seq 50); do [ -s "$O62/nix.calls" ] && break; sleep 0.1; done
out=$(opt62 options refresh)
check "a second refresh while one runs is refused" jq -e '.ok == false and (.error | contains("already being read"))' <<<"$out"
wait "$first"

# Killed between building and the rename: the old cache stays published, and
# the half-built generation is removed.
gens_before=$(find "$OC/options.d" -mindepth 1 | wc -l)
# shellcheck disable=SC2016 # the stub's own script
printf '#!/bin/sh\nkill -TERM $PPID\nsleep 1\nexit 1\n' >"$O62/bin/mv"; chmod +x "$O62/bin/mv"
before=$(readlink "$OC/options")
out=$(opt62 options refresh)
rm "$O62/bin/mv"
check "a refresh killed before the rename answers ok:false" jq -e '.ok == false' <<<"$out"
check "the old cache is still the published one" test "$before" = "$(readlink "$OC/options")"
check "and no half-built generation is left" test "$gens_before" = "$(find "$OC/options.d" -mindepth 1 | wc -l)"

# Two generations are kept, so a reader that resolved the old one is safe.
first_gen=$(readlink "$OC/options"); sleep 1
opt62 options refresh >/dev/null; second_gen=$(readlink "$OC/options")
check "the replaced generation survives one publish" test -d "$first_gen" -a "$first_gen" != "$second_gen"
sleep 1; opt62 options refresh >/dev/null
check "and goes after the next" test ! -d "$first_gen"
# A cache home may itself be a symlink; preserve the previous resolved target.
mkdir -p "$O62/real-cache"
ln -s "$O62/real-cache" "$O62/linked-cache"
CACHE62=$O62/linked-cache opt62 options refresh >/dev/null
linked_old=$(readlink -f "$O62/linked-cache/nixarchy/options")
sleep 1
CACHE62=$O62/linked-cache opt62 options refresh >/dev/null
check "symlinked cache home keeps the replaced generation" test -d "$linked_old"
rm -rf "$O62"

echo "failure is a value, not an exit code"
out=$("$ADAPTER" nosuchcommand); rc=$?
check "exits 0 on an unknown command" test "$rc" = 0
check "says so in the object"         jq -e '.ok == false and (.error | length > 0)' <<<"$out"

echo
# ctoggle's HOME: a writer that wrote there would have written into ~.
check "no catalogue toggle wrote into HOME" \
  test -z "$(find "$THOME" -mindepth 1 -print -quit)"
find "$THOME" -mindepth 1 -printf '  in the scratch HOME: %P\n'
rm -rf "$XDG_STATE_HOME" "$THOME" "$QUIET" "$FIXSTUB"
if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
