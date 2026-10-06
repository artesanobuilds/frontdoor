# Architecture

## The shape of the process

```
launchd: com.frontdoor.tmux-server ──> tmux server (foreground, supervised)
launchd: com.frontdoor.william ─────> tools/keeper.sh every ~60 s
                                        │  owns tmux session "william"
                                        │  starts:  claude --model <opus> --effort medium
                                        │            --channels plugin:telegram@claude-plugins-official
                                        │  waits for the Telegram poller (a bun child), then types
                                        │  /loop 30m @william heartbeat   (60m in quiet hours)
                                        └─ recycles the session at the 07:00 / 22:00 cadence boundary
launchd: com.frontdoor.mailcheck ───> tools/mailcheck.sh every 10 min
                                        └─ new "to William:" mail → typed into the session as a prompt
```

Three things arrive in the session as input: a Telegram message (the plugin injects it as a
`<channel>` tag), a heartbeat fire (the `/loop`), and an agent-mail prompt (the poller). All
three are handled by the same persona with the same files.

## Why these choices

**A kept-alive session, not a server.** Claude Code already has the tools, the plugin system,
the MCP channel, and the model. Wrapping it in launchd + tmux gives a 24/7 assistant with no
code to maintain beyond shell scripts. The price is that sessions recycle constantly, so nothing
can live in context.

**Everything on disk.** `state/conversation-log.md` and `state/open-loops.yaml` are the only
memory of the conversation. `state/notifications.yaml` records every send, which is what makes
a re-run tick idempotent. `runs/<date>/<stamp>.md` is the tick's own report and `runs/latest.md`
is what a freshly recycled session reads first. If it isn't in a file, it didn't happen.

**A thin persona and progressive disclosure.** `agent/william.md` is ~100 lines: the rules that
override judgment (money, other people, irreversible loss, privacy) and a table mapping each
activity to one guide. Each turn loads one guide. This cut per-tick cost by more than half
compared with a single large prompt, and it makes the guides safe for the agent to edit.

**Guides are the agent's; the persona, config and keeper are the owner's.** William rewrites
`guides/` and `playbook.md` during calibration. He proposes changes to the rest and waits. The
asymmetry is deliberate: the files that keep him online and the files that define his limits
should not be changed by the process they govern.

**Detectors over rules.** `tools/selfcheck.sh` runs after every report with WARN-only invariants.
Every one of them came from a day where a written rule and the real behavior had drifted apart
and nothing noticed. Prose depends on compliance; a count does not.

**Thirty minutes, not ten.** The heartbeat started at 10 minutes. Most of the spend was context
re-reads, not work. At 30/60 the assistant costs roughly a third and nobody noticed the
difference, because inbound messages are real-time regardless of cadence. The agent-mail poller
restores the 10-minute feel for the one thing that benefits from it, at the cost of a Gmail
search.

**One mailbox for the agent team.** Agents on three platforms share no memory, no API, and no
process. They all have Gmail. A subject-line protocol with an id is the smallest thing that
works, it is readable by a human in the mail client, and every agent can rebuild its state from
the mailbox alone.

## Data flow for a family request

```
Mom (Telegram, es) ──> William: "¿puedes recordarle a Alex la torta del sábado?"
  ├─ reply to Mom's chat: "Claro, se lo paso."
  ├─ todo.md ## 👪 Family requests: "- [ ] pick up the cake Saturday (from: Mom, …)"
  ├─ state/open-loops.yaml: family-request-cake-2026-10-10
  ├─ if real work:  email  "William to Mica: order and pick up the cake Sat [#a0012]"
  │                 state/agent-requests.yaml + state/agent-mail-log.md
  ├─ owner: next digest (or now, if urgent)
  └─ later: "Mica to William: ordered, pickup Sat 11:00 [#a0012]" (10-min poller)
            → owner on Telegram, Mom on Telegram, loop closed, log line
```

## Directory layout

```
agent/william.md        persona (install to ~/.claude/agents/)
config.example.yaml     ids, hours, names, paths → copy to config.yaml
guides/                 one guide per activity; the agent edits these
commands/               /bills /todo /week slash commands (install to .claude/commands/)
tools/                  keeper, mailcheck, write-report, selfcheck, status, console, usage
launchd/                the three LaunchAgents + the tmux supervisor
patches/                the Telegram plugin guard and why it is needed
docs/                   this file, setup, lessons learned, the agent-team protocol
state/ runs/ memory/ inbox/ checklists/ week-plans/   runtime, git-ignored
```

## Costs

With Opus as the decision maker and haiku/sonnet subagents for scans, a 30/60-minute cadence
runs in the low tens of dollars per day on a Max plan's accounting, dominated by cache reads.
`tools/usage.sh today|month` reads the transcript JSONL and prints tokens and an estimate per
model; update its price table when pricing changes.
