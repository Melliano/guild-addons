-- Tracks your own journey: levels, deaths, zones, dungeons, bosses,
-- professions, gear upgrades, stats and a pile of silly milestones.
local _, GJ = ...

local ICON = "Interface\\Icons\\"
local MAX_LEVEL = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60

---------------------------------------------------------------------------
-- Silly (and not so silly) milestones driven by counters.
-- stat -> list of { threshold, id, title, description, icon }
---------------------------------------------------------------------------
local MILE = 1760 -- yards in a mile

GJ.CounterMilestones = {
    deaths = {
        { 1,   "Welcome To The Spirit Healer", "Died for the first time. It gets easier.", "Spell_Holy_Resurrection" },
        { 10,  "Corpse Runner", "Died 10 times.", "Ability_Rogue_Sprint" },
        { 25,  "Frequent Dier", "Died 25 times. The Spirit Healer knows your name.", "Spell_Shadow_DeathScream" },
        { 50,  "Spirit Healer's Favourite", "Died 50 times.", "Spell_Holy_SpiritHeal" },
        { 100, "Professional Floor Inspector", "Died 100 times.", "INV_Misc_Bone_HumanSkull_01" },
    },
    kills = {
        { 100,   "Getting Warmed Up", "100 kills.", "INV_Sword_04" },
        { 1000,  "Murder Hobo", "1,000 kills.", "INV_Sword_27" },
        { 5000,  "Walking Extinction Event", "5,000 kills.", "Ability_Warrior_Rampage" },
        { 10000, "Azeroth's Problem", "10,000 kills.", "Spell_Shadow_ShadowWordPain" },
    },
    critters = {
        { 1,   "Bunny Bully", "Killed a defenceless critter. Monster.", "INV_Misc_Food_15" },
        { 25,  "Critter Crusher", "Killed 25 critters.", "Ability_Hunter_Pet_Boar" },
        { 100, "Menace To Wildlife", "Killed 100 critters. The squirrels have a bounty on you.", "Ability_Hunter_Pet_Bat" },
    },
    jumps = {
        { 1000,  "Bunny Hopper", "Jumped 1,000 times.", "Ability_Rogue_Sprint" },
        { 10000, "Kangaroo Mode", "Jumped 10,000 times.", "Spell_Nature_Swiftness" },
        { 50000, "Has Never Walked Anywhere", "Jumped 50,000 times. Your spacebar wants a word.", "Ability_Druid_Dash" },
    },
    hearths = {
        { 10,  "Homebody", "Used your Hearthstone 10 times.", "INV_Misc_Rune_01" },
        { 100, "Homesick", "Used your Hearthstone 100 times.", "INV_Misc_Rune_01" },
    },
    flights = {
        { 1,   "Look Ma, No Hands", "Took your first flight path.", "Ability_Mount_Wyvern_01" },
        { 25,  "Frequent Flyer", "Took 25 flight paths.", "Ability_Mount_Wyvern_01" },
        { 100, "Gryphon Gold Member", "Took 100 flight paths.", "Ability_Mount_Wyvern_01" },
    },
    falls = {
        { 25,  "Gravity Tester", "Took falling damage 25 times.", "Spell_Magic_FeatherFall" },
        { 100, "Ankles Of Glass", "Took falling damage 100 times.", "Spell_Magic_FeatherFall" },
    },
    fallDeaths = {
        { 1, "Gravity Check", "Died from falling. The ground won.", "Spell_Magic_FeatherFall" },
        { 5, "Thinks They Can Fly", "Died from falling 5 times.", "Spell_Magic_FeatherFall" },
    },
    drownDeaths = {
        { 1, "Forgot To Breathe", "Drowned. Fish do it all the time, how hard can it be?", "Spell_Frost_SummonWaterElemental" },
    },
    critterDeaths = {
        { 1, "Humiliated By Wildlife", "Was killed by a critter. Never live this down.", "INV_Misc_Food_15" },
    },
    dances = {
        { 50,  "Dancing Queen", "Danced 50 times.", "INV_Misc_Toy_07" },
        { 500, "Night Elf Energy", "Danced 500 times. Should you be levelling?", "INV_Misc_Toy_07" },
    },
    hugs = {
        { 25, "Hug Dealer", "Hugged 25 times.", "Spell_Holy_PrayerOfHealing" },
    },
    guildMsgs = {
        { 100,  "Yapper", "Sent 100 guild chat messages.", "INV_Misc_Note_01" },
        { 1000, "Professional Yapper", "Sent 1,000 guild chat messages.", "INV_Misc_Note_01" },
        { 5000, "Has A Keyboard Problem", "Sent 5,000 guild chat messages.", "INV_Misc_Note_02" },
    },
    quests = {
        { 50,   "Errand Runner", "Turned in 50 quests.", "INV_Misc_Book_09" },
        { 250,  "Exclamation Mark Addict", "Turned in 250 quests.", "INV_Misc_Book_09" },
        { 500,  "Quest Goblin", "Turned in 500 quests.", "INV_Misc_Book_11" },
        { 1000, "Has Read Zero Quest Text", "Turned in 1,000 quests.", "INV_Misc_Book_11" },
    },
    pvpKills = {
        { 1,   "First Blood (Real)", "Got an honorable kill on another player.", "Ability_Warrior_BattleShout" },
        { 100, "Gank Squad", "100 honorable kills.", "Ability_Warrior_BattleShout" },
    },
    goldGained = {
        { 100 * 10000,  "Gold Digger", "Earned 100 gold over your journey.", "INV_Misc_Coin_02" },
        { 1000 * 10000, "Goblin Banker", "Earned 1,000 gold over your journey.", "INV_Misc_Coin_01" },
    },
    distance = {
        { 10 * MILE,  "Stretched The Legs", "Travelled 10 miles on foot or mount.", "Ability_Rogue_Sprint" },
        { 100 * MILE, "Walked To Mordor (Wrong Game)", "Travelled 100 miles.", "Ability_Mount_RidingHorse" },
        { 500 * MILE, "And I Would Walk 500 More", "Travelled 500 miles.", "Ability_Mount_RidingHorse" },
    },
    wipes = {
        { 1,  "Wipe Club", "Was part of a full group wipe.", "Spell_Shadow_DeathCoil" },
        { 10, "Wipe Club President", "Was part of 10 group wipes.", "Spell_Shadow_DeathCoil" },
    },
    played = {
        { 86400,     "Touch Grass Warning", "1 day of /played.", "INV_Misc_Herb_07" },
        { 7 * 86400, "Touch Grass Emergency", "7 days of /played.", "INV_Misc_Herb_07" },
        { 30 * 86400, "Has Become The Game", "30 days of /played. You live here now.", "INV_Misc_Herb_07" },
    },
}

