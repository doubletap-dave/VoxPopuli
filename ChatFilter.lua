-- VoxPopuli - ChatFilter
-- Hides chat, bubbles, and (optionally) invites from non-whitelisted players.

local _, NS = ...

-- Chat event -> channel toggle key
NS.eventToChannel = {
    CHAT_MSG_SAY = "SAY",
    CHAT_MSG_YELL = "YELL",
    CHAT_MSG_EMOTE = "EMOTE",
    CHAT_MSG_TEXT_EMOTE = "EMOTE",
    CHAT_MSG_WHISPER = "WHISPER",
    CHAT_MSG_CHANNEL = "CHANNEL",
    CHAT_MSG_GUILD = "GUILD",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_RAID_WARNING = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE",
}

-- Events whose messages can also appear as open-world chat bubbles.
local BUBBLE_EVENTS = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
}

-- ---------------------------------------------------------------------------
-- Message filtering
-- ---------------------------------------------------------------------------

local lastHiddenLine

local function MessageFilter(chatFrame, event, msg, author, ...)
    local db = NS.db
    if not db or not db.toggles.enabled then return false end

    local chan = NS.eventToChannel[event]
    if chan and not db.toggles.channels[chan] then return false end

    if NS.IsSecret(msg) or NS.IsSecret(author) then return false end
    local guid = select(10, ...)  -- arg12
    if NS.IsSecret(guid) then guid = nil end

    local ok, friendly = pcall(NS.IsFriendly, author, guid)
    -- Watch bubbles on every bubble-type message: muted ones get hidden, and
    -- friendly ones trigger a restore check (bubbles get reused).
    if BUBBLE_EVENTS[event] then
        NS.WatchBubbles((ok and not friendly) and msg or nil)
    end
    if not ok or friendly then return false end

    -- The filter runs once per chat window showing the message; count it once.
    local lineID = select(9, ...)  -- arg11
    if lineID == nil or lineID ~= lastHiddenLine then
        lastHiddenLine = lineID
        NS.BumpHidden()
    end
    return true -- hide it
end

for event in pairs(NS.eventToChannel) do
    ChatFrame_AddMessageEventFilter(event, MessageFilter)
end

-- ---------------------------------------------------------------------------
-- Chat bubbles
-- ---------------------------------------------------------------------------
-- The game draws bubbles separately from the chat window. After a muted
-- player's say/yell/party message, look for a bubble with that exact text and
-- make it invisible (alpha 0, restored if the bubble gets reused for someone
-- else). Dungeons and raids lock bubbles away from addons, so this only works
-- in the open world.

local mutedTexts = {}      -- text -> time it stops being hidden
local hiddenHolders = {}   -- bubble frames we've made invisible
local watchUntil = 0
local bubbleWatcher = CreateFrame("Frame")
bubbleWatcher:Hide()

local function BubbleHolder(bubble)
    local holder = bubble.GetChildren and bubble:GetChildren()
    if holder and holder.String then return holder end
    if bubble.String then return bubble end
end

local function ScanBubbles()
    if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return end
    local now = GetTime()
    for text, t in pairs(mutedTexts) do
        if t < now then mutedTexts[text] = nil end
    end
    for _, bubble in pairs(C_ChatBubbles.GetAllChatBubbles(false)) do
        local holder = BubbleHolder(bubble)
        if holder and holder.String then
            local ok, text = pcall(holder.String.GetText, holder.String)
            if ok and text and not NS.IsSecret(text) and text ~= "" then
                if mutedTexts[text] then
                    if not hiddenHolders[holder] then
                        holder:SetAlpha(0)
                        hiddenHolders[holder] = true
                    end
                elseif hiddenHolders[holder] then
                    holder:SetAlpha(1)
                    hiddenHolders[holder] = nil  -- bubble reused for someone else
                end
            end
        end
    end
end

