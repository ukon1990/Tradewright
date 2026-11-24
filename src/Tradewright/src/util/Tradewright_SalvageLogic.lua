local _, Tradewright = ...

--- Pure helpers for salvage yields: what disenchanting, prospecting and milling give, counted from
--- the player's own outcomes. No WoW API.
---
--- Outcomes are kept in the sightings store (see Tradewright_SourceLogic.lua), in epochs like its
--- loot tallies so they ship and prune the same way:
---   yields = { [epoch] = { [yieldKey] = { casts, inputs, items = { [itemID] = quantity received },
---     single, hits = { [itemID] = casts that gave it } } } }
--- `single` counts the casts recorded one at a time, the only ones that tell which cast gave what:
--- `hits` counts those per item, so `hits / single` is an item's chance per cast.
---
--- A `yieldKey` names the action and what was destroyed: "p:<itemID>" prospecting an ore,
--- "m:<itemID>" milling a herb, "d:<expansionID>:<quality>:<W or A>:<item level>" disenchanting a
--- weapon or a piece of armor. Disenchanted items are read in groups of nearby item levels (see
--- GroupKey), as no two pieces of gear are the same item.
---
--- `input = { itemID }` for ore and herbs, `{ expansionID, quality, isWeapon, itemLevel }` for gear.
local SalvageLogic = {}
Tradewright.SalvageLogic = SalvageLogic

local ACTION_PREFIX = { prospect = "p", mill = "m", disenchant = "d" }

--- The action a retail salvage recipe stands for, by its profession's skill line: Jewelcrafting
--- prospects, Inscription mills.
SalvageLogic.ACTION_BY_PROFESSION = { [755] = "prospect", [773] = "mill" }

-- Gear this many item levels apart disenchants alike; the published classic tables step by five.
SalvageLogic.DISENCHANT_LEVEL_BAND = 5
-- Own outcomes of an input are trusted over everyone's and over researched yields from this many casts.
SalvageLogic.TRUSTED_CASTS = 20

local function disenchantKey(input, itemLevel)
	return table.concat({ "d", tostring(input.expansionID or 0), tostring(input.quality or 0), input.isWeapon and "W" or "A", tostring(itemLevel) }, ":")
end

--- The key an outcome of `action` ("prospect", "mill" or "disenchant") on `input` is saved under.
function SalvageLogic.YieldKey(action, input)
	if action == "disenchant" then
		return disenchantKey(input, tonumber(input.itemLevel) or 0)
	end
	return ACTION_PREFIX[action] .. ":" .. tostring(input.itemID)
end

--- The key every input that salvages like `input` shares: its own key for ore and herbs, and for
--- gear the key with the item level rounded up to the end of its band.
function SalvageLogic.GroupKey(action, input)
	if action ~= "disenchant" then
		return SalvageLogic.YieldKey(action, input)
	end
	local band = SalvageLogic.DISENCHANT_LEVEL_BAND
	return disenchantKey(input, math.ceil((tonumber(input.itemLevel) or 0) / band) * band)
end

-- The group of a saved disenchant key; any other key is its own group.
local function groupOfKey(yieldKey)
	local head, itemLevel = yieldKey:match("^(d:.+:)(%d+)$")
	if not head then
		return yieldKey
	end
	local band = SalvageLogic.DISENCHANT_LEVEL_BAND
	return head .. tostring(math.ceil(tonumber(itemLevel) / band) * band)
end

-- The one item whose count went down between two `{ [itemID] = count }` tables: `itemID, lost`.
-- nil when none or several did.
local function singleLoss(before, after)
	local lostItemID, lostCount
	for itemID, count in pairs(before) do
		local lost = count - (after[itemID] or 0)
		if lost > 0 then
			if lostItemID then
				return nil
			end
			lostItemID, lostCount = itemID, lost
		end
	end
	return lostItemID, lostCount
end

