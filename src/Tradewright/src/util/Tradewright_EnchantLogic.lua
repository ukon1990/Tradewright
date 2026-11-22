local _, Tradewright = ...

--- Pure helpers for enchant recipes. No WoW API.
---
--- An enchant makes no item of its own. Crafted for sale it is cast on an Enchanting Vellum, which
--- gives a scroll; that scroll is what the recipe is valued as.
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
