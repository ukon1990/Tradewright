local _, Tradewright = ...

-- Pure rules for stashing crafting reagents: which stacks leave the bags for the bank (or the bank
-- character's mailbox), which stay for the craft queue, and which bank stacks come back when the
-- queue needs them. Stacks are never split. No WoW API here, so the offline tests can load this file alone.
local ReagentStashLogic = {}
Tradewright.ReagentStashLogic = ReagentStashLogic

-- The game's item classes that are crafting materials (Enum.ItemClass): gem, reagent, trade goods.
local MATERIAL_CLASS = { [3] = true, [5] = true, [7] = true }

-- Adds the reagents of one recipe to the set.
local function addRecipeReagents(reagents, recipe)
	for _, slot in ipairs(recipe.slots or {}) do
		for _, reagent in ipairs(slot.reagents or {}) do
			local itemID = tonumber(reagent.itemID)
			if itemID then
				reagents[itemID] = true
			end
		end
	end
end

--- Every item a scanned recipe uses, as reagents[itemID] = true, and how many professions were
--- scanned. `professions` is a character's saved scan: { [skillLineKey] = { recipes = { ... } } }.
function ReagentStashLogic.ProfessionReagents(professions)
	local reagents, scanned = {}, 0
	for _, profession in pairs(professions or {}) do
		for _, recipe in pairs(profession.recipes or {}) do
			addRecipeReagents(reagents, recipe)
		end
		scanned = scanned + (next(profession.recipes or {}) and 1 or 0)
	end
	return reagents, scanned
end

--- What the queued crafts of `characterKey` need, as need[itemID] = quantity. `reagentLines` are the
--- lines of a craft queue summary: { itemID, sources = { { characterKey, quantity } } }.
--- Adds to `need` when given, so several summaries can be added up.
function ReagentStashLogic.QueueNeeds(reagentLines, characterKey, need)
	need = need or {}
	for _, line in ipairs(reagentLines or {}) do
		local itemID = tonumber(line.itemID)
		for _, source in ipairs(line.sources or {}) do
			if itemID and source.characterKey == characterKey then
				need[itemID] = (need[itemID] or 0) + (tonumber(source.quantity) or 0)
			end
		end
	end
	return need
end

--- Whether an item is stashed. With `professionReagents` (a ProfessionReagents set) only the items
--- in it are; without it every crafting material is, by item class.
function ReagentStashLogic.IsStashed(itemID, classID, professionReagents)
	if professionReagents then
		return professionReagents[itemID] == true
	end
	return MATERIAL_CLASS[classID] == true
end

local function stacksByItem(stacks, wanted)
	local byItem = {}
	for _, stack in ipairs(stacks) do
		if not stack.locked and wanted(stack) then
			byItem[stack.itemID] = byItem[stack.itemID] or {}
			table.insert(byItem[stack.itemID], stack)
		end
	end
	return byItem
end

-- Stacks in the reagent bag are kept first: they take no slot another item could use. Then the
-- larger stacks, so as few slots as possible stay filled.
local function keptBefore(a, b)
	if (a.inReagentBag == true) ~= (b.inReagentBag == true) then
		return a.inReagentBag == true
	end
	return (a.count or 1) > (b.count or 1)
end

-- Marks in `stays` the stacks of one item that cover `quantity`; returns how many it marked.
local function markStaying(stays, itemStacks, quantity)
	local marked = 0
	table.sort(itemStacks, keptBefore)
	for _, stack in ipairs(itemStacks) do
		if quantity <= 0 then
			break
		end
		stays[stack] = true
		marked = marked + 1
		quantity = quantity - (stack.count or 1)
	end
	return marked
end

--- The stacks to move from the bags to the bank, and how many stashed stacks stay for the queue.
--- stacks: { { itemID, count, classID, locked, inReagentBag } }, in display order, which the result
--- keeps. rules.professionReagents: see IsStashed. rules.keep[itemID]: how many must stay; whole
--- stacks stay until that is covered, so a little more than needed can stay.
function ReagentStashLogic.StacksToDeposit(stacks, rules)
	local keep = rules.keep or {}
	local byItem = stacksByItem(stacks, function(stack)
		return ReagentStashLogic.IsStashed(stack.itemID, stack.classID, rules.professionReagents)
	end)
	local stays, stayCount = {}, 0
	for itemID, itemStacks in pairs(byItem) do
		stayCount = stayCount + markStaying(stays, itemStacks, keep[itemID] or 0)
	end
	local deposit = {}
	for _, stack in ipairs(stacks) do
		if byItem[stack.itemID] and not stack.locked and not stays[stack] then
			deposit[#deposit + 1] = stack
		end
	end
	return deposit, stayCount
end

-- The stack to take next when `missing` are still needed: the largest that does not overshoot,
-- else the smallest, which covers the rest with the least extra.
local function nextStackIndex(itemStacks, missing)
	local fitting, smallest
	for index, stack in ipairs(itemStacks) do
		local count = stack.count or 1
		if count <= missing and (not fitting or count > itemStacks[fitting].count) then
			fitting = index
		end
		if not smallest or count < itemStacks[smallest].count then
			smallest = index
		end
	end
	return fitting or smallest
end

--- The bank stacks to move to the bags so the bags hold need[itemID] of every item, and what the
--- bank cannot cover as short[itemID] = quantity. carried[itemID] is what the bags hold now.
--- bankStacks: { { itemID, count, locked } }.
function ReagentStashLogic.StacksToWithdraw(bankStacks, need, carried)
	local byItem = stacksByItem(bankStacks, function(stack)
		return (need[stack.itemID] or 0) > (carried[stack.itemID] or 0)
	end)
	local withdraw, short = {}, {}
	for itemID, quantity in pairs(need) do
		local missing = quantity - (carried[itemID] or 0)
		local itemStacks = byItem[itemID] or {}
		while missing > 0 and #itemStacks > 0 do
			local stack = table.remove(itemStacks, nextStackIndex(itemStacks, missing))
			withdraw[#withdraw + 1] = stack
			missing = missing - (stack.count or 1)
		end
		if missing > 0 then
			short[itemID] = missing
		end
	end
	return withdraw, short
end
