local addonName, ProfessionExporter = ...

local LEGACY_SETTING_PATHS_BY_ROOT = {
	lastActiveTab = "general.lastActiveTab",
	showMinimapButton = "general.showMinimapButton",
	themePreset = "appearance.themePreset",
	windowScale = "appearance.windowScale",
	accentColor = "appearance.accentColor",
	surfaceTint = "appearance.surfaceTint",
	reducedOrnament = "appearance.reducedOrnament",
	captureSpecializationTree = "capture.captureSpecializationTree",
	specBreakdownPerRecipe = "capture.specBreakdownPerRecipe",
	includeRecipeOutputItemData = "capture.includeRecipeOutputItemData",
	inventorySnapshotBatchSize = "capture.inventorySnapshotBatchSize",
	economyShowColumns = "inventory.economyShowColumns",
	economyShowMatCost = "inventory.economyShowMatCost",
	economyShowSaleRate = "inventory.economyShowSaleRate",
	minimapButtonAngle = "integrations.minimapButtonAngle",
	economyUseAuctionatorFallback = "integrations.economyUseAuctionatorFallback",
	economyTSMMarketString = "integrations.economyTSMMarketString",
	economyTSMMatString = "integrations.economyTSMMatString",
	economyTSMSaleRateString = "integrations.economyTSMSaleRateString",
	debugEnabled = "debug.enabled",
}

local LEGACY_SETTING_ROOTS_BY_PATH = {}
for rootKey, path in pairs(LEGACY_SETTING_PATHS_BY_ROOT) do
	LEGACY_SETTING_ROOTS_BY_PATH[path] = rootKey
end

local function seedNestedSetting(st, rootKey, groupTable, nestedKey, defaultValue)
	if groupTable[nestedKey] == nil then
		if st[rootKey] ~= nil then
			groupTable[nestedKey] = st[rootKey]
		else
			groupTable[nestedKey] = defaultValue
		end
	end
	if st[rootKey] == nil then
		st[rootKey] = groupTable[nestedKey]
	end
end

function ProfessionExporter:GetLegacySettingRootKey(path)
	return LEGACY_SETTING_ROOTS_BY_PATH[tostring(path or "")]
end

function ProfessionExporter:SyncLegacySettingAlias(path, value)
	local rootKey = self:GetLegacySettingRootKey(path)
	if not rootKey then
		return
	end
	local settings = self.db and self.db.settings
	if type(settings) == "table" then
		settings[rootKey] = value
	end
end

local function currentExpansionTag()
	local iface = tonumber((select(4, GetBuildInfo()))) or 0
	return iface >= 120000 and "midnight" or iface >= 110200 and "tww" or iface >= 100000 and "df" or "legacy"
end

function ProfessionExporter:BuildMergedRuntimeDB(baseDb, professionsDb, inventoryDb, auctionDb)
	return {
		schemaVersion = self.SCHEMA_VERSION,
		addonVersion = self.VERSION,
		meta = baseDb.meta,
		settings = baseDb.settings,
		characters = professionsDb.characters,
		aggregate = professionsDb.aggregate,
		history = professionsDb.history,
		craftQueue = professionsDb.craftQueue,
		craftingOrderWorkQueue = professionsDb.craftingOrderWorkQueue,
		itemHistory = inventoryDb.itemHistory,
		walletHistory = inventoryDb.walletHistory,
		ledger = inventoryDb.ledger,
		auction = auctionDb.auction,
	}
end

function ProfessionExporter:RunLegacyMigrationIfNeeded(baseDb, professionsDb, inventoryDb, auctionDb)
	AuctionHelperMigrationDB = AuctionHelperMigrationDB or {}
	local migration = AuctionHelperMigrationDB
	if migration.professionExporterImported == true then
		return false
	end
	if type(ProfessionExporterDB) ~= "table" and type(ProfessionExporterLastExport) ~= "table" then
		return false
	end

	local legacyDb = type(ProfessionExporterDB) == "table" and ProfessionExporterDB or nil
	local legacyExport = type(ProfessionExporterLastExport) == "table" and ProfessionExporterLastExport or nil
	if legacyDb then
		if next(baseDb.settings or {}) == nil and type(legacyDb.settings) == "table" then
			baseDb.settings = legacyDb.settings
		end
		baseDb.meta = baseDb.meta or {}
		if type(legacyDb.meta) == "table" then
			for k, v in pairs(legacyDb.meta) do
				baseDb.meta[k] = v
			end
		end
		if next(professionsDb.characters or {}) == nil and type(legacyDb.characters) == "table" then
			professionsDb.characters = legacyDb.characters
		end
		if next(professionsDb.aggregate or {}) == nil and type(legacyDb.aggregate) == "table" then
			professionsDb.aggregate = legacyDb.aggregate
		end
		if next(professionsDb.history or {}) == nil and type(legacyDb.history) == "table" then
			professionsDb.history = legacyDb.history
		end
		if next(professionsDb.craftQueue or {}) == nil and type(legacyDb.craftQueue) == "table" then
			professionsDb.craftQueue = legacyDb.craftQueue
		end
		if next(professionsDb.craftingOrderWorkQueue or {}) == nil and type(legacyDb.craftingOrderWorkQueue) == "table" then
			professionsDb.craftingOrderWorkQueue = legacyDb.craftingOrderWorkQueue
		end
		if next(inventoryDb.itemHistory or {}) == nil and type(legacyDb.itemHistory) == "table" then
			inventoryDb.itemHistory = legacyDb.itemHistory
		end
		if next(inventoryDb.walletHistory or {}) == nil and type(legacyDb.walletHistory) == "table" then
			inventoryDb.walletHistory = legacyDb.walletHistory
		end
		if next(inventoryDb.ledger or {}) == nil and type(legacyDb.ledger) == "table" then
			inventoryDb.ledger = legacyDb.ledger
		end
		if type(legacyDb.auction) == "table" and next(auctionDb.auction or {}) == nil then
			auctionDb.auction = legacyDb.auction
		end
	end
	if legacyExport then
		AuctionHelperLastExport = AuctionHelperLastExport or {}
		for k, v in pairs(legacyExport) do
			AuctionHelperLastExport[k] = v
		end
		if AuctionHelperLastExport.json and not AuctionHelperLastExport.payload then
			AuctionHelperLastExport.payload = AuctionHelperLastExport.json
			AuctionHelperLastExport.format = AuctionHelperLastExport.format or "legacy-json"
		end
	end
	migration.professionExporterImported = true
	migration.importedAt = time()
	migration.importedSchemaVersion = self.SCHEMA_VERSION
	ProfessionExporterDB = nil
	ProfessionExporterLastExport = nil
	return true
end

