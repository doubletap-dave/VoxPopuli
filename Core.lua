-- VoxPopuli - Core
-- The exact inverse of OlympusMute: instead of muting chosen guilds, mute
-- EVERYONE except whitelisted ("friendly") guilds and players.

local ADDON_NAME, NS = ...

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

NS.defaults = {
    -- Guild name fragments that are never muted (case-insensitive, partial
    -- match, same as OlympusMute). "Olympus" is preseeded per the request:
    -- everyone BUT Olympus (and other friendlies) gets muted.
    friendlyGuilds = { ["olympus"] = true },
    -- Exact-match guild blocklist (inverse of OlympusMute 1.0.8's exact
    -- whitelist): these guilds are ALWAYS muted, even if they partially
    -- match a friendly pattern (e.g. "Anti Olympus").
    hostileGuilds = {},

    -- Explicit per-player overrides. allowedPlayers wins over everything;
    -- blockedPlayers wins over friendly guilds. Keys are "name-realm".
    allowedPlayers = {},   -- ["name-realm"] = true  (never mute)
    blockedPlayers = {},   -- ["name-realm"] = true  (always mute)

    -- GUID -> "name-realm", for players identified via units (stable across
    -- renames and cheaper than name matching in the chat filter).
    guids = {},

    -- Learned data: ["name-realm"] = "Guild Name", or false if known guildless.
    known = {},

    -- Your own guild, auto-whitelisted on login (removed if you leave it).
    autoGuild = nil,

    toggles = {
        enabled = true,
        -- When true, chat from players whose guild we haven't learned yet is
        -- hidden. When false, strangers show until identified (like
        -- OlympusMute's "first messages may appear" behavior, inverted).
        muteUnknown = true,
        -- Automatically scan friendly guild rosters via /who shortly after
        -- login, so whitelisted players are recognized with zero setup.
        autoscan = true,
        bubbles = true,          -- hide chat bubbles of muted players
        groupWarn = true,        -- warn when grouped with non-whitelisted
        declineGuildInvite = true,
        declineGroupInvite = false,
        declineDuel = false,
        declineTrade = false,
        debug = false,           -- extra troubleshooting output (/vox debug)
        channels = {
            SAY = true, YELL = true, EMOTE = true,
            WHISPER = true, CHANNEL = true, GUILD = true,
            PARTY = true, RAID = true, INSTANCE = true,
        },
    },

    stats = { hiddenSession = 0, hiddenTotal = 0 },
}

-- ---------------------------------------------------------------------------
-- SavedVariables + helpers
-- ---------------------------------------------------------------------------

function NS.MergeDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            NS.MergeDefaults(db[k], v)
        elseif db[k] == nil then
            db[k] = v
        end
    end
    return db
end

function NS.Print(msg)
    print("|cff33ff99VoxPopuli|r: " .. tostring(msg))
end

function NS.Debug(msg)
    if NS.db and NS.db.toggles.debug then
        print("|cff33ff99VoxPopuli|r |cff999999debug:|r " .. tostring(msg))
    end
end

function NS.ReportError(err)
    NS.Print("|cffff4444error:|r " .. tostring(err))
end

-- The Forever client is a retail fork: the secret-values system is active.
-- Never compare or format values from unit/cast APIs in combat without this.
function NS.IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Minimum guild-name fragment length (stops "a" from matching half the server).
NS.MIN_GUILD_LEN = 3

-- "Name" or "Name-Realm" -> "name-realm" (lowercased, realm-suffixed, so
-- cross-realm players with the same name don't collide).
function NS.NormalizeName(name)
    if type(name) ~= "string" or name == "" or NS.IsSecret(name) then return nil end
    if not name:find("-", 1, true) then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if realm and not NS.IsSecret(realm) then name = name .. "-" .. realm end
    end
    return name:lower()
end

function NS.IsFriendlyGuild(guildName)
    if not guildName then return false end
    local g = tostring(guildName):lower()
    for friendly in pairs(NS.db.friendlyGuilds) do
        if g:find(tostring(friendly):lower(), 1, true) then
            return true
        end
    end
    return false
end

-- Exact, case-insensitive match against the blocklist.
function NS.IsHostileGuild(guildName)
    if not guildName then return false end
    return NS.db.hostileGuilds[tostring(guildName):lower()] == true
end

-- Remove chat lines already printed by a player we just resolved as muted.
-- Player links look like |Hplayer:Name-Realm:...|h, so match on the short name
-- with both "-" (Name-Realm) and ":" (bare Name) separators.
function NS.PurgeHistory(name)
    local short = type(name) == "string" and name:match("^[^-]+")
    if not short then return end
    local a, b = "|Hplayer:" .. short .. "-", "|Hplayer:" .. short .. ":"
    local function predicate(msg)
        if type(msg) == "table" then msg = msg.message end
        if type(msg) ~= "string" or NS.IsSecret(msg) then return false end
        return msg:find(a, 1, true) ~= nil or msg:find(b, 1, true) ~= nil
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.RemoveMessagesByPredicate then
            pcall(frame.RemoveMessagesByPredicate, frame, predicate)
        end
    end
end

-- The core question: should this author's chat be shown?
-- Precedence: manual allow > manual block > exact guild blocklist >
-- partial guild whitelist > mute-unknowns setting.
function NS.IsFriendly(author, guid)
    local db = NS.db
    if not db or not db.toggles.enabled then return true end

    local key = nil
    if guid and not NS.IsSecret(guid) then key = db.guids[guid] end
    if not key then
        if not author or author == "" or NS.IsSecret(author) then return true end
        key = NS.NormalizeName(author)
        if not key then return true end
    end

    local me = UnitName("player")
    if me and not NS.IsSecret(me) then
        local meKey = NS.NormalizeName(me)
        if meKey and key == meKey then return true end  -- never hide yourself
    end

    if db.allowedPlayers[key] then return true end
    if db.blockedPlayers[key] then return false end

    local guild = db.known[key]
    if guild == nil then
        return not db.toggles.muteUnknown  -- stranger: show only if not muting unknowns
    end
    if guild == false then return false end  -- known guildless: not friendly
    if NS.IsHostileGuild(guild) then return false end  -- exact blocklist beats partial whitelist
    return NS.IsFriendlyGuild(guild)
end

function NS.BumpHidden()
    local s = NS.db.stats
    s.hiddenSession = s.hiddenSession + 1
    s.hiddenTotal = s.hiddenTotal + 1
end

-- One-time migration: player keys used to be short names ("name"); they're
-- now "name-realm" so cross-realm players can't collide. Re-key once.
function NS.MigrateKeys(db)
    if db.keyVersion == 2 then return end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and not NS.IsSecret(realm) then
        realm = realm:lower()
        for _, set in ipairs({ db.known, db.allowedPlayers, db.blockedPlayers }) do
            if type(set) == "table" then
                local add, drop = {}, {}
                for k, v in pairs(set) do
                    if type(k) == "string" and not k:find("-", 1, true) then
                        add[k .. "-" .. realm] = v
                        drop[#drop + 1] = k
                    end
                end
                for k, v in pairs(add) do set[k] = v end
                for _, k in ipairs(drop) do set[k] = nil end
            end
        end
    end
    db.keyVersion = 2
end

-- ---------------------------------------------------------------------------
-- Login
-- ---------------------------------------------------------------------------

function NS.OnLogin()
    local db = NS.db
    db.stats.hiddenSession = 0

    -- Your own guild is friendly by definition.
    if IsInGuild() then
        local guild = GetGuildInfo("player")
        if guild then
            local key = guild:lower()
            if db.autoGuild and db.autoGuild ~= key then
                db.friendlyGuilds[db.autoGuild] = nil
            end
            db.autoGuild = key
            db.friendlyGuilds[key] = true
        end
    elseif db.autoGuild then
        db.friendlyGuilds[db.autoGuild] = nil
        db.autoGuild = nil
    end

    local n = 0
    for _ in pairs(db.friendlyGuilds) do n = n + 1 end
    NS.Print(("loaded. %d friendly guild(s), unknowns are %s. /vox help"):format(
        n, db.toggles.muteUnknown and "MUTED" or "shown"))

    -- Watch chat frames for /who result lines (the Forever client prints small
    -- /who results straight to the window with no reliable WHO_LIST_UPDATE).
    if NS.HookWhoLines then xpcall(NS.HookWhoLines, NS.ReportError) end

    -- Preemptive: learn friendly rosters on our own after things settle.
    if db.toggles.autoscan then
        C_Timer.After(15, function()
            if NS.db.toggles.autoscan then NS.AutoScanChain() end
        end)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        VoxPopuliDB = VoxPopuliDB or {}
        NS.db = NS.MergeDefaults(VoxPopuliDB, NS.defaults)
        VoxPopuliDB = NS.db
        NS.MigrateKeys(NS.db)
    elseif event == "PLAYER_LOGIN" then
        NS.OnLogin()
    end
end)
