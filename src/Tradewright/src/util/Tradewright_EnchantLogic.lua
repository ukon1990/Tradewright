local _, Tradewright = ...

--- Pure helpers for enchant recipes. No WoW API.
---
--- An enchant makes no item of its own. On retail, crafted for sale it is cast on an Enchanting
--- Vellum, which gives a scroll; that scroll is what the recipe is valued as. WoW Forever has no
--- vellum, so there an enchant is cast on gear the player wears or carries.
---
--- `scrollData = { [enchant spell id] = scroll item id }` (see Tradewright_EnchantScrollData.lua).
local EnchantLogic = {}
Tradewright.EnchantLogic = EnchantLogic

--- The scroll an enchant makes on a vellum, or nil when the enchant is not listed.
function EnchantLogic.ScrollItemID(scrollData, recipeSpellID)
	recipeSpellID = tonumber(recipeSpellID)
	local scrollItemID = recipeSpellID and type(scrollData) == "table" and tonumber(scrollData[recipeSpellID])
	return scrollItemID or nil
end

--- Whether a recipe is an enchant: the game says so (`recipeType` equals `enchantRecipeType`, the
--- client's Enum.TradeskillRecipeType.Enchant), or it is a listed enchant. Clients without recipe
--- types, and recipes scanned before the type was stored, are only known by the list.
function EnchantLogic.IsEnchantRecipe(recipeType, enchantRecipeType, scrollData, recipeSpellID)
	recipeType, enchantRecipeType = tonumber(recipeType), tonumber(enchantRecipeType)
	if recipeType and recipeType == enchantRecipeType then
		return true
	end
	return EnchantLogic.ScrollItemID(scrollData, recipeSpellID) ~= nil
end

-- An item without a vendor price is taken last: nothing says it is cheap.
local function sellPriceOf(item)
	return tonumber(item.sellPrice) or math.huge
end

-- Whether `item` makes a better target than `best`. Among worn items the first found stays.
local function betterTarget(item, best)
	local worn, bestWorn = item.equipped == true, best.equipped == true
	if worn ~= bestWorn then
		return worn
	end
	return not worn and sellPriceOf(item) < sellPriceOf(best)
end

--- The gear to cast an enchant on, from `items = { { equipped, sellPrice, … } }` (the items the enchant
--- can go on): a worn item first, so the enchant stays on the character, else the bag item that sells
--- to a vendor for least. nil when the list is empty.
function EnchantLogic.PickTarget(items)
	local best
	for _, item in ipairs(items or {}) do
		if not best or betterTarget(item, best) then
			best = item
		end
	end
	return best
end
