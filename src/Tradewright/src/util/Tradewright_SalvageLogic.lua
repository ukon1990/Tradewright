local _, Tradewright = ...

--- Pure helpers for salvage yields: what disenchanting, prospecting and milling give, counted from
--- the player's own outcomes. No WoW API.
---
--- Outcomes are kept in the sightings store (see Tradewright_SourceLogic.lua), in epochs like its
--- loot tallies so they ship and prune the same way:
---   yields = { [epoch] = { [yieldKey] = { casts, inputs, items = { [itemID] = quantity received } } } }
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
end

local function addRecord(total, record)
	total.casts = total.casts + record.casts
	total.inputs = total.inputs + record.inputs
	for itemID, quantity in pairs(record.items) do
		total.items[itemID] = (total.items[itemID] or 0) + quantity
	end
end

-- Everything `store` holds for the group, over all its epochs.
local function groupTotal(store, groupKey)
	local total = { casts = 0, inputs = 0, items = {} }
	for _, bucket in pairs(store and store.yields or {}) do
		for yieldKey, record in pairs(bucket) do
			if groupOfKey(yieldKey) == groupKey then
				addRecord(total, record)
			end
		end
	end
	return total
end

-- `{ casts, basis, inputsPerCast, perInput = { [itemID] = quantity per destroyed input } }` from summed counts.
local function yieldOf(total, basis)
	local perInput = {}
	for itemID, quantity in pairs(total.items) do
		perInput[itemID] = quantity / total.inputs
	end
	return { casts = total.casts, basis = basis, inputsPerCast = total.inputs / total.casts, perInput = perInput }
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
--- addon (Tradewright_SalvageData.lua): `{ [itemID] = quantity per input }`, or nil.
--- `data = { prospect = { [itemID] = yield }, mill = { [itemID] = yield }, disenchant = { row, … } }`,
--- a disenchant row being `{ expansionID, quality, isWeapon, fromLevel, toLevel, yield }`.
function SalvageLogic.ResearchedYield(data, action, input)
	local byAction = data and data[action]
	if not byAction then
		return nil
	end
	if action ~= "disenchant" then
		return byAction[input.itemID]
	end
	for _, row in ipairs(byAction) do
		if rowCoversGear(row, input) then
			return row.yield
		end
	end
	return nil
end

--- What one `input` gives on average when salvaged, or nil when nothing is known.
--- `sources = { own, shipped, researched }`: the player's saved store, the store shipped with the
--- addon (other players' counted outcomes), and the researched tables (see ResearchedYield); any of
--- them may be nil.
--- Returns `{ perInput, casts, basis, inputsPerCast }`, the last being how many items one cast
--- destroyed on average (5 ore for a prospect), nil for researched yields. The player's own outcomes win once there are enough of them
--- ("own"), as yields shift with skill and talents; then all counted outcomes ("counted"); then
--- researched yields ("researched", casts 0); last, the few counted outcomes there are.
function SalvageLogic.Yield(sources, action, input)
	local groupKey = SalvageLogic.GroupKey(action, input)
	local own = groupTotal(sources.own, groupKey)
	if own.casts >= SalvageLogic.TRUSTED_CASTS then
		return yieldOf(own, "own")
	end
	addRecord(own, groupTotal(sources.shipped, groupKey))
	local counted = own
	local researched = SalvageLogic.ResearchedYield(sources.researched, action, input)
	if counted.casts >= SalvageLogic.TRUSTED_CASTS or (counted.inputs > 0 and not researched) then
		return yieldOf(counted, "counted")
	end
	return researched and { casts = 0, basis = "researched", perInput = researched } or nil
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

return SalvageLogic
