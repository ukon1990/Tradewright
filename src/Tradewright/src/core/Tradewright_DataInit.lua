local _, Tradewright = ...

-- SavedVariables initialisation and defaults.

local LEGACY_SETTING_PATHS_BY_ROOT = {
	lastActiveTab = "general.lastActiveTab",
	showMinimapButton = "general.showMinimapButton",
	windowScale = "appearance.windowScale",
	captureSpecializationTree = "capture.captureSpecializationTree",
	specBreakdownPerRecipe = "capture.specBreakdownPerRecipe",
	includeRecipeOutputItemData = "capture.includeRecipeOutputItemData",
	inventorySnapshotBatchSize = "capture.inventorySnapshotBatchSize",
	economyShowColumns = "inventory.economyShowColumns",
	economyShowMatCost = "inventory.economyShowMatCost",
	minimapButtonAngle = "integrations.minimapButtonAngle",
	debugEnabled = "debug.enabled",
}

local LEGACY_SETTING_ROOTS_BY_PATH = {}
for rootKey, path in pairs(LEGACY_SETTING_PATHS_BY_ROOT) do
	LEGACY_SETTING_ROOTS_BY_PATH[path] = rootKey
end

-- Storage sub-tables created per SavedVariable (in creation order).
local BASE_TABLE_KEYS = { "meta", "settings" }
-- "craftingOrderWorkQueue" is the saved name of the crafting-order queue; renaming it would drop saved orders.
local PROFESSIONS_TABLE_KEYS = { "characters", "aggregate", "history", "craftQueue", "craftingOrderWorkQueue" }
local INVENTORY_TABLE_KEYS = { "itemHistory", "walletHistory", "ledger" }
local AUCTION_TABLE_KEYS = { "auction" }
local SETTING_GROUPS = { "general", "appearance", "capture", "inventory", "integrations", "debug", "auction" }

-- { rootKey, settings group, nestedKey, default }: nested setting mirrored to a legacy root alias.
local EARLY_SEEDS = {
	{ "lastActiveTab", "general", "lastActiveTab", "overview" },
	{ "showMinimapButton", "general", "showMinimapButton", true },
	{ "windowScale", "appearance", "windowScale", 1 },
	{ "captureSpecializationTree", "capture", "captureSpecializationTree", true },
	{ "includeRecipeOutputItemData", "capture", "includeRecipeOutputItemData", false },
	{ "inventorySnapshotBatchSize", "capture", "inventorySnapshotBatchSize", 0 },
	{ "economyShowColumns", "inventory", "economyShowColumns", true },
	{ "economyShowMatCost", "inventory", "economyShowMatCost", true },
}
local LATE_SEEDS = {
	{ "minimapButtonAngle", "integrations", "minimapButtonAngle", 225 },
	{ "debugEnabled", "debug", "enabled", false },
}

local INVENTORY_SETTING_TABLE_KEYS = { "columnOrder", "hiddenColumns" }
-- { key, default } applied only when the key is nil (scalars only; tables are created fresh).
local OVERVIEW_DEFAULTS = { { "walletGraphMetric", "balance" } }
local INVENTORY_DEFAULTS = {
	{ "detailsOpen", true }, { "detailsWidth", 340 }, { "detailsGraphMetric", "market" },
	{ "detailsGraphShowQuantity", true }, { "historyRetentionDays", 30 },
}
local CRAFTS_DEFAULTS = {
	{ "detailsOpen", true }, { "detailsWidth", 340 }, { "detailsGraphMetric", "market" },
	{ "detailsGraphShowQuantity", true }, { "defaultExpansionMode", "current" }, { "scenario", "default" },
	{ "reagentSourceMode", "owned_first" }, { "profitState", "all" }, { "costBasis", "auto" },
	{ "saleBasis", "auto" }, { "sortColumn", "profit" }, { "sortAsc", false },
}
local CRAFTS_TABLE_KEYS = { "characterFilter", "professionFilter", "categoryFilter" }
local CRAFTING_ORDER_DEFAULTS = { { "hideUnlearned", false }, { "patronKnowledgeOnly", false } }
local AUCTION_SETTING_DEFAULTS = {
	{ "enabled", true }, { "sellPanelEnabled", true }, { "tabEnabled", true }, { "minMarginPercent", 5 },
	{ "minMarginCopper", 100 }, { "historyRetentionDays", 30 }, { "visibleRefreshThrottleMs", 150 },
	{ "dumpBatchSize", 50 }, { "priceFreshnessMinutes", 15 }, { "autoCraftEconomyRefreshOnOpen", false },
	{ "craftScanIncludeOptionalSlots", false }, { "suggestFullScan", true },
}
-- Auction settings mirrored into the auction module's own settings table (in this order).
local AUCTION_MIRRORED_KEYS = {}
for i, d in ipairs(AUCTION_SETTING_DEFAULTS) do
	AUCTION_MIRRORED_KEYS[i] = d[1]
