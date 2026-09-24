# VoxPopuli

The antithesis of [OlympusMute](https://www.curseforge.com/wow/addons/olympusmute) —
but better. They built a tool to oppress; this is liberation. Instead of hiding
chat from chosen guilds, it hides **all player chat except** from whitelisted
("friendly") guilds and players.

## What it does

- Hides Say, Yell, Emote, Whisper, Trade/General/custom channels, Guild,
  Party, Raid, Raid Warning, and Instance chat from everyone who isn't
  whitelisted. (System messages, boss emotes, and NPC dialogue are untouched.)
- **Retroactively purges** a player's earlier chat lines once they're
  identified as hostile — OlympusMute does this too, so we do it better.
- Hides muted players' chat bubbles in the open world, with exact text
  matching and frame restoration when bubbles are reused.
- Auto-declines guild invites from non-whitelisted players (on by default);
  group invites, duels, and trades are toggleable (off by default). Invites
  received *before* someone is identified get declined once they are.
- Full in-game settings panel: Interface > AddOns > VoxPopuli, or just
  type `/vox`.
- Adds a "Hidden by VoxPopuli" line to muted players' tooltips — and learns
  the player *first*, so the very first tooltip is already correct.
- Warns you (chat + raid warning frame) when you group with a
  non-whitelisted player, with a delayed recheck for late-arriving guild info.
- Counts hidden messages (session + all-time) and learned players:
  `/vox stats`.
- Realm-aware identity (`Name-Realm`), GUID mapping, and saved-variable
  migration — no cross-realm mistaken identity.

## How players are identified

Chat messages don't include the sender's guild, so like OlympusMute it learns
from targeting, mousing over, nameplates, grouping, and `/who`:

- `/vox scan` — deep level-banded scan rotation (works around /who's
  50-result limit, including on the Forever client where small results print
  straight to the chat frame).
- `/vox autoscan on|off` — automatically walk all friendly rosters via /who
  shortly after login (default: on). This is what makes the addon zero-setup:
  Olympus is pre-whitelisted and everyone else is muted from the jump.
- `/vox id <Name>` — identify one player's guild.
- `/vox check <Name>` — see exactly why someone is shown or muted.

Your own guild is auto-whitelisted on login.

## Install

1. Unzip so the layout is `Interface/AddOns/VoxPopuli/VoxPopuli.toc`.
2. Enable it on the character select addons screen (tick "Load out of date
   AddOns" if the client flags the interface version).
3. `/vox help` in game, or `/vox` to open the settings panel.

## Key commands

| Command | Effect |
|---|---|
| `/vox` | Open the settings panel |
| `/vox guild add <name>` | Whitelist a guild (partial, case-insensitive — "Olympus" matches "Olympus Rising") |
| `/vox guild block <name>` | Blocklist a guild (exact match — always muted, even if it partially matches the whitelist; e.g. "Anti Olympus") |
| `/vox player allow <name>` | Never mute this player (overrides everything) |
| `/vox player block <name>` | Always mute this player (overrides friendly guild; purges their history) |
| `/vox unknowns on\|off` | Mute players whose guild isn't learned yet (default: on) |
| `/vox autoscan on\|off` | Auto-learn friendly rosters on login (default: on) |
| `/vox channel <name> [on\|off]` | Per-channel toggles |
| `/vox declines guild\|group\|duel\|trade [on\|off]` | Auto-decline toggles |
| `/vox debug` | Extra troubleshooting output |

## Notes / limitations

- A stranger's first messages are hidden until they're identified (that's the
  inverse of OlympusMute's "first messages may appear" caveat). Turn off
  `unknowns` if you'd rather see strangers until proven hostile.
- OlympusMute emits no addon traffic at all (verified against its 1.0.8
  source), so its *users* can't be detected — Blizzard exposes no API for
  listing another player's addons. This addon filters by guild and player,
  which is the best any client-side tool can do.
- Interface version in the .toc is 16001 (WoW: Forever). If your client
  reports it out of date, either tick "Load out of date AddOns" or bump the
  number to your client's build.

MIT License.
