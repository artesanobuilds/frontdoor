# Setup

About an hour the first time. macOS only (launchd, tmux, zsh).

## 0. Prerequisites

```bash
brew install tmux jq bun librsvg          # librsvg only to re-render the diagram
brew install googleworkspace/tap/gws      # or see https://github.com/googleworkspace/cli
# Claude Code: https://claude.com/claude-code  (a Max plan is what the reference install uses)
```

## 1. Clone and configure

```bash
git clone https://github.com/artesanobuilds/frontdoor.git ~/frontdoor
cd ~/frontdoor
cp config.example.yaml config.yaml        # fill in: your Telegram id, timezone, areas, agents
mkdir -p state runs memory inbox/processed checklists week-plans
printf '# TODO\n\n## Inbox (unsorted)\n' > todo.md
printf 'reminders: []\n' > reminders.yaml
printf 'bills: []\n' > bills.yaml
printf '# Playbook\n' > playbook.md
printf '# Memory index\n' > memory/MEMORY.md
cp agent/william.md ~/.claude/agents/william.md
mkdir -p .claude/commands && cp commands/*.md .claude/commands/
```

If you clone somewhere else, set `FRONTDOOR_HOME` in the launchd plists and your shell.

## 2. Telegram

1. Create a bot with [@BotFather](https://t.me/BotFather); copy the token.
2. Install the official plugin in Claude Code: `/plugin install telegram@claude-plugins-official`.
3. Put the token in `~/.claude/channels/telegram/.env` as `TELEGRAM_BOT_TOKEN=…` (the
   `/telegram:configure` skill does this for you).
4. Find your numeric user id (message [@userinfobot](https://t.me/userinfobot)). Put it in
   `config.yaml:telegram.chat_id` and in `~/.claude/channels/telegram/access.json` as the FIRST
   entry of `allowFrom`, with `"dmPolicy": "allowlist"`.
5. Apply the plugin guard: [patches/telegram-plugin-guard.md](../patches/telegram-plugin-guard.md).
   Without it, every other Claude Code session on the machine steals the channel.

## 3. Google (calendar + Gmail)

William gets his **own** credential directory so his token refreshes don't fight your other
sessions, and his scopes stay minimal.

```bash
export GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-william
gws auth setup            # one-time: a GCP project + OAuth "Desktop app" client; follow the prompts
gws auth login --services calendar,gmail
gws auth status           # expect token_valid: true
```

If your account is on a Google Workspace domain and the token dies daily with
`invalid_rapt`, that is the domain's *Google Cloud session control* policy. In the Admin console
mark the OAuth client as **Trusted** (Security → API controls → App access control) and tick
**Exempt trusted apps** under Google Cloud session control. Personal @gmail.com accounts don't
have this problem.

## 4. The agent team (optional)

Edit `config.yaml:agents`: the shared mailbox (the same Gmail William is logged into), the
member agents and their scopes. Onboard each member agent with
[docs/member-agent-prompt.md](member-agent-prompt.md) (the prompt plus where to paste it per
platform) and give it Gmail access to the same mailbox. The full protocol, for reference, is
[docs/agent-team-protocol.md](agent-team-protocol.md). That is the whole integration.

## 5. Keep it alive

```bash
cp launchd/tmux-server-supervise launchd/tmux-durable-lib ~/.local/bin/ && chmod +x ~/.local/bin/tmux-*
for p in launchd/com.frontdoor.*.plist; do
  sed "s|__HOME__|$HOME|g; s|__FRONTDOOR_HOME__|$HOME/frontdoor|g" "$p" > ~/Library/LaunchAgents/$(basename "$p")
done
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.frontdoor.tmux-server.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.frontdoor.william.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.frontdoor.mailcheck.plist   # if using the agent team
```

Within a minute `tail state/keeper.log` should show `telegram channel up` and
`heartbeat loop sent`. DM your bot. He answers.

Handy shell functions:

```zsh
william()         { /opt/homebrew/bin/tmux attach -t william }
william-console() { ~/frontdoor/tools/console.sh }
```

## 6. Rules of the road

- **Never start a second William.** The Telegram token allows one poller. Don't run `claude` in
  the FrontDoor directory by hand, don't run the keeper by hand, don't send `/loop` yourself.
  Observe with `william` (read-only intent) or `tools/status.sh`.
- **Don't edit live state from another session.** A tick may be writing the same file.
- **`latest.md` is a symlink.** `cp` onto it destroys the report it points at. Use
  `tools/write-report.sh`.
- The persona, config, keeper and plists are yours. The guides and playbook are William's; he
  rewrites them during his end-of-day calibration. Change the mechanism, not the prose, when
  you want a behavior to stick.

## Adding a family member

They message @userinfobot and send you the number. Add it to `config.yaml:telegram.family`
with a name and language, and to `access.json:allowFrom` (after your own id). No restart.
Send them the bot link `https://t.me/<your_bot_username>`.
