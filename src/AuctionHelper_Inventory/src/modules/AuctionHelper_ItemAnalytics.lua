local addonName, ProfessionExporter = ...

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

function ProfessionExporter:GetItemHistoryRetentionSeconds()
	local settings = self.db and self.db.settings and self.db.settings.inventory or nil
	local days = tonumber(settings and settings.historyRetentionDays) or 30
	days = math.max(1, math.floor(days))
	return days * 24 * 60 * 60
end

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

local function isCharacterSelected(selection, characterKey)
	if isCharacterSelectionEmpty(selection) then
		return true
	end
	return selection[characterKey] == true
end

--- itemID -> quality rank from scanned recipe quality variants (fallback when item link has no tier).
function ProfessionExporter:BuildOutputItemQualityRankIndex(selectedCharacters)
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

function ProfessionExporter:GetItemCraftQualityRank(itemID, selectedCharacters, rankIndex)
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
function ProfessionExporter:GetItemDisplayProfessionQualityRank(itemID, selectedCharacters, rankIndex)
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

function ProfessionExporter:GetInventoryMetricRangeOptions()
	return {
		{ value = "all", label = "All time" },
		{ value = "24h", label = "24 hours" },
		{ value = "7d", label = "7 days" },
		{ value = "30d", label = "30 days" },
		{ value = "90d", label = "90 days" },
		{ value = "1y", label = "1 year" },
	}
end

function ProfessionExporter:GetInventoryMetricRange()
	return self:GetSetting("inventory.metricRange", "30d")
end

function ProfessionExporter:SetInventoryMetricRange(value)
	local chosen = "30d"
	for _, option in ipairs(self:GetInventoryMetricRangeOptions()) do
		if option.value == value then
			chosen = value
			break
		end
	end
	self:SetSetting("inventory.metricRange", chosen)
end

function ProfessionExporter:GetHistoryRangeCutoff(rangeKey)
	if not rangeKey or rangeKey == "all" then
		return nil
	end
	local seconds = RANGE_TO_SECONDS[rangeKey]
	if not seconds then
		return nil
	end
	return time() - seconds
end

function ProfessionExporter:EnsureItemHistory(itemID)
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

function ProfessionExporter:CompactItemHistoryStorage()
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

function ProfessionExporter:RecordItemHistoryObservation(itemID, historyKey, value, source, observedAt)
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
	bucket.count = nil
	bucket.sum = nil
	bucket.last = nil
	bucket.min = nil
	bucket.max = nil
	bucket.source = nil
	store.buckets[tostring(bucketAt)] = bucket
	store.latest = {
		value = n,
		at = observedAt,
		source = source,
	}
	trimHistoryBuckets(store.buckets, time() - self:GetItemHistoryRetentionSeconds())
end

function ProfessionExporter:GetItemHistorySeries(itemID, historyKey, rangeKey)
	self:InitDB()
	local itemHistory = self.db.itemHistory and self.db.itemHistory[tostring(itemID)] or nil
	if not itemHistory or type(itemHistory[historyKey]) ~= "table" then
		return {}
	end
	return sortedBucketList(itemHistory[historyKey].buckets, self:GetHistoryRangeCutoff(rangeKey))
end

function ProfessionExporter:GetItemHistoryStats(itemID, historyKey, rangeKey)
	return summarizeSeries(self:GetItemHistorySeries(itemID, historyKey, rangeKey))
end

function ProfessionExporter:GetItemHistoryStatsMemo(itemID, historyKey, rangeKey, memoTbl)
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

