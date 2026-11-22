-- Auction house side panel: one-time construction of frames, buttons, tables and their script handlers.
-- Per-refresh widget state lives in Tradewright_AuctionPanelRefresh.lua.
local addonName, Tradewright = ...

local shared = Tradewright.AuctionShared
local attachSimpleTooltip = shared.attachSimpleTooltip
local panelButton = shared.panelButton

local function isAuctionHousePanelReady(panel)
	return panel
		and panel.__ahAuctionPanelInitialized == true
		and panel.tabCart
		and panel.tableHost
		and panel.cartTableHost
end

local function isFrame(frame)
	return frame and frame.IsObjectType and frame:IsObjectType("Frame")
end

local function wipeFrameChildren(frame)
	if not frame or not frame.GetNumChildren then
		return
	end
	for i = frame:GetNumChildren(), 1, -1 do
		local child = select(i, frame:GetChildren())
		if child and child.SetParent then
			child:SetParent(nil)
		end
	end
end

-- Anchor spec for a widget placed 4px to the right of `frame`.
local function rightOf(frame)
	return { "LEFT", frame, "RIGHT", 4, 0 }
end

local function adoptPanel(self, ui, panel)
	ui.auctionPanel = panel
	self:HideExtraAuctionHousePanels(panel)
	return panel
end

-- Returns a ready panel to reuse; drops stale ones so they get rebuilt.
local function reuseExistingPanel(self, ui, frameName)
	if ui.auctionPanel and ui.auctionPanel:IsObjectType("Frame") then
		if isAuctionHousePanelReady(ui.auctionPanel) then
			self:HideExtraAuctionHousePanels(ui.auctionPanel)
			return ui.auctionPanel
		end
		ui.auctionPanel = nil
	end
	local existing = _G[frameName]
	if isFrame(existing) then
		if isAuctionHousePanelReady(existing) then
			return adoptPanel(self, ui, existing)
		end
		existing:Hide()
		existing:SetParent(nil)
		_G[frameName] = nil
	end
end

local function createPanelFrame(frameName, ah)
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	return template and CreateFrame("Frame", frameName, ah, template) or CreateFrame("Frame", frameName, ah)
end

-- Finds, adopts or creates the panel frame. Returns panel, done (return it as is) and the AH anchor frame.
local function acquirePanelFrame(self, ui)
	local frameName = addonName .. "AuctionPanel"
	local reused = reuseExistingPanel(self, ui, frameName)
	if reused then
		return reused, true
	end
	local ah = self:GetAuctionHouseAnchorFrame()
	if not ah then
		return nil, true
	end
	local helperPanel = _G["Tradewright_AuctionDataAuctionPanel"]
	if isFrame(helperPanel) and frameName ~= "Tradewright_AuctionDataAuctionPanel" then
		return adoptPanel(self, ui, helperPanel), true
	end
	local panel = createPanelFrame(frameName, ah)
	if isAuctionHousePanelReady(panel) then
		return adoptPanel(self, ui, panel), true
	end
	if panel.__ahAuctionPanelInitInProgress then
		ui.auctionPanel = panel
		return panel, true
	end
	return panel, false, ah
end

local function initPanelFrame(self, panel, ah)
	if panel.GetNumChildren and panel:GetNumChildren() > 0 then
		wipeFrameChildren(panel)
	end
	panel.__ahAuctionPanelInitInProgress = true
	panel:SetSize(500, 500)
	panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 8, -20)
	panel:SetPoint("BOTTOMLEFT", ah, "BOTTOMRIGHT", 8, 16)
	panel:SetResizable(true)
	if panel.SetResizeBounds then
		panel:SetResizeBounds(380, 320, 760, 900)
	elseif panel.SetMinResize and panel.SetMaxResize then
		panel:SetMinResize(380, 320)
		panel:SetMaxResize(760, 900)
	end
	self:StyleWindow(panel)
	panel:Hide()
end

local function tabClick(tab)
	return function()
		Tradewright:SetAuctionPanelActiveTab(tab, true)
	end
end

