#!/bin/zsh
# Invariant detector. WARN-only, never fatal, no writes.
#
# Why this exists (2026-09-30 calibration): the day's seven self-corrections were mostly cases
# where a RECORDED RULE and the REAL BEHAVIOR had diverged and nothing noticed -- a verification
# grep that rotted as the data shape drifted (278 vs 279), a log-length rule practice had
# abandoned for two months, a 0-byte report whose "no damage" claim was never checked against the
# filesystem, a calibration ritual with three unrecorded days. Prose rules did not catch any of
# them, because prose depends on compliance. These checks do not.
#
# Invoked automatically by tools/write-report.sh -- the one step EVERY tick must take -- so the
# output lands in the tick's own stdout and the next tick sees it. Run standalone any time:
#   /bin/zsh tools/selfcheck.sh
set -u
H="${0:A:h:h}"
PY=/usr/bin/python3            # homebrew python3 has no yaml module
D="$(date +%Y-%m-%d)"
Y="$(date -v-1d +%Y-%m-%d)"

# A. zero-byte reports -- the write-report.sh:20 `cat > "$TARGET"` bug lands one of these and
#    repoints latest.md at it. Fix is tracked; the SILENCE is not.
for F in "$H/runs/$D"/*.md(N); do
  [ -L "$F" ] && continue
  [ -s "$F" ] || print -r -- "WARN: 0-byte report runs/$D/${F:t} -- a tick called write-report.sh with an empty body (write-report.sh:20)"
done

# B. both latest.md pointers are symlinks, never regular files written THROUGH the link
for L in "$H/runs/latest.md" "$H/runs/$D/latest.md"; do
  [ -e "$L" ] || continue
  [ -L "$L" ] || print -r -- "WARN: ${L#$H/} is a REGULAR FILE, not a symlink -- something wrote through the pointer"
done

# C. conversation-log byte bar (BYTES, not lines -- the 146KB blowup of 2026-08-11 passed a
#    line-count bar the whole way up). Warn early at 20KB so the prune is scheduled, not discovered.
LOG="$H/state/conversation-log.md"
if [ -f "$LOG" ]; then
  B=$(wc -c < "$LOG" | tr -d ' ')
  [ "$B" -ge 24576 ] && print -r -- "WARN: conversation-log.md ${B}B -- AT/OVER the 24KB prune bar, prune now"
  [ "$B" -ge 20480 ] && [ "$B" -lt 24576 ] && print -r -- "WARN: conversation-log.md ${B}B -- approaching the 24KB prune bar"
fi

# D+F. every state YAML parses, and the entry count keyed to LIST STRUCTURE agrees with the
#      parser. A grep keyed to the first field name rots the moment one tick writes a
#      differently-ordered entry; a disagreement here is that rot, caught the same day.
$PY - "$H" <<'PYEOF'
import sys, os, yaml, re
h = sys.argv[1]
# file -> inner key holding the list
files = {"state/notifications.yaml":"sent", "state/open-loops.yaml":"loops",
         "state/reminders.yaml":"reminders", "reminders.yaml":"reminders",
         "bills.yaml":"bills", "state/bills-status.yaml":"months",
         "state/feedback.yaml":"feedback"}   # added 2026-09-30: grep '^- date:' says 17, parser says 28
for rel, key in files.items():
    p = os.path.join(h, rel)
    if not os.path.exists(p):
        continue
    try:
        d = yaml.safe_load(open(p))
    except Exception as e:
        print(f"WARN: {rel} FAILS TO PARSE -- {type(e).__name__}: {str(e)[:120]}")
        continue
    if not isinstance(d, dict) or key not in d:
        print(f"WARN: {rel} has no top-level '{key}:' key (keys={list(d)[:4] if isinstance(d,dict) else type(d).__name__}) -- the shape changed")
        continue
    items = d[key]
    if not isinstance(items, list):
        continue
    n_parser = len(items)
    n_struct = sum(1 for L in open(p) if re.match(r"^- ", L))
    if n_parser != n_struct:
        print(f"WARN: {rel} count mismatch -- parser {n_parser} vs '^- ' structure {n_struct}; a counting rule has rotted")
PYEOF

# D2. DELIVERED-BUT-STILL-OPEN one-shot reminders (added 2026-10-02 calibration).
#     Five non-recurring reminders sat `status: open` with `notified_at` already set -- the oldest
#     since 2026-08-14. Nothing noticed for seven weeks, and each one inflated the "open reminders"
#     count on every single tick. A delivered one-shot with no `recur` is DONE; leaving it open is
#     a state bug, not a pending obligation. This is local-only, so it costs nothing to assert.
$PY - "$H" <<'PYEOF2'
import sys, os, yaml
h = sys.argv[1]
for rel in ("reminders.yaml", "state/reminders.yaml"):
    p = os.path.join(h, rel)
    if not os.path.exists(p):
        continue
    try:
        d = yaml.safe_load(open(p))
    except Exception:
        continue          # the parse WARN in block D already covers this
    items = d.get("reminders") if isinstance(d, dict) else None
    if not isinstance(items, list):
        continue
    bad = [x.get("id") for x in items
           if isinstance(x, dict) and x.get("status") == "open"
           and x.get("notified_at") and not x.get("recur")]
    if bad:
        print("WARN: %s has %d DELIVERED one-shot reminder(s) still status:open -- %s; "
              "a notified non-recurring reminder should be done" % (rel, len(bad), ", ".join(map(str, bad[:6]))))
PYEOF2

# D3. STAGED SEND vs. REMINDER DOUBLE-PING (added 2026-10-03 calibration).
#     Real near-miss that day: the W41 planning offer was staged for Sun 09:00-11:00 PT while
#     reminder hes-spirit-week-2026-10-05 was due Sun 09:00 with the SAME content. Reminders are
#     processed at STEP 2 of the tick order, BEFORE staged-send handling, so the 09:00 tick would
#     have fired the reminder as its own message and THEN sent the offer -- two messages, minutes
#     apart, same content. It was caught by hand and fixed by writing a guard into the reminder's
#     own note; this detector is so the NEXT one does not depend on someone remembering.
#     Fires when a staged-*.md file exists and an open reminder is due before that file's EXPIRY
#     while its note carries no guard marker. WARN-only: overlap is legitimate, silence is not.
/usr/bin/python3 - "$H" <<'PYEOF3'
import os, sys, glob, re, datetime
h = sys.argv[1]
try:
    import yaml
except Exception:
    sys.exit(0)

staged = sorted(glob.glob(os.path.join(h, "state", "staged-*.md")))
if not staged:
    sys.exit(0)

# Latest expiry mentioned across staged files; a date alone is enough granularity here.
expiries = []
for f in staged:
    head = open(f, errors="replace").read(4000)
    for m in re.finditer(r"EXPIR\w*[^0-9]{0,40}(\d{4}-\d{2}-\d{2})", head, re.I):
        expiries.append(m.group(1))
if not expiries:
    sys.exit(0)
horizon = max(expiries)

p = os.path.join(h, "reminders.yaml")
if not os.path.exists(p):
    sys.exit(0)
try:
    d = yaml.safe_load(open(p))
except Exception:
    sys.exit(0)
items = d.get("reminders") if isinstance(d, dict) else None
if not isinstance(items, list):
    sys.exit(0)

GUARDS = ("DO NOT DELIVER THIS AS A STANDALONE PING", "NOT AS A STANDALONE PING",
          "DELIVER IT INSIDE", "do not fire separately")
risky = []
for x in items:
    if not isinstance(x, dict) or x.get("status") != "open":
        continue
    due = str(x.get("due") or "")[:10]
    if not due or due > horizon:
        continue
    note = str(x.get("note") or "") + " " + str(x.get("text") or "")
    if any(g.lower() in note.lower() for g in GUARDS):
        continue
    risky.append("%s (due %s)" % (x.get("id"), due))

if risky:
    print("WARN: %d open reminder(s) fall due on/before the staged send's expiry (%s) with no "
          "standalone-ping guard in the note -- %s; reminders fire at step 2, BEFORE staged sends, "
          "so decide now whether each rides inside the send or goes separately"
          % (len(risky), horizon, ", ".join(risky[:6])))
PYEOF3

# E. calibration ritual actually recorded. Three days (9/24-9/26) plus 9/28 and 9/29 went
#    unrecorded and were only noticed weeks later by hand. A hole is not three quiet days.
FB="$H/state/feedback.yaml"
# (written as an `if`, not `a && ! b && c`: zsh RUNS the && form fine but `zsh -n` rejects it,
#  so the chain form made this very script unlintable. A detector must be checkable itself.)
if [ -f "$FB" ]; then
  if ! grep -q "date: '$Y'" "$FB"; then
    print -r -- "WARN: state/feedback.yaml has no entry for $Y -- yesterday's calibration was skipped or not recorded"
  fi
fi
exit 0
