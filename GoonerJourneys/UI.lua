-- The journey window: guild roster on the left, the selected goon's
-- Timeline / Stats / Gear / Map on the right, plus guild Leaderboards.
local _, GJ = ...

local WIDTH, HEIGHT = 860, 560
local LIST_W = 210
local ROW_H = 30
local CONTENT_W = WIDTH - LIST_W - 40

local ui = {}
GJ.ui = ui

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function fontString(parent, template, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if size then
        local font, _, flags = fs:GetFont()
        fs:SetFont(font, size, flags)
    end
    fs:SetJustifyH("LEFT")
    return fs
end

local function button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, h or 22)
    b:SetText(text)
    return b
end

local function classLabel(m)
    local cls = m.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class]) or m.class or ""
    local race = m.race or ""
    return ("Level %d %s %s"):format(m.level or 0, race, cls)
end

local function scrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -26, 0)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(CONTENT_W - 30, 10)
    sf:SetScrollChild(child)
    return sf, child
end

---------------------------------------------------------------------------
-- Main frame
---------------------------------------------------------------------------
local function createMain()
    local f = CreateFrame("Frame", "GoonerJourneysFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    tinsert(UISpecialFrames, "GoonerJourneysFrame")

    local title = fontString(f, "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
    title:SetJustifyH("CENTER")
    title:SetText(GJ.COLOR .. "The Gooner Journeys|r")
    if type(f.TitleText) == "table" then f.TitleText:SetText("") end

    local status = fontString(f, "GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT", 14, 10)
    ui.status = status

    ui.frame = f
    return f
end

---------------------------------------------------------------------------
-- Roster list
---------------------------------------------------------------------------
local function createRoster(f)
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 12, -30)
    list:SetSize(LIST_W, HEIGHT - 70)

    local bg = list:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)

    local header = fontString(list, "GameFontNormal")
    header:SetPoint("TOPLEFT", 8, -6)
    header:SetText("The Goons")
    ui.rosterHeader = header

    ui.rows = {}
    ui.rosterOffset = 0
    local visible = math.floor((HEIGHT - 100) / ROW_H)
    ui.rosterVisible = visible
    for i = 1, visible do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(LIST_W - 8, ROW_H - 2)
        row:SetPoint("TOPLEFT", 4, -24 - (i - 1) * ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.5, 0, 0.25)
        row.dot = row:CreateTexture(nil, "OVERLAY")
        row.dot:SetSize(8, 8)
        row.dot:SetPoint("LEFT", 4, 0)
        row.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.name = fontString(row, "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", 18, -2)
        row.sub = fontString(row, "GameFontDisableSmall")
        row.sub:SetPoint("BOTTOMLEFT", 18, 2)
        row:SetScript("OnClick", function(btn)
            if btn.guid then GJ:SelectMember(btn.guid) end
        end)
        ui.rows[i] = row
    end

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        local total = #(ui.members or {})
        ui.rosterOffset = math.max(0, math.min(math.max(0, total - visible), ui.rosterOffset - delta))
        GJ:RefreshRoster()
    end)

    local lb = button(list, "Leaderboards", LIST_W - 16, 22)
    lb:SetPoint("BOTTOM", 0, 6)
    lb:SetScript("OnClick", function() GJ:ShowTab("leaders") end)
end

