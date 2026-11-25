-- Folding for panels docked to a game window (auction house, profession, mailbox). A chevron in the
-- panel's header folds it; a thin rail stays at the same edge, with a few counts on it, and clicking the
-- rail unfolds the panel. Each panel saves its folded state under its own setting.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CLEAR = { r = 0, g = 0, b = 0, a = 0 }
local RAIL_WIDTH = 28
-- The same offsets the docked panels use, so the rail sits exactly where the panel's left edge was.
local DOCK_GAP_X, DOCK_TOP, DOCK_BOTTOM = 8, -20, 16
local RAIL_GAP = 8
local MARK_SIZE = 14
local COUNT_WIDTH, COUNT_HEIGHT = 20, 16
local BAR_WIDTH, BAR_HEIGHT = 6, 120

-- Every dock built so far, so the keybinding can find the one whose game window is open.
local docks = {}

-- `color` is a theme token ("gold", "success"): outline and number share it.
local function createCount(pe, rail, color)
	local count = CreateFrame("Frame", nil, rail)
	count:SetSize(COUNT_WIDTH, COUNT_HEIGHT)
	pe:AddSurface(count, CLEAR, pe:GetTheme()[color])
	count.text = count:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	count.text:SetPoint("CENTER", 0, 0)
	pe:ColorText(count.text, color)
	count:Hide()
	return count
end

local function createProgressBar(pe, rail)
	local bar = CreateFrame("StatusBar", nil, rail)
	bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
	bar:SetOrientation("VERTICAL")
	bar:SetStatusBarTexture(WHITE)
	bar:SetMinMaxValues(0, 1)
	pe:ColorStatusBar(bar, "tick")
	local theme = pe:GetTheme()
	pe:AddSurface(bar, theme.surface2, theme.borderStrong, 1, 1)
	bar:Hide()
	return bar
end

-- Top down: chevron, mark, a rule, then the badges laid out by layoutBadges.
local function createRailParts(pe, rail)
	pe:DrawGlyph(rail, "foldRight", -14)
	local mark = rail:CreateTexture(nil, "ARTWORK")
	mark:SetSize(MARK_SIZE, MARK_SIZE)
	mark:SetPoint("TOP", 0, -28)
	pe:ColorTexture(mark, "tick")
	rail.rule = rail:CreateTexture(nil, "ARTWORK")
	rail.rule:SetSize(MARK_SIZE, 1)
	rail.rule:SetPoint("TOP", mark, "BOTTOM", 0, -RAIL_GAP)
	pe:ColorTexture(rail.rule, "borderSubtle")
	rail.goldCount = createCount(pe, rail, "gold")
	rail.greenCount = createCount(pe, rail, "success")
	rail.progressBar = createProgressBar(pe, rail)
end

