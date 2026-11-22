local addonName, Tradewright = ...

-- Minimap button: click opens the dashboard, right-click the settings tab, drag moves it round the minimap.

local DEFAULT_ANGLE = 225
local TOOLTIP_LINES = { { "Click", "Open the dashboard" }, { "Right-click", "Open settings" }, { "Drag", "Move this button" } }

-- Standard minimap-button layout (same offsets as LibDBIcon): the tracking-border
-- ring sits in the top-left of its texture, so everything anchors TOPLEFT, not CENTER.
local function addButtonTextures(button)
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface/Minimap/UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(Tradewright.ADDON_ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	button.icon = icon
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
end

-- Saves the angle from the minimap centre to the cursor and moves the button there.
local function followCursor(button)
	Tradewright:InitDB()
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cursorX, cursorY = cursorX / scale, cursorY / scale
	Tradewright:SetSetting("integrations.minimapButtonAngle", math.deg(math.atan2(cursorY - centerY, cursorX - centerX)))
	Tradewright:UpdateMinimapButtonPosition(button)
end

local function showTooltip(button)
	local theme = Tradewright:GetTheme()
	local muted = theme.textMuted
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText("Tradewright", theme.gold.r, theme.gold.g, theme.gold.b)
	for _, pair in ipairs(TOOLTIP_LINES) do
		GameTooltip:AddDoubleLine(pair[1], pair[2], muted.r, muted.g, muted.b, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function bindButtonScripts(button)
	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			Tradewright:OpenSettingsTab()
		else
			Tradewright:ToggleDashboard()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", followCursor)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

local function createMinimapButton()
	local button = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight", "ADD")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	addButtonTextures(button)
	bindButtonScripts(button)
	return button
end

--- Creates the button once; afterwards shows or hides it by the "Show minimap button" setting.
function Tradewright:EnsureMinimapButton()
	if not Minimap then
		return
	end
	self:InitDB()
	local ui = self.ui
	local showButton = self:GetSetting("general.showMinimapButton", true)
	if not ui.minimapButton then
		ui.minimapButton = createMinimapButton()
	end
	ui.minimapButton:SetShown(showButton)
	if showButton then
		self:UpdateMinimapButtonPosition(ui.minimapButton)
	end
end

function Tradewright:UpdateMinimapButtonPosition(button)
	if not button or not Minimap then
		return
	end
	local degrees = tonumber(self:GetSetting("integrations.minimapButtonAngle", DEFAULT_ANGLE)) or DEFAULT_ANGLE
	local radians = math.rad(degrees)
	local radius = (math.min(Minimap:GetWidth(), Minimap:GetHeight()) * 0.5) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end
