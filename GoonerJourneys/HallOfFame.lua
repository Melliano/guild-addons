-- Hall of Fame: one-off shout-outs that ship with a release. Each entry pops
-- up once for every guildie (with a fanfare) the first time they log in on
-- a version that has it, and stays in the Guild > Hall of Fame tab.
--
-- The goons named on an entry are shown as 3D character models on a
-- stage: their race, gender and last synced gear (your own character
-- exactly as you look).
--
-- To add one: add an entry at the TOP of GJ.HALL_OF_FAME below (a new
-- unique id), then release.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local GOLD = { 1, 0.82, 0.25 }
local POPUP_FOR = 21 * 86400 -- don't pop up entries older than 3 weeks for new installs

GJ.HALL_OF_FAME = {
    {
        id = "hall-of-thanes-2026-11",
        t = 1794225600, -- 9 Nov 2026
        kicker = "THIS WEEK'S HALL OF FAME",
        title = "HALL OF THANES",
        headline = "conquered the Hall of Thanes",
        text = "Four goons walked into the Hall of Thanes and four goons walked out. "
            .. "Their names are now carved into the walls of the Gooner Hall forever.",
        members = { "Seemour", "Orianna", "Rook", "Rasputin" },
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- Find a synced goon by display name (case-insensitive; also matches a
-- first name against "First Surname").
function GJ:FindMemberByName(name)
    if type(name) ~= "string" then return nil end
    local want = name:lower()
    local partial
    for _, m in pairs(self.db.members) do
        local n = type(m.name) == "string" and m.name:lower()
        if n then
            if n == want then return m end
            if not partial and (n:find("^" .. want .. "[%s%-]")) then partial = m end
        end
    end
    return partial
end

local function joinNames(list)
    if #list <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- "Seemour, Orianna, Rook and Rasputin" with class colours where known.
function GJ:HallNames(entry)
    local out = {}
    for _, name in ipairs(entry.members or {}) do
        local m = self:FindMemberByName(name)
        out[#out + 1] = m and self:ColoredName(m) or name
    end
    return joinNames(out)
end

local function fanfare()
    PlaySound((SOUNDKIT and SOUNDKIT.LEVEL_UP) or 888, "Master")
    C_Timer.After(0.9, function()
        PlaySound((SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 878, "Master")
    end)
end

---------------------------------------------------------------------------
-- The stage: one 3D character model per goon
---------------------------------------------------------------------------
-- Race file name ("NightElf") -> race ID for SetCustomRace. Built from the
-- game so new races (Skyborne) work; classic IDs as a fallback.
local RACE_IDS
local function raceID(raceFile)
    if not raceFile then return nil end
    if not RACE_IDS then
        RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8 }
        if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
            for id = 1, 120 do
                local ok, info = pcall(C_CreatureInfo.GetRaceInfo, id)
                if ok and info and info.clientFileString then RACE_IDS[info.clientFileString] = id end
            end
        end
    end
    return RACE_IDS[raceFile]
end

-- Gear slots that show on a character (not neck, rings or trinkets).
local VISIBLE_SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }

-- Dress a DressUpModel as this goon. Returns true if it worked.
function GJ:DressModel(model, m)
    if not m then return false end
    local ok = pcall(function()
        if self:IsMe(m.guid) then
            model:SetUnit("player")
            return
        end
        local id = raceID(m.race)
        if not id or not model.SetCustomRace then error("no race") end
        -- UnitSex: 2 = male, 3 = female; SetCustomRace wants 0 / 1.
        model:SetCustomRace(id, (m.sex == 3) and 1 or 0)
        if model.Undress then model:Undress() end
        local gear = m.gear or {}
        for _, slot in ipairs(VISIBLE_SLOTS) do
            if type(gear[slot]) == "string" then model:TryOn(gear[slot]) end
        end
    end)
    return ok
end

local function stageSlot(parent)
    local slot = CreateFrame("Button", nil, parent)
    slot.floor = S.Circle(slot, 80, { 1, 0.82, 0.25, 0.22 }, "BACKGROUND")
    slot.floor:SetPoint("BOTTOM", 0, 14)
    slot.model = CreateFrame("DressUpModel", nil, slot)
    slot.model:SetPoint("TOPLEFT", 0, 0)
    slot.model:SetPoint("BOTTOMRIGHT", 0, 18)
    -- Fallback when a model can't be built: the class icon.
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(56, 56)
    slot.icon:SetPoint("CENTER", 0, 10)
    S.RoundMask(slot, slot.icon)
    slot.name = S.Text(slot, 13, C.text, S.FONT)
    slot.name:SetPoint("BOTTOM", 0, 0)
    slot.name:SetJustifyH("CENTER")
    slot:SetScript("OnClick", function(self)
        if self.guid then
            if GJ.hallPopup then GJ.hallPopup:Hide() end
            if not (GJ.ui.frame and GJ.ui.frame:IsShown()) then GJ:ToggleUI() end
            GJ:SelectMember(self.guid)
        end
    end)
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.title or "")
        if self.sub then GameTooltip:AddLine(self.sub, 1, 1, 1) end
        if self.guid then GameTooltip:AddLine("Click to open their journey", 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    return slot
end

-- Fill `stage` with one model per name, fanned slightly towards the middle.
local stageSlots = setmetatable({}, { __mode = "k" })

local function layoutStage(stage, names, width, height)
    local slots = stageSlots[stage]
    if not slots then slots = {} stageSlots[stage] = slots end
    local n = math.max(1, #names)
    local w = width / n
    for i, name in ipairs(names) do
        local slot = slots[i]
        if not slot then
            slot = stageSlot(stage)
            slots[i] = slot
        end
        slot:SetSize(w, height)
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", stage, "TOPLEFT", (i - 1) * w, 0)
        slot:Show()
        local m = GJ:FindMemberByName(name)
        slot.guid = m and m.guid or nil
        slot.name:SetText(name)
        if m then
            local r, g, b = GJ:ClassColor(m.class)
            slot.name:SetTextColor(r, g, b)
            slot.title = GJ:ColoredName(m)
            slot.sub = ("Level %d %s %s"):format(m.level or 0, S.Pretty(m.race), S.ClassName(m.class))
        else
            slot.name:SetTextColor(unpack(C.text))
            slot.title, slot.sub = name, "Legend"
        end
        slot.model:Show()
        local dressed = GJ:DressModel(slot.model, m)
        if dressed then
            -- Fan out: left half turns right, right half turns left.
            local facing = ((i - (n + 1) / 2) / n) * -0.9
            pcall(slot.model.SetFacing, slot.model, facing)
            slot.icon:Hide()
        else
            slot.model:Hide()
            slot.icon:SetTexture(m and S.ClassIcon(m.class) or "Interface\\Icons\\INV_Misc_QuestionMark")
            slot.icon:Show()
        end
    end
    for i = #names + 1, #slots do slots[i]:Hide() end
end

local function createStage(parent, width, height)
    local stage = CreateFrame("Frame", nil, parent)
    stage:SetSize(width, height)
    S.Panel(stage, { 0.05, 0.045, 0.035, 1 }, { GOLD[1], GOLD[2], GOLD[3], 0.6 })
    -- Warm spotlight glow from above.
    local glow = stage:CreateTexture(nil, "BACKGROUND", nil, -6)
    glow:SetTexture(S.WHITE)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", -1, 1)
    if CreateColor and glow.SetGradient then
        pcall(glow.SetGradient, glow, "VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.18))
    else
        glow:SetVertexColor(0, 0, 0, 0)
    end
    stage.width, stage.height = width, height
    return stage
end

---------------------------------------------------------------------------
-- The induction popup
---------------------------------------------------------------------------
local POP_W, POP_H = 620, 500
local STAGE_W, STAGE_H = POP_W - 44, 260

local function buildPopup()
    local f = CreateFrame("Frame", "GoonerJourneysHallOfFame", UIParent)
    f:SetSize(POP_W, POP_H)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    tinsert(UISpecialFrames, "GoonerJourneysHallOfFame")
    S.Panel(f, C.bg, GOLD)
    local bar = S.Fill(f, GOLD, "ARTWORK")
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(3)

    f.kicker = S.Text(f, 11, GOLD, S.FONT)
    f.kicker:SetPoint("TOP", 0, -20)
    f.kicker:SetJustifyH("CENTER")
    f.title = S.Text(f, 30, GOLD, S.FONT)
    f.title:SetFont(S.FONT, 30, "OUTLINE")
    f.title:SetPoint("TOP", f.kicker, "BOTTOM", 0, -8)
    f.title:SetJustifyH("CENTER")
    f.headline = S.Text(f, 14, C.text)
    f.headline:SetPoint("TOP", f.title, "BOTTOM", 0, -10)
    f.headline:SetJustifyH("CENTER")
    f.headline:SetWidth(POP_W - 44)
    f.headline:SetWordWrap(true)

    f.stage = createStage(f, STAGE_W, STAGE_H)
    f.stage:SetPoint("TOP", 0, -128)

    f.text = S.Text(f, 12, C.muted)
    f.text:SetPoint("TOP", f.stage, "BOTTOM", 0, -14)
    f.text:SetWidth(POP_W - 60)
    f.text:SetJustifyH("CENTER")
    f.text:SetWordWrap(true)

    local close = S.Button(f, "Legendary", 120, 28, "primary")
    close:SetPoint("BOTTOMRIGHT", -22, 18)
    close:SetScript("OnClick", function() f:Hide() end)
    local open = S.Button(f, "Hall of Fame", 130, 28)
    open:SetPoint("RIGHT", close, "LEFT", -8, 0)
    open:SetScript("OnClick", function()
        f:Hide()
        if not (GJ.ui.frame and GJ.ui.frame:IsShown()) then GJ:ToggleUI() end
        GJ:ShowTab("halloffame")
    end)
    f.date = S.Text(f, 11, C.faint)
    f.date:SetPoint("BOTTOMLEFT", 22, 26)
    -- Several new entries at once: show them one after another.
    f:HookScript("OnHide", function()
        if GJ.hallQueue and #GJ.hallQueue > 0 then
            C_Timer.After(0.5, function()
                local nextEntry = table.remove(GJ.hallQueue, 1)
                if nextEntry then GJ:ShowHallOfFame(nextEntry) end
            end)
        end
    end)
    return f
end

function GJ:ShowHallOfFame(entry)
    entry = entry or self.HALL_OF_FAME[1]
    if not entry then return end
    if not self.hallPopup then self.hallPopup = buildPopup() end
    local f = self.hallPopup
    f.kicker:SetText(entry.kicker or "HALL OF FAME")
    f.title:SetText(entry.title or "")
    f.headline:SetText(("%s %s"):format(self:HallNames(entry), entry.headline or ""))
    f:Show()
    layoutStage(f.stage, entry.members or {}, STAGE_W - 2, STAGE_H - 4)
    f.text:SetText(entry.text or "")
    f.date:SetText(entry.t and date("%d %b %Y", entry.t) or "")
    fanfare()
end

-- On login: pop up each entry we haven't seen yet (oldest first, one at a
-- time). New installs only get recent ones; older ones are in the tab.
function GJ:CheckHallOfFame()
    local priv = self.db.private
    priv.hofSeen = priv.hofSeen or {}
    local now = self:Now()
    local pending = {}
    for _, entry in ipairs(self.HALL_OF_FAME) do
        if not priv.hofSeen[entry.id] then
            priv.hofSeen[entry.id] = now
            if not entry.t or now - entry.t < POPUP_FOR then pending[#pending + 1] = entry end
        end
    end
    if #pending == 0 or not self.db.settings.hallOfFame then return end
    -- Oldest first; the popup's OnHide shows the next one.
    table.sort(pending, function(x, y) return (x.t or 0) < (y.t or 0) end)
    self.hallQueue = pending
    self:ShowHallOfFame(table.remove(self.hallQueue, 1))
end

GJ:On("GJ_LOGIN", function()
    C_Timer.After(12, function() GJ:CheckHallOfFame() end)
end)

---------------------------------------------------------------------------
-- Guild > Hall of Fame tab
---------------------------------------------------------------------------
local tab = {}
local CARD_H = 330
local TAB_STAGE_H = 190

function GJ:CreateHallOfFamePage(parent, width, height)
    tab.width = width
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetAllPoints()
    tab.scroll, tab.child = S.Scroll(holder, width - 12)
    tab.cards = {}
    tab.empty = S.Text(holder, 13, C.muted)
    tab.empty:SetPoint("TOP", 0, -40)
end

local function entryCard(i)
    local card = tab.cards[i]
    if card then return card end
    local w = tab.width - 14
    card = CreateFrame("Frame", nil, tab.child)
    card:SetWidth(w)
    S.Panel(card, C.card, C.border)
    card.stripe = S.Fill(card, GOLD, "ARTWORK")
    card.stripe:SetPoint("TOPLEFT", 1, -1)
    card.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    card.stripe:SetWidth(3)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(40, 40)
    card.icon:SetPoint("TOPLEFT", 16, -14)
    S.RoundMask(card, card.icon)
    card.kicker = S.Text(card, 10, GOLD, S.FONT)
    card.kicker:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -2)
    card.title = S.Text(card, 18, C.text, S.FONT)
    card.title:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -4)
    card.date = S.Text(card, 11, C.faint)
    card.date:SetPoint("TOPRIGHT", -14, -16)
    card.date:SetJustifyH("RIGHT")
    card.headline = S.Text(card, 13, C.text)
    card.headline:SetPoint("TOPLEFT", 16, -66)
    card.headline:SetWidth(w - 32)
    card.headline:SetWordWrap(true)
    card.stage = createStage(card, w - 32, TAB_STAGE_H)
    card.stage:SetPoint("TOPLEFT", 16, -92)
    card.replay = S.Button(card, "Replay", 80, 24)
    card.replay:SetPoint("BOTTOMRIGHT", -14, 12)
    tab.cards[i] = card
    return card
end

function GJ:RefreshHallOfFame()
    if not tab.child then return end
    local y = 0
    for i, entry in ipairs(self.HALL_OF_FAME) do
        local card = entryCard(i)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -y)
        card.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_Head_Dragon_01")
        card.kicker:SetText(entry.kicker or "HALL OF FAME")
        card.title:SetText(entry.title or "")
        card.date:SetText(entry.t and date("%d %b %Y", entry.t) or "")
        card.headline:SetText(("%s %s"):format(self:HallNames(entry), entry.headline or ""))
        local h = CARD_H
        layoutStage(card.stage, entry.members or {}, tab.width - 48, TAB_STAGE_H - 4)
        card.replay:SetScript("OnClick", function() GJ:ShowHallOfFame(entry) end)
        card:SetHeight(h)
        card:Show()
        y = y + h + 10
    end
    for i = #self.HALL_OF_FAME + 1, #tab.cards do tab.cards[i]:Hide() end
    tab.child:SetHeight(math.max(10, y))
    tab.empty:SetText(#self.HALL_OF_FAME == 0 and "Nobody's famous yet." or "")
    if tab.scroll.UpdateThumb then tab.scroll.UpdateThumb() end
end