local elapsedSince = 0
bubbleWatcher:SetScript("OnUpdate", function(self, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.05 then return end
    elapsedSince = 0
    pcall(ScanBubbles)
    if GetTime() > watchUntil then self:Hide() end
end)

-- Called for every bubble-type message. mutedText is the message when the
-- sender is muted, nil otherwise (still watch: a friendly message may be
-- reusing a bubble we hid earlier).
function NS.WatchBubbles(mutedText)
    local db = NS.db
    if not db or not db.toggles.bubbles then return end
    if mutedText and mutedText ~= "" and not NS.IsSecret(mutedText) then
        mutedTexts[mutedText] = GetTime() + 30
    end
    if mutedText or next(hiddenHolders) then
        watchUntil = GetTime() + 1.5
        bubbleWatcher:Show()
    end
end

-- Restore every bubble we hid (used when the toggle is switched off).
function NS.ResetBubbles()
    for holder in pairs(hiddenHolders) do
        pcall(holder.SetAlpha, holder, 1)
    end
    wipe(hiddenHolders)
    wipe(mutedTexts)
end

-- ---------------------------------------------------------------------------
-- Auto-decline invites / duels / trades from non-whitelisted players
-- ---------------------------------------------------------------------------

NS.pendingInvite = nil      -- normalized "name-realm" of an unidentified inviter
NS.pendingInviteKind = nil  -- "party" or "guild"

local lastGuildDecline = 0

local function GuildInviteVisible()
    if GuildInviteFrame and GuildInviteFrame:IsShown() then return true end
    return StaticPopup_Visible and StaticPopup_Visible("GUILD_INVITE") and true or false
end

local function DeclineGuildInvite()
    -- Press the invite window's own Decline button when it exists, so the game
    -- does exactly what a manual click does; fall back to the API call.
    local btn = _G.GuildInviteFrameDeclineButton
    if btn and btn:IsVisible() then
        btn:Click()
    elseif DeclineGuild then
        DeclineGuild()
    elseif C_GuildInfo and C_GuildInfo.DeclineGuild then
        C_GuildInfo.DeclineGuild()
    end
    if StaticPopup_Hide then StaticPopup_Hide("GUILD_INVITE") end
    if GuildInviteFrame and GuildInviteFrame:IsShown() then GuildInviteFrame:Hide() end
end

local function HandleGuildInvite(inviter, guildName)
    local db = NS.db
    if not db.toggles.declineGuildInvite then return end
    if type(inviter) ~= "string" or NS.IsSecret(inviter) then return end
    NS.Debug(("guild invite from %s <%s>"):format(tostring(inviter), tostring(guildName)))
    -- The invite event carries the guild: learn it immediately, then decide.
    NS.Learn(inviter, guildName)
    local key = NS.NormalizeName(inviter)
    if key and not NS.IsFriendly(key) then
        DeclineGuildInvite()
        -- The invite window can open a moment after the event; check again.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function()
                if GuildInviteVisible() then xpcall(DeclineGuildInvite, NS.ReportError) end
            end)
        end
        if GetTime() - lastGuildDecline > 2 then
            NS.Print(("declined a guild invite from %s (not whitelisted)."):format(inviter))
        end
        lastGuildDecline = GetTime()
    else
        -- Friendly for now, but watch: if they're identified as non-friendly
        -- while the window is still open (target/mouseover), decline then.
        NS.pendingInvite = key
        NS.pendingInviteKind = "guild"
    end
end

-- Backup trigger: the "[Name] invites you to join <Guild>." line printed to
-- chat. Only acted on while an invite window is actually open, and only for
-- bare player links (player chat lines carry ":lineID:CHANNEL" and never match).
local function ParseInviteLine(msg)
    if type(msg) ~= "string" or NS.IsSecret(msg) then return end
    local db = NS.db
    if not db or not db.toggles.declineGuildInvite then return end
    if GetTime() - lastGuildDecline < 2 or not GuildInviteVisible() then return end
    msg = msg:gsub("^|c%x%x%x%x%x%x%x%x", "")
    local name = msg:match("^|Hplayer:([^:|]+)|h%[[^%]]*%]|h ")
    if not name then return end
    local key = NS.NormalizeName(name)
    if key and not NS.IsFriendly(key) then
        NS.Debug("backup trigger: guild invite line from " .. name)
        DeclineGuildInvite()
        lastGuildDecline = GetTime()
    end
end

local function HookInviteLines()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and f.AddMessage then
            hooksecurefunc(f, "AddMessage", function(self, msg)
                pcall(ParseInviteLine, msg)
            end)
        end
    end
end
pcall(HookInviteLines)

-- Group invites don't say which guild the inviter is in, so decline right away
-- if they're already known non-friendly. Otherwise remember them: if they get
-- identified while the invite is still open (mouseover, target, shift-click),
-- the invite is declined at that point.
local function HandlePartyInvite(inviter, ...)
    local db = NS.db
    if not db.toggles.declineGroupInvite then return end
    if type(inviter) ~= "string" or NS.IsSecret(inviter) then return end
    local guid = select(6, ...)
    if NS.IsSecret(guid) then guid = nil end
    local key = NS.NormalizeName(inviter)
    local knownBad = false
    if guid and db.guids[guid] then
        knownBad = not NS.IsFriendly(nil, guid)
    elseif key and db.known[key] ~= nil then
        knownBad = not NS.IsFriendly(key)
    end
    if knownBad then
        NS.pendingInvite = nil
        NS.pendingInviteKind = nil
        DeclineGroup()
        if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
        NS.Print("declined a group invite from " .. inviter .. " (not whitelisted).")
    else
        NS.pendingInvite = key
        NS.pendingInviteKind = "party"
        NS.Debug("holding group invite from " .. inviter .. " as pending")
    end
end

