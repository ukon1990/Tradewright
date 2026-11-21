-- Export building: per-scope slices of the scan data, compact records and the encoded export payload.
local _, AuctionHelper = ...

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