-- One-off silly milestones.
GJ.OneOffMilestones = {
    nightOwl     = { "Night Gooner", "Was playing between 3 and 5 in the morning.", "Spell_Shadow_Twilight" },
    skint        = { "Absolutely Skint", "Had zero copper at level 20 or higher.", "INV_Misc_Bag_10" },
    naked        = { "Naked And Afraid", "Wandered around with nothing equipped at level 10+.", "INV_Chest_Cloth_21" },
    dingDead     = { "Ding... Dead", "Died within a minute of levelling up.", "Spell_Shadow_DeathScream" },
    townDeath    = { "Died In Town (How?)", "Died while in a rested area.", "INV_Misc_Bone_HumanSkull_01" },
    sameDayDeaths = { "Bad Day At The Office", "Died 5 times in one session.", "Spell_Shadow_DeathScream" },
    firstMount   = { "Giddy Up", "Rode a mount for the first time.", "Ability_Mount_RidingHorse" },
    maxLevel     = { "Certified Gooner", "Reached max level.", "INV_Misc_Head_Dragon_01" },
}

---------------------------------------------------------------------------
-- How timeline events are shown.
---------------------------------------------------------------------------
local function itemText(id)
    local name, link = GJ.ItemInfo(id)
    return link or name or ("item " .. tostring(id))
end

