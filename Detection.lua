-- VoxPopuli - Detection
-- Chat messages don't carry the sender's guild, so (like OlympusMute) we learn
-- guilds from players we encounter: targeting, mouseover, nameplates, groups,
-- and /who scans. Friendly guild rosters are learned via /vox scan.

local _, NS = ...

-- ---------------------------------------------------------------------------
-- Learning
-- ---------------------------------------------------------------------------

-- name: "Name" or "Name-Realm"; guild: string|nil; guid: string|nil
-- When a player is newly resolved as muted, their earlier visible lines are
-- purged from the chat frames (mirrors OlympusMute's PurgeHistory, inverted).
function NS.Learn(name, guild, guid)
    local db = NS.db
    if not db or not name or name == "" then return end
    local key = NS.NormalizeName(name)
    if not key then return end
    if guid and not NS.IsSecret(guid) then db.guids[guid] = key end

    local prev = db.known[key]
    if guild and guild ~= "" and not NS.IsSecret(guild) then
        db.known[key] = guild
    else
        -- Known to be guildless (distinct from never-seen).
        if db.known[key] ~= nil then db.known[key] = false end
    end

    if db.known[key] ~= prev then
        NS.Debug(("learned %s -> %s"):format(key, tostring(db.known[key])))
        if not NS.IsFriendly(key) then
            NS.PurgeHistory(key)
        end
        -- Identified while their invite was still open: decline it now.
        if NS.CheckPendingInvite then NS.CheckPendingInvite(key) end
    end
    if NS.RefreshPanel then NS.RefreshPanel() end
end

local function LearnFromUnit(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    if UnitIsUnit(unit, "player") then return end
    local guid = UnitGUID(unit)
    if NS.IsSecret(guid) then return end
    local name, realm
    if UnitFullName then name, realm = UnitFullName(unit) else name = UnitName(unit) end
    if not name or NS.IsSecret(name) then return end
    if realm and realm ~= "" and not NS.IsSecret(realm) then name = name .. "-" .. realm end
    local guild = GetGuildInfo(unit)
    if NS.IsSecret(guild) then return end
    NS.NoteLevel(UnitLevel(unit))
    NS.Learn(name, guild, guid)
end

local function SafeScan(unit) pcall(LearnFromUnit, unit) end

-- Shared with ChatFilter (tooltip learn-first) and the options panel.
NS.SafeScanUnit = SafeScan

-- ---------------------------------------------------------------------------
-- /who scanning (learn members of friendly guilds)
-- ---------------------------------------------------------------------------

NS.scanQueue = {}       -- auto-login chain (base queries only)
NS.scanQueries = nil    -- manual banded rotation (beats the 50-result cap)
NS.scanStep = 0
NS.pendingWho = nil
NS.maxSeenLevel = 0

-- Highest level seen on any scanned player; the banded rotation stops there
-- instead of pointlessly querying empty high-level bands.
function NS.NoteLevel(level)
    level = tonumber(level)
    if not level or level < 1 or level > 200 then return end
    if level > (NS.maxSeenLevel or 0) then
        NS.maxSeenLevel = level
        NS.scanQueries = nil
    end
end

-- Shift-clicking a name (or our own /who) can fire the same search several
-- times in a row. Let identical searches through once; drop repeats < 3s.
local lastWhoFilter, lastWhoTime = nil, 0
function NS.SendWho(filter)
    local now = GetTime()
    if filter == lastWhoFilter and now - lastWhoTime < 3 then
        NS.Debug("skipped repeat /who " .. tostring(filter))
        return
    end
    lastWhoFilter, lastWhoTime = filter, now
    NS.Debug("/who " .. tostring(filter))
    if C_FriendList and C_FriendList.SendWho then
        C_FriendList.SendWho(filter)
    elseif type(SendWho) == "function" then
        SendWho(filter)
    end
end

local function FriendlyGuildList()
    local t = {}
    for g in pairs(NS.db.friendlyGuilds) do t[#t + 1] = g end
    table.sort(t)
    return t
end

-- /who returns at most 50 matches, so one search can't cover a big roster.
-- Manual scans walk a rotation: every friendly guild, split into level bands
-- (wide bands low, single levels near the cap where most players sit).
local function BuildScanQueries()
    local cap = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    local seen = math.max(NS.maxSeenLevel or 0, UnitLevel("player") or 1)
    local maxLevel = math.min(cap, seen)
    local q = {}
    for _, gname in ipairs(FriendlyGuildList()) do
        local base = 'g-"' .. gname .. '"'
        q[#q + 1] = base
        local lo = 1
        while lo <= maxLevel - 4 do
            q[#q + 1] = ("%s %d-%d"):format(base, lo, lo + 3)
            lo = lo + 4
        end
        for lvl = lo, maxLevel do
            q[#q + 1] = ("%s %d-%d"):format(base, lvl, lvl)
        end
    end
    return q
end

-- step/total for the options panel's scan button label
function NS.GetScanProgress()
    return NS.scanStep, #(NS.scanQueries or {})
end

-- Manual scan (slash command): one step of the banded rotation per use.
function NS.ScanNext()
    NS.scanQueries = NS.scanQueries or BuildScanQueries()
    if #NS.scanQueries == 0 then
        NS.Print("Nothing to scan: no friendly guilds.")
        return
    end
    NS.scanStep = NS.scanStep % #NS.scanQueries + 1
    local query = NS.scanQueries[NS.scanStep]
    NS.pendingWho = query
    NS.autoScanning = false
    NS.SendWho(query)
    NS.Print(("scan %d/%d: /who %s"):format(NS.scanStep, #NS.scanQueries, query))
    if NS.UpdateScanButton then NS.UpdateScanButton() end
end

-- Automatic chain: walks every friendly guild's base roster once, spaced out
-- to respect the /who throttle. Kicks off on login (see Core.OnLogin).
-- (Base queries only — the deep banded rotation is for manual /vox scan.)
function NS.AutoScanChain()
    local db = NS.db
    if not db.toggles.autoscan then return end
    if #NS.scanQueue == 0 then
        for _, gname in ipairs(FriendlyGuildList()) do
            NS.scanQueue[#NS.scanQueue + 1] = 'g-"' .. gname .. '"'
        end
    end
    local query = table.remove(NS.scanQueue, 1)
    if not query then return end
    NS.pendingWho = query
    NS.autoScanning = true
    NS.SendWho(query)
    NS.Debug("auto-scan: " .. query)
end

-- Identify one player by name.
function NS.Identify(name)
    if not name or name == "" then
        NS.Print("Usage: /vox id <PlayerName>")
        return
    end
    NS.pendingWho = "id:" .. name
    NS.autoScanning = false
    NS.SendWho('n-"' .. name .. '"')
end

local function HandleWhoResults()
    local db = NS.db
    if not (C_FriendList and C_FriendList.GetNumWhoResults) then return end
    local n = C_FriendList.GetNumWhoResults()
    local learned = 0
    for i = 1, n do
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName and not NS.IsSecret(info.fullName) then
            local key = NS.NormalizeName(info.fullName)
            if key then
                NS.NoteLevel(info.level)
                local prev = db.known[key]
                if info.fullGuildName and info.fullGuildName ~= "" and not NS.IsSecret(info.fullGuildName) then
                    if prev ~= info.fullGuildName then learned = learned + 1 end
                    db.known[key] = info.fullGuildName
                elseif prev then
                    -- Was in a guild, now isn't: drop friendly status.
                    db.known[key] = false
                    learned = learned + 1
                end
                if db.known[key] ~= prev and not NS.IsFriendly(key) then
                    NS.PurgeHistory(key)
                end
            end
        end
    end
    if NS.pendingWho then
        NS.Print(("Who results: %d player(s), %d (re)identified."):format(n, learned))
        -- Continue the automatic login chain, spaced for the /who throttle.
        local chained = NS.autoScanning
        NS.pendingWho = nil
        NS.autoScanning = false
        if chained and #NS.scanQueue > 0 and NS.db.toggles.autoscan then
            C_Timer.After(8, NS.AutoScanChain)
        end
    end
end

-- ---------------------------------------------------------------------------
-- /who result lines printed straight to chat (Forever client)
-- ---------------------------------------------------------------------------
-- Shift-clicking a name runs /who, and small results print as a system line
-- with no reliable WHO_LIST_UPDATE on this client:
--   |Hplayer:Name|h[Name]|h: Level 20 Human Warrior <Guild> - Zone
-- Read the player link and <guild> straight from the line. A /who line starts
-- with a bare player link followed by "|h: "; normal chat links carry
-- ":lineID:CHANNEL" and never match, so players can't fake-learn by typing.
local function ParseWhoLine(msg)
    if type(msg) ~= "string" or NS.IsSecret(msg) then return end
    msg = msg:gsub("^|c%x%x%x%x%x%x%x%x", "")
    local name, rest = msg:match("^|Hplayer:([^:|]+)|h%[[^%]]*%]|h: (.*)$")
    if not name then return end
    local guild = rest:match("<([^<>]+)>")
    NS.NoteLevel(rest:match("(%d+)"))
    NS.Learn(name, guild)
end

local function HookChatFrames()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.AddMessage then
            hooksecurefunc(frame, "AddMessage", function(self, msg)
                pcall(ParseWhoLine, msg)
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Group warning
-- ---------------------------------------------------------------------------

local warned = {}

local function CheckGroup()
    local db = NS.db
    if not IsInGroup() then
        table.wipe(warned)
        return
    end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and GetNumGroupMembers() or 4
    local found = {}
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
            SafeScan(unit)
            local n, realm
            if UnitFullName then n, realm = UnitFullName(unit) else n = UnitName(unit) end
            if n and not NS.IsSecret(n) then
                local key = NS.NormalizeName((realm and realm ~= "") and (n .. "-" .. realm) or n)
                if key and not warned[key] then
                    warned[key] = true
                    if db.toggles.groupWarn and not NS.IsFriendly(key) then
                        local guild = db.known[key]
                        found[#found + 1] = ("%s%s"):format(n,
                            (guild and guild ~= false) and (" <" .. guild .. ">") or "")
                    end
                end
            end
        end
    end
    if #found == 0 then return end
    NS.Print("|cffff5555Heads up:|r your group has non-whitelisted players: "
        .. table.concat(found, ", ") .. ". Their chat is hidden.")
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
        RaidNotice_AddMessage(RaidWarningFrame,
            "VoxPopuli: non-whitelisted player in your group", ChatTypeInfo.RAID_WARNING)
    end
end

local function CheckGroupSoon()
    xpcall(CheckGroup, NS.ReportError)
    -- Guild info for new members can arrive a moment late; look again.
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            for i = 1, (IsInRaid() and GetNumGroupMembers() or 4) do
                SafeScan((IsInRaid() and "raid" or "party") .. i)
            end
            xpcall(CheckGroup, NS.ReportError)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("WHO_LIST_UPDATE")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:SetScript("OnEvent", function(self, event, arg1)
    if not NS.db then return end
    if event == "PLAYER_TARGET_CHANGED" then
        SafeScan("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        SafeScan("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        SafeScan(arg1)
    elseif event == "GROUP_ROSTER_UPDATE" then
        CheckGroupSoon()
    elseif event == "WHO_LIST_UPDATE" then
        xpcall(HandleWhoResults, NS.ReportError)
    elseif event == "CHAT_MSG_SYSTEM" then
        pcall(ParseWhoLine, arg1)
    end
end)

-- Watch chat frames directly too: on the Forever client small /who results
-- are written straight to the window with no CHAT_MSG_SYSTEM event.
-- (Hooked at login, once the chat frames exist.)
function NS.HookWhoLines()
    if NS._whoHooked then return end
    NS._whoHooked = true
    xpcall(HookChatFrames, NS.ReportError)
end
