# claude-telegram-multi-relay

> Orchestrate a **fleet** of Claude Code sessions over Telegram: create, send,
> broadcast, schedule recurring tasks via macOS launchd, monitor health, and
> manage the full lifecycle across tmux windows and Telegram forum topics.

Connect Claude Code with Telegram **two-way**, supporting **multi-session**,
**multi-topic**, and **multi-user/multi-group** — plus **persistent scheduling**
that survives reboot and wake-from-sleep.

Use when the user wants to: run multiple Claude sessions in parallel; schedule
automated tasks that trigger Claude sessions; manage launchd agents for Claude
workers; or control a fleet of Claude workers from their phone.

KHÔNG dùng cho: single-session work (→ use `ccc` directly), chatbot workflows,
or CronCreate-only temp scheduling (→ use CronCreate directly).

---

## What this is (read first)

This is the **orchestration layer** on top of [`ccc`](https://github.com/kidandcat/ccc)
(Claude Code Companion), the relay engine. `ccc` handles the single-session
Claude↔Telegram bridge; **this skill** adds multi-session/topic/user
coordination + scheduling + fleet management.

- Full explanation: [`docs/`](./docs/) — start with
  [`01-what-is-telegram-relay.md`](./docs/01-what-is-telegram-relay.md) and
  [`03-multi-session-architecture.md`](./docs/03-multi-session-architecture.md).
- Install + bot token setup: [`docs/04-install-guide.md`](./docs/04-install-guide.md).

## Architecture

```
claude-telegram-multi-relay  (this skill — orchestration)
├── scripts/relay.sh             core library: new/send/broadcast/list/kill/cron-*
├── scripts/run-scheduled.sh     launchd ↔ Claude bridge
├── scripts/cron_to_launchd.py   cron expr → launchd plist converter
├── Session Registry             $ORCH_DIR/registry.json   (purpose, tags, status)
├── Schedule Registry            $ORCH_DIR/schedules.json  (cron, prompt, history)
├── LaunchAgents                 ~/Library/LaunchAgents/com.vccc.*.plist
├── Log Dir                      $ORCH_DIR/logs/
├── ccc engine                   https://github.com/kidandcat/ccc  (token, hook, relay)
├── ccc config                   $HOME/.config/ccc/config.json
├── Telegram Bot API             token from ccc config
├── tmux                         one window per session
└── macOS launchd                primary scheduler (launchctl + plist)
```

`ORCH_DIR` defaults to `$HOME/.claude/ccc-orchestrator` (override via
`config/relay.example.env` → copy to `$ORCH_DIR/relay.env`). All paths are
configurable; nothing is hardcoded to a machine.

## Data model (4 sources, must stay in sync — R-12)

| Source | Role |
|---|---|
| `ccc config.json` | connection: bot_token, group_id, sessions{topic_id, path, window_id, group_id} |
| `registry.json` | orchestration meta: purpose, tags, status, auto_restart |
| `schedules.json` | cron expr, prompt, last_run, enabled |
| `com.vccc.*.plist` | launchd job definition |

ccc tracks connection data; registry tracks orchestration meta; schedules +
plist track recurring execution.

## Multi-group (1 bot → N groups)

ccc supports **one bot token serving many Telegram groups** simultaneously.
Each session stores its own `group_id`. Routing: `session.group_id ?? config.group_id`.

```json
{
  "bot_token": "...",
  "group_id": -1003460044206,
  "sessions": {
    "session-a": { "topic_id": 785, "path": "...", "window_id": "@19", "group_id": -1003460044206 },
    "session-b": { "topic_id": 123, "path": "...", "window_id": "@20", "group_id": -1000000000000 }
  }
}
```

Backward compatible: a session without `group_id` falls back to the top-level
value. Setup: add the bot to multiple topic-enabled groups → `/new <name>` in
each → the session auto-binds to that group.

## How to invoke the implementation

**Prefer reading JSON via the `Read` tool** (R-00); use `python3` only to write
or cross-reference. The canonical bash implementation lives in
`scripts/relay.sh` — source it, then call the `relay_*` functions, OR call
`./scripts/relay.sh <command>` directly:

```bash
source scripts/relay.sh
relay_new   <name> <purpose> [working_dir] [group_id]
relay_send  <name> <prompt>
relay_broadcast <prompt> [all|group:NAME|tag:NAME]
relay_list
relay_status <name>
relay_kill  <name>
relay_cron_create <name> <cron> <session> <prompt>
relay_cron_list
relay_cron_delete <name>
relay_cron_toggle <name> [true|false]
relay_cron_history [name] [lines]
```

Below are the command specs Claude should follow when driving these by hand.

---

## Commands

### 1. NEW — create session

**Trigger:** "tạo session mới", "new session", "spawn session"

**Flow:**
1. Validate name (lowercase kebab-case, unique).
2. `working_dir` = provided or `$PROJECTS_DIR/<name>`.
3. `mkdir -p <dir>/.claude` → write `{"permissionMode":"bypassPermissions"}`
   (R-26: `ccc run` needs this or every action prompts for permission).
4. Create Telegram topic via `createForumTopic` (chat_id=group_id) → topic_id.
5. `tmux new-window -n <name> -c <dir>` → window_id.
6. `tmux send-keys -t <window_id> '<CCC_BIN> run' Enter` (R-18: always `ccc run`).
7. After 2s, `tmux rename-window -t <id> <name>` (R-27: ccc may rename it).
8. Register in ccc config: `{topic_id, path, window_id, group_id}`.
9. Register in registry: `{purpose, tags, created_at, status:"active"}`.
10. Notify the topic.

> **Per-session group_id:** pass a 4th arg / `group_id` field to bind this
> session to a *different* group than the default (multi-user).

### 2. SEND — send command to a session

1. Lookup `window_id` from ccc config.
2. Check window alive (`tmux list-windows`); dead → `auto_restart` handling.
3. `tmux send-keys -t <window_id> '<prompt>' Enter` (escape single quotes — R-10).
4. Update `last_command`.
5. (Optional) notify the topic.

### 3. BROADCAST — send to many sessions

Resolve targets: `all` | `group:<name>` | `tag:<name>`. Cap 10 concurrent
(R-07). Report `<N> sent, <M> failed`.

### 3b. SWITCH FOLDER — move a session to a new working dir

This is a **RECREATE**, not a config update (R-23). Telegram `topic_id` is
preserved — the user keeps chatting in the same topic.

1. Read old `window_id`, `topic_id`, `path` from ccc config.
2. `tmux rename-window -t <old> "<name>-old"` (avoid grep picking the old window).
3. Validate new dir + inject `bypassPermissions` settings (R-26).
4. `tmux new-window -n <name> -c <new_dir>` → new_window_id (verify != old).
5. `ccc run` + sleep 3 + rename window back (R-18/R-27).
6. Update ccc config: `path`, `window_id` (keep `topic_id`).
7. Update registry: `status=active`, `last_command=now`.
8. Kill old window; verify dead.
9. Notify.

### 4. LIST — list sessions

Table: name · status (🟢/🟡/🔴/⚪) · window · topic · purpose · last_command.
Status derived from whether `window_id` exists in `tmux list-windows`.

### 5. STATUS — health check

1. window exists?
2. Claude process in pane (`tmux list-panes` → `ps` → grep claude)?
3. pane content tail for errors.
4. dead + auto_restart → restart; else notify.

### 6. KILL — terminate session

1. Confirm (Telegram buttons — R-01).
2. `C-c` then `/exit`; wait 5s; `tmux kill-window` if alive.
3. Remove from ccc config; registry status = `terminated`.
4. Notify.

### 7. CRON — full CRUD (launchd-backed)

User writes a familiar 5-field **cron** expression; `scripts/cron_to_launchd.py`
converts it to a launchd plist internally.

- **CREATE** `relay_cron_create <name> <cron> <session> <prompt>` → writes
  `~/Library/LaunchAgents/com.vccc.<name>.plist`, adds to `schedules.json`,
  `launchctl load`.
- **READ** `relay_cron_list` — cross-references registry vs `launchctl list` vs
  plist files on disk; detects orphans (R-13).
- **UPDATE** unload → edit registry → regenerate plist → reload (atomic, R-16).
- **DELETE** `launchctl unload` → remove plist → remove registry entry (R-15).
- **TOGGLE** enable/disable (plist kept on disk).
- **HISTORY** `tail` the `.log`/`.err` launchd auto-captures (R-14, no manual tee).

**Common conversions** (local time, NOT UTC — R-24):

| Cron | launchd |
|---|---|
| `7 9 * * 1-5` | StartCalendarInterval (5 dicts: Hour=9,Minute=7,Weekday=1..5) |
| `*/15 * * * *` | StartInterval 900 |
| `13 * * * *` | StartCalendarInterval Minute=13 |
| `0 18 * * 5` | StartCalendarInterval Hour=18,Weekday=5 |

### 9. AUDIT — fleet health sweep

After each CRON CREATE/UPDATE (R-22): bridge script has PATH export (R-19),
functions defined before call sites (R-20), pre-flight dep check (R-21); every
schedule has a loaded plist, an alive session (or auto-create), a clean
last_status; detect orphans. Report ✅/🟡/🔴 counts + fix list.

### 10. MONITOR — watch the whole fleet

For each session: `relay_status`. Compile 🟢/🟡/🔴. Auto-restart dead sessions
with `auto_restart=true` (cap 3/hour — R-09, else notify human). Schedule it
itself: `relay_cron_create fleet-monitor "*/30 * * * *" monitor "Check all"`.

---

## Rules (battle-tested)

| ID | Rule |
|----|------|
| R-00 | Read JSON via `Read` tool; `python3` only for write/cross-ref |
| R-01 | Confirm before kill (Telegram buttons) |
| R-01b | SWITCH FOLDER keeps topic_id (same topic, new dir) |
| R-02 | name = lowercase kebab-case, unique |
| R-03 | every session gets a Telegram topic |
| R-04 | launchd is primary scheduler; CronCreate only for session-only temp |
| R-05 | all agents use label `com.vccc.<name>` |
| R-06 | plists live in `~/Library/LaunchAgents/` |
| R-07 | broadcast ≤ 10 sessions |
| R-08 | monitor interval ≥ 10 min |
| R-09 | auto-restart ≤ 3/hour, then notify human |
| R-10 | escape single quotes in send-keys prompts |
| R-11 | check session alive before send |
| R-12 | registry + schedules + ccc config + plist must stay in sync |
| R-13 | cron_list detects orphans both ways |
| R-14 | launchd auto-captures stdout/stderr (no manual tee) |
| R-15 | cron_delete unloads launchctl before removing plist |
| R-16 | cron_update = unload → edit → reload (atomic) |
| R-17 | schedule name has no dots |
| R-18 | always start Claude via `<CCC_BIN> run` (canonical entry) |
| R-19 | bridge script exports PATH right after `set -euo pipefail` |
| R-20 | bridge functions defined before first call (no hoisting) |
| R-21 | bridge pre-flight checks tmux/python3/ccc |
| R-22 | run AUDIT after each cron create/update |
| R-23 | SWITCH FOLDER is RECREATE (rename old → new window → ccc run → kill old) |
| R-24 | NEVER timezone-convert: cron hour == plist Hour, local time |
| R-25 | default working dir = `$PROJECTS_DIR/<name>` (quote if spaces) |
| R-26 | new dir must have `.claude/settings.json` bypassPermissions before `ccc run` |
| R-27 | rename tmux window back to session name after `ccc run` |

## Error handling

- session not found → list + suggest similar
- tmux window dead → auto_restart or notify
- Telegram API fail → log, continue, retry later
- launchctl load fail → `plutil -lint`, report
- bridge fail → check `.err` (launchd captured it)
- tmux not found in bridge → PATH (R-19), run AUDIT

## Quality tier

TEMPLATED — workflow orchestration. Rules-based, no ambiguous scenarios.

---

*Living skill. Living rules. Update when ccc API changes or new fleet patterns emerge.*
