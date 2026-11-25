-- Layout of the AH side panel: header tabs, control rows, the scan choice and where the active table sits.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local KNOWN_AH_SIDE_PANELS = {
	"Tradewright_AuctionDataAuctionPanel",
}

local AUCTION_PANEL_TABS = { sell = true, cart = true, auctions = true }

function Tradewright:GetAuctionPanelActiveTab(defaultTab)
	self.ui = self.ui or {}
	local tab = tostring(self.ui.auctionPanelActiveTab or defaultTab or "sell")
	return AUCTION_PANEL_TABS[tab] and tab or "sell"
end

function Tradewright:SetAuctionPanelActiveTab(tabId, manual)
	self.ui = self.ui or {}
	tabId = AUCTION_PANEL_TABS[tabId] and tabId or "sell"
	self.ui.auctionPanelActiveTab = tabId
	if tabId == "auctions" then
		self:RequestOwnedAuctions()
	end
	if manual == true then
		self.ui.auctionPanelTabManual = true
	end
	if self.RefreshAuctionHousePanel then
		self:RefreshAuctionHousePanel()
	end
end

function Tradewright:HideExtraAuctionHousePanels(keepPanel)
	for _, frameName in ipairs(KNOWN_AH_SIDE_PANELS) do
		local frame = _G[frameName]
		if frame and frame ~= keepPanel and frame.IsObjectType and frame:IsObjectType("Frame") and frame.Hide then
			frame:Hide()
		end
	end
end

local AH_PAD = 12
local AH_ROW = 26
local AH_ROW_GAP = 8

-- One scan control replaces four buttons: pick what to scan, then press Scan.
local AUCTION_SCAN_CHOICES = {
	{ value = "both", label = L["My crafts and items"] },
	{ value = "crafts", label = L["My crafts"] },
	{ value = "account", label = L["My items"] },
	{ value = "shown", label = L["Save shown prices"] },
}

function Tradewright:RunAuctionPanelScanChoice()
	local choice = self:GetSetting("auction.panelScanChoice", "both")
	if choice == "crafts" then
		self:QueueAuctionEconomyScan({ crafts = true })
	elseif choice == "account" then
		self:QueueAuctionEconomyScan({ accountInventory = true })
	elseif choice == "shown" then
		if not self:CanStartFullAuctionSideActions(true) then
			return
		end
		self:StartAuctionDump("visible")
	else
		self:QueueAuctionEconomyScan({ crafts = true, accountInventory = true })
	end
	self:RefreshAuctionHousePanel()
end

-- A row is AH_ROW tall unless it sets rowHeight (a row with labels above its controls).
local function anchorRow(panel, frame, y)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", panel, "TOPLEFT", AH_PAD, -y)
	frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -AH_PAD, -y)
	frame:SetHeight(frame.rowHeight or AH_ROW)
end

local function placeIn(row, frame, point, relative, relativePoint, x)
	frame:SetParent(row)
	frame:ClearAllPoints()
	frame:SetPoint(point, relative, relativePoint, x or 0, 0)
end

