-- Guild news: little cards that slide in when a goon dings, dies, kills a
-- boss for the first time, gets an epic, unlocks a silly milestone or
-- ranks up. Optionally announces your own news in guild chat.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local MAX_VISIBLE = 4
local LIFETIME = 7
local FRESH = 15 * 60 -- only toast things that happened in the last 15 minutes

local KIND_COLOR = {
    death = C.red, silly = C.gold, level = C.accent, boss = { 0.70, 0.45, 1 },
    raid = { 1, 0.5, 0.2 }, dungeon = { 0.35, 0.65, 1 }, item = { 0.65, 0.4, 1 },
    rank = C.green,
}

---------------------------------------------------------------------------
-- What's newsworthy and how it reads
---------------------------------------------------------------------------
-- Returns title, detail (or nil if not newsworthy).
function GJ:NewsText(member, ev)
    local who = self:IsMe(member.guid) and "You" or (member.name or "Someone")
    local k = ev.k
    if k == "level" then
        return ("%s reached level %d"):format(who, ev.d or 0),
            ev.p and ("after " .. self:FormatDuration(ev.p) .. " played") or nil
    elseif k == "death" then
        local where = ev.m and self:MapName(ev.m) or nil
        return ("%s died"):format(who),
            ("Killed by %s, level %s%s"):format(ev.d or "unknown causes", tostring(ev.l or "?"), where and (", " .. where) or "")
    elseif k == "boss" then
        return ("%s killed %s"):format(who, ev.d or "a boss"), "First kill" .. (ev.inst and (" in " .. ev.inst) or "")
    elseif k == "dungeon" or k == "raid" then
        return ("%s entered %s"):format(who, ev.d or "?"), "First time in this " .. (k == "raid" and "raid" or "dungeon")
    elseif k == "item" and (ev.q or 0) >= 4 then
        local name = self.ItemInfo(ev.d)
        local label = (ev.q == 5) and "a legendary" or "an epic"
        return ("%s equipped %s!"):format(who, label), name
    elseif k == "silly" then
        local info = self:MilestoneInfo(ev.d)
        if info then return ("%s unlocked %s"):format(who, info[1]), info[2] end
    end
    return nil
end

---------------------------------------------------------------------------
-- Toast cards
---------------------------------------------------------------------------
local anchor
local active, queue, pool = {}, {}, {}

local function layout()
    for i, card in ipairs(active) do
        card:ClearAllPoints()
        card:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * 64)
    end
end

local function release(card)
    card:Hide()
    for i, c in ipairs(active) do
        if c == card then table.remove(active, i) break end
    end
    pool[#pool + 1] = card
    layout()
    if #queue > 0 then
        local nextToast = table.remove(queue, 1)
        GJ:ShowToast(unpack(nextToast))
    end
end

local function makeCard()
    local card = CreateFrame("Button", nil, anchor)
    card:SetSize(340, 58)
    card:SetFrameStrata("DIALOG")
    S.Panel(card, C.bg, C.border)
    card.stripe = S.Fill(card, C.accent, "ARTWORK")
    card.stripe:SetPoint("TOPLEFT", 1, -1)
    card.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    card.stripe:SetWidth(3)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(36, 36)
    card.icon:SetPoint("LEFT", 14, 0)
    S.RoundMask(card, card.icon)
    card.title = S.Text(card, 13, C.text, S.FONT)
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -2)
    card.title:SetWidth(270)
    card.detail = S.Text(card, 11, C.muted)
    card.detail:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
    card.detail:SetWidth(270)
    card.tag = S.Text(card, 9, C.faint, S.FONT)
    card.tag:SetPoint("TOPRIGHT", -10, -7)
    card.tag:SetJustifyH("RIGHT")
    card.tag:SetText("GOONER NEWS")
    card:SetScript("OnClick", function(self)
        if self.guid then
            if not (GJ.ui.frame and GJ.ui.frame:IsShown()) then GJ:ToggleUI() end
            GJ:SelectMember(self.guid)
        end
        release(self)
    end)
    card:SetScript("OnUpdate", function(self, dt)
        self.age = self.age + dt
        local a
        if self.age < 0.25 then a = self.age / 0.25
        elseif self.age > LIFETIME - 0.6 then a = math.max(0, (LIFETIME - self.age) / 0.6)
        else a = 1 end
        if self:IsMouseOver() and self.age > 0.25 then
            self.age = math.min(self.age, LIFETIME - 1)
            a = 1
        end
        self:SetAlpha(a)
        if self.age >= LIFETIME then release(self) end
    end)
    return card