--- What salvaging did to the bags, from the item counts before and after (`{ [itemID] = count }`):
--- `{ inputItemID, inputCount, results = { [itemID] = quantity } }`. nil unless exactly one item
--- went down and at least one went up; anything else is not one clean outcome (nothing looted yet,
--- or something unrelated moved too).
function SalvageLogic.OutcomeBetween(before, after)
	local inputItemID, inputCount = singleLoss(before, after)
	local results = {}
	for itemID, count in pairs(after) do
		local gained = count - (before[itemID] or 0)
		if gained > 0 then
			results[itemID] = gained
		end
	end
	if not inputItemID or not next(results) then
		return nil
	end
	return { inputItemID = inputItemID, inputCount = inputCount, results = results }
end

-- A cast recorded alone tells which items it gave: one more single cast, one more hit for each.
local function countSingleCast(record, results)
	record.single = (record.single or 0) + 1
	record.hits = record.hits or {}
	for itemID in pairs(results or {}) do
		record.hits[itemID] = (record.hits[itemID] or 0) + 1
	end
end

--- Records an outcome in `store`: `outcome = { input, inputCount, results, casts }`, where
--- `inputCount` of `input` were destroyed over `casts` casts (1 when left out) and gave
--- `results = { [itemID] = quantity }`.
function SalvageLogic.RecordOutcome(store, action, outcome)
	local bucket = store.yields[store.epoch] or {}
	store.yields[store.epoch] = bucket
	local key = SalvageLogic.YieldKey(action, outcome.input)
	local record = bucket[key] or { casts = 0, inputs = 0, items = {} }
	bucket[key] = record
	record.casts = record.casts + (outcome.casts or 1)
	record.inputs = record.inputs + outcome.inputCount
	for itemID, quantity in pairs(outcome.results or {}) do
		record.items[itemID] = (record.items[itemID] or 0) + quantity
	end
	if (outcome.casts or 1) == 1 then
		countSingleCast(record, outcome.results)
	end
end

local function addCounts(total, counts)
	for itemID, count in pairs(counts or {}) do
		total[itemID] = (total[itemID] or 0) + count
	end
end

-- Records saved before `single` and `hits` existed add nothing to them.
local function addRecord(total, record)
	total.casts = total.casts + record.casts
	total.inputs = total.inputs + record.inputs
	total.single = (total.single or 0) + (record.single or 0)
	total.hits = total.hits or {}
	addCounts(total.items, record.items)
	addCounts(total.hits, record.hits)
end

-- Everything `store` holds for the group, over all its epochs.
local function groupTotal(store, groupKey)
	local total = { casts = 0, inputs = 0, items = {}, single = 0, hits = {} }
	for _, bucket in pairs(store and store.yields or {}) do
		for yieldKey, record in pairs(bucket) do
			if groupOfKey(yieldKey) == groupKey then
				addRecord(total, record)
			end
		end
	end
	return total
end

-- Each item's chance per cast and the average count when it drops, from the casts recorded one at a
-- time; nil when there are none.
local function countedChances(total, perInput)
	if total.single == 0 then
		return nil
	end
	local chances = {}
	for itemID, average in pairs(perInput) do
		local chance = (total.hits[itemID] or 0) / total.single
		if chance > 0 then
			chances[itemID] = { chance = chance, each = average / chance }
		end
	end
	return chances
end

-- `{ casts, basis, inputsPerCast, perInput = { [itemID] = quantity per destroyed input }, chances }` from summed counts.
local function yieldOf(total, basis)
	local perInput = {}
	for itemID, quantity in pairs(total.items) do
		perInput[itemID] = quantity / total.inputs
	end
	return {
		casts = total.casts, basis = basis, inputsPerCast = total.inputs / total.casts, perInput = perInput,
		chances = countedChances(total, perInput),
	}
end

-- A researched row's materials, `{ [itemID] = { chance, min, max } }`, as averages per input and chances.
-- Prospecting and milling rows hold plain averages: they have no chances.
local function researchedOf(materials)
	local perInput, chances, complete = {}, {}, true
	for itemID, material in pairs(materials) do
		if type(material) == "table" then
			perInput[itemID] = material.chance * (material.min + material.max) / 2
			chances[itemID] = { chance = material.chance, min = material.min, max = material.max }
		else
			perInput[itemID], complete = material, false
		end
	end
	return perInput, complete and chances or nil
