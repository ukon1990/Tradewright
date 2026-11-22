-- Merges collected sightings into the data file that ships with the addon.
--
--   lua5.1 scripts/build-source-data.lua <SavedVariables/Tradewright.lua> [more ...]
--
-- Run from the repository root; scripts/build-source-data.mjs finds the saved files and calls this.
-- The merge itself is SourceLogic.ShipStore, the same code the addon reads the data with, so the
-- shipped file and the addon cannot disagree about its shape.

local ADDON = "src/Tradewright/"
local DATA_FILE = ADDON .. "src/data/Tradewright_SourceData.lua"
local HEADER = [[
local _, Tradewright = ...

-- Sightings shipped with the addon, in the shape of the sightings store (see Tradewright_SourceLogic.lua).
-- Written by scripts/build-source-data.lua from collected saved data; do not edit by hand.
-- `collected` says up to which tally epoch each collector's loot counts are already in here.
Tradewright.SOURCE_DATA = ]]

-- Runs an addon file the way the client does: with the addon's name and its shared table.
local function loadAddonFile(path, addon)
	local chunk = assert(loadfile(path))
	chunk("Tradewright", addon)
end

-- The saved store in a SavedVariables file, or nil when the file has none.
local function readSavedStore(path)
	local globals = {}
	local chunk = assert(loadfile(path))
	setfenv(chunk, globals)
	chunk()
	return globals.TradewrightSourcesDB
end

-- Numbers before strings, each in order, so the file only changes where the data did.
local function sortedKeys(value)
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then
			return type(a) == "number"
		end
		return a < b
	end)
	return keys
end

local function isList(value)
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	return count == #value
end

local function scalarText(value)
	return type(value) == "string" and string.format("%q", value) or tostring(value)
end

-- A list of scalars (a place) on one line; anything else one entry per line.
local function isFlatList(value)
	if not isList(value) then
		return false
	end
	for _, item in ipairs(value) do
		if type(item) == "table" then
			return false
		end
	end
	return true
end

local function writeValue(out, value, indent)
	if type(value) ~= "table" then
		out[#out + 1] = scalarText(value)
	elseif isFlatList(value) then
		local items = {}
		for index, item in ipairs(value) do
			items[index] = scalarText(item)
		end
		out[#out + 1] = #items == 0 and "{}" or ("{ " .. table.concat(items, ", ") .. " }")
	else
		local list = isList(value)
		out[#out + 1] = "{\n"
		for _, key in ipairs(sortedKeys(value)) do
			out[#out + 1] = indent .. "\t" .. (list and "" or ("[" .. scalarText(key) .. "] = "))
			writeValue(out, value[key], indent .. "\t")
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = indent .. "}"
	end
end

local function countKeys(byKey)
	local count = 0
	for _ in pairs(byKey) do
		count = count + 1
	end
	return count
end

local addon = {}
loadAddonFile(ADDON .. "src/util/Tradewright_SourceLogic.lua", addon)
loadAddonFile(DATA_FILE, addon)
local shipped = addon.SourceLogic.EnsureStore(addon.SOURCE_DATA)
-- These two only mean something in a player's saved store.
shipped.epoch, shipped.collectorID = nil, nil

local merged = 0
for _, path in ipairs(arg) do
	local store = readSavedStore(path)
	if store and store.collectorID then
		addon.SourceLogic.ShipStore(shipped, addon.SourceLogic.EnsureStore(store))
		shipped.epoch, shipped.collectorID = nil, nil
		merged = merged + 1
		print("merged " .. path)
	else
		print("no sightings in " .. path)
	end
end
if merged == 0 then
	print("Nothing to build.")
	os.exit(1)
end

local out = { HEADER }
writeValue(out, shipped, "")
out[#out + 1] = "\n"
local file = assert(io.open(DATA_FILE, "w"))
file:write(table.concat(out))
file:close()
print(string.format("%s: %d NPCs, %d items sold, %d loot sources", DATA_FILE, countKeys(shipped.npcs), countKeys(shipped.sold),
	countKeys(shipped.tallies[0] or {})))
