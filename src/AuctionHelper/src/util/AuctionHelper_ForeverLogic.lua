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
--- Storage keys: commodities "<region>:<itemID>"; items "<region>:<realmID>:<itemID>[:<ilvl>:<suffix>:<pet>]".
--- The item ID sits at a fixed position; keys that do not have one there (such as legacy keys built
--- from a table's address, "<region>:<realm>:table: 0x…") return nil.
function ForeverLogic.ParseItemIDFromStorageKey(storageKey)
	if type(storageKey) ~= "string" or storageKey == "" then
		return nil
	end
	local parts = {}
	for part in (storageKey .. ":"):gmatch("([^:]*):") do
		parts[#parts + 1] = part
	end
	local idPart = #parts == 2 and parts[2] or parts[3]
	local itemID = idPart and idPart:match("^%d+$") and tonumber(idPart)
	if itemID and itemID > 0 then
		return itemID
	end
	return nil
end

--- The item part of an item storage key. A C_AuctionHouse item key table becomes
--- "<itemID>:<ilvl>:<suffix>:<pet>"; anything else becomes the plain item ID.
function ForeverLogic.SerializeItemKey(itemKey, itemID)
	if type(itemKey) == "table" then
		local id = tonumber(itemKey.itemID) or tonumber(itemID) or 0
		local ilvl = math.floor(tonumber(itemKey.itemLevel) or 0)
		local suffix = math.floor(tonumber(itemKey.itemSuffix) or 0)
		local pet = math.floor(tonumber(itemKey.battlePetSpeciesID) or 0)
		if ilvl == 0 and suffix == 0 and pet == 0 then
			return tostring(id)
		end
		return string.format("%d:%d:%d:%d", id, ilvl, suffix, pet)
	end
	if itemKey ~= nil and tostring(itemKey):match("^%d+[%d:]*$") then
		return tostring(itemKey)
	end
	return tostring(tonumber(itemID) or 0)
end

--- One-time repair of item snapshot / history entries stored under a table address. The item ID is
--- recovered from `indexes.byItemID`; `buildKey(itemID)` returns the correct key. Entries that cannot
--- be traced back to an item are dropped. Returns the number of entries moved.
function ForeverLogic.RepairAuctionStorageKeys(auction, buildKey)
	if type(auction) ~= "table" or type(buildKey) ~= "function" then
		return 0
	end
	local snapshot = auction.snapshot and auction.snapshot.items or {}
	local hourly = auction.history and auction.history.hourly or {}
	local byItemID = auction.indexes and auction.indexes.byItemID or {}
	local function isBroken(key)
		return type(key) == "string" and key:find("table:", 1, true) ~= nil
	end
	local moved = 0
	for itemIDText, keys in pairs(byItemID) do
		local itemID = tonumber(itemIDText)
		local brokenKeys = {}
		if itemID and type(keys) == "table" then
			for key in pairs(keys) do
				if isBroken(key) then
					brokenKeys[#brokenKeys + 1] = key
				end
			end
		end
		for _, oldKey in ipairs(brokenKeys) do
			local newKey = buildKey(itemID)
			local entry = snapshot[oldKey]
			if entry then
				local existing = snapshot[newKey]
				local entryAt = tonumber(entry.t or entry.seenAt) or 0
				local existingAt = existing and (tonumber(existing.t or existing.seenAt) or 0) or -1
				if entryAt >= existingAt then
					snapshot[newKey] = entry
				end
				moved = moved + 1
			end
			if hourly[oldKey] and not hourly[newKey] then
				hourly[newKey] = hourly[oldKey]
			end
			keys[oldKey] = nil
			keys[newKey] = true
		end
	end
	for _, root in ipairs({ snapshot, hourly }) do
		for key in pairs(root) do
			if isBroken(key) then
				root[key] = nil
			end
		end
	end
	return moved
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

local DAY = 24 * 3600

--- One pass over `auction.history.hourly[storageKey]`: 7-day and 24-hour averages, range and listed quantity.
--- Listed quantity per hour is the bucket's summed sample size divided by its observation count.
function ForeverLogic.SummarizeHourlyHistory(hourlyByHour, now)
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
function ForeverLogic.ClassifyMarketItem(price, summary, ref, opts)
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
function ForeverLogic.TopN(rows, n, key, asc)
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

	local byItemID = {}
	local function absorb(root, scope)
		for storageKey, entry in pairs(root or {}) do
			local fields = ForeverLogic.NormalizeMarketSnapshotFields(entry)
			local itemID = ForeverLogic.ParseItemIDFromStorageKey(storageKey)
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

--- Narrows Market rows. filters: classes, subclasses, qualities (sets keyed by label / quality number;
--- empty or nil = any), owned (set of item IDs, used when ownedOnly), minPrice / maxPrice (copper).
--- getInfo(itemID) returns { classLabel, subclassLabel, quality }. A quality filter hides items whose
--- quality is not known yet.
function ForeverLogic.FilterMarketRows(rows, filters, getInfo)
	filters = filters or {}
	local function any(set)
		return type(set) ~= "table" or next(set) == nil
	end
	local needInfo = not any(filters.classes) or not any(filters.subclasses) or not any(filters.qualities)
	local minPrice, maxPrice = tonumber(filters.minPrice), tonumber(filters.maxPrice)
	local out = {}
	for _, row in ipairs(rows or {}) do
		local keep = true
		local price = tonumber(row.price) or 0
		if minPrice and price < minPrice then
			keep = false
		elseif maxPrice and price > maxPrice then
			keep = false
		elseif filters.ownedOnly and not (filters.owned and filters.owned[row.itemID]) then
			keep = false
		elseif needInfo then
			local info = getInfo and getInfo(row.itemID) or {}
			if not any(filters.classes) and not filters.classes[info.classLabel or ""] then
				keep = false
			elseif not any(filters.subclasses) and not filters.subclasses[info.subclassLabel or ""] then
				keep = false
			elseif not any(filters.qualities) and (info.quality == nil or not filters.qualities[info.quality]) then
				keep = false
			end
		end
		if keep then
			out[#out + 1] = row
		end
	end
	return out
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
--- Retail keeps the modern sell frame (SetPostItem) only when it exists; Forever always may use classic.
--- Clients without the modern sell frame may use classic even when not Forever.
function ForeverLogic.ShouldUseClassicSellInject(isForever, hasModernSellFrame)
	if isForever == true then
		return true
	end
	return hasModernSellFrame ~= true
end

---- Totals and undercut flags for the player's own auctions.
--- auctions: { { itemID, quantity, sold, buyout, bid, deposit } } — the price is per unit while listed
--- and the whole incoming amount once sold; deposit is the listing's whole deposit, nil when unknown
--- or not counted. lowestByItem[itemID] is the lowest scanned unit price, if any.
--- Each row gets `undercut`: true / false, or nil when the item has no scanned price to compare;
--- undercut rows also get `undercutBy` (copper per unit) and `undercutPct` (of the player's price).
--- ahCut (fraction, default 0.05) gives `net`, what a listing pays out after the auction house cut,
--- and for undercut rows `repostNet`, the payout if it were cancelled (forfeiting the deposit) and
--- reposted at the lowest scanned price.
function ForeverLogic.SummarizeOwnedAuctions(auctions, lowestByItem, ahCut)
	local keep = 1 - (tonumber(ahCut) or 0.05)
	local rows = {}
	local totals = { soldValue = 0, soldCount = 0, listedValue = 0, listedNet = 0, listedCount = 0, undercutCount = 0 }
	for _, auction in ipairs(auctions or {}) do
		local quantity = math.max(1, tonumber(auction.quantity) or 1)
		local price = tonumber(auction.buyout) or tonumber(auction.bid) or 0
		local row = { auctionID = auction.auctionID, itemID = auction.itemID, quantity = quantity, sold = auction.sold == true }
		if row.sold then
			row.value = price
			totals.soldValue = totals.soldValue + price
			totals.soldCount = totals.soldCount + 1
		else
			row.unitPrice = price
			row.value = price * quantity
			row.net = math.floor(row.value * keep)
			row.deposit = tonumber(auction.deposit)
			row.marketPrice = tonumber(lowestByItem and lowestByItem[auction.itemID])
			if row.marketPrice and price > 0 then
				row.undercut = row.marketPrice < price
				if row.undercut then
					row.undercutBy = price - row.marketPrice
					row.undercutPct = row.undercutBy / price * 100
					row.repostNet = math.floor(row.marketPrice * quantity * keep) - (row.deposit or 0)
				end
			end
			totals.listedValue = totals.listedValue + row.value
			totals.listedNet = totals.listedNet + row.net
			totals.listedCount = totals.listedCount + 1
			totals.undercutCount = totals.undercutCount + (row.undercut and 1 or 0)
		end
		rows[#rows + 1] = row
	end
	return rows, totals
end

--- Sales statistics from ledger events (kind "sell": ts, itemID / itemName, quantity, totalCopper
--- gross, netCopper after the auction house cut). `days` limits to the last N days; nil is all time.
--- Returns { totals, items, daily, recent, spanDays }: items carry sales, units, net, avgUnit,
--- perWeek (sales per week over the span) and lastAt; daily is { at, value } net per day, oldest
--- first; recent is the matching events, newest first.
function ForeverLogic.SummarizeSales(events, now, days)
	local since = days and (now - days * 86400) or 0
	local totals = { net = 0, gross = 0, sales = 0, units = 0 }
	local byItem, items, byDay, daily, recent = {}, {}, {}, {}, {}
	local firstAt = now
	for _, event in ipairs(events or {}) do
		local ts = tonumber(event.ts) or 0
		if event.kind == "sell" and ts >= since then
			local gross = tonumber(event.totalCopper) or 0
			local net = tonumber(event.netCopper) or gross
			local units = tonumber(event.quantity) or 1
			local key = event.itemID or event.itemName
			local item = byItem[key]
			if not item then
				item = { itemID = event.itemID, name = event.itemName, sales = 0, units = 0, net = 0, gross = 0, lastAt = 0 }
				byItem[key] = item
				items[#items + 1] = item
			end
			item.sales, item.units = item.sales + 1, item.units + units
			item.net, item.gross = item.net + net, item.gross + gross
			item.lastAt = math.max(item.lastAt, ts)
			totals.sales, totals.units = totals.sales + 1, totals.units + units
			totals.net, totals.gross = totals.net + net, totals.gross + gross
			firstAt = math.min(firstAt, ts)
			local day = math.floor(ts / 86400)
			if not byDay[day] then
				byDay[day] = { at = day * 86400 + 43200, value = 0 }
				daily[#daily + 1] = byDay[day]
			end
			byDay[day].value = byDay[day].value + net
			recent[#recent + 1] = event
		end
	end
	local spanDays = days or math.max(1, (now - firstAt) / 86400)
	for _, item in ipairs(items) do
		item.avgUnit = item.units > 0 and item.gross / item.units or nil
		item.perWeek = item.sales / spanDays * 7
	end
	table.sort(daily, function(a, b) return a.at < b.at end)
	table.sort(recent, function(a, b) return (tonumber(a.ts) or 0) > (tonumber(b.ts) or 0) end)
	return { totals = totals, items = items, daily = daily, recent = recent, spanDays = spanDays }
end

--- The auction house / bank character chosen for `realm`, or nil when none is chosen or the
--- chosen character is no longer known. sellerByRealm[realm] = characterKey ("" means none).
function ForeverLogic.ResolveSellerCharacter(sellerByRealm, realm, knownCharacters)
	local key = type(sellerByRealm) == "table" and realm and sellerByRealm[realm] or nil
	if type(key) ~= "string" or key == "" or not (knownCharacters and knownCharacters[key]) then
		return nil
	end
	return key
end

--- Shares the bag stock out over the characters that need materials mailed to them.
--- lines: { { itemID, name, allocations = { { characterKey, mailQuantity } } } }; stock[itemID] is
--- what the bags hold. Returns the destinations that get at least one item, sorted by character:
--- { characterKey, mailName, items = { { itemID, quantity, name } }, totalQuantity,
--- missing = { { itemID, quantity, name } }, complete }. A destination is complete when everything
--- it needs mailed is in the bags; earlier lines and characters are served first.
function ForeverLogic.BuildMailPlan(lines, stock)
	local left, byKey, out = {}, {}, {}
	for _, line in ipairs(lines or {}) do
		local itemID = line.itemID
		left[itemID] = left[itemID] or tonumber(stock and stock[itemID]) or 0
		for _, alloc in ipairs(line.allocations or {}) do
			local key = tostring(alloc.characterKey or "")
			local need = tonumber(alloc.mailQuantity) or 0
			if key ~= "" and need > 0 then
				local dest = byKey[key]
				if not dest then
					dest = { characterKey = key, mailName = key:match("^([^%-]+)") or key, items = {}, missing = {}, totalQuantity = 0 }
					byKey[key] = dest
				end
				local send = math.min(need, left[itemID])
				left[itemID] = left[itemID] - send
				if send > 0 then
					dest.items[#dest.items + 1] = { itemID = itemID, quantity = send, name = line.name }
					dest.totalQuantity = dest.totalQuantity + send
				end
				if send < need then
					dest.missing[#dest.missing + 1] = { itemID = itemID, quantity = need - send, name = line.name }
				end
			end
		end
	end
	for _, dest in pairs(byKey) do
		if #dest.items > 0 then
			dest.complete = #dest.missing == 0
			out[#out + 1] = dest
		end
	end
	table.sort(out, function(a, b) return a.characterKey < b.characterKey end)
	return out
end

--- Crafted items waiting to go back to the seller, clamped to what the bags still hold.
--- toSeller[itemID] = quantity owed, bagItems[itemID] = { quantity, name }. Returns no destination
--- without a seller or without anything to send, else one: { kind = "crafts", characterKey,
--- mailName, items = { { itemID, quantity, name } }, totalQuantity }, items sorted by name.
function ForeverLogic.BuildReturnToSellerPlan(toSeller, bagItems, sellerKey)
	local dest = { kind = "crafts", characterKey = sellerKey, mailName = tostring(sellerKey or ""):match("^([^%-]+)"),
		items = {}, totalQuantity = 0 }
	for itemID, owed in pairs(toSeller or {}) do
		local bag = bagItems and bagItems[itemID]
		local quantity = math.min(tonumber(owed) or 0, bag and tonumber(bag.quantity) or 0)
		if quantity > 0 then
			dest.items[#dest.items + 1] = { itemID = itemID, quantity = quantity, name = bag.name }
			dest.totalQuantity = dest.totalQuantity + quantity
		end
	end
	if not sellerKey or #dest.items == 0 then
		return {}
	end
	table.sort(dest.items, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return { dest }
end

--- What a character can spare from its bags. bagItems[itemID] = { quantity, quality, sellable, name };
--- keep[itemID] is how many this character keeps; held[itemID] is how many are already spoken for
--- (its own queued crafts, other mail rows). An item with a keep amount is spare above keep + held;
--- one without is spare above held only when `sendOthers` is on. Never spare: items that are not
--- sellable or are poor quality. Returns { { itemID, quantity, name } } sorted by name.
function ForeverLogic.BuildSurplusPlan(bagItems, keep, held, sendOthers)
	local items = {}
	for itemID, bag in pairs(bagItems or {}) do
		local kept = tonumber(keep and keep[itemID])
		if bag.sellable and (tonumber(bag.quality) or 0) >= 1 and (kept or sendOthers) then
			local quantity = (tonumber(bag.quantity) or 0) - (kept or 0) - (tonumber(held and held[itemID]) or 0)
			if quantity > 0 then
				items[#items + 1] = { itemID = itemID, quantity = quantity, name = bag.name }
			end
		end
	end
	table.sort(items, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return items
end

-- Classic recipe reagent slot from (itemID, quantity).
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

-- Where a click on a dashboard deal goes: left click shows the item details; right click opens the
-- auction house buy page while the auction house is open, else the Market tab.
function ForeverLogic.ResolveDealRowClick(button, ahOpen)
	if button ~= "RightButton" then
		return "details"
	end
	return ahOpen and "auction" or "market"
end

-- True when a live auction house search differs from the saved scan entry ({ p = price, q = quantity, n = auctions }).
-- A value the search did not report (nil) is never a difference.
function ForeverLogic.LiveSearchDiffers(saved, price, quantity, listings)
	if type(saved) ~= "table" then
		return true
	end
	local function differs(old, new)
		return tonumber(new) ~= nil and tonumber(old) ~= tonumber(new)
	end
	return differs(saved.p, price) or differs(saved.q, quantity) or differs(saved.n, listings)
end

return ForeverLogic
