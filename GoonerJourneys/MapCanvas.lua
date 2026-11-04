-- A small map widget: draws a zone's map art and lets us drop dots/pins on
-- it. Used by the journey window's Map tab.
local _, GJ = ...

local Canvas = {}
Canvas.__index = Canvas

function GJ:CreateMapCanvas(parent, width)
    local self = setmetatable({}, Canvas)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, width * 2 / 3)
    f:SetClipsChildren(true)
    self.frame = f
    self.width = width
    self.tiles = {}
    self.dots = {}
    self.dotsUsed = 0
    self.pins = {}
    self.pinsUsed = 0

    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)

    self.art = CreateFrame("Frame", nil, f)
    self.art:SetAllPoints()
    self.dotLayer = CreateFrame("Frame", nil, f)
    self.dotLayer:SetAllPoints()
    self.dotLayer:SetFrameLevel(self.art:GetFrameLevel() + 2)

    self.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    self.empty:SetPoint("CENTER")
    return self
end

function Canvas:SetMap(mapID)
    self.mapID = mapID
    for _, t in ipairs(self.tiles) do t:Hide() end
    self.empty:SetText("")
    if not mapID then
        self.empty:SetText("No map")
        return
    end
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    local textures = C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(mapID, 1)
    if not layer or not textures or #textures == 0 then
        self.empty:SetText(GJ:MapName(mapID))
        return
    end
    local scale = self.width / layer.layerWidth
    local height = layer.layerHeight * scale
    self.frame:SetHeight(height)
    local cols = math.ceil(layer.layerWidth / layer.tileWidth)
    local tw, th = layer.tileWidth * scale, layer.tileHeight * scale
    for i, fileID in ipairs(textures) do
        local t = self.tiles[i]
        if not t then
            t = self.art:CreateTexture(nil, "ARTWORK")
            self.tiles[i] = t
        end
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        t:ClearAllPoints()
        t:SetSize(tw, th)
        t:SetPoint("TOPLEFT", self.art, "TOPLEFT", col * tw, -row * th)
        t:SetTexture(fileID)
        t:Show()
    end
end

function Canvas:Clear()
    for i = 1, self.dotsUsed do self.dots[i]:Hide() end
    self.dotsUsed = 0
    for i = 1, self.pinsUsed do self.pins[i]:Hide() end
    self.pinsUsed = 0
end

-- Cheap trail dot (no mouse interaction).
function Canvas:AddDot(x, y, r, g, b, a, size)
    self.dotsUsed = self.dotsUsed + 1
    local t = self.dots[self.dotsUsed]
    if not t then
        t = self.dotLayer:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        self.dots[self.dotsUsed] = t
    end
    size = size or 4
    t:SetSize(size, size)
    t:SetVertexColor(r, g, b, a or 0.85)
    t:ClearAllPoints()
    t:SetPoint("CENTER", self.dotLayer, "TOPLEFT", x * self.width, -y * self.frame:GetHeight())
    t:Show()
    return t
end

-- Interactive pin with an icon and tooltip lines.
function Canvas:AddPin(x, y, texture, size, tooltipTitle, tooltipLines, r, g, b)
    self.pinsUsed = self.pinsUsed + 1
    local p = self.pins[self.pinsUsed]
    if not p then
        p = CreateFrame("Button", nil, self.dotLayer)
        p.icon = p:CreateTexture(nil, "OVERLAY")
        p.icon:SetAllPoints()
        p:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(btn.title or "")
            for _, line in ipairs(btn.lines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", GameTooltip_Hide)
        self.pins[self.pinsUsed] = p
    end
    p:SetFrameLevel(self.dotLayer:GetFrameLevel() + 5)
    p:SetSize(size or 14, size or 14)
    p.icon:SetTexture(texture)
    p.icon:SetVertexColor(r or 1, g or 1, b or 1)
    p.title, p.lines = tooltipTitle, tooltipLines
    p:ClearAllPoints()
    p:SetPoint("CENTER", self.dotLayer, "TOPLEFT", x * self.width, -y * self.frame:GetHeight())
    p:Show()
    return p
end