function ProfessionExporter:GetItemRecipeRelationships(itemID, selectedCharacters)
	self:InitDB()
	itemID = tonumber(itemID)
	local relationships = {
		producedBy = {},
		usedBy = {},
	}
	if not itemID then
		return relationships
	end

	for characterKey, characterData in pairs(self.db.characters or {}) do
		if isCharacterSelected(selectedCharacters, characterKey) then
			local meta = characterData.meta or {}
			local characterLabel = (meta.name and meta.realm) and (tostring(meta.name) .. " - " .. tostring(meta.realm)) or characterKey
			for _, professionData in pairs(characterData.professions or {}) do
				for recipeID, recipeData in pairs(professionData.recipes or {}) do
					local info = self:RecipeDataInfo(recipeData) or {}
					local outputs = recipeData.outputs or {}
					local primaryItemID = self:RecipeOutputsPrimaryItemId(outputs)
					local recipeName = info.name or ("Recipe #" .. tostring(recipeID))
					if tonumber(primaryItemID) == itemID then
						relationships.producedBy[#relationships.producedBy + 1] = {
							characterKey = characterKey,
							characterLabel = characterLabel,
							professionName = professionData.professionName or "?",
							recipeID = tonumber(recipeID) or recipeID,
							recipeName = recipeName,
						}
					end
					for _, slot in ipairs(self:RecipeDataSlots(recipeData) or {}) do
						for _, reagent in ipairs(slot.reagents or {}) do
							if tonumber(reagent.itemID) == itemID then
								relationships.usedBy[#relationships.usedBy + 1] = {
									characterKey = characterKey,
									characterLabel = characterLabel,
									professionName = professionData.professionName or "?",
									recipeID = tonumber(recipeID) or recipeID,
									recipeName = recipeName,
									quantityRequired = tonumber(slot.quantityRequired) or 0,
								}
								break
							end
						end
					end
				end
			end
		end
	end

	table.sort(relationships.producedBy, function(left, right)
		if left.professionName == right.professionName then
			return tostring(left.recipeName) < tostring(right.recipeName)
		end
		return tostring(left.professionName) < tostring(right.professionName)
	end)
	table.sort(relationships.usedBy, function(left, right)
		if left.professionName == right.professionName then
			return tostring(left.recipeName) < tostring(right.recipeName)
		end
		return tostring(left.professionName) < tostring(right.professionName)
	end)

	return relationships
end

function ProfessionExporter:BuildInventoryItemTotals(itemID, selectedCharacters)
	self:InitDB()
	local totals = {
		bags = 0,
		bank = 0,
		warband = 0,
		total = 0,
	}
	for characterKey, characterData in pairs(self.db.characters or {}) do
		if isCharacterSelected(selectedCharacters, characterKey) then
			local itemEntry = characterData.inventorySnapshot
				and characterData.inventorySnapshot.items
				and characterData.inventorySnapshot.items[tostring(itemID)]
				or nil
			if itemEntry then
				totals.bags = totals.bags + (tonumber(itemEntry.bags) or 0)
				totals.bank = totals.bank + (tonumber(itemEntry.bank) or 0)
				totals.warband = totals.warband + (tonumber(itemEntry.warband) or 0)
				totals.total = totals.total + (tonumber(itemEntry.total) or 0)
			end
		end
	end
	return totals
end

function ProfessionExporter:BuildItemCraftingSnapshot(itemID, selectedCharacters, rangeKey)
	local stats = self:GetItemHistoryStats(itemID, "crafting", rangeKey)
	local relationships = self:GetItemRecipeRelationships(itemID, selectedCharacters)
	return {
		lastCraftCost = stats.latest,
		avgCraftCost = stats.average,
		count = stats.count,
		change = stats.change,
		producedBy = relationships.producedBy,
		usedBy = relationships.usedBy,
		series = self:GetItemHistorySeries(itemID, "crafting", rangeKey),
	}
end

function ProfessionExporter:BuildItemEconomySnapshot(itemID, selectedCharacters, rangeKey)
	local marketStats = self:GetItemHistoryStats(itemID, "market", rangeKey)
	local itemHistory = self.db and self.db.itemHistory and self.db.itemHistory[tostring(itemID)] or {}
	local latestMarket = itemHistory.market and itemHistory.market.latest or nil
	return {
		currentMarket = latestMarket and latestMarket.value or nil,
		currentMarketAt = latestMarket and latestMarket.at or nil,
		currentMarketSource = latestMarket and latestMarket.source or nil,
		lastObservedPrice = marketStats.latest,
		avgObservedPrice = marketStats.average,
		count = marketStats.count,
		change = marketStats.change,
		series = self:GetItemHistorySeries(itemID, "market", rangeKey),
		inventoryTotals = self:BuildInventoryItemTotals(itemID, selectedCharacters),
	}
end

function ProfessionExporter:BuildItemDetailSnapshot(itemID, context)
	context = context or {}
	local selectedCharacters = context.selectedCharacters
	local rangeKey = context.rangeKey or self:GetInventoryMetricRange()
	local desc = self:ResolveItemDescriptor(itemID) or {}
	local economy = self:BuildItemEconomySnapshot(itemID, selectedCharacters, rangeKey)
	local crafting = self:BuildItemCraftingSnapshot(itemID, selectedCharacters, rangeKey)
	local rid = tonumber(itemID)
	return {
		itemID = rid,
		name = desc.name or self:GetItemDisplayName(itemID),
		icon = desc.icon,
		rankIndex = self:GetItemDisplayProfessionQualityRank(itemID, selectedCharacters, context.rankIndex),
		itemType = desc.itemType,
		itemSubType = desc.itemSubType,
		classID = desc.classID,
		subclassID = desc.subclassID,
		economy = economy,
		crafting = crafting,
		rangeKey = rangeKey,
	}
