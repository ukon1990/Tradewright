local addonName, ProfessionExporter = ...

--- Pure Forever / client helpers (offline-testable).
local ForeverLogic = {}
ProfessionExporter.ForeverLogic = ForeverLogic

--- Detect Forever vs true retail. Forever shares WOW_PROJECT_MAINLINE; use interface band 16000-16999.
function ForeverLogic.DetectClientFlags(interfaceVersion, projectId, mainlineId)
	interfaceVersion = tonumber(interfaceVersion) or 0
	local isForever = interfaceVersion >= 16000 and interfaceVersion < 17000
	local isRetail = (projectId == mainlineId) and not isForever
	return {
		IS_FOREVER = isForever,
		IS_RETAIL = isRetail,
		IS_SUPPORTED = isRetail or isForever,
	}
end

function ForeverLogic.ApplyClientFlags(target)
	target = target or ProfessionExporter
	local flags = ForeverLogic.DetectClientFlags(
		select(4, GetBuildInfo()),
		WOW_PROJECT_ID,
		WOW_PROJECT_MAINLINE
	)
	target.IS_FOREVER = flags.IS_FOREVER
	target.IS_RETAIL = flags.IS_RETAIL
	target.IS_SUPPORTED = flags.IS_SUPPORTED
	return flags
end

if type(GetBuildInfo) == "function" then
	ForeverLogic.ApplyClientFlags(ProfessionExporter)
end

--- Fold one classic/replicate auction list row into a full-dump aggregate bucket (by itemID).
--- Tracks listingCount (auctions with buyout) and marketHigh (max unit price) for Market UI.
function ForeverLogic.AggregateClassicAuctionRow(aggregate, itemID, count, buyoutPrice)
	aggregate = aggregate or {}
	itemID = tonumber(itemID)
	if not itemID or itemID <= 0 then
		return aggregate
	end
	local quantity = math.max(1, tonumber(count) or 1)
	local rawBuyout = tonumber(buyoutPrice)
	local bucket = aggregate[itemID] or {
		itemID = itemID,
		marketLow = nil,
		marketHigh = nil,
		minBuyout = nil,
		sampleSize = 0,
		listingCount = 0,
		weightedQty = 0,
		weightedSum = 0,
	}
	if rawBuyout and rawBuyout > 0 then
		local perUnit = rawBuyout / quantity
		bucket.marketLow = bucket.marketLow and math.min(bucket.marketLow, perUnit) or perUnit
		bucket.marketHigh = bucket.marketHigh and math.max(bucket.marketHigh, perUnit) or perUnit
		bucket.minBuyout = bucket.minBuyout and math.min(bucket.minBuyout, rawBuyout) or rawBuyout
		bucket.sampleSize = (tonumber(bucket.sampleSize) or 0) + quantity
		bucket.listingCount = (tonumber(bucket.listingCount) or 0) + 1
		bucket.weightedQty = (tonumber(bucket.weightedQty) or 0) + quantity
		bucket.weightedSum = (tonumber(bucket.weightedSum) or 0) + (perUnit * quantity)
	end
	aggregate[itemID] = bucket
	return aggregate
end

--- Item ID from auction storage keys (`region:itemID` or `region:realm:itemID`).
function ForeverLogic.ParseItemIDFromStorageKey(storageKey)
	if type(storageKey) ~= "string" or storageKey == "" then
		return nil
	end
	local last = storageKey:match("(%d+)$")
	local itemID = tonumber(last)
	if itemID and itemID > 0 then
		return itemID
	end
	return nil
end

--- Normalize compact (`p/q/n/h/t/s`) or long snapshot entry fields.
function ForeverLogic.NormalizeMarketSnapshotFields(entry)
	if type(entry) ~= "table" then
		return nil
	end
	local price = tonumber(entry.p or entry.marketLow or entry.minBuyout or entry.price)
	if not price or price <= 0 then
		return nil
	end
	return {
		price = price,
		marketHigh = tonumber(entry.h or entry.marketHigh),
		sampleSize = tonumber(entry.q or entry.sampleSize) or 0,
		listingCount = tonumber(entry.n or entry.listingCount) or 0,
		seenAt = tonumber(entry.t or entry.seenAt),
		source = entry.s or entry.source,
	}
