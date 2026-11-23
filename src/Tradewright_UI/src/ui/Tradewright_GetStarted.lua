-- The Get started window: three steps that take a new player from no data to working prices, and
-- the title bar button that reopens it while steps remain.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })

local WINDOW_WIDTH, STEP_HEIGHT, PAD, GAP = 420, 44, 12, 8
local TEXT_LEFT, STATE_WIDTH = 36, 60
local THEME_SELECT_WIDTH = 120
local SEEN_SETTING, DONE_SETTING = "general.getStartedSeen", "general.getStartedDone"

local function stepTexts(pe)
	local StartLogic = pe.StartLogic
	return {
		fullScan = {
			title = L["Go to an auction house and press Full scan"],
			detail = string.format(L["Prices every item at once. Can be run every %d minutes."],
				math.floor(pe:GetFullScanCooldownSec() / 60)),
		},
		professionScan = {
			title = L["Open each profession and press Scan"],
			detail = L["Saves your recipes, for craft profit."],
		},
		scanDays = {
			title = L["Full scan again on later days"],
			detail = string.format(L["Deals and usual prices need %d scan days."], StartLogic.SCAN_DAYS_NEEDED),
		},
	}
end

local function hasProfessionScan(pe)
	for _, character in pairs(pe.db.characters or {}) do
		if type(character.professions) == "table" and next(character.professions) then
			return true
		end
	end
	return false
end

local function startProgress(pe)
	pe:InitDB()
	local scanDays = pe:GetScanDayCount(pe.StartLogic.SCAN_DAYS_NEEDED)
	return pe.StartLogic.Progress({
		hasFullScan = pe:GetLastFullAuctionScanAt() ~= nil,
		hasProfessionScan = hasProfessionScan(pe),
		scanDays = scanDays,
	}), scanDays
end

local function createStepRow(pe, parent, number)
	local row = pe:CreateInset(parent)
	row:SetHeight(STEP_HEIGHT)
	row.number = pe:CreateText(row, "GameFontNormalLarge", "textMuted", "CENTER")
	row.number:SetPoint("LEFT", 10, 0)
	row.number:SetWidth(16)
	row.number:SetText(number)
	row.state = pe:CreateText(row, "GameFontHighlightSmall", "textMuted", "RIGHT")
	row.state:SetPoint("RIGHT", -10, 0)
	row.state:SetWidth(STATE_WIDTH)
	row.title = pe:CreateText(row, "GameFontHighlight")
	row.title:SetPoint("TOPLEFT", TEXT_LEFT, -7)
	row.title:SetPoint("TOPRIGHT", -(STATE_WIDTH + 16), -7)
	row.detail = pe:CreateText(row, "GameFontHighlightSmall", "textMuted")
	row.detail:SetPoint("BOTTOMLEFT", TEXT_LEFT, 7)
	row.detail:SetPoint("BOTTOMRIGHT", -(STATE_WIDTH + 16), 7)
	return row
end

-- The theme choice, offered here because a new player has not found Settings yet. Not a step:
-- it has no number and never counts toward the progress.
local function createThemeRow(pe, parent)
	local ThemeLogic = pe.ThemeLogic
	local row = pe:CreateInset(parent)
	row:SetHeight(STEP_HEIGHT)
	row.select = pe:CreateSettingDropdown(row, {
		setting = "appearance.theme",
		default = ThemeLogic.DEFAULT_THEME,
		width = THEME_SELECT_WIDTH,
		choices = ThemeLogic.Choices(),
		onChanged = function()
			pe:ApplyThemeChange()
		end,
	})
	row.select:SetPoint("RIGHT", -10, 0)
	local title = pe:CreateText(row, "GameFontHighlight")
	title:SetPoint("TOPLEFT", TEXT_LEFT, -7)
	title:SetPoint("RIGHT", row.select, "LEFT", -GAP, 0)
	title:SetText(L["Pick the colours of the window"])
	local detail = pe:CreateText(row, "GameFontHighlightSmall", "textMuted")
	detail:SetPoint("BOTTOMLEFT", TEXT_LEFT, 7)
	detail:SetPoint("RIGHT", row.select, "LEFT", -GAP, 0)
	detail:SetText(L["Change it later, or pick your own colours, under Settings > General."])
	return row
end

-- Right-hand note of a step: done, how far the scan days are, or that it is the one to do next.
local function stepStateText(pe, step, isNext, scanDays)
	if step.done then
		return L["Done"]
	end
	if step.id == "scanDays" then
		local needed = pe.StartLogic.SCAN_DAYS_NEEDED
		return string.format(L["%d of %d"], math.min(scanDays, needed), needed)
	end
	return isNext and L["Next"] or ""
end

local function refreshStepRows(pe, window, progress, scanDays)
	local theme, texts = pe:GetTheme(), stepTexts(pe)
	for index, step in ipairs(progress.steps) do
		local row, isNext = window.stepRows[index], index == progress.nextIndex
		local color = step.done and theme.success or isNext and theme.gold or theme.textMuted
		pe:ApplyBackdrop(row, theme.surface2, isNext and theme.tick or theme.borderSubtle)
		row.title:SetText(texts[step.id].title)
		row.detail:SetText(texts[step.id].detail)
		row.state:SetText(stepStateText(pe, step, isNext, scanDays))
		Tradewright:ColorText(row.number, color)
		Tradewright:ColorText(row.state, color)
	end
end

local function closeWindow(pe)
	pe:SetSetting(SEEN_SETTING, true)
	pe.ui.getStartedCover:Hide()
end

