local _, AuctionHelper = ...

-- Item quantity history: per-character bag, bank and warband counts per hour, recorded from inventory snapshots.

local ItemHistory = AuctionHelper.ItemHistory
local trimHistoryBuckets = ItemHistory.trimHistoryBuckets
local quantityRowValue = ItemHistory.quantityRowValue
local isCharacterSelected = ItemHistory.isCharacterSelected

--- counts: { bags, bank, warband, total } for one character, e.g. an inventory snapshot entry.
function AuctionHelper:RecordItemQuantityObservation(itemID, characterKey, counts, observedAt)
	itemID = tonumber(itemID)
	characterKey = characterKey and tostring(characterKey) or nil
	if not itemID or itemID <= 0 or not characterKey or characterKey == "" then
		return
	end
	local itemHistory = self:EnsureItemHistory(itemID)
	if not itemHistory or type(itemHistory.quantity) ~= "table" then
		return
	end
	local store = itemHistory.quantity
	store.buckets = store.buckets or {}
	store.latestByChar = store.latestByChar or {}
	observedAt = tonumber(observedAt) or time()
	local currentRow = {
		b = tonumber(counts.bags) or 0,
		k = tonumber(counts.bank) or 0,
		w = tonumber(counts.warband) or 0,
		t = tonumber(counts.total) or 0,
		a = observedAt,
	}
	-- Unchanged counts only move the "latest" markers; a bucket is written only when something changed.
	local lastRow = store.latestByChar[characterKey]
	if type(lastRow) == "table"
		and quantityRowValue(lastRow, "b", "bags") == currentRow.b
		and quantityRowValue(lastRow, "k", "bank") == currentRow.k
		and quantityRowValue(lastRow, "w", "warband") == currentRow.w
		and quantityRowValue(lastRow, "t", "total") == currentRow.t then
		store.latest = { value = currentRow.t, at = observedAt, characterKey = characterKey }
		store.latestByChar[characterKey] = currentRow
		return
	end
	local bucketAt = observedAt - (observedAt % 3600)
	local bucket = store.buckets[tostring(bucketAt)] or { c = {} }
	bucket.c = bucket.c or bucket.perChar or {}
	bucket.c[characterKey] = currentRow
	bucket.perChar = nil
	store.buckets[tostring(bucketAt)] = bucket
	store.latest = { value = currentRow.t, at = observedAt, characterKey = characterKey }
	store.latestByChar[characterKey] = currentRow
	trimHistoryBuckets(store.buckets, time() - self:GetItemHistoryRetentionSeconds())
end

local function sumQuantityBucket(bucket, selectedCharacters)
	local bags, bank, warband, total, n = 0, 0, 0, 0, 0
	local perChar = type(bucket) == "table" and (bucket.c or bucket.perChar) or nil
	if type(perChar) ~= "table" then
		return 0, { bags = 0, bank = 0, warband = 0, sampleCount = 0 }
	end
	for characterKey, row in pairs(perChar) do
		if isCharacterSelected(selectedCharacters, characterKey) then
			bags = bags + quantityRowValue(row, "b", "bags")
			bank = bank + quantityRowValue(row, "k", "bank")
			warband = warband + quantityRowValue(row, "w", "warband")
			total = total + quantityRowValue(row, "t", "total")
			n = n + 1
		end
	end
	return total, { bags = bags, bank = bank, warband = warband, sampleCount = n }
end

local function sortedQuantityBucketList(bucketMap, cutoff, selectedCharacters)
	local list = {}
	for key, bucket in pairs(bucketMap or {}) do
		local at = tonumber(key)
		if at and at > 0 and (not cutoff or at >= cutoff) then
			local total, meta = sumQuantityBucket(bucket, selectedCharacters)
			list[#list + 1] = {
				at = at,
				value = total,
				meta = meta,
			}
		end
	end
	table.sort(list, function(left, right)
		return left.at < right.at
	end)
	return list
end

function AuctionHelper:GetItemQuantityHistorySeries(itemID, selectedCharacters, rangeKey)
	self:InitDB()
	local itemHistory = self.db.itemHistory and self.db.itemHistory[tostring(itemID)] or nil
	if not itemHistory or type(itemHistory.quantity) ~= "table" then
		return {}
	end
	return sortedQuantityBucketList(
		itemHistory.quantity.buckets,
		self:GetHistoryRangeCutoff(rangeKey),
		selectedCharacters
	)
end

function AuctionHelper:ItemQuantitySeriesToGraphPoints(series)
	local out = {}
	for _, point in ipairs(series or {}) do
		out[#out + 1] = {
			at = point.at,
			value = tonumber(point.value) or 0,
			meta = point.meta,
		}
	end
	return out
end

function AuctionHelper:RecordQuantityObservationsFromSnapshot(characterData)
	local key = characterData and characterData.meta and characterData.meta.key
	if not key or key ~= self:GetCharacterKey() then
		return
	end
	local snap = characterData.inventorySnapshot
	if not snap or type(snap.items) ~= "table" then
		return
	end
	local at = tonumber(snap.capturedAt) or time()
	for itemKey, entry in pairs(snap.items) do
		local itemID = tonumber(itemKey)
		if itemID then
			self:RecordItemQuantityObservation(itemID, key, entry, at)
		end
	end
end
