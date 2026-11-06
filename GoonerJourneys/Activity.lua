-- Guild activity feed ("Latest" tab): everything newsworthy every goon has
-- done, newest first and grouped by day, so nothing is missed while you
-- were offline. Built from the synced timelines; nothing extra is sent.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local MAX_ITEMS = 150
local ROW_H = 50
local HEAD_H = 26

local KIND_COLOR = {
    death = C.red, silly = C.gold, level = C.accent, boss = { 0.70, 0.45, 1 },
    raid = { 1, 0.5, 0.2 }, dungeon = { 0.35, 0.65, 1 }, item = { 0.65, 0.4, 1 },
    rank = C.green,
}

-- Newest-first list of { t, m = member, kind, icon, title, detail }.
function GJ:GuildActivity(limit)
    local items = {}
    for _, m in ipairs(self:SortedMembers()) do
        local score, rankIdx = 0, 1
        for _, ev in ipairs(m.events) do
            if type(ev) == "table" and not ev.dup then
                local title, detail = self:NewsText(m, ev)
                if title then
                    items[#items + 1] = { t = ev.t or 0, m = m, kind = ev.k, icon = self:EventIcon(ev),
                        title = title, detail = detail }
                end
                -- Replay the Gooner Score to spot rank-ups.
                score = score + self:EventPoints(ev)
                local rankName, idx = self:Rank(score)
                if idx > rankIdx then
                    rankIdx = idx
                    local who = self:IsMe(m.guid) and "You are" or ((m.name or "Someone") .. " is")
                    items[#items + 1] = { t = ev.t or 0, m = m, kind = "rank",
                        icon = "Interface\\Icons\\INV_Misc_Toy_07",
                        title = ("%s now a %s"):format(who, rankName),
                        detail = ("Gooner Score %d"):format(score), after = true }
                end
            end
        end
    end
    table.sort(items, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return (a.after and 1 or 0) > (b.after and 1 or 0) -- rank-up above the event that caused it
    end)
    limit = limit or MAX_ITEMS
    for i = #items, limit + 1, -1 do items[i] = nil end
    return items
end

local function dayLabel(t)
    local key = date("%Y-%m-%d", t)
    local now = GJ:Now()
    if key == date("%Y-%m-%d", now) then return "TODAY" end
    if key == date("%Y-%m-%d", now - 86400) then return "YESTERDAY" end
    return date("%A %d %B", t):upper()
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local page = { rows = {}, heads = {} }

local function getHead(i)
    local h = page.heads[i]
    if h then return h end
    h = S.Text(page.child, 11, C.muted, S.FONT)
    page.heads[i] = h
    return h
end

local function getRow(i)
    local row = page.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, page.child)
    row:SetSize(page.width - 14, ROW_H)
    S.Panel(row, C.card, C.border)
    local hl = S.Fill(row, { 1, 1, 1, 0.04 }, "HIGHLIGHT")
    hl:SetAllPoints()
    row.stripe = S.Fill(row, C.accent, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT", 1, -1)
    row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    row.stripe:SetWidth(3)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", 14, 0)
    S.RoundMask(row, row.icon)
    row.title = S.Text(row, 13, C.text, S.FONT)
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, -1)
    row.title:SetWidth(page.width - 220)
    row.detail = S.Text(row, 11, C.muted)
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
    row.detail:SetWidth(page.width - 220)
    row.when = S.Text(row, 11, C.faint)
    row.when:SetPoint("RIGHT", -14, 0)
    row.when:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(r) if r.guid then GJ:SelectMember(r.guid) end end)
    row:SetScript("OnEnter", function(r)
        if not r.t then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:AddLine(date("%d %b %Y  %H:%M", r.t))
        GameTooltip:AddLine("Click to open their journey", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    page.rows[i] = row
    return row
end

function GJ:CreateActivityPage(parent, width, height)
    page.width = width
    page.count = S.Text(parent, 11, C.faint)
    page.count:SetPoint("TOPRIGHT", 0, 0)
    page.count:SetJustifyH("RIGHT")
    local intro = S.Text(parent, 11, C.muted)
    intro:SetPoint("TOPLEFT", 0, 0)
    intro:SetText("What the goons have been up to. Click anything to open their journey.")

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", 0, -22)
    holder:SetPoint("BOTTOMRIGHT")
    page.scroll, page.child = S.Scroll(holder, width - 12)
    page.empty = S.Text(holder, 13, C.muted)
    page.empty:SetPoint("TOP", 0, -40)
end

function GJ:RefreshActivity()
    if not page.child then return end
    for _, r in ipairs(page.rows) do r:Hide() end
    for _, h in ipairs(page.heads) do h:Hide() end

    local items = self:GuildActivity()
    local y, ri, hi, lastDay = 0, 0, 0, nil
    for _, it in ipairs(items) do
        local day = dayLabel(it.t)
        if day ~= lastDay then
            lastDay = day
            hi = hi + 1
            local h = getHead(hi)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 2, -(y + 8))
            h:SetText(day)
            h:Show()
            y = y + HEAD_H
        end
        ri = ri + 1
        local row = getRow(ri)
        row.guid, row.t = it.m.guid, it.t
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        local col = KIND_COLOR[it.kind] or C.accent
        row.stripe:SetVertexColor(col[1], col[2], col[3])
        row.icon:SetTexture(it.icon)
        local r, g, b = self:ClassColor(it.m.class)
        row.title:SetText(it.title)
        row.title:SetTextColor(r, g, b)
        row.detail:SetText(it.detail or "")
        row.when:SetText(self:FormatAgo(it.t))
        row:Show()
        y = y + ROW_H + 6
    end
    page.child:SetHeight(math.max(10, y))
    page.empty:SetText(#items == 0 and "Nothing yet. Go make some memories." or "")
    page.count:SetText(#items >= MAX_ITEMS and ("latest " .. MAX_ITEMS) or "")
    if page.scroll.UpdateThumb then page.scroll.UpdateThumb() end
end