local function buildPanelTabs(panel)
	local tabSell = panelButton(panel, { 64, 20 }, "Sell", { "TOPRIGHT", panel, "TOPRIGHT", -78, -8 }, tabClick("sell"))
	panel.tabSell = tabSell
	panel.tabCart = panelButton(panel, { 92, 20 }, "Cart", { "RIGHT", tabSell, "LEFT", -4, 0 }, tabClick("cart"))
	panel.tabAuctions = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.tabAuctions:SetScript("OnClick", tabClick("auctions"))
end

-- Title, tab buttons, subtitle and the stats line; keeps title and stats in `w` for later anchors.
local function buildPanelHeader(panel, w)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetPoint("TOPRIGHT", -10, -10)
	title:SetJustifyH("LEFT")
	title:SetText(Tradewright.DISPLAY_NAME)
	panel.title = title
	buildPanelTabs(panel)
	local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	subtitle:SetPoint("TOPRIGHT", -10, -4)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Current character sellables")
	panel.subtitle = subtitle
	local stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	stats:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
	stats:SetPoint("TOPRIGHT", -10, -8)
	stats:SetJustifyH("LEFT")
	stats:SetJustifyV("TOP")
	stats:SetWordWrap(true)
	panel.stats = stats
	w.title, w.stats = title, stats
end

local function refreshShownPrices()
	if not Tradewright:CanStartFullAuctionSideActions(true) then
		return
	end
	local ids = Tradewright:BuildAuctionVisibleItemIDs()
	Tradewright:QueueVisibleAuctionRefresh(ids)
	Tradewright:RefreshAuctionHousePanel()
end

-- First sell-tab row: refresh shown prices plus the three economy scan buttons.
local function buildSellScanButtons(panel, w)
	w.btnRefresh = panelButton(panel, { 86, 20 }, "Refresh shown", { "TOPLEFT", w.stats, "BOTTOMLEFT", 0, -6 }, refreshShownPrices)
	w.btnScanCraftPrices = panelButton(panel, { 60, 20 }, "Crafts", rightOf(w.btnRefresh), function()
		Tradewright:QueueAuctionEconomyScan({ crafts = true })
	end)
	attachSimpleTooltip(w.btnScanCraftPrices, "Craft prices", "Looks up the price of everything your scanned recipes make and use.")
	panel.btnScanCraftPrices = w.btnScanCraftPrices
	w.btnScanAccountInv = panelButton(panel, { 64, 20 }, "Account", rightOf(w.btnScanCraftPrices), function()
		Tradewright:QueueAuctionEconomyScan({ accountInventory = true })
	end)
	attachSimpleTooltip(w.btnScanAccountInv, "Account items", "Looks up the price of tradable items any of your characters owns.")
	panel.btnScanAccountInv = w.btnScanAccountInv
	w.btnScanCraftAndAccount = panelButton(panel, { 46, 20 }, "Both", rightOf(w.btnScanAccountInv), function()
		Tradewright:QueueAuctionEconomyScan({ crafts = true, accountInventory = true })
	end)
	attachSimpleTooltip(
		w.btnScanCraftAndAccount,
		"Scan crafts + account",
		"Runs craft economy targets and tradable account inventory targets in one queue (duplicates deduped)."
	)
	panel.btnScanCraftAndAccount = w.btnScanCraftAndAccount
end

local function dumpVisibleAuctions()
	if not Tradewright:CanStartFullAuctionSideActions(true) then
		return
	end
	Tradewright:StartAuctionDump("visible")
	Tradewright:RefreshAuctionHousePanel()
end

local function buildSellDumpButtons(panel, w)
	w.btnDump = panelButton(panel, { 62, 20 }, "Dump", rightOf(w.btnScanCraftAndAccount), dumpVisibleAuctions)
	panel.btnDumpVisible = w.btnDump
	w.btnDumpFull = panelButton(panel, { 72, 20 }, "Full scan", rightOf(w.btnDump), function()
		Tradewright:StartAuctionDump("full")
		Tradewright:RefreshAuctionHousePanel()
	end)
	attachSimpleTooltip(w.btnDumpFull, "Full scan", "Reads every auction in the house and adds an hour to each item's price history.")
	panel.btnDumpFull = w.btnDumpFull
