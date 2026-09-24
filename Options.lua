-- VoxPopuli - Options
-- In-game settings panel (Interface > AddOns > VoxPopuli, or /vox).

local _, NS = ...

local panel = CreateFrame("Frame")
panel.name = "VoxPopuli"
NS.optionsPanel = panel

-- The settings canvas does not scroll on its own. Everything below lives in
-- a scroll child so the guild and player editors stay reachable.
local scroll = CreateFrame("ScrollFrame", "VoxPopuliOptionsScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", -28, 0)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(480, 900)
scroll:SetScrollChild(content)

local function OnWheel(_, delta)
    local range = scroll:GetVerticalScrollRange() or 0
    local nextScroll = scroll:GetVerticalScroll() - delta * 36
    if nextScroll < 0 then nextScroll = 0 end
    if nextScroll > range then nextScroll = range end
    scroll:SetVerticalScroll(nextScroll)
end
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", OnWheel)

local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("VoxPopuli")

local viewBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
viewBtn:SetSize(110, 22)
viewBtn:SetPoint("TOPRIGHT", -8, -12)
viewBtn:SetText("View lists")
viewBtn:SetScript("OnClick", function()
    if NS.OpenLists then NS.OpenLists() end
end)

local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
desc:SetPoint("RIGHT", content, "RIGHT", -16, 0)
desc:SetJustifyH("LEFT")
desc:SetText("Shows chat and invites only from guilds and players you choose. "
    .. "Everyone else is hidden. This only changes what you see: nothing is added "
    .. "to your ignore list, and other players are not notified.")

-- Stats line: the first thing you see when opening the panel.
local statsText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
statsText:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
statsText:SetPoint("RIGHT", content, "RIGHT", -16, 0)
statsText:SetJustifyH("LEFT")
statsText:SetText("Hidden 0 messages\nAllowed guilds: 0\nLearned on its own: 0 players\nAdded by hand: 0")

local function CheckLabel(check, text)
    local label = check.Text or check.text or check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:ClearAllPoints()
    label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    label:SetText(text)
end

local function OnOff(v) return v and "|cff33ff99ON|r" or "|cffff3333OFF|r" end

