local _, AuctionHelper = ...

--- Pure farm-run maths (E09). A run is `{ name, zone, startedAt, endedAt, pausedSeconds, pausedAt,
--- coin, vendorSold, items = { [itemID] = qty } }`. No WoW API.
local FarmLogic = {}
AuctionHelper.FarmLogic = FarmLogic

--- Seconds the run was active: wall time less pauses, including a pause still in progress.
function FarmLogic.ActiveSeconds(run, now)
	local finish = tonumber(run.endedAt) or tonumber(now) or 0
	local paused = tonumber(run.pausedSeconds) or 0
	if run.pausedAt and not run.endedAt then
		paused = paused + math.max(0, finish - run.pausedAt)
	end
	return math.max(0, finish - (tonumber(run.startedAt) or finish) - paused)
end

local function option(opts, key, default)
	return opts and tonumber(opts[key]) or default
end

-- Usual price after the cut for an item with enough known turnover, else nil.
local function auctionNet(price, opts)
	local usual, sells = tonumber(price.usual), tonumber(price.sellsPerDay)
	if not (usual and sells) or sells < option(opts, "minSellsPerDay", 1) then
		return nil
	end
	return usual * (1 - option(opts, "cut", 0.05))
end

--- What one looted item counts for. `price = { vendor, usual, sellsPerDay }`, any of them nil.
--- An item with enough known turnover counts at the better of its vendor price and its usual price
--- after the cut ("auction"); anything else counts at vendor price ("vendor"). Returns `value, kind`.
function FarmLogic.ItemValue(price, opts)
	price = price or {}
	local vendor = tonumber(price.vendor) or 0
	local net = auctionNet(price, opts)
	if net and net > vendor then
		return net, "auction"
	end
	return vendor, "vendor"
end

