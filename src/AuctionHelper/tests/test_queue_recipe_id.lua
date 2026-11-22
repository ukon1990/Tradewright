-- Run with: lua5.1 tests/test_queue_recipe_id.lua (from AuctionHelper root)
-- Which recipe id the Queue view hands to the profession window for a craft queue line.
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

local STORED_ID, SPELL_ID, SHOULDERS, OTHER_ITEM = 2177, 3768, 4264, 5555

local pe = { db = { characters = { Tester = { professions = { ["165"] = { recipes = {
	[tostring(STORED_ID)] = { recipeSpellID = SPELL_ID, outputs = { itemID = SHOULDERS } },
	-- Another recipe whose stored id happens to equal the first one's spell.
	[tostring(SPELL_ID)] = { recipeSpellID = 9999, outputs = { itemID = OTHER_ITEM } },
} } } } } } }
function pe:GetRecipeSpellID(recipeData) return recipeData.recipeSpellID end
function pe:GetRankMarkup() return "" end
local chunk, err = loadfile(root .. "/../AuctionHelper_UI/src/ui/AuctionHelper_ProfessionQueueView.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)

local function line(recipeID, outputItemID, skillLineID)
	return { recipeID = recipeID, outputItemID = outputItemID, characterKey = "Tester", skillLineID = skillLineID or 165 }
end

check("Queued from the dashboard (stored id): translated to the spell", pe:GetCraftQueueLineSpellID(line(STORED_ID, SHOULDERS)) == SPELL_ID)
check("Queued in the profession window (spell id): kept, though another recipe is stored under that number",
	pe:GetCraftQueueLineSpellID(line(SPELL_ID, SHOULDERS)) == SPELL_ID)
check("No scan for the profession: the id is used as it is", pe:GetCraftQueueLineSpellID(line(STORED_ID, SHOULDERS, 999)) == STORED_ID)
check("A crafting-order line without a profession: the id is used as it is",
	pe:GetCraftQueueLineSpellID({ recipeID = SPELL_ID, outputItemID = SHOULDERS }) == SPELL_ID)

if failed > 0 then
	os.exit(1)
end
