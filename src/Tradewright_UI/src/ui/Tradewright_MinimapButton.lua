local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Minimap button: click opens the dashboard, right-click the settings tab, drag moves it round the minimap.
-- LibDBIcon draws and drags the button, so addons that gather minimap buttons recognise it.

local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")

local ICON_NAME = Tradewright.DISPLAY_NAME
local SHOW_SETTING = "general.showMinimapButton"
local ANGLE_SETTING = "integrations.minimapButtonAngle"
local DEFAULT_ANGLE = 225
local TOOLTIP_LINES = { { "Click", L["Open Tradewright"] }, { "Right-click", L["Open settings"] }, { "Drag", L["Move this button"] } }

-- LibDBIcon reads `hide` and `minimapPos` from the table it is given and writes `minimapPos`
-- while the button is dragged. This table maps both fields onto the settings the button has
-- always used, so the saved format stays as it was.
local iconSettings = setmetatable({}, {
	__index = function(_, field)
		if field == "hide" then
			return not Tradewright:GetSetting(SHOW_SETTING, true)
		elseif field == "minimapPos" then
			return tonumber(Tradewright:GetSetting(ANGLE_SETTING, DEFAULT_ANGLE)) or DEFAULT_ANGLE
		end
	end,
	__newindex = function(_, field, value)
		if field == "minimapPos" then
			Tradewright:SetSetting(ANGLE_SETTING, value)
		end
	end,
})

local function addTooltipLines(tooltip)
	local theme = Tradewright:GetTheme()
	local muted = theme.textMuted
	tooltip:AddLine(Tradewright.DISPLAY_NAME, theme.gold.r, theme.gold.g, theme.gold.b)
	for _, pair in ipairs(TOOLTIP_LINES) do
		tooltip:AddDoubleLine(pair[1], pair[2], muted.r, muted.g, muted.b, 1, 1, 1)
	end
end

local function createLauncher()
	return LibDataBroker:NewDataObject(ICON_NAME, {
		type = "launcher",
		icon = Tradewright.ADDON_ICON,
		OnClick = function(_, mouse)
			if mouse == "RightButton" then
				Tradewright:OpenSettingsTab()
			else
				Tradewright:ToggleDashboard()
			end
		end,
		OnTooltipShow = addTooltipLines,
	})
end

--- Creates the button once; afterwards shows or hides it by the "Show minimap button" setting.
function Tradewright:EnsureMinimapButton()
	if not LibDBIcon:IsRegistered(ICON_NAME) then
		LibDBIcon:Register(ICON_NAME, createLauncher(), iconSettings)
	end
	LibDBIcon:Refresh(ICON_NAME)
end
