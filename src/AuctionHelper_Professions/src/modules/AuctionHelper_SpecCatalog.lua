local _, AuctionHelper = ...

AuctionHelper.SPEC_CATALOG_VERSION = 1
AuctionHelper.EXPANSION_ID_MIDNIGHT = 11
AuctionHelper.EXPANSION_ID_TWW = 10
AuctionHelper.EXPANSION_ID_DRAGONFLIGHT = 9

--- Base profession skill line -> { expansionID, profession } for each expansion tier line.
--- Index matches CraftSim/wowpedia TradeSkillLineID expansion columns (9=TWW, 11=Midnight).
AuctionHelper.TRADE_SKILL_LINE_BY_PROFESSION = {
	[Enum.Profession.Blacksmithing] = { BASE = 164, [9] = 2822, [10] = 2872, [11] = 2907 },
	[Enum.Profession.Leatherworking] = { BASE = 165, [9] = 2830, [10] = 2880, [11] = 2915 },
	[Enum.Profession.Alchemy] = { BASE = 171, [9] = 2823, [10] = 2871, [11] = 2906 },
	[Enum.Profession.Herbalism] = { BASE = 182, [9] = 2832, [10] = 2877, [11] = 2912 },
	[Enum.Profession.Cooking] = { BASE = 185, [9] = 2824, [10] = 2873, [11] = 2908 },
	[Enum.Profession.Mining] = { BASE = 186, [9] = 2833, [10] = 2881, [11] = 2916 },
	[Enum.Profession.Tailoring] = { BASE = 197, [9] = 2831, [10] = 2883, [11] = 2918 },
	[Enum.Profession.Engineering] = { BASE = 202, [9] = 2827, [10] = 2875, [11] = 2910 },
	[Enum.Profession.Enchanting] = { BASE = 333, [9] = 2825, [10] = 2874, [11] = 2909 },
	[Enum.Profession.Fishing] = { BASE = 356, [9] = 2826, [10] = 2876, [11] = 2911 },
	[Enum.Profession.Skinning] = { BASE = 393, [9] = 2834, [10] = 2882, [11] = 2917 },
	[Enum.Profession.Jewelcrafting] = { BASE = 755, [9] = 2829, [10] = 2879, [11] = 2914 },
	[Enum.Profession.Inscription] = { BASE = 773, [9] = 2828, [10] = 2878, [11] = 2913 },
}

function AuctionHelper:InitSpecCatalogStore()
	if type(self._specCatalog) == "table" then
		return
	end
	self._specCatalog = {}
end

function AuctionHelper:RegisterSpecCatalog(expansionID, profession, data)
	self:InitSpecCatalogStore()
	expansionID = tonumber(expansionID)
	profession = tonumber(profession)
	if not expansionID or not profession or type(data) ~= "table" then
		return
	end
	self._specCatalog[expansionID] = self._specCatalog[expansionID] or {}
	self._specCatalog[expansionID][profession] = {
		expansionID = expansionID,
		profession = profession,
		recipeMapping = data.recipeMapping or {},
		nodeData = data.nodeData or {},
	}
end

function AuctionHelper:GetSpecCatalog(expansionID, profession)
	self:InitSpecCatalogStore()
	expansionID = tonumber(expansionID)
	profession = tonumber(profession)
	local byExp = self._specCatalog[expansionID]
	return byExp and byExp[profession] or nil
end

function AuctionHelper:ResolveSpecCatalogForTierSkillLine(tierSkillLineID)
	tierSkillLineID = tonumber(tierSkillLineID)
	if not tierSkillLineID then
		return nil
	end
	for profession, lines in pairs(self.TRADE_SKILL_LINE_BY_PROFESSION) do
		for expansionID, skillLineID in pairs(lines) do
			if type(expansionID) == "number" and skillLineID == tierSkillLineID then
				return expansionID, profession, self:GetSpecCatalog(expansionID, profession)
			end
		end
	end
	return nil
