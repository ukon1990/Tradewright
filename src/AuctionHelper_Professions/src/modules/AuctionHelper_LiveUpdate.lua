local _, AuctionHelper = ...

-- Debounce rapid fires (BAG_UPDATE_DELAYED, etc.). Profession UI list churn uses TRADE_SKILL_LIST_UPDATE
-- very frequently; we do not run a full merge on that event (only refresh remembered skill line id).
local LIVE_INV_DEBOUNCE_SEC = 0.45
local LIVE_PROFESSION_DEBOUNCE_SEC = 0.5
local LIVE_RECIPE_CHUNK_SIZE = 40
-- Sync-collect up to this many new recipes on the close/merge frame; larger sets are chunked.
local LIVE_SYNC_RECIPE_BUDGET = 50

local sortNumericIds = AuctionHelper.ProfessionFingerprint.sortNumericIds

function AuctionHelper:LiveUpdatesBlocked()
	local state = self:GetState()
	return not self.IS_SUPPORTED or state.scanInProgress
end

--- Ensure the logged-in character has a DB row; create a fresh scan record if missing (live updates / dashboard refresh).
function AuctionHelper:GetOrCreateCharacterDataForLiveUpdate()
	self:InitDB()
	local key = self:GetCharacterKey()
	local charData = self.db.characters[key]
	if not charData then
		charData = self:CreateCharacterScanRecord()
		self.db.characters[key] = charData
		self:BumpDataRevision()
	end
	charData.meta = self:GetCharacterMetadata()
	return key, charData
end

--- Refresh profession-relevant inventory counts for the current character; creates stored data if none exists yet.
function AuctionHelper:ScheduleLiveInventoryRefresh()
	if self:LiveUpdatesBlocked() then
		self:DebugLog("LIVE", "ScheduleLiveInventoryRefresh skipped", {
			(not self.IS_SUPPORTED and "not supported") or "scanInProgress blocks live inventory",
		})
		return
	end

	local state = self:GetState()
	if state.liveInvTimer then
		state.liveInvTimer:Cancel()
	end

	self:DebugLog("LIVE", "ScheduleLiveInventoryRefresh (debounce timer)", {
		string.format("delaySec=%.2f", LIVE_INV_DEBOUNCE_SEC),
	})

	state.liveInvTimer = C_Timer.NewTimer(LIVE_INV_DEBOUNCE_SEC, function()
		state.liveInvTimer = nil
		if self:LiveUpdatesBlocked() then
			self:DebugLog("LIVE", "live inventory timer aborted (scan started)", {})
			return
		end
		self:InitDB()
		local key, charData = self:GetOrCreateCharacterDataForLiveUpdate()
		charData.lastLiveInventoryUpdate = time()
		self:UpdateInventorySnapshot(charData, {
			forceImmediate = false,
			onComplete = function()
				if self:LiveUpdatesBlocked() then
					self:DebugLog("LIVE", "live inventory onComplete aborted (scan started)", {})
					return
				end
				self:PatchAggregateInventorySummaryForCharacter(key, charData)
				self:NotifyDashboardUpdate(true)
				self:RefreshCraftsTabIfVisible()
				if self.RefreshAuctionHousePanel then
					self:RefreshAuctionHousePanel()
				end
				if self.ScheduleRefreshProfessionCraftEconomyPanel then
					self:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
				end
				self:DebugLog("LIVE", "live inventory timer applied snapshot", {
					string.format("characterKey=%s", key),
					string.format("itemTypesTracked=%s", tostring(charData.inventorySnapshot and charData.inventorySnapshot.itemTypesTracked)),
				})
			end,
		})
	end)
end

function AuctionHelper:CancelLiveProfessionRefreshTimer()
	local state = self:GetState()
	if state.liveProfessionTimer then
		state.liveProfessionTimer:Cancel()
		state.liveProfessionTimer = nil
	end
end

function AuctionHelper:CancelLiveProfessionMergeJob()
	local state = self:GetState()
	if state.liveProfessionMergeJob then
		state.liveProfessionMergeJob.cancelled = true
		state.liveProfessionMergeJob = nil
	end
end