local function showRailTooltip(rail)
	local dock = rail.dock
	local theme = Tradewright:GetTheme()
	GameTooltip:SetOwner(rail, "ANCHOR_RIGHT")
	GameTooltip:SetText(Tradewright.DISPLAY_NAME, 1, 1, 1)
	GameTooltip:AddLine(L["Click to show the panel."], theme.gold.r, theme.gold.g, theme.gold.b)
	for _, detail in ipairs(dock.details or {}) do
		GameTooltip:AddDoubleLine(detail.label, detail.value, theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function createRail(pe, dock)
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local rail = CreateFrame("Button", nil, dock.gameWindow, template)
	rail:SetWidth(RAIL_WIDTH)
	dock.rail = rail
	pe:SetPanelDockOffset(dock, DOCK_GAP_X)
	rail:SetFrameLevel(dock.panel:GetFrameLevel())
	pe:StyleWindow(rail)
	rail:SetHighlightTexture(WHITE)
	pe:TintTexture(rail:GetHighlightTexture(), "gold", 0.09)
	createRailParts(pe, rail)
	rail.dock = dock
	rail:SetScript("OnClick", function() pe:SetPanelDockExpanded(dock, true) end)
	rail:SetScript("OnEnter", showRailTooltip)
	rail:SetScript("OnLeave", GameTooltip_Hide)
	rail:Hide()
	return rail
end

-- Builds the fold button and rail for a docked panel. `spec`: `panel`, `gameWindow` (the game frame it
-- docks to), `setting` (where the folded state is saved), optional `onExpand` (run after unfolding).
-- The caller places `dock.collapseButton` in the panel header.
function Tradewright:CreatePanelDock(spec)
	local pe = self
	local dock = { panel = spec.panel, gameWindow = spec.gameWindow, setting = spec.setting, onExpand = spec.onExpand }
	dock.collapseButton = self:CreateIconButton(spec.panel, "foldLeft", function()
		pe:SetPanelDockExpanded(dock, false)
	end, L["Hide panel"])
	dock.rail = createRail(self, dock)
	docks[#docks + 1] = dock
	return dock
end

-- Moves the rail to `offsetX` right of the game window, for a panel that docks further out than usual.
function Tradewright:SetPanelDockOffset(dock, offsetX)
	local rail = dock.rail
	rail:ClearAllPoints()
	rail:SetPoint("TOPLEFT", dock.gameWindow, "TOPRIGHT", offsetX, DOCK_TOP)
	rail:SetPoint("BOTTOMLEFT", dock.gameWindow, "BOTTOMRIGHT", offsetX, DOCK_BOTTOM)
end

function Tradewright:IsPanelDockExpanded(dock)
	return self:GetSetting(dock.setting, true) ~= false
end

-- True while the panel or its rail is on screen, so its counts are worth keeping current.
function Tradewright:IsPanelDockShown(dock)
	return dock.panel:IsShown() or dock.rail:IsShown()
end

-- Shows the panel or its rail as saved; `enabled` false hides both (the panel is switched off).
function Tradewright:ShowPanelDock(dock, enabled)
	local expanded = self:IsPanelDockExpanded(dock)
	dock.panel:SetShown(enabled ~= false and expanded)
	dock.rail:SetShown(enabled ~= false and not expanded)
end

function Tradewright:SetPanelDockExpanded(dock, expanded)
	self:SetSetting(dock.setting, expanded == true)
	GameTooltip_Hide()
	self:ShowPanelDock(dock, true)
	if expanded and dock.onExpand then
		dock.onExpand()
	end
end

local function setCount(count, value)
	value = tonumber(value) or 0
	count:SetShown(value > 0)
	count.text:SetText(value > 0 and tostring(value) or "")
end

-- Stacks the shown badges under the rule, RAIL_GAP apart.
local function layoutBadges(rail)
	local above = rail.rule
	for _, badge in ipairs({ rail.goldCount, rail.greenCount, rail.progressBar }) do
		if badge:IsShown() then
			badge:ClearAllPoints()
			badge:SetPoint("TOP", above, "BOTTOM", 0, -RAIL_GAP)
			above = badge
		end
	end
end

-- `badges`: `gold` and `green` counts (hidden at zero), `progress` 0..1 or nil for no bar, and
-- `details`, a list of { label, value } for the rail's tooltip.
function Tradewright:SetPanelDockBadges(dock, badges)
	local rail = dock.rail
	setCount(rail.goldCount, badges.gold)
	setCount(rail.greenCount, badges.green)
	rail.progressBar:SetShown(badges.progress ~= nil)
	rail.progressBar:SetValue(badges.progress or 0)
	dock.details = badges.details
	layoutBadges(rail)
end

-- Keybinding: folds or unfolds the docked panel whose game window is open.
function Tradewright:TogglePanelDock()
	for _, dock in ipairs(docks) do
		if dock.gameWindow:IsShown() and self:IsPanelDockShown(dock) then
			self:SetPanelDockExpanded(dock, not self:IsPanelDockExpanded(dock))
			return
		end
	end
end

BINDING_HEADER_TRADEWRIGHT = Tradewright.DISPLAY_NAME
BINDING_NAME_TRADEWRIGHT_TOGGLE_PANEL_DOCK = L["Fold or unfold the Tradewright panel"]
