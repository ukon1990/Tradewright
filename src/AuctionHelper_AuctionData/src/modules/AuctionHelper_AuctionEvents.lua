-- Auction house event handlers: the house opening and closing, search results, posts, sales and bag changes.
local _, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local normalizeItemID = shared.normalizeItemID
local normalizeSearchEventItemID = shared.normalizeSearchEventItemID

local AUTO_SCAN_MAX_AGE_SEC = 60 * 60

function AuctionHelper:OnAuctionHouseAuctionCreated()
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

function AuctionHelper:OnAuctionHouseAuctionSold()
	local state = self:GetState()
	local itemID = normalizeItemID(state and state.auctionActiveItemID)
	if itemID then
		self:RecordAuctionTransaction({
			kind = "sold",
			itemID = itemID,
			quantity = 1,
			source = "auction_event",
		})
	end
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
end

--- Prefer retail AuctionHouseFrame; Forever / classic clients often expose AuctionFrame.
function AuctionHelper:GetAuctionHouseAnchorFrame()
	local ah = _G.AuctionHouseFrame
	if ah then
		return ah
	end
	return _G.AuctionFrame
end

function AuctionHelper:IsAuctionHouseFrameOpen()
	local ah = self:GetAuctionHouseAnchorFrame()
	return ah and ah.IsShown and ah:IsShown() and true or false
end

function AuctionHelper:OnAuctionHouseShow()
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
			panel:Show()
		end
	end
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
	self:RetryPrimeAuctionPanelRows(1)
	if self:CanStartFullAuctionSideActions(false) then
		local state = self:GetState()
		local targets = self:BuildPrioritizedAuctionAutoScanTargets({
			includeVisibleBags = true,
			includeCrafts = true,
			includeAccountInventory = true,
			includeSessionSearched = false,
			requireStaleNonVisible = true,
			freshnessWindowSeconds = AUTO_SCAN_MAX_AGE_SEC,
		})
		if #targets > 0 then
			state.auctionPendingPriceScanMode = "mixed"
			state.auctionInvalidateCraftsAfterRefresh = true
			state.auctionRefreshQueue = {}
			state.auctionRefreshQueueOrderCounter = 0
			self:QueueAuctionScanTargets(targets, { skipSessionSearched = true })
		end
		self:StartAuctionRoiEnrichment(self:BuildAuctionVisibleItemIDs())
	end
end

function AuctionHelper:OnAuctionHouseClosed()
	local state = self:GetState()
	if state.auctionDump and state.auctionDump.running == true then
		state.auctionDump.running = false
		state.auctionDump.finishedAt = AuctionHelper:Now()
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
	if self.ui and self.ui.auctionPanel then
		self.ui.auctionPanel:Hide()
	end
end

function AuctionHelper:OnAuctionHouseBrowseResultsUpdated()
	local state = self:GetState()
	self:DebugLog("AH", "event browse results", {
		string.format("pending=%s", tostring(state and state.auctionPendingBrowseSearch and state.auctionPendingBrowseSearch.itemID)),
	})
	if self:TrySelectPendingAuctionBrowseResult() then
		C_Timer.After(0, function()
			AuctionHelper:TrySelectPendingAuctionBrowseResult()
		end)
	end
	self:SaveBrowseResultsToScanEntries()
	self:RefreshAuctionHousePanel()
end

function AuctionHelper:OnCommoditySearchResultsUpdated(itemID)
	local state = self:GetState()
	self:DebugLog("AH", "event commodity results", {
		string.format("arg=%s selected=%s ctx=%s", tostring(normalizeSearchEventItemID(itemID)),
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

function AuctionHelper:OnItemSearchResultsUpdated(itemKey)
	local state = self:GetState()
	self:DebugLog("AH", "event item results", {
		string.format("arg=%s selected=%s ctx=%s", tostring(normalizeSearchEventItemID(itemKey)),
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

function AuctionHelper:OnAuctionBagUpdate()
	if self:IsAuctionHouseFrameOpen() then
		local panel = self.ui and self.ui.auctionPanel
		if panel and panel.IsShown and panel:IsShown() then
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
