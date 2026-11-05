-- Guild sync over hidden addon messages.
--
-- There is no server: every member's addon keeps a copy of everyone's
-- journey and gossips it over the GUILD addon channel. When someone logs in
-- they broadcast a digest (how much they hold for each member); anyone who
-- holds more pushes the missing pieces to the whole guild, so everyone's
-- copy fills in. Pushes are jittered and suppressed if someone else already
-- sent the same data, to avoid the whole guild answering at once.
local _, GJ = ...

local PREFIX = "GoonJ"
local PROTO = 1
local MAX_MSG = 250          -- Blizzard's limit is 255 bytes per message
local CHUNK = MAX_MSG - 6    -- room for the chunk header
local EVENTS_PER_PUSH = 12
local CELLS_PER_PUSH = 150
local DIGEST_INTERVAL = 3 * 60     -- periodic full check so gaps fill in on their own
local LIVE_INTERVAL = 15

local Serialize = GJ.Serializer.Serialize
local Deserialize = GJ.Serializer.Deserialize

local function b36(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local digits, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    while n > 0 do
        local r = n % 36
        s = digits:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

---------------------------------------------------------------------------
-- Outgoing queue with a token bucket (Blizzard throttles addon messages per
-- prefix to roughly a burst of 10 then 1 per second).
---------------------------------------------------------------------------
local queues = { {}, {}, {} } -- 1 = live, 2 = normal, 3 = bulk
local tokens, MAX_TOKENS, REGEN = 6, 6, 0.9
local lastTick = GetTime and GetTime() or 0
local pausedUntil = 0
local msgCounter = 0
local MAX_FAILS = 5 -- a message the game keeps rejecting is dropped, not retried forever

-- Diagnostics for /gooner status.
local stats = { guild = 0, whisper = 0, failed = 0, dropped = 0, lastError = nil }
GJ.commStats = stats

---------------------------------------------------------------------------
-- Peers: everyone we hear addon messages from. Some clients never receive
-- our GUILD messages (seen on WoW Forever) even though we receive theirs.
-- We detect that with a probe and then also whisper our data to them.
---------------------------------------------------------------------------
local peers = {} -- [sender] = { last, n, guid, whisper, probing, acked, channel }
GJ.peers = peers

local function baseName(name)
    return name and name:match("^[^-]+") or name
end

local function peer(sender)
    local p = peers[sender]
    if not p then p = { n = 0, last = 0 } peers[sender] = p end
    return p
end

local function whisperTargets()
    local now, list = GetTime(), nil
    for name, p in pairs(peers) do
        if p.whisper and now - p.last < 180 then
            list = list or {}
            list[#list + 1] = name
        end
    end
    return list
end

-- Guild roster cache so we only accept whispered data from guildies.
local roster, rosterSize = {}, 0
local function refreshRoster()
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local total = GetNumGuildMembers() or 0
    wipe(roster)
    rosterSize = 0
    for i = 1, total do
        local name = GetGuildRosterInfo(i)
        if name then
            roster[baseName(name)] = true
            rosterSize = rosterSize + 1
        end
    end
end

local function isGuildie(sender)
    if rosterSize == 0 then return true end -- roster not loaded yet: don't drop data
    return roster[baseName(sender)] == true
end

local function inLockdown()
    if C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then return true end
    end
    return false
end

local function rawSend(item)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, item.ch, item.to)
    if not ok then return false, tostring(result) end
    -- Older clients return a boolean, newer return Enum.SendAddonMessageResult.
    if result == nil or result == true or result == 0 then return true end
    return false, tostring(result)
end

local function enqueue(priority, body, live)
    if not IsInGuild() then return end
    local payload = Serialize(body)
    local parts = {}
    if #payload <= MAX_MSG - 1 then
        parts[1] = "S" .. payload
    else
        msgCounter = (msgCounter + 1) % 1296
        local id = b36(msgCounter)
        local pos, n = 1, #payload
        while pos <= n do
            local piece = payload:sub(pos, pos + CHUNK - 1)
            local kind = (pos == 1) and "B" or ((pos + CHUNK > n) and "E" or "C")
            parts[#parts + 1] = kind .. id .. ":" .. piece
            pos = pos + CHUNK
        end
    end
    local q = queues[priority]
    -- Live pings are only useful while fresh: a new one replaces any that
    -- haven't gone out yet (e.g. during a chat lockdown).
    if live then
        for i = #q, 1, -1 do
            if q[i].live then table.remove(q, i) end
        end
    end
    local function add(ch, to)
        for _, text in ipairs(parts) do
            q[#q + 1] = { text = text, ch = ch, to = to, live = live, fails = 0 }
        end
    end
    add("GUILD")
    local targets = whisperTargets()
    if targets then
        for _, name in ipairs(targets) do add("WHISPER", name) end
    end
end

local function pump()
    local now = GetTime()
    tokens = math.min(MAX_TOKENS, tokens + (now - lastTick) * REGEN)
    lastTick = now
    if now < pausedUntil or inLockdown() then return end
    while tokens >= 1 do
        local q
        for i = 1, #queues do
            if #queues[i] > 0 then q = queues[i] break end
        end
        if not q then return end
        local item = q[1]
        local ok, err = rawSend(item)
        if ok then
            table.remove(q, 1)
            tokens = tokens - 1
            if item.ch == "GUILD" then stats.guild = stats.guild + 1 else stats.whisper = stats.whisper + 1 end
        else
            stats.failed = stats.failed + 1
            stats.lastError = err
            item.fails = item.fails + 1
            if item.fails >= MAX_FAILS then
                table.remove(q, 1)
                stats.dropped = stats.dropped + 1
            end
            pausedUntil = now + 2
            return
        end
    end
end

function GJ:SendLive(body) enqueue(1, body, true) end
function GJ:SendUrgent(body) enqueue(1, body) end
function GJ:Send(body) enqueue(2, body) end
function GJ:SendBulk(body) enqueue(3, body) end

function GJ:QueueSize()
    return #queues[1] + #queues[2] + #queues[3]
end

---------------------------------------------------------------------------
-- Incoming: reassemble chunks then dispatch by message kind.
---------------------------------------------------------------------------
local partial = {}
local handlers = {}

-- Other modules can add message kinds.
function GJ:RegisterHandler(kind, fn) handlers[kind] = fn end

local function dispatch(sender, payload)
    local ok, body = Deserialize(payload)
    if not ok or type(body) ~= "table" or type(body.k) ~= "string" then return end
    if body.v and body.v > PROTO then
        if not GJ.warnedNewer then
            GJ.warnedNewer = true
            GJ:Print("A guildie has a newer version of the addon - grab the latest zip!")
        end
    end
    local h = handlers[body.k]
    if h then h(body, sender) end
end

GJ:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or not sender then return end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return end
    if channel == "WHISPER" and not isGuildie(sender) then return end
    if baseName(sender) ~= GJ:PlayerName() then
        local p = peer(sender)
        p.n = p.n + 1
        p.last = GetTime()
        p.channel = channel
    end
    local kind = text:sub(1, 1)
    if kind == "S" then
        dispatch(sender, text:sub(2))
        return
    end
    local id, piece = text:match("^[BCE](%w+):(.*)$")
    if not id then return end
    -- The same chunks can arrive twice (guild + whisper), so keep them apart.
    local key = sender .. "\1" .. channel .. "\1" .. id
    if kind == "B" then
        partial[key] = { piece, t = GetTime() }
    elseif partial[key] then
        local buf = partial[key]
        buf[#buf + 1] = piece
        buf.t = GetTime()
        if kind == "E" then
            partial[key] = nil
            dispatch(sender, table.concat(buf))
        end
    end
end)

-- Drop stale partial messages.
local function cleanupPartials()
    local now = GetTime()
    for k, buf in pairs(partial) do
        if now - buf.t > 120 then partial[k] = nil end
    end
end

---------------------------------------------------------------------------
-- Push suppression: remember what has recently been broadcast for each
-- member so we do not repeat what another guildie just sent.
---------------------------------------------------------------------------
local pushed = {} -- [guid][field] = { v = highest index/stamp, t = GetTime() }

local function markPushed(guid, field, value)
    local p = pushed[guid]
    if not p then p = {} pushed[guid] = p end
    local e = p[field]
    if not e then e = { v = 0, t = 0 } p[field] = e end
    if value > e.v then e.v = value end
    e.t = GetTime()
end

-- True if someone broadcast data for this member covering `value` after
-- the moment `since` (i.e. after the request we are answering).
local function alreadyPushed(guid, field, value, since)
    local e = pushed[guid] and pushed[guid][field]
    if not e then return false end
    return e.t >= since and e.v >= value
end

---------------------------------------------------------------------------
-- Building pushes
---------------------------------------------------------------------------
local function infoFor(member)
    if GJ:IsMe(member.guid) then return GJ:MyInfo() end
    return { n = member.name, c = member.class, r = member.race, l = member.level, gu = member.guild, s = member.sex }
end

function GJ:PushEvents(member, fromSeq)
    local total = #member.events
    local seq = math.max(1, fromSeq)
    while seq <= total do
        local slice = {}
        for i = seq, math.min(total, seq + EVENTS_PER_PUSH - 1) do
            slice[#slice + 1] = member.events[i]
        end
        self:Send({ k = "E", v = PROTO, g = member.guid, s = seq, e = slice, i = infoFor(member) })
        seq = seq + #slice
    end
    markPushed(member.guid, "e", total)
end

function GJ:PushCells(member, fromIdx)
    local total = #member.cells
    local idx = math.max(1, fromIdx)
    while idx <= total do
        local parts = {}
        for i = idx, math.min(total, idx + CELLS_PER_PUSH - 1) do
            parts[#parts + 1] = b36(member.cells[i])
        end
        self:SendBulk({ k = "C", v = PROTO, g = member.guid, s = idx, c = table.concat(parts, ",") })
        idx = idx + #parts
    end
    markPushed(member.guid, "c", total)
end

function GJ:PushStats(member)
    if (member.statsStamp or 0) == 0 then return end
    self:Send({ k = "S", v = PROTO, g = member.guid, t = member.statsStamp, s = member.stats, i = infoFor(member) })
    markPushed(member.guid, "s", member.statsStamp)
end

function GJ:PushGear(member)
    if (member.gearStamp or 0) == 0 then return end
    self:Send({ k = "G", v = PROTO, g = member.guid, t = member.gearStamp, q = member.gear })
    markPushed(member.guid, "g", member.gearStamp)
end

---------------------------------------------------------------------------
-- Digest / request handling
---------------------------------------------------------------------------
local lastDigest = 0

-- onlyGuids: optional set restricting which members are listed.
function GJ:BroadcastDigest(force, onlyGuids)
    if not IsInGuild() or not self.db then return end
    if not force and not onlyGuids and GetTime() - lastDigest < 60 then return end
    if not onlyGuids then lastDigest = GetTime() end
    local guild = self:GuildName()
    local d = {}
    for guid, m in pairs(self.db.members) do
        if (not onlyGuids or onlyGuids[guid]) and (m.guild == guild or self:IsMe(guid)) then
            d[guid] = self:DigestOf(m)
        end
    end
    self:Send({ k = "D", v = PROTO, f = self:PlayerGUID(), d = d, i = self:MyInfo() })
end

local pendingPush = {} -- [guid] = { e = from, c = from, s = true, g = true }
local pushTimerRunning = false
local lastRequest = {}

local function flushPushes()
    pushTimerRunning = false
    for guid, want in pairs(pendingPush) do
        local m = GJ:GetMember(guid)
        if m then
            -- Owners always answer for themselves; others skip if someone
            -- else already covered it since the request came in.
            local mine, since = GJ:IsMe(guid), want.since
            if want.e and (mine or not alreadyPushed(guid, "e", #m.events, since)) then GJ:PushEvents(m, want.e) end
            if want.s and (mine or not alreadyPushed(guid, "s", m.statsStamp or 0, since)) then GJ:PushStats(m) end
            if want.g and (mine or not alreadyPushed(guid, "g", m.gearStamp or 0, since)) then GJ:PushGear(m) end
            if want.c and (mine or not alreadyPushed(guid, "c", #m.cells, since)) then GJ:PushCells(m, want.c) end
        end
    end
    wipe(pendingPush)
end

local function schedulePush(guid, field, value)
    local p = pendingPush[guid]
    if not p then p = { since = GetTime() } pendingPush[guid] = p end
    if field == "e" or field == "c" then
        p[field] = math.min(p[field] or math.huge, value)
    else
        p[field] = true
    end
    if not pushTimerRunning then
        pushTimerRunning = true
        -- Owner of the data answers fast, everyone else waits a random bit.
        local delay = GJ:IsMe(guid) and 0.5 or (2 + math.random() * 6)
        C_Timer.After(delay, flushPushes)
    end
end

handlers.D = function(body, sender)
    if body.f == GJ:PlayerGUID() or type(body.d) ~= "table" then return end
    if body.f then peer(sender).guid = body.f end
    -- Their digest says they have nothing of ours: check they can hear us.
    local ofMe = body.d[GJ:PlayerGUID()]
    if body.f and (type(ofMe) ~= "table" or (ofMe[1] or 0) == 0) then GJ:ProbePeer(sender, body.f) end
    if body.f and body.i then
        local m = GJ:GetMember(body.f, true)
        GJ:ApplyInfo(m, body.i)
        m.lastSeen = GJ:Now()
    end
    local guild = GJ:GuildName()
    local theyHaveMore = {}
    local anyMore = false
    -- What do they lack that we have?
    for guid, m in pairs(GJ.db.members) do
        if m.guild == guild or GJ:IsMe(guid) then
            local theirs = body.d[guid] or { 0, 0, 0, 0 }
            local mine = GJ:DigestOf(m)
            if mine[1] > (theirs[1] or 0) then schedulePush(guid, "e", (theirs[1] or 0) + 1) end
            if mine[2] > (theirs[2] or 0) then schedulePush(guid, "c", (theirs[2] or 0) + 1) end
            if mine[3] > (theirs[3] or 0) then schedulePush(guid, "s") end
            if mine[4] > (theirs[4] or 0) then schedulePush(guid, "g") end
        end
    end
    -- What do they have that we lack? Ask for it with a targeted digest.
    for guid, theirs in pairs(body.d) do
        if type(theirs) == "table" and not GJ:IsMe(guid) then
            local m = GJ:GetMember(guid)
            local mine = m and GJ:DigestOf(m) or { 0, 0, 0, 0 }
            for i = 1, 4 do
                if (theirs[i] or 0) > mine[i] then
                    if GetTime() - (lastRequest[guid] or 0) > 60 then
                        theyHaveMore[guid] = true
                        anyMore = true
                    end
                    break
                end
            end
        end
    end
    if anyMore then
        for guid in pairs(theyHaveMore) do lastRequest[guid] = GetTime() end
        C_Timer.After(1 + math.random() * 3, function() GJ:BroadcastDigest(false, theyHaveMore) end)
    end
end

local function requestMissing(guid)
    if GetTime() - (lastRequest[guid] or 0) < 60 then return end
    lastRequest[guid] = GetTime()
    C_Timer.After(2 + math.random() * 3, function() GJ:BroadcastDigest(false, { [guid] = true }) end)
end

handlers.E = function(body)
    if type(body.g) ~= "string" then return end
    if GJ:IsMe(body.g) then return end
    local m = GJ:GetMember(body.g, true)
    GJ:ApplyInfo(m, body.i)
    local n = GJ:MergeEvents(body.g, body.s, body.e)
    if n < 0 then requestMissing(body.g) end
    if type(body.s) == "number" and type(body.e) == "table" then
        markPushed(body.g, "e", body.s + #body.e - 1)
    end
end

handlers.C = function(body)
    if type(body.g) ~= "string" or type(body.c) ~= "string" then return end
    if GJ:IsMe(body.g) then return end
    local list = {}
    for token in body.c:gmatch("[^,]+") do
        list[#list + 1] = tonumber(token, 36)
    end
    local n = GJ:MergeCells(body.g, body.s, list)
    if n < 0 then requestMissing(body.g) end
    if type(body.s) == "number" then markPushed(body.g, "c", body.s + #list - 1) end
end

handlers.S = function(body)
    if type(body.g) ~= "string" or GJ:IsMe(body.g) then return end
    local m = GJ:GetMember(body.g, true)
    GJ:ApplyInfo(m, body.i)
    GJ:MergeSnapshot(body.g, "stats", body.t, body.s)
    if type(body.t) == "number" then markPushed(body.g, "s", body.t) end
end

handlers.G = function(body)
    if type(body.g) ~= "string" or GJ:IsMe(body.g) then return end
    GJ:MergeSnapshot(body.g, "gear", body.t, body.q)
    if type(body.t) == "number" then markPushed(body.g, "g", body.t) end
end

-- Live position ping (not stored long-term, not relayed).
handlers.P = function(body)
    if type(body.g) ~= "string" or GJ:IsMe(body.g) then return end
    local m = GJ:GetMember(body.g, true)
    GJ:ApplyInfo(m, body.i)
    m.lastSeen = GJ:Now()
    m.live = { t = GJ:Now(), m = body.m, x = body.x, y = body.y, z = body.z, inst = body.inst, dead = body.dead }
    GJ:Fire("GJ_LIVE_UPDATED", body.g)
end

---------------------------------------------------------------------------
-- Can they hear us? Ask over the guild channel; if no answer comes back,
-- they are deaf to our GUILD messages, so whisper them everything as well.
---------------------------------------------------------------------------
local PROBE_WAIT = 20

function GJ:ProbePeer(sender, guid)
    local p = peer(sender)
    if p.whisper or (p.probing and GetTime() - p.probing < 120) then return end
    p.probing = GetTime()
    p.acked = false
    self:SendUrgent({ k = "Q", v = PROTO, f = self:PlayerGUID(), to = guid })
    C_Timer.After(PROBE_WAIT, function()
        if p.acked or p.whisper then return end
        p.whisper = true
        GJ:Debug(("%s isn't receiving guild addon messages from us - whispering them instead."):format(sender))
        GJ:SendLivePing()
        GJ:BroadcastDigest(true)
    end)
end

handlers.Q = function(body, sender)
    if body.to ~= GJ:PlayerGUID() or type(body.f) ~= "string" then return end
    GJ:SendUrgent({ k = "R", v = PROTO, f = GJ:PlayerGUID(), to = body.f })
end

handlers.R = function(body, sender)
    if body.to ~= GJ:PlayerGUID() then return end
    peer(sender).acked = true
end

-- Forget whisper mode for people who went offline; re-probe next time.
local function expirePeers()
    local now = GetTime()
    for _, p in pairs(peers) do
        if now - p.last > 300 then
            p.whisper, p.probing, p.acked = nil, nil, nil
        end
    end
end

function GJ:PrintStatus()
    local now = GetTime()
    self:Print(("Sync status (v%s)"):format(self.version))
    DEFAULT_CHAT_FRAME:AddMessage(("   Guild: %s   Prefix registered: %s   Chat lockdown: %s"):format(
        tostring(self:GuildName()), tostring(C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX)),
        tostring(inLockdown())))
    DEFAULT_CHAT_FRAME:AddMessage(("   Sent: %d guild, %d whisper   Failed: %d   Dropped: %d   Queued: %d%s"):format(
        stats.guild, stats.whisper, stats.failed, stats.dropped, self:QueueSize(),
        stats.lastError and ("   Last error: " .. stats.lastError) or ""))
    local any = false
    for name, p in pairs(peers) do
        any = true
        local mode = p.whisper and "|cffffd100whispering them|r" or (p.acked and "|cff55ff55hears us|r") or (p.probing and "checking..." or "")
        DEFAULT_CHAT_FRAME:AddMessage(("   %s: %d msgs, last %ds ago via %s  %s"):format(
            name, p.n, math.floor(now - p.last), tostring(p.channel), mode))
    end
    if not any then
        DEFAULT_CHAT_FRAME:AddMessage("   Heard from nobody yet. If a guildie with the addon is online, their game isn't reaching yours.")
    end
end

---------------------------------------------------------------------------
-- Our own updates: push new events/cells promptly so online guildies get
-- them live.
---------------------------------------------------------------------------
local ownDirty = {}
local ownTimer = false

local function flushOwn()
    ownTimer = false
    local me = GJ:Me()
    if ownDirty.e then GJ:PushEvents(me, ownDirty.e) end
    if ownDirty.s then GJ:PushStats(me) end
    if ownDirty.g then GJ:PushGear(me) end
    if ownDirty.c then GJ:PushCells(me, ownDirty.c) end
    wipe(ownDirty)
end

function GJ:MarkOwnDirty(field, fromIndex)
    if field == "e" or field == "c" then
        ownDirty[field] = math.min(ownDirty[field] or math.huge, fromIndex)
    else
        ownDirty[field] = true
    end
    if not ownTimer then
        ownTimer = true
        C_Timer.After(field == "e" and 2 or 20, flushOwn)
    end
end

GJ:On("GJ_OWN_EVENT", function()
    local me = GJ:Me()
    GJ:MarkOwnDirty("e", #me.events)
end)

function GJ:SendLivePing()
    if not IsInGuild() then return end
    local mapID, x, y = self:GetPlayerPosition()
    local inst
    local inInstance, instType = IsInInstance()
    if inInstance then inst = GetInstanceInfo() end
    self:SendLive({
        k = "P", v = PROTO, g = self:PlayerGUID(), i = self:MyInfo(),
        m = mapID,
        x = x and math.floor(x * 1000 + 0.5),
        y = y and math.floor(y * 1000 + 0.5),
        z = GetZoneText(),
        inst = inst,
        dead = UnitIsDeadOrGhost("player") or nil,
    })
end

---------------------------------------------------------------------------
-- Startup and timers
---------------------------------------------------------------------------
GJ:On("GJ_LOGIN", function()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    C_Timer.NewTicker(0.25, pump)
    C_Timer.NewTicker(60, cleanupPartials)
    C_Timer.NewTicker(60, expirePeers)
    GJ:On("GUILD_ROSTER_UPDATE", refreshRoster)
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
    refreshRoster()
    C_Timer.NewTicker(LIVE_INTERVAL, function() GJ:SendLivePing() end)
    -- Let the guild roster settle, then announce what we have.
    C_Timer.After(8, function()
        GJ:RefreshMyInfo()
        GJ:SendLivePing()
        GJ:BroadcastDigest(true)
    end)
    -- Joined (or changed) guild mid-session: introduce ourselves right away,
    -- sharing everything recorded before there was a guild.
    local knownGuild = GJ:GuildName()
    GJ:On("PLAYER_GUILD_UPDATE", function()
        C_Timer.After(3, function()
            local guild = GJ:GuildName()
            if guild and guild ~= knownGuild then
                knownGuild = guild
                GJ:RefreshMyInfo()
                GJ:Print(("Joined %s - sharing your journey with the guild."):format(guild))
                GJ:SendLivePing()
                GJ:BroadcastDigest(true)
            end
        end)
    end)
    C_Timer.NewTicker(DIGEST_INTERVAL, function()
        C_Timer.After(math.random() * 60, function() GJ:BroadcastDigest(false) end)
    end)
end)
