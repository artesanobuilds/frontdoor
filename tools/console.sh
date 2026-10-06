#!/bin/zsh
# William observability console — opens a tmux window with:
#   left pane : read-only view of the live William session
#   right pane: status dashboard (tools/status.sh refreshed every 30s)
# Detach with Ctrl-b d. The left pane mirrors the real session — avoid typing in it.

TMUX_BIN=/opt/homebrew/bin/tmux
WHOME="${FRONTDOOR_HOME:-$HOME/frontdoor}"

if ! $TMUX_BIN has-session -t william 2>/dev/null; then
  echo "William session is down — starting it via keeper.sh first…"
  "$WHOME/tools/keeper.sh"
  sleep 2
fi

# rebuild the console session fresh each time
$TMUX_BIN kill-session -t william-console 2>/dev/null
$TMUX_BIN new-session -d -s william-console -c "$WHOME" \
  "while true; do clear; $WHOME/tools/status.sh; sleep 30; done"
# left pane: read-only mirror of the live session (linked window)
$TMUX_BIN split-window -h -b -t william-console -c "$WHOME" \
  "$TMUX_BIN attach-session -t william -r"
$TMUX_BIN select-pane -t william-console -R
exec $TMUX_BIN attach-session -t william-console
