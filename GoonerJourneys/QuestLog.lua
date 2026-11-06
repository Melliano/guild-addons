-- Guild quest log tab: every quest a goon has picked up, grouped by area,
-- with who is on it right now, who has finished it and who dropped it.
-- Filter by status, goon and level; sort by level, name or most goons.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local ROW_H = 50
local HEAD_H = 28
local MAX_ROWS = 300
local NAMES_SHOWN = 3
local NEAR_LEVELS = 5
local OTHER = "Other"

local STATUS = {
    { "all", "Everything" },
    { "active", "In progress" },
    { "done", "Completed" },
    { "dropped", "Dropped" },
}

local SORTS = {
    { "level", "Level" },
    { "name", "Name" },
    { "goons", "Most goons" },
}

local page = { status = "all", search = "", who = nil, near = false, rows = {}, heads = {} }

---------------------------------------------------------------------------
-- Building the view (no UI here, so it can be tested)
---------------------------------------------------------------------------
local function has(list, guid)
    for _, m in ipairs(list) do if m.guid == guid then return true end end
    return false
end

local function involvement(q) return #q.active + #q.done end

local function passes(q, opts)
    local who, status = opts.who, opts.status or "all"
    if who then
        if status == "active" and not has(q.active, who) then return false end
        if status == "done" and not has(q.done, who) then return false end
        if status == "dropped" and not has(q.dropped, who) then return false end
        if status == "all" and not (has(q.active, who) or has(q.done, who) or has(q.dropped, who)) then return false end
    else
        if status == "active" and #q.active == 0 then return false end
        if status == "done" and #q.done == 0 then return false end
        if status == "dropped" and #q.dropped == 0 then return false end
    end
    if opts.near and q.lv and math.abs(q.lv - opts.near) > NEAR_LEVELS then return false end
    if opts.search and opts.search ~= "" then
        local hay = (q.n .. " " .. (q.z or "")):lower()
        if not hay:find(opts.search, 1, true) then return false end
    end
    return true
end

local QUEST_ORDER = {
    level = function(a, b)
        if (a.lv or 999) ~= (b.lv or 999) then return (a.lv or 999) < (b.lv or 999) end
        return a.n < b.n
    end,
    name = function(a, b) return a.n < b.n end,
    goons = function(a, b)
        if involvement(a) ~= involvement(b) then return involvement(a) > involvement(b) end
        if (a.lv or 999) ~= (b.lv or 999) then return (a.lv or 999) < (b.lv or 999) end
        return a.n < b.n
    end,
}

local function zoneName(a, b)
    if (a.zone == OTHER) ~= (b.zone == OTHER) then return b.zone == OTHER end
    return a.zone < b.zone
end

local GROUP_ORDER = {
    level = function(a, b)
        if (a.minLv or 999) ~= (b.minLv or 999) then return (a.minLv or 999) < (b.minLv or 999) end
        return zoneName(a, b)
    end,
    name = zoneName,
    goons = function(a, b)
        if a.goons ~= b.goons then return a.goons > b.goons end
        return zoneName(a, b)
    end,
}

