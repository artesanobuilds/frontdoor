#!/bin/zsh
# Write a heartbeat tick report and re-point BOTH latest.md symlinks.
# Report body comes from stdin. Prints the path it wrote.
#
# Why this exists: six separate ticks (through 2026-08-25) reached for `cp ... latest.md`
# and wrote THROUGH the symlink, clobbering a prior report. This script is the only
# sanctioned way to land a report -- it never names latest.md as a write target, only ln -sfn.
# Usage:  /bin/zsh tools/write-report.sh <<'MD'   ...body...   MD
# MUST run under zsh (`/bin/zsh tools/write-report.sh`), NOT bash and NOT with a file
# argument: it resolves its own home via the zsh-only `${0:A:h:h}` expansion, which bash
# leaves as a literal and then fails on. Body on stdin only.
set -eu
HOME_DIR="${0:A:h:h}"
RUNDATE="$(date +%Y-%m-%d)"
RUNSTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
DIR="$HOME_DIR/runs/$RUNDATE"
mkdir -p "$DIR"
TARGET="$DIR/$RUNSTAMP.md"
[ -e "$TARGET" ] && { print -u2 "refusing to overwrite existing $TARGET"; exit 1; }
cat > "$TARGET"
# pointers: ln -sfn ONLY. -n so an existing symlink-to-dir is replaced, not descended into.
ln -sfn "$RUNSTAMP.md" "$DIR/latest.md"
ln -sfn "$RUNDATE/$RUNSTAMP.md" "$HOME_DIR/runs/latest.md"
# verify both are symlinks resolving to the new report
for L in "$DIR/latest.md" "$HOME_DIR/runs/latest.md"; do
  [ -L "$L" ] || { print -u2 "FAIL: $L is not a symlink"; exit 1; }
  [ "$(cd "${L:h}" && print -r -- "${$(readlink "$L"):A}")" = "${TARGET:A}" ] || { print -u2 "FAIL: $L does not resolve to $TARGET"; exit 1; }
done
# Stray-name detector (non-fatal). Format drift happens when a tick hand-rolls the stamp with
# local `date` and drops the Z; those files sort wrong and an `ls | tail -1` read of "latest"
# picks the wrong report. Warn on stdout so the NEXT tick sees it in this script's output.
for F in "$DIR"/*.md(N); do
  [ -L "$F" ] && continue
  [[ "${F:t}" == <->-<->-<->T<->-<->-<->Z.md ]] || print -r -- "WARN: non-canonical report name ${F:t} in runs/$RUNDATE -- reports must be named by tools/write-report.sh (UTC, trailing Z)"
done
# Invariant detector -- runs here because write-report.sh is the one step EVERY tick takes, so
# the WARNs cannot be skipped by a tick that forgets to look. Never fatal.
/bin/zsh "$HOME_DIR/tools/selfcheck.sh" || true
print -r -- "$TARGET"
