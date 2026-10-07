#!/bin/zsh
# mailcheck — the 10-minute agent-mail poll. Run by launchd (com.frontdoor.mailcheck).
#
# Why a separate poller and not a faster heartbeat: a heartbeat tick re-reads William's whole
# context, so 10-minute ticks cost ~3x a 30-minute cadence for the same work. This script costs
# one Gmail search. When it finds protocol mail addressed to William that he has not seen, it
# types a short prompt into the live tmux session — the same way a Telegram DM arrives — and
# William handles it immediately. The heartbeat still sweeps the mailbox as a safety net.
#
# Idempotence: message ids already handed over are kept in state/agent-mail-seen.txt.
set -u
WHOME="${FRONTDOOR_HOME:-$HOME/frontdoor}"
TMUX_BIN=/opt/homebrew/bin/tmux
SESSION=william
SEEN="$WHOME/state/agent-mail-seen.txt"
LOG="$WHOME/state/mailcheck.log"
PY=/usr/bin/python3
cd "$WHOME" || exit 1
log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

# config: who am I, which credential dir
read -r SELF CFG_DIR <<< "$($PY - <<'EOF'
import yaml, os
c = yaml.safe_load(open("config.yaml"))
print(c.get("agents", {}).get("self", "William"), os.path.expanduser(c.get("gmail", {}).get("config_dir", "~/.config/gws-william")))
EOF
)"
export GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$CFG_DIR"

# nothing to inject into if William is down; the keeper will bring him back and the tick sweeps
"$TMUX_BIN" has-session -t "$SESSION" 2>/dev/null || { log "session down, skipping"; exit 0; }

# newest protocol mail addressed to me, last 2 days (the tick covers anything older)
PARAMS=$($PY -c 'import json,sys; print(json.dumps({"userId":"me","q":"subject:\"to %s:\" newer_than:2d" % sys.argv[1],"maxResults":20}))' "$SELF")
RAW=$(gws gmail users messages list --params "$PARAMS" 2>/dev/null | grep -v -i '^Using keyring')
IDS=$(print -r -- "$RAW" | $PY -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if "error" in d:            # auth or API failure: say nothing, never report "no mail"
    sys.exit(2)
print(" ".join(m["id"] for m in d.get("messages", [])))
')
RC=$?
if (( RC == 2 )); then log "gmail query failed — not reporting: $(print -r -- "$RAW" | tr -d "\n" | cut -c1-200)"; exit 0; fi

touch "$SEEN"
NEW=()
for id in ${=IDS}; do grep -q "^$id$" "$SEEN" || NEW+=("$id"); done
(( ${#NEW} == 0 )) && exit 0

# hand over: record first (so a crash mid-send never double-injects), then type the prompt
for id in "${NEW[@]}"; do print -r -- "$id" >> "$SEEN"; done
PROMPT="agent mail: ${#NEW} new message(s) addressed to ${SELF} — Gmail ids ${NEW[*]}. Read guides/agents.md and handle them now."
"$TMUX_BIN" send-keys -t "$SESSION" -l "$PROMPT"
sleep 1
"$TMUX_BIN" send-keys -t "$SESSION" Enter
log "injected ${#NEW} message id(s): ${NEW[*]}"
# keep the seen-list bounded
tail -500 "$SEEN" > "$SEEN.tmp" && mv "$SEEN.tmp" "$SEEN"
