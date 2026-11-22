local _, Tradewright = ...

-- Cheapest way to get a crafting material: buy it, or craft it with a recipe one of your characters
-- knows. Vendor prices stay with the engine's own rule for vendor-sourced reagents.
--
-- The craft cost comes from the crafts engine's own last finished evaluation, so it already follows the
-- engine's rules (quality, optional reagents). That makes it one evaluation behind: a material that is
-- cheaper to craft is priced that way from the evaluation after the one that first priced its recipe.
-- The index is kept across cache invalidation so a rebuild can read the previous results.

-- A cooldown's output is capped, so its recipe is not a way to get a material in bulk.
local function withoutCooldowns(pe, rows)
	local kept = {}
	for _, row in ipairs(rows) do
		if not (pe:IsCooldownRecipe(row.recipeID) or pe:IsCooldownRecipe(row.recipeSpellID)) then
			kept[#kept + 1] = row
		end
	end
	return kept
end

local function craftUnitCostIndex(pe)
	local state = pe:GetState()
	local rows = state.craftOpportunityRows or state.craftOpportunityRowsStale
	if rows and rows ~= state.craftUnitCostRows then
		state.craftUnitCostRows = rows
		state.craftUnitCostIndex = pe.MaterialLogic.UnitCostIndex(withoutCooldowns(pe, rows))
	end
	return state.craftUnitCostIndex or {}
end

--- Cost per unit of crafting `itemID` yourself and who can: `cost, crafterKey`, or nil.
function Tradewright:GetCraftUnitCost(itemID)
	local entry = craftUnitCostIndex(self)[tonumber(itemID)]
	if not entry then
		return nil
	end
	return entry.cost, entry.crafter
end

--- Queues `count` crafts of a craft row and, for every material its plan prices as crafted, the
--- crafts that make that material, for the character whose recipe is cheapest. One level deep: the
--- materials of those crafts are bought, as the queue's "Cart" shows.
function Tradewright:AddCraftWithMaterialCraftsToQueue(row, count)
	local added, reason = self:AddCraftToQueue(row, count)
	if not added then
		return added, reason
	end
	local evaluation = row.perChar and row.perChar[row.bestCharacterKey]
	local materialCrafts = self.MaterialLogic.MaterialCraftsNeeded(evaluation and evaluation.reagentPlan, count, craftUnitCostIndex(self))
	for _, material in ipairs(materialCrafts) do
		self:AddCraftToQueue(material.row, material.crafts)
	end
	return added
end

--- The cheapest unit price for a material and where it comes from. `unit, source` is what the engine
--- found by its usual rules (vendor for vendor-sourced reagents, ledger, market); your own recipe
--- replaces it when crafting the material is cheaper.
function Tradewright:CheapestMaterialUnit(itemID, unit, source)
	if not self:GetSetting("crafts.useCheapestSource", true) then
		return unit, source
	end
	return self.MaterialLogic.CheapestSource({
		{ unit, source },
		{ self:GetCraftUnitCost(itemID), "Craft" },
	})
end
