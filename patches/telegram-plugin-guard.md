# Telegram plugin: the single-poller guard (re-apply after every plugin update)

A Telegram bot token allows exactly **one** `getUpdates` poller. Claude Code's official
`telegram` plugin is a user-level plugin, so **every** Claude Code session on the machine
(another project, an IDE that imports the plugin's MCP config, a stray `claude --resume`) spawns
its own poller and steals the channel from William. Messages vanish, and the keeper recycles
William on top of it.

The fix is two small local patches to the plugin's `server.ts`. A plugin update overwrites them;
`tools/keeper.sh` logs `telegram channel did not come up` when that happens, and you re-apply.

## Where

Patch the version that is actually running, not the newest on disk:

```
ps -eo pid,ppid,command | grep "bun run" | grep telegram | grep -v grep
```

Path pattern: `~/.claude/plugins/cache/claude-plugins-official/telegram/<version>/server.ts`.
(There is also a `marketplaces/…/external_plugins/telegram/server.ts` copy; the cache one runs.)

## Patch 1: refuse to start unless this is William's session

At the very top of `server.ts`, after the shebang and before the imports:

```ts
// Local patch: only the session started by tools/keeper.sh may poll the Telegram token.
// The value is a per-start nonce that must match the file the keeper wrote.
import { readFileSync as __nonceRead } from 'fs'
{
  const want = process.env.WILLIAM_CHANNEL
  const nf = process.env.WILLIAM_NONCE_FILE
  let ok = false
  try { ok = !!want && !!nf && __nonceRead(nf, 'utf8').trim() === want } catch {}
  if (!ok) {
    console.error('telegram channel: WILLIAM_CHANNEL nonce missing or stale — refusing to start')
    process.exit(0)
  }
}
```

`tools/keeper.sh` generates a random nonce on every start, writes it to `state/channel-nonce`
(mode 600) and passes both `WILLIAM_CHANNEL=<nonce>` and `WILLIAM_NONCE_FILE=<path>` to the
session with `tmux new-session -e`. Why a nonce and not a flag: a flag leaks. The first version
was `WILLIAM_CHANNEL=1`, and every process that ever inherited it (an agent UI started from a
terminal tab, a `claude --resume`) passed the guard and stole the channel for weeks. A value
that changes on every keeper start cannot be inherited usefully: anything older than the current
session fails the compare.

## Patch 2: permission prompts go to the owner only

The plugin sends every permission prompt (with Allow/Deny buttons) to **every** allow-listed
chat. With family members allow-listed, they would see William's tool prompts and could approve
them. In the `permission_request` notification handler, change

```ts
for (const chat_id of access.allowFrom) {
```
to
```ts
for (const chat_id of access.allowFrom.slice(0, 1)) {
```

and keep the owner's id **first** in `~/.claude/channels/telegram/access.json:allowFrom`.

## Applying safely

1. `cp server.ts server.ts.pre-patch`
2. Edit as above.
3. Verify it refuses cleanly WITHOUT the var (this never touches the live token):
   `cd <plugin dir> && env -u WILLIAM_CHANNEL bun run --silent start < /dev/null` → exit 0 and
   the refusal line. Never test WITH the var set; that would steal the channel from the live
   session.
4. The running poller keeps the old code; the patch takes effect on the next keeper recycle.

## Known side effect, and the cache trap

Every other Claude Code session on the machine shows the Telegram MCP as "failed to connect".
That is the guard working. But Claude Code also records that failure in a **shared** file,
`~/.claude/mcp-needs-auth-cache.json`, and every session started afterwards (William included)
then silently skips the channel. `tools/keeper.sh` deletes that entry before each start. If you
ever see `did not come up within 60s` with no `bun` child at all, that file is the first place to
look.
