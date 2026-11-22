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

--- Records one outcome in `store`: `inputCount` of `input` were destroyed in one cast and gave
--- `results = { [itemID] = quantity }` (empty when the cast gave nothing).
function SalvageLogic.RecordOutcome(store, action, input, inputCount, results)
	local bucket = store.yields[store.epoch] or {}
	store.yields[store.epoch] = bucket
	local key = SalvageLogic.YieldKey(action, input)
	local record = bucket[key] or { casts = 0, inputs = 0, items = {} }
	bucket[key] = record
	record.casts = record.casts + 1
	record.inputs = record.inputs + inputCount
	for itemID, quantity in pairs(results or {}) do
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

-- `{ casts, basis, perInput = { [itemID] = quantity per destroyed input } }` from summed counts.
local function yieldOf(total, basis)
	local perInput = {}
	for itemID, quantity in pairs(total.items) do
		perInput[itemID] = quantity / total.inputs
	end
	return { casts = total.casts, basis = basis, perInput = perInput }
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
--- Returns `{ perInput, casts, basis }`. The player's own outcomes win once there are enough of them
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
