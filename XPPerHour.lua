-- XPPerHour: XP/hour, time to level, gains to level
local ADDON = ...

local WINDOW = 600          -- "recent" rate looks at the last 10 minutes
local db
local sessionStart, sessionXP = 0, 0
local lastXP, lastMax, lastLevel
local gains = {}            -- { t, xp } recent gains, for the 10 min rate
local lastGains = {}        -- last 10 gain amounts, for "gains to level"

local function Short(n)
    if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
    if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
    return ("%d"):format(n)
end

local function Clock(sec)
    if not sec or sec ~= sec or sec == math.huge or sec <= 0 then return "--" end
    local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
    if h > 99 then return ">99h" end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm %02ds"):format(m, math.floor(sec) % 60)
end

local function MaxLevel()
    return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------
local f = CreateFrame("Frame", "XPPerHourFrame", UIParent, "BackdropTemplate")
f:SetSize(170, 74)
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
f:SetBackdropColor(0, 0, 0, 0.65)
f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    db.pos = { point, rel, x, y }
end)

local lines = {}
for i = 1, 4 do
    local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 8, -7 - (i - 1) * 15)
    r:SetPoint("TOPRIGHT", -8, -7 - (i - 1) * 15)
    l:SetTextColor(1, 0.82, 0)
    lines[i] = { l = l, r = r }
end
lines[1].l:SetText("XP / hour")
lines[2].l:SetText("Last 10 min")
lines[3].l:SetText("Time to level")
lines[4].l:SetText("Gains to level")

local function Rates()
    local now = GetTime()
    local elapsed = now - sessionStart
    local perHour = elapsed > 30 and sessionXP / elapsed * 3600 or 0
    while gains[1] and now - gains[1].t > WINDOW do table.remove(gains, 1) end
    local recent = 0
    for _, g in ipairs(gains) do recent = recent + g.xp end
    local span = math.min(WINDOW, elapsed)
    local recentPerHour = span > 30 and recent / span * 3600 or 0
    return perHour, recentPerHour, elapsed
end

local function Update()
    if not db then return end
    if UnitLevel("player") >= MaxLevel() then f:Hide() return end
    if not db.hidden then f:Show() end
    local perHour, recentPerHour = Rates()
    local left = UnitXPMax("player") - UnitXP("player")
    local rate = recentPerHour > 0 and recentPerHour or perHour

    lines[1].r:SetText(Short(perHour))
    lines[2].r:SetText(Short(recentPerHour))
    lines[3].r:SetText(Clock(rate > 0 and left / rate * 3600 or nil))

    local avg = 0
    for _, v in ipairs(lastGains) do avg = avg + v end
    avg = #lastGains > 0 and avg / #lastGains or 0
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local txt = avg > 0 and ("~%d"):format(math.ceil(left / avg)) or "--"
    if rested and rested > 0 then txt = txt .. " |cff6aa8ff(rested)|r" end
    lines[4].r:SetText(txt)
end

local function Reset()
    sessionStart, sessionXP = GetTime(), 0
    wipe(gains); wipe(lastGains)
    Update()
end

f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then Reset(); print("|cff33ff99XPPerHour|r: reset.") end
end)
f:SetScript("OnEnter", function(self)
    local perHour, _, elapsed = Rates()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("XPPerHour")
    GameTooltip:AddDoubleLine("Session time", Clock(elapsed), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Session XP", Short(sessionXP), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("XP to level", Short(UnitXPMax("player") - UnitXP("player")), 1, 1, 1, 1, 1, 1)
    local rested = GetXPExhaustion and GetXPExhaustion()
    if rested and rested > 0 then GameTooltip:AddDoubleLine("Rested", Short(rested), 1, 1, 1, 0.4, 0.66, 1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Drag to move, right-click to reset. /xph for options", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
f:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local function OnXP()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if lastXP then
        local delta
        if level > lastLevel then
            delta = (lastMax - lastXP) + xp       -- leveled up: rest of old level + new
        else
            delta = xp - lastXP
        end
        if delta > 0 then
            sessionXP = sessionXP + delta
            gains[#gains + 1] = { t = GetTime(), xp = delta }
            lastGains[#lastGains + 1] = delta
            if #lastGains > 10 then table.remove(lastGains, 1) end
        end
    end
    lastXP, lastMax, lastLevel = xp, max, level
    Update()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("UPDATE_EXHAUSTION")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        XPPerHourDB = XPPerHourDB or {}
        db = XPPerHourDB
    elseif event == "PLAYER_LOGIN" then
        f:ClearAllPoints()
        if db.pos then f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
        else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
        lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        Reset()
        if db.hidden then f:Hide() end
    elseif event == "PLAYER_XP_UPDATE" then
        OnXP()
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(0.5, OnXP)
    else
        Update()
    end
end)

C_Timer.NewTicker(1, function() if f:IsShown() then Update() end end)

SLASH_XPPERHOUR1 = "/xph"
SlashCmdList.XPPERHOUR = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        Reset(); print("|cff33ff99XPPerHour|r: reset.")
    elseif msg == "lock" then
        db.locked = not db.locked
        print("|cff33ff99XPPerHour|r: frame " .. (db.locked and "locked" or "unlocked") .. ".")
    elseif msg == "" or msg == "toggle" then
        db.hidden = not db.hidden
        f:SetShown(not db.hidden)
    else
        print("|cff33ff99XPPerHour|r: /xph (show/hide), /xph reset, /xph lock")
    end
end
