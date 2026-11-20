-- Auction house side panel: one-time construction of frames, buttons, tables and their script handlers.
-- Per-refresh widget state lives in AuctionHelper_AuctionPanelRefresh.lua.
local addonName, ProfessionExporter = ...

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

local function attachSimpleTooltip(widget, title, body)
	ProfessionExporter:AttachSimpleTooltip(widget, title, body)
end

-- Anchor spec for a widget placed 4px to the right of `frame`.
local function rightOf(frame)
	return { "LEFT", frame, "RIGHT", 4, 0 }
end

local function panelButton(panel, size, text, point, onClick)
	return ProfessionExporter:CreateAuctionPanelButton(panel, size, text, point, onClick)
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
	local helperPanel = _G["AuctionHelper_AuctionDataAuctionPanel"]
	if isFrame(helperPanel) and frameName ~= "AuctionHelper_AuctionDataAuctionPanel" then
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
		ProfessionExporter:SetAuctionPanelActiveTab(tab, true)
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
	title:SetText("AuctionHelper")
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
	if not ProfessionExporter:CanStartFullAuctionSideActions(true) then
		return
	end
	local ids = ProfessionExporter:BuildAuctionVisibleItemIDs()
	ProfessionExporter:QueueVisibleAuctionRefresh(ids)
	ProfessionExporter:RefreshAuctionHousePanel()
end

-- First sell-tab row: refresh shown prices plus the three economy scan buttons.
local function buildSellScanButtons(panel, w)
	w.btnRefresh = panelButton(panel, { 86, 20 }, "Refresh shown", { "TOPLEFT", w.stats, "BOTTOMLEFT", 0, -6 }, refreshShownPrices)
	w.btnScanCraftPrices = panelButton(panel, { 60, 20 }, "Crafts", rightOf(w.btnRefresh), function()
		ProfessionExporter:QueueAuctionEconomyScan({ crafts = true })
	end)
	attachSimpleTooltip(w.btnScanCraftPrices, "Craft prices", "Looks up the price of everything your scanned recipes make and use.")
	panel.btnScanCraftPrices = w.btnScanCraftPrices
	w.btnScanAccountInv = panelButton(panel, { 64, 20 }, "Account", rightOf(w.btnScanCraftPrices), function()
		ProfessionExporter:QueueAuctionEconomyScan({ accountInventory = true })
	end)
	attachSimpleTooltip(w.btnScanAccountInv, "Account items", "Looks up the price of tradable items any of your characters owns.")
	panel.btnScanAccountInv = w.btnScanAccountInv
	w.btnScanCraftAndAccount = panelButton(panel, { 46, 20 }, "Both", rightOf(w.btnScanAccountInv), function()
		ProfessionExporter:QueueAuctionEconomyScan({ crafts = true, accountInventory = true })
	end)
	attachSimpleTooltip(
		w.btnScanCraftAndAccount,
		"Scan crafts + account",
		"Runs craft economy targets and tradable account inventory targets in one queue (duplicates deduped)."
	)
	panel.btnScanCraftAndAccount = w.btnScanCraftAndAccount
end

local function dumpVisibleAuctions()
	if not ProfessionExporter:CanStartFullAuctionSideActions(true) then
		return
	end
	ProfessionExporter:StartAuctionDump("visible")
	ProfessionExporter:RefreshAuctionHousePanel()
end

