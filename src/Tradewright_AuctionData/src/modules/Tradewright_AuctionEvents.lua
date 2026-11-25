-- Auction house event handlers: the house opening and closing, search results, posts, sales and bag changes.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local shared = Tradewright.AuctionShared
local AuctionLogic = Tradewright.AuctionLogic
local normalizeItemID = shared.normalizeItemID
local normalizeSearchEventItemID = shared.normalizeSearchEventItemID

local AUTO_SCAN_MAX_AGE_SEC = 60 * 60

function Tradewright:OnAuctionHouseAuctionCreated()
	local state = self:GetState()
	if self:ConfirmAuctionBulkCurrent("auction_created") then
		return
	end
	local recent = state and state.recentAuctionBulkConfirmation or nil
	if recent and recent.itemID and ((GetTime and GetTime() or 0) - (tonumber(recent.at) or 0)) <= 2 then
		self:PrimeAuctionPanelRows()
		self:RefreshAuctionHousePanel()
		return
	end
	local itemID = normalizeItemID(state and state.auctionActiveItemID)
	if itemID then
		self:RecordAuctionTransaction({
			kind = "posted",
			itemID = itemID,
			quantity = 1,
			source = "auction_event",
		})
	end
	if not state.auctionRefreshRunning and not state.auctionRoiRunning then
		state.auctionActiveItemID = nil
	end
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
end

-- The event does not say which auction sold, so sales are counted from the auction house mail
-- (the ledger) instead; here the panel only refreshes.
function Tradewright:OnAuctionHouseAuctionSold()
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
end

--- Prefer retail AuctionHouseFrame; Forever / classic clients often expose AuctionFrame.
function Tradewright:GetAuctionHouseAnchorFrame()
	local ah = _G.AuctionHouseFrame
	if ah then
		return ah
	end
	return _G.AuctionFrame
end

function Tradewright:IsAuctionHouseFrameOpen()
	local ah = self:GetAuctionHouseAnchorFrame()
	return ah and ah.IsShown and ah:IsShown() and true or false
end

local function buildStaleScanTargets(pe, includeBulk)
	return pe:BuildPrioritizedAuctionAutoScanTargets({
		includeVisibleBags = true,
		includeCrafts = includeBulk,
		includeAccountInventory = includeBulk,
		includeSessionSearched = false,
		requireStaleNonVisible = true,
		freshnessWindowSeconds = AUTO_SCAN_MAX_AGE_SEC,
	})
end

-- Bag items are always checked one by one: the player needs their prices to see undercuts. The
-- craft and inventory prices (the bulk) are many, so when a full scan is ready they wait for it.
local function queueStalePricesOnOpen(pe)
	local state = pe:GetState()
	local allTargets, sellingTargets = buildStaleScanTargets(pe, true), buildStaleScanTargets(pe, false)
	local plan = AuctionLogic.PlanScanOnOpen({
		fullScanReady = pe:GetFullAuctionDumpCooldownRemaining() <= 0,
		suggestFullScan = pe:GetSetting("auction.suggestFullScan", true) ~= false,
		staleBulkCount = #allTargets - #sellingTargets,
	})
	local targets = plan.queueBulk and allTargets or sellingTargets
	state.auctionPricesWaitingForFullScan = #allTargets - #targets
	if #targets == 0 then
		-- Nothing is queued, so no scan progress would repaint the panel and light the button.
		pe:RefreshAuctionHousePanel()
		return
	end
	state.auctionPendingPriceScanMode = plan.queueBulk and "mixed" or nil
	state.auctionInvalidateCraftsAfterRefresh = plan.queueBulk
	state.auctionRefreshQueue = {}
	state.auctionRefreshQueueOrderCounter = 0
	pe:QueueAuctionScanTargets(targets, { skipSessionSearched = true })
end

function Tradewright:OnAuctionHouseShow()
	if self:GetSetting("auction.enabled", true) == false then
		return
	end
	self.ui = self.ui or {}
	self.ui.auctionPanelTabManual = nil
	self.ui.auctionPanelActiveTab = nil
	if self:GetSetting("auction.sellPanelEnabled", true) then
		local panel = self:EnsureAuctionHousePanel()
		self:HideExtraAuctionHousePanels(panel)
		if panel then
			self:ShowPanelDock(panel.dock, true)
		end
	end
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
	self:RetryPrimeAuctionPanelRows(1)
	self:GetState().auctionPricesWaitingForFullScan = nil
	if self:CanStartFullAuctionSideActions(false) then
		queueStalePricesOnOpen(self)
		self:StartAuctionRoiEnrichment(self:BuildAuctionVisibleItemIDs())
	end
end

-- Hides the panel and its rail, so a rail left showing cannot come back once the panel is switched off.
local function hideAuctionPanel(pe)
	local panel = pe.ui and pe.ui.auctionPanel
	if panel and panel.dock then
		pe:ShowPanelDock(panel.dock, false)
	elseif panel then
		panel:Hide()
	end
end

