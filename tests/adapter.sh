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

# `check "..." ! grep ...` does not work: check runs "$@", so the `!` is
# looked up as a command and is not one. A function can be, so negation gets
# one rather than every negative assertion silently failing.
not() { ! "$@"; }

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

# FIRST, because the whole design rests on it: a path assignment merges
# with an attrset that already exists, so an input can be declared by
# appending one top-level line rather than editing the inputs block.
merged=$(printf '{ a = { x = 1; }; a.y = 2; }' | nix-instantiate --eval --strict - 2>/dev/null || true)
check "a path assignment merges with an existing attrset" \
  test "$merged" = '{ a = { x = 1; y = 2; }; }'

FK=$(fresh_flake)
out=$(NIXARCHY_FLAKE="$FK" "$ADAPTER" flake add lib "path:$FLAKE_TMP/lib" 2>&1 || true)
check "declares an input"            jq -e '.ok == true'          <<<"$out"
check "shows the import rather than writing it" \
                                     jq -e '.import == "inputs.lib.nixosModules.default"' <<<"$out"
check "says it does not know the host file" \
                                     jq -e '.importNote | length > 0' <<<"$out"
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
check "says so when a flake cannot be read" \
  jq -e '.ok == false and (.message | length > 0)' \
  <<<"$("$ADAPTER" flake show "path:$FLAKE_TMP/nowhere" 2>&1 || true)"

echo "search"
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

echo "writers"
CONFIG=$(fresh_config); export XDG_CONFIG_HOME="$CONFIG"
on=$("$ADAPTER" toggle app brave)
check "toggling on reports enabled" jq -e '.apps[] | select(.id=="brave") | .enabled' <<<"$on"
check "the file really changed"     grep -qE '^[[:space:]]*brave\.enable = true;  #@ brave$' "$CONFIG/nixarchy/apps.nix"
off=$("$ADAPTER" toggle app brave)
check "toggling off reports disabled" jq -e '.apps[] | select(.id=="brave") | .enabled | not' <<<"$off"
svc=$("$ADAPTER" toggle service openssh)
check "services use their own file" jq -e '.services[] | select(.id=="openssh") | .enabled' <<<"$svc"
check "an unknown id is a value"    jq -e '.ok == false' <<<"$("$ADAPTER" toggle app nosuchapp)"
check "an unknown kind is a value"  jq -e '.ok == false' <<<"$("$ADAPTER" toggle widget brave)"

added=$("$ADAPTER" pkg add ripgrep)
check "pkg add lands in the list"   jq -e '.packages | map(.attr) | index("ripgrep")' <<<"$added"
removed=$("$ADAPTER" pkg remove ripgrep)
check "pkg remove takes it out"     jq -e '.packages | map(.attr) | index("ripgrep") | not' <<<"$removed"
check "apps.nix still parses"       nix-instantiate --parse "$CONFIG/nixarchy/apps.nix"
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
fi

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
"$ADAPTER" toggle app brave >/dev/null
# A toggle is one choice, though the diff sees a line leave and a line arrive.
check "a toggle counts once"   jq -e '.count == 1 and .changes[0].change == "on"' <<<"$("$ADAPTER" pending)"
"$ADAPTER" pkg add ripgrep >/dev/null
# #@pkgs-begin / #@pkgs-end are scaffolding pkg-add creates, not choices.
check "a package counts once"  jq -e '.count == 2' <<<"$("$ADAPTER" pending)"
"$ADAPTER" toggle app brave >/dev/null
check "toggling back drops it" jq -e '.count == 1' <<<"$("$ADAPTER" pending)"
# A row that is commented out on both sides is not a queued change, however
# much its text moved. Topping a catalogue up appends commented rows, and
# counting those reported sixteen things waiting to be built when the answer
# was none.
printf '\n    # newthing.enable = true;  #@ newthing\n' >> "$CONFIG/nixarchy/apps.nix"
check "a commented row is not a change" jq -e '.count == 1' <<<"$("$ADAPTER" pending)"
rm -rf "$CONFIG" "$FLAKE"; unset NIXARCHY_FLAKE

echo "apply"
# Driven against a STUB of nixarchy-apply, never the real one: the real one
# elevates and rebuilds a machine, so a test that invoked it would be a test
# that changed the machine. The stub records how it was called, then prints
# whatever the mode asks for.
STUB=$(mktemp -d)
cat > "$STUB/nixarchy-apply" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_DIR/argv"
cat > "$STUB_DIR/stdin"
echo "elevation=${NH_ELEVATION_STRATEGY:-unset}"
case "${STUB_MODE-}" in
  stream)    echo early; sleep 1; echo late ;;
  escapes)   printf '\033[1mADDED\033[0m\n50%%\r100%%\n' ;;
  fail)      echo "error: build failed"; exit 3 ;;
  nonewline) printf 'last' ;;
  fakejson)  echo '{"ok":true,"exit":0}'; echo after ;;
esac
exit 0
STUBEOF
chmod +x "$STUB/nixarchy-apply"
run_apply() { STUB_DIR="$STUB" STUB_MODE=$1 PATH="$STUB:$PATH" "$ADAPTER" apply; }
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
rm -rf "$STUB"

# What is queued, across more than one file at once.
#
# Every other case here queues one kind of thing, which is exactly how
# `pending` came to report only the first file that differed: apps alone was
# right, services alone was right, and the two together lost one of them.
# Anything queued in `advanced` had never been counted at all.
echo "pending across more than one file"
PCFG=$(fresh_config)
PBASE=$(mktemp -d); mkdir -p "$PBASE/nixarchy"
# The applied copy starts as the selection does, so nothing is queued yet.
cp "$PCFG/nixarchy"/*.nix "$PBASE/nixarchy/"
pending() { XDG_CONFIG_HOME="$PCFG" NIXARCHY_FLAKE="$PBASE" "$ADAPTER" pending; }

check "nothing queued is nothing"   jq -e '.count == 0' <<<"$(pending)"
XDG_CONFIG_HOME="$PCFG" "$ADAPTER" toggle service openssh >/dev/null
check "one file, one change"        jq -e '.count == 1' <<<"$(pending)"
check "and it names that file"      jq -e '[.changes[].file] == ["services"]' <<<"$(pending)"
XDG_CONFIG_HOME="$PCFG" "$ADAPTER" toggle app brave >/dev/null
check "two files, two changes"      jq -e '.count == 2' <<<"$(pending)"
check "and both files are named"    jq -e '[.changes[].file] | sort == ["apps", "services"]' <<<"$(pending)"
# A file that exists and cannot be read is not an empty one: it used to be
# reported as every line in the applied copy having been removed.
chmod 000 "$PCFG/nixarchy/services.nix"
check "an unreadable file is an error, not an empty file" \
                                    jq -e '.ok == false' <<<"$(pending)"
chmod 600 "$PCFG/nixarchy/services.nix"
check "and it recovers once readable" jq -e '.ok == true and .count == 2' <<<"$(pending)"
rm -rf "$PCFG" "$PBASE"

# The shape that caused it, so the next one is caught before it ships.
#
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

echo "failure is a value, not an exit code"
out=$("$ADAPTER" nosuchcommand); rc=$?
check "exits 0 on an unknown command" test "$rc" = 0
check "says so in the object"         jq -e '.ok == false and (.error | length > 0)' <<<"$out"

echo
if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
