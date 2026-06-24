#!/bin/bash
# relay.sh — core library for claude-telegram-multi-relay
#
# Multi-session, multi-topic, multi-user orchestration layer on top of the
# `ccc` (Claude Code Companion) relay engine: https://github.com/kidandcat/ccc
#
# This file is NOT a standalone program — it is a sourceable library.
#   source "$(dirname "$0")/relay.sh"
# Then call: relay_new, relay_send, relay_broadcast, relay_list,
#            relay_status, relay_kill, relay_cron_* .
#
# All paths are configurable via env vars or config/relay.example.env.
# Nothing in this file is hardcoded to a specific machine.

set -uo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Config resolution
# ─────────────────────────────────────────────────────────────────────────────

# Default base dir for new session working folders.
_DEFAULT_PROJECTS_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/9. active"

# Load optional env file if present (does not override already-set vars).
_RELAY_ENV="${ORCH_DIR:-$HOME/.claude/ccc-orchestrator}/relay.env"
[ -f "$_RELAY_ENV" ] && set -a && . "$_RELAY_ENV" && set +a

CCC_BIN="${CCC_BIN:-ccc}"
ORCH_DIR="${ORCH_DIR:-$HOME/.claude/ccc-orchestrator}"
CCC_CONFIG="${CCC_CONFIG:-$HOME/.config/ccc/config.json}"
PROJECTS_DIR="${PROJECTS_DIR:-$_DEFAULT_PROJECTS_DIR}"

REGISTRY_PATH="$ORCH_DIR/registry.json"
SCHEDULES_PATH="$ORCH_DIR/schedules.json"
LOG_DIR="$ORCH_DIR/logs"
BRIDGE_SCRIPT="$ORCH_DIR/run-scheduled.sh"
PLIST_DIR="$HOME/Library/LaunchAgents"

# ─────────────────────────────────────────────────────────────────────────────
# Preconditions
# ─────────────────────────────────────────────────────────────────────────────

relay_init() {
  mkdir -p "$ORCH_DIR" "$LOG_DIR"
  [ -f "$REGISTRY_PATH" ] || echo '{"sessions":{},"groups":{}}' > "$REGISTRY_PATH"
  [ -f "$SCHEDULES_PATH" ] || echo '{"schedules":{}}' > "$SCHEDULES_PATH"
}

# Read a JSON value from ccc config via python (single source of truth for tokens).
_ccc_get() { # <python-expression-against-config-object-named-c>
  python3 -c "
import json,sys
try:
    with open('$CCC_CONFIG') as f: c=json.load(f)
    print($1)
except Exception as e:
    print('', file=sys.stderr); sys.exit(1)
" 2>/dev/null
}

_cfg_json() { # <session-name>  -> prints session object json or {}
  python3 -c "
import json
try:
    with open('$CCC_CONFIG') as f: c=json.load(f)
    print(json.dumps(c.get('sessions',{}).get('$1',{})))
except Exception: print('{}')
"
}

_bot_token() { _ccc_get "c.get('bot_token','')"; }
_default_group() { _ccc_get "c.get('group_id','')"; }

# Per-session group with top-level fallback (multi-group / multi-user support).
_session_group() { # <name>
  python3 -c "
import json
try:
    with open('$CCC_CONFIG') as f: c=json.load(f)
    s=c.get('sessions',{}).get('$1',{})
    g=s.get('group_id') or c.get('group_id','')
    print(g)
except Exception: print('')
"
}

_session_topic() { # <name>
  python3 -c "
import json
try:
    with open('$CCC_CONFIG') as f: c=json.load(f)
    print(c.get('sessions',{}).get('$1',{}).get('topic_id',''))
except Exception: print('')
"
}

get_window_id() { # <name>
  python3 -c "
import json
try:
    with open('$CCC_CONFIG') as f: c=json.load(f)
    print(c.get('sessions',{}).get('$1',{}).get('window_id',''))
except Exception: print('')
"
}

# ─────────────────────────────────────────────────────────────────────────────
# Telegram helpers
# ─────────────────────────────────────────────────────────────────────────────

