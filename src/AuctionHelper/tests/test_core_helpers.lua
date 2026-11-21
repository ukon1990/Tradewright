-- Run with: lua5.1 tests/test_core_helpers.lua (from AuctionHelper root)
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local pe = {}
local chunk, err = loadfile(root .. "/src/util/AuctionHelper_CoreHelpers.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)

-- Trim
check("Trim: nil gives an empty string", pe:Trim(nil) == "")
check("Trim: empty string stays empty", pe:Trim("") == "")
check("Trim: only spaces gives empty", pe:Trim(" \t\n ") == "")
check("Trim: both ends trimmed, inner space kept", pe:Trim("  Linen  Cloth ") == "Linen  Cloth")
check("Trim: a number becomes its text", pe:Trim(42) == "42")

-- Plural
check("Plural: count 1 is singular", pe:Plural(1, "item") == "item")
check("Plural: count 0 is plural", pe:Plural(0, "item") == "items")
check("Plural: count 2 is plural", pe:Plural(2, "item") == "items")
check("Plural: irregular plural", pe:Plural(3, "entry", "entries") == "entries")
check("Plural: count given as text", pe:Plural("1", "mail") == "mail")
check("Plural: missing count is plural", pe:Plural(nil, "mail") == "mails")

-- Colorize
local theme = { warning = { r = 1, g = 0.5, b = 0 }, textMuted = { r = 0.6, g = 0.63, b = 0.67 } }
function pe:GetTheme() return theme end
check("Colorize: theme key", pe:Colorize("Low", "warning") == "|cffff7f00Low|r", pe:Colorize("Low", "warning"))
check("Colorize: colour table rounds channels down", pe:Colorize("x", theme.textMuted) == "|cff99a0aax|r", pe:Colorize("x", theme.textMuted))
check("Colorize: hex string", pe:Colorize("(you)", "33ff99") == "|cff33ff99(you)|r")
check("Colorize: number text", pe:Colorize(7, "warning") == "|cffff7f007|r")
check("Colorize: empty text keeps the escape", pe:Colorize("", "warning") == "|cffff7f00|r")
check("Colorize: unknown key leaves text plain", pe:Colorize("plain", "nope") == "plain")
check("Colorize: no colour leaves text plain", pe:Colorize("plain", nil) == "plain")

-- FirstValueFrom
local function positive(value)
	value = tonumber(value)
	return value and value > 0 and value or nil
end
local function booleanOnly(value)
	if type(value) == "boolean" then
		return value
	end
	return nil
end
local probe = {
	Throws = function() error("not ready") end,
	Zero = function() return 0 end,
	Good = function(self) return self.inner end,
	inner = "12",
	recipeID = 99,
	notAMethod = 5,
}
check("FirstValueFrom: a throwing method is skipped", pe:FirstValueFrom(probe, { "Throws", "Good" }, nil, positive) == 12)
check("FirstValueFrom: a rejected value is skipped", pe:FirstValueFrom(probe, { "Zero", "Good" }, nil, positive) == 12)
check("FirstValueFrom: missing methods fall through to fields",
	pe:FirstValueFrom(probe, { "Missing", "notAMethod", "Throws" }, { "missing", "recipeID" }, positive) == 99)
check("FirstValueFrom: methods win over fields", pe:FirstValueFrom(probe, { "Good" }, { "recipeID" }, positive) == 12)
check("FirstValueFrom: nothing accepted gives nil", pe:FirstValueFrom(probe, { "Zero" }, { "missing" }, positive) == nil)
check("FirstValueFrom: not a table gives nil", pe:FirstValueFrom(nil, { "Good" }, { "recipeID" }, positive) == nil)
check("FirstValueFrom: false is a found value",
	pe:FirstValueFrom({ IsOn = function() return false end, on = true }, { "IsOn" }, { "on" }, booleanOnly) == false)
check("FirstValueFrom: a non-boolean field is skipped",
	pe:FirstValueFrom({ a = "yes", b = true }, nil, { "a", "b" }, booleanOnly) == true)

-- ForEachBagSlot with a fake container API: bag 0 has 3 slots, bag 1 has 2, bag 2 none.
local contents = {
	[0] = { { itemID = 2589, stackCount = 5 }, nil, { itemID = 2592, stackCount = 1 } },
	[1] = { nil, { itemID = 2589, stackCount = 2 } },
}
local slotCounts = { [0] = 3, [1] = 2, [2] = 0 }
_G.C_Container = {
	GetContainerNumSlots = function(bag) return slotCounts[bag] end,
	GetContainerItemInfo = function(bag, slot) return contents[bag] and contents[bag][slot] end,
}
function pe:GetLastBagIndex() return 2 end

local visited, linen = {}, 0
pe:ForEachBagSlot(nil, function(bag, slot, info)
	visited[#visited + 1] = bag .. ":" .. slot
	if info and info.itemID == 2589 then
		linen = linen + info.stackCount
	end
end)
check("ForEachBagSlot: walks every carried slot, empty ones too", table.concat(visited, " ") == "0:1 0:2 0:3 1:1 1:2", table.concat(visited, " "))
check("ForEachBagSlot: counts add up over bags", linen == 7, linen)

visited = {}
pe:ForEachBagSlot({ 1 }, function(bag, slot) visited[#visited + 1] = bag .. ":" .. slot end)
check("ForEachBagSlot: only the given bags", table.concat(visited, " ") == "1:1 1:2")

visited = {}
local stopped = pe:ForEachBagSlot(nil, function(bag, slot, info)
	visited[#visited + 1] = bag .. ":" .. slot
	return info ~= nil and info.itemID == 2592
end)
check("ForEachBagSlot: returning true stops the walk", stopped == true and #visited == 3, #visited)

_G.C_Container = nil
local called = false
check("ForEachBagSlot: no container API walks nothing", pe:ForEachBagSlot(nil, function() called = true end) == false and not called)

-- GetTsmPriceStrings
local settings = { ["integrations.economyTSMMarketString"] = "DBRecent" }
function pe:GetSetting(path, default)
	if settings[path] ~= nil then
		return settings[path]
	end
	return default
end
local tsm = pe:GetTsmPriceStrings()
check("TSM strings: saved value wins", tsm.market == "DBRecent")
check("TSM strings: defaults for the rest",
	tsm.fallback == "DBMinBuyout" and tsm.material == "Crafting" and tsm.saleRate == "DBRegionSaleRate")

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All core helper checks passed")
