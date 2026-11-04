-- The journey window: guild roster on the left, the selected goon's
-- Timeline / Stats / Gear / Journey Map on the right, plus Leaderboards.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local WIDTH, HEIGHT = 940, 620
local HEADER_H = 46
local SIDEBAR_W = 236
local ROW_H = 46
local PAD = 20
local CONTENT_W = WIDTH - SIDEBAR_W - PAD * 2

local ui = {}
GJ.ui = ui

local function fmtNum(n)
    if type(n) ~= "number" then return tostring(n or "-") end
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function memberColor(m)
    local r, g, b = GJ:ClassColor(m and m.class)
    return { r, g, b }
end

---------------------------------------------------------------------------
-- Window shell
---------------------------------------------------------------------------
local function createMain()
    local f = CreateFrame("Frame", "GoonerJourneysFrame", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    tinsert(UISpecialFrames, "GoonerJourneysFrame")
    S.Panel(f, C.bg, { 0, 0, 0, 1 })

    -- Soft drop shadow.
    local shadow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetTexture(S.WHITE)
    shadow:SetVertexColor(0, 0, 0, 0.35)
    shadow:SetPoint("TOPLEFT", -6, 6)
    shadow:SetPoint("BOTTOMRIGHT", 6, -6)

    -- Header bar (drag handle).
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local hbg = S.Fill(header, { 0.075, 0.08, 0.095, 1 }, "BACKGROUND")
    hbg:SetAllPoints()
    local hline = S.Fill(header, C.border, "ARTWORK")
    hline:SetPoint("BOTTOMLEFT")
    hline:SetPoint("BOTTOMRIGHT")
    hline:SetHeight(1)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("LEFT", 14, 0)
    logo:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    S.RoundMask(header, logo)

    local title = S.Text(header, 15, C.accent, S.FONT)
    title:SetPoint("LEFT", logo, "RIGHT", 10, 7)
    title:SetText("THE GOONER JOURNEYS")
    local sub = S.Text(header, 11, C.muted)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetText(GJ:GuildName() or "Unregistered Hypercam Users")
    ui.guildLabel = sub

    local close = CreateFrame("Button", nil, header)
    close:SetSize(HEADER_H - 12, HEADER_H - 12)
    close:SetPoint("RIGHT", -8, 0)
    local cx = S.Text(close, 20, C.muted, S.FONT)
    cx:SetPoint("CENTER", 0, 1)
    cx:SetText("x")
    local chl = S.Fill(close, { 1, 1, 1, 0.08 }, "HIGHLIGHT")
    chl:SetAllPoints()
    close:SetScript("OnClick", function() f:Hide() end)

    ui.status = S.Text(header, 11, C.faint)
    ui.status:SetPoint("RIGHT", close, "LEFT", -12, 0)
    ui.status:SetJustifyH("RIGHT")

    ui.frame = f
    return f
end

---------------------------------------------------------------------------
-- Sidebar roster
---------------------------------------------------------------------------
local function createRoster(f)
    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", 1, -HEADER_H - 1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR_W)
    local bg = S.Fill(side, C.sidebar, "BACKGROUND")
    bg:SetAllPoints()
    local line = S.Fill(side, C.border, "ARTWORK")
    line:SetPoint("TOPRIGHT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetWidth(1)

    local head = S.Text(side, 11, C.muted, S.FONT)
    head:SetPoint("TOPLEFT", 16, -16)
    head:SetText("GOONS")
    ui.rosterCount = S.Text(side, 11, C.faint)
    ui.rosterCount:SetPoint("LEFT", head, "RIGHT", 8, 0)

    ui.rows = {}
    ui.rosterOffset = 0
    local top = 38
    local visible = math.floor((HEIGHT - HEADER_H - top - 12) / ROW_H)
    ui.rosterVisible = visible
    for i = 1, visible do
        local row = CreateFrame("Button", nil, side)
        row:SetSize(SIDEBAR_W - 16, ROW_H - 4)
        row:SetPoint("TOPLEFT", 8, -top - (i - 1) * ROW_H)
        row.sel = S.Fill(row, C.cardHi, "BACKGROUND")
        row.sel:SetAllPoints()
        local hl = S.Fill(row, { 1, 1, 1, 0.04 }, "HIGHLIGHT")
        hl:SetAllPoints()
        row.stripe = S.Fill(row, C.accent, "ARTWORK")
        row.stripe:SetPoint("TOPLEFT")
        row.stripe:SetPoint("BOTTOMLEFT")
        row.stripe:SetWidth(3)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 12, 0)
        S.RoundMask(row, row.icon)
        row.status = S.Circle(row, 10, C.green, "OVERLAY")
        row.status:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -2)
        row.statusRing = S.Circle(row, 14, C.sidebar, "OVERLAY")
        row.statusRing:SetDrawLayer("OVERLAY", -1)
        row.statusRing:SetPoint("CENTER", row.status)

        row.name = S.Text(row, 13, C.text, S.FONT)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
        row.name:SetWidth(SIDEBAR_W - 110)
        row.sub = S.Text(row, 11, C.muted)
        row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
        row.sub:SetWidth(SIDEBAR_W - 80)
        row.level = S.Text(row, 12, C.muted, S.FONT)
        row.level:SetPoint("TOPRIGHT", -10, -6)
        row.level:SetJustifyH("RIGHT")

        row:SetScript("OnClick", function(btn) if btn.guid then GJ:SelectMember(btn.guid) end end)
        ui.rows[i] = row
    end

    side:EnableMouseWheel(true)
    side:SetScript("OnMouseWheel", function(_, delta)
        local total = #(ui.members or {})
        ui.rosterOffset = math.max(0, math.min(math.max(0, total - visible), ui.rosterOffset - delta))
        GJ:RefreshRoster()
    end)