end

local function historyBucketAvg(bucket)
	local qty = tonumber(bucket and (bucket.q or bucket.weightedQty)) or 0
	local sum = tonumber(bucket and (bucket.w or bucket.weightedSum)) or 0
	if qty > 0 and sum > 0 then
		return sum / qty
	end
	return tonumber(bucket and (bucket.l or bucket.last))
end

--- Sorted hourly history points from `auction.history.hourly[storageKey]`.
function ForeverLogic.BuildMarketHistorySeries(hourlyByHour)
	local points = {}
	if type(hourlyByHour) ~= "table" then
		return points
	end
	for hourKey, bucket in pairs(hourlyByHour) do
		local at = tonumber(hourKey)
		if at and type(bucket) == "table" then
			local last = tonumber(bucket.l or bucket.last)
			local minP = tonumber(bucket.m or bucket.min)
			local maxP = tonumber(bucket.x or bucket.max)
			if last or minP or maxP then
				points[#points + 1] = {
					at = at,
					last = last,
					min = minP,
					max = maxP,
					avg = historyBucketAvg(bucket),
					qty = tonumber(bucket.q or bucket.weightedQty) or 0,
					count = tonumber(bucket.n or bucket.count) or 0,
					seenAt = tonumber(bucket.t or bucket.lastSeenAt),
				}
			end
		end
	end
	table.sort(points, function(a, b)
		return a.at < b.at
	end)
	return points
end

local function marketRowMatchesQuery(row, query)
	if not query or query == "" then
		return true
	end
	if tostring(row.itemID or ""):find(query, 1, true) then
		return true
	end
	local name = string.lower(tostring(row.name or ""))
	return name:find(query, 1, true) ~= nil
end

local function compareMarketRows(a, b, sortKey, sortAsc)
	local left = a[sortKey]
	local right = b[sortKey]
	if sortKey == "name" then
		left = string.lower(tostring(left or ""))
		right = string.lower(tostring(right or ""))
	else
		left = tonumber(left) or 0
		right = tonumber(right) or 0
	end
	if left == right then
		local an = string.lower(tostring(a.name or ""))
		local bn = string.lower(tostring(b.name or ""))
		if an == bn then
			return (tonumber(a.itemID) or 0) < (tonumber(b.itemID) or 0)
		end
		return an < bn
	end
	if sortAsc then
		return left < right
	end
	return left > right
end

