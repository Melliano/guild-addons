-- Walked trail: every N seconds (default 30) remember which grid cell of the
-- current zone map you are standing in, and add up distance travelled.
local _, GJ = ...

function GJ:GetPlayerPosition()
    local mapID = self:ZoneMapID()
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return mapID end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return mapID end
    return mapID, x, y
end

local lastWorld -- { continent, x, y }
local ticker

local function sample()
    if UnitIsDeadOrGhost("player") then lastWorld = nil return end
    local mapID, x, y = GJ:GetPlayerPosition()
    if not (mapID and x) then lastWorld = nil return end

    local me = GJ:Me()
    local before = #me.cells
    if GJ:AddCell(me, GJ:CellKey(mapID, x, y)) then
        GJ:MarkOwnDirty("c", before + 1)
        GJ:Fire("GJ_DATA_CHANGED", me.guid, "cells")
    end

    -- Distance travelled, in yards, using world coordinates.
    if C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local continent, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
        if continent and world then
            local wx, wy = world:GetXY()
            if lastWorld and lastWorld[1] == continent and not UnitOnTaxi("player") then
                local dx, dy = wx - lastWorld[2], wy - lastWorld[3]
                local d = math.sqrt(dx * dx + dy * dy)
                -- Ignore teleports / hearths (no one moves 2000 yards in a sample).
                local maxStep = 60 * GJ.db.settings.trailInterval
                if d > 1 and d < maxStep then
                    GJ:Bump("distance", math.floor(d))
                end
            end
            lastWorld = { continent, wx, wy }
        end
    end
    if GJ.CheckMount then GJ.CheckMount() end
end

function GJ:RestartTrailTicker()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(self.db.settings.trailInterval, sample)
end

GJ:On("GJ_LOGIN", function()
    GJ:RestartTrailTicker()
    C_Timer.After(6, sample)
end)

-- Sample on zone changes too so short visits are captured.
GJ:On("ZONE_CHANGED_NEW_AREA", function() lastWorld = nil C_Timer.After(2, sample) end)