end
AUCTION_MIRRORED_KEYS[#AUCTION_MIRRORED_KEYS + 1] = "selectedExpansions"

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

local function seedSettings(st, seeds)
	for _, s in ipairs(seeds) do
		seedNestedSetting(st, s[1], st[s[2]], s[3], s[4])
	end
end

local function ensureTables(t, keys)
	for _, k in ipairs(keys) do
		t[k] = t[k] or {}
	end
end

local function applyNilDefaults(t, defaults)
	for _, d in ipairs(defaults) do
		if t[d[1]] == nil then
			t[d[1]] = d[2]
		end
	end
end

function Tradewright:GetLegacySettingRootKey(path)
	return LEGACY_SETTING_ROOTS_BY_PATH[tostring(path or "")]
end

function Tradewright:SyncLegacySettingAlias(path, value)
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

local function ensureExpansionSelection(t)
	if t.selectedExpansions == nil then
		t.selectedExpansions = { [currentExpansionTag()] = true }
	end
end

function Tradewright:BuildMergedRuntimeDB(baseDb, professionsDb, inventoryDb, auctionDb)
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

local function ensureSavedVariableRoots()
	TradewrightDB = TradewrightDB or {}
	TradewrightProfessionsDB = TradewrightProfessionsDB or {}
	TradewrightInventoryDB = TradewrightInventoryDB or {}
	TradewrightAuctionDB = TradewrightAuctionDB or {}
	TradewrightLastExport = TradewrightLastExport or {}
end

local function prepareStorageDb(self, db, tableKeys)
	db.schemaVersion = self.SCHEMA_VERSION
	db.addonVersion = self.VERSION
	ensureTables(db, tableKeys)
end

local function applyInventoryDefaults(inventory)
	inventory.metricRange = inventory.metricRange or "30d"
	ensureTables(inventory, INVENTORY_SETTING_TABLE_KEYS)
	applyNilDefaults(inventory, INVENTORY_DEFAULTS)
	ensureExpansionSelection(inventory)
end

local function applyCraftsDefaults(st)
	st.overview = st.overview or {}
	applyNilDefaults(st.overview, OVERVIEW_DEFAULTS)
	st.crafts = st.crafts or {}
	applyNilDefaults(st.crafts, CRAFTS_DEFAULTS)
	ensureExpansionSelection(st.crafts)
	ensureTables(st.crafts, CRAFTS_TABLE_KEYS)
	st.craftingOrders = st.craftingOrders or {}
	applyNilDefaults(st.craftingOrders, CRAFTING_ORDER_DEFAULTS)
end

local function applyDebugDefaults(debug, general)
	if debug.persistToSavedVariables == nil then debug.persistToSavedVariables = false end
	debug.lines = debug.lines or {}
	if debug.maxLines == nil then debug.maxLines = 100 end
	if general.persistLastExport == nil then general.persistLastExport = true end
end

-- The profit floor moved from whole gold to copper; keep a floor the player already picked.
local function migrateMinProfit(st)
	local opportunities = st.opportunities
	if type(opportunities) == "table" and opportunities.minProfitCopper == nil and tonumber(opportunities.minProfitGold) then
		opportunities.minProfitCopper = tonumber(opportunities.minProfitGold) * 10000
	end
end

local function applySettingDefaults(st)
	ensureTables(st, SETTING_GROUPS)
	local general, inventory, debug, auctionSettings = st.general, st.inventory, st.debug, st.auction
	seedSettings(st, EARLY_SEEDS)
	applyInventoryDefaults(inventory)
	applyCraftsDefaults(st)
	seedSettings(st, LATE_SEEDS)
	applyDebugDefaults(debug, general)
	migrateMinProfit(st)
	applyNilDefaults(auctionSettings, AUCTION_SETTING_DEFAULTS)
	ensureExpansionSelection(auctionSettings)
	return auctionSettings
end

local function syncAuctionModuleSettings(self, auctionSettings)
	local auction = self.InitAuctionDB and self:InitAuctionDB() or nil
	if not auction then
		return
	end
	auction.settings = auction.settings or {}
	for _, key in ipairs(AUCTION_MIRRORED_KEYS) do
		auction.settings[key] = auctionSettings[key]
	end
end

function Tradewright:InitDB()
	ensureSavedVariableRoots()
	local baseDb, professionsDb = TradewrightDB, TradewrightProfessionsDB
	local inventoryDb, auctionDb = TradewrightInventoryDB, TradewrightAuctionDB
	local needsStorageCompaction = (tonumber(baseDb.schemaVersion) or 0) < self.SCHEMA_VERSION
	prepareStorageDb(self, baseDb, BASE_TABLE_KEYS)
	prepareStorageDb(self, professionsDb, PROFESSIONS_TABLE_KEYS)
	prepareStorageDb(self, inventoryDb, INVENTORY_TABLE_KEYS)
	prepareStorageDb(self, auctionDb, AUCTION_TABLE_KEYS)

	self.baseDb = baseDb
	self.professionsDb = professionsDb
	self.inventoryDb = inventoryDb
	self.auctionStorageDb = auctionDb
	self.db = self:BuildMergedRuntimeDB(baseDb, professionsDb, inventoryDb, auctionDb)

	syncAuctionModuleSettings(self, applySettingDefaults(self.db.settings))
	if Tradewright.InitLedger then
		Tradewright:InitLedger()
	end
	if needsStorageCompaction then
		self:CompactSavedVariablesStorage()
	end
end

function Tradewright:CompactSavedVariablesStorage()
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
