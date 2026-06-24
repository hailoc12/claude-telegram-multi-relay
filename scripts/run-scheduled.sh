#!/bin/bash
# run-scheduled.sh — bridge between macOS launchd and a Claude session.
#
# Called by: launchd via a com.vccc.<name>. plist ProgramArguments.
# Usage:     run-scheduled.sh <schedule-name>
#
# launchd captures stdout -> StandardOutPath, stderr -> StandardErrorPath
# (declared in the plist), so we do NOT manually tee logs here.
#
# CRITICAL for launchd/cron: those environments ship a MINIMAL PATH, so we must
# set it explicitly or tmux/python3/curl silently go missing (R-19).

set -euo pipefail

export PATH="${BRIDGE_PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"

SCHEDULE_NAME="$1"

# Resolve config (honors config/relay.example.env when copied into place).
CCC_BIN="${CCC_BIN:-ccc}"
ORCH_DIR="${ORCH_DIR:-$HOME/.claude/ccc-orchestrator}"
SCHEDULES_PATH="$ORCH_DIR/schedules.json"
CCC_CONFIG="${CCC_CONFIG:-$HOME/.config/ccc/config.json}"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/9. active}"
_ENV="$ORCH_DIR/relay.env"; [ -f "$_ENV" ] && set -a && . "$_ENV" && set +a

# update_status must be defined BEFORE any call site (bash does not hoist).
update_status() { # <name> <status>
  python3 -c "
import json,datetime
p='$SCHEDULES_PATH'
with open(p) as f: s=json.load(f)
if '$1' in s['schedules']:
    s['schedules']['$1']['last_run']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    s['schedules']['$1']['last_status']='$2'
    json.dump(s,open(p,'w'),indent=2)
"
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing: $SCHEDULE_NAME"

# Pre-flight: fail fast with a clear message instead of a cryptic crash later.
for cmd in tmux python3 "$CCC_BIN"; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "FATAL: '$cmd' not found in PATH=$PATH"; update_status "$SCHEDULE_NAME" "error:missing_$cmd"; exit 1; }
done

# Read this schedule's definition.
SCHEDULE_JSON=$(python3 -c "
import json,sys
try:
    s=json.load(open('$SCHEDULES_PATH'))['schedules'].get('$SCHEDULE_NAME')
    if s is None: print('ERROR:NOT_FOUND'); sys.exit(0)
    if not s.get('enabled',True): print('ERROR:DISABLED'); sys.exit(0)
    print(json.dumps(s))
except Exception as e: print(f'ERROR:{e}')
" 2>/dev/null)

case "$SCHEDULE_JSON" in
  ERROR:*) echo "❌ $SCHEDULE_JSON"; exit 1;;
esac

SESSION_NAME=$(python3 -c "import json,sys;print(json.load(sys.stdin)['session_name'])" <<<"$SCHEDULE_JSON")
PROMPT=$(python3 -c "import json,sys;print(json.load(sys.stdin)['prompt'])" <<<"$SCHEDULE_JSON")
AUTO_CREATE=$(python3 -c "import json,sys;print(json.load(sys.stdin).get('auto_create_session',True))" <<<"$SCHEDULE_JSON")
echo "   session: $SESSION_NAME | prompt: ${PROMPT:0:80}..."

# Is the target session's tmux window alive?
WINDOW_ID=$(python3 -c "
import json
try: print(json.load(open('$CCC_CONFIG')).get('sessions',{}).get('$SESSION_NAME',{}).get('window_id',''))
except Exception: print('')
" 2>/dev/null || echo "")

SESSION_ALIVE=false
[ -n "$WINDOW_ID" ] && tmux list-windows -F '#{window_id}' 2>/dev/null | grep -q "^${WINDOW_ID}$" && SESSION_ALIVE=true

# Auto-create the session if it died (keeps scheduled tasks resilient).
if [ "$SESSION_ALIVE" = "false" ]; then
  if [ "$AUTO_CREATE" = "True" ]; then
    echo "   session not alive — auto-creating..."
    WORKING_DIR=$(python3 -c "
import json
try: print(json.load(open('$CCC_CONFIG')).get('sessions',{}).get('$SESSION_NAME',{}).get('path','$PROJECTS_DIR/$SESSION_NAME'))
except Exception: print('$PROJECTS_DIR/$SESSION_NAME')
" 2>/dev/null || echo "$PROJECTS_DIR/$SESSION_NAME")
    mkdir -p "$WORKING_DIR/.claude"
    echo '{"permissionMode":"bypassPermissions"}' > "$WORKING_DIR/.claude/settings.json"
    tmux new-window -n "$SESSION_NAME" -c "$WORKING_DIR" 2>/dev/null || true
    WINDOW_ID=$(tmux list-windows -F '#{window_id} #{window_name}' | grep " $SESSION_NAME$" | tail -1 | cut -d' ' -f1)
    if [ -n "$WINDOW_ID" ]; then
      tmux send-keys -t "$WINDOW_ID" "$CCC_BIN run" Enter
      sleep 5
      tmux rename-window -t "$WINDOW_ID" "$SESSION_NAME" 2>/dev/null || true
    else
      echo "   failed to create session"; update_status "$SCHEDULE_NAME" "error:failed_create"; exit 1
    fi
  else
    echo "   session dead, auto_create=false"; update_status "$SCHEDULE_NAME" "error:session_dead"; exit 1
  fi
fi

# Deliver the prompt to the live session.
ESCAPED_PROMPT=$(printf '%s' "$PROMPT" | sed "s/'/'\\\\''/g")
tmux send-keys -t "$WINDOW_ID" "$ESCAPED_PROMPT" Enter
echo "   prompt sent."
update_status "$SCHEDULE_NAME" "sent"

# Best-effort Telegram notification into the session's topic.
BOT_TOKEN=$(python3 -c "import json;print(json.load(open('$CCC_CONFIG'))['bot_token'])" 2>/dev/null || echo "")
GROUP_ID=$(python3 -c "
import json
try:
    c=json.load(open('$CCC_CONFIG')); s=c.get('sessions',{}).get('$SESSION_NAME',{})
    print(s.get('group_id') or c.get('group_id',''))
except Exception: print('')
" 2>/dev/null || echo "")
TOPIC_ID=$(python3 -c "import json;print(json.load(open('$CCC_CONFIG')).get('sessions',{}).get('$SESSION_NAME',{}).get('topic_id',''))" 2>/dev/null || echo "")

if [ -n "$BOT_TOKEN$GROUP_ID$TOPIC_ID" ]; then
  python3 -c "
import json,urllib.request
data=json.dumps({'chat_id':$GROUP_ID,'message_thread_id':$TOPIC_ID,'text':'⏰ Scheduled: $SCHEDULE_NAME\n'+'${PROMPT:0:100}','parse_mode':'HTML'}).encode()
try: urllib.request.urlopen(urllib.request.Request('https://api.telegram.org/bot$BOT_TOKEN/sendMessage',data=data,headers={'Content-Type':'application/json'}),timeout=10)
except Exception: pass
" 2>/dev/null || true
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done."
