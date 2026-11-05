-- The Gooner Journeys: core namespace, event bus, helpers and slash commands.
local ADDON, GJ = ...
_G.GoonerJourneys = GJ

GJ.name = ADDON
GJ.title = "The Gooner Journeys"
GJ.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "dev"
if GJ.version:find("@", 1, true) then GJ.version = "dev" end

GJ.COLOR = "|cffff7f00"

---------------------------------------------------------------------------
-- API compatibility: WoW Forever runs on the modern engine where many old
-- globals moved into C_Item / C_Spell. Prefer the new ones, fall back to
-- the classic globals.
---------------------------------------------------------------------------
local C_Item = C_Item or {}

function GJ.ItemInfo(item)
    if item == nil then return nil end
    if C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    if GetItemInfo then return GetItemInfo(item) end
end

function GJ.ItemIcon(item)
    if item == nil then return nil end
    local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
    if id and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if id and GetItemIcon then return GetItemIcon(id) end
    local _, _, _, _, _, _, _, _, _, tex = GJ.ItemInfo(item)
    return tex
end

function GJ.ItemQualityColor(quality)
    if C_Item.GetItemQualityColor then return C_Item.GetItemQualityColor(quality) end
    if GetItemQualityColor then return GetItemQualityColor(quality) end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function GJ.ItemLevel(item)
    if C_Item.GetDetailedItemLevelInfo then return C_Item.GetDetailedItemLevelInfo(item) end
    if GetDetailedItemLevelInfo then return GetDetailedItemLevelInfo(item) end
end

function GJ.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------
function GJ:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage(GJ.COLOR .. "Gooner Journeys|r: " .. msg)
end

function GJ:Debug(...)
    if self.db and self.db.settings.debug then
        self:Print("|cff888888[debug]|r", ...)
    end
end

---------------------------------------------------------------------------
-- Event bus. Modules register with GJ:On("EVENT", fn). Internal (non-WoW)
-- messages use the same mechanism via GJ:Fire("GJ_SOMETHING", ...).
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
GJ.eventFrame = frame
local handlers = {}

function GJ:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not event:find("^GJ_") then
            frame:RegisterEvent(event)
        end
    end
    table.insert(handlers[event], fn)
end

function GJ:Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    GJ:Fire(event, ...)
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function GJ:Now()
    return time()
end

function GJ:PlayerGUID()
    return UnitGUID("player")
end

-- Characters on Forever have region-unique names and no realms, so members
-- are always keyed by GUID; names are only for display.
function GJ:PlayerName()
    local name = UnitName("player")
    return name
end

function GJ:GuildName()
    if not IsInGuild() then return nil end
    local guild = GetGuildInfo("player")
    return guild
end

function GJ:ClassColor(classFile)
    local c = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
    if c then return c.r, c.g, c.b, c.colorStr or ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
    return 0.8, 0.8, 0.8, "ffcccccc"
end

function GJ:ColoredName(member)
    if not member then return "?" end
    local _, _, _, hex = self:ClassColor(member.class)
    return "|c" .. hex .. (member.name or "?") .. "|r"
end

function GJ:FormatDuration(seconds)
    seconds = math.floor(seconds or 0)
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return ("%dd %dh %dm"):format(d, h, m) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

function GJ:FormatMoney(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return ("%d|cffffd700g|r %d|cffc7c7cfs|r %d|cffeda55fc|r"):format(g, s, c)
end

function GJ:FormatAgo(t)
    if not t then return "never" end
    local diff = self:Now() - t
    if diff < 90 then return "just now" end
    if diff < 3600 then return ("%dm ago"):format(diff / 60) end
    if diff < 86400 then return ("%dh ago"):format(diff / 3600) end
    return ("%dd ago"):format(diff / 86400)
end

function GJ:MapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.name or ("Map " .. tostring(mapID))
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
GJ:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    GJ:InitDB()
    GJ:Fire("GJ_DB_READY")
end)

GJ:On("PLAYER_LOGIN", function()
    GJ:Fire("GJ_LOGIN")
    GJ:Print(("v%s loaded. Type |cffffff00/gooner|r to open, or click the minimap button."):format(GJ.version))
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_GOONERJOURNEYS1 = "/gooner"
SLASH_GOONERJOURNEYS2 = "/gj"
SLASH_GOONERJOURNEYS3 = "/journey"
SlashCmdList.GOONERJOURNEYS = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        GJ:ToggleUI()
    elseif cmd == "sync" then
        GJ:BroadcastDigest(true)
        GJ:Print("Asked the guild for fresh journeys.")
    elseif cmd == "minimap" then
        GJ.db.settings.minimap.hide = not GJ.db.settings.minimap.hide
        GJ:UpdateMinimapButton()
    elseif cmd == "map" then
        GJ.db.settings.worldMapOverlay = not GJ.db.settings.worldMapOverlay
        GJ:Print("World map guild overlay", GJ.db.settings.worldMapOverlay and "on" or "off")
        GJ:RefreshWorldMapOverlay()
    elseif cmd == "interval" then
        local n = tonumber(rest)
        if n and n >= 5 and n <= 300 then
            GJ.db.settings.trailInterval = n
            GJ:RestartTrailTicker()
            GJ:Print("Trail sample interval set to", n, "seconds.")
        else
            GJ:Print("Usage: /gooner interval <5-300>  (currently " .. GJ.db.settings.trailInterval .. "s)")
        end
    elseif cmd == "recap" then
        GJ:ShowCurrentRecap()
    elseif cmd == "update" then
        GJ:ShowUpdatePopup()
    elseif cmd == "where" then
        GJ:PrintWhere()
    elseif cmd == "status" then
        GJ:PrintStatus()
    elseif cmd == "versions" then
        GJ:PrintVersions()
    elseif cmd == "toasts" or cmd == "news" then
        GJ.db.settings.toasts = not GJ.db.settings.toasts
        GJ:Print("Guild news pop-ups", GJ.db.settings.toasts and "on" or "off")
    elseif cmd == "announce" then
        GJ.db.settings.announce = not GJ.db.settings.announce
        GJ:Print("Announcing your own news in guild chat", GJ.db.settings.announce and "on" or "off")
    elseif cmd == "alerts" then
        GJ.db.settings.goonerAlerts = not GJ.db.settings.goonerAlerts
        GJ:Print("Gooner zone alerts", GJ.db.settings.goonerAlerts and "on" or "off")
    elseif cmd == "weekly" then
        GJ.db.settings.weeklyRecap = not GJ.db.settings.weeklyRecap
        GJ:Print("Weekly recap on login", GJ.db.settings.weeklyRecap and "on" or "off")
    elseif cmd == "debug" then
        GJ.db.settings.debug = not GJ.db.settings.debug
        GJ:Print("Debug", GJ.db.settings.debug and "on" or "off")
    else
        GJ:Print("Commands: /gooner [show | recap | sync | status | where | versions | update | news | announce | alerts | weekly | map | minimap | interval <sec> | debug]")
    end
end
