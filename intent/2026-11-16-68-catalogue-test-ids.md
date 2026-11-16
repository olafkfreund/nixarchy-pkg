---
status: draft
issue: 68
author: olafkfreund
---

# Intent: the catalogue tests pass on any nixarchy machine whose catalogue they read

## Problem

`tests/adapter.sh` builds every catalogue case from this machine's own
`/etc/nixarchy/*-template.nix` (`fresh_config`, `tests/adapter.sh:33`), and
then toggles ids it names by hand. The catalogue moved on and the names did
not. On a current nixarchy machine (checked on main, `d3aabd3`), 11 checks
fail. There are two causes, and the issue names only the first.

- **`brave` is gone.** `toggle app brave` (`tests/adapter.sh:292`, `:295`,
  `:423`, `:429`, `:515`) now answers `ok: false`, because
  `apps-template.nix` has no `#@ brave` row. Every check that reads that
  toggle fails: `:293`, `:294`, `:296`, and the `pending` counts at `:425`
  and `:428`. "Toggling back drops it" (`:430`) still passes, by coincidence.
- **`openssh` is refused on a host that already runs sshd.**
  `toggle service openssh` (`:297`, `:512`) answers `ok: false` here.
  `nixarchy-service-enable` says "sshd is already on, and not from this menu
  row" (its line 74) and leaves the file unchanged. So "services use their
  own file" (`:298`), "one file, one change" (`:513`) and "and it names that
  file" (`:514`) fail because of how the host is configured, not because the
  adapter is wrong. The other 11 services in the template toggle cleanly
  here.
- **Three checks need both.** "Two files, two changes" (`:516`), "and both
  files are named" (`:517`) and "and it recovers once readable" (`:524`)
  need the `openssh` and the `brave` toggle. Fixing `brave` alone leaves six
  of the eleven failing on a host that runs sshd.

Swapping in other ids is not as simple as it looks. Three traps:

- **The writers accept fewer ids than the adapter.** The adapter's check
  allows `[a-zA-Z0-9._-]` (`bin/nixarchy-pkg:495`). `nixarchy-app-enable`,
  `-app-disable`, `-service-enable` and `-service-disable` allow only
  `[a-z0-9_-]` (for example `nixarchy-app-enable` line 23).
- **Some apps do not toggle back to where they started.** Seven apps are on
  by default (`default_on` in `nixarchy-app-disable`: `aether`, `hype`,
  `monologue`, `omacalc`, `omacut`, `omawrite`, `signed`). Their template row
  is `# aether.enable = false;`. Turning one off writes a live
  `enable = false;` line, which the adapter reads as an enabled, queued row.
  Such an app fails "toggling off reports disabled" and "toggling back drops
  it".
- **`openssh` touches the real home directory when sshd is off.** On a host
  without sshd, `nixarchy-service-enable`'s openssh gate can prompt with
  `gum`, fetch keys from GitHub, and append to `$HOME/.ssh/authorized_keys`
  (its `authorize_key`, lines 45-59, called from the gate around lines
  106-125). The tests isolate `XDG_CONFIG_HOME` and `XDG_STATE_HOME`, not
  `HOME` or the terminal (`tests/adapter.sh:29-42`). Toggling openssh, or any
  service that later gains a gate like it, can change the user's real files.

Also, `:294` expects the toggled line to end at its marker
(`#@ brave$`). Many template rows carry a note after the marker, so that
check cannot be reused unchanged for another id.

CI runs `bash tests/adapter.sh` (`.github/workflows/ci.yml:28`), but CI has
no `/etc/nixarchy`, so `HAVE_CATALOGUE` is set false (`:54`) and these
sections are skipped. `nix flake check` does not run the suite at all
(`flake.nix:63` only shellchecks it). Nothing catches the drift except
running the suite by hand on a real machine, and then it reports failures
that are not regressions.

The `realid` check (`:631`, in the "a read says what it could not read"
section) already picks an id at run time. Its pattern `#@ [a-z0-9-]+` skips
`_1password`, the template's first app, and lands on `bitwarden`. That is
luck, not design.

## Proposed outcome

- On any nixarchy machine, the catalogue sections pass when the adapter is
  correct, whatever apps and services the catalogue ships and whatever the
  host already runs.
- No test toggles a catalogue id by a name the template might drop.
- A check that cannot run on this host, for a known host reason, says so and
  why, as a skip. A refusal the tests do not expect is still a failure, so a
  broken adapter cannot hide behind skips.
- The checks keep asserting what they assert today: toggle on and off, the
  file really changes, services land in their own file, and the `pending`
  counts.
- Running the suite never prompts, and never changes anything outside its
  throwaway directories.

## Affected users and systems

- `tests/adapter.sh` only: the "writers", "pending" and "pending across more
  than one file" sections, and the `realid` check.
- Whoever runs the suite on a nixarchy machine. CI runs the suite but skips
  these sections.

## Constraints

- Must keep every test on a throwaway `XDG_CONFIG_HOME` and `XDG_STATE_HOME`,
  and must not touch the user's real `$HOME` (for example
  `~/.ssh/authorized_keys`) or prompt on the terminal.
- Must not change the adapter, the writers or the catalogue to suit a test.
- Must never run the real `nixarchy-apply`; the existing stub stays.
- Stays shellcheck-clean (`flake.nix:63`).
- No new dependency.

## Open questions

1. **Is a writer's host refusal a skip or a failure?** openssh is refused
   here for a real reason. Recommended: only refusals the tests know to be
   host-dependent (openssh's) count as a skip. Any other refusal fails. The
   alternative is to avoid gated services entirely and fail on any refusal,
   which is simpler and also keeps the tests away from openssh's prompts.
2. **What makes a row usable for a round-trip test?** Recommended: an app
   or service whose id the writers accept, which is not a `.settings` row,
   not on by default, and not gated by a host check. The spec decides how to
   find it (from the template or from `nixarchy-pkg state`).
3. **Should a fixture catalogue be added** so CI runs these sections too?
   Recommended: not in this task. It is worth a follow-up once these
   sections stop depending on names.