end

function ProfessionExporter:EnrichInventoryRowAnalytics(row, characterData, roleMap, selectedCharacters, rangeKey, rankIndex, historyStatsMemo, perCharacterRoleMaps)
	if row.aggregatedInventory then
		self:ApplyEconomyToAggregatedInventoryRow(row, selectedCharacters, roleMap, perCharacterRoleMaps)
	else
		self:ApplyEconomyToInventoryRow(row, characterData, roleMap)
	end
	rangeKey = rangeKey or self:GetInventoryMetricRange()
	if row.marketCopper then
		self:RecordItemHistoryObservation(row.itemID, "market", row.marketCopper, row.marketSource, time())
	end
	if row.matCopperPerUnit then
		self:RecordItemHistoryObservation(row.itemID, "crafting", row.matCopperPerUnit, "Crafting", time())
	end

	local marketStats = self:GetItemHistoryStatsMemo(row.itemID, "market", rangeKey, historyStatsMemo)
	local craftStats = self:GetItemHistoryStatsMemo(row.itemID, "crafting", rangeKey, historyStatsMemo)
	local latestMarket = self.db.itemHistory
		and self.db.itemHistory[tostring(row.itemID)]
		and self.db.itemHistory[tostring(row.itemID)].market
		and self.db.itemHistory[tostring(row.itemID)].market.latest
		or nil

	row.currentAhCopper = row.marketCopper
	row.currentAhAt = latestMarket and latestMarket.at or nil
	row.currentAhSource = row.marketSource
	row.lastObservedPrice = marketStats.latest
	row.avgObservedPrice = marketStats.average
	row.lastCraftCost = craftStats.latest or row.matCopperPerUnit
	row.avgCraftCost = craftStats.average or row.matCopperPerUnit
	row.profitCopperPerUnit = row.currentAhCopper and row.avgCraftCost and (row.currentAhCopper - row.avgCraftCost) or nil
	row.profitCopperStack = row.profitCopperPerUnit and row.total and (row.profitCopperPerUnit * row.total) or nil
	row.historyPoints = marketStats.count
	row.craftingPoints = craftStats.count
	row.selectedCharacters = selectedCharacters
	row.rankIndex = self:GetItemDisplayProfessionQualityRank(row.itemID, selectedCharacters, rankIndex)
end

function ProfessionExporter:OpenItemDetails(itemID, context)
	local ui = self.ui or {}
	ui.invSelectedItemID = tonumber(itemID)
	ui.invDetailsContext = context or ui.invDetailsContext or {}
	local tab = ui.activeMainTab
	if tab == "inventory" and ui.inventoryPanel then
		self:SetSetting("inventory.detailsOpen", true)
		self:LayoutInventoryPanel(ui.inventoryPanel)
		self:RenderInventoryDetails(ui.invSelectedItemID)
	elseif tab == "crafts" and ui.craftsPanel then
		self:SetSetting("crafts.detailsOpen", true)
		local row = self:SelectCraftOpportunityByOutputItemID(ui.invSelectedItemID)
		ui.craftsItemDetailOnlyItemID = nil
		if row then
			ui.craftsSelectedRowKey = row.rowKey
			ui.craftsSelectedRowData = row
			self:SetSetting("crafts.selectedRowKey", row.rowKey)
		else
			ui.craftsSelectedRowKey = nil
			ui.craftsSelectedRowData = nil
			self:SetSetting("crafts.selectedRowKey", nil)
			if ui.invSelectedItemID then
				ui.craftsItemDetailOnlyItemID = ui.invSelectedItemID
			end
		end
		self:RenderCraftsDetails(row)
		self:LayoutCraftsPanel(ui.craftsPanel)
	end
end