-- Sell row 3: search and item filters. Every control has a label above it, the search box too,
-- so the row is as tall as a labelled dropdown and the controls sit on its bottom edge.
local function buildSellFilterRow(pe, panel)
	local row = CreateFrame("Frame", nil, panel)
	local filters = { panel.subclassDropdown, panel.classDropdown }
	if pe.IS_RETAIL then
		table.insert(filters, 1, panel.expansionDropdown)
	else
		panel.expansionDropdown:Hide()
		panel.expansionDropdown.Show = panel.expansionDropdown.Hide
		panel.expansionDropdown.SetShown = function() end
		pe.ui.ahExpansionFilterValues = {}
	end
	row.rowHeight = filters[1]:GetHeight()
	placeIn(row, filters[1], "BOTTOMRIGHT", row, "BOTTOMRIGHT")
	for index = 2, #filters do
		placeIn(row, filters[index], "BOTTOMRIGHT", filters[index - 1], "BOTTOMLEFT", -AH_ROW_GAP)
	end
	-- The skinned edit box draws 6px wider and 2px taller on each side than the box itself.
	local search = panel.searchBox
	search:SetParent(row)
	search:ClearAllPoints()
	search:SetHeight(AH_ROW - 4)
	search:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 2)
	search:SetPoint("BOTTOMRIGHT", filters[#filters], "BOTTOMLEFT", -(AH_ROW_GAP + 6), 2)
	pe:AddSearchPlaceholder(search, L["Search name or ID"])
	local label = pe:CreateText(row, "GameFontHighlightSmall", "textMuted")
	label:SetPoint("TOPLEFT")
	label:SetText(L["Search"])
	return row
end

-- Sell row 4: two filter checkboxes and Reset filters.
local function buildSellCheckRow(pe, panel)
	local row = CreateFrame("Frame", nil, panel)
	placeIn(row, panel.craftedOnly, "LEFT", row, "LEFT", -4)
	pe:SkinCheckButton(panel.craftedOnly)
	local craftedLabel = panel.craftedOnly.Text
	placeIn(row, panel.profitableOnly, "LEFT", panel.craftedOnly, "RIGHT", (craftedLabel and craftedLabel:GetStringWidth() or 60) + 18)
	placeIn(row, panel.clearBtn, "RIGHT", row, "RIGHT")
	panel.clearBtn:SetHeight(pe:GetTheme().size.controlSmall)
	pe:SetButtonLabel(panel.clearBtn, L["Reset filters"], true)
	return row
end

-- Re-anchors the panel to the shared design: 34px header with Sell / Cart / Auctions switch, rows of 26px controls
-- 8px apart inside a 12px inset, the table filling the rest, a progress row and a 24px status footer.
function Tradewright:BuildAuctionPanelLayout(panel)
	local pe = self
	local theme = self:GetTheme()
	local headerHeight = theme.size.header

	panel:SetClampedToScreen(true)
	panel.title:SetFontObject("GameFontNormalLarge")
	panel.title:ClearAllPoints()
	panel.title:SetPoint("LEFT", panel, "TOPLEFT", 12, -(headerHeight / 2) - 1)
	panel.title:SetPoint("RIGHT", panel.tabCart, "LEFT", -12, 0)
	panel.title:SetWordWrap(false)
	panel.headerRule = panel:CreateTexture(nil, "BORDER")
	panel.headerRule:SetPoint("TOPLEFT", 1, -headerHeight)
	panel.headerRule:SetPoint("TOPRIGHT", -1, -headerHeight)
	panel.headerRule:SetHeight(1)
	Tradewright:ColorTexture(panel.headerRule, "borderSubtle", 1)
	panel.subtitle:Hide()
	panel.stats:Hide()
	panel.subtitle.Show = panel.subtitle.Hide
	panel.stats.Show = panel.stats.Hide
	panel.subtitle.SetShown = function() end
	panel.stats.SetShown = function() end

	for _, tab in ipairs({ panel.tabSell, panel.tabCart, panel.tabAuctions }) do
		self:SkinButton(tab)
		tab:SetHeight(theme.size.controlSmall)
	end
	self:SetButtonLabel(panel.tabSell, L["Sell"], true)
	self:SetButtonLabel(panel.tabAuctions, L["Auctions"], true)
	-- Reading order: Sell, Cart, Auctions.
	panel.tabAuctions:ClearAllPoints()
	panel.tabAuctions:SetPoint("RIGHT", panel, "TOPRIGHT", -12, -(headerHeight / 2))
	panel.tabCart:ClearAllPoints()
	panel.tabCart:SetPoint("RIGHT", panel.tabAuctions, "LEFT", 1, 0)
	panel.tabSell:ClearAllPoints()
	panel.tabSell:SetPoint("RIGHT", panel.tabCart, "LEFT", 1, 0)
	panel.title:SetPoint("RIGHT", panel.tabSell, "LEFT", -12, 0)

	-- Footer: status text, resize grip.
	panel.footer = CreateFrame("Frame", nil, panel)
	panel.footer:SetPoint("BOTTOMLEFT", 1, 1)
	panel.footer:SetPoint("BOTTOMRIGHT", -1, 1)
	panel.footer:SetHeight(theme.size.footer)
	local footerRule = panel.footer:CreateTexture(nil, "BORDER")
	footerRule:SetPoint("TOPLEFT")
	footerRule:SetPoint("TOPRIGHT")
	footerRule:SetHeight(1)
	Tradewright:ColorTexture(footerRule, "borderSubtle", 1)
	panel.resizeHandle:SetParent(panel.footer)
	panel.resizeHandle:ClearAllPoints()
	panel.resizeHandle:SetSize(14, 14)
	panel.resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
	panel.footerText = self:CreateText(panel.footer, "GameFontHighlightSmall", "textMuted")
	panel.footerText:SetPoint("LEFT", AH_PAD, 0)
	panel.footerText:SetPoint("RIGHT", panel.resizeHandle, "LEFT", -8, 0)

	local y = headerHeight + 1 + AH_PAD
	-- Sell row 1: scan choice, Scan, Refresh shown, Full scan.
	panel.sellRow1 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.sellRow1, y)
	placeIn(panel.sellRow1, panel.btnDumpFull, "RIGHT", panel.sellRow1, "RIGHT")
	local refresh = panel.sellControls[1]
	placeIn(panel.sellRow1, refresh, "RIGHT", panel.btnDumpFull, "LEFT", -AH_ROW_GAP)
	panel.btnScanChoice = self:CreateButton(panel.sellRow1, L["Check prices"], function()
		pe:RunAuctionPanelScanChoice()
	end, { tooltip = L["Looks up the prices picked on the left. Keep the auction house open until it ends."] })
	panel.btnScanChoice:SetPoint("RIGHT", refresh, "LEFT", -AH_ROW_GAP, 0)
	panel.scanChoice = self:CreateSingleSelectDropdown(panel.sellRow1, {
		width = 160,
		getOptions = function() return AUCTION_SCAN_CHOICES end,
		getValue = function() return pe:GetSetting("auction.panelScanChoice", "both") end,
		setValue = function(value) pe:SetSetting("auction.panelScanChoice", value) end,
		tooltip = L["Which prices to check"],
	})
	panel.scanChoice:SetPoint("LEFT", panel.sellRow1, "LEFT", 0, 0)
	panel.scanChoice:SetPoint("RIGHT", panel.btnScanChoice, "LEFT", -AH_ROW_GAP, 0)
	for _, old in ipairs({ panel.btnScanCraftPrices, panel.btnScanAccountInv, panel.btnScanCraftAndAccount, panel.btnDumpVisible }) do
		old:Hide()
		old.Show = old.Hide
		old.SetShown = function() end
	end

	-- Sell row 2: posting on the left, rules for the selected item on the right.
	y = y + AH_ROW + AH_ROW_GAP
	panel.sellRow2 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.sellRow2, y)
	placeIn(panel.sellRow2, panel.btnPostProfitable, "LEFT", panel.sellRow2, "LEFT")
	self:SetButtonPrimary(panel.btnPostProfitable, true)
	placeIn(panel.sellRow2, panel.btnPostAll, "LEFT", panel.btnPostProfitable, "RIGHT", AH_ROW_GAP)
	placeIn(panel.sellRow2, panel.btnPauseBulk, "LEFT", panel.btnPostAll, "RIGHT", AH_ROW_GAP)
	placeIn(panel.sellRow2, panel.btnClearRule, "RIGHT", panel.sellRow2, "RIGHT")
	placeIn(panel.sellRow2, panel.btnReserveItem, "RIGHT", panel.btnClearRule, "LEFT", -AH_ROW_GAP)
	placeIn(panel.sellRow2, panel.btnIgnoreItem, "RIGHT", panel.btnReserveItem, "LEFT", -AH_ROW_GAP)

	panel.sellRow3 = buildSellFilterRow(self, panel)
	panel.sellRow4 = buildSellCheckRow(self, panel)
	panel.sellRows = { panel.sellRow1, panel.sellRow2, panel.sellRow3, panel.sellRow4 }
	self:LayoutAuctionSellRows(panel, false)

	-- Progress row (shown while scanning or posting).
	panel.progressRow = CreateFrame("Frame", nil, panel)
	panel.progressRow:SetPoint("BOTTOMLEFT", panel.footer, "TOPLEFT", AH_PAD - 1, AH_ROW_GAP)
	panel.progressRow:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(AH_PAD - 1), AH_ROW_GAP)
	panel.progressRow:SetHeight(AH_ROW)
	placeIn(panel.progressRow, panel.btnPauseScan, "RIGHT", panel.progressRow, "RIGHT")
	panel.btnPauseScan:SetHeight(theme.size.controlSmall)
	placeIn(panel.progressRow, panel.progressText, "LEFT", panel.progressRow, "LEFT")
	panel.progressText:SetWidth(170)
	panel.progressText:SetWordWrap(false)
	panel.progressTiming:SetParent(panel.progressRow)
	panel.progressTiming:ClearAllPoints()
	panel.progressTiming:SetPoint("RIGHT", panel.btnPauseScan, "LEFT", -AH_ROW_GAP, 0)
	panel.progressTiming:SetFontObject("GameFontHighlightSmall")
	Tradewright:ColorText(panel.progressTiming, "textMuted")
	panel.progressTiming:SetWordWrap(false)
	panel.progressBar:SetParent(panel.progressRow)
	panel.progressBar:ClearAllPoints()
	panel.progressBar:SetPoint("LEFT", panel.progressText, "RIGHT", AH_ROW_GAP, 0)
	panel.progressBar:SetPoint("RIGHT", panel.progressTiming, "LEFT", -AH_ROW_GAP, 0)

	-- Cart: summary, search row, table, action row.
	y = headerHeight + 1 + AH_PAD
	panel.cartSummary:ClearAllPoints()
	panel.cartSummary:SetPoint("TOPLEFT", panel, "TOPLEFT", AH_PAD, -y)
	panel.cartSummary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -AH_PAD, -y)
	Tradewright:ColorText(panel.cartSummary, "textMuted")
	panel.cartRow1 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.cartRow1, y + 32)
	placeIn(panel.cartRow1, panel.btnCartRefresh, "RIGHT", panel.cartRow1, "RIGHT")
	placeIn(panel.cartRow1, panel.btnCartSearch, "RIGHT", panel.btnCartRefresh, "LEFT", -AH_ROW_GAP)
	self:SetButtonPrimary(panel.btnCartSearch, true)
	placeIn(panel.cartRow1, panel.cartSearchBox, "LEFT", panel.cartRow1, "LEFT", 6)
	panel.cartSearchBox:SetPoint("RIGHT", panel.btnCartSearch, "LEFT", -14, 0)
	self:AddSearchPlaceholder(panel.cartSearchBox, L["Search item, recipe or character"])
	panel.cartRow2 = CreateFrame("Frame", nil, panel)
	panel.cartRow2:SetPoint("BOTTOMLEFT", panel.footer, "TOPLEFT", AH_PAD - 1, AH_ROW_GAP)
	panel.cartRow2:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(AH_PAD - 1), AH_ROW_GAP)
	panel.cartRow2:SetHeight(AH_ROW)
	placeIn(panel.cartRow2, panel.btnCartClear, "RIGHT", panel.cartRow2, "RIGHT")
	Tradewright:ColorText(panel.btnCartClear:GetFontString(), "danger")
	placeIn(panel.cartRow2, panel.btnCartRemove, "RIGHT", panel.btnCartClear, "LEFT", -AH_ROW_GAP)
	if self.IS_RETAIL then
		placeIn(panel.cartRow2, panel.btnCartBuy, "RIGHT", panel.btnCartRemove, "LEFT", -AH_ROW_GAP)
	else
		panel.btnCartBuy:Hide()
		panel.btnCartBuy.Show = panel.btnCartBuy.Hide
		panel.btnCartBuy.SetShown = function() end
	end
	panel.cartHint = self:CreateText(panel.cartRow2, "GameFontHighlightSmall", "textMuted")
	panel.cartHint:SetPoint("LEFT")
	panel.cartHint:SetPoint("RIGHT", self.IS_RETAIL and panel.btnCartBuy or panel.btnCartRemove, "LEFT", -AH_ROW_GAP, 0)
	panel.cartTableHost:ClearAllPoints()
	panel.cartTableHost:SetPoint("TOPLEFT", panel.cartRow1, "BOTTOMLEFT", 0, -AH_PAD)
	panel.cartTableHost:SetPoint("BOTTOMRIGHT", panel.cartRow2, "TOPRIGHT", 0, AH_PAD)

	-- Auctions: a totals row, a row with the recheck and cancel buttons, then the table down to the footer.
	panel.ownedRow = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.ownedRow, headerHeight + 1 + AH_PAD)
	placeIn(panel.ownedRow, panel.ownedSummary, "LEFT", panel.ownedRow, "LEFT")
	panel.ownedSummary:SetPoint("RIGHT", panel.ownedRow, "RIGHT")
	panel.ownedRow2 = CreateFrame("Frame", nil, panel)
	anchorRow(panel, panel.ownedRow2, headerHeight + 1 + AH_PAD + AH_ROW + AH_ROW_GAP)
	placeIn(panel.ownedRow2, panel.btnOwnedCheck, "LEFT", panel.ownedRow2, "LEFT")
	self:SetButtonPrimary(panel.btnOwnedCheck, true)
	placeIn(panel.ownedRow2, panel.btnOwnedCancel, "LEFT", panel.btnOwnedCheck, "RIGHT", AH_ROW_GAP)
	Tradewright:ColorText(panel.btnOwnedCancel:GetFontString(), "danger")
	panel.ownedTableHost:ClearAllPoints()
	panel.ownedTableHost:SetPoint("TOPLEFT", panel.ownedRow2, "BOTTOMLEFT", 0, -AH_PAD)
	panel.ownedTableHost:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(AH_PAD - 1), AH_PAD)

	for _, button in ipairs({ panel.btnDumpFull, refresh, panel.btnPostProfitable, panel.btnPostAll, panel.btnPauseBulk,
		panel.btnIgnoreItem, panel.btnReserveItem, panel.btnClearRule, panel.btnCartSearch, panel.btnCartRefresh,
		panel.btnCartBuy, panel.btnCartRemove, panel.btnCartClear, panel.btnOwnedCheck, panel.btnOwnedCancel }) do
		self:SkinButton(button)
		self:SetButtonLabel(button, button:GetText())
		button:SetHeight(theme.size.control)
	end
	self:SkinButton(panel.btnPauseScan)
	self:SetButtonLabel(panel.btnPauseScan, L["Pause"], true)
	self:SkinTree(panel)
