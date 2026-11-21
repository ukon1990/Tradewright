-- The saved auction database: setup, snapshot rows, observations, hourly history and its trim, and transactions.
local _, AuctionHelper = ...

local FL = AuctionHelper.ForeverLogic
local MarketLogic = AuctionHelper.MarketLogic
local shared = AuctionHelper.AuctionShared
local normalizeItemID = shared.normalizeItemID
local shallowCopy = shared.shallowCopy

local AUCTION_TX_MAX_EVENTS = 3000

local function auctionHistoryBucketCount(bucket)
	return tonumber(bucket and (bucket.n or bucket.count)) or 0
end

local function auctionHistoryBucketWeightedQty(bucket)
	return tonumber(bucket and (bucket.q or bucket.weightedQty)) or 0
end

local function auctionHistoryBucketWeightedSum(bucket)
	return tonumber(bucket and (bucket.w or bucket.weightedSum)) or 0
end

function AuctionHelper:InitAuctionDB()
	local db = self.db or self:BuildMergedRuntimeDB(self.baseDb or {}, self.professionsDb or {}, self.inventoryDb or {}, self.auctionStorageDb or {})
	if type(db) ~= "table" then
		return nil
	end
	self.db = self.db or db
	self.db.auction = self.db.auction or {}
	local auction = self.db.auction
	auction.snapshot = auction.snapshot or {}
	auction.snapshot.commodities = auction.snapshot.commodities or {}
	auction.snapshot.items = auction.snapshot.items or {}
	auction.history = auction.history or {}
	auction.history.hourly = auction.history.hourly or {}
	auction.history.daily = auction.history.daily or {}
	auction.transactions = auction.transactions or {}
	auction.transactions.events = auction.transactions.events or {}
	auction.indexes = auction.indexes or {}
	auction.indexes.byItemID = auction.indexes.byItemID or {}
	auction.indexes.byBagItem = auction.indexes.byBagItem or {}
	auction.indexes.byRecipeOutput = auction.indexes.byRecipeOutput or {}
	auction.indexes.byCharacterAuction = auction.indexes.byCharacterAuction or {}
	auction.rules = auction.rules or {}
	auction.rules.byItemID = auction.rules.byItemID or {}
	auction.itemLastScanAt = auction.itemLastScanAt or {}
	auction.itemDepositPerUnit = auction.itemDepositPerUnit or {}
	-- Version 2: item entries saved under a table address ("…:table: 0x…") are moved to real item keys.
	if (tonumber(auction.storageKeyVersion) or 1) < 2 and self.ForeverLogic and self.ForeverLogic.RepairAuctionStorageKeys then
		local moved = self.ForeverLogic.RepairAuctionStorageKeys(auction, function(itemID)
			return self:BuildAuctionStorageKey(itemID, "item")
		end)
		auction.storageKeyVersion = 2
		if moved > 0 then
			self:DebugLog("AH", "repaired auction storage keys", { string.format("moved=%d", moved) })
		end
	end
	return auction
end

--- Long-field view of a saved snapshot row; nil when the row has no price.
function AuctionHelper:NormalizeAuctionSnapshotEntry(entry)
	local fields = MarketLogic.NormalizeMarketSnapshotFields(entry)
	if not fields then
		return nil
	end
	return {
		seenAt = fields.seenAt,
		source = fields.source and tostring(fields.source) or nil,
		marketLow = fields.price,
		minBuyout = fields.price,
		marketHigh = fields.marketHigh,
		sampleSize = fields.sampleSize,
		listingCount = fields.listingCount,
	}
end

