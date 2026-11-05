-- Guild death map: every goon's deaths on one map, zone by zone. Hover a
-- skull to see who died and to what; click it to open their journey.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

-- All guild deaths grouped by map. Returns a list sorted by most deaths:
-- { mapID, count, deaths = { { m = member, ev = event }, ... } }
function GJ:GuildDeathMaps()
    local byMap = {}
    for _, m in ipairs(self:SortedMembers()) do
        for _, ev in ipairs(m.events) do
            if ev.k == "death" and not ev.dup and ev.m then
                local entry = byMap[ev.m]
                if not entry then
                    entry = { mapID = ev.m, count = 0, deaths = {} }
                    byMap[ev.m] = entry
                end
                entry.count = entry.count + 1
                entry.deaths[#entry.deaths + 1] = { m = m, ev = ev }
            end
        end
    end
    local list = {}
    for _, entry in pairs(byMap) do list[#list + 1] = entry end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.mapID < b.mapID
    end)
    return list
end

-- The most frequent killer in a list of deaths: name, count.
local function deadliest(deaths)
    local counts, best, bestN = {}, nil, 0
    for _, d in ipairs(deaths) do
        local killer = d.ev.d
        if type(killer) == "string" and killer ~= "unknown causes" then
            counts[killer] = (counts[killer] or 0) + 1
            if counts[killer] > bestN then best, bestN = killer, counts[killer] end
        end
    end
    return best, bestN
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local page = {}

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

function GJ:CreateDeathMapPage(parent, width, height)
    page.canvas = self:CreateMapCanvas(parent, width, height)
    page.canvas.frame:SetPoint("TOPLEFT")
    local holder = page.canvas.frame

    -- Zone picker (top-left).
    local zc = chip(holder, 28)
    zc:SetPoint("TOPLEFT", 10, -10)
    local prev = arrow(zc, "<")
    prev:SetPoint("LEFT", 2, 0)
    page.label = S.Text(zc, 13, C.text, S.FONT)
    page.label:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    local nextB = arrow(zc, ">")
    nextB:SetPoint("LEFT", page.label, "RIGHT", 6, 0)
    page.zoneChip = zc

    local function step(d)
        if not page.list or #page.list == 0 then return end
        page.index = (((page.index or 1) - 1 + d) % #page.list) + 1
        GJ:DrawDeathMap()
    end
    prev:SetScript("OnClick", function() step(-1) end)
    nextB:SetScript("OnClick", function() step(1) end)

    -- Hint (bottom-left).
    local hint = chip(holder, 26)
    hint:SetPoint("BOTTOMLEFT", 10, 10)
    local skull = hint:CreateTexture(nil, "OVERLAY")
    skull:SetSize(12, 12)
    skull:SetPoint("LEFT", 10, 0)
    skull:SetTexture(SKULL)
    local ht = S.Text(hint, 11, C.muted)
    ht:SetPoint("LEFT", skull, "RIGHT", 6, 0)
    ht:SetText("Ring colour = class. Click a skull to open that goon's journey.")
    hint:SetWidth(ht:GetStringWidth() + 38)

    -- Count and deadliest killer (bottom-right).
    local cc = chip(holder, 26)
    cc:SetPoint("BOTTOMRIGHT", -10, 10)
    page.count = S.Text(cc, 11, C.text)
    page.count:SetPoint("CENTER")
    page.countChip = cc
end

function GJ:DrawDeathMap()
    local canvas = page.canvas
    if not canvas then return end
    canvas:Clear()
    local list = page.list or {}
    local entry = list[page.index or 1]
    if not entry then
        canvas:SetMap(nil)
        canvas.empty:SetText("No goon has died yet. Give it time.")
        page.label:SetText("No deaths yet")
        page.zoneChip:SetWidth(page.label:GetStringWidth() + 74)
        page.count:SetText("0 deaths")
        page.countChip:SetWidth(page.count:GetStringWidth() + 20)
        return
    end
    canvas:SetMap(entry.mapID)
    page.label:SetText(("%s  %s"):format(self:MapName(entry.mapID), S.Wrap(C.faint, (page.index or 1) .. "/" .. #list)))
    page.zoneChip:SetWidth(page.label:GetStringWidth() + 74)

    for _, d in ipairs(entry.deaths) do
        local m, ev = d.m, d.ev
        if ev.x and ev.y then
            local r, g, b = self:ClassColor(m.class)
            local guid = m.guid
            local p = canvas:AddPin(ev.x / 1000, ev.y / 1000, SKULL, 16,
                self:ColoredName(m) .. S.Wrap(C.red, " died here"),
                {
                    "Killed by " .. tostring(ev.d or "unknown causes"),
                    "Level " .. tostring(ev.l or "?"),
                    date("%d %b %Y %H:%M", ev.t or 0),
                })
            p.icon:SetTexCoord(0, 1, 0, 1)
            p.ring:SetVertexColor(r, g, b, 0.95)
            p.onClick = function()
                if GJ.ui and GJ.ui.frame and not GJ.ui.frame:IsShown() then GJ:ToggleUI() end
                GJ:SelectMember(guid)
            end
        end
    end

    local text = entry.count == 1 and "1 death" or (entry.count .. " deaths")
    local killer, n = deadliest(entry.deaths)
    if killer and n > 1 then
        text = text .. "   " .. S.Wrap(C.muted, "Deadliest: ") .. S.Wrap(C.red, ("%s (%d)"):format(killer, n))
    end
    page.count:SetText(text)
    page.countChip:SetWidth(page.count:GetStringWidth() + 20)
end

function GJ:RefreshDeathMap()
    if not page.canvas then return end
    local prevMap = page.list and page.list[page.index or 1] and page.list[page.index or 1].mapID
    page.list = self:GuildDeathMaps()
    page.index = 1
    if prevMap then
        for i, entry in ipairs(page.list) do
            if entry.mapID == prevMap then page.index = i break end
        end
    end
    self:DrawDeathMap()
end
