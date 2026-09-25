# VoxPopuli

Hides chat from players who are hostile to guilds you allow. Out of the box, any guild with "Olympus" in its name is shown, and your own guild is added when you log in. Everyone else stays visible until they insult an allowed guild, join an anti-guild, or use an offensive name. You can switch on "hide everyone except allowed guilds and players" if you want the stricter filter.

Filtering is client-side only: it changes what you see and nothing else. Nothing is added to your ignore list (so there is no 50-name cap), and the other player is never notified.

## What it does

- Hides player chat from hidden players in Say, Yell, Emote, Whisper, General/Trade/custom channels, Guild, Party, Raid, Raid Warning, and Instance chat. System messages, boss emotes, and NPC dialogue stay visible.
- Hides their chat bubbles in the open world. Dungeons and raids do not let addons change bubbles.
- Auto-declines guild invites from people who are not on your list (on by default). Group invites, duels, and trades can each be turned on separately (off by default). An invite that arrives before someone is identified is declined once they are.
- Adds a "Hidden by VoxPopuli" line to hidden players' tooltips, and a whitelist line for players you have marked as always shown.
- When a hidden player is in your party or raid, one window lists every one of them. Show their chat until the group ends, or leave them hidden. The saved block comes back when the group ends.
- Hides character names that mash Charlie Kirk or Erika Kirk together with an insult, such as "Kirkland Neckhole" or "Charlie Neckkirks". Plain names like Charlie, Erika, Kirk, and Kirkland are left alone.
- Counts hidden messages for this session and all time, and how many players it has learned.

## How players are recognized

Chat messages do not include the sender's guild, so VoxPopuli learns guilds from players you encounter:

- Targeting or mousing over a player
- Seeing their nameplate
- Grouping with them
- Shift-clicking their name in chat
- Any `/who` results, including the Scan button and `/vox id`

When a player is recognized as hidden, their earlier lines are removed from your chat windows. Learned players are saved between sessions. If a `/who` or shift-click shows that someone has left a guild you allow, that is remembered.

Allowed guild names match messy variants: case, spaces, punctuation, lookalike digits, and a short typo. "Olympus" matches "OLYMPUS I" and "OLYMPUS FATTIES". A name that matches and is also against that guild, such as "Anti Olympus" or "Olympus Haters", is hidden. A player you mark "always show" overrides every rule. A player you mark "always hide" stays hidden even if their guild is allowed.

## Options panel

Open it under Interface > AddOns > VoxPopuli, or type `/vox` (alias `/vp`):

- Hidden-message and learned-player counts at the top. View lists opens a sortable window for players, guilds, allowed names, blocked names, and chat flags.
- Turn filtering, each auto-decline, the group warning, bubble hiding, and the login `/who` reminder on or off
- Hide everyone except allowed guilds and players, or leave that off and hide only hostile chat, anti-guilds, offensive names, and players you marked always hidden
- With the stricter mode on, also hide players whose guild is not known yet
- Allowed guild names: add or remove a fuzzy name
- Blocked guild names: exact names that are always hidden
- Scan /who: each click runs the next search in a rotation over every allowed guild and level band, working around `/who`'s 50-result limit
- Mark a player as always shown or always hidden, or clear that override

## Slash commands

- `/vox` — open the options panel
- `/vox on` / `/vox off` — turn filtering on or off
- `/vox guild add Name` / `/vox guild remove Name` — edit the allowed-guild list (partial match)
- `/vox guild block Name` / `/vox guild unblock Name` — edit the exact-name block list
- `/vox guild list` — print both guild lists
- `/vox player allow Name` / `/vox player block Name` / `/vox player remove Name` — per-player overrides
- `/vox player list` — print player overrides
- `/vox everyone on|off` — hide everyone except allowed guilds and players
- `/vox unknowns on|off` — with that mode on, also hide players whose guild is not known yet
- `/vox lists` — open the sortable saved-list window
- `/vox declines guild|group|duel|trade [on|off]` — auto-decline toggles
- `/vox groupwarn on|off` — group warning
- `/vox bubbles on|off` — chat bubble hiding
- `/vox channel Name [on|off]` — per-channel filter (say, yell, emote, whisper, channel, guild, party, raid, instance)
- `/vox scan` — put the next `/who` in the chat box; press Enter to run it. The Scan button on the options panel runs that search on click.
- `/vox id Name` — put a `/who` for one player in the chat box; press Enter
- `/vox check Name` — show why a player is shown or hidden
- `/vox stats` — hidden-message counts
- `/vox autoscan on|off` — login reminder to scan allowed rosters
- `/vox clear` — reset all settings to the defaults

## Notes

- With the default filter, strangers stay visible until they are hostile, in an anti-guild, or using an offensive name. `/vox everyone on` hides anyone outside your allow list.
- This client does not let addons call `/who` on their own. Use the Scan button, or `/vox scan` and press Enter. The login reminder only prepares the next search; it does not run it.
- Players you mark as always hidden stay hidden if they change guilds.
- Built for WoW: Forever. If the game hides some instance chat from addons, those messages pass through unfiltered.

## Install

1. Unzip so the layout is `Interface/AddOns/VoxPopuli/VoxPopuli.toc`.
2. Enable it on the character select addons screen (tick "Load out of date AddOns" if the client flags the interface version).
3. `/vox help` in game, or `/vox` to open the settings panel.

MIT License.
