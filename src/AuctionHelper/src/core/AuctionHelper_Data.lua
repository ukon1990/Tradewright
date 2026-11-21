-- Session state (GetState), character metadata, and the recipe, reagent and filter readers the profession scan and export share.
local _, AuctionHelper = ...

function AuctionHelper:GetState()
	self.state = self.state or {
		scanInProgress = false,
		currentProfession = nil,
		queue = {},
		pendingScan = false,
		copyFrame = nil,
		liveInvTimer = nil,
		liveProfessionTimer = nil,
		liveFingerprintTimer = nil,
		liveProfessionMergeJob = nil,
		dataRevision = 0,
		builtAggregateRevision = nil,
		invSnapshotPending = nil,
		liveProfessionSkillLineID = nil,
		liveProfessionOpenFingerprint = nil,
		liveProfessionOpenFingerprintInfo = nil,
		liveProfessionLastFingerprint = nil,
		liveProfessionLastFingerprintInfo = nil,
		exportJsonBusy = false,
	}
	return self.state
end

function AuctionHelper:BumpDataRevision()
	local s = self:GetState()
	s.dataRevision = (s.dataRevision or 0) + 1
end

function AuctionHelper:AggregateNeedsRebuild()
	self:InitDB()
	local s = self:GetState()
	local agg = self.db.aggregate
	if type(agg) ~= "table" or type(agg.characterKeys) ~= "table" then
		return true
	end
	if s.builtAggregateRevision == nil then
		return true
	end
	return s.builtAggregateRevision ~= (s.dataRevision or 0)
end

function AuctionHelper:GetCharacterMetadata()
	local _, classFile = UnitClass("player")
	local _, raceFile = UnitRace("player")
	local name, realm = UnitFullName("player")

	return {
		key = self:GetCharacterKey(),
		name = name,
		realm = realm or GetRealmName(),
		class = classFile,
		race = raceFile,
		faction = UnitFactionGroup("player"),
		level = UnitLevel("player"),
		guid = UnitGUID("player"),
		locale = GetLocale(),
		timestamp = time(),
		build = self:GetBuildMetadata(),
	}
end

function AuctionHelper:GetPlayerProfessions()
	local professions = {}
	local professionIndices = { GetProfessions() }

	for _, professionIndex in ipairs(professionIndices) do
		if professionIndex then
			local professionName, icon, skillLevel, maxSkillLevel, numAbilities, spellOffset, skillLineID,
				bonusSkill, specializationIndex, specializationOffset, currentLevelName = GetProfessionInfo(professionIndex)

			if skillLineID and skillLineID > 0 then
				table.insert(professions, {
					professionIndex = professionIndex,
					professionName = professionName,
					currentLevelName = currentLevelName,
					icon = icon,
					skillLevel = skillLevel,
					maxSkillLevel = maxSkillLevel,
					numAbilities = numAbilities,
					spellOffset = spellOffset,
					skillLineID = skillLineID,
					bonusSkill = bonusSkill,
					specializationIndex = specializationIndex,
					specializationOffset = specializationOffset,
				})
			end
		end
	end

	table.sort(professions, function(left, right)
		return self:SortByNameThenId(left, right)
	end)
	return professions
end

function AuctionHelper:CreateCharacterScanRecord()
	local metadata = self:GetCharacterMetadata()

	return {
		meta = metadata,
		addonVersion = self.VERSION,
		schemaVersion = self.SCHEMA_VERSION,
		scanStartedAt = time(),
		scanFinishedAt = nil,
		professions = {},
	}
end

function AuctionHelper:SnapshotFilters()
	return {
		showUnlearned = C_TradeSkillUI.GetShowUnlearned and C_TradeSkillUI.GetShowUnlearned() or nil,
		onlyShowMakeable = C_TradeSkillUI.GetOnlyShowMakeableRecipes and C_TradeSkillUI.GetOnlyShowMakeableRecipes() or nil,
		onlyShowSkillUp = C_TradeSkillUI.GetOnlyShowSkillUpRecipes and C_TradeSkillUI.GetOnlyShowSkillUpRecipes() or nil,
		recipeItemNameFilter = C_TradeSkillUI.GetRecipeItemNameFilter and C_TradeSkillUI.GetRecipeItemNameFilter() or nil,
		itemLevelFilter = C_TradeSkillUI.GetRecipeItemLevelFilter and { C_TradeSkillUI.GetRecipeItemLevelFilter() } or nil,
	}