end

-- Whether a researched disenchant row covers the gear: `{ expansionID, quality, isWeapon, fromLevel, toLevel }`,
-- where a row without `isWeapon` covers weapons and armor alike.
local function rowCoversGear(row, input)
	local itemLevel = tonumber(input.itemLevel) or 0
	return row.expansionID == (input.expansionID or 0) and row.quality == input.quality
		and (row.isWeapon == nil or row.isWeapon == (input.isWeapon == true))
		and itemLevel >= row.fromLevel and itemLevel <= row.toLevel
end

--- The researched yield of `input` in `data`, the tables looked up on the web and shipped with the
--- addon (Tradewright_SalvageData.lua): `perInput, chances` (see Yield), or nil.
--- `data = { prospect = { [itemID] = yield }, mill = { [itemID] = yield }, disenchant = { row, … } }`,
--- a disenchant row being `{ expansionID, quality, isWeapon, fromLevel, toLevel, yield }`.
function SalvageLogic.ResearchedYield(data, action, input)
	local byAction = data and data[action]
	if not byAction then
		return nil
	end
	if action ~= "disenchant" then
		return byAction[input.itemID] and researchedOf(byAction[input.itemID])
	end
	for _, row in ipairs(byAction) do
		if rowCoversGear(row, input) then
			return researchedOf(row.yield)
		end
	end
	return nil
end

--- What one `input` gives on average when salvaged, or nil when nothing is known.
--- `sources = { own, shipped, researched }`: the player's saved store, the store shipped with the
--- addon (other players' counted outcomes), and the researched tables (see ResearchedYield); any of
--- them may be nil.
--- Returns `{ perInput, casts, basis, inputsPerCast, chances, ownCasts }`: `inputsPerCast` how many
--- items one cast destroyed on average (5 ore for a prospect), nil for researched yields; `chances`
--- each item's chance per cast with its count, `{ chance, min, max }` researched or `{ chance, each }`
--- counted (average count when it drops), nil when not known; `ownCasts` the player's own casts of
--- the group, counted towards TRUSTED_CASTS. The player's own outcomes win once there are enough of them
--- ("own"), as yields shift with skill and talents; then all counted outcomes ("counted"); then
--- researched yields ("researched", casts 0); last, the few counted outcomes there are.
function SalvageLogic.Yield(sources, action, input)
	local groupKey = SalvageLogic.GroupKey(action, input)
	local own = groupTotal(sources.own, groupKey)
	local ownCasts = own.casts
	local yield
	if ownCasts >= SalvageLogic.TRUSTED_CASTS then
		yield = yieldOf(own, "own")
	else
		addRecord(own, groupTotal(sources.shipped, groupKey))
		local researched, chances = SalvageLogic.ResearchedYield(sources.researched, action, input)
		if own.casts >= SalvageLogic.TRUSTED_CASTS or (own.inputs > 0 and not researched) then
			yield = yieldOf(own, "counted")
		elseif researched then
			yield = { casts = 0, basis = "researched", perInput = researched, chances = chances }
		end
	end
	if yield then
		yield.ownCasts = ownCasts
	end
	return yield
end

local ACTION_OF_PREFIX = { p = "prospect", m = "mill" }

--- Which ore or herbs `itemID` has come from, over the counted outcomes of `stores` (a list of
--- stores): `{ { action, inputItemID, perInput, inputsPerCast, casts } }`, the most giving first.
--- `perInput` is how many of the item one destroyed input gave on average. Disenchanted gear is left
--- out: a kind of gear is no item to go and buy.
function SalvageLogic.SourcesOf(stores, itemID)
	local totals = {}
	for _, store in ipairs(stores) do
		for _, bucket in pairs(store.yields or {}) do
			for yieldKey, record in pairs(bucket) do
				local prefix, inputItemID = yieldKey:match("^([pm]):(%d+)$")
				if prefix and (record.items[itemID] or 0) > 0 then
					local total = totals[yieldKey] or { casts = 0, inputs = 0, items = {} }
					totals[yieldKey] = total
					total.action, total.inputItemID = ACTION_OF_PREFIX[prefix], tonumber(inputItemID)
					addRecord(total, record)
				end
			end
		end
	end
	local sources = {}
	for _, total in pairs(totals) do
		sources[#sources + 1] = {
			action = total.action, inputItemID = total.inputItemID, casts = total.casts,
			perInput = total.items[itemID] / total.inputs, inputsPerCast = total.inputs / total.casts,
		}
	end
	table.sort(sources, function(a, b)
		if a.perInput ~= b.perInput then
			return a.perInput > b.perInput
		end
		return a.inputItemID < b.inputItemID
	end)
	return sources
end

--- What salvaging one input is worth: the yield's items at `valueOfItem(itemID)` (copper, or nil
--- when the item has no known value). Returns `value, unvalued`, the second being how many of the
--- items had no value and so count for nothing.
function SalvageLogic.Value(yield, valueOfItem)
	local value, unvalued = 0, 0
	for itemID, quantity in pairs(yield.perInput) do
		local itemValue = valueOfItem(itemID)
		if itemValue then
			value = value + quantity * itemValue
		else
			unvalued = unvalued + 1
		end
	end
	return value, unvalued