end

-- Second sell-tab row, part one: bulk posting and its pause toggle.
local function buildSellPostButtons(panel, w)
	w.btnPostProfitable = panelButton(panel, { 96, 20 }, "Post profitable", { "TOPLEFT", w.btnRefresh, "BOTTOMLEFT", 0, -4 }, function()
		Tradewright:RunAuctionPanelBulkAction("post_profitable")
	end)
	attachSimpleTooltip(
		w.btnPostProfitable,
		"Post profitable",
		"Queues every shown item that sells for more than it costs, skipping prices that look dumped. Click Post next once per auction."
	)
	panel.btnPostProfitable = w.btnPostProfitable
	w.btnPostAll = panelButton(panel, { 68, 20 }, "Post all", rightOf(w.btnPostProfitable), function()
		Tradewright:RunAuctionPanelBulkAction("post_all")
	end)
	attachSimpleTooltip(
		w.btnPostAll,
		"Post all",
		"Queues every shown item, including low margins and prices that look dumped. Click Post next once per auction."
	)
	panel.btnPostAll = w.btnPostAll
	w.btnPauseBulk = panelButton(panel, { 58, 20 }, "Pause", rightOf(w.btnPostAll), function()
		Tradewright:ToggleAuctionBulkPause()
	end)
	attachSimpleTooltip(w.btnPauseBulk, "Pause / Resume", "Pauses or resumes the current bulk post worker without clearing its queue position.")
	w.btnPauseBulk:Hide()
	panel.btnPauseBulk = w.btnPauseBulk
end

local function toggleSelectedIgnoreRule()
	local itemID = Tradewright:GetSelectedAuctionPanelItemID()
	if not itemID then
		Tradewright:PrintMessage("Select an auction row first.")
		return
	end
	local rule = Tradewright:GetAuctionItemRule(itemID) or {}
	Tradewright:SetAuctionItemRule(itemID, { ignore = rule.ignore == true and nil or true })
	Tradewright:DebugLog("AH", "rule ignore toggled", {
		string.format("itemID=%d ignore=%s", itemID, tostring(rule.ignore ~= true)),
	})
	Tradewright:PrimeAuctionPanelRows()
	Tradewright:RefreshAuctionHousePanel()
end

local function clearSelectedItemRule()
	local itemID = Tradewright:GetSelectedAuctionPanelItemID()
	if not itemID then
		Tradewright:PrintMessage("Select an auction row first.")
		return
	end
	Tradewright:ClearAuctionItemRule(itemID)
	Tradewright:DebugLog("AH", "rule cleared", {
		string.format("itemID=%d", itemID),
	})
	Tradewright:PrimeAuctionPanelRows()
	Tradewright:RefreshAuctionHousePanel()
end

-- Second sell-tab row, part two: per-item bulk rules for the selected row.
local function buildSellRuleButtons(panel, w)
	w.btnIgnoreItem = panelButton(panel, { 58, 20 }, "Ignore", rightOf(w.btnPauseBulk), toggleSelectedIgnoreRule)
	attachSimpleTooltip(w.btnIgnoreItem, "Ignore", "Never post the selected item in bulk.")
	panel.btnIgnoreItem = w.btnIgnoreItem
	w.btnReserveItem = panelButton(panel, { 58, 20 }, "Keep…", rightOf(w.btnIgnoreItem), function()
		Tradewright:ShowAuctionReservePrompt(Tradewright:GetSelectedAuctionPanelItemID())
	end)
	attachSimpleTooltip(w.btnReserveItem, "Keep", "Keep a number of the selected item in your bags when posting in bulk.")
	panel.btnReserveItem = w.btnReserveItem
	w.btnClearRule = panelButton(panel, { 58, 20 }, "Clear rule", rightOf(w.btnReserveItem), clearSelectedItemRule)
	attachSimpleTooltip(w.btnClearRule, "Clear rule", "Remove the ignore or keep rule from the selected item.")
	panel.btnClearRule = w.btnClearRule
end

