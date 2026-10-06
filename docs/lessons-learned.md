# Lessons learned (July to October 2026)

What broke, what it cost, and the rule that came out of it. Dates are when the rule was written.

## Keeping a session alive

- **One poller per Telegram token.** Any other Claude Code session on the machine with the
  plugin installed steals the channel silently. Guard the plugin (`patches/`), and never set the
  guard variable globally: a `tmux setenv -g` leaked it into every later pane, other sessions
  passed the guard, and the keeper spent a month killing them and recycling William on top. The
  "recycle storm" was diagnosed three times as a keeper race before someone ran `ps eww` on the
  killed process's parent. *Check the parent of the thing you killed before theorizing.* (10-05)
- **Claude Code caches "this MCP server needs auth" in a shared file**
  (`~/.claude/mcp-needs-auth-cache.json`). When another session trips the guard, the entry is
  written, and every session started afterwards, William included, skips the channel with no
  log line at all. The keeper now deletes the entry before each start. *Session-alive is not
  channel-alive; the only proof is the bun child.* (10-05)
- **The keeper must not own the tmux server.** A keeper-started server daemonizes to PPID 1
  with nobody supervising it; after a reboot it was gone. A second LaunchAgent runs `tmux -D` in
  the foreground, and the keeper only kickstarts it. (09-01)
- **Send the heartbeat `/loop` only after the channel is up.** Typing it too early preempts
  channel init; the session is deaf and the keeper recycles it in a loop. (08-04)
- **Enter gets swallowed.** The UI sometimes leaves the command in the input box. Verify it
  submitted, re-send Enter, retype if needed. (08-03)
- **Session-alive is not tick-alive.** A starved box swallowed the loop for 5h27m while the
  pane looked fine. The only proof a tick ran is a file in `runs/<date>/`. (09-09)

## State and files

- **`latest.md` is a symlink.** `cp` and `>` onto it destroyed five reports in one day. Only
  `tools/write-report.sh` may land a report; it never names `latest.md` as a write target. (08-23)
- **Count with the parser, never with a first-field grep.** `^- (kind|key):` went stale the day
  one entry was written with fields in a different order, returned 278 for 279, and nobody
  noticed for weeks. (09-30)
- **Any counter you inherit is a claim.** Recompute from the file every tick. Counters drifted
  between ticks for days before this rule. (09-11)
- **Quote every prose value in YAML**, including ones a script emits as new keys. A colon in an
  unquoted reason broke the loops file twice. (09-20)
- **A 146 KB conversation log passed a line-count bar the whole way up.** Measure bytes; prune
  at 24 KB; silent ticks write no entry. (08-11)
- **Three date systems.** Report dates are local, report stamps are UTC, the keeper log is
  local. Label every clock time. An unlabeled "18:30" nearly sent a bundle seven hours early. (10-05)

## Talking to a person

- **Real-time replies are independent of the tick.** A slow reply is a broken channel, never
  "waiting for the next tick". (08-02)
- **High effort added minutes to phone replies for no gain.** `--effort medium`. (08-04)
- **A coaching agent with an empty backlog is theater.** Nudges aim at a listed item or ask for
  one. (08-02)
- **People answer in the calendar, not the chat.** After a calendar-shaped offer, sweep
  `updatedMin`. Silent action is a reply. (10-04, 09-21)
- **Offers expire silently; promises never.** Batch dead offers into one kill-list with a stated
  silence default. One wind-down beats three nags. (09-17, 09-20)
- **Message category beats message form.** A human waiting is urgent; self-directed can wait for
  the digest. (08-17)
- **Collision nudges don't work.** Measured over weeks: the owner does not resolve calendar
  collisions in advance, in any wording. Surface once, stop. (08-21)
- **Put the behavioral rule in the file read at the moment of decision.** When coaching was
  suspended, the banner went at the top of `guides/coaching.md`, not in a memory note. (08-27)

## Cost

- **10-minute ticks were mostly context re-reads.** 30/60 cut cost by two thirds; inbound stays
  real-time regardless. (08-04)
- **Progressive disclosure.** A ~100-line persona that points at one guide per activity, instead
  of one large prompt. (08-03)
- **Smallest model that does the job.** Opus decides; haiku scans; sonnet summarizes. (08-03)

## Working with other agents

- **Trusted-but-fallible is literal.** A collaborator self-corrected twice in three hours; verify
  any claim about state before it reaches a phone. (08-04)
- **A dead source is a noted gap, not a mystery to re-diagnose every tick.** Say so once with the
  date, keep the config key as history, move on. (08-16, 09-20)
- **Prefer a detector over a rule.** Seven self-corrections in one day were all cases where a
  recorded rule and the real behavior had diverged and nothing noticed. `tools/selfcheck.sh`
  exists because prose depends on compliance. (09-30)
- **One mailbox, subject-routed, every agent logs everything.** Agents on different platforms
  share nothing but Gmail. The id in the subject is the whole protocol. (10-05)

## Google auth

- **Scope trimming did not fix daily re-auth.** `invalid_rapt` is Workspace *session control*,
  an admin policy, not a token property. Fix: mark the OAuth client Trusted and exempt trusted
  apps. Personal Gmail accounts never see it. (08-05, 10-05)
- **One failed probe is not an outage.** Two consecutive ones are. (08-05)
- **A malformed `gws` call returns an error JSON that parses as an empty inbox.** Assert
  `'error' not in d` before trusting a zero. (08-xx)
