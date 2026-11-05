-- Map widget for the Journey Map tab: draws a zone's map art (cropped so
-- the old parchment edges don't show), a soft trail, pins and a pulsing
-- "here now" marker.
local _, GJ = ...
local S = GJ.Style

local Canvas = {}
Canvas.__index = Canvas

local CROP = 0.035 -- trim this fraction off each side of the map art

function GJ:CreateMapCanvas(parent, width, height)
    local self = setmetatable({}, Canvas)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    f:SetClipsChildren(true)
    S.Panel(f, { 0.03, 0.035, 0.045, 1 }, S.C.border)
    self.frame = f
    self.width, self.height = width, height
    self.tiles, self.dots, self.pins = {}, {}, {}
    self.dotsUsed, self.pinsUsed = 0, 0

    self.art = CreateFrame("Frame", nil, f)
    self.art:SetPoint("TOPLEFT", 1, -1)
    self.art:SetPoint("BOTTOMRIGHT", -1, 1)
    self.art:SetClipsChildren(true)

    -- Slight darkening so the trail pops.
    local shade = S.Fill(self.art, { 0, 0, 0, 0.22 }, "ARTWORK", 5)
    shade:SetAllPoints()

    self.dotLayer = CreateFrame("Frame", nil, self.art)
    self.dotLayer:SetAllPoints()
    self.dotLayer:SetFrameLevel(self.art:GetFrameLevel() + 2)

    -- Edge vignette.
    local function edge(point1, point2, w, h, horiz, flip)
        local t = self.art:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetTexture(S.WHITE)
        t:SetPoint(point1)
        t:SetPoint(point2)
        if w then t:SetWidth(w) else t:SetHeight(h) end
        local a, b = CreateColor and CreateColor(0, 0, 0, 0.55), CreateColor and CreateColor(0, 0, 0, 0)
        if a and t.SetGradient then
            if flip then a, b = b, a end
            pcall(t.SetGradient, t, horiz and "HORIZONTAL" or "VERTICAL", a, b)
        else
            t:SetVertexColor(0, 0, 0, 0)
        end
    end
    edge("TOPLEFT", "BOTTOMLEFT", 40, nil, true, false)
    edge("TOPRIGHT", "BOTTOMRIGHT", 40, nil, true, true)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 40, false, false)
    edge("TOPLEFT", "TOPRIGHT", nil, 40, false, true)

    self.empty = S.Text(f, 14, S.C.muted, S.FONT)
    self.empty:SetPoint("CENTER")

    -- "Here now" marker.
    local here = CreateFrame("Frame", nil, self.dotLayer)
    here:SetSize(40, 40)
    here:SetFrameLevel(self.dotLayer:GetFrameLevel() + 20)
    -- White marker with a black outline and white pulse, so it never blends
    -- into the (class coloured) trail or the map.
    here.ring = S.Circle(here, 44, { 1, 1, 1, 0.9 }, "ARTWORK")
    here.ring:SetPoint("CENTER")
    S.Pulse(here.ring, 0.3, 1, 1.6)
    here.outline = here:CreateTexture(nil, "OVERLAY", nil, 0)
    here.outline:SetTexture(S.CIRCLE)
    here.outline:SetSize(22, 22)
    here.outline:SetVertexColor(0, 0, 0, 1)
    here.outline:SetPoint("CENTER")
    here.dot = here:CreateTexture(nil, "OVERLAY", nil, 2)
    here.dot:SetTexture(S.CIRCLE)
    here.dot:SetSize(16, 16)
    here.dot:SetVertexColor(1, 1, 1, 1)
    here.dot:SetPoint("CENTER")
    here:Hide()
    self.here = here
    return self
end

-- Map 0..1 map coords into canvas pixels (accounting for the crop).
function Canvas:ToPixels(x, y)
    if not self.artW then return x * self.width, y * self.height end
    return x * self.artW - self.offX, y * self.artH - self.offY
end