function ProfessionExporter:RecordItemQuantityObservation(itemID, characterKey, bags, bank, warband, total, observedAt)
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
		b = tonumber(bags) or 0,
		k = tonumber(bank) or 0,
		w = tonumber(warband) or 0,
		t = tonumber(total) or 0,
		a = observedAt,
	}
	local lastRow = store.latestByChar[characterKey]
	if type(lastRow) == "table"
		and quantityRowValue(lastRow, "b", "bags") == currentRow.b
		and quantityRowValue(lastRow, "k", "bank") == currentRow.k
		and quantityRowValue(lastRow, "w", "warband") == currentRow.w
		and quantityRowValue(lastRow, "t", "total") == currentRow.t then
		store.latest = {
			value = currentRow.t,
			at = observedAt,
			characterKey = characterKey,
		}
		store.latestByChar[characterKey] = currentRow
		return
	end
	local bucketAt = observedAt - (observedAt % 3600)
	local bucket = store.buckets[tostring(bucketAt)] or { c = {} }
	bucket.c = bucket.c or bucket.perChar or {}
	bucket.c[characterKey] = currentRow
	bucket.perChar = nil
	store.buckets[tostring(bucketAt)] = bucket
	store.latest = {
		value = currentRow.t,
		at = observedAt,
		characterKey = characterKey,
	}
	store.latestByChar[characterKey] = currentRow
	trimHistoryBuckets(store.buckets, time() - self:GetItemHistoryRetentionSeconds())
end

local function sumQuantityBucket(bucket, selectedCharacters)
	local bags, bank, warband, total, n = 0, 0, 0, 0, 0
	local perChar = type(bucket) == "table" and (bucket.c or bucket.perChar) or nil
	if type(perChar) ~= "table" then
		return 0, { bags = 0, bank = 0, warband = 0, sampleCount = 0 }
	end
	for ck, row in pairs(perChar) do
		if isCharacterSelected(selectedCharacters, ck) then
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

function ProfessionExporter:GetItemQuantityHistorySeries(itemID, selectedCharacters, rangeKey)
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

function ProfessionExporter:ItemHistoryBucketsToGraphSeries(itemID, historyKey, rangeKey)
	local raw = self:GetItemHistorySeries(itemID, historyKey, rangeKey)
	local out = {}
	for _, p in ipairs(raw) do
		local v = tonumber(p.avg or p.last)
		if v then
			out[#out + 1] = {
				at = p.at,
				value = v,
				meta = {
					count = p.count,
					min = p.min,
					max = p.max,
					source = p.source,
				},
			}
		end
	end
	return out
end

function ProfessionExporter:ItemQuantitySeriesToGraphPoints(series)
	local out = {}
	for _, p in ipairs(series or {}) do
		out[#out + 1] = {
			at = p.at,
			value = tonumber(p.value) or 0,
			meta = p.meta,
		}
	end
	return out
end

--- Stable item id for itemHistory / quantity graphs when scan output id is wrong (e.g. recipe id stored as output).
function ProfessionExporter:ResolveGraphItemIDForCraftRow(row)
	if not row then
		return nil
	end
	local id = tonumber(row.outputItemID)
	local rid = tonumber(row.recipeID)
	if id and rid and id == rid then
		id = nil
	end
	local function itemIdExists(iid)
		iid = tonumber(iid)
		if not iid or iid <= 0 then
			return false
		end
		if self.IS_SUPPORTED and C_Item and C_Item.DoesItemExistByID then
			return C_Item.DoesItemExistByID(iid) == true
		end
		return true
	end
	if id and itemIdExists(id) then
		return id
	end
	if rid and C_TradeSkillUI and C_TradeSkillUI.GetRecipeQualityItemIDs then
		local ok, list = pcall(C_TradeSkillUI.GetRecipeQualityItemIDs, rid)
		if ok and type(list) == "table" then
			for _, v in ipairs(list) do
				local iid = tonumber(v)
				if iid and itemIdExists(iid) then
					return iid
				end
			end
		end
	end
	self:InitDB()
	if rid then
		for _, charData in pairs(self.db.characters or {}) do
			for _, professionData in pairs(charData.professions or {}) do
				local recipeData = professionData.recipes and professionData.recipes[tostring(rid)]
				if recipeData and recipeData.outputs then
					local outs = recipeData.outputs
					for _, variant in ipairs(outs.qualityVariants or {}) do
						local vid = tonumber(variant and variant.itemID)
						if vid and itemIdExists(vid) then
							return vid
						end
					end
					local pid = tonumber(self:RecipeOutputsPrimaryItemId(outs))
					if pid and itemIdExists(pid) then
						return pid
					end
				end
			end
		end
	end
	local fallback = tonumber(row.outputItemID)
	if fallback and fallback > 0 then
		return fallback
	end
	return nil