-- Called from NS.Learn when a player is (re)identified: if they had a pending
-- invite and now resolve as non-friendly, decline it on the spot.
function NS.CheckPendingInvite(key)
    if not NS.pendingInvite or NS.pendingInvite ~= key then return end
    if NS.IsFriendly(key) then return end
    NS.Debug("pending inviter identified as non-friendly: " .. tostring(key))
    if NS.pendingInviteKind == "guild" then
        if GuildInviteVisible() then
            DeclineGuildInvite()
            NS.Print("declined a guild invite from " .. tostring(key) .. " (not whitelisted).")
        end
    else
        if StaticPopup_Visible and StaticPopup_Visible("PARTY_INVITE") then
            DeclineGroup()
            StaticPopup_Hide("PARTY_INVITE")
            NS.Print("declined a group invite from " .. tostring(key) .. " (not whitelisted).")
        end
    end
    NS.pendingInvite = nil
    NS.pendingInviteKind = nil
end

local function HandleDuel(challenger)
    local db = NS.db
    if not db.toggles.declineDuel then return end
    if type(challenger) ~= "string" or NS.IsSecret(challenger) then return end
    local key = NS.NormalizeName(challenger)
    if key and not NS.IsFriendly(key) then
        CancelDuel()
        if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
        NS.Print("declined a duel from " .. challenger .. " (not whitelisted).")
    end
end

local function TradePartnerName(name)
    if type(name) == "string" and not NS.IsSecret(name) then return name end
    local n, realm
    if UnitFullName then n, realm = UnitFullName("NPC") else n = UnitName("NPC") end
    if not n or NS.IsSecret(n) then return nil end
    return (realm and realm ~= "") and (n .. "-" .. realm) or n
end

local function HandleTrade(name)
    local db = NS.db
    if not db.toggles.declineTrade then return end
    name = TradePartnerName(name)
    if not name then return end
    local key = NS.NormalizeName(name)
    if key and not NS.IsFriendly(key) then
        CancelTrade()
        if StaticPopup_Hide then StaticPopup_Hide("TRADE") end
        NS.Print("declined a trade from " .. name .. " (not whitelisted).")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PARTY_INVITE_REQUEST")  -- arg1: inviter name
frame:RegisterEvent("PARTY_INVITE_CANCEL")
frame:RegisterEvent("GUILD_INVITE_REQUEST")  -- arg1: inviter, arg2: guild
frame:RegisterEvent("DUEL_REQUESTED")        -- arg1: challenger name
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")   -- invite resolved (joined/left): drop pending
pcall(frame.RegisterEvent, frame, "TRADE_REQUEST")  -- not on every client
frame:SetScript("OnEvent", function(self, event, arg1, ...)
    local db = NS.db
    if not db or not db.toggles.enabled then return end
    if event == "PARTY_INVITE_REQUEST" then
        xpcall(function() HandlePartyInvite(arg1, ...) end, NS.ReportError)
    elseif event == "PARTY_INVITE_CANCEL" then
        NS.pendingInvite = nil
        NS.pendingInviteKind = nil
    elseif event == "GUILD_INVITE_REQUEST" then
        xpcall(function() HandleGuildInvite(arg1, ...) end, NS.ReportError)
    elseif event == "DUEL_REQUESTED" then
        xpcall(function() HandleDuel(arg1) end, NS.ReportError)
    elseif event == "TRADE_SHOW" then
        xpcall(function() HandleTrade(nil) end, NS.ReportError)
    elseif event == "TRADE_REQUEST" then
        xpcall(function() HandleTrade(arg1) end, NS.ReportError)
    elseif event == "GROUP_ROSTER_UPDATE" then
        NS.pendingInvite = nil
        NS.pendingInviteKind = nil
    end
end)

-- ---------------------------------------------------------------------------
-- Tooltip: learn first, then annotate
-- ---------------------------------------------------------------------------

local function OnTooltipUnit(tooltip)
    local db = NS.db
    if not db or not db.toggles.enabled then return end
    if not tooltip or not tooltip.GetUnit then return end
    local _, unit = tooltip:GetUnit()
    if not unit or NS.IsSecret(unit) or not UnitIsPlayer(unit) then return end
    if UnitIsUnit(unit, "player") then return end
    xpcall(function()
        NS.SafeScanUnit(unit)  -- learn them now so the very first tooltip is right
        local n, realm
        if UnitFullName then n, realm = UnitFullName(unit) else n = UnitName(unit) end
        if not n or NS.IsSecret(n) then return end
        local key = NS.NormalizeName((realm and realm ~= "") and (n .. "-" .. realm) or n)
        if not key then return end
        if db.allowedPlayers[key] then
            tooltip:AddLine("VoxPopuli: whitelisted", 0.4, 1, 0.4)
        elseif not NS.IsFriendly(key) then
            local guild = db.known[key]
            tooltip:AddLine("Hidden by VoxPopuli"
                .. ((guild and guild ~= false) and (" <" .. guild .. ">") or ""), 1, 0.3, 0.3)
        end
    end, NS.ReportError)
end

local function InstallTooltip()
    local hook = function(tt) OnTooltipUnit(tt) end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, hook)
    elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", hook)
    end
end
pcall(InstallTooltip)
