local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
function Tradewright:FinishScan()
	self:DebugLog("SCAN", "FinishScan", {
		string.format("characterKey=%s", tostring(self:GetCharacterKey())),
	})
	self:InitDB()
	local state = self:GetState()
	local exportFullAfterScan = state.exportFullAfterScan == true
	state.exportFullAfterScan = nil
	state.scanInProgress = false
	state.currentProfession = nil
	state.queue = {}
	state.pendingScan = false

	local characterKey = self:GetCharacterKey()
	local characterData = state.currentCharacterData
	if characterData then
		characterData.scanFinishedAt = time()
		self:UpdateInventorySnapshot(characterData, { forceImmediate = true })
		self.db.characters[characterKey] = characterData
		table.insert(self.db.history, 1, {
			characterKey = characterKey,
			finishedAt = characterData.scanFinishedAt,
			professionCount = self:TableCount(characterData.professions),
		})
		while #self.db.history > 20 do
			table.remove(self.db.history)
		end
		self:BuildAggregate()
	end

	self:PrintMessage(string.format(L["Scan finished. Stored %d professions for %s."],
		characterData and self:TableCount(characterData.professions) or 0,
		characterKey))

	self:NotifyDashboardUpdate(true)
	self:DebugLog("SCAN", "FinishScan complete", {
		string.format("professionsStored=%s", tostring(characterData and self:TableCount(characterData.professions) or 0)),
	})

	if exportFullAfterScan and characterData then
		C_Timer.After(0, function()
			self:PrintMessage(L["Fresh scan complete. Preparing full character export."])
			self:Export("character")
		end)
	end
end

function Tradewright:StartFullCharacterDump()
	local state = self:GetState()
	if state.scanInProgress then
		self:PrintMessage(L["A scan is already in progress. Wait for it to finish, then run the full export again."])
		return
	end

	self:SetSetting("capture.captureSpecializationTree", true)
	state.exportFullAfterScan = true
	self:PrintMessage(L["Scanning every profession before the full export."])
	if self:StartScan() ~= true then
		state.exportFullAfterScan = nil
	end
end

function Tradewright:ProcessNextProfession()
	local state = self:GetState()
	if not state.scanInProgress then
		return
	end

	local nextProfession = table.remove(state.queue, 1)
	if not nextProfession then
		self:FinishScan()
		return
	end

	state.currentProfession = nextProfession
	state.pendingScan = false
	state.filterSnapshot = self:SnapshotFilters()

	self:PrintMessage(string.format(L["Opening %s (%d remaining)…"], tostring(nextProfession.professionName), #state.queue))
	self:DebugLog("SCAN", "ProcessNextProfession", {
		string.format(L["opening=%s skillLineID=%s remainingQueue=%d"], tostring(nextProfession.professionName), tostring(nextProfession.skillLineID), #state.queue),
	})
	C_TradeSkillUI.OpenTradeSkill(nextProfession.skillLineID)
end

function Tradewright:TryScanCurrentProfession()
	local state = self:GetState()
	if not state.scanInProgress or not state.currentProfession or state.pendingScan then
		return
	end

	local openInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	if not openInfo then
		return
	end

	local openSkillLineID = openInfo.professionID or openInfo.profession or openInfo.skillLineID
	if tonumber(openSkillLineID) ~= tonumber(state.currentProfession.skillLineID) then
		return
	end

	state.pendingScan = true
	self:DebugLog("SCAN", "TryScanCurrentProfession scheduled capture", {
		string.format(L["profession=%s skillLineID=%s waitSec=%s"], tostring(state.currentProfession.professionName), tostring(state.currentProfession.skillLineID), tostring(self.SCAN_WAIT_SECONDS)),
	})
	C_Timer.After(self.SCAN_WAIT_SECONDS, function()
		if not state.scanInProgress or not state.currentProfession then
			self:DebugLog("SCAN", "TryScanCurrentProfession timer aborted", {})
			return
		end

		self:ApplyExportFilters()
		local professionData = self:CollectCurrentProfessionData(state.currentProfession)
		self:RestoreFilters(state.filterSnapshot)

		if professionData then
			state.currentCharacterData.professions[tostring(state.currentProfession.skillLineID)] = professionData
			local specTierCount = professionData.specializationTrees and self:TableCount(professionData.specializationTrees) or 0
			self:PrintMessage(string.format(
				L["Scanned %s: %d recipes, %d specialization tier(s)."],
				tostring(professionData.professionName),
				professionData.recipeCount or 0,
				specTierCount
			))
			self:DebugLog("SCAN", "TryScanCurrentProfession captured", {
				string.format(L["profession=%s recipeCount=%s specTierCount=%s primarySpecSkillLineID=%s"],
					tostring(professionData.professionName),
					tostring(professionData.recipeCount),
					tostring(specTierCount),
					tostring(professionData.primarySpecializationSkillLineID)),
			})
		else
			self:PrintMessage(string.format(L["Skipping %s: no profession data returned."], tostring(state.currentProfession.professionName)))
			self:DebugLog("SCAN", "TryScanCurrentProfession no professionData", {})
		end

		state.pendingScan = false
		state.currentProfession = nil

		if C_TradeSkillUI.CloseTradeSkill then
			C_TradeSkillUI.CloseTradeSkill()
		end

		C_Timer.After(0.1, function()
			self:ProcessNextProfession()
		end)
	end)
end

function Tradewright:ScanOpenProfession()
	if not self.IS_SUPPORTED then
		self:PrintMessage(L["Profession scan requires retail or Forever WoW."])
		return false
	end

	local state = self:GetState()
	if state.scanInProgress then
		self:PrintMessage(L["A full character scan is already running. Wait for it to finish."])
		return false
	end

	local openInfo = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
	if not openInfo then
		self:PrintMessage(L["Open a profession window first, then click Scan."])
		return false
	end

	local skillLineID = tonumber(openInfo.professionID or openInfo.profession or openInfo.skillLineID)
	if not skillLineID then
		self:PrintMessage(L["Could not resolve the open profession skill line."])
		return false
	end

	local professionData = self:ApplyLiveProfessionMergeForSkillLineID(skillLineID, {
		forceFull = true,
		allowChunked = false,
	})
	if not professionData then
		self:PrintMessage(L["Profession scan failed. Try reopening the profession window."])
		return false
	end

	local specTierCount = professionData.specializationTrees and self:TableCount(professionData.specializationTrees) or 0
	self:PrintMessage(string.format(
		L["Saved %s: %d recipes, %d specialization tier(s)."],
		tostring(professionData.professionName or openInfo.professionName or skillLineID),
		professionData.recipeCount or 0,
		specTierCount
	))
	return true
end

function Tradewright:StartScan()
	if not self.IS_SUPPORTED then
		self:PrintMessage(L["This exporter currently supports retail and Forever only."])
		return
	end

	local state = self:GetState()
	if state.scanInProgress then
		self:PrintMessage(L["A scan is already in progress."])
		return
	end

	self:InitDB()
	local professions = self:GetPlayerProfessions()
	if #professions == 0 then
		self:PrintMessage(L["No learned professions found on this character."])
		return
	end

	state.scanInProgress = true
	state.currentCharacterData = self:CreateCharacterScanRecord()
	state.queue = professions
	state.currentProfession = nil
	state.pendingScan = false

	self:PrintMessage(string.format(L["Starting profession scan for %d professions."], #professions))
	self:DebugLog("SCAN", "StartScan", {
		string.format(L["professionCount=%d characterKey=%s"], #professions, self:GetCharacterKey()),
	})
	self:ProcessNextProfession()
	return true
end