local function addItems(out, run, priceFn, opts)
	for itemID, qty in pairs(run.items or {}) do
		local value, kind = FarmLogic.ItemValue(priceFn(itemID), opts)
		local total = value * qty
		out.byItem[#out.byItem + 1] = { itemID = itemID, qty = qty, value = total, kind = kind }
		if kind == "auction" then
			out.auctionValue = out.auctionValue + total
		else
			out.vendorValue = out.vendorValue + total
		end
	end
	table.sort(out.byItem, function(a, b)
		return a.value > b.value
	end)
end

--- Value of a run at the prices `priceFn(itemID)` gives now:
--- `{ coin, vendorSold, vendorValue, auctionValue, total, activeSeconds, perHour, byItem }`.
--- The three parts stay separate: coin picked up, vendor value (sold or still held), auction estimate.
function FarmLogic.SummarizeRun(run, priceFn, now, opts)
	local out = {
		coin = tonumber(run.coin) or 0, vendorSold = tonumber(run.vendorSold) or 0,
		vendorValue = 0, auctionValue = 0, byItem = {},
		activeSeconds = FarmLogic.ActiveSeconds(run, now),
	}
	addItems(out, run, priceFn, opts)
	out.total = out.coin + out.vendorSold + out.vendorValue + out.auctionValue
	out.perHour = out.activeSeconds > 0 and out.total / out.activeSeconds * 3600 or 0
	return out
end

--- Take `qty` of an item out of a run (it was sold to a vendor, so its gold is counted there).
function FarmLogic.RemoveItems(run, itemID, qty)
	local have = run.items and run.items[itemID]
	if not have then
		return 0
	end
	local removed = math.min(have, qty)
	run.items[itemID] = have > removed and have - removed or nil
	return removed
end

local function number(value)
	return tonumber(value) or 0
end

-- Every run of a farm folded into one: summed items, coin, vendor sales, time and value when saved.
local function combineRuns(farm)
	local all = { items = {}, coin = 0, vendorSold = 0, activeSeconds = 0, valueWhenSaved = 0, lastRunAt = 0, runs = 0 }
	for _, run in ipairs(farm.runs or {}) do
		for itemID, qty in pairs(run.items or {}) do
			all.items[itemID] = (all.items[itemID] or 0) + qty
		end
		all.coin = all.coin + number(run.coin)
		all.vendorSold = all.vendorSold + number(run.vendorSold)
		all.activeSeconds = all.activeSeconds + number(run.activeSeconds)
		all.valueWhenSaved = all.valueWhenSaved + number(run.valueWhenSaved)
		all.lastRunAt = math.max(all.lastRunAt, number(run.endedAt))
		all.runs = all.runs + 1
	end
	return all
end

local function perHour(value, seconds)
	return seconds > 0 and value / seconds * 3600 or 0
end

--- A saved farm at the prices `priceFn(itemID)` gives now: `{ runs, activeSeconds, lastRunAt,
--- valueWhenSaved, thenPerHour, nowPerHour, changePct, liquidShare, coinShare, perHourByItem }`.
--- "Then" is what the runs were worth when saved; "now" values the same loot at today's prices.
function FarmLogic.SummarizeFarm(farm, priceFn, opts)
	local all = combineRuns(farm)
	local now = FarmLogic.SummarizeRun({ items = all.items, coin = all.coin, vendorSold = all.vendorSold }, priceFn, 0, opts)
	local out = {
		runs = all.runs, activeSeconds = all.activeSeconds, lastRunAt = all.lastRunAt, valueWhenSaved = all.valueWhenSaved,
		thenPerHour = perHour(all.valueWhenSaved, all.activeSeconds), nowPerHour = perHour(now.total, all.activeSeconds),
		liquidShare = now.total > 0 and now.auctionValue / now.total or 0,
		coinShare = now.total > 0 and (now.total - now.auctionValue) / now.total or 0,
		perHourByItem = {},
	}
	if out.thenPerHour > 0 then
		out.changePct = (out.nowPerHour - out.thenPerHour) / out.thenPerHour
	end
	for index, item in ipairs(now.byItem) do
		out.perHourByItem[index] = {
			itemID = item.itemID, kind = item.kind,
			qtyPerHour = perHour(item.qty, all.activeSeconds), valuePerHour = perHour(item.value, all.activeSeconds),
		}
	end
	return out
end

--- For each item ever looted in a saved farm, the farm with the highest units an hour:
--- `{ [itemID] = { farm = name, perHour = units } }`. `farms` is `{ [name] = { runs = { … } } }`.
function FarmLogic.BuildLootIndex(farms)
	local index = {}
	for name, farm in pairs(farms or {}) do
		local all = combineRuns(farm)
		for itemID, qty in pairs(all.items) do
			local rate = perHour(qty, all.activeSeconds)
			if rate > 0 and (not index[itemID] or rate > index[itemID].perHour) then
				index[itemID] = { farm = name, perHour = rate }
			end
		end
	end
	return index
end

local function targetWanted(item, source, opts)
	if opts.onlyRecipes and not item.usedByRecipes then
		return false
	end
	return not (opts.onlyFarmed and not source)
end

-- An item ranks only when its usual price and sells a day are both known, unless it is an early estimate.
local function targetPrices(item)
	local usual, sells = tonumber(item.usual), tonumber(item.sellsPerDay)
	sells = sells and sells > 0 and sells or nil
	if not usual or usual <= 0 or not (sells or item.early) then
		return nil
	end
	return usual, sells
end

-- One "what to farm" row, or nil when the item is not known to sell or a filter leaves it out.
local function targetRow(item, source, opts)
	local usual, sells = targetPrices(item)
	if not usual or not targetWanted(item, source, opts) then
		return nil
	end
	local row = {
		itemID = item.itemID, storageKey = item.storageKey, usual = usual, sellsPerDay = sells,
		tradedPerDay = sells and usual * sells, daysOfSupply = sells and number(item.quantity) / sells,
		listedValue = usual * number(item.quantity), supplyChange = item.supplyChange,
		usedByRecipes = item.usedByRecipes == true, early = item.early == true, days = item.days,
	}
	if source then
		row.source, row.sourcePerHour = source.farm, source.perHour
		row.yoursPerHour = source.perHour * usual * (1 - option(opts, "cut", 0.05))
	end
	return row
end

--- Sort value of a "what to farm" row: gold traded a day when sales are known. An early estimate without
--- sales sorts below every such row (a negative value), ordered by the gold listed on the auction house.
function FarmLogic.TargetRank(row)
	return row.tradedPerDay or -1 / (1 + (row.listedValue or 0))
end

--- "What to farm" rows from `items = { { itemID, usual, sellsPerDay, quantity, supplyChange, usedByRecipes,
--- early, days } }` and a loot index, best `TargetRank` first. `early` items (too little history) may lack
--- sells a day. `tradedPerDay` is a ranking, not income: it inherits the upward bias of the sells-a-day
--- estimate. `yoursPerHour` is your own rate at the usual price after the cut.
function FarmLogic.BuildFarmTargets(items, lootIndex, opts)
	opts = opts or {}
	local rows = {}
	for _, item in ipairs(items or {}) do
		rows[#rows + 1] = targetRow(item, lootIndex and lootIndex[item.itemID], opts)
	end
	table.sort(rows, function(a, b)
		return FarmLogic.TargetRank(a) > FarmLogic.TargetRank(b)
	end)
	return rows
end

local function activeFilterNames(opts)
	local names = {}
	if opts.onlyRecipes then
		names[#names + 1] = "\"My recipes use it\""
	end
	if opts.onlyFarmed then
		names[#names + 1] = "\"Only farmed before\""
	end
	return names
end

--- Title and hint for an empty "what to farm" list, saying which step is missing.
--- `counts = { tradeGoods = scanned trade goods, priced = those with a usual price and sells a day }`.
function FarmLogic.FarmTargetsEmptyText(counts, opts)
	local tradeGoods, priced = tonumber(counts.tradeGoods) or 0, tonumber(counts.priced) or 0
	if tradeGoods == 0 then
		return "No trade goods scanned yet", "Run a full auction house scan."
	end
	local names = activeFilterNames(opts or {})
	if priced == 0 or #names == 0 then
		return "Not enough price history yet", string.format(
			"%d trade goods scanned. Each needs full scans on 5 different days, or turn on Early estimates.", tradeGoods)
	end
	return "Hidden by filters", string.format("%d trade goods hidden by %s.", priced, table.concat(names, " and "))
end

return FarmLogic