function ProfessionExporter:InitDB()
	AuctionHelperDB = AuctionHelperDB or {}
	AuctionHelperMigrationDB = AuctionHelperMigrationDB or {}
	AuctionHelperProfessionsDB = AuctionHelperProfessionsDB or {}
	AuctionHelperInventoryDB = AuctionHelperInventoryDB or {}
	AuctionHelperAuctionDB = AuctionHelperAuctionDB or {}
	AuctionHelperLastExport = AuctionHelperLastExport or {}

	local baseDb = AuctionHelperDB
	local professionsDb = AuctionHelperProfessionsDB
	local inventoryDb = AuctionHelperInventoryDB
	local auctionDb = AuctionHelperAuctionDB
	local previousSchemaVersion = tonumber(baseDb.schemaVersion) or 0
	local needsStorageCompaction = previousSchemaVersion < self.SCHEMA_VERSION

	baseDb.schemaVersion = self.SCHEMA_VERSION
	baseDb.addonVersion = self.VERSION
	baseDb.meta = baseDb.meta or {}
	baseDb.settings = baseDb.settings or {}

	professionsDb.schemaVersion = self.SCHEMA_VERSION
	professionsDb.addonVersion = self.VERSION
	professionsDb.characters = professionsDb.characters or {}
	professionsDb.aggregate = professionsDb.aggregate or {}
	professionsDb.history = professionsDb.history or {}
	professionsDb.craftQueue = professionsDb.craftQueue or {}
	professionsDb.craftingOrderWorkQueue = professionsDb.craftingOrderWorkQueue or {}

	inventoryDb.schemaVersion = self.SCHEMA_VERSION
	inventoryDb.addonVersion = self.VERSION
	inventoryDb.itemHistory = inventoryDb.itemHistory or {}
	inventoryDb.walletHistory = inventoryDb.walletHistory or {}
	inventoryDb.ledger = inventoryDb.ledger or {}

	auctionDb.schemaVersion = self.SCHEMA_VERSION
	auctionDb.addonVersion = self.VERSION
	auctionDb.auction = auctionDb.auction or {}

	self:RunLegacyMigrationIfNeeded(baseDb, professionsDb, inventoryDb, auctionDb)

	self.baseDb = baseDb
	self.professionsDb = professionsDb
	self.inventoryDb = inventoryDb
	self.auctionStorageDb = auctionDb
	self.db = self:BuildMergedRuntimeDB(baseDb, professionsDb, inventoryDb, auctionDb)

	local st = self.db.settings
	st.general = st.general or {}
	st.appearance = st.appearance or {}
	st.capture = st.capture or {}
	st.inventory = st.inventory or {}
	st.integrations = st.integrations or {}
	st.debug = st.debug or {}
	st.auction = st.auction or {}

	local general = st.general
	local appearance = st.appearance
	local capture = st.capture
	local inventory = st.inventory
	local integrations = st.integrations
	local debug = st.debug
	local auctionSettings = st.auction

	seedNestedSetting(st, "lastActiveTab", general, "lastActiveTab", "overview")
	seedNestedSetting(st, "showMinimapButton", general, "showMinimapButton", true)
	seedNestedSetting(st, "themePreset", appearance, "themePreset", "slate")
	seedNestedSetting(st, "windowScale", appearance, "windowScale", 1)
	seedNestedSetting(st, "accentColor", appearance, "accentColor", { r = 0.24, g = 0.66, b = 0.74 })
	seedNestedSetting(st, "surfaceTint", appearance, "surfaceTint", { r = 0.10, g = 0.12, b = 0.16 })
	seedNestedSetting(st, "reducedOrnament", appearance, "reducedOrnament", false)
	seedNestedSetting(st, "captureSpecializationTree", capture, "captureSpecializationTree", true)
	seedNestedSetting(st, "includeRecipeOutputItemData", capture, "includeRecipeOutputItemData", false)
	seedNestedSetting(st, "inventorySnapshotBatchSize", capture, "inventorySnapshotBatchSize", 0)
	seedNestedSetting(st, "economyShowColumns", inventory, "economyShowColumns", true)
	seedNestedSetting(st, "economyShowMatCost", inventory, "economyShowMatCost", true)
	seedNestedSetting(st, "economyShowSaleRate", inventory, "economyShowSaleRate", true)
	inventory.metricRange = inventory.metricRange or "30d"
	inventory.columnOrder = inventory.columnOrder or {}
	inventory.hiddenColumns = inventory.hiddenColumns or {}
	if inventory.detailsOpen == nil then inventory.detailsOpen = true end
	if inventory.detailsWidth == nil then inventory.detailsWidth = 340 end
	if inventory.detailsGraphMetric == nil then inventory.detailsGraphMetric = "market" end
	if inventory.detailsGraphShowQuantity == nil then inventory.detailsGraphShowQuantity = true end
	if inventory.historyRetentionDays == nil then inventory.historyRetentionDays = 30 end
	if inventory.selectedExpansions == nil then inventory.selectedExpansions = { [currentExpansionTag()] = true } end

	st.overview = st.overview or {}
	if st.overview.walletGraphMetric == nil then st.overview.walletGraphMetric = "balance" end

	st.crafts = st.crafts or {}
	local crafts = st.crafts
	if crafts.detailsOpen == nil then crafts.detailsOpen = true end
	if crafts.detailsWidth == nil then crafts.detailsWidth = 340 end
	if crafts.detailsGraphMetric == nil then crafts.detailsGraphMetric = "market" end
	if crafts.detailsGraphShowQuantity == nil then crafts.detailsGraphShowQuantity = true end
	if crafts.defaultExpansionMode == nil then crafts.defaultExpansionMode = "current" end
	if crafts.scenario == nil then crafts.scenario = "default" end
	if crafts.reagentSourceMode == nil then crafts.reagentSourceMode = "owned_first" end
	if crafts.profitState == nil then crafts.profitState = "all" end
	if crafts.costBasis == nil then crafts.costBasis = "auto" end
	if crafts.saleBasis == nil then crafts.saleBasis = "auto" end
	if crafts.sortColumn == nil then crafts.sortColumn = "profit" end
	if crafts.sortAsc == nil then crafts.sortAsc = false end
	if crafts.ahCutPercent == nil then crafts.ahCutPercent = 5 end
	if crafts.selectedExpansions == nil then crafts.selectedExpansions = { [currentExpansionTag()] = true } end
	crafts.characterFilter = crafts.characterFilter or {}
	crafts.professionFilter = crafts.professionFilter or {}
	crafts.categoryFilter = crafts.categoryFilter or {}

	st.craftingOrders = st.craftingOrders or {}
	local craftingOrders = st.craftingOrders
	if craftingOrders.hideUnlearned == nil then craftingOrders.hideUnlearned = false end
	if craftingOrders.patronKnowledgeOnly == nil then craftingOrders.patronKnowledgeOnly = false end

	seedNestedSetting(st, "minimapButtonAngle", integrations, "minimapButtonAngle", 225)
	seedNestedSetting(st, "economyUseAuctionatorFallback", integrations, "economyUseAuctionatorFallback", true)
	seedNestedSetting(st, "economyTSMMarketString", integrations, "economyTSMMarketString", "dbmarket")
	seedNestedSetting(st, "economyTSMFallbackString", integrations, "economyTSMFallbackString", "DBMinBuyout")
	seedNestedSetting(st, "economyTSMMatString", integrations, "economyTSMMatString", "Crafting")
	seedNestedSetting(st, "economyTSMSaleRateString", integrations, "economyTSMSaleRateString", "DBRegionSaleRate")

	seedNestedSetting(st, "debugEnabled", debug, "enabled", false)
	if debug.persistToSavedVariables == nil then debug.persistToSavedVariables = false end
	debug.lines = debug.lines or {}
	if debug.maxLines == nil then debug.maxLines = 100 end
	if general.persistLastExport == nil then general.persistLastExport = true end

	if auctionSettings.enabled == nil then auctionSettings.enabled = true end
	if auctionSettings.sellPanelEnabled == nil then auctionSettings.sellPanelEnabled = true end
	if auctionSettings.tabEnabled == nil then auctionSettings.tabEnabled = true end
	if auctionSettings.minMarginPercent == nil then auctionSettings.minMarginPercent = 5 end
	if auctionSettings.minMarginCopper == nil then auctionSettings.minMarginCopper = 100 end
	if auctionSettings.historyRetentionDays == nil then auctionSettings.historyRetentionDays = 14 end
	if auctionSettings.visibleRefreshThrottleMs == nil then auctionSettings.visibleRefreshThrottleMs = 150 end
	if auctionSettings.dumpBatchSize == nil then auctionSettings.dumpBatchSize = 50 end
	if auctionSettings.priceFreshnessMinutes == nil then auctionSettings.priceFreshnessMinutes = 15 end
	if auctionSettings.autoCraftEconomyRefreshOnOpen == nil then auctionSettings.autoCraftEconomyRefreshOnOpen = false end
	if auctionSettings.craftScanIncludeOptionalSlots == nil then auctionSettings.craftScanIncludeOptionalSlots = false end
	if auctionSettings.selectedExpansions == nil then auctionSettings.selectedExpansions = { [currentExpansionTag()] = true } end

	local auction = self.InitAuctionDB and self:InitAuctionDB() or nil
	if auction then
		auction.settings = auction.settings or {}
		auction.settings.enabled = auctionSettings.enabled
		auction.settings.sellPanelEnabled = auctionSettings.sellPanelEnabled
		auction.settings.tabEnabled = auctionSettings.tabEnabled
		auction.settings.minMarginPercent = auctionSettings.minMarginPercent
		auction.settings.minMarginCopper = auctionSettings.minMarginCopper
		auction.settings.historyRetentionDays = auctionSettings.historyRetentionDays
		auction.settings.visibleRefreshThrottleMs = auctionSettings.visibleRefreshThrottleMs
		auction.settings.dumpBatchSize = auctionSettings.dumpBatchSize
		auction.settings.priceFreshnessMinutes = auctionSettings.priceFreshnessMinutes
		auction.settings.autoCraftEconomyRefreshOnOpen = auctionSettings.autoCraftEconomyRefreshOnOpen
		auction.settings.craftScanIncludeOptionalSlots = auctionSettings.craftScanIncludeOptionalSlots
		auction.settings.selectedExpansions = auctionSettings.selectedExpansions
	end

	if ProfessionExporter.InitLedger then
		ProfessionExporter:InitLedger()
	end
	if needsStorageCompaction then
		self:CompactSavedVariablesStorage()
	end