end

function AuctionHelper:ApplyExportFilters()
	if C_TradeSkillUI.SetShowLearned then
		C_TradeSkillUI.SetShowLearned(true)
	end
	if C_TradeSkillUI.SetShowUnlearned then
		C_TradeSkillUI.SetShowUnlearned(true)
	end
	if C_TradeSkillUI.SetOnlyShowMakeableRecipes then
		C_TradeSkillUI.SetOnlyShowMakeableRecipes(false)
	end
	if C_TradeSkillUI.SetOnlyShowSkillUpRecipes then
		C_TradeSkillUI.SetOnlyShowSkillUpRecipes(false)
	end
	if C_TradeSkillUI.ClearRecipeCategoryFilter then
		C_TradeSkillUI.ClearRecipeCategoryFilter()
	end
	if C_TradeSkillUI.ClearInventorySlotFilter then
		C_TradeSkillUI.ClearInventorySlotFilter()
	end
	if C_TradeSkillUI.SetRecipeItemNameFilter then
		C_TradeSkillUI.SetRecipeItemNameFilter(nil)
	end
	if C_TradeSkillUI.SetRecipeItemLevelFilter then
		C_TradeSkillUI.SetRecipeItemLevelFilter(0, 0)
	end
end

function AuctionHelper:RestoreFilters(snapshot)
	if not snapshot then
		return
	end

	if snapshot.showUnlearned ~= nil and C_TradeSkillUI.SetShowUnlearned then
		C_TradeSkillUI.SetShowUnlearned(snapshot.showUnlearned)
	end
	if C_TradeSkillUI.SetOnlyShowMakeableRecipes and snapshot.onlyShowMakeable ~= nil then
		C_TradeSkillUI.SetOnlyShowMakeableRecipes(snapshot.onlyShowMakeable)
	end
	if C_TradeSkillUI.SetOnlyShowSkillUpRecipes and snapshot.onlyShowSkillUp ~= nil then
		C_TradeSkillUI.SetOnlyShowSkillUpRecipes(snapshot.onlyShowSkillUp)
	end
	if C_TradeSkillUI.SetRecipeItemNameFilter and snapshot.recipeItemNameFilter ~= nil then
		C_TradeSkillUI.SetRecipeItemNameFilter(snapshot.recipeItemNameFilter)
	end
	if C_TradeSkillUI.SetRecipeItemLevelFilter and snapshot.itemLevelFilter then
		C_TradeSkillUI.SetRecipeItemLevelFilter(snapshot.itemLevelFilter[1] or 0, snapshot.itemLevelFilter[2] or 0)
	end
end

function AuctionHelper:GetQualityThresholds(maxQuality, recipeDifficulty)
	if not maxQuality or not recipeDifficulty or recipeDifficulty <= 0 then
		return {}
	end

	if maxQuality == 2 then
		return { recipeDifficulty }
	elseif maxQuality == 3 then
		return { recipeDifficulty * 0.5, recipeDifficulty }
	elseif maxQuality == 5 then
		return { recipeDifficulty * 0.2, recipeDifficulty * 0.5, recipeDifficulty * 0.8, recipeDifficulty }
	end

	return {}
end

