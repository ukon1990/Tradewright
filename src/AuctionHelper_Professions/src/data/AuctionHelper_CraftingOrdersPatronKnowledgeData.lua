local _, AuctionHelper = ...

--- Recipe spell IDs (same as C_TradeSkillUI.GetRecipeInfo first argument) that award
--- profession knowledge when fulfilled via Patron/NPC crafting orders.
--- This is not the same as "first craft" UI; populate from datamining or community data.
--- When empty, the "Patron knowledge only" filter has no effect (all recipes stay visible).
if AuctionHelper.CRAFTING_ORDERS_PATRON_KNOWLEDGE_RECIPE_IDS == nil then
	AuctionHelper.CRAFTING_ORDERS_PATRON_KNOWLEDGE_RECIPE_IDS = {
		-- [123456] = true,
	}
end
