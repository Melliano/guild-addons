-- Simulates three guildies to check tracking + guild sync end to end.
-- Run with any Lua 5.1 interpreter from the repo root:  lua5.1 tests/sync_test.lua
package.path = "tests/?.lua;" .. package.path
local Mock = require("wowmock")

local FILES = {
    "GoonerJourneys/Core.lua", "GoonerJourneys/Serialize.lua", "GoonerJourneys/Data.lua",
    "GoonerJourneys/Comm.lua", "GoonerJourneys/Tracker.lua", "GoonerJourneys/Quests.lua", "GoonerJourneys/Trail.lua",
    "GoonerJourneys/Gear.lua", "GoonerJourneys/Style.lua", "GoonerJourneys/Score.lua", "GoonerJourneys/MapCanvas.lua",
    "GoonerJourneys/WorldMapOverlay.lua", "GoonerJourneys/MapPing.lua", "GoonerJourneys/UI.lua", "GoonerJourneys/Race.lua",
    "GoonerJourneys/DeathMap.lua", "GoonerJourneys/QuestLog.lua",
    "GoonerJourneys/News.lua", "GoonerJourneys/Activity.lua", "GoonerJourneys/HallOfFame.lua", "GoonerJourneys/Recap.lua", "GoonerJourneys/Version.lua", "GoonerJourneys/GoonerZone.lua",
    "GoonerJourneys/Minimap.lua",
}

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  ok   " .. msg)
    else failed = failed + 1 print("  FAIL " .. msg) end
end

-- Serializer round trip ----------------------------------------------------
do
    local a = Mock.newClient({ name = "Serial", guid = "Player-1-00000000" })
    local GJ = a:load(FILES)
    table.remove(Mock.clients) -- not part of the guild sim
    local S = GJ.Serializer
    local src = { 1, 2, "three|pipe~tilde'quote\0nul\nnl", { nested = true, n = -12.5 }, k = "v", [10] = false }
    local str = S.Serialize(src)
    check(not str:find("[%z|\n]"), "serialized string has no NUL, pipes or newlines")
    local ok, out = S.Deserialize(str)
    check(ok and out[3] == src[3] and out[4].nested == true and out[4].n == -12.5 and out.k == "v" and out[10] == false,
        "serializer round-trips nested tables and awkward characters")
    check(not S.Deserialize("{'oops"), "deserializer rejects garbage")
end

-- Guild sim -----------------------------------------------------------------
local alice = Mock.newClient({ name = "Alice", guid = "Player-1-0000000A", class = "MAGE", level = 3 })
local bob = Mock.newClient({ name = "Bob", guid = "Player-1-0000000B", level = 7 })
local carl = Mock.newClient({ name = "Carl", guid = "Player-1-0000000C", level = 1 })
local A, B, C = alice:load(FILES), bob:load(FILES), carl:load(FILES)

alice.inventory[1] = "|cff1eff00|Hitem:1234::::::::3:::::::|h[Helm]|h|r"
alice:login()
bob:login()
Mock.advance(30)