local function buildSellDumpButtons(panel, w)
	w.btnDump = panelButton(panel, { 62, 20 }, "Dump", rightOf(w.btnScanCraftAndAccount), dumpVisibleAuctions)
	panel.btnDumpVisible = w.btnDump
	w.btnDumpFull = panelButton(panel, { 72, 20 }, "Full scan", rightOf(w.btnDump), function()
		ProfessionExporter:StartAuctionDump("full")
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	attachSimpleTooltip(w.btnDumpFull, "Full scan", "Reads every auction in the house and adds an hour to each item's price history.")
	panel.btnDumpFull = w.btnDumpFull
end

-- Second sell-tab row, part one: bulk posting and its pause toggle.
local function buildSellPostButtons(panel, w)
	w.btnPostProfitable = panelButton(panel, { 96, 20 }, "Post profitable", { "TOPLEFT", w.btnRefresh, "BOTTOMLEFT", 0, -4 }, function()
		ProfessionExporter:RunAuctionPanelBulkAction("post_profitable")
	end)
	attachSimpleTooltip(
		w.btnPostProfitable,
		"Post profitable",
		"Queues every shown item that sells for more than it costs, skipping prices that look dumped. Click Post next once per auction."
	)
	panel.btnPostProfitable = w.btnPostProfitable
	w.btnPostAll = panelButton(panel, { 68, 20 }, "Post all", rightOf(w.btnPostProfitable), function()
		ProfessionExporter:RunAuctionPanelBulkAction("post_all")
	end)
	attachSimpleTooltip(
		w.btnPostAll,
		"Post all",
		"Queues every shown item, including low margins and prices that look dumped. Click Post next once per auction."
	)
	panel.btnPostAll = w.btnPostAll
	w.btnPauseBulk = panelButton(panel, { 58, 20 }, "Pause", rightOf(w.btnPostAll), function()
		ProfessionExporter:ToggleAuctionBulkPause()
	end)
	attachSimpleTooltip(w.btnPauseBulk, "Pause / Resume", "Pauses or resumes the current bulk post worker without clearing its queue position.")
	w.btnPauseBulk:Hide()
	panel.btnPauseBulk = w.btnPauseBulk
end

local function toggleSelectedIgnoreRule()
	local itemID = ProfessionExporter:GetSelectedAuctionPanelItemID()
	if not itemID then
		ProfessionExporter:PrintMessage("Select an auction row first.")
		return
	end
	local rule = ProfessionExporter:GetAuctionItemRule(itemID) or {}
	ProfessionExporter:SetAuctionItemRule(itemID, { ignore = rule.ignore == true and nil or true })
	ProfessionExporter:DebugLog("AH", "rule ignore toggled", {
		string.format("itemID=%d ignore=%s", itemID, tostring(rule.ignore ~= true)),
	})
	ProfessionExporter:PrimeAuctionPanelRows()
	ProfessionExporter:RefreshAuctionHousePanel()
end

local function clearSelectedItemRule()
	local itemID = ProfessionExporter:GetSelectedAuctionPanelItemID()
	if not itemID then
		ProfessionExporter:PrintMessage("Select an auction row first.")
		return
	end
	ProfessionExporter:ClearAuctionItemRule(itemID)
	ProfessionExporter:DebugLog("AH", "rule cleared", {
		string.format("itemID=%d", itemID),
	})
	ProfessionExporter:PrimeAuctionPanelRows()
	ProfessionExporter:RefreshAuctionHousePanel()
end

-- Second sell-tab row, part two: per-item bulk rules for the selected row.
local function buildSellRuleButtons(panel, w)
	w.btnIgnoreItem = panelButton(panel, { 58, 20 }, "Ignore", rightOf(w.btnPauseBulk), toggleSelectedIgnoreRule)
	attachSimpleTooltip(w.btnIgnoreItem, "Ignore", "Never post the selected item in bulk.")
	panel.btnIgnoreItem = w.btnIgnoreItem
	w.btnReserveItem = panelButton(panel, { 58, 20 }, "Keep…", rightOf(w.btnIgnoreItem), function()
		ProfessionExporter:ShowAuctionReservePrompt(ProfessionExporter:GetSelectedAuctionPanelItemID())
	end)
	attachSimpleTooltip(w.btnReserveItem, "Keep", "Keep a number of the selected item in your bags when posting in bulk.")
	panel.btnReserveItem = w.btnReserveItem
	w.btnClearRule = panelButton(panel, { 58, 20 }, "Clear rule", rightOf(w.btnReserveItem), clearSelectedItemRule)
	attachSimpleTooltip(w.btnClearRule, "Clear rule", "Remove the ignore or keep rule from the selected item.")
	panel.btnClearRule = w.btnClearRule
end

-- Check button that stores its checked state in ui[uiKey] and refreshes the panel.
local function filterCheckButton(panel, ui, point, label, uiKey)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetPoint(point[1], point[2], point[3], point[4], point[5])
	local text = check.Text or (check.GetName and check:GetName() and _G[check:GetName() .. "Text"]) or nil
	if text then
		text:SetText(label)
	end
	check:SetScript("OnClick", function(btn)
		ui[uiKey] = btn:GetChecked() == true
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	return check
end

-- Search box plus the crafted-only / profitable-only check buttons.
local function buildSellSearchFilters(panel, ui, w)
	local search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	search:SetSize(118, 20)
	search:SetAutoFocus(false)
	search:SetPoint("TOPLEFT", w.btnPostProfitable, "BOTTOMLEFT", 6, -8)
	search:SetScript("OnTextChanged", function(box)
		ui.ahFilterText = box:GetText() or ""
		ProfessionExporter:RefreshAuctionHousePanel()
	end)
	panel.searchBox = search
	w.search = search
	w.craftedOnly = filterCheckButton(panel, ui, { "LEFT", search, "RIGHT", 6, -1 }, "Crafted only", "ahCraftedOnly")
	panel.craftedOnly = w.craftedOnly
	w.profitableOnly = filterCheckButton(panel, ui, { "LEFT", w.craftedOnly, "RIGHT", 54, 0 }, "Profitable only", "ahProfitableOnly")
	panel.profitableOnly = w.profitableOnly
end

local function buildClassDropdowns(self, panel, ui, w)
	ui.ahClassDropdown = self:CreateMultiSelectDropdown(panel, {
		label = "Class",
		allLabel = "All classes",
		width = 114,
		getSelection = function()
			return ui.ahClassFilterValues or {}
		end,
		setSelection = function(selection)
			ui.ahClassFilterValues = selection or {}
		end,
		onChanged = function()
			ui.ahSubclassFilterValues = {}
			ProfessionExporter:RefreshAuctionHousePanel()
		end,
	})
	ui.ahClassDropdown:SetPoint("TOPLEFT", w.search, "BOTTOMLEFT", 0, -8)
	panel.classDropdown = ui.ahClassDropdown
	ui.ahSubclassDropdown = self:CreateMultiSelectDropdown(panel, {
		label = "Subclass",
		allLabel = "All subclasses",
		width = 114,
		getSelection = function()
			return ui.ahSubclassFilterValues or {}
		end,
		setSelection = function(selection)
			ui.ahSubclassFilterValues = selection or {}
		end,
		onChanged = function()
			ProfessionExporter:RefreshAuctionHousePanel()
		end,
	})
	ui.ahSubclassDropdown:SetPoint("TOPLEFT", ui.ahClassDropdown, "TOPRIGHT", 4, 0)
	panel.subclassDropdown = ui.ahSubclassDropdown
end

local function copyBoolMap(t)
	local out = {}
	if type(t) == "table" then
		for k, v in pairs(t) do
			if v then
				out[k] = true
			end
		end
	end
	return out
end

local function buildExpansionDropdown(self, panel, ui)
	ui.ahExpansionFilterValues = copyBoolMap(self:GetSetting("auction.selectedExpansions", {}))
	ui.ahExpansionDropdown = self:CreateMultiSelectDropdown(panel, {
		label = "Expansion",
		width = 114,
		allLabel = "All expansions",
		getOptions = function()
			return ProfessionExporter:GetExpansionFilterOptions()
		end,
		getSelection = function()
			return ui.ahExpansionFilterValues or {}
		end,
		setSelection = function(selection)
			ui.ahExpansionFilterValues = selection or {}
			ProfessionExporter:SetSetting("auction.selectedExpansions", selection)
		end,
		onChanged = function()
			ProfessionExporter:RefreshAuctionHousePanel()
		end,
	})
	ui.ahExpansionDropdown:SetPoint("TOPLEFT", ui.ahSubclassDropdown, "TOPRIGHT", 4, 0)
	panel.expansionDropdown = ui.ahExpansionDropdown
end

local function resetSellFilters(panel, ui)
	ui.ahFilterText = ""
	ui.ahCraftedOnly = false
	ui.ahProfitableOnly = false
	ui.ahClassFilterValues = {}
	ui.ahSubclassFilterValues = {}
	ui.ahExpansionFilterValues = {}
	panel.searchBox:SetText("")
	panel.craftedOnly:SetChecked(false)
	panel.profitableOnly:SetChecked(false)
	ProfessionExporter:SetSetting("auction.selectedExpansions", {})
	if ui.ahClassDropdown then
		ui.ahClassDropdown:RefreshText()
	end
	if ui.ahSubclassDropdown then
		ui.ahSubclassDropdown:RefreshText()
	end
	if ui.ahExpansionDropdown then
		ui.ahExpansionDropdown:RefreshText()
	end
	ProfessionExporter:RefreshAuctionHousePanel()
end

local function buildSellFilters(self, panel, ui, w)
	buildSellSearchFilters(panel, ui, w)
	buildClassDropdowns(self, panel, ui, w)
	buildExpansionDropdown(self, panel, ui)
	w.clearBtn = panelButton(panel, { 52, 18 }, "Reset filters", { "LEFT", w.profitableOnly, "RIGHT", 48, 0 }, function()
		resetSellFilters(panel, ui)
	end)
	panel.clearBtn = w.clearBtn
end

local function applySellFilterDefaults(ui)
	ui.ahSortKey = ui.ahSortKey or "potentialROI"
	if ui.ahSortAsc == nil then
		ui.ahSortAsc = false
	end
	if ui.ahFilterText == nil then
		ui.ahFilterText = ""
	end
	if ui.ahCraftedOnly == nil then
		ui.ahCraftedOnly = false
	end
	if ui.ahProfitableOnly == nil then
		ui.ahProfitableOnly = false
	end
	ui.ahClassFilterValues = ui.ahClassFilterValues or {}
	ui.ahSubclassFilterValues = ui.ahSubclassFilterValues or {}
	ui.ahExpansionFilterValues = ui.ahExpansionFilterValues or {}
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
	local pe = ProfessionExporter
	local lines = sellRowTooltipLines(pe, rowData)
	local hint = "Click to put it in the sell slot · Shift-click to link"
	if rowData.isDumpedLow then
		hint = "The price looks dumped unusually low. " .. hint
	end
	pe:ShowItemRowTooltip(rowFrame, rowData.itemID, lines, hint)
end

local function onSellRowClick(_, rowData, _, tableWidget)
	local id = rowData and rowData.itemID
	if not id or ProfessionExporter:HandleItemRowModifiedClick(id) then
		return
	end
	ProfessionExporter:GetState().auctionPanelSelectedItemID = id
	tableWidget:SetSelectedRow(rowData)
	ProfessionExporter:RefreshAuctionPanelRules()
	-- Clicking a row should also revalidate this item's current market value.
	if ProfessionExporter:CanStartFullAuctionSideActions(true) then
		ProfessionExporter:QueueVisibleAuctionRefresh({ id })
	end
	local ok = ProfessionExporter:TrySendItemToAuctionSellFrame(id, rowData and rowData.firstBag, rowData and rowData.firstSlot)
	ProfessionExporter:GetState().auctionPanelSelectedItemID = id
	if ok then
		ProfessionExporter:GetState().auctionLastSellSelectionItemID = id
		ProfessionExporter:RefreshAuctionPanelRules()
		ProfessionExporter:PrintMessage(string.format("Selected %s for AH sell.", ProfessionExporter:GetItemDisplayName(id)))
	else
		ProfessionExporter:RefreshAuctionPanelRules()
		ProfessionExporter:PrintMessage(string.format(
			"Could not put %s in the sell slot (not sellable, or its data is still loading).",
			ProfessionExporter:GetItemDisplayName(id)
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
	applySellFilterDefaults(ui)
	panel.table = self:CreateReusableTable(panel.tableHost, {
		rowHeight = 24,
		autoFitToScroll = true,
		footer = true,
		emptyTitle = "Nothing to sell",
		emptyHint = "No items in your bags match the filters.",
		isRowSelected = function(rowData)
			return rowData and rowData.itemID ~= nil and rowData.itemID == ProfessionExporter:GetSelectedAuctionPanelItemID()
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

local function syncSellFilterWidgets(self, panel, ui)
	panel.searchBox:SetText(ui.ahFilterText or "")
	panel.craftedOnly:SetChecked(ui.ahCraftedOnly == true)
	panel.profitableOnly:SetChecked(ui.ahProfitableOnly == true)
	panel.classDropdown:RefreshText()
	panel.subclassDropdown:RefreshText()
	if panel.expansionDropdown then
		panel.expansionDropdown:RefreshText()
	end
	self:RefreshAuctionPanelRules()
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
		ProfessionExporter:ToggleAuctionRefreshPause()
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
	buildSellFilters(self, panel, ui, w)
	buildSellTable(self, panel, ui)
	syncSellFilterWidgets(self, panel, ui)
	buildProgressWidgets(self, panel)
end

function ProfessionExporter:EnsureAuctionHousePanel()
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
