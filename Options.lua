-- VoxPopuli - Options
-- In-game settings panel (Interface > AddOns > VoxPopuli, or /vox).

local _, NS = ...

local panel = CreateFrame("Frame")
panel.name = "VoxPopuli"
NS.optionsPanel = panel

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("VoxPopuli")

local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
desc:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
desc:SetJustifyH("LEFT")
desc:SetText("The inverse of a mute list: EVERYONE is muted except whitelisted "
    .. "(\"friendly\") guilds and players. Only affects your screen; nothing is added "
    .. "to your ignore list. Players are learned when you target, mouse over, group "
    .. "with, or see their nameplate, from /who results, or when you shift-click "
    .. "their name in chat.")

-- Stats line: the first thing you see when opening the panel.
local statsText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
statsText:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
statsText:SetJustifyH("LEFT")

local function CheckLabel(check, text)
    local label = check.Text or check.text or check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:ClearAllPoints()
    label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    label:SetText(text)
end

local function OnOff(v) return v and "|cff33ff99ON|r" or "|cffff3333OFF|r" end

local function MakeCheck(text, anchor, get, set, dx, dy)
    local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    if dx then
        c:SetPoint("LEFT", anchor, "LEFT", dx, dy or 0)
    else
        c:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    CheckLabel(c, text)
    c:SetScript("OnClick", function(self)
        set(self:GetChecked())
        NS.Print(text .. " " .. OnOff(get()))
        NS.RefreshPanel()
    end)
    c._get = get
    return c
end

local t = function() return NS.db and NS.db.toggles end
local function T(key) return function() return t() and t()[key] end end
local function S(key, after) return function(v)
    t()[key] = v and true or false
    if after then after() end
end end

local checks = {}
local enable = MakeCheck("Enable filtering", statsText,
    function() return t() and t().enabled end, S("enabled"))
