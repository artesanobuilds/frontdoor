#!/bin/zsh
# William keeper — ensures the Telegram-connected William session is alive in tmux.
# Run by launchd (com.frontdoor.william, KeepAlive + ThrottleInterval=60 → acts as a 60s watchdog)
# and safe to run by hand. Idempotent: exits fast when the session is healthy.

TMUX_BIN=/opt/homebrew/bin/tmux  # not TMUX: that shadows tmux's own socket var
CLAUDE="$HOME/.local/bin/claude"
WHOME="${FRONTDOOR_HOME:-$HOME/frontdoor}"
LOG="$WHOME/state/keeper.log"
SESSION=william
MODEL=claude-opus-5

# Tick cadence by local hour (mirror config.yaml quiet_hours 22:00-07:00): proactive work is
# held overnight anyway, so tick hourly at night to save tokens. Inbound Telegram DMs are
# real-time regardless — they inject into the session instantly, independent of the loop.
HOUR=$((10#$(date +%H)))
if (( HOUR >= 22 || HOUR < 7 )); then CADENCE=60; else CADENCE=30; fi  # tuned 2026-08-04: 10→30m daytime
CADENCE_FILE="$WHOME/state/keeper-cadence"

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

# keep the log from growing unbounded
[[ -f "$LOG" ]] && [[ $(wc -l < "$LOG") -gt 2000 ]] && tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

# Is $1 a DESCENDANT of $2 (walking the ppid chain, not just a direct child)?
# William's bun poller is often a GRANDchild of the pane pid, so a direct-child test
# (`ppid != WPID`, `pgrep -P WPID`) misreads William's own poller as foreign, kills it,
# and then recycles the session on top of it. That is the recycle storm — diagnosed
# 2026-09-07, confirmed 2026-09-09 (10 session starts, ages 181s..19659s), and it is why
# William was unreachable for ~80h. Fixed 2026-09-10.
is_descendant() {
  local pid="$1" root="$2" hops=0
  [[ -z "$pid" || -z "$root" ]] && return 1
  while [[ -n "$pid" && "$pid" != "0" && "$pid" != "1" ]] && (( hops < 24 )); do
    [[ "$pid" == "$root" ]] && return 0
    pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
    hops=$(( hops + 1 ))
  done
  return 1
}

# --- Telegram poller hygiene -----------------------------------------------
# Cursor imports Claude plugin MCP configs and spawns its OWN telegram server, which
# kills William's poller (the server kills conflicting token holders on start).
# Any bun telegram poller NOT parented by William's claude is foreign → kill it.
WPID=""
if "$TMUX_BIN" has-session -t "$SESSION" 2>/dev/null; then
  PANE_PID=$("$TMUX_BIN" list-panes -t "$SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)
  WPID="$PANE_PID"
fi
for BPID in $(pgrep -f 'bun run --cwd .*telegram' 2>/dev/null); do
  BPPID=$(ps -p "$BPID" -o ppid= 2>/dev/null | tr -d ' ')
  if [[ -z "$WPID" ]] || ! is_descendant "$BPID" "$WPID"; then
    log "killing foreign telegram poller pid=$BPID (parent=$BPPID, william=$WPID)"
    kill "$BPID" 2>/dev/null
  fi
done

if "$TMUX_BIN" has-session -t "$SESSION" 2>/dev/null; then
  # session exists — claude is dead only if the pane fell back to a bare shell or is gone.
  # NOTE: claude's pane_current_command reports as its version number (e.g. "2.1.220"),
  # so we detect death by shell-fallback, not by matching "claude".
  PANE_CMD=$("$TMUX_BIN" list-panes -t "$SESSION" -F '#{pane_current_command}' 2>/dev/null | head -1)
  if [[ -n "$PANE_CMD" && ! "$PANE_CMD" =~ ^(zsh|bash|sh|-zsh|-bash)$ ]]; then
    # claude alive — but is its telegram channel? A healthy channel session has a bun
    # child. Give new sessions a 3-min grace period before judging.
    SESSION_AGE=$(( $(date +%s) - $("$TMUX_BIN" display-message -p -t "$SESSION" '#{session_created}') ))
    CHANNEL_OK=0
    for BPID in $(pgrep -f 'bun run --cwd .*telegram' 2>/dev/null); do
      is_descendant "$BPID" "$WPID" && CHANNEL_OK=1 && break
    done
    if (( SESSION_AGE < 180 )) || (( CHANNEL_OK )); then
      # healthy — but recycle at day/night boundaries so the loop cadence matches the hour
      if [[ -f "$CADENCE_FILE" && "$(cat "$CADENCE_FILE")" != "$CADENCE" ]]; then
        log "cadence boundary ($(cat "$CADENCE_FILE")m → ${CADENCE}m) — recycling session"
        "$TMUX_BIN" kill-session -t "$SESSION"
      else
        exit 0
      fi
    else
      log "claude alive but telegram channel dead (no bun child, age ${SESSION_AGE}s) — recycling session"
    fi
  else
    log "session exists but claude died (pane: ${PANE_CMD:-none}) — killing stale session"
  fi
  "$TMUX_BIN" kill-session -t "$SESSION"
fi

# Never start the tmux SERVER from here. The server must be owned by launchd
# (com.frontdoor.tmux-server, foreground tmux -D) or it dies unrecovered with its
# starter — a keeper-started server daemonizes to PPID 1 but launchd is not
# supervising it. If no server is up, kick the agent and wait; only proceed
# serverless (new-session would start a keeper-owned server) as a loud last resort.
if ! "$TMUX_BIN" -N ls >/dev/null 2>&1; then
  launchctl kickstart "gui/$(id -u)/com.frontdoor.tmux-server" 2>/dev/null
  for i in {1..40}; do "$TMUX_BIN" -N ls >/dev/null 2>&1 && break; sleep 0.5; done
  if ! "$TMUX_BIN" -N ls >/dev/null 2>&1; then
    log "WARNING: launchd tmux server absent after 20s — session will start a keeper-owned server (durability off)"
  fi
fi

# 2026-10-05: Claude Code keeps a SHARED cache of MCP servers it believes need auth
# (~/.claude/mcp-needs-auth-cache.json). When any OTHER session in this directory (a bb thread,
# a `claude --resume`) loads the telegram plugin, the WILLIAM_CHANNEL guard makes it exit, and
# Claude Code records plugin:telegram:telegram there. Every session started afterwards -- William
# included -- then silently skips the channel: no bun child, "did not come up within 60s", recycle
# loop (10:57-11:06 today, three recycles). Drop the entry before each start.
NAC="$HOME/.claude/mcp-needs-auth-cache.json"
if [[ -f "$NAC" ]] && grep -q 'plugin:telegram:telegram' "$NAC"; then
  /usr/bin/python3 - "$NAC" <<'PY' && log "cleared stale plugin:telegram:telegram entry from mcp-needs-auth-cache.json"
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.pop("plugin:telegram:telegram", None)
json.dump(d, open(p, "w"))
PY
fi

log "starting William session (model $MODEL, tick ${CADENCE}m)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin"
# Marks this session as the ONE allowed Telegram poller — the plugin's server.ts refuses to run
# without it, so other Claude Code sessions can't steal the channel (see project memory).
# effort medium: William's work is judgment about a known life, not hard reasoning — high effort
# added minutes of latency to phone replies for no gain (2026-08-04).
# 2026-08-20: pass WILLIAM_CHANNEL through tmux EXPLICITLY. A new session inherits the tmux
# SERVER's environment, not the keeper's shell — and after the 08-20 reboot another startup
# script created the tmux server 2s before the keeper, so the exported var never reached the
# pane, the plugin guard exited 0, and the channel never came up (recycle storm 07:51-08:0x).
# 2026-10-05: -e ONLY, never `setenv -g`. The global setenv leaked the guard into every pane
# created later on the shared server (the user's ws* tabs, and bb launched from one), so other
# Claude sessions started their own pollers and stole the token. Those were the "foreign"
# pollers in keeper.log (08:28 parent was a bb thread's claude): the real recycle-storm cause.
# 2026-10-07: a per-start NONCE instead of "1". Any other process that inherited an older value
# (a bb thread, a `claude --resume` from a dirty tab) fails the plugin guard, which compares the
# env value to state/channel-nonce. Only the session started right here matches.
NONCE=$(head -c 16 /dev/urandom | xxd -p)
NONCE_FILE="$WHOME/state/channel-nonce"
print -r -- "$NONCE" > "$NONCE_FILE"; chmod 600 "$NONCE_FILE"
"$TMUX_BIN" new-session -d -s "$SESSION" -c "$WHOME" -e "WILLIAM_CHANNEL=$NONCE" -e "WILLIAM_NONCE_FILE=$NONCE_FILE" \
  "$CLAUDE --model $MODEL --effort medium --channels plugin:telegram@claude-plugins-official"

# wait for the UI to be ready (prompt visible)
for i in {1..30}; do
  "$TMUX_BIN" capture-pane -t "$SESSION" -p 2>/dev/null | grep -q '❯' && break
  sleep 2
done
# CRITICAL (2026-08-04): wait for the Telegram channel server to finish connecting BEFORE
# injecting the loop. Sending it too early preempts channel init — the bun poller never starts,
# the session is deaf to Telegram, and the health check below recycles it in a loop.
NEWPID=$("$TMUX_BIN" list-panes -t "$SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)
for i in {1..30}; do
  pgrep -P "$NEWPID" -f 'bun run --cwd .*telegram' >/dev/null 2>&1 && break
  sleep 2
done
if pgrep -P "$NEWPID" -f 'bun run --cwd .*telegram' >/dev/null 2>&1; then
  log "telegram channel up"
else
  log "WARNING: telegram channel did not come up within 60s"
fi
sleep 3   # let the input box settle
"$TMUX_BIN" send-keys -t "$SESSION" "/loop ${CADENCE}m @william heartbeat"
sleep 2
"$TMUX_BIN" send-keys -t "$SESSION" Enter
sleep 5
# verify the command actually SUBMITTED. Text sitting on the "❯ " input line means Enter was
# swallowed by the UI (seen 2026-08-03) — the loop never starts. Re-send Enter, then retype.
if "$TMUX_BIN" capture-pane -t "$SESSION" -p | grep -qE '^❯.*(/loop|heartbeat)'; then
  log "heartbeat command still in input box — re-sending Enter"
  "$TMUX_BIN" send-keys -t "$SESSION" Enter
  sleep 5
fi
if ! "$TMUX_BIN" capture-pane -t "$SESSION" -p | grep -q 'heartbeat'; then
  log "heartbeat send not visible — retyping"
  "$TMUX_BIN" send-keys -t "$SESSION" "/loop ${CADENCE}m @william heartbeat"
  sleep 2
  "$TMUX_BIN" send-keys -t "$SESSION" Enter
fi
echo "$CADENCE" > "$CADENCE_FILE"
log "session started, heartbeat loop sent (${CADENCE}m)"
