-- VoxPopuli - Saved lists
-- Sortable view of learned players, guilds seen, hand lists, and chat flags.

local _, NS = ...

local ROW_H = 18
local frame, scroll, child, searchBox, emptyText, headerButtons
local rows = {}
local view = "players"
local sortKey = "name"
local sortAsc = true
local built = {}

local TABS = {
    { id = "players", label = "Players" },
    { id = "guilds", label = "Guilds" },
    { id = "allowed", label = "Allowed" },
    { id = "blocked", label = "Blocked" },
    { id = "flagged", label = "Flagged" },
}

local COLUMNS = {
    players = {
        { key = "name", label = "Player", width = 180 },
        { key = "guild", label = "Guild", width = 170 },
        { key = "status", label = "Status", width = 150 },
    },
    guilds = {
        { key = "name", label = "Guild", width = 250 },
        { key = "count", label = "Players", width = 80 },
        { key = "status", label = "Standing", width = 160 },
    },
    allowed = {
        { key = "name", label = "Allowed name", width = 280 },
        { key = "status", label = "Match", width = 180 },
    },
    blocked = {
        { key = "name", label = "Blocked name", width = 280 },
        { key = "status", label = "Match", width = 180 },
    },
    flagged = {
        { key = "name", label = "Player", width = 200 },
        { key = "status", label = "Why", width = 280 },
    },
}

local function GuildText(guild)
    if type(guild) == "string" and guild ~= "" then return guild end
    return ""
end

local function PlayerStatus(db, key, guild)
    if db.allowedPlayers[key] then return "Always shown" end
    if NS.IsOffensiveName and NS.IsOffensiveName(key) then return "Offensive name" end
    if db.blockedPlayers[key] then return "Always hidden" end
    if db.haters and db.haters[key] then return "Flagged from chat" end
    if not guild or guild == "" then return "No guild" end
    if NS.IsHostileGuild(guild) then return "Blocked guild" end
    if NS.IsFriendlyGuild(guild) then return "Allowed guild" end
    return "Other guild"
end

