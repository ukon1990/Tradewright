local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Pure bag helpers: which category an item belongs to, how the slots are grouped and laid
-- out, and the totals. No WoW API here, so the offline tests can load this file on its own.
local BagLogic = {}
Tradewright.BagLogic = BagLogic

-- Display order of the category headings.
BagLogic.CATEGORIES = {
	{ key = "gearset", label = L["Gear in a set"] },
	{ key = "gearloose", label = L["Gear not in a set"] },
	{ key = "gear", label = L["Gear"] },
	{ key = "consumable", label = L["Consumables"] },
	{ key = "food", label = L["Food and drink"] },
	{ key = "trade", label = L["Trade goods"] },
	{ key = "quest", label = L["Quest"] },
	{ key = "other", label = L["Other"] },
	{ key = "junk", label = L["Junk"] },
}

-- The game's item class IDs (Enum.ItemClass).
local CLASS = { consumable = 0, container = 1, weapon = 2, quest = 12 }
local FOOD_SUBCLASS = 5
local FISHING_POLE_SUBCLASS = 20
local REAGENT_BAG_SUBCLASS = 11
-- Weapon, armor and profession gear; gem, reagent and trade goods; item enhancement.
local CLASS_CATEGORY = {
	[0] = "consumable", [2] = "gear", [3] = "trade", [4] = "gear", [5] = "trade", [7] = "trade",
	[8] = "consumable", [19] = "gear",
}

-- Gear whose `inSet` is known (true or false) is split by it: saved equipment sets or none.
local function gearKey(item)
	if item.inSet == nil then
		return "gear"
	end
	return item.inSet and "gearset" or "gearloose"
end

--- Category key of an item: quest items first, then poor quality as junk, then by item class.
function BagLogic.CategoryOf(item)
	if item.isQuest or item.classID == CLASS.quest then
		return "quest"
	end
	if item.quality == 0 then
		return "junk"
	end
	if item.classID == CLASS.consumable and item.subclassID == FOOD_SUBCLASS then
		return "food"
	end
	local key = CLASS_CATEGORY[item.classID] or "other"
	return key == "gear" and gearKey(item) or key
end

--- The item name in a link, or nil: the link of an item the game has no data for has an empty name.
function BagLogic.LinkName(link)
	local name = link and string.match(link, "%[(.-)%]")
	return name ~= "" and name or nil
end

-- Best quality first, then name, then the larger stack; bag and slot keep the order stable.
local function sortKeys(item)
	return { -(item.quality or 1), item.name or "", -(item.count or 1), (item.bag or 0) * 1000 + (item.slot or 0) }
end

local function itemBefore(a, b)
	local ka, kb = sortKeys(a), sortKeys(b)
	for index = 1, #ka do
		if ka[index] ~= kb[index] then
			return ka[index] < kb[index]
		end
	end
	return false
end

