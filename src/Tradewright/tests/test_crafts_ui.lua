-- Run with: lua5.1 tests/test_crafts_ui.lua (from Tradewright root)
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

local settings, state = {}, {}
local pe = { IS_RETAIL = false, ui = {}, db = { characters = {} } }
function pe:GetSetting(key, default) if settings[key] ~= nil then return settings[key] end return default end
function pe:GetState() return state end
function pe:DescribeAuctionCut() return "5%, measured" end
function pe:Colorize(text, colorKey) return "<" .. colorKey .. ">" .. text end
function pe:FormatNumberGrouped(n) return tostring(n) end
function pe:TableCount(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function pe:Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function pe:GetRankMarkup() return "" end
function pe:GetItemDisplayName() return "?" end
function pe:GetCraftQueueQuantityForOpportunityRow() return 0 end
function pe:CreateItemColumn(spec) return spec end
local chunk, err = loadfile(root .. "/../Tradewright_UI/src/ui/Tradewright_CraftsUI.lua")
assert(chunk, err)
chunk("Tradewright_UI", pe)

-- Options note
check("note names the cut in use and the scan source",
	pe:GetCraftsOptionsNote() == "Auction cut 5%, measured · Prices from the last auction house scan", pe:GetCraftsOptionsNote())
state.craftEvalInProgress, state.craftEvalWorkList, state.craftEvalIdx = true, { 1, 2, 3, 4 }, 3
check("note shows progress while evaluating", pe:GetCraftsOptionsNote() == "<warning>Updating 2 of 4 recipes…", pe:GetCraftsOptionsNote())
state.craftEvalWorkList = {}
check("empty work list falls back to cut note", pe:GetCraftsOptionsNote():find("^Auction cut") ~= nil)

-- Footer
local rows = {
	{ rowKey = "a", profit = 10, professionName = "Alchemy" },
	{ rowKey = "b", profit = -5, professionName = "Alchemy" },
	{ rowKey = "c", profit = 1, professionName = "Tailoring" },
	{ rowKey = "d" },
}
local left, right = pe:GetCraftsFooterTexts(rows)
check("footer counts profitable", left == "2 profitable of 4 crafts", left)
check("footer counts professions incl. unknown", right == "3 professions", right)

-- Selection
pe.ui.craftsSelectedRowKey = "c"
check("keeps selected row", pe:PickCraftsSelectedRow(rows) == rows[3])
pe.ui.craftsSelectedRowKey = "gone"
check("falls back to first row", pe:PickCraftsSelectedRow(rows) == rows[1] and pe.ui.craftsSelectedRowKey == "a")
pe.ui.craftsSelectedRowKey, pe.ui.craftsItemDetailOnlyItemID = "gone", 123
check("item-only detail keeps no row", pe:PickCraftsSelectedRow(rows) == nil and pe.ui.craftsSelectedRowKey == "gone")
check("no rows picks nothing", pe:PickCraftsSelectedRow({}) == nil)

-- Row detail warning
local _, detail = pe:GetCraftRowLabels({ professionName = "Alchemy" })
check("missing mats price warns", detail == "Alchemy · <warning>no reagent price", detail)
_, detail = pe:GetCraftRowLabels({ professionName = "Alchemy", matCost = 1, qualityReachable = false, concentrationCost = 5 })
check("concentration warning", detail == "Alchemy · <warning>needs concentration", detail)
_, detail = pe:GetCraftRowLabels({ professionName = "Alchemy", matCost = 1, qualityReachable = false })
check("rank warning", detail == "Alchemy · <warning>rank out of reach", detail)
_, detail = pe:GetCraftRowLabels({ professionName = "Alchemy", matCost = 1 })
check("no warning when priced and reachable", detail == "Alchemy", detail)

if failed > 0 then
	print(failed .. " crafts UI check(s) failed")
	os.exit(1)
end
print("All crafts UI checks passed")
