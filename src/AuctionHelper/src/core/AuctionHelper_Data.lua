local addonName, AuctionHelper = ...

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

function AuctionHelper:SkillLineHasSpecializationConfig(skillLineID)
	skillLineID = tonumber(skillLineID)
	if not skillLineID or skillLineID <= 0 or not C_ProfSpecs or not C_ProfSpecs.GetConfigIDForSkillLine then
		return false
	end
	local configID = C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)
	return configID and configID > 0
end

--- Expansion-tier skill lines from recipe category headers (e.g. Midnight Mining = 2916, not base 186).
function AuctionHelper:ExtractExpansionSkillLineIDsFromCategories(categories, baseSkillLineID)
	baseSkillLineID = tonumber(baseSkillLineID)
	local found = {}
	local function walk(nodes)
		for _, node in ipairs(nodes or {}) do
			local info = node.info
			if type(info) == "table" then
				local sid = tonumber(info.skillLineID)
				if sid and sid > 0 and sid ~= baseSkillLineID and info.hasProgressBar then
					found[sid] = info.name or true
				end
			end
			walk(node.subCategories)
		end
	end
	walk(categories)
	return found
end

--- Resolve expansion variant skill line IDs that own a C_ProfSpecs config for this base profession.
function AuctionHelper:ResolveProfessionSpecSkillLineIDs(baseSkillLineID, childInfo, categories)
	baseSkillLineID = tonumber(baseSkillLineID)
	if not baseSkillLineID or baseSkillLineID <= 0 then
		return {}
	end

	local ordered = {}
	local seen = {}
	local function add(skillLineID, source)
		skillLineID = tonumber(skillLineID)
		if not skillLineID or skillLineID <= 0 or seen[skillLineID] then
			return
		end
		if not self:SkillLineHasSpecializationConfig(skillLineID) then
			return
		end
		seen[skillLineID] = true
		table.insert(ordered, skillLineID)
		self:DebugLog("SCAN", "spec skill line candidate", {
			string.format("skillLineID=%s source=%s baseSkillLineID=%s", tostring(skillLineID), tostring(source), tostring(baseSkillLineID)),
		})
	end

	if type(childInfo) == "table" then
		local childID = tonumber(childInfo.professionID or childInfo.skillLineID or childInfo.profession)
		if childID and childID > 0 and childID ~= baseSkillLineID then
			add(childID, "childProfessionInfo")
		end
	end

	for sid in pairs(self:ExtractExpansionSkillLineIDsFromCategories(categories, baseSkillLineID)) do
		add(sid, "category")
	end

	if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
		for _, variantID in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines()) do
			variantID = tonumber(variantID)
			if variantID and variantID ~= baseSkillLineID then
				local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(variantID)
				if info and tonumber(info.parentProfessionID) == baseSkillLineID then
					add(variantID, "GetAllProfessionTradeSkillLines")
				end
			end
		end
	end

	table.sort(ordered)
	return ordered
end

function AuctionHelper:PickPrimarySpecializationSkillLineID(candidates, currentLevelName, childInfo)
	if type(candidates) ~= "table" or #candidates == 0 then
		return nil
	end

	if type(childInfo) == "table" then
		local childID = tonumber(childInfo.professionID or childInfo.skillLineID or childInfo.profession)
		if childID and childID > 0 then
			for _, sid in ipairs(candidates) do
				if sid == childID then
					return childID
				end
			end
		end
	end

	currentLevelName = type(currentLevelName) == "string" and string.lower(currentLevelName) or nil
	if currentLevelName and currentLevelName ~= "" and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
		for _, sid in ipairs(candidates) do
			local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(sid)
			local variantName = info and info.professionName
			if type(variantName) == "string" and string.lower(variantName) == currentLevelName then
				return sid
			end
		end
	end

	return candidates[1]
end

function AuctionHelper:ExtractPerkIDFromApiValue(perkValue)
	if type(perkValue) == "table" then
		return tonumber(perkValue.perkID)
	end
	return tonumber(perkValue)
end

function AuctionHelper:ResolveSpecEntryName(definitionInfo, pathDescription)
	if type(definitionInfo) == "table" then
		local name = definitionInfo.overrideName
		if name and tostring(name) ~= "" then
			return tostring(name)
		end
	end
	if type(pathDescription) == "string" and pathDescription ~= "" then
		local firstLine = pathDescription:match("^(.-)|n") or pathDescription
		firstLine = firstLine:match("^(.-)|n") or firstLine
		if firstLine and firstLine ~= "" then
			return firstLine
		end
	end
	return nil
end

function AuctionHelper:ResolveSpecEntryDescription(definitionInfo, perkDescription, pathDescription)
	if type(perkDescription) == "string" and perkDescription ~= "" then
		return perkDescription
	end
	if type(definitionInfo) == "table" then
		local desc = definitionInfo.overrideDescription
		if desc and tostring(desc) ~= "" then
			return tostring(desc)
		end
	end
	if type(pathDescription) == "string" and pathDescription ~= "" then
		return pathDescription
	end
	return nil
end

function AuctionHelper:ClassifySpecNodeKind(nodeInfo)
	local maxRanks = tonumber(nodeInfo and (nodeInfo.maxRanks or nodeInfo.totalMaxRanks)) or 1
	return maxRanks > 1 and "path" or "milestone"
end

