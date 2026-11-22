local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
--- Pure helpers for crafting materials: the cheapest way to get one, counts per storage location and
--- classic reagent slots. No WoW API.
local MaterialLogic = {}
Tradewright.MaterialLogic = MaterialLogic

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

--- Covers `missing` units from other characters' stock before buying. `holders` is
--- { { characterKey, quantity }, … }. Returns fromHolders, toBuy and the holders with stock, the
--- largest first (ties by character key).
function MaterialLogic.CoverFromHolders(missing, holders)
	missing = math.max(0, tonumber(missing) or 0)
	local sorted, stock = {}, 0
	for _, holder in ipairs(holders or {}) do
		local quantity = tonumber(holder.quantity) or 0
		if quantity > 0 then
			sorted[#sorted + 1] = holder
			stock = stock + quantity
		end
	end
	table.sort(sorted, function(a, b)
		if a.quantity ~= b.quantity then
			return a.quantity > b.quantity
		end
		return tostring(a.characterKey) < tostring(b.characterKey)
	end)
	local fromHolders = math.min(missing, stock)
	return fromHolders, missing - fromHolders, sorted
end

--- How many times a recipe can be made from what `have(itemID)` returns. `plan` is a queued craft's
--- reagent plan: `{ { itemID, quantityRequired, slotOptional }, … }`. Optional slots do not count.
--- Returns nil when the plan names no required material, so the caller cannot tell.
function MaterialLogic.CraftableCount(plan, have)
	local count
	for _, slot in ipairs(plan or {}) do
		local required = tonumber(slot.quantityRequired) or 0
		if slot.itemID and required > 0 and not slot.slotOptional then
			local times = math.floor((tonumber(have(slot.itemID)) or 0) / required)
			count = math.min(count or times, times)
		end
	end
	return count
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
--- craft rows: `{ [itemID] = { cost, crafter, row, outputQty } }`, `row` being the craft row that
--- makes it cheapest. Rows with a missing material price or a cooldown are left out: a cooldown's
--- output is capped, so it is not a way to get materials in bulk.
function MaterialLogic.UnitCostIndex(rows)
	local index = {}
	for _, row in ipairs(rows or {}) do
		local itemID, cost = unitCostOf(row)
		if itemID and (not index[itemID] or cost < index[itemID].cost) then
			index[itemID] = {
				cost = cost, crafter = row.bestCharacterKey, row = row, outputQty = math.max(1, tonumber(row.outputQty) or 1),
			}
		end
	end
	return index
end

--- The crafts that make the materials of `count` crafts whose reagent plan prices them as crafted
--- ("Craft"): `{ { row, crafts } }`, one entry per such material, from `unitCostIndex`
--- (MaterialLogic.UnitCostIndex). Stock already owned is not taken off: the queue shows that itself.
function MaterialLogic.MaterialCraftsNeeded(reagentPlan, count, unitCostIndex)
	local needed = {}
	for _, slot in ipairs(reagentPlan or {}) do
		local source = slot.priceSource == "Craft" and unitCostIndex[tonumber(slot.itemID)]
		local units = (tonumber(slot.quantityRequired) or 0) * count
		if source and units > 0 then
			needed[#needed + 1] = { row = source.row, crafts = math.ceil(units / source.outputQty) }
		end
	end
	return needed
end

--- How many to make: enough for `days` of sales, less what is already owned and listed, capped at `cap`.
--- `opts = { sellsPerDay, days, owned, listed, cap, profit, minProfit }`. Returns 0 when the craft's
--- profit is below `minProfit` (default: any loss), and nil when it is not known to sell.
function MaterialLogic.RestockQuantity(opts)
	local sells = tonumber(opts.sellsPerDay)
	if not sells then
		return nil
	end
	if (tonumber(opts.profit) or 0) <= (tonumber(opts.minProfit) or 0) then
		return 0
	end
	local target = math.floor(sells * (tonumber(opts.days) or 1) + 0.5)
	local make = target - (tonumber(opts.owned) or 0) - (tonumber(opts.listed) or 0)
	return math.max(0, math.min(make, tonumber(opts.cap) or make))
end

--- State of a recipe cooldown that ends at `readyAt` (nil when the recipe has none on record):
--- `{ state = "none" | "ready" | "waiting", secondsLeft }`.
function MaterialLogic.CooldownState(readyAt, now)
	readyAt = tonumber(readyAt)
	if not readyAt then
		return { state = "none", secondsLeft = 0 }
	end
	local left = readyAt - (tonumber(now) or 0)
	if left <= 0 then
		return { state = "ready", secondsLeft = 0 }
	end
	return { state = "waiting", secondsLeft = left }
end

--- Every recipe cooldown on record, across characters: `cooldownsByCharacter = { [characterKey] =
--- { [recipeID] = readyAt } }`. Returns `{ ready = { { characterKey, recipeID } }, nextIn }`:
--- the cooldowns that are ready, and the seconds until the next one is (nil when none is waiting).
function MaterialLogic.SummarizeCooldowns(cooldownsByCharacter, now)
	local summary = { ready = {} }
	for characterKey, cooldowns in pairs(cooldownsByCharacter or {}) do
		for recipeID, readyAt in pairs(cooldowns) do
			local cooldown = MaterialLogic.CooldownState(readyAt, now)
			if cooldown.state == "ready" then
				summary.ready[#summary.ready + 1] = { characterKey = characterKey, recipeID = recipeID }
			elseif cooldown.state == "waiting" then
				summary.nextIn = math.min(summary.nextIn or cooldown.secondsLeft, cooldown.secondsLeft)
			end
		end
	end
	return summary
end

--- "1 cooldown ready · next in 1 day 4 hours" for a cooldown summary, nil when none is on record.
function MaterialLogic.CooldownFooter(summary)
	local parts = {}
	if #summary.ready > 0 then
		parts[#parts + 1] = string.format(L["%d %s ready"], #summary.ready, Tradewright:Plural(#summary.ready, "cooldown"))
	end
	if summary.nextIn then
		parts[#parts + 1] = string.format(L["next in %s"], MaterialLogic.FormatCooldown(summary.nextIn))
	end
	return #parts > 0 and table.concat(parts, " · ") or nil
end

--- "1 day 4 hours", "3 hours", "20 minutes" for a cooldown's remaining seconds.
function MaterialLogic.FormatCooldown(seconds)
	local minutes = math.ceil((tonumber(seconds) or 0) / 60)
	local days, hours = math.floor(minutes / 1440), math.floor(minutes % 1440 / 60)
	local function unit(count, name)
		return count .. " " .. Tradewright:Plural(count, name)
	end
	if days > 0 then
		return hours > 0 and (unit(days, "day") .. " " .. unit(hours, "hour")) or unit(days, "day")
	elseif hours > 0 then
		return unit(hours, "hour")
	end
	return unit(math.max(1, minutes), "minute")
end

--- Resolve bags/bank/warband when warband API may be missing (Forever).
--- withWarband may be nil when the 5-arg GetItemCount form failed.
function MaterialLogic.ResolveLocationCounts(bags, withBank, withWarband)
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

-- Classic recipe reagent slot from (itemID, quantity).
function MaterialLogic.MakeClassicReagentSlot(slotIndex, itemID, quantity)
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

--- The one reagent slot of a salvage recipe (Prospecting, Milling), which destroys an item of the
--- player's choice: any one of `itemIDs`, `quantity` of it per craft. Reagent planning then picks the
--- cheapest, as for any slot that takes one of several items. nil without a usable item.
function MaterialLogic.MakeSalvageSlot(itemIDs, quantity)
	local reagents = {}
	for _, itemID in ipairs(itemIDs or {}) do
		itemID = tonumber(itemID)
		if itemID and itemID > 0 then
			reagents[#reagents + 1] = { reagentIndex = #reagents + 1, itemID = itemID, quantity = quantity }
		end
	end
	if #reagents == 0 then
		return nil
	end
	return {
		slotIndex = 1, dataSlotIndex = 1, reagentType = 1, quantityRequired = quantity,
		required = true, optional = false, salvage = true, reagents = reagents,
	}
end

--- How much of a material still has to be bought when crafts in the craft queue make some of it:
--- `toBuy, fromQueue`. What the character already has is used first; `queuedOutput` is what the
--- queued crafts make of the material in total.
function MaterialLogic.ToBuyAfterQueuedCrafts(needed, have, queuedOutput)
	local missing = math.max(0, (needed or 0) - (have or 0))
	local fromQueue = math.min(missing, queuedOutput or 0)
	return missing - fromQueue, fromQueue
end

return MaterialLogic
