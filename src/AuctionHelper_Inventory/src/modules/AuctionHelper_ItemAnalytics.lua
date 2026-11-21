local _, AuctionHelper = ...

-- Item history in SavedVariables, `db.itemHistory[tostring(itemID)]`, one bucket per hour keyed by the
-- hour's start (Unix time). Bucket fields use one-letter keys to keep the file small:
--   market / crafting buckets (copper per unit):
--     c = count of observations, s = sum of the values, l = last value,
--     n = min (lowest value), x = max (highest value), o = source label of the last observation
--   quantity buckets: c = { [characterKey] = row }, one row per character:
--     b = bags, k = bank, w = warband bank, t = total, a = when it was seen (Unix time)
-- Older saved data used the long names (count, sum, last, min, max, source, perChar, bags, bank,
-- warband, total, at); readers accept both and writers convert to the short keys.
-- `db.walletHistory` keeps the long names (count, sum, last, min, max) and is not compacted.

local RANGE_TO_SECONDS = {
	["24h"] = 24 * 60 * 60,
	["7d"] = 7 * 24 * 60 * 60,
	["30d"] = 30 * 24 * 60 * 60,
	["90d"] = 90 * 24 * 60 * 60,
	["1y"] = 365 * 24 * 60 * 60,
}

local function trimHistoryBuckets(bucketMap, keepAfter)
	if type(bucketMap) ~= "table" then
		return
	end
	for key in pairs(bucketMap) do
		local n = tonumber(key)
		if n and n < keepAfter then
			bucketMap[key] = nil
		end
	end
end

-- A bucket's average is sum / count; a bucket without observations falls back to its last value.
local function sortedBucketList(bucketMap, cutoff)
	local list = {}
	for key, bucket in pairs(bucketMap or {}) do
		local at = tonumber(key)
		if at and at > 0 and (not cutoff or at >= cutoff) then
			local count = tonumber(bucket.c or bucket.count) or 0
			local sum = tonumber(bucket.s or bucket.sum) or 0
			local last = tonumber(bucket.l or bucket.last)
			list[#list + 1] = {
				at = at,
				last = last,
				avg = count > 0 and (sum / count) or last,
				min = tonumber(bucket.n or bucket.min),
				max = tonumber(bucket.x or bucket.max),
				count = count,
				source = bucket.o or bucket.source,
			}
		end
	end
	table.sort(list, function(left, right)
		return left.at < right.at
	end)
	return list
end

local function quantityRowValue(row, shortKey, longKey)
	return tonumber(row and (row[shortKey] or row[longKey])) or 0
end

function AuctionHelper:GetItemHistoryRetentionSeconds()
	local settings = self.db and self.db.settings and self.db.settings.inventory or nil
	local days = tonumber(settings and settings.historyRetentionDays) or 30
	days = math.max(1, math.floor(days))
	return days * 24 * 60 * 60
end

-- Over the hour buckets of a range: average of the bucket averages, the latest last value, and
-- change = latest minus the first bucket's average (nil with fewer than two buckets).
local function summarizeSeries(list)
	local total = 0
	local count = 0
	local latest = nil
	local first = nil
	for _, point in ipairs(list or {}) do
		local value = tonumber(point.avg or point.last)
		if value and value > 0 then
			total = total + value
			count = count + 1
			latest = point.last or value
			if not first then
				first = value
			end
		end
	end
	return {
		count = count,
		latest = latest,
		average = count > 0 and (total / count) or nil,
		change = (count > 1 and latest and first) and (latest - first) or nil,
	}
end

local function isCharacterSelectionEmpty(selection)
	return type(selection) ~= "table" or next(selection) == nil
end

-- No selection (nil or empty) means every character.
local function isCharacterSelected(selection, characterKey)
	if isCharacterSelectionEmpty(selection) then
		return true
	end
	return selection[characterKey] == true
end