local function Collect(kind)
    local db = NS.db
    local out = {}
    if not db then return out end
    if kind == "players" then
        local seen = {}
        local function touch(key)
            if seen[key] then return seen[key] end
            local guild = GuildText(db.known[key])
            local row = { name = key, guild = guild, status = PlayerStatus(db, key, guild) }
            seen[key] = row
            out[#out + 1] = row
            return row
        end
        for key in pairs(db.known) do touch(key) end
        for key in pairs(db.allowedPlayers) do touch(key) end
        for key in pairs(db.blockedPlayers) do touch(key) end
        if db.haters then
            for key in pairs(db.haters) do touch(key) end
        end
    elseif kind == "guilds" then
        local counts = {}
        for _, guild in pairs(db.known) do
            guild = GuildText(guild)
            if guild ~= "" then counts[guild] = (counts[guild] or 0) + 1 end
        end
        for name, count in pairs(counts) do
            local status = "Other"
            if NS.IsHostileGuild(name) then status = "Blocked"
            elseif NS.IsFriendlyGuild(name) then status = "Allowed" end
            out[#out + 1] = { name = name, count = tostring(count), status = status }
        end
    elseif kind == "allowed" then
        for name in pairs(db.friendlyGuilds) do
            local note = (db.autoGuild and name == db.autoGuild) and "Your guild, partial" or "Partial"
            out[#out + 1] = { name = name, status = note }
        end
    elseif kind == "blocked" then
        for name in pairs(db.hostileGuilds) do
            out[#out + 1] = { name = name, status = "Exact" }
        end
    elseif kind == "flagged" then
        for key, why in pairs(db.haters or {}) do
            local reason = (type(why) == "string") and why or "Insulted an allowed guild"
            out[#out + 1] = { name = key, status = reason }
        end
    end
    return out
end

local function SortRows(list)
    table.sort(list, function(a, b)
        local av = tostring(a[sortKey] or ""):lower()
        local bv = tostring(b[sortKey] or ""):lower()
        if sortKey == "count" then
            av, bv = tonumber(a.count) or 0, tonumber(b.count) or 0
            if av == bv then
                return tostring(a.name) < tostring(b.name)
            end
            if sortAsc then return av < bv end
            return av > bv
        end
        if av == bv then
            return tostring(a.name):lower() < tostring(b.name):lower()
        end
        if sortAsc then return av < bv end
        return av > bv
    end)
end

local function Filtered()
    local list = Collect(view)
    local q = searchBox and strtrim(searchBox:GetText() or ""):lower() or ""
    if q ~= "" then
        local keep = {}
        for _, row in ipairs(list) do
            local blob = (tostring(row.name) .. " " .. tostring(row.guild or "") .. " " .. tostring(row.status or "")):lower()
            if blob:find(q, 1, true) then keep[#keep + 1] = row end
        end
        list = keep
    end
    SortRows(list)
    return list
end

local painting = false
local function PaintRows()
    if painting or not scroll then return end
    painting = true
    built = Filtered()
    local height = math.max(#built * ROW_H, scroll:GetHeight() or 1)
    child:SetHeight(height)
    child:SetWidth(math.max((scroll:GetWidth() or 500) - 4, 1))
    local maxScroll = math.max(0, height - (scroll:GetHeight() or 0))
    if scroll:GetVerticalScroll() > maxScroll then
        scroll:SetVerticalScroll(maxScroll)
    end
    local offset = scroll:GetVerticalScroll() or 0
    local first = math.floor(offset / ROW_H) + 1
    local cols = COLUMNS[view]
    local shift = offset - (first - 1) * ROW_H
    for i, row in ipairs(rows) do
        local item = built[first + i - 1]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -((i - 1) * ROW_H) - shift)
        row:SetPoint("RIGHT", scroll, "RIGHT", -18, 0)
        if item then
            row:Show()
            local cells = { row.name, row.guild, row.status }
            local x = 4
            for c = 1, 3 do
                local col = cols[c]
                cells[c]:ClearAllPoints()
                cells[c]:SetPoint("LEFT", row, "LEFT", x, 0)
                if col then
                    cells[c]:SetWidth(col.width)
                    cells[c]:SetText(tostring(item[col.key] or ""))
                    cells[c]:Show()
                    x = x + col.width + 8
                else
                    cells[c]:SetText("")
                    cells[c]:Hide()
                end
            end
            row.bg:SetVertexColor(1, 1, 1, (first + i) % 2 == 0 and 0.06 or 0.12)
        else
            row:Hide()
        end
    end
    local hx = 0
    for i, btn in ipairs(headerButtons) do
        local col = cols[i]
        if col then
            btn:Show()
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", hx, 0)
            btn:SetWidth(col.width)
            local mark = (sortKey == col.key) and (sortAsc and "  ^" or "  v") or ""
            btn:SetText(col.label .. mark)
            hx = hx + col.width + 8
        else
            btn:Hide()
        end
    end
    if emptyText then
        if #built == 0 then
            emptyText:Show()
            emptyText:SetText(searchBox:GetText() ~= "" and "Nothing matches." or "Nothing saved in this list.")
        else
            emptyText:Hide()
        end
    end
    painting = false
end

local function ShowTab(id)
    view = id
    sortKey = "name"
    sortAsc = true
    if scroll then scroll:SetVerticalScroll(0) end
    PaintRows()
end

function NS.OpenLists()
    if not frame then return end
    frame:Show()
    PaintRows()
end

function NS.RefreshLists()
    if frame and frame:IsShown() then PaintRows() end
end

local function Build()
    frame = CreateFrame("Frame", "VoxPopuliListsFrame", UIParent)
    frame:SetSize(560, 420)
    frame:SetPoint("CENTER", 0, 40)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(380)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:Hide()
    NS.PaintFrame(frame, 0.45, 0.62, 0.95)

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", -70, 0)
    drag:SetHeight(26)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local title = drag:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 10, 0)
    title:SetText("VoxPopuli lists")

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(52, 18)
    close:SetPoint("TOPRIGHT", -8, -4)
    close:SetText("Close")
    close:SetScript("OnClick", function() frame:Hide() end)

    local tabAnchor
    for _, tab in ipairs(TABS) do
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(78, 20)
        if tabAnchor then
            btn:SetPoint("LEFT", tabAnchor, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", 10, -32)
        end
        btn:SetText(tab.label)
        btn:SetScript("OnClick", function() ShowTab(tab.id) end)
        tabAnchor = btn
    end

    searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(160, 20)
    searchBox:SetPoint("TOPRIGHT", -16, -32)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", searchBox.ClearFocus)
    searchBox:SetScript("OnTextChanged", function() PaintRows() end)

    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("RIGHT", searchBox, "LEFT", -8, 0)
    searchLabel:SetText("Find")

    headerButtons = {}
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 10, -58)
    header:SetPoint("TOPRIGHT", -28, -58)
    header:SetHeight(ROW_H)
    local hx = 0
    for i = 1, 3 do
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(160, ROW_H)
        btn:SetPoint("LEFT", hx, 0)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints()
        fs:SetJustifyH("LEFT")
        btn:SetFontString(fs)
        btn:SetScript("OnClick", function()
            local col = COLUMNS[view][i]
            if not col then return end
            if sortKey == col.key then sortAsc = not sortAsc
            else sortKey = col.key sortAsc = true end
            PaintRows()
        end)
        headerButtons[i] = btn
        hx = hx + 170
    end

    scroll = CreateFrame("ScrollFrame", "VoxPopuliListsScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -78)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(500, 1)
    child:EnableMouse(false)
    scroll:SetScrollChild(child)

    local function wheel(_, delta)
        local range = scroll:GetVerticalScrollRange() or 0
        local nextScroll = scroll:GetVerticalScroll() - delta * ROW_H * 2
        if nextScroll < 0 then nextScroll = 0 end
        if nextScroll > range then nextScroll = range end
        scroll:SetVerticalScroll(nextScroll)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", wheel)
    scroll:HookScript("OnVerticalScroll", function()
        PaintRows()
    end)

    local visible = 20
    for i = 1, visible do
        local row = CreateFrame("Frame", nil, scroll)
        row:SetHeight(ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        if row.bg.SetColorTexture then
            row.bg:SetColorTexture(1, 1, 1, 1)
        else
            row.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        end
        row.bg:SetAllPoints()
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetWidth(180)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.guild = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.guild:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.guild:SetWidth(160)
        row.guild:SetJustifyH("LEFT")
        row.guild:SetWordWrap(false)
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetPoint("LEFT", row.guild, "RIGHT", 8, 0)
        row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.status:SetJustifyH("LEFT")
        row.status:SetWordWrap(false)
        row:Hide()
        rows[i] = row
    end

    emptyText = scroll:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOP", 0, -12)
    emptyText:Hide()

    frame:SetScript("OnShow", PaintRows)
end

Build()
