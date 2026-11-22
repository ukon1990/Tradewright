local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Read-only queries over learned recipes and craft rows: item IDs to price, filter options, confidence, row lookup.

local classifyCraftReagentSlot = Tradewright.CraftReagentPlan.classifyCraftReagentSlot

--- Unique sorted item IDs for AH pricing: outputs + reagents from stored learned recipes.
--- opts.characterKey: restrict to one character; default = all characters in db.
function Tradewright:BuildCraftEconomyItemIDs(opts)
	self:InitDB()
	opts = type(opts) == "table" and opts or {}
	local includeOptional = self:GetSetting("auction.craftScanIncludeOptionalSlots", false) == true
	local scopeKey = opts.characterKey and tostring(opts.characterKey) or nil
	local seen = {}
	local function add(id)
		id = tonumber(id)
		if id and id > 0 then
			seen[id] = true
		end
	end

	for characterKey, characterData in pairs(self.db.characters or {}) do
		if not scopeKey or tostring(characterKey) == scopeKey then
			for _, professionData in pairs(characterData.professions or {}) do
				for _, recipeData in pairs(professionData.recipes or {}) do
					local info = self:RecipeDataInfo(recipeData)
					if info and info.learned ~= false then
						local outs = recipeData.outputs
						if outs then
							add(self:RecipeOutputsPrimaryItemId(outs))
							if type(outs.qualityVariants) == "table" then
								for _, variant in ipairs(outs.qualityVariants) do
									add(variant and variant.itemID)
								end
							end
						end
						local slots = self:RecipeDataSlots(recipeData)
						if type(slots) == "table" then
							for _, slot in ipairs(slots) do
								local slotClass = classifyCraftReagentSlot(professionData, recipeData, slot)
								local include = false
								if slotClass == "mandatory_base" or slotClass == "required_target" then
									include = true
								elseif slotClass == "optional" and includeOptional then
									include = true
								end
								if include and type(slot.reagents) == "table" then
									for _, reagent in ipairs(slot.reagents) do
										add(reagent and reagent.itemID)
									end
								end
							end
						end
					end
				end
			end
		end
	end

	local ids = {}
	for id in pairs(seen) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

--- Targets for AH search queue: itemID plus optional auction item-key fields when present on stored outputs.
function Tradewright:BuildCraftEconomyAuctionTargets(opts)
	opts = type(opts) == "table" and opts or {}
	local ids = self:BuildCraftEconomyItemIDs(opts)
	local targets = {}
	for _, id in ipairs(ids) do
		targets[#targets + 1] = { itemID = id, itemKeyFields = nil }
	end
	return targets
end

function Tradewright:FilterCraftRows(rows, filters)
	return self.FilterLogic.FilterCraftRows(rows, filters)
end

function Tradewright:GetCraftProfessionFilterOptions()
	self:InitDB()
	local seen = {}
	local opts = { { value = "all", label = L["All professions"] } }
	for _, characterData in pairs(self.db.characters or {}) do
		for skillLineID, professionData in pairs(characterData.professions or {}) do
			local sid = tostring(skillLineID)
			if not seen[sid] then
				seen[sid] = true
				opts[#opts + 1] = {
					value = sid,
					label = professionData.professionName or sid,
				}
			end
		end
	end
	table.sort(opts, function(a, b)
		if a.value == "all" then
			return true
		end
		if b.value == "all" then
			return false
		end
		return tostring(a.label) < tostring(b.label)
	end)
	return opts
end

function Tradewright:GetCraftCategoryFilterOptions(rows)
	local seen = {}
	local opts = { { value = "all", label = L["All categories"] } }
	for _, row in ipairs(rows or {}) do
		local cid = row.categoryID
		if cid and not seen[cid] then
			seen[cid] = true
			local label = row.categoryName and tostring(row.categoryName)
			if not label or label == "" then
				label = self:ResolveCraftCategoryLabel(row.skillLineID, cid)
			end
			if not label or label == "" then
				label = L["Category "] .. tostring(cid)
			end
			opts[#opts + 1] = { value = tostring(cid), label = label }
		end
	end
	table.sort(opts, function(a, b)
		if a.value == "all" then
			return true
		end
		if b.value == "all" then
			return false
		end
		return tostring(a.label) < tostring(b.label)
	end)
	return opts
end

function Tradewright:ResolveCraftConfidenceState(eval, dataSource)
	if not eval then
		return "stale_scan"
	end
	if not eval.saleGross then
		return "missing_sale_price"
	end
	if eval.matMissingPrice then
		return "missing_mat_price"
	end
	if dataSource == "scan_fallback_live" then
		return "stale_scan"
	end
	return "ok"
end

function Tradewright:FindCraftOpportunityRowForRecipe(recipeID, outputItemID)
	if not recipeID or not outputItemID then
		return nil
	end
	local rows = self:BuildCraftOpportunityRows({ forceSync = true })
	for _, row in ipairs(rows) do
		if tonumber(row.outputItemID) == tonumber(outputItemID)
			and (tonumber(row.recipeID) == tonumber(recipeID)
				or tonumber(row.recipeSpellID) == tonumber(recipeID)) then
			return row
		end
	end
	return nil
end