end

function ProfessionExporter:EnsureWalletHistoryStore(characterKey)
	self:InitDB()
	characterKey = characterKey and tostring(characterKey) or ""
	if characterKey == "" then
		return nil
	end
	self.db.walletHistory = self.db.walletHistory or {}
	local w = self.db.walletHistory[characterKey]
	if not w then
		w = { buckets = {} }
		self.db.walletHistory[characterKey] = w
	end
	return w
end

function ProfessionExporter:RecordWalletObservation(characterKey, copper, observedAt)
	characterKey = characterKey and tostring(characterKey) or ""
	local n = tonumber(copper)
	if characterKey == "" or not n or n < 0 then
		return
	end
	local store = self:EnsureWalletHistoryStore(characterKey)
	if not store then
		return
	end
	store.buckets = store.buckets or {}
	observedAt = tonumber(observedAt) or time()
	local bucketAt = observedAt - (observedAt % 3600)
	local bucket = store.buckets[tostring(bucketAt)] or {
		count = 0,
		sum = 0,
		last = nil,
		min = nil,
		max = nil,
	}
	bucket.count = (bucket.count or 0) + 1
	bucket.sum = (bucket.sum or 0) + n
	bucket.last = n
	bucket.min = bucket.min and math.min(bucket.min, n) or n
	bucket.max = bucket.max and math.max(bucket.max, n) or n
	store.buckets[tostring(bucketAt)] = bucket
	trimHistoryBuckets(store.buckets, time() - RANGE_TO_SECONDS["1y"])
	self:NotifyWalletHistoryUpdate()
end

function ProfessionExporter:NotifyWalletHistoryUpdate()
	local ui = self.ui
	if not ui or ui.activeMainTab ~= "overview" then
		return
	end
	local mf = ui.mainFrame
	if not mf or not mf:IsShown() then
		return
	end
	if self.OverviewTab and self.OverviewTab.Refresh then
		self.OverviewTab:Refresh()
	end
end

function ProfessionExporter:RecordWalletObservationFromCharacterData(characterData)
	local key = characterData and characterData.meta and characterData.meta.key
	if not key or key ~= self:GetCharacterKey() then
		return
	end
	self:RecordWalletObservation(key, GetMoney(), time())
end

function ProfessionExporter:RecordQuantityObservationsFromSnapshot(characterData)
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
			self:RecordItemQuantityObservation(
				itemID,
				key,
				entry.bags,
				entry.bank,
				entry.warband,
				entry.total,
				at
			)
		end
	end
end

function ProfessionExporter:OnInventorySnapshotWritten(characterData)
	self:RecordWalletObservationFromCharacterData(characterData)
	self:RecordQuantityObservationsFromSnapshot(characterData)
end

local function walletSortedList(bucketMap, cutoff)
	local list = {}
	for key, bucket in pairs(bucketMap or {}) do
		local at = tonumber(key)
		if at and at > 0 and (not cutoff or at >= cutoff) then
			list[#list + 1] = {
				at = at,
				last = bucket.last,
				count = bucket.count or 0,
			}
		end
	end
	table.sort(list, function(left, right)
		return left.at < right.at
	end)
	return list
end

