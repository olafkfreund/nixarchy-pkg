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

# The apply answers. Driven against a STUB of nixarchy-apply's shape, never
# the real one: the real one elevates and rebuilds a machine, so a test that
# invoked it would be a test that changed the machine.
echo "apply answers"
APPLY_TMP=$(mktemp -d)
cleanup_apply() { rm -rf "$APPLY_TMP"; }
trap cleanup_apply EXIT

# The stub mirrors nixarchy-apply:193 onwards: the preview prompt exists only
# when a preview binary is on PATH, and the switch prompt always follows.
mkdir -p "$APPLY_TMP/bin"
cat > "$APPLY_TMP/bin/nixarchy-apply" <<STUB
#!$(command -v bash)
if command -v nixarchy-preview >/dev/null 2>&1; then
  read -r -p "Preview in a VM first? [y/N] " reply || reply=""
  echo "PREVIEW_GOT=\$reply"
fi
read -r -p "Build and switch now? [y/N] " reply || reply=""
echo "SWITCH_GOT=\$reply"
case "\$reply" in
  [yY]*) echo "SWITCHED" ;;
  *) echo "Not switching. Run: something" ;;
esac
exit 0
STUB
chmod +x "$APPLY_TMP/bin/nixarchy-apply"
printf '#!/usr/bin/env bash\nexit 0\n' > "$APPLY_TMP/bin/nixarchy-preview"
chmod +x "$APPLY_TMP/bin/nixarchy-preview"

# With a preview binary present: two prompts, n then y.
out=$(PATH="$APPLY_TMP/bin:$PATH" "$ADAPTER" apply 2>&1 || true)
check "declines the preview when there is one"  grep -q 'PREVIEW_GOT=n' <<<"$out"
check "and accepts the switch"                  grep -q 'SWITCH_GOT=y'  <<<"$out"
check "and reports applied"                     grep -q '"ok":true'     <<<"$out"

# With it absent: ONE prompt, and it must get y. This is the regression --
# a fixed `n\ny\n` answered the switch prompt with n and reported success.
#
# Deleting the stub is not enough: the real nixarchy-preview is still on PATH
# on any machine that has it, and both the stub and cmd_apply ask `command -v`.
# So every PATH entry that provides one is stripped, and the result is checked
# rather than assumed -- on a machine without preview at all this is a no-op.
rm "$APPLY_TMP/bin/nixarchy-preview"

# A MINIMAL path rather than a filtered one. Stripping every directory that
# provides nixarchy-preview also strips whatever else lives beside it -- on
# this machine that took jq, and the adapter died before it asked anything,
# which made the assertion below pass for the wrong reason. So the stub
# directory gets exactly the tools `apply` needs and nothing else.
# bash and env among them: the adapter's own shebang is `#!/usr/bin/env bash`,
# so a PATH without those two cannot start it at all -- which failed as
# "env: 'bash': No such file or directory" and looked like a fault in the
# code under test rather than in the harness.
for t in jq grep bash env; do ln -sf "$(command -v $t)" "$APPLY_TMP/bin/$t"; done
# Tested as files, not with `env PATH=... command -v`: `command` is a shell
# builtin, so env looks for a binary of that name, never finds one, and the
# check passes or fails for a reason that has nothing to do with PATH.
check "the minimal path still has jq"        test -x "$APPLY_TMP/bin/jq"
check "and really has no nixarchy-preview"   not test -e "$APPLY_TMP/bin/nixarchy-preview"

out=$(PATH="$APPLY_TMP/bin" "$ADAPTER" apply 2>&1 || true)
check "asks only the switch when there is no preview" not grep -q 'PREVIEW_GOT' <<<"$out"
check "and still accepts it"                    grep -q 'SWITCH_GOT=y'  <<<"$out"
check "and reports applied"                     grep -q '"ok":true'     <<<"$out"

# And the belt: a decline must never read as success, whatever caused it.
cat > "$APPLY_TMP/bin/nixarchy-apply" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
echo "Not switching. Run: something"
exit 0
STUB
chmod +x "$APPLY_TMP/bin/nixarchy-apply"
out=$(PATH="$APPLY_TMP/bin:$PATH" "$ADAPTER" apply 2>&1 || true)
check "a decline is reported as a failure"      grep -q '"ok":false'    <<<"$out"
check "and is not called applied"               not grep -q '"message":"applied"' <<<"$out"
cleanup_apply
trap - EXIT

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
# A stand-in, so the wiring is proven without a real nixos-rebuild.
STUB=$(mktemp -d)
cat > "$STUB/nixarchy-apply" <<'STUBEOF'
#!/usr/bin/env bash
echo "elevation=${NH_ELEVATION_STRATEGY:-unset}"
echo "stdin=$(tr '\n' ',' </dev/stdin)"
exit 0
STUBEOF
chmod +x "$STUB/nixarchy-apply"
out=$(PATH="$STUB:$PATH" "$ADAPTER" apply)
# nh elevates itself and a QML Process has no tty; pkexec routes the
# prompt to Omarchy's own polkit agent instead.
check "apply asks for pkexec elevation" grep -q 'elevation=pkexec' <<<"$out"
# nixarchy-apply asks "Preview in a VM first?" then "Build and switch now?".
check "apply declines the VM and confirms the switch" grep -q 'stdin=n,y,' <<<"$out"
check "the last line is JSON"  jq -e '.ok' <<<"$(tail -1 <<<"$out")"
cat > "$STUB/nixarchy-apply" <<'STUBEOF'
#!/usr/bin/env bash
echo "error: build failed"; exit 1
STUBEOF
chmod +x "$STUB/nixarchy-apply"
check "a failing apply is reported" \
  jq -e '.ok == false and .exit == 1' <<<"$(PATH="$STUB:$PATH" "$ADAPTER" apply | tail -1)"
rm -rf "$STUB"

echo "failure is a value, not an exit code"
out=$("$ADAPTER" nosuchcommand); rc=$?
check "exits 0 on an unknown command" test "$rc" = 0
check "says so in the object"         jq -e '.ok == false and (.error | length > 0)' <<<"$out"

echo
if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
echo "all passed"