--- The saved snapshot row (`t/p/s` plus `q/n/h` when above zero) for an observation or an older row.
function AuctionHelper:BuildCompactAuctionSnapshotEntry(observation)
	local fields = MarketLogic.NormalizeMarketSnapshotFields(observation)
	if not fields then
		return nil
	end
	local entry = {
		t = fields.seenAt or AuctionHelper:Now(),
		p = fields.price,
		s = tostring(fields.source or "unknown"),
	}
	if fields.sampleSize > 0 then
		entry.q = fields.sampleSize
	end
	if fields.listingCount > 0 then
		entry.n = math.floor(fields.listingCount)
	end
	if fields.marketHigh and fields.marketHigh > 0 then
		entry.h = fields.marketHigh
	end
	return entry
end

function AuctionHelper:CompactAuctionStorageData()
	local auction = self:InitAuctionDB()
	if not auction then
		return
	end
	local function compactSnapshotRoot(root)
		for storageKey, entry in pairs(root or {}) do
			local compact = self:BuildCompactAuctionSnapshotEntry(entry)
			if compact then
				root[storageKey] = compact
			else
				root[storageKey] = nil
			end
		end
	end
	compactSnapshotRoot(auction.snapshot and auction.snapshot.commodities or nil)
	compactSnapshotRoot(auction.snapshot and auction.snapshot.items or nil)
	auction.history = auction.history or {}
	self:RollupDailyAuctionHistory()
	self:TrimAuctionHistory()
end

function AuctionHelper:GetAuctionRegionKey()
	return tostring(GetCurrentRegion and GetCurrentRegion() or "unknown")
end

function AuctionHelper:GetAuctionConnectedRealmID()
	local id = tonumber(GetNormalizedRealmID and GetNormalizedRealmID() or nil)
	if id and id > 0 then
		return id
	end
	return tonumber(GetRealmID and GetRealmID() or 0) or 0
end

function AuctionHelper:BuildAuctionStorageKey(itemID, marketScope, itemKey)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return nil
	end
	local region = self:GetAuctionRegionKey()
	if marketScope == "commodity" then
		return string.format("%s:%d", region, itemID)
	end
	local connectedRealmID = self:GetAuctionConnectedRealmID()
	local keyPart = FL.SerializeItemKey(itemKey, itemID)
	return string.format("%s:%d:%s", region, connectedRealmID, keyPart)
end

local function getBucketTable(root, storageKey)
	if type(root) ~= "table" or not storageKey then
		return nil
	end
	root[storageKey] = root[storageKey] or {}
	return root[storageKey]
end

function AuctionHelper:RecordAuctionObservation(observation)
	if type(observation) ~= "table" then
		return false
	end
	local auction = self:InitAuctionDB()
	local state = self:GetState()
	state.auctionDataRevision = (state.auctionDataRevision or 0) + 1
	local itemID = normalizeItemID(observation.itemID)
	if not itemID then
		return false
	end
	local marketScope = observation.isCommodity and "commodity" or "item"
	local storageKey = self:BuildAuctionStorageKey(itemID, marketScope, observation.itemKey)
	if not storageKey then
		return false
	end

	local seenAt = tonumber(observation.seenAt) or AuctionHelper:Now()
	local entry = self:BuildCompactAuctionSnapshotEntry(observation)
	if not entry then
		return false
	end

	local snapRoot = marketScope == "commodity" and auction.snapshot.commodities or auction.snapshot.items
	snapRoot[storageKey] = entry

	auction.indexes.byItemID[tostring(itemID)] = auction.indexes.byItemID[tostring(itemID)] or {}
	auction.indexes.byItemID[tostring(itemID)][storageKey] = true

	self:UpdateAuctionHistoryFromObservation(storageKey, entry)
	self:TouchItemAuctionScanTimestamp(itemID, seenAt)
	return true
end

