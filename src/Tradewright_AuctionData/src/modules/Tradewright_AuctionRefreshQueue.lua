-- The refresh queue: one live AH search at a time for queued items, with timeouts, pause and progress.
local _, Tradewright = ...

local FL = Tradewright.ForeverLogic
local shared = Tradewright.AuctionShared
local normalizeItemID = shared.normalizeItemID

local MIN_SEARCH_DELAY_SEC = 0.05 -- shortest pause between two queued searches
local SEARCH_TIMEOUT_SEC = 1.5 -- a search with no results by then is skipped

function Tradewright:SendAuctionPanelSearchQuery(itemID, scanKeyFields)
	itemID = normalizeItemID(itemID)
	if not itemID or not C_AuctionHouse then
		self:DebugLog("AH", "search skipped", {
			string.format("itemID=%s reason=no_c_auction_house", tostring(itemID)),
		})
		return false
	end
	local itemKey = self:MakeAuctionHouseItemKey(itemID, scanKeyFields)
	if not itemKey then
		self:DebugLog("AH", "search skipped", {
			string.format("itemID=%s reason=no_item_key", tostring(itemID)),
		})
		return false
	end
	local queryFunc = C_AuctionHouse.SendSearchQuery
	local queryApi = "SendSearchQuery"
	if type(queryFunc) ~= "function" and type(C_AuctionHouse.SendSellSearchQuery) == "function" then
		queryFunc = C_AuctionHouse.SendSellSearchQuery
		queryApi = "SendSellSearchQuery"
	end
	if type(queryFunc) ~= "function" then
		self:DebugLog("AH", "search skipped", {
			string.format("itemID=%d reason=no_query_func", itemID),
		})
		return false
	end
	local ok = pcall(queryFunc, itemKey, {}, true)
	if ok ~= true and queryApi ~= "SendSellSearchQuery" and type(C_AuctionHouse.SendSellSearchQuery) == "function" then
		local sellOk = pcall(C_AuctionHouse.SendSellSearchQuery, itemKey, {}, true)
		if sellOk == true then
			ok = true
			queryApi = "SendSellSearchQuery"
		end
	end
	self:DebugLog("AH", "search query", {
		string.format("itemID=%d ok=%s api=%s", itemID, tostring(ok == true), tostring(queryApi)),
	})
	return ok == true
end

-- Listed quantity, else what the last snapshot saw.
local function fetchedQuantity(self, itemID, priceState)
	local quantity = tonumber(priceState.nativeListingQuantity)
	if quantity and quantity > 0 then
		return quantity
	end
	local summary = self:GetItemEconomySummary(itemID, {})
	local snapshot = summary and summary.snapshot
	return snapshot and (tonumber(snapshot.sampleSize) or tonumber(snapshot.quantity))
end

local function logFetchedAuctionPrice(self, itemID, priceState, currentPrice)
	self:DebugLog("AH", "refresh fetched", { string.format("itemID=%d name=%s price=%s qty=%s source=%s", itemID,
		tostring(self:GetItemDisplayName(itemID) or "?"), tostring(currentPrice),
		tostring(fetchedQuantity(self, itemID, priceState) or "?"), tostring(priceState.currentPriceSource or "unknown")) })
end

local function countAuctionPriceSource(state, priceState)
	local counts = state.auctionSourceCounts or { native = 0, snapshot = 0, fallback = 0 }
	state.auctionSourceCounts = counts
	local source = priceState.currentPriceIsNative and "native" or priceState.currentPriceSource == "snapshot" and "snapshot" or "fallback"
	counts[source] = (counts[source] or 0) + 1
end

