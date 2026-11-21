-- Run with: lua5.1 tests/test_tooltip_logic.lua (from AuctionHelper root)
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
for _, file in ipairs({ "AuctionHelper_CoreHelpers.lua", "AuctionHelper_TooltipLogic.lua" }) do
	local chunk, err = loadfile(root .. "/src/util/" .. file)
	assert(chunk, err)
	chunk("AuctionHelper", pe)
end
local TL = pe.TooltipLogic
assert(TL, "TooltipLogic missing")

-- Money as plain copper so the expected text is easy to read.
local function opts(detail)
	return {
		detail = detail,
		money = function(c) return tostring(c) .. "c" end,
		moneyShort = function(c) return tostring(c) .. "c" end,
		number = function(n) return tostring(math.floor(n + 0.5)) end,
	}
end
local function find(block, label)
	for _, line in ipairs(block.lines) do
		if line.label == label then
			return line
		end
	end
end

-- Owners
local maelis = { name = "Maelis", bags = { [1] = 200, [2] = 3 }, bank = {} }
local bankey = { name = "Bånkey", bags = { [1] = 240 }, bank = { [1] = 1000, [3] = 4 } }
local thalric = { name = "Thalric", bags = {}, bank = { [1] = 40 } }
local characters = { ["Maelis-R"] = maelis, ["Bankey-R"] = bankey, ["Thalric-R"] = thalric }
local owners, total = TL.Owners(characters, 1)
check("Owners: largest first", #owners == 3 and owners[1].name == "Bånkey" and owners[2].name == "Maelis")
check("Owners: split and total", owners[1].bags == 240 and owners[1].bank == 1000 and total == 1480)
check("Owners: nobody", #TL.Owners(characters, 99) == 0)
local others, othersTotal = TL.Owners(characters, 1, "Bankey-R")
check("Owners: skips one character", #others == 2 and othersTotal == 240)
check("Owners: no characters", #TL.Owners(nil, 1) == 0)

-- Age
check("Age: minutes", TL.AgeText(30) == "1 min ago" and TL.AgeText(600) == "10 min ago")
check("Age: hours", TL.AgeText(3 * 3600) == "3 h ago")
check("Age: days", TL.AgeText(3 * 86400) == "3 days ago")

-- Nothing to show
check("Block: no summary", TL.BuildLines(nil, opts()) == nil)
check("Block: nothing known", TL.BuildLines({ ownedAll = 5, vendor = 10 }, opts()) == nil)
check("Block: only own sales shows nothing until Shift", TL.BuildLines({ avgSale = 50 }, opts()) == nil)
check("Block: own sales with Shift", find(TL.BuildLines({ avgSale = 50 }, opts(true)), "Your average sale").value == "50c")

-- Compact block
local ore = {
	price = 12000, priceAge = 3 * 3600, priceStale = false, average = 10500, low = 9000, high = 13000, trend = 14.3,
	usualDays = 14, listed = 4210, sellsPerDay = 800, ownedAll = 280, listedByYou = 40, vendor = 1200, vendorBeatsAh = false,
	craftCost = 9500, profit = 1900, margin = 20, avgSale = 11800, rule = { reserveQty = 20 },
	owners = { { name = "Maelis", bags = 200, bank = 0 }, { name = "Bånkey", bags = 0, bank = 80, warband = 5 } },
	recipeUse = { usedCount = 6, professions = { "Alchemy", "Cooking" }, crafters = {} },
}
local compact = TL.BuildLines(ore, opts(false))
check("Compact: four lines", #compact.lines == 4, #compact.lines)
check("Compact: header shows the age", compact.header.right == "3 h ago" and compact.header.tone == nil)
check("Compact: price with trend", compact.lines[1].label == "Price" and compact.lines[1].value == "12000c  +14% usual"
	and compact.lines[1].tone == "success", compact.lines[1].value)
check("Compact: usual with range", compact.lines[2].label == "Usual" and compact.lines[2].value == "10500c  (9000c – 13000c)")
check("Compact: listed with sells a day", compact.lines[3].value == "4210 · ~800 sold/day", compact.lines[3].value)
check("Compact: owned, worth and listed", compact.lines[4].value == "280 · worth 3360000c · 40 listed", compact.lines[4].value)
check("Compact: no craft or vendor line", not find(compact, "Craft cost") and not find(compact, "Vendor pays"))

-- Variations
local stale = TL.BuildLines({ price = 100, priceAge = 9 * 3600, priceStale = true }, opts())
check("Stale: orange age", stale.header.tone == "warning" and stale.header.right == "9 h ago")
local estimate = TL.BuildLines({ estimate = 500, ownedAll = 2 }, opts())
check("Estimate: header says so", estimate.header.right == "estimate" and estimate.lines[1].value == "500c")
check("Estimate: worth uses it", find(estimate, "You own").value == "2 · worth 1000c")
local cheap = TL.BuildLines({ price = 100, trend = -20, average = 125, listed = 3, sellsPerDay = 2.5 }, opts())
check("Trend: below usual is info", cheap.lines[1].tone == "info" and cheap.lines[1].value == "100c  -20% usual")
check("Usual: 7-day label without a usual price, no range", cheap.lines[2].label == "7-day avg" and cheap.lines[2].value == "125c")
check("Listed: slow sellers keep a decimal", cheap.lines[3].value == "3 · ~2.5 sold/day", cheap.lines[3].value)
check("Owned: nothing owned, no line", not find(cheap, "You own"))
local onlyListed = TL.BuildLines({ price = 100, ownedAll = 0, listedByYou = 7 }, opts())
check("Owned: only listed", find(onlyListed, "You own").value == "0 · 7 listed")
local junk = TL.BuildLines({ price = 100, vendor = 150, vendorBeatsAh = true }, opts())
local vendorLine = find(junk, "Vendor pays")
check("Vendor: shown without Shift when it beats the AH", vendorLine and vendorLine.tone == "warning"
	and vendorLine.value == "150c · more than the AH")
junk = TL.BuildLines({ price = 100, vendor = 150, vendorBeatsAh = true }, opts(true))
local count = 0
for _, line in ipairs(junk.lines) do
	count = count + (line.label == "Vendor pays" and 1 or 0)
end
check("Vendor: not repeated with Shift", count == 1)

-- Detail block
local detail = TL.BuildLines(ore, opts(true))
check("Detail: craft cost and profit", find(detail, "Craft cost").value == "9500c"
	and find(detail, "Profit after cut").value == "+1900c  +20%" and find(detail, "Profit after cut").tone == "success")
check("Detail: one line per character", find(detail, "Maelis").value == "200 bags" and find(detail, "Bånkey").value == "80 bank · 5 warband")
check("Detail: rule", find(detail, "Rule").value == "keep 20")
check("Detail: vendor", find(detail, "Vendor pays").value == "1200c" and find(detail, "Vendor pays").tone == nil)
check("Detail: used in", find(detail, "Used in").value == "6 recipes (Alchemy, Cooking)")
check("Detail: no crafters, no line", not find(detail, "Crafted by"))
check("Detail: average sale last", detail.lines[#detail.lines].label == "Your average sale")
local loss = TL.BuildLines({ price = 100, craftCost = 150, profit = -55, margin = -36.7, rule = { ignore = true } }, opts(true))
check("Detail: loss is danger", find(loss, "Profit after cut").tone == "danger" and find(loss, "Profit after cut").value == "-55c  -37%")
check("Detail: never-post rule", find(loss, "Rule").value == "never posted in bulk")
local many = { price = 100, ownedAll = 70, owners = {} }
for i = 1, 7 do
	many.owners[i] = { name = "Char" .. i, bags = 10, bank = 0 }
end
local manyBlock = TL.BuildLines(many, opts(true))
check("Detail: five characters, then the rest counted", find(manyBlock, "Char5") and not find(manyBlock, "Char6")
	and find(manyBlock, "and 2 more"))

-- Recipes
local use = TL.RecipeUse({
	usedBy = {
		{ recipeID = 1, professionName = "Alchemy" }, { recipeID = 1, professionName = "Alchemy" },
		{ recipeID = 2, professionName = "Alchemy" }, { recipeID = 3, professionName = "Cooking" },
	},
	producedBy = {
		{ characterLabel = "Maelis - Realm", professionName = "Mining" },
		{ characterLabel = "Maelis - Realm", professionName = "Mining" },
		{ characterKey = "Thalric-R", professionName = "Mining" },
	},
})
check("Recipes: a recipe known twice counts once", use.usedCount == 3)
check("Recipes: professions once each", #use.professions == 2 and use.professions[1] == "Alchemy")
check("Recipes: crafters by name", #use.crafters == 2 and use.crafters[1] == "Maelis (Mining)" and use.crafters[2] == "Thalric-R (Mining)",
	table.concat(use.crafters, "|"))
local single = TL.BuildLines({ price = 1, recipeUse = { usedCount = 1, professions = { "Cooking" }, crafters = { "Maelis (Mining)" } } }, opts(true))
check("Recipes: singular", find(single, "Used in").value == "1 recipe (Cooking)" and find(single, "Crafted by").value == "Maelis (Mining)")
check("Recipes: empty", TL.RecipeUse({}).usedCount == 0 and #TL.RecipeUse({}).crafters == 0)

if failed > 0 then
	print(string.format("%d failure(s)", failed))
	os.exit(1)
end
print("All tooltip logic checks passed")
