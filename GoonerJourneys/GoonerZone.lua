-- GOONER ZONE DETECTED: when a guildie walks into the Lion's Pride Inn in
-- Goldshire, the whole guild gets a big flashing alert with a raid-warning
-- sound. Visits are counted and unlock their own silly milestones.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local PINK = { 1, 0.25, 0.65 }
local COOLDOWN = 10 * 60       -- one alert per goon per 10 minutes
local SHOW_FOR = 6

-- Sub-zone text -> how it reads in the alert.
GJ.GOONER_ZONES = {
    ["Lion's Pride Inn"] = "the Lion's Pride Inn",
}

GJ.CounterMilestones.innVisits = {
    { 1,   "Gooner Zone Detected", "Walked into the Lion's Pride Inn in Goldshire. Everyone knows.", "INV_Drink_05" },
    { 10,  "Regular At The Lion's Pride", "Visited the Goldshire inn 10 times.", "INV_Drink_05" },
    { 50,  "Has A Room Key", "Visited the Goldshire inn 50 times.", "INV_Misc_Key_03" },
    { 100, "Lives In Goldshire Inn", "Visited the Goldshire inn 100 times. Seek help.", "INV_Misc_Key_03" },
}

-- Returns the alert text for where we are, or nil.
function GJ:CurrentGoonerZone()
    local sub = GetSubZoneText and GetSubZoneText() or ""
    if self.GOONER_ZONES[sub] then return self.GOONER_ZONES[sub] end
    -- Fallback for clients that report the inn as plain "Goldshire":
    -- indoors and resting in Goldshire means you're in the inn.
    if sub == "Goldshire" and IsIndoors and IsIndoors() and IsResting() then
        return "the Lion's Pride Inn"
    end
    return nil
end

---------------------------------------------------------------------------
-- The alert banner
---------------------------------------------------------------------------
local banner

local function build()
    banner = CreateFrame("Button", "GoonerJourneysGoonerAlert", UIParent)
    banner:SetSize(540, 104)
    banner:SetPoint("CENTER", UIParent, "CENTER", 0, 190)
    banner:SetFrameStrata("FULLSCREEN_DIALOG")
    S.Panel(banner, { 0.07, 0.02, 0.05, 0.96 }, PINK)
    banner.glow = S.Fill(banner, { PINK[1], PINK[2], PINK[3], 0.18 }, "BORDER")
    banner.glow:SetPoint("TOPLEFT", 1, -1)
    banner.glow:SetPoint("BOTTOMRIGHT", -1, 1)

    local function sideIcon(point, x)
        local t = banner:CreateTexture(nil, "ARTWORK")
        t:SetSize(44, 44)
        t:SetPoint(point, x, 0)
        t:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        return t
    end
    sideIcon("LEFT", 18)
    sideIcon("RIGHT", -18)

    banner.title = S.Text(banner, 26, PINK, S.FONT)
    banner.title:SetFont(S.FONT, 26, "OUTLINE")
    banner.title:SetPoint("TOP", 0, -18)
    banner.title:SetJustifyH("CENTER")
    banner.title:SetText("GOONER ZONE DETECTED")

    banner.text = S.Text(banner, 15, C.text)
    banner.text:SetPoint("TOP", banner.title, "BOTTOM", 0, -10)
    banner.text:SetJustifyH("CENTER")
    banner.text:SetWidth(420)

    banner.sub = S.Text(banner, 11, C.muted)
    banner.sub:SetPoint("TOP", banner.text, "BOTTOM", 0, -6)
    banner.sub:SetJustifyH("CENTER")
    banner.sub:SetWidth(420)

    banner:SetScript("OnClick", function(self)
        self:Hide()
        if self.guid then
            if not (GJ.ui.frame and GJ.ui.frame:IsShown()) then GJ:ToggleUI() end
            GJ:SelectMember(self.guid)
        end
    end)
    banner:SetScript("OnUpdate", function(self, dt)
        self.age = self.age + dt
        -- Flashing border/glow.
        local pulse = 0.5 + 0.5 * math.sin(self.age * 9)
        self.borderTex:SetVertexColor(PINK[1], PINK[2], PINK[3], 0.4 + 0.6 * pulse)
        self.glow:SetAlpha(0.3 + 0.7 * pulse)
        local a = 1
        if self.age < 0.2 then a = self.age / 0.2
        elseif self.age > SHOW_FOR - 0.8 then a = math.max(0, (SHOW_FOR - self.age) / 0.8) end
        self:SetAlpha(a)
        if self.age >= SHOW_FOR then self:Hide() end
    end)
end

function GJ:ShowGoonerAlert(member, place)
    if not self.db.settings.goonerAlerts then return end
    if not banner then build() end
    local own = self:IsMe(member.guid)
    banner.guid = member.guid
    banner.age = 0
    banner.text:SetText(("%s %s entered %s"):format(own and "You" or self:ColoredName(member), own and "have" or "has", place or "the Lion's Pride Inn"))
    local visits = member.stats and member.stats.innVisits
    banner.sub:SetText(visits and visits > 1 and ("Visit number %d. We're not judging. (We are.)"):format(visits) or "First recorded visit. Everyone has been notified.")
    banner:Show()
    PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
end

---------------------------------------------------------------------------
-- Detection (you) and broadcast
---------------------------------------------------------------------------
local inZone = false
local lastAlert = -COOLDOWN

local function check()
    local place = GJ:CurrentGoonerZone()
    if place and not inZone then
        inZone = true
        if GetTime() - lastAlert >= COOLDOWN then
            lastAlert = GetTime()
            GJ:Bump("innVisits")
            local me = GJ:Me()
            GJ:ShowGoonerAlert(me, place)
            GJ:Send({ k = "A", g = me.guid, i = GJ:MyInfo(), z = place, n = me.stats.innVisits })
            if GJ.Announce then GJ:Announce("GOONER ALERT: You have entered " .. place) end
        end
    elseif not place then
        inZone = false
    end
end

local function soon() C_Timer.After(0.5, check) end
GJ:On("ZONE_CHANGED", soon)
GJ:On("ZONE_CHANGED_INDOORS", soon)
GJ:On("ZONE_CHANGED_NEW_AREA", soon)
GJ:On("PLAYER_UPDATE_RESTING", soon)

-- Guildies: show their alert (once per 10 minutes per goon).
local seen = {}
GJ:RegisterHandler("A", function(body)
    if type(body.g) ~= "string" or GJ:IsMe(body.g) then return end
    local m = GJ:GetMember(body.g, true)
    GJ:ApplyInfo(m, body.i)
    if GetTime() - (seen[body.g] or -COOLDOWN) < COOLDOWN then return end
    seen[body.g] = GetTime()
    if type(body.n) == "number" then
        m.stats = m.stats or {}
        if body.n > (m.stats.innVisits or 0) then m.stats.innVisits = body.n end
    end
    GJ:ShowGoonerAlert(m, type(body.z) == "string" and body.z or nil)
end)
