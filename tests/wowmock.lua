-- Minimal World of Warcraft API mock so the addon can be loaded and its sync
-- logic exercised outside the game. Each simulated player gets its own
-- global environment; addon messages go over a shared in-memory "guild".
local Mock = {}

Mock.now = 1000          -- virtual GetTime()
Mock.epoch = 1790000000  -- virtual time()
Mock.clients = {}
Mock.timers = {}
Mock.sent = 0

-- A permissive object: any method call works and returns another permissive
-- object (good enough for frames/textures/fontstrings).
local function permissive()
    local obj = {}
    local mt = {}
    mt.__index = function(t, k)
        local f = function(self, ...)
            if k == "GetWidth" or k == "GetHeight" then return 100 end
            if k == "GetSize" then return 100, 100 end
            if k == "IsShown" then return false end
            if k == "GetStringHeight" then return 12 end
            if k == "GetStringWidth" then return 60 end
            if k == "GetVerticalScrollRange" or k == "GetVerticalScroll" then return 0 end
            if k == "GetFont" then return "Fonts\\FRIZQT__.TTF", 12, "" end
            if k == "GetFrameLevel" then return 1 end
            if k == "GetCenter" then return 50, 50 end
            if k == "GetEffectiveScale" then return 1 end
            return permissive()
        end
        rawset(t, k, f)
        return f
    end
    mt.__call = function() return permissive() end
    return setmetatable(obj, mt)
end
Mock.permissive = permissive

function Mock.addTimer(delay, fn, ticker)
    local t = { at = Mock.now + delay, fn = fn, every = ticker and delay or nil, cancelled = false }
    t.Cancel = function(self) self.cancelled = true end
    table.insert(Mock.timers, t)
    return t
end

