---
status: draft
issue: 68
intent: intent/2026-11-16-68-catalogue-test-ids.md
---

# Spec: the catalogue tests pick their ids at run time

## Design

**Decisions from intent approval** (its open questions, taken as
recommended):

1. Only refusals the tests know to be host-dependent count as a skip. Today
   that is `openssh`'s. Any other refusal is a failure.
2. A row is usable for a round-trip test when the writers accept its id, it
   is not a `.settings` row, it is not on by default, and it has no host
   gate.
3. No fixture catalogue in this task.

**Decisions for the owner** (none of the intent's questions were left open;
these are choices this spec makes and the owner can overturn):

- **A gated service is never toggled, not toggled and then skipped.**
  Decision 1 calls openssh's refusal a skip. Toggling it to find out is
  what can prompt and write `~/.ssh/authorized_keys` on a host without sshd
  (`nixarchy-service-enable` lines 45-59, 83-89, 106-125). So the tests
  exclude it by name before choosing, and print one note saying so. Every
  service they do toggle must succeed, or the check fails.
- **Every catalogue toggle also runs with no terminal and a scratch
  `HOME`.** The exclusion list covers the gate we know; this covers one we
  do not. With no controlling terminal, `gum` cannot prompt and the writer
  refuses ("No terminal, a cancel and a refused prompt are all a non-zero
  gum, so all refuse", `nixarchy-service-enable` line 38). With `HOME` in a
  temp dir, a write to `~/...` lands there. The rest of the suite keeps the
  real `HOME`, which `nix` and `git` need.
- **Ids come from the scratch copy of the template, by a strict pattern,
  not from `nixarchy-pkg state`.** Using the adapter to choose the ids the
  adapter is then tested on would let an adapter bug pick a bad id and hide
  itself.
- **No eligible row is a failure, with a message that says which kind.**
  A catalogue whose apps are all `.settings` or on by default, or whose
  services are all gated, would leave nothing to round-trip. That is not a
  host reason, so by decision 1 it fails: "no app row the tests can
  round-trip (every row is a settings row, on by default, or not in the
  `# <id>.enable = true;  #@ <id>` shape)". The owner may prefer a skip
  here; it would hide a catalogue-shape change from this suite.

Everything is in `tests/adapter.sh`. No change to `bin/nixarchy-pkg`, the
writers, the catalogue or the QML.

### 1. Picking the ids

Defined after `fresh_config` (`tests/adapter.sh:33-42`):

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
      cat >/dev/null; }   # drain, so sed never sees a closed pipe
}