--- itemID -> quality rank from scanned recipe quality variants (fallback when item link has no tier).
function AuctionHelper:BuildOutputItemQualityRankIndex(selectedCharacters)
	self:InitDB()
	local index = {}
	for characterKey, characterData in pairs(self.db.characters or {}) do
		if isCharacterSelected(selectedCharacters, characterKey) then
			for _, professionData in pairs(characterData.professions or {}) do
				for _, recipeData in pairs(professionData.recipes or {}) do
					local outputs = recipeData.outputs
					if outputs then
						local variants = outputs.qualityVariants
						if type(variants) == "table" then
							for i, variant in ipairs(variants) do
								local vid = tonumber(variant.itemID)
								if vid and not index[vid] then
									index[vid] = tonumber(variant.qualityIndex) or i
								end
							end
						end
						local pid = tonumber(self:RecipeOutputsPrimaryItemId(outputs))
						if pid and not index[pid] then
							local matched = nil
							if type(variants) == "table" then
								for _, variant in ipairs(variants) do
									if tonumber(variant.itemID) == pid then
										matched = tonumber(variant.qualityIndex)
										break
									end
								end
							end
							index[pid] = matched or 1
						end
					end
				end
			end
		end
	end
	return index
end

function AuctionHelper:GetItemCraftQualityRank(itemID, selectedCharacters, rankIndex)
	self:InitDB()
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	if type(rankIndex) == "table" then
		return rankIndex[itemID]
	end

	for characterKey, characterData in pairs(self.db.characters or {}) do
		if isCharacterSelected(selectedCharacters, characterKey) then
			for _, professionData in pairs(characterData.professions or {}) do
				for _, recipeData in pairs(professionData.recipes or {}) do
					local outputs = recipeData.outputs
					if outputs then
						local variants = outputs.qualityVariants
						if type(variants) == "table" then
							for i, variant in ipairs(variants) do
								if tonumber(variant.itemID) == itemID then
									return tonumber(variant.qualityIndex) or i
								end
							end
						end
						-- A primary output that is not among the quality variants has no tiers: rank 1.
						if tonumber(self:RecipeOutputsPrimaryItemId(outputs)) == itemID then
							return 1
						end
					end
				end
			end
		end
	end

	return nil
end

--- Tier shown next to inventory icon: prefer live item link (matches tooltip), then scan, then 1.
function AuctionHelper:GetItemDisplayProfessionQualityRank(itemID, selectedCharacters, rankIndex)
	itemID = tonumber(itemID)
	if not itemID then
		return 1
	end
	if self.IS_SUPPORTED and C_Item and C_Item.GetItemInfo then
		local _, link = C_Item.GetItemInfo(itemID)
		local fromLink = link and self:ParseProfessionQualityTierFromItemLink(link) or nil
		if fromLink and fromLink >= 1 then
			return fromLink
		end
	end
	local fromMap = type(rankIndex) == "table" and rankIndex[itemID] or nil
	local fromScan = fromMap or self:GetItemCraftQualityRank(itemID, selectedCharacters, rankIndex)
	local n = tonumber(fromScan)
	if n and n >= 1 then
		return n
	end
	return 1
end

function AuctionHelper:GetInventoryMetricRangeOptions()
	return {
		{ value = "all", label = "All time" },
		{ value = "24h", label = "24 hours" },
		{ value = "7d", label = "7 days" },
		{ value = "30d", label = "30 days" },
		{ value = "90d", label = "90 days" },
		{ value = "1y", label = "1 year" },
	}
end

-- "Last 30 days" / "All time": the range as the player reads it, for labels and summaries.
function AuctionHelper:GetRangeLabel(rangeKey)
	for _, option in ipairs(self:GetInventoryMetricRangeOptions()) do
		if option.value == rangeKey then
			return option.value == "all" and option.label or ("Last " .. option.label)
		end
	end
	return tostring(rangeKey or "")
end

