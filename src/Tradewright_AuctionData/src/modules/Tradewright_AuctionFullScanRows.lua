-- Rows of a full scan: classic browse pages, the visible result list, and saving each observation.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local shared = Tradewright.AuctionShared
local formatDurationShort = shared.formatDurationShort
local normalizeItemID = shared.normalizeItemID

local CLASSIC_AH_DUMP_PAGE_SIZE = 50
local CLASSIC_AH_DUMP_QUERY_RETRY_SEC = 0.5
local CLASSIC_AH_DUMP_QUERY_MAX_RETRIES = 40

local CLASSIC_AH_DUMP_NEXT_PAGE_SEC = 0.15

function Tradewright:IsAuctionDumpAhOriginPrice(row)
	if type(row) ~= "table" then
		return false
	end
	local price = tonumber(row.currentPrice or row.marketLow or row.minBuyout or row.price)
	if not price or price <= 0 then
		return false
	end
	if row.currentPriceIsNative == true then
		return true
	end
	local src = tostring(row.currentPriceSource or row.source or "")
	if src == "snapshot" or src == "native" then
		return true
	end
	if src:find("results_live", 1, true) or src:find("replicate", 1, true) or src:find("dump_", 1, true) or src:find("browse", 1, true) then
		return true
	end
	if src:find("fallback:", 1, true) or src:find("fallback", 1, true) then
		return false
	end
	return false
end

function Tradewright:ResolveDumpItemCommodity(itemKey, fallback)
	if C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
		local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, itemKey)
		if ok and status == Enum.ItemCommodityStatus.Commodity then
			return true
		end
		if ok and status == Enum.ItemCommodityStatus.Item then
			return false
		end
	end
	if fallback == true or fallback == false then
		return fallback
	end
	return false
end

--- Persist a dump/replicate observation: always stamp last-updated and session-searched;
--- write snapshot/native price when a usable unit price is present.
--- Ignores the 1-hour auto-scan gate. Timestamps use Tradewright:Now() unless the caller passes a newer value.
function Tradewright:PersistAuctionDumpObservation(observation)
	if type(observation) ~= "table" then
		return false
	end
	local itemID = normalizeItemID(observation.itemID)
	if not itemID then
		return false
	end
	local nowTs = Tradewright:Now()
	local requested = tonumber(observation.seenAt)
	local seenAt = nowTs
	if requested and requested > nowTs then
		seenAt = requested
	end
	local price = tonumber(observation.marketLow or observation.minBuyout or observation.price or observation.currentPrice)
	local sampleSize = math.max(1, tonumber(observation.sampleSize) or 1)
	local source = tostring(observation.source or "dump")
	local keyFields = observation.itemKeyFields
	self:TouchItemAuctionScanTimestamp(itemID, seenAt)
	self:MarkAuctionTargetSearched(itemID, keyFields, source, seenAt)
	if price and price > 0 then
		self:RecordAuctionObservation({
			itemID = itemID,
			isCommodity = observation.isCommodity == true,
			itemKey = observation.itemKey,
			marketLow = price,
			minBuyout = tonumber(observation.minBuyout) or price,
			marketHigh = tonumber(observation.marketHigh),
			sampleSize = sampleSize,
			listingCount = tonumber(observation.listingCount),
			source = source,
			seenAt = seenAt,
		})
		self:UpsertNativeAuctionPrice(itemID, price, source, sampleSize, seenAt)
	end
	return true
end

