local _, AuctionHelper = ...

--- Pure row filters for the Inventory and Crafts tabs, and the row filter the Market tab uses. No WoW API.
local FilterLogic = {}
AuctionHelper.FilterLogic = FilterLogic

local function passesAll(row, filters)
	for _, filter in ipairs(filters) do
		if not filter[3](row) then
			return false
		end
	end
	return true
end

--- Rows that pass every active filter, in their original order. filters: `{ name, active, predicate(row) }`; name is only a label for readers.
function FilterLogic.KeepRows(rows, filters)
	local active = {}
	for _, filter in ipairs(filters) do
		if filter[2] then
			active[#active + 1] = filter
		end
	end
	local out = {}
	for _, row in ipairs(rows or {}) do
		if passesAll(row, active) then
			out[#out + 1] = row
		end
	end
	return out
end

local function isEmpty(selection)
	return type(selection) ~= "table" or next(selection) == nil
end

--- Lower-cased, trimmed search text ("" for nil).
function FilterLogic.SearchText(text)
	if not text then
		return ""
	end
	return string.lower((string.gsub(tostring(text), "^%s*(.-)%s*$", "%1")))
end

local function contains(value, needle)
	return string.find(string.lower(tostring(value or "")), needle, 1, true) ~= nil
end

local function anyFieldContains(row, fields, needle)
	for _, field in ipairs(fields) do
		if contains(row[field], needle) then
			return true
		end
	end
	return false
end

local function positive(value)
	return (tonumber(value) or 0) > 0
end

local function anyKeySelected(map, selection)
	for key in pairs(map or {}) do
		if selection[key] then
			return true
		end
	end
	return false
end

local INVENTORY_SEARCH_FIELDS = { "itemID", "name", "roleLabel", "itemTypeLabel", "itemSubTypeLabel" }
local LOCATIONS = { "bags", "bank", "warband" }

local function inSelectedLocation(row, locations)
	for _, location in ipairs(LOCATIONS) do
		if locations[location] and positive(row[location]) then
			return true
		end
	end
	return false
end

--- Inventory rows matching `filters` = { text, characters, role, itemType, expansions, qualities,
--- locations (bags / bank / warband), hasPrice, profitable }; empty sets match any. Account-wide rows
--- pass the character filter; rows without an expansion count as "legacy". getQuality(itemID) is
--- only asked when a quality filter is set, and an unknown quality never matches.
function FilterLogic.FilterInventoryRows(rows, filters, getQuality)
	filters = filters or {}
	local text = FilterLogic.SearchText(filters.text)
	local characters, roles, types = filters.characters, filters.role, filters.itemType
	local expansions, locations, qualities = filters.expansions, filters.locations, filters.qualities
	return FilterLogic.KeepRows(rows, {
		{ "text", text ~= "", function(row)
			return anyFieldContains(row, INVENTORY_SEARCH_FIELDS, text)
		end },
		{ "character", not isEmpty(characters), function(row)
			return row.aggregatedInventory or characters[row.characterKey] == true
		end },
		{ "role", not isEmpty(roles), function(row)
			return roles[row.roleKey] == true
		end },
		{ "itemType", not isEmpty(types), function(row)
			return types[row.itemTypeLabel] == true
		end },
		{ "expansion", not isEmpty(expansions), function(row)
			return expansions[row.expansionTag or "legacy"] == true
		end },
		{ "hasPrice", filters.hasPrice, function(row)
			return positive(row.currentAhCopper)
		end },
		{ "profitable", filters.profitable, function(row)
			return positive(row.profitCopperPerUnit)
		end },
		{ "location", not isEmpty(locations), function(row)
			return inSelectedLocation(row, locations)
		end },
		{ "quality", not isEmpty(qualities), function(row)
			local quality = getQuality(row.itemID)
			return quality ~= nil and qualities[quality] == true
		end },
	})
end

-- Crafts profit filter by state; "all" and unknown states keep every row.
local PROFIT_STATES = {
	profitable = function(row)
		return row.profit ~= nil and row.profit > 0
	end,
	negative = function(row)
		return row.profit ~= nil and row.profit < 0
	end,
	missing_price = function(row)
		return row.profit == nil or row.matMissingPrice == true
	end,
	uncraftable = function(row)
		return not row.canCraftNow
	end,
}

-- A set filter that also stands aside when "all" is selected.
local function narrows(selection)
	return not isEmpty(selection) and not selection.all
end

--- Crafts rows matching `filters` = { text, characters, professions, expansions, categories,
--- profitState }; empty sets (or "all") match any. Text searches recipe and output names; a
--- character matches when it appears in the row's perChar.
function FilterLogic.FilterCraftRows(rows, filters)
	filters = filters or {}
	local text = FilterLogic.SearchText(filters.text)
	local characters, professions = filters.characters, filters.professions
	local expansions, categories = filters.expansions, filters.categories
	local profitFilter = PROFIT_STATES[filters.profitState or "all"]
	return FilterLogic.KeepRows(rows, {
		{ "character", not isEmpty(characters), function(row)
			return anyKeySelected(row.perChar, characters)
		end },
		{ "profession", narrows(professions), function(row)
			return professions[tostring(row.skillLineID or "")] == true
		end },
		{ "expansion", not isEmpty(expansions), function(row)
			return expansions[row.expansionTag]
		end },
		{ "category", narrows(categories), function(row)
			return row.categoryID and categories[tostring(row.categoryID)]
		end },
		{ "text", text ~= "", function(row)
			return contains(row.recipeName, text) or contains(row.outputName, text)
		end },
		{ "profit", profitFilter ~= nil, profitFilter },
	})
end
