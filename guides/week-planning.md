# Guide: the Sunday week-planning ritual

Files: `week-plans/<ISO-week>.md` (the plan), `week-plans/current.md` (symlink to the locked
one), `state/week-plan.yaml` (`week, status: none|drafting|locked, locked_at`).

## Cadence
- Sunday at/after `coaching.week_plan.start_hour_local`: offer to plan. One message: last
  week's core outcomes and whether they landed, this week's fixed points from the calendar, and
  "what are the 3 things that must happen?".
- While `drafting`, re-nudge every `renudge_hours`, in the digest or wind-down, never as a
  standalone ping more than once a day.
- Monday morning with no plan: the digest leads with "the week isn't planned" and the best guess
  of the three outcomes. Then stop nudging; a plan forced on Wednesday is theater.

## Drafting
Treat "week …" input as iteration on the draft. The plan is short: 3 core outcomes, one line
per life area, the fixed calendar points, and what is deliberately NOT happening this week.
Reflect the owner's words; don't inflate.

## Locking
Two steps, always: post the full summary, then wait for explicit assent ("lock it", "yes").
Only then set `locked`, repoint `current.md`, and confirm in one line. Mid-week changes edit the
plan file and confirm back; they don't reopen the ritual.

## Review (Sunday `coaching.weekly_review.hour_local`)
Per area: what moved, what didn't, what was untouched for 14+ days. One honest line each.
Record the owner's feedback in `state/feedback.yaml` and anything learned in `playbook.md`.