local function createTitleBar(pe, window)
	local headerHeight = pe:GetTheme().size.header
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("TOPRIGHT", -6, -6)
	pe:SkinCloseButton(close)
	close:SetScript("OnClick", function()
		closeWindow(pe)
	end)
	local title = pe:CreateText(window, "GameFontNormalLarge", "gold")
	title:SetPoint("LEFT", window, "TOPLEFT", PAD, -headerHeight / 2)
	title:SetPoint("RIGHT", close, "LEFT", -GAP, 0)
	title:SetText(L["Get started"])
	return headerHeight
end

-- Intro line, the three step rows, the theme row and the Got it button, stacked under the title bar.
local function createWindowBody(pe, window, top)
	local intro = pe:CreateText(window, "GameFontHighlightSmall", "textMuted")
	intro:SetPoint("TOPLEFT", PAD, -top)
	intro:SetPoint("TOPRIGHT", -PAD, -top)
	intro:SetText(L["Tradewright shows prices you scan yourself. Three steps:"])
	local y = top + 16 + GAP
	window.stepRows = {}
	for number = 1, 3 do
		local row = createStepRow(pe, window, number)
		row:SetPoint("TOPLEFT", PAD, -y)
		row:SetPoint("TOPRIGHT", -PAD, -y)
		window.stepRows[number] = row
		y = y + STEP_HEIGHT + GAP
	end
	window.themeRow = createThemeRow(pe, window)
	window.themeRow:SetPoint("TOPLEFT", PAD, -y)
	window.themeRow:SetPoint("TOPRIGHT", -PAD, -y)
	y = y + STEP_HEIGHT + GAP
	local gotIt = pe:CreateButton(window, L["Got it"], function()
		closeWindow(pe)
	end, { solid = true })
	gotIt:SetPoint("TOPRIGHT", -PAD, -y)
	local note = pe:CreateText(window, "GameFontHighlightSmall", "textMuted")
	note:SetPoint("LEFT", window, "TOPLEFT", PAD, -y - gotIt:GetHeight() / 2)
	note:SetPoint("RIGHT", gotIt, "LEFT", -GAP, 0)
	note:SetText(L["Steps tick off by themselves."])
	return y + gotIt:GetHeight() + PAD
end

-- The window sits on a dark cover over the Tradewright window, which also takes the clicks, so
-- nothing behind it is pressed by accident.
local function ensureWindow(pe)
	local ui = pe.ui
	if ui.getStartedCover then
		return ui.getStartedCover.window
	end
	local cover = CreateFrame("Frame", nil, ui.mainFrame)
	cover:SetAllPoints()
	cover:SetFrameStrata("DIALOG")
	cover:EnableMouse(true)
	local shade = cover:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.6)
	local window = CreateFrame("Frame", nil, cover, "BackdropTemplate")
	pe:StyleWindow(window)
	window:SetPoint("CENTER")
	window:SetSize(WINDOW_WIDTH, createWindowBody(pe, window, createTitleBar(pe, window) + PAD))
	cover.window = window
	cover:Hide()
	ui.getStartedCover = cover
	return window
end

function Tradewright:OpenGetStarted()
	local progress, scanDays = startProgress(self)
	local window = ensureWindow(self)
	refreshStepRows(self, window, progress, scanDays)
	-- The theme may have been changed in Settings since the window was last open.
	window.themeRow.select:RefreshText()
	self.ui.getStartedCover:Show()
end

-- Opens the window by itself until the player has closed it once. A player who already has every
-- step done still gets to see it: it is also the introduction to how the prices come about.
function Tradewright:ShowGetStartedOnce()
	if not self:GetSetting(SEEN_SETTING, false) then
		self:OpenGetStarted()
	end
end

-- `/tw intro` shows the window now. `/tw intro reset` forgets that it was closed and that the
-- steps were done, so it opens by itself again the next time the Tradewright window opens.
function Tradewright:HandleGetStartedSlash(rest)
	if string.lower(rest or "") == "reset" then
		self:SetSetting(SEEN_SETTING, false)
		self:SetSetting(DONE_SETTING, false)
		self:PrintMessage(L["Get started shows again the next time the Tradewright window opens."])
		return
	end
	if not (self.ui.mainFrame and self.ui.mainFrame:IsShown()) then
		self:ToggleDashboard()
	end
	self:OpenGetStarted()
end

local function ensureTitleBarButton(pe, frame)
	if not frame.getStartedButton then
		frame.getStartedButton = pe:CreateButton(frame.titleBar, "", function()
			pe:OpenGetStarted()
		end, { small = true, primary = true })
		frame.getStartedButton:SetPoint("RIGHT", frame.subtitle, "LEFT", -10, 0)
	end
	return frame.getStartedButton
end

local function hideTitleBarButton(frame)
	if frame.getStartedButton then
		frame.getStartedButton:Hide()
	end
end

-- Keeps the title bar button ("Get started 1/3") and an open window in step with saved data. Once
-- every step is done that is saved: the button goes away and the steps are not worked out again.
-- An open window stays until the player closes it.
function Tradewright:RefreshGetStarted()
	local ui = self.ui
	local frame = ui and ui.mainFrame
	if not (frame and frame.titleBar) then
		return
	end
	if self:GetSetting(DONE_SETTING, false) then
		return hideTitleBarButton(frame)
	end
	local progress, scanDays = startProgress(self)
	if ui.getStartedCover and ui.getStartedCover:IsShown() then
		refreshStepRows(self, ui.getStartedCover.window, progress, scanDays)
	end
	if not progress.nextIndex then
		self:SetSetting(DONE_SETTING, true)
		return hideTitleBarButton(frame)
	end
	local button = ensureTitleBarButton(self, frame)
	self:SetButtonLabel(button, string.format(L["Get started %d/%d"], progress.doneCount, #progress.steps), true)
	button:Show()
end