--- Build Market browser rows from snapshot roots.
--- resolveName(itemID) optional; query is plain substring (lowered by caller or here).
function ForeverLogic.BuildMarketBrowserRows(commodities, items, options)
	options = options or {}
	local resolveName = options.resolveName
	local query = string.lower(tostring(options.query or ""))
	local sortKey = tostring(options.sortKey or "name")
	local sortAsc = options.sortAsc ~= false
	if sortKey == "price" or sortKey == "marketHigh" or sortKey == "sampleSize" or sortKey == "listingCount" or sortKey == "seenAt" then
		if options.sortAsc == nil then
			sortAsc = false
		end
	end

	local rows = {}
	local function absorb(root, scope)
		for storageKey, entry in pairs(root or {}) do
			local fields = ForeverLogic.NormalizeMarketSnapshotFields(entry)
			local itemID = ForeverLogic.ParseItemIDFromStorageKey(storageKey)
			if fields and itemID then
				local name = (type(resolveName) == "function" and resolveName(itemID)) or ("#" .. tostring(itemID))
				local row = {
					storageKey = storageKey,
					itemID = itemID,
					name = name,
					scope = scope,
					price = fields.price,
					marketHigh = fields.marketHigh or fields.price,
					sampleSize = fields.sampleSize,
					listingCount = fields.listingCount,
					seenAt = fields.seenAt,
					source = fields.source,
				}
				if marketRowMatchesQuery(row, query) then
					rows[#rows + 1] = row
				end
			end
		end
	end
	absorb(commodities, "commodity")
	absorb(items, "item")
	table.sort(rows, function(a, b)
		return compareMarketRows(a, b, sortKey, sortAsc)
	end)
	return rows
end

--- Resolve bags/bank/warband when warband API may be missing (Forever).
--- withWarband may be nil when the 5-arg GetItemCount form failed.
function ForeverLogic.ResolveLocationCounts(bags, withBank, withWarband)
	bags = math.max(0, tonumber(bags) or 0)
	withBank = math.max(bags, tonumber(withBank) or bags)
	local bank = math.max(0, withBank - bags)
	local warband = 0
	if withWarband ~= nil then
		withWarband = math.max(bags, tonumber(withWarband) or bags)
		warband = math.max(0, withWarband - bags)
	end
	return bags, bank, warband, bags + bank + warband
end

local function encodeLuaValue(value, depth)
	depth = (depth or 0) + 1
	if depth > 24 then
		return "nil"
	end
	local valueType = type(value)
	if valueType == "nil" then
		return "nil"
	elseif valueType == "boolean" then
		return value and "true" or "false"
	elseif valueType == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "nil"
		end
		return tostring(value)
	elseif valueType == "string" then
		return string.format("%q", value)
	elseif valueType ~= "table" then
		return string.format("%q", tostring(value))
	end

	local parts = {}
	local n = #value
	local isArray = n > 0
	if isArray then
		for i = 1, n do
			if value[i] == nil then
				isArray = false
				break
			end
		end
	end
	if isArray then
		for i = 1, n do
			parts[#parts + 1] = encodeLuaValue(value[i], depth)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end

	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
	for _, key in ipairs(keys) do
		local keyLiteral
		if type(key) == "string" and key:match("^[%a_][%w_]*$") then
			keyLiteral = key
		elseif type(key) == "number" then
			keyLiteral = "[" .. tostring(key) .. "]"
		else
			keyLiteral = "[" .. string.format("%q", tostring(key)) .. "]"
		end
		parts[#parts + 1] = keyLiteral .. "=" .. encodeLuaValue(value[key], depth)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

ForeverLogic.EncodeLuaValue = encodeLuaValue

--- Build AHLUA1 plain-text export package body (including prefix).
function ForeverLogic.BuildPlainLuaExportPayload(exportData)
	if type(exportData) ~= "table" then
		return nil, "invalid export data"
	end
	local ok, body = pcall(encodeLuaValue, exportData, 0)
	if not ok or type(body) ~= "string" or body == "" then
		return nil, body or "Lua encode failed"
	end
	return "AHLUA1:return " .. body, nil
end

--- Gate classic cursor sell inject (PickupContainerItem + ClickAuctionSellItemButton).
--- Retail keeps SetItemByLocation-only when that API exists; Forever always may use classic.
--- Clients without SetItemByLocation may use classic even when not Forever.
function ForeverLogic.ShouldUseClassicSellInject(isForever, hasSetItemByLocation)
	if isForever == true then
		return true
	end
	return hasSetItemByLocation ~= true
end

--- Classic recipe reagent slot from (itemID, quantity).
function ForeverLogic.MakeClassicReagentSlot(slotIndex, itemID, quantity)
	itemID = tonumber(itemID)
	quantity = tonumber(quantity) or 0
	if not itemID or itemID <= 0 or quantity <= 0 then
		return nil
	end
	return {
		slotIndex = slotIndex,
		dataSlotIndex = slotIndex,
		reagentType = 1,
		quantityRequired = quantity,
		required = true,
		optional = false,
		reagents = {
			{
				reagentIndex = 1,
				itemID = itemID,
				quantity = quantity,
			},
		},
	}
end

return ForeverLogic