GJ.EventKinds = {
    start   = { icon = "INV_Misc_Map_01", text = function(ev) return ("Began their Gooner Journey at level %d"):format(ev.l or 1) end },
    level   = { icon = "Spell_Holy_SurgeOfLight", text = function(ev)
        local s = ("Reached level %d"):format(ev.d or 0)
        if ev.lt and ev.p then
            s = s .. (" |cff999999(level took %s, %s played)|r"):format(GJ:FormatDuration(ev.lt), GJ:FormatDuration(ev.p))
        elseif ev.p then
            s = s .. (" |cff999999(%s played)|r"):format(GJ:FormatDuration(ev.p))
        end
        return s
    end },
    death   = { icon = "INV_Misc_Bone_HumanSkull_01", color = "ffff5555", text = function(ev)
        return ("Died to %s"):format(ev.d or "unknown causes")
    end },
    zone    = { icon = "INV_Misc_Map_01", text = function(ev) return ("Explored %s for the first time"):format(ev.d or "?") end },
    dungeon = { icon = "INV_Misc_Key_14", text = function(ev) return ("First time entering %s"):format(ev.d or "?") end },
    raid    = { icon = "INV_Misc_Key_10", color = "ffff8000", text = function(ev) return ("First time entering raid: %s"):format(ev.d or "?") end },
    boss    = { icon = "INV_Misc_Head_Dragon_01", color = "ffa335ee", text = function(ev)
        if ev.inst then return ("First kill: %s (%s)"):format(ev.d or "?", ev.inst) end
        return ("First kill: %s"):format(ev.d or "?")
    end },
    prof    = { icon = "Trade_Engineering", text = function(ev)
        local name, rank = tostring(ev.d or ""):match("^(.-)|(%d+)$")
        if not name then return tostring(ev.d) end
        if rank == "1" then return ("Learned %s"):format(name) end
        return ("Reached %s %s"):format(rank, name)
    end },
    item    = { icon = "INV_Chest_Plate06", text = function(ev)
        local label = ({ [3] = "rare", [4] = "epic", [5] = "legendary" })[ev.q or 0] or "shiny"
        return ("Equipped their first %s: %s"):format(label, itemText(ev.d))
    end },
    silly   = { icon = "INV_Misc_QuestionMark", color = "ffffd100", text = function(ev)
        local m = GJ:MilestoneInfo(ev.d)
        if m then return ("|cffffd100%s|r - %s"):format(m[1], m[2]) end
        return tostring(ev.d)
    end },
}

function GJ:MilestoneInfo(id)
    if type(id) ~= "string" then return nil end
    if self.OneOffMilestones[id] then return self.OneOffMilestones[id] end
    local stat, threshold = id:match("^(%w+):(%d+)$")
    local list = stat and self.CounterMilestones[stat]
    if list then
        threshold = tonumber(threshold)
        for _, m in ipairs(list) do
            if m[1] == threshold then return { m[2], m[3], m[4] } end
        end
    end
    return nil
end

function GJ:EventIcon(ev)
    if ev.k == "silly" then
        local m = self:MilestoneInfo(ev.d)
        if m and m[3] then return ICON .. m[3] end
    elseif ev.k == "item" and ev.d then
        local tex = GJ.ItemIcon(ev.d)
        if tex then return tex end
    end
    local kind = self.EventKinds[ev.k]
    return ICON .. (kind and kind.icon or "INV_Misc_QuestionMark")
end

function GJ:EventText(ev)
    local kind = self.EventKinds[ev.k]
    if not kind then return tostring(ev.k) .. ": " .. tostring(ev.d) end
    local ok, text = pcall(kind.text, ev)
    text = ok and text or "?"
    if kind.color and ev.k ~= "silly" then text = "|c" .. kind.color .. text .. "|r" end
    return text
end

---------------------------------------------------------------------------
-- Stats helpers
---------------------------------------------------------------------------
local function stats()
    return GJ:Me().stats
end

local function touchStats()
    local me = GJ:Me()
    me.statsStamp = GJ:Now()
    GJ:MarkOwnDirty("s")
    GJ:Fire("GJ_DATA_CHANGED", me.guid, "stats")
end

function GJ:Silly(id)
    local me = self:Me()
    if self:HasEvent(me, "silly", id) then return end
    local info = self:MilestoneInfo(id)
    self:AddEvent("silly", id)
    if info then
        self:Print(("Milestone unlocked: |cffffd100%s|r - %s"):format(info[1], info[2]))
        PlaySound(SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 888)
    end
end

function GJ:SetStat(stat, value)
    local s = stats()
    if s[stat] == value then return end
    s[stat] = value
    local list = self.CounterMilestones[stat]
    if list then
        for _, m in ipairs(list) do
            if value >= m[1] then self:Silly(stat .. ":" .. m[1]) end
        end
    end
    touchStats()
end

function GJ:Bump(stat, amount)
    self:SetStat(stat, (stats()[stat] or 0) + (amount or 1))
end

