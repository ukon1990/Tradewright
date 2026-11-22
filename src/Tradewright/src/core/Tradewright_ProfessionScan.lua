-- Profession scan: reagent slots and recipe records from the open profession window, merged into a stored profession row.
local _, Tradewright = ...

function Tradewright:CollectClassicRecipeReagentSlots(recipeSpellID)
	local slots = {}
	local makeSlot = self.MaterialLogic and self.MaterialLogic.MakeClassicReagentSlot
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

function Tradewright:CollectRecipeData(recipeSpellID)
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

function Tradewright:BeginProfessionCollectCaches()
	self._itemDescCache = {}
	self._currencyDescCache = {}
	self._includeRecipeOutputItemData = self:GetSetting("capture.includeRecipeOutputItemData", false) == true
end

function Tradewright:EndProfessionCollectCaches()
	self._itemDescCache = nil
	self._currencyDescCache = nil
	self._includeRecipeOutputItemData = nil
end

--- Rebuild recipeIDs array + recipeCount from the recipes map.
function Tradewright:RebuildProfessionRecipeIndex(professionData)
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
function Tradewright:CollectRecipesIntoProfessionData(professionData, recipeSpellIDs, fromIndex, toIndex)
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
function Tradewright:PruneProfessionRecipesNotInSpellSet(professionData, spellIDSet)
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

function Tradewright:StampProfessionLiveFingerprint(professionData, fingerprintInfo)
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

function Tradewright:UpdateProfessionDescriptorFields(professionData, professionDescriptor, baseInfo, childInfo)
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

function Tradewright:ApplySpecializationResultToProfessionData(professionData, specResult)
	if not professionData then
		return
	end
	professionData.specializationTree = specResult and specResult.primary or nil
	professionData.specializationTrees = specResult and specResult.bySkillLineID or nil
	professionData.primarySpecializationSkillLineID = specResult and specResult.primarySkillLineID or nil
end

--- Finalize indexes, optional catalog attach, and live fingerprint stamp.
function Tradewright:FinalizeProfessionDataCollect(professionData, professionDescriptor, fingerprintInfo)
	self:RebuildProfessionRecipeIndex(professionData)
	if self.AttachSpecCatalogMetadata and professionDescriptor then
		self:AttachSpecCatalogMetadata(professionData, professionDescriptor.skillLineID)
	end
	self:StampProfessionLiveFingerprint(professionData, fingerprintInfo)
	return professionData
end

function Tradewright:CollectCurrentProfessionData(professionDescriptor)
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
function Tradewright:CreateProfessionDataShell(professionDescriptor, opts)
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