--- Re-scan the currently open profession into saved character data, then refresh inventory snapshot.
function AuctionHelper:ScheduleLiveProfessionRefresh()
	if self:LiveUpdatesBlocked() then
		self:DebugLog("LIVE", "ScheduleLiveProfessionRefresh skipped", {
			(not self.IS_SUPPORTED and "not supported") or "scanInProgress blocks live profession merge",
		})
		return
	end

	local state = self:GetState()
	if state.pendingScan then
		self:DebugLog("LIVE", "ScheduleLiveProfessionRefresh skipped (pendingScan)", {})
		return
	end

	self:InitDB()

	self:CancelLiveProfessionRefreshTimer()

	self:DebugLog("LIVE", "ScheduleLiveProfessionRefresh (debounce timer)", {
		string.format("delaySec=%.2f", LIVE_PROFESSION_DEBOUNCE_SEC),
	})

	state.liveProfessionTimer = C_Timer.NewTimer(LIVE_PROFESSION_DEBOUNCE_SEC, function()
		state.liveProfessionTimer = nil
		if self:LiveUpdatesBlocked() or self:GetState().pendingScan then
			self:DebugLog("LIVE", "live profession timer aborted", {
				string.format("scanInProgress=%s pendingScan=%s", tostring(self:GetState().scanInProgress), tostring(self:GetState().pendingScan)),
			})
			return
		end
		self:ApplyLiveOpenProfessionMerge()
	end)
end

local function buildKnownSpellSet(self, professionData)
	local known = {}
	if not professionData or type(professionData.recipes) ~= "table" then
		return known
	end
	for _, recipeData in pairs(professionData.recipes) do
		local spellID = self:GetRecipeSpellID(recipeData)
		if spellID then
			known[spellID] = true
		end
	end
	return known
end

local function listNewSpellIDs(currentRecipeIDs, knownSpellSet)
	local newIDs = {}
	for i = 1, #(currentRecipeIDs or {}) do
		local id = tonumber(currentRecipeIDs[i])
		if id and not knownSpellSet[id] then
			newIDs[#newIDs + 1] = id
		end
	end
	return newIDs
end

local function buildSpellIDSet(recipeIDs)
	local set = {}
	for i = 1, #(recipeIDs or {}) do
		local id = tonumber(recipeIDs[i])
		if id then
			set[id] = true
		end
	end
	return set
end

function AuctionHelper:FindProfessionDescriptorForSkillLineID(openSkillLineID)
	openSkillLineID = tonumber(openSkillLineID)
	if not openSkillLineID then
		return nil
	end
	for _, profession in ipairs(self:GetPlayerProfessions()) do
		if tonumber(profession.skillLineID) == openSkillLineID then
			return profession
		end
	end
	return nil
end

function AuctionHelper:CommitLiveProfessionMergeResult(key, charData, openSkillLineID, professionData, opts)
	opts = type(opts) == "table" and opts or {}
	charData.professions[tostring(openSkillLineID)] = professionData
	charData.lastLiveProfessionUpdate = time()
	self:GetState().liveProfessionSkillLineID = openSkillLineID
	self.db.characters[key] = charData

	local refreshInventory = opts.refreshInventory ~= false
	if refreshInventory then
		self:UpdateInventorySnapshot(charData, {
			forceImmediate = opts.forceImmediateInventory == true,
			onComplete = function()
				if self:LiveUpdatesBlocked() then
					return
				end
				self:PatchAggregateInventorySummaryForCharacter(key, charData)
				self:NotifyDashboardUpdate(true)
				if self.RefreshCraftsTabIfVisible then
					self:RefreshCraftsTabIfVisible()
				end
			end,
		})
	else
		self:BumpDataRevision()
		self:NotifyDashboardUpdate(true)
	end

	self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID done", {
		string.format("characterKey=%s", key),
		string.format("profession=%s recipeCount=%s", tostring(professionData.professionName), tostring(professionData.recipeCount)),
		string.format("mode=%s", tostring(opts.mode or "full")),
		string.format("itemTypesTracked=%s", tostring(charData.inventorySnapshot and charData.inventorySnapshot.itemTypesTracked)),
	})
	return professionData
end