end

function ProfessionExporter:CompactSavedVariablesStorage()
	if self.db and self.db.debug then
		self.db.debug.lines = {}
		self.db.debug.maxLines = math.max(20, math.min(100, tonumber(self.db.debug.maxLines) or 100))
	end
	if self.CompactAuctionStorageData then
		self:CompactAuctionStorageData()
	end
	if self.CompactItemHistoryStorage then
		self:CompactItemHistoryStorage()
	end
	if self.baseDb and self.baseDb.meta then
		self.baseDb.meta.storageCompactedAt = time()
		self.baseDb.meta.storageCompactedSchema = self.SCHEMA_VERSION
	end
end

function ProfessionExporter:GetState()
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

function ProfessionExporter:BumpDataRevision()
	local s = self:GetState()
	s.dataRevision = (s.dataRevision or 0) + 1
end

function ProfessionExporter:AggregateNeedsRebuild()
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

function ProfessionExporter:GetCharacterMetadata()
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

function ProfessionExporter:GetPlayerProfessions()
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

function ProfessionExporter:CreateCharacterScanRecord()
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

function ProfessionExporter:SnapshotFilters()
	return {
		showUnlearned = C_TradeSkillUI.GetShowUnlearned and C_TradeSkillUI.GetShowUnlearned() or nil,
		onlyShowMakeable = C_TradeSkillUI.GetOnlyShowMakeableRecipes and C_TradeSkillUI.GetOnlyShowMakeableRecipes() or nil,
		onlyShowSkillUp = C_TradeSkillUI.GetOnlyShowSkillUpRecipes and C_TradeSkillUI.GetOnlyShowSkillUpRecipes() or nil,
		recipeItemNameFilter = C_TradeSkillUI.GetRecipeItemNameFilter and C_TradeSkillUI.GetRecipeItemNameFilter() or nil,
		itemLevelFilter = C_TradeSkillUI.GetRecipeItemLevelFilter and { C_TradeSkillUI.GetRecipeItemLevelFilter() } or nil,
	}
end

function ProfessionExporter:ApplyExportFilters()
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

function ProfessionExporter:RestoreFilters(snapshot)
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

function ProfessionExporter:GetQualityThresholds(maxQuality, recipeDifficulty)
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

function ProfessionExporter:BuildMaxQualityRequiredReagentInfo(schematic)
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

function ProfessionExporter:DescribeOperationInfo(recipeID, schematic)
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

function ProfessionExporter:DescribeRecipeOutput(recipeID, recipeInfo, schematic)
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

function ProfessionExporter:DescribeReagentSlot(reagentSlotSchematic, slotIndex)
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

function ProfessionExporter:CollectRecipeCategories()
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

function ProfessionExporter:SkillLineHasSpecializationConfig(skillLineID)
	skillLineID = tonumber(skillLineID)
	if not skillLineID or skillLineID <= 0 or not C_ProfSpecs or not C_ProfSpecs.GetConfigIDForSkillLine then
		return false
	end
	local configID = C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)
	return configID and configID > 0
end

--- Expansion-tier skill lines from recipe category headers (e.g. Midnight Mining = 2916, not base 186).
function ProfessionExporter:ExtractExpansionSkillLineIDsFromCategories(categories, baseSkillLineID)
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
function ProfessionExporter:ResolveProfessionSpecSkillLineIDs(baseSkillLineID, childInfo, categories)
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

function ProfessionExporter:PickPrimarySpecializationSkillLineID(candidates, currentLevelName, childInfo)
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

function ProfessionExporter:ExtractPerkIDFromApiValue(perkValue)
	if type(perkValue) == "table" then
		return tonumber(perkValue.perkID)
	end
	return tonumber(perkValue)
end

function ProfessionExporter:ResolveSpecEntryName(definitionInfo, pathDescription)
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

function ProfessionExporter:ResolveSpecEntryDescription(definitionInfo, perkDescription, pathDescription)
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

function ProfessionExporter:ClassifySpecNodeKind(nodeInfo)
	local maxRanks = tonumber(nodeInfo and (nodeInfo.maxRanks or nodeInfo.totalMaxRanks)) or 1
	return maxRanks > 1 and "path" or "milestone"
end

