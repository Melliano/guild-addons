-- Saved data: one record per guild member (keyed by GUID). Every record has
-- append-only lists (events, trail cells) plus stamped snapshots (stats,
-- gear) so that records can be merged from any guildie who has a copy.
local _, GJ = ...

local SCHEMA = 1

local DEFAULT_SETTINGS = {
    minimap = { angle = 215, hide = false },
    trailInterval = 30,       -- seconds between trail samples
    worldMapOverlay = true,   -- draw guildies + trails on the world map
    toasts = true,            -- guild news pop-ups
    announce = false,         -- post your own news in guild chat
    weeklyRecap = true,
    goonerAlerts = true,      -- GOONER ZONE DETECTED banner       -- show last week's recap on first login of the week
    debug = false,
}

local function applyDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            if type(v) == "table" then
                t[k] = {}
                applyDefaults(t[k], v)
            else
                t[k] = v
            end
        elseif type(v) == "table" and type(t[k]) == "table" then
            applyDefaults(t[k], v)
        end
    end
end

function GJ:InitDB()
    GoonerJourneysDB = GoonerJourneysDB or {}
    local db = GoonerJourneysDB
    if db.schema ~= SCHEMA then
        -- First install (or incompatible old data): start fresh.
        wipe(db)
        db.schema = SCHEMA
    end
    db.settings = db.settings or {}
    applyDefaults(db.settings, DEFAULT_SETTINGS)
    db.members = db.members or {}
    db.private = db.private or {} -- per-character counters that are not shared
    self.db = db
    self.cellSets = {}
end

---------------------------------------------------------------------------
-- Members
---------------------------------------------------------------------------
function GJ:GetMember(guid, create)
    if not guid then return nil end
    local m = self.db.members[guid]
    if not m and create then
        m = {
            guid = guid,
            events = {},
            cells = {},
            stats = {},
            statsStamp = 0,
            gear = {},
            gearStamp = 0,
        }
        self.db.members[guid] = m
    end
    return m
end

function GJ:Me()
    return self:GetMember(self:PlayerGUID(), true)
end

function GJ:IsMe(guid)
    return guid == self:PlayerGUID()
end

-- Basic identity info carried with most messages.
function GJ:MyInfo()
    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    return {
        n = self:PlayerName(),
        c = classFile,
        r = raceFile,
        l = UnitLevel("player"),
        gu = self:GuildName(),
        s = UnitSex("player"),
        av = GJ.version,
    }
end

function GJ:ApplyInfo(member, info)
    if type(info) ~= "table" then return end
    if type(info.n) == "string" then member.name = info.n end
    if type(info.c) == "string" then member.class = info.c end
    if type(info.r) == "string" then member.race = info.r end
    if type(info.l) == "number" then member.level = info.l end
    if type(info.gu) == "string" then member.guild = info.gu end
    if type(info.s) == "number" then member.sex = info.s end
    if type(info.av) == "string" then
        member.ver = info.av
        self:Fire("GJ_VERSION_SEEN", info.av, member)
    end
end

function GJ:RefreshMyInfo()
    local me = self:Me()
    self:ApplyInfo(me, self:MyInfo())
    me.lastSeen = self:Now()
    return me
end