function AuctionHelper:BuildMaxQualityRequiredReagentInfo(schematic)
	local craftingReagentInfo = {}
	if not schematic or type(schematic.reagentSlotSchematics) ~= "table" then
		return craftingReagentInfo
	end

	for _, reagentSlotSchematic in ipairs(schematic.reagentSlotSchematics) do
		if reagentSlotSchematic.reagentType == Enum.CraftingReagentType.Basic and reagentSlotSchematic.dataSlotIndex and reagentSlotSchematic.reagents then
			local chosenReagent = nil
			local chosenQuality = -1

			for _, reagent in ipairs(reagentSlotSchematic.reagents) do
				local quality = 0
				if reagent.itemID then
					quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(reagent.itemID) or 0
				end
				if quality >= chosenQuality then
					chosenQuality = quality
					chosenReagent = reagent
				end
			end

			if chosenReagent and (chosenReagent.itemID or chosenReagent.currencyID) then
				table.insert(craftingReagentInfo, {
					reagent = {
						itemID = chosenReagent.itemID,
						currencyID = chosenReagent.currencyID,
					},
					quantity = reagentSlotSchematic.quantityRequired or 0,
					dataSlotIndex = reagentSlotSchematic.dataSlotIndex,
				})
			end
		end
	end

	return craftingReagentInfo
end

function AuctionHelper:DescribeOperationInfo(recipeID, schematic)
	if not C_TradeSkillUI.GetCraftingOperationInfo then
		return nil
	end

	local baseOperationInfo = C_TradeSkillUI.GetCraftingOperationInfo(recipeID, {}, nil, false)
	if not baseOperationInfo then
		return nil
	end

	local result = {
		base = self:SanitizeValue(baseOperationInfo),
		baseDifficulty = baseOperationInfo.baseDifficulty,
		baseSkill = baseOperationInfo.baseSkill,
		bonusSkill = baseOperationInfo.bonusSkill,
		concentrationCost = baseOperationInfo.concentrationCost,
		guaranteedCraftingQualityID = baseOperationInfo.guaranteedCraftingQualityID,
		bonusStats = self:SanitizeValue(baseOperationInfo.bonusStats),
		qualityThresholds = self:GetQualityThresholds(schematic and schematic.maxQuality or nil, baseOperationInfo.baseDifficulty),
		requiredReagentSkillDelta = nil,
		maxQualityRequiredReagents = nil,
		withMaxQualityRequiredReagents = nil,
	}

	local maxQualityReagentInfo = self:BuildMaxQualityRequiredReagentInfo(schematic)
	if #maxQualityReagentInfo > 0 then
		local withMaxQualityReagents = C_TradeSkillUI.GetCraftingOperationInfo(recipeID, maxQualityReagentInfo, nil, false)
		if withMaxQualityReagents then
			local baseSkill = (baseOperationInfo.baseSkill or 0) + (baseOperationInfo.bonusSkill or 0)
			local maxSkill = (withMaxQualityReagents.baseSkill or 0) + (withMaxQualityReagents.bonusSkill or 0)
			result.requiredReagentSkillDelta = maxSkill - baseSkill
			result.maxQualityRequiredReagents = self:SanitizeValue(maxQualityReagentInfo)
			result.withMaxQualityRequiredReagents = self:SanitizeValue(withMaxQualityReagents)
		end
	end

	return result
end

function AuctionHelper:DescribeRecipeOutput(recipeID, _recipeInfo, schematic)
	local includeRawOutput = self._includeRecipeOutputItemData == true

	local output = {
		itemID = schematic and schematic.outputItemID or nil,
		item = self:ResolveItemDescriptor(schematic and schematic.outputItemID or nil),
		itemQuality = schematic and schematic.outputItemQuality or nil,
		quantityMin = schematic and schematic.quantityMin or nil,
		quantityMax = schematic and schematic.quantityMax or nil,
		recipeType = schematic and schematic.recipeType or nil,
		qualityVariants = {},
		raw = nil,
	}

	if includeRawOutput and C_TradeSkillUI.GetRecipeOutputItemData then
		local outputItemData = self:SafeCall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, {}, nil)
		output.raw = self:SanitizeValue(outputItemData)
	end

	local qualityItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs and self:NormalizeApiList(C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID)) or {}
	if #qualityItemIDs > 0 then
		for qualityIndex, itemID in ipairs(qualityItemIDs) do
			table.insert(output.qualityVariants, {
				qualityIndex = qualityIndex,
				itemID = itemID,
				item = self:ResolveItemDescriptor(itemID),
			})
		end
	elseif output.itemID then
		table.insert(output.qualityVariants, {
			qualityIndex = 1,
			itemID = output.itemID,
			item = self:ResolveItemDescriptor(output.itemID),
		})
	end

	return output