# send_to_topic <session-name> <message>
send_to_topic() {
  local name="$1" message="$2"
  local token group topic
  token="$(_bot_token)"; group="$(_session_group "$name")"; topic="$(_session_topic "$name")"
  [ -z "$token$group$topic" ] && { echo "⚠️  Telegram routing incomplete for '$name'"; return 1; }
  python3 -c "
import json,urllib.request
data=json.dumps({'chat_id':$group,'message_thread_id':$topic,'text':'''$message''','parse_mode':'HTML'}).encode()
req=urllib.request.Request('https://api.telegram.org/bot$token/sendMessage',data=data,headers={'Content-Type':'application/json'})
urllib.request.urlopen(req,timeout=10)
" 2>/dev/null || echo "⚠️  Telegram send failed for '$name'"
}

_create_topic() { # <group-id> <topic-name>  -> prints topic_id
  local group="$1" tname="$2" token
  token="$(_bot_token)"
  python3 -c "
import json,urllib.request
data=json.dumps({'chat_id':$group,'name':'''$tname'''}).encode()
req=urllib.request.Request('https://api.telegram.org/bot$token/createForumTopic',data=data,headers={'Content-Type':'application/json'})
print(json.load(urllib.request.urlopen(req,timeout=10))['result']['message_thread_id'])
"
}

# ─────────────────────────────────────────────────────────────────────────────
# Registry helpers
# ─────────────────────────────────────────────────────────────────────────────

register_session() { # <name> <purpose> [tags]
  local name="$1" purpose="$2" tags="${3:-}"
  python3 -c "
import json,datetime
p='$REGISTRY_PATH'
with open(p) as f: r=json.load(f)
r['sessions']['$name']={
  'purpose':'''$purpose''',
  'tags':[t.strip() for t in '$tags'.split(',') if t.strip()],
  'created_at':datetime.datetime.utcnow().isoformat()+'Z',
  'auto_restart':False,'max_idle_minutes':30,
  'last_command':datetime.datetime.utcnow().isoformat()+'Z','status':'active'}
with open(p,'w') as f: json.dump(r,f,indent=2,ensure_ascii=False)
"
}

update_last_command() { # <name>
  python3 -c "
import json,datetime
p='$REGISTRY_PATH'
with open(p) as f: r=json.load(f)
if '$name' in r['sessions']:
    r['sessions']['$name']['last_command']=datetime.datetime.utcnow().isoformat()+'Z'
with open(p,'w') as f: json.dump(r,f,indent=2,ensure_ascii=False)
"
}

list_active_sessions() {
  python3 -c "
import json
with open('$REGISTRY_PATH') as f: r=json.load(f)
for n,m in r['sessions'].items():
    if m.get('status')!='terminated': print(n)
"
}

# ─────────────────────────────────────────────────────────────────────────────
# Session lifecycle
# ─────────────────────────────────────────────────────────────────────────────

# relay_new <name> <purpose> [working_dir] [group_id]
relay_new() {
  local name="$1" purpose="$2"
  local working_dir="${3:-$PROJECTS_DIR/$name}"
  local group="${4:-$(_default_group)}"
  relay_init

  # Validate kebab-case + uniqueness
  case "$name" in
    *[!a-z0-9-]*|[A-Z]*) echo "❌ name must be lowercase kebab-case: $name"; return 1;;
  esac
  [ -n "$(get_window_id "$name")" ] && { echo "❌ session '$name' already exists"; return 1; }
  [ -z "$group" ] && { echo "❌ no group_id (run 'ccc setgroup')"; return 1; }

  # 1. Working dir + permission bypass so ccc/claude never blocks on prompts
  mkdir -p "$working_dir/.claude"
  echo '{"permissionMode":"bypassPermissions"}' > "$working_dir/.claude/settings.json"

  # 2. Telegram forum topic
  local topic_id; topic_id="$(_create_topic "$group" "$name")"
  [ -z "$topic_id" ] && { echo "❌ failed to create Telegram topic (enable Topics in group)"; return 1; }

  # 3. tmux window + start Claude via ccc
  tmux new-window -n "$name" -c "$working_dir"
  local window_id; window_id="$(tmux list-windows -F '#{window_id} #{window_name}' | grep " $name$" | tail -1 | cut -d' ' -f1)"
  tmux send-keys -t "$window_id" "$CCC_BIN run" Enter
  sleep 2
  tmux rename-window -t "$window_id" "$name" 2>/dev/null || true

  # 4. Register in ccc config (the relay engine's source of truth)
  python3 -c "
