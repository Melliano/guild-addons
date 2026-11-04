-- Minimap button (drag to move around the minimap edge).
local _, GJ = ...

local btn

local function updatePosition()
    local angle = math.rad(GJ.db.settings.minimap.angle or 215)
    local radius = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function create()
    btn = CreateFrame("Button", "GoonerJourneysMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)

    btn:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            GJ.db.settings.worldMapOverlay = not GJ.db.settings.worldMapOverlay
            GJ:Print("World map guild overlay", GJ.db.settings.worldMapOverlay and "on" or "off")
            GJ:RefreshWorldMapOverlay()
        else
            GJ:ToggleUI()
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            GJ.db.settings.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
            updatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(GJ.COLOR .. "The Gooner Journeys|r")
        local online, total = 0, 0
        for _, m in ipairs(GJ:SortedMembers()) do
            total = total + 1
            if GJ:IsOnline(m) then online = online + 1 end
        end
        GameTooltip:AddLine(("%d goons tracked, %d online"):format(total, online), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffff00Left-click|r to open the journeys", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffff00Right-click|r to toggle goons on the world map", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffff00Drag|r to move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end

function GJ:UpdateMinimapButton()
    if not btn then create() end
    updatePosition()
    btn:SetShown(not self.db.settings.minimap.hide)
end

GJ:On("GJ_LOGIN", function() GJ:UpdateMinimapButton() end)
