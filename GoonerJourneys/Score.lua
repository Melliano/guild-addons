-- Gooner Score: points for every milestone on your timeline, and the rank
-- that comes with it.
local _, GJ = ...

local POINTS = {
    start   = 0,
    level   = 10,  -- every 5 levels
    zone    = 5,
    dungeon = 15,
    raid    = 25,
    boss    = 20,
    prof    = 5,
    silly   = 10,
    death   = 1,   -- participation award
}
local ITEM_POINTS = { [3] = 10, [4] = 25, [5] = 100 }
local SPECIAL = { maxLevel = 100 }

GJ.RANKS = {
    { 0,    "Gooner Initiate" },
    { 100,  "Apprentice Gooner" },
    { 250,  "Journeyman Gooner" },
    { 500,  "Seasoned Gooner" },
    { 1000, "Veteran Gooner" },
    { 2000, "Elite Gooner" },
    { 4000, "Grand Gooner" },
}

function GJ:EventPoints(ev)
    if ev.dup then return 0 end
    -- Every level past 30 is a milestone, but only every 5th is worth the full points.
    if ev.k == "level" and type(ev.d) == "number" and ev.d % 5 ~= 0 then return 2 end
    if ev.k == "item" then return ITEM_POINTS[ev.q or 0] or 0 end
    if ev.k == "silly" and SPECIAL[ev.d] then return SPECIAL[ev.d] end
    return POINTS[ev.k] or 0
end

local cache = {}

function GJ:Score(member)
    if not member then return 0 end
    local c = cache[member.guid]
    local n = #member.events
    if c and c.n == n then return c.score end
    local score = 0
    for i = 1, n do
        local ev = member.events[i]
        if ev then score = score + self:EventPoints(ev) end
    end
    cache[member.guid] = { n = n, score = score }
    return score
end

-- Returns rank name, rank index, points needed for the next rank (or nil).
function GJ:Rank(score)
    local idx = 1
    for i, r in ipairs(self.RANKS) do
        if score >= r[1] then idx = i end
    end
    local nextRank = self.RANKS[idx + 1]
    return self.RANKS[idx][2], idx, nextRank and nextRank[1] or nil
end

function GJ:MemberRank(member)
    local score = self:Score(member)
    local name, idx, nextAt = self:Rank(score)
    return name, score, idx, nextAt
end
