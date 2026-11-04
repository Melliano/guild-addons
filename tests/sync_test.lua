-- Simulates three guildies to check tracking + guild sync end to end.
-- Run with any Lua 5.1 interpreter from the repo root:  lua5.1 tests/sync_test.lua
package.path = "tests/?.lua;" .. package.path
local Mock = require("wowmock")

local FILES = {
    "GoonerJourneys/Core.lua", "GoonerJourneys/Serialize.lua", "GoonerJourneys/Data.lua",
    "GoonerJourneys/Comm.lua", "GoonerJourneys/Tracker.lua", "GoonerJourneys/Trail.lua",
    "GoonerJourneys/Gear.lua", "GoonerJourneys/MapCanvas.lua", "GoonerJourneys/WorldMapOverlay.lua",
    "GoonerJourneys/UI.lua", "GoonerJourneys/Minimap.lua",
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
alice:fire("PLAYER_LEVEL_UP", 5)
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
    for _, tab in ipairs({ "timeline", "stats", "gear", "map", "leaders" }) do B:ShowTab(tab) end
end)
check(ok, "UI tabs render: " .. tostring(err))

print(("\n%d passed, %d failed, %d addon messages sent"):format(passed, failed, Mock.sent))
if failed > 0 then os.exit(1) end