-- Members of my guild that have journey data, sorted: online first, then by level.
function GJ:SortedMembers()
    local guild = self:GuildName()
    local list = {}
    for _, m in pairs(self.db.members) do
        if m.name and (not guild or m.guild == guild or self:IsMe(m.guid)) then
            list[#list + 1] = m
        end
    end
    table.sort(list, function(a, b)
        local ao, bo = self:IsOnline(a) and 1 or 0, self:IsOnline(b) and 1 or 0
        if ao ~= bo then return ao > bo end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

function GJ:IsOnline(member)
    if self:IsMe(member.guid) then return true end
    return member.live and member.live.t and (self:Now() - member.live.t) < 120
end

---------------------------------------------------------------------------
-- Events (timeline entries)
--   t = time, k = kind, d = detail, l = level, m = mapID, x/y = 0..1000
---------------------------------------------------------------------------
function GJ:AddEvent(kind, detail, extra)
    local me = self:RefreshMyInfo()
    local ev = { t = self:Now(), k = kind, d = detail, l = UnitLevel("player") }
    local mapID, x, y = self:GetPlayerPosition()
    if mapID then
        ev.m = mapID
        if x then
            ev.x, ev.y = math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
        end
    end
    if extra then
        for k, v in pairs(extra) do ev[k] = v end
    end
    me.events[#me.events + 1] = ev
    me.updated = ev.t
    self:Debug("event", kind, tostring(detail))
    self:Fire("GJ_DATA_CHANGED", me.guid, "events")
    self:Fire("GJ_OWN_EVENT", ev)
    return ev
end

function GJ:HasEvent(member, kind, detail)
    for _, ev in ipairs(member.events) do
        if ev.k == kind and (detail == nil or ev.d == detail) then return true end
    end
    return false
end

-- Merge an incoming contiguous slice of events starting at sequence `start`.
-- Returns the number of new events stored, or -1 if there was a gap.
function GJ:MergeEvents(guid, start, list)
    if self:IsMe(guid) or type(list) ~= "table" or type(start) ~= "number" then return 0 end
    local m = self:GetMember(guid, true)
    local have = #m.events
    if start > have + 1 then return -1 end
    local added = 0
    local fresh = {}
    for i, ev in ipairs(list) do
        local seq = start + i - 1
        if seq > have and type(ev) == "table" and type(ev.k) == "string" then
            m.events[seq] = ev
            added = added + 1
            fresh[#fresh + 1] = ev
        end
    end
    if added > 0 then self:Fire("GJ_NEW_EVENTS", guid, fresh) end
    if added > 0 then
        m.updated = self:Now()
        self:Fire("GJ_DATA_CHANGED", guid, "events")
    end
    return added
end

---------------------------------------------------------------------------
-- Trail cells: each zone map is split into a 100x100 grid and we remember
-- every cell a member has stood in. Cell key = mapID * 10000 + cy * 100 + cx
---------------------------------------------------------------------------
GJ.GRID = 100

function GJ:CellKey(mapID, x, y)
    local cx = math.min(GJ.GRID - 1, math.max(0, math.floor(x * GJ.GRID)))
    local cy = math.min(GJ.GRID - 1, math.max(0, math.floor(y * GJ.GRID)))
    return mapID * 10000 + cy * 100 + cx
end

function GJ:DecodeCell(key)
    local mapID = math.floor(key / 10000)
    local rest = key % 10000
    local cy = math.floor(rest / 100)
    local cx = rest % 100
    return mapID, (cx + 0.5) / GJ.GRID, (cy + 0.5) / GJ.GRID
end

function GJ:GetCellSet(member)
    local set = self.cellSets[member.guid]
    if not set or set.n ~= #member.cells then
        set = { n = #member.cells, keys = {} }
        for _, key in ipairs(member.cells) do set.keys[key] = true end
        self.cellSets[member.guid] = set
    end
    return set
end

function GJ:AddCell(member, key)
    local set = self:GetCellSet(member)
    if set.keys[key] then return false end
    member.cells[#member.cells + 1] = key
    set.keys[key] = true
    set.n = #member.cells
    return true
end

function GJ:MergeCells(guid, start, list)
    if self:IsMe(guid) or type(list) ~= "table" or type(start) ~= "number" then return 0 end
    local m = self:GetMember(guid, true)
    local have = #m.cells
    if start > have + 1 then return -1 end
    local added = 0
    for i, key in ipairs(list) do
        local idx = start + i - 1
        if idx > have and type(key) == "number" then
            -- Keep positional indexes aligned with the sender even if a key
            -- is somehow a duplicate; the set handles lookups.
            m.cells[idx] = key
            added = added + 1
        end
    end
    if added > 0 then
        self.cellSets[guid] = nil
        m.updated = self:Now()
        self:Fire("GJ_DATA_CHANGED", guid, "cells")
    end
    return added
end

-- Cells for one map, as a list of {x, y}.
function GJ:CellsOnMap(member, mapID)
    local out = {}
    local lo, hi = mapID * 10000, mapID * 10000 + 9999
    for _, key in ipairs(member.cells) do
        if key >= lo and key <= hi then
            local _, x, y = self:DecodeCell(key)
            out[#out + 1] = { x, y }
        end
    end
    return out
end

-- mapID -> number of cells, for every map a member has walked on.
function GJ:MapsWalked(member)
    local counts = {}
    for _, key in ipairs(member.cells) do
        local mapID = math.floor(key / 10000)
        counts[mapID] = (counts[mapID] or 0) + 1
    end
    return counts
end

---------------------------------------------------------------------------
-- Stamped snapshots
---------------------------------------------------------------------------
function GJ:MergeSnapshot(guid, field, stamp, value)
    if self:IsMe(guid) or type(stamp) ~= "number" or type(value) ~= "table" then return false end
    local m = self:GetMember(guid, true)
    local stampField = field .. "Stamp"
    if stamp <= (m[stampField] or 0) then return false end
    m[field] = value
    m[stampField] = stamp
    m.updated = self:Now()
    self:Fire("GJ_DATA_CHANGED", guid, field)
    return true
end

-- Digest of what we hold for a member: counts and stamps.
function GJ:DigestOf(member)
    return { #member.events, #member.cells, member.statsStamp or 0, member.gearStamp or 0 }
end