function AuctionHelper:GetInventoryMetricRange()
	return self:GetSetting("inventory.metricRange", "30d")
end

function AuctionHelper:SetInventoryMetricRange(value)
	local chosen = "30d"
	for _, option in ipairs(self:GetInventoryMetricRangeOptions()) do
		if option.value == value then
			chosen = value
			break
		end
	end
	self:SetSetting("inventory.metricRange", chosen)
end

function AuctionHelper:GetHistoryRangeCutoff(rangeKey)
	if not rangeKey or rangeKey == "all" then
		return nil
	end
	local seconds = RANGE_TO_SECONDS[rangeKey]
	if not seconds then
		return nil
	end
	return time() - seconds
end

function AuctionHelper:EnsureItemHistory(itemID)
	self:InitDB()
	itemID = tonumber(itemID)
	if not itemID or itemID <= 0 then
		return nil
	end
	local history = self.db.itemHistory
	local key = tostring(itemID)
	local row = history[key]
	if not row then
		row = {
			market = { buckets = {}, latest = nil },
			crafting = { buckets = {}, latest = nil },
			quantity = { buckets = {}, latest = nil },
		}
		history[key] = row
	else
		row.quantity = row.quantity or { buckets = {}, latest = nil }
	end
	return row
end

-- Drops buckets older than the retention setting, rewrites the rest with the short keys (legend at
-- the top of the file) and drops empty buckets.
function AuctionHelper:CompactItemHistoryStorage()
	local cutoff = time() - self:GetItemHistoryRetentionSeconds()
	for itemKey, row in pairs(self.db.itemHistory or {}) do
		if type(row) == "table" then
			for _, historyKey in ipairs({ "market", "crafting" }) do
				local store = row[historyKey]
				if type(store) == "table" then
					local newBuckets = {}
					for bucketKey, bucket in pairs(store.buckets or {}) do
						local at = tonumber(bucketKey)
						if at and at >= cutoff and type(bucket) == "table" then
							local compact = {
								c = tonumber(bucket.c or bucket.count) or 0,
								s = tonumber(bucket.s or bucket.sum) or 0,
								l = tonumber(bucket.l or bucket.last),
								n = tonumber(bucket.n or bucket.min),
								x = tonumber(bucket.x or bucket.max),
								o = bucket.o or bucket.source,
							}
							if compact.c > 0 or compact.l then
								newBuckets[tostring(at)] = compact
							end
						end
					end
					store.buckets = newBuckets
				end
			end
			local quantity = row.quantity
			if type(quantity) == "table" then
				local newBuckets = {}
				for bucketKey, bucket in pairs(quantity.buckets or {}) do
					local at = tonumber(bucketKey)
					if at and at >= cutoff and type(bucket) == "table" then
						local compactBucket = { c = {} }
						local perChar = bucket.c or bucket.perChar or {}
						for characterKey, qtyRow in pairs(perChar) do
							local compactRow = {
								b = quantityRowValue(qtyRow, "b", "bags"),
								k = quantityRowValue(qtyRow, "k", "bank"),
								w = quantityRowValue(qtyRow, "w", "warband"),
								t = quantityRowValue(qtyRow, "t", "total"),
								a = tonumber(qtyRow.a or qtyRow.at) or at,
							}
							compactBucket.c[characterKey] = compactRow
						end
						if next(compactBucket.c) ~= nil then
							newBuckets[tostring(at)] = compactBucket
						end
					end
				end
				quantity.buckets = newBuckets
				quantity.latestByChar = quantity.latestByChar or {}
			end
			if next(row) == nil then
				self.db.itemHistory[itemKey] = nil
			end
		else
			self.db.itemHistory[itemKey] = nil
		end
	end
end

-- The same value from the same source as the latest one is skipped: every inventory redraw records
-- the current price again, so only changes are counted.
local function historyObservationIsRedundant(store, value, source)
	local latest = store and store.latest
	if not latest then
		return false
	end
	if tonumber(latest.value) ~= tonumber(value) then
		return false
	end
	return tostring(latest.source or "") == tostring(source or "")
