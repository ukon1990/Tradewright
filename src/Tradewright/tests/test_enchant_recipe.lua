-- Run with: lua5.1 tests/test_enchant_recipe.lua (from Tradewright root)
-- An enchant makes no item of its own. It is valued as the scroll it makes on an Enchanting Vellum,
-- found in the shipped list, and its reagents get one vellum.
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

local WORD_OF_AGILITY, WORD_OF_AGILITY_SCROLL, LEYLIGHT_SHARD = 191001, 128546, 124441
local NEWER_ENCHANT, NEWER_SCROLL, BRACERS_RECIPE = 999001, 999002, 999003
local ENCHANT_TYPE, ITEM_TYPE = 3, 1

rawset(_G, "Enum", { CraftingReagentType = { Basic = 1, Finishing = 2 }, TradeskillRecipeType = { Item = ITEM_TYPE, Enchant = ENCHANT_TYPE } })

-- Retail casts enchants on a vellum; the Forever section below turns this off.
local pe = { IS_RETAIL = true }
function pe:RecipeDataInfo(recipeData) return recipeData.info end
function pe:RecipeDataSlots(recipeData) return recipeData.slots end
function pe:GetRecipeSpellID(recipeData) return recipeData.recipeSpellID end
for _, file in ipairs({
	"/Tradewright/src/util/Tradewright_EnchantLogic.lua",
	"/Tradewright/src/data/Tradewright_EnchantScrollData.lua",
	"/Tradewright_Professions/src/modules/Tradewright_CraftReagentPlan.lua",
}) do
	local chunk, err = loadfile(addons .. file)
	assert(chunk, err)
	chunk("Tradewright", pe)
end
local EnchantLogic, ReagentPlan = pe.EnchantLogic, pe.CraftReagentPlan
local VELLUM = ReagentPlan.ENCHANTING_VELLUM_ITEM_ID

local function recipe(spellID, recipeType)
	return {
		recipeSpellID = spellID,
		info = { name = "Word of Agility" },
		outputs = { recipeType = recipeType },
		slots = { { slotIndex = 1, reagentType = 1, required = true, quantityRequired = 15, reagents = { { itemID = LEYLIGHT_SHARD } } } },
	}
end

-- The shipped list
do
	local data = pe.ENCHANT_SCROLL_DATA
	local sound, count = true, 0
	for spellID, scrollItemID in pairs(data) do
		count = count + 1
		sound = sound and type(spellID) == "number" and type(scrollItemID) == "number" and spellID > 0 and scrollItemID > 0
			and spellID % 1 == 0 and scrollItemID % 1 == 0
	end
	check("List: every entry is a spell id with a scroll item id", sound and count > 0, count)
	check("List: an enchant's scroll is found", EnchantLogic.ScrollItemID(data, WORD_OF_AGILITY) == WORD_OF_AGILITY_SCROLL)
	check("List: also by an id read as text", EnchantLogic.ScrollItemID(data, tostring(WORD_OF_AGILITY)) == WORD_OF_AGILITY_SCROLL)
	check("List: an unlisted spell has no scroll", EnchantLogic.ScrollItemID(data, NEWER_ENCHANT) == nil
		and EnchantLogic.ScrollItemID(data, nil) == nil and EnchantLogic.ScrollItemID(nil, WORD_OF_AGILITY) == nil)
end

-- Which recipes are enchants
do
	check("Enchant: the game's recipe type says so", ReagentPlan.craftIsEnchantRecipe(recipe(NEWER_ENCHANT, ENCHANT_TYPE)))
	check("Enchant: a listed spell without a stored type", ReagentPlan.craftIsEnchantRecipe(recipe(WORD_OF_AGILITY, nil)))
	check("Enchant: an item recipe is none", not ReagentPlan.craftIsEnchantRecipe(recipe(BRACERS_RECIPE, ITEM_TYPE)))
	check("Enchant: a client without recipe types knows listed spells only", EnchantLogic.IsEnchantRecipe(nil, nil, pe.ENCHANT_SCROLL_DATA, WORD_OF_AGILITY)
		and not EnchantLogic.IsEnchantRecipe(nil, nil, pe.ENCHANT_SCROLL_DATA, BRACERS_RECIPE))
end

