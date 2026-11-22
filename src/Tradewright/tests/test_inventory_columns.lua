-- Run with: lua5.1 tests/test_inventory_columns.lua (from Tradewright root)
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local columnsFile = root .. "/../Tradewright_UI/src/ui/Tradewright_InventoryColumns.lua"

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local settings = {}
local pe = { IS_RETAIL = true }
function pe:GetSetting(key, default) return settings[key] or default end
function pe:SetSetting(key, value) settings[key] = value end
function pe:FormatNumberGrouped(n) return tostring(n) end
function pe:FormatCopperShort(copper) return copper .. "c" end
function pe:FormatShortTime(at) return "t" .. tostring(at) end
function pe:Colorize(text, colorKey) return "<" .. colorKey .. ">" .. text end
function pe:GetCharacterNameMarkup(key) return "[" .. key .. "]" end
function pe:GetItemDisplayName(itemID) return "item" .. itemID end
function pe:GetRankMarkup(rank) return rank and ("*" .. rank) or "" end
function pe:CreateItemColumn(spec) spec.id = "item"; spec.sortable = true; return spec end
for _, path in ipairs({ root .. "/../Tradewright_UI/src/ui/Tradewright_Columns.lua", columnsFile }) do
	local chunk, err = loadfile(path)
	assert(chunk, err)
	chunk("Tradewright_UI", pe)
end

local byId, ids = {}, {}
for _, column in ipairs(pe:GetInventoryColumnDefinitions()) do
	byId[column.id] = column
	ids[#ids + 1] = column.id
end
local expectedOrder = "item,qty,holders,loc,currentAh,lastSeen,avgSeen,avgCraft,lastCraft,profitUnit,profitStack,seenAt"
check("Definitions: order", table.concat(ids, ",") == expectedOrder, table.concat(ids, ","))

local row = {
	itemID = 7, rankIndex = 2, total = 40, bags = 30, bank = 10, warband = 5,
	holders = { { key = "Alt", count = 30 }, { key = "Main", count = 10 } },
	currentAhCopper = 1200, profitCopperPerUnit = 0, currentAhAt = 99,
}
check("Item: name with rank", byId.item.getName(row) == "item7*2")
check("Qty: text and sort", byId.qty.getText(row) == "40" and byId.qty.sortValue(row) == 40)
check("Holders: who holds it", byId.holders.getText(row) == "[Alt] <textMuted>30, [Main] <textMuted>10", byId.holders.getText(row))
check("Holders: nobody", byId.holders.getText({}) == "-")
check("Holders: sorts by count of characters", byId.holders.sortValue(row) == 2)
check("Loc: bags / bank / warband on retail", byId.loc.getText(row) == "30 / 10 / 5", byId.loc.getText(row))
check("Loc: compares bags, then bank", byId.loc.compare({ bags = 1, bank = 9 }, { bags = 2, bank = 0 }) == -1
	and byId.loc.compare({ bags = 2, bank = 3 }, { bags = 2, bank = 1 }) == 1 and byId.loc.compare({}, {}) == 0)
check("Money: text", byId.currentAh.getText(row) == "1200c")
check("Money: zero is shown", byId.profitUnit.getText(row) == "0c")
check("Money: missing is a dash and sorts last", byId.lastSeen.getText(row) == "-" and byId.lastSeen.sortValue(row) == -1)
check("Money: widths", byId.currentAh.width == 86 and byId.profitStack.width == 90 and byId.avgCraft.minWidth == 56)
check("Money: optional, right-aligned, desc", byId.avgSeen.optional and byId.avgSeen.justifyH == "RIGHT" and byId.avgSeen.defaultSort == "desc")
check("Seen: time", byId.seenAt.getText(row) == "t99" and byId.seenAt.sortValue({}) == 0)

-- Default visibility and saved choices
local function shown(id)
	return pe:IsInventoryColumnVisible(id)
end
check("Visible: defaults", shown("qty") and shown("currentAh") and not shown("loc") and not shown("lastSeen"))
pe:SetInventoryColumnVisible("loc", true)
pe:SetInventoryColumnVisible("qty", false)
check("Visible: saved choice wins", shown("loc") and not shown("qty"))
pe:SetInventoryColumnVisible("loc", false)
check("Visible: back to default clears the choice", settings["inventory.hiddenColumns"].loc == nil)

-- Order and table columns
pe:SaveInventoryColumnOrder({ { id = "seenAt" }, { id = "qty" }, { id = "gone" } })
local ordered = pe:GetInventoryColumnOrder()
check("Order: saved first, then the rest", ordered[1].id == "seenAt" and ordered[2].id == "qty" and ordered[3].id == "item" and #ordered == 12)
local tableColumns = pe:BuildInventoryTableColumns()
local visible = {}
for _, column in ipairs(tableColumns) do
	visible[column.id] = column.visible({})
end
check("Table columns: honour saved choices", visible.qty == false and visible.seenAt == false and visible.currentAh == true and visible.item == true)

if failed > 0 then
	print(failed .. " inventory column check(s) failed")
	os.exit(1)
end
print("All inventory column checks passed")