checks[#checks + 1] = enable
checks[#checks + 1] = MakeCheck("Mute players whose guild is unknown", enable, T("muteUnknown"), S("muteUnknown"))
checks[#checks + 1] = MakeCheck("Auto-scan friendly rosters via /who after login", checks[#checks], T("autoscan"), S("autoscan"))
local declineGuild = MakeCheck("Auto-decline guild invites from non-whitelisted", checks[#checks], T("declineGuildInvite"), S("declineGuildInvite"))
checks[#checks + 1] = declineGuild
local declineGroup = MakeCheck("Auto-decline group invites from non-whitelisted", declineGuild, T("declineGroupInvite"), S("declineGroupInvite"))
checks[#checks + 1] = declineGroup
local declineDuel = MakeCheck("Auto-decline duels", declineGroup, T("declineDuel"), S("declineDuel"))
checks[#checks + 1] = declineDuel
local declineTrade = MakeCheck("Auto-decline trades", declineDuel, T("declineTrade"), S("declineTrade"), 240, 0)
checks[#checks + 1] = declineTrade
local groupWarn = MakeCheck("Warn me when a non-whitelisted player is in my group", declineDuel, T("groupWarn"), S("groupWarn"))
checks[#checks + 1] = groupWarn
checks[#checks + 1] = MakeCheck("Hide their chat bubbles (open world only)", groupWarn, T("bubbles"),
    S("bubbles", function() if not t().bubbles and NS.ResetBubbles then NS.ResetBubbles() end end))
checks[#checks + 1] = MakeCheck("Debug output (/vox debug)", checks[#checks], T("debug"), S("debug"))

local function MakeButton(text, width, onClick, anchor, x, y)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetPoint("TOPLEFT", anchor, x and "TOPRIGHT" or "BOTTOMLEFT", x or 0, y or 0)
    b:SetScript("OnClick", onClick)
    return b
end

local function MakeEditBox(anchor)
    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(180, 20)
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, -6)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    return box
end

local function SectionLabel(anchor, text)
    local l = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, -10)
    l:SetText(text)
    return l
end

local lastCheck = checks[#checks]

-- Friendly guilds ------------------------------------------------------------
local gLabel = SectionLabel(lastCheck, "Friendly guilds (matches any part of the name):")
local gBox = MakeEditBox(gLabel)
local function GuildAction(fn)
    return function()
        fn(gBox:GetText())
        gBox:SetText("")
        gBox:ClearFocus()
        NS.RefreshPanel()
    end
end
gBox:SetScript("OnEnterPressed", GuildAction(function(text)
    text = strtrim(text or "")
    if text == "" then return end
    local key = text:lower()
    if #key < NS.MIN_GUILD_LEN then
        NS.Print(("Guild names need at least %d letters."):format(NS.MIN_GUILD_LEN))
        return
    end
    NS.db.friendlyGuilds[key] = true
    NS.scanQueries = nil
    NS.Print('Guild "' .. text .. '" added to whitelist (partial match).')
end))
local gAdd = MakeButton("Add guild", 90, nil, gBox, 8, 2)
gAdd:SetScript("OnClick", GuildAction(function(text)
    text = strtrim(text or "")
    if text == "" then return end
    local key = text:lower()
    if #key < NS.MIN_GUILD_LEN then
        NS.Print(("Guild names need at least %d letters."):format(NS.MIN_GUILD_LEN))
        return
    end
    NS.db.friendlyGuilds[key] = true
    NS.scanQueries = nil
    NS.Print('Guild "' .. text .. '" added to whitelist (partial match).')
end))
MakeButton("Remove guild", 110, GuildAction(function(text)
    text = strtrim(text or "")
    if text == "" then return end
    NS.db.friendlyGuilds[text:lower()] = nil
    NS.scanQueries = nil
    NS.Print('Guild "' .. text .. '" removed from whitelist.')
end), gAdd, 8, 0)

local gText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
gText:SetPoint("TOPLEFT", gBox, "BOTTOMLEFT", -6, -8)
gText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
gText:SetJustifyH("LEFT")

-- Blocklist ------------------------------------------------------------------
local bLabel = SectionLabel(gText, "Blocklisted guilds (exact name, always muted):")
local bBox = MakeEditBox(bLabel)
local function BlockAction(fn)
    return function()
        fn(bBox:GetText())
        bBox:SetText("")
        bBox:ClearFocus()
        NS.RefreshPanel()
    end
end
bBox:SetScript("OnEnterPressed", BlockAction(function(text)
    text = strtrim(text or "")
    if text == "" then return end
    NS.db.hostileGuilds[text:lower()] = true
    NS.Print('Guild "' .. text .. '" blocklisted (exact match).')
end))
local bAdd = MakeButton("Block guild", 100, nil, bBox, 8, 2)
bAdd:SetScript("OnClick", BlockAction(function(text)
    text = strtrim(text or "")
    if text == "" then return end
    NS.db.hostileGuilds[text:lower()] = true
    NS.Print('Guild "' .. text .. '" blocklisted (exact match).')
end))
MakeButton("Unblock guild", 110, BlockAction(function(text)
    text = strtrim(text or "")
    if text == "" then return end
    NS.db.hostileGuilds[text:lower()] = nil
    NS.Print('Guild "' .. text .. '" removed from blocklist.')
end), bAdd, 8, 0)

local bText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
bText:SetPoint("TOPLEFT", bBox, "BOTTOMLEFT", -6, -8)
bText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
bText:SetJustifyH("LEFT")

-- Scan button ------------------------------------------------------------------
local scanBtn = MakeButton("Scan /who", 200, function() NS.ScanNext() end, bText, nil, -10)
function NS.UpdateScanButton()
    local step, total = NS.GetScanProgress()
    if total == 0 then scanBtn:SetText("Scan /who") return end
    scanBtn:SetText(("Scan /who (%d/%d)"):format(step % total + 1, total))
end

-- Player overrides -------------------------------------------------------------
local pLabel = SectionLabel(scanBtn, "Player overrides (Name or Name-Realm):")
local pBox = MakeEditBox(pLabel)
local function PlayerAction(fn)
    return function()
        fn(pBox:GetText())
        pBox:SetText("")
        pBox:ClearFocus()
        NS.RefreshPanel()
    end
end
pBox:SetScript("OnEnterPressed", PlayerAction(function() end))
local pAllow = MakeButton("Never mute", 100, nil, pBox, 8, 2)
pAllow:SetScript("OnClick", PlayerAction(function(text)
    local key = NS.NormalizeName(strtrim(text or ""))
    if not key then return end
    NS.db.allowedPlayers[key] = true
    NS.db.blockedPlayers[key] = nil
    NS.Print(text .. " will never be muted.")
end))
local pBlock = MakeButton("Always mute", 100, nil, pAllow, 8, 0)
pBlock:SetScript("OnClick", PlayerAction(function(text)
    local key = NS.NormalizeName(strtrim(text or ""))
    if not key then return end
    NS.db.blockedPlayers[key] = true
    NS.db.allowedPlayers[key] = nil
    NS.PurgeHistory(key)
    NS.Print(text .. " will always be muted.")
end))

local pText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
pText:SetPoint("TOPLEFT", pBox, "BOTTOMLEFT", -6, -8)
pText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
pText:SetJustifyH("LEFT")

-- Refresh ----------------------------------------------------------------------

local function SortedKeys(set)
    local items = {}
    for k in pairs(set) do items[#items + 1] = k end
    table.sort(items)
    return items
end

function NS.RefreshPanel()
    local db = NS.db
    if not db or not panel:IsShown() then return end
    for _, c in ipairs(checks) do
        if c._get then c:SetChecked(c._get()) end
    end
    local g = SortedKeys(db.friendlyGuilds)
    gText:SetText("Whitelisted: |cffffffff"
        .. (#g > 0 and table.concat(g, ", ") or "(none)") .. "|r")
    local b = SortedKeys(db.hostileGuilds)
    bText:SetText("Blocklisted: |cffffffff"
        .. (#b > 0 and table.concat(b, ", ") or "(none)") .. "|r")
    NS.UpdateScanButton()
    local a = SortedKeys(db.allowedPlayers)
    local m = SortedKeys(db.blockedPlayers)
    local parts = {}
    if #a > 0 then parts[#parts + 1] = "|cff66ff66Never muted:|r " .. table.concat(a, ", ") end
    if #m > 0 then parts[#parts + 1] = "|cffff6666Always muted:|r " .. table.concat(m, ", ") end
    pText:SetText(#parts > 0 and table.concat(parts, "\n") or "|cff999999No player overrides.|r")
    local n = 0
    for _ in pairs(db.known) do n = n + 1 end
    statsText:SetText(("Hidden |cffffd100%d|r messages (%d this session)  ·  |cffffd100%d|r players learned"):format(
        db.stats.hiddenTotal or 0, db.stats.hiddenSession or 0, n))
end
panel:SetScript("OnShow", NS.RefreshPanel)

function NS.OpenOptions()
    if Settings and Settings.OpenToCategory and NS.optionsCategory then
        local cat = NS.optionsCategory
        Settings.OpenToCategory(cat.GetID and cat:GetID() or cat.ID)
    elseif InterfaceOptionsFrame_OpenToCategory and panel then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel) -- old client quirk: needs two calls
    end
end

if Settings and Settings.RegisterCanvasLayoutCategory then
    NS.optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(NS.optionsCategory)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end
