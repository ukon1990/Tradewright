local _, Tradewright = ...

-- Whether disenchant, prospecting and milling values are good enough to act on. A value rests on
-- three things: the yields (researched estimates or counted outcomes), the prices of what they give,
-- and how recent the last full scan is. The caller gathers those from the game; this file judges them.
local SalvageCheckLogic = {}
Tradewright.SalvageCheckLogic = SalvageCheckLogic

-- Days of scans a usual price needs; the Opportunities lists ask the same.
SalvageCheckLogic.USUAL_PRICE_DAYS = 5
-- Prices drift within a day. An older full scan still values items, only loosely.
SalvageCheckLogic.STALE_SCAN_SEC = 24 * 3600
-- When more than this share of what the yields give has no price, the value is mostly guesswork.
SalvageCheckLogic.MAX_UNPRICED_SHARE = 0.5

-- Each material's share of everything the yields give, by quantity: `{ [itemID] = share }`.
-- Quantity is the only weight available for an item with no price.
local function materialShares(yields)
	local quantities, total = {}, 0
	for _, yield in ipairs(yields) do
		for itemID, quantity in pairs(yield.perInput or {}) do
			quantities[itemID] = (quantities[itemID] or 0) + quantity
			total = total + quantity
		end
	end
	for itemID, quantity in pairs(quantities) do
		quantities[itemID] = total > 0 and quantity / total or 0
	end
	return quantities
end

local function byShare(a, b)
	if a.share ~= b.share then
		return a.share > b.share
	end
	return a.itemID < b.itemID
end

-- Every material with its price facts, `{ itemID, share, priced, days, usual }`, the largest share
-- first; `usual` when its price can be trusted (a vendor price, or enough days of scans).
local function materialFacts(shares, priceOf)
	local materials = {}
	for itemID, share in pairs(shares) do
		local priced, days = priceOf(itemID)
		materials[#materials + 1] = {
			itemID = itemID, share = share, priced = priced and true or false, days = days,
			usual = priced and (days == nil or days >= SalvageCheckLogic.USUAL_PRICE_DAYS) or false,
		}
	end
	table.sort(materials, byShare)
	return materials
end

-- Reasons about the materials, in the materials' order, and the share that has no price at all.
local function materialReasons(materials)
	local reasons, unpricedShare = {}, 0
	for _, material in ipairs(materials) do
		if not material.priced then
			unpricedShare = unpricedShare + material.share
			reasons[#reasons + 1] = { code = "no_price", itemID = material.itemID, share = material.share }
		elseif not material.usual then
			reasons[#reasons + 1] = { code = "few_price_days", itemID = material.itemID, days = material.days, share = material.share }
		end
	end
	return reasons, unpricedShare
end

-- Kinds of input (yield groups) valued, and how many of them rest on counted outcomes.
local function kindCounts(yields)
	local seen, kinds = {}, { total = 0, counted = 0 }
	for _, yield in ipairs(yields) do
		local kind = yield.kind or yield
		if not seen[kind] then
			seen[kind] = true
			kinds.total = kinds.total + 1
			kinds.counted = kinds.counted + (yield.basis ~= "researched" and 1 or 0)
		end
	end
	return kinds
end

local function estimatedCount(yields)
	local count = 0
	for _, yield in ipairs(yields) do
		if yield.basis == "researched" then
			count = count + 1
		end
	end
	return count
end

local function append(list, items)
	for _, item in ipairs(items) do
		list[#list + 1] = item
	end
end

-- "none", "weak" or "good" for the reasons Check found; researched yields alone keep "good" (see Check).
local function levelOf(facts, reasons, unpricedShare)
	if not facts.lastFullScanAt or unpricedShare > SalvageCheckLogic.MAX_UNPRICED_SHARE then
		return "none"
	end
	for _, reason in ipairs(reasons) do
		if reason.code ~= "estimated_yields" then
			return "weak"
		end
	end
	return "good"
end

--- Judges the facts behind a set of salvage values.
--- `facts = { now, lastFullScanAt, yields, priceOf }`: `yields` the yields in use (see
--- SalvageLogic.Yield: `{ basis, perInput, kind }`, one per item valued, `kind` its yield group),
--- `priceOf(itemID)` returning
--- whether the item has a price and how many days of scans are behind it (nil for a vendor price,
--- which needs no history).
--- Returns `{ level, reasons }`. `level` is "none" (no full scan, no yields, or most of what the
--- yields give unpriced), "weak" (any reason below but estimated yields) or "good". Researched
--- yields alone keep "good": the shipped tables agree with about 20,000 counted disenchants within
--- a few points (docs/research/salvage-yields.md), and the player cannot replace them short of 20
--- disenchants of every kind of gear. They are still named, and each value marks them.
--- `reasons` are, in this order:
--- `{ code = "no_full_scan" }`, `{ code = "no_yields" }`, `{ code = "old_scan", hours }`,
--- `{ code = "no_price", itemID, share }` and `{ code = "few_price_days", itemID, days, share }`
--- (largest share first), `{ code = "estimated_yields", count, total }`.
--- Also: `scanHours`, the last full scan's age (nil without one); `materials`, every material
--- with `{ itemID, share, priced, days, usual }`, largest share first; `kinds = { total, counted }`,
--- the kinds of input valued and those resting on counted outcomes.
function SalvageCheckLogic.Check(facts)
	local reasons = {}
	if not facts.lastFullScanAt then
		reasons[#reasons + 1] = { code = "no_full_scan" }
	end
	local scanHours = facts.lastFullScanAt and math.floor((facts.now - facts.lastFullScanAt) / 3600) or nil
	if #facts.yields == 0 then
		reasons[#reasons + 1] = { code = "no_yields" }
		return { level = "none", reasons = reasons, scanHours = scanHours, materials = {}, kinds = { total = 0, counted = 0 } }
	end
	if facts.lastFullScanAt and facts.now - facts.lastFullScanAt > SalvageCheckLogic.STALE_SCAN_SEC then
		reasons[#reasons + 1] = { code = "old_scan", hours = scanHours }
	end
	local materials = materialFacts(materialShares(facts.yields), facts.priceOf)
	local priceReasons, unpricedShare = materialReasons(materials)
	append(reasons, priceReasons)
	local estimated = estimatedCount(facts.yields)
	if estimated > 0 then
		reasons[#reasons + 1] = { code = "estimated_yields", count = estimated, total = #facts.yields }
	end
	return {
		level = levelOf(facts, reasons, unpricedShare), reasons = reasons, scanHours = scanHours,
		materials = materials, kinds = kindCounts(facts.yields),
	}
end