end

local STAT_KEYS = {
	"skill",
	"multicraft",
	"resourcefulness",
	"ingenuity",
	"craftingspeed",
}

function AuctionHelper:NewSpecStatTotals()
	return {
		skill = 0,
		multicraft = 0,
		resourcefulness = 0,
		ingenuity = 0,
		craftingspeed = 0,
		resourcefulnessExtraItemsFactor = 0,
		ingenuityExtraConcentrationFactor = 0,
		reduceConcentrationCost = 0,
	}
end

function AuctionHelper:AddSpecStatTotals(target, source)
	if type(target) ~= "table" or type(source) ~= "table" then
		return target
	end
	for _, key in ipairs(STAT_KEYS) do
		target[key] = (target[key] or 0) + (tonumber(source[key]) or 0)
	end
	target.resourcefulnessExtraItemsFactor = (target.resourcefulnessExtraItemsFactor or 0)
		+ (tonumber(source.resourcefulnessExtraItemsFactor) or 0)
	target.ingenuityExtraConcentrationFactor = (target.ingenuityExtraConcentrationFactor or 0)
		+ (tonumber(source.ingenuityExtraConcentrationFactor) or 0)
	target.reduceConcentrationCost = (target.reduceConcentrationCost or 0) + (tonumber(source.reduceConcentrationCost) or 0)
	return target
end

function AuctionHelper:ParseCatalogPerkStats(stats)
	local out = self:NewSpecStatTotals()
	if type(stats) ~= "table" then
		return out
	end
	for stat, amount in pairs(stats) do
		amount = tonumber(amount) or 0
		if out[stat] ~= nil then
			out[stat] = out[stat] + amount
		elseif stat == "reagentssavedfromresourcefulness" then
			out.resourcefulnessExtraItemsFactor = out.resourcefulnessExtraItemsFactor + (amount / 100)
		elseif stat == "ingenuityrefundincrease" then
			out.ingenuityExtraConcentrationFactor = out.ingenuityExtraConcentrationFactor + (amount / 100)
		elseif stat == "reduceconcentrationcost" then
			out.reduceConcentrationCost = out.reduceConcentrationCost + (amount / 100)
		elseif stat == "additionalitemscraftedwithmulticraft" then
			-- Stored as rating points in catalog; extra yield handled separately in profit tools.
		end
	end
	return out
end

function AuctionHelper:GetSpecNodeRank(nodeRanks, nodeID)
	if type(nodeRanks) ~= "table" or not nodeID then
		return 0
	end
	local rank = nodeRanks[tostring(nodeID)]
	if rank == nil then
		rank = nodeRanks[nodeID]
	end
	return math.max(0, tonumber(rank) or 0)
end

function AuctionHelper:GetSpecUnlockRankForPerk(perkID, _configID)
	perkID = tonumber(perkID)
	if not perkID or not C_ProfSpecs or not C_ProfSpecs.GetUnlockRankForPerk then
		return 0
	end
	return tonumber(C_ProfSpecs.GetUnlockRankForPerk(perkID)) or 0
end

