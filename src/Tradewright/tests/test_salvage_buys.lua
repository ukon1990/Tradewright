-- Run with: lua5.1 tests/test_salvage_buys.lua (from Tradewright root)
-- Rows of the Destroying tab's auction view: scanned gear below its disenchant value, the margin
-- from Settings, and a data check over everything scanned rather than only the rows that passed.
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

local CHEAP_SWORD, DEAR_SWORD, LINEN = 2580, 2581, 2589

-- Both swords disenchant to 100; one is listed at 40, the other at 95. Linen cannot be disenchanted.
local function newAddon(settings)
	local pe = { state = {} }
	loadInto(pe, root .. "/src/util/Tradewright_SalvageLogic.lua")
	function pe:GetState() return self.state end
	function pe:Now() return 1000 end
	function pe:GetSetting(key, default)
		local value = (settings or {})[key]
		if value == nil then
			return default
		end
		return value
	end
	function pe:GetMarketInsights()
		return { builtAt = 1, byItemID = {
			[CHEAP_SWORD] = { storageKey = "i:" .. CHEAP_SWORD, price = 40 },
			[DEAR_SWORD] = { storageKey = "i:" .. DEAR_SWORD, price = 95 },
			[LINEN] = { storageKey = "c:" .. LINEN, price = 1 },
		} }
	end
	function pe:GetSalvageInput(_, itemID)
		return itemID ~= LINEN and { quality = 2, itemLevel = 20 } or nil
	end
	function pe:GetSalvageValue() return { value = 100, basis = "researched", casts = 0 } end
	function pe:GetPriceSteps() return nil end
	function pe:CheckSalvageValues(_, inputs) return { level = "weak", reasons = {}, inputs = #inputs } end
	loadInto(pe, addons .. "/Tradewright_Inventory/src/modules/Tradewright_SalvageBuys.lua")
	return pe
end

do
	local rows, valueCheck = newAddon():GetSalvageBuyRows()
	check("The default margin is 15%", newAddon():GetSalvageBuyMargin() == 0.15)
	check("Only gear below its value less the margin is listed", #rows == 1 and rows[1].itemID == CHEAP_SWORD, #rows)
	check("A row says where its yield comes from", rows[1].basis == "researched" and rows[1].gain == 60)
	check("The check covers every scanned item that can be disenchanted", valueCheck.inputs == 2)
	rows = newAddon({ ["salvage.buyMargin"] = 0 }):GetSalvageBuyRows()
	check("A smaller margin lets more through", #rows == 2, #rows)
end

if failed > 0 then
	os.exit(1)
end
print("All salvage buy tests passed")