function Tradewright:FinishQueuedAuctionRefreshItem(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return
	end
	local state = self:GetState()
	local ctx = state.auctionSearchContext
	local scanKeyFields = nil
	if ctx and tonumber(ctx.itemID) == tonumber(itemID) then
		scanKeyFields = ctx.scanKeyFields
		state.auctionSearchContext = nil
	end
	self:MarkAuctionTargetSearched(itemID, scanKeyFields, "queue_finish", Tradewright:Now())
	local priceState = self:ProcessAuctionRefreshItem(itemID, scanKeyFields)
	local currentPrice = tonumber(priceState.currentPrice)
	self:DebugLog("AH", "refresh resolved", {
		string.format("itemID=%d shown=%s source=%s native=%s fallback=%s", itemID, tostring(currentPrice), tostring(priceState.currentPriceSource), tostring(priceState.nativePrice), tostring(priceState.fallbackPrice)),
	})
	if currentPrice and currentPrice > 0 then
		logFetchedAuctionPrice(self, itemID, priceState, currentPrice)
		state.auctionLivePriceByItem = state.auctionLivePriceByItem or {}
		state.auctionLivePriceByItem[itemID] = currentPrice
		countAuctionPriceSource(state, priceState)
	end
	self:UpdateAuctionPanelRowPrice(itemID, priceState)
	state.auctionScanDone = tonumber(state.auctionRefreshIndex) or 0
	state.auctionRefreshIndex = (tonumber(state.auctionRefreshIndex) or 1) + 1
	if (tonumber(state.auctionRefreshIndex) or 1) % 3 == 0 then
		self:RefreshAuctionHousePanel()
	end
	C_Timer.After(tonumber(state.auctionRefreshDelay) or MIN_SEARCH_DELAY_SEC, function()
		Tradewright:ContinueQueuedAuctionRefresh()
	end)
end

function Tradewright:OnAuctionRefreshSearchTimeout(token)
	local state = self:GetState()
	local ctx = state.auctionSearchContext
	if not ctx or tonumber(ctx.token) ~= tonumber(token) then
		return
	end
	self:DebugLog("AH", "search timeout", {
		string.format("itemID=%s token=%s", tostring(ctx.itemID), tostring(token)),
	})
	self:FinishQueuedAuctionRefreshItem(ctx.itemID)
end

function Tradewright:ContinueQueuedAuctionRefresh()
	local state = self:GetState()
	if not state.auctionRefreshRunning or state.auctionSearchContext then
		return
	end
	if self:IsAuctionScanHeld(state) then
		return
	end
	local scanList = state.auctionRefreshScanList or {}
	local index = tonumber(state.auctionRefreshIndex) or 1
	local entry = scanList[index]
	local itemID = entry and normalizeItemID(entry.itemID)
	local scanKeyFields = entry and entry.itemKeyFields or nil
	if not itemID then
		state.auctionRefreshRunning = false
		state.auctionRefreshQueue = {}
		state.auctionRefreshScanList = nil
		state.auctionRefreshIndex = nil
		state.auctionSearchContext = nil
		state.auctionRefreshPaused = false
		state.auctionRefreshPausedForBulk = false
		state.auctionRefreshStartedAt = nil
		self:MarkAuctionQueueScanCompleted()
		local invCrafts = state.auctionInvalidateCraftsAfterRefresh == true
		state.auctionInvalidateCraftsAfterRefresh = false
		if invCrafts and self.InvalidateCraftOpportunityCaches then
			self:InvalidateCraftOpportunityCaches()
			if self.NotifyDashboardUpdate then
				self:NotifyDashboardUpdate(true)
			end
			if self.RefreshCraftsTabIfVisible then
				self:RefreshCraftsTabIfVisible()
			end
		end
		if not state.auctionRoiRunning then
			state.auctionScanMode = "idle"
			state.auctionScanTotal = 0
			state.auctionScanDone = 0
			state.auctionActiveItemID = nil
		end
		self:MaybeStartDeferredAuctionBulk()
		self:RefreshAuctionHousePanel()
		return
	end
	state.auctionActiveItemID = itemID
	self:DebugLog("AH", "refresh step", {
		string.format("itemID=%d index=%d/%d", itemID, index, #scanList),
	})
	self:RecordAuctionTransaction({
		kind = "visible_refresh",
		itemID = itemID,
		quantity = 1,
		source = "queue",
	})
	-- Do not prime Blizzard's sell frame during automatic refresh scans.
	-- On first AH open, especially for commodities, Blizzard can throw internally while
	-- resolving the sell/post pane before its view state is fully initialized.
	-- We rely on explicit search queries here instead; manual sell/bulk-post paths still
	-- use TrySendItemToAuctionSellFrame where appropriate.
	if self:SendAuctionPanelSearchQuery(itemID, scanKeyFields) then
		local token = (tonumber(state.auctionSearchToken) or 0) + 1
		state.auctionSearchToken = token
		state.auctionSearchContext = {
			itemID = itemID,
			scanKeyFields = self:NormalizeAuctionItemKeyFields(scanKeyFields),
			token = token,
			startedAt = GetTime and GetTime() or 0,
		}
		C_Timer.After(SEARCH_TIMEOUT_SEC, function()
			Tradewright:OnAuctionRefreshSearchTimeout(token)
		end)
		return
	end
	self:FinishQueuedAuctionRefreshItem(itemID)
end

function Tradewright:ToggleAuctionRefreshPause()
	local state = self:GetState()
	if state.auctionRefreshRunning ~= true then
		return
	end
	state.auctionRefreshPaused = state.auctionRefreshPaused ~= true
	if state.auctionRefreshPaused == true then
		self:DebugLog("AH", "scan paused", {
			string.format("mode=%s itemID=%s index=%s", tostring(state.auctionScanMode), tostring(state.auctionActiveItemID), tostring(state.auctionRefreshIndex)),
		})
	else
		state.auctionRefreshPausedForBulk = false
		self:DebugLog("AH", "scan resumed", {
			string.format("mode=%s itemID=%s index=%s", tostring(state.auctionScanMode), tostring(state.auctionActiveItemID), tostring(state.auctionRefreshIndex)),
		})
		if state.auctionSearchContext then
			self:RefreshAuctionHousePanel()
			return
		end
		C_Timer.After(MIN_SEARCH_DELAY_SEC, function()
			Tradewright:ContinueQueuedAuctionRefresh()
		end)
	end
	self:RefreshAuctionHousePanel()
end

function Tradewright:RunQueuedAuctionRefresh()
	local state = self:GetState()
	if not self:CanStartFullAuctionSideActions(false) then
		return
	end
	if state.auctionRefreshRunning then
		return
	end
	local queue = state.auctionRefreshQueue or {}
	local scanList = {}
	for key, entry in pairs(queue) do
		if entry == true then
			local id = normalizeItemID(key)
			if id then
				scanList[#scanList + 1] = { itemID = id, itemKeyFields = nil }
			end
		elseif type(entry) == "table" and entry.itemID then
			scanList[#scanList + 1] = {
				itemID = normalizeItemID(entry.itemID),
				itemKeyFields = self:NormalizeAuctionItemKeyFields(entry.itemKeyFields),
				queueOrder = tonumber(entry.queueOrder) or 0,
			}
		end
	end
	if #scanList == 0 then
		return
	end
	table.sort(scanList, function(a, b)
		local ao = tonumber(a.queueOrder) or 0
		local bo = tonumber(b.queueOrder) or 0
		if ao ~= bo then
			return ao < bo
		end
		local ai, bi = tonumber(a.itemID) or 0, tonumber(b.itemID) or 0
		if ai ~= bi then
			return ai < bi
		end
		return FL.SerializeItemKey(a.itemKeyFields, normalizeItemID(a.itemID)) < FL.SerializeItemKey(b.itemKeyFields, normalizeItemID(b.itemID))
	end)
	state.auctionScanMode = tostring(state.auctionPendingPriceScanMode or "price")
	state.auctionPendingPriceScanMode = nil
	state.auctionScanTotal = #scanList
	state.auctionScanDone = 0
	state.auctionLivePriceByItem = state.auctionLivePriceByItem or {}
	state.auctionNativePriceByItem = state.auctionNativePriceByItem or {}
	state.auctionSourceCounts = { native = 0, snapshot = 0, fallback = 0 }
	state.auctionSearchContext = nil
	state.auctionRefreshRunning = true
	state.auctionRefreshPaused = false
	state.auctionRefreshPausedForBulk = false
	local throttleMs = tonumber(self:GetSetting("auction.visibleRefreshThrottleMs", 150)) or 150
	state.auctionRefreshDelay = math.max(MIN_SEARCH_DELAY_SEC, throttleMs / 1000)
	state.auctionRefreshScanList = scanList
	state.auctionRefreshIndex = 1
	state.auctionRefreshStartedAt = GetTime and GetTime() or nil
	self:ContinueQueuedAuctionRefresh()
end

function Tradewright:QueueVisibleAuctionRefresh(itemIDs)
	if not self:CanStartFullAuctionSideActions(false) then
		return
	end
	local targets = {}
	for _, itemID in ipairs(itemIDs or {}) do
		local id = normalizeItemID(itemID)
		if id then
			targets[#targets + 1] = { itemID = id, itemKeyFields = nil }
		end
	end
	self:QueueAuctionScanTargets(targets)
end

function Tradewright:QueueAuctionScanTargets(targets, opts)
	if not self:CanStartFullAuctionSideActions(false) then
		return
	end
	opts = type(opts) == "table" and opts or {}
	local state = self:GetState()
	state.auctionRefreshQueue = state.auctionRefreshQueue or {}
	local queued = state.auctionRefreshQueue
	state.auctionRefreshQueueOrderCounter = tonumber(state.auctionRefreshQueueOrderCounter) or 0
	for _, t in ipairs(targets or {}) do
		local id = normalizeItemID(t and t.itemID)
		if id then
			local fields = self:NormalizeAuctionItemKeyFields(t.itemKeyFields or t.auctionItemKey)
			local k = FL.SerializeItemKey(fields, id)
			if opts.skipSessionSearched ~= true or not self:HasAuctionTargetBeenSearchedThisSession(id, fields) then
				local existing = queued[k]
				if existing then
					existing.itemID = id
					existing.itemKeyFields = fields
				else
					state.auctionRefreshQueueOrderCounter = state.auctionRefreshQueueOrderCounter + 1
					queued[k] = {
						itemID = id,
						itemKeyFields = fields,
						queueOrder = state.auctionRefreshQueueOrderCounter,
					}
				end
			end
		end
	end
	self:RunQueuedAuctionRefresh()
end
