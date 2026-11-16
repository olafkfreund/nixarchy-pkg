---
status: draft
issue: 68
spec: spec/2026-11-16-68-catalogue-test-ids.md
coders:
  1: codex   # pick_app/pick_service/ctoggle: sed regex with a backreference, locale, pipefail and SIGPIPE traps -- small tricky shell
  2: coder   # swap every hard-coded id for $APP/$SVC/ctoggle and add the CAN_TOGGLE guards -- mechanical, needs care with guard boundaries
reviewers:
  - codex   # bash semantics: pipefail, function-prefix env, setsid
  - agy     # independent read of the diff against this plan
---

# Plan: the catalogue tests pick their ids at run time

Branch `fix/68-catalogue-test-ids`. This file is self-contained: a coder
reads it and `tests/adapter.sh`, nothing else. **Coders never stage or
commit.** The coordinator commits after each step as `test: … (#68)`.

Only `tests/adapter.sh` changes. Not `bin/nixarchy-pkg`, not the writers,
not the catalogue, not the QML.

Line numbers are on `main` at `322d021` (#60 merged; its `tests/adapter.sh`
is byte-identical to the `feat/60-truthful-queue` tip). They are written
"#60 :N" below. Anchors quote the line; numbers drift.

After every step, run:
- `bash -n tests/adapter.sh`
- `shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh`
- `bash tests/adapter.sh`

Before this task, the suite has **11 failures** on a nixarchy machine with
sshd on, all fixed by this task: "toggling on reports enabled", "the file
really changed", "toggling off reports disabled", "services use their own
file", "a toggle counts once", "a package counts once", "one file, one
change", "and it names that file", "two files, two changes", "and both files
are named", "and it recovers once readable". After step 2: **0 failures**.

## Decisions (from the approved spec)

- **Why they fail.** The tests toggle `brave` (gone from
  `/etc/nixarchy/apps-template.nix`) and `openssh` (refused on a host that
  already runs sshd: "sshd is already on, and not from this menu row",
  `nixarchy-service-enable` line 74). Three checks need both toggles.
- **Ids are chosen at run time** from a scratch copy of the template, by a
  strict pattern. Never from `nixarchy-pkg state`: the adapter must not
  choose the ids it is tested on.
- **A usable app** is the first row of the shape
  `# <id>.enable = true;  #@ <id>` (optionally
  `programs.nixarchy.apps.<id>.enable`), with `<id>` in `[a-z0-9_-]` (what
  the writers accept, `nixarchy-app-enable` line 23). This excludes the 7
  `.settings` rows and the 7 on-by-default apps (`aether`, `hype`,
  `monologue`, `omacalc`, `omacut`, `omawrite`, `signed`), whose row is
  `# <id>.enable = false;` and which toggle off to a live `false`.
- **A usable service** is the first row `# <any option> = true;  #@ <id>`
  that is not in `GATED_SERVICES=" openssh "`. Services name their own
  options (`virtualisation.podman.enable`,
  `hardware.graphics.enable32Bit`, …), so the option part is free.
- **A gated service is never toggled**, not toggled and then skipped:
  toggling openssh on a host without sshd can prompt (`gum`) and write
  `~/.ssh/authorized_keys` (`nixarchy-service-enable` lines 45-59, 83-89,
  106-125). One printed note says it is excluded.
