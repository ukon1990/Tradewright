local _, ProfessionExporter = ...

--- Pure farm-run maths (E09). A run is `{ name, zone, startedAt, endedAt, pausedSeconds, pausedAt,
--- coin, vendorSold, items = { [itemID] = qty } }`. No WoW API.
local FarmLogic = {}
ProfessionExporter.FarmLogic = FarmLogic

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

return FarmLogic
