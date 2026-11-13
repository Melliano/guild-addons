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
        id = "deadmines-2026-11",
        t = 1794225600, -- 9 Nov 2026
        kicker = "THIS WEEK'S HALL OF FAME",
        title = "THE DEADMINES",
        headline = "conquered the Deadmines",
        text = "Five goons walked into the Deadmines and five goons walked out. "
            .. "Their names are now carved into the walls of the Gooner Hall forever.",
        members = { "Seemour", "Orianna", "Rook", "Rasputin", "Boush" },
        icon = "Interface\\Icons\\INV_Pick_02",
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

-- "Seemour, Orianna, Rook, Rasputin and Boush" with class colours where known.
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
-- The stage: a hero card per goon, or live 3D models when every goon on
-- the entry can be shown live (WoW Forever doesn't let addons build other
-- players' characters from scratch - no SetCustomRace - so a guildie's
-- model only works while the game can see them: group, target, nearby).
---------------------------------------------------------------------------
-- A unit token for this goon if the game can see them right now (group,
-- target, mouseover, nameplates): then we can show their exact look.
function GJ:FindUnitFor(guid)
    if not guid then return nil end
    local tokens = { "target", "focus", "mouseover" }
    for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
    for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and plates then
            for _, plate in ipairs(plates) do
                local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
                if u then tokens[#tokens + 1] = u end
            end
        end
    end
    for _, u in ipairs(tokens) do
        local ok, g = pcall(UnitGUID, u)
        if ok and g == guid and (not UnitIsVisible or UnitIsVisible(u)) then return u end
    end
    return nil
end

-- Show this goon's live model. Returns true, how ("you" | "exact") or
-- false, reason.
function GJ:DressModel(model, m)
    if not m then return false, "not synced yet" end
    if self:IsMe(m.guid) then
        local ok, err = pcall(model.SetUnit, model, "player")
        return ok, ok and "you" or tostring(err)
    end
    local unit = self:FindUnitFor(m.guid)
    if not unit then return false, "not in view (group up or stand nearby)" end
    local ok, err = pcall(model.SetUnit, model, unit)
    return ok, ok and "exact" or tostring(err)
end

-- Their best few items: rarest first, then highest item level.
local GEAR_SKIP = { [4] = true, [19] = true } -- shirt, tabard
function GJ:BestItems(m, count)
    local list = {}
    for slot, item in pairs(m and m.gear or {}) do
        if type(slot) == "number" and type(item) == "string" and not GEAR_SKIP[slot] then
            local _, _, quality, ilvl = GJ.ItemInfo(item)
            list[#list + 1] = { item = item, q = quality or 1, ilvl = ilvl or 0 }
        end
    end
    table.sort(list, function(x, y)
        if x.q ~= y.q then return x.q > y.q end
        if x.ilvl ~= y.ilvl then return x.ilvl > y.ilvl end
        return x.item < y.item
    end)
    for i = #list, (count or 3) + 1, -1 do list[i] = nil end
    return list
end

local function gearIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b.border = S.Fill(b, C.border, "ARTWORK")
    b.border:SetAllPoints()
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetScript("OnEnter", function(self)
        if self.item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.item)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function stageSlot(parent)
    local slot = CreateFrame("Button", nil, parent)

    -- Live model mode.
    slot.shadow = S.Circle(slot, 10, { 0, 0, 0, 0.5 }, "BORDER")
    slot.shadow:SetSize(80, 14)
    slot.model = CreateFrame("DressUpModel", nil, slot)
    slot.model:SetPoint("TOPLEFT", 0, -4)
    slot.model:SetPoint("BOTTOMRIGHT", 0, 22)
    slot.name = S.Text(slot, 13, C.text, S.FONT)
    slot.name:SetPoint("BOTTOM", 0, 0)
    slot.name:SetJustifyH("CENTER")

    -- Hero card mode.
    local card = CreateFrame("Frame", nil, slot)
    card:SetPoint("TOPLEFT", 5, -8)
    card:SetPoint("BOTTOMRIGHT", -5, 8)
    S.Panel(card, { 0.09, 0.085, 0.075, 0.95 }, { 1, 1, 1, 0.08 })
    card.stripe = S.Fill(card, C.accent, "ARTWORK")
    card.stripe:SetPoint("TOPLEFT", 1, -1)
    card.stripe:SetPoint("TOPRIGHT", -1, -1)
    card.stripe:SetHeight(3)
    card.glow = S.Circle(card, 10, { 1, 1, 1, 0.08 }, "BORDER")
    card.ring = S.Circle(card, 10, C.accent, "ARTWORK")
    card.icon = card:CreateTexture(nil, "OVERLAY")
    S.RoundMask(card, card.icon)
    card.badge = S.Circle(card, 26, C.bg, "OVERLAY")
    card.badge:SetDrawLayer("OVERLAY", 3)
    card.badgeRing = S.Circle(card, 30, C.accent, "OVERLAY")
    card.badgeRing:SetDrawLayer("OVERLAY", 2)
    card.level = S.Text(card, 11, C.text, S.FONT)
    card.level:SetDrawLayer("OVERLAY", 4)
    card.level:SetJustifyH("CENTER")
    card.name = S.Text(card, 15, C.text, S.FONT)
    card.name:SetJustifyH("CENTER")
    card.sub = S.Text(card, 11, C.muted)
    card.sub:SetJustifyH("CENTER")
    card.rank = S.Text(card, 10, C.accent, S.FONT)
    card.rank:SetJustifyH("CENTER")
    card.gear = {}
    for i = 1, 3 do card.gear[i] = gearIcon(card) end
    slot.card = card

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

-- Size and fill a hero card for this goon.
local function fillCard(card, m, name, w, h)
    local col = { GJ:ClassColor(m and m.class) }
    local p = math.floor(math.min(w - 40, h * 0.38))     -- portrait size
    local top = math.floor(h * 0.07)
    card.stripe:SetVertexColor(col[1], col[2], col[3], 1)
    card.glow:SetSize(p + 26, p + 26)
    card.glow:ClearAllPoints()
    card.glow:SetPoint("TOP", 0, -top + 9)
    card.glow:SetVertexColor(col[1], col[2], col[3], 0.12)
    card.ring:SetSize(p + 8, p + 8)
    card.ring:ClearAllPoints()
    card.ring:SetPoint("TOP", 0, -top + 4)
    card.ring:SetVertexColor(col[1], col[2], col[3], 1)
    card.icon:SetSize(p, p)
    card.icon:ClearAllPoints()
    card.icon:SetPoint("CENTER", card.ring)
    card.icon:SetTexture(m and S.ClassIcon(m.class) or "Interface\\Icons\\INV_Misc_QuestionMark")
    card.badgeRing:ClearAllPoints()
    card.badgeRing:SetPoint("CENTER", card.ring, "BOTTOMRIGHT", -p * 0.12, p * 0.12)
    card.badgeRing:SetVertexColor(col[1], col[2], col[3], 1)
    card.badge:ClearAllPoints()
    card.badge:SetPoint("CENTER", card.badgeRing)
    card.level:ClearAllPoints()
    card.level:SetPoint("CENTER", card.badgeRing, "CENTER", 0, 0)
    card.level:SetText(m and m.level or "?")
    local showBadge = m ~= nil
    card.badge:SetShown(showBadge) card.badgeRing:SetShown(showBadge) card.level:SetShown(showBadge)

    card.name:ClearAllPoints()
    card.name:SetPoint("TOP", card.ring, "BOTTOM", 0, -10)
    card.name:SetWidth(w - 16)
    card.name:SetText(name)
    card.name:SetTextColor(col[1], col[2], col[3])
    card.sub:ClearAllPoints()
    card.sub:SetPoint("TOP", card.name, "BOTTOM", 0, -4)
    card.sub:SetWidth(w - 16)
    card.sub:SetText(m and ("%s %s"):format(S.Pretty(m.race), S.ClassName(m.class)) or "Not synced yet")
    card.rank:ClearAllPoints()
    card.rank:SetPoint("TOP", card.sub, "BOTTOM", 0, -4)
    card.rank:SetWidth(w - 16)
    card.rank:SetText(m and GJ:MemberRank(m):upper() or "")
    card.rank:SetShown(h >= 200) -- no room on the smaller tab cards

    local items = GJ:BestItems(m, 3)
    local g = math.max(18, math.min(26, math.floor(h * 0.11)))
    local total = #items * g + math.max(0, #items - 1) * 5
    for i, b in ipairs(card.gear) do
        local it = items[i]
        if it then
            b:SetSize(g, g)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", card, "BOTTOM", -total / 2 + (i - 1) * (g + 5), 10)
            b.item = it.item
            b.icon:SetTexture(GJ.ItemIcon(it.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local r, gg, bb = GJ.ItemQualityColor(it.q)
            b.border:SetVertexColor(r, gg, bb, 1)
            b:Show()
        else
            b:Hide()
        end
    end
end

-- Fill `stage` with one goon per slot: live models if every goon can be
-- shown live right now, otherwise matching hero cards for everyone.
local stageSlots = setmetatable({}, { __mode = "k" })

local function layoutStage(stage, names, width, height)
    local slots = stageSlots[stage]
    if not slots then slots = {} stageSlots[stage] = slots end
    local n = math.max(1, #names)
    local w = width / n
    local members, live = {}, #names > 0
    for i, name in ipairs(names) do
        members[i] = GJ:FindMemberByName(name)
        local m = members[i]
        if not m or not (GJ:IsMe(m.guid) or GJ:FindUnitFor(m.guid)) then live = false end
    end
    stage.gjMode = live and "models" or "cards"

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
        local m = members[i]
        slot.guid = m and m.guid or nil
        if m then
            slot.title = GJ:ColoredName(m)
            slot.sub = ("Level %d %s %s"):format(m.level or 0, S.Pretty(m.race), S.ClassName(m.class))
        else
            slot.title, slot.sub = name, "Hasn't synced to you yet"
        end

        local modelOK = live and GJ:DressModel(slot.model, m)
        if modelOK then
            slot.card:Hide()
            slot.model:Show()
            pcall(slot.model.SetPortraitZoom, slot.model, 0)
            local facing = ((i - (n + 1) / 2) / n) * -0.9
            pcall(slot.model.SetFacing, slot.model, facing)
            slot.shadow:ClearAllPoints()
            slot.shadow:SetPoint("BOTTOM", 0, math.floor(height * 0.24))
            slot.shadow:Show()
            slot.name:SetText(name)
            local r, g, b = GJ:ClassColor(m and m.class)
            slot.name:SetTextColor(r, g, b)
            slot.name:Show()
        else
            slot.model:Hide()
            slot.shadow:Hide()
            slot.name:Hide()
            fillCard(slot.card, m, name, w - 10, height - 16)
            slot.card:Show()
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
        pcall(glow.SetGradient, glow, "VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.10))
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

-- /gooner fame debug: why each goon's model does or doesn't show.
function GJ:DebugHallOfFame()
    local entry = self.HALL_OF_FAME[1]
    if not entry then return end
    local probe = CreateFrame("DressUpModel", nil, UIParent)
    probe:SetSize(10, 10)
    probe:Hide()
    self:Print("Hall of Fame: live 3D models show when every goon below is OK, otherwise hero cards:")
    for _, name in ipairs(entry.members or {}) do
        local m = self:FindMemberByName(name)
        local gearCount = 0
        if m and m.gear then for k in pairs(m.gear) do if type(k) == "number" then gearCount = gearCount + 1 end end end
        local ok, how = self:DressModel(probe, m)
        DEFAULT_CHAT_FRAME:AddMessage(("   %s: %s | race %s, sex %s, %d gear items | %s"):format(
            name, m and "synced" or "NOT FOUND", tostring(m and m.race), tostring(m and m.sex), gearCount,
            ok and ("model OK (" .. tostring(how) .. ")") or ("model failed: " .. tostring(how))))
    end
end
