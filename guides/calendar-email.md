# Guide: calendar, Gmail, iMessage, reminders, checklists, memory

All Google access goes through the `gws` CLI with William's own credential directory:
`export GOOGLE_WORKSPACE_CLI_CONFIG_DIR=<config.yaml:gmail.config_dir>` **in the same shell** as
the call. Scopes: calendar + gmail only.

## Calendar
- `gws calendar events list --params '{"calendarId":"primary","timeMin":"…","timeMax":"…","singleEvents":true,"orderBy":"startTime"}'`.
  `calendarId` goes in `--params`; there is no `users` segment.
- A healthy answer is an `items` array (possibly empty). **A malformed call returns an error
  JSON that parses as an empty calendar.** Assert `'error' not in d` before trusting a zero.
- Solo events the owner asked for: create directly. Anything with guests: draft, show, wait.
- The calendar is a reply surface: after any calendar-shaped offer, sweep `updatedMin` on the
  next tick. People answer by creating the event instead of texting back.
- Collisions: surface them once, in the digest. Don't nag people to resolve collisions in advance;
  measured, they don't.

## Gmail
- `gws gmail users messages list --params '{"userId":"me","q":"…","maxResults":N}'` then `get`
  per id with `format: metadata` unless you need the body.
- Keep a high-water message id in the run report so the next tick reads only what's new.
- Mail is read-mostly: drafts, sends after confirmation, and protocol mail to the agent team
  (`guides/agents.md`). Never archive, label, or delete; another tool may own that.
- Sending: `gws gmail users messages send` with a base64url RFC 2822 `raw`. Keep bodies plain.

## Auth
`invalid_grant … invalid_rapt` means the Workspace session policy expired the token; only the
owner can log in again (`gws auth login` with the config dir exported). One failed probe is not
an outage; two consecutive ones are. Say so in the digest once and degrade: calendar and mail
sections become "unavailable since <time>", everything else continues.

## iMessage (read-only)
`sqlite3 -readonly <config.yaml:sources.imessage_db>`. Requires Full Disk Access for the
terminal; a TCC block is a noted gap, not an error. Unreplied texts older than a day go in the
digest as one line each. Never write, never send, never copy the db.

## Reminders
`reminders.yaml` (`reminders:`): `id, text, due, recur, status, notified_at, note`. Deliver when
`due <= now`, record in `state/notifications.yaml`. A delivered one-shot becomes `done`.
A reminder whose content is already in a staged send carries a guard note so it does not fire
separately (`tools/selfcheck.sh` warns).

## Checklists
`checklists/<name>.md`: markdown checkboxes. "checklist X" shows it; items the owner ticks by
text get flipped and confirmed back.

## Memory
`memory/MEMORY.md` is the index; one fact per file. Add a file when you learn something about
the owner that will still be true next month; update the index line. Never secrets.
