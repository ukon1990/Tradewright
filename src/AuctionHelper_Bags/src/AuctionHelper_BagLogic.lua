local _, ProfessionExporter = ...

-- Pure bag helpers (E11): which category an item belongs to, how the slots are grouped and laid
-- out, and the totals. No WoW API here, so the offline tests can load this file on its own.
local BagLogic = {}
ProfessionExporter.BagLogic = BagLogic

-- Display order of the category headings.
BagLogic.CATEGORIES = {
	{ key = "gear", label = "Gear" },
	{ key = "consumable", label = "Consumables" },
	{ key = "food", label = "Food and drink" },
	{ key = "trade", label = "Trade goods" },
	{ key = "quest", label = "Quest" },
	{ key = "other", label = "Other" },
	{ key = "junk", label = "Junk" },
}

-- The game's item class IDs (Enum.ItemClass).
local CLASS = { consumable = 0, container = 1, quest = 12 }
local FOOD_SUBCLASS = 5
local REAGENT_BAG_SUBCLASS = 11
-- Weapon, armor and profession gear; gem, reagent and trade goods; item enhancement.
local CLASS_CATEGORY = {
	[0] = "consumable", [2] = "gear", [3] = "trade", [4] = "gear", [5] = "trade", [7] = "trade",
	[8] = "consumable", [19] = "gear",
}

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
	return CLASS_CATEGORY[item.classID] or "other"
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

--- Who holds an item: { { key, name, bags, bank } } with the largest holder first, and the total.
function BagLogic.Owners(characters, itemID)
	local owners, total = {}, 0
	for key, snapshot in pairs(characters) do
		local bags = snapshot.bags and snapshot.bags[itemID] or 0
		local bank = snapshot.bank and snapshot.bank[itemID] or 0
		if bags + bank > 0 then
			owners[#owners + 1] = { key = key, name = snapshot.name or key, bags = bags, bank = bank }
			total = total + bags + bank
		end
	end
	table.sort(owners, function(a, b)
		local ta, tb = a.bags + a.bank, b.bags + b.bank
		if ta ~= tb then
			return ta > tb
		end
		return a.name < b.name
	end)
	return owners, total
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

--- Whether an item matches the search text (any case, plain text). Empty text matches all.
function BagLogic.Matches(item, query)
	if not query or query == "" then
		return true
	end
	return string.find(string.lower(item.name or ""), string.lower(query), 1, true) ~= nil
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

--- Character keys for the tabs: the logged-in character first, then the most recently seen, at
--- most `limit` in all.
function BagLogic.TabOrder(characters, currentKey, limit)
	local keys = {}
	for key in pairs(characters) do
		if key ~= currentKey then
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
	table.insert(keys, 1, currentKey)
	for index = #keys, (limit or #keys) + 1, -1 do
		keys[index] = nil
	end
	return keys
end