---------------------------------------------------------------------------
-- Played time (silently request it, without spamming chat)
---------------------------------------------------------------------------
local playedAt, playedTotal
local mutedFrames = {}
local pendingLevel -- level we just reached, waiting for /played to arrive

-- Briefly stop the chat windows listening for TIME_PLAYED_MSG so our silent
-- request does not print "Total time played" into chat. This only toggles
-- event registration; it never replaces Blizzard functions (which would
-- taint the UI).
local function unmuteChat()
    for frame in pairs(mutedFrames) do
        frame:RegisterEvent("TIME_PLAYED_MSG")
    end
    wipe(mutedFrames)
end

local function requestPlayed()
    if not RequestTimePlayed then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
            frame:UnregisterEvent("TIME_PLAYED_MSG")
            mutedFrames[frame] = true
        end
    end
    RequestTimePlayed()
    C_Timer.After(5, unmuteChat)
end

GJ:On("TIME_PLAYED_MSG", function(total)
    C_Timer.After(0, unmuteChat)
    if type(total) ~= "number" then return end
    playedTotal, playedAt = total, GetTime()
    GJ:SetStat("played", total)
    -- Level-by-level /played history for the Race to 60 chart.
    local s = stats()
    s.lvlp = s.lvlp or {}
    s.lvlt = s.lvlt or {}
    local level = pendingLevel or UnitLevel("player")
    local changed = false
    if pendingLevel and not s.lvlp[pendingLevel] then
        s.lvlp[pendingLevel], s.lvlt[pendingLevel] = total, GJ:Now()
        changed = true
    elseif level == 1 and not s.lvlp[1] then
        s.lvlp[1], s.lvlt[1] = 0, GJ:Now()
        changed = true
    end
    pendingLevel = nil
    if changed then touchStats() end
end)

function GJ:CurrentPlayed()
    if not playedTotal then return nil end
    return math.floor(playedTotal + (GetTime() - playedAt))
end

---------------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------------
local lastLevelUp = 0

-- /played when you reached `level`, if we know it.
local function playedAtLevel(level)
    local s = stats()
    if type(s.lvlp) == "table" and type(s.lvlp[level]) == "number" then return s.lvlp[level] end
    for _, ev in ipairs(GJ:Me().events) do
        if ev.k == "level" and ev.d == level and type(ev.p) == "number" then return ev.p end
    end
end

-- Every level is a milestone (and a guild news pop-up), with total /played
-- and how long that level took.
-- dinged: true when you just levelled up. On login we only know your
-- current level, not when you reached it, so no times are recorded then.
local function recordLevel(level, dinged)
    GJ:RefreshMyInfo()
    GJ:SetStat("level", level)
    if not GJ:HasEvent(GJ:Me(), "level", level) then
        local played = dinged and GJ:CurrentPlayed() or nil
        local extra = { p = played }
        local before = level > 1 and playedAtLevel(level - 1)
        if played and before and played >= before then extra.lt = played - before end
        if played then
            -- Remember it now, so the next level's time works even if the
            -- /played reply never comes.
            local s = stats()
            s.lvlp = s.lvlp or {}
            s.lvlt = s.lvlt or {}
            if not s.lvlp[level] then s.lvlp[level], s.lvlt[level] = played, GJ:Now() end
        end
        GJ:AddEvent("level", level, extra)
    end
    if level >= MAX_LEVEL then GJ:Silly("maxLevel") end
end

GJ:On("PLAYER_LEVEL_UP", function(level)
    lastLevelUp = GetTime()
    pendingLevel = level
    recordLevel(level, true)
    requestPlayed()
end)

---------------------------------------------------------------------------
-- Zones and instances
---------------------------------------------------------------------------
local ZONE_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

function GJ:ZoneMapID()
    local mapID = C_Map.GetBestMapForUnit("player")
    local guard = 0
    while mapID and guard < 10 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then break end
        if info.mapType == ZONE_TYPE then return mapID, info.name end
        if not info.parentMapID or info.parentMapID == 0 then break end
        mapID = info.parentMapID
        guard = guard + 1
    end
    return C_Map.GetBestMapForUnit("player")
end

local lastInstanceID, lastInstanceAt = nil, 0