local function MakeCheck(text, anchor, get, set, dx, dy)
    local c = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
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
checks[#checks + 1] = MakeCheck("Hide everyone except allowed guilds and players", enable, T("hideEveryone"), S("hideEveryone"))
checks[#checks + 1] = MakeCheck("When that is on, also hide players whose guild is unknown", checks[#checks], T("muteUnknown"), S("muteUnknown"))
checks[#checks + 1] = MakeCheck("Flag chat that insults an allowed guild", checks[#checks], T("sentiment"), S("sentiment"))
checks[#checks + 1] = MakeCheck("On login, remind me to /who friendly rosters", checks[#checks], T("autoscan"), S("autoscan"))
local declineGuild = MakeCheck("Auto-decline guild invites from hidden players", checks[#checks], T("declineGuildInvite"), S("declineGuildInvite"))
checks[#checks + 1] = declineGuild
local declineGroup = MakeCheck("Auto-decline group invites from non-whitelisted", declineGuild, T("declineGroupInvite"), S("declineGroupInvite"))
checks[#checks + 1] = declineGroup
local declineDuel = MakeCheck("Auto-decline duels", declineGroup, T("declineDuel"), S("declineDuel"))
checks[#checks + 1] = declineDuel
local declineTrade = MakeCheck("Auto-decline trades", declineDuel, T("declineTrade"), S("declineTrade"), 240, 0)
checks[#checks + 1] = declineTrade
local groupWarn = MakeCheck("Warn me when a hidden player is in my group", declineDuel, T("groupWarn"), S("groupWarn"))
checks[#checks + 1] = groupWarn
checks[#checks + 1] = MakeCheck("Hide their chat bubbles (open world only)", groupWarn, T("bubbles"),
    S("bubbles", function() if not t().bubbles and NS.ResetBubbles then NS.ResetBubbles() end end))
checks[#checks + 1] = MakeCheck("Debug window (/vox debug)", checks[#checks], T("debug"), S("debug", function()
    if NS.SetDebug then NS.SetDebug(t().debug) end
end))

local function MakeButton(text, width, onClick, anchor, x, y)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetPoint("TOPLEFT", anchor, x and "TOPRIGHT" or "BOTTOMLEFT", x or 0, y or 0)
    b:SetScript("OnClick", onClick)
    return b
end

local function MakeEditBox(anchor)
    local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    box:SetSize(180, 20)
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, -6)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    return box
end

local function SectionLabel(anchor, text)
    local l = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, -10)
    l:SetText(text)
    return l
end

local lastCheck = checks[#checks]

-- Friendly guilds ------------------------------------------------------------
local gLabel = SectionLabel(lastCheck, "Allowed guilds (fuzzy; anti-names are blocked):")
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
    NS.InvalidateScan()
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
    NS.InvalidateScan()
    NS.Print('Guild "' .. text .. '" added to whitelist (partial match).')
end))
MakeButton("Remove guild", 110, GuildAction(function(text)
    text = strtrim(text or "")
    if text == "" then return end
    NS.db.friendlyGuilds[text:lower()] = nil
    NS.InvalidateScan()
    NS.Print('Guild "' .. text .. '" removed from whitelist.')
end), gAdd, 8, 0)

local gText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
gText:SetPoint("TOPLEFT", gBox, "BOTTOMLEFT", -6, -8)
gText:SetPoint("RIGHT", content, "RIGHT", -16, 0)
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

local bText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
bText:SetPoint("TOPLEFT", bBox, "BOTTOMLEFT", -6, -8)
bText:SetPoint("RIGHT", content, "RIGHT", -16, 0)
bText:SetJustifyH("LEFT")

-- Scan button ------------------------------------------------------------------
-- A secure button cannot be anchored to this panel ("Cannot anchor protected
-- frames to regions"), so the panel keeps a plain spacer and the real button
-- is parented to UIParent and moved to the spacer's screen position.
-- The secure click runs /who. HookScript, not SetScript: replacing OnClick
-- taints the button and the macro will not run.
local scanAnchor = CreateFrame("Frame", nil, content)
scanAnchor:SetSize(200, 24)
scanAnchor:SetPoint("TOPLEFT", bText, "BOTTOMLEFT", 0, -10)

local secureOk, scanBtn = pcall(CreateFrame, "Button", "VoxPopuliScanButton", UIParent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
if secureOk then
    scanBtn:SetAttribute("type", "macro")
    scanBtn:SetAttribute("macrotext", "")
    scanBtn:RegisterForClicks("LeftButtonUp")
    scanBtn:SetFrameStrata("FULLSCREEN_DIALOG")
    scanBtn:SetFrameLevel(200)
    scanBtn:Hide()
    scanBtn:HookScript("PostClick", function()
        if NS.OnScanClicked then NS.OnScanClicked() end
    end)
    local lastX, lastY, lastW, lastH
    local function PlaceScanButton()
        if InCombatLockdown and InCombatLockdown() then return end
        if not panel:IsVisible() then
            lastX = nil
            if scanBtn:IsShown() then scanBtn:Hide() end
            return
        end
        local left, bottom = scanAnchor:GetLeft(), scanAnchor:GetBottom()
        local uiScale = UIParent:GetEffectiveScale()
        if not left or not bottom or not uiScale or uiScale == 0 then return end
        -- The button lives on UIParent, so hide it when the spacer scrolls
        -- out of the visible settings page.
        local sTop, sBot = scroll:GetTop(), scroll:GetBottom()
        local aTop = scanAnchor:GetTop()
        if sTop and sBot and aTop and (aTop > sTop + 1 or bottom < sBot - 1) then
            lastX = nil
            if scanBtn:IsShown() then scanBtn:Hide() end
            return
        end
        local scale = scanAnchor:GetEffectiveScale() / uiScale
        local function snap(v) return math.floor(v * 2 + 0.5) / 2 end
        local x, y = snap(left * scale), snap(bottom * scale)
        local w, h = snap(scanAnchor:GetWidth() * scale), snap(scanAnchor:GetHeight() * scale)
        if x == lastX and y == lastY and w == lastW and h == lastH and scanBtn:IsShown() then return end
        lastX, lastY, lastW, lastH = x, y, w, h
        scanBtn:ClearAllPoints()
        scanBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        scanBtn:SetSize(w, h)
        scanBtn:Show()
    end
    scanAnchor:SetScript("OnShow", PlaceScanButton)
    scanAnchor:SetScript("OnHide", function()
        lastX = nil
        if not (InCombatLockdown and InCombatLockdown()) and scanBtn:IsShown() then
            scanBtn:Hide()
        end
    end)
    scanAnchor:SetScript("OnUpdate", function()
        if panel:IsShown() then PlaceScanButton() end
    end)
else
    scanBtn = CreateFrame("Button", "VoxPopuliScanButton", scanAnchor, "UIPanelButtonTemplate")
    scanBtn:SetAllPoints(scanAnchor)
    scanBtn:SetScript("OnClick", function() NS.ScanNext() end)
end
scanBtn:SetText("Scan /who")
NS.scanButton = scanBtn
function NS.UpdateScanButton()
    local step, total = NS.GetScanProgress()
    if total == 0 then scanBtn:SetText("Scan /who") return end
    scanBtn:SetText(("Scan /who (%d/%d)"):format(step % total + 1, total))
end

-- Player overrides -------------------------------------------------------------
local pLabel = SectionLabel(scanAnchor, "Player overrides (Name or Name-Realm):")
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

local pText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
pText:SetPoint("TOPLEFT", pBox, "BOTTOMLEFT", -6, -8)
pText:SetPoint("RIGHT", content, "RIGHT", -16, 0)
pText:SetJustifyH("LEFT")

local footer = CreateFrame("Frame", nil, content)
footer:SetPoint("TOPLEFT", pText, "BOTTOMLEFT", 0, -24)
footer:SetSize(1, 1)

local function LayoutScroll()
    local width = scroll:GetWidth()
    if width and width > 40 then
        content:SetWidth(width)
    end
    local top, foot = content:GetTop(), footer:GetBottom()
    if top and foot then
        content:SetHeight((top - foot) + 16)
    end
end
NS.LayoutOptions = LayoutScroll
scroll:HookScript("OnSizeChanged", function()
    LayoutScroll()
end)

local function HookWheel(frame)
    if not frame or frame.__voxWheel then return end
    frame.__voxWheel = true
    frame:EnableMouseWheel(true)
    frame:HookScript("OnMouseWheel", OnWheel)
end
HookWheel(content)
HookWheel(panel)
for _, child in ipairs({ content:GetChildren() }) do
    HookWheel(child)
end

-- Refresh ----------------------------------------------------------------------

local function SortedKeys(set)
    local items = {}
    for k in pairs(set) do items[#items + 1] = k end
    table.sort(items)
    return items
end

function NS.RefreshPanel()
    local db = NS.db
    if NS.RefreshLists then NS.RefreshLists() end
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
    if NS.CensusText then statsText:SetText(NS.CensusText()) end
    LayoutScroll()
end
panel:SetScript("OnShow", function()
    NS.RefreshPanel()
    LayoutScroll()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, LayoutScroll)
    end
end)

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
