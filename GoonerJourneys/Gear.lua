-- Snapshot of equipped gear so guildies can inspect it any time, even when
-- you are offline.
local _, GJ = ...

GJ.GEAR_SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" },
    { 4, "Shirt" }, { 19, "Tabard" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
    { 11, "Finger" }, { 12, "Finger" }, { 13, "Trinket" }, { 14, "Trinket" },
    { 16, "Main Hand" }, { 17, "Off Hand" }, { 18, "Ranged" },
}

local function snapshot()
    local me = GJ:Me()
    local gear = {}
    local total, count = 0, 0
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local itemString = link:match("item:[%-%d:]+")
            if itemString then
                -- Trim trailing empty fields to save bandwidth.
                gear[slot] = itemString:gsub(":+$", "")
            end
            if slot ~= 4 and slot ~= 19 then
                local ok, ilvl = pcall(GJ.ItemLevel, link)
                if not ok then ilvl = nil end
                if ilvl then total, count = total + ilvl, count + 1 end
            end
        end
    end
    if count > 0 then gear.ilvl = math.floor(total / count * 10 + 0.5) / 10 end

    -- Only stamp if something actually changed.
    local changed = false
    for k, v in pairs(gear) do if me.gear[k] ~= v then changed = true break end end
    if not changed then
        for k in pairs(me.gear) do if gear[k] == nil then changed = true break end end
    end
    if not changed then return end

    me.gear = gear
    me.gearStamp = GJ:Now()
    GJ:MarkOwnDirty("g")
    GJ:Fire("GJ_DATA_CHANGED", me.guid, "gear")
    GJ:CheckGearMilestones()
end

local pending = false
GJ:On("PLAYER_EQUIPMENT_CHANGED", function()
    if pending then return end
    pending = true
    C_Timer.After(3, function()
        pending = false
        snapshot()
    end)
end)

GJ:On("GJ_LOGIN", function()
    C_Timer.After(7, snapshot)
end)