local function checkLocation()
    local me = GJ:Me()
    local inInstance, instType = IsInInstance()
    if inInstance and (instType == "party" or instType == "raid") then
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        if name and instanceID then
            local kind = instType == "raid" and "raid" or "dungeon"
            if not GJ:HasEvent(me, kind, name) then
                GJ:AddEvent(kind, name, { iid = instanceID })
            end
            if instanceID ~= lastInstanceID or GetTime() - lastInstanceAt > 3600 then
                GJ:Bump(kind == "raid" and "raidRuns" or "dungeonRuns")
            end
            lastInstanceID, lastInstanceAt = instanceID, GetTime()
        end
        return
    end
    if inInstance then return end -- battlegrounds etc.
    local mapID, name = GJ:ZoneMapID()
    if mapID and name and not GJ:HasEvent(me, "zone", name) then
        GJ:AddEvent("zone", name)
        local count = 0
        for _, ev in ipairs(me.events) do if ev.k == "zone" then count = count + 1 end end
        GJ:SetStat("zones", count)
    end
end

GJ:On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(1, checkLocation) end)
GJ:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, checkLocation) end)

GJ:On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, groupSize, success)
    if success ~= 1 and success ~= true then return end
    GJ:Bump("bosses")
    local me = GJ:Me()
    for _, ev in ipairs(me.events) do
        if ev.k == "boss" and ev.eid == encounterID then return end
    end
    local inst = GetInstanceInfo()
    GJ:AddEvent("boss", encounterName, { eid = encounterID, inst = inst })
end)

