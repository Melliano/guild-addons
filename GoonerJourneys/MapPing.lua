-- Map pings: middle-click the world map to ping a spot for the whole guild.
-- Guildies see a pulsing ring in your class colour (with your name) on their
-- world map for a short while, plus a chat line and a ping sound.
local _, GJ = ...

local PING_FOR = 30        -- seconds a ping stays on the map
local MIN_GAP = 2          -- you can ping at most this often
local RING = 34            -- max ring size in pixels

GJ.mapPings = {} -- [guid] = { t = GetTime(), m = mapID, x = 0..1, y = 0..1, name, class }

local lastOwnPing = -MIN_GAP

---------------------------------------------------------------------------
-- Sending and receiving
---------------------------------------------------------------------------
local function store(guid, name, class, mapID, x, y)
    GJ.mapPings[guid] = { t = GetTime(), m = mapID, x = x, y = y, name = name, class = class }
    if GJ.RefreshMapPings then GJ:RefreshMapPings() end
end

local function pingSound()
    if PlaySound then PlaySound((SOUNDKIT and SOUNDKIT.MAP_PING) or 3175, "Master") end
end

local function placeText(mapID, x, y)
    return ("%s (%.0f, %.0f)"):format(GJ:MapName(mapID), x * 100, y * 100)
end

-- mapID + normalised x/y (0..1) on that map. Returns true if it was sent.
function GJ:SendMapPing(mapID, x, y)
    if not mapID or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return false end
    if GetTime() - lastOwnPing < MIN_GAP then return false end
    lastOwnPing = GetTime()
    local me = self:Me()
    store(me.guid, me.name or self:PlayerName(), me.class, mapID, x, y)
    pingSound()
    self:SendUrgent({
        k = "M", v = 1, g = self:PlayerGUID(), i = self:MyInfo(),
        m = mapID, x = math.floor(x * 1000 + 0.5), y = math.floor(y * 1000 + 0.5),
    })
    return true
end

local lastHeard = {} -- [guid] = GetTime(), so a misbehaving client can't flood us
GJ:RegisterHandler("M", function(body)
    if type(body.g) ~= "string" or GJ:IsMe(body.g) then return end
    if type(body.m) ~= "number" or type(body.x) ~= "number" or type(body.y) ~= "number" then return end
    if GetTime() - (lastHeard[body.g] or -MIN_GAP) < MIN_GAP - 0.5 then return end
    lastHeard[body.g] = GetTime()
    local m = GJ:GetMember(body.g, true)
    GJ:ApplyInfo(m, body.i)
    if m.guild and GJ:GuildName() and m.guild ~= GJ:GuildName() then return end
    if not GJ.db.settings.mapPings then return end
    local x, y = body.x / 1000, body.y / 1000
    store(body.g, m.name, m.class, body.m, x, y)
    pingSound()
    GJ:Print(("%s pinged the map: |cffffd100%s|r  - press M to see it"):format(GJ:ColoredName(m), placeText(body.m, x, y)))
end)

-- Active (not yet expired) ping for a guildie, or nil.
function GJ:GetMapPing(guid)
    local p = self.mapPings[guid]
    if p and GetTime() - p.t < PING_FOR then return p end
    self.mapPings[guid] = nil
    return nil
end

---------------------------------------------------------------------------
-- Drawing on the world map
---------------------------------------------------------------------------
local layer, markers = nil, {}

local function ensureLayer()
    if layer then return layer end
    local wm = WorldMapFrame
    local canvas = wm and wm.ScrollContainer and wm.ScrollContainer.Child
    if not canvas then return nil end
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints()
    layer:SetFrameLevel(canvas:GetFrameLevel() + 2100)
    return layer
end

local function marker(i)
    local f = markers[i]
    if f then return f end
    f = CreateFrame("Frame", nil, layer)
    f:SetSize(RING, RING)
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture(GJ.Style.CIRCLE)
    f.ring:SetPoint("CENTER")
    f.dot = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.dot:SetTexture(GJ.Style.CIRCLE)
    f.dot:SetPoint("CENTER")
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f, "CENTER", 0, -10)
    f:SetScript("OnUpdate", function(self)
        local age = GetTime() - (self.t or 0)
        local s = self.scale or 1
        local phase = (age % 1.2) / 1.2 -- ring grows and fades every 1.2s
        local size = (8 + phase * (RING - 8)) / s
        self.ring:SetSize(size, size)
        self.ring:SetAlpha((1 - phase) * 0.9)
        local fade = age > PING_FOR - 3 and math.max(0, (PING_FOR - age) / 3) or 1
        self:SetAlpha(fade)
        if age >= PING_FOR then self:Hide() end
    end)
    markers[i] = f
    return f
end

function GJ:RefreshMapPings()
    for _, f in ipairs(markers) do f:Hide() end
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    if not ensureLayer() then return end
    local shownMap = WorldMapFrame:GetMapID()
    if not shownMap then return end
    local sc = WorldMapFrame.ScrollContainer
    local scale = sc and sc.GetCanvasScale and sc:GetCanvasScale() or 1
    local w, h = layer:GetSize()
    local i = 0
    for guid in pairs(self.mapPings) do
        local p = self:GetMapPing(guid)
        local x, y
        if p then x, y = self.TranslateMapPos(p.m, p.x, p.y, shownMap) end
        if x then
            i = i + 1
            local f = marker(i)
            local r, g, b = self:ClassColor(p.class)
            f.t, f.scale = p.t, scale
            f:SetSize(RING / scale, RING / scale)
            f.ring:SetVertexColor(r, g, b)
            f.dot:SetVertexColor(r, g, b)
            f.dot:SetSize(9 / scale, 9 / scale)
            f.label:SetText(p.name or "?")
            f.label:SetTextColor(r, g, b)
            f.label:SetScale(1 / scale)
            f:ClearAllPoints()
            f:SetPoint("CENTER", layer, "TOPLEFT", x * w, -y * h)
            f:Show()
        end
    end
end

---------------------------------------------------------------------------
-- Middle-click on the world map
---------------------------------------------------------------------------
local function cursorOnMap()
    local wm = WorldMapFrame
    local sc = wm and wm.ScrollContainer
    if not sc then return nil end
    local x, y
    if sc.GetNormalizedCursorPosition then
        x, y = sc:GetNormalizedCursorPosition()
    elseif wm.GetNormalizedCursorPosition then
        x, y = wm:GetNormalizedCursorPosition()
    end
    return wm:GetMapID(), x, y
end

local hooked = false
local function hook()
    if hooked or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
    hooked = true
    WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function(_, button)
        if button ~= "MiddleButton" then return end
        local mapID, x, y = cursorOnMap()
        GJ:SendMapPing(mapID, x, y) -- quietly ignored if you pinged under 2s ago
    end)
    WorldMapFrame:HookScript("OnShow", function() GJ:RefreshMapPings() end)
end

GJ:On("GJ_LOGIN", hook)
