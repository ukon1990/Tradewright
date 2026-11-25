-- Run with: lua5.1 tests/test_salvage_input.lua (from Tradewright root)
-- What disenchanting takes: weapons and armor, except gear the game marks as not disenchantable,
-- which neither the tooltip nor any API tells (the wands an enchanter makes, for one).
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

local GREATER_MAGIC_WAND, GREATER_MYSTIC_WAND, CLOAK, LINEN = 11288, 11290, 2580, 2589
local WEAPON_CLASS, ARMOR_CLASS, TRADE_GOODS_CLASS = 2, 4, 7
local items = {
	[GREATER_MAGIC_WAND] = { quality = 2, itemLevel = 23, classID = WEAPON_CLASS },
	[GREATER_MYSTIC_WAND] = { quality = 2, itemLevel = 30, classID = WEAPON_CLASS },
	[CLOAK] = { quality = 2, itemLevel = 20, classID = ARMOR_CLASS },
	[LINEN] = { quality = 1, itemLevel = 5, classID = TRADE_GOODS_CLASS },
}

rawset(_G, "CreateFrame", function()
	return { SetScript = function() end, RegisterEvent = function() end }
end)

local pe = {}
function pe:ItemDescriptorFromID(itemID) return items[itemID] end
for _, file in ipairs({
	"/src/util/Tradewright_SalvageLogic.lua",
	"/src/data/Tradewright_NoDisenchantData.lua",
	"/src/modules/Tradewright_SalvageSightings.lua",
}) do
	local chunk, err = loadfile(root .. file)
	assert(chunk, err)
	chunk("Tradewright", pe)
end

local cloak = pe:GetSalvageInput("disenchant", CLOAK)
check("Uncommon armor is disenchanted", cloak and cloak.quality == 2 and cloak.isWeapon == false)
check("A wand the game will not disenchant is not taken", pe:GetSalvageInput("disenchant", GREATER_MAGIC_WAND) == nil)
check("Nor one missing from Forever's export, listed from Classic Era", pe:GetSalvageInput("disenchant", GREATER_MYSTIC_WAND) == nil)
check("Trade goods are not disenchanted", pe:GetSalvageInput("disenchant", LINEN) == nil)
check("Prospecting and milling are not affected", pe:GetSalvageInput("prospect", GREATER_MAGIC_WAND).itemID == GREATER_MAGIC_WAND)

if failed > 0 then
	os.exit(1)
end
print("all salvage input tests passed")