end

function AuctionHelper:DescribeReagentSlot(reagentSlotSchematic, slotIndex)
	local slot = {
		slotIndex = slotIndex,
		dataSlotIndex = reagentSlotSchematic.dataSlotIndex,
		reagentType = reagentSlotSchematic.reagentType,
		quantityRequired = reagentSlotSchematic.quantityRequired,
		order = reagentSlotSchematic.order,
		optional = reagentSlotSchematic.optional,
		required = reagentSlotSchematic.required,
		slotInfo = self:SanitizeValue(reagentSlotSchematic.slotInfo),
		reagentSource = reagentSlotSchematic.reagentSource,
		hiddenInCraftingForm = reagentSlotSchematic.hiddenInCraftingForm,
		reagents = {},
	}

	if type(reagentSlotSchematic.reagents) == "table" then
		for reagentIndex, reagent in ipairs(reagentSlotSchematic.reagents) do
			local quality = reagent.itemID and C_TradeSkillUI.GetItemReagentQualityByItemInfo(reagent.itemID) or nil
			table.insert(slot.reagents, {
				reagentIndex = reagentIndex,
				itemID = reagent.itemID,
				item = self:ResolveItemDescriptor(reagent.itemID),
				currencyID = reagent.currencyID,
				currency = self:ResolveCurrencyDescriptor(reagent.currencyID),
				quantity = reagent.quantity,
				quality = quality,
			})
		end
	end

	return slot
end

