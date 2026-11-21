local _, AuctionHelper = ...

-- Debounce rapid fires (BAG_UPDATE_DELAYED, etc.). Profession UI list churn uses TRADE_SKILL_LIST_UPDATE
-- very frequently; we do not run a full merge on that event (only refresh remembered skill line id).
local LIVE_INV_DEBOUNCE_SEC = 0.45
local LIVE_PROFESSION_DEBOUNCE_SEC = 0.5
local LIVE_FINGERPRINT_DEBOUNCE_SEC = 0.35
local LIVE_RECIPE_CHUNK_SIZE = 40
-- Sync-collect up to this many new recipes on the close/merge frame; larger sets are chunked.
local LIVE_SYNC_RECIPE_BUDGET = 50

local function quickArrayHash(values)
	local hash = 2166136261
	for i = 1, #values do
		local n = tonumber(values[i]) or 0
		hash = bit.bxor(hash, n % 4294967296)
		hash = (hash * 16777619) % 4294967296
	end
	return string.format("%08x", hash)
end

local function sortNumericIds(ids)
	table.sort(ids, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return ids
end

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

--- Build a structured fingerprint for the open profession UI.
--- Returns nil when the trade skill UI has no usable profession info.
--- Fields: fingerprint, metaFingerprint, skillLineID, recipeIDs, recipeCount, recipeHash, stable
function AuctionHelper:BuildOpenProfessionQuickFingerprint()
	if not self.IS_SUPPORTED or not C_TradeSkillUI then
		return nil
	end
	local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	if not baseInfo then
		return nil
	end
	local baseSkillLineID = tonumber(baseInfo.professionID or baseInfo.profession or baseInfo.skillLineID)
	local childInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo() or nil
	local skillLineID = tonumber(childInfo and (childInfo.professionID or childInfo.profession or childInfo.skillLineID)) or baseSkillLineID
	if not skillLineID then
		return nil
	end
	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and self:NormalizeApiList(C_TradeSkillUI.GetAllRecipeIDs()) or {}
	sortNumericIds(recipeIDs)
	local configID = C_ProfSpecs and C_ProfSpecs.GetConfigIDForSkillLine and C_ProfSpecs.GetConfigIDForSkillLine(skillLineID) or 0
	if (not configID or configID <= 0) and baseSkillLineID and baseSkillLineID ~= skillLineID
		and C_ProfSpecs and C_ProfSpecs.GetConfigIDForSkillLine then
		configID = C_ProfSpecs.GetConfigIDForSkillLine(baseSkillLineID) or 0
	end
	local currencyInfo = C_ProfSpecs and C_ProfSpecs.GetCurrencyInfoForSkillLine and C_ProfSpecs.GetCurrencyInfoForSkillLine(skillLineID) or nil
	local knowledgeQty = tonumber(currencyInfo and (currencyInfo.amount or currencyInfo.quantity or currencyInfo.totalQuantity)) or 0
	local skillLevel = tonumber(baseInfo.skillLevel) or 0
	local maxSkillLevel = tonumber(baseInfo.maxSkillLevel) or 0
	local bonusSkill = tonumber(baseInfo.bonusSkill) or 0
	local recipeHash = quickArrayHash(recipeIDs)
	local metaFingerprint = table.concat({
		tostring(skillLineID),
		tostring(skillLevel),
		tostring(maxSkillLevel),
		tostring(bonusSkill),
		tostring(configID or 0),
		tostring(knowledgeQty),
	}, "|")
	local fingerprint = table.concat({
		metaFingerprint,
		tostring(#recipeIDs),
		recipeHash,
	}, "|")
	return {
		fingerprint = fingerprint,
		metaFingerprint = metaFingerprint,
		skillLineID = skillLineID,
		baseSkillLineID = baseSkillLineID,
		recipeIDs = recipeIDs,
		recipeCount = #recipeIDs,
		recipeHash = recipeHash,
		configID = configID or 0,
		knowledgeQty = knowledgeQty,
		skillLevel = skillLevel,
		maxSkillLevel = maxSkillLevel,
		bonusSkill = bonusSkill,
		-- Empty recipe lists are common during TRADE_SKILL_SHOW before data loads; do not lock baseline on them.
		stable = #recipeIDs > 0,
	}
end

function AuctionHelper:CancelLiveFingerprintTimer()
	local state = self:GetState()
	if state.liveFingerprintTimer then
		state.liveFingerprintTimer:Cancel()
		state.liveFingerprintTimer = nil
	end
end

--- Apply a fingerprint snapshot into session state. Only locks openFingerprint once stable.
function AuctionHelper:ApplyOpenProfessionFingerprintInfo(info)
	if type(info) ~= "table" or not info.fingerprint then
		return
	end
	local state = self:GetState()
	state.liveProfessionLastFingerprint = info.fingerprint
	state.liveProfessionLastFingerprintInfo = info
	if info.stable then
		if not state.liveProfessionOpenFingerprint then
			state.liveProfessionOpenFingerprint = info.fingerprint
			state.liveProfessionOpenFingerprintInfo = info
			self:DebugLog("LIVE", "openFingerprint locked (stable)", {
				string.format("skillLineID=%s recipeCount=%s", tostring(info.skillLineID), tostring(info.recipeCount)),
			})
		end
	end
end

function AuctionHelper:RefreshOpenProfessionFingerprintNow()
	local info = self:BuildOpenProfessionQuickFingerprint()
	self:ApplyOpenProfessionFingerprintInfo(info)
	return info
end

function AuctionHelper:ScheduleOpenProfessionFingerprintRefresh()
	local state = self:GetState()
	self:CancelLiveFingerprintTimer()
	state.liveFingerprintTimer = C_Timer.NewTimer(LIVE_FINGERPRINT_DEBOUNCE_SEC, function()
		state.liveFingerprintTimer = nil
		if self:LiveUpdatesBlocked() then
			return
		end
		self:RefreshOpenProfessionFingerprintNow()
	end)
end

--- Remember which profession the crafting UI is showing (cheap). Fingerprint rebuild is debounced.
function AuctionHelper:RememberOpenProfessionSkillLineID()
	if not C_TradeSkillUI.GetBaseProfessionInfo then
		return
	end
	local openInfo = C_TradeSkillUI.GetBaseProfessionInfo()
	if not openInfo then
		return
	end
	local state = self:GetState()
	local id = tonumber(openInfo.professionID or openInfo.profession or openInfo.skillLineID)
	if id then
		if state.liveProfessionSkillLineID and state.liveProfessionSkillLineID ~= id then
			-- Switched profession tab/window: reset session fingerprint baseline.
			state.liveProfessionOpenFingerprint = nil
			state.liveProfessionOpenFingerprintInfo = nil
			state.liveProfessionLastFingerprint = nil
			state.liveProfessionLastFingerprintInfo = nil
			self:CancelLiveProfessionMergeJob()
		end
		state.liveProfessionSkillLineID = id
	end
	self:ScheduleOpenProfessionFingerprintRefresh()
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
	for _, p in ipairs(self:GetPlayerProfessions()) do
		if tonumber(p.skillLineID) == openSkillLineID then
			return p
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

--- One merge for a known skill line (window may already be closing; APIs may still be valid briefly).
--- opts.forceFull — full rescan (Scan button / explicit). opts.fingerprintInfo — prebuilt fingerprint.
--- opts.allowChunked — default true for live path; false for forceFull sync scans.
function AuctionHelper:ApplyLiveProfessionMergeForSkillLineID(openSkillLineID, opts)
	opts = type(opts) == "table" and opts or {}
	local forceFull = opts.forceFull == true
	local allowChunked = opts.allowChunked
	if allowChunked == nil then
		allowChunked = not forceFull
	end

	if self:LiveUpdatesBlocked() or self:GetState().pendingScan then
		self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID skipped", {
			string.format("blocked=%s pendingScan=%s", tostring(self:LiveUpdatesBlocked()), tostring(self:GetState().pendingScan)),
		})
		return nil
	end

	if not openSkillLineID then
		return nil
	end

	self:CancelLiveProfessionMergeJob()

	self:InitDB()
	local key, charData = self:GetOrCreateCharacterDataForLiveUpdate()
	local skillKey = tostring(openSkillLineID)
	local existing = charData.professions and charData.professions[skillKey] or nil

	local fingerprintInfo = opts.fingerprintInfo
	if type(fingerprintInfo) ~= "table" then
		local filterSnapshot = self:SnapshotFilters()
		self:ApplyExportFilters()
		fingerprintInfo = self:BuildOpenProfessionQuickFingerprint()
		self:RestoreFilters(filterSnapshot)
	end

	-- Avoid wiping good SavedVariables when the UI tears down before recipes are available.
	if not forceFull and fingerprintInfo and not fingerprintInfo.stable
		and existing and tonumber(existing.recipeCount) and tonumber(existing.recipeCount) > 0 then
		self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID skipped (unstable fingerprint, keeping saved)", {
			string.format("skillLineID=%s savedRecipeCount=%s", tostring(openSkillLineID), tostring(existing.recipeCount)),
		})
		return existing
	end

	if not forceFull and existing and fingerprintInfo and existing.liveFingerprint
		and existing.liveFingerprint == fingerprintInfo.fingerprint then
		self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID skipped (saved fingerprint match)", {
			string.format("skillLineID=%s", tostring(openSkillLineID)),
		})
		return existing
	end

	local descriptor = self:FindProfessionDescriptorForSkillLineID(openSkillLineID)
	if not descriptor then
		self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID no matching GetPlayerProfessions entry", {
			string.format("openSkillLineID=%s", tostring(openSkillLineID)),
		})
		return nil
	end

	local hasExistingRecipes = existing and type(existing.recipes) == "table" and next(existing.recipes) ~= nil
	local doFull = forceFull or not hasExistingRecipes

	if doFull then
		local snapshot = self:SnapshotFilters()
		self:ApplyExportFilters()
		local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and self:NormalizeApiList(C_TradeSkillUI.GetAllRecipeIDs()) or {}
		sortNumericIds(recipeIDs)

		if allowChunked and #recipeIDs > LIVE_SYNC_RECIPE_BUDGET then
			self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID collecting (chunked full)", {
				string.format("profession=%s skillLineID=%s recipeCount=%d", tostring(descriptor.professionName), tostring(openSkillLineID), #recipeIDs),
			})
			local professionData = self:CreateProfessionDataShell(descriptor, { rebuildSpecs = true })
			self:RestoreFilters(snapshot)
			-- Prefer a fingerprint taken under the same filter state used for collection.
			local filteredFp = self:BuildOpenProfessionQuickFingerprint() or fingerprintInfo
			self:StartChunkedRecipeMergeJob({
				key = key,
				charData = charData,
				openSkillLineID = openSkillLineID,
				descriptor = descriptor,
				professionData = professionData,
				recipeSpellIDs = recipeIDs,
				fingerprintInfo = filteredFp,
				mode = "chunked_full",
			})
			return nil
		end

		self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID collecting (full)", {
			string.format("profession=%s skillLineID=%s", tostring(descriptor.professionName), tostring(openSkillLineID)),
		})
		local professionData = self:CollectCurrentProfessionData(descriptor)
		-- Stamp while export filters are still applied so liveFingerprint matches close-path compares.
		local filteredFp = self:BuildOpenProfessionQuickFingerprint() or fingerprintInfo
		self:RestoreFilters(snapshot)
		if not professionData then
			self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID CollectCurrentProfessionData returned nil", {})
			return nil
		end
		if filteredFp then
			self:StampProfessionLiveFingerprint(professionData, filteredFp)
		end
		return self:CommitLiveProfessionMergeResult(key, charData, openSkillLineID, professionData, {
			mode = forceFull and "force_full" or "full",
			refreshInventory = true,
			forceImmediateInventory = forceFull,
		})
	end

	-- Incremental path: keep existing recipe rows; collect only new spell IDs; rebuild specs when meta changes.
	local knownSpellSet = buildKnownSpellSet(self, existing)
	local newSpellIDs = listNewSpellIDs(fingerprintInfo and fingerprintInfo.recipeIDs, knownSpellSet)
	local currentSpellSet = buildSpellIDSet(fingerprintInfo and fingerprintInfo.recipeIDs)
	local needSpecs = true
	if fingerprintInfo and fingerprintInfo.metaFingerprint and existing.liveMetaFingerprint
		and existing.liveMetaFingerprint == fingerprintInfo.metaFingerprint
		and existing.specializationTrees then
		needSpecs = false
	end
	if self:GetSetting("capture.captureSpecializationTree", true) == false then
		needSpecs = false
	end

	local pruned = self:PruneProfessionRecipesNotInSpellSet(existing, currentSpellSet)
	local recipesChanged = (#newSpellIDs > 0) or (pruned > 0)

	if not recipesChanged and not needSpecs then
		local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
		local childInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo() or nil
		self:UpdateProfessionDescriptorFields(existing, descriptor, baseInfo, childInfo)
		self:StampProfessionLiveFingerprint(existing, fingerprintInfo)
		self:BumpDataRevision()
		self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID metadata-only stamp", {
			string.format("skillLineID=%s", tostring(openSkillLineID)),
		})
		return self:CommitLiveProfessionMergeResult(key, charData, openSkillLineID, existing, {
			mode = "metadata",
			refreshInventory = false,
		})
	end

	self:DebugLog("LIVE", "ApplyLiveProfessionMergeForSkillLineID collecting (incremental)", {
		string.format("profession=%s skillLineID=%s", tostring(descriptor.professionName), tostring(openSkillLineID)),
		string.format("newRecipes=%d pruned=%d needSpecs=%s", #newSpellIDs, pruned, tostring(needSpecs)),
	})

	local snapshot = self:SnapshotFilters()
	self:ApplyExportFilters()

	local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	local childInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo() or nil
	local categories = self:CollectRecipeCategories()
	self:UpdateProfessionDescriptorFields(existing, descriptor, baseInfo, childInfo)
	existing.categories = categories

	if needSpecs then
		local captureSpec = self:GetSetting("capture.captureSpecializationTree", true) ~= false
		local specResult = captureSpec and self:CollectSpecializationTreesForProfession(
			descriptor.skillLineID,
			childInfo,
			categories,
			descriptor.currentLevelName
		) or nil
		self:ApplySpecializationResultToProfessionData(existing, specResult)
	end

	self:RestoreFilters(snapshot)

	if allowChunked and #newSpellIDs > LIVE_SYNC_RECIPE_BUDGET then
		self:StartChunkedRecipeMergeJob({
			key = key,
			charData = charData,
			openSkillLineID = openSkillLineID,
			descriptor = descriptor,
			professionData = existing,
			recipeSpellIDs = newSpellIDs,
			fingerprintInfo = fingerprintInfo,
			mode = "chunked_incremental",
		})
		return nil
	end

	if #newSpellIDs > 0 then
		self:BeginProfessionCollectCaches()
		self:CollectRecipesIntoProfessionData(existing, newSpellIDs, 1, #newSpellIDs)
		self:EndProfessionCollectCaches()
	end

	self:FinalizeProfessionDataCollect(existing, descriptor, fingerprintInfo)
	return self:CommitLiveProfessionMergeResult(key, charData, openSkillLineID, existing, {
		mode = "incremental",
		refreshInventory = recipesChanged,
		forceImmediateInventory = false,
	})
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
