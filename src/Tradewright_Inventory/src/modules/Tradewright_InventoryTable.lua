local _, Tradewright = ...

--- Per itemID: appears as recipe output and/or reagent in scanned professions.
function Tradewright:BuildItemRoleMap(characterData)
	local roles = {}
	local function ensure(id)
		id = tonumber(id)
		if not id or id <= 0 then
			return nil
		end
		if not roles[id] then
			roles[id] = { output = false, reagent = false }
		end
		return roles[id]
	end

	if not characterData or type(characterData.professions) ~= "table" then
		return roles
	end

	for _, professionData in pairs(characterData.professions) do
		for _, recipeData in pairs(professionData.recipes or {}) do
			local outputs = recipeData.outputs
			if outputs then
				local primary = self:RecipeOutputsPrimaryItemId(outputs)
				local r = ensure(primary)
				if r then
					r.output = true
				end
				if type(outputs.qualityVariants) == "table" then
					for _, variant in ipairs(outputs.qualityVariants) do
						local rr = ensure(variant.itemID)
						if rr then
							rr.output = true
						end
					end
				end
			end
			local slots = self:RecipeDataSlots(recipeData)
			if type(slots) == "table" then
				for _, slot in ipairs(slots) do
					if type(slot.reagents) == "table" then
						for _, reagent in ipairs(slot.reagents) do
							local rr = ensure(reagent.itemID)
							if rr then
								rr.reagent = true
							end
						end
					end
				end
			end
		end
	end

	return roles
end

function Tradewright:GetItemRoleLabelFromRoles(roleEntry)
	if not roleEntry then
		return "Other"
	end
	local o, r = roleEntry.output, roleEntry.reagent
	if o and r then
		return "Crafted + reagent"
	end
	if o then
		return "Crafted"
	end
	if r then
		return "Crafting reagent"
	end
	return "Other"
end

function Tradewright:GetItemRoleKeyFromRoles(roleEntry)
	if not roleEntry then
		return "tracked"
	end
	local o, r = roleEntry.output, roleEntry.reagent
	if o and r then
		return "crafted_reagent"
	end
	if o then
		return "crafted"
	end
	if r then
		return "crafting_reagent"
	end
	return "tracked"
end

--- character: { data, key, display (short label for the sidebar), roleMap }. roleMap comes from
--- BuildItemRoleMap(data); pass it when building many rows, else it is rebuilt per row.
function Tradewright:BuildInventoryRowFromSnapshot(character, invEntry, itemID)
	local roles = character.roleMap or self:BuildItemRoleMap(character.data)
	local roleEntry = roles[itemID]
	local itemDesc = self:ResolveItemDescriptor(itemID)
	return {
		characterKey = character.key,
		characterDisplay = character.display,
		itemID = itemID,
		name = (itemDesc and itemDesc.name) or self:GetItemDisplayName(itemID),
		icon = itemDesc and itemDesc.icon,
		roleKey = self:GetItemRoleKeyFromRoles(roleEntry),
		roleLabel = self:GetItemRoleLabelFromRoles(roleEntry),
		sourceLabel = self:GetItemRoleLabelFromRoles(roleEntry),
		itemTypeLabel = itemDesc and itemDesc.itemType or "Unknown",
		itemSubTypeLabel = itemDesc and itemDesc.itemSubType or "",
		classID = itemDesc and itemDesc.classID,
		subclassID = itemDesc and itemDesc.subclassID,
		isCraftingReagent = itemDesc and itemDesc.isCraftingReagent or false,
		bags = invEntry.bags or 0,
		bank = invEntry.bank or 0,
		warband = invEntry.warband or 0,
		total = invEntry.total or 0,
	}
end

--- All rows with total > 0 for one character.
function Tradewright:BuildInventoryRowsForCharacter(db, characterKey)
	local charData = db and db.characters and db.characters[characterKey]
	if not charData then
		return {}
	end
	local inv = charData.inventorySnapshot
	if not inv or type(inv.items) ~= "table" then
		return {}
	end
	local meta = charData.meta or {}
	local display = (meta.name and meta.realm) and string.format("%s - %s", tostring(meta.name), tostring(meta.realm))
		or characterKey
	local character = { data = charData, key = characterKey, display = display, roleMap = self:BuildItemRoleMap(charData) }
	local rows = {}
	for itemKey, entry in pairs(inv.items) do
		local id = tonumber(itemKey)
		if id and (entry.total or 0) > 0 then
			table.insert(rows, self:BuildInventoryRowFromSnapshot(character, entry, id))
		end
	end
	return rows
end