local function sellRowTooltipLines(pe, rowData)
	local lines = {}
	if not (rowData.nativePrice and rowData.nativePrice > 0) then
		lines[#lines + 1] = { "Live price", "not scanned this visit" }
	end
	if rowData.fallbackPrice and rowData.fallbackPrice > 0 then
		lines[#lines + 1] = { "Fallback price", pe:FormatCopperFull(rowData.fallbackPrice) .. " · " .. tostring(rowData.fallbackPriceSource or "other addon") }
	end
	lines[#lines + 1] = { "Return", pe:FormatPercent(rowData.potentialROI) }
	if rowData.isIgnoredByRule then
		lines[#lines + 1] = { "Rule", "never posted in bulk" }
	elseif (tonumber(rowData.reserveQty) or 0) > 0 then
		lines[#lines + 1] = { "Rule", "keep " .. pe:FormatNumberGrouped(rowData.reserveQty) }
	end
	return lines
end

local function showSellRowTooltip(rowFrame, rowData)
	if not rowData or not rowData.itemID then
		return
	end
	local pe = Tradewright
	local lines = sellRowTooltipLines(pe, rowData)
	local hint = "Click to put it in the sell slot · Shift-click to link"
	if rowData.isDumpedLow then
		hint = "The price looks dumped unusually low. " .. hint
	end
	pe:ShowItemRowTooltip(rowFrame, rowData.itemID, lines, hint)
end

local function onSellRowClick(_, rowData, _, tableWidget)
	local id = rowData and rowData.itemID
	if not id or Tradewright:HandleItemRowModifiedClick(id) then
		return
	end
	Tradewright:GetState().auctionPanelSelectedItemID = id
	tableWidget:SetSelectedRow(rowData)
	Tradewright:RefreshAuctionPanelRules()
	-- Clicking a row should also revalidate this item's current market value.
	if Tradewright:CanStartFullAuctionSideActions(true) then
		Tradewright:QueuePriorityAuctionRefresh({ id })
	end
	local ok = Tradewright:TrySendItemToAuctionSellFrame(id, rowData and rowData.firstBag, rowData and rowData.firstSlot)
	Tradewright:GetState().auctionPanelSelectedItemID = id
	if ok then
		Tradewright:GetState().auctionLastSellSelectionItemID = id
		Tradewright:RefreshAuctionPanelRules()
		Tradewright:PrintMessage(string.format("Selected %s for AH sell.", Tradewright:GetItemDisplayName(id)))
	else
		Tradewright:RefreshAuctionPanelRules()
		Tradewright:PrintMessage(string.format(
			"Could not put %s in the sell slot (not sellable, or its data is still loading).",
			Tradewright:GetItemDisplayName(id)
		))
	end
end

-- Pins a reusable table's frame to fill its host.
local function fillHost(tableWidget, host)
	tableWidget.frame:ClearAllPoints()
	tableWidget.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
	tableWidget.frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
end

local function buildSellTable(self, panel, ui)
	panel.tableHost = CreateFrame("Frame", nil, panel)
	panel.tableHost:SetPoint("TOPLEFT", ui.ahClassDropdown, "BOTTOMLEFT", -2, -8)
	panel.tableHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 52)
	self:ApplyAuctionSellFilterDefaults(ui)
	panel.table = self:CreateReusableTable(panel.tableHost, {
		rowHeight = 24,
		autoFitToScroll = true,
		footer = true,
		emptyTitle = "Nothing to sell",
		emptyHint = "No items in your bags match the filters.",
		isRowSelected = function(rowData)
			return rowData and rowData.itemID ~= nil and rowData.itemID == Tradewright:GetSelectedAuctionPanelItemID()
		end,
		maxRows = 120,
		sortKey = ui.ahSortKey,
		sortAsc = ui.ahSortAsc,
		onSortChanged = function(sortKey, sortAsc)
			ui.ahSortKey = sortKey
			ui.ahSortAsc = sortAsc
		end,
		onRowEnter = showSellRowTooltip,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = onSellRowClick,
	})
	if panel.table and panel.table.frame then
		fillHost(panel.table, panel.tableHost)
	end
	panel.table:SetColumns(self:BuildAuctionPanelColumns())
end

local function buildProgressWidgets(self, panel)
	panel.progressText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.progressText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 44)
	panel.progressText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 44)
	panel.progressText:SetJustifyH("LEFT")
	panel.progressText:SetText("")
	panel.progressBar = CreateFrame("StatusBar", nil, panel)
	panel.progressBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 24)
	panel.progressBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 24)
	panel.progressBar:SetHeight(14)
	self:StyleProgressBar(panel.progressBar)
	panel.progressBarBg = panel.progressBar.ahTrack
	panel.btnPauseScan = panelButton(panel, { 64, 18 }, "Pause", { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4 }, function()
		Tradewright:ToggleAuctionRefreshPause()
	end)
	attachSimpleTooltip(
		panel.btnPauseScan,
		"Pause / Resume Scan",
		"Pauses or resumes the queued auction price scan without clearing its progress."
	)
	panel.btnPauseScan:Hide()
	panel.progressTiming = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.progressTiming:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 6)
	panel.progressTiming:SetPoint("BOTTOMRIGHT", panel.btnPauseScan, "BOTTOMLEFT", -8, 0)
	panel.progressTiming:SetJustifyH("LEFT")
	panel.progressTiming:SetText("")
	panel.progressTiming:Hide()