function AuctionHelper:UpdateAuctionHistoryFromObservation(storageKey, entry)
	local auction = self:InitAuctionDB()
	if not storageKey or type(entry) ~= "table" then
		return
	end
	local fields = MarketLogic.NormalizeMarketSnapshotFields(entry)
	local seenAt = fields and fields.seenAt or AuctionHelper:Now()
	local hourBucketTs = math.floor(seenAt / 3600) * 3600
	local itemHistory = getBucketTable(auction.history.hourly, storageKey)
	if not itemHistory then
		return
	end
	local bucketKey = tostring(hourBucketTs)
	local bucket = itemHistory[bucketKey] or {}
	if fields then
		local price = fields.price
		local qty = math.max(1, fields.sampleSize)
		bucket.m = bucket.m and math.min(bucket.m, price) or bucket.min and math.min(bucket.min, price) or price
		bucket.x = bucket.x and math.max(bucket.x, price) or bucket.max and math.max(bucket.max, price) or price
		bucket.l = price
		bucket.n = auctionHistoryBucketCount(bucket) + 1
		bucket.q = auctionHistoryBucketWeightedQty(bucket) + qty
		bucket.w = auctionHistoryBucketWeightedSum(bucket) + (price * qty)
		bucket.t = seenAt
		bucket.min = nil
		bucket.max = nil
		bucket.last = nil
		bucket.count = nil
		bucket.weightedQty = nil
		bucket.weightedSum = nil
		bucket.avg = nil
		bucket.lastSeenAt = nil
		itemHistory[bucketKey] = bucket
	end
	self:TrimAuctionHistory()
end

function AuctionHelper:TrimAuctionHistory()
	-- Called per observation; walking all history each time made full dumps quadratic.
	local state = self:GetState()
	if state.auctionHistoryTrimmedAt and AuctionHelper:Now() - state.auctionHistoryTrimmedAt < 600 then
		return
	end
	state.auctionHistoryTrimmedAt = AuctionHelper:Now()
	local auction = self:InitAuctionDB()
	local settings = self.db and self.db.settings and self.db.settings.auction or nil
	local retentionDays = tonumber(settings and settings.historyRetentionDays) or 30
	retentionDays = math.max(1, retentionDays)
	local cutoffTs = AuctionHelper:Now() - retentionDays * 24 * 3600
	for storageKey, historyByHour in pairs(auction.history.hourly or {}) do
		for hourTs in pairs(historyByHour) do
			if tonumber(hourTs) and tonumber(hourTs) < cutoffTs then
				historyByHour[hourTs] = nil
			else
				local bucket = historyByHour[hourTs]
				if type(bucket) == "table" then
					local compact = {
						n = auctionHistoryBucketCount(bucket),
						q = auctionHistoryBucketWeightedQty(bucket),
						w = auctionHistoryBucketWeightedSum(bucket),
						l = tonumber(bucket.l or bucket.last),
						m = tonumber(bucket.m or bucket.min),
						x = tonumber(bucket.x or bucket.max),
						t = tonumber(bucket.t or bucket.lastSeenAt),
					}
					if compact.n <= 0 and compact.q <= 0 and not compact.l then
						historyByHour[hourTs] = nil
					else
						historyByHour[hourTs] = compact
					end
				end
			end
		end
		if next(historyByHour) == nil then
			auction.history.hourly[storageKey] = nil
		end
	end
	local function pruneSnapshotRoot(root)
		for storageKey, entry in pairs(root or {}) do
			local fields = MarketLogic.NormalizeMarketSnapshotFields(entry)
			if not fields or not fields.seenAt or fields.seenAt < cutoffTs then
				root[storageKey] = nil
			else
				root[storageKey] = self:BuildCompactAuctionSnapshotEntry(entry)
			end
		end
	end
	pruneSnapshotRoot(auction.snapshot and auction.snapshot.commodities or nil)
	pruneSnapshotRoot(auction.snapshot and auction.snapshot.items or nil)
	for itemKey, storageKeys in pairs(auction.indexes.byItemID or {}) do
		for storageKey in pairs(storageKeys or {}) do
			if not (auction.snapshot.commodities[storageKey] or auction.snapshot.items[storageKey] or auction.history.hourly[storageKey]) then
				storageKeys[storageKey] = nil
			end
		end
		if next(storageKeys) == nil then
			auction.indexes.byItemID[itemKey] = nil
		end
	end
end

