---
title: From a terminal
---

# From a terminal

The panel does not talk to your machine directly. Everything it does goes
through one script — `bin/nixarchy-pkg` in the plugin directory — and that
script is perfectly usable on its own.

```bash
~/.config/omarchy/plugins/nixarchy.pkg/bin/nixarchy-pkg state
```

Every command prints one JSON object and exits 0. A refusal is a value, not a
crash: `{"ok": false, "error": "..."}` with exit status 0, because a writer
declining to do something is an answer.

## The commands

| | |
| --- | --- |
| `state` | Everything the panel draws: apps, services, packages, options, drafts |
| `search <query> --kind pkg\|opt [--limit N]` | The index, ranked |
| `toggle app\|service <id>` | What `SPACE` does |
| `pkg add <attr> [--stable\|--unstable]` | What `RETURN` and `SHIFT+RETURN` do |
| `pkg remove <attr>` | |
| `opt describe <path>` | An option's type, default, example and docs |
| `opt set <path> <value>` / `opt remove <path>` | |
| `draft new <url>` / `draft undraft <name>` | See [Drafts](drafts) |
| `pending` | What would change on the next apply |
| `apply` | The rebuild. Streams a log, then one JSON object |
| `reindex` | Rebuild the search index. About a minute |

## A worked example

What is queued, as a list of names:

```bash
nixarchy-pkg pending | jq -r '.changes[].id'
```

Everything unfree in your selection:

```bash
nixarchy-pkg state | jq -r '.packages[].attr'
```

Whether this machine follows stable or unstable:

```bash
nixarchy-pkg state | jq -r '.channel'
```

## What is stable and what is not

This page makes the output an interface, so it should say which parts.

**Relied on:** `ok` on every object, and `error` when `ok` is false. The
top-level keys of `state` — `apps`, `services`, `packages`, `options`,
`drafts`, `files`, `channel`, `indexStale`. The `count` and `changes` of
`pending`. Those are the shape, and changing them would be a breaking change.

**Not relied on:** the exact wording of any `message` or `error` string.
Those are a writer's own words, passed through unaltered, and the writers
belong to nixarchy rather than to this plugin — they will improve their
messages and this will pass the improvements along.

**Not an interface at all:** the log lines `apply` streams before its final
object. That is a build's output. Parse the last line, which is JSON, and
treat the rest as text for a human.

## The one thing to know about `apply`

It is the only command here that changes the machine, and it asks for
elevation. From a terminal you will get an ordinary password prompt; from the
panel it goes through polkit. If you are scripting, think about which of
those you want before you wire it into something unattended.
