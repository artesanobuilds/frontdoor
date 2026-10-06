#!/bin/zsh
# William status snapshot — rendered by console.sh in a watch loop.

WHOME="${FRONTDOOR_HOME:-$HOME/frontdoor}"
TMUX_BIN=/opt/homebrew/bin/tmux
TOKEN_FILE="$HOME/.claude/channels/telegram/.env"
cd "$WHOME" || exit 1

echo "═══ WILLIAM STATUS · $(date '+%a %H:%M:%S') ═══"
echo

# --- session / launchd ---
if $TMUX_BIN has-session -t william 2>/dev/null; then
  PANE_CMD=$($TMUX_BIN list-panes -t william -F '#{pane_current_command}' | head -1)
  CREATED=$($TMUX_BIN display-message -p -t william '#{t:session_created}' 2>/dev/null)
  echo "session   : 🟢 tmux 'william' up (pane: $PANE_CMD, since $CREATED)"
else
  echo "session   : 🔴 tmux session DOWN (keeper should revive within ~60s)"
fi
if launchctl list 2>/dev/null | grep -q com.frontdoor.william; then
  echo "launchd   : 🟢 com.frontdoor.william loaded"
else
  echo "launchd   : 🔴 LaunchAgent not loaded"
fi

# --- telegram health ---
if pgrep -qf 'bun.*telegram'; then
  echo "telegram  : 🟢 bun channel server running"
else
  echo "telegram  : 🟡 bun channel server not detected (starts with the session)"
fi
if [[ -f "$TOKEN_FILE" ]]; then
  TOKEN=$(grep -m1 TELEGRAM_BOT_TOKEN "$TOKEN_FILE" | cut -d= -f2)
  PENDING=$(curl -s -m 4 "https://api.telegram.org/bot${TOKEN}/getWebhookInfo" | /usr/bin/jq -r '.result.pending_update_count // "?"' 2>/dev/null)
  echo "undeliverd: ${PENDING:-?} pending telegram updates"
fi

# --- heartbeat ---
LATEST=$(readlink runs/latest.md 2>/dev/null)
if [[ -n "$LATEST" && -f "runs/$LATEST" ]]; then
  AGE_MIN=$(( ($(date +%s) - $(stat -f %m "runs/$LATEST")) / 60 ))
  # threshold follows the active cadence (60m in quiet hours, 30m daytime) + slack
  CAD=$(cat state/keeper-cadence 2>/dev/null || echo 30)
  ICON="🟢"; (( AGE_MIN > CAD * 2 )) && ICON="🔴"
  echo "heartbeat : $ICON last tick ${AGE_MIN}m ago, ${CAD}m cadence ($LATEST)"
else
  echo "heartbeat : 🟡 no run reports yet"
fi

# --- work queues ---
OPEN_REM=$(grep -c 'status: open' reminders.yaml 2>/dev/null); OPEN_REM=${OPEN_REM:-0}
INBOX=$(find inbox -maxdepth 1 -name '*.yaml' 2>/dev/null | wc -l | tr -d ' ')
PENDQ=$(grep -c 'status: pending' state/questions.yaml 2>/dev/null); PENDQ=${PENDQ:-0}
MONTH=$(date '+%Y-%m')
UNPAID=$(/usr/bin/ruby -ryaml -e '
  s = YAML.load_file("state/bills-status.yaml") rescue {"months"=>[]}
  b = YAML.load_file("bills.yaml") rescue {"bills"=>[]}
  m = ARGV[0]
  paid = (s["months"]||[]).select{|x| x["month"]==m && x["status"]=="paid"}.map{|x| x["bill_id"]}
  puts (b["bills"]||[]).reject{|x| paid.include?(x["id"])}.map{|x| x["name"]}.join(", ")
' "$MONTH" 2>/dev/null)
echo "queues    : reminders open: $OPEN_REM · inbox pings: $INBOX · questions pending: $PENDQ"
echo "bills     : unpaid/unchecked $MONTH: ${UNPAID:-none}"
echo

# --- tokens & cost ---
"$WHOME/tools/usage.sh" today
echo
"$WHOME/tools/usage.sh" month | tail -1

# --- system ---
echo
echo "system    : uptime$(uptime | sed 's/.*up/ up/;s/,.*load/ · load/')"

# --- latest run report tail ---
echo
echo "─── latest run report ───"
[[ -n "$LATEST" && -f "runs/$LATEST" ]] && tail -12 "runs/$LATEST"
