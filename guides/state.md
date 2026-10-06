# Guide: state files and the TODO list

Read before writing any YAML state file, and for anything starting with "todo".

## The files
| File | Key | What |
|---|---|---|
| `state/conversation-log.md` | – | one line per exchange; byte-capped (prune at 24 KB to `conversation-log-archive.md`) |
| `state/open-loops.yaml` | `loops` | promises and offers: `id, created, promise, status, done_at, note` |
| `state/notifications.yaml` | `sent` | every send, for idempotence |
| `state/questions.yaml` | `questions` | the assumption-confirmation queue |
| `state/feedback.yaml` | `feedback` | corrections received: `date, source, text, action_taken` |
| `state/bills-status.yaml` | `months` | per-month paid/pending per bill |
| `state/week-plan.yaml` | – | status of the current plan |
| `state/agent-requests.yaml` | `requests` | open/closed agent-team requests |
| `state/agent-mail-log.md` | – | one line per protocol email seen |
| `reminders.yaml`, `bills.yaml` | `reminders`, `bills` | the owner's lists |

Every YAML wraps its list under a **different** key. Know the shape before you append.

## State integrity (data loss is not recoverable)
- After EVERY write: parse-verify (`/usr/bin/python3 -c "import yaml; yaml.safe_load(open('f'))"`
  or `ruby -ryaml`) **and** spot-check that untouched entries survived. Valid YAML is not proof
  of preserved structure; a clobbered file parses fine.
- **Never count entries with a first-field grep** (`^- id:`): it rots the moment one entry is
  written with fields in another order, and it fails closed with a plausible wrong number. Count
  zero-indent list structure (`grep -cE '^- '`) or load the YAML and take the length.
- **Appending to an append-only log:** assert the trailing newline first, verify the entry count
  went up by exactly one.
- **Quote every prose value** you put into YAML, hand-typed or generated. A colon or a `#` in an
  unquoted note has broken the file more than once.
- If something broke, back up as `.bak-<date>` and repair before the tick ends.
- `latest.md` in `runs/` is a symlink. Never `cp` or `>` onto it. `tools/write-report.sh` only.

## TODO list
`todo.md`: sections are the life areas in `config.yaml:areas`, plus Inbox and Family requests.
Item format: `- [ ] text  (added YYYY-MM-DD, prio: high|med|low)`.
Any message starting with "todo": bare → show top items per area; otherwise the rest is a
brain dump. Parse it into discrete items, assign area and priority, dedupe against what's
there, append with today's date, and reply with a short "filed: …" summary. At most one
clarifying question; the owner is dumping, not filling a form.
Daily prune at digest time: completed items older than 7 days move to `todo-archive.md`; items
untouched for 14+ days get flagged in the weekly review.

## Feedback
Replies are feedback ("too chatty", "digest earlier", "stop reminding me about X"). Log each in
`state/feedback.yaml` and never act on the same one twice. Tune `config.yaml` values immediately
when the feedback is about cadence or hours, annotating `# tuned <date>: <why>`.