end

function AuctionHelper:RecordItemHistoryObservation(itemID, historyKey, value, source, observedAt)
	local n = tonumber(value)
	if not n or n <= 0 then
		return
	end
	local itemHistory = self:EnsureItemHistory(itemID)
	if not itemHistory or type(itemHistory[historyKey]) ~= "table" then
		return
	end
	local store = itemHistory[historyKey]
	if historyObservationIsRedundant(store, n, source) then
		return
	end
	store.buckets = store.buckets or {}
	observedAt = tonumber(observedAt) or time()
	local bucketAt = observedAt - (observedAt % 3600)
	local bucket = store.buckets[tostring(bucketAt)] or {}
	bucket.c = (tonumber(bucket.c or bucket.count) or 0) + 1
	bucket.s = (tonumber(bucket.s or bucket.sum) or 0) + n
	bucket.l = n
	bucket.n = bucket.n and math.min(bucket.n, n) or bucket.min and math.min(bucket.min, n) or n
	bucket.x = bucket.x and math.max(bucket.x, n) or bucket.max and math.max(bucket.max, n) or n
	bucket.o = source or bucket.o or bucket.source
	bucket.count, bucket.sum, bucket.last, bucket.min, bucket.max, bucket.source = nil, nil, nil, nil, nil, nil
	store.buckets[tostring(bucketAt)] = bucket
	store.latest = { value = n, at = observedAt, source = source }
	trimHistoryBuckets(store.buckets, time() - self:GetItemHistoryRetentionSeconds())
end

function AuctionHelper:GetItemHistorySeries(itemID, historyKey, rangeKey)
	self:InitDB()
	local itemHistory = self.db.itemHistory and self.db.itemHistory[tostring(itemID)] or nil
	if not itemHistory or type(itemHistory[historyKey]) ~= "table" then
		return {}
	end
	return sortedBucketList(itemHistory[historyKey].buckets, self:GetHistoryRangeCutoff(rangeKey))
end

function AuctionHelper:GetItemHistoryStats(itemID, historyKey, rangeKey)
	return summarizeSeries(self:GetItemHistorySeries(itemID, historyKey, rangeKey))
end

function AuctionHelper:GetItemHistoryStatsMemo(itemID, historyKey, rangeKey, memoTbl)
	if not memoTbl then
		return self:GetItemHistoryStats(itemID, historyKey, rangeKey)
	end
	local key = tostring(itemID) .. "\0" .. tostring(historyKey) .. "\0" .. tostring(rangeKey or "all")
	local hit = memoTbl[key]
	if hit then
		return hit
	end
	hit = self:GetItemHistoryStats(itemID, historyKey, rangeKey)
	memoTbl[key] = hit
	return hit
end

function AuctionHelper:ItemHistoryBucketsToGraphSeries(itemID, historyKey, rangeKey)
	local raw = self:GetItemHistorySeries(itemID, historyKey, rangeKey)
	local out = {}
	for _, point in ipairs(raw) do
		local v = tonumber(point.avg or point.last)
		if v then
			out[#out + 1] = {
				at = point.at,
				value = v,
				meta = {
					count = point.count,
					min = point.min,
					max = point.max,
					source = point.source,
				},
			}
		end
	end
	return out
end

function AuctionHelper:OnInventorySnapshotWritten(characterData)
	self:RecordWalletObservationFromCharacterData(characterData)
	self:RecordQuantityObservationsFromSnapshot(characterData)
end

-- Shared with the history files split out of this one (wallet, quantity, item detail).
AuctionHelper.ItemHistory = {
	RANGE_TO_SECONDS = RANGE_TO_SECONDS,
	trimHistoryBuckets = trimHistoryBuckets,
	quantityRowValue = quantityRowValue,
	isCharacterSelected = isCharacterSelected,
}