function AuctionHelper:StartChunkedRecipeMergeJob(job)
	local state = self:GetState()
	self:CancelLiveProfessionMergeJob()
	state.liveProfessionMergeJob = job
	job.cancelled = false
	job.index = 1

	self:BeginProfessionCollectCaches()
	self:DebugLog("LIVE", "chunked recipe merge started", {
		string.format("skillLineID=%s", tostring(job.openSkillLineID)),
		string.format("recipeTotal=%d", #job.recipeSpellIDs),
		string.format("mode=%s", tostring(job.mode)),
	})

	local function processChunk()
		if job.cancelled or state.liveProfessionMergeJob ~= job then
			self:EndProfessionCollectCaches()
			return
		end
		if self:LiveUpdatesBlocked() or state.pendingScan then
			job.cancelled = true
			if state.liveProfessionMergeJob == job then
				state.liveProfessionMergeJob = nil
			end
			self:EndProfessionCollectCaches()
			self:DebugLog("LIVE", "chunked recipe merge aborted", {
				string.format("skillLineID=%s", tostring(job.openSkillLineID)),
			})
			return
		end

		local toIndex = math.min(job.index + LIVE_RECIPE_CHUNK_SIZE - 1, #job.recipeSpellIDs)
		self:CollectRecipesIntoProfessionData(job.professionData, job.recipeSpellIDs, job.index, toIndex)
		job.index = toIndex + 1

		if job.index <= #job.recipeSpellIDs then
			C_Timer.After(0, processChunk)
			return
		end

		self:EndProfessionCollectCaches()
		if state.liveProfessionMergeJob == job then
			state.liveProfessionMergeJob = nil
		end

		local fingerprintInfo = job.fingerprintInfo or self:BuildOpenProfessionQuickFingerprint()
		self:FinalizeProfessionDataCollect(job.professionData, job.descriptor, fingerprintInfo)
		self:CommitLiveProfessionMergeResult(job.key, job.charData, job.openSkillLineID, job.professionData, {
			mode = job.mode or "chunked",
			refreshInventory = true,
			forceImmediateInventory = false,
		})
	end

	C_Timer.After(0, processChunk)
end

local MERGE_LOG = "ApplyLiveProfessionMergeForSkillLineID"

local function mergeBlockedOrMissing(self, openSkillLineID)
	if self:LiveUpdatesBlocked() or self:GetState().pendingScan then
		self:DebugLog("LIVE", MERGE_LOG .. " skipped", {
			string.format("blocked=%s pendingScan=%s", tostring(self:LiveUpdatesBlocked()), tostring(self:GetState().pendingScan)),
		})
		return true
	end
	return not openSkillLineID
end

local function exportFilteredFingerprint(self)
	local filterSnapshot = self:SnapshotFilters()
	self:ApplyExportFilters()
	local fingerprintInfo = self:BuildOpenProfessionQuickFingerprint()
	self:RestoreFilters(filterSnapshot)
	return fingerprintInfo
end

-- True when the saved profession should stay as is (unstable UI teardown, or nothing changed).
local function keepSavedProfession(self, openSkillLineID, existing, fingerprintInfo)
	if not existing or not fingerprintInfo then
		return false
	end
	-- Avoid wiping good SavedVariables when the UI tears down before recipes are available.
	if not fingerprintInfo.stable and tonumber(existing.recipeCount) and tonumber(existing.recipeCount) > 0 then
		self:DebugLog("LIVE", MERGE_LOG .. " skipped (unstable fingerprint, keeping saved)", {
			string.format("skillLineID=%s savedRecipeCount=%s", tostring(openSkillLineID), tostring(existing.recipeCount)),
		})
		return true
	end
	if existing.liveFingerprint and existing.liveFingerprint == fingerprintInfo.fingerprint then
		self:DebugLog("LIVE", MERGE_LOG .. " skipped (saved fingerprint match)", { string.format("skillLineID=%s", tostring(openSkillLineID)) })
		return true
	end
	return false
end

local function chunkedMergeJob(merge, professionData, recipeSpellIDs, fingerprintInfo, mode)
	return { key = merge.key, charData = merge.charData, openSkillLineID = merge.openSkillLineID, descriptor = merge.descriptor,
		professionData = professionData, recipeSpellIDs = recipeSpellIDs, fingerprintInfo = fingerprintInfo, mode = mode }
end

local function professionLogLine(merge)
	return string.format("profession=%s skillLineID=%s", tostring(merge.descriptor.professionName), tostring(merge.openSkillLineID))
end

local function startChunkedFullMerge(self, merge, recipeIDs, filterSnapshot)
	self:DebugLog("LIVE", MERGE_LOG .. " collecting (chunked full)", { professionLogLine(merge) .. string.format(" recipeCount=%d", #recipeIDs) })
	local professionData = self:CreateProfessionDataShell(merge.descriptor, { rebuildSpecs = true })
	self:RestoreFilters(filterSnapshot)
	-- Prefer a fingerprint taken under the same filter state used for collection.
	local filteredFp = self:BuildOpenProfessionQuickFingerprint() or merge.fingerprintInfo
	self:StartChunkedRecipeMergeJob(chunkedMergeJob(merge, professionData, recipeIDs, filteredFp, "chunked_full"))
	return nil
end

local function fullLiveProfessionMerge(self, merge)
	local snapshot = self:SnapshotFilters()
	self:ApplyExportFilters()
	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and self:NormalizeApiList(C_TradeSkillUI.GetAllRecipeIDs()) or {}
	sortNumericIds(recipeIDs)
	if merge.allowChunked and #recipeIDs > LIVE_SYNC_RECIPE_BUDGET then
		return startChunkedFullMerge(self, merge, recipeIDs, snapshot)
	end

	self:DebugLog("LIVE", MERGE_LOG .. " collecting (full)", { professionLogLine(merge) })
	local professionData = self:CollectCurrentProfessionData(merge.descriptor)
	-- Stamp while export filters are still applied so liveFingerprint matches close-path compares.
	local filteredFp = self:BuildOpenProfessionQuickFingerprint() or merge.fingerprintInfo
	self:RestoreFilters(snapshot)
	if not professionData then
		self:DebugLog("LIVE", MERGE_LOG .. " CollectCurrentProfessionData returned nil", {})
		return nil
	end
	if filteredFp then
		self:StampProfessionLiveFingerprint(professionData, filteredFp)
	end
	return self:CommitLiveProfessionMergeResult(merge.key, merge.charData, merge.openSkillLineID, professionData,
		{ mode = merge.forceFull and "force_full" or "full", refreshInventory = true, forceImmediateInventory = merge.forceFull })
end

local function needsSpecRebuild(self, existing, fingerprintInfo)
	if self:GetSetting("capture.captureSpecializationTree", true) == false then
		return false
	end
	local sameMeta = fingerprintInfo and fingerprintInfo.metaFingerprint and existing.liveMetaFingerprint
		and existing.liveMetaFingerprint == fingerprintInfo.metaFingerprint
	return not (sameMeta and existing.specializationTrees)
end

local function professionInfos()
	local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	local childInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo() or nil
	return baseInfo, childInfo
end

local function stampProfessionMetadataOnly(self, merge)
	local existing = merge.existing
	local baseInfo, childInfo = professionInfos()
	self:UpdateProfessionDescriptorFields(existing, merge.descriptor, baseInfo, childInfo)
	self:StampProfessionLiveFingerprint(existing, merge.fingerprintInfo)
	self:BumpDataRevision()
	self:DebugLog("LIVE", MERGE_LOG .. " metadata-only stamp", { string.format("skillLineID=%s", tostring(merge.openSkillLineID)) })
	return self:CommitLiveProfessionMergeResult(merge.key, merge.charData, merge.openSkillLineID, existing, { mode = "metadata", refreshInventory = false })
end

-- Categories, descriptor fields and (when asked) spec trees, collected under export filters.
local function refreshProfessionMetadata(self, merge, needSpecs)
	local existing, descriptor = merge.existing, merge.descriptor
	local snapshot = self:SnapshotFilters()
	self:ApplyExportFilters()
	local baseInfo, childInfo = professionInfos()
	local categories = self:CollectRecipeCategories()
	self:UpdateProfessionDescriptorFields(existing, descriptor, baseInfo, childInfo)
	existing.categories = categories
	if needSpecs then
		local captureSpec = self:GetSetting("capture.captureSpecializationTree", true) ~= false
		local specResult = captureSpec
			and self:CollectSpecializationTreesForProfession(descriptor.skillLineID, childInfo, categories, descriptor.currentLevelName) or nil
		self:ApplySpecializationResultToProfessionData(existing, specResult)
	end
	self:RestoreFilters(snapshot)
end

local function collectNewRecipes(self, professionData, newSpellIDs)
	if #newSpellIDs > 0 then
		self:BeginProfessionCollectCaches()
		self:CollectRecipesIntoProfessionData(professionData, newSpellIDs, 1, #newSpellIDs)
		self:EndProfessionCollectCaches()
	end
end

-- Keeps existing recipe rows; collects only new spell IDs; rebuilds specs when meta changes.
local function incrementalLiveProfessionMerge(self, merge)
	local existing, fingerprintInfo = merge.existing, merge.fingerprintInfo
	local recipeIDs = fingerprintInfo and fingerprintInfo.recipeIDs
	local newSpellIDs = listNewSpellIDs(recipeIDs, buildKnownSpellSet(self, existing))
	local needSpecs = needsSpecRebuild(self, existing, fingerprintInfo)
	local pruned = self:PruneProfessionRecipesNotInSpellSet(existing, buildSpellIDSet(recipeIDs))
	local recipesChanged = (#newSpellIDs > 0) or (pruned > 0)
	if not recipesChanged and not needSpecs then
		return stampProfessionMetadataOnly(self, merge)
	end

	self:DebugLog("LIVE", MERGE_LOG .. " collecting (incremental)", {
		professionLogLine(merge),
		string.format("newRecipes=%d pruned=%d needSpecs=%s", #newSpellIDs, pruned, tostring(needSpecs)),
	})
	refreshProfessionMetadata(self, merge, needSpecs)
	if merge.allowChunked and #newSpellIDs > LIVE_SYNC_RECIPE_BUDGET then
		self:StartChunkedRecipeMergeJob(chunkedMergeJob(merge, existing, newSpellIDs, fingerprintInfo, "chunked_incremental"))
		return nil
	end
	collectNewRecipes(self, existing, newSpellIDs)
	self:FinalizeProfessionDataCollect(existing, merge.descriptor, fingerprintInfo)
	return self:CommitLiveProfessionMergeResult(merge.key, merge.charData, merge.openSkillLineID, existing,
		{ mode = "incremental", refreshInventory = recipesChanged, forceImmediateInventory = false })
end

--- One merge for a known skill line (window may already be closing; APIs may still be valid briefly).
--- opts.forceFull — full rescan (Scan button / explicit). opts.fingerprintInfo — prebuilt fingerprint.
--- opts.allowChunked — default true for live path; false for forceFull sync scans.
function AuctionHelper:ApplyLiveProfessionMergeForSkillLineID(openSkillLineID, opts)
	opts = type(opts) == "table" and opts or {}
	local forceFull = opts.forceFull == true
	if mergeBlockedOrMissing(self, openSkillLineID) then
		return nil
	end
	self:CancelLiveProfessionMergeJob()
	self:InitDB()
	local key, charData = self:GetOrCreateCharacterDataForLiveUpdate()
	local existing = charData.professions and charData.professions[tostring(openSkillLineID)] or nil
	local fingerprintInfo = opts.fingerprintInfo
	if type(fingerprintInfo) ~= "table" then
		fingerprintInfo = exportFilteredFingerprint(self)
	end
	if not forceFull and keepSavedProfession(self, openSkillLineID, existing, fingerprintInfo) then
		return existing
	end
	local descriptor = self:FindProfessionDescriptorForSkillLineID(openSkillLineID)
	if not descriptor then
		self:DebugLog("LIVE", MERGE_LOG .. " no matching GetPlayerProfessions entry", { string.format("openSkillLineID=%s", tostring(openSkillLineID)) })
		return nil
	end
	local allowChunked = opts.allowChunked
	if allowChunked == nil then
		allowChunked = not forceFull
	end
	local merge = { key = key, charData = charData, openSkillLineID = openSkillLineID, descriptor = descriptor,
		existing = existing, fingerprintInfo = fingerprintInfo, forceFull = forceFull, allowChunked = allowChunked }
	local hasExistingRecipes = existing and type(existing.recipes) == "table" and next(existing.recipes) ~= nil
	if forceFull or not hasExistingRecipes then
		return fullLiveProfessionMerge(self, merge)
	end
	return incrementalLiveProfessionMerge(self, merge)
end

function AuctionHelper:ApplyLiveOpenProfessionMerge()
	if self:LiveUpdatesBlocked() or self:GetState().pendingScan then
		self:DebugLog("LIVE", "ApplyLiveOpenProfessionMerge skipped", {
			string.format("blocked=%s pendingScan=%s", tostring(self:LiveUpdatesBlocked()), tostring(self:GetState().pendingScan)),
		})
		return
	end

	local openSkillLineID = nil
	local openInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	if openInfo then
		openSkillLineID = tonumber(openInfo.professionID or openInfo.profession or openInfo.skillLineID)
	end
	if not openSkillLineID then
		openSkillLineID = self:GetState().liveProfessionSkillLineID
	end
	if not openSkillLineID then
		self:DebugLog("LIVE", "ApplyLiveOpenProfessionMerge no skill line id (UI closed?)", {})
		return
	end

	self:ApplyLiveProfessionMergeForSkillLineID(openSkillLineID)
end

--- Final merge when the crafting window closes (cancels any pending debounced merge from open).
function AuctionHelper:ApplyLiveProfessionMergeOnWindowClose()
	local state = self:GetState()
	self:CancelLiveProfessionRefreshTimer()
	self:CancelLiveFingerprintTimer()

	-- Final fingerprint under export filters so it matches SavedVariables stamps
	-- (user UI filters like "only makeable" would otherwise force a false dirty).
	local filterSnapshot = self:SnapshotFilters()
	self:ApplyExportFilters()
	local fingerprintInfo = self:RefreshOpenProfessionFingerprintNow()
	self:RestoreFilters(filterSnapshot)

	local id = state.liveProfessionSkillLineID
	local openFingerprint = state.liveProfessionOpenFingerprint
	local lastFingerprint = state.liveProfessionLastFingerprint
	state.liveProfessionSkillLineID = nil
	state.liveProfessionOpenFingerprint = nil
	state.liveProfessionOpenFingerprintInfo = nil
	state.liveProfessionLastFingerprint = nil
	state.liveProfessionLastFingerprintInfo = nil

	if not id or self:LiveUpdatesBlocked() or state.pendingScan then
		return
	end

	-- Primary skip: unchanged vs last SavedVariables dump.
	self:InitDB()
	local key = self:GetCharacterKey()
	local charData = self.db.characters and self.db.characters[key]
	local existing = charData and charData.professions and charData.professions[tostring(id)]
	if existing and fingerprintInfo and existing.liveFingerprint == fingerprintInfo.fingerprint then
		self:DebugLog("LIVE", "ApplyLiveProfessionMergeOnWindowClose skipped (saved fingerprint unchanged)", {
			string.format("skillLineID=%s", tostring(id)),
		})
		return
	end

	-- Secondary skip: stable session with no changes while open, but only if we already have a saved dump.
	-- Note: session open fingerprint may have been taken under user filters; prefer saved compare above.
	if openFingerprint ~= nil and lastFingerprint ~= nil and openFingerprint == lastFingerprint
		and existing and existing.liveFingerprint then
		self:DebugLog("LIVE", "ApplyLiveProfessionMergeOnWindowClose skipped (session fingerprint unchanged)", {
			string.format("skillLineID=%s", tostring(id)),
		})
		return
	end

	-- Unstable close with existing data: keep saved rather than collecting an empty list.
	if fingerprintInfo and not fingerprintInfo.stable and existing and tonumber(existing.recipeCount) and tonumber(existing.recipeCount) > 0 then
		self:DebugLog("LIVE", "ApplyLiveProfessionMergeOnWindowClose skipped (unstable close fingerprint)", {
			string.format("skillLineID=%s", tostring(id)),
		})
		return
	end

	self:ApplyLiveProfessionMergeForSkillLineID(id, {
		fingerprintInfo = fingerprintInfo,
		allowChunked = true,
	})
end