function AuctionHelper:BuildSpecNodeRanksFromSpecializationTree(specTree)
	local byTier = {}
	if type(specTree) ~= "table" then
		return byTier
	end

	local function absorbTabNodes(byTier, tierKey, tab)
		if type(tab) ~= "table" then
			return
		end
		local nodeLists = {}
		if type(tab.paths) == "table" then
			nodeLists[#nodeLists + 1] = tab.paths
		end
		if type(tab.nodes) == "table" then
			nodeLists[#nodeLists + 1] = tab.nodes
		end
		for _, nodes in ipairs(nodeLists) do
			for _, node in ipairs(nodes) do
				local ni = node.nodeInfo
				local nodeID = tonumber(node.nodeID or (ni and ni.ID))
				if nodeID and ni and tonumber(ni.maxRanks or 0) > 1 then
					local activeRank = tonumber(ni.activeRank or ni.currentRank or 0) or 0
					local rank = math.max(0, activeRank - 1)
					byTier[tierKey][tostring(nodeID)] = rank
				end
			end
		end
	end

	local function absorbTree(tree, tierKey)
		if type(tree) ~= "table" then
			return
		end
		tierKey = tostring(tierKey or tree.skillLineID or "unknown")
		byTier[tierKey] = byTier[tierKey] or {}
		for _, tab in ipairs(tree.tabs or {}) do
			absorbTabNodes(byTier, tierKey, tab)
		end
	end

	if specTree.bySkillLineID then
		for tierKey, tree in pairs(specTree.bySkillLineID) do
			absorbTree(tree, tierKey)
		end
	elseif specTree.tabs then
		absorbTree(specTree, specTree.skillLineID)
	else
		for tierKey, tree in pairs(specTree) do
			if type(tree) == "table" and tree.tabs then
				absorbTree(tree, tierKey)
			end
		end
	end
	return byTier
end

function AuctionHelper:ResolveSpecCatalogForRecipe(recipeID, baseSkillLineID)
	recipeID = tonumber(recipeID)
	baseSkillLineID = tonumber(baseSkillLineID)
	if not recipeID or not baseSkillLineID then
		return nil
	end
	local professionEnum = nil
	for profession, lines in pairs(self.TRADE_SKILL_LINE_BY_PROFESSION) do
		if lines.BASE == baseSkillLineID then
			professionEnum = profession
			break
		end
	end
	if not professionEnum then
		return nil
	end
	for expansionID = 11, 9, -1 do
		local catalog = self:GetSpecCatalog(expansionID, professionEnum)
		if catalog and catalog.recipeMapping and catalog.recipeMapping[recipeID] then
			local tierSkillLineID = self.TRADE_SKILL_LINE_BY_PROFESSION[professionEnum][expansionID]
			return expansionID, professionEnum, catalog, tierSkillLineID
		end
	end
	return nil
end

function AuctionHelper:BuildSpecNodeGroupsForRecipe(recipeID, catalog)
	local groups = {}
	if not catalog or type(catalog.recipeMapping) ~= "table" or type(catalog.nodeData) ~= "table" then
		return groups
	end
	recipeID = tonumber(recipeID)
	local mapping = recipeID and catalog.recipeMapping[recipeID] or nil
	if type(mapping) ~= "table" then
		return groups
	end
	for _, entryID in ipairs(mapping) do
		local perkData = catalog.nodeData[entryID]
		if type(perkData) == "table" then
			local baseNodeID = tonumber(perkData.nodeID)
			if baseNodeID and tonumber(perkData.maxRank) == 1 then
				groups[baseNodeID] = groups[baseNodeID] or { baseNodeID = baseNodeID, perkIDs = {} }
				table.insert(groups[baseNodeID].perkIDs, tonumber(entryID))
			end
		end
	end
	return groups
end

function AuctionHelper:ComputeSpecStatsForBaseNode(baseNodeID, perkIDs, nodeRanks, catalog, configID)
	local totals = self:NewSpecStatTotals()
	local nodeData = catalog and catalog.nodeData or {}
	baseNodeID = tonumber(baseNodeID)
	local rank = self:GetSpecNodeRank(nodeRanks, baseNodeID)
	local baseEntry = baseNodeID and nodeData[baseNodeID] or nil
	local detail = {
		nodeID = baseNodeID,
		rank = rank,
		maxRank = baseEntry and tonumber(baseEntry.maxRank) or nil,
		name = baseEntry and (baseEntry.name or nil) or nil,
		perks = {},
		stats = self:NewSpecStatTotals(),
	}

	if baseEntry and type(baseEntry.stats) == "table" then
		local baseStats = self:ParseCatalogPerkStats(baseEntry.stats)
		for _, key in ipairs(STAT_KEYS) do
			baseStats[key] = (baseStats[key] or 0) * rank
		end
		self:AddSpecStatTotals(detail.stats, baseStats)
		self:AddSpecStatTotals(totals, baseStats)
	end

	for _, perkID in ipairs(perkIDs or {}) do
		local perkData = nodeData[perkID]
		if type(perkData) == "table" then
			local threshold = self:GetSpecUnlockRankForPerk(perkID, configID)
			local active = rank >= threshold
			local perkStats = self:ParseCatalogPerkStats(perkData.stats)
			local perkRow = {
				perkID = perkID,
				unlockRank = threshold,
				active = active,
				stats = perkStats,
			}
			table.insert(detail.perks, perkRow)
			if active then
				self:AddSpecStatTotals(detail.stats, perkStats)
				self:AddSpecStatTotals(totals, perkStats)
			end
		end
	end

	detail.stats.skill = math.floor((detail.stats.skill or 0) + 0.5)
	totals.skill = math.floor((totals.skill or 0) + 0.5)
	return totals, detail
end

function AuctionHelper:ComputeSpecBreakdownForRecipe(recipeID, catalog, nodeRanks, configID)
	if not catalog then
		return nil
	end
	local groups = self:BuildSpecNodeGroupsForRecipe(recipeID, catalog)
	if not next(groups) then
		return {
			recipeID = tonumber(recipeID),
			totals = self:NewSpecStatTotals(),
			nodes = {},
			catalogMatched = false,
		}
	end

	local result = {
		recipeID = tonumber(recipeID),
		totals = self:NewSpecStatTotals(),
		nodes = {},
		catalogMatched = true,
	}
	for baseNodeID, group in pairs(groups) do
		local _, detail = self:ComputeSpecStatsForBaseNode(baseNodeID, group.perkIDs, nodeRanks, catalog, configID)
		if detail then
			table.insert(result.nodes, detail)
			self:AddSpecStatTotals(result.totals, detail.stats)
		end
	end
	table.sort(result.nodes, function(a, b) return (a.nodeID or 0) < (b.nodeID or 0) end)
	return result
end

local function catalogTierInfo(self, catalog, expansionID, tierSkillLineID)
	return {
		available = true,
		version = self.SPEC_CATALOG_VERSION,
		expansionID = expansionID,
		tierSkillLineID = tierSkillLineID,
		nodeCount = self:TableCount(catalog.nodeData or {}),
		recipeMappingCount = self:TableCount(catalog.recipeMapping or {}),
	}
end

local function professionForBaseSkillLine(self, baseSkillLineID)
	for profession, lines in pairs(self.TRADE_SKILL_LINE_BY_PROFESSION or {}) do
		if lines.BASE == baseSkillLineID then
			return profession
		end
	end
	return nil
end

-- Catalogs for the profession's own expansion tiers, plus any other ranked tier that has one.
local function collectCatalogsUsed(self, professionEnum, ranksByTier)
	local catalogsUsed = {}
	for expansionID = 11, 9, -1 do
		local catalog = professionEnum and self:GetSpecCatalog(expansionID, professionEnum)
		local tierSkillLineID = catalog and self.TRADE_SKILL_LINE_BY_PROFESSION[professionEnum][expansionID]
		if tierSkillLineID then
			catalogsUsed[tostring(tierSkillLineID)] = catalogTierInfo(self, catalog, expansionID, tierSkillLineID)
		end
	end
	for tierKey in pairs(ranksByTier) do
		if not catalogsUsed[tierKey] then
			local expansionID, _, catalog = self:ResolveSpecCatalogForTierSkillLine(tonumber(tierKey))
			if catalog then
				catalogsUsed[tierKey] = catalogTierInfo(self, catalog, expansionID, tonumber(tierKey))
			end
		end
	end
	return catalogsUsed
end

local function specConfigIDForTier(professionData, tierSkillLineID)
	local trees = professionData.specializationTrees
	local tierTree = trees and trees[tostring(tierSkillLineID)]
	if tierTree then
		return tierTree.configID
	end
	local legacyTree = professionData.specializationTree
	if legacyTree and legacyTree.skillLineID == tierSkillLineID then
		return legacyTree.configID
	end
	return nil
end

local function attachRecipeSpecBreakdown(self, professionData, recipeKey, recipeData, baseSkillLineID)
	local recipeSpellID = self:GetRecipeSpellID(recipeData) or tonumber(recipeKey)
	local expansionID, recipeProfession, catalog, tierSkillLineID = self:ResolveSpecCatalogForRecipe(recipeSpellID, baseSkillLineID)
	if not catalog or not recipeSpellID then
		return
	end
	local nodeRanks = professionData.specNodeRanksByTier[tostring(tierSkillLineID)] or {}
	local configID = specConfigIDForTier(professionData, tierSkillLineID)
	local breakdown = self:ComputeSpecBreakdownForRecipe(recipeSpellID, catalog, nodeRanks, configID)
	if not breakdown then
		return
	end
	breakdown.recipeID = self:GetRecipeExportID(recipeData) or tonumber(recipeKey)
	breakdown.recipeSpellID = recipeSpellID
	breakdown.expansionID = expansionID
	breakdown.profession = recipeProfession
	breakdown.tierSkillLineID = tierSkillLineID
	recipeData.specBreakdown = breakdown
	if type(recipeData.crafting) == "table" then
		local skill = breakdown.totals and breakdown.totals.skill or 0
		recipeData.crafting.specSkillFromCatalog = skill
		recipeData.crafting.bonusSkillFromCatalog = skill
	end
end

function AuctionHelper:AttachSpecCatalogMetadata(professionData, baseSkillLineID)
	if type(professionData) ~= "table" then
		return professionData
	end

	local ranksByTier = self:BuildSpecNodeRanksFromSpecializationTree(professionData.specializationTrees or {})
	if professionData.specializationTree and not next(ranksByTier) then
		ranksByTier = self:BuildSpecNodeRanksFromSpecializationTree(professionData.specializationTree)
	end
	professionData.specNodeRanksByTier = ranksByTier
	local primaryKey = professionData.primarySpecializationSkillLineID
		and tostring(professionData.primarySpecializationSkillLineID) or nil
	professionData.specNodeRanks = (primaryKey and ranksByTier[primaryKey]) or {}

	local catalogsUsed = collectCatalogsUsed(self, professionForBaseSkillLine(self, tonumber(baseSkillLineID)), ranksByTier)
	professionData.specCatalog = {
		available = next(catalogsUsed) ~= nil,
		version = self.SPEC_CATALOG_VERSION,
		byTier = catalogsUsed,
	}

	local captureBreakdown = self:GetSetting("capture.specBreakdownPerRecipe", true) ~= false
	if not captureBreakdown or type(professionData.recipes) ~= "table" then
		return professionData
	end
	for recipeKey, recipeData in pairs(professionData.recipes) do
		attachRecipeSpecBreakdown(self, professionData, recipeKey, recipeData, baseSkillLineID)
	end
	return professionData
end

function AuctionHelper:BuildSpecCatalogExport(expansionID)
	self:InitSpecCatalogStore()
	expansionID = tonumber(expansionID) or self.EXPANSION_ID_MIDNIGHT
	local byProf = self._specCatalog[expansionID]
	if type(byProf) ~= "table" then
		return nil
	end
	local out = {
		catalogVersion = self.SPEC_CATALOG_VERSION,
		expansionID = expansionID,
		professions = {},
	}
	for profession, catalog in pairs(byProf) do
		out.professions[tostring(profession)] = {
			profession = profession,
			expansionID = expansionID,
			recipeMapping = catalog.recipeMapping,
			nodeData = catalog.nodeData,
		}
	end
	return out
end
