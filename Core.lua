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

    -- Players whose chat insulted an allowed guild. Separate from hand blocks.
    haters = {},

    -- Your own guild, auto-whitelisted on login (removed if you leave it).
    autoGuild = nil,

    toggles = {
        enabled = true,
        -- When true, chat from players whose guild we haven't learned yet is
        -- hidden. When false, strangers show until identified (like
        -- OlympusMute's "first messages may appear" behavior, inverted).
        muteUnknown = true,
        -- When true, hide every player who is not on an allowed guild or the
        -- always-show list. When false, only manual blocks, chat insults,
        -- and anti-guilds are hidden. Everyone else stays visible.
        hideEveryone = false,
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
        -- Score chat locally and flag players who insult an allowed guild.
        sentiment = true,
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

-- Drawn textures, not SetBackdrop. This client was leaving the debug frame
-- as loose text with no visible panel.
function NS.PaintFrame(frame, r, g, b)
    local function plate(layer)
        local t = frame:CreateTexture(nil, layer)
        if t.SetColorTexture then
            t:SetColorTexture(1, 1, 1, 1)
        else
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            if not t:GetTexture() then
                t:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            end
        end
        return t
    end
    local bg = plate("BACKGROUND")
    bg:SetPoint("TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", 0, 0)
    bg:SetVertexColor(0.04, 0.05, 0.04, 0.96)

    r, g, b = r or 0.30, g or 0.78, b or 0.42
    local function bar(p1, p2, x1, y1, x2, y2, thickness, horizontal)
        local t = plate("BORDER")
        t:SetVertexColor(r, g, b, 1)
        t:SetPoint(p1, frame, p1, x1, y1)
        t:SetPoint(p2, frame, p2, x2, y2)
        if horizontal then t:SetHeight(thickness) else t:SetWidth(thickness) end
        return t
    end
    bar("TOPLEFT", "TOPRIGHT", 0, 0, 0, 0, 2, true)
    bar("BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, 0, 0, 2, true)
    bar("TOPLEFT", "BOTTOMLEFT", 0, 0, 0, 0, 2, false)
    bar("TOPRIGHT", "BOTTOMRIGHT", 0, 0, 0, 0, 2, false)

    local titleBg = plate("BORDER")
    titleBg:SetPoint("TOPLEFT", 2, -2)
    titleBg:SetPoint("TOPRIGHT", -2, -2)
    titleBg:SetHeight(24)
    titleBg:SetVertexColor(0.10, 0.16, 0.11, 1)
    return titleBg
end

function NS.Debug(msg)
    if not (NS.db and NS.db.toggles.debug) then return end
    if NS.DebugLine then
        NS.DebugLine(msg)
    else
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

-- Letters only, lowercased, with common digit lookalikes folded in.
-- Punctuation becomes a space so "OLY-MPUS" and "OLYMPUS I" compare cleanly.
local LEET = { ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t" }

function NS.Fold(s)
    if type(s) ~= "string" or NS.IsSecret(s) then return "" end
    s = s:lower()
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|", "")
    local buf = {}
    for i = 1, #s do
        local c = LEET[s:sub(i, i)] or s:sub(i, i)
        buf[#buf + 1] = c:match("%a") and c or " "
    end
    return (table.concat(buf):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Compact(s)
    return (s:gsub("%s+", ""))
end

local function Within(a, b, maxD)
    local n, m = #a, #b
    if math.abs(n - m) > maxD then return false end
    local prev = {}
    for j = 0, m do prev[j] = j end
    for i = 1, n do
        local cur = { [0] = i }
        local best = cur[0]
        local ca = a:sub(i, i)
        for j = 1, m do
            local cost = (ca == b:sub(j, j)) and 0 or 1
            local v = prev[j] + 1
            if cur[j - 1] + 1 < v then v = cur[j - 1] + 1 end
            if prev[j - 1] + cost < v then v = prev[j - 1] + cost end
            cur[j] = v
            if v < best then best = v end
        end
        if best > maxD then return false end
        prev = cur
    end
    return prev[m] <= maxD
end

-- True when needle appears in haystack, allowing extra words, spaces,
-- punctuation, digit lookalikes, and a typo or two on longer names.
function NS.FuzzyHas(haystack, needle)
    local n = NS.Fold(needle)
    if #n < NS.MIN_GUILD_LEN then return false end
    local h = NS.Fold(haystack)
    if h == "" then return false end
    if h:find(n, 1, true) then return true end
    local hc, nc = Compact(h), Compact(n)
    if hc:find(nc, 1, true) then return true end
    local maxD = 1
    if #nc >= 8 then maxD = 2
    elseif #nc < 5 then return false end
    local lo, hi = math.max(1, #nc - maxD), #nc + maxD
    local limit = #hc
    for i = 1, limit do
        for len = lo, hi do
            local last = i + len - 1
            if last > limit then break end
            if Within(hc:sub(i, last), nc, maxD) then return true end
        end
    end
    return false
end

local ANTI_TOKEN = {
    anti = true, against = true, hate = true, hater = true, haters = true,
    versus = true, enemy = true, enemies = true,
}

-- A name that resembles an allowed guild and is explicitly against it
-- ("Anti Olympus", "ANTI-OLYMPUS", "Olympus Haters") is not friendly.
function NS.IsAntiVariant(name)
    local db = NS.db
    if not db or type(name) ~= "string" then return false end
    local matched = false
    for stem in pairs(db.friendlyGuilds) do
        if NS.FuzzyHas(name, stem) then matched = true break end
    end
    if not matched then return false end
    for token in NS.Fold(name):gmatch("%S+") do
        if ANTI_TOKEN[token] or token:sub(1, 4) == "anti" then return true end
    end
    return false
end

function NS.IsFriendlyGuild(guildName)
    if not guildName or NS.IsAntiVariant(guildName) then return false end
    for friendly in pairs(NS.db.friendlyGuilds) do
        if NS.FuzzyHas(guildName, friendly) then return true end
    end
    return false
end

-- Hand blocklist, or an automatic anti-variant of an allowed guild.
function NS.IsHostileGuild(guildName)
    if not guildName then return false end
    if NS.IsAntiVariant(guildName) then return true end
    local key = tostring(guildName):lower()
    return NS.db.hostileGuilds[key] == true or NS.db.hostileGuilds[NS.Fold(guildName)] == true
end

-- Local insult check. The client cannot send chat to an outside model, so
-- this scores an allowed-guild mention against a hostile/friendly word list.
local NEG_WORD = {
    hate = true, hates = true, hated = true, hating = true,
    suck = true, sucks = true, sucked = true, sucking = true,
    trash = true, garbage = true, awful = true, terrible = true, worst = true,
    dumb = true, stupid = true, idiot = true, idiots = true, moron = true,
    loser = true, losers = true, pathetic = true, cringe = true, annoying = true,
    disgusting = true, useless = true, clown = true, clowns = true, joke = true,
    die = true, kill = true, kills = true, grief = true, griefer = true, griefers = true,
    dogshit = true, bullshit = true, shit = true, shitty = true,
    fuck = true, fucking = true, fucked = true,
    lame = true, nasty = true, bad = true,
}
local POS_WORD = {
    love = true, loves = true, loved = true, best = true, great = true, good = true,
    thanks = true, thank = true, welcome = true, nice = true, cool = true, based = true,
    win = true, wins = true, awesome = true, amazing = true, fun = true,
}
local NEGATE = { ["not"] = true, never = true, dont = true }

function NS.HostileAboutAllowed(msg)
    local db = NS.db
    if not db or type(msg) ~= "string" then return false end
    local stem
    for friendly in pairs(db.friendlyGuilds) do
        if NS.FuzzyHas(msg, friendly) then stem = NS.Fold(friendly) break end
    end
    if not stem then return false end
    local tokens = {}
    for tok in NS.Fold(msg):gmatch("%S+") do tokens[#tokens + 1] = tok end
    local idx
    for i, tok in ipairs(tokens) do
        if NS.FuzzyHas(tok, stem) or tok:find(Compact(stem), 1, true) then
            idx = i
            break
        end
    end
    local lo, hi = 1, #tokens
    if idx then
        lo = math.max(1, idx - 4)
        hi = math.min(#tokens, idx + 4)
    elseif #tokens > 14 then
        return false
    end
    local neg, pos, skip = 0, 0, false
    for i = lo, hi do
        if skip then
            skip = false
        else
            local w = tokens[i]
            local nxt = tokens[i + 1]
            if NEGATE[w] and nxt and POS_WORD[nxt] then
                neg = neg + 2
                skip = true
            elseif NEG_WORD[w] then
                neg = neg + 2
            elseif POS_WORD[w] then
                pos = pos + 2
            end
        end
    end
    if neg >= 2 and neg > pos then
        return true, stem
    end
    return false
end

-- Remember a player who insulted an allowed guild. Hand-allows and members
-- of an allowed guild are left alone.
function NS.NoteHater(name, guid, why)
    local db = NS.db
    if not db or type(name) ~= "string" then return end
    local key = NS.NormalizeName(name)
    if not key or db.allowedPlayers[key] then return end
    local me = UnitName("player")
    if me and not NS.IsSecret(me) and NS.NormalizeName(me) == key then return end
    local guild = db.known[key]
    if type(guild) == "string" and NS.IsFriendlyGuild(guild) then return end
    if guid and not NS.IsSecret(guid) then db.guids[guid] = key end
    if db.haters[key] then return end
    db.haters[key] = why or true
    NS.Debug("flagged " .. key .. " (" .. tostring(why) .. ")")
    NS.PurgeHistory(key)
    if NS.RefreshPanel then NS.RefreshPanel() end
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
-- Precedence: manual allow > manual block > chat flag > anti-guild.
-- If hideEveryone is on, anyone outside an allowed guild is hidden too.
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
    -- Shown only until the current party or raid ends. Not written to SavedVariables.
    if NS.sessionAllows and NS.sessionAllows[key] then return true end
    if db.blockedPlayers[key] then return false end
    if db.haters and db.haters[key] then return false end

    local guild = db.known[key]
    if type(guild) == "string" and guild ~= "" and NS.IsHostileGuild(guild) then
        return false
    end
    if not db.toggles.hideEveryone then
        return true
    end
    if guild == nil then
        return not db.toggles.muteUnknown
    end
    if guild == false or guild == "" then return false end
    return NS.IsFriendlyGuild(guild)
end

-- Why this player is on a real block list, ignoring the temporary group exception.
-- Nil for people who are merely outside the allow list.
NS.sessionAllows = {}
NS.sessionAsked = {}

function NS.BlacklistReason(key)
    local db = NS.db
    if not db or not key or db.allowedPlayers[key] then return nil end
    if db.blockedPlayers[key] then return "always hidden" end
    if db.haters and db.haters[key] then return "flagged from chat" end
    local guild = db.known[key]
    if type(guild) == "string" and guild ~= "" and NS.IsHostileGuild(guild) then
        return "anti-guild " .. guild
    end
    return nil
end

function NS.BumpHidden()
    local s = NS.db.stats
    s.hiddenSession = s.hiddenSession + 1
    s.hiddenTotal = s.hiddenTotal + 1
end

local function CountKeys(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

-- Saved-list breakdown for the options panel and the debug window.
-- Learned players are everyone the addon identified on its own.
-- The four lists are names you added by hand (plus your own guild).
function NS.CensusText()
    local db = NS.db
    if not db then return "" end
    local allowed, other, guildless = 0, 0, 0
    for _, guild in pairs(db.known) do
        if not guild or guild == "" then
            guildless = guildless + 1
        elseif NS.IsHostileGuild(guild) or not NS.IsFriendlyGuild(guild) then
            other = other + 1
        else
            allowed = allowed + 1
        end
    end
    local learned = allowed + other + guildless
    local own = db.autoGuild and " (includes your guild)" or ""
    return ("Hidden |cffffd100%d|r messages (%d this session)\n"
        .. "Allowed guilds: |cffffffff%d|r%s    Blocked guilds: |cffffffff%d|r\n"
        .. "Learned on its own: |cffffffff%d|r players"
        .. "  ·  allowed guild |cffffffff%d|r"
        .. "  ·  other guild |cffffffff%d|r"
        .. "  ·  no guild |cffffffff%d|r\n"
        .. "Added by hand: always shown |cffffffff%d|r  ·  always hidden |cffffffff%d|r\n"
        .. "Flagged from chat: |cffffffff%d|r"):format(
        db.stats.hiddenTotal or 0, db.stats.hiddenSession or 0,
        CountKeys(db.friendlyGuilds), own, CountKeys(db.hostileGuilds),
        learned, allowed, other, guildless,
        CountKeys(db.allowedPlayers), CountKeys(db.blockedPlayers),
        CountKeys(db.haters))
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
    NS.Print(("loaded. %d allowed guild(s). %s. /vox help"):format(
        n, db.toggles.hideEveryone
            and "Hiding everyone except allowed guilds and players"
            or "Hiding only anti-guilds and hostile chat"))

    -- Watch chat frames for /who result lines (the Forever client prints small
    -- /who results straight to the window with no reliable WHO_LIST_UPDATE).
    if NS.HookWhoLines then xpcall(NS.HookWhoLines, NS.ReportError) end

    -- SendWho() is protected here, so login cannot run /who by itself.
    -- Arm the Scan button (a secure "/who" macro) and tell the player.
    if db.toggles.autoscan and NS.ArmScanButton then
        NS.ArmScanButton()
        NS.Print("Addons can't call /who on this client. Click Scan /who, or type /vox scan and press Enter.")
    end

    if db.toggles.debug and NS.SetDebug then
        NS.SetDebug(true)
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