--- Merge profession role flags across characters in the same sense as BuildInventoryItemTotals (empty selection = all).
--- Also returns perCharacterRoleMaps[characterKey] = full map from BuildItemRoleMap (reuse for mat-cost estimates; one scan per character per refresh).
function Tradewright:BuildMergedItemRoleMapForSelection(db, characterSelection)
	local merged = {}
	local perCharacterRoleMaps = {}
	if not db or type(db.characters) ~= "table" then
		return merged, perCharacterRoleMaps
	end
	for characterKey, characterData in pairs(db.characters) do
		if self:IsFilterSelectionEmpty(characterSelection) or characterSelection[characterKey] == true then
			local rm = self:BuildItemRoleMap(characterData)
			perCharacterRoleMaps[characterKey] = rm
			for id, entry in pairs(rm) do
				local idn = tonumber(id)
				if idn and entry then
					local m = merged[idn]
					if not m then
						m = { output = false, reagent = false }
						merged[idn] = m
					end
					m.output = m.output or entry.output
					m.reagent = m.reagent or entry.reagent
				end
			end
		end
	end
	return merged, perCharacterRoleMaps
end

--- One row per itemID; bags/bank/warband/total from BuildInventoryItemTotals(characterSelection).
--- @param characterDisplayLabel string label for the Character column (e.g. filter summary).
--- @param mergedRolesOptional table|nil if set, skip rebuilding merged roles (must match characterSelection).
function Tradewright:BuildInventoryRowsAggregatedByItem(db, characterSelection, characterDisplayLabel, mergedRolesOptional)
	local rows = {}
	if not db then
		return rows
	end

	local mergedRoles = mergedRolesOptional
	if not mergedRoles then
		mergedRoles = self:BuildMergedItemRoleMapForSelection(db, characterSelection)
	end
	local seen = {}
	for characterKey, characterData in pairs(db.characters or {}) do
		if self:IsFilterSelectionEmpty(characterSelection) or characterSelection[characterKey] == true then
			local inv = characterData.inventorySnapshot
			if inv and type(inv.items) == "table" then
				for itemKey, entry in pairs(inv.items) do
					local id = tonumber(itemKey)
					if id and (entry.total or 0) > 0 then
						seen[id] = true
					end
				end
			end
		end
	end

	local itemIds = {}
	for id in pairs(seen) do
		itemIds[#itemIds + 1] = id
	end
	table.sort(itemIds)

	local label = characterDisplayLabel or ""
	for _, itemID in ipairs(itemIds) do
		local totals = self:BuildInventoryItemTotals(itemID, characterSelection)
		if (totals.total or 0) > 0 then
			local roleEntry = mergedRoles[itemID]
			local itemDesc = self:ResolveItemDescriptor(itemID)
			rows[#rows + 1] = {
				characterKey = nil,
				characterDisplay = label,
				itemID = itemID,
				aggregatedInventory = true,
				name = (itemDesc and itemDesc.name) or self:GetItemDisplayName(itemID),
				icon = itemDesc and itemDesc.icon,
				roleKey = self:GetItemRoleKeyFromRoles(roleEntry),
				roleLabel = self:GetItemRoleLabelFromRoles(roleEntry),
				sourceLabel = self:GetItemRoleLabelFromRoles(roleEntry),
				itemTypeLabel = itemDesc and itemDesc.itemType or "Unknown",
				itemSubTypeLabel = itemDesc and itemDesc.itemSubType or "",
				expansionTag = self:ExpansionLeToFilterTag(itemDesc and itemDesc.expansionID) or "legacy",
				classID = itemDesc and itemDesc.classID,
				subclassID = itemDesc and itemDesc.subclassID,
				isCraftingReagent = itemDesc and itemDesc.isCraftingReagent or false,
				bags = totals.bags or 0,
				bank = totals.bank or 0,
				warband = totals.warband or 0,
				total = totals.total or 0,
				holders = totals.holders,
			}
		end
	end

	return rows
end

--- Pick a learned recipe on character that outputs itemID (for mat cost); prefers lowest material estimate when priceFn given.
function Tradewright:FindBestRecipeForOutputItem(characterData, itemID, estimateMatFn)
	if not characterData or not itemID then
		return nil, nil
	end
	local bestRecipe, bestCost = nil, math.huge
	for _, professionData in pairs(characterData.professions or {}) do
		for rid, recipeData in pairs(professionData.recipes or {}) do
			local info = self:RecipeDataInfo(recipeData)
			local learned = recipeData.learned
			if learned == nil and info then
				learned = info.learned
			end
			if learned ~= false then
				local outs = recipeData.outputs
				local match = false
				if outs then
					if self:RecipeOutputsPrimaryItemId(outs) == itemID then
						match = true
					end
					if not match and type(outs.qualityVariants) == "table" then
						for _, variant in ipairs(outs.qualityVariants) do
							if variant.itemID == itemID then
								match = true
								break
							end
						end
					end
				end
				if match then
					local recipeID = tonumber(rid) or rid
					if estimateMatFn then
						local c = estimateMatFn(recipeData)
						if c and c < bestCost then
							bestCost = c
							bestRecipe = recipeID
						end
					else
						return recipeID, recipeData
					end
				end
			end
		end
	end
	if bestRecipe and bestCost < math.huge then
		return bestRecipe, bestCost
	end
	return nil, nil
end