end

local FIRST_SCAN_HINT_HEIGHT = 40

-- Until the first full scan the panel has no prices at all, so it says what to press.
function Tradewright:IsFirstFullScanHintDue()
	return self:GetLastFullAuctionScanAt() == nil and not self:IsFullAuctionDumpRunning()
end

local function createFirstScanHint(pe, panel)
	local theme = pe:GetTheme()
	local hint = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	pe:ApplyBackdrop(hint, theme.surface2, theme.tick)
	hint:SetHeight(FIRST_SCAN_HINT_HEIGHT)
	hint.title = pe:CreateText(hint, "GameFontNormal", "gold")
	hint.title:SetPoint("TOPLEFT", 10, -6)
	hint.title:SetPoint("TOPRIGHT", -10, -6)
	hint.title:SetText(L["No prices yet. Press Full scan."])
	hint.detail = pe:CreateText(hint, "GameFontHighlightSmall", "textMuted")
	hint.detail:SetPoint("BOTTOMLEFT", 10, 6)
	hint.detail:SetPoint("BOTTOMRIGHT", -10, 6)
	hint.detail:SetText(L["Keep the auction house open until it ends."])
	return hint
end

-- Stacks the sell rows under the header. The first-scan hint, when shown, sits right under the
-- scan row (the one with Full scan) and pushes the other rows and the table down.
function Tradewright:LayoutAuctionSellRows(panel, hintShown)
	if hintShown and not panel.firstScanHint then
		panel.firstScanHint = createFirstScanHint(self, panel)
	end
	local hint = panel.firstScanHint
	if hint then
		hint:SetShown(hintShown)
	end
	local y = self:GetTheme().size.header + 1 + AH_PAD
	for index, row in ipairs(panel.sellRows or {}) do
		anchorRow(panel, row, y)
		y = y + (row.rowHeight or AH_ROW) + AH_ROW_GAP
		if index == 1 and hintShown then
			hint:ClearAllPoints()
			hint:SetPoint("TOPLEFT", panel, "TOPLEFT", AH_PAD, -y)
			hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -AH_PAD, -y)
			y = y + FIRST_SCAN_HINT_HEIGHT + AH_ROW_GAP
		end
	end
	panel.sellTableTop = y - AH_ROW_GAP + AH_PAD
