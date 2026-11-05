-- Flat, modern look shared by every window: colours, fonts and a few widget
-- builders (panels, buttons, tabs, round dots, scroll areas).
local _, GJ = ...

local S = {}
GJ.Style = S

S.WHITE = "Interface\\Buttons\\WHITE8x8"
S.CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
S.FONT = "Fonts\\FRIZQT__.TTF"
S.FONT_BODY = "Fonts\\ARIALN.TTF"

S.C = {
    bg       = { 0.055, 0.059, 0.071, 0.97 },
    sidebar  = { 0.075, 0.08, 0.095, 1 },
    card     = { 0.10, 0.107, 0.125, 1 },
    cardHi   = { 0.14, 0.148, 0.17, 1 },
    border   = { 0.18, 0.19, 0.22, 1 },
    text     = { 0.92, 0.93, 0.95 },
    muted    = { 0.55, 0.58, 0.64 },
    faint    = { 0.36, 0.38, 0.43 },
    accent   = { 1.0, 0.55, 0.10 },
    green    = { 0.30, 0.85, 0.45 },
    red      = { 0.95, 0.35, 0.35 },
    gold     = { 1.0, 0.82, 0.25 },
}

function S.Hex(c)
    return ("ff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

function S.Wrap(c, text)
    return "|c" .. S.Hex(c) .. text .. "|r"
end

-- Solid colour texture.
function S.Fill(frame, color, layer, sublevel)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetTexture(S.WHITE)
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- Background + 1px border.
function S.Panel(frame, bg, border)
    local b = S.Fill(frame, border or S.C.border, "BACKGROUND", -8)
    b:SetAllPoints()
    local f = S.Fill(frame, bg or S.C.card, "BACKGROUND", -7)
    f:SetPoint("TOPLEFT", 1, -1)
    f:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.bgTex, frame.borderTex = f, b
    return f, b
end

function S.Text(parent, size, color, font, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(font or S.FONT_BODY, size or 13, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.6)
    color = color or S.C.text
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Round dot (coloured circle).
function S.Circle(parent, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(S.CIRCLE)
    t:SetSize(size, size)
    if color then t:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
    return t
end

-- Make a texture show as a circle (portraits, icons).
function S.RoundMask(parent, texture)
    if not parent.CreateMaskTexture then return end
    local ok, mask = pcall(parent.CreateMaskTexture, parent)
    if not ok or not mask then return end
    mask:SetTexture(S.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

-- Flat button. style = "primary" | "ghost" (default)
function S.Button(parent, text, w, h, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 24)
    local primary = style == "primary"
    local bg = primary and { S.C.accent[1] * 0.85, S.C.accent[2] * 0.85, S.C.accent[3] * 0.85, 1 } or S.C.card
    S.Panel(b, bg, primary and S.C.accent or S.C.border)
    local hl = S.Fill(b, { 1, 1, 1, 0.07 }, "HIGHLIGHT")
    hl:SetAllPoints()
    b.label = S.Text(b, 12, primary and { 0.08, 0.06, 0.04 } or S.C.text, S.FONT)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(text or "")
    b.SetLabel = function(self, t) self.label:SetText(t) end
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    return b
end

-- Tab strip: text tabs with an accent underline on the active one.
-- maxWidth (optional): squeeze the padding so every tab fits.
function S.Tabs(parent, defs, onSelect, maxWidth)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(30)
    local line = S.Fill(strip, S.C.border, "BACKGROUND")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    strip.tabs = {}
    local buttons, textTotal = {}, 0
    for i, def in ipairs(defs) do
        local t = CreateFrame("Button", nil, strip)
        t.text = S.Text(t, 13, S.C.muted, S.FONT)
        t.text:SetPoint("CENTER", 0, 1)
        t.text:SetText(def[2])
        buttons[i] = t
        textTotal = textTotal + t.text:GetStringWidth()
    end
    local pad, minW = 26, 60
    if maxWidth and #defs > 0 and textTotal + #defs * pad > maxWidth then
        pad = math.max(10, math.floor((maxWidth - textTotal) / #defs))
        minW = 0
    end
    local x = 0
    for i, def in ipairs(defs) do
        local key = def[1]
        local t = buttons[i]
        local w = t.text:GetStringWidth() + pad
        if w < minW then w = minW end
        t:SetSize(w, 30)
        t:SetPoint("BOTTOMLEFT", x, 0)
        x = x + w
        t.bar = S.Fill(t, S.C.accent, "ARTWORK")
        t.bar:SetPoint("BOTTOMLEFT", 8, 0)
        t.bar:SetPoint("BOTTOMRIGHT", -8, 0)
        t.bar:SetHeight(2)
        t.bar:Hide()
        t:SetScript("OnEnter", function(self) if not self.active then self.text:SetTextColor(unpack(S.C.text)) end end)
        t:SetScript("OnLeave", function(self) if not self.active then self.text:SetTextColor(unpack(S.C.muted)) end end)
        t:SetScript("OnClick", function() onSelect(key) end)
        strip.tabs[key] = t
    end
    function strip:SetActive(key)
        for k, t in pairs(self.tabs) do
            t.active = (k == key)
            t.bar:SetShown(t.active)
            local c = t.active and S.C.text or S.C.muted
            t.text:SetTextColor(c[1], c[2], c[3])
        end
    end
    return strip
end

-- Scroll area with a thin custom scrollbar. Returns scrollFrame, child.
function S.Scroll(parent, width)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT")
    sf:SetPoint("BOTTOMRIGHT", -8, 0)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(width, 10)
    sf:SetScrollChild(child)

    local track = CreateFrame("Frame", nil, parent)
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(4)
    local thumb = S.Fill(track, { 1, 1, 1, 0.18 }, "ARTWORK")
    thumb:SetWidth(4)

    local function update()
        local range = sf:GetVerticalScrollRange() or 0
        local h = sf:GetHeight() or 1
        if range <= 0 then thumb:Hide() return end
        thumb:Show()
        local th = math.max(24, h * h / (h + range))
        thumb:SetHeight(th)
        local pos = (sf:GetVerticalScroll() or 0) / range
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -pos * (h - th))
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local v = math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 40))
        self:SetVerticalScroll(v)
        update()
    end)
    sf:SetScript("OnScrollRangeChanged", update)
    sf.UpdateThumb = update
    return sf, child
end

-- "Night Elf" from "NightElf", etc.
function S.Pretty(token)
    if not token then return "" end
    return (token:gsub("(%l)(%u)", "%1 %2"))
end

function S.ClassName(classFile)
    if not classFile then return "" end
    local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
    return n or (classFile:sub(1, 1) .. classFile:sub(2):lower())
end

function S.ClassIcon(classFile)
    if not classFile then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    return "Interface\\Icons\\ClassIcon_" .. classFile:sub(1, 1) .. classFile:sub(2):lower()
end

-- Looping pulse ring (used for "you are here").
function S.Pulse(texture, fromScale, toScale, duration)
    if not texture.CreateAnimationGroup then return end
    local ag = texture:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local sc = ag:CreateAnimation("Scale")
    if sc.SetScaleFrom then
        sc:SetScaleFrom(fromScale, fromScale)
        sc:SetScaleTo(toScale, toScale)
    else
        sc:SetScale(toScale / fromScale, toScale / fromScale)
    end
    sc:SetDuration(duration or 1.4)
    local al = ag:CreateAnimation("Alpha")
    if al.SetFromAlpha then al:SetFromAlpha(0.8) al:SetToAlpha(0) end
    al:SetDuration(duration or 1.4)
    ag:Play()
    return ag
end