--- Per-hour aggregated AH sample quantity (`weightedQty` in history buckets) for graph overlays.
--- Uses the same time range cutoff as item detail graphs (`GetHistoryRangeCutoff` from ItemAnalytics).
function AuctionHelper:GetAuctionHistoryQuantitySeriesForItem(itemID, rangeKey)
	itemID = tonumber(itemID)
	if not itemID then
		return {}
	end
	local auction = self:InitAuctionDB()
	local byItem = auction.indexes and auction.indexes.byItemID and auction.indexes.byItemID[tostring(itemID)]
	if not byItem or type(byItem) ~= "table" then
		return {}
	end
	local cutoff = type(self.GetHistoryRangeCutoff) == "function" and self:GetHistoryRangeCutoff(rangeKey) or nil
	local merge = {}
	for storageKey in pairs(byItem) do
		local hist = auction.history and auction.history.hourly and auction.history.hourly[storageKey]
		if type(hist) == "table" then
			for hourKey, bucket in pairs(hist) do
				local at = tonumber(hourKey)
				if at and at > 0 and (not cutoff or at >= cutoff) and type(bucket) == "table" then
					local weightedQty = auctionHistoryBucketWeightedQty(bucket)
					local sampleCount = auctionHistoryBucketCount(bucket)
					if weightedQty > 0 or sampleCount > 0 then
						local hourTotals = merge[at] or { weightedQty = 0, obsCount = 0 }
						hourTotals.weightedQty = hourTotals.weightedQty + weightedQty
						hourTotals.obsCount = hourTotals.obsCount + sampleCount
						merge[at] = hourTotals
					end
				end
			end
		end
	end
	local list = {}
	for at, hourTotals in pairs(merge) do
		list[#list + 1] = {
			at = at,
			value = hourTotals.weightedQty,
			meta = {
				ahHistory = true,
				sampleCount = hourTotals.obsCount,
			},
		}
	end
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	return list
end

function AuctionHelper:RecordAuctionTransaction(event)
	if type(event) ~= "table" then
		return false
	end
	local auction = self:InitAuctionDB()
	local kind = tostring(event.kind or "unknown")
	local entry = shallowCopy(event)
	entry.kind = kind
	entry.ts = tonumber(event.ts) or AuctionHelper:Now()
	entry.itemID = normalizeItemID(event.itemID)
	entry.characterKey = event.characterKey and tostring(event.characterKey) or self:GetCharacterKey()
	entry.quantity = math.max(0, tonumber(event.quantity) or 0)
	entry.unitCopper = tonumber(event.unitCopper)
	entry.totalCopper = tonumber(event.totalCopper)
	entry.source = tostring(event.source or "auction")
	table.insert(auction.transactions.events, entry)
	while #auction.transactions.events > AUCTION_TX_MAX_EVENTS do
		table.remove(auction.transactions.events, 1)
	end
	local charIdx = auction.indexes.byCharacterAuction
	charIdx[entry.characterKey] = charIdx[entry.characterKey] or {}
	table.insert(charIdx[entry.characterKey], {
		ts = entry.ts,
		itemID = entry.itemID,
		kind = entry.kind,
		quantity = entry.quantity,
		unitCopper = entry.unitCopper,
	})
	return true
end

function AuctionHelper:GetAuctionSnapshot(itemKey, marketScope)
	local auction = self:InitAuctionDB()
	if not itemKey then
		return nil
	end
	local id = normalizeItemID(itemKey)
	local storageKey
	if type(itemKey) == "string" and string.find(itemKey, ":", 1, true) then
		storageKey = itemKey
	else
		storageKey = self:BuildAuctionStorageKey(id, marketScope == "commodity" and "commodity" or "item")
	end
	if not storageKey then
		return nil
	end
	local snap = auction.snapshot.commodities[storageKey] or auction.snapshot.items[storageKey]
	return snap and self:NormalizeAuctionSnapshotEntry(snap) or nil
end