end

-- Places the active tab's table between its controls and the progress row or footer.
function Tradewright:LayoutAuctionPanelBody(panel, activeTab, progressShown)
	local sell = activeTab == "sell"
	for _, row in ipairs(panel.sellRows or {}) do
		row:SetShown(sell)
	end
	panel.cartRow1:SetShown(activeTab == "cart")
	panel.cartRow2:SetShown(activeTab == "cart")
	panel.ownedRow:SetShown(activeTab == "auctions")
	panel.ownedRow2:SetShown(activeTab == "auctions")
	panel.ownedTableHost:SetShown(activeTab == "auctions")
	panel.progressRow:SetShown(sell and progressShown)
	panel.tableHost:ClearAllPoints()
	panel.tableHost:SetPoint("TOPLEFT", panel, "TOPLEFT", AH_PAD, -panel.sellTableTop)
	if sell and progressShown then
		panel.tableHost:SetPoint("BOTTOMRIGHT", panel.progressRow, "TOPRIGHT", 0, AH_ROW_GAP)
	else
		panel.tableHost:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(AH_PAD - 1), AH_PAD)
	end
end

-- Fold button at the right end of the header, left of it the Sell / Cart / Auctions switch, and the rail
-- that stands in for the panel while it is folded.
function Tradewright:BuildAuctionPanelDock(panel)
	local pe = self
	if panel.dock then
		-- A rebuilt panel gets a new dock; the old rail belongs to the game window, so hide it.
		panel.dock.rail:Hide()
	end
	panel.dock = self:CreatePanelDock({
		panel = panel,
		gameWindow = panel:GetParent(),
		setting = "auction.sidePanelExpanded",
		onExpand = function() pe:RefreshAuctionHousePanel() end,
	})
	local collapse = panel.dock.collapseButton
	collapse:SetPoint("RIGHT", panel, "TOPRIGHT", -6, -(self:GetTheme().size.header / 2))
	panel.tabAuctions:ClearAllPoints()
	panel.tabAuctions:SetPoint("RIGHT", collapse, "LEFT", -8, 0)
end