function Tradewright:CollectVisibleAuctionDumpRows()
	local rows = {}
	local seen = {}
	local function addOrOverlay(row, overlay)
		local itemID = normalizeItemID(row and row.itemID)
		if not itemID then
			return
		end
		row.itemID = itemID
		local existing = seen[itemID]
		if existing then
			if overlay then
				local overlayPrice = tonumber(row.currentPrice)
				if overlayPrice and overlayPrice > 0 then
					existing.currentPrice = overlayPrice
					existing.sampleSize = tonumber(row.sampleSize) or existing.sampleSize
					existing.isCommodity = row.isCommodity
					existing.itemKey = row.itemKey
					existing.itemKeyFields = row.itemKeyFields
					existing.source = row.source
				end
			end
			return
		end
		seen[itemID] = row
		rows[#rows + 1] = row
	end

	local state = self:GetState()
	local sourceRows = self:PrimeAuctionPanelRows()
	if type(sourceRows) ~= "table" then
		sourceRows = state.auctionPanelRows or {}
	end
	for _, row in ipairs(sourceRows or {}) do
		local itemID = normalizeItemID(row and row.itemID)
		if itemID and self:IsAuctionDumpAhOriginPrice(row) then
			addOrOverlay({
				itemID = itemID,
				currentPrice = tonumber(row.currentPrice),
				sampleSize = 1,
				isCommodity = self:ResolveDumpItemCommodity(itemID, true),
				itemKey = tostring(itemID),
				source = "dump_visible",
			}, false)
		end
	end

	if C_AuctionHouse and C_AuctionHouse.GetBrowseResults then
		local results = C_AuctionHouse.GetBrowseResults() or {}
		for _, result in pairs(results) do
			if type(result) == "table" then
				local itemKey = result.itemKey
				local itemID = normalizeItemID(itemKey and itemKey.itemID)
				if itemID then
					local keyFields = self:ExtractAuctionItemKeyFieldsFromEventArg(itemKey)
					addOrOverlay({
						itemID = itemID,
						currentPrice = tonumber(result.minPrice),
						sampleSize = math.max(1, tonumber(result.totalQuantity) or 1),
						isCommodity = self:ResolveDumpItemCommodity(itemKey, false),
						itemKey = tostring(itemID),
						itemKeyFields = keyFields,
						source = "dump_browse",
					}, true)
				end
			end
		end
	end
	return rows
end

function Tradewright:StartClassicFullAuctionDump(existingToken)
	if not self:CanUseClassicAuctionDump() then
		self:PrintMessage(L["A full scan is not possible here."])
		return false
	end
	if not self:IsAuctionHouseFrameOpen() then
		self:PrintMessage(L["Open the auction house before starting a full scan."])
		return false
	end
	local state = self:GetState()
	local cooldownRemaining = self:GetFullAuctionDumpCooldownRemaining()
	if cooldownRemaining > 0 and not existingToken then
		self:PrintMessage(string.format(L["Full scan is on cooldown for %s."], formatDurationShort(cooldownRemaining)))
		self:RefreshAuctionHousePanel()
		return false
	end
	self:StopAuctionScanForDump()
	local token = tonumber(existingToken)
	if not token then
		token = (tonumber(state.auctionDumpToken) or 0) + 1
		state.auctionDumpToken = token
	end
	state.auctionDump = {
		token = token,
		running = true,
		mode = "full",
		classic = true,
		status = "querying",
		startedAt = Tradewright:Now(),
		requestStartedAt = Tradewright:Now(),
		page = 0,
		total = 0,
		done = 0,
		index = 0,
		persistDone = 0,
		persistTotal = 0,
		aggregate = {},
		pageSize = CLASSIC_AH_DUMP_PAGE_SIZE,
		queryRetries = 0,
	}
	self:PrintMessage(L["Full scan started. Keep the auction house open until it ends."])
	self:RefreshAuctionHousePanel()
	self:QueryClassicAuctionDumpPage(token, 0)
	return true
end

function Tradewright:QueryClassicAuctionDumpPage(token, page, retries)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.classic ~= true or dump.running ~= true or tonumber(dump.token) ~= tonumber(token) then
		return
	end
	retries = tonumber(retries) or 0
	if not self:IsAuctionHouseFrameOpen() then
		self:FailFullAuctionDump(L["Auction house closed during the full scan."])
		return
	end
	if type(CanSendAuctionQuery) == "function" and not CanSendAuctionQuery() then
		if retries >= CLASSIC_AH_DUMP_QUERY_MAX_RETRIES then
			self:FailFullAuctionDump(L["Timed out waiting to query auction listings."])
			return
		end
		dump.status = "waiting_query"
		dump.queryRetries = retries + 1
		C_Timer.After(CLASSIC_AH_DUMP_QUERY_RETRY_SEC, function()
			Tradewright:QueryClassicAuctionDumpPage(token, page, retries + 1)
		end)
		return
	end
	dump.status = "querying"
	dump.page = tonumber(page) or 0
	dump.requestStartedAt = Tradewright:Now()
	dump.queryRetries = 0
	local ok = pcall(QueryAuctionItems, "", nil, nil, dump.page, false, nil, false, false)
	if not ok then
		self:FailFullAuctionDump(L["The auction house did not answer. Try the full scan again."])
		return
	end
	self:RefreshAuctionHousePanel()
end

function Tradewright:OnAuctionItemListUpdate()
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.classic ~= true or dump.running ~= true then
		return false
	end
	if dump.status ~= "querying" and dump.status ~= "waiting_query" then
		return false
	end
	local numBatch, totalAuctions = GetNumAuctionItems("list")
	numBatch = tonumber(numBatch) or 0
	totalAuctions = tonumber(totalAuctions) or 0
	dump.total = totalAuctions
	dump.status = "processing"
	dump.seenAt = Tradewright:Now()
	dump.aggregate = dump.aggregate or {}
	local aggregateRow = self.AggregateAuctionRow
	for i = 1, numBatch do
		local _, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
		itemID = normalizeItemID(itemID)
		if not itemID and type(GetAuctionItemLink) == "function" then
			local link = GetAuctionItemLink("list", i)
			if type(link) == "string" then
				itemID = normalizeItemID(link:match("item:(%d+)"))
			end
		end
		aggregateRow(dump.aggregate, itemID, count, buyoutPrice)
	end
	local pageSize = tonumber(dump.pageSize) or CLASSIC_AH_DUMP_PAGE_SIZE
	local page = tonumber(dump.page) or 0
	dump.done = math.min(totalAuctions, (page * pageSize) + numBatch)
	self:RefreshAuctionHousePanel()
	if numBatch >= pageSize and dump.done < totalAuctions then
		C_Timer.After(CLASSIC_AH_DUMP_NEXT_PAGE_SEC, function()
			Tradewright:QueryClassicAuctionDumpPage(dump.token, page + 1)
		end)
		return true
	end
	-- Finished paging: persist aggregates through the shared dump pipeline.
	dump.persistKeys = {}
	for itemID in pairs(dump.aggregate or {}) do
		dump.persistKeys[#dump.persistKeys + 1] = itemID
	end
	table.sort(dump.persistKeys)
	dump.persistIndex = 1
	dump.persistDone = 0
	dump.persistTotal = #dump.persistKeys
	dump.sourceLabel = "classic_full"
	self:PersistFullAuctionDumpChunk(dump.token)
	return true
end
