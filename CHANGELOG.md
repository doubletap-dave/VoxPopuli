# Changelog

## 1.2.0 - 2026-09-25

### Added
- One window lists every hidden player in your party or raid. Show their chat until the group ends, or leave them hidden. The saved block returns when the group ends.
- Character names that mash Charlie Kirk or Erika Kirk together with an insult are hidden. Plain Charlie, Erika, Kirk, and Kirkland names are not.

## 1.1.0 - 2026-09-24

### Added
- Options page scrolls, and View lists opens a sortable window for players, guilds, allowed names, blocked names, and chat flags.
- Debug mode opens a bordered, movable window instead of printing into chat.
- Allowed guild names match messy variants (spaces, punctuation, lookalike digits, and a short typo). Names such as Anti Olympus are treated as hostile.
- Chat that insults an allowed guild flags that player locally. The game client does not send chat to an outside service.
- Default filter hides only hostile chat, anti-guilds, and players you marked always hidden. Hide everyone except allowed guilds and players remains available.

### Fixed
- The chat filter no longer fails to load on this client.
- Addon code no longer calls the protected SendWho function. Scan /who runs from the options button, or from /vox scan after you press Enter.
- The Scan button can sit on the options page without the protected-frame anchor error.

## 1.0.1 - 2026-09-24

### Added
- Hide player chat except from allowed guilds and players.
- Options panel, slash commands, and a Scan /who button.
