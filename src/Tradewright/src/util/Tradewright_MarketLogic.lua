-- Pure Market tab helpers: snapshot fields, hourly history, deal flags and the browser rows with their filters. No WoW API.
local _, Tradewright = ...

local MarketLogic = {}
Tradewright.MarketLogic = MarketLogic
local FL = Tradewright.ForeverLogic

--- Normalize compact (`p/q/n/h/t/s`) or long snapshot entry fields.
function MarketLogic.NormalizeMarketSnapshotFields(entry)
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
function MarketLogic.BuildMarketHistorySeries(hourlyByHour)
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

local DAY = 24 * 3600

--- One pass over `auction.history.hourly[storageKey]`: 7-day and 24-hour averages, range and listed quantity.
--- Listed quantity per hour is the bucket's summed sample size divided by its observation count.
function MarketLogic.SummarizeHourlyHistory(hourlyByHour, now)
	local out = { hours = 0 }
	if type(hourlyByHour) ~= "table" then
		return out
	end
	now = tonumber(now) or 0
	local sum7, sum24, n24, qtySum = 0, 0, 0, 0
	for hourKey, bucket in pairs(hourlyByHour) do
		local at = tonumber(hourKey)
		local avg = type(bucket) == "table" and historyBucketAvg(bucket) or nil
		if at and avg and avg > 0 and at >= now - 7 * DAY then
			local count = math.max(1, tonumber(bucket.n or bucket.count) or 1)
			local qty = (tonumber(bucket.q or bucket.weightedQty) or 0) / count
			out.hours = out.hours + 1
			sum7 = sum7 + avg
			qtySum = qtySum + qty
			local low = tonumber(bucket.m or bucket.min) or avg
			local high = tonumber(bucket.x or bucket.max) or avg
			out.low7d = out.low7d and math.min(out.low7d, low) or low
			out.high7d = out.high7d and math.max(out.high7d, high) or high
			if at >= now - DAY then
				sum24 = sum24 + avg
				n24 = n24 + 1
			end
			if not out.lastAt or at > out.lastAt then
				out.lastAt = at
				out.lastPrice = tonumber(bucket.l or bucket.last) or avg
				out.qtyNow = qty
			end
		end
	end
	if out.hours > 0 then
		out.avg7d = sum7 / out.hours
		out.qtyAvg7d = qtySum / out.hours
	end
	if n24 > 0 then
		out.avg24h = sum24 / n24
	end
	return out
end

--- Deal and mover flags for one item. `ref` is the reference price (external value or own average);
--- `opts.refExternal` means it does not need own history. Ratios are fractions (0.3 = 30%).
function MarketLogic.ClassifyMarketItem(price, summary, ref, opts)
	opts = opts or {}
	summary = summary or {}
	price = tonumber(price)
	local out = {}
	local minHours = opts.minHours or 3
	local enoughHistory = (summary.hours or 0) >= minHours
	ref = tonumber(ref)
	if price and price > 0 and ref and ref > 0 and (opts.refExternal or enoughHistory) then
		out.discount = (ref - price) / ref
		out.isDeal = out.discount >= (opts.dealThreshold or 0.3)
		out.gain = ref * (1 - (opts.ahCut or 0.05)) - price
	end
	local avg = tonumber(summary.avg7d)
	if price and price > 0 and avg and avg > 0 and enoughHistory then
		out.change = (price - avg) / avg
		local mover = opts.moverThreshold or 0.15
		out.isRiser = out.change >= mover
		out.isFaller = out.change <= -mover
	end
	local qtyAvg = tonumber(summary.qtyAvg7d)
	if qtyAvg and qtyAvg > 0 and summary.qtyNow and enoughHistory then
		out.supplyChange = (summary.qtyNow - qtyAvg) / qtyAvg
	end
	return out
end