# A catalogue toggle: no terminal to prompt on, and a HOME of its own.
ctoggle() { HOME="$THOME" setsid -w "$ADAPTER" toggle "$@" </dev/null; }
```

`THOME=$(mktemp -d)` is made beside `XDG_STATE_HOME` (`:29`) and removed at
the end. `setsid` is util-linux, already needed for `flock`.

Measured on p620 against `/etc/nixarchy` (scratch copies, 2026-11-16):

- `pick_app` matches 64 rows and picks `_1password`; it skips all 7
  `.settings` rows and all 7 on-by-default rows. On a file holding only
  those two kinds it prints nothing.
- `pick_service`'s pattern matches all 12 services, including the five
  with their own option names; it picks `agent-local`.
- Through `ctoggle`: `_1password` on, then off, and `agent-local` on, all
  answer `ok: true` with the expected `enabled`; openssh, tried once for
  this measurement only, is refused with the sshd message. The scratch
  `HOME` stays empty. 0.58 s for the three.
- Without `LC_ALL=C`, an earlier form of the service pattern silently
  skipped `agent-local` (its note has bytes `.` would not match). Hence the
  rule above.

Once, inside `if $HAVE_CATALOGUE; then`, before "writers"
(`tests/adapter.sh:289`):

```bash
probe=$(fresh_config)
APP=$(pick_app "$probe/nixarchy/apps.nix")
SVC=$(pick_service "$probe/nixarchy/services.nix")
rm -rf "$probe"
echo "  using app '${APP:-none}', service '${SVC:-none}'; never toggling:$GATED_SERVICES"
CAN_TOGGLE=true
[ -n "$APP" ] || { fail "no app row the tests can round-trip (…)"; CAN_TOGGLE=false; }
[ -n "$SVC" ] || { fail "no service row the tests can round-trip (…)"; CAN_TOGGLE=false; }
```

The "writers" toggle block (`:290-300`), the "pending" toggle block
(`:416-438`), "pending across more than one file" (`:504-525`) and the
`realid` check (`:631-633`) each sit inside `if $CAN_TOGGLE; then … fi`, so
an empty id fails once, at the top, and nothing downstream runs on `""`.
The remaining checks in those sections that need no catalogue id
(`pkg add`, `opt …`) stay outside the guard.

### 2. The checks that change

Line numbers are main's; on `feat/60-truthful-queue` the last two blocks
sit at 986-1000 and 1109-1116, with the same text.

| Where | Now | Becomes |
| --- | --- | --- |
| `:292-296` "writers" | `"$ADAPTER" toggle app brave`, `select(.id=="brave")` | `ctoggle app "$APP"`, `jq --arg id "$APP" '… select(.id==$id) …'` |
| `:294` "the file really changed" | `'^[[:space:]]*brave\.enable = true;  #@ brave$'` | `"^[[:space:]]*(programs\.nixarchy\.apps\.)?$APP\.enable = true;[[:space:]]+#@ $APP([[:space:]]\|\$)"`: a row may carry a note after its marker |
| `:297-298` | `toggle service openssh`, `select(.id=="openssh")` | `ctoggle service "$SVC"`, `jq --arg id "$SVC"` |
| `:300` "an unknown kind is a value" | `toggle widget brave` | `ctoggle widget "$APP"` (it already passes; this removes the last dropped name) |
| `:423`, `:429` "pending" | `toggle app brave` | `ctoggle app "$APP"` |
| `:512`, `:515` | `toggle service openssh`, `toggle app brave` | `ctoggle service "$SVC"`, `ctoggle app "$APP"` (keeping the `XDG_CONFIG_HOME="$PCFG"` prefix) |
| `:631-633` `realid` | `grep -oE '#@ [a-z0-9-]+' … \| head -1`, then `toggle app` | `realid=$(pick_app "$APPSNIX")`, then `ctoggle app` |

Nothing else in the assertions changes: the counts, the file names
(`["apps", "services"]`) and the unreadable-file case stay as they are.
`pick_*` only return `[a-z0-9_-]+`, so the ids are safe inside a regex; a
comment at `:294` says so.

### 3. What this does not do

- No skip counter. The suite has `pass`/`fail` only (`tests/adapter.sh:14-15`);
  the gated-service line is a printed note, like the existing
  `skip: needs $TEMPLATES` lines (`:121`, `:440`, `:637`).
- No fixture catalogue, so CI (`.github/workflows/ci.yml:28`, no
  `/etc/nixarchy`) still skips these sections.
- Desktop notifications: `nixarchy-app-enable` (lines 59-63) and
  `nixarchy-service-enable` send them on a toggle. They did before; the
  tests do not stub `omarchy-notification-send`. A scratch `HOME` does not
  stop them (they go over D-Bus).

### Slices

One PR. It lands after #60 (PR #70), rebased onto it; the change is to the
same lines on both.

### Companion nixarchy issue

None needed. Optional, not filed by this task: *"nixarchy-service-enable:
a non-interactive mode"*, under which every gate refuses instead of
prompting, so callers need not take away the terminal to be safe.

## Alternatives rejected

- **Toggle every service until one succeeds.** Reaches openssh on the way
  on some catalogues.
- **Read ids from `nixarchy-pkg state`.** Couples the choice to the code
  under test.
- **A scratch `HOME` for the whole suite.** `nix` and `git` elsewhere in the
  suite use the real one's configuration. Only the toggles get one.
- **Keep naming ids, but current ones.** That is how `brave` broke.

## Risks

- **A new gate that needs no terminal** and writes outside `HOME` (for
  example to `/run` or over D-Bus) would not be caught by `ctoggle`. None
  exists today: every prompt and write outside the selection in
  `nixarchy-service-enable` is under `[ "$id" = openssh ]` (its line 133).
  `GATED_SERVICES`'s comment says to add such services.
- **A catalogue whose first plain app fails for another reason.** The check
  fails and says so: a real failure to look at.
- **The row shape changes.** `pick_*` return nothing and the suite fails at
  the top with the reason, rather than toggling the wrong thing.
- Hosts: any nixarchy machine. CI is unaffected.

## Verification

- `shellcheck tests/adapter.sh` is clean (the `flake.nix:63` check).
- On razer (repo verification host), in throwaway XDG dirs:
  `bash tests/adapter.sh` reports 0 FAIL and prints the chosen ids. Also on
  any host with sshd on (the case that failed).
- Negative checks, by hand in a scratch copy: a `apps.nix` with only
  `.settings` and on-by-default rows makes the suite fail once at the top
  with "no app row …" and run no toggle; adding `agent-local` to
  `GATED_SERVICES` makes it pick `devenv`.
- No-prompt check: run the suite with no terminal
  (`setsid -w bash tests/adapter.sh </dev/null`); it finishes.
- No-escape check: before and after the run,
  `find ~/.config/nixarchy ~/.local/state/nixarchy ~/.ssh -type f -print0 | sort -z | xargs -0 sha256sum`
  gives identical output, and the scratch `HOME`'s listing is captured
  before it is removed.
- `git diff` touches only `tests/adapter.sh`.