function ProfessionExporter:FinalizeSpecializationTabGraph(tab)
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
		if type(nodeRecord) ~= "table" then
			-- skip
		elseif nodeRecord.nodeKind == "path" then
			pathByID[nodeRecord.nodeID] = nodeRecord
			paths[#paths + 1] = nodeRecord
		elseif nodeRecord.nodeKind == "milestone" then
			nodeRecord.childPathIDs = nil
			milestoneByID[nodeRecord.nodeID] = nodeRecord
			milestones[#milestones + 1] = nodeRecord
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

function ProfessionExporter:CollectSpecializationTreeForSkillLine(skillLineID)
	skillLineID = tonumber(skillLineID)
	if not skillLineID or skillLineID <= 0 or not self:SkillLineHasSpecializationConfig(skillLineID) then
		return nil
	end

	local configID = C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)
	if not configID or configID <= 0 then
		return nil
	end

	local specializationSkillLineID = skillLineID
	local variantInfo = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
		and C_TradeSkillUI.GetProfessionInfoBySkillLineID(specializationSkillLineID) or nil
	local expansionID = nil
	if self.ResolveSpecCatalogForTierSkillLine then
		expansionID = self:ResolveSpecCatalogForTierSkillLine(specializationSkillLineID)
	end

	local configInfo = C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID) or nil
	local treeIDs = configInfo and self:ShallowArrayCopy(configInfo.treeIDs) or {}
	local result = {
		configID = configID,
		skillLineID = specializationSkillLineID,
		tierName = variantInfo and variantInfo.professionName or nil,
		expansionID = expansionID,
		parentProfessionID = variantInfo and variantInfo.parentProfessionID or nil,
		configInfo = self:SanitizeValue(configInfo),
		treeIDs = treeIDs,
		tabs = {},
		unspentKnowledge = nil,
	}

	local currencyInfo = C_ProfSpecs.GetCurrencyInfoForSkillLine and C_ProfSpecs.GetCurrencyInfoForSkillLine(specializationSkillLineID) or nil
	result.unspentKnowledge = self:SanitizeValue(currencyInfo)

	for _, treeID in ipairs(treeIDs) do
		local tabInfo = C_ProfSpecs.GetTabInfo and C_ProfSpecs.GetTabInfo(treeID) or nil
		local tabState = C_ProfSpecs.GetStateForTab and C_ProfSpecs.GetStateForTab(treeID, configID) or nil
		local nodeIDs = C_Traits.GetTreeNodes and (C_Traits.GetTreeNodes(treeID) or {}) or {}
		local tab = {
			treeID = treeID,
			rootPathID = C_ProfSpecs.GetRootPathForTab and self:SafeCall(C_ProfSpecs.GetRootPathForTab, treeID) or nil,
			tabInfo = self:SanitizeValue(tabInfo),
			state = tabState,
			nodes = {},
		}

		for _, nodeID in ipairs(nodeIDs) do
			local nodeInfo = C_Traits.GetNodeInfo and C_Traits.GetNodeInfo(configID, nodeID) or nil
			local pathDescription = C_ProfSpecs.GetDescriptionForPath and self:SafeCall(C_ProfSpecs.GetDescriptionForPath, nodeID) or nil
			local nodeKind = self:ClassifySpecNodeKind(nodeInfo)
			local nodeRecord = {
				nodeID = nodeID,
				nodeKind = nodeKind,
				childPathIDs = nodeKind == "path" and C_ProfSpecs.GetChildrenForPath
					and self:SanitizeValue(self:SafeCall(C_ProfSpecs.GetChildrenForPath, nodeID)) or nil,
				nodeInfo = self:SanitizeValue(nodeInfo),
				pathDescription = pathDescription,
				unlockRank = C_ProfSpecs.GetUnlockRankForPerk and self:SafeCall(C_ProfSpecs.GetUnlockRankForPerk, nodeID) or nil,
				entries = {},
			}

			local entryIDs = nodeInfo and nodeInfo.entryIDs or nil
			local perkIDsForPath = C_ProfSpecs.GetPerksForPath and self:SafeCall(C_ProfSpecs.GetPerksForPath, nodeID) or nil
			if type(entryIDs) == "table" then
				for entryIndex, entryID in ipairs(entryIDs) do
					local entryInfo = C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID, entryID) or nil
					local definitionInfo = entryInfo and C_Traits.GetDefinitionInfo and C_Traits.GetDefinitionInfo(entryInfo.definitionID) or nil
					local perkID = self:ExtractPerkIDFromApiValue(perkIDsForPath and perkIDsForPath[entryIndex] or nil)
					local perkDescription = perkID and C_ProfSpecs.GetDescriptionForPerk
						and self:SafeCall(C_ProfSpecs.GetDescriptionForPerk, perkID) or nil
					table.insert(nodeRecord.entries, {
						entryID = entryID,
						perkID = perkID,
						entryInfo = self:SanitizeValue(entryInfo),
						definitionInfo = self:SanitizeValue(definitionInfo),
						perkDescription = perkDescription,
						unlockRank = perkID and C_ProfSpecs.GetUnlockRankForPerk
							and self:SafeCall(C_ProfSpecs.GetUnlockRankForPerk, perkID)
							or (C_ProfSpecs.GetUnlockRankForPerk and self:SafeCall(C_ProfSpecs.GetUnlockRankForPerk, entryID) or nil),
					})
					if not nodeRecord.nodeName then
						nodeRecord.nodeName = self:ResolveSpecEntryName(definitionInfo, pathDescription)
					end
					if not nodeRecord.nodeDescription then
						nodeRecord.nodeDescription = self:ResolveSpecEntryDescription(definitionInfo, perkDescription, pathDescription)
					end
				end
			end
			if nodeKind == "milestone" then
				nodeRecord.milestoneRank = nodeRecord.unlockRank
			end

			table.insert(tab.nodes, nodeRecord)
		end

		self:FinalizeSpecializationTabGraph(tab)
		table.insert(result.tabs, tab)
	end

	return result
end

--- Backwards-compatible wrapper; prefer CollectSpecializationTreesForProfession during scans.
function ProfessionExporter:CollectSpecializationTree(skillLineID, fallbackSkillLineID)
	local candidates = {}
	if tonumber(skillLineID) and self:SkillLineHasSpecializationConfig(skillLineID) then
		table.insert(candidates, tonumber(skillLineID))
	end
	if tonumber(fallbackSkillLineID) and self:SkillLineHasSpecializationConfig(fallbackSkillLineID) then
		local fallback = tonumber(fallbackSkillLineID)
		local found = false
		for _, sid in ipairs(candidates) do
			if sid == fallback then
				found = true
				break
			end
		end
		if not found then
			table.insert(candidates, fallback)
		end
	end
	for _, sid in ipairs(candidates) do
		local tree = self:CollectSpecializationTreeForSkillLine(sid)
		if tree then
			return tree
		end
	end
	return nil
end

--- Full specialization dump keyed by expansion variant skill line (tostring(skillLineID)).
function ProfessionExporter:CollectSpecializationTreesForProfession(baseSkillLineID, childInfo, categories, currentLevelName)
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
		for _, tree in pairs(bySkillLineID) do
			primary = tree
			primarySkillLineID = tree.skillLineID
			break
		end
	end

	self:DebugLog("SCAN", "CollectSpecializationTreesForProfession captured", {
		string.format("baseSkillLineID=%s tierCount=%d primarySkillLineID=%s", tostring(baseSkillLineID), self:TableCount(bySkillLineID), tostring(primarySkillLineID)),
	})

	return {
		primarySkillLineID = primarySkillLineID,
		primary = primary,
		bySkillLineID = bySkillLineID,
	}
end

function ProfessionExporter:CollectClassicRecipeReagentSlots(recipeSpellID)
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
			local name, icon, reagentCount, playerCount, itemID = C_TradeSkillUI.GetRecipeReagentInfo(recipeSpellID, i)
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
				local reagentName, reagentTexture, reagentCount = GetTradeSkillReagentInfo(skillIndex, i)
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

function ProfessionExporter:CollectRecipeData(recipeSpellID)
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

function ProfessionExporter:BeginProfessionCollectCaches()
	self._itemDescCache = {}
	self._currencyDescCache = {}
	self._includeRecipeOutputItemData = self:GetSetting("capture.includeRecipeOutputItemData", false) == true
end

function ProfessionExporter:EndProfessionCollectCaches()
	self._itemDescCache = nil
	self._currencyDescCache = nil
	self._includeRecipeOutputItemData = nil
end

--- Rebuild recipeIDs array + recipeCount from the recipes map.
function ProfessionExporter:RebuildProfessionRecipeIndex(professionData)
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
function ProfessionExporter:CollectRecipesIntoProfessionData(professionData, recipeSpellIDs, fromIndex, toIndex)
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
function ProfessionExporter:PruneProfessionRecipesNotInSpellSet(professionData, spellIDSet)
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

function ProfessionExporter:StampProfessionLiveFingerprint(professionData, fingerprintInfo)
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

function ProfessionExporter:UpdateProfessionDescriptorFields(professionData, professionDescriptor, baseInfo, childInfo)
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

function ProfessionExporter:ApplySpecializationResultToProfessionData(professionData, specResult)
	if not professionData then
		return
	end
	professionData.specializationTree = specResult and specResult.primary or nil
	professionData.specializationTrees = specResult and specResult.bySkillLineID or nil
	professionData.primarySpecializationSkillLineID = specResult and specResult.primarySkillLineID or nil
end