function AuctionHelper:FinalizeSpecializationTabGraph(tab)
	if type(tab) ~= "table" then
		return tab
	end

	local rawNodes = tab.nodes or {}
	local pathByID = {}
	local milestoneByID = {}
	local paths = {}
	local milestones = {}
	local edges = {}

	for _, nodeRecord in ipairs(rawNodes) do
		if type(nodeRecord) == "table" then
			if nodeRecord.nodeKind == "path" then
				pathByID[nodeRecord.nodeID] = nodeRecord
				paths[#paths + 1] = nodeRecord
			elseif nodeRecord.nodeKind == "milestone" then
				nodeRecord.childPathIDs = nil
				milestoneByID[nodeRecord.nodeID] = nodeRecord
				milestones[#milestones + 1] = nodeRecord
			end
		end
	end

	for _, pathRecord in ipairs(paths) do
		local childPathIDs = {}
		for _, childID in ipairs(pathRecord.childPathIDs or {}) do
			childID = tonumber(childID)
			if childID and milestoneByID[childID] then
				local milestone = milestoneByID[childID]
				milestone.parentPathID = pathRecord.nodeID
				if not milestone.parentPathName and pathRecord.nodeName then
					milestone.parentPathName = pathRecord.nodeName
				end
			elseif childID and pathByID[childID] then
				childPathIDs[#childPathIDs + 1] = childID
				edges[#edges + 1] = {
					fromPathID = pathRecord.nodeID,
					toPathID = childID,
					kind = "path",
				}
			end
		end
		pathRecord.childPathIDs = #childPathIDs > 0 and childPathIDs or nil
	end

	table.sort(paths, function(a, b) return (a.nodeID or 0) < (b.nodeID or 0) end)
	table.sort(milestones, function(a, b)
		local pa = a.parentPathID or 0
		local pb = b.parentPathID or 0
		if pa ~= pb then
			return pa < pb
		end
		return (a.unlockRank or 0) < (b.unlockRank or 0)
	end)
	table.sort(edges, function(a, b)
		if a.fromPathID ~= b.fromPathID then
			return (a.fromPathID or 0) < (b.fromPathID or 0)
		end
		return (a.toPathID or 0) < (b.toPathID or 0)
	end)

	tab.paths = paths
	tab.milestones = milestones
	tab.edges = edges
	tab.nodes = nil
	return tab
end

-- Specialization API functions differ by client: a missing one reads as nil; pcallProfSpecs also catches errors.
local function callIfPresent(api, name, ...)
	local fn = api and api[name]
	return fn and fn(...) or nil
end

local function pcallProfSpecs(self, name, ...)
	return self:SafeCall(C_ProfSpecs[name], ...) or nil
end

function AuctionHelper:CollectSpecializationEntry(configID, entryID, perkValue)
	local entryInfo = callIfPresent(C_Traits, "GetEntryInfo", configID, entryID)
	local perkID = self:ExtractPerkIDFromApiValue(perkValue)
	return {
		entryID = entryID,
		perkID = perkID,
		entryInfo = self:SanitizeValue(entryInfo),
		definitionInfo = self:SanitizeValue(entryInfo and callIfPresent(C_Traits, "GetDefinitionInfo", entryInfo.definitionID) or nil),
		perkDescription = perkID and pcallProfSpecs(self, "GetDescriptionForPerk", perkID) or nil,
		unlockRank = perkID and pcallProfSpecs(self, "GetUnlockRankForPerk", perkID) or pcallProfSpecs(self, "GetUnlockRankForPerk", entryID),
	}
end

--- Entries in node order; the first entry with a name or description names the node.
function AuctionHelper:CollectSpecializationNodeEntries(configID, nodeRecord, entryIDs)
	local pathDescription = nodeRecord.pathDescription
	local perkIDsForPath = pcallProfSpecs(self, "GetPerksForPath", nodeRecord.nodeID)
	for entryIndex, entryID in ipairs(type(entryIDs) == "table" and entryIDs or {}) do
		local entry = self:CollectSpecializationEntry(configID, entryID, perkIDsForPath and perkIDsForPath[entryIndex] or nil)
		table.insert(nodeRecord.entries, entry)
		nodeRecord.nodeName = nodeRecord.nodeName or self:ResolveSpecEntryName(entry.definitionInfo, pathDescription)
		nodeRecord.nodeDescription = nodeRecord.nodeDescription
			or self:ResolveSpecEntryDescription(entry.definitionInfo, entry.perkDescription, pathDescription)
	end
end

function AuctionHelper:CollectSpecializationNode(configID, nodeID)
	local nodeInfo = callIfPresent(C_Traits, "GetNodeInfo", configID, nodeID)
	local pathDescription = pcallProfSpecs(self, "GetDescriptionForPath", nodeID)
	local nodeKind = self:ClassifySpecNodeKind(nodeInfo)
	local nodeRecord = {
		nodeID = nodeID,
		nodeKind = nodeKind,
		childPathIDs = nodeKind == "path" and self:SanitizeValue(pcallProfSpecs(self, "GetChildrenForPath", nodeID)) or nil,
		nodeInfo = self:SanitizeValue(nodeInfo),
		pathDescription = pathDescription,
		unlockRank = pcallProfSpecs(self, "GetUnlockRankForPerk", nodeID),
		entries = {},
	}
	self:CollectSpecializationNodeEntries(configID, nodeRecord, nodeInfo and nodeInfo.entryIDs or nil)
	if nodeKind == "milestone" then
		nodeRecord.milestoneRank = nodeRecord.unlockRank
	end
	return nodeRecord
end

function AuctionHelper:CollectSpecializationTab(configID, treeID)
	local tab = {
		treeID = treeID,
		rootPathID = pcallProfSpecs(self, "GetRootPathForTab", treeID),
		tabInfo = self:SanitizeValue(callIfPresent(C_ProfSpecs, "GetTabInfo", treeID)),
		state = callIfPresent(C_ProfSpecs, "GetStateForTab", treeID, configID),
		nodes = {},
	}
	for _, nodeID in ipairs(callIfPresent(C_Traits, "GetTreeNodes", treeID) or {}) do
		table.insert(tab.nodes, self:CollectSpecializationNode(configID, nodeID))
	end
	return self:FinalizeSpecializationTabGraph(tab)
end

function AuctionHelper:CollectSpecializationTreeForSkillLine(skillLineID)
	skillLineID = tonumber(skillLineID)
	if not self:SkillLineHasSpecializationConfig(skillLineID) then
		return nil
	end
	local configID = C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)
	local variantInfo = callIfPresent(C_TradeSkillUI, "GetProfessionInfoBySkillLineID", skillLineID) or {}
	local configInfo = callIfPresent(C_Traits, "GetConfigInfo", configID)
	local treeIDs = configInfo and self:ShallowArrayCopy(configInfo.treeIDs) or {}
	local result = {
		configID = configID,
		skillLineID = skillLineID,
		tierName = variantInfo.professionName,
		expansionID = self.ResolveSpecCatalogForTierSkillLine and self:ResolveSpecCatalogForTierSkillLine(skillLineID) or nil,
		parentProfessionID = variantInfo.parentProfessionID,
		configInfo = self:SanitizeValue(configInfo),
		treeIDs = treeIDs,
		tabs = {},
		unspentKnowledge = self:SanitizeValue(callIfPresent(C_ProfSpecs, "GetCurrencyInfoForSkillLine", skillLineID)),
	}
	for _, treeID in ipairs(treeIDs) do
		table.insert(result.tabs, self:CollectSpecializationTab(configID, treeID))
	end
	return result
end

--- Full specialization dump keyed by expansion variant skill line (tostring(skillLineID)).
function AuctionHelper:CollectSpecializationTreesForProfession(baseSkillLineID, childInfo, categories, currentLevelName)
	local candidates = self:ResolveProfessionSpecSkillLineIDs(baseSkillLineID, childInfo, categories)
	if #candidates == 0 then
		self:DebugLog("SCAN", "CollectSpecializationTreesForProfession no candidates", {
			string.format("baseSkillLineID=%s currentLevelName=%s", tostring(baseSkillLineID), tostring(currentLevelName)),
		})
		return nil
	end

	local bySkillLineID = {}
	for _, sid in ipairs(candidates) do
		local tree = self:CollectSpecializationTreeForSkillLine(sid)
		if tree then
			bySkillLineID[tostring(sid)] = tree
		end
	end

	if not next(bySkillLineID) then
		self:DebugLog("SCAN", "CollectSpecializationTreesForProfession no trees captured", {
			string.format("baseSkillLineID=%s candidateCount=%d", tostring(baseSkillLineID), #candidates),
		})
		return nil
	end

	local primarySkillLineID = self:PickPrimarySpecializationSkillLineID(candidates, currentLevelName, childInfo)
	local primary = primarySkillLineID and bySkillLineID[tostring(primarySkillLineID)] or nil
	if not primary then
		local _, tree = next(bySkillLineID)
		primary = tree
		primarySkillLineID = tree.skillLineID
	end

	self:DebugLog("SCAN", "CollectSpecializationTreesForProfession captured", {
		string.format("baseSkillLineID=%s tierCount=%d primarySkillLineID=%s",
			tostring(baseSkillLineID), self:TableCount(bySkillLineID), tostring(primarySkillLineID)),
	})

	return {
		primarySkillLineID = primarySkillLineID,
		primary = primary,
		bySkillLineID = bySkillLineID,
	}
end

function AuctionHelper:CollectClassicRecipeReagentSlots(recipeSpellID)
	local slots = {}
	local makeSlot = self.ForeverLogic and self.ForeverLogic.MakeClassicReagentSlot
	local function pushSlot(slotIndex, itemID, quantity)
		local slot = makeSlot and makeSlot(slotIndex, itemID, quantity) or nil
		if not slot then
			itemID = tonumber(itemID)
			quantity = tonumber(quantity) or 0
			if not itemID or itemID <= 0 or quantity <= 0 then
				return
			end
			slot = {
				slotIndex = slotIndex,
				dataSlotIndex = slotIndex,
				reagentType = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1,
				quantityRequired = quantity,
				required = true,
				optional = false,
				reagents = {
					{
						reagentIndex = 1,
						itemID = itemID,
						quantity = quantity,
					},
				},
			}
		end
		if slot.reagents and slot.reagents[1] and self.ResolveItemDescriptor then
			slot.reagents[1].item = self:ResolveItemDescriptor(slot.reagents[1].itemID)
		end
		if Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic then
			slot.reagentType = Enum.CraftingReagentType.Basic
		end
		slots[#slots + 1] = slot
	end

	if C_TradeSkillUI and C_TradeSkillUI.GetRecipeNumReagents and C_TradeSkillUI.GetRecipeReagentInfo then
		local numReagents = tonumber(C_TradeSkillUI.GetRecipeNumReagents(recipeSpellID)) or 0
		for i = 1, numReagents do
			local _, _, reagentCount, _, itemID = C_TradeSkillUI.GetRecipeReagentInfo(recipeSpellID, i)
			if not itemID and C_TradeSkillUI.GetRecipeReagentItemLink then
				local link = C_TradeSkillUI.GetRecipeReagentItemLink(recipeSpellID, i)
				if type(link) == "string" then
					itemID = tonumber(link:match("item:(%d+)"))
				end
			end
			pushSlot(i, itemID, reagentCount)
		end
		if #slots > 0 then
			return slots
		end
	end

	-- Classic TradeSkillFrame path: recipe index on the open profession window.
	if type(GetTradeSkillNumReagents) == "function" and type(GetTradeSkillReagentInfo) == "function" then
		local skillIndex = nil
		if type(GetTradeSkillInfo) == "function" and type(GetNumTradeSkills) == "function" then
			for i = 1, GetNumTradeSkills() do
				local skillName, skillType = GetTradeSkillInfo(i)
				if skillType ~= "header" then
					local link = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i) or nil
					local spellFromLink = type(link) == "string" and tonumber(link:match("enchant:(%d+)")) or nil
					local itemFromLink = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
					if spellFromLink == recipeSpellID or itemFromLink == recipeSpellID then
						skillIndex = i
						break
					end
					-- Some clients expose the recipe spell via GetTradeSkillRecipeLink / spell name only.
					if not skillIndex and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
						local info = C_TradeSkillUI.GetRecipeInfo(recipeSpellID)
						if info and info.name and skillName == info.name then
							skillIndex = i
							break
						end
					end
				end
			end
		end
		if skillIndex then
			local numReagents = tonumber(GetTradeSkillNumReagents(skillIndex)) or 0
			for i = 1, numReagents do
				local _, _, reagentCount = GetTradeSkillReagentInfo(skillIndex, i)
				local itemID = nil
				if type(GetTradeSkillReagentItemLink) == "function" then
					local link = GetTradeSkillReagentItemLink(skillIndex, i)
					if type(link) == "string" then
						itemID = tonumber(link:match("item:(%d+)"))
					end
				end
				pushSlot(i, itemID, reagentCount)
			end
		end
	end

	return slots
end

function AuctionHelper:CollectRecipeData(recipeSpellID)
	recipeSpellID = tonumber(recipeSpellID)
	if not recipeSpellID then
		return nil
	end
	local recipeInfo = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeSpellID) or nil
	local schematic = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, false) or nil
	if not recipeInfo then
		return nil
	end

	local recipeData = {
		recipeSpellID = tonumber(recipeInfo.recipeID) or recipeSpellID,
		skillLineAbilityID = tonumber(recipeInfo.skillLineAbilityID) or tonumber(recipeInfo.recipeID) or recipeSpellID,
		info = self:SanitizeValue(recipeInfo),
		schematic = self:SanitizeValue(schematic),
		outputs = self:DescribeRecipeOutput(recipeSpellID, recipeInfo, schematic),
		slots = {},
		crafting = self:DescribeOperationInfo(recipeSpellID, schematic),
		links = {},
	}

	if schematic and type(schematic.reagentSlotSchematics) == "table" then
		for slotIndex, reagentSlotSchematic in ipairs(schematic.reagentSlotSchematics) do
			table.insert(recipeData.slots, self:DescribeReagentSlot(reagentSlotSchematic, slotIndex))
		end
	end
	-- Empty schematic (or missing reagents) → classic Forever / TradeSkill fallback.
	if #recipeData.slots == 0 then
		recipeData.slots = self:CollectClassicRecipeReagentSlots(recipeSpellID)
	end

	return recipeData
end

function AuctionHelper:BeginProfessionCollectCaches()
	self._itemDescCache = {}
	self._currencyDescCache = {}
	self._includeRecipeOutputItemData = self:GetSetting("capture.includeRecipeOutputItemData", false) == true
end

function AuctionHelper:EndProfessionCollectCaches()
	self._itemDescCache = nil
	self._currencyDescCache = nil
	self._includeRecipeOutputItemData = nil
end

--- Rebuild recipeIDs array + recipeCount from the recipes map.
function AuctionHelper:RebuildProfessionRecipeIndex(professionData)
	if not professionData then
		return
	end
	local recipes = professionData.recipes
	if type(recipes) ~= "table" then
		professionData.recipes = {}
		professionData.recipeIDs = {}
		professionData.recipeCount = 0
		return
	end
	local recipeIDsStored = {}
	for storageKey in pairs(recipes) do
		recipeIDsStored[#recipeIDsStored + 1] = tonumber(storageKey) or storageKey
	end
	table.sort(recipeIDsStored, function(a, b)
		local na, nb = tonumber(a), tonumber(b)
		if na and nb then
			return na < nb
		end
		return tostring(a) < tostring(b)
	end)
	professionData.recipeIDs = recipeIDsStored
	professionData.recipeCount = #recipeIDsStored
end

--- Insert/overwrite recipes for the given crafting spell IDs. Returns how many were written.
function AuctionHelper:CollectRecipesIntoProfessionData(professionData, recipeSpellIDs, fromIndex, toIndex)
	if not professionData then
		return 0
	end
	professionData.recipes = professionData.recipes or {}
	recipeSpellIDs = recipeSpellIDs or {}
	fromIndex = math.max(1, tonumber(fromIndex) or 1)
	toIndex = math.min(#recipeSpellIDs, tonumber(toIndex) or #recipeSpellIDs)
	local written = 0
	for i = fromIndex, toIndex do
		local recipeData = self:CollectRecipeData(recipeSpellIDs[i])
		if recipeData then
			local storageKey = self:GetRecipeStorageKey(recipeData)
			if storageKey then
				professionData.recipes[storageKey] = recipeData
				written = written + 1
			end
		end
	end
	return written
end

--- Drop stored recipes whose crafting spell id is not in the current open recipe set.
function AuctionHelper:PruneProfessionRecipesNotInSpellSet(professionData, spellIDSet)
	if not professionData or type(professionData.recipes) ~= "table" or type(spellIDSet) ~= "table" then
		return 0
	end
	local removed = 0
	for storageKey, recipeData in pairs(professionData.recipes) do
		local spellID = self:GetRecipeSpellID(recipeData)
		if not spellID or not spellIDSet[spellID] then
			professionData.recipes[storageKey] = nil
			removed = removed + 1
		end
	end
	return removed
end

function AuctionHelper:StampProfessionLiveFingerprint(professionData, fingerprintInfo)
	if not professionData then
		return
	end
	local info = fingerprintInfo
	if type(info) ~= "table" and self.BuildOpenProfessionQuickFingerprint then
		info = self:BuildOpenProfessionQuickFingerprint()
	end
	if type(info) ~= "table" then
		return
	end
	if info.fingerprint then
		professionData.liveFingerprint = info.fingerprint
		professionData.liveFingerprintAt = time()
	end
	if info.metaFingerprint then
		professionData.liveMetaFingerprint = info.metaFingerprint
	end
end

function AuctionHelper:UpdateProfessionDescriptorFields(professionData, professionDescriptor, baseInfo, childInfo)
	if not professionData or not professionDescriptor then
		return
	end
	professionData.professionIndex = professionDescriptor.professionIndex
	professionData.skillLineID = professionDescriptor.skillLineID
	professionData.professionName = professionDescriptor.professionName
	professionData.currentLevelName = professionDescriptor.currentLevelName
	professionData.skillLevel = professionDescriptor.skillLevel
	professionData.maxSkillLevel = professionDescriptor.maxSkillLevel
	professionData.bonusSkill = professionDescriptor.bonusSkill
	professionData.icon = professionDescriptor.icon
	if baseInfo ~= nil then
		professionData.baseProfessionInfo = self:SanitizeValue(baseInfo)
	end
	if childInfo ~= nil then
		professionData.childProfessionInfo = self:SanitizeValue(childInfo)
	end
end

function AuctionHelper:ApplySpecializationResultToProfessionData(professionData, specResult)
	if not professionData then
		return
	end
	professionData.specializationTree = specResult and specResult.primary or nil
	professionData.specializationTrees = specResult and specResult.bySkillLineID or nil
	professionData.primarySpecializationSkillLineID = specResult and specResult.primarySkillLineID or nil
end

--- Finalize indexes, optional catalog attach, and live fingerprint stamp.
function AuctionHelper:FinalizeProfessionDataCollect(professionData, professionDescriptor, fingerprintInfo)
	self:RebuildProfessionRecipeIndex(professionData)
	if self.AttachSpecCatalogMetadata and professionDescriptor then
		self:AttachSpecCatalogMetadata(professionData, professionDescriptor.skillLineID)
	end
	self:StampProfessionLiveFingerprint(professionData, fingerprintInfo)
	return professionData
end

function AuctionHelper:CollectCurrentProfessionData(professionDescriptor)
	self:InitDB()
	self:BeginProfessionCollectCaches()

	local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	local childInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo() or nil
	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and self:NormalizeApiList(C_TradeSkillUI.GetAllRecipeIDs()) or {}

	local categories = self:CollectRecipeCategories()
	local captureSpec = self:GetSetting("capture.captureSpecializationTree", true) ~= false
	local specResult = captureSpec and self:CollectSpecializationTreesForProfession(
		professionDescriptor.skillLineID,
		childInfo,
		categories,
		professionDescriptor.currentLevelName
	) or nil

	local professionData = {
		professionIndex = professionDescriptor.professionIndex,
		skillLineID = professionDescriptor.skillLineID,
		professionName = professionDescriptor.professionName,
		currentLevelName = professionDescriptor.currentLevelName,
		skillLevel = professionDescriptor.skillLevel,
		maxSkillLevel = professionDescriptor.maxSkillLevel,
		bonusSkill = professionDescriptor.bonusSkill,
		icon = professionDescriptor.icon,
		baseProfessionInfo = self:SanitizeValue(baseInfo),
		childProfessionInfo = self:SanitizeValue(childInfo),
		categories = categories,
		recipeIDs = {},
		recipes = {},
		specializationTree = specResult and specResult.primary or nil,
		specializationTrees = specResult and specResult.bySkillLineID or nil,
		primarySpecializationSkillLineID = specResult and specResult.primarySkillLineID or nil,
		recipeCount = 0,
	}

	self:CollectRecipesIntoProfessionData(professionData, recipeIDs, 1, #recipeIDs)
	self:EndProfessionCollectCaches()

	local fingerprintInfo = self.BuildOpenProfessionQuickFingerprint and self:BuildOpenProfessionQuickFingerprint() or nil
	return self:FinalizeProfessionDataCollect(professionData, professionDescriptor, fingerprintInfo)
end

--- Create a shell profession row (no recipes yet) for chunked / incremental live collects.
function AuctionHelper:CreateProfessionDataShell(professionDescriptor, opts)
	opts = type(opts) == "table" and opts or {}
	local baseInfo = opts.baseInfo
	if baseInfo == nil then
		baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	end
	local childInfo = opts.childInfo
	if childInfo == nil then
		childInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo() or nil
	end
	local categories = opts.categories or self:CollectRecipeCategories()
	local professionData = {
		professionIndex = professionDescriptor.professionIndex,
		skillLineID = professionDescriptor.skillLineID,
		professionName = professionDescriptor.professionName,
		currentLevelName = professionDescriptor.currentLevelName,
		skillLevel = professionDescriptor.skillLevel,
		maxSkillLevel = professionDescriptor.maxSkillLevel,
		bonusSkill = professionDescriptor.bonusSkill,
		icon = professionDescriptor.icon,
		baseProfessionInfo = self:SanitizeValue(baseInfo),
		childProfessionInfo = self:SanitizeValue(childInfo),
		categories = categories,
		recipeIDs = {},
		recipes = opts.existingRecipes or {},
		specializationTree = opts.specializationTree,
		specializationTrees = opts.specializationTrees,
		primarySpecializationSkillLineID = opts.primarySpecializationSkillLineID,
		recipeCount = 0,
		liveFingerprint = opts.liveFingerprint,
		liveMetaFingerprint = opts.liveMetaFingerprint,
		liveFingerprintAt = opts.liveFingerprintAt,
	}
	if opts.rebuildSpecs then
		local captureSpec = self:GetSetting("capture.captureSpecializationTree", true) ~= false
		local specResult = captureSpec and self:CollectSpecializationTreesForProfession(
			professionDescriptor.skillLineID,
			childInfo,
			categories,
			professionDescriptor.currentLevelName
		) or nil
		self:ApplySpecializationResultToProfessionData(professionData, specResult)
	end
	return professionData
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

--- Lightweight character record fields for partial exports (no professions / inventory blobs).
function AuctionHelper:GetCharacterExportHeader(characterData)
	if not characterData then
		return nil
	end
	return {
		meta = characterData.meta,
		addonVersion = characterData.addonVersion,
		schemaVersion = characterData.schemaVersion,
		scanStartedAt = characterData.scanStartedAt,
		scanFinishedAt = characterData.scanFinishedAt,
		lastLiveProfessionUpdate = characterData.lastLiveProfessionUpdate,
		lastLiveInventoryUpdate = characterData.lastLiveInventoryUpdate,
	}
end

--- Shallow export slice; does not mutate stored profession rows. "recipes" omits specializationTree and recipeIDs.
function AuctionHelper:ProfessionExportSliceProfession(prof, slice)
	if not prof or type(prof) ~= "table" then
		return nil
	end
	if slice == "recipes" then
		local out = {}
		for k, v in pairs(prof) do
			if k ~= "specializationTree" and k ~= "specializationTrees" and k ~= "primarySpecializationSkillLineID"
				and k ~= "recipeIDs" and k ~= "specNodeRanks" and k ~= "specNodeRanksByTier" and k ~= "specCatalog" then
				out[k] = v
			end
		end
		return out
	end
	if slice == "talents" then
		return {
			professionIndex = prof.professionIndex,
			skillLineID = prof.skillLineID,
			professionName = prof.professionName,
			currentLevelName = prof.currentLevelName,
			skillLevel = prof.skillLevel,
			maxSkillLevel = prof.maxSkillLevel,
			bonusSkill = prof.bonusSkill,
			icon = prof.icon,
			baseProfessionInfo = prof.baseProfessionInfo,
			childProfessionInfo = prof.childProfessionInfo,
			primarySpecializationSkillLineID = prof.primarySpecializationSkillLineID,
			specializationTree = prof.specializationTree,
			specializationTrees = prof.specializationTrees,
			specCatalog = prof.specCatalog,
			specNodeRanks = prof.specNodeRanks,
			specNodeRanksByTier = prof.specNodeRanksByTier,
		}
	end
	return nil
end

function AuctionHelper:MapProfessionsExportSlice(professionsMap, slice)
	local out = {}
	for sid, prof in pairs(professionsMap or {}) do
		out[sid] = self:ProfessionExportSliceProfession(prof, slice)
	end
	return out
end

function AuctionHelper:GetCompactCharacterHeader(characterData)
	local meta = characterData and characterData.meta or nil
	return {
		k = meta and meta.key or nil,
		n = meta and meta.name or nil,
		r = meta and meta.realm or nil,
		c = meta and meta.class or nil,
		f = meta and meta.faction or nil,
		l = meta and meta.level or nil,
		ss = characterData and characterData.scanStartedAt or nil,
		sf = characterData and characterData.scanFinishedAt or nil,
		lp = characterData and characterData.lastLiveProfessionUpdate or nil,
		li = characterData and characterData.lastLiveInventoryUpdate or nil,
	}
end

function AuctionHelper:BuildCompactInventorySnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return nil
	end
	local items = {}
	for itemKey, entry in pairs(snapshot.items or {}) do
		local itemID = tonumber(itemKey)
		if itemID then
			items[#items + 1] = {
				itemID,
				tonumber(entry and entry.bags) or 0,
				tonumber(entry and entry.bank) or 0,
				tonumber(entry and entry.warband) or 0,
				tonumber(entry and entry.total) or 0,
			}
		end
	end
	table.sort(items, function(a, b) return a[1] < b[1] end)
	return {
		at = snapshot.capturedAt,
		it = snapshot.itemTypesTracked,
		iw = snapshot.itemTypesWithStock,
		tq = snapshot.totalQuantity,
		items = items,
	}
end

function AuctionHelper:BuildCompactRecipeRecord(recipeID, recipeData)
	local info = self:RecipeDataInfo(recipeData) or {}
	local exportID = self:GetRecipeExportID(recipeData) or tonumber(recipeID) or recipeID
	local outputs = recipeData and recipeData.outputs or nil
	local variants = {}
	for _, variant in ipairs(outputs and outputs.qualityVariants or {}) do
		local itemID = tonumber(variant and variant.itemID)
		if itemID then
			variants[#variants + 1] = itemID
		end
	end
	local slots = {}
	for _, slot in ipairs(self:RecipeDataSlots(recipeData) or {}) do
		local reagents = {}
		for _, reagent in ipairs(slot.reagents or {}) do
			local itemID = tonumber(reagent and reagent.itemID)
			if itemID then
				reagents[#reagents + 1] = itemID
			end
		end
		table.sort(reagents)
		slots[#slots + 1] = {
			i = tonumber(slot.slotIndex) or 0,
			q = tonumber(slot.quantityRequired) or 0,
			o = slot.optional and 1 or 0,
			r = reagents,
		}
	end
	return {
		i = tonumber(exportID) or exportID,
		rs = self:GetRecipeSpellID(recipeData),
		l = info.learned == false and 0 or 1,
		rd = info.relativeDifficulty,
		cid = info.categoryID,
		o = self:RecipeOutputsPrimaryItemId(outputs),
		ov = variants,
		s = slots,
	}
end

function AuctionHelper:BuildCompactProfessionRecord(professionData)
	if type(professionData) ~= "table" then
		return nil
	end
	local recipes = {}
	for recipeID, recipeData in pairs(professionData.recipes or {}) do
		recipes[#recipes + 1] = self:BuildCompactRecipeRecord(recipeID, recipeData)
	end
	table.sort(recipes, function(a, b) return tostring(a.i) < tostring(b.i) end)
	return {
		sid = professionData.skillLineID,
		n = professionData.professionName,
		sl = professionData.skillLevel,
		ml = professionData.maxSkillLevel,
		bs = professionData.bonusSkill,
		rc = professionData.recipeCount,
		recipes = recipes,
	}
end

function AuctionHelper:BuildCompactProfessionsExport(characterData)
	local professions = {}
	for _, professionData in pairs(characterData and characterData.professions or {}) do
		local row = self:BuildCompactProfessionRecord(professionData)
		if row then
			professions[#professions + 1] = row
		end
	end
	table.sort(professions, function(a, b)
		return self:SortByNameThenId({ professionName = a.n, skillLineID = a.sid }, { professionName = b.n, skillLineID = b.sid })
	end)
	return professions
end

function AuctionHelper:BuildCompactAuctionSnapshotExport()
	if not self.InitAuctionDB then
		return nil, "Auction data module is not loaded."
	end
	local auction = self:InitAuctionDB()
	local out = { c = {}, i = {} }
	for storageKey, entry in pairs(auction.snapshot and auction.snapshot.commodities or {}) do
		local row = self:BuildCompactAuctionSnapshotEntry(entry)
		if row then
			out.c[#out.c + 1] = { storageKey, row.t, row.p, row.s, row.q or 0 }
		end
	end
	for storageKey, entry in pairs(auction.snapshot and auction.snapshot.items or {}) do
		local row = self:BuildCompactAuctionSnapshotEntry(entry)
		if row then
			out.i[#out.i + 1] = { storageKey, row.t, row.p, row.s, row.q or 0 }
		end
	end
	table.sort(out.c, function(a, b) return a[1] < b[1] end)
	table.sort(out.i, function(a, b) return a[1] < b[1] end)
	return out
end

function AuctionHelper:BuildCompactAuctionHistoryExport()
	if not self.InitAuctionDB then
		return nil, "Auction data module is not loaded."
	end
	local auction = self:InitAuctionDB()
	local rows = {}
	for storageKey, historyByHour in pairs(auction.history and auction.history.hourly or {}) do
		local buckets = {}
		for hourKey, bucket in pairs(historyByHour or {}) do
			buckets[#buckets + 1] = {
				tonumber(hourKey) or 0,
				tonumber(bucket and bucket.n) or 0,
				tonumber(bucket and bucket.q) or 0,
				tonumber(bucket and bucket.w) or 0,
				tonumber(bucket and bucket.l) or 0,
				tonumber(bucket and bucket.m) or 0,
				tonumber(bucket and bucket.x) or 0,
				tonumber(bucket and bucket.t) or 0,
			}
		end
		table.sort(buckets, function(a, b) return a[1] < b[1] end)
		rows[#rows + 1] = { storageKey, buckets }
	end
	table.sort(rows, function(a, b) return a[1] < b[1] end)
	return rows
end

function AuctionHelper:BuildCompactCraftingCostsExport()
	if not self.BuildCraftOpportunityRows then
		return nil, "Professions data module is not loaded."
	end
	local rows = self:BuildCraftOpportunityRows({ forceSync = true }) or {}
	local out = {}
	for _, row in ipairs(rows) do
		out[#out + 1] = {
			tonumber(row.recipeID) or row.recipeID,
			tonumber(row.outputItemID) or nil,
			row.recipeName,
			row.outputName,
			tonumber(row.skillLineID) or nil,
			row.professionName,
			row.bestCharacterKey,
			tonumber(row.matCost),
			tonumber(row.saleNet),
			tonumber(row.profit),
			tonumber(row.roi),
			tonumber(row.outputQty),
			tonumber(row.qualityIndex),
			row.confidence,
			row.badges,
		}
	end
	return out
end

local UNKNOWN_PROFESSION = "Unknown profession identifier. Use a skill line ID or exact profession name."

local function exportMeta(self, scope, extra)
	local meta = { scope = scope, generatedAt = time(), addonVersion = self.VERSION, schemaVersion = self.SCHEMA_VERSION }
	for k, v in pairs(extra or {}) do
		meta[k] = v
	end
	return meta
end

local function rebuildAggregateIfNeeded(self)
	if self:AggregateNeedsRebuild() then
		self:BuildAggregate()
	end
end

local function exportSpecCatalog(self)
	if not self.BuildSpecCatalogExport then
		return nil, "Spec catalog module not loaded. Enable AuctionHelper Professions."
	end
	local expansionID = self.EXPANSION_ID_MIDNIGHT or 11
	local catalog = self:BuildSpecCatalogExport(expansionID)
	if not catalog then
		return nil, "No bundled spec catalog for expansion " .. tostring(expansionID) .. "."
	end
	local meta = exportMeta(self, "spec_catalog", { expansionID = expansionID, catalogVersion = catalog.catalogVersion })
	return { meta = meta, specCatalog = catalog }
end

-- Scopes that do not need this character's scan data: scope -> builder(self).
local ACCOUNT_EXPORTS = {
	account = function(self)
		rebuildAggregateIfNeeded(self)
		return { meta = exportMeta(self, "account"), characters = self.db.characters, aggregate = self.db.aggregate }
	end,
	account_summary = function(self)
		rebuildAggregateIfNeeded(self)
		return { meta = exportMeta(self, "account_summary"), aggregate = self.db.aggregate }
	end,
	auction_snapshot = function(self)
		local snapshot, err = self:BuildCompactAuctionSnapshotExport()
		if not snapshot then
			return nil, err
		end
		local meta = exportMeta(self, "auction_snapshot", { module = "auction" })
		return { meta = meta, keys = { "storageKey", "seenAt", "price", "source", "sampleSize" }, snapshot = snapshot }
	end,
	auction_history = function(self)
		local historyRows, err = self:BuildCompactAuctionHistoryExport()
		if not historyRows then
			return nil, err
		end
		local meta = exportMeta(self, "auction_history", { module = "auction" })
		local keys = { "hourTs", "obsCount", "weightedQty", "weightedSum", "last", "min", "max", "lastSeenAt" }
		return { meta = meta, keys = keys, history = historyRows }
	end,
	spec_catalog = exportSpecCatalog,
	spec_catalog_midnight = exportSpecCatalog,
}

-- ctx = { scope, characterKey, data = character record, identifier }
local function characterMeta(self, ctx, scope, extra)
	extra = extra or {}
	extra.characterKey = ctx.characterKey
	return exportMeta(self, scope or ctx.scope, extra)
end

local function professionsSliceExport(slice)
	return function(self, ctx)
		local meta = characterMeta(self, ctx)
		local character = self:GetCharacterExportHeader(ctx.data)
		return { meta = meta, character = character, professions = self:MapProfessionsExportSlice(ctx.data.professions or {}, slice) }
	end
end

local function findExportProfession(self, ctx)
	local professions = {}
	for _, professionData in pairs(ctx.data.professions or {}) do
		table.insert(professions, professionData)
	end
	return self:FindProfessionByIdentifier(professions, ctx.identifier)
end

local function exportProfessionSlice(self, ctx)
	local profession = findExportProfession(self, ctx)
	if not profession then
		return nil, UNKNOWN_PROFESSION
	end
	local slice = ctx.scope == "profession_recipes" and "recipes" or "talents"
	local meta = characterMeta(self, ctx, nil, { professionIdentifier = ctx.identifier })
	return { meta = meta, character = ctx.data.meta, profession = self:ProfessionExportSliceProfession(profession, slice) }
end

-- Scopes built from this character's scan data: scope -> builder(self, ctx).
local CHARACTER_EXPORTS = {
	professions = function(self, ctx)
		local meta = characterMeta(self, ctx)
		return { meta = meta, character = self:GetCharacterExportHeader(ctx.data), professions = ctx.data.professions or {} }
	end,
	professions_recipes = professionsSliceExport("recipes"),
	professions_talents = professionsSliceExport("talents"),
	inventory = function(self, ctx)
		local meta = characterMeta(self, ctx)
		return { meta = meta, character = self:GetCharacterExportHeader(ctx.data), inventorySnapshot = ctx.data.inventorySnapshot }
	end,
	inventory_compact = function(self, ctx)
		local meta = characterMeta(self, ctx, nil, { module = "inventory" })
		local character = self:GetCompactCharacterHeader(ctx.data)
		local inventory = self:BuildCompactInventorySnapshot(ctx.data.inventorySnapshot)
		return { meta = meta, keys = { "itemID", "bags", "bank", "warband", "total" }, character = character, inventory = inventory }
	end,
	professions_compact = function(self, ctx)
		local meta = characterMeta(self, ctx, nil, { module = "professions" })
		local keys = {
			profession = { "sid", "name", "skillLevel", "maxSkillLevel", "bonusSkill", "recipeCount", "recipes" },
			recipe = { "recipeID", "learned", "relativeDifficulty", "categoryID", "output", "outputVariants", "slots" },
			slot = { "slotIndex", "quantity", "optional", "reagents" },
		}
		local character = self:GetCompactCharacterHeader(ctx.data)
		return { meta = meta, keys = keys, character = character, professions = self:BuildCompactProfessionsExport(ctx.data) }
	end,
	crafting_costs = function(self, ctx)
		local rows, err = self:BuildCompactCraftingCostsExport()
		if not rows then
			return nil, err
		end
		local keys = {
			"recipeID", "outputItemID", "recipeName", "outputName", "skillLineID", "professionName", "bestCharacterKey",
			"matCost", "saleNet", "profit", "roi", "outputQty", "qualityIndex", "confidence", "badges",
		}
		return { meta = characterMeta(self, ctx, nil, { module = "professions" }), keys = keys, rows = rows }
	end,
	character_meta = function(self, ctx)
		return { meta = characterMeta(self, ctx), character = self:GetCharacterExportHeader(ctx.data) }
	end,
	profession = function(self, ctx)
		local profession = findExportProfession(self, ctx)
		if not profession then
			return nil, UNKNOWN_PROFESSION
		end
		local meta = characterMeta(self, ctx, nil, { professionIdentifier = ctx.identifier })
		return { meta = meta, character = ctx.data.meta, profession = profession }
	end,
	profession_recipes = exportProfessionSlice,
	profession_talents = exportProfessionSlice,
}

local function exportCharacter(self, ctx)
	return { meta = characterMeta(self, ctx, "character"), character = ctx.data }
end

function AuctionHelper:GetExportData(scope, identifier)
	self:InitDB()
	local characterKey = self:GetCharacterKey()
	scope = scope or "character"
	local accountExport = ACCOUNT_EXPORTS[scope]
	if accountExport then
		return accountExport(self)
	end
	local characterData = self.db.characters[characterKey]
	if not characterData then
		return nil, "No scan data stored for this character yet. Run /auctionhelper scan first."
	end
	local build = CHARACTER_EXPORTS[scope] or exportCharacter
	return build(self, { scope = scope, characterKey = characterKey, data = characterData, identifier = identifier })
end

function AuctionHelper:BuildPlainLuaExportPayload(exportData)
	local logic = self.ForeverLogic
	if logic and logic.BuildPlainLuaExportPayload then
		return logic.BuildPlainLuaExportPayload(exportData)
	end
	return nil, "ForeverLogic unavailable"
end

function AuctionHelper:BuildCompactExportPayload(exportData)
	if type(exportData) ~= "table" then
		return nil, "invalid export data"
	end
	local meta = exportData.meta or {}
	meta.module = tostring(meta.module or meta.scope or "core")
	meta.generatedBy = "AuctionHelper"
	exportData.meta = meta
	if C_EncodingUtil and C_EncodingUtil.SerializeCBOR and C_EncodingUtil.CompressString and C_EncodingUtil.EncodeBase64 then
		meta.format = self.EXPORT_FORMAT or "AHCBOR1"
		meta.encoding = "cbor+deflate+base64"
		local okSerialize, serialized = pcall(C_EncodingUtil.SerializeCBOR, exportData)
		if not okSerialize or type(serialized) ~= "string" or serialized == "" then
			return nil, serialized or "SerializeCBOR failed"
		end
		local okCompress, compressed = pcall(C_EncodingUtil.CompressString, serialized, Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0)
		if not okCompress or type(compressed) ~= "string" or compressed == "" then
			return nil, compressed or "CompressString failed"
		end
		local okEncode, encoded = pcall(C_EncodingUtil.EncodeBase64, compressed)
		if not okEncode or type(encoded) ~= "string" or encoded == "" then
			return nil, encoded or "EncodeBase64 failed"
		end
		return string.format("%s:%s", self.EXPORT_FORMAT or "AHCBOR1", encoded), nil
	end

	-- Forever / older clients: plain Lua text for the copy box and SavedVariables.
	meta.format = "AHLUA1"
	meta.encoding = "lua-text"
	local payload, err = self:BuildPlainLuaExportPayload(exportData)
	if not payload then
		return nil, err or "Lua export failed"
	end
	return payload, nil
end

--- Persist compressed export package for pickup after /reload.
function AuctionHelper:SaveExportToSavedVariables(payload, meta)
	if type(payload) ~= "string" or payload == "" then
		return false
	end
	AuctionHelperLastExport = AuctionHelperLastExport or {}
	AuctionHelperLastExport.savedAt = time()
	AuctionHelperLastExport.byteLength = #payload
	AuctionHelperLastExport.scope = meta and meta.scope or nil
	AuctionHelperLastExport.module = meta and meta.module or nil
	AuctionHelperLastExport.characterKey = meta and meta.characterKey or nil
	AuctionHelperLastExport.professionIdentifier = meta and meta.professionIdentifier or nil
	AuctionHelperLastExport.payload = nil
	local isLua = type(payload) == "string" and payload:sub(1, 7) == "AHLUA1:"
	AuctionHelperLastExport.format = isLua and "AHLUA1" or (self.EXPORT_FORMAT or "AHCBOR1")
	AuctionHelperLastExport.encoding = isLua and "lua-text" or "cbor+deflate+base64"
	local persistFull = self:GetSetting("general.persistLastExport", true) == true
	if not persistFull then
		AuctionHelperLastExport.persisted = false
		return false
	end
	if #payload > self.MAX_SAVEDEXPORT_BYTES then
		AuctionHelperLastExport.persisted = false
		return false
	end
	AuctionHelperLastExport.persisted = true
	AuctionHelperLastExport.payload = payload
	return true
end

function AuctionHelper:CopyBoxBuildFooterText(opts)
	opts = opts or {}
	if opts.unsavedHint and opts.unsavedHint ~= "" then
		return opts.unsavedHint
	end
	if opts.savedToVariables then
		return "Also saved for /reload: SavedVariables/AuctionHelper.lua, AuctionHelperLastExport"
	end
	return ""
end

function AuctionHelper:BuildCopyBoxPagedWrapperJson(pageIndex, pageCount, payloadFragment)
	return string.format("AHPAGE:%d/%d\n%s", pageIndex, pageCount, payloadFragment)
end

--- Build segment list: each { startPos, length } into fullJson; each wrapped page <= maxWrappedBytes.
--- Uses byte-length estimates in the binary search (no JsonEscape per probe), verifies with one Build per page.
--- Must run inside a coroutine; yields to spread work across frames.
function AuctionHelper:ComputeCopyBoxPagingSegmentsYielding(fullJson, maxWrappedBytes)
	local placeholder = self.COPYBOX_PAGING_PLACEHOLDER_PAGE_COUNT or 9999999
	local yieldInnerEvery = self.COPYBOX_PAGING_YIELD_INNER_STEPS or 32
	local segments = {}
	local len = #fullJson
	local pos = 1
	local pageIdx = 1
	local innerSteps = 0
	local function maybeYieldInner()
		innerSteps = innerSteps + 1
		if innerSteps >= yieldInnerEvery then
			innerSteps = 0
			coroutine.yield()
		end
	end

	while pos <= len do
		coroutine.yield()
		local remain = len - pos + 1
		local lo, hi = 1, remain
		local best = 1
		while lo <= hi do
			maybeYieldInner()
			local mid = math.floor((lo + hi) / 2)
			local frag = string.sub(fullJson, pos, pos + mid - 1)
			local est = self:EstimateCopyBoxWrappedPagingByteLength(pageIdx, placeholder, frag)
			if est <= maxWrappedBytes then
				best = mid
				lo = mid + 1
			else
				hi = mid - 1
			end
		end
		best = math.max(best, 1)
		while best >= 1 do
			local frag = string.sub(fullJson, pos, pos + best - 1)
			if #self:BuildCopyBoxPagedWrapperJson(pageIdx, placeholder, frag) <= maxWrappedBytes then
				break
			end
			best = best - 1
		end
		best = math.max(best, 1)
		table.insert(segments, { pos, best })
		pos = pos + best
		pageIdx = pageIdx + 1
	end
	return segments
end

--- Runs ComputeCopyBoxPagingSegmentsYielding via C_Timer (same pattern as RunEncodeJsonAsync).
function AuctionHelper:RunComputeCopyBoxPagingAsync(fullJson, maxWrappedBytes, onComplete)
	if type(onComplete) ~= "function" then
		return
	end

	local co = coroutine.create(function()
		return self:ComputeCopyBoxPagingSegmentsYielding(fullJson, maxWrappedBytes)
	end)

	local function oneStep()
		local ok, ret = coroutine.resume(co)
		if not ok then
			onComplete(nil, ret)
			return
		end
		if coroutine.status(co) == "dead" then
			onComplete(ret, nil)
			return
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(0, oneStep)
		else
			oneStep()
		end
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(0, oneStep)
	else
		while true do
			local ok2, ret2 = coroutine.resume(co)
			if not ok2 then
				onComplete(nil, ret2)
				return
			end
			if coroutine.status(co) == "dead" then
				onComplete(ret2, nil)
				return
			end
		end
	end
end

function AuctionHelper:EncodeCopyBoxWrappedPage(fullJson, seg, pageIndex, totalPages)
	local frag = string.sub(fullJson, seg[1], seg[1] + seg[2] - 1)
	return self:BuildCopyBoxPagedWrapperJson(pageIndex, totalPages, frag)
end

function AuctionHelper:LayoutCopyFrameScroll(copyFrame, useEnvelopePaging)
	if not copyFrame or not copyFrame.pageHintStr then
		return
	end
	local intro = "The text is selected. Press Ctrl+C, then paste it where you need it."
	if useEnvelopePaging then
		intro = intro .. " This package has several pages: copy each page and join them in order."
	end
	copyFrame.pageHintStr:SetText(intro)
	local pages = copyFrame._numPages or 1
	copyFrame.metaStr:SetText(string.format("%s bytes%s",
		self.FormatNumberGrouped and self:FormatNumberGrouped(copyFrame._fullLen or 0) or tostring(copyFrame._fullLen or 0),
		useEnvelopePaging and pages > 1 and string.format(" · %d pages", pages) or ""))
end

function AuctionHelper:CopyBoxApplyCurrentPage()
	local state = self:GetState()
	local cf = state.copyFrame
	if not cf or not cf._fullJson then
		return
	end
	if cf._pagingSegmentsPending then
		cf.editBox:SetText("Preparing paged export…")
		if cf.pageLabel then
			cf.pageLabel:SetText("…")
		end
		if cf.btnPrev then
			cf.btnPrev:SetEnabled(false)
		end
		if cf.btnNext then
			cf.btnNext:SetEnabled(false)
		end
		if cf.pageBar then
			cf.pageBar:SetShown(true)
		end
		return
	end
	local p = cf._pageIndex
	local numPages = cf._numPages
	local body
	if cf._pagingMode == "envelope" and cf._segments and cf._segments[p] then
		body = self:EncodeCopyBoxWrappedPage(cf._fullJson, cf._segments[p], p, numPages)
	elseif cf._pagingMode == "raw" then
		body = cf._fullJson
	else
		body = cf._fullJson or ""
	end
	cf.editBox:SetText(body)
	if cf.pageLabel then
		if cf._pagingMode == "envelope" and numPages > 1 then
			cf.pageLabel:SetText(string.format("Page %d of %d", p, numPages))
		else
			cf.pageLabel:SetText("Page 1 of 1")
		end
	end
	if cf.btnPrev then
		cf.btnPrev:SetEnabled(cf._pagingMode == "envelope" and p > 1)
	end
	if cf.btnNext then
		cf.btnNext:SetEnabled(cf._pagingMode == "envelope" and p < numPages)
	end
	if cf.pageBar then
		cf.pageBar:SetShown(cf._pagingMode == "envelope" and numPages > 1)
	end
	cf.editBox:HighlightText()
	cf.editBox:SetFocus()
end

function AuctionHelper:CopyBoxGoPage(delta)
	local state = self:GetState()
	local cf = state.copyFrame
	if not cf or cf._pagingMode ~= "envelope" or not cf._segments or cf._numPages <= 1 then
		return
	end
	cf._pageIndex = math.max(1, math.min(cf._numPages, cf._pageIndex + delta))
	self:CopyBoxApplyCurrentPage()
end

local function themedText(parent, font, colorKey, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", font)
	local color = AuctionHelper:GetTheme()[colorKey or "textPrimary"]
	text:SetTextColor(color.r, color.g, color.b)
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	return text
end

local function themedButton(parent, label, onClick, primary)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(label)
	AuctionHelper:SkinButton(button)
	button:SetSize(math.ceil(button:GetFontString():GetStringWidth()) + 24, AuctionHelper:GetTheme().size.control)
	if primary then
		AuctionHelper:SetButtonPrimary(button, true)
	end
	button:SetScript("OnClick", onClick)
	return button
end

-- The export window: header, one-line instructions, the selectable package text, page controls and
-- a footer saying where else the package was saved. Uses only core theme helpers.
function AuctionHelper:CreateCopyFrame()
	local theme = self:GetTheme()
	local pad = theme.spacing.md
	local f = CreateFrame("Frame", addonName .. "CopyFrame", UIParent, "BackdropTemplate")
	f:SetPoint("CENTER")
	f:SetSize(720, 560)
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(200)
	self:StyleWindow(f)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, f:GetName())

	local headerY = -(theme.size.header / 2)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("RIGHT", f, "TOPRIGHT", -6, headerY)
	self:SkinCloseButton(close)
	close:SetScript("OnClick", function() f:Hide() end)
	f.closeXButton = close
	f.metaStr = themedText(f, "GameFontHighlightSmall", "textMuted", "RIGHT")
	f.metaStr:SetPoint("RIGHT", close, "LEFT", -10, 0)
	f.copyTitle = themedText(f, "GameFontNormalLarge", "gold")
	f.copyTitle:SetPoint("LEFT", f, "TOPLEFT", pad, headerY - 1)
	f.copyTitle:SetPoint("RIGHT", f.metaStr, "LEFT", -12, 0)
	f.copyTitle:SetText("Export")
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", 1, -theme.size.header)
	rule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	rule:SetHeight(1)
	rule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)

	local footer = CreateFrame("Frame", nil, f)
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(theme.size.footer)
	local footerRule = footer:CreateTexture(nil, "BORDER")
	footerRule:SetPoint("TOPLEFT")
	footerRule:SetPoint("TOPRIGHT")
	footerRule:SetHeight(1)
	footerRule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	f.footerStr = themedText(footer, "GameFontHighlightSmall", "textMuted")
	f.footerStr:SetPoint("LEFT", pad, 0)
	f.footerStr:SetPoint("RIGHT", -pad, 0)

	f.pageHintStr = themedText(f, "GameFontHighlightSmall", "textMuted")
	f.pageHintStr:SetWordWrap(true)
	f.pageHintStr:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(theme.size.header + 1 + pad))
	f.pageHintStr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -(theme.size.header + 1 + pad))

	local actions = CreateFrame("Frame", nil, f)
	actions:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", pad - 1, pad)
	actions:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -(pad - 1), pad)
	actions:SetHeight(theme.size.control)
	local done = themedButton(actions, "Close", function() f:Hide() end, true)
	done:SetPoint("RIGHT")
	local selectAll = themedButton(actions, "Select all", function()
		f.editBox:SetFocus()
		f.editBox:HighlightText()
	end)
	selectAll:SetPoint("RIGHT", done, "LEFT", -8, 0)
	f.pageBar = CreateFrame("Frame", nil, actions)
	f.pageBar:SetPoint("TOPLEFT")
	f.pageBar:SetPoint("BOTTOMLEFT")
	f.pageBar:SetWidth(260)
	f.btnPrev = themedButton(f.pageBar, "Previous", function() AuctionHelper:CopyBoxGoPage(-1) end)
	f.btnPrev:SetPoint("LEFT")
	f.pageLabel = themedText(f.pageBar, "GameFontHighlightSmall", "textMuted", "CENTER")
	f.pageLabel:SetPoint("LEFT", f.btnPrev, "RIGHT", 8, 0)
	f.pageLabel:SetWidth(76)
	f.btnNext = themedButton(f.pageBar, "Next", function() AuctionHelper:CopyBoxGoPage(1) end)
	f.btnNext:SetPoint("LEFT", f.pageLabel, "RIGHT", 8, 0)

	-- The package text sits in a raised, clipped box; the edit box follows the scroll width.
	local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
	box:SetPoint("TOPLEFT", f.pageHintStr, "BOTTOMLEFT", 0, -10)
	box:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", 0, pad)
	self:ApplyBackdrop(box, theme.surface2, theme.borderControl)
	if box.SetClipsChildren then
		box:SetClipsChildren(true)
	end
	local scrollFrame = CreateFrame("ScrollFrame", addonName .. "CopyScrollFrame", box, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 8, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", -18, 8)
	local editBox = CreateFrame("EditBox", addonName .. "CopyEditBox", scrollFrame)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(true)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	editBox:SetWidth(600)
	editBox:SetScript("OnEscapePressed", function() f:Hide() end)
	scrollFrame:SetScrollChild(editBox)
	scrollFrame:SetScript("OnSizeChanged", function(_, width)
		editBox:SetWidth(math.max(100, width))
	end)
	f.scrollFrame = scrollFrame
	f.editBox = editBox
	self:SkinTree(f)
	return f
end

--- opts: fullByteLength, savedToVariables, unsavedHint
function AuctionHelper:ShowCopyBox(text, opts)
	opts = opts or {}
	local state = self:GetState()
	local copyFrame = state.copyFrame
	local fullJson = text or ""
	local fullLen = opts.fullByteLength or #fullJson
	local rawSingleLimit = self.COPYBOX_PAGE_BYTES or self.COPYBOX_JSON_PREVIEW_BYTES or (48 * 1024)
	local maxWrapped = self.COPYBOX_WRAPPED_PAGE_MAX_BYTES or rawSingleLimit
	if maxWrapped < 4096 then
		maxWrapped = 4096
	end

	local useEnvelope = fullLen > rawSingleLimit
	local segments
	local numPages
	local pagingMode
	local footerText

	if useEnvelope then
		pagingMode = "envelope"
		numPages = 1
		segments = nil
		footerText = self:CopyBoxBuildFooterText(opts)
	else
		numPages = 1
		pagingMode = "raw"
		footerText = self:CopyBoxBuildFooterText(opts)
	end

	if not copyFrame then
		copyFrame = self:CreateCopyFrame()
		state.copyFrame = copyFrame
	end

	copyFrame._fullJson = fullJson
	copyFrame._fullLen = fullLen
	copyFrame._segments = segments
	copyFrame._numPages = numPages
	copyFrame._pageIndex = 1
	copyFrame._pagingMode = pagingMode
	copyFrame._opts = opts
	copyFrame._pagingSegmentsPending = useEnvelope and true or false

	self:LayoutCopyFrameScroll(copyFrame, useEnvelope)

	if footerText ~= "" then
		copyFrame.footerStr:SetText(footerText)
		copyFrame.footerStr:Show()
	else
		copyFrame.footerStr:SetText("")
		copyFrame.footerStr:Hide()
	end

	copyFrame:Show()
	AuctionHelper:SkinTree(copyFrame)
	self:CopyBoxApplyCurrentPage()

	if useEnvelope then
		copyFrame._pagingToken = (copyFrame._pagingToken or 0) + 1
		local myToken = copyFrame._pagingToken
		self:RunComputeCopyBoxPagingAsync(fullJson, maxWrapped, function(computedSegments, err)
			if not copyFrame or copyFrame._pagingToken ~= myToken then
				return
			end
			copyFrame._pagingSegmentsPending = false
			if err or type(computedSegments) ~= "table" then
				copyFrame._pagingMode = "raw"
				copyFrame._segments = nil
				copyFrame._numPages = 1
				self:LayoutCopyFrameScroll(copyFrame, false)
				copyFrame.editBox:SetText(
					"Paging failed: "
						.. tostring(err or "unknown error")
						.. "\n\nTry exporting a smaller scope (for example one profession or compact auction/inventory data)."
				)
				return
			end
			local np = math.max(#computedSegments, 1)
			local useEnv = np > 1
			if not useEnv then
				copyFrame._pagingMode = "raw"
				copyFrame._segments = nil
				copyFrame._numPages = 1
				self:LayoutCopyFrameScroll(copyFrame, false)
			else
				copyFrame._pagingMode = "envelope"
				copyFrame._segments = computedSegments
				copyFrame._numPages = np
				self:LayoutCopyFrameScroll(copyFrame, true)
			end
			copyFrame._pageIndex = 1
			local ft = self:CopyBoxBuildFooterText(copyFrame._opts or {})
			if ft ~= "" then
				copyFrame.footerStr:SetText(ft)
				copyFrame.footerStr:Show()
			end
			self:CopyBoxApplyCurrentPage()
		end)
	end
end

-- Export scope -> what the progress window calls it. Profession slices fill in the profession at %s.
local EXPORT_SCOPE_LABELS = {
	account = "account", account_summary = "account summary",
	professions = "professions (character)", professions_compact = "professions compact",
	professions_recipes = "professions recipes (character)", professions_talents = "professions talents (character)",
	inventory = "inventory (character)", inventory_compact = "inventory compact",
	auction_snapshot = "auction snapshot", auction_history = "auction history", crafting_costs = "crafting costs",
	spec_catalog = "spec catalog (Midnight bundled)", character_meta = "character meta",
	profession = "profession (%s)", profession_recipes = "profession recipes (%s)", profession_talents = "profession talents (%s)",
}

local function exportScopeLabel(scope, identifier)
	local label = EXPORT_SCOPE_LABELS[scope]
	return label and string.format(label, tostring(identifier or "?")) or tostring(scope or "character")
end

function AuctionHelper:Export(scope, identifier)
	local st = self:GetState()
	if st.exportJsonBusy then
		self:PrintMessage("Export already in progress.")
		return
	end

	self:ShowExportProgress(exportScopeLabel(scope, identifier))

	local dbg = self:IsDebugEnabled()
	debugprofilestart()
	local exportData, err = self:GetExportData(scope, identifier)
	local msGather = debugprofilestop()
	if not exportData then
		self:HideExportProgress()
		self:PrintMessage(err or "Nothing to export.")
		return
	end

	local meta = exportData.meta or {}
	st.exportJsonBusy = true
	self:SetExportProgressPhase("Packing the export", true)
	self:UpdateExportProgressSteps(1)
	debugprofilestart()
	local payload, encodeErr = self:BuildCompactExportPayload(exportData)
	local msEncode = debugprofilestop()
	self:HideExportProgress(payload and not encodeErr)
	st.exportJsonBusy = false

	if encodeErr or not payload then
		self:PrintMessage("Package export failed: " .. tostring(encodeErr or "unknown error"))
		if dbg then
			self:PrintMessage(string.format("Export timing: gather=%.1fms pack=%.1fms (failed)", msGather, msEncode))
		end
		return
	end

	if #payload > self.MAX_EXPORT_BYTES then
		self:PrintMessage(string.format("Compressed export is %d bytes. Use a smaller scope if needed.", #payload))
	end

	local savedOk = self:SaveExportToSavedVariables(payload, meta)
	local unsavedHint
	if not savedOk and #payload > self.MAX_SAVEDEXPORT_BYTES then
		unsavedHint = string.format("Full compressed export was not saved (over %d byte SavedVariables limit). Try smaller scopes"
			.. " such as professions_recipes, profession_talents, inventory, or a single profession.", self.MAX_SAVEDEXPORT_BYTES)
	end

	debugprofilestart()
	self:ShowCopyBox(payload, { fullByteLength = #payload, savedToVariables = savedOk, unsavedHint = unsavedHint })
	local msUi = debugprofilestop()

	if dbg then
		self:PrintMessage(string.format("Export timing: gather=%.1fms pack=%.1fms copyUI=%.1fms (package %d bytes)",
			msGather, msEncode, msUi, #payload))
	end

	local formatLabel = (meta and meta.format) or (type(payload) == "string" and payload:sub(1, 7) == "AHLUA1:" and "AHLUA1") or self.EXPORT_FORMAT or "AHCBOR1"
	self:PrintMessage(string.format("Exported %s package (%d bytes, %s).", tostring(meta.scope or scope or "character"), #payload, formatLabel))
	if savedOk then
		self:PrintMessage("Compressed export queued for SavedVariables — |cffffffff/reload|r or log out to write WTF\\Account\\…\\SavedVariables\\AuctionHelper.lua (AuctionHelperLastExport.payload).")
	elseif #payload > self.MAX_SAVEDEXPORT_BYTES then
		self:PrintMessage("SavedVariables copy skipped (compressed export still exceeds size limit).")
	end
end

function AuctionHelper:PrintStatus()
	self:InitDB()
	local characterKey = self:GetCharacterKey()
	local characterData = self.db.characters[characterKey]
	local state = self:GetState()

	if state.scanInProgress then
		local currentName = state.currentProfession and state.currentProfession.professionName or "pending"
		self:PrintMessage(string.format("Scan in progress. Current profession: %s. Remaining queue: %d.", currentName, #state.queue))
		return
	end

	if not characterData then
		self:PrintMessage("No stored scan for this character yet.")
		return
	end

	self:PrintMessage(string.format("Last scan for %s finished at %s with %d professions.",
		characterKey,
		date("%Y-%m-%d %H:%M:%S", characterData.scanFinishedAt or 0),
		self:TableCount(characterData.professions)))
end

local ON_OFF_ARGS = { on = true, ["1"] = true, ["true"] = true, off = false, ["0"] = false, ["false"] = false }

-- `/auctionhelper settings <usageName> on|off` for one boolean setting.
local function onOffSetting(key, default, usageName, label)
	return function(self, arg)
		local value = ON_OFF_ARGS[arg]
		if value == nil then
			self:PrintMessage(string.format("Usage: /auctionhelper settings %s on|off", usageName))
			return
		end
		self:SetSetting(key, value)
		self:PrintMessage(string.format("%s: %s.", label, self:GetSetting(key, default) and "on" or "off"))
	end
end

local setSpecTreeCapture = onOffSetting("capture.captureSpecializationTree", true, "spectree", "Specialization tree capture")
local setRecipeOutputCapture = onOffSetting("capture.includeRecipeOutputItemData", false, "recipeoutput", "Recipe output item API dump")

local function setInventoryBatchSize(self, arg)
	local size = tonumber(arg)
	if not size or size < 0 then
		self:PrintMessage("Usage: /auctionhelper settings invbatch <n>  (0 = one frame; 50–100 spreads GetItemCount work)")
		return
	end
	self:SetSetting("capture.inventorySnapshotBatchSize", math.floor(size))
	self:PrintMessage(string.format("Inventory snapshot batch size: %d.", self:GetSetting("capture.inventorySnapshotBatchSize", 0)))
end

-- `/auctionhelper settings <sub> <arg>` (sub lower-cased) -> handler(self, arg).
local SETTINGS_SUBCOMMANDS = {
	spectree = setSpecTreeCapture, specialization = setSpecTreeCapture,
	recipeoutput = setRecipeOutputCapture, rawoutput = setRecipeOutputCapture,
	invbatch = setInventoryBatchSize, inventorybatch = setInventoryBatchSize,
}

function AuctionHelper:HandleSettingsSlash(rest)
	self:InitDB()
	local sub, arg = rest:match("^(%S+)%s*(.*)$")
	local handler = SETTINGS_SUBCOMMANDS[string.lower(sub or "")]
	if handler then
		handler(self, self:Trim(arg or ""))
		return
	end
	self:PrintMessage("Usage: /auctionhelper settings spectree on|off | recipeoutput on|off | invbatch <n>")
end

-- The auction subcommand handlers return true when they ran; false falls through to the usage line.
local function printAuctionStatus(self)
	local enabled = self:GetSetting("auction.enabled", true)
	local rows = self.BuildAuctionInventoryRows and self:BuildAuctionInventoryRows() or {}
	self:PrintMessage(string.format("Auction module: %s. Inventory rows: %d.", enabled and "enabled" or "disabled", #rows))
	return true
end

local function setAuctionModuleEnabled(self, enabled)
	self:SetSetting("auction.enabled", enabled)
	self:PrintMessage(enabled and "Auction module enabled." or "Auction module disabled.")
	return true
end

local function refreshAuctionPrices(self, target)
	target = string.lower(target)
	if (target == "crafts" or target == "craft") and self.QueueCraftEconomyAuctionRefresh then
		self:QueueCraftEconomyAuctionRefresh({})
		self:PrintMessage("Queued craft refresh.")
		return true
	end
	if self.BuildAuctionVisibleItemIDs and self.QueueVisibleAuctionRefresh then
		self:QueueVisibleAuctionRefresh(self:BuildAuctionVisibleItemIDs())
		self:PrintMessage("Queued visible auction refresh.")
		return true
	end
	return false
end

local function runAuctionDump(self, mode)
	if not self.StartAuctionDump then
		return false
	end
	self:RunAuctionDumpSlash(mode)
	return true
end

-- `/auctionhelper auction <sub> <arg>` (sub lower-cased) -> handler(self, arg).
local AUCTION_SUBCOMMANDS = {
	[""] = printAuctionStatus, status = printAuctionStatus,
	enable = function(self) return setAuctionModuleEnabled(self, true) end,
	disable = function(self) return setAuctionModuleEnabled(self, false) end,
	refresh = refreshAuctionPrices,
	dump = runAuctionDump,
}

function AuctionHelper:HandleAuctionSlash(rest)
	local sub, arg = self:Trim(rest or ""):match("^(%S+)%s*(.*)$")
	local handler = AUCTION_SUBCOMMANDS[string.lower(sub or "")]
	if handler and handler(self, self:Trim(arg or "")) then
		return
	end
	self:PrintMessage("Usage: /auctionhelper auction [status|enable|disable|refresh [crafts]|dump [visible|full]]")
end

--- The dump runs asynchronously and prints its own "complete" line when it ends. When it refuses
--- to start, StartAuctionDump prints why; an empty dump finishes at once and is not "started".
function AuctionHelper:RunAuctionDumpSlash(mode)
	mode = mode ~= "" and mode or "visible"
	local dump = self:StartAuctionDump(mode) and self:GetState().auctionDump
	if dump and dump.running == true then
		self:PrintMessage(string.format("Auction dump started (mode: %s).", mode))
	end
end

local SLASH_HELP_LINES = {
	"Commands: /auctionhelper (window) | /auctionhelper docs | /auctionhelper scan | /auctionhelper full | /auctionhelper status"
		.. " | /auctionhelper debug [on|off|toggle] | /auctionhelper export … | /auctionhelper settings …"
		.. " | /auctionhelper auction …  (short: /ah)",
	"Export: character | account | account_summary | professions | professions_recipes | professions_talents"
		.. " | professions_compact | inventory | inventory_compact | auction_snapshot | auction_history | crafting_costs"
		.. " | spec_catalog | meta | profession <id|name> | profession_recipes <id|name> | profession_talents <id|name>",
	"Settings: spectree on|off | recipeoutput on|off | invbatch <n> (0 = sync snapshot). Auction: status|enable|disable|refresh [crafts]|dump.",
	"Export: AHLUA1 (plain Lua text) on Forever, AHCBOR1 (CBOR + Deflate + Base64) on retail. Full payload is written to AuctionHelperLastExport after /reload"
		.. " — see timing lines when debug is on.",
}

local EXPORT_USAGE = "Usage: /auctionhelper export [character|account|account_summary|professions|professions_recipes"
	.. "|professions_talents|professions_compact|inventory|inventory_compact|auction_snapshot|auction_history|crafting_costs"
	.. "|spec_catalog|meta|profession <id|name>|profession_recipes <id|name>|profession_talents <id|name>]"

-- `/auctionhelper export <arg>` (lower-cased) -> export scope.
local EXPORT_SCOPE_BY_ARG = {
	[""] = "character", character = "character",
	account = "account",
	account_summary = "account_summary", summary = "account_summary", aggregates = "account_summary", aggregate = "account_summary",
	professions = "professions",
	professions_recipes = "professions_recipes",
	professions_talents = "professions_talents",
	professions_compact = "professions_compact", profcompact = "professions_compact",
	inventory = "inventory", items = "inventory",
	inventory_compact = "inventory_compact", invcompact = "inventory_compact",
	auction_snapshot = "auction_snapshot", auctionsnapshot = "auction_snapshot",
	auction_history = "auction_history", auctionhistory = "auction_history",
	crafting_costs = "crafting_costs", craftcosts = "crafting_costs",
	spec_catalog = "spec_catalog", speccatalog = "spec_catalog", spec_catalog_midnight = "spec_catalog",
	meta = "character_meta", charmeta = "character_meta", character_meta = "character_meta",
}

local function handleExportSlash(self, rest)
	local scope = EXPORT_SCOPE_BY_ARG[string.lower(rest or "")]
	if scope then
		self:Export(scope)
		return
	end
	local sliceScope, identifier = rest:match("^(%S+)%s+(.+)$")
	sliceScope = string.lower(sliceScope or "")
	if (sliceScope == "profession_recipes" or sliceScope == "profession_talents") and identifier then
		self:Export(sliceScope, self:Trim(identifier))
		return
	end
	if sliceScope == "profession" and identifier then
		self:Export("profession", identifier)
		return
	end
	self:PrintMessage(EXPORT_USAGE)
end

local function setDebugOn(self)
	self:SetDebugEnabled(true)
end

local function setDebugOff(self)
	self:SetDebugEnabled(false)
end

local function clearDebugLog(self)
	self:ClearDebugLog()
	self:PrintMessage("Persistent debug log cleared.")
end

local function printDebugLogPath(self)
	self:PrintMessage("Persistent debug log is stored in AuctionHelperDB.settings.debug.lines and written to"
		.. " WTF\\Account\\...\\SavedVariables\\AuctionHelper.lua on /reload or logout.")
end

local function printDebugStatus(self)
	self:InitDB()
	local count = self.db and self.db.debug and self.db.debug.lines and #self.db.debug.lines or 0
	self:PrintMessage(string.format("Debug logging: %s. Persistent lines buffered: %d.", self:IsDebugEnabled() and "on" or "off", count))
end

local function toggleDebug(self)
	self:SetDebugEnabled(not self:IsDebugEnabled())
end

-- `/auctionhelper debug <sub>` (lower-cased); anything else toggles.
local DEBUG_SUBCOMMANDS = {
	on = setDebugOn, ["1"] = setDebugOn, ["true"] = setDebugOn,
	clear = clearDebugLog, reset = clearDebugLog,
	where = printDebugLogPath, path = printDebugLogPath,
	status = printDebugStatus,
	off = setDebugOff, ["0"] = setDebugOff, ["false"] = setDebugOff,
}

local function handleDebugSlash(self, rest)
	local handler = DEBUG_SUBCOMMANDS[string.lower(rest or "")] or toggleDebug
	handler(self)
	if self.ui and self.ui.mainFrame and self.ui.mainFrame:IsShown() then
		self:RefreshDashboard(true)
	end
end

local function printSlashHelp(self)
	for _, line in ipairs(SLASH_HELP_LINES) do
		self:PrintMessage(line)
	end
end

local function openDocumentation(self)
	self:OpenDocumentationTab()
end

local function handleAuctionSlash(self, rest)
	self:HandleAuctionSlash(rest)
end

local function startFullCharacterDump(self)
	self:StartFullCharacterDump()
end

-- `/auctionhelper <command> <rest>` (command lower-cased) -> handler(self, rest).
local SLASH_COMMANDS = {
	[""] = function(self) self:ToggleDashboard() end,
	docs = openDocumentation, documentation = openDocumentation,
	help = printSlashHelp,
	settings = function(self, rest) self:HandleSettingsSlash(rest) end,
	auction = handleAuctionSlash, ah = handleAuctionSlash,
	debug = handleDebugSlash,
	scan = function(self) self:StartScan() end,
	full = startFullCharacterDump, dumpfull = startFullCharacterDump,
	status = function(self) self:PrintStatus() end,
	export = handleExportSlash,
}

function AuctionHelper:HandleSlash(input)
	input = self:Trim(input)
	local command, rest = input:match("^(%S+)%s*(.-)$")
	command = string.lower(command or "")
	rest = self:Trim(rest)
	local handler = SLASH_COMMANDS[command]
	if handler then
		handler(self, rest)
		return
	end
	self:PrintMessage("Unknown command. Use /auctionhelper help.")
end