-- The crafted item
do
	local asked = {}
	rawset(_G, "C_TradeSkillUI", { GetRecipeOutputItemData = function(recipeID, reagents)
		asked[#asked + 1] = recipeID
		local first = reagents[1]
		if recipeID == NEWER_ENCHANT and first and first.reagent.itemID == VELLUM then
			return { itemID = NEWER_SCROLL }
		end
		return nil
	end })
	local resolve = ReagentPlan.resolveCraftOutputItemID
	check("Output: a listed enchant is its scroll", resolve(pe, WORD_OF_AGILITY, recipe(WORD_OF_AGILITY, ENCHANT_TYPE)) == WORD_OF_AGILITY_SCROLL)
	check("Output: the list needs no answer from the game", #asked == 0)
	check("Output: an unlisted enchant is what the game makes on a vellum", resolve(pe, NEWER_ENCHANT, recipe(NEWER_ENCHANT, ENCHANT_TYPE)) == NEWER_SCROLL)
	check("Output: none when the game names no item", resolve(pe, BRACERS_RECIPE, recipe(BRACERS_RECIPE, ITEM_TYPE)) == nil)
	rawset(_G, "C_TradeSkillUI", { GetRecipeOutputItemData = function() error("reagents not accepted") end })
	check("Output: a refused call is no item, not an error", resolve(pe, NEWER_ENCHANT, recipe(NEWER_ENCHANT, ENCHANT_TYPE)) == nil)
end

-- The reagents
do
	local function vellumLines(plan)
		local lines, quantity = 0, 0
		for _, entry in ipairs(plan) do
			if entry.itemID == VELLUM then
				lines, quantity = lines + 1, quantity + entry.quantityRequired
			end
		end
		return lines, quantity
	end
	local plan = pe:PickCheapestReagentsPerSlot(recipe(WORD_OF_AGILITY, nil), function() return 10 end)
	local lines, quantity = vellumLines(plan)
	check("Plan: an enchant costs its reagents and one vellum", #plan == 2 and plan[1].itemID == LEYLIGHT_SHARD and lines == 1 and quantity == 1, #plan)
	plan = pe:PickCheapestReagentsPerSlot(recipe(BRACERS_RECIPE, ITEM_TYPE), function() return 10 end)
	check("Plan: an item recipe gets no vellum", #plan == 1 and vellumLines(plan) == 0)
end

-- WoW Forever: no vellum, the enchant is cast on gear
do
	pe.IS_RETAIL = false
	rawset(_G, "C_TradeSkillUI", { GetRecipeOutputItemData = function() return { itemID = NEWER_SCROLL } end })
	check("Forever: an enchant is cast on gear", ReagentPlan.enchantCastOnGear(recipe(WORD_OF_AGILITY, ENCHANT_TYPE))
		and not ReagentPlan.enchantGoesOnVellum(recipe(WORD_OF_AGILITY, ENCHANT_TYPE)))
	check("Forever: an item recipe is not", not ReagentPlan.enchantCastOnGear(recipe(BRACERS_RECIPE, ITEM_TYPE)))
	check("Forever: an enchant makes no scroll", ReagentPlan.resolveCraftOutputItemID(pe, WORD_OF_AGILITY, recipe(WORD_OF_AGILITY, ENCHANT_TYPE)) == nil)
	local plan = pe:PickCheapestReagentsPerSlot(recipe(WORD_OF_AGILITY, ENCHANT_TYPE), function() return 10 end, { forceEnchantingVellum = true })
	check("Forever: an enchant costs its reagents only, even when the queue asks for a vellum", #plan == 1 and plan[1].itemID == LEYLIGHT_SHARD, #plan)
	local withTarget = { { itemID = LEYLIGHT_SHARD, slotClass = "mandatory_base" }, { itemID = VELLUM, slotClass = "required_target" } }
	ReagentPlan.planEnchantTarget(withTarget, recipe(WORD_OF_AGILITY, ENCHANT_TYPE), true)
	check("Forever: a target entry leaves the plan", #withTarget == 1 and withTarget[1].itemID == LEYLIGHT_SHARD)
	pe.IS_RETAIL = true
end

-- Which gear an enchant goes on
do
	local pick = EnchantLogic.PickTarget
	local worn = { equipped = true, sellPrice = 500 }
	local cheap, dear, unpriced = { sellPrice = 3 }, { sellPrice = 90 }, {}
	check("Target: worn gear comes first", pick({ dear, cheap, worn }) == worn)
	check("Target: else the bag item that sells for least", pick({ dear, unpriced, cheap }) == cheap)
	check("Target: an item without a vendor price comes last", pick({ unpriced, dear }) == dear)
	check("Target: the first worn item stays", pick({ worn, { equipped = true, sellPrice = 1 } }) == worn)
	check("Target: nothing fits", pick({}) == nil and pick(nil) == nil)
end

if failed > 0 then
	os.exit(1)
end
