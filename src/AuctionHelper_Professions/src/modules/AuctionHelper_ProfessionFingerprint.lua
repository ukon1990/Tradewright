local _, AuctionHelper = ...

-- Fingerprint of the open profession window (skill line, recipe IDs, hash), so live updates merge only when it changed.

local LIVE_FINGERPRINT_DEBOUNCE_SEC = 0.35

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

-- Shared with AuctionHelper_LiveUpdate.lua.
AuctionHelper.ProfessionFingerprint = {
	sortNumericIds = sortNumericIds,
}