print("Login + basic tracking")
local aMe = A:Me()
check(aMe.events[1] and aMe.events[1].k == "start", "Alice's journey starts with a 'start' event")
check(#aMe.cells >= 1, "Alice's trail recorded at least one cell")
check(aMe.gear[1] == "item:1234::::::::3", "Alice's gear snapshot stored item string: " .. tostring(aMe.gear[1]))

print("Live sync while both online")
local aOnB = B:GetMember(alice.guid)
check(aOnB ~= nil and aOnB.name == "Alice", "Bob knows Alice")
check(aOnB and #aOnB.events == #aMe.events, ("Bob has all Alice's events (%d/%d)"):format(aOnB and #aOnB.events or 0, #aMe.events))
check(aOnB and aOnB.live and aOnB.live.m == 1429, "Bob sees Alice's live position")
check(aOnB and aOnB.gear[1] == aMe.gear[1], "Bob sees Alice's gear")

-- Alice levels to 5 and dies to a rabbit; walks around.
alice.level = 5
local toastsOnBob = {}
local origToast = B.ShowToast
B.ShowToast = function(self, guid, icon, title, detail, kind)
    toastsOnBob[#toastsOnBob + 1] = { guid = guid, title = title, kind = kind }
    return origToast(self, guid, icon, title, detail, kind)
end
alice:fire("PLAYER_LEVEL_UP", 5)
alice:fire("TIME_PLAYED_MSG", 3600, 60)
alice:fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 45 experience.")
alice:fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 60 experience. (+30 exp Rested bonus)")
alice:fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 250 experience.") -- quest XP, not a kill
alice.target = { name = "Rabbit", hostile = true, attackingMe = true, critter = true }
alice.inCombat = true
alice:fire("PLAYER_DEAD")
alice.target, alice.inCombat = nil, false
for i = 1, 20 do alice.x = 0.1 + i * 0.03 Mock.advance(30) end
Mock.advance(30) -- let the last trail batch flush

print("Milestones")
check((aMe.stats.kills or 0) == 2, "kills counted from XP messages only (" .. tostring(aMe.stats.kills) .. ")")
check(A:HasEvent(aMe, "level", 5), "level 5 milestone recorded")
check(A:HasEvent(aMe, "death"), "death recorded")
check(A:HasEvent(aMe, "silly", "critterDeaths:1"), "silly 'Humiliated By Wildlife' unlocked")
check(A:HasEvent(aMe, "silly", "deaths:1"), "silly first-death milestone unlocked")
local death
for _, ev in ipairs(aMe.events) do if ev.k == "death" then death = ev end end
check(death and death.d == "Rabbit" and death.x, "death has killer and coordinates")

aOnB = B:GetMember(alice.guid)
check(#aOnB.events == #aMe.events, ("Bob got Alice's new events (%d/%d)"):format(#aOnB.events, #aMe.events))
check(#aOnB.cells == #aMe.cells, ("Bob got Alice's trail (%d/%d cells)"):format(#aOnB.cells, #aMe.cells))
check((aOnB.stats.deaths or 0) == 1, "Bob got Alice's stats")

print("Offline relay: Alice leaves, Carl logs in later and learns about Alice from Bob")
alice:logout()
Mock.advance(10)
carl:login()
Mock.advance(120)
local aOnC = C:GetMember(alice.guid)
check(aOnC ~= nil, "Carl knows Alice (relayed by Bob)")
check(aOnC and #aOnC.events == #aMe.events, ("Carl has Alice's events (%d/%d)"):format(aOnC and #aOnC.events or 0, #aMe.events))
check(aOnC and #aOnC.cells == #aMe.cells, ("Carl has Alice's trail (%d/%d)"):format(aOnC and #aOnC.cells or 0, #aMe.cells))
check(aOnC and aOnC.gear[1] == aMe.gear[1], "Carl has Alice's gear")
check(aOnC and not C:IsOnline(aOnC), "Carl sees Alice as offline")

print("Solo play is shared later")
bob:logout()
carl.level = 10
carl:fire("PLAYER_LEVEL_UP", 10)
Mock.advance(60)
local carlEvents = #C:Me().events
bob.online = true -- Bob comes back (same session/env)
bob:fire("PLAYER_LOGIN") -- not a real relog, just trigger a digest via /gooner sync
B:BroadcastDigest(true)
Mock.advance(120)
local cOnB = B:GetMember(carl.guid)
check(cOnB and #cOnB.events == carlEvents, ("Bob catches up on Carl's solo events (%d/%d)"):format(cOnB and #cOnB.events or 0, carlEvents))

print("Guildless player records their journey, then shares it after joining")
local dave = Mock.newClient({ name = "Dave", guid = "Player-1-0000000D", level = 1 })
dave.guild = nil
local D = dave:load(FILES)
dave:login()
dave.level = 5
dave:fire("PLAYER_LEVEL_UP", 5)
Mock.advance(60)
check(D:HasEvent(D:Me(), "level", 5), "Dave tracks milestones with no guild")
check(B:GetMember(dave.guid) == nil, "nothing is shared before Dave has a guild")
dave.guild = "Unregistered Hypercam Users"
dave:fire("PLAYER_GUILD_UPDATE", "player")
Mock.advance(60)
local dOnB = B:GetMember(dave.guid)
check(dOnB and #dOnB.events == #D:Me().events, ("after joining, Bob gets Dave's pre-guild journey (%d/%d)"):format(dOnB and #dOnB.events or 0, #D:Me().events))
check(dOnB and dOnB.guild == "Unregistered Hypercam Users", "Dave shows up as a guild member")

print("Guild news pop-ups")
local sawDing, sawDeath = false, false
for _, t in ipairs(toastsOnBob) do
    if t.guid == alice.guid and t.kind == "level" and t.title:find("Alice reached level 5") then sawDing = true end
    if t.guid == alice.guid and t.kind == "death" then sawDeath = true end
end
check(sawDing, "Bob gets a pop-up when Alice dings")
check(sawDeath, "Bob gets a pop-up when Alice dies")
local before = #toastsOnBob
B:MergeEvents("Player-1-000000FF", 1, { { t = B:Now() - 7200, k = "level", d = 10, l = 10 } })
check(#toastsOnBob == before, "old news synced later does not pop up")

print("Gooner Score and ranks")
local score = A:Score(A:Me())
check(score > 0, "Alice has a Gooner Score (" .. score .. ")")
check(B:Score(B:GetMember(alice.guid)) == score, "Bob computes the same score for Alice")
check(A:Rank(0) == "Gooner Initiate" and A:Rank(600) == "Seasoned Gooner" and A:Rank(99999) == "Grand Gooner", "rank thresholds")

print("Race to 60")
check(A:Me().stats.lvlp and A:Me().stats.lvlp[5] == 3600, "level 5 timed at 1h played")
local aOnBob = B:GetMember(alice.guid)
check(aOnBob.stats.lvlp and aOnBob.stats.lvlp[5] == 3600, "Bob has Alice's level timings")
check(B:TimeToLevel(aOnBob, 5) == 3600, "fastest-to lookup works")

print("Weekly recap")
local r = B:ComputeRecap(0, B:Now() + 1, nil)
check(r.deaths >= 1 and r.mvp ~= nil, ("recap counts deaths (%d) and picks an MVP"):format(r.deaths))
check(r.levels >= 1, "recap counts levels gained from timings")
local ok1, err1 = pcall(function()
    B.db.private.recap = { week = B.RecapWeekKey(B:Now()) - 1, baseline = {} }
    B:CheckWeeklyRecap()
end)
check(ok1, "new week shows last week's recap: " .. tostring(err1))
check(B.db.private.recap.week == B.RecapWeekKey(B:Now()), "recap rolls over to the new week")

print("Update nudge")
check(A:CompareVersions("0.3.0", "0.2.1") == 1 and A:CompareVersions("v0.2.1", "0.2.1") == 0 and A:CompareVersions("dev", "0.2.1") == nil, "version comparison")
B.version = "0.2.1"
A.version = "0.3.0"
alice.online = true
A:SendLivePing()
Mock.advance(5)
check(B.newerVersion == "0.3.0", "Bob learns a newer version exists from Alice's ping")
Mock.advance(120) -- let Alice's backlog (sent under her old version label) drain
A:SendLivePing()
Mock.advance(5)
alice.online = false
check(B:GetMember(alice.guid).ver == "0.3.0", "Bob knows Alice's version")
local ok2, err2 = pcall(function() B:ShowUpdatePopup() B:PrintVersions() end)
check(ok2, "update popup and /gooner versions work: " .. tostring(err2))
A.version = "test"

print("Falls need real fall damage")
local falls0 = C:Me().stats.falls or 0
for i = 1, 30 do -- 30 long jumps down a slope, no damage
    carl.falling = true
    Mock.advance(1.5)
    carl.falling = false
    Mock.advance(1)
end
check((C:Me().stats.falls or 0) == falls0, "long jumps without losing health are not falls")
check(not C:HasEvent(C:Me(), "silly", "falls:25"), "no bogus Gravity Tester")
carl.falling = true
Mock.advance(2)
carl.falling = false
carl.hp = 70
Mock.advance(1)
check((C:Me().stats.falls or 0) == falls0 + 1, "a fall that hurts counts")
carl.hp = 100
carl.inCombat = true
carl.falling = true
Mock.advance(2)
carl.falling = false
carl.hp = 60
Mock.advance(1)
check((C:Me().stats.falls or 0) == falls0 + 1, "health lost mid-fight isn't blamed on falling")
carl.inCombat, carl.hp = false, 100

print("GOONER ZONE DETECTED")
local alertsOnBob = {}
local origAlert = B.ShowGoonerAlert
B.ShowGoonerAlert = function(self, member, place)
    alertsOnBob[#alertsOnBob + 1] = { name = member.name, place = place }
    return origAlert(self, member, place)
end
carl.subzone = "Lion's Pride Inn"
carl:fire("ZONE_CHANGED_INDOORS")
Mock.advance(10)
check(#alertsOnBob == 1 and alertsOnBob[1].name == "Carl" and alertsOnBob[1].place == "the Lion's Pride Inn",
    "Bob gets a GOONER ALERT when Carl walks into the Lion's Pride Inn")
check(C:Me().stats.innVisits == 1 and C:HasEvent(C:Me(), "silly", "innVisits:1"), "Carl's visit counted and 'Gooner Zone Detected' unlocked")
carl.subzone = "Goldshire"
carl:fire("ZONE_CHANGED_INDOORS")
Mock.advance(5)
carl.subzone = "Lion's Pride Inn"
carl:fire("ZONE_CHANGED_INDOORS")
Mock.advance(10)
check(#alertsOnBob == 1 and C:Me().stats.innVisits == 1, "popping out and back in within 10 minutes doesn't spam")
carl.subzone = "Goldshire"
carl:fire("ZONE_CHANGED_INDOORS")
Mock.advance(11 * 60)
carl.subzone = "Lion's Pride Inn"
carl:fire("ZONE_CHANGED_INDOORS")
Mock.advance(10)
check(#alertsOnBob == 2 and C:Me().stats.innVisits == 2, "coming back later alerts again (visit 2)")
carl.subzone = nil
Mock.advance(11 * 60)

print("GOONER ZONE detection is forgiving")
local function detects(sub, resting, mini)
    carl.subzone, carl.resting, carl.minimapZone = sub, resting, mini
    local r = C:CurrentGoonerZone()
    carl.subzone, carl.resting, carl.minimapZone = nil, nil, nil
    return r ~= nil
end
check(detects("Lion\226\128\153s Pride Inn"), "curly apostrophe still detected")
check(detects("lions pride inn"), "lower case / no apostrophe still detected")
check(detects("Goldshire", false, "Lion's Pride Inn"), "detected from the minimap zone text")
check(detects("Goldshire", true), "resting in Goldshire counts as the inn")
check(not detects("Goldshire", false), "walking through Goldshire doesn't")
check(not detects("Northshire Abbey", true), "resting somewhere else doesn't")
-- Already inside at login / after /reload: no zone event fires, it still alerts.
local before = #alertsOnBob
carl.subzone = "Lion's Pride Inn"
Mock.advance(10)
check(#alertsOnBob == before + 1, "already standing in the inn is picked up without a zone event")
local okWhere = pcall(function() C:PrintWhere() end)
check(okWhere, "/gooner where prints without errors")
carl.subzone = nil

print("Guild death map")
local deathMaps = B:GuildDeathMaps()
local elwynn
for _, entry in ipairs(deathMaps) do if entry.mapID == 1429 then elwynn = entry end end
check(elwynn and elwynn.count >= 1, "Alice's death shows on the guild death map")
local aliceDeath
for _, d in ipairs(elwynn and elwynn.deaths or {}) do
    if d.m.guid == alice.guid then aliceDeath = d end
end
check(aliceDeath and aliceDeath.ev.d == "Rabbit" and aliceDeath.ev.x, "death map pin knows the killer and the spot")

print("Guild quest log")
local function questRow(GJ, id)
    for _, q in ipairs(GJ:GuildQuests()) do if q.id == id then return q end end
end
local function has(list, guid)
    for _, m in ipairs(list or {}) do if m.guid == guid then return true end end
    return false
end
-- Bob did The Fargodeep Mine long before he installed the addon.
bob.completedQuests[62] = true
carl.questLog = {
    { id = 62, title = "The Fargodeep Mine", level = 7, header = "Elwynn Forest" },
    { id = 60, title = "Kobold Candles", level = 7, header = "Elwynn Forest" },
    { id = 61, title = "Gold Dust Exchange", level = 7, header = "Elwynn Forest" },
}
carl:fire("QUEST_ACCEPTED", 1, 62)
carl:fire("QUEST_LOG_UPDATE")
Mock.advance(60)
local cState = C:QuestState(C:Me())
check(cState[62] == "a" and cState[60] == "a" and cState[61] == "a", "Carl's picked-up quests are recorded")
local q62 = questRow(B, 62)
check(q62 and q62.n == "The Fargodeep Mine" and q62.z == "Elwynn Forest" and q62.lv == 7, "Bob sees Carl's quest with its name, zone and level")
check(q62 and has(q62.active, carl.guid), "Bob sees Carl is on The Fargodeep Mine")
check(q62 and has(q62.done, bob.guid), "Bob's old completion is filled in once a guildie picks the quest up")
local q62c = questRow(C, 62)
check(q62c and has(q62c.done, bob.guid), "Carl sees Bob has already done it")
check(questRow(B, 999) == nil, "quests nobody picked up aren't listed")

-- Carl turns in 62.
carl:fire("QUEST_TURNED_IN", 62, 100, 0)
carl.completedQuests[62] = true
table.remove(carl.questLog, 1)
carl:fire("QUEST_LOG_UPDATE")
Mock.advance(30)
q62 = questRow(B, 62)
check(q62 and has(q62.done, carl.guid) and not has(q62.active, carl.guid), "Bob sees Carl completed The Fargodeep Mine")
check(C:QuestState(C:Me())[62] == "c", "turning in doesn't re-add the quest as picked up")

-- Collapsing a zone header hides quests from addons; that isn't dropping them.
carl.collapsed["Elwynn Forest"] = true
carl:fire("QUEST_LOG_UPDATE")
Mock.advance(60)
check(C:QuestState(C:Me())[60] == "a", "a collapsed quest log header doesn't count as dropping quests")
carl.collapsed["Elwynn Forest"] = nil

-- Carl drops Kobold Candles.
for i, q in ipairs(carl.questLog) do if q.id == 60 then table.remove(carl.questLog, i) break end end
carl:fire("QUEST_LOG_UPDATE")
Mock.advance(5)
check(C:QuestState(C:Me())[60] == "a", "a quest missing for a moment isn't dropped yet")
Mock.advance(60)
local q60 = questRow(B, 60)
check(C:QuestState(C:Me())[60] == "x", "a quest gone for a while counts as dropped")
check(q60 and has(q60.dropped, carl.guid) and #q60.active == 0, "dropped quests stay on the list, marked as dropped")

-- Older versions never ask for quest logs, so we don't send them any.
local questPushes = 0
local origPushQuests = B.PushQuests
B.PushQuests = function(...) questPushes = questPushes + 1 return origPushQuests(...) end
local Ser = B.Serializer.Serialize
bob:fire("CHAT_MSG_ADDON", "GoonJ", "S" .. Ser({ k = "D", v = 1, f = "Player-1-000000O1", d = {},
    i = { n = "Oldie", gu = "Unregistered Hypercam Users" } }), "GUILD", "Oldie")
Mock.advance(15)
check(questPushes == 0, "no quest data is sent to guildies on older versions")
bob:fire("CHAT_MSG_ADDON", "GoonJ", "S" .. Ser({ k = "D", v = 1, f = "Player-1-000000N1", d = {}, q = 1,
    i = { n = "Newbie", gu = "Unregistered Hypercam Users" } }), "GUILD", "Newbie")
Mock.advance(15)
check(questPushes > 0, "quest data is sent to guildies who understand it")
B.PushQuests = origPushQuests
Mock.advance(120)

print("Guild quests: grouped by area, filters and sorting")
do
    local me = { guid = bob.guid, name = "Bob" }
    local al = { guid = alice.guid, name = "Alice" }
    local ca = { guid = carl.guid, name = "Carl" }
    local fake = {
        { id = 1, n = "Kobold Candles", lv = 7, z = "Elwynn Forest", active = { ca }, done = {}, dropped = {} },
        { id = 2, n = "A Fishy Peril", lv = 5, z = "Elwynn Forest", active = {}, done = { al, ca }, dropped = {} },
        { id = 3, n = "The Defias Brotherhood", lv = 14, z = "Westfall", active = { me, al }, done = {}, dropped = {} },
        { id = 4, n = "Red Linen Goods", lv = 10, z = "Westfall", active = {}, done = {}, dropped = { me } },
        { id = 5, n = "Mystery Note", z = nil, active = { al }, done = {}, dropped = {} },
        { id = 6, n = "Wanted: Hogger", lv = 11, z = "Elwynn Forest", active = {}, done = { me }, dropped = {} },
    }
    local orig = B.GuildQuests
    B.GuildQuests = function() return fake end
    local function zones(groups)
        local t = {}
        for _, g in ipairs(groups) do t[#t + 1] = g.zone .. "(" .. #g.quests .. ")" end
        return table.concat(t, " ")
    end
    local function names(g)
        local t = {}
        for _, q in ipairs(g.quests) do t[#t + 1] = q.n end
        return table.concat(t, ", ")
    end
    local g, total = B:QuestView({})
    check(total == 6 and zones(g) == "Elwynn Forest(3) Westfall(2) Other(1)",
        "grouped by area, lowest-level area first, no-area quests under Other: " .. zones(g))
    check(names(g[1]) == "A Fishy Peril, Kobold Candles, Wanted: Hogger", "quests sorted by level inside an area")
    check(g[1].minLv == 5 and g[1].maxLv == 11 and g[1].inProgress == 1 and g[1].completed == 2, "area header counts and level range")
    g = B:QuestView({ sort = "name" })
    check(zones(g) == "Elwynn Forest(3) Westfall(2) Other(1)" and names(g[2]) == "Red Linen Goods, The Defias Brotherhood", "sort by name")
    g = B:QuestView({ sort = "goons" })
    check(g[1].zone == "Elwynn Forest" and g[1].quests[1].n == "A Fishy Peril", "sort by most goons")
    g, total = B:QuestView({ status = "active" })
    check(total == 3 and zones(g) == "Elwynn Forest(1) Westfall(1) Other(1)", "filter: in progress")
    g, total = B:QuestView({ status = "done" })
    check(total == 2, "filter: completed")
    g, total = B:QuestView({ status = "dropped" })
    check(total == 1 and g[1].quests[1].n == "Red Linen Goods", "filter: dropped")
    g, total = B:QuestView({ who = bob.guid })
    check(total == 3, "filter: one goon (anything they're on, finished or dropped)")
    g, total = B:QuestView({ who = alice.guid, status = "active" })
    check(total == 2, "filter: one goon + in progress")
    g, total = B:QuestView({ near = 12 })
    check(total == 5, "filter: near my level (within 5, plus quests with no level; the level 5 quest is out)")
    g, total = B:QuestView({ search = "westfall" })
    check(total == 2 and #g == 1, "search still works across areas")
    B.GuildQuests = orig
end

print("World map pings")
do
    local hal = Mock.newClient({ name = "Hal", guid = "Player-1-00000011", class = "MAGE", level = 20 })
    local ivy = Mock.newClient({ name = "Ivy", guid = "Player-1-00000012", level = 20 })
    hal.guild, ivy.guild = "Ping Guild", "Ping Guild"
    local H, I = hal:load(FILES), ivy:load(FILES)
    hal:login()
    ivy:login()
    Mock.advance(30)
    check(H:SendMapPing(1429, 0.42, 0.66) == true, "Hal pings Elwynn at 42, 66")
    check(H:SendMapPing(1429, 0.5, 0.5) == false, "a second ping straight away is ignored")
    Mock.advance(3)
    local p = I:GetMapPing(hal.guid)
    check(p and p.m == 1429 and math.abs(p.x - 0.42) < 0.002 and math.abs(p.y - 0.66) < 0.002, "Ivy gets Hal's ping")
    check(p and p.name == "Hal" and p.class == "MAGE", "the ping carries Hal's name and class colour")
    check(H:GetMapPing(hal.guid) ~= nil, "Hal sees his own ping")
    check(H:SendMapPing(1429, 1.5, 0.2) == false, "off-map positions are rejected")
    Mock.advance(3)
    H:SendMapPing(1429, 0.10, 0.20)
    Mock.advance(3)
    local p2 = I:GetMapPing(hal.guid)
    check(p2 and math.abs(p2.x - 0.10) < 0.002, "a new ping replaces the old one")
    Mock.advance(31)
    check(I:GetMapPing(hal.guid) == nil, "pings disappear after 30 seconds")
    I.db.settings.mapPings = false
    H:SendMapPing(1429, 0.3, 0.3)
    Mock.advance(3)
    check(I:GetMapPing(hal.guid) == nil, "/gooner pings off: no pings shown")
    hal:logout()
    ivy:logout()
end

print("Stays clear of Blizzard-only actions")
local clean = true
for _, cl in ipairs({ alice, bob, carl, dave }) do
    if cl.events["COMBAT_LOG_EVENT_UNFILTERED"] or cl.touchedCombatLog then clean = false end
    for name, fn in pairs(cl.originalGlobals) do
        if rawget(cl.env, name) ~= fn then clean = false end
    end
end
check(clean, "never registers for or reads the combat log, never replaces Blizzard functions")
check(alice.env.ChatFrame1.registered, "chat frame gets its /played listener back")

print("UI builds and refreshes without errors")
local ok, err = pcall(function()
    B:ToggleUI()
    B.ui.frame:GetScript("OnShow")
    B:SelectMember(alice.guid)
    for _, tab in ipairs({ "timeline", "stats", "gear", "map", "latest", "race", "leaders", "deaths", "quests" }) do B:ShowTab(tab) end
    -- Guild quests with a folded area and a different sort.
    B.db.settings.questCollapsed["Elwynn Forest"] = true
    B.db.settings.questSort = "goons"
    B:ShowTab("quests")
    B.db.settings.questCollapsed = {}
    B.db.settings.questSort = "level"
    B:RefreshQuests()
    B:ShowCurrentRecap()
end)
check(rawget(bob.env, "GetItemInfo") == nil and (bob.itemInfoCalls or 0) > 0,
    "gear tab draws items through C_Item when the old GetItemInfo global is gone")
check(A:Me().gear.ilvl == 10, "average item level read via C_Item")
check(ok, "UI tabs render: " .. tostring(err))

print("Guild activity feed")
-- A goon who earns 100 points (Apprentice Gooner) and dies twice in a row
-- (the second death is a client double-fire and must not show).
local fid = "Player-1-000000FE"
local t0 = B:Now() - 600
local fevs = {}
for i = 1, 10 do fevs[i] = { t = t0 + i, k = "silly", d = "nightOwl", l = 20 } end
fevs[11] = { t = t0 + 20, k = "death", d = "Hogger", l = 20 }
fevs[12] = { t = t0 + 22, k = "death", d = "Hogger", l = 20 }
B:MergeEvents(fid, 1, fevs)
local fm = B:GetMember(fid)
fm.name, fm.guild, fm.class = "Feedy", "Unregistered Hypercam Users", "MAGE"

local feed = B:GuildActivity()
local sawFeedDeath, sawFeedDing, sawFeedRank, ordered, feedyDeaths = false, false, false, true, 0
for i, it in ipairs(feed) do
    if it.m.guid == alice.guid and it.kind == "death" then sawFeedDeath = true end
    if it.m.guid == alice.guid and it.kind == "level" and it.title:find("level 5") then sawFeedDing = true end
    if it.m.guid == fid and it.kind == "rank" and it.title:find("Apprentice Gooner") then sawFeedRank = true end
    if it.m.guid == fid and it.kind == "death" then feedyDeaths = feedyDeaths + 1 end
    if i > 1 and it.t > feed[i - 1].t then ordered = false end
end
check(sawFeedDeath and sawFeedDing, "feed shows Alice's death and her level 5 ding")
check(sawFeedRank, "feed shows rank-ups")
check(ordered, "feed is newest first")
check(feedyDeaths == 1, "doubled deaths aren't in the feed (" .. feedyDeaths .. ")")
check(#B:GuildActivity(3) == 3, "feed respects its limit")
B.db.members[fid] = nil

print("Guild and Goons sections")
local ok3, err3 = pcall(function()
    B:ShowTab("race")
    B:SelectMember(alice.guid)
    B:ShowTab("stats")
    assert(B.ui.section == "goons", "a goon tab shows the Goons section")
    B:ShowSection("guild")
    assert(B.ui.section == "guild" and B.ui.currentTab == "race", "guild reopens on the last guild tab: " .. tostring(B.ui.currentTab))
    B:ShowTab("deaths")
    B:ShowSection("goons")
    assert(B.ui.section == "goons" and B.ui.currentTab == "stats", "goons returns to the last goon tab: " .. tostring(B.ui.currentTab))
    B:ShowSection("guild")
    assert(B.ui.currentTab == "deaths", "guild returns to the last guild tab: " .. tostring(B.ui.currentTab))
    B:SelectMember(carl.guid) -- e.g. clicking a skull or a leaderboard name
    assert(B.ui.section == "goons" and B.selectedGUID == carl.guid and B.ui.currentTab == "stats",
        "picking a goon from a guild tab opens them in Goons")
    B.ui.guildTab = nil
    B:ShowSection("guild")
    assert(B.ui.currentTab == "latest", "guild opens on Latest the first time: " .. tostring(B.ui.currentTab))
    B:ShowTab("bogus")
    assert(B.ui.currentTab == "timeline", "unknown tab falls back to the timeline")
end)
check(ok3, "Guild/Goons sections switch and remember tabs: " .. tostring(err3))

print("Deaths are only counted once")
do
    local gil = Mock.newClient({ name = "Gil", guid = "Player-1-00000010", level = 9 })
    gil.guild = "Death Guild"
    local G = gil:load(FILES)
    gil:login()
    Mock.advance(10)
    gil.dead = true
    gil:fire("PLAYER_DEAD")
    gil:fire("PLAYER_DEAD")          -- the game fires it again for the same death
    Mock.advance(2)
    gil:fire("PLAYER_ALIVE")         -- released spirit: a ghost, still dead
    gil:fire("PLAYER_DEAD")
    local function realDeaths(m)
        local n = 0
        for _, ev in ipairs(m.events) do if ev.k == "death" and not ev.dup then n = n + 1 end end
        return n
    end
    check(realDeaths(G:Me()) == 1 and G:Me().stats.deaths == 1,
        ("one death recorded, not several (events %d, stat %d)"):format(realDeaths(G:Me()), G:Me().stats.deaths or 0))
    Mock.advance(30)
    gil.dead = false
    gil:fire("PLAYER_UNGHOST")
    Mock.advance(30)
    gil.dead = true
    gil:fire("PLAYER_DEAD")
    check(realDeaths(G:Me()) == 2 and G:Me().stats.deaths == 2, "a real second death still counts")

    -- Old versions recorded doubles: they're flagged and taken off the count.
    local me = G:Me()
    local t = me.events[#me.events].t
    me.events[#me.events + 1] = { t = t + 1, k = "death", d = "Rabbit", src = "Rabbit" }
    me.stats.deaths = 3
    G:MarkDuplicateDeaths(me)
    G:FixDuplicateDeathStats()
    check(me.events[#me.events].dup == true, "old duplicate death flagged")
    check(me.stats.deaths == 2, ("old duplicate taken off the death count (%d)"):format(me.stats.deaths))
    G:FixDuplicateDeathStats()
    check(me.stats.deaths == 2, "correction only applied once")
    gil:logout()
end

print("One-way guild channel: whisper fallback")
do
    local whispersBefore = Mock.whispers or 0
    local erin = Mock.newClient({ name = "Erin", guid = "Player-1-0000000E", level = 12 })
    local fay = Mock.newClient({ name = "Fay", guid = "Player-1-0000000F", level = 14 })
    erin.guild, fay.guild = "Deaf Guild", "Deaf Guild"
    erin.inventory[5] = "|cff1eff00|Hitem:5555::::::::12:::::::|h[Vest]|h|r"
    fay.deafTo = { Erin = true } -- Fay never receives Erin's GUILD messages
    local E, F = erin:load(FILES), fay:load(FILES)
    erin:login()
    fay:login()
    Mock.advance(120)
    local eOnF = F:GetMember(erin.guid)
    check(eOnF ~= nil and eOnF.name == "Erin", "Fay learns about Erin despite never hearing her guild messages")
    check(eOnF and #eOnF.events == #E:Me().events, ("Fay has Erin's events (%d/%d)"):format(eOnF and #eOnF.events or 0, #E:Me().events))
    check(eOnF and eOnF.gear[5] ~= nil, "Fay sees Erin's gear")
    check(eOnF and F:IsOnline(eOnF), "Fay sees Erin as online")
    local fOnE = E:GetMember(fay.guid)
    check(fOnE ~= nil and #fOnE.events == #F:Me().events, "Erin still gets Fay's journey over the guild channel")
    check((Mock.whispers or 0) > whispersBefore, "whispers were used")
    check(E.peers.Fay and E.peers.Fay.whisper == true, "Erin switched Fay to whisper mode")
    check(not (F.peers.Erin and F.peers.Erin.whisper), "Fay keeps using the guild channel for Erin (it works that way)")
    local ok = pcall(function() E:PrintStatus() end)
    check(ok, "/gooner status prints without errors")

    print("Guildie logs off while in whisper mode")
    fay:logout()
    Mock.advance(60)
    local whispersAfterMinute = E.commStats.whisper
    Mock.advance(300)
    check((erin.offlineWhispers or 0) <= 1, ("at most one whisper to Fay after she logged off (%d)"):format(erin.offlineWhispers or 0))
    check((erin.visibleSpam or 0) == 0, "no 'No player named' spam in Erin's chat")
    check(E.commStats.whisper == whispersAfterMinute, "Erin stops whispering Fay once she's gone")
    fay:login()
    Mock.advance(120)
    check(F:IsOnline(F:GetMember(erin.guid)), "Fay sees Erin again after logging back in")
    erin:logout()
    fay:logout()
end

print("Guildies who hear each other don't fall back to whispers")
check(not (A.peers.Bob and A.peers.Bob.whisper) and not (B.peers.Alice and B.peers.Alice.whisper),
    "no whisper mode between Alice and Bob")

print("Hall of Fame")
check(B.db.private.hofSeen and B.db.private.hofSeen["hall-of-thanes-2026-11"], "Hall of Thanes popped up on login and was marked seen")
local shown = {}
local origHof = B.ShowHallOfFame
B.ShowHallOfFame = function(self, entry) shown[#shown + 1] = entry and entry.id or "latest" return origHof(self, entry) end
B.db.private.hofSeen = nil
B:CheckHallOfFame()
check(#shown == 1 and shown[1] == "hall-of-thanes-2026-11", "a new entry pops up once")
B:CheckHallOfFame()
check(#shown == 1, "and not again")
table.insert(B.HALL_OF_FAME, 1, { id = "test-new", t = B:Now(), title = "TEST", members = { "Alice" } })
table.insert(B.HALL_OF_FAME, { id = "test-ancient", t = B:Now() - 400 * 86400, title = "OLD", members = { "Bob" } })
B:CheckHallOfFame()
check(#shown == 2 and shown[2] == "test-new", "a later entry pops up when it ships")
check(B.db.private.hofSeen["test-ancient"] and not shown[3], "very old entries are marked seen without a popup")
B.db.settings.hallOfFame = false
table.insert(B.HALL_OF_FAME, 1, { id = "test-off", t = B:Now(), title = "OFF", members = {} })
B:CheckHallOfFame()
check(#shown == 2, "/gooner fame setting off: no popup")
B.db.settings.hallOfFame = true
check(B:FindMemberByName("alice") == B:GetMember(alice.guid) and B:FindMemberByName("Nobody") == nil, "find goons by name, any case")
check(B:HallNames({ members = { "Alice", "Orianna", "Rook" } }):find("Orianna and Rook$") ~= nil, "names read 'A, B and C'")
local okHof, errHof = pcall(function()
    B:ShowTab("halloffame")
    B:RefreshHallOfFame()
    B:ShowHallOfFame()
end)
check(okHof, "Hall of Fame tab and popup draw: " .. tostring(errHof))
table.remove(B.HALL_OF_FAME, 1) table.remove(B.HALL_OF_FAME, 1) table.remove(B.HALL_OF_FAME)
local function fakeModel()
    local calls = {}
    return setmetatable({ calls = calls }, { __index = function(_, k)
        return function(_, ...) calls[#calls + 1] = { k, ... } end
    end }), calls
end
local function called(calls, name)
    for _, c in ipairs(calls) do if c[1] == name then return c end end
end
local model, calls = fakeModel()
check(B:DressModel(model, B:GetMember(alice.guid)), "a guildie's model can be dressed")
local race = called(calls, "SetCustomRace")
check(race and race[2] == 1 and race[3] == 0, "uses their race and gender (Human, male)")
local tryOn = called(calls, "TryOn")
check(tryOn and tryOn[2] == A:Me().gear[1], "and puts their synced gear on")
local own, ownCalls = fakeModel()
B:DressModel(own, B:Me())
local unit = called(ownCalls, "SetUnit")
check(unit and unit[2] == "player" and not called(ownCalls, "SetCustomRace"), "your own model is exactly you")
check(not B:DressModel(fakeModel(), { guid = "x", name = "Mystery" }), "unknown race falls back to the class icon")

print(("\n%d passed, %d failed, %d addon messages sent"):format(passed, failed, Mock.sent))
if failed > 0 then os.exit(1) end
