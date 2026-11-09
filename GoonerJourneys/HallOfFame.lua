-- Hall of Fame: one-off shout-outs that ship with a release. Each entry pops
-- up once for every guildie (with a fanfare) the first time they log in on
-- a version that has it, and stays in the Guild > Hall of Fame tab.
--
-- To add one: add an entry at the TOP of GJ.HALL_OF_FAME below (a new
-- unique id), optionally drop a photo in media/ (see media/README.md),
-- then release.
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
        -- image = "Interface\\AddOns\\GoonerJourneys\\media\\hall_of_thanes",
        -- imageW = 512, imageH = 256,
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
-- Member cards (used when there's no photo, and under the photo)
---------------------------------------------------------------------------
local function memberCard(parent, w, h)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(w, h)
    S.Panel(card, C.card, C.border)
    local hl = S.Fill(card, { 1, 1, 1, 0.05 }, "HIGHLIGHT")
    hl:SetAllPoints()
    card.ring = S.Circle(card, h - 14, GOLD, "ARTWORK")
    card.ring:SetPoint("LEFT", 8, 0)
    card.icon = card:CreateTexture(nil, "OVERLAY")
    card.icon:SetSize(h - 20, h - 20)
    card.icon:SetPoint("CENTER", card.ring)
    S.RoundMask(card, card.icon)
    card.name = S.Text(card, 13, C.text, S.FONT)
    card.name:SetPoint("TOPLEFT", card.ring, "TOPRIGHT", 8, -3)
    card.name:SetWidth(w - h - 6)
    card.sub = S.Text(card, 10, C.muted)
    card.sub:SetPoint("BOTTOMLEFT", card.ring, "BOTTOMRIGHT", 8, 3)
    card.sub:SetWidth(w - h - 6)
    card:SetScript("OnClick", function(self)
        if self.guid then
            if GJ.hallPopup then GJ.hallPopup:Hide() end
            if not (GJ.ui.frame and GJ.ui.frame:IsShown()) then GJ:ToggleUI() end
            GJ:SelectMember(self.guid)
        end
    end)
    return card
end

local function fillMemberCard(card, name)
    local m = GJ:FindMemberByName(name)
    card.guid = m and m.guid or nil
    card.name:SetText(name)
    if m then
        local r, g, b = GJ:ClassColor(m.class)
        card.name:SetTextColor(r, g, b)
        card.ring:SetVertexColor(r, g, b, 1)
        card.icon:SetTexture(S.ClassIcon(m.class))
        card.sub:SetText(("Level %d %s"):format(m.level or 0, S.ClassName(m.class)))
    else
        card.name:SetTextColor(unpack(C.text))
        card.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        card.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        card.sub:SetText("Legend")
    end
end

-- Lay out member cards in a row across `width`.
local function layoutMembers(holder, pool, names, width, cardH)
    local n = math.max(1, #names)
    local gap = 8
    local w = (width - (n - 1) * gap) / n
    for i, name in ipairs(names) do
        local card = pool[i]
        if not card then
            card = memberCard(holder, w, cardH)
            pool[i] = card
        end
        card:SetSize(w, cardH)
        card.name:SetWidth(w - cardH - 6)
        card.sub:SetWidth(w - cardH - 6)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (w + gap), 0)
        fillMemberCard(card, name)
        card:Show()
    end
    for i = #names + 1, #pool do pool[i]:Hide() end
end

---------------------------------------------------------------------------
-- The induction popup
---------------------------------------------------------------------------
local POP_W, POP_H = 580, 500
local PHOTO_W, PHOTO_H = POP_W - 44, 230

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

    -- Photo frame (shown when the entry has an image).
    f.photo = CreateFrame("Frame", nil, f)
    f.photo:SetSize(PHOTO_W, PHOTO_H)
    f.photo:SetPoint("TOP", 0, -128)
    S.Panel(f.photo, { 0, 0, 0, 1 }, GOLD)
    f.photo.tex = f.photo:CreateTexture(nil, "ARTWORK")
    f.photo.tex:SetPoint("TOPLEFT", 2, -2)
    f.photo.tex:SetPoint("BOTTOMRIGHT", -2, 2)

    -- Big trophy (shown when there's no photo).
    f.trophy = CreateFrame("Frame", nil, f)
    f.trophy:SetSize(PHOTO_W, PHOTO_H)
    f.trophy:SetPoint("TOP", 0, -128)
    f.trophy.glow = S.Circle(f.trophy, 170, { GOLD[1], GOLD[2], GOLD[3], 0.25 }, "BACKGROUND")
    f.trophy.glow:SetPoint("CENTER", 0, 10)
    S.Pulse(f.trophy.glow, 0.85, 1.15, 2.2)
    f.trophy.ring = S.Circle(f.trophy, 130, GOLD, "ARTWORK")
    f.trophy.ring:SetPoint("CENTER", 0, 10)
    f.trophy.icon = f.trophy:CreateTexture(nil, "OVERLAY")
    f.trophy.icon:SetSize(120, 120)
    f.trophy.icon:SetPoint("CENTER", f.trophy.ring)
    S.RoundMask(f.trophy, f.trophy.icon)

    f.members = CreateFrame("Frame", nil, f)
    f.members:SetSize(POP_W - 44, 50)
    f.members:SetPoint("TOP", f.photo, "BOTTOM", 0, -12)
    f.memberCards = {}

    f.text = S.Text(f, 12, C.muted)
    f.text:SetPoint("TOP", f.members, "BOTTOM", 0, -12)
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
    if entry.image then
        f.photo.tex:SetTexture(entry.image)
        f.photo.tex:SetTexCoord(0, 1, 0, 1)
        f.photo:Show()
        f.trophy:Hide()
    else
        f.trophy.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_Head_Dragon_01")
        f.trophy:Show()
        f.photo:Hide()
    end
    layoutMembers(f.members, f.memberCards, entry.members or {}, POP_W - 44, 50)
    f.text:SetText(entry.text or "")
    f.date:SetText(entry.t and date("%d %b %Y", entry.t) or "")
    f:Show()
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
local CARD_H_PHOTO, CARD_H = 330, 168

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
    card.photo = card:CreateTexture(nil, "ARTWORK")
    card.photo:SetSize(320, 160)
    card.photo:SetPoint("TOPLEFT", 16, -92)
    card.members = CreateFrame("Frame", nil, card)
    card.members:SetSize(w - 32, 46)
    card.memberCards = {}
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
        local h
        card.members:ClearAllPoints()
        if entry.image then
            card.photo:SetTexture(entry.image)
            card.photo:Show()
            card.members:SetPoint("TOPLEFT", 16, -262)
            h = CARD_H_PHOTO
        else
            card.photo:Hide()
            card.members:SetPoint("TOPLEFT", 16, -94)
            h = CARD_H
        end
        layoutMembers(card.members, card.memberCards, entry.members or {}, tab.width - 46, 46)
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