end

local function collectSellControls(panel, ui, w)
	return {
		w.btnRefresh,
		w.btnScanCraftPrices,
		w.btnScanAccountInv,
		w.btnScanCraftAndAccount,
		w.btnDump,
		w.btnDumpFull,
		w.btnPostProfitable,
		w.btnPostAll,
		w.btnPauseBulk,
		w.btnIgnoreItem,
		w.btnReserveItem,
		w.btnClearRule,
		w.search,
		w.craftedOnly,
		w.profitableOnly,
		ui.ahClassDropdown,
		ui.ahSubclassDropdown,
		ui.ahExpansionDropdown,
		w.clearBtn,
		panel.tableHost,
		panel.table and panel.table.frame or nil,
	}
end

local function buildResizeHandle(panel)
	panel.resizeHandle = CreateFrame("Button", nil, panel)
	panel.resizeHandle:SetSize(18, 18)
	panel.resizeHandle:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
	panel.resizeHandle:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
	panel.resizeHandle:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
	panel.resizeHandle:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
	panel.resizeHandle:RegisterForDrag("LeftButton")
	panel.resizeHandle:SetScript("OnDragStart", function()
		panel:StartSizing("BOTTOMRIGHT")
	end)
	panel.resizeHandle:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
	end)
	attachSimpleTooltip(panel.resizeHandle, "Resize", "Drag to resize the auction side panel.")
end

-- Sell tab (default): action buttons, filters, the sellables table and the shared progress area.
local function buildSellTab(self, panel, ui, w)
	buildPanelHeader(panel, w)
	buildSellScanButtons(panel, w)
	buildSellDumpButtons(panel, w)
	buildSellPostButtons(panel, w)
	buildSellRuleButtons(panel, w)
	self:BuildAuctionSellFilters(panel, ui, w)
	buildSellTable(self, panel, ui)
	self:SyncAuctionSellFilterWidgets(panel, ui)
	buildProgressWidgets(self, panel)
end

function Tradewright:EnsureAuctionHousePanel()
	self.ui = self.ui or {}
	local ui = self.ui
	local panel, done, ah = acquirePanelFrame(self, ui)
	if done then
		return panel
	end
	initPanelFrame(self, panel, ah)
	local w = {}
	buildSellTab(self, panel, ui, w)
	self:BuildAuctionPanelCartTab(panel, w.title)
	self:BuildAuctionPanelOwnedTab(panel)
	panel.sellControls = collectSellControls(panel, ui, w)
	buildResizeHandle(panel)
	self:BuildAuctionPanelLayout(panel)
	panel.__ahAuctionPanelInitInProgress = nil
	panel.__ahAuctionPanelInitialized = true
	ui.auctionPanel = panel
	self:HideExtraAuctionHousePanels(panel)
	return panel
end