--- Finalize indexes, optional catalog attach, and live fingerprint stamp.
function ProfessionExporter:FinalizeProfessionDataCollect(professionData, professionDescriptor, fingerprintInfo)
	self:RebuildProfessionRecipeIndex(professionData)
	if self.AttachSpecCatalogMetadata and professionDescriptor then
		self:AttachSpecCatalogMetadata(professionData, professionDescriptor.skillLineID)
	end
	self:StampProfessionLiveFingerprint(professionData, fingerprintInfo)
	return professionData
end

function ProfessionExporter:CollectCurrentProfessionData(professionDescriptor)
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
function ProfessionExporter:CreateProfessionDataShell(professionDescriptor, opts)
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

function ProfessionExporter:PatchAggregateInventorySummaryForCharacter(characterKey, characterData)
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

function ProfessionExporter:BuildAggregate()
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
function ProfessionExporter:GetCharacterExportHeader(characterData)
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
function ProfessionExporter:ProfessionExportSliceProfession(prof, slice)
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

function ProfessionExporter:MapProfessionsExportSlice(professionsMap, slice)
	local out = {}
	for sid, prof in pairs(professionsMap or {}) do
		out[sid] = self:ProfessionExportSliceProfession(prof, slice)
	end
	return out
end

function ProfessionExporter:GetCompactCharacterHeader(characterData)
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

function ProfessionExporter:BuildCompactInventorySnapshot(snapshot)
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

function ProfessionExporter:BuildCompactRecipeRecord(recipeID, recipeData)
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

function ProfessionExporter:BuildCompactProfessionRecord(professionData)
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

function ProfessionExporter:BuildCompactProfessionsExport(characterData)
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

function ProfessionExporter:BuildCompactAuctionSnapshotExport()
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

function ProfessionExporter:BuildCompactAuctionHistoryExport()
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

function ProfessionExporter:BuildCompactCraftingCostsExport()
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

function ProfessionExporter:GetExportData(scope, identifier)
	self:InitDB()
	local characterKey = self:GetCharacterKey()
	scope = scope or "character"

	if scope == "account" then
		if self:AggregateNeedsRebuild() then
			self:BuildAggregate()
		end
		return {
			meta = {
				scope = "account",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
			},
			characters = self.db.characters,
			aggregate = self.db.aggregate,
		}
	end

	if scope == "account_summary" then
		if self:AggregateNeedsRebuild() then
			self:BuildAggregate()
		end
		return {
			meta = {
				scope = "account_summary",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
			},
			aggregate = self.db.aggregate,
		}
	end

	if scope == "auction_snapshot" then
		local snapshot, err = self:BuildCompactAuctionSnapshotExport()
		if not snapshot then
			return nil, err
		end
		return {
			meta = {
				scope = "auction_snapshot",
				module = "auction",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
			},
			keys = { "storageKey", "seenAt", "price", "source", "sampleSize" },
			snapshot = snapshot,
		}
	end

	if scope == "auction_history" then
		local historyRows, err = self:BuildCompactAuctionHistoryExport()
		if not historyRows then
			return nil, err
		end
		return {
			meta = {
				scope = "auction_history",
				module = "auction",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
			},
			keys = { "hourTs", "obsCount", "weightedQty", "weightedSum", "last", "min", "max", "lastSeenAt" },
			history = historyRows,
		}
	end

	if scope == "spec_catalog" or scope == "spec_catalog_midnight" then
		if not self.BuildSpecCatalogExport then
			return nil, "Spec catalog module not loaded. Enable AuctionHelper Professions."
		end
		local expansionID = scope == "spec_catalog_midnight" and (self.EXPANSION_ID_MIDNIGHT or 11) or (self.EXPANSION_ID_MIDNIGHT or 11)
		local catalog = self:BuildSpecCatalogExport(expansionID)
		if not catalog then
			return nil, "No bundled spec catalog for expansion " .. tostring(expansionID) .. "."
		end
		return {
			meta = {
				scope = "spec_catalog",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				expansionID = expansionID,
				catalogVersion = catalog.catalogVersion,
			},
			specCatalog = catalog,
		}
	end

	local characterData = self.db.characters[characterKey]
	if not characterData then
		return nil, "No scan data stored for this character yet. Run /auctionhelper scan first."
	end

	if scope == "professions" then
		return {
			meta = {
				scope = "professions",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
			},
			character = self:GetCharacterExportHeader(characterData),
			professions = characterData.professions or {},
		}
	end

	if scope == "professions_recipes" then
		return {
			meta = {
				scope = "professions_recipes",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
			},
			character = self:GetCharacterExportHeader(characterData),
			professions = self:MapProfessionsExportSlice(characterData.professions or {}, "recipes"),
		}
	end

	if scope == "professions_talents" then
		return {
			meta = {
				scope = "professions_talents",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
			},
			character = self:GetCharacterExportHeader(characterData),
			professions = self:MapProfessionsExportSlice(characterData.professions or {}, "talents"),
		}
	end

	if scope == "inventory" then
		return {
			meta = {
				scope = "inventory",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
			},
			character = self:GetCharacterExportHeader(characterData),
			inventorySnapshot = characterData.inventorySnapshot,
		}
	end

	if scope == "inventory_compact" then
		return {
			meta = {
				scope = "inventory_compact",
				module = "inventory",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
			},
			keys = { "itemID", "bags", "bank", "warband", "total" },
			character = self:GetCompactCharacterHeader(characterData),
			inventory = self:BuildCompactInventorySnapshot(characterData.inventorySnapshot),
		}
	end

	if scope == "professions_compact" then
		return {
			meta = {
				scope = "professions_compact",
				module = "professions",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
			},
			keys = {
				profession = { "sid", "name", "skillLevel", "maxSkillLevel", "bonusSkill", "recipeCount", "recipes" },
				recipe = { "recipeID", "learned", "relativeDifficulty", "categoryID", "output", "outputVariants", "slots" },
				slot = { "slotIndex", "quantity", "optional", "reagents" },
			},
			character = self:GetCompactCharacterHeader(characterData),
			professions = self:BuildCompactProfessionsExport(characterData),
		}
	end

	if scope == "crafting_costs" then
		local rows, err = self:BuildCompactCraftingCostsExport()
		if not rows then
			return nil, err
		end
		return {
			meta = {
				scope = "crafting_costs",
				module = "professions",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
			},
			keys = { "recipeID", "outputItemID", "recipeName", "outputName", "skillLineID", "professionName", "bestCharacterKey", "matCost", "saleNet", "profit", "roi", "outputQty", "qualityIndex", "confidence", "badges" },
			rows = rows,
		}
	end

	if scope == "character_meta" then
		return {
			meta = {
				scope = "character_meta",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
			},
			character = self:GetCharacterExportHeader(characterData),
		}
	end

	if scope == "profession" then
		local professions = {}
		for _, professionData in pairs(characterData.professions or {}) do
			table.insert(professions, professionData)
		end
		local profession = self:FindProfessionByIdentifier(professions, identifier)
		if not profession then
			return nil, "Unknown profession identifier. Use a skill line ID or exact profession name."
		end
		return {
			meta = {
				scope = "profession",
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
				professionIdentifier = identifier,
			},
			character = characterData.meta,
			profession = profession,
		}
	end

	if scope == "profession_recipes" or scope == "profession_talents" then
		local professions = {}
		for _, professionData in pairs(characterData.professions or {}) do
			table.insert(professions, professionData)
		end
		local profession = self:FindProfessionByIdentifier(professions, identifier)
		if not profession then
			return nil, "Unknown profession identifier. Use a skill line ID or exact profession name."
		end
		local slice = scope == "profession_recipes" and "recipes" or "talents"
		return {
			meta = {
				scope = scope,
				generatedAt = time(),
				addonVersion = self.VERSION,
				schemaVersion = self.SCHEMA_VERSION,
				characterKey = characterKey,
				professionIdentifier = identifier,
			},
			character = characterData.meta,
			profession = self:ProfessionExportSliceProfession(profession, slice),
		}
	end

	return {
		meta = {
			scope = "character",
			generatedAt = time(),
			addonVersion = self.VERSION,
			schemaVersion = self.SCHEMA_VERSION,
			characterKey = characterKey,
		},
		character = characterData,
	}
