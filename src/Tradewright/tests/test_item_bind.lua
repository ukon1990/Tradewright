-- Run with: lua5.1 tests/test_item_bind.lua (from Tradewright root)
-- Which static bind types count as tradeable on the auction house.
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
local chunk, err = loadfile(root .. "/src/util/Tradewright_ItemInfo.lua")
assert(chunk, err)
chunk("Tradewright", pe)

local descriptor
pe.ResolveItemDescriptor = function() return descriptor end
local function tradeable(bindType)
	descriptor = { name = "Item", bindType = bindType }
	return pe:IsItemLikelyTradeableOnAuctionByStaticInfo(2589)
end

-- Retail Enum.ItemBind values.
_G.Enum = { ItemBind = {
	None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4, Unused1 = 5, Unused2 = 6, ToWoWAccount = 7,
	ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9, ToWoWAccountUntilEquipped = 10, ToWarband = 11,
} }
local EXPECTED = {
	None = true, OnAcquire = false, OnEquip = true, OnUse = true, Quest = false, Unused1 = true, Unused2 = true,
	ToWoWAccount = false, ToBnetAccount = false, ToBnetAccountUntilEquipped = false, ToWoWAccountUntilEquipped = false,
	ToWarband = false,
}
for name, value in pairs(Enum.ItemBind) do
	check("Enum.ItemBind." .. name .. " tradeable = " .. tostring(EXPECTED[name]), tradeable(value) == EXPECTED[name])
end
check("Bind type as a numeric string is compared as a number", tradeable("1") == false)
check("Missing bind type counts as tradeable", tradeable(nil) == true)
check("Non-numeric bind type counts as tradeable", tradeable("soulbound") == true)
check("Unknown bind value counts as tradeable", tradeable(99) == true)

-- Older clients: no Enum.ItemBind, only the LE_ITEM_BIND_* globals.
_G.Enum = nil
_G.LE_ITEM_BIND_ON_ACQUIRE, _G.LE_ITEM_BIND_QUEST = 1, 4
check("Without Enum: bind on acquire is not tradeable", tradeable(1) == false)
check("Without Enum: quest item is not tradeable", tradeable(4) == false)
check("Without Enum: bind on equip is tradeable", tradeable(2) == true)
check("Without Enum: account bind value is tradeable (no enum to name it)", tradeable(7) == true)
_G.LE_ITEM_BIND_ON_ACQUIRE, _G.LE_ITEM_BIND_QUEST = nil, nil
check("Without Enum or globals everything is tradeable", tradeable(1) == true)

-- Enum with only some members (Forever may ship a subset).
_G.Enum = { ItemBind = { OnAcquire = 1 } }
check("Partial enum: listed member still blocks", tradeable(1) == false)
check("Partial enum: missing members do not block", tradeable(4) == true)
_G.Enum = nil

descriptor = nil
check("Unknown item is not tradeable", pe:IsItemLikelyTradeableOnAuctionByStaticInfo(2589) == false)
check("Invalid item id is not tradeable", pe:IsItemLikelyTradeableOnAuctionByStaticInfo(0) == false
	and pe:IsItemLikelyTradeableOnAuctionByStaticInfo("x") == false)
descriptor = { bindType = 1 }
check("Item without a name is not tradeable", pe:IsItemLikelyTradeableOnAuctionByStaticInfo(2589) == false)

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All item bind checks passed")
