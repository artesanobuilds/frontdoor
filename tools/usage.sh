#!/bin/zsh
# William token/cost report — parses Claude Code transcript JSONLs for William's project dir,
# sums tokens per model, applies a price table (estimates; update as pricing changes).
# Usage: usage.sh [today|month]  (default: today)

WHOME="${FRONTDOOR_HOME:-$HOME/frontdoor}"
# Claude Code names the transcript dir after the project path with / replaced by -
PROJ="$HOME/.claude/projects/${WHOME//\//-}"
SCOPE="${1:-today}"

if [[ "$SCOPE" == "month" ]]; then
  CUTOFF=$(date '+%Y-%m-01T00:00:00')
  LABEL="this month"
else
  CUTOFF=$(date '+%Y-%m-%dT00:00:00')
  LABEL="today"
fi

if [[ ! -d "$PROJ" ]]; then
  echo "no transcripts yet at $PROJ"
  exit 0
fi

echo "tokens & est. cost ($LABEL):"
# find files modified since cutoff (cheap pre-filter), then filter records by timestamp
find "$PROJ" -name '*.jsonl' -newermt "${CUTOFF/T/ }" 2>/dev/null | while read -r f; do
  cat "$f"
done | /usr/bin/jq -rs --arg cutoff "$CUTOFF" '
  # price per MTok: [input, output, cache_write, cache_read]
  def prices: {
    "claude-opus-5":      {in: 15, out: 75, cw: 18.75, cr: 1.50},
    "claude-opus-4-8":    {in: 15, out: 75, cw: 18.75, cr: 1.50},
    "claude-opus-4-7":    {in: 15, out: 75, cw: 18.75, cr: 1.50},
    "claude-sonnet-5":    {in: 3,  out: 15, cw: 3.75,  cr: 0.30},
    "claude-haiku-4-5-20251001": {in: 1, out: 5, cw: 1.25, cr: 0.10},
    "default":            {in: 3,  out: 15, cw: 3.75,  cr: 0.30}
  };
  [ .[]
    | select(.timestamp? and .timestamp >= $cutoff)
    | .message? | select(. != null)
    | select(.usage? != null)
    | {model: (.model // "unknown"),
       in:  (.usage.input_tokens // 0),
       out: (.usage.output_tokens // 0),
       cw:  (.usage.cache_creation_input_tokens // 0),
       cr:  (.usage.cache_read_input_tokens // 0)} ]
  | group_by(.model)
  | map({model: .[0].model,
         in: (map(.in) | add), out: (map(.out) | add),
         cw: (map(.cw) | add), cr: (map(.cr) | add)})
  | map(. + {cost: ((prices[.model] // prices["default"]) as $p
      | (.in * $p.in + .out * $p.out + .cw * $p.cw + .cr * $p.cr) / 1000000)})
  | (map(.cost) | add // 0) as $total
  | (map("  \(.model): in \(.in) · out \(.out) · cacheW \(.cw) · cacheR \(.cr) → $\(.cost * 100 | round / 100)") | join("\n"))
    + "\n  TOTAL ≈ $\($total * 100 | round / 100)"
' 2>/dev/null
