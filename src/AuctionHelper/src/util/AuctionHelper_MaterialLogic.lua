local _, ProfessionExporter = ...

--- Pure helpers for choosing the cheapest way to get a crafting material (F60). No WoW API.
local MaterialLogic = {}
ProfessionExporter.MaterialLogic = MaterialLogic

--- The cheapest of `candidates = { { cost, source }, … }`: `cost, source`. Entries without a positive
--- cost are skipped; on a tie the earlier entry wins, so list the preferred source first.
function MaterialLogic.CheapestSource(candidates)
	local bestCost, bestSource
	for _, candidate in ipairs(candidates or {}) do
		local cost = tonumber(candidate[1])
		if cost and cost > 0 and (not bestCost or cost < bestCost) then
			bestCost, bestSource = cost, candidate[2]
		end
	end
	return bestCost, bestSource
end

-- Material cost of one unit of a craft row's output, or nil when the row cannot say.
local function unitCostOf(row)
	local cost = tonumber(row.fullMatCost) or tonumber(row.matCost)
	local itemID = tonumber(row.outputItemID)
	if not (cost and itemID) or cost <= 0 or row.matMissingPrice or row.hasCooldown then
		return nil
	end
	return itemID, cost / math.max(1, tonumber(row.outputQty) or 1)
end

--- Cheapest material cost per unit for every item the player's characters can craft, from evaluated
--- craft rows: `{ [itemID] = { cost, crafter } }`. Rows with a missing material price or a cooldown
--- are left out: a cooldown's output is capped, so it is not a way to get materials in bulk.
function MaterialLogic.UnitCostIndex(rows)
	local index = {}
	for _, row in ipairs(rows or {}) do
		local itemID, cost = unitCostOf(row)
		if itemID and (not index[itemID] or cost < index[itemID].cost) then
			index[itemID] = { cost = cost, crafter = row.bestCharacterKey }
		end
	end
	return index
end

return MaterialLogic
