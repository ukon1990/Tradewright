local Tradewright = select(2, ...)

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Destroying tab: one table and side pane, switched between views (Tradewright_SalvageViews.lua):
-- the items the characters own that can be destroyed, and gear in the last scan listed below its
-- disenchant value. Stat tiles at the top say how far the values can be trusted (Tradewright_SalvageTiles.lua).
-- The code says "salvage" for destroying, as "destroy" means deleting an item.

local SalvageTab = {}
Tradewright.SalvageTab = SalvageTab

local GAP = 12
local PAD = 10
local DETAIL_WIDTH = 300
-- Two lines per row: the item, and the kind of gear it is.
local ROW_HEIGHT = 36
local VIEW_ROW_HEIGHT = 26
local LINE_HEIGHT = 16

local MARGINS = { 0.05, 0.10, 0.15, 0.20, 0.25, 0.30 }
local YIELD_HEADING = { disenchant = L["One disenchant gives"], prospect = L["One prospect gives"], mill = L["One mill gives"] }

local function currentView(pe)
	local wanted = pe:GetSetting("salvage.view", pe.SalvageViews[1].id)
	for _, view in ipairs(pe.SalvageViews) do
		if view.id == wanted then
			return view
		end
	end
	return pe.SalvageViews[1]
end

-- The owned view can show prospecting and milling on retail; the auction search is for gear only.
local function currentAction(pe, view)
	if view.id ~= "owned" then
		return "disenchant"
	end
	local chosen = pe:GetSetting("salvage.action", "disenchant")
	for _, action in ipairs(pe:GetSalvageActions()) do
		if action == chosen then
			return action
		end
	end
	return "disenchant"
end

-- Search and its hint sit at the bottom of the side pane, in views of auctions only.
local function buildSearch(pe, panel, card)
	card.search = pe:CreateButton(card.body, L["Search the auction house"], function()
		if panel.selected then
			pe:OpenItemInAuctionHouse(panel.selected.itemID)
		end
	end)
	card.search:SetPoint("BOTTOMLEFT")
	card.search:SetPoint("BOTTOMRIGHT")
	card.searchHint = pe:CreateText(card.body, "GameFontHighlightSmall", "textMuted")
	card.searchHint:SetPoint("BOTTOMLEFT", card.search, "TOPLEFT", 0, 6)
	card.searchHint:SetPoint("BOTTOMRIGHT", card.search, "TOPRIGHT", 0, 6)
end

local function buildDetail(pe, panel)
	local card = pe:CreateInset(panel)
	card:SetWidth(DETAIL_WIDTH)
	card.empty = pe:CreateEmptyState(card)
	card.empty:SetAllPoints()
	card.body = CreateFrame("Frame", nil, card)
	card.body:SetPoint("TOPLEFT", PAD, -PAD)
	card.body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	card.header = pe:CreateDetailHeader(card.body, nil, function() pe:ShowItemDetailsWindow(card.header.itemID) end)
	card.header:SetPoint("TOPLEFT")
	card.header:SetPoint("TOPRIGHT")
	card.facts = pe:CreateKeyValueList(card.body)
	card.facts:SetPoint("TOPLEFT", card.header, "BOTTOMLEFT", 0, -10)
	card.facts:SetPoint("TOPRIGHT", card.header, "BOTTOMRIGHT", 0, -10)
	card.yieldHeading = pe:CreateHeading(card.body, L["One disenchant gives"])
	card.yieldHeading:SetPoint("TOPLEFT", card.facts, "BOTTOMLEFT", 0, -10)
	card.yieldHeading:SetPoint("TOPRIGHT", card.facts, "BOTTOMRIGHT", 0, -10)
	card.yields = pe:CreateKeyValueList(card.body)
	card.yields:SetPoint("TOPLEFT", card.yieldHeading, "BOTTOMLEFT", 0, -6)
	card.yields:SetPoint("TOPRIGHT", card.yieldHeading, "BOTTOMRIGHT", 0, -6)
	card.note = pe:CreateParagraph(card.body)
	card.note:SetPoint("TOPLEFT", card.yields, "BOTTOMLEFT", 0, -8)
	card.note:SetPoint("TOPRIGHT", card.yields, "BOTTOMRIGHT", 0, -8)
	buildSearch(pe, panel, card)
	return card
end