end

function ProfessionExporter:BuildPlainLuaExportPayload(exportData)
	local logic = self.ForeverLogic
	if logic and logic.BuildPlainLuaExportPayload then
		return logic.BuildPlainLuaExportPayload(exportData)
	end
	return nil, "ForeverLogic unavailable"
end

function ProfessionExporter:BuildCompactExportPayload(exportData)
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
function ProfessionExporter:SaveExportToSavedVariables(payload, meta)
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

function ProfessionExporter:CopyBoxBuildFooterText(opts, pagingEnvelope)
	if not opts then
		opts = {}
	end
	local parts = {}
	if pagingEnvelope then
		table.insert(parts, "|cffffffffPaged export:|r concatenate the payload fragments from page 1 through N in order. Each page starts with an AuctionHelper paging header.")
	end
	if opts.savedToVariables then
		table.insert(parts, "|cffffffffSavedVariables:|r full compressed payload queued — |cffffffff/reload|r or log out, then read |cffffffffWTF/Account/<account>/SavedVariables/AuctionHelper.lua|r (|cffffffffAuctionHelperLastExport.payload|r).")
	end
	if opts.unsavedHint and opts.unsavedHint ~= "" then
		table.insert(parts, opts.unsavedHint)
	end
	return table.concat(parts, "\n")
end

function ProfessionExporter:BuildCopyBoxPagedWrapperJson(pageIndex, pageCount, payloadFragment)
	return string.format("AHPAGE:%d/%d\n%s", pageIndex, pageCount, payloadFragment)
end

--- Build segment list: each { startPos, length } into fullJson; each wrapped page <= maxWrappedBytes.
--- Uses byte-length estimates in the binary search (no JsonEscape per probe), verifies with one Build per page.
--- Must run inside a coroutine; yields to spread work across frames.
function ProfessionExporter:ComputeCopyBoxPagingSegmentsYielding(fullJson, maxWrappedBytes)
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
		if best < 1 then
			best = 1
		end
		while best >= 1 do
			local frag = string.sub(fullJson, pos, pos + best - 1)
			if #self:BuildCopyBoxPagedWrapperJson(pageIdx, placeholder, frag) <= maxWrappedBytes then
				break
			end
			best = best - 1
		end
		if best < 1 then
			best = 1
		end
		table.insert(segments, { pos, best })
		pos = pos + best
		pageIdx = pageIdx + 1
	end
	return segments
end

--- Runs ComputeCopyBoxPagingSegmentsYielding via C_Timer (same pattern as RunEncodeJsonAsync).
function ProfessionExporter:RunComputeCopyBoxPagingAsync(fullJson, maxWrappedBytes, onComplete)
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

function ProfessionExporter:EncodeCopyBoxWrappedPage(fullJson, seg, pageIndex, totalPages)
	local frag = string.sub(fullJson, seg[1], seg[1] + seg[2] - 1)
	return self:BuildCopyBoxPagedWrapperJson(pageIndex, totalPages, frag)
end

function ProfessionExporter:LayoutCopyFrameScroll(copyFrame, useEnvelopePaging)
	local scroll = copyFrame.scrollFrame
	local hint = copyFrame.pageHintStr
	if not scroll or not hint then
		return
	end
	scroll:ClearAllPoints()
	if useEnvelopePaging then
		hint:Show()
		scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -2, -8)
		scroll:SetPoint("BOTTOMLEFT", copyFrame, "BOTTOMLEFT", 16, 92)
		scroll:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -32, 92)
	else
		hint:Hide()
		scroll:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 16, -46)
		scroll:SetPoint("BOTTOMLEFT", copyFrame, "BOTTOMLEFT", 16, 92)
		scroll:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -32, 92)
	end
end

function ProfessionExporter:CopyBoxApplyCurrentPage()
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
			cf.pageLabel:SetText(string.format("Page %d / %d  (AuctionHelper package)", p, numPages))
		else
			cf.pageLabel:SetText("Page 1 / 1")
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

function ProfessionExporter:CopyBoxGoPage(delta)
	local state = self:GetState()
	local cf = state.copyFrame
	if not cf or cf._pagingMode ~= "envelope" or not cf._segments or cf._numPages <= 1 then
		return
	end
	cf._pageIndex = math.max(1, math.min(cf._numPages, cf._pageIndex + delta))
	self:CopyBoxApplyCurrentPage()
end