--- Items as groups in display order: { key, label, items }. Empty categories are left out.
function BagLogic.GroupItems(items)
	local byKey = {}
	for _, item in ipairs(items) do
		local key = BagLogic.CategoryOf(item)
		byKey[key] = byKey[key] or {}
		table.insert(byKey[key], item)
	end
	local groups = {}
	for _, category in ipairs(BagLogic.CATEGORIES) do
		local list = byKey[category.key]
		if list then
			table.sort(list, itemBefore)
			groups[#groups + 1] = { key = category.key, label = category.label, items = list }
		end
	end
	return groups
end

--- Where everything is drawn, top-left origin, y growing downwards. `opts`: columns, slot, gap,
--- heading (height), headingGap, groupGap. Returns { headings = { { group, y } },
--- slots = { { item, group, x, y } }, height }. A group's `extra` items (the free-slot tile) follow
--- its own.
function BagLogic.Layout(groups, opts)
	local step = opts.slot + opts.gap
	local layout = { headings = {}, slots = {}, height = 0 }
	local y = 0
	for index, group in ipairs(groups) do
		if index > 1 then
			y = y + opts.groupGap
		end
		layout.headings[#layout.headings + 1] = { group = group, y = y }
		y = y + opts.heading + opts.headingGap
		local count = 0
		for _, list in ipairs({ group.items, group.extra or {} }) do
			for _, item in ipairs(list) do
				local column, row = count % opts.columns, math.floor(count / opts.columns)
				layout.slots[#layout.slots + 1] = { item = item, group = group, x = column * step, y = y + row * step }
				count = count + 1
			end
		end
		local rows = math.max(1, math.ceil(count / opts.columns))
		y = y + rows * opts.slot + (rows - 1) * opts.gap
	end
	layout.height = y
	return layout
end

local function addCounts(into, counts)
	for itemID, count in pairs(counts or {}) do
		into[itemID] = (into[itemID] or 0) + count
	end
end

--- Per-item counts of one saved character: `mode` is "bags", "bank" or "both".
function BagLogic.MergeCounts(snapshot, mode)
	local counts = {}
	if mode ~= "bank" then
		addCounts(counts, snapshot.bags)
	end
	if mode ~= "bags" then
		addCounts(counts, snapshot.bank)
	end
	return counts
end

--- Per-item counts added up over every character.
function BagLogic.MergeAll(characters, mode)
	local counts = {}
	for _, snapshot in pairs(characters) do
		addCounts(counts, BagLogic.MergeCounts(snapshot, mode))
	end
	return counts
end

--- Copy saved characters from `from` into `into`, keeping whichever record of a character was
--- seen last (a record never seen loses).
function BagLogic.AdoptHoldings(into, from)
	for key, record in pairs(from) do
		local existing = into[key]
		if not existing or (record.seenAt or 0) > (existing.seenAt or 0) then
			into[key] = record
		end
	end
end

--- Gold per character: { { key, name, money } } with the richest first, and the total, in copper.
--- Characters whose gold was never saved are left out.
function BagLogic.GoldByCharacter(characters)
	local rows, total = {}, 0
	for key, snapshot in pairs(characters) do
		if snapshot.money then
			rows[#rows + 1] = { key = key, name = snapshot.name or key, money = snapshot.money }
			total = total + snapshot.money
		end
	end
	table.sort(rows, function(a, b)
		if a.money ~= b.money then
			return a.money > b.money
		end
		return a.name < b.name
	end)
	return rows, total
end

--- Slot totals of the carried bags: { slots, used, free, reagentFree }. `free` counts normal bags
--- only, since only reagents fit in the reagent bag. `bags`: { { slots, free, isReagent } }.
function BagLogic.BagTotals(bags)
	local totals = { slots = 0, used = 0, free = 0, reagentFree = 0 }
	for _, bag in ipairs(bags) do
		totals.slots = totals.slots + bag.slots
		totals.used = totals.used + bag.slots - bag.free
		if bag.isReagent then
			totals.reagentFree = totals.reagentFree + bag.free
		else
			totals.free = totals.free + bag.free
		end
	end
	return totals
end

--- What a vendor pays for the junk among `items`, in copper.
function BagLogic.JunkValue(items)
	local value = 0
	for _, item in ipairs(items) do
		if BagLogic.CategoryOf(item) == "junk" then
			value = value + (item.sellPrice or 0) * (item.count or 1)
		end
	end
	return value
end

-- The cheaper of two candidates ({ item, value }); a missing one loses.
local function cheaper(best, item, value)
	if not best or value < best.value then
		return { item = item, value = value }
	end
	return best
end

local MAX_DROP_QUALITY = 2

-- Profession tools a skill or recipe needs in the bags. Tools that do the same job share a kind;
-- the last one of a kind is never offered for deleting. Fishing poles are found by subclass. The
-- Gnomish Army Knife keeps its own kind: until it is known to replace every tool, both stay.
local TOOL_KIND = {
	[7005] = "skinning", -- Skinning Knife
	[12709] = "skinning", -- Finkle's Skinner
	[19901] = "skinning", -- Zulian Slicer
	[2901] = "mining", -- Mining Pick
	[5956] = "blacksmithing", -- Blacksmith Hammer
	[6219] = "engineering", -- Arclight Spanner
	[10498] = "microAdjustor", -- Gyromatic Micro-Adjustor
	[40772] = "armyKnife", -- Gnomish Army Knife
	[4471] = "fire", -- Flint and Tinder
	[5060] = "lockpicking", -- Thieves' Tools
	[9149] = "philosophersStone", -- Philosopher's Stone
	[15846] = "saltShaker", -- Salt Shaker
	[20815] = "jewelersKit", -- Jeweler's Kit
	[39505] = "inkingSet", -- Virtuoso Inking Set
	[6218] = "copperRod", -- Runed Copper Rod
	[6339] = "silverRod", -- Runed Silver Rod
	[11130] = "goldenRod", -- Runed Golden Rod
	[11145] = "truesilverRod", -- Runed Truesilver Rod
	[16207] = "arcaniteRod", -- Runed Arcanite Rod
}

--- The kind of profession tool an item is ("skinning", "fishing", ...), or nil for any other item.
function BagLogic.ToolKind(item)
	if item.classID == CLASS.weapon and item.subclassID == FISHING_POLE_SUBCLASS then
		return "fishing"
	end
	return TOOL_KIND[item.itemID]
end

-- How many tools of each kind the bags hold.
local function toolCounts(items)
	local counts = {}
	for _, item in ipairs(items) do
		local kind = BagLogic.ToolKind(item)
		if kind then
			counts[kind] = (counts[kind] or 0) + (item.count or 1)
		end
	end
	return counts
end

-- Whether deleting the stack would leave no tool of its kind.
local function isLastTool(item, counts)
	local kind = BagLogic.ToolKind(item)
	return kind ~= nil and counts[kind] <= (item.count or 1)
end

-- Whether an item that is not junk may be offered for deleting: it has a vendor price (so it is
-- no key, hearthstone or other item without value), is at most uncommon, and is no quest item or bag.
local function mayDrop(item)
	return (item.sellPrice or 0) > 0 and (item.quality or 1) <= MAX_DROP_QUALITY and item.classID ~= CLASS.container
		and BagLogic.CategoryOf(item) ~= "quest"
end

-- "junk" or "other" and what the stack is worth; nil for a stack that is never offered.
local function dropKind(item, auctionPriceOf)
	local count, vendor = item.count or 1, item.sellPrice or 0
	if item.locked then
		return nil
	end
	if BagLogic.CategoryOf(item) == "junk" then
		return "junk", vendor * count
	end
	if not mayDrop(item) then
		return nil
	end
	return "other", math.max(vendor, auctionPriceOf and auctionPriceOf(item.itemID) or 0) * count
end

--- The stack to delete when the bags are full: the junk stack a vendor pays least for, or with no
--- junk the cheapest other stack that may be dropped, valued at the higher of its vendor and
--- auction price (`auctionPriceOf(itemID)` -> copper each, or nil). Locked items are skipped, and
--- so is the last profession tool of each kind (a spare copy may go).
--- Returns { item, value, isJunk }, or nil when nothing qualifies.
function BagLogic.CheapestToDrop(items, auctionPriceOf)
	local best, tools = {}, toolCounts(items)
	for _, item in ipairs(items) do
		local kind, value = dropKind(item, auctionPriceOf)
		if kind and not isLastTool(item, tools) then
			best[kind] = cheaper(best[kind], item, value)
		end
	end
	local pick = best.junk or best.other
	if pick then
		pick.isJunk = best.junk ~= nil
	end
	return pick
end

--- The loot worth taking in place of `drop` (CheapestToDrop's result): the most valuable entry of
--- `loot` ({ { slot, name, count, value } }) when it is worth more than the stack to delete, else nil.
function BagLogic.BestLootSwap(loot, drop)
	local best
	for _, entry in ipairs(loot) do
		if entry.value > drop.value and (not best or entry.value > best.value) then
			best = entry
		end
	end
	return best
end

-- Selecting stacks and acting on several at once.

function BagLogic.SlotKey(bag, slot)
	return bag * 1000 + slot
end

--- Select a stack, or unselect it when it was selected. `selection` maps SlotKey to item ID.
--- Returns whether the stack is selected now.
function BagLogic.ToggleSelected(selection, item)
	local key = BagLogic.SlotKey(item.bag, item.slot)
	selection[key] = not selection[key] and item.itemID or nil
	return selection[key] ~= nil
end

--- The selected stacks among `items`, in their order. A selected stack that is gone, or whose
--- slot now holds another item, is dropped from `selection`.
function BagLogic.SelectedItems(selection, items)
	local found, picked = {}, {}
	for _, item in ipairs(items) do
		local key = item.bag and BagLogic.SlotKey(item.bag, item.slot)
		if key and selection[key] == item.itemID then
			found[key] = true
			picked[#picked + 1] = item
		end
	end
	for key in pairs(selection) do
		if not found[key] then
			selection[key] = nil
		end
	end
	return picked
end

local PLACE_LABEL = { bags = "bags", bank = "bank", warband = L["warband bank"] }

--- Where a stack in `place` ("bags", "bank" or "warband") can be moved: { { key, label } }.
--- `state`: bankOpen, hasWarband. Nothing moves while the bank is closed.
function BagLogic.MoveTargets(place, state)
	local targets = {}
	if not state.bankOpen then
		return targets
	end
	for _, key in ipairs({ "bags", "bank", "warband" }) do
		if key ~= place and (key ~= "warband" or state.hasWarband) then
			targets[#targets + 1] = { key = key, label = L["Move to "] .. PLACE_LABEL[key] }
		end
	end
	return targets
end

--- One free slot ({ bag, slot }) per stack: { { item, bag, slot } }, and how many did not fit.
function BagLogic.PlanMoves(items, freeSlots)
	local moves = {}
	for index = 1, math.min(#items, #freeSlots) do
		moves[index] = { item = items[index], bag = freeSlots[index].bag, slot = freeSlots[index].slot }
	end
	return moves, #items - #moves
end

--- The stacks a vendor buys, and what they pay for all of them.
function BagLogic.SellQueue(items)
	local queue, total = {}, 0
	for _, item in ipairs(items) do
		local value = (item.sellPrice or 0) * (item.count or 1)
		if value > 0 and not item.locked then
			queue[#queue + 1] = item
			total = total + value
		end
	end
	return queue, total
end

-- Never destroyed in bulk: locked stacks, quest items, bags, and anything rare or better.
local function mayDestroy(item)
	return not item.locked and (item.quality or 1) <= MAX_DROP_QUALITY and item.classID ~= CLASS.container
		and BagLogic.CategoryOf(item) ~= "quest"
end

--- The stacks that may be destroyed, what they are worth (the higher of vendor and auction price),
--- and how many of `items` are refused.
function BagLogic.DestroyQueue(items, auctionPriceOf)
	local queue, total = {}, 0
	for _, item in ipairs(items) do
		if mayDestroy(item) then
			local each = math.max(item.sellPrice or 0, auctionPriceOf and auctionPriceOf(item.itemID) or 0)
			queue[#queue + 1] = item
			total = total + each * (item.count or 1)
		end
	end
	return queue, total, #items - #queue
end

local CATEGORY_LABEL = {}
for _, category in ipairs(BagLogic.CATEGORIES) do
	CATEGORY_LABEL[category.key] = category.label
end

--- Whether an item fits the search text: every word typed must be found in the item's name, its
--- category heading or its `keywords` (item type, subtype, equip slot and quality), in any case.
function BagLogic.Matches(item, query)
	if not query or query == "" then
		return true
	end
	local label = CATEGORY_LABEL[BagLogic.CategoryOf(item)]
	local text = string.lower(table.concat({ item.name or "", item.keywords or "", label }, " "))
	for word in string.gmatch(string.lower(query), "%S+") do
		if not string.find(text, word, 1, true) then
			return false
		end
	end
	return true
end

--- The bags among `items` that fit a bag slot: reagent bags for the reagent slot, others elsewhere.
function BagLogic.ReplacementBags(items, forReagentSlot)
	local bags = {}
	for _, item in ipairs(items) do
		local isReagentBag = item.subclassID == REAGENT_BAG_SUBCLASS
		if item.classID == CLASS.container and isReagentBag == (forReagentSlot and true or false) then
			bags[#bags + 1] = item
		end
	end
	table.sort(bags, itemBefore)
	return bags
end

--- Keys for the tabs: the logged-in character first, then `pinnedKey` when it is saved (the
--- warband bank), then the most recently seen, at most `limit` in all.
function BagLogic.TabOrder(characters, currentKey, limit, pinnedKey)
	local keys = {}
	for key in pairs(characters) do
		if key ~= currentKey and key ~= pinnedKey then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys, function(a, b)
		local sa, sb = characters[a].seenAt or 0, characters[b].seenAt or 0
		if sa ~= sb then
			return sa > sb
		end
		return a < b
	end)
	if pinnedKey and characters[pinnedKey] and pinnedKey ~= currentKey then
		table.insert(keys, 1, pinnedKey)
	end
	table.insert(keys, 1, currentKey)
	for index = #keys, (limit or #keys) + 1, -1 do
		keys[index] = nil
	end
	return keys
end
