-- Race to max level: a line chart of level against /played for the guild,
-- plus "fastest to level X" cards (the same data as text).
local _, GJ = ...
local S = GJ.Style
local C = S.C

local MAX_SERIES = 8
local LABEL_MAX = 4  -- direct-label lines only when there are few of them
local MILESTONES = { 10, 20, 30, 40, 50, 60 }

local race = {}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
-- Sorted { level, playedSeconds } points for a member.
function GJ:LevelCurve(m)
    local byLevel = {}
    local s = m.stats or {}
    if type(s.lvlp) == "table" then
        for lvl, p in pairs(s.lvlp) do
            if type(lvl) == "number" and type(p) == "number" then byLevel[lvl] = p end
        end
    end
    for _, ev in ipairs(m.events) do
        if ev.k == "level" and type(ev.d) == "number" and type(ev.p) == "number" and not byLevel[ev.d] then
            byLevel[ev.d] = ev.p
        end
    end
    local pts = {}
    for lvl, p in pairs(byLevel) do pts[#pts + 1] = { lvl, p } end
    table.sort(pts, function(a, b) return a[1] < b[1] end)
    -- Current position: where they are right now.
    local last = pts[#pts]
    local played = s.played
    if played and m.level and (not last or (m.level >= last[1] and played > last[2])) then
        pts[#pts + 1] = { m.level, played, current = true }
    end
    return pts
end

function GJ:TimeToLevel(m, level)
    local s = m.stats or {}
    if type(s.lvlp) == "table" and type(s.lvlp[level]) == "number" then return s.lvlp[level] end
    for _, ev in ipairs(m.events) do
        if ev.k == "level" and ev.d == level and type(ev.p) == "number" then return ev.p end
    end
    return nil
end

local function niceMax(hours)
    for _, step in ipairs({ 1, 2, 4, 6, 12, 24, 48, 72, 96, 120, 168, 240, 336, 480, 720 }) do
        if hours <= step then return step end
    end
    return math.ceil(hours / 240) * 240
end

local function hoursLabel(h)
    if h >= 48 then return ("%dd"):format(h / 24) end
    return ("%dh"):format(h)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function GJ:CreateRacePage(page, width, height)
    race.page = page
    race.width = width

    race.legend = CreateFrame("Frame", nil, page)
    race.legend:SetPoint("TOPLEFT")
    race.legend:SetSize(width, 16)
    race.legendItems = {}

    local chartH = height - 16 - 8 - 112
    local chart = CreateFrame("Frame", nil, page)
    chart:SetPoint("TOPLEFT", 0, -24)
    chart:SetSize(width, chartH)
    S.Panel(chart, C.card, C.border)
    race.chart = chart

    local plot = CreateFrame("Frame", nil, chart)
    plot:SetPoint("TOPLEFT", 36, -14)
    plot:SetPoint("BOTTOMRIGHT", -84, 26)
    race.plot = plot
    race.plotW, race.plotH = width - 36 - 84, chartH - 14 - 26

    race.grid, race.yLabels, race.xLabels = {}, {}, {}
    race.lines, race.markers, race.hits, race.labels = {}, {}, {}, {}

    race.empty = S.Text(chart, 13, C.muted)
    race.empty:SetPoint("CENTER")
    race.empty:SetJustifyH("CENTER")

    race.axisTitle = S.Text(chart, 10, C.faint)
    race.axisTitle:SetPoint("BOTTOMRIGHT", -12, 7)
    race.axisTitle:SetJustifyH("RIGHT")
    race.axisTitle:SetText("hours played")

    -- Fastest-to cards
    local head = S.Text(page, 11, C.muted, S.FONT)
    head:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 2, -10)
    head:SetText("FASTEST TO LEVEL")
    race.cards = {}
    local cols, gap = 3, 8
    local w = (width - (cols - 1) * gap) / cols
    for i, lvl in ipairs(MILESTONES) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local card = CreateFrame("Frame", nil, page)
        card:SetSize(w, 40)
        card:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", col * (w + gap), -28 - row * 46)
        S.Panel(card, C.card, C.border)
        card.lvl = S.Text(card, 16, C.accent, S.FONT)
        card.lvl:SetPoint("LEFT", 12, 0)
        card.lvl:SetText(lvl)
        card.name = S.Text(card, 12, C.text)
        card.name:SetPoint("TOPLEFT", 46, -6)
        card.name:SetWidth(w - 56)
        card.sub = S.Text(card, 11, C.muted)
        card.sub:SetPoint("BOTTOMLEFT", 46, 6)
        card.sub:SetWidth(w - 56)
        race.cards[i] = card
    end
end

local function pooled(list, i, make)
    local o = list[i]
    if not o then o = make() list[i] = o end
    o:Show()
    return o
end

local function hideFrom(list, n)
    for i = n + 1, #list do list[i]:Hide() end
end

function GJ:RefreshRace()
    if not race.plot then return end
    local plot = race.plot
    local members = self:SortedMembers()

    -- Series: goons with a curve, highest level first.
    local series = {}
    for _, m in ipairs(members) do
        local pts = self:LevelCurve(m)
        if #pts >= 1 then series[#series + 1] = { m = m, pts = pts } end
    end
    table.sort(series, function(a, b)
        local la, lb = a.pts[#a.pts][1], b.pts[#b.pts][1]
        if la ~= lb then return la > lb end
        return a.pts[#a.pts][2] < b.pts[#b.pts][2]
    end)
    local hidden = math.max(0, #series - MAX_SERIES)
    while #series > MAX_SERIES do table.remove(series) end

    local maxPlayed, maxLevel = 1, 10
    for _, sr in ipairs(series) do
        for _, p in ipairs(sr.pts) do
            if p[2] > maxPlayed then maxPlayed = p[2] end
            if p[1] > maxLevel then maxLevel = p[1] end
        end
    end
    local xMax = niceMax(maxPlayed / 3600)
    local yMax = math.min(60, math.ceil(maxLevel / 10) * 10)
    if yMax < 10 then yMax = 10 end
    local W, H = race.plotW, race.plotH
    local function px(played) return (played / 3600) / xMax * W end
    local function py(level) return (level / yMax) * H end

    -- Grid + axis labels (recessive).
    local gi = 0
    for lvl = 0, yMax, 10 do
        gi = gi + 1
        local g = pooled(race.grid, gi, function() return S.Fill(plot, { 1, 1, 1, 0.06 }, "BACKGROUND", 1) end)
        g:ClearAllPoints()
        g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, py(lvl))
        g:SetSize(W, 1)
        local l = pooled(race.yLabels, gi, function() return S.Text(plot, 10, C.faint) end)
        l:ClearAllPoints()
        l:SetPoint("RIGHT", plot, "BOTTOMLEFT", -8, py(lvl))
        l:SetJustifyH("RIGHT")
        l:SetText(lvl)
    end
    hideFrom(race.grid, gi)
    hideFrom(race.yLabels, gi)
    local xi = 0
    for i = 0, 4 do
        xi = xi + 1
        local h = xMax * i / 4
        local l = pooled(race.xLabels, xi, function() return S.Text(plot, 10, C.faint) end)
        l:ClearAllPoints()
        l:SetPoint("TOP", plot, "BOTTOMLEFT", W * i / 4, -6)
        l:SetJustifyH("CENTER")
        l:SetText(hoursLabel(h))
    end
    hideFrom(race.xLabels, xi)

    -- Lines, end markers, hover targets.
    local li, mi, hi = 0, 0, 0
    local ends = {}
    for _, sr in ipairs(series) do
        local r, g, b = self:ClassColor(sr.m.class)
        local pts = sr.pts
        for i = 2, #pts do
            li = li + 1
            local line = pooled(race.lines, li, function()
                local ln = plot:CreateLine(nil, "ARTWORK")
                ln:SetThickness(2)
                return ln
            end)
            line:SetColorTexture(r, g, b, 1)
            line:SetStartPoint("BOTTOMLEFT", plot, px(pts[i - 1][2]), py(pts[i - 1][1]))
            line:SetEndPoint("BOTTOMLEFT", plot, px(pts[i][2]), py(pts[i][1]))
        end
        for i, p in ipairs(pts) do
            hi = hi + 1
            local hit = pooled(race.hits, hi, function()
                local h = CreateFrame("Frame", nil, plot)
                h:SetSize(14, 14)
                h:EnableMouse(true)
                h.dot = S.Circle(h, 6, nil, "OVERLAY")
                h.dot:SetPoint("CENTER")
                h:SetScript("OnEnter", function(self)
                    self.dot:Show()
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.title)
                    GameTooltip:AddLine(self.text, 1, 1, 1)
                    GameTooltip:Show()
                end)
                h:SetScript("OnLeave", function(self) self.dot:Hide() GameTooltip:Hide() end)
                return h
            end)
            hit:SetFrameLevel(plot:GetFrameLevel() + 5)
            hit:ClearAllPoints()
            hit:SetPoint("CENTER", plot, "BOTTOMLEFT", px(p[2]), py(p[1]))
            hit.dot:SetVertexColor(r, g, b, 1)
            hit.dot:Hide()
            hit.title = self:ColoredName(sr.m)
            hit.text = p.current
                and ("Level %d now, %s played"):format(p[1], self:FormatDuration(p[2]))
                or ("Reached level %d at %s played"):format(p[1], self:FormatDuration(p[2]))
        end
        -- End marker: 8px dot with a 2px surface ring.
        local last = pts[#pts]
        mi = mi + 1
        local mk = pooled(race.markers, mi, function()
            local f = CreateFrame("Frame", nil, plot)
            f:SetSize(12, 12)
            f.ring = S.Circle(f, 12, C.card, "ARTWORK")
            f.ring:SetPoint("CENTER")
            f.dot = S.Circle(f, 8, nil, "OVERLAY")
            f.dot:SetPoint("CENTER")
            return f
        end)
        mk:SetFrameLevel(plot:GetFrameLevel() + 3)
        mk:ClearAllPoints()
        mk:SetPoint("CENTER", plot, "BOTTOMLEFT", px(last[2]), py(last[1]))
        mk.dot:SetVertexColor(r, g, b, 1)
        ends[#ends + 1] = { sr = sr, x = px(last[2]), y = py(last[1]) }
    end
    hideFrom(race.lines, li)
    hideFrom(race.hits, hi)
    hideFrom(race.markers, mi)

    -- Direct labels (few series only), nudged apart vertically.
    local lbi = 0
    if #ends <= LABEL_MAX then
        table.sort(ends, function(a, b) return a.y < b.y end)
        local lastY = -100
        for _, e in ipairs(ends) do
            local y = math.max(e.y, lastY + 13)
            lastY = y
            lbi = lbi + 1
            local l = pooled(race.labels, lbi, function() return S.Text(plot, 11, C.text) end)
            l:ClearAllPoints()
            l:SetPoint("LEFT", plot, "BOTTOMLEFT", e.x + 9, y)
            l:SetText(e.sr.m.name or "?")
        end
    end
    hideFrom(race.labels, lbi)

    -- Legend (always, for 2+ series).
    local x, gi2 = 0, 0
    if #series >= 2 then
        for _, sr in ipairs(series) do
            gi2 = gi2 + 1
            local item = pooled(race.legendItems, gi2, function()
                local f = CreateFrame("Frame", nil, race.legend)
                f:SetSize(10, 16)
                f.dot = S.Circle(f, 8, nil, "ARTWORK")
                f.dot:SetPoint("LEFT")
                f.text = S.Text(f, 11, C.muted)
                f.text:SetPoint("LEFT", f.dot, "RIGHT", 5, 0)
                return f
            end)
            local r, g, b = self:ClassColor(sr.m.class)
            item.dot:SetVertexColor(r, g, b, 1)
            item.text:SetText(sr.m.name or "?")
            item:ClearAllPoints()
            item:SetPoint("LEFT", race.legend, "LEFT", x, 0)
            x = x + 8 + 5 + item.text:GetStringWidth() + 16
        end
    end
    hideFrom(race.legendItems, gi2)
    if hidden > 0 then
        gi2 = gi2 + 1
        local more = pooled(race.legendItems, gi2, function()
            local f = CreateFrame("Frame", nil, race.legend)
            f:SetSize(10, 16)
            f.dot = S.Circle(f, 8, nil, "ARTWORK")
            f.dot:SetPoint("LEFT")
            f.text = S.Text(f, 11, C.muted)
            f.text:SetPoint("LEFT", f.dot, "RIGHT", 5, 0)
            return f
        end)
        more.dot:SetVertexColor(0, 0, 0, 0)
        more.text:SetText(("+%d more"):format(hidden))
        more:ClearAllPoints()
        more:SetPoint("LEFT", race.legend, "LEFT", x, 0)
    end

    local anyLine = li > 0
    race.empty:SetText(anyLine and "" or "The race starts now - every ding is timed from here on.")
    race.axisTitle:SetShown(anyLine)
    for _, l in ipairs(race.xLabels) do l:SetShown(anyLine) end
    for _, l in ipairs(race.yLabels) do l:SetShown(anyLine) end
    for _, g in ipairs(race.grid) do g:SetShown(anyLine) end

    -- Fastest-to cards.
    for i, lvl in ipairs(MILESTONES) do
        local times = {}
        for _, m in ipairs(members) do
            local t = self:TimeToLevel(m, lvl)
            if t then times[#times + 1] = { m, t } end
        end
        table.sort(times, function(a, b) return a[2] < b[2] end)
        local card = race.cards[i]
        if times[1] then
            card.name:SetText(("%s  %s"):format(self:ColoredName(times[1][1]), S.Wrap(C.muted, self:FormatDuration(times[1][2]))))
            card.sub:SetText(times[2] and ("2nd: %s  %s"):format(times[2][1].name or "?", self:FormatDuration(times[2][2])) or "No challengers yet")
            card.lvl:SetTextColor(unpack(C.accent))
        else
            card.name:SetText(S.Wrap(C.faint, "Nobody yet"))
            card.sub:SetText("")
            card.lvl:SetTextColor(unpack(C.faint))
        end
    end
end
