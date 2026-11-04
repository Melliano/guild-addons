-- Draws guildies' live positions (and the selected member's trail and death
-- spots) on top of the normal world map.
local _, GJ = ...

local overlay, dots, pins = nil, {}, {}
local dotsUsed, pinsUsed = 0, 0

local function canvasInfo()
    local wm = WorldMapFrame
    if not wm or not wm.ScrollContainer or not wm.ScrollContainer.Child then return nil end
    local canvas = wm.ScrollContainer.Child
    local scale = wm.ScrollContainer.GetCanvasScale and wm.ScrollContainer:GetCanvasScale() or 1
    return canvas, scale, wm:GetMapID()
end

local function ensureOverlay()
    if overlay then return overlay end
    local canvas = canvasInfo()
    if not canvas then return nil end
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 2000)
    return overlay
end

local function clear()
    for i = 1, dotsUsed do dots[i]:Hide() end
    for i = 1, pinsUsed do pins[i]:Hide() end
    dotsUsed, pinsUsed = 0, 0
end

-- Convert a position on mapID to a position on the shown map.
local function translate(fromMap, x, y, toMap)
    if fromMap == toMap then return x, y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local continent, world = C_Map.GetWorldPosFromMapPos(fromMap, CreateVector2D(x, y))
    if not continent or not world then return nil end
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, world, toMap)
    if not pos then return nil end
    local px, py = pos:GetXY()
    if px < 0 or px > 1 or py < 0 or py > 1 then return nil end
    return px, py
end

local function addDot(x, y, r, g, b, size, scale)
    dotsUsed = dotsUsed + 1
    local t = dots[dotsUsed]
    if not t then
        t = overlay:CreateTexture(nil, "OVERLAY")
        t:SetTexture(GJ.Style.CIRCLE)
        dots[dotsUsed] = t
    end
    local w, h = overlay:GetSize()
    t:SetSize(size / scale, size / scale)
    t:SetVertexColor(r, g, b, 0.55)
    t:ClearAllPoints()
    t:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
    t:Show()
end

local function addPin(x, y, texture, size, scale, title, lines, r, g, b, label)
    pinsUsed = pinsUsed + 1
    local p = pins[pinsUsed]
    if not p then
        p = CreateFrame("Button", nil, overlay)
        p.icon = p:CreateTexture(nil, "OVERLAY")
        p.icon:SetAllPoints()
        p.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        p.label:SetPoint("TOP", p, "BOTTOM", 0, -1)
        p:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(btn.title or "")
            for _, line in ipairs(btn.lines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", GameTooltip_Hide)
        pins[pinsUsed] = p
    end
    local w, h = overlay:GetSize()
    p:SetSize(size / scale, size / scale)
    p:SetFrameLevel(overlay:GetFrameLevel() + 10)
    p.icon:SetTexture(texture)
    p.icon:SetVertexColor(r or 1, g or 1, b or 1)
    p.label:SetText(label or "")
    p.label:SetScale(1 / scale)
    p.title, p.lines = title, lines
    p:ClearAllPoints()
    p:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
    p:Show()
end

function GJ:RefreshWorldMapOverlay()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    if not ensureOverlay() then return end
    clear()
    if not self.db.settings.worldMapOverlay then return end
    local _, scale, shownMap = canvasInfo()
    if not shownMap then return end
    scale = scale or 1

    -- Selected member's trail + deaths (only when looking at a zone they walked).
    local sel = self.selectedGUID and self:GetMember(self.selectedGUID)
    if sel and self.showTrailOnWorldMap then
        local r, g, b = self:ClassColor(sel.class)
        for _, c in ipairs(self:CellsOnMap(sel, shownMap)) do
            addDot(c[1], c[2], r, g, b, 7, scale)
        end
        for _, ev in ipairs(sel.events) do
            if ev.k == "death" and ev.m == shownMap and ev.x then
                addPin(ev.x / 1000, ev.y / 1000, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 14, scale,
                    sel.name .. " died here", { self:EventText(ev), date("%d %b %Y %H:%M", ev.t) })
            end
        end
    end

    -- Live guildies.
    for _, m in pairs(self.db.members) do
        if not self:IsMe(m.guid) and self:IsOnline(m) and m.live and m.live.m and m.live.x then
            local x, y = translate(m.live.m, m.live.x / 1000, m.live.y / 1000, shownMap)
            if x then
                local r, g, b = self:ClassColor(m.class)
                local lines = { ("Level %d %s"):format(m.level or 0, m.class and (LOCALIZED_CLASS_NAMES_MALE[m.class] or m.class) or "") }
                if m.live.z then lines[#lines + 1] = m.live.z end
                if m.live.dead then lines[#lines + 1] = "|cffff5555Currently dead|r" end
                addPin(x, y, GJ.Style.CIRCLE, 12, scale, m.name, lines, r, g, b, m.name)
            end
        end
    end
end

local hooked = false
local function hookWorldMap()
    if hooked or not WorldMapFrame then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", function() GJ:RefreshWorldMapOverlay() end)
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function() GJ:RefreshWorldMapOverlay() end)
    end
    -- Zooming changes the canvas scale; refresh occasionally while open.
    local elapsed, lastScale = 0, nil
    WorldMapFrame:HookScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        local _, scale = canvasInfo()
        if scale ~= lastScale then
            lastScale = scale
            GJ:RefreshWorldMapOverlay()
        end
    end)
end

GJ:On("GJ_LOGIN", hookWorldMap)
GJ:On("GJ_LIVE_UPDATED", function()
    if WorldMapFrame and WorldMapFrame:IsShown() then GJ:RefreshWorldMapOverlay() end
end)

-- Open the world map on a member's map with their trail shown.
function GJ:ShowOnWorldMap(guid, mapID)
    self.selectedGUID = guid
    self.showTrailOnWorldMap = true
    if not WorldMapFrame then return end
    if InCombatLockdown() then
        self:Print("Can't open the world map in combat - press M after the fight and the trail will be there.")
        return
    end
    if not WorldMapFrame:IsShown() then
        if ToggleWorldMap then ToggleWorldMap() else WorldMapFrame:Show() end
    end
    if mapID then WorldMapFrame:SetMapID(mapID) end
    self:RefreshWorldMapOverlay()
end