end

function GJ:RefreshRoster()
    if not ui.frame then return end
    local members = self:SortedMembers()
    ui.members = members
    local online = 0
    for _, m in ipairs(members) do if self:IsOnline(m) then online = online + 1 end end
    ui.rosterCount:SetText(("%d  |  %s"):format(#members, S.Wrap(C.green, online .. " online")))
    ui.guildLabel:SetText(self:GuildName() or "No guild yet - your journey is still being recorded")
    for i, row in ipairs(ui.rows) do
        local m = members[i + ui.rosterOffset]
        if m then
            row.guid = m.guid
            local col = memberColor(m)
            row.name:SetText(m.name or "?")
            row.name:SetTextColor(col[1], col[2], col[3])
            row.icon:SetTexture(S.ClassIcon(m.class))
            row.level:SetText(m.level or "")
            local isOn = self:IsOnline(m)
            local where
            if isOn then
                where = (m.live and (m.live.inst or m.live.z)) or (self:IsMe(m.guid) and GetZoneText()) or "Online"
            else
                where = "Seen " .. self:FormatAgo(m.lastSeen or m.updated)
            end
            row.sub:SetText(where or "")
            row.status:SetVertexColor(unpack(isOn and C.green or C.faint))
            local selected = m.guid == self.selectedGUID and ui.currentTab ~= "leaders"
            row.sel:SetShown(selected)
            row.stripe:SetShown(selected)
            row.stripe:SetVertexColor(col[1], col[2], col[3])
            row:Show()
        else
            row.guid = nil
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Profile header, quick stats and tabs
---------------------------------------------------------------------------
local TABS = {
    { "timeline", "Timeline" },
    { "stats", "Stats" },
    { "gear", "Gear" },
    { "map", "Journey Map" },
    { "leaders", "Leaderboards" },
}

local QUICK = {
    { "LEVEL", function(m, s) return m.level or "-" end },
    { "DEATHS", function(m, s) return fmtNum(s.deaths or 0) end },
    { "ZONES", function(m, s) return fmtNum(s.zones or 0) end },
    { "MILES", function(m, s) return ("%.1f"):format((s.distance or 0) / 1760) end },
    { "PLAYED", function(m, s) return s.played and GJ:FormatDuration(s.played) or "-" end },
}

local function createDetail(f)
    local d = CreateFrame("Frame", nil, f)
    d:SetPoint("TOPLEFT", SIDEBAR_W + PAD, -HEADER_H - 16)
    d:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    ui.detail = d

    -- Profile
    local av = CreateFrame("Frame", nil, d)
    av:SetSize(56, 56)
    av:SetPoint("TOPLEFT")
    ui.avatarRing = S.Circle(av, 56, C.accent, "BACKGROUND")
    ui.avatarRing:SetPoint("CENTER")
    local inner = S.Circle(av, 52, C.bg, "BORDER")
    inner:SetPoint("CENTER")
    ui.avatar = av:CreateTexture(nil, "ARTWORK")
    ui.avatar:SetSize(48, 48)
    ui.avatar:SetPoint("CENTER")
    S.RoundMask(av, ui.avatar)

    ui.name = S.Text(d, 22, C.text, S.FONT)
    ui.name:SetPoint("TOPLEFT", av, "TOPRIGHT", 14, -6)
    ui.meta = S.Text(d, 12, C.muted)
    ui.meta:SetPoint("TOPLEFT", ui.name, "BOTTOMLEFT", 0, -5)

    local pill = CreateFrame("Frame", nil, d)
    pill:SetHeight(24)
    pill:SetPoint("TOPRIGHT", 0, -4)
    S.Panel(pill, C.card, C.border)
    ui.pillDot = S.Circle(pill, 8, C.green, "OVERLAY")
    ui.pillDot:SetPoint("LEFT", 10, 0)
    ui.pillText = S.Text(pill, 12, C.text)
    ui.pillText:SetPoint("LEFT", ui.pillDot, "RIGHT", 7, 0)
    ui.pill = pill

    -- Quick stats strip
    ui.quick = {}
    local qw = (CONTENT_W - (#QUICK - 1) * 8) / #QUICK
    for i, def in ipairs(QUICK) do
        local q = CreateFrame("Frame", nil, d)
        q:SetSize(qw, 50)
        q:SetPoint("TOPLEFT", (i - 1) * (qw + 8), -70)
        S.Panel(q, C.card, C.border)
        q.value = S.Text(q, 17, C.text, S.FONT)
        q.value:SetPoint("TOPLEFT", 12, -9)
        q.label = S.Text(q, 10, C.muted, S.FONT)
        q.label:SetPoint("BOTTOMLEFT", 12, 8)
        q.label:SetText(def[1])
        ui.quick[i] = q
    end

    ui.tabStrip = S.Tabs(d, TABS, function(key) GJ:ShowTab(key) end)
    ui.tabStrip:SetPoint("TOPLEFT", 0, -130)
    ui.tabStrip:SetPoint("TOPRIGHT", 0, -130)

    ui.pages = {}
    for _, def in ipairs(TABS) do
        local p = CreateFrame("Frame", nil, d)
        p:SetPoint("TOPLEFT", 0, -172)
        p:SetPoint("BOTTOMRIGHT")
        p:Hide()
        ui.pages[def[1]] = p
    end
    ui.pageH = HEIGHT - HEADER_H - 16 - PAD - 172
end

---------------------------------------------------------------------------
-- Timeline
---------------------------------------------------------------------------
local FILTERS = {
    { "all", "Everything" },
    { "big", "Big moments" },
    { "death", "Deaths" },
    { "silly", "Silly" },
    { "places", "Places" },
}
local BIG = { level = true, boss = true, raid = true, dungeon = true, item = true, start = true }
local PLACES = { zone = true, dungeon = true, raid = true, boss = true }

local KIND_COLOR = {
    death = C.red, silly = C.gold, level = C.accent, boss = { 0.70, 0.45, 1 },
    raid = { 1, 0.5, 0.2 }, dungeon = { 0.35, 0.65, 1 }, zone = { 0.35, 0.8, 0.6 },
    item = { 0.65, 0.4, 1 }, prof = { 0.5, 0.8, 1 }, start = C.accent,
}

local function filterMatch(filter, ev)
    if filter == "all" then return true end
    if filter == "big" then return BIG[ev.k] or (ev.k == "silly" and ev.d == "maxLevel") end
    if filter == "death" then return ev.k == "death" end
    if filter == "silly" then return ev.k == "silly" end
    if filter == "places" then return PLACES[ev.k] end
end

local function createTimeline()
    local page = ui.pages.timeline
    ui.filter = "all"
    ui.filterButtons = {}
    local x = 0
    for _, def in ipairs(FILTERS) do
        local b = S.Button(page, def[2], 0, 22)
        b:SetWidth(b.label:GetStringWidth() + 24)
        b:SetPoint("TOPLEFT", x, 0)
        x = x + b:GetWidth() + 6
        b:SetScript("OnClick", function()
            ui.filter = def[1]
            GJ:RefreshTimeline()
        end)
        b.key = def[1]
        ui.filterButtons[#ui.filterButtons + 1] = b
    end
    ui.timelineCount = S.Text(page, 11, C.faint)
    ui.timelineCount:SetPoint("TOPRIGHT", 0, -5)
    ui.timelineCount:SetJustifyH("RIGHT")

    local holder = CreateFrame("Frame", nil, page)
    holder:SetPoint("TOPLEFT", 0, -32)
    holder:SetPoint("BOTTOMRIGHT")
    ui.timelineScroll, ui.timelineChild = S.Scroll(holder, CONTENT_W - 12)
    ui.timelineRows = {}
    ui.timelineEmpty = S.Text(holder, 13, C.muted)
    ui.timelineEmpty:SetPoint("TOP", 0, -40)
end

local function timelineRow(i)
    local row = ui.timelineRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, ui.timelineChild)
    row:SetWidth(CONTENT_W - 14)
    S.Panel(row, C.card, C.border)
    row.stripe = S.Fill(row, C.accent, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT", 1, -1)
    row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    row.stripe:SetWidth(3)
    row.iconBg = S.Circle(row, 34, { 0, 0, 0, 0.5 }, "ARTWORK")
    row.iconBg:SetPoint("LEFT", 14, 0)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("CENTER", row.iconBg)
    S.RoundMask(row, row.icon)
    row.text = S.Text(row, 13, C.text)
    row.text:SetPoint("TOPLEFT", row.iconBg, "TOPRIGHT", 12, -1)
    row.text:SetWidth(CONTENT_W - 210)
    row.text:SetWordWrap(true)
    row.meta = S.Text(row, 11, C.muted)
    row.meta:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -4)
    row.date = S.Text(row, 11, C.faint)
    row.date:SetPoint("TOPRIGHT", -12, -10)
    row.date:SetJustifyH("RIGHT")
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(r)
        if r.itemID then
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. r.itemID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    ui.timelineRows[i] = row
    return row
end

function GJ:RefreshTimeline()
    for _, b in ipairs(ui.filterButtons) do
        local active = b.key == ui.filter
        b.bgTex:SetVertexColor(unpack(active and C.cardHi or C.card))
        b.borderTex:SetVertexColor(unpack(active and C.accent or C.border))
        b.label:SetTextColor(unpack(active and C.text or C.muted))
    end
    local m = self.selectedGUID and self:GetMember(self.selectedGUID)
    for _, r in ipairs(ui.timelineRows) do r:Hide() end
    if not m then return end
    local y, n = 0, 0
    for i = #m.events, 1, -1 do
        local ev = m.events[i]
        if ev and filterMatch(ui.filter, ev) then
            n = n + 1
            local row = timelineRow(n)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            local col = KIND_COLOR[ev.k] or C.accent
            row.stripe:SetVertexColor(col[1], col[2], col[3])
            row.icon:SetTexture(self:EventIcon(ev))
            row.text:SetText(self:EventText(ev))
            local where = ev.m and self:MapName(ev.m) or nil
            if ev.k == "death" and ev.x and where then where = ("%s (%.0f, %.0f)"):format(where, ev.x / 10, ev.y / 10) end
            row.meta:SetText(("Level %s%s"):format(tostring(ev.l or "?"), where and ("   " .. where) or ""))
            row.date:SetText(date("%d %b %Y  %H:%M", ev.t or 0))
            row.itemID = (ev.k == "item") and ev.d or nil
            local h = math.max(54, row.text:GetStringHeight() + 36)
            row:SetHeight(h)
            row:Show()
            y = y + h + 6
        end
    end
    ui.timelineChild:SetHeight(math.max(10, y))
    ui.timelineEmpty:SetText(n == 0 and "Nothing here yet - go make some memories." or "")
    ui.timelineCount:SetText(n > 0 and (n .. (n == 1 and " entry" or " entries")) or "")
    if ui.timelineScroll.UpdateThumb then ui.timelineScroll.UpdateThumb() end
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
local STAT_GROUPS = {
    { "COMBAT", {
        { "Kills", function(m, s) return fmtNum(s.kills or 0) end },
        { "Deaths", function(m, s) return fmtNum(s.deaths or 0) end },
        { "Critters murdered", function(m, s) return fmtNum(s.critters or 0) end },
        { "Honorable kills", function(m, s) return fmtNum(s.pvpKills or 0) end },
        { "Bosses killed", function(m, s) return fmtNum(s.bosses or 0) end },
        { "Group wipes", function(m, s) return fmtNum(s.wipes or 0) end },
    } },
    { "ADVENTURE", {
        { "Quests turned in", function(m, s) return fmtNum(s.quests or 0) end },
        { "Zones explored", function(m, s) return fmtNum(s.zones or 0) end },
        { "Dungeon runs", function(m, s) return fmtNum(s.dungeonRuns or 0) end },
        { "Raid runs", function(m, s) return fmtNum(s.raidRuns or 0) end },
        { "Miles travelled", function(m, s) return ("%.1f"):format((s.distance or 0) / 1760) end },
        { "Flight paths", function(m, s) return fmtNum(s.flights or 0) end },
    } },
    { "NONSENSE", {
        { "Jumps", function(m, s) return fmtNum(s.jumps or 0) end },
        { "Big falls", function(m, s) return fmtNum(s.falls or 0) end },
        { "Dances", function(m, s) return fmtNum(s.dances or 0) end },
        { "Hugs", function(m, s) return fmtNum(s.hugs or 0) end },
        { "Guild messages", function(m, s) return fmtNum(s.guildMsgs or 0) end },
        { "Hearthstones", function(m, s) return fmtNum(s.hearths or 0) end },
    } },
    { "WEALTH", {
        { "Gold earned", function(m, s) return GJ:FormatMoney(s.goldGained or 0) end },
        { "Richest ever", function(m, s) return GJ:FormatMoney(s.goldPeak or 0) end },
        { "Gold now", function(m, s) return GJ:FormatMoney(s.gold or 0) end },
    } },
}

local TILE_COLS = 3
local TILE_H = 52

local function createStats()
    local page = ui.pages.stats
    local holder = CreateFrame("Frame", nil, page)
    holder:SetAllPoints()
    ui.statsScroll, ui.statsChild = S.Scroll(holder, CONTENT_W - 12)
    ui.statTiles, ui.statHeads = {}, {}
end

local function statTile(i)
    local t = ui.statTiles[i]
    if t then return t end
    t = CreateFrame("Frame", nil, ui.statsChild)
    t:SetHeight(TILE_H)
    S.Panel(t, C.card, C.border)
    t.value = S.Text(t, 16, C.text, S.FONT)
    t.value:SetPoint("TOPLEFT", 12, -9)
    t.label = S.Text(t, 11, C.muted)
    t.label:SetPoint("BOTTOMLEFT", 12, 8)
    t.barBg = S.Fill(t, { 1, 1, 1, 0.06 }, "ARTWORK")
    t.barBg:SetPoint("BOTTOMLEFT", 1, 1)
    t.barBg:SetPoint("BOTTOMRIGHT", -1, 1)
    t.barBg:SetHeight(3)
    t.bar = S.Fill(t, C.accent, "ARTWORK", 1)
    t.bar:SetPoint("BOTTOMLEFT", 1, 1)
    t.bar:SetHeight(3)
    ui.statTiles[i] = t
    return t
end

local function statHead(i)
    local h = ui.statHeads[i]
    if h then return h end
    h = S.Text(ui.statsChild, 11, C.muted, S.FONT)
    ui.statHeads[i] = h
    return h
end

function GJ:RefreshStats()
    for _, t in ipairs(ui.statTiles) do t:Hide() end
    for _, h in ipairs(ui.statHeads) do h:Hide() end
    local m = self.selectedGUID and self:GetMember(self.selectedGUID)
    if not m then return end
    local s = m.stats or {}
    local tileW = (CONTENT_W - 12 - (TILE_COLS - 1) * 8) / TILE_COLS
    local y, ti, hi = 0, 0, 0

    local groups = {}
    for _, g in ipairs(STAT_GROUPS) do groups[#groups + 1] = g end
    if s.profs and next(s.profs) then
        local list = {}
        local names = {}
        for name in pairs(s.profs) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            list[#list + 1] = { name, function() return s.profs[name] end, (s.profs[name] or 0) / 300 }
        end
        groups[#groups + 1] = { "PROFESSIONS", list }
    end

    for _, group in ipairs(groups) do
        hi = hi + 1
        local h = statHead(hi)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 2, -y)
        h:SetText(group[1])
        h:Show()
        y = y + 20
        for j, def in ipairs(group[2]) do
            ti = ti + 1
            local t = statTile(ti)
            local col = (j - 1) % TILE_COLS
            local row = math.floor((j - 1) / TILE_COLS)
            t:SetWidth(tileW)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", col * (tileW + 8), -(y + row * (TILE_H + 8)))
            local ok, v = pcall(def[2], m, s)
            t.value:SetText(ok and v ~= nil and tostring(v) or "-")
            t.label:SetText(def[1])
            if def[3] then
                t.bar:SetWidth(math.max(1, (tileW - 2) * math.min(1, def[3])))
                t.bar:Show() t.barBg:Show()
            else
                t.bar:Hide() t.barBg:Hide()
            end
            t:Show()
        end
        y = y + math.ceil(#group[2] / TILE_COLS) * (TILE_H + 8) + 10
    end
    ui.statsChild:SetHeight(y)
    if ui.statsScroll.UpdateThumb then ui.statsScroll.UpdateThumb() end
end

---------------------------------------------------------------------------
-- Gear
---------------------------------------------------------------------------
local function createGear()
    local page = ui.pages.gear
    ui.gearSlots = {}
    ui.gearNote = S.Text(page, 11, C.faint)
    ui.gearNote:SetPoint("TOPLEFT", 0, 0)
    ui.gearIlvl = S.Text(page, 12, C.text, S.FONT)
    ui.gearIlvl:SetPoint("TOPRIGHT", 0, 0)
    ui.gearIlvl:SetJustifyH("RIGHT")

    local cols = 3
    local gap = 8
    local w = (CONTENT_W - (cols - 1) * gap) / cols
    local h = 42
    for i, def in ipairs(GJ.GEAR_SLOTS) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local b = CreateFrame("Button", nil, page)
        b:SetSize(w, h)
        b:SetPoint("TOPLEFT", col * (w + gap), -22 - row * (h + 6))
        S.Panel(b, C.card, C.border)
        local hl = S.Fill(b, { 1, 1, 1, 0.04 }, "HIGHLIGHT")
        hl:SetAllPoints()
        b.iconBorder = S.Fill(b, C.border, "ARTWORK")
        b.iconBorder:SetSize(34, 34)
        b.iconBorder:SetPoint("LEFT", 5, 0)
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetSize(32, 32)
        b.icon:SetPoint("CENTER", b.iconBorder)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.itemName = S.Text(b, 12, C.text)
        b.itemName:SetPoint("TOPLEFT", b.iconBorder, "TOPRIGHT", 8, -3)
        b.itemName:SetWidth(w - 54)
        b.slotName = S.Text(b, 10, C.faint, S.FONT)
        b.slotName:SetPoint("BOTTOMLEFT", b.iconBorder, "BOTTOMRIGHT", 8, 3)
        b.slotName:SetText(def[2]:upper())
        b.slot = def[1]
        b:SetScript("OnEnter", function(btn)
            if btn.item then
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(btn.item)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("OnClick", function(btn)
            if btn.item and IsModifiedClick("CHATLINK") then
                local _, link = GetItemInfo(btn.item)
                if link then ChatEdit_InsertLink(link) end
            end
        end)
        ui.gearSlots[i] = b
    end
end

function GJ:RefreshGear()
    local m = self.selectedGUID and self:GetMember(self.selectedGUID)
    local gear = m and m.gear or {}
    for _, b in ipairs(ui.gearSlots) do
        local item = gear[b.slot]
        b.item = item
        if item then
            local name, _, quality, _, _, _, _, _, _, tex = GetItemInfo(item)
            local id = tonumber(item:match("item:(%d+)"))
            b.icon:SetTexture(tex or (id and GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icon:SetDesaturated(false)
            b.icon:SetAlpha(1)
            local r, g, bl = 0.8, 0.8, 0.8
            if quality and GetItemQualityColor then r, g, bl = GetItemQualityColor(quality) end
            b.itemName:SetText(name or "Loading...")
            b.itemName:SetTextColor(r, g, bl)
            b.iconBorder:SetVertexColor(r, g, bl, 1)
        else
            b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            b.icon:SetDesaturated(true)
            b.icon:SetAlpha(0.15)
            b.itemName:SetText("Empty")
            b.itemName:SetTextColor(unpack(C.faint))
            b.iconBorder:SetVertexColor(unpack(C.border))
        end
    end
    if m and (m.gearStamp or 0) > 0 then
        ui.gearNote:SetText(("Snapshot %s  -  hover for tooltips, shift-click to link"):format(GJ:FormatAgo(m.gearStamp)))
        ui.gearIlvl:SetText(gear.ilvl and ("Average item level  " .. S.Wrap(C.accent, ("%.1f"):format(gear.ilvl))) or "")
    else
        ui.gearNote:SetText("No gear snapshot yet.")
        ui.gearIlvl:SetText("")
    end
end

GJ:On("GET_ITEM_INFO_RECEIVED", function()
    if ui.frame and ui.frame:IsShown() and ui.currentTab == "gear" and not ui.gearRefreshPending then
        ui.gearRefreshPending = true
        C_Timer.After(0.3, function() ui.gearRefreshPending = false GJ:RefreshGear() end)
    end
end)

---------------------------------------------------------------------------
-- Journey Map
---------------------------------------------------------------------------
local function chip(parent, h)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(h or 26)
    S.Panel(c, { 0.05, 0.055, 0.065, 0.92 }, { 0, 0, 0, 0.9 })
    c:SetFrameLevel(parent:GetFrameLevel() + 30)
    return c
end

local function arrow(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.t = S.Text(b, 14, C.text, S.FONT)
    b.t:SetPoint("CENTER", 0, 1)
    b.t:SetText(text)
    local hl = S.Fill(b, { 1, 1, 1, 0.1 }, "HIGHLIGHT")
    hl:SetAllPoints()
    return b
end

local function createMap()
    local page = ui.pages.map
    ui.canvas = GJ:CreateMapCanvas(page, CONTENT_W, ui.pageH)
    ui.canvas.frame:SetPoint("TOPLEFT")
    local holder = ui.canvas.frame

    -- Zone picker chip (top-left).
    local zc = chip(holder, 28)
    zc:SetPoint("TOPLEFT", 10, -10)
    local prev = arrow(zc, "<")
    prev:SetPoint("LEFT", 2, 0)
    ui.mapLabel = S.Text(zc, 13, C.text, S.FONT)
    ui.mapLabel:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    local nextB = arrow(zc, ">")
    nextB:SetPoint("LEFT", ui.mapLabel, "RIGHT", 6, 0)
    ui.mapChip, ui.mapNext = zc, nextB

    local function step(d)
        if not ui.mapList or #ui.mapList == 0 then return end
        ui.mapIndex = (((ui.mapIndex or 1) - 1 + d) % #ui.mapList) + 1
        GJ:DrawMap()
    end
    prev:SetScript("OnClick", function() step(-1) end)
    nextB:SetScript("OnClick", function() step(1) end)

    -- World map button (top-right).
    local world = S.Button(holder, "Open world map", 128, 28, "primary")
    world:SetPoint("TOPRIGHT", -10, -10)
    world:SetFrameLevel(holder:GetFrameLevel() + 30)
    world:SetScript("OnClick", function()
        if GJ.selectedGUID then GJ:ShowOnWorldMap(GJ.selectedGUID, ui.mapList and ui.mapList[ui.mapIndex or 1]) end
    end)

    -- Legend (bottom-left).
    local lg = chip(holder, 26)
    lg:SetPoint("BOTTOMLEFT", 10, 10)
    local x = 10
    local function legend(tex, color, label, round)
        local t = lg:CreateTexture(nil, "OVERLAY")
        t:SetSize(12, 12)
        t:SetPoint("LEFT", x, 0)
        t:SetTexture(tex)
        if color then t:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
        local fs = S.Text(lg, 11, C.muted)
        fs:SetPoint("LEFT", t, "RIGHT", 5, 0)
        fs:SetText(label)
        x = x + 12 + 5 + fs:GetStringWidth() + 14
        return t
    end
    ui.legendTrail = legend(S.CIRCLE, C.accent, "Trail")
    legend("Interface\\TargetingFrame\\UI-TargetingFrame-Skull", nil, "Deaths")
    legend("Interface\\Icons\\Spell_Holy_SurgeOfLight", nil, "Milestones")
    ui.legendHere = legend(S.CIRCLE, C.green, "Here now")
    lg:SetWidth(x)

    -- Count (bottom-right).
    local cc = chip(holder, 26)
    cc:SetPoint("BOTTOMRIGHT", -10, 10)
    ui.mapCount = S.Text(cc, 11, C.text)
    ui.mapCount:SetPoint("CENTER")
    ui.mapCountChip = cc
end

local function buildMapList(m)
    local counts = GJ:MapsWalked(m)
    for _, ev in ipairs(m.events) do
        if ev.m and not counts[ev.m] then counts[ev.m] = 0 end
    end
    local list = {}
    for mapID in pairs(counts) do list[#list + 1] = mapID end
    table.sort(list, function(a, b) return counts[a] > counts[b] end)
    local liveMap = GJ:IsMe(m.guid) and GJ:ZoneMapID() or (GJ:IsOnline(m) and m.live and m.live.m)
    if liveMap then
        for i, id in ipairs(list) do if id == liveMap then table.remove(list, i) break end end
        table.insert(list, 1, liveMap)
    end
    return list
end

function GJ:DrawMap()
    local m = self.selectedGUID and self:GetMember(self.selectedGUID)
    local canvas = ui.canvas
    canvas:Clear()
    if not m then canvas:SetMap(nil) return end
    local list = ui.mapList or {}
    local mapID = list[ui.mapIndex or 1]
    canvas:SetMap(mapID)
    if not mapID then
        ui.mapLabel:SetText("No journey yet")
        ui.mapChip:SetWidth(ui.mapLabel:GetStringWidth() + 74)
        ui.mapCount:SetText("0 spots walked")
        ui.mapCountChip:SetWidth(ui.mapCount:GetStringWidth() + 20)
        return
    end
    ui.mapLabel:SetText(("%s  %s"):format(self:MapName(mapID), S.Wrap(C.faint, ui.mapIndex .. "/" .. #list)))
    ui.mapChip:SetWidth(ui.mapLabel:GetStringWidth() + 74)

    local col = memberColor(m)
    ui.legendTrail:SetVertexColor(col[1], col[2], col[3])
    ui.legendHere:SetVertexColor(col[1], col[2], col[3])

    local cells = self:CellsOnMap(m, mapID)
    for _, c in ipairs(cells) do
        canvas:AddDot(c[1], c[2], col[1], col[2], col[3], 0.5)
    end
    local deaths = 0
    for _, ev in ipairs(m.events) do
        if ev.m == mapID and ev.x then
            if ev.k == "death" then
                deaths = deaths + 1
                local p = canvas:AddPin(ev.x / 1000, ev.y / 1000, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 16,
                    S.Wrap(C.red, "Died here"), { self:EventText(ev), date("%d %b %Y %H:%M", ev.t), "Level " .. tostring(ev.l) })
                p.icon:SetTexCoord(0, 1, 0, 1)
                p.ring:SetVertexColor(0.35, 0.05, 0.05, 0.9)
            elseif ev.k == "level" or ev.k == "silly" or ev.k == "boss" then
                local p = canvas:AddPin(ev.x / 1000, ev.y / 1000, self:EventIcon(ev), 18, self:EventText(ev),
                    { date("%d %b %Y %H:%M", ev.t) })
                p.ring:SetVertexColor(0, 0, 0, 0.8)
            end
        end
    end

    local liveMap, lx, ly
    if self:IsMe(m.guid) then
        liveMap, lx, ly = self:GetPlayerPosition()
    elseif self:IsOnline(m) and m.live and m.live.x then
        liveMap, lx, ly = m.live.m, m.live.x / 1000, m.live.y / 1000
    end
    if liveMap == mapID and lx then
        canvas:SetHere(lx, ly, col[1], col[2], col[3])
    end

    local spots = #cells == 1 and "1 spot walked" or (fmtNum(#cells) .. " spots walked")
    if deaths > 0 then spots = spots .. "   " .. S.Wrap(C.red, deaths .. (deaths == 1 and " death" or " deaths")) end
    ui.mapCount:SetText(spots)
    ui.mapCountChip:SetWidth(ui.mapCount:GetStringWidth() + 20)
end

function GJ:RefreshMap(keepIndex)
    local m = self.selectedGUID and self:GetMember(self.selectedGUID)
    if not m then return end
    local prevMap = ui.mapList and ui.mapList[ui.mapIndex or 1]
    ui.mapList = buildMapList(m)
    ui.mapIndex = 1
    if keepIndex and prevMap then
        for i, id in ipairs(ui.mapList) do if id == prevMap then ui.mapIndex = i break end end
    end
    self:DrawMap()
end

---------------------------------------------------------------------------
-- Leaderboards
---------------------------------------------------------------------------
local BOARDS = {
    { "Highest level", "Spell_Holy_SurgeOfLight", function(m) return m.level or 0 end },
    { "Most deaths", "INV_Misc_Bone_HumanSkull_01", function(m) return m.stats.deaths or 0 end },
    { "Most kills", "INV_Sword_04", function(m) return m.stats.kills or 0 end },
    { "Critter murderer", "INV_Misc_Food_15", function(m) return m.stats.critters or 0 end },
    { "Most jumps", "Ability_Rogue_Sprint", function(m) return m.stats.jumps or 0 end },
    { "Biggest yapper", "INV_Misc_Note_01", function(m) return m.stats.guildMsgs or 0 end },
    { "Most travelled (miles)", "Ability_Mount_RidingHorse", function(m) return math.floor((m.stats.distance or 0) / 1760) end },
    { "Most bosses", "INV_Misc_Head_Dragon_01", function(m) return m.stats.bosses or 0 end },
    { "Most /played (hours)", "INV_Misc_PocketWatch_01", function(m) return math.floor((m.stats.played or 0) / 3600) end },
    { "Silly milestones", "INV_Misc_Toy_07", function(m)
        local n = 0
        for _, ev in ipairs(m.events) do if ev.k == "silly" then n = n + 1 end end
        return n
    end },
}

local MEDAL = { { 1, 0.82, 0.25 }, { 0.78, 0.8, 0.85 }, { 0.85, 0.55, 0.3 } }

local function createLeaders()
    local page = ui.pages.leaders
    local holder = CreateFrame("Frame", nil, page)
    holder:SetAllPoints()
    local scroll, child = S.Scroll(holder, CONTENT_W - 12)
    ui.leadersScroll, ui.leadersChild = scroll, child
    ui.boards = {}
    local cols, gap = 2, 10
    local w = (CONTENT_W - 12 - gap) / cols
    local h = 118
    for i, def in ipairs(BOARDS) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local card = CreateFrame("Frame", nil, child)
        card:SetSize(w, h)
        card:SetPoint("TOPLEFT", col * (w + gap), -row * (h + gap))
        S.Panel(card, C.card, C.border)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 12, -10)
        icon:SetTexture("Interface\\Icons\\" .. def[2])
        S.RoundMask(card, icon)
        local title = S.Text(card, 12, C.text, S.FONT)
        title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        title:SetText(def[1])
        local lines = {}
        for j = 1, 3 do
            local badge = S.Circle(card, 18, MEDAL[j], "ARTWORK")
            badge:SetPoint("TOPLEFT", 14, -36 - (j - 1) * 25)
            local num = S.Text(card, 10, { 0.1, 0.1, 0.1 }, S.FONT)
            num:SetPoint("CENTER", badge, "CENTER", 0, 0)
            num:SetJustifyH("CENTER")
            num:SetShadowOffset(0, 0)
            num:SetText(j)
            local name = S.Text(card, 13, C.text)
            name:SetPoint("LEFT", badge, "RIGHT", 10, 0)
            name:SetWidth(w - 130)
            local val = S.Text(card, 13, C.muted, S.FONT)
            val:SetPoint("RIGHT", card, "TOPRIGHT", -14, -45 - (j - 1) * 25)
            val:SetJustifyH("RIGHT")
            lines[j] = { badge = badge, num = num, name = name, val = val }
        end
        ui.boards[i] = lines
    end
    child:SetHeight(math.ceil(#BOARDS / cols) * (h + gap))
end

function GJ:RefreshLeaders()
    local members = self:SortedMembers()
    for i, def in ipairs(BOARDS) do
        local scored = {}
        for _, m in ipairs(members) do
            m.stats = m.stats or {}
            local ok, v = pcall(def[3], m)
            if ok and v and v > 0 then scored[#scored + 1] = { m, v } end
        end
        table.sort(scored, function(a, b) return a[2] > b[2] end)
        for j = 1, 3 do
            local e, line = scored[j], ui.boards[i][j]
            if e then
                local col = memberColor(e[1])
                line.name:SetText(e[1].name or "?")
                line.name:SetTextColor(col[1], col[2], col[3])
                line.val:SetText(fmtNum(e[2]))
                line.badge:SetAlpha(1) line.num:SetAlpha(1)
            else
                line.name:SetText(j == 1 and "Nobody yet" or "")
                line.name:SetTextColor(unpack(C.faint))
                line.val:SetText("")
                line.badge:SetAlpha(0.15) line.num:SetAlpha(0.3)
            end
        end
    end
    if ui.leadersScroll.UpdateThumb then ui.leadersScroll.UpdateThumb() end
end

---------------------------------------------------------------------------
-- Selection and refresh
---------------------------------------------------------------------------
function GJ:ShowTab(tab)
    ui.currentTab = tab
    for key, page in pairs(ui.pages) do page:SetShown(key == tab) end
    ui.tabStrip:SetActive(tab)
    self:RefreshRoster()
    self:RefreshCurrentTab()
end

function GJ:RefreshCurrentTab()
    local tab = ui.currentTab
    if tab == "timeline" then self:RefreshTimeline()
    elseif tab == "stats" then self:RefreshStats()
    elseif tab == "gear" then self:RefreshGear()
    elseif tab == "map" then self:RefreshMap(true)
    elseif tab == "leaders" then self:RefreshLeaders() end
end

function GJ:RefreshHeader()
    local m = self.selectedGUID and self:GetMember(self.selectedGUID)
    if not m then return end
    local col = memberColor(m)
    ui.name:SetText(m.name or "?")
    ui.name:SetTextColor(col[1], col[2], col[3])
    ui.avatarRing:SetVertexColor(col[1], col[2], col[3])
    ui.avatar:SetTexture(S.ClassIcon(m.class))
    local meta = ("Level %d %s %s"):format(m.level or 0, S.Pretty(m.race), S.ClassName(m.class))
    local start = m.events[1] and m.events[1].t
    if start then meta = meta .. S.Wrap(C.faint, "   |   Journey began " .. date("%d %b %Y", start)) end
    ui.meta:SetText(meta)

    local text, dot
    if self:IsMe(m.guid) then
        text, dot = GetZoneText() or "Online", C.green
    elseif self:IsOnline(m) then
        text = m.live.inst or m.live.z or "Online"
        if m.live.dead then text = text .. "  " .. S.Wrap(C.red, "(dead)") end
        dot = C.green
    else
        text, dot = "Last seen " .. self:FormatAgo(m.lastSeen or m.updated), C.faint
    end
    ui.pillText:SetText(text)
    ui.pillDot:SetVertexColor(dot[1], dot[2], dot[3])
    ui.pill:SetWidth(ui.pillText:GetStringWidth() + 36)

    local s = m.stats or {}
    for i, def in ipairs(QUICK) do
        local ok, v = pcall(def[2], m, s)
        ui.quick[i].value:SetText(ok and tostring(v) or "-")
    end
end

function GJ:SelectMember(guid)
    self.selectedGUID = guid
    if ui.currentTab == "leaders" then ui.currentTab = "timeline" end
    self:RefreshHeader()
    self:ShowTab(ui.currentTab or "timeline")
    if WorldMapFrame and WorldMapFrame:IsShown() then self:RefreshWorldMapOverlay() end
end

function GJ:RefreshStatus()
    if not ui.status then return end
    local q = self:QueueSize()
    ui.status:SetText(q > 0 and ("Syncing  " .. q) or ("v" .. self.version))
end

local function build()
    if ui.frame then return end
    local f = createMain()
    createRoster(f)
    createDetail(f)
    createTimeline()
    createStats()
    createGear()
    createMap()
    createLeaders()
    f:SetScript("OnShow", function()
        if not GJ.selectedGUID then GJ.selectedGUID = GJ:PlayerGUID() end
        GJ:SelectMember(GJ.selectedGUID)
        GJ:RefreshStatus()
    end)
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 5 then return end
        acc = 0
        GJ:RefreshStatus()
        GJ:RefreshRoster()
        GJ:RefreshHeader()
    end)
end

function GJ:ToggleUI()
    build()
    ui.frame:SetShown(not ui.frame:IsShown())
end

local refreshPending = false
GJ:On("GJ_DATA_CHANGED", function(guid)
    if not ui.frame or not ui.frame:IsShown() or refreshPending then return end
    refreshPending = true
    C_Timer.After(1, function()
        refreshPending = false
        GJ:RefreshRoster()
        if guid == GJ.selectedGUID or ui.currentTab == "leaders" then
            GJ:RefreshHeader()
            GJ:RefreshCurrentTab()
        end
    end)
end)

GJ:On("GJ_LIVE_UPDATED", function(guid)
    if ui.frame and ui.frame:IsShown() and guid == GJ.selectedGUID and ui.currentTab == "map" then
        GJ:DrawMap()
    end
end)
