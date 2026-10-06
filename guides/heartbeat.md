# Guide: heartbeat tick

Fired by `/loop <N>m @william heartbeat`. One tick per fire, then exit. Every tick ends with a
report written by `tools/write-report.sh`; a tick that wrote no report did not happen.

## Before anything: the log gate
Decide at the start whether this tick will send anything. If it ends up sending nothing and
changing no state, it writes **no** entry in `state/conversation-log.md` (the log is for
conversation, and a silent tick is not conversation). It still writes a run report.

## Order of work
1. **Inbox + open loops.** Process `inbox/*.yaml` (`guides/collab.md`). Re-read
   `state/open-loops.yaml`: deliver promises that are due; offers expire silently, promises never.
   **1b. Agent mail.** Sweep `subject:"to William:"` since the high-water mark and run the
   overdue nudges (`guides/agents.md`).
2. **Reminders.** Deliver `open` reminders with `due <= now` not already in
   `state/notifications.yaml`. A delivered one-shot (no `recur`) becomes `done`.
3. **Bills.** Open the month's entries when lead windows start; escalate per `guides/bills.md`.
4. **Pre-event nudges.** Events starting within `heartbeat.pre_event_nudge_minutes`, once per
   event. Count travel legs before tick timing: a nudge after the person had to leave is noise.
5. **Morning digest.** Once per local day, first tick at/after `digest.hour_local`. In priority
   order: week-plan core outcomes (or "the week isn't planned") · today's calendar · due
   reminders · unpaid bills · top-3 TODOs · 👪 family requests since the last digest · open agent
   requests (id, agent, topic, age) · unreplied texts if readable · the single nudge · up to
   `coaching.max_questions_per_day` queued questions. Short enough to read at a glance. Run the
   daily TODO prune. Record `kind: digest` + date in `state/notifications.yaml`.
6. **Stall check-ins** (non-quiet hours): `guides/coaching.md`.
7. **Sunday planning + review:** `guides/week-planning.md`.
8. **End-of-day calibration** on the last tick before quiet hours: `guides/calibrate.md`.
9. **Report:** `tools/write-report.sh` on stdin. Never hand-roll the path or touch `latest.md`.

## Rules that came from incidents
- **Every send is idempotent.** Check `state/notifications.yaml` for the same `kind` + key before
  sending. Two concurrent ticks once sent the same digest twice.
- **Any counter you inherit is a claim.** Recompute every count from the file; never carry a
  number from the previous report.
- **Carry-forward is a hypothesis.** The previous run report was written by a dead session.
  Verify its "pending" items against the state files before acting on them.
- **Tick holes are normal.** A sleeping laptop, a recycle, a slow box: a tick can vanish for
  hours. Anything time-critical is **staged**: write `state/staged-<slug>.md` with the full text,
  the send window and an EXPIRY, so any later tick can fire it. Stage in the tick before, not the
  tick of.
- **Session-alive is not tick-alive.** The only proof a tick ran is a file in `runs/<date>/`.
- **Quiet hours** hold everything non-urgent. Reminders and urgent pings break through.
- **Label every clock time PT or UTC** in reports. `RUNDATE` is local, `RUNSTAMP` is UTC; an
  unlabeled "18:30" once nearly sent a bundle seven hours early.
- **WATCH items:** after three identical checks of the same unresolved thing, stop checking every
  tick and check at boundaries (digest, calibration) only.
- **Idle ticks are for building.** A tick with nothing to send may improve a detector in
  `tools/selfcheck.sh` or a guide, with the rule "prefer a detector over a rule".
