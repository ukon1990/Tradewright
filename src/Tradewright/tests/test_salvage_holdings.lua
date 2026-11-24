-- Run with: lua5.1 tests/test_salvage_holdings.lua (from Tradewright root)
-- Rows of the Destroying tab: owned items with a value when destroyed, which use is best, soulbound
-- copies kept off the auction house, and which actions each client offers.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addons = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local function loadInto(pe, path)
	local chunk, err = loadfile(path)
	assert(chunk, err)
	chunk("Tradewright", pe)
end

local CLOAK, BOUND_RING, LINEN = 2580, 2581, 2589

-- A cloak worth 50 at auction (after the cut) and 80 disenchanted, a bind-on-pickup ring, and linen
-- that cannot be disenchanted.
local function newAddon(holdings, isRetail, professions)
	local pe = { IS_RETAIL = isRetail }
	loadInto(pe, root .. "/src/util/Tradewright_SalvageLogic.lua")
	function pe:GetItemHoldings() return holdings end
	function pe:SomeCharacterHasProfession(skillLineID) return (professions or {})[skillLineID] == true end
	function pe:GetSalvageInput(action, itemID)
		if action == "disenchant" and (itemID == CLOAK or itemID == BOUND_RING) then
			return { quality = 2, itemLevel = 20 }
		end
		return nil
	end
	function pe:GetSalvageValue() return { value = 80, basis = "researched", casts = 0 } end
	function pe:GetItemVendorSellCopper() return 10 end
	function pe:IsItemLikelyTradeableOnAuctionByStaticInfo(itemID) return itemID ~= BOUND_RING end
	function pe:GetMarketEstimateCopper() return 100 end
	function pe:ApplyAhCutToSaleCopper(copper) return copper / 2 end
	function pe:CheckSalvageValues(_, inputs) return { level = "weak", reasons = {}, inputs = #inputs } end
	loadInto(pe, addons .. "/Tradewright_Inventory/src/modules/Tradewright_SalvageHoldings.lua")
	return pe
end

local function rowFor(rows, itemID, where)
	for _, row in ipairs(rows) do
		if row.itemID == itemID and row.where == where then
			return row
		end
	end
	return nil
end

-- Rows
do
	local pe = newAddon({
		Main = { name = "Main", bags = { [CLOAK] = 2, [LINEN] = 20 }, bank = { [CLOAK] = 1 }, boundInBank = { [CLOAK] = 1 } },
		Alt = { name = "Alt", bags = { [BOUND_RING] = 1 } },
	})
	local rows, valueCheck = pe:GetSalvageHoldingRows("disenchant")
	check("One row per character and place, only items with a value", #rows == 3, #rows)
	local cloak = rowFor(rows, CLOAK, "bags")
	check("A tradeable cloak has an auction value after the cut", cloak.auction == 50 and cloak.vendor == 10 and cloak.salvage == 80)
	check("Disenchanting is best, gaining over the auction for the whole stack", cloak.bestUse == "salvage" and cloak.gain == 2 * 30)
	local banked = rowFor(rows, CLOAK, "bank")
	check("A soulbound copy in the bank has no auction value", banked.bound and banked.auction == nil and banked.gain == 70)
	local ring = rowFor(rows, BOUND_RING, "bags")
	check("A bind-on-pickup item has no auction value", ring.auction == nil and ring.characterName == "Alt")
	check("The check covers every row", valueCheck.inputs == 3)
end

-- Actions per client
do
	check("Forever offers disenchanting only", table.concat(newAddon({}, false, { [755] = true }):GetSalvageActions(), ",") == "disenchant")
	check("Retail adds prospecting once a character has Jewelcrafting",
		table.concat(newAddon({}, true, { [755] = true }):GetSalvageActions(), ",") == "disenchant,prospect")
end

-- Who can disenchant
do
	local pe = newAddon({})
	pe.db = { characters = {
		["Elra-R"] = { meta = { name = "Elra" }, professions = { ["333"] = { skillLevel = 180 } } },
		["Torvik-R"] = { meta = { name = "Torvik" }, professions = { ["333"] = { skillLevel = 75 } } },
		["Maelis-R"] = { meta = { name = "Maelis" }, professions = { ["164"] = { skillLevel = 200 } } },
	} }
	local enchanters = pe:GetEnchanters()
	check("Enchanters only, highest skill first", #enchanters == 2 and enchanters[1].name == "Elra" and enchanters[1].skillLevel == 180
		and enchanters[2].characterKey == "Torvik-R")
end

if failed > 0 then
	os.exit(1)
end
print("All salvage holdings tests passed")
