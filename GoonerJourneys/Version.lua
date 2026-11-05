-- "Update available" nudge: every message carries the sender's addon
-- version. If a guildie is on a newer one, let the player know (once per
-- session) and show where to download it.
local _, GJ = ...
local S = GJ.Style
local C = S.C

GJ.RELEASES_URL = "https://github.com/Melliano/guild-addons/releases/latest"

local function parse(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match("^v?(%d+)%.(%d+)%.?(%d*)")
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) or 0 }
end

-- 1 if a > b, -1 if a < b, 0 if equal, nil if either isn't a release.
function GJ:CompareVersions(a, b)
    local pa, pb = parse(a), parse(b)
    if not pa or not pb then return nil end
    for i = 1, 3 do
        if pa[i] ~= pb[i] then return pa[i] > pb[i] and 1 or -1 end
    end
    return 0
end

local notified = false

GJ:On("GJ_VERSION_SEEN", function(ver)
    if GJ:CompareVersions(ver, GJ.version) ~= 1 then return end
    if not GJ.newerVersion or GJ:CompareVersions(ver, GJ.newerVersion) == 1 then
        GJ.newerVersion = ver
        GJ:Fire("GJ_UPDATE_AVAILABLE", ver)
    end
    if not notified then
        notified = true
        C_Timer.After(3, function()
            GJ:Print(("A guildie is on |cffffd100v%s|r (you have v%s). Get it from %s or type |cffffff00/gooner update|r.")
                :format(GJ.newerVersion, GJ.version, GJ.RELEASES_URL))
        end)
    end
end)

---------------------------------------------------------------------------
-- Popup with a copyable download link
---------------------------------------------------------------------------
local popup

function GJ:ShowUpdatePopup()
    if not popup then
        popup = CreateFrame("Frame", "GoonerJourneysUpdate", UIParent)
        popup:SetSize(420, 170)
        popup:SetPoint("CENTER", 0, 120)
        popup:SetFrameStrata("DIALOG")
        popup:EnableMouse(true)
        tinsert(UISpecialFrames, "GoonerJourneysUpdate")
        S.Panel(popup, C.bg, { 0, 0, 0, 1 })
        local bar = S.Fill(popup, C.accent, "ARTWORK")
        bar:SetPoint("TOPLEFT", 1, -1)
        bar:SetPoint("TOPRIGHT", -1, -1)
        bar:SetHeight(3)
        popup.title = S.Text(popup, 16, C.text, S.FONT)
        popup.title:SetPoint("TOPLEFT", 20, -20)
        popup.body = S.Text(popup, 12, C.muted)
        popup.body:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -8)
        popup.body:SetWidth(380)
        popup.body:SetWordWrap(true)

        local box = CreateFrame("EditBox", nil, popup)
        box:SetSize(380, 28)
        box:SetPoint("TOPLEFT", 20, -86)
        S.Panel(box, C.card, C.border)
        box:SetFont(S.FONT_BODY, 13, "")
        box:SetTextInsets(8, 8, 0, 0)
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function() popup:Hide() end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnTextChanged", function(self, user)
            if user then self:SetText(GJ.RELEASES_URL) self:HighlightText() end
        end)
        popup.box = box

        local close = S.Button(popup, "Close", 90, 26, "primary")
        close:SetPoint("BOTTOMRIGHT", -20, 16)
        close:SetScript("OnClick", function() popup:Hide() end)
        local hint = S.Text(popup, 11, C.faint)
        hint:SetPoint("BOTTOMLEFT", 20, 22)
        hint:SetText("Click the link, Ctrl+C to copy, paste in your browser")
    end
    if self.newerVersion then
        popup.title:SetText(("Update available: v%s"):format(self.newerVersion))
        popup.body:SetText(("You're on v%s. Download the new zip, replace your GoonerJourneys folder and /reload. Your journey data is kept."):format(self.version))
    else
        popup.title:SetText(("You're up to date (v%s)"):format(self.version))
        popup.body:SetText("Latest releases are always here:")
    end
    popup.box:SetText(self.RELEASES_URL)
    popup:Show()
    popup.box:SetFocus()
    popup.box:HighlightText()
end

-- /gooner versions: who's on what.
function GJ:PrintVersions()
    local list = {}
    for _, m in ipairs(self:SortedMembers()) do
        local v = self:IsMe(m.guid) and self.version or m.ver
        list[#list + 1] = { m, v or "unknown" }
    end
    table.sort(list, function(a, b)
        local c = self:CompareVersions(a[2], b[2])
        if c and c ~= 0 then return c > 0 end
        return (a[1].name or "") < (b[1].name or "")
    end)
    self:Print("Addon versions:")
    for _, e in ipairs(list) do
        local v = e[2]
        local behind = self.newerVersion and self:CompareVersions(v, self.newerVersion) == -1
        DEFAULT_CHAT_FRAME:AddMessage(("   %s  %s"):format(self:ColoredName(e[1]),
            behind and ("|cffff5555v" .. v .. " (old)|r") or ("v" .. v)))
    end
end
