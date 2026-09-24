-- VoxPopuli - Config
-- Slash command interface: /vox (alias /vp)

local _, NS = ...

local function Toggle(t, key, label)
    t[key] = not t[key]
    NS.Print(("%s %s."):format(label, t[key] and "|cff33ff99ON|r" or "|cffff3333OFF|r"))
end

local function SetOnOff(t, key, label, val)
    if val ~= "on" and val ~= "off" then
        NS.Print(("Usage: ... %s on|off"):format(key))
        return
    end
    t[key] = (val == "on")
    NS.Print(("%s %s."):format(label, t[key] and "|cff33ff99ON|r" or "|cffff3333OFF|r"))
end

local function ListSet(set, title)
    local items = {}
    for k in pairs(set) do table.insert(items, k) end
    table.sort(items)
    if #items == 0 then
        NS.Print(title .. ": (none)")
    else
        NS.Print(title .. " (" .. #items .. "):")
        for _, k in ipairs(items) do print("   - " .. k) end
    end
end

local function GuildCmd(rest)
    local db = NS.db
    local sub, name = rest:match("^(%S+)%s*(.-)%s*$")
    sub = sub and sub:lower() or ""
    if sub == "add" and name ~= "" then
        local key = name:lower()
        if #key < NS.MIN_GUILD_LEN then
            NS.Print(("Guild names need at least %d letters."):format(NS.MIN_GUILD_LEN))
            return
        end
        for k in pairs(db.friendlyGuilds) do
            if k == key then NS.Print('"' .. name .. '" is already whitelisted.') return end
        end
        db.friendlyGuilds[key] = true
        NS.scanQueries = nil  -- roster list changed: rebuild the scan rotation
        NS.Print(('Guild "' .. name .. '" added to whitelist (partial match).'))
    elseif sub == "remove" and name ~= "" then
        db.friendlyGuilds[name:lower()] = nil
        NS.scanQueries = nil
        NS.Print(('Guild "' .. name .. '" removed from whitelist.'))
    elseif sub == "block" and name ~= "" then
        db.hostileGuilds[name:lower()] = true
        NS.Print(('Guild "' .. name .. '" blocklisted (exact match): always muted, even if it matches the whitelist.'))
    elseif sub == "unblock" and name ~= "" then
        db.hostileGuilds[name:lower()] = nil
        NS.Print(('Guild "' .. name .. '" removed from blocklist.'))
    elseif sub == "list" then
        ListSet(db.friendlyGuilds, "Whitelisted guilds (partial match)")
        ListSet(db.hostileGuilds, "Blocklisted guilds (exact match)")
    else
        NS.Print("Usage: /vox guild add|remove|block|unblock <name> | /vox guild list")
    end
    if NS.RefreshPanel then NS.RefreshPanel() end
end

local function PlayerCmd(rest)
    local db = NS.db
    local sub, name = rest:match("^(%S+)%s*(.-)%s*$")
    sub = sub and sub:lower() or ""
    local key = name ~= "" and NS.NormalizeName(name) or nil
    if sub == "allow" and key then
        db.allowedPlayers[key] = true
        db.blockedPlayers[key] = nil
        NS.Print(name .. " will never be muted.")
    elseif sub == "block" and key then
        db.blockedPlayers[key] = true
        db.allowedPlayers[key] = nil
        NS.PurgeHistory(key)  -- wipe their earlier visible lines now
        NS.Print(name .. " will always be muted.")
    elseif sub == "remove" and key then
        db.allowedPlayers[key] = nil
        db.blockedPlayers[key] = nil
        NS.Print(name .. " removed from player overrides.")
    elseif sub == "list" then
        ListSet(db.allowedPlayers, "Always-allowed players")
        ListSet(db.blockedPlayers, "Always-muted players")
    else
        NS.Print("Usage: /vox player allow|block|remove <name> | /vox player list")
    end
    if NS.RefreshPanel then NS.RefreshPanel() end
end

local function CheckCmd(name)
    local db = NS.db
    if not name or name == "" then
        NS.Print("Usage: /vox check <PlayerName>")
        return
    end
    local key = NS.NormalizeName(name)
    local guild = key and db.known[key]
    local status
    if key and db.allowedPlayers[key] then status = "ALLOWED (manual override)"
    elseif key and db.blockedPlayers[key] then status = "MUTED (manual override)"
    elseif guild == nil then status = db.toggles.muteUnknown and "MUTED (unknown)" or "shown (unknown)"
    elseif guild == false then status = "MUTED (guildless)"
    elseif NS.IsHostileGuild(guild) then status = "MUTED (blocklisted guild: " .. guild .. ")"
    elseif NS.IsFriendlyGuild(guild) then status = "SHOWN (guild: " .. guild .. ")"
    else status = "MUTED (guild: " .. guild .. ")" end
    NS.Print(name .. ": " .. status)
end

local function ChannelCmd(rest)
    local db = NS.db
    local chan, val = rest:match("^(%S+)%s*(%S*)%s*$")
    chan = chan and chan:upper() or ""
    if db.toggles.channels[chan] == nil then
        NS.Print("Channels: say, yell, emote, whisper, channel, guild, party, raid, instance")
        return
    end
    if val == "" then
        Toggle(db.toggles.channels, chan, "Channel " .. chan)
    else
        SetOnOff(db.toggles.channels, chan, "Channel " .. chan, val:lower())
    end
end

local function DeclineCmd(rest)
    local db = NS.db
    local which, val = rest:match("^(%S+)%s*(%S*)%s*$")
    which = which and which:lower() or ""
    local key = ({
        guild = "declineGuildInvite", group = "declineGroupInvite",
        duel = "declineDuel", trade = "declineTrade",
    })[which]
    if not key then
        NS.Print("Usage: /vox declines guild|group|duel|trade [on|off]")
        return
    end
    if val == "" then Toggle(db.toggles, key, "Auto-decline " .. which)
    else SetOnOff(db.toggles, key, "Auto-decline " .. which, val:lower()) end
end

local function Help()
    NS.Print("Commands (|cff33ff99/vox|r, alias |cff33ff99/vp|r) - bare /vox opens options:")
    for _, line in ipairs({
        "on|off - enable/disable everything",
        "guild add|remove <name> | guild block|unblock <name> | guild list - whitelist (partial) / blocklist (exact)",
        "player allow|block|remove <name> | player list - per-player overrides",
        "id <name> - identify a player's guild via /who",
        "scan - scan next friendly guild roster via /who (level-banded rotation)",
        "check <name> - show why a player is shown or muted",
        "unknowns on|off - mute players whose guild is unknown",
        "autoscan on|off - auto-learn friendly rosters via /who after login",
        "bubbles on|off - hide muted players' chat bubbles",
        "groupwarn on|off - warn about non-whitelisted group members",
        "declines guild|group|duel|trade [on|off]",
        "channel <name> [on|off] - say,yell,emote,whisper,channel,guild,party,raid,instance",
        "debug - toggle troubleshooting output",
        "stats - show hidden-message counts",
        "clear - reset all settings to defaults",
    }) do print("   " .. line) end
end

SLASH_VOXPOPULI1 = "/vox"
SLASH_VOXPOPULI2 = "/vp"
SlashCmdList["VOXPOPULI"] = function(msg)
    local db = NS.db
    if not db then return end
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)%s*$")
    cmd = cmd and cmd:lower() or ""
    rest = rest or ""

    if cmd == "" or cmd == "config" or cmd == "options" then
        if NS.OpenOptions then NS.OpenOptions() else Help() end
    elseif cmd == "help" then Help()
    elseif cmd == "on" then db.toggles.enabled = true NS.Print("Enabled.")
    elseif cmd == "off" then db.toggles.enabled = false NS.Print("Disabled.")
    elseif cmd == "guild" then GuildCmd(rest)
    elseif cmd == "player" then PlayerCmd(rest)
    elseif cmd == "id" then NS.Identify(strtrim(rest))
    elseif cmd == "scan" then NS.ScanNext()
    elseif cmd == "check" then CheckCmd(strtrim(rest))
    elseif cmd == "debug" then
        db.toggles.debug = not db.toggles.debug
        NS.Print("debug " .. (db.toggles.debug and "|cff33ff99ON|r" or "|cffff3333OFF|r"))
    elseif cmd == "unknowns" then
        if rest == "" then Toggle(db.toggles, "muteUnknown", "Mute unknown players")
        else SetOnOff(db.toggles, "muteUnknown", "Mute unknown players", rest:lower()) end
    elseif cmd == "autoscan" then
        if rest == "" then Toggle(db.toggles, "autoscan", "Auto-scan friendly rosters on login")
        else SetOnOff(db.toggles, "autoscan", "Auto-scan friendly rosters on login", rest:lower()) end
    elseif cmd == "bubbles" then
        if rest == "" then Toggle(db.toggles, "bubbles", "Bubble hiding")
        else SetOnOff(db.toggles, "bubbles", "Bubble hiding", rest:lower()) end
        if not db.toggles.bubbles and NS.ResetBubbles then NS.ResetBubbles() end
    elseif cmd == "groupwarn" then
        if rest == "" then Toggle(db.toggles, "groupWarn", "Group warnings")
        else SetOnOff(db.toggles, "groupWarn", "Group warnings", rest:lower()) end
    elseif cmd == "declines" then DeclineCmd(rest)
    elseif cmd == "channel" then ChannelCmd(rest)
    elseif cmd == "stats" then
        NS.Print(("Hidden this session: %d | all time: %d"):format(
            db.stats.hiddenSession, db.stats.hiddenTotal))
    elseif cmd == "clear" then
        VoxPopuliDB = NS.MergeDefaults({}, NS.defaults)
        NS.db = VoxPopuliDB
        NS.Print("All settings reset to defaults.")
    else
        NS.Print("Unknown command. /vox help")
    end
    if NS.RefreshPanel then NS.RefreshPanel() end
end
