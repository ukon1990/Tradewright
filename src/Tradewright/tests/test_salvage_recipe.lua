-- Run with: lua5.1 tests/test_salvage_recipe.lua (from Tradewright root)
-- A salvage recipe (Prospecting, Milling) destroys an item of the player's choice. Its reagent slot
-- holds every item the game accepts, and reagent planning picks the cheapest one with a price.
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

local PROSPECTING, COPPER_ORE, TIN_ORE, IRON_ORE = 31252, 2770, 2771, 2772
local salvagable = { [PROSPECTING] = { COPPER_ORE, TIN_ORE, IRON_ORE } }

rawset(_G, "Enum", { CraftingReagentType = { Basic = 1, Finishing = 2 } })
rawset(_G, "C_TradeSkillUI", { GetSalvagableItemIDs = function(spellID) return salvagable[spellID] end })

local pe = {}
function pe:RecipeDataInfo(recipeData) return recipeData.info end
function pe:RecipeDataSlots(recipeData) return recipeData.slots end
function pe:GetRecipeSpellID(recipeData) return recipeData.recipeSpellID end
for _, file in ipairs({
	"/Tradewright/src/util/Tradewright_MaterialLogic.lua",
	"/Tradewright/src/util/Tradewright_EnchantLogic.lua",
	"/Tradewright/src/core/Tradewright_ProfessionScan.lua",
	"/Tradewright_Professions/src/modules/Tradewright_CraftReagentPlan.lua",
}) do
	local chunk, err = loadfile(addons .. file)
	assert(chunk, err)
	chunk("Tradewright", pe)
end

local function savedRecipe(isSalvage)
	return { recipeSpellID = PROSPECTING, info = { name = "Prospecting", isSalvageRecipe = isSalvage }, schematic = { quantityMax = 5 }, slots = {} }
end

-- The slot
do
	local slot = pe.MaterialLogic.MakeSalvageSlot({ COPPER_ORE, 0, "x", TIN_ORE }, 5)
	check("Slot: one required slot with every usable item", slot.required and slot.quantityRequired == 5 and #slot.reagents == 2
		and slot.reagents[2].itemID == TIN_ORE)
	check("Slot: none without a usable item", pe.MaterialLogic.MakeSalvageSlot({}, 5) == nil)
end

-- A recipe saved before salvage slots were collected
do
	local recipeData = savedRecipe(true)
	check("Saved recipe: known as a salvage recipe", pe:PrepareSalvageRecipe(recipeData) == true)
	check("Saved recipe: gets its slot from the game", #recipeData.slots == 1 and #recipeData.slots[1].reagents == 3)
	pe:PrepareSalvageRecipe(recipeData)
	check("Saved recipe: the slot is added once", #recipeData.slots == 1)
	local other = savedRecipe(nil)
	check("Another recipe is left alone", pe:PrepareSalvageRecipe(other) == false and #other.slots == 0)
end

-- The cheapest item is planned
do
	local recipeData = savedRecipe(true)
	pe:PrepareSalvageRecipe(recipeData)
	local prices = { [COPPER_ORE] = 40, [TIN_ORE] = 25 }
	local plan = pe:PickCheapestReagentsPerSlot(recipeData, function(itemID) return prices[itemID] end)
	check("Plan: one line, the cheapest item with a price, for what one craft destroys",
		#plan == 1 and plan[1].itemID == TIN_ORE and plan[1].quantityRequired == 5, plan[1] and plan[1].itemID)
	plan = pe:PickCheapestReagentsPerSlot(recipeData, function() return nil end)
	check("Plan: no price known still names an item, so the cart can list it", #plan == 1 and plan[1].itemID == COPPER_ORE)
end

if failed > 0 then
	os.exit(1)
end