- **Every catalogue toggle runs with no terminal and a scratch `HOME`**
  (`ctoggle`). With no controlling terminal `gum` cannot prompt and the
  writer refuses ("No terminal, a cancel and a refused prompt are all a
  non-zero gum, so all refuse", line 38). A write to `~/…` lands in the
  scratch dir. The rest of the suite keeps the real `HOME`, which `nix` and
  `git` need.
- **No usable row is a failure**, once, at the top, with a message saying
  why; every check that would toggle is then not run. Not a skip: it means
  the catalogue's row shape changed.
- **No skip counter, no fixture catalogue.** CI has no `/etc/nixarchy` and
  still skips these sections.
- Measured on p620 (scratch copies, 2026-11-16): `pick_app` → `_1password`
  (64 matching rows); `pick_service` → `agent-local` (all 12 services
  match the pattern); `_1password` on/off and `agent-local` on through
  `ctoggle` all `ok: true`; scratch `HOME` stays empty; 0.58 s for three
  toggles.

## Steps

### 0. Coordinator: rebase and re-check

Rebase `fix/68-catalogue-test-ids` onto current `main` (#60 is merged). Re-check
that every anchor below is still where this plan says (`grep -n` the quoted
lines). Fix the line numbers here if they moved; that is not a deviation.

### 1. Helpers and the probe (codex)

**a. Helpers.** In `tests/adapter.sh`, directly after `fresh_config()`
(#60 :33-42, ends `printf '%s' "$dir"` / `}`), add exactly:

```bash
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
```

**b. Scratch `HOME`.** Directly after
`XDG_STATE_HOME=$(mktemp -d); export XDG_STATE_HOME` (#60 :29), add:

```bash
# A HOME for catalogue toggles only (ctoggle), so no writer reaches ~.
THOME=$(mktemp -d)
```

and at the end, beside `rm -rf "$XDG_STATE_HOME"` (the last lines of the
file), make it `rm -rf "$XDG_STATE_HOME" "$THOME"`.

**c. The probe.** Directly after the `HAVE_CATALOGUE` block (#60 :53-55,
ends `catalogue sections will be skipped"; }`), add:

```bash
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
```

Check: the three commands above; the suite still has the same 11
failures (nothing uses the helpers yet), plus the note line naming
`_1password` and `agent-local` on p620/razer.

Also check by hand, in a scratch dir:
`printf '# x.settings = { };  #@ x.settings\n# aether.enable = false;  #@ aether\n' > "$d/a.nix"`,
source the two functions, `pick_app "$d/a.nix"` prints nothing and exits 0.

Traps:
- `set -euo pipefail` is on (`tests/adapter.sh:7`). No `| head`, no early
  exit from a pipe reader without draining.
- `fail` and `pass` are defined at :14-15, before this point.
- Do not write anything to `/tmp` by name; `mktemp -d` only.
- `readonly GATED_SERVICES` must be defined once (the file is sourced
  nowhere else).

### 2. Use the chosen ids, and guard what needs them (coder)

Every change below is in `tests/adapter.sh`. Line numbers are #60's.

**a. "writers"** (#60 :289-305). Replace :292-298 and :300 with:

```bash
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
```

Move :299 ("an unknown id is a value", `toggle app nosuchapp`) unchanged to
just **before** the `if $CAN_TOGGLE; then`, so the guard is one block (it
toggles nothing, so order does not matter). Keep the `pkg add`/`pkg remove`/parse checks
(:302-306) outside the guard.

**b. "pending"** (#60 :416-438). The lines from
`"$ADAPTER" toggle app brave >/dev/null` (:423) through
`check "a commented row is not a change" …` (:436) go inside
`if $CAN_TOGGLE; then … fi`, with both toggles becoming
`ctoggle app "$APP" >/dev/null`. The lines before :423 (never-applied,
matching-flake checks) stay outside. `rm -rf "$CONFIG" "$FLAKE"; unset
NIXARCHY_FLAKE` (:437) stays outside, after the `fi`.

**c. "pending across more than one file"** (#60 :994-1015). Its
`if $HAVE_CATALOGUE; then` (:993) also covers the next two sections, up to
the `else` at :1126, so **do not touch that guard**. Instead wrap the lines
from `XDG_CONFIG_HOME="$PCFG" "$ADAPTER" toggle service openssh >/dev/null`
(:1002) through `check "and it recovers once readable" …` (:1014) in
`if $CAN_TOGGLE; then … fi`. "nothing queued is nothing" (:1001) stays
before it; `rm -rf "$PCFG" "$PBASE"` (:1015) stays after it. Inside:
- :1002 → `XDG_CONFIG_HOME="$PCFG" ctoggle service "$SVC" >/dev/null`;
- :1005 → `XDG_CONFIG_HOME="$PCFG" ctoggle app "$APP" >/dev/null`.

Everything else (counts, `["apps", "services"]`, the `chmod 000` case) is
unchanged.

**d. `realid`** (#60 :1121-1123). Replace

```bash
realid=$(grep -oE '#@ [a-z0-9-]+' "$APPSNIX" | head -1 | awk '{print $2}')
check "a real id still toggles" \
  jq -e '.ok == true' <<<"$("$ADAPTER" toggle app "$realid" 2>&1 || true)"
```

with

```bash
if $CAN_TOGGLE; then
realid=$APP   # $APPSNIX is a fresh copy of the same template the probe read
check "a real id still toggles" \
  jq -e '.ok == true' <<<"$(ctoggle app "$realid" 2>&1 || true)"
fi
```

The `'[a-z]*'` refusal checks above it (:1116-1120) are unchanged and stay
outside the guard (they toggle nothing).

**e. Nothing reached the scratch `HOME`.** At the end of the file, just
before `rm -rf "$XDG_STATE_HOME" "$THOME"`, add:

```bash
# ctoggle's HOME: a writer that wrote there would have written into ~.
check "no catalogue toggle wrote into HOME" \
  test -z "$(find "$THOME" -mindepth 1 -print -quit)"
find "$THOME" -mindepth 1 -printf '  in the scratch HOME: %P\n'
```

(Measured: three toggles left it empty.)

Check:
- `grep -nE 'toggle (app|service) (brave|openssh)' tests/adapter.sh` finds
  nothing (the probe's comment still names `brave`; that is fine).
- `grep -n '"\$ADAPTER" toggle' tests/adapter.sh` finds only the `ctoggle`
  definition, :299's `nosuchapp` and the `'[a-z]*'` refusal.
- `bash tests/adapter.sh`: **0 failures** on a nixarchy host (p620 or
  razer), note line present.
- `shellcheck` clean.

Traps:
- Do not re-indent bodies inside the new guards (the file's own rule,
  #60 :50-52): only the `if`/`fi` lines are added.
- `jq --arg id` for every id in a filter; no string interpolation into jq.
- `XDG_CONFIG_HOME="$PCFG" ctoggle …` keeps its prefix; do not export it.
- `ctoggle` reads stdin from `/dev/null`; do not pipe into it.

### 3. Coordinator: verify, review, PR

- On razer (the lead runs it): `bash tests/adapter.sh` → 0 failures.
- No-prompt check: `setsid -w bash tests/adapter.sh </dev/null` finishes.
- No-escape check: before and after the run,
  `find ~/.config/nixarchy ~/.local/state/nixarchy ~/.ssh -type f -print0 | sort -z | xargs -0 sha256sum`
  is identical.
- Negative checks, in a scratch **copy of the whole worktree**
  (`cp -r . "$(mktemp -d)"`; `ADAPTER` is found relative to the script, so
  the copy must carry `bin/` too):
  - replace the `readonly GATED_SERVICES=" openssh "` line with
    `readonly GATED_SERVICES=" openssh agent-local "`; the note names
    `devenv`, 0 failures;
  - make a scratch templates dir whose `apps-template.nix` holds only a
    `.settings` row and an on-by-default row (and the real services and
    advanced templates), and point `readonly TEMPLATES=` at it; the suite
    reports exactly one new FAIL, "no app row the tests can round-trip …",
    and none of "toggling on reports enabled", "a toggle counts once",
    "one file, one change", "a real id still toggles" appear in its output.
- Reviews: Codex and agy, read-only, on `git diff main` against this plan.
- `git diff main --stat` touches only `tests/adapter.sh` (plus this plan).
- PR links intent, spec and plan.

## Tests

| Command | Expected |
| --- | --- |
| `bash -n tests/adapter.sh` | exit 0 |
| `shellcheck bin/nixarchy-pkg bin/nixarchy-pkg-keys tests/adapter.sh` | no output |
| `bash tests/adapter.sh` on razer/p620 | `all passed`; note line names the chosen app and service |
| `bash tests/adapter.sh` in CI (no `/etc/nixarchy`) | unchanged: catalogue sections skipped, `all passed` |
| `setsid -w bash tests/adapter.sh </dev/null` on razer | finishes, no prompt |
| `nix flake check` | passes (shellcheck check covers the file) |

## Rollback

Revert the PR. Only `tests/adapter.sh` changes; nothing ships to users.

## Companion issues

None. (Optional, not filed: "nixarchy-service-enable: a non-interactive
mode", under which every gate refuses instead of prompting.)