import json
p='$CCC_CONFIG'
with open(p) as f: c=json.load(f)
c.setdefault('sessions',{})['$name']={'topic_id':$topic_id,'path':'''$working_dir''','window_id':'$window_id','group_id':$group}
with open(p,'w') as f: json.dump(c,f,indent=2)
"

  # 5. Registry metadata
  register_session "$name" "$purpose"

  # 6. Notify
  send_to_topic "$name" "✅ Session <b>$name</b> ready
Purpose: $purpose
Dir: $working_dir
Window: $window_id"
  echo "✅ created '$name' (topic $topic_id, window $window_id)"
}

# relay_send <name> <prompt>
relay_send() {
  local name="$1" prompt="$2"
  local window_id; window_id="$(get_window_id "$name")"
  [ -z "$window_id" ] && { echo "❌ '$name' not found"; return 1; }
  if ! tmux list-windows -F '#{window_id}' 2>/dev/null | grep -q "^${window_id}$"; then
    echo "⚠️  window $window_id dead"; _handle_dead "$name"; return $?
  fi
  tmux send-keys -t "$window_id" "$prompt" Enter
  update_last_command "$name"
  echo "✅ sent to '$name': ${prompt:0:80}"
}

# relay_broadcast <prompt> [all|group:NAME|tag:NAME]
relay_broadcast() {
  local prompt="$1" target="${2:-all}" sessions="" success=0 failed=0
  case "$target" in
    all)        sessions="$(list_active_sessions)";;
    group:*)    sessions="$(python3 -c "import json;r=json.load(open('$REGISTRY_PATH'));[print(n) for n in r.get('groups',{}).get('${target#group:}',[])]")";;
    tag:*)      sessions="$(python3 -c "import json;r=json.load(open('$REGISTRY_PATH'));[print(n) for n,m in r['sessions'].items() if '${target#tag:}' in m.get('tags',[])]")";;
    *)          echo "❌ target must be all|group:X|tag:X"; return 1;;
  esac
  [ -z "$sessions" ] && { echo "ℹ️  no matching sessions"; return 0; }
  local count; count=$(echo "$sessions" | grep -c .)
  [ "$count" -gt 10 ] && { echo "❌ broadcast limit is 10 (got $count)"; return 1; }
  for n in $sessions; do
    relay_send "$n" "$prompt" >/dev/null && ((success++)) || ((failed++))
  done
  echo "📊 broadcast: $success sent, $failed failed"
}

# relay_list
relay_list() {
  python3 -c "
import json,subprocess
reg=json.load(open('$REGISTRY_PATH'))
try: ccc=json.load(open('$CCC_CONFIG'))
except Exception: ccc={}
r= subprocess.run(['tmux','list-windows','-F','#{window_id}'],capture_output=True,text=True)
active=set(l.split()[0] for l in r.stdout.strip().split(chr(10)) if l)
print(f'📋 Sessions ({len(reg[\"sessions\"])} registered)\n')
for n,m in reg['sessions'].items():
    s=ccc.get('sessions',{}).get(n,{})
    w=s.get('window_id','?'); t=s.get('topic_id','?')
    st='🟢 active' if w in active else ('⚪ untracked' if w=='?' else '🔴 dead')
    print(f'{n:25s} {st:12s} win:{w:5s} topic:{t}')
    print(f'  {m.get(\"purpose\",\"-\")}  • last: {m.get(\"last_command\",\"never\")[:19]}')
"
}

# relay_status <name>
relay_status() {
  local name="$1" window_id; window_id="$(get_window_id "$name")"
  [ -z "$window_id" ] && { echo "🔴 NOT REGISTERED"; return 2; }
  tmux list-windows -F '#{window_id}' 2>/dev/null | grep -q "^${window_id}$" || { echo "🔴 DEAD — window $window_id gone"; return 1; }
  local pid; pid="$(tmux list-panes -t "$window_id" -F '#{pane_pid}' | head -1)"
  ps -p "$pid" -o command= 2>/dev/null | grep -q claude && { echo "🟢 ACTIVE (pid $pid)"; return 0; }
  echo "🟡 IDLE — claude not detected"; return 4
}