function Canvas:SetMap(mapID)
    self.mapID = mapID
    for _, t in ipairs(self.tiles) do t:Hide() end
    self.empty:SetText("")
    self.artW = nil
    if not mapID then
        self.empty:SetText("No journey recorded yet")
        return
    end
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    local textures = C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(mapID, 1)
    if not layer or not textures or #textures == 0 then
        self.empty:SetText(GJ:MapName(mapID))
        return
    end
    -- Scale so the cropped art covers the whole canvas.
    local innerW, innerH = self.width - 2, self.height - 2
    local visW, visH = layer.layerWidth * (1 - 2 * CROP), layer.layerHeight * (1 - 2 * CROP)
    local scale = math.max(innerW / visW, innerH / visH)
    self.artW, self.artH = layer.layerWidth * scale, layer.layerHeight * scale
    self.offX = (self.artW - innerW) / 2
    self.offY = (self.artH - innerH) / 2

    local cols = math.ceil(layer.layerWidth / layer.tileWidth)
    local tw, th = layer.tileWidth * scale, layer.tileHeight * scale
    for i, fileID in ipairs(textures) do
        local t = self.tiles[i]
        if not t then
            t = self.art:CreateTexture(nil, "BACKGROUND")
            self.tiles[i] = t
        end
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        t:ClearAllPoints()
        t:SetSize(tw, th)
        t:SetPoint("TOPLEFT", self.art, "TOPLEFT", col * tw - self.offX, -row * th + self.offY)
        t:SetTexture(fileID)
        t:SetDesaturation(0.25)
        t:Show()
    end
end

function Canvas:Clear()
    for i = 1, self.dotsUsed do self.dots[i]:Hide() end
    for i = 1, self.pinsUsed do self.pins[i]:Hide() end
    self.dotsUsed, self.pinsUsed = 0, 0
    self.here:Hide()
end

-- Soft round trail dot; size is relative to one grid cell so neighbouring
-- cells blend into a path.
function Canvas:AddDot(x, y, r, g, b, a, size)
    self.dotsUsed = self.dotsUsed + 1
    local t = self.dots[self.dotsUsed]
    if not t then
        t = self.dotLayer:CreateTexture(nil, "ARTWORK")
        t:SetTexture(S.CIRCLE)
        self.dots[self.dotsUsed] = t
    end
    local cell = (self.artW or self.width) / GJ.GRID
    size = size or math.max(6, cell * 1.6)
    t:SetSize(size, size)
    t:SetVertexColor(r, g, b, a or 0.55)
    local px, py = self:ToPixels(x, y)
    t:ClearAllPoints()
    t:SetPoint("CENTER", self.dotLayer, "TOPLEFT", px, -py)
    t:Show()
    return t
end

-- Interactive pin with an icon (shown round) and tooltip lines.
function Canvas:AddPin(x, y, texture, size, tooltipTitle, tooltipLines, round)
    self.pinsUsed = self.pinsUsed + 1
    local p = self.pins[self.pinsUsed]
    if not p then
        p = CreateFrame("Button", nil, self.dotLayer)
        p.ring = S.Circle(p, 10, { 0, 0, 0, 0.75 }, "ARTWORK")
        p.ring:SetPoint("CENTER")
        p.icon = p:CreateTexture(nil, "OVERLAY")
        p.icon:SetPoint("CENTER")
        S.RoundMask(p, p.icon)
        p:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(btn.title or "")
            for _, line in ipairs(btn.lines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", GameTooltip_Hide)
        p:SetScript("OnClick", function(btn) if btn.onClick then btn.onClick() end end)
        self.pins[self.pinsUsed] = p
    end
    size = size or 18
    p:SetFrameLevel(self.dotLayer:GetFrameLevel() + 5)
    p:SetSize(size + 4, size + 4)
    p.ring:SetSize(size + 4, size + 4)
    p.icon:SetSize(size, size)
    p.icon:SetTexture(texture)
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.title, p.lines = tooltipTitle, tooltipLines
    p.onClick = nil -- callers set this after AddPin if the pin is clickable
    local px, py = self:ToPixels(x, y)
    p:ClearAllPoints()
    p:SetPoint("CENTER", self.dotLayer, "TOPLEFT", px, -py)
    p:Show()
    return p
end

function Canvas:SetHere(x, y, r, g, b)
    if not x then self.here:Hide() return end
    local px, py = self:ToPixels(x, y)
    self.here:ClearAllPoints()
    self.here:SetPoint("CENTER", self.dotLayer, "TOPLEFT", px, -py)
    self.here:Show()
end