end

function GJ:ShowToast(guid, icon, title, detail, kind)
    if not self.db.settings.toasts then return end
    if not anchor then
        anchor = CreateFrame("Frame", "GoonerJourneysNewsAnchor", UIParent)
        anchor:SetSize(340, 10)
        anchor:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
    if #active >= MAX_VISIBLE then
        if #queue < 20 then queue[#queue + 1] = { guid, icon, title, detail, kind } end
        return
    end
    local card = table.remove(pool) or makeCard()
    card.guid = guid
    card.age = 0
    card.icon:SetTexture(icon)
    card.title:SetText(title)
    card.detail:SetText(detail or "")
    local col = KIND_COLOR[kind] or C.accent
    card.stripe:SetVertexColor(col[1], col[2], col[3])
    card:SetAlpha(0)
    card:Show()
    active[#active + 1] = card
    layout()
end

---------------------------------------------------------------------------
-- Guild chat announcements (your own news only, off by default)
---------------------------------------------------------------------------
local pendingAnnounce = {}

local function canChat()
    if InCombatLockdown and InCombatLockdown() then return false end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then return false end
    end
    return IsInGuild()
end

local function sendGuild(text)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then pcall(send, text, "GUILD") end
end

local function flushAnnounce()
    if not canChat() then return end
    while #pendingAnnounce > 0 do
        sendGuild(table.remove(pendingAnnounce, 1))
    end
end
GJ:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(2, flushAnnounce) end)

local function announce(title, detail)
    if not GJ.db.settings.announce then return end
    local text = "[Gooner Journeys] " .. title:gsub("^You are ", "I am "):gsub("^You ", "I ") .. (detail and (" - " .. detail) or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    if #text > 250 then text = text:sub(1, 250) end
    pendingAnnounce[#pendingAnnounce + 1] = text
    flushAnnounce()
end

GJ.Announce = function(_, title, detail) announce(title, detail) end

---------------------------------------------------------------------------
-- Hook up: new events from guildies + our own
---------------------------------------------------------------------------
local function handle(member, events, own)
    if not member then return end
    local now = GJ:Now()
    local gained = 0
    for _, ev in ipairs(events) do
        gained = gained + GJ:EventPoints(ev)
        if now - (ev.t or 0) < FRESH then
            local title, detail = GJ:NewsText(member, ev)
            if title then
                GJ:ShowToast(member.guid, GJ:EventIcon(ev), title, detail, ev.k)
                if own then announce(title, detail) end
            end
        end
    end
    -- Rank up?
    if gained > 0 then
        local after = GJ:Score(member)
        local _, beforeIdx = GJ:Rank(after - gained)
        local rankName, afterIdx = GJ:Rank(after)
        local newest = events[#events]
        if afterIdx > beforeIdx and newest and now - (newest.t or 0) < FRESH then
            local who = own and "You are" or ((member.name or "Someone") .. " is")
            local title = ("%s now a %s"):format(who, rankName)
            local detail = ("Gooner Score %d"):format(after)
            GJ:ShowToast(member.guid, "Interface\\Icons\\INV_Misc_Toy_07", title, detail, "rank")
            if own then announce(title, detail) end
        end
    end
end

GJ:On("GJ_OWN_EVENT", function(ev) handle(GJ:Me(), { ev }, true) end)
GJ:On("GJ_NEW_EVENTS", function(guid, events)
    local m = GJ:GetMember(guid)
    if m and (m.guild == GJ:GuildName() or not GJ:GuildName()) then handle(m, events, false) end
end)