end

-- Order of preference when two uses are worth the same: the one with the least work first.
local USES = { "vendor", "auction", "salvage" }

--- The best thing to do with one item, given what each use gets for it in copper
--- (`{ vendor, auction, salvage }`, nil for a use that is not open): `use, gain`, `gain` being how
--- much more it gets than the next best use (all of it when no other use is open). nil when no use is.
function SalvageLogic.BestUse(values)
	local open = {}
	for rank, use in ipairs(USES) do
		if values[use] then
			open[#open + 1] = { use = use, value = values[use], rank = rank }
		end
	end
	if #open == 0 then
		return nil, nil
	end
	table.sort(open, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.rank < b.rank
	end)
	return open[1].use, open[1].value - (open[2] and open[2].value or 0)
end

-- Units listed below `limit` and what they cost, from price steps (`{ price, quantity, ... }`,
-- cheapest first). Without steps only the cheapest listing is known: one unit at `price`.
local function listedBelow(item, limit)
	if not (item.steps and #item.steps > 0) then
		return 1, item.price
	end
	local quantity, cost = 0, 0
	for index = 1, #item.steps, 2 do
		if item.steps[index] >= limit then
			break
		end
		quantity = quantity + item.steps[index + 1]
		cost = cost + item.steps[index] * item.steps[index + 1]
	end
	return quantity, cost
end

--- Auctions worth buying to destroy: each `item = { itemID, price, value, steps, ... }` (cheapest
--- buyout, what destroying one gives, price steps when known) whose buyout is below its value less
--- `margin` (0.15 keeps 15% of the value back for prices that move and yields that vary).
--- Returns copies of those items, most gain first, with `limit` (the highest price worth paying),
--- `quantity` and `cost` (units listed below the limit and their total price), `gain` (their value
--- less the cost) and `gainShare` (gain over cost). No auction cut: the items are bought, not sold.
function SalvageLogic.BuyBelowValue(items, margin)
	local rows = {}
	for _, item in ipairs(items) do
		local limit = item.value * (1 - margin)
		-- Steps from an older search can disagree with the cheapest buyout: no units, no row.
		local quantity, cost = listedBelow(item, limit)
		if item.price > 0 and item.price < limit and quantity > 0 then
			local row = {}
			for key, field in pairs(item) do
				row[key] = field
			end
			row.limit, row.quantity, row.cost = limit, quantity, cost
			row.gain = quantity * item.value - cost
			row.gainShare = row.gain / row.cost
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		if a.gain ~= b.gain then
			return a.gain > b.gain
		end
		return a.itemID < b.itemID
	end)
	return rows
end

return SalvageLogic
