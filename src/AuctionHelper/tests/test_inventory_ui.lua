-- Run with: lua5.1 tests/test_inventory_ui.lua (from AuctionHelper root)
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

local pe = { IS_RETAIL = false, ui = {} }
function pe:FormatNumberGrouped(n) return tostring(n) end
function pe:FormatCopperShort(copper) return copper .. "c" end
function pe:Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function pe:CountFilterSelection(selection) local n = 0 for _ in pairs(selection or {}) do n = n + 1 end return n end
local chunk, err = loadfile(root .. "/../AuctionHelper_UI/src/ui/AuctionHelper_InventoryUI.lua")
assert(chunk, err)
chunk("AuctionHelper_UI", pe)

-- Held text
local row = { total = 12, bags = 10, bank = 2, warband = 3 }
check("held text without warband on Forever", pe:GetInventoryHeldText(row) == "12 · 10 bags · 2 bank", pe:GetInventoryHeldText(row))
pe.IS_RETAIL = true
check("held text with warband on retail", pe:GetInventoryHeldText(row) == "12 · 10 bags · 2 bank · 3 warband", pe:GetInventoryHeldText(row))
check("held text skips empty warband", pe:GetInventoryHeldText({}) == "0 · 0 bags · 0 bank", pe:GetInventoryHeldText({}))

-- Filter state
pe.ui = { invRoleFilterValues = { crafted = true }, invExpansionFilterValues = { tww = true }, invHasPriceOnly = true }
local state = pe:BuildInventoryFilterState()
check("filter state keeps selections", state.role.crafted == true and next(state.characters) == nil and next(state.locations) == nil)
check("filter state flags", state.hasPrice == true and state.profitable == false and state.text == "")
check("filter state expansions on retail", state.expansions.tww == true)
pe.IS_RETAIL = false
check("filter state ignores expansions on Forever", next(pe:BuildInventoryFilterState().expansions) == nil)

-- Footer
local rows = {
	{ total = 2, currentAhCopper = 100, avgCraftCost = 30 },
	{ total = 3, currentAhCopper = 10 },
	{},
}
local characterOptions = { { value = "all" }, { value = "a" }, { value = "b" }, { value = "c" } }
pe.ui = { invCharacterFilterValues = {} }
local left, right = pe:GetInventoryFooterTexts(rows, characterOptions)
check("footer counts all characters", left == "3 items · 5 in total · all 3 characters", left)
check("footer sums values", right == "Auction value 230c · Craft value 60c", right)
pe.ui.invCharacterFilterValues = { a = true }
left = pe:GetInventoryFooterTexts(rows, characterOptions)
check("footer counts selected characters", left == "3 items · 5 in total · 1 of 3 characters", left)

if failed > 0 then
	print(failed .. " inventory UI check(s) failed")
	os.exit(1)
end
print("All inventory UI checks passed")
