-- VoxPopuli - Debug window
-- Shown while the debug toggle is on. Holds the log that used to go to chat,
-- plus a live copy of the saved-list counts.

local _, NS = ...

local frame = CreateFrame("Frame", "VoxPopuliDebugFrame", UIParent)
frame:SetSize(480, 320)
frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -140)
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetFrameLevel(400)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:Hide()
NS.PaintFrame(frame)

local drag = CreateFrame("Frame", nil, frame)
drag:SetPoint("TOPLEFT", 0, 0)
drag:SetPoint("TOPRIGHT", -120, 0)
drag:SetHeight(26)
drag:EnableMouse(true)
drag:RegisterForDrag("LeftButton")
drag:SetScript("OnDragStart", function() frame:StartMoving() end)
drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

local title = drag:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("LEFT", 10, 0)
title:SetText("VoxPopuli debug")

local hideBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
hideBtn:SetSize(48, 18)
hideBtn:SetPoint("TOPRIGHT", -8, -4)
hideBtn:SetText("Hide")

local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
clearBtn:SetSize(48, 18)
clearBtn:SetPoint("RIGHT", hideBtn, "LEFT", -4, 0)
clearBtn:SetText("Clear")

local census = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
census:SetPoint("TOPLEFT", 12, -32)
census:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
census:SetJustifyH("LEFT")
census:SetText(" ")

local well = CreateFrame("Frame", nil, frame)
well:SetPoint("TOPLEFT", census, "BOTTOMLEFT", -4, -6)
well:SetPoint("BOTTOMRIGHT", -8, 8)
do
    local bg = well:CreateTexture(nil, "BACKGROUND")
    if bg.SetColorTexture then
        bg:SetColorTexture(0, 0, 0, 0.45)
    else
        bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        bg:SetVertexColor(0, 0, 0, 0.45)
    end
    bg:SetAllPoints()
end

local log = CreateFrame("ScrollingMessageFrame", nil, well)
log:SetPoint("TOPLEFT", 6, -4)
log:SetPoint("BOTTOMRIGHT", -6, 4)
log:SetJustifyH("LEFT")
log:SetFading(false)
log:SetMaxLines(400)
log:EnableMouseWheel(true)
do
    local font, size, flags = GameFontHighlightSmall:GetFont()
    log:SetFont(font or "Fonts\\FRIZQT__.TTF", size or 10, flags)
end
log:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
end)

local function RefreshCensus()
    if NS.CensusText then census:SetText(NS.CensusText()) end
end

local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 then return end
    elapsed = 0
    RefreshCensus()
end)

clearBtn:SetScript("OnClick", function() log:Clear() end)
hideBtn:SetScript("OnClick", function()
    if NS.SetDebug then NS.SetDebug(false) else frame:Hide() end
end)

function NS.DebugLine(msg)
    log:AddMessage("|cffbbbbbb" .. date("%H:%M:%S") .. "|r  " .. tostring(msg))
    RefreshCensus()
end

function NS.SetDebug(on)
    on = on and true or false
    if NS.db then NS.db.toggles.debug = on end
    if on then
        RefreshCensus()
        frame:Show()
        log:AddMessage("|cff33ff99debug on|r")
    else
        frame:Hide()
    end
    if NS.RefreshPanel then NS.RefreshPanel() end
end