--- opts: fullByteLength, savedToVariables, unsavedHint
function ProfessionExporter:ShowCopyBox(text, opts)
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
		footerText = self:CopyBoxBuildFooterText(opts, true)
	else
		numPages = 1
		pagingMode = "raw"
		footerText = self:CopyBoxBuildFooterText(opts, false)
	end

	if not copyFrame then
		--- BackdropTemplate only: DialogBoxFrame also spawns default OK/Cancel that overlapped our Close.
		copyFrame = CreateFrame("Frame", addonName .. "CopyFrame", UIParent, "BackdropTemplate")
		copyFrame:SetPoint("CENTER")
		copyFrame:SetSize(720, 560)
		copyFrame:SetFrameStrata("DIALOG")
		copyFrame:SetFrameLevel(200)
		copyFrame:SetBackdrop({
			bgFile = "Interface/ChatFrame/ChatFrameBackground",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true,
			tileSize = 8,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		copyFrame:SetBackdropColor(0.06, 0.06, 0.09, 0.98)
		copyFrame:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
		copyFrame:SetMovable(true)
		copyFrame:SetClampedToScreen(true)
		copyFrame:EnableMouse(true)
		copyFrame:RegisterForDrag("LeftButton")
		copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
		copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)

		local copyTitle = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		copyTitle:SetPoint("TOP", 0, -14)
		copyTitle:SetText("Export Package")
		copyFrame.copyTitle = copyTitle

		local closeX = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
		closeX:SetPoint("TOPRIGHT", -8, -8)
		closeX:SetScript("OnClick", function()
			copyFrame:Hide()
		end)
		copyFrame.closeXButton = closeX

		local pageHintStr = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		pageHintStr:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 16, -42)
		pageHintStr:SetPoint("TOPRIGHT", copyFrame, "TOPRIGHT", -40, -42)
		pageHintStr:SetJustifyH("LEFT")
		pageHintStr:SetWordWrap(true)
		copyFrame.pageHintStr = pageHintStr

		local footerStr = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		footerStr:SetPoint("BOTTOMLEFT", 18, 34)
		footerStr:SetPoint("BOTTOMRIGHT", -18, 34)
		footerStr:SetJustifyH("LEFT")
		footerStr:SetJustifyV("BOTTOM")
		footerStr:SetWordWrap(true)
		copyFrame.footerStr = footerStr

		local pageBar = CreateFrame("Frame", nil, copyFrame)
		pageBar:SetHeight(26)
		pageBar:SetPoint("BOTTOMLEFT", 14, 60)
		pageBar:SetPoint("BOTTOMRIGHT", -14, 60)
		copyFrame.pageBar = pageBar

		local btnPrev = CreateFrame("Button", nil, pageBar, "UIPanelButtonTemplate")
		btnPrev:SetSize(72, 22)
		btnPrev:SetPoint("LEFT", 0, 0)
		btnPrev:SetText("Prev")
		btnPrev:SetScript("OnClick", function()
			ProfessionExporter:CopyBoxGoPage(-1)
		end)
		copyFrame.btnPrev = btnPrev

		local pageLabel = pageBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		pageLabel:SetPoint("CENTER", pageBar, "CENTER", 0, 0)
		pageLabel:SetText("Page 1 / 1")
		copyFrame.pageLabel = pageLabel

		local btnNext = CreateFrame("Button", nil, pageBar, "UIPanelButtonTemplate")
		btnNext:SetSize(72, 22)
		btnNext:SetPoint("RIGHT", 0, 0)
		btnNext:SetText("Next")
		btnNext:SetScript("OnClick", function()
			ProfessionExporter:CopyBoxGoPage(1)
		end)
		copyFrame.btnNext = btnNext

		local scrollFrame = CreateFrame("ScrollFrame", addonName .. "CopyScrollFrame", copyFrame, "UIPanelScrollFrameTemplate")
		local editBox = CreateFrame("EditBox", addonName .. "CopyEditBox", scrollFrame)
		editBox:SetMultiLine(true)
		editBox:SetAutoFocus(true)
		editBox:SetFontObject(ChatFontNormal)
		editBox:SetWidth(630)
		editBox:SetScript("OnEscapePressed", function()
			copyFrame:Hide()
		end)

		scrollFrame:SetScrollChild(editBox)

		local closeButton = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
		closeButton:SetPoint("BOTTOM", 0, 8)
		closeButton:SetSize(120, 22)
		closeButton:SetText(CLOSE)
		closeButton:SetScript("OnClick", function()
			copyFrame:Hide()
		end)

		copyFrame.scrollFrame = scrollFrame
		copyFrame.editBox = editBox
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

	if useEnvelope then
		copyFrame.pageHintStr:SetText(
			"The payload is a compressed AuctionHelper package. If there are multiple pages, join page payload fragments in order."
		)
	else
		copyFrame.pageHintStr:SetText("")
	end
	self:LayoutCopyFrameScroll(copyFrame, useEnvelope)

	if footerText ~= "" then
		copyFrame.footerStr:SetText(footerText)
		copyFrame.footerStr:Show()
	else
		copyFrame.footerStr:SetText("")
		copyFrame.footerStr:Hide()
	end

	copyFrame:Show()
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
				copyFrame.pageHintStr:SetText("")
				copyFrame.editBox:SetText(
					"Paging failed: "
						.. tostring(err or "unknown error")
						.. "\n\nTry exporting a smaller scope (for example one profession or compact auction/inventory data)."
				)
				return
			end
			local np = #computedSegments
			if np < 1 then
				np = 1
			end
			local useEnv = np > 1
			if not useEnv then
				copyFrame._pagingMode = "raw"
				copyFrame._segments = nil
				copyFrame._numPages = 1
				self:LayoutCopyFrameScroll(copyFrame, false)
				copyFrame.pageHintStr:SetText("")
			else
				copyFrame._pagingMode = "envelope"
				copyFrame._segments = computedSegments
				copyFrame._numPages = np
				self:LayoutCopyFrameScroll(copyFrame, true)
			end
			copyFrame._pageIndex = 1
			local ft = self:CopyBoxBuildFooterText(copyFrame._opts or {}, useEnv)
			if ft ~= "" then
				copyFrame.footerStr:SetText(ft)
				copyFrame.footerStr:Show()
			end
			self:CopyBoxApplyCurrentPage()
		end)
	end
end