function AuctionHelper:CollectRecipeCategories()
	local categories = {}
	if not C_TradeSkillUI.GetCategories then
		return categories
	end

	local function collectCategoryNode(categoryID, seen)
		local nodeID = tonumber(categoryID)
		if not nodeID then
			return nil
		end
		seen = seen or {}
		if seen[nodeID] then
			return nil
		end
		seen[nodeID] = true

		local info = C_TradeSkillUI.GetCategoryInfo and C_TradeSkillUI.GetCategoryInfo(nodeID) or nil
		local childIDs = C_TradeSkillUI.GetSubCategories and self:NormalizeApiList(C_TradeSkillUI.GetSubCategories(nodeID)) or {}
		local children = {}
		for _, childID in ipairs(childIDs) do
			local childNode = collectCategoryNode(childID, seen)
			if childNode then
				children[#children + 1] = childNode
			end
		end
		seen[nodeID] = nil

		return {
			categoryID = nodeID,
			info = self:SanitizeValue(info),
			subCategoryIDs = self:SanitizeValue(childIDs) or {},
			subCategories = children,
		}
	end

	local categoryIDs = self:NormalizeApiList(C_TradeSkillUI.GetCategories())
	for _, categoryID in ipairs(categoryIDs) do
		local node = collectCategoryNode(categoryID, {})
		if node then
			table.insert(categories, node)
		end
	end
	return categories
end

function AuctionHelper:PatchAggregateInventorySummaryForCharacter(characterKey, characterData)
	self:InitDB()
	local aggregate = self.db and self.db.aggregate
	if type(aggregate) ~= "table" or type(aggregate.characterKeys) ~= "table" or type(aggregate.inventoryByCharacter) ~= "table" then
		return false
	end
	characterKey = tostring(characterKey or "")
	if characterKey == "" then
		return false
	end
	local found = false
	for i = 1, #aggregate.characterKeys do
		if aggregate.characterKeys[i] == characterKey then
			found = true
			break
		end
	end
	if not found then
		table.insert(aggregate.characterKeys, characterKey)
		table.sort(aggregate.characterKeys)
	end
	local inv = characterData and characterData.inventorySnapshot
	if inv then
		aggregate.inventoryByCharacter[characterKey] = {
			capturedAt = inv.capturedAt,
			itemTypesTracked = inv.itemTypesTracked,
			itemTypesWithStock = inv.itemTypesWithStock,
			totalQuantity = inv.totalQuantity,
		}
	else
		aggregate.inventoryByCharacter[characterKey] = nil
	end
	aggregate.updatedAt = time()
	return true
end

function AuctionHelper:BuildAggregate()
	local aggregate = {
		updatedAt = time(),
		characterKeys = {},
		professions = {},
		recipes = {},
		inventoryByCharacter = {},
	}

	for characterKey, characterData in pairs(self.db.characters or {}) do
		table.insert(aggregate.characterKeys, characterKey)

		for _, professionData in pairs(characterData.professions or {}) do
			local skillLineID = tostring(professionData.skillLineID or "unknown")
			local professionEntry = aggregate.professions[skillLineID]
			if not professionEntry then
				professionEntry = {
					skillLineID = professionData.skillLineID,
					name = professionData.professionName,
					currentLevelName = professionData.currentLevelName,
					characterStates = {},
					recipeIDs = {},
				}
				aggregate.professions[skillLineID] = professionEntry
			end

			professionEntry.characterStates[characterKey] = {
				skillLevel = professionData.skillLevel,
				maxSkillLevel = professionData.maxSkillLevel,
				bonusSkill = professionData.bonusSkill,
				recipeCount = professionData.recipeCount,
				lastScan = characterData.scanFinishedAt,
			}

			for recipeID, recipeData in pairs(professionData.recipes or {}) do
				professionEntry.recipeIDs[recipeID] = true

				local aggregateRecipe = aggregate.recipes[recipeID]
				if not aggregateRecipe then
					aggregateRecipe = {
						skillLineID = professionData.skillLineID,
						profession = professionData.professionName,
						characterStates = {},
						products = {},
					}
					aggregate.recipes[recipeID] = aggregateRecipe
				end

				local info = self:RecipeDataInfo(recipeData)
				local learned = recipeData.learned
				if learned == nil and info then
					learned = info.learned == true
				end
				local relDiff = recipeData.relativeDifficulty
				if relDiff == nil and info then
					relDiff = info.relativeDifficulty
				end

				aggregateRecipe.characterStates[characterKey] = {
					learned = learned,
					relativeDifficulty = relDiff,
					currentLevelName = professionData.currentLevelName,
				}

				local outs = recipeData.outputs
				if outs then
					local primary = self:RecipeOutputsPrimaryItemId(outs)
					if primary then
						aggregateRecipe.products[tostring(primary)] = true
					end
					for _, variant in ipairs(outs.qualityVariants or {}) do
						if variant.itemID then
							aggregateRecipe.products[tostring(variant.itemID)] = true
						end
					end
				end
			end
		end

		local inv = characterData.inventorySnapshot
		if inv then
			aggregate.inventoryByCharacter[characterKey] = {
				capturedAt = inv.capturedAt,
				itemTypesTracked = inv.itemTypesTracked,
				itemTypesWithStock = inv.itemTypesWithStock,
				totalQuantity = inv.totalQuantity,
			}
		end
	end

	table.sort(aggregate.characterKeys)

	for _, professionEntry in pairs(aggregate.professions) do
		local recipeIDs = {}
		for recipeID in pairs(professionEntry.recipeIDs) do
			table.insert(recipeIDs, tonumber(recipeID) or recipeID)
		end
		table.sort(recipeIDs)
		professionEntry.recipeIDs = recipeIDs
	end

	for _, aggregateRecipe in pairs(aggregate.recipes) do
		local list = {}
		local src = aggregateRecipe.products or aggregateRecipe.outputItemIDs
		if type(src) == "table" then
			if #src > 0 then
				for _, id in ipairs(src) do
					table.insert(list, tonumber(id) or id)
				end
			else
				for itemID in pairs(src) do
					table.insert(list, tonumber(itemID) or itemID)
				end
			end
		end
		table.sort(list)
		aggregateRecipe.products = list
		aggregateRecipe.outputItemIDs = nil
	end

	self.db.aggregate = aggregate

	local st = self:GetState()
	st.builtAggregateRevision = st.dataRevision or 0
end