-- A key-value list as tall as its rows, so what follows sits right under it.
local function fillList(list, rows)
	list:SetRows(rows or {})
	list:SetHeight(math.max(1, #(rows or {}) * LINE_HEIGHT))
end

-- What one destroy gives, under its own heading; hidden when no yield is known.
local function showYields(pe, panel, row)
	local card = panel.detail
	local rows, yield = pe.SalvageYield.rows(pe, row, panel.action)
	card.yieldHeading:SetShown(rows ~= nil)
	card.yieldHeading:SetText(YIELD_HEADING[panel.action])
	fillList(card.yields, rows)
	card.note:SetText(yield and pe.SalvageYield.source(pe, yield) or "")
end

local function showDetail(pe, panel, row)
	local card, view = panel.detail, panel.shownView
	panel.selected = row
	card.empty:SetShown(row == nil)
	card.body:SetShown(row ~= nil)
	if not row then
		card.empty:SetMessage(L["Select an item"], view.selectHint)
		return
	end
	card.header:SetItem(row.itemID, pe:GetItemDisplayName(row.itemID), view.subtitle(pe, row))
	fillList(card.facts, view.detailRows(pe, row, panel.action))
	showYields(pe, panel, row)
	local ahOpen = pe:IsAuctionHouseFrameOpen()
	card.search:SetShown(view.canSearch == true)
	card.search:SetEnabled(ahOpen)
	card.searchHint:SetShown(view.canSearch == true)
	card.searchHint:SetText(ahOpen and "" or L["Open the auction house to search for this item."])
end

local function buildTable(pe, panel)
	return pe:CreateReusableTable(panel, {
		footer = true, rowHeight = ROW_HEIGHT, autoFitToScroll = true, sortKey = "gain", sortAsc = false,
		isRowSelected = function(row)
			return panel.selected ~= nil and row == panel.selected
		end,
		onRowEnter = function(rowFrame, row)
			if not row then
				return
			end
			local hint = panel.shownView.canSearch and L["Click for the sums · Right-click to search the auction house · Shift-click to link"]
				or L["Click for the sums · Shift-click to link"]
			pe:ShowItemRowTooltip(rowFrame, row and row.itemID, panel.shownView.tooltipPairs(pe, row, panel.action), hint)
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, row, button, tableWidget)
			if not row or pe:HandleItemRowModifiedClick(row.itemID) then
				return
			end
			tableWidget:SetSelectedRow(row)
			showDetail(pe, panel, row)
			if button == "RightButton" and panel.shownView.canSearch and pe:IsAuctionHouseFrameOpen() then
				pe:OpenItemInAuctionHouse(row.itemID)
			end
		end,
	})
end

-- The action choice of the owned view (retail only: Forever has nothing but disenchanting) and the
-- margin of the auction view, both at the right end of the view row.
local function buildChoices(pe, panel)
	panel.actionChoice = pe:CreateSettingDropdown(panel.viewRow, {
		setting = "salvage.action", default = "disenchant", width = 140,
		getChoices = function()
			local choices = {}
			for _, action in ipairs(pe:GetSalvageActions()) do
				choices[#choices + 1] = { value = action, label = pe.SalvageActionLabel[action] }
			end
			return choices
		end,
		onChanged = function() SalvageTab:Refresh() end,
	})
	panel.actionChoice:SetPoint("RIGHT")
	local margins = {}
	for _, margin in ipairs(MARGINS) do
		margins[#margins + 1] = { value = margin, label = string.format(L["Margin %s"], pe:FormatPercent(margin)) }
	end
	panel.marginChoice = pe:CreateSettingDropdown(panel.viewRow, {
		setting = "salvage.buyMargin", default = 0.15, width = 120, choices = margins,
		tooltip = L["How far below the disenchant value a buy must be, for prices that move and yields that vary."],
		onChanged = function() SalvageTab:Refresh() end,
	})
	panel.marginChoice:SetPoint("RIGHT")
end

-- One button per view, left to right.
local function buildViewRow(pe, panel)
	panel.viewRow = CreateFrame("Frame", nil, panel)
	panel.viewRow:SetPoint("TOPLEFT")
	panel.viewRow:SetPoint("TOPRIGHT")
	panel.viewRow:SetHeight(VIEW_ROW_HEIGHT)
	panel.viewButtons = {}
	local previous
	for _, view in ipairs(pe.SalvageViews) do
		local button = pe:CreateButton(panel.viewRow, view.label, function()
			pe:SetSetting("salvage.view", view.id)
			SalvageTab:Refresh()
		end)
		button.view = view
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", -1, 0)
		else
			button:SetPoint("LEFT")
		end
		previous = button
		panel.viewButtons[#panel.viewButtons + 1] = button
	end
	buildChoices(pe, panel)
end

local function buildPanel(pe, container)
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	buildViewRow(pe, panel)
	panel.tiles = pe.SalvageTiles.Create(pe, panel)
	panel.tiles:SetPoint("TOPLEFT", panel.viewRow, "BOTTOMLEFT", 0, -GAP)
	panel.tiles:SetPoint("TOPRIGHT", panel.viewRow, "BOTTOMRIGHT", 0, -GAP)
	panel.detail = buildDetail(pe, panel)
	panel.detail:SetPoint("TOPRIGHT", panel.tiles, "BOTTOMRIGHT", 0, -GAP)
	panel.detail:SetPoint("BOTTOMRIGHT")
	panel.table = buildTable(pe, panel)
	panel.table.frame:SetPoint("TOPLEFT", panel.tiles, "BOTTOMLEFT", 0, -GAP)
	panel.table.frame:SetPoint("BOTTOMRIGHT", panel.detail, "BOTTOMLEFT", -GAP, 0)
	return panel
end

function SalvageTab:Create(container, uiState)
	uiState.salvagePanel = uiState.salvagePanel or buildPanel(Tradewright, container)
	uiState.salvagePanel:Show()
	return uiState.salvagePanel
end

function SalvageTab:ApplyTheme() -- luacheck: ignore 212
end

local function showViewRow(pe, panel, view)
	for _, button in ipairs(panel.viewButtons) do
		pe:StyleShellButton(button, button.view == view)
	end
	panel.actionChoice:SetShown(view.id == "owned" and #pe:GetSalvageActions() > 1)
	panel.actionChoice:RefreshText()
	panel.marginChoice:SetShown(view.id == "buy")
	panel.marginChoice:RefreshText()
end

-- A new view or action brings new columns. SetColumns redraws at once: drop the old rows first so
-- the new columns never draw them.
local function useColumns(pe, panel, view, action)
	if panel.shownView ~= view or panel.action ~= action then
		panel.table:SetRows({})
		panel.shownView, panel.action, panel.selected = view, action, nil
		panel.table:SetColumns(view.columns(pe, action))
	end
end

-- The steps that get the data to good enough, numbered, for the empty table.
local function missingSteps(pe, check)
	local steps = {}
	if not check.scanHours then
		steps[#steps + 1] = L["Open the auction house and press Full scan: gear and materials get a price."]
	end
	steps[#steps + 1] = string.format(L["Scan once a day. After %d days the materials have a usual price and the values turn solid."],
		pe.SalvageCheckLogic.USUAL_PRICE_DAYS)
	for index, step in ipairs(steps) do
		steps[index] = index .. ". " .. step
	end
	return table.concat(steps, "\n")
end

-- With no usable data the auction view shows only what is missing: rows built on it would mislead.
local function showRows(pe, panel, view, rows, check)
	if view.hideRowsWhenNone and check.level == "none" then
		panel.table:SetEmptyText(L["Not enough data to search yet"], missingSteps(pe, check))
		return {}
	end
	panel.table:SetEmptyText(view.emptyTitle, view.emptyHint)
	return rows
end

-- Keep the selected row when it is still listed; otherwise show the empty side pane.
local function reselect(pe, panel, rows)
	local keep
	for _, row in ipairs(rows) do
		if panel.selected and panel.shownView.sameRow(row, panel.selected) then
			keep = row
		end
	end
	showDetail(pe, panel, keep)
end

function SalvageTab:Refresh()
	local pe = Tradewright
	local panel = pe.ui and pe.ui.salvagePanel
	if not panel then
		return
	end
	local view = currentView(pe)
	local action = currentAction(pe, view)
	showViewRow(pe, panel, view)
	useColumns(pe, panel, view, action)
	local rows, check = view.getRows(pe, action, function()
		if panel:IsVisible() then
			self:Refresh()
		end
	end)
	pe.SalvageTiles.Show(pe, panel.tiles, check)
	panel.table:SetLoading(not rows and pe.MarketInsightsLoadingNote or nil)
	rows = rows and showRows(pe, panel, view, rows, check) or {}
	panel.table:SetRows(rows)
	panel.table:SetFooterText(view.footer(pe, rows))
	panel.table:Refresh()
	reselect(pe, panel, rows)
end