function ProfessionExporter:Export(scope, identifier)
	local st = self:GetState()
	if st.exportJsonBusy then
		self:PrintMessage("Export already in progress.")
		return
	end

	local scopeLabel = scope == "account" and "account"
		or scope == "account_summary" and "account summary"
		or scope == "professions" and "professions (character)"
		or scope == "professions_recipes" and "professions recipes (character)"
		or scope == "professions_talents" and "professions talents (character)"
		or scope == "professions_compact" and "professions compact"
		or scope == "inventory" and "inventory (character)"
		or scope == "inventory_compact" and "inventory compact"
		or scope == "auction_snapshot" and "auction snapshot"
		or scope == "auction_history" and "auction history"
		or scope == "crafting_costs" and "crafting costs"
		or scope == "spec_catalog" and "spec catalog (Midnight bundled)"
		or scope == "character_meta" and "character meta"
		or (scope == "profession" and string.format("profession (%s)", tostring(identifier or "?")))
		or (scope == "profession_recipes" and string.format("profession recipes (%s)", tostring(identifier or "?")))
		or (scope == "profession_talents" and string.format("profession talents (%s)", tostring(identifier or "?")))
		or tostring(scope or "character")
	self:ShowExportProgress(scopeLabel)

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
	self:SetExportProgressPhase("Packing compressed export…", true)
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
		self:PrintMessage(string.format(
			"Compressed export is %d bytes. Use a smaller scope if needed.",
			#payload
		))
	end

	local savedOk = self:SaveExportToSavedVariables(payload, meta)
	local unsavedHint
	if not savedOk and #payload > self.MAX_SAVEDEXPORT_BYTES then
		unsavedHint = string.format(
			"Full compressed export was not saved (over %d byte SavedVariables limit). Try smaller scopes such as professions_recipes, profession_talents, inventory, or a single profession.",
			self.MAX_SAVEDEXPORT_BYTES
		)
	end

	debugprofilestart()
	self:ShowCopyBox(payload, {
		fullByteLength = #payload,
		savedToVariables = savedOk,
		unsavedHint = unsavedHint,
	})
	local msUi = debugprofilestop()

	if dbg then
		self:PrintMessage(string.format(
			"Export timing: gather=%.1fms pack=%.1fms copyUI=%.1fms (package %d bytes)",
			msGather,
			msEncode,
			msUi,
			#payload
		))
	end

	local formatLabel = (meta and meta.format) or (type(payload) == "string" and payload:sub(1, 7) == "AHLUA1:" and "AHLUA1") or self.EXPORT_FORMAT or "AHCBOR1"
	self:PrintMessage(string.format("Exported %s package (%d bytes, %s).", tostring(meta.scope or scope or "character"), #payload, formatLabel))
	if savedOk then
		self:PrintMessage("Compressed export queued for SavedVariables — |cffffffff/reload|r or log out to write WTF\\Account\\…\\SavedVariables\\AuctionHelper.lua (AuctionHelperLastExport.payload).")
	elseif #payload > self.MAX_SAVEDEXPORT_BYTES then
		self:PrintMessage("SavedVariables copy skipped (compressed export still exceeds size limit).")
	end
end

function ProfessionExporter:PrintStatus()
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

function ProfessionExporter:HandleSettingsSlash(rest)
	self:InitDB()
	local sub, arg = rest:match("^(%S+)%s*(.*)$")
	sub = string.lower(sub or "")
	arg = self:Trim(arg or "")
	if sub == "spectree" or sub == "specialization" then
		if arg == "on" or arg == "1" or arg == "true" then
			self:SetSetting("capture.captureSpecializationTree", true)
		elseif arg == "off" or arg == "0" or arg == "false" then
			self:SetSetting("capture.captureSpecializationTree", false)
		else
			self:PrintMessage("Usage: /auctionhelper settings spectree on|off")
			return
		end
		self:PrintMessage(string.format("Specialization tree capture: %s.", self:GetSetting("capture.captureSpecializationTree", true) and "on" or "off"))
		return
	end

	if sub == "recipeoutput" or sub == "rawoutput" then
		if arg == "on" or arg == "1" or arg == "true" then
			self:SetSetting("capture.includeRecipeOutputItemData", true)
		elseif arg == "off" or arg == "0" or arg == "false" then
			self:SetSetting("capture.includeRecipeOutputItemData", false)
		else
			self:PrintMessage("Usage: /auctionhelper settings recipeoutput on|off")
			return
		end
		self:PrintMessage(string.format("Recipe output item API dump: %s.", self:GetSetting("capture.includeRecipeOutputItemData", false) and "on" or "off"))
		return
	end

	if sub == "invbatch" or sub == "inventorybatch" then
		local n = tonumber(arg)
		if not n or n < 0 then
			self:PrintMessage("Usage: /auctionhelper settings invbatch <n>  (0 = one frame; 50–100 spreads GetItemCount work)")
			return
		end
		self:SetSetting("capture.inventorySnapshotBatchSize", math.floor(n))
		self:PrintMessage(string.format("Inventory snapshot batch size: %d.", self:GetSetting("capture.inventorySnapshotBatchSize", 0)))
		return
	end

	self:PrintMessage("Usage: /auctionhelper settings spectree on|off | recipeoutput on|off | invbatch <n>")
end

function ProfessionExporter:HandleAuctionSlash(rest)
	rest = self:Trim(rest or "")
	local sub, arg = rest:match("^(%S+)%s*(.*)$")
	sub = string.lower(sub or "")
	arg = self:Trim(arg or "")
	if sub == "" or sub == "status" then
		local enabled = self:GetSetting("auction.enabled", true)
		local rows = self.BuildAuctionInventoryRows and self:BuildAuctionInventoryRows() or {}
		self:PrintMessage(string.format("Auction module: %s. Inventory rows: %d.", enabled and "enabled" or "disabled", #rows))
		return
	end
	if sub == "enable" then
		self:SetSetting("auction.enabled", true)
		self:PrintMessage("Auction module enabled.")
		return
	end
	if sub == "disable" then
		self:SetSetting("auction.enabled", false)
		self:PrintMessage("Auction module disabled.")
		return
	end
	if sub == "refresh" then
		local r = string.lower(arg or "")
		if r == "crafts" or r == "craft" then
			if self.QueueCraftEconomyAuctionRefresh then
				self:QueueCraftEconomyAuctionRefresh({})
				return
			end
		end
		if self.BuildAuctionVisibleItemIDs and self.QueueVisibleAuctionRefresh then
			self:QueueVisibleAuctionRefresh(self:BuildAuctionVisibleItemIDs())
			self:PrintMessage("Queued visible auction refresh.")
			return
		end
	end
	if sub == "dump" then
		if self.StartAuctionDump then
			local mode = arg ~= "" and arg or "visible"
			self:StartAuctionDump(mode)
			self:PrintMessage(string.format("Auction dump completed (mode: %s).", mode))
			return
		end
	end
	self:PrintMessage("Usage: /auctionhelper auction [status|enable|disable|refresh [crafts]|dump [visible|all]]")
end

function ProfessionExporter:HandleSlash(input)
	input = self:Trim(input)
	local command, rest = input:match("^(%S+)%s*(.-)$")
	command = string.lower(command or "")
	rest = self:Trim(rest)

	if command == "" then
		self:ToggleDashboard()
		return
	end

	if command == "docs" or command == "documentation" then
		self:OpenDocumentationTab()
		return
	end

	if command == "help" then
		self:PrintMessage("Commands: /auctionhelper (window) | /auctionhelper docs | /auctionhelper scan | /auctionhelper full | /auctionhelper status | /auctionhelper debug [on|off|toggle] | /auctionhelper export … | /auctionhelper settings … | /auctionhelper auction …  (alias: /profexport)")
		self:PrintMessage("Export: character | account | account_summary | professions | professions_recipes | professions_talents | professions_compact | inventory | inventory_compact | auction_snapshot | auction_history | crafting_costs | spec_catalog | meta | profession <id|name> | profession_recipes <id|name> | profession_talents <id|name>")
		self:PrintMessage("Settings: spectree on|off | recipeoutput on|off | invbatch <n> (0 = sync snapshot). Auction: status|enable|disable|refresh [crafts]|dump.")
		self:PrintMessage("Export: data is packed as AHCBOR1 (CBOR + Deflate + Base64). Full payload is written to AuctionHelperLastExport after /reload — see timing lines when debug is on.")
		return
	end

	if command == "settings" then
		self:HandleSettingsSlash(rest)
		return
	end

	if command == "auction" or command == "ah" then
		self:HandleAuctionSlash(rest)
		return
	end

	if command == "debug" then
		local sub = string.lower(rest or "")
		if sub == "on" or sub == "1" or sub == "true" then
			self:SetDebugEnabled(true)
		elseif sub == "clear" or sub == "reset" then
			self:ClearDebugLog()
			self:PrintMessage("Persistent debug log cleared.")
		elseif sub == "where" or sub == "path" then
			self:PrintMessage("Persistent debug log is stored in AuctionHelperDB.settings.debug.lines and written to WTF\\Account\\...\\SavedVariables\\AuctionHelper.lua on /reload or logout.")
		elseif sub == "status" then
			self:InitDB()
			local count = self.db and self.db.debug and self.db.debug.lines and #self.db.debug.lines or 0
			self:PrintMessage(string.format("Debug logging: %s. Persistent lines buffered: %d.", self:IsDebugEnabled() and "on" or "off", count))
		elseif sub == "off" or sub == "0" or sub == "false" then
			self:SetDebugEnabled(false)
		else
			self:SetDebugEnabled(not self:IsDebugEnabled())
		end
		if self.ui and self.ui.mainFrame and self.ui.mainFrame:IsShown() then
			self:RefreshDashboard(true)
		end
		return
	end

	if command == "scan" then
		self:StartScan()
		return
	end

	if command == "full" or command == "dumpfull" then
		self:StartFullCharacterDump()
		return
	end

	if command == "status" then
		self:PrintStatus()
		return
	end

	if command == "export" then
		local r = string.lower(rest or "")
		if r == "" or r == "character" then
			self:Export("character")
			return
		end

		if r == "account" then
			self:Export("account")
			return
		end

		if r == "account_summary" or r == "summary" or r == "aggregates" or r == "aggregate" then
			self:Export("account_summary")
			return
		end

		if r == "professions" then
			self:Export("professions")
			return
		end

		if r == "professions_recipes" then
			self:Export("professions_recipes")
			return
		end

		if r == "professions_talents" then
			self:Export("professions_talents")
			return
		end

		if r == "professions_compact" or r == "profcompact" then
			self:Export("professions_compact")
			return
		end

		if r == "inventory" or r == "items" then
			self:Export("inventory")
			return
		end

		if r == "inventory_compact" or r == "invcompact" then
			self:Export("inventory_compact")
			return
		end

		if r == "auction_snapshot" or r == "auctionsnapshot" then
			self:Export("auction_snapshot")
			return
		end

		if r == "auction_history" or r == "auctionhistory" then
			self:Export("auction_history")
			return
		end

		if r == "crafting_costs" or r == "craftcosts" then
			self:Export("crafting_costs")
			return
		end

		if r == "spec_catalog" or r == "speccatalog" or r == "spec_catalog_midnight" then
			self:Export("spec_catalog")
			return
		end

		if r == "meta" or r == "charmeta" or r == "character_meta" then
			self:Export("character_meta")
			return
		end

		local scope, identifier = rest:match("^(%S+)%s+(.+)$")
		scope = string.lower(scope or "")
		if (scope == "profession_recipes" or scope == "profession_talents") and identifier then
			self:Export(scope, self:Trim(identifier))
			return
		end
		if scope == "profession" and identifier then
			self:Export("profession", identifier)
			return
		end

		self:PrintMessage("Usage: /auctionhelper export [character|account|account_summary|professions|professions_recipes|professions_talents|professions_compact|inventory|inventory_compact|auction_snapshot|auction_history|crafting_costs|spec_catalog|meta|profession <id|name>|profession_recipes <id|name>|profession_talents <id|name>]")
		return
	end

	self:PrintMessage("Unknown command. Use /auctionhelper help.")
end