function GJ:RefreshRoster()
    if not ui.frame then return end
    local members = self:SortedMembers()
    ui.members = members
    local online = 0
    for _, m in ipairs(members) do if self:IsOnline(m) then online = online + 1 end end
    ui.rosterHeader:SetText(("The Goons |cff999999(%d, %d online)|r"):format(#members, online))
    for i, row in ipairs(ui.rows) do
        local m = members[i + ui.rosterOffset]
        if m then
            row.guid = m.guid
            row.name:SetText(self:ColoredName(m))
            local where
            if self:IsOnline(m) then
                where = (m.live and (m.live.inst or m.live.z)) or (self:IsMe(m.guid) and GetZoneText()) or "Online"
                row.dot:SetVertexColor(0.2, 1, 0.2)
            else
                where = "Seen " .. self:FormatAgo(m.lastSeen or m.updated)
                row.dot:SetVertexColor(0.4, 0.4, 0.4)
            end
            row.sub:SetText(("Lvl %d  %s"):format(m.level or 0, where or ""))
            row.sel:SetShown(m.guid == self.selectedGUID)
            row:Show()
        else
            row.guid = nil
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Detail header + tabs
---------------------------------------------------------------------------
local TABS = {
    { "timeline", "Timeline" },
    { "stats", "Stats" },
    { "gear", "Gear" },
    { "map", "Journey Map" },
    { "leaders", "Leaderboards" },
}

local function createDetail(f)
    local d = CreateFrame("Frame", nil, f)
    d:SetPoint("TOPLEFT", LIST_W + 22, -30)
    d:SetPoint("BOTTOMRIGHT", -12, 30)
    ui.detail = d

    ui.portrait = d:CreateTexture(nil, "ARTWORK")
    ui.portrait:SetSize(40, 40)
    ui.portrait:SetPoint("TOPLEFT", 0, 0)

    ui.name = fontString(d, "GameFontNormalHuge")
    ui.name:SetPoint("TOPLEFT", ui.portrait, "TOPRIGHT", 8, -2)
    ui.subtitle = fontString(d, "GameFontHighlightSmall")
    ui.subtitle:SetPoint("TOPLEFT", ui.name, "BOTTOMLEFT", 0, -3)
    ui.liveText = fontString(d, "GameFontHighlightSmall")
    ui.liveText:SetPoint("TOPRIGHT", 0, -4)
    ui.liveText:SetJustifyH("RIGHT")

    ui.tabs = {}
    local x = 0
    for _, def in ipairs(TABS) do
        local b = button(d, def[2], 112, 22)
        b:SetPoint("TOPLEFT", x, -48)
        x = x + 116
        b:SetScript("OnClick", function() GJ:ShowTab(def[1]) end)
        ui.tabs[def[1]] = b
    end

    ui.pages = {}
    for _, def in ipairs(TABS) do
        local p = CreateFrame("Frame", nil, d)
        p:SetPoint("TOPLEFT", 0, -78)
        p:SetPoint("BOTTOMRIGHT", 0, 0)
        p:Hide()
        ui.pages[def[1]] = p
    end
end

---------------------------------------------------------------------------
-- Timeline page
---------------------------------------------------------------------------
local FILTERS = {
    { "all", "Everything" },
    { "big", "Big moments" },
    { "death", "Deaths" },
    { "silly", "Silly stuff" },
    { "places", "Places & dungeons" },
}
local BIG = { level = true, boss = true, raid = true, dungeon = true, item = true, start = true }
local PLACES = { zone = true, dungeon = true, raid = true, boss = true }

local function filterMatch(filter, ev)
    if filter == "all" then return true end
    if filter == "big" then return BIG[ev.k] or (ev.k == "silly" and ev.d == "maxLevel") end
    if filter == "death" then return ev.k == "death" end
    if filter == "silly" then return ev.k == "silly" end
    if filter == "places" then return PLACES[ev.k] end
end

local function createTimeline()
    local page = ui.pages.timeline
    ui.filterIndex = 1
    local fb = button(page, "Show: Everything", 170, 20)
    fb:SetPoint("TOPRIGHT", 0, 0)
    fb:SetScript("OnClick", function()
        ui.filterIndex = ui.filterIndex % #FILTERS + 1
        fb:SetText("Show: " .. FILTERS[ui.filterIndex][2])
        GJ:RefreshTimeline()
    end)
    ui.timelineCount = fontString(page, "GameFontDisableSmall")
    ui.timelineCount:SetPoint("TOPLEFT", 0, -4)

    local holder = CreateFrame("Frame", nil, page)
    holder:SetPoint("TOPLEFT", 0, -26)
    holder:SetPoint("BOTTOMRIGHT")
    local sf, child = scrollArea(holder)
    ui.timelineChild = child
    ui.timelineRows = {}
end

local function timelineRow(i)
    local row = ui.timelineRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, ui.timelineChild)
    row:SetWidth(CONTENT_W - 34)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("TOPLEFT", 2, -2)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.date = fontString(row, "GameFontDisableSmall")
    row.date:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.text = fontString(row, "GameFontHighlight")
    row.text:SetPoint("TOPLEFT", row.date, "BOTTOMLEFT", 0, -2)
    row.text:SetWidth(CONTENT_W - 80)
    row.text:SetWordWrap(true)
    row.line = row:CreateTexture(nil, "BACKGROUND")
    row.line:SetColorTexture(1, 1, 1, 0.06)
    row.line:SetPoint("BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
    -- Item tooltips
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
    local m = self.selectedGUID and self:GetMember(self.selectedGUID)
    for _, r in ipairs(ui.timelineRows) do r:Hide() end
    if not m then return end
    local filter = FILTERS[ui.filterIndex][1]
    local y, n = 0, 0
    for i = #m.events, 1, -1 do
        local ev = m.events[i]
        if ev and filterMatch(filter, ev) then
            n = n + 1
            local row = timelineRow(n)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.icon:SetTexture(self:EventIcon(ev))
            local where = ev.m and self:MapName(ev.m) or ""
            if ev.k == "death" and ev.x then where = ("%s (%.0f, %.0f)"):format(where, ev.x / 10, ev.y / 10) end
            row.date:SetText(("%s  |cff888888Lvl %s  %s|r"):format(date("%d %b %Y %H:%M", ev.t or 0), tostring(ev.l or "?"), where))
            row.text:SetText(self:EventText(ev))
            row.itemID = (ev.k == "item") and ev.d or nil
            local h = math.max(32, 18 + row.text:GetStringHeight() + 6)
            row:SetHeight(h)
            row:Show()
            y = y + h + 2
        end
    end
    ui.timelineChild:SetHeight(math.max(10, y))
    ui.timelineCount:SetText(n == 0 and "Nothing here yet." or (n .. " entries"))
end

---------------------------------------------------------------------------
-- Stats page
---------------------------------------------------------------------------
local STAT_ROWS = {
    { "Level", function(m, s) return m.level end },
    { "Time played", function(m, s) return s.played and GJ:FormatDuration(s.played) end },
    { "Deaths", function(m, s) return s.deaths or 0 end },
    { "Kills", function(m, s) return s.kills or 0 end },
    { "Critters murdered", function(m, s) return s.critters or 0 end },
    { "Honorable kills", function(m, s) return s.pvpKills or 0 end },
    { "Quests turned in", function(m, s) return s.quests or 0 end },
    { "Zones explored", function(m, s) return s.zones or 0 end },
    { "Dungeon runs", function(m, s) return s.dungeonRuns or 0 end },
    { "Raid runs", function(m, s) return s.raidRuns or 0 end },
    { "Bosses killed", function(m, s) return s.bosses or 0 end },
    { "Group wipes", function(m, s) return s.wipes or 0 end },
    { "Distance travelled", function(m, s) return ("%.1f miles"):format((s.distance or 0) / 1760) end },
    { "Flight paths taken", function(m, s) return s.flights or 0 end },
    { "Hearthstones", function(m, s) return s.hearths or 0 end },
    { "Jumps", function(m, s) return s.jumps or 0 end },
    { "Times fell over", function(m, s) return s.falls or 0 end },
    { "Dances", function(m, s) return s.dances or 0 end },
    { "Hugs given", function(m, s) return s.hugs or 0 end },
    { "Guild chat messages", function(m, s) return s.guildMsgs or 0 end },
    { "Gold earned (total)", function(m, s) return GJ:FormatMoney(s.goldGained or 0) end },
    { "Richest ever", function(m, s) return GJ:FormatMoney(s.goldPeak or 0) end },
    { "Gold right now", function(m, s) return GJ:FormatMoney(s.gold or 0) end },
    { "Average item level", function(m, s) return m.gear and m.gear.ilvl end },
    { "Silly milestones", function(m, s)
        local n = 0
        for _, ev in ipairs(m.events) do if ev.k == "silly" then n = n + 1 end end
        return n
    end },
}

local function createStats()
    local page = ui.pages.stats
    local holder = CreateFrame("Frame", nil, page)
    holder:SetAllPoints()
    local _, child = scrollArea(holder)
    ui.statsChild = child
    ui.statLabels, ui.statValues = {}, {}
    local colW = (CONTENT_W - 40) / 2
    for i = 1, #STAT_ROWS + 12 do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local l = fontString(child, "GameFontNormal")
        l:SetPoint("TOPLEFT", col * colW, -row * 22)
        local v = fontString(child, "GameFontHighlight")
        v:SetPoint("TOPRIGHT", child, "TOPLEFT", col * colW + colW - 16, -row * 22)
        v:SetJustifyH("RIGHT")
        ui.statLabels[i], ui.statValues[i] = l, v
    end
end

function GJ:RefreshStats()
    local m = self.selectedGUID and self:GetMember(self.selectedGUID)
    for i = 1, #ui.statLabels do ui.statLabels[i]:SetText("") ui.statValues[i]:SetText("") end
    if not m then return end
    local s = m.stats or {}
    local i = 0
    for _, def in ipairs(STAT_ROWS) do
        i = i + 1
        local ok, v = pcall(def[2], m, s)
        ui.statLabels[i]:SetText(def[1])
        ui.statValues[i]:SetText(ok and v ~= nil and tostring(v) or "-")
    end
    if s.profs then
        local names = {}
        for name in pairs(s.profs) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            i = i + 1
            if i > #ui.statLabels then break end
            ui.statLabels[i]:SetText(name)
            ui.statValues[i]:SetText(tostring(s.profs[name]))
        end
    end
    ui.statsChild:SetHeight(math.ceil(i / 2) * 22 + 10)
end

---------------------------------------------------------------------------
-- Gear page
---------------------------------------------------------------------------
local function createGear()
    local page = ui.pages.gear
    ui.gearSlots = {}
    ui.gearNote = fontString(page, "GameFontDisableSmall")
    ui.gearNote:SetPoint("BOTTOMLEFT", 0, 4)
    local colW = (CONTENT_W - 20) / 2
    for i, def in ipairs(GJ.GEAR_SLOTS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local b = CreateFrame("Button", nil, page)
        b:SetSize(colW - 10, 36)
        b:SetPoint("TOPLEFT", col * colW, -row * 40)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(34, 34)
        b.icon:SetPoint("LEFT")
        b.border = b:CreateTexture(nil, "OVERLAY")
        b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        b.border:SetBlendMode("ADD")
        b.border:SetSize(62, 62)
        b.border:SetPoint("CENTER", b.icon)
        b.slotName = fontString(b, "GameFontDisableSmall")
        b.slotName:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, -2)
        b.slotName:SetText(def[2])
        b.itemName = fontString(b, "GameFontHighlight")
        b.itemName:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 2)
        b.itemName:SetWidth(colW - 60)
        b.itemName:SetWordWrap(false)
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
            local r, g, bl = 1, 1, 1
            if quality and GetItemQualityColor then r, g, bl = GetItemQualityColor(quality) end
            b.itemName:SetText(name or "Loading...")
            b.itemName:SetTextColor(r, g, bl)
            b.border:SetVertexColor(r, g, bl)
            b.border:SetShown(quality and quality >= 2)
        else
            b.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
            b.itemName:SetText("|cff666666Empty|r")
            b.border:Hide()
        end
    end
    if m and (m.gearStamp or 0) > 0 then
        ui.gearNote:SetText(("Snapshot from %s%s.  Shift-click to link."):format(GJ:FormatAgo(m.gearStamp),
            gear.ilvl and ("  Avg item level %.1f"):format(gear.ilvl) or ""))
    else
        ui.gearNote:SetText("No gear snapshot yet.")
    end
end

GJ:On("GET_ITEM_INFO_RECEIVED", function()
    if ui.frame and ui.frame:IsShown() and ui.currentTab == "gear" then
        if not ui.gearRefreshPending then
            ui.gearRefreshPending = true
            C_Timer.After(0.3, function() ui.gearRefreshPending = false GJ:RefreshGear() end)
        end
    end
end)

---------------------------------------------------------------------------
-- Map page
---------------------------------------------------------------------------
local function createMap()
    local page = ui.pages.map
    local prev = button(page, "<", 26, 22)
    prev:SetPoint("TOPLEFT", 0, 0)
    local nextB = button(page, ">", 26, 22)
    nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    ui.mapLabel = fontString(page, "GameFontNormal")
    ui.mapLabel:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
    local world = button(page, "Open on World Map", 150, 22)
    world:SetPoint("TOPRIGHT", 0, 0)
    world:SetScript("OnClick", function()
        if GJ.selectedGUID then GJ:ShowOnWorldMap(GJ.selectedGUID, ui.mapList and ui.mapList[ui.mapIndex or 1]) end
    end)
    local function step(d)
        if not ui.mapList or #ui.mapList == 0 then return end
        ui.mapIndex = (((ui.mapIndex or 1) - 1 + d) % #ui.mapList) + 1
        GJ:DrawMap()
    end
    prev:SetScript("OnClick", function() step(-1) end)
    nextB:SetScript("OnClick", function() step(1) end)

    ui.canvas = GJ:CreateMapCanvas(page, CONTENT_W - 10)
    ui.canvas.frame:SetPoint("TOPLEFT", 0, -28)
    ui.mapLegend = fontString(page, "GameFontDisableSmall")
    ui.mapLegend:SetPoint("BOTTOMLEFT", 0, 0)
    ui.mapLegend:SetText("Dots = where they walked.  Skulls = where they died.  Big dot = where they are now.")
end

-- Build the list of maps for the selected member: current live map first,
-- then every map they have walked on, most-walked first.
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
    return list, counts
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
        ui.mapLabel:SetText("No journey recorded yet")
        return
    end
    local cells = self:CellsOnMap(m, mapID)
    ui.mapLabel:SetText(("%s  |cff999999(%d/%d, %d spots walked)|r"):format(self:MapName(mapID), ui.mapIndex, #list, #cells))
    local r, g, b = self:ClassColor(m.class)
    for _, c in ipairs(cells) do
        canvas:AddDot(c[1], c[2], r, g, b, 0.8, 5)
    end
    for _, ev in ipairs(m.events) do
        if ev.m == mapID and ev.x then
            if ev.k == "death" then
                canvas:AddPin(ev.x / 1000, ev.y / 1000, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 16,
                    "Died here", { self:EventText(ev), date("%d %b %Y %H:%M", ev.t), "Level " .. tostring(ev.l) })
            elseif ev.k == "level" or ev.k == "silly" then
                canvas:AddPin(ev.x / 1000, ev.y / 1000, self:EventIcon(ev), 14, self:EventText(ev),
                    { date("%d %b %Y %H:%M", ev.t) })
            end
        end
    end
    -- Live position
    local liveMap, lx, ly
    if self:IsMe(m.guid) then
        liveMap, lx, ly = self:GetPlayerPosition()
    elseif self:IsOnline(m) and m.live and m.live.x then
        liveMap, lx, ly = m.live.m, m.live.x / 1000, m.live.y / 1000
    end
    if liveMap == mapID and lx then
        canvas:AddPin(lx, ly, "Interface\\Buttons\\WHITE8x8", 12, m.name .. " is here now", { m.live and m.live.z or GetZoneText() }, r, g, b)
        canvas:AddPin(lx, ly, "Interface\\Minimap\\Ping\\ping5", 28, m.name .. " is here now", {}, 1, 1, 1)
    end
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
    { "Highest level", function(m) return m.level or 0 end },
    { "Most deaths", function(m) return m.stats.deaths or 0 end },
    { "Most kills", function(m) return m.stats.kills or 0 end },
    { "Critter murderer", function(m) return m.stats.critters or 0 end },
    { "Most jumps", function(m) return m.stats.jumps or 0 end },
    { "Biggest yapper", function(m) return m.stats.guildMsgs or 0 end },
    { "Most travelled (miles)", function(m) return math.floor((m.stats.distance or 0) / 1760) end },
    { "Most bosses", function(m) return m.stats.bosses or 0 end },
    { "Most /played (hours)", function(m) return math.floor((m.stats.played or 0) / 3600) end },
    { "Silly milestones", function(m)
        local n = 0
        for _, ev in ipairs(m.events) do if ev.k == "silly" then n = n + 1 end end
        return n
    end },
}

local function createLeaders()
    local page = ui.pages.leaders
    local holder = CreateFrame("Frame", nil, page)
    holder:SetAllPoints()
    local _, child = scrollArea(holder)
    ui.leadersChild = child
    ui.boards = {}
    local colW = (CONTENT_W - 40) / 2
    for i, def in ipairs(BOARDS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local title = fontString(child, "GameFontNormal")
        title:SetPoint("TOPLEFT", col * colW, -row * 92)
        title:SetText(def[1])
        local lines = {}
        for j = 1, 3 do
            local l = fontString(child, "GameFontHighlightSmall")
            l:SetPoint("TOPLEFT", col * colW + 6, -row * 92 - 4 - j * 18)
            l:SetWidth(colW - 20)
            lines[j] = l
        end
        ui.boards[i] = lines
    end
    child:SetHeight(math.ceil(#BOARDS / 2) * 92)
end

function GJ:RefreshLeaders()
    local members = self:SortedMembers()
    local medals = { "|cffffd700#1|r", "|cffc7c7cf#2|r", "|cffeda55f#3|r" }
    for i, def in ipairs(BOARDS) do
        local scored = {}
        for _, m in ipairs(members) do
            m.stats = m.stats or {}
            local ok, v = pcall(def[2], m)
            if ok and v and v > 0 then scored[#scored + 1] = { m, v } end
        end
        table.sort(scored, function(a, b) return a[2] > b[2] end)
        for j = 1, 3 do
            local e = scored[j]
            ui.boards[i][j]:SetText(e and ("%s  %s  |cff999999%s|r"):format(medals[j], self:ColoredName(e[1]), BreakUpLargeNumbers and BreakUpLargeNumbers(e[2]) or e[2]) or "")
        end
    end
end

---------------------------------------------------------------------------
-- Selection and refresh
---------------------------------------------------------------------------
function GJ:ShowTab(tab)
    ui.currentTab = tab
    for key, page in pairs(ui.pages) do page:SetShown(key == tab) end
    for key, b in pairs(ui.tabs) do
        if key == tab then b:LockHighlight() else b:UnlockHighlight() end
    end
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
    ui.name:SetText(self:ColoredName(m))
    local journeyStart = m.events[1] and m.events[1].t
    ui.subtitle:SetText(classLabel(m) .. (journeyStart and ("   |cff999999Journey began %s|r"):format(date("%d %b %Y", journeyStart)) or ""))
    if m.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class] then
        ui.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        ui.portrait:SetTexCoord(unpack(CLASS_ICON_TCOORDS[m.class]))
    else
        ui.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        ui.portrait:SetTexCoord(0, 1, 0, 1)
    end
    local live
    if self:IsMe(m.guid) then
        live = "|cff33ff33Online|r - " .. (GetZoneText() or "")
    elseif self:IsOnline(m) then
        local where = m.live.inst and ("in " .. m.live.inst) or (m.live.z or "")
        live = "|cff33ff33Online|r - " .. where .. (m.live.dead and " |cffff5555(dead)|r" or "")
    else
        live = "|cff999999Offline - last seen " .. self:FormatAgo(m.lastSeen or m.updated) .. "|r"
    end
    ui.liveText:SetText(live)
end

function GJ:SelectMember(guid)
    self.selectedGUID = guid
    if ui.currentTab == "leaders" then ui.currentTab = "timeline" end
    self:RefreshRoster()
    self:RefreshHeader()
    self:ShowTab(ui.currentTab or "timeline")
    if WorldMapFrame and WorldMapFrame:IsShown() then self:RefreshWorldMapOverlay() end
end

function GJ:RefreshStatus()
    if not ui.status then return end
    local q = self:QueueSize()
    ui.status:SetText(("v%s   %s"):format(self.version, q > 0 and ("Syncing... (" .. q .. " messages queued)") or "Synced with online goons"))
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
        GJ:RefreshRoster()
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

-- Live-refresh the window when data for the selected member changes.
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