-- opts: status ("all"/"active"/"done"/"dropped"), search (lower case),
-- who (a member GUID), near (your level), sort ("level"/"name"/"goons").
-- Returns a list of { zone, quests, inProgress, completed, goons, minLv, maxLv }
-- and the number of quests that matched.
function GJ:QuestView(opts)
    opts = opts or {}
    local sort = QUEST_ORDER[opts.sort] and opts.sort or "level"
    local groups, byZone, total = {}, {}, 0
    for _, q in ipairs(self:GuildQuests()) do
        if passes(q, opts) then
            total = total + 1
            local zone = (q.z and q.z ~= "") and q.z or OTHER
            local g = byZone[zone]
            if not g then
                g = { zone = zone, quests = {}, inProgress = 0, completed = 0, goons = 0 }
                byZone[zone] = g
                groups[#groups + 1] = g
            end
            g.quests[#g.quests + 1] = q
            if #q.active > 0 then g.inProgress = g.inProgress + 1 end
            if #q.done > 0 then g.completed = g.completed + 1 end
            g.goons = g.goons + involvement(q)
            if q.lv then
                g.minLv = math.min(g.minLv or q.lv, q.lv)
                g.maxLv = math.max(g.maxLv or q.lv, q.lv)
            end
        end
    end
    for _, g in ipairs(groups) do table.sort(g.quests, QUEST_ORDER[sort]) end
    table.sort(groups, GROUP_ORDER[sort])
    return groups, total
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
-- "Bob, Alice, Carl +2" in class colours.
local function nameList(members)
    local parts = {}
    for i = 1, math.min(#members, NAMES_SHOWN) do
        parts[#parts + 1] = GJ:ColoredName(members[i])
    end
    local s = table.concat(parts, ", ")
    if #members > NAMES_SHOWN then s = s .. S.Wrap(C.faint, (" +%d"):format(#members - NAMES_SHOWN)) end
    return s
end

local function levelColor(level)
    if level and GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    end
    return C.muted
end

local function setChip(b, on)
    b.bgTex:SetVertexColor(unpack(on and C.cardHi or C.card))
    b.borderTex:SetVertexColor(unpack(on and C.accent or C.border))
    b.label:SetTextColor(unpack(on and C.text or C.muted))
end

local function chip(parent, text)
    local b = S.Button(parent, text, 0, 22)
    b:SetWidth(b.label:GetStringWidth() + 24)
    return b
end

local function fitLabel(b, text)
    b:SetLabel(text)
    b:SetWidth(b.label:GetStringWidth() + 24)
end

-- Small pop-up menu under a button. items = { { key, label, selected } }
local function openMenu(anchor, items, onPick)
    local menu = page.menu
    if menu:IsShown() and menu.anchor == anchor then menu:Hide() return end
    menu.anchor = anchor
    for _, b in ipairs(menu.buttons) do b:Hide() end
    local w = 120
    for i, item in ipairs(items) do
        local b = menu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetHeight(20)
            local hl = S.Fill(b, { 1, 1, 1, 0.07 }, "HIGHLIGHT")
            hl:SetAllPoints()
            b.text = S.Text(b, 12, C.text)
            b.text:SetPoint("LEFT", 10, 0)
            menu.buttons[i] = b
        end
        b.text:SetText(item[2])
        local c = item[3] and C.accent or C.text
        b.text:SetTextColor(c[1], c[2], c[3])
        b:SetScript("OnClick", function() menu:Hide() onPick(item[1]) end)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 1, -4 - (i - 1) * 20)
        b:SetPoint("TOPRIGHT", -1, -4 - (i - 1) * 20)
        b:Show()
        w = math.max(w, b.text:GetStringWidth() + 30)
    end
    menu:SetSize(w, #items * 20 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

local function getRow(i)
    local row = page.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, page.child)
    row:SetSize(page.width - 14, ROW_H)
    S.Panel(row, C.card, C.border)
    row.stripe = S.Fill(row, C.accent, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT", 1, -1)
    row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    row.stripe:SetWidth(3)
    row.level = S.Text(row, 12, C.muted, S.FONT)
    row.level:SetPoint("TOPLEFT", 14, -10)
    row.level:SetWidth(30)
    row.title = S.Text(row, 13, C.text, S.FONT)
    row.title:SetPoint("TOPLEFT", 46, -9)
    row.title:SetWidth(page.width * 0.48)
    row.sub = S.Text(row, 11, C.faint)
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
    row.sub:SetWidth(page.width * 0.48)
    row.active = S.Text(row, 11, C.text)
    row.active:SetPoint("TOPRIGHT", -12, -9)
    row.active:SetJustifyH("RIGHT")
    row.active:SetWidth(page.width * 0.42)
    row.done = S.Text(row, 11, C.text)
    row.done:SetPoint("TOPRIGHT", row.active, "BOTTOMRIGHT", 0, -5)
    row.done:SetJustifyH("RIGHT")
    row.done:SetWidth(page.width * 0.42)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(r)
        local q = r.quest
        if not q then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:AddLine(q.n)
        if q.z or q.lv then
            GameTooltip:AddLine(("%s%s"):format(q.lv and ("Level " .. q.lv) or "", q.z and ((q.lv and "  -  " or "") .. q.z) or ""), 0.6, 0.6, 0.6)
        end
        local function section(label, members, r1, g1, b1)
            if #members == 0 then return end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(label, r1, g1, b1)
            for _, m in ipairs(members) do GameTooltip:AddLine("  " .. GJ:ColoredName(m)) end
        end
        section("On it now", q.active, C.green[1], C.green[2], C.green[3])
        section("Completed", q.done, C.gold[1], C.gold[2], C.gold[3])
        section("Dropped it", q.dropped, C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    page.rows[i] = row
    return row
end

local function getHead(i)
    local h = page.heads[i]
    if h then return h end
    h = CreateFrame("Button", nil, page.child)
    h:SetSize(page.width - 14, HEAD_H)
    local hl = S.Fill(h, { 1, 1, 1, 0.05 }, "HIGHLIGHT")
    hl:SetAllPoints()
    h.line = S.Fill(h, C.border, "BACKGROUND")
    h.line:SetPoint("BOTTOMLEFT")
    h.line:SetPoint("BOTTOMRIGHT")
    h.line:SetHeight(1)
    h.toggle = S.Text(h, 14, C.accent, S.FONT)
    h.toggle:SetPoint("LEFT", 4, 0)
    h.toggle:SetWidth(14)
    h.name = S.Text(h, 14, C.text, S.FONT)
    h.name:SetPoint("LEFT", 22, 0)
    h.info = S.Text(h, 11, C.muted)
    h.info:SetPoint("RIGHT", -8, 0)
    h.info:SetJustifyH("RIGHT")
    h:SetScript("OnClick", function(self)
        local col = GJ.db.settings.questCollapsed
        col[self.zone] = not col[self.zone] or nil
        GJ:RefreshQuests()
    end)
    page.heads[i] = h
    return h
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function GJ:CreateQuestPage(parent, width, height)
    page.width = width

    -- Row 1: status chips, search box.
    page.statusButtons = {}
    local x = 0
    for _, def in ipairs(STATUS) do
        local b = chip(parent, def[2])
        b:SetPoint("TOPLEFT", x, 0)
        x = x + b:GetWidth() + 6
        b.key = def[1]
        b:SetScript("OnClick", function()
            page.status = def[1]
            GJ:RefreshQuests()
        end)
        page.statusButtons[#page.statusButtons + 1] = b
    end

    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(170, 22)
    box:SetPoint("TOPRIGHT", 0, 0)
    S.Panel(box, C.card, C.border)
    box:SetFont(S.FONT_BODY, 12, "")
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    local placeholder = S.Text(box, 12, C.faint)
    placeholder:SetPoint("LEFT", 8, 0)
    placeholder:SetText("Search quests or zones")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "")
        page.search = text:lower()
        GJ:RefreshQuests()
    end)

    -- Row 2: sort, goon, near my level, collapse/expand all, count.
    page.sortButton = chip(parent, "Sort: Level")
    page.sortButton:SetPoint("TOPLEFT", 0, -28)
    page.sortButton:SetScript("OnClick", function(self)
        local items = {}
        for _, def in ipairs(SORTS) do
            items[#items + 1] = { def[1], def[2], GJ.db.settings.questSort == def[1] }
        end
        openMenu(self, items, function(key)
            GJ.db.settings.questSort = key
            GJ:RefreshQuests()
        end)
    end)

    page.whoButton = chip(parent, "Goon: Everyone")
    page.whoButton:SetPoint("LEFT", page.sortButton, "RIGHT", 6, 0)
    page.whoButton:SetScript("OnClick", function(self)
        local items = {
            { false, "Everyone", page.who == nil },
            { GJ:PlayerGUID(), "Me", page.who == GJ:PlayerGUID() },
        }
        for _, m in ipairs(GJ:SortedMembers()) do
            if not GJ:IsMe(m.guid) and #items < 26 then
                items[#items + 1] = { m.guid, GJ:ColoredName(m), page.who == m.guid }
            end
        end
        openMenu(self, items, function(key)
            page.who = key or nil
            GJ:RefreshQuests()
        end)
    end)

    page.nearButton = chip(parent, "Near my level")
    page.nearButton:SetPoint("LEFT", page.whoButton, "RIGHT", 6, 0)
    page.nearButton:SetScript("OnClick", function()
        page.near = not page.near
        GJ:RefreshQuests()
    end)

    page.foldButton = chip(parent, "Collapse all")
    page.foldButton:SetPoint("TOPRIGHT", 0, -28)
    page.foldButton:SetScript("OnClick", function()
        local col = GJ.db.settings.questCollapsed
        if page.anyOpen then
            for _, g in ipairs(page.groups or {}) do col[g.zone] = true end
        else
            wipe(col)
        end
        GJ:RefreshQuests()
    end)

    page.count = S.Text(parent, 11, C.faint)
    page.count:SetPoint("RIGHT", page.foldButton, "LEFT", -10, 0)
    page.count:SetJustifyH("RIGHT")

    page.menu = CreateFrame("Frame", nil, parent)
    page.menu:SetFrameStrata("DIALOG")
    S.Panel(page.menu, C.bg, C.border)
    page.menu.buttons = {}
    page.menu:Hide()
    parent:HookScript("OnHide", function() page.menu:Hide() end)

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", 0, -60)
    holder:SetPoint("BOTTOMRIGHT")
    page.scroll, page.child = S.Scroll(holder, width - 12)
    page.empty = S.Text(holder, 13, C.muted)
    page.empty:SetPoint("TOP", 0, -40)
end

local function fillRow(row, q)
    local col = (#q.active > 0 and C.green) or (#q.done > 0 and C.gold) or C.faint
    row.stripe:SetVertexColor(col[1], col[2], col[3])
    local lc = levelColor(q.lv)
    row.level:SetText(q.lv and tostring(q.lv) or "")
    row.level:SetTextColor(lc[1], lc[2], lc[3])
    row.title:SetText(q.n)
    local bits = {}
    if #q.active > 0 then bits[#bits + 1] = S.Wrap(C.green, #q.active .. " on it") end
    if #q.done > 0 then bits[#bits + 1] = S.Wrap(C.gold, #q.done .. " done") end
    if #q.dropped > 0 then bits[#bits + 1] = #q.dropped .. " dropped" end
    row.sub:SetText(table.concat(bits, S.Wrap(C.faint, "  -  ")))
    if #q.active > 0 then
        row.active:SetText(S.Wrap(C.green, "On it: ") .. nameList(q.active))
    elseif #q.dropped > 0 and #q.done == 0 then
        row.active:SetText(S.Wrap(C.faint, "Dropped by ") .. nameList(q.dropped))
    else
        row.active:SetText("")
    end
    row.done:SetText(#q.done > 0 and (S.Wrap(C.gold, "Done: ") .. nameList(q.done)) or "")
end

function GJ:RefreshQuests()
    if not page.child then return end
    local settings = self.db.settings
    for _, b in ipairs(page.statusButtons) do setChip(b, b.key == page.status) end
    local sortKey = settings.questSort or "level"
    for _, def in ipairs(SORTS) do
        if def[1] == sortKey then fitLabel(page.sortButton, "Sort: " .. def[2]) end
    end
    setChip(page.sortButton, sortKey ~= "level")
    local whoName = "Everyone"
    if page.who then
        local m = self:GetMember(page.who)
        whoName = self:IsMe(page.who) and "Me" or (m and m.name) or "?"
    end
    fitLabel(page.whoButton, "Goon: " .. whoName)
    setChip(page.whoButton, page.who ~= nil)
    setChip(page.nearButton, page.near)

    for _, r in ipairs(page.rows) do r:Hide() end
    for _, h in ipairs(page.heads) do h:Hide() end

    local groups, total = self:QuestView({
        status = page.status, search = page.search, who = page.who, sort = sortKey,
        near = page.near and UnitLevel("player") or nil,
    })
    page.groups = groups
    local searching = page.search ~= ""
    local collapsed = settings.questCollapsed
    local shown, y, anyOpen = 0, 0, false
    for gi, g in ipairs(groups) do
        local closed = collapsed[g.zone] and not searching
        if not closed then anyOpen = true end
        local h = getHead(gi)
        h.zone = g.zone
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h.toggle:SetText(closed and "+" or "-")
        h.name:SetText(g.zone)
        local info = { #g.quests == 1 and "1 quest" or (#g.quests .. " quests") }
        if g.inProgress > 0 then info[#info + 1] = S.Wrap(C.green, g.inProgress .. " in progress") end
        if g.completed > 0 then info[#info + 1] = S.Wrap(C.gold, g.completed .. " done") end
        if g.minLv then
            info[#info + 1] = g.minLv == g.maxLv and ("level " .. g.minLv) or ("levels " .. g.minLv .. "-" .. g.maxLv)
        end
        h.info:SetText(table.concat(info, S.Wrap(C.faint, "   ")))
        h:Show()
        y = y + HEAD_H + 4
        if not closed then
            for _, q in ipairs(g.quests) do
                if shown < MAX_ROWS then
                    shown = shown + 1
                    local row = getRow(shown)
                    row.quest = q
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -y)
                    fillRow(row, q)
                    row:Show()
                    y = y + ROW_H + 6
                end
            end
            y = y + 6
        end
    end
    page.anyOpen = anyOpen
    fitLabel(page.foldButton, anyOpen and "Collapse all" or "Expand all")
    page.foldButton:SetShown(#groups > 0)
    page.child:SetHeight(math.max(10, y))

    if total == 0 and #self:GuildQuests() == 0 then
        page.empty:SetText("No quests yet. They show up here as goons pick them up.")
    elseif total == 0 then
        page.empty:SetText("No quests match these filters.")
    else
        page.empty:SetText("")
    end
    local areas = #groups == 1 and "1 area" or (#groups .. " areas")
    local label = (total == 1 and "1 quest" or (total .. " quests")) .. " in " .. areas
    if total > shown and shown >= MAX_ROWS then label = ("showing %d of %d - filter to narrow it down"):format(shown, total) end
    page.count:SetText(label)
    if page.scroll.UpdateThumb then page.scroll.UpdateThumb() end
end