function Tradewright:OnAuctionHouseClosed()
	local state = self:GetState()
	if state.auctionDump and state.auctionDump.running == true then
		state.auctionDump.running = false
		state.auctionDump.finishedAt = Tradewright:Now()
	end
	state.auctionRefreshQueue = {}
	state.auctionRefreshRunning = false
	state.auctionRefreshPaused = false
	state.auctionRefreshPausedForBulk = false
	state.auctionRefreshScanList = nil
	state.auctionRefreshIndex = nil
	state.auctionSearchContext = nil
	state.auctionPendingBrowseSearch = nil
	state.auctionRoiQueue = {}
	state.auctionRoiRunning = false
	state.auctionLivePriceByItem = {}
	state.auctionNativePriceByItem = {}
	state.auctionSourceCounts = nil
	state.auctionLastSellSelectionItemID = nil
	state.auctionPanelSelectedItemID = nil
	state.auctionCartSelectedItemID = nil
	state.auctionPanelRows = nil
	state.auctionPanelRowsViewRevision = nil
	state.auctionPanelRowsBagSignature = nil
	state.auctionOwnedBagState = nil
	state.auctionBulk = nil
	state.recentAuctionBulkConfirmation = nil
	state.auctionScanMode = "idle"
	state.auctionScanTotal = 0
	state.auctionScanDone = 0
	state.auctionActiveItemID = nil
	state.auctionInvalidateCraftsAfterRefresh = false
	state.auctionPendingPriceScanMode = nil
	state.auctionRefreshStartedAt = nil
	state.auctionRefreshQueueOrderCounter = nil
	state.auctionSearchedTargets = nil
	state.auctionSearchedTargetsMeta = nil
	hideAuctionPanel(self)
end

function Tradewright:OnAuctionHouseBrowseResultsUpdated()
	local state = self:GetState()
	self:DebugLog("AH", "event browse results", {
		string.format("pending=%s", tostring(state and state.auctionPendingBrowseSearch and state.auctionPendingBrowseSearch.itemID)),
	})
	if self:TrySelectPendingAuctionBrowseResult() then
		C_Timer.After(0, function()
			Tradewright:TrySelectPendingAuctionBrowseResult()
		end)
	end
	self:SaveBrowseResultsToScanEntries()
	self:RefreshAuctionHousePanel()
end

function Tradewright:OnCommoditySearchResultsUpdated(itemID)
	local state = self:GetState()
	self:DebugLog("AH", "event commodity results", {
		string.format(L["arg=%s selected=%s ctx=%s"], tostring(normalizeSearchEventItemID(itemID)),
			tostring(state and state.auctionLastSellSelectionItemID), tostring(state and state.auctionSearchContext and state.auctionSearchContext.itemID)),
	})
	local ctx = state and state.auctionSearchContext or nil
	if ctx and self:DoesAuctionSearchEventMatchItem(ctx.itemID, itemID, ctx.scanKeyFields) then
		self:FinishQueuedAuctionRefreshItem(ctx.itemID)
		return
	end
	local selectedItemID = normalizeItemID(itemID) or normalizeItemID(state and state.auctionLastSellSelectionItemID)
	if selectedItemID then
		self:ApplyAuctionSearchResultToDatabase(selectedItemID, nil, "commodity_results_event")
	end
	self:RefreshAuctionHousePanel()
end

function Tradewright:OnItemSearchResultsUpdated(itemKey)
	local state = self:GetState()
	self:DebugLog("AH", "event item results", {
		string.format(L["arg=%s selected=%s ctx=%s"], tostring(normalizeSearchEventItemID(itemKey)),
			tostring(state and state.auctionLastSellSelectionItemID), tostring(state and state.auctionSearchContext and state.auctionSearchContext.itemID)),
	})
	local ctx = state and state.auctionSearchContext or nil
	if ctx and self:DoesAuctionSearchEventMatchItem(ctx.itemID, itemKey, ctx.scanKeyFields) then
		self:FinishQueuedAuctionRefreshItem(ctx.itemID)
		return
	end
	local selectedItemID = normalizeSearchEventItemID(itemKey) or normalizeItemID(state and state.auctionLastSellSelectionItemID)
	local keyFields = self:ExtractAuctionItemKeyFieldsFromEventArg(itemKey)
	if selectedItemID then
		self:ApplyAuctionSearchResultToDatabase(selectedItemID, keyFields, "item_results_event")
	end
	self:RefreshAuctionHousePanel()
end

function Tradewright:OnAuctionBagUpdate()
	if self:IsAuctionHouseFrameOpen() then
		local panel = self.ui and self.ui.auctionPanel
		-- Also while folded: the rail's cart count follows the bags.
		if panel and panel.dock and self:IsPanelDockShown(panel.dock) then
			self:PrimeAuctionPanelRows()
			self:RefreshAuctionHousePanel()
		end
	end
	if self.RefreshCraftsTabIfVisible then
		self:RefreshCraftsTabIfVisible()
	end
	if self.RefreshProfessionCraftEconomyPanel then
		self:RefreshProfessionCraftEconomyPanel()
	end
end