# relay_kill <name>
relay_kill() {
  local name="$1" window_id; window_id="$(get_window_id "$name")"
  [ -z "$window_id" ] && { echo "❌ '$name' not found"; return 1; }
  tmux send-keys -t "$window_id" C-c 2>/dev/null; tmux send-keys -t "$window_id" '/exit' Enter 2>/dev/null
  sleep 3; tmux kill-window -t "$window_id" 2>/dev/null || true
  python3 -c "
import json
p='$CCC_CONFIG'
with open(p) as f: c=json.load(f)
c.get('sessions',{}).pop('$name',None)
with open(p,'w') as f: json.dump(c,f,indent=2)
"
  python3 -c "
import json,datetime
p='$REGISTRY_PATH'
with open(p) as f: r=json.load(f)
if '$name' in r['sessions']: r['sessions']['$name']['status']='terminated'
with open(p,'w') as f: json.dump(r,f,indent=2)
"
  echo "🔴 '$name' terminated"
}

_handle_dead() {
  local name="$1"
  local ar; ar="$(python3 -c "import json;r=json.load(open('$REGISTRY_PATH'));print(r['sessions'].get('$name',{}).get('auto_restart',False))")"
  if [ "$ar" = "True" ]; then
    echo "🔄 auto-restarting '$name'..."
    local path; path="$(python3 -c "import json;c=json.load(open('$CCC_CONFIG'));print(c.get('sessions',{}).get('$name',{}).get('path',''))")"
    local group; group="$(_session_group "$name")"
    relay_new "$name" "auto-restarted" "$path" "$group"
  else
    echo "🔴 '$name' dead (auto_restart=false)"
    python3 -c "import json;p='$REGISTRY_PATH';r=json.load(open(p));r['sessions']['$name']['status']='dead';json.dump(r,open(p,'w'),indent=2)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Cron CRUD (launchd-backed; see cron_to_launchd.py + run-scheduled.sh)
# ─────────────────────────────────────────────────────────────────────────────

relay_cron_exists() {
  python3 -c "import json;print('yes' if '$1' in json.load(open('$SCHEDULES_PATH')).get('schedules',{}) else 'no')" | grep -q yes
}

# relay_cron_create <name> <cron> <session> <prompt>
relay_cron_create() {
  local name="$1" cron="$2" session="$3" prompt="$4"
  local here; here="$(cd "$(dirname "$0")" && pwd)"
  relay_init
  [ -f "$BRIDGE_SCRIPT" ] || cp "$here/run-scheduled.sh" "$BRIDGE_SCRIPT" 2>/dev/null || true
  echo "$cron" | grep -qE '^[0-9*/,-]+ +[0-9*/,-]+ +[0-9*/,-]+ +[0-9*/,-]+ +[0-9*/,-]+$' \
    || { echo "❌ invalid cron (need 5 fields: M H DoM Mon DoW)"; return 1; }
  relay_cron_exists "$name" && { echo "❌ '$name' exists; use cron_update"; return 1; }

  local label="com.vccc.$name" plist="$PLIST_DIR/com.vccc.$name.plist"
  local log="$LOG_DIR/$name.log" err="$LOG_DIR/$name.err"
  local plist_xml; plist_xml="$(python3 "$here/cron_to_launchd.py" "$label" "$BRIDGE_SCRIPT" "$name" "$cron" "$log" "$err")"
  [ -z "$plist_xml" ] && { echo "❌ cron→plist conversion failed"; return 1; }
  echo "$plist_xml" > "$plist"

  python3 -c "
import json,datetime
p='$SCHEDULES_PATH'
with open(p) as f: s=json.load(f)
s['schedules']['$name']={'cron':'''$cron''','session_name':'''$session''','prompt':'''$prompt''',
  'plist_path':'$plist','created_at':datetime.datetime.utcnow().isoformat()+'Z',
  'updated_at':datetime.datetime.utcnow().isoformat()+'Z','last_run':None,'last_status':None,
  'last_log':None,'enabled':True,'auto_create_session':True}
json.dump(s,open(p,'w'),indent=2,ensure_ascii=False)
"
  launchctl load "$plist" 2>/dev/null
  launchctl list | grep -q "$label" && echo "✅ $label loaded ($cron)" || echo "⚠️  plist written; verify: launchctl list | grep $label"
}

relay_cron_list() {
  python3 -c "
import json,subprocess,glob,os
s=json.load(open('$SCHEDULES_PATH'))
loaded=set()
for line in subprocess.run(['launchctl','list'],capture_output=True,text=True).stdout.split(chr(10)):
    if 'com.vccc.' in line and line.split(): loaded.add(line.split()[-1])
disk=set(os.path.basename(f).replace('com.vccc.','').replace('.plist','') for f in glob.glob('$PLIST_DIR/com.vccc.*.plist'))
print('⏰ Scheduled tasks\n')
for n,m in s.get('schedules',{}).items():
    lab='com.vccc.'+n
    en='✅' if m.get('enabled') else '⏸️'
    ld='✅' if lab in loaded else '❌'
    dk='✅' if n in disk else '❌'
    print(f'{n:24s} {en} loaded:{ld} disk:{dk}  {m.get(\"cron\",\"?\"):18s} → {m.get(\"session_name\",\"?\")}')
"
}

relay_cron_delete() {
  local name="$1" plist="$PLIST_DIR/com.vccc.$name.plist"
  relay_cron_exists "$name" || { echo "❌ '$name' not found"; return 1; }
  launchctl unload "$plist" 2>/dev/null || true
  rm -f "$plist"
  python3 -c "import json;p='$SCHEDULES_PATH';s=json.load(open(p));del s['schedules']['$name'];json.dump(s,open(p,'w'),indent=2)"
  echo "✅ deleted com.vccc.$name"
}

relay_cron_toggle() {
  local name="$1" enable="$2" plist="$PLIST_DIR/com.vccc.$name.plist"
  relay_cron_exists "$name" || { echo "❌ '$name' not found"; return 1; }
  if [ "$enable" = "false" ]; then
    launchctl unload "$plist" 2>/dev/null || true
    python3 -c "import json;p='$SCHEDULES_PATH';s=json.load(open(p));s['schedules']['$name']['enabled']=False;json.dump(s,open(p,'w'),indent=2)"
    echo "⏸️  disabled com.vccc.$name"
  else
    launchctl load "$plist" 2>/dev/null
    python3 -c "import json;p='$SCHEDULES_PATH';s=json.load(open(p));s['schedules']['$name']['enabled']=True;json.dump(s,open(p,'w'),indent=2)"
    echo "▶️ enabled com.vccc.$name"
  fi
}

relay_cron_history() {
  local name="$1" lines="${2:-20}"
  if [ -n "$name" ]; then
    echo "── $name.log ──"; tail -"$lines" "$LOG_DIR/$name.log" 2>/dev/null
    echo "── $name.err ──"; tail -"$lines" "$LOG_DIR/$name.err" 2>/dev/null
  else
    for f in "$LOG_DIR"/*.log; do [ -f "$f" ] && { echo "── $(basename "$f") ──"; tail -3 "$f"; }; done
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CLI dispatcher (when invoked directly: relay.sh <command> ...)
# ─────────────────────────────────────────────────────────────────────────────

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  cmd="${1:-help}"; shift || true
  case "$cmd" in
    new)      relay_new "$@";;
    send)     relay_send "$@";;
    broadcast)relay_broadcast "$@";;
    list|ls)  relay_list "$@";;
    status)   relay_status "$@";;
    kill)     relay_kill "$@";;
    cron-create)  relay_cron_create "$@";;
    cron-list)    relay_cron_list "$@";;
    cron-delete)  relay_cron_delete "$@";;
    cron-toggle)  relay_cron_toggle "$@";;
    cron-history) relay_cron_history "$@";;
    help|*)   echo "Usage: relay.sh {new|send|broadcast|list|status|kill|cron-create|cron-list|cron-delete|cron-toggle|cron-history} ...";;
  esac
fi
