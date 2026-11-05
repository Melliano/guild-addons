-- Guild quest log tab: every quest a goon has picked up, with who is on it
-- right now, who has finished it and who dropped it.
local _, GJ = ...
local S = GJ.Style
local C = S.C

local ROW_H = 50
local MAX_ROWS = 300
local NAMES_SHOWN = 3

local FILTERS = {
    { "all", "Everything" },
    { "active", "In progress" },
    { "done", "Completed" },
}

local page = { filter = "all", search = "", rows = {} }

-- "Bob, Alice, Carl +2" in class colours.
local function nameList(members)
    local parts = {}
    for i = 1, math.min(#members, NAMES_SHOWN) do
        parts[#parts + 1] = GJ:ColoredName(members[i])
    end
    local s = table.concat(parts, ", ")
    if #members > NAMES_SHOWN then s = s .. S.Wrap(C.faint, (" +%d"):format(#members - NAMES_SHOWN)) end
    return s
end

local function levelColor(level)
    if level and GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    end
    return C.muted
end

local function matches(row)
    if page.filter == "active" and #row.active == 0 then return false end
    if page.filter == "done" and #row.done == 0 then return false end
    if page.search ~= "" then
        local hay = (row.n .. " " .. (row.z or "")):lower()
        if not hay:find(page.search, 1, true) then return false end
    end
    return true
end

local function getRow(i)
    local row = page.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, page.child)
    row:SetSize(page.width - 14, ROW_H)
    S.Panel(row, C.card, C.border)
    row.stripe = S.Fill(row, C.accent, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT", 1, -1)
    row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    row.stripe:SetWidth(3)
    row.level = S.Text(row, 12, C.muted, S.FONT)
    row.level:SetPoint("TOPLEFT", 14, -10)
    row.level:SetWidth(30)
    row.title = S.Text(row, 13, C.text, S.FONT)
    row.title:SetPoint("TOPLEFT", 46, -9)
    row.title:SetWidth(page.width * 0.48)
    row.zone = S.Text(row, 11, C.faint)
    row.zone:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
    row.zone:SetWidth(page.width * 0.48)
    row.active = S.Text(row, 11, C.text)
    row.active:SetPoint("TOPRIGHT", -12, -9)
    row.active:SetJustifyH("RIGHT")
    row.active:SetWidth(page.width * 0.42)
    row.done = S.Text(row, 11, C.text)
    row.done:SetPoint("TOPRIGHT", row.active, "BOTTOMRIGHT", 0, -5)
    row.done:SetJustifyH("RIGHT")
    row.done:SetWidth(page.width * 0.42)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(r)
        local q = r.quest
        if not q then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:AddLine(q.n)
        if q.z or q.lv then
            GameTooltip:AddLine(("%s%s"):format(q.lv and ("Level " .. q.lv) or "", q.z and ((q.lv and "  -  " or "") .. q.z) or ""), 0.6, 0.6, 0.6)
        end
        local function section(label, members, r1, g1, b1)
            if #members == 0 then return end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(label, r1, g1, b1)
            for _, m in ipairs(members) do GameTooltip:AddLine("  " .. GJ:ColoredName(m)) end
        end
        section("On it now", q.active, C.green[1], C.green[2], C.green[3])
        section("Completed", q.done, C.gold[1], C.gold[2], C.gold[3])
        section("Dropped it", q.dropped, C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    page.rows[i] = row
    return row
end

function GJ:CreateQuestPage(parent, width, height)
    page.width = width
    page.filterButtons = {}
    local x = 0
    for _, def in ipairs(FILTERS) do
        local b = S.Button(parent, def[2], 0, 22)
        b:SetWidth(b.label:GetStringWidth() + 24)
        b:SetPoint("TOPLEFT", x, 0)
        x = x + b:GetWidth() + 6
        b.key = def[1]
        b:SetScript("OnClick", function()
            page.filter = def[1]
            GJ:RefreshQuests()
        end)
        page.filterButtons[#page.filterButtons + 1] = b
    end

    -- Search box (top-right).
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(170, 22)
    box:SetPoint("TOPRIGHT", 0, 0)
    S.Panel(box, C.card, C.border)
    box:SetFont(S.FONT_BODY, 12, "")
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    local placeholder = S.Text(box, 12, C.faint)
    placeholder:SetPoint("LEFT", 8, 0)
    placeholder:SetText("Search quests or zones")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "")
        page.search = text:lower()
        GJ:RefreshQuests()
    end)

    page.count = S.Text(parent, 11, C.faint)
    page.count:SetPoint("RIGHT", box, "LEFT", -10, 0)
    page.count:SetJustifyH("RIGHT")

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", 0, -32)
    holder:SetPoint("BOTTOMRIGHT")
    page.scroll, page.child = S.Scroll(holder, width - 12)
    page.empty = S.Text(holder, 13, C.muted)
    page.empty:SetPoint("TOP", 0, -40)
end

function GJ:RefreshQuests()
    if not page.child then return end
    for _, b in ipairs(page.filterButtons) do
        local active = b.key == page.filter
        b.bgTex:SetVertexColor(unpack(active and C.cardHi or C.card))
        b.borderTex:SetVertexColor(unpack(active and C.accent or C.border))
        b.label:SetTextColor(unpack(active and C.text or C.muted))
    end
    for _, r in ipairs(page.rows) do r:Hide() end

    local all = self:GuildQuests()
    local n, shown, y = 0, 0, 0
    for _, q in ipairs(all) do
        if matches(q) then
            n = n + 1
            if shown < MAX_ROWS then
                shown = shown + 1
                local row = getRow(shown)
                row.quest = q
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                local col = (#q.active > 0 and C.green) or (#q.done > 0 and C.gold) or C.faint
                row.stripe:SetVertexColor(col[1], col[2], col[3])
                local lc = levelColor(q.lv)
                row.level:SetText(q.lv and tostring(q.lv) or "")
                row.level:SetTextColor(lc[1], lc[2], lc[3])
                row.title:SetText(q.n)
                row.zone:SetText(q.z or "")
                if #q.active > 0 then
                    row.active:SetText(S.Wrap(C.green, "On it: ") .. nameList(q.active))
                elseif #q.dropped > 0 and #q.done == 0 then
                    row.active:SetText(S.Wrap(C.faint, "Dropped by ") .. nameList(q.dropped))
                else
                    row.active:SetText("")
                end
                row.done:SetText(#q.done > 0 and (S.Wrap(C.gold, "Done: ") .. nameList(q.done)) or "")
                row:Show()
                y = y + ROW_H + 6
            end
        end
    end
    page.child:SetHeight(math.max(10, y))
    if #all == 0 then
        page.empty:SetText("No quests yet. They show up here as goons pick them up.")
    elseif n == 0 then
        page.empty:SetText("No quests match.")
    else
        page.empty:SetText("")
    end
    local label = n == 1 and "1 quest" or (n .. " quests")
    if n > shown then label = ("showing %d of %d - search to narrow it down"):format(shown, n) end
    page.count:SetText(label)
    if page.scroll.UpdateThumb then page.scroll.UpdateThumb() end
end