--- The `n` rows with the largest (or smallest, when `asc`) numeric `key`; rows without the key are skipped.
function MarketLogic.TopN(rows, n, key, asc)
	local out = {}
	for _, row in ipairs(rows or {}) do
		if tonumber(row[key]) then
			out[#out + 1] = row
		end
	end
	table.sort(out, function(a, b)
		if asc then
			return a[key] < b[key]
		end
		return a[key] > b[key]
	end)
	for index = #out, (n or #out) + 1, -1 do
		out[index] = nil
	end
	return out
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

-- One item can be saved under several keys: the full scan's entry per item ID, a commodity entry
-- from a live search, and one entry per variant (item level, suffix). True when `row` should be
-- shown instead of `other`: the newer one, and on a tie the full scan's entry (the shortest item key).
local function marketRowWins(row, other)
	local seen, otherSeen = row.seenAt or 0, other.seenAt or 0
	if seen ~= otherSeen then
		return seen > otherSeen
	end
	if row.scope ~= other.scope then
		return row.scope == "item"
	end
	return #row.storageKey < #other.storageKey
end

--- Build Market browser rows from snapshot roots, one row per item ID (see marketRowWins).
--- resolveName(itemID) optional; query is plain substring (lowered by caller or here).
function MarketLogic.BuildMarketBrowserRows(commodities, items, options)
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

	local byItemID = {}
	local function absorb(root, scope)
		for storageKey, entry in pairs(root or {}) do
			local fields = MarketLogic.NormalizeMarketSnapshotFields(entry)
			local itemID = FL.ParseItemIDFromStorageKey(storageKey)
			if fields and itemID then
				local row = {
					storageKey = storageKey,
					itemID = itemID,
					scope = scope,
					price = fields.price,
					marketHigh = fields.marketHigh or fields.price,
					sampleSize = fields.sampleSize,
					listingCount = fields.listingCount,
					seenAt = fields.seenAt,
					source = fields.source,
				}
				if not byItemID[itemID] or marketRowWins(row, byItemID[itemID]) then
					byItemID[itemID] = row
				end
			end
		end
	end
	absorb(commodities, "commodity")
	absorb(items, "item")
	local rows = {}
	for itemID, row in pairs(byItemID) do
		row.name = (type(resolveName) == "function" and resolveName(itemID)) or ("#" .. tostring(itemID))
		if marketRowMatchesQuery(row, query) then
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		return compareMarketRows(a, b, sortKey, sortAsc)
	end)
	return rows
end

local function isEmptySelection(set)
	return type(set) ~= "table" or next(set) == nil
end

local function marketInfoMatches(info, filters)
	if not isEmptySelection(filters.classes) and not filters.classes[info.classLabel or ""] then
		return false
	end
	if not isEmptySelection(filters.subclasses) and not filters.subclasses[info.subclassLabel or ""] then
		return false
	end
	return isEmptySelection(filters.qualities) or (info.quality ~= nil and filters.qualities[info.quality])
end

--- Narrows Market rows. filters: classes, subclasses, qualities (sets keyed by label / quality number;
--- empty or nil = any), owned (set of item IDs, used when ownedOnly), minPrice / maxPrice (copper).
--- getInfo(itemID) returns { classLabel, subclassLabel, quality }, asked once per row after the price
--- and owned checks. A quality filter hides items whose quality is not known yet.
function MarketLogic.FilterMarketRows(rows, filters, getInfo)
	filters = filters or {}
	local minPrice, maxPrice = tonumber(filters.minPrice), tonumber(filters.maxPrice)
	local needInfo = not (isEmptySelection(filters.classes) and isEmptySelection(filters.subclasses) and isEmptySelection(filters.qualities))
	return Tradewright.FilterLogic.KeepRows(rows, {
		{ "minPrice", minPrice ~= nil, function(row)
			return (tonumber(row.price) or 0) >= minPrice
		end },
		{ "maxPrice", maxPrice ~= nil, function(row)
			return (tonumber(row.price) or 0) <= maxPrice
		end },
		{ "owned", filters.ownedOnly, function(row)
			return filters.owned and filters.owned[row.itemID]
		end },
		{ "itemInfo", needInfo, function(row)
			return marketInfoMatches(getInfo and getInfo(row.itemID) or {}, filters)
		end },
	})
end

-- Where a click on a dashboard deal goes: left click shows the item details; right click opens the
-- auction house buy page while the auction house is open, else the Market tab.
function MarketLogic.ResolveDealRowClick(button, ahOpen)
	if button ~= "RightButton" then
		return "details"
	end
	return ahOpen and "auction" or "market"
end