function ProfessionExporter:WalletHistoryToGraphSeries(characterKey, rangeKey)
	self:InitDB()
	local wh = self.db.walletHistory and self.db.walletHistory[tostring(characterKey)] or nil
	if not wh then
		return {}
	end
	local raw = walletSortedList(wh.buckets, self:GetHistoryRangeCutoff(rangeKey))
	local out = {}
	for _, p in ipairs(raw) do
		local v = tonumber(p.last)
		if v then
			out[#out + 1] = { at = p.at, value = v, meta = { count = p.count } }
		end
	end
	return out
end

function ProfessionExporter:WalletBalanceSeriesToEarned(balanceSeries)
	local out = {}
	for i = 2, #(balanceSeries or {}) do
		local prev = balanceSeries[i - 1].value
		local cur = balanceSeries[i].value
		out[#out + 1] = {
			at = balanceSeries[i].at,
			value = cur - prev,
			meta = {
				previous = prev,
				current = cur,
			},
		}
	end
	return out
end

function ProfessionExporter:BuildAccountWalletBalanceSeries(rangeKey)
	self:InitDB()
	local cutoff = self:GetHistoryRangeCutoff(rangeKey)
	local charLists = {}
	for ck, wh in pairs(self.db.walletHistory or {}) do
		local list = walletSortedList(wh.buckets, cutoff)
		if #list > 0 then
			charLists[tostring(ck)] = list
		end
	end
	local hourSet = {}
	for _, list in pairs(charLists) do
		for _, p in ipairs(list) do
			hourSet[p.at] = true
		end
	end
	local hours = {}
	for at in pairs(hourSet) do
		hours[#hours + 1] = at
	end
	table.sort(hours)
	local indices = {}
	local result = {}
	for _, H in ipairs(hours) do
		local sum = 0
		local any = false
		for ck, list in pairs(charLists) do
			local idx = indices[ck] or 1
			while idx < #list and list[idx + 1].at <= H do
				idx = idx + 1
			end
			indices[ck] = idx
			local entry = list[idx]
			if entry and entry.at <= H and entry.last then
				sum = sum + (tonumber(entry.last) or 0)
				any = true
			end
		end
		if any then
			result[#result + 1] = { at = H, value = sum, meta = { account = true } }
		end
	end
	return result
end

function ProfessionExporter:GetOverviewWalletGraphSeries(selectedCharacterKey, rangeKey, mode)
	local acct = self.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"
	local balance
	if selectedCharacterKey == acct then
		balance = self:BuildAccountWalletBalanceSeries(rangeKey)
	else
		balance = self:WalletHistoryToGraphSeries(selectedCharacterKey, rangeKey)
	end
	if mode == "earned" then
		return self:WalletBalanceSeriesToEarned(balance)
	end
	return balance
end

function ProfessionExporter:GetCurrentGoldSummaryForOverview(selectedCharacterKey)
	local acct = self.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"
	self:InitDB()
	local currentKey = self:GetCharacterKey()

	local function lastStoredCopperForKey(ck)
		local wh = self.db.walletHistory and self.db.walletHistory[tostring(ck)] or nil
		if not wh then
			return nil
		end
		local bestAt, bestVal = nil, nil
		for hk, bucket in pairs(wh.buckets or {}) do
			local at = tonumber(hk)
			local v = tonumber(bucket.last)
			if at and v and (not bestAt or at > bestAt) then
				bestAt = at
				bestVal = v
			end
		end
		return bestVal
	end

	if selectedCharacterKey == acct then
		local total = 0
		for ck, _ in pairs(self.db.characters or {}) do
			if ck == currentKey then
				total = total + GetMoney()
			else
				local v = lastStoredCopperForKey(ck)
				if v then
					total = total + v
				end
			end
		end
		return total
	end

	local ck = tostring(selectedCharacterKey or "")
	if ck == currentKey then
		return GetMoney()
	end
	return lastStoredCopperForKey(ck)
end

local function graphTimestampForSeries(at)
	if not at or at <= 0 then
		return "—"
	end
	return date("%Y-%m-%d %H:%M", at)
end

local function formatCopperFullLocal(pe, copper)
	return pe:FormatCopperFull(copper)
end

function ProfessionExporter:BuildItemDetailScrollBodyLines(detail)
	if not detail or type(detail) ~= "table" then
		return {}
	end
	local totals = detail.economy and detail.economy.inventoryTotals or {}
	local lines = {
		"|cffffffffOverview|r",
		string.format(
			"Inventory total: %s (bags %s / bank %s / warband %s)",
			ProfessionExporter:FormatNumberGrouped(totals.total or 0),
			ProfessionExporter:FormatNumberGrouped(totals.bags or 0),
			ProfessionExporter:FormatNumberGrouped(totals.bank or 0),
			ProfessionExporter:FormatNumberGrouped(totals.warband or 0)
		),
		string.format("Average AH observation: %s", formatCopperFullLocal(ProfessionExporter, detail.economy and detail.economy.avgObservedPrice)),
		string.format("Average crafting cost: %s", formatCopperFullLocal(ProfessionExporter, detail.crafting and detail.crafting.avgCraftCost)),
		string.format(
			"Observed price points: %d  |  crafting points: %d",
			(detail.economy and detail.economy.count) or 0,
			(detail.crafting and detail.crafting.count) or 0
		),
		" ",
	}
	lines[#lines + 1] = "|cffffffffProduces this item|r"
	local producedBy = detail.crafting and detail.crafting.producedBy or {}
	if #producedBy == 0 then
		lines[#lines + 1] = "No scanned recipe outputs for this item yet."
	else
		for index = 1, math.min(10, #producedBy) do
			local entry = producedBy[index]
			lines[#lines + 1] = string.format("%s | %s | %s", tostring(entry.professionName), tostring(entry.recipeName), tostring(entry.characterLabel))
		end
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = "|cffffffffUses this item|r"
	local usedBy = detail.crafting and detail.crafting.usedBy or {}
	if #usedBy == 0 then
		lines[#lines + 1] = "No scanned reagent usage for this item yet."
	else
		for index = 1, math.min(10, #usedBy) do
			local entry = usedBy[index]
			lines[#lines + 1] = string.format(
				"%s | %s x%d | %s",
				tostring(entry.professionName),
				tostring(entry.recipeName),
				tonumber(entry.quantityRequired) or 0,
				tostring(entry.characterLabel)
			)
		end
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] =
		"|cffffcc00Sale-specific ledger stats are not populated yet unless a real source provides them; current history tracks observed AH and crafting values from addon activity.|r"
	return lines
end

function ProfessionExporter:ApplyItemDetailTimeSeriesGraph(itemID, graphWidget, config)
	config = config or {}
	if not graphWidget or not graphWidget.SetSeries then
		return
	end
	itemID = tonumber(itemID)
	if not itemID then
		return
	end
	local graphItemID = tonumber(config.graphItemID) or itemID
	local metric = self:GetSetting(config.metricSettingKey or "inventory.detailsGraphMetric", "market")
	local rangeKey = config.rangeKey or self:GetInventoryMetricRange()
	local qtyFilter = config.quantityCharacterFilter or {}
	local emptyQty = config.quantityEmptyHint
		or "No quantity history in this range yet. Run an inventory refresh while this item is tracked."
	local accent = self:GetSetting("appearance.accentColor", {})
	graphWidget:SetAccentColor({ r = accent.r, g = accent.g, b = accent.b, a = 0.95 })
	if graphWidget.SetSecondaryAccentColor then
		graphWidget:SetSecondaryAccentColor({ r = 0.92, g = 0.58, b = 0.18, a = 0.95 })
	end
	if graphWidget.SetQuantityAccentColor then
		graphWidget:SetQuantityAccentColor({ r = 0.42, g = 0.78, b = 0.5, a = 0.9 })
	end
	local series = {}
	local secondarySeries = {}
	local quantitySeries = {}
	local yFormatter = function(v)
		return tostring(math.floor(tonumber(v) or 0))
	end
	local emptyExtra = "No observations in this range."
	local tooltipBuilder
	local function qtyTooltip(tip, pt)
		tip:AddLine(graphTimestampForSeries(pt.at), 1, 1, 1)
		local m = pt.meta or {}
		if m.ahHistory then
			tip:AddLine(
				string.format("AH sample quantity: %s", ProfessionExporter:FormatNumberGrouped(tonumber(pt.value) or 0)),
				0.85,
				0.92,
				1
			)
			if (m.sampleCount or 0) > 0 then
				tip:AddLine(string.format("Price observations in hour: %d", m.sampleCount), 0.72, 0.8, 0.88)
			end
		else
			tip:AddLine(string.format("Total quantity: %s", ProfessionExporter:FormatNumberGrouped(tonumber(pt.value) or 0)), 0.85, 0.92, 1)
			if (m.sampleCount or 0) > 0 then
				tip:AddLine(
					string.format(
						"Bags %s  |  Bank %s  |  Warband %s",
						ProfessionExporter:FormatNumberGrouped(m.bags or 0),
						ProfessionExporter:FormatNumberGrouped(m.bank or 0),
						ProfessionExporter:FormatNumberGrouped(m.warband or 0)
					),
					0.72,
					0.8,
					0.88
				)
			end
		end
	end
	local function craftingTooltip(tip, pt)
		tip:AddLine(graphTimestampForSeries(pt.at), 1, 1, 1)
		tip:AddLine("|cffffcc00Crafting cost|r  " .. formatCopperFullLocal(ProfessionExporter, pt.value), 0.85, 0.92, 1)
		local m = pt.meta or {}
		if m.flat then
			tip:AddLine("Current estimate (flat)", 0.72, 0.8, 0.88)
		end
		if m.count and m.count > 0 then
			tip:AddLine(string.format("Samples in hour: %d", m.count), 0.72, 0.8, 0.88)
		end
		if m.min and m.max then
			tip:AddLine(
				string.format(
					"Min %s  |  Max %s",
					formatCopperFullLocal(ProfessionExporter, m.min),
					formatCopperFullLocal(ProfessionExporter, m.max)
				),
				0.72,
				0.8,
				0.88
			)
		end
	end
	local function marketTooltip(tip, pt)
		tip:AddLine(graphTimestampForSeries(pt.at), 1, 1, 1)
		tip:AddLine("|cffffffffMarket|r  " .. formatCopperFullLocal(ProfessionExporter, pt.value), 0.85, 0.92, 1)
		local m = pt.meta or {}
		if m.source then
			tip:AddLine(string.format("Source: %s", tostring(m.source)), 0.72, 0.8, 0.88)
		end
		if m.count and m.count > 0 then
			tip:AddLine(string.format("Samples in hour: %d", m.count), 0.72, 0.8, 0.88)
		end
		if m.min and m.max then
			tip:AddLine(
				string.format(
					"Min %s  |  Max %s",
					formatCopperFullLocal(ProfessionExporter, m.min),
					formatCopperFullLocal(ProfessionExporter, m.max)
				),
				0.72,
				0.8,
				0.88
			)
		end
	end
	if metric == "quantity" then
		local qtyRaw = self:GetItemQuantityHistorySeries(graphItemID, qtyFilter, rangeKey)
		series = self:ItemQuantitySeriesToGraphPoints(qtyRaw)
		yFormatter = function(v)
			return ProfessionExporter:FormatNumberGrouped(math.floor(tonumber(v) or 0))
		end
		emptyExtra = emptyQty
		tooltipBuilder = function(tip, hit)
			local pt = hit and hit.pt or hit
			qtyTooltip(tip, pt)
		end
	elseif metric == "crafting" then
		series = self:ItemHistoryBucketsToGraphSeries(graphItemID, "crafting", rangeKey)
		yFormatter = function(v)
			return ProfessionExporter:FormatCopperShort(tonumber(v) or 0)
		end
		if config.quantityOverlay then
			local qtyRaw = self:GetAuctionHistoryQuantitySeriesForItem(graphItemID, rangeKey)
			quantitySeries = self:ItemQuantitySeriesToGraphPoints(qtyRaw)
		end
		tooltipBuilder = function(tip, hit)
			local pt = hit and hit.pt or hit
			local kind = hit and hit.kind or "primary"
			if kind == "quantity" then
				qtyTooltip(tip, pt)
			else
				craftingTooltip(tip, pt)
			end
		end
	else
		series = self:ItemHistoryBucketsToGraphSeries(graphItemID, "market", rangeKey)
		yFormatter = function(v)
			return ProfessionExporter:FormatCopperShort(tonumber(v) or 0)
		end
		if config.secondaryCraftingOverlay then
			secondarySeries = self:ItemHistoryBucketsToGraphSeries(graphItemID, "crafting", rangeKey)
			local flatCost = tonumber(config.currentCraftCostCopper)
			if (#secondarySeries == 0) and flatCost and flatCost > 0 and #series >= 1 then
				local t0, t1 = series[1].at, series[#series].at
				secondarySeries = {
					{ at = t0, value = flatCost, meta = { flat = true } },
					{ at = t1, value = flatCost, meta = { flat = true } },
				}
			end
		end
		if config.quantityOverlay then
			local qtyRaw = self:GetAuctionHistoryQuantitySeriesForItem(graphItemID, rangeKey)
			quantitySeries = self:ItemQuantitySeriesToGraphPoints(qtyRaw)
		end
		tooltipBuilder = function(tip, hit)
			local pt = hit and hit.pt or hit
			local kind = hit and hit.kind or "primary"
			if kind == "quantity" then
				qtyTooltip(tip, pt)
			elseif kind == "secondary" then
				craftingTooltip(tip, pt)
			else
				marketTooltip(tip, pt)
			end
		end
	end
	if graphWidget.SetRightYFormatter then
		graphWidget:SetRightYFormatter(function(v)
			return ProfessionExporter:FormatNumberGrouped(math.floor(tonumber(v) or 0))
		end)
	end
	graphWidget:SetEmptyText(emptyExtra)
	graphWidget:SetSeries(series)
	if graphWidget.SetSecondarySeries then
		graphWidget:SetSecondarySeries(secondarySeries)
	end
	if graphWidget.SetQuantitySeries then
		graphWidget:SetQuantitySeries(quantitySeries)
	end
	graphWidget:SetYFormatter(yFormatter)
	graphWidget:SetTooltipBuilder(tooltipBuilder)
	graphWidget:Refresh()
end
