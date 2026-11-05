-- Quest log tracking: every quest a goon picks up, and what became of it.
--
-- Each member's record keeps an append-only list of quest changes, synced
-- like the trail:
--   { i = questID, s = "a" (picked up) | "c" (completed) | "x" (dropped),
--     t = time, n = title, lv = level, z = zone header }
-- The title/level/zone are only sent the first time a member mentions a
-- quest. Replaying the list gives each member's current state per quest.
local _, GJ = ...

local VALID = { a = true, c = true, x = true }
local DROP_AFTER = 30      -- seconds a quest must be missing before it counts as dropped
local TURNIN_GRACE = 10    -- a turned-in quest lingers in the log briefly; don't re-add it

function GJ:QuestEntries(member)
    if not member.quests then member.quests = {} end
    return member.quests
end

-- state: questID -> "a" | "c" | "x";  info: questID -> { n, lv, z }
local cache = {}
function GJ:QuestState(member)
    local entries = self:QuestEntries(member)
    local c = cache[member.guid]
    if c and c.n == #entries then return c.state, c.info end
    local state, info = {}, {}
    for _, e in ipairs(entries) do
        if type(e) == "table" and type(e.i) == "number" and VALID[e.s] then
            state[e.i] = e.s
            if type(e.n) == "string" and not info[e.i] then
                info[e.i] = { n = e.n, lv = tonumber(e.lv), z = type(e.z) == "string" and e.z or nil }
            end
        end
    end
    cache[member.guid] = { n = #entries, state = state, info = info }
    return state, info
end

-- Merge an incoming contiguous slice. Returns entries added, or -1 on a gap.
function GJ:MergeQuests(guid, start, list)
    if self:IsMe(guid) or type(list) ~= "table" or type(start) ~= "number" then return 0 end
    local m = self:GetMember(guid, true)
    local entries = self:QuestEntries(m)
    local have = #entries
    if start > have + 1 then return -1 end
    local added = 0
    for i, e in ipairs(list) do
        local idx = start + i - 1
        if idx > have and type(e) == "table" and type(e.i) == "number" and VALID[e.s] then
            entries[idx] = e
            added = added + 1
        elseif idx > have then
            break -- keep the list contiguous
        end
    end
    if added > 0 then
        m.updated = self:Now()
        self:Fire("GJ_DATA_CHANGED", guid, "quests")
    end
    return added
end

-- questID -> { n, lv, z } from every record we hold.
function GJ:QuestCatalog()
    local out = {}
    for _, m in pairs(self.db.members) do
        local _, info = self:QuestState(m)
        for id, meta in pairs(info) do
            if not out[id] then out[id] = meta end
        end
    end
    return out
end

-- Every quest a guildie has picked up, with who is on it, who has done it
-- and who dropped it. Sorted by zone, then level, then title.
function GJ:GuildQuests()
    local rows = {}
    local catalog = self:QuestCatalog()
    for _, m in ipairs(self:SortedMembers()) do
        local state = self:QuestState(m)
        for id, s in pairs(state) do
            local row = rows[id]
            if not row then
                local meta = catalog[id] or {}
                row = { id = id, n = meta.n or ("Quest #" .. id), lv = meta.lv, z = meta.z,
                    active = {}, done = {}, dropped = {} }
                rows[id] = row
            end
            local bucket = (s == "a" and row.active) or (s == "c" and row.done) or row.dropped
            bucket[#bucket + 1] = m
        end
    end
    local list = {}
    for _, row in pairs(rows) do list[#list + 1] = row end
    table.sort(list, function(a, b)
        local za, zb = a.z or "~", b.z or "~"
        if za ~= zb then return za < zb end
        if (a.lv or 0) ~= (b.lv or 0) then return (a.lv or 0) < (b.lv or 0) end
        return a.n < b.n
    end)
    return list
end

---------------------------------------------------------------------------
-- Reading your own quest log
---------------------------------------------------------------------------
-- Returns questID -> { n, lv, z }, and whether the scan saw every quest
-- (collapsed zone headers hide their quests from addons).
local function readQuestLog()
    local quests, complete, seen = {}, true, 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local numEntries, numQuests = C_QuestLog.GetNumQuestLogEntries()
        local header
        for i = 1, numEntries or 0 do
            local info = C_QuestLog.GetInfo(i)
            if not info then
                complete = false
            elseif info.isHeader then
                header = info.title
                if info.isCollapsed then complete = false end
            elseif not info.isHidden then
                seen = seen + 1
                if type(info.questID) == "number" and info.questID > 0 and info.title then
                    quests[info.questID] = { n = info.title, lv = info.level, z = header }
                else
                    complete = false
                end
            end
        end
        if numQuests and seen < numQuests then complete = false end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local numEntries, numQuests = GetNumQuestLogEntries()
        local header
        for i = 1, numEntries or 0 do
            local title, level, _, isHeader, isCollapsed, _, _, questID = GetQuestLogTitle(i)
            if isHeader then
                header = title
                if isCollapsed then complete = false end
            elseif title then
                seen = seen + 1
                if type(questID) == "number" and questID > 0 then
                    quests[questID] = { n = title, lv = level, z = header }
                else
                    complete = false
                end
            end
        end
        if numQuests and seen < numQuests then complete = false end
    else
        return nil
    end
    return quests, complete
end

local function isCompleted(id)
    local api = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not api then return false end
    local ok, done = pcall(api, id)
    return ok and done and true or false
end

local function record(id, s, meta)
    local me = GJ:Me()
    local entries = GJ:QuestEntries(me)
    local _, info = GJ:QuestState(me)
    local e = { i = id, s = s, t = GJ:Now() }
    if meta and meta.n and not info[id] then
        e.n, e.lv, e.z = meta.n, meta.lv, meta.z
    end
    entries[#entries + 1] = e
    me.updated = e.t
    GJ:Debug("quest", s, id, tostring(meta and meta.n))
    GJ:MarkOwnDirty("k", #entries)
    GJ:Fire("GJ_DATA_CHANGED", me.guid, "quests")
end

local lastLog = {}
local missingSince = {}
local turnedIn = {}
local loadingUntil = math.huge -- no "dropped" decisions until we're settled in the world
local scanPending = false

local scan
local function requestScan(delay)
    if scanPending then return end
    scanPending = true
    C_Timer.After(delay or 1, function()
        scanPending = false
        scan()
    end)
end

scan = function()
    local log, complete = readQuestLog()
    if not log then return end
    local now = GetTime()
    for id, meta in pairs(log) do lastLog[id] = meta end
    local me = GJ:Me()
    local state = GJ:QuestState(me)

    -- Picked up (or picked up again, for repeatable quests).
    for id, meta in pairs(log) do
        missingSince[id] = nil
        if state[id] ~= "a" and not (turnedIn[id] and now - turnedIn[id] < TURNIN_GRACE) then
            record(id, "a", meta)
        end
    end

    -- Gone from the log: completed, or dropped. Only decide on a full scan,
    -- outside loading screens, and only once it has stayed gone a while.
    if not complete or now < loadingUntil then return end
    local waiting = false
    for id, s in pairs(state) do
        if s == "a" and not log[id] then
            if isCompleted(id) then
                record(id, "c", lastLog[id])
                missingSince[id] = nil
            else
                missingSince[id] = missingSince[id] or now
                if now - missingSince[id] >= DROP_AFTER then
                    record(id, "x")
                    missingSince[id] = nil
                else
                    waiting = true
                end
            end
        end
    end
    if waiting then requestScan(DROP_AFTER + 1) end
end

GJ:On("QUEST_TURNED_IN", function(questID)
    if type(questID) ~= "number" then return end
    turnedIn[questID] = GetTime()
    missingSince[questID] = nil
    local state = GJ:QuestState(GJ:Me())
    if state[questID] ~= "c" then record(questID, "c", lastLog[questID]) end
end)

GJ:On("QUEST_ACCEPTED", function() requestScan(1) end)
GJ:On("QUEST_LOG_UPDATE", function() requestScan(1) end)
GJ:On("QUEST_REMOVED", function() requestScan(1) end)
GJ:On("PLAYER_LEAVING_WORLD", function() loadingUntil = math.huge end)
GJ:On("PLAYER_ENTERING_WORLD", function()
    loadingUntil = GetTime() + 10
    requestScan(11)
end)

---------------------------------------------------------------------------
-- Quests you finished before anyone was tracking: when a guildie picks up
-- a quest you've already done, mark it completed for you too.
---------------------------------------------------------------------------
local historyPending = false

local function checkHistory()
    historyPending = false
    local state = GJ:QuestState(GJ:Me())
    for id, meta in pairs(GJ:QuestCatalog()) do
        if not state[id] and isCompleted(id) then record(id, "c", meta) end
    end
end

local function requestHistory(delay)
    if historyPending then return end
    historyPending = true
    C_Timer.After(delay or 5, checkHistory)
end

GJ:On("GJ_DATA_CHANGED", function(guid, field)
    if field == "quests" and not GJ:IsMe(guid) then requestHistory(5) end
end)

GJ:On("GJ_LOGIN", function()
    loadingUntil = GetTime() + 10
    requestScan(6)
    requestHistory(15)
end)
