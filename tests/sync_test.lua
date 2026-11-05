-- Simulates three guildies to check tracking + guild sync end to end.
-- Run with any Lua 5.1 interpreter from the repo root:  lua5.1 tests/sync_test.lua
package.path = "tests/?.lua;" .. package.path
local Mock = require("wowmock")

local FILES = {
    "GoonerJourneys/Core.lua", "GoonerJourneys/Serialize.lua", "GoonerJourneys/Data.lua",
    "GoonerJourneys/Comm.lua", "GoonerJourneys/Tracker.lua", "GoonerJourneys/Trail.lua",
    "GoonerJourneys/Gear.lua", "GoonerJourneys/Style.lua", "GoonerJourneys/Score.lua", "GoonerJourneys/MapCanvas.lua",
    "GoonerJourneys/WorldMapOverlay.lua", "GoonerJourneys/UI.lua", "GoonerJourneys/Race.lua",
    "GoonerJourneys/News.lua", "GoonerJourneys/Recap.lua", "GoonerJourneys/Version.lua", "GoonerJourneys/GoonerZone.lua",
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
    for _, tab in ipairs({ "timeline", "stats", "gear", "map", "race", "leaders" }) do B:ShowTab(tab) end
    B:ShowCurrentRecap()
end)
check(rawget(bob.env, "GetItemInfo") == nil and (bob.itemInfoCalls or 0) > 0,
    "gear tab draws items through C_Item when the old GetItemInfo global is gone")
check(A:Me().gear.ilvl == 10, "average item level read via C_Item")
check(ok, "UI tabs render: " .. tostring(err))

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

print(("\n%d passed, %d failed, %d addon messages sent"):format(passed, failed, Mock.sent))
if failed > 0 then os.exit(1) end
