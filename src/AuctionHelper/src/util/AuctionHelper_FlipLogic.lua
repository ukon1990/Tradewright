local _, ProfessionExporter = ...

--- Pure flip maths for the Opportunities tab (offline-testable, no WoW API). Builds on MarketSignals.
local FlipLogic = {}
ProfessionExporter.FlipLogic = FlipLogic

local DEFAULTS = { minDiscount = 0.25, minProfit = 50000, minSellsPerDay = 1, dayShare = 1 / 3, cut = 0.05 }

local function option(opts, key)
	local value = opts and tonumber(opts[key])
	return value or DEFAULTS[key]
end

-- How many to buy and what it costs. With price steps: everything listed at or under the limit price,
-- capped at a share of a day's sales. Without: one unit at the lowest price, quantity unknown.
local function flipQuantity(item, limitPrice, opts)
	local MS = ProfessionExporter.MarketSignals
	if not (item.steps and #item.steps > 0) then
		return { units = 1, cost = item.price }
	end
	local listedUnder = MS.CostToClear(item.steps, limitPrice).qty
	local cap = math.max(1, math.ceil(option(opts, "dayShare") * item.sellsPerDay))
	local buyQty = math.min(listedUnder, cap)
	if buyQty < 1 then
		return nil
	end
	return { units = buyQty, buyQty = buyQty, listedUnder = listedUnder, cost = MS.AverageFill(item.steps, buyQty) * buyQty }
end

local function isCandidate(item, opts)
	local usual, price, sells = tonumber(item.usual), tonumber(item.price), tonumber(item.sellsPerDay)
	if not (usual and price and sells) or usual <= 0 or price <= 0 then
		return false
	end
	return (usual - price) / usual >= option(opts, "minDiscount") and sells >= option(opts, "minSellsPerDay")
end

--- One flip row for `item = { itemID, storageKey, price, usual, sellsPerDay, confidence, steps, depositLoss }`,
--- or nil when it is not worth showing. Profit is after the cut and the expected deposit loss.
function FlipLogic.BuildFlipRow(item, opts)
	if not isCandidate(item, opts) then
		return nil
	end
	local cut = option(opts, "cut")
	local limitPrice = item.usual * (1 - option(opts, "minDiscount"))
	local buy = flipQuantity(item, limitPrice, opts)
	if not buy then
		return nil
	end
	local profit = buy.units * item.usual * (1 - cut) - buy.cost - (tonumber(item.depositLoss) or 0) * buy.units
	if profit < option(opts, "minProfit") then
		return nil
	end
	return {
		itemID = item.itemID, storageKey = item.storageKey, price = item.price, usual = item.usual,
		discount = (item.usual - item.price) / item.usual, limitPrice = limitPrice,
		buyQty = buy.buyQty, listedUnder = buy.listedUnder, cost = buy.cost,
		profit = profit, profitEach = profit / buy.units, roi = profit / buy.cost,
		saleNet = item.usual * (1 - cut), breakEven = buy.cost / buy.units / (1 - cut),
		sellsPerDay = item.sellsPerDay, depositLoss = tonumber(item.depositLoss) or 0,
		slow = buy.buyQty ~= nil and buy.buyQty > item.sellsPerDay,
		fewSales = item.confidence == "few",
	}
end

--- Flip rows for a list of items, most profit first.
function FlipLogic.BuildFlipRows(items, opts)
	local rows = {}
	for _, item in ipairs(items or {}) do
		local row = FlipLogic.BuildFlipRow(item, opts)
		if row then
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		return a.profit > b.profit
	end)
	return rows
end

-- Units listed under `vendorSell` and what they cost. Without price steps: one unit at the lowest price.
local function underVendor(item)
	if not (item.steps and #item.steps > 0) then
		return 1, item.price
	end
	local qty, cost = 0, 0
	for index = 1, #item.steps, 2 do
		if item.steps[index] >= item.vendorSell then
			break
		end
		qty = qty + item.steps[index + 1]
		cost = cost + item.steps[index] * item.steps[index + 1]
	end
	return qty, cost
end

--- One "sure thing" row for `item = { itemID, storageKey, price, vendorSell, steps }`: units listed
--- below what a vendor pays, or nil. The gain has no auction cut: the items are sold to a vendor.
function FlipLogic.BuildVendorRow(item, opts)
	local price, vendorSell = tonumber(item.price), tonumber(item.vendorSell)
	if not (price and vendorSell) or price <= 0 or price >= vendorSell then
		return nil
	end
	local qty, cost = underVendor(item)
	local gain = qty * vendorSell - cost
	if qty < 1 or gain < (opts and tonumber(opts.minGain) or 1000) then
		return nil
	end
	return {
		itemID = item.itemID, storageKey = item.storageKey, price = price, vendorSell = vendorSell,
		qty = qty, cost = cost, gain = gain, qtyKnown = item.steps ~= nil and #item.steps > 0,
	}
end

--- Sure-thing rows for a list of items, most gain first.
function FlipLogic.BuildVendorRows(items, opts)
	local rows = {}
	for _, item in ipairs(items or {}) do
		local row = FlipLogic.BuildVendorRow(item, opts)
		if row then
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		return a.gain > b.gain
	end)
	return rows
end

return FlipLogic
