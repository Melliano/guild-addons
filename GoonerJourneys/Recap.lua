-- Weekly recap: on your first login of a new week, a card sums up what the
-- guild got up to last week. /gooner recap shows this week so far.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local WEEK = 7 * 86400
local MONDAY_OFFSET = 4 * 86400 -- epoch was a Thursday; shift so weeks start Monday 00:00 UTC
local DELTA_STATS = { "jumps", "kills", "distance", "guildMsgs", "deaths", "quests", "critters" }

local function weekKey(t) return math.floor((t - MONDAY_OFFSET) / WEEK) end
local function weekStart(key) return key * WEEK + MONDAY_OFFSET end

local function snapshot()
    local base = {}
    for guid, m in pairs(GJ.db.members) do
        local s = m.stats or {}
        local row = {}
        for _, k in ipairs(DELTA_STATS) do row[k] = s[k] or 0 end
        base[guid] = row
    end
    return base
end

-- Crunch the numbers for [fromT, toT).
function GJ:ComputeRecap(fromT, toT, baseline)
    local guild = self:GuildName()
    local r = { from = fromT, to = toT, levels = 0, deaths = 0, firsts = 0, milestones = 0, members = 0, people = {} }
    for guid, m in pairs(self.db.members) do
        if m.name and (m.guild == guild or self:IsMe(guid)) then
            local p = { m = m, score = 0, levels = 0, deaths = 0, lastDeath = nil }
            for _, ev in ipairs(m.events) do
                local t = ev.t or 0
                if t >= fromT and t < toT then
                    p.score = p.score + self:EventPoints(ev)
                    if ev.k == "death" then
                        p.deaths = p.deaths + 1
                        if not p.lastDeath or t > p.lastDeath.t then p.lastDeath = ev end
                    elseif ev.k == "boss" or ev.k == "dungeon" or ev.k == "raid" then
                        r.firsts = r.firsts + 1
                    elseif ev.k == "silly" then
                        r.milestones = r.milestones + 1
                    end
                end
            end
            -- Exact levels gained from the per-level history when we have it.
            local lvlt = m.stats and m.stats.lvlt
            if type(lvlt) == "table" then
                for _, t in pairs(lvlt) do
                    if type(t) == "number" and t >= fromT and t < toT then p.levels = p.levels + 1 end
                end
            end
            local base = baseline and baseline[guid]
            if base then
                local s = m.stats or {}
                for _, k in ipairs(DELTA_STATS) do
                    p[k .. "Delta"] = math.max(0, (s[k] or 0) - (base[k] or 0))
                end
            end
            if p.score > 0 or p.levels > 0 or (p.jumpsDelta or 0) > 0 or (p.distanceDelta or 0) > 0 then
                r.members = r.members + 1
            end
            r.levels = r.levels + p.levels
            r.deaths = r.deaths + p.deaths
            r.people[#r.people + 1] = p
        end
    end

    local function best(field)
        local top
        for _, p in ipairs(r.people) do
            if (p[field] or 0) > 0 and (not top or p[field] > top[field]) then top = p end
        end
        return top
    end
    r.mvp = best("score")
    r.mostDeaths = best("deaths")
    r.jumper = best("jumpsDelta")
    r.traveller = best("distanceDelta")
    r.yapper = best("guildMsgsDelta")
    r.leveller = best("levels")
    -- Funniest death: one to a critter if there is one, else the latest.
    for _, p in ipairs(r.people) do
        local d = p.lastDeath
        if d then
            local critter = d.critter or (d.src and self.CRITTERS[d.src])
            if not r.death or (critter and not r.deathCritter) or (critter == r.deathCritter and d.t > r.death.t) then
                r.death, r.deathWho, r.deathCritter = d, p.m, critter and true or false
            end
        end
    end
    return r
end

---------------------------------------------------------------------------
-- The recap card
---------------------------------------------------------------------------
local card

local function buildCard()
    card = CreateFrame("Frame", "GoonerJourneysRecap", UIParent)
    card:SetSize(460, 470)
    card:SetPoint("CENTER", 0, 40)
    card:SetFrameStrata("DIALOG")
    card:SetMovable(true)
    card:EnableMouse(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", card.StartMoving)
    card:SetScript("OnDragStop", card.StopMovingOrSizing)
    card:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "GoonerJourneysRecap")
    S.Panel(card, C.bg, { 0, 0, 0, 1 })

    local top = S.Fill(card, C.accent, "ARTWORK")
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(3)

    card.kicker = S.Text(card, 11, C.accent, S.FONT)
    card.kicker:SetPoint("TOPLEFT", 22, -22)
    card.title = S.Text(card, 22, C.text, S.FONT)
    card.title:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -6)
    card.range = S.Text(card, 12, C.muted)
    card.range:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)

    card.tiles = {}
    local labels = { "LEVELS GAINED", "DEATHS", "FIRSTS", "MILESTONES" }
    local w = (460 - 44 - 3 * 8) / 4
    for i, label in ipairs(labels) do
        local t = CreateFrame("Frame", nil, card)
        t:SetSize(w, 60)
        t:SetPoint("TOPLEFT", 22 + (i - 1) * (w + 8), -102)
        S.Panel(t, C.card, C.border)
        t.value = S.Text(t, 22, C.text, S.FONT)
        t.value:SetPoint("TOPLEFT", 10, -9)
        t.label = S.Text(t, 9, C.muted, S.FONT)
        t.label:SetPoint("BOTTOMLEFT", 10, 8)
        t.label:SetText(label)
        card.tiles[i] = t
    end

    card.lines = {}
    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, card)
        row:SetSize(460 - 44, 34)
        row:SetPoint("TOPLEFT", 22, -178 - (i - 1) * 40)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT")
        S.RoundMask(row, row.icon)
        row.label = S.Text(row, 10, C.muted, S.FONT)
        row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
        row.text = S.Text(row, 13, C.text)
        row.text:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
        row.text:SetWidth(460 - 44 - 40)
        card.lines[i] = row
    end

    local close = S.Button(card, "Nice", 110, 28, "primary")
    close:SetPoint("BOTTOMRIGHT", -22, 18)
    close:SetScript("OnClick", function() card:Hide() end)
    local open = S.Button(card, "Open journeys", 130, 28)
    open:SetPoint("RIGHT", close, "LEFT", -8, 0)
    open:SetScript("OnClick", function()
        card:Hide()
        if not (GJ.ui.frame and GJ.ui.frame:IsShown()) then GJ:ToggleUI() end
        GJ:ShowTab("leaders")
    end)
