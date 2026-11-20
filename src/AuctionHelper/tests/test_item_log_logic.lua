-- Run with: lua5.1 tests/test_item_log_logic.lua (from AuctionHelper root)
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
local chunk, err = loadfile(root .. "/../AuctionHelper_Inventory/src/modules/AuctionHelper_ItemLogLogic.lua")
assert(chunk, err)
chunk("AuctionHelper_Inventory", pe)
local L = pe.ItemLogLogic
assert(L, "ItemLogLogic missing")

-- What changed
local changes = L.Diff({ [1] = 20, [2] = 1, [3] = 5 }, { [1] = 23, [3] = 5, [4] = 2 })
check("Diff: gained, lost and new, unchanged left out", #changes == 3 and changes[1].delta == 3 and changes[2].delta == -1
	and changes[3].itemID == 4 and changes[3].delta == 2)
check("Diff: nothing changed", #L.Diff({ [1] = 1 }, { [1] = 1 }) == 0)

-- Why
check("Reason: looted", L.Reason(1, { loot = true }) == "looted")
check("Reason: a craft beats an open loot window", L.Reason(1, { loot = true, craft = true }) == "crafted")
check("Reason: quest reward", L.Reason(1, { quest = true, merchant = true }) == "quest")
check("Reason: mail in and out", L.Reason(2, { mail = true }) == "mail_in" and L.Reason(-2, { mail = true }) == "mail_out")
check("Reason: vendor", L.Reason(1, { merchant = true }) == "bought" and L.Reason(-1, { merchant = true }) == "sold")
check("Reason: auction", L.Reason(1, { auction = true }) == "auction_in" and L.Reason(-1, { auction = true }) == "listed")
check("Reason: destroyed beats an open vendor", L.Reason(-1, { destroy = true, merchant = true }) == "destroyed")
check("Reason: bank", L.Reason(-5, { bank = true }, 0) == "to_bank" and L.Reason(5, { bank = true }) == "from_bank")
check("Reason: warband bank when its count moved the other way", L.Reason(-5, { bank = true }, 5) == "to_warband"
	and L.Reason(5, { bank = true }, -5) == "from_warband")
check("Reason: unknown gain is logged", L.Reason(1, {}) == "received")
check("Reason: unknown loss is not", L.Reason(-1, {}) == nil and L.Reason(-1, { craft = true, loot = true }) == nil)
check("Reason: putting gear on or off is not", L.Reason(1, { equip = true, loot = true }) == nil)

-- Keeping the log short
local limits = { rows = 3, days = 2 }
local log = {}
L.Add(log, { t = 1000, id = 1, n = 2, why = "looted" }, limits)
L.Add(log, { t = 1030, id = 1, n = 3, why = "looted" }, limits)
check("Add: same item and reason within a minute is one line", #log == 1 and log[1].n == 5 and log[1].t == 1030)
L.Add(log, { t = 1200, id = 1, n = 1, why = "looted" }, limits)
L.Add(log, { t = 1201, id = 1, n = -1, why = "sold" }, limits)
L.Add(log, { t = 1202, id = 2, n = 1, why = "mail_in", who = "Bankey" }, limits)
check("Add: oldest dropped beyond the row limit", #log == 3 and log[1].t == 1200)
L.Add(log, { t = 1203, id = 2, n = 1, why = "mail_in", who = "Maelis" }, limits)
check("Add: another sender is another line", #log == 3 and log[3].who == "Maelis")
L.Trim(log, 1203 + 2 * 86400, limits)
check("Trim: entries older than the day limit go", #log == 1 and log[1].who == "Maelis", #log)

-- Text and filter
check("Describe: plain", L.Describe({ why = "looted" }) == "Looted" and L.Describe({ why = "to_warband" }) == "Moved to the warband bank")
check("Describe: mail names the other character", L.Describe({ why = "mail_in", who = "Bankey" }) == "Mail from Bankey"
	and L.Describe({ why = "mail_out", who = "Bankey" }) == "Mailed to Bankey" and L.Describe({ why = "mail_in" }) == "From mail")
local names = { [1] = "Runecloth", [2] = "Wolf Helm" }
local function nameOf(id) return names[id] end
local list = { { t = 1, id = 1, why = "looted" }, { t = 2, id = 2, why = "mail_in", who = "Bankey" }, { t = 3, id = 1, why = "sold" } }
check("Visible: newest first", L.Visible(list, nameOf, "", 10)[1].t == 3 and #L.Visible(list, nameOf, nil, 10) == 3)
check("Visible: by item name", #L.Visible(list, nameOf, "RUNE", 10) == 2)
check("Visible: by reason", #L.Visible(list, nameOf, "bankey", 10) == 1 and #L.Visible(list, nameOf, "looted", 10) == 1)
check("Visible: limit", #L.Visible(list, nameOf, "", 2) == 2)
check("Visible: unknown item name still listed", #L.Visible({ { t = 1, id = 9, why = "looted" } }, nameOf, "", 5) == 1)

if failed > 0 then
	print(string.format("%d failure(s)", failed))
	os.exit(1)
end
print("All item log logic checks passed")
