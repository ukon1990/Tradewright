-- Run with: lua5.1 tests/test_reagent_stash_logic.lua (from AuctionHelper root)
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
local chunk, err = loadfile(root .. "/src/util/AuctionHelper_ReagentStashLogic.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)
local SL = pe.ReagentStashLogic
assert(SL, "ReagentStashLogic missing")

local TRADE_GOODS, ARMOR = 7, 4
local ORE, HERB, LEATHER, HELM = 1, 2, 3, 4

local function names(stacks)
	local out = {}
	for _, stack in ipairs(stacks) do out[#out + 1] = stack.name end
	table.sort(out)
	return table.concat(out, ",")
end

-- Reagents of the scanned professions
do
	local reagents, scanned = SL.ProfessionReagents({
		mining = { recipes = { a = { slots = { { reagents = { { itemID = ORE }, { itemID = "9" } } } } }, b = { slots = {} } } },
		neverScanned = { recipes = {} },
	})
	check("Professions: every reagent of every recipe", reagents[ORE] and reagents[9] and not reagents[HERB])
	check("Professions: one without recipes is not counted as scanned", scanned == 1)
	check("Professions: no saved scan gives nothing", select(2, SL.ProfessionReagents(nil)) == 0)
end

-- What the queue needs on one character
do
	local lines = {
		{ itemID = ORE, sources = { { characterKey = "Me", quantity = 5 }, { characterKey = "Alt", quantity = 50 }, { characterKey = "Me", quantity = 2 } } },
		{ itemID = HERB, sources = { { characterKey = "Alt", quantity = 9 } } },
	}
	local need = SL.QueueNeeds(lines, "Me")
	check("Queue needs: only this character's crafts", need[ORE] == 7 and need[HERB] == nil)
	SL.QueueNeeds({ { itemID = ORE, sources = { { characterKey = "Me", quantity = 3 } } } }, "Me", need)
	check("Queue needs: a second summary adds up", need[ORE] == 10)
end

-- Depositing
do
	local function stacks()
		return {
			{ name = "ore20", itemID = ORE, count = 20, classID = TRADE_GOODS },
			{ name = "ore5", itemID = ORE, count = 5, classID = TRADE_GOODS },
			{ name = "oreInReagentBag", itemID = ORE, count = 3, classID = TRADE_GOODS, inReagentBag = true },
			{ name = "herb", itemID = HERB, count = 10, classID = TRADE_GOODS },
			{ name = "lockedLeather", itemID = LEATHER, count = 4, classID = TRADE_GOODS, locked = true },
			{ name = "helm", itemID = HELM, count = 1, classID = ARMOR },
		}
	end
	local all, stay = SL.StacksToDeposit(stacks(), {})
	check("Deposit all: every crafting material, the reagent bag too", names(all) == "herb,ore20,ore5,oreInReagentBag", names(all))
	check("Deposit all: nothing stays", stay == 0)

	local mine = SL.StacksToDeposit(stacks(), { professionReagents = { [ORE] = true, [HELM] = true } })
	check("Own professions: only their reagents, whatever the item class", names(mine) == "helm,ore20,ore5,oreInReagentBag", names(mine))

	local kept, keptCount = SL.StacksToDeposit(stacks(), { keep = { [ORE] = 8 } })
	check("Keep for queue: the reagent bag stack stays first, then the largest", names(kept) == "herb,ore5", names(kept))
	check("Keep for queue: counts the stacks that stay", keptCount == 2)

	local short = SL.StacksToDeposit(stacks(), { keep = { [ORE] = 500, [HELM] = 1 } })
	check("Keep for queue: a need above the stock keeps every stack", names(short) == "herb", names(short))
	check("Deposit: display order is kept", all[1].name == "ore20" and all[4].name == "herb")
end

-- Taking back from the bank
do
	local bank = {
		{ name = "ore200", itemID = ORE, count = 200 },
		{ name = "ore5", itemID = ORE, count = 5 },
		{ name = "ore2", itemID = ORE, count = 2 },
		{ name = "herb10", itemID = HERB, count = 10 },
		{ name = "lockedHerb", itemID = HERB, count = 10, locked = true },
		{ name = "leather", itemID = LEATHER, count = 10 },
	}
	local take, short = SL.StacksToWithdraw(bank, { [ORE] = 10, [HERB] = 30, [LEATHER] = 4, [HELM] = 1 }, { [ORE] = 4, [LEATHER] = 4 })
	check("Withdraw: small stacks that fit before one that overshoots", names(take) == "herb10,ore2,ore5", names(take))
	check("Withdraw: nothing taken for an item the bags already cover", not names(take):find("leather"))
	check("Withdraw: reports what the bank cannot cover", short[HERB] == 20 and short[HELM] == 1 and short[ORE] == nil)

	local over = SL.StacksToWithdraw(bank, { [ORE] = 1 }, {})
	check("Withdraw: when every stack overshoots, the smallest goes", names(over) == "ore2", names(over))
end

if failed > 0 then
	os.exit(1)
end
print("All ReagentStashLogic tests passed")
