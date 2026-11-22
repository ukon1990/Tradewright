-- Run with: lua5.1 tests/test_live_update.lua (from Tradewright root)
-- Live profession merge: when the saved profession is kept, when a full collect runs (sync or chunked),
-- and what the incremental merge collects, prunes and commits.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addons = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local allRecipeIDs = {}
local wowGlobals = {
	time = function()
		return 5000
	end,
	C_TradeSkillUI = {
		GetAllRecipeIDs = function()
			return allRecipeIDs
		end,
		GetBaseProfessionInfo = function()
			return { professionID = 164 }
		end,
		GetChildProfessionInfo = function()
			return { professionID = 2907 }
		end,
	},
	C_Timer = { After = function() end },
}
for name, value in pairs(wowGlobals) do
	rawset(_G, name, value)
end

local SKILL = 164
local DESCRIPTOR = { skillLineID = SKILL, professionName = "Blacksmithing", currentLevelName = "Midnight" }

local function range(from, to)
	local out = {}
	for i = from, to do
		out[#out + 1] = i
	end
	return out
end

local function savedProfession(recipeIDs, extra)
	local data = { recipes = {}, recipeCount = #recipeIDs, liveFingerprint = "fp-old", liveMetaFingerprint = "meta-1",
		specializationTrees = { x = true } }
	for _, id in ipairs(recipeIDs) do
		data.recipes[tostring(id)] = { spellID = id }
	end
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	return data
end

local function newAddon(saved, settings)
	settings = settings or {}
	local state = {}
	local pe = { db = { characters = {} }, IS_SUPPORTED = true, calls = {}, commits = {}, jobs = {}, collected = {},
		filterDepth = 0, specApplied = 0 }
	if saved then
		pe.db.characters["Me-Realm"] = { professions = { [tostring(SKILL)] = saved } }
	end
	local function note(name)
		pe.calls[#pe.calls + 1] = name
	end
	function pe:GetState()
		return state
	end
	function pe:DebugLog() end
	function pe:InitDB() end
	function pe:GetCharacterKey()
		return "Me-Realm"
	end
	function pe:CreateCharacterScanRecord()
		return { professions = {} }
	end
	function pe:GetCharacterMetadata()
		return { name = "Me" }
	end
	function pe:BumpDataRevision()
		note("BumpDataRevision")
	end
	function pe:NotifyDashboardUpdate() end
	function pe:RefreshRecipeDifficulties() end
	function pe:SnapshotFilters()
		self.filterDepth = self.filterDepth + 1
		return {}
	end
	function pe:ApplyExportFilters() end
	function pe:RestoreFilters()
		self.filterDepth = self.filterDepth - 1
	end
	function pe:GetPlayerProfessions()
		return self.noDescriptor and {} or { DESCRIPTOR }
	end
	function pe:NormalizeApiList(list)
		local out = {}
		for i, v in ipairs(list) do
			out[i] = v
		end
		return out
	end
	function pe:CreateProfessionDataShell(descriptor)
		return { shell = true, professionName = descriptor.professionName }
	end
	function pe:CollectCurrentProfessionData(descriptor)
		if self.collectFails then
			return nil
		end
		return { full = true, professionName = descriptor.professionName, recipeCount = #allRecipeIDs }
	end
	function pe:StampProfessionLiveFingerprint(data, fp)
		data.liveFingerprint = fp.fingerprint
	end
	function pe:UpdateInventorySnapshot(_, opts)
		self.inventoryOpts = opts
	end
	function pe:GetRecipeSpellID(recipeData)
		return recipeData.spellID
	end
	function pe:GetSetting(key, default)
		if settings[key] ~= nil then
			return settings[key]
		end
		return default
	end
	function pe:PruneProfessionRecipesNotInSpellSet(data, spellSet)
		local pruned = 0
		for key, recipe in pairs(data.recipes) do
			if not spellSet[recipe.spellID] then
				data.recipes[key] = nil
				pruned = pruned + 1
			end
		end
		return pruned
	end
	function pe:UpdateProfessionDescriptorFields(data)
		data.descriptorUpdated = true
	end
	function pe:CollectRecipeCategories()
		return { "cat" }
	end
	function pe:CollectSpecializationTreesForProfession()
		return { trees = true }
	end
	function pe:ApplySpecializationResultToProfessionData()
		self.specApplied = self.specApplied + 1
	end
	function pe:BeginProfessionCollectCaches() end
	function pe:EndProfessionCollectCaches() end
	function pe:CollectRecipesIntoProfessionData(_, ids, from, to)
		for i = from, to do
			self.collected[#self.collected + 1] = ids[i]
		end
	end
	function pe:FinalizeProfessionDataCollect(data, _, fp)
		data.finalizedWith = fp
	end

	assert(loadfile(addons .. "/Tradewright_Professions/src/modules/Tradewright_ProfessionFingerprint.lua"))("Tradewright", pe)
	local chunk, err = loadfile(addons .. "/Tradewright_Professions/src/modules/Tradewright_LiveUpdate.lua")
	assert(chunk, err)
	chunk("Tradewright", pe)

	local commit = pe.CommitLiveProfessionMergeResult
	function pe:CommitLiveProfessionMergeResult(key, charData, skillLineID, data, opts)
		self.commits[#self.commits + 1] = { data = data, opts = opts }
		return commit(self, key, charData, skillLineID, data, opts)
	end
	function pe:StartChunkedRecipeMergeJob(job)
		self.jobs[#self.jobs + 1] = job
	end
	function pe:BuildOpenProfessionQuickFingerprint()
		return self.fingerprint
	end
	return pe
end

local function fingerprint(recipeIDs, extra)
	local fp = { stable = true, fingerprint = "fp-new", metaFingerprint = "meta-1", recipeIDs = recipeIDs }
	for k, v in pairs(extra or {}) do
		fp[k] = v
	end
	return fp
end

local function merge(pe, opts)
	return pe:ApplyLiveProfessionMergeForSkillLineID(SKILL, opts)
end

local function stored(pe)
	return pe.db.characters["Me-Realm"].professions[tostring(SKILL)]
end

-- Guards

do
	local pe = newAddon()
	pe:GetState().scanInProgress = true
	check("Guard: blocked during a scan", merge(pe) == nil and #pe.commits == 0)
	pe:GetState().scanInProgress = nil
	pe:GetState().pendingScan = true
	check("Guard: blocked by a pending scan", merge(pe) == nil and #pe.commits == 0)
	pe:GetState().pendingScan = nil
	check("Guard: no skill line", pe:ApplyLiveProfessionMergeForSkillLineID(nil) == nil and #pe.commits == 0)
end

do
	local saved = savedProfession({ 1, 2 })
	local pe = newAddon(saved)
	pe.fingerprint = fingerprint({}, { stable = false })
	check("Guard: unstable fingerprint keeps saved recipes", merge(pe) == saved and #pe.commits == 0)
	check("Guard: filters restored after fingerprint", pe.filterDepth == 0)
end

do
	local saved = savedProfession({ 1, 2 })
	local pe = newAddon(saved)
	check("Guard: saved fingerprint match keeps saved",
		merge(pe, { fingerprintInfo = fingerprint({ 1, 2 }, { fingerprint = "fp-old" }) }) == saved and #pe.commits == 0)
end

do
	local pe = newAddon(savedProfession({ 1 }))
	pe.noDescriptor = true
	check("Guard: profession not known to the player", merge(pe, { fingerprintInfo = fingerprint({ 1, 3 }) }) == nil and #pe.commits == 0)
end

-- Full merge

do
	allRecipeIDs = { 30, 10, 20 }
	local pe = newAddon()
	pe.fingerprint = fingerprint({ 10, 20, 30 }, { fingerprint = "fp-filtered" })
	local result = merge(pe)
	check("Full: no saved recipes collects everything", result and result.full == true)
	check("Full: stamped with the filtered fingerprint", result.liveFingerprint == "fp-filtered")
	check("Full: stored under the skill line", stored(pe) == result)
	check("Full: mode full, inventory refreshed later", pe.commits[1].opts.mode == "full"
		and pe.inventoryOpts and pe.inventoryOpts.forceImmediate == false)
	check("Full: filters restored", pe.filterDepth == 0)
	check("Full: last live update stamped", pe.db.characters["Me-Realm"].lastLiveProfessionUpdate == 5000)
end

do
	allRecipeIDs = { 1, 2 }
	local pe = newAddon(savedProfession({ 1, 2 }))
	local result = merge(pe, { forceFull = true, fingerprintInfo = fingerprint({ 1, 2 }, { fingerprint = "fp-old" }) })
	check("Full: force ignores a fingerprint match", result and result.full == true)
	check("Full: forced mode and immediate inventory", pe.commits[1].opts.mode == "force_full" and pe.inventoryOpts.forceImmediate == true)
end

do
	allRecipeIDs = { 1 }
	local pe = newAddon()
	pe.collectFails = true
	pe.fingerprint = fingerprint({ 1 })
	check("Full: failed collect returns nil", merge(pe) == nil and #pe.commits == 0 and pe.filterDepth == 0)
end

do
	allRecipeIDs = range(1, 51)
	allRecipeIDs[1], allRecipeIDs[51] = 51, 1
	local pe = newAddon()
	pe.fingerprint = fingerprint({}, { fingerprint = "fp-chunk" })
	check("Full chunked: large list returns nil", merge(pe) == nil and #pe.commits == 0)
	local job = pe.jobs[1]
	check("Full chunked: job started", job and job.mode == "chunked_full" and job.professionData.shell == true)
	check("Full chunked: recipe ids sorted", job.recipeSpellIDs[1] == 1 and job.recipeSpellIDs[51] == 51)
	check("Full chunked: job carries merge target", job.key == "Me-Realm" and job.openSkillLineID == SKILL and job.descriptor == DESCRIPTOR
		and job.fingerprintInfo.fingerprint == "fp-chunk")
	check("Full chunked: filters restored", pe.filterDepth == 0)
end

do
	allRecipeIDs = range(1, 51)
	local pe = newAddon()
	pe.fingerprint = fingerprint({})
	local result = merge(pe, { forceFull = true })
	check("Full: forced merge collects sync even when large", result and result.full == true and #pe.jobs == 0)
	local pe2 = newAddon()
	pe2.fingerprint = fingerprint({})
	merge(pe2, { allowChunked = false })
	check("Full: chunking can be turned off", #pe2.jobs == 0 and #pe2.commits == 1)
end

-- Incremental merge

do
	local saved = savedProfession({ 1, 2 })
	local pe = newAddon(saved)
	local result = merge(pe, { fingerprintInfo = fingerprint({ 1, 2 }) })
	check("Metadata: unchanged recipes and specs only restamp", result == saved and saved.liveFingerprint == "fp-new")
	check("Metadata: commit without inventory refresh", pe.commits[1].opts.mode == "metadata" and pe.inventoryOpts == nil)
	check("Metadata: descriptor refreshed, nothing collected", saved.descriptorUpdated and #pe.collected == 0 and pe.specApplied == 0)
end

do
	local saved = savedProfession({ 1, 2 })
	local pe = newAddon(saved)
	local fp = fingerprint({ 2, 3, 4 })
	local result = merge(pe, { fingerprintInfo = fp })
	check("Incremental: keeps the saved table", result == saved)
	check("Incremental: collects only new recipes", #pe.collected == 2 and pe.collected[1] == 3 and pe.collected[2] == 4)
	check("Incremental: drops recipes no longer listed", saved.recipes["1"] == nil and saved.recipes["2"] ~= nil)
	check("Incremental: mode and inventory refresh", pe.commits[1].opts.mode == "incremental" and pe.inventoryOpts ~= nil)
	check("Incremental: categories and finalize", saved.categories[1] == "cat" and saved.finalizedWith == fp)
	check("Incremental: specs not rebuilt when meta unchanged", pe.specApplied == 0)
	check("Incremental: filters restored", pe.filterDepth == 0)
end

do
	local saved = savedProfession({ 1 })
	local pe = newAddon(saved)
	merge(pe, { fingerprintInfo = fingerprint({ 1 }, { metaFingerprint = "meta-2" }) })
	check("Incremental: changed meta rebuilds specs", pe.specApplied == 1)
	check("Incremental: spec-only change skips inventory", pe.commits[1].opts.mode == "incremental" and pe.inventoryOpts == nil)
end

do
	local saved = savedProfession({ 1 })
	local pe = newAddon(saved, { ["capture.captureSpecializationTree"] = false })
	merge(pe, { fingerprintInfo = fingerprint({ 1 }, { metaFingerprint = "meta-2" }) })
	check("Incremental: spec capture off means metadata only", pe.specApplied == 0 and pe.commits[1].opts.mode == "metadata")
end

do
	local saved = savedProfession({ 1 }, { specializationTrees = false })
	local pe = newAddon(saved)
	merge(pe, { fingerprintInfo = fingerprint({ 1 }) })
	check("Incremental: missing spec trees rebuilds specs", pe.specApplied == 1)
end

do
	local saved = savedProfession({ 1 })
	local pe = newAddon(saved)
	local fp = fingerprint(range(1, 52))
	check("Incremental chunked: many new recipes return nil", merge(pe, { fingerprintInfo = fp }) == nil and #pe.commits == 0)
	local job = pe.jobs[1]
	check("Incremental chunked: job over the new ids only", job and job.mode == "chunked_incremental" and #job.recipeSpellIDs == 51
		and job.recipeSpellIDs[1] == 2 and job.professionData == saved and job.fingerprintInfo == fp)
	check("Incremental chunked: categories refreshed first", saved.categories ~= nil and pe.filterDepth == 0)
end

do
	local saved = savedProfession({ 1 })
	local pe = newAddon(saved)
	merge(pe, { fingerprintInfo = fingerprint(range(1, 52)), allowChunked = false })
	check("Incremental: chunking off collects sync", #pe.jobs == 0 and #pe.collected == 51)
end

if failed > 0 then
	print(string.format("%d check(s) failed", failed))
	os.exit(1)
end
print("All live update checks passed")
