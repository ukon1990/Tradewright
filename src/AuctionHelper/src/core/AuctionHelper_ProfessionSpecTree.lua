-- Profession specialization trees: which skill lines have a spec config and the full tab, node and entry dump.
local _, AuctionHelper = ...

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