function Mock.advance(seconds, step)
    step = step or 0.25
    local target = Mock.now + seconds
    while Mock.now < target do
        Mock.now = Mock.now + step
        Mock.epoch = Mock.epoch + step
        local due = {}
        for _, t in ipairs(Mock.timers) do
            if not t.cancelled and t.at <= Mock.now then due[#due + 1] = t end
        end
        for _, t in ipairs(due) do
            if t.every then
                t.at = t.at + t.every
            else
                t.cancelled = true
            end
            local ok, err = pcall(t.fn, t)
            if not ok then error(err) end
        end
        for _, cl in ipairs(Mock.clients) do
            if cl.online and cl.onUpdates then
                for frame, fn in pairs(cl.onUpdates) do
                    local ok, err = pcall(fn, frame, step)
                    if not ok then error("OnUpdate error: " .. tostring(err)) end
                end
            end
        end
        local live = {}
        for _, t in ipairs(Mock.timers) do if not t.cancelled then live[#live + 1] = t end end
        Mock.timers = live
    end
end

-- Build a fresh environment for one simulated player.
function Mock.newClient(opts)
    local c = {
        name = opts.name, guid = opts.guid, class = opts.class or "WARRIOR",
        level = opts.level or 1, guild = opts.guild or "Unregistered Hypercam Users",
        online = false, frames = {}, money = 0, mapID = opts.mapID or 1429,
        x = opts.x or 0.5, y = opts.y or 0.5, inventory = {},
    }
    local env = {}
    setmetatable(env, { __index = _G })
    c.env = env
    env._G = env

    env.GetTime = function() return Mock.now end
    env.time = function() return math.floor(Mock.epoch) end
    env.date = function(fmt, t) return os.date(fmt, t or math.floor(Mock.epoch)) end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.tostringall = function(...)
        local t = { ... }
        for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
        return unpack(t, 1, select("#", ...))
    end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.tinsert = table.insert
    env.unpack = unpack
    env.geterrorhandler = function() return function(e) error(e, 0) end end
    env.hooksecurefunc = function(a, b, cfn)
        if type(a) == "table" then
            local orig = a[b]
            a[b] = function(...) local r = { orig(...) } cfn(...) return unpack(r) end
        else
            local orig = env[a]
            env[a] = function(...) local r = { orig(...) } b(...) return unpack(r) end
        end
    end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) c.log = c.log or {} table.insert(c.log, msg) end }
    env.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    env.C_Timer = {
        After = function(d, fn) Mock.addTimer(d, fn) end,
        NewTicker = function(d, fn) return Mock.addTimer(d, fn, true) end,
    }
    env.CreateFrame = function(kind, name)
        local f = permissive()
        rawset(f, "RegisterEvent", function(self, ev) c.events = c.events or {} c.events[ev] = true end)
        rawset(f, "SetScript", function(self, script, fn)
            if script == "OnEvent" then c.onEvent = fn end
            if script == "OnUpdate" then
                c.onUpdates = c.onUpdates or {}
                c.onUpdates[self] = fn
            end
        end)
        if name then env[name] = f end
        return f
    end
    env.UIParent = permissive()
    env.Minimap = permissive()
    env.UISpecialFrames = {}
    env.GameTooltip = permissive()
    env.GameTooltip_Hide = function() end
    env.WorldMapFrame = nil
    env.SlashCmdList = {}
    env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" }, MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" } }
    env.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage" }
    env.Enum = { UIMapType = { Zone = 3 } }
    env.SOUNDKIT = {}
    env.PlaySound = function() end

    env.UnitGUID = function(u) if u == "player" then return c.guid end end
    env.UnitName = function(u) if u == "player" then return c.name end end
    env.UnitClass = function() return c.class, c.class end
    env.UnitRace = function() return "Human", "Human" end
    env.UnitSex = function() return 2 end
    env.UnitLevel = function() return c.level end
    env.UnitIsDeadOrGhost = function() return c.dead or false end
    env.UnitOnTaxi = function() return false end
    env.IsInGuild = function() return c.guild ~= nil end
    env.GetGuildInfo = function() return c.guild end
    env.IsInInstance = function() return false end
    env.GetInstanceInfo = function() return nil end
    env.GetZoneText = function() return "Elwynn Forest" end
    env.GetSubZoneText = function() return c.subzone or "" end
    env.IsIndoors = function() return c.subzone == "Lion's Pride Inn" end
    env.IsResting = function() return false end
    env.IsMounted = function() return false end
    env.GetMoney = function() return c.money end
    env.GetMaxPlayerLevel = function() return 60 end
    env.GetInventoryItemLink = function(_, slot) return c.inventory[slot] end
    env.GetInventoryItemID = function(_, slot)
        local l = c.inventory[slot]
        return l and tonumber(l:match("item:(%d+)"))
    end
    env.GetInventoryItemQuality = function(_, slot) return c.inventory[slot] and 2 end
    -- Modern engine: no GetItemInfo/GetItemIcon globals, only C_Item.
    env.GetItemInfo = nil
    env.C_Item = {
        GetItemInfo = function(item)
            c.itemInfoCalls = (c.itemInfoCalls or 0) + 1
            return "Test Helm", "|cff1eff00|Hitem:1234|h[Test Helm]|h|r", 2, nil, nil, nil, nil, nil, nil, 133071
        end,
        GetItemIconByID = function() return 133071 end,
        GetItemQualityColor = function() return 0.12, 1, 0 end,
        GetDetailedItemLevelInfo = function() return 10 end,
    }
    env.GetNumSkillLines = function() return 0 end
    env.CombatLogGetCurrentEventInfo = function() c.touchedCombatLog = true end
    env.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
    -- c.target = { name = "Rabbit", hostile = true, attackingMe = true, critter = true, dead = false }
    env.UnitExists = function(u) return (u == "target" and c.target ~= nil) or u == "player" end
    env.UnitName = function(u)
        if u == "player" then return c.name end
        if u == "target" and c.target then return c.target.name end
    end
    env.UnitCanAttack = function(_, u) return u == "target" and c.target and c.target.hostile or false end
    env.UnitIsUnit = function(a, b)
        if a == "targettarget" and b == "player" then return c.target and c.target.attackingMe or false end
        return a == b
    end
    env.UnitIsDead = function(u) return u == "target" and c.target and c.target.dead or false end
    env.UnitCreatureType = function(u) return u == "target" and c.target and c.target.critter and "Critter" or "Beast" end
    env.UnitAffectingCombat = function() return c.inCombat or false end
    env.IsFalling = function() return c.falling or false end
    env.UnitHealth = function(u) if u == "player" then return c.hp or 100 end end
    env.C_NamePlate = { GetNamePlates = function() return {} end }
    env.ChatFrame1 = { registered = true }
    function env.ChatFrame1:IsEventRegistered() return self.registered end
    function env.ChatFrame1:UnregisterEvent() self.registered = false end
    function env.ChatFrame1:RegisterEvent() self.registered = true end
    env.RequestTimePlayed = function() end

    env.C_Map = {
        GetBestMapForUnit = function() return c.mapID end,
        GetMapInfo = function(id) return { mapID = id, name = "Zone" .. id, mapType = 3, parentMapID = 0 } end,
        GetPlayerMapPosition = function(id)
            return { GetXY = function() return c.x, c.y end }
        end,
    }

    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, text, channel, target)
            if not c.online then return false end
            assert(#text <= 255, "addon message too long: " .. #text)
            assert(not text:find("%z"), "NUL in addon message")
            Mock.sent = Mock.sent + 1
            if channel == "WHISPER" then
                Mock.whispers = (Mock.whispers or 0) + 1
                local delivered = false
                for _, other in ipairs(Mock.clients) do
                    if other.online and other.name == target then
                        other:fire("CHAT_MSG_ADDON", prefix, text, channel, c.name)
                        delivered = true
                    end
                end
                if not delivered then
                    -- What the real game does: a system message in chat.
                    local msg = ("No player named '%s' is currently playing."):format(target)
                    c.offlineWhispers = (c.offlineWhispers or 0) + 1
                    local hidden = false
                    for _, f in ipairs(c.chatFilters or {}) do
                        if f(nil, "CHAT_MSG_SYSTEM", msg) then hidden = true end
                    end
                    if not hidden then c.visibleSpam = (c.visibleSpam or 0) + 1 end
                    c:fire("CHAT_MSG_SYSTEM", msg)
                end
                return true
            end
            for _, other in ipairs(Mock.clients) do
                -- deafTo[name]: this client never receives name's GUILD messages
                if other.online and other.guild == c.guild and not (other.deafTo and other.deafTo[c.name]) then
                    other:fire("CHAT_MSG_ADDON", prefix, text, channel, c.name)
                end
            end
            return true
        end,
        IsAddonMessagePrefixRegistered = function() return true end,
    }

    function c:fire(event, ...)
        if self.onEvent and self.events and self.events[event] then
            self.onEvent(nil, event, ...)
        end
    end

    env.ChatFrame_DisplayTimePlayed = function() end
    env.ChatFrame_AddMessageEventFilter = function(event, fn)
        if event == "CHAT_MSG_SYSTEM" then
            c.chatFilters = c.chatFilters or {}
            table.insert(c.chatFilters, fn)
        end
    end
    c.originalGlobals = { ChatFrame_DisplayTimePlayed = env.ChatFrame_DisplayTimePlayed }

    function c:load(files)
        local ns = {}
        for _, path in ipairs(files) do
            local fh = assert(io.open(path, "r"))
            local src = fh:read("*a")
            fh:close()
            local chunk = assert(loadstring(src, path))
            setfenv(chunk, env)
            chunk("GoonerJourneys", ns)
        end
        self.GJ = ns
        return ns
    end

    function c:login()
        self.online = true
        self:fire("ADDON_LOADED", "GoonerJourneys")
        self:fire("PLAYER_LOGIN")
        self:fire("PLAYER_ENTERING_WORLD")
    end

    function c:logout()
        self.online = false
    end

    table.insert(Mock.clients, c)
    return c
end

return Mock