---------------------------------------------------------------------------
-- Kills, critters, deaths, falls and wipes.
--
-- WoW Forever runs on the modern engine where the combat log is off limits
-- to addons (touching it triggers "blocked from an action only available to
-- the Blizzard UI"), so everything here uses ordinary events and unit
-- queries instead.
---------------------------------------------------------------------------
local CRITTERS = {}
for _, n in ipairs({
    "Rabbit", "Hare", "Squirrel", "Rat", "Toad", "Frog", "Cow", "Sheep", "Chicken", "Deer",
    "Fawn", "Roach", "Cockroach", "Snake", "Prairie Dog", "Adder", "Black Rat", "Maggot",
    "Skunk", "Mouse", "Biletoad", "Larva", "Fire Beetle", "Horned Toad", "Gazelle",
    "Hen", "Rooster", "Cat", "Crab", "Shore Crab", "Sand Crab", "Beetle", "Scorpid Larva",
}) do CRITTERS[n] = true end
GJ.CRITTERS = CRITTERS

-- Some unit info can be a "secret value" on the modern engine; never
-- compare or store those.
local function safe(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function isCritter(unit)
    local name = safe(UnitName(unit))
    if name and CRITTERS[name] then return true end
    local ctype = safe(UnitCreatureType and UnitCreatureType(unit))
    return ctype == "Critter" or (ctype ~= nil and ctype == (CRITTER or "Critter"))
end

-- Kills: the "X dies, you gain N experience" message.
local function patternFrom(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    -- Match only up to the end of the first sentence; bonus suffixes vary.
    p = p:match("^(.-%(%%d%+%))") or p
    return "^" .. p
end
local XP_PATTERN = patternFrom(COMBATLOG_XPGAIN_FIRSTPERSON) or "^(.+) dies, you gain (%d+) experience"

GJ:On("CHAT_MSG_COMBAT_XP_GAIN", function(text)
    text = safe(text)
    if type(text) == "string" and text:match(XP_PATTERN) then
        GJ:Bump("kills")
    end
end)

GJ:On("CHAT_MSG_COMBAT_HONOR_GAIN", function(text)
    text = safe(text)
    -- Honorable kill messages name the victim; bonus honor messages do not.
    if type(text) == "string" and text:find("dies") then
        GJ:Bump("pvpKills")
    end
end)

-- Critters: a critter we were targeting dies while we are attacking.
local critterSeen = {}
local function checkTargetCritter()
    if not UnitExists("target") or not UnitIsDead("target") then return end
    local guid = safe(UnitGUID("target"))
    if not guid or critterSeen[guid] then return end
    if isCritter("target") and (IsCurrentSpell and IsCurrentSpell(6603) or UnitAffectingCombat("player") or GJ.recentAttack) then
        critterSeen[guid] = true
        GJ:Bump("critters")
    end
end
GJ:On("UNIT_HEALTH", function(unit) if unit == "target" then pcall(checkTargetCritter) end end)
GJ:On("PLAYER_TARGET_CHANGED", function() GJ.recentAttack = nil end)
GJ:On("UNIT_SPELLCAST_SENT", function(unit) if unit == "player" then GJ.recentAttack = GetTime() end end)

-- Who is beating on us? Polled while in combat: our target if it is
-- attacking us, otherwise any nameplate unit targeting us.
local lastAttacker -- { name, t, critter }
local function unitAttackingMe(unit)
    if not UnitExists(unit) or not UnitCanAttack("player", unit) then return false end
    return UnitIsUnit(unit .. "target", "player")
end

local function scanAttacker()
    local found
    if unitAttackingMe("target") then
        found = "target"
    elseif C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit and unitAttackingMe(unit) then found = unit break end
        end
    end
    if not found and UnitExists("target") and UnitCanAttack("player", "target") then
        found = "target"
    end
    if found then
        local name = safe(UnitName(found))
        if name then lastAttacker = { name = name, t = GetTime(), critter = isCritter(found) } end
    end
end

-- Falling and drowning.
--
-- Addons can't see fall damage directly any more, so a "fall" is: you were
-- in the air for a while AND your health dropped when you landed, outside
-- of combat. Being airborne alone isn't enough - ordinary jumps down a
-- slope easily last over a second.
local MIN_AIRTIME = 0.9
local fallStart, fallHP = nil, nil
local lastFallDamage = 0
local lastLanding = { t = 0, air = 0 }
local breathRunning = false
GJ:On("MIRROR_TIMER_START", function(timer) if timer == "BREATH" then breathRunning = true end end)
GJ:On("MIRROR_TIMER_STOP", function(timer) if timer == "BREATH" then breathRunning = false end end)

local function playerHP()
    local hp = safe(UnitHealth("player"))
    return type(hp) == "number" and hp or nil
end

local function landed(airtime, startHP)
    lastLanding = { t = GetTime(), air = airtime }
    if airtime < MIN_AIRTIME or not startHP then return end
    -- Give the damage a moment to apply, then compare.
    C_Timer.After(0.3, function()
        local hp = playerHP()
        if hp and hp > 0 and hp < startHP and not UnitAffectingCombat("player") then
            lastFallDamage = GetTime()
            GJ:Bump("falls")
        end
    end)
end

local poll = CreateFrame("Frame")
local pollAcc = 0
poll:SetScript("OnUpdate", function(_, dt)
    pollAcc = pollAcc + dt
    if pollAcc < 0.1 then return end
    pollAcc = 0
    if IsFalling and IsFalling() then
        if not fallStart then
            fallStart = GetTime()
            fallHP = playerHP()
        end
    elseif fallStart then
        local air, hp = GetTime() - fallStart, fallHP
        fallStart, fallHP = nil, nil
        landed(air, hp)
    end
    if UnitAffectingCombat("player") then
        pcall(scanAttacker)
    end
end)

local lastWipe = 0
local sessionDeaths = 0

local function checkWipe()
    if not IsInInstance() or not IsInGroup or not IsInGroup() then return end
    local size = GetNumGroupMembers()
    if size < 3 then return end
    local prefix = IsInRaid() and "raid" or "party"
    local dead = UnitIsDeadOrGhost("player") and 1 or 0
    local count = IsInRaid() and size or (size - 1)
    for i = 1, count do
        local u = prefix .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") and UnitIsDeadOrGhost(u) then dead = dead + 1 end
    end
    if dead >= math.max(3, math.min(size, 5) - 1) and GetTime() - lastWipe > 300 then
        lastWipe = GetTime()
        GJ:Bump("wipes")
    end
end

-- PLAYER_DEAD can fire more than once for a single death (e.g. on release
-- or when logging in dead). Count it once, until we're alive again.
local deadLatch = false
local lastDeathAt = -1000
GJ:On("PLAYER_ENTERING_WORLD", function() deadLatch = UnitIsDeadOrGhost("player") and true or false end)
GJ:On("PLAYER_UNGHOST", function() deadLatch = false end)
GJ:On("PLAYER_ALIVE", function() if not UnitIsDeadOrGhost("player") then deadLatch = false end end)

GJ:On("PLAYER_DEAD", function()
    if deadLatch or GetTime() - lastDeathAt < 15 then return end
    deadLatch = true
    lastDeathAt = GetTime()
    sessionDeaths = sessionDeaths + 1
    local cause, extra = "unknown causes", {}
    local now = GetTime()
    if breathRunning then
        cause, extra.env = "drowning", "drowning"
    elseif (fallStart and now - fallStart > 1.5) or (now - lastLanding.t < 1 and lastLanding.air > 1.5)
        or now - lastFallDamage < 1 then
        cause, extra.env = "falling", "falling"
    else
        pcall(scanAttacker)
        if lastAttacker and now - lastAttacker.t < 10 then
            cause = lastAttacker.name
            extra.src = lastAttacker.name
            extra.critter = lastAttacker.critter or nil
        end
    end
    GJ:AddEvent("death", cause, extra)
    GJ:Bump("deaths")
    if extra.env == "falling" then GJ:Bump("fallDeaths") end
    if extra.env == "drowning" then GJ:Bump("drownDeaths") end
    if extra.critter or (extra.src and CRITTERS[extra.src]) then GJ:Bump("critterDeaths") end
    if now - lastLevelUp < 60 then GJ:Silly("dingDead") end
    if IsResting() then GJ:Silly("townDeath") end
    if sessionDeaths >= 5 then GJ:Silly("sameDayDeaths") end
    lastAttacker = nil
    C_Timer.After(4, function() pcall(checkWipe) end)
    GJ:SendLivePing(true)
end)

---------------------------------------------------------------------------
-- Quests, money, hearthstone, flights, mounts, chat, emotes, jumps
---------------------------------------------------------------------------
GJ:On("QUEST_TURNED_IN", function() GJ:Bump("quests") end)

local lastMoney
local function checkMoney()
    local money = GetMoney()
    if lastMoney and money > lastMoney then
        GJ:Bump("goldGained", money - lastMoney)
    end
    lastMoney = money
    if money > (stats().goldPeak or 0) then GJ:SetStat("goldPeak", money) end
    GJ:SetStat("gold", money)
    if money == 0 and UnitLevel("player") >= 20 then GJ:Silly("skint") end
end
GJ:On("PLAYER_MONEY", checkMoney)

local HEARTH_IDS = { [8690] = true }
GJ:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local name = GJ.SpellName(spellID)
    if HEARTH_IDS[spellID] or name == "Hearthstone" then
        GJ:Bump("hearths")
    end
end)

local onTaxi = false
local function checkTaxi()
    local now = UnitOnTaxi("player")
    if now and not onTaxi then GJ:Bump("flights") end
    onTaxi = now
end
GJ:On("PLAYER_CONTROL_LOST", function() C_Timer.After(1, checkTaxi) end)
GJ:On("PLAYER_CONTROL_GAINED", function() C_Timer.After(0.5, checkTaxi) end)

local function checkMount()
    if IsMounted() then
        GJ:Silly("firstMount")
    end
end
GJ:On("PLAYER_MOUNT_DISPLAY_CHANGED", checkMount)
GJ.CheckMount = checkMount

GJ:On("CHAT_MSG_GUILD", function(...)
    local guid = select(12, ...)
    if guid == UnitGUID("player") then GJ:Bump("guildMsgs") end
end)

-- Emotes: read our own emote messages rather than hooking emote functions.
GJ:On("CHAT_MSG_TEXT_EMOTE", function(text, ...)
    local guid = safe(select(11, ...))
    text = safe(text)
    if guid ~= UnitGUID("player") or type(text) ~= "string" then return end
    text = text:lower()
    if text:find("dance") then GJ:Bump("dances")
    elseif text:find("hug") then GJ:Bump("hugs") end
end)

-- Jumps are counted locally and folded into stats every so often, so we do
-- not mark stats dirty on every single spacebar press.
local pendingJumps = 0
if JumpOrAscendStart then
    hooksecurefunc("JumpOrAscendStart", function()
        if not IsFlying or not IsFlying() then pendingJumps = pendingJumps + 1 end
    end)
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
local PROF_HEADERS = {
    [TRADE_SKILLS or "Professions"] = true,
    ["Professions"] = true,
    ["Secondary Skills"] = true,
}
if SECONDARY_SKILLS then PROF_HEADERS[(SECONDARY_SKILLS:gsub(":$", ""))] = true end
local PROF_STEPS = { 1, 75, 150, 225, 300, 375 }

-- name -> rank for every profession the player knows.
local function readProfessions()
    local profs = {}
    if GetNumSkillLines and GetSkillLineInfo then
        local header
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank = GetSkillLineInfo(i)
            if isHeader then
                header = name
            elseif name and header and PROF_HEADERS[header] and type(rank) == "number" then
                profs[name] = rank
            end
        end
    elseif GetProfessions and GetProfessionInfo then
        -- Modern engine API.
        local list = { GetProfessions() }
        for i = 1, 6 do
            local index = list[i]
            if index then
                local name, _, rank = GetProfessionInfo(index)
                if name and type(rank) == "number" then profs[name] = rank end
            end
        end
    end
    return profs
end

local function checkProfessions()
    local me = GJ:Me()
    local ok, profs = pcall(readProfessions)
    if not ok or type(profs) ~= "table" then return end
    for name, rank in pairs(profs) do
        for _, step in ipairs(PROF_STEPS) do
            if rank >= step then
                local id = name .. "|" .. step
                if not GJ:HasEvent(me, "prof", id) then GJ:AddEvent("prof", id) end
            end
        end
    end
    local s = stats()
    local changed = false
    s.profs = s.profs or {}
    for name, rank in pairs(profs) do
        if s.profs[name] ~= rank then s.profs[name] = rank changed = true end
    end
    if changed then touchStats() end
end
GJ:On("SKILL_LINES_CHANGED", function() C_Timer.After(1, checkProfessions) end)

---------------------------------------------------------------------------
-- Gear milestones (first rare/epic/legendary equipped, naked check)
---------------------------------------------------------------------------
function GJ:CheckGearMilestones()
    local me = self:Me()
    local equipped = 0
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then
            if slot ~= 4 and slot ~= 19 then equipped = equipped + 1 end -- ignore shirt/tabard
            local q = GetInventoryItemQuality("player", slot)
            if q and q >= 3 then
                local have = false
                for _, ev in ipairs(me.events) do
                    if ev.k == "item" and ev.q == q then have = true break end
                end
                if not have then self:AddEvent("item", id, { q = q }) end
            end
        end
    end
    if equipped == 0 and UnitLevel("player") >= 10 then self:Silly("naked") end
end

---------------------------------------------------------------------------
-- Login
---------------------------------------------------------------------------
-- Take duplicate deaths recorded by older versions back off our counters.
-- Remembers how many were already corrected, so it only happens once.
function GJ:FixDuplicateDeathStats()
    local me = self:Me()
    local dups = { deaths = 0, fallDeaths = 0, drownDeaths = 0, critterDeaths = 0 }
    for _, ev in ipairs(me.events) do
        if ev.k == "death" and ev.dup then
            dups.deaths = dups.deaths + 1
            if ev.env == "falling" then dups.fallDeaths = dups.fallDeaths + 1 end
            if ev.env == "drowning" then dups.drownDeaths = dups.drownDeaths + 1 end
            if ev.critter or (ev.src and CRITTERS[ev.src]) then dups.critterDeaths = dups.critterDeaths + 1 end
        end
    end
    local priv = self.db.private
    priv.deathDupsFixed = priv.deathDupsFixed or {}
    local done = priv.deathDupsFixed[me.guid] or {}
    local s = stats()
    for stat, n in pairs(dups) do
        local todo = n - (done[stat] or 0)
        if todo > 0 then
            self:SetStat(stat, math.max(0, (s[stat] or 0) - todo))
            done[stat] = n
        end
    end
    priv.deathDupsFixed[me.guid] = done
end

GJ:On("GJ_LOGIN", function()
    local me = GJ:RefreshMyInfo()
    if #me.events == 0 then
        GJ:AddEvent("start", nil)
    end
    GJ:FixDuplicateDeathStats()
    lastMoney = GetMoney()
    C_Timer.After(5, function()
        recordLevel(UnitLevel("player"))
        checkMoney()
        checkProfessions()
        checkMount()
        GJ:CheckGearMilestones()
        local hour = tonumber(date("%H"))
        if hour and hour >= 3 and hour < 5 then GJ:Silly("nightOwl") end
    end)
    C_Timer.After(10, requestPlayed)
    -- Periodic housekeeping: fold jumps in, refresh played estimate.
    C_Timer.NewTicker(60, function()
        if pendingJumps > 0 then
            local n = pendingJumps
            pendingJumps = 0
            GJ:Bump("jumps", n)
        end
        local played = GJ:CurrentPlayed()
        if played then
            local s = stats()
            -- Only bump the shared stat every 10 minutes to avoid churn.
            if played - (s.played or 0) >= 600 then GJ:SetStat("played", played) end
        end
        if not me.statsStamp or me.statsStamp == 0 then touchStats() end
    end)
end)