end

local function nameOf(p)
    return p and GJ:ColoredName(p.m) or "?"
end

function GJ:ShowRecap(r, isPreviousWeek)
    if not card then buildCard() end
    card.kicker:SetText(isPreviousWeek and "LAST WEEK IN GOONING" or "THIS WEEK SO FAR")
    card.title:SetText(self:GuildName() or "The Gooner Journeys")
    card.range:SetText(("%s  to  %s"):format(date("%a %d %b", r.from), date("%a %d %b", r.to - 1)))
    local values = { r.levels, r.deaths, r.firsts, r.milestones }
    for i, t in ipairs(card.tiles) do t.value:SetText(values[i]) end

    local lines = {}
    local function add(icon, label, text)
        lines[#lines + 1] = { "Interface\\Icons\\" .. icon, label, text }
    end
    if r.mvp then add("INV_Misc_Toy_07", "MVP", ("%s earned %d Gooner Score"):format(nameOf(r.mvp), r.mvp.score)) end
    if r.leveller then add("Spell_Holy_SurgeOfLight", "GRINDER", ("%s gained %d level%s"):format(nameOf(r.leveller), r.leveller.levels, r.leveller.levels == 1 and "" or "s")) end
    if r.mostDeaths then add("INV_Misc_Bone_HumanSkull_01", "MOST DEATHS", ("%s died %d time%s"):format(nameOf(r.mostDeaths), r.mostDeaths.deaths, r.mostDeaths.deaths == 1 and "" or "s")) end
    if r.death then add("Spell_Shadow_DeathScream", "DEATH OF THE WEEK", ("%s was killed by %s"):format(self:ColoredName(r.deathWho), r.death.d or "unknown causes")) end
    if r.jumper then add("Ability_Rogue_Sprint", "BUNNY HOPPER", ("%s jumped %s times"):format(nameOf(r.jumper), BreakUpLargeNumbers and BreakUpLargeNumbers(r.jumper.jumpsDelta) or r.jumper.jumpsDelta)) end
    if r.traveller then add("Ability_Mount_RidingHorse", "TOURIST", ("%s travelled %.1f miles"):format(nameOf(r.traveller), r.traveller.distanceDelta / 1760)) end
    if r.yapper and #lines < 6 then add("INV_Misc_Note_01", "YAPPER", ("%s sent %d guild messages"):format(nameOf(r.yapper), r.yapper.guildMsgsDelta)) end
    if #lines == 0 then add("INV_Misc_QuestionMark", "QUIET WEEK", "Nobody did anything. Suspicious.") end

    for i, row in ipairs(card.lines) do
        local l = lines[i]
        if l then
            row.icon:SetTexture(l[1])
            row.label:SetText(l[2])
            row.text:SetText(l[3])
            row:Show()
        else
            row:Hide()
        end
    end
    card:Show()
end

function GJ:ShowCurrentRecap()
    local rec = self.db.private.recap or {}
    local now = self:Now()
    local key = weekKey(now)
    local baseline = rec.week == key and rec.baseline or nil
    self:ShowRecap(self:ComputeRecap(weekStart(key), now + 1, baseline), false)
end

-- On login: if a new week started since we last looked, show last week.
function GJ:CheckWeeklyRecap()
    local priv = self.db.private
    priv.recap = priv.recap or {}
    local rec = priv.recap
    local key = weekKey(self:Now())
    if rec.week and rec.week < key then
        if rec.shown ~= key then
            local from = weekStart(rec.week)
            local to = weekStart(rec.week + 1)
            local r = self:ComputeRecap(from, to, rec.baseline)
            rec.shown = key
            if self.db.settings.weeklyRecap then self:ShowRecap(r, true) end
        end
        rec.week, rec.baseline = key, snapshot()
    elseif not rec.week then
        rec.week, rec.baseline, rec.shown = key, snapshot(), key
    end
end

GJ:On("GJ_LOGIN", function()
    -- Give the guild a moment to sync before crunching numbers.
    C_Timer.After(25, function() GJ:CheckWeeklyRecap() end)
end)

GJ.RecapWeekKey, GJ.RecapWeekStart = weekKey, weekStart
