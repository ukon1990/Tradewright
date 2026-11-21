local addonName, AuctionHelper = ...


AuctionHelper.ui = AuctionHelper.ui or {}

function AuctionHelper:GetDashboardCharacterKeyList(db)
	db = db or self.db
	local seen = {}
	local keys = {}
	if type(db.aggregate) == "table" and type(db.aggregate.characterKeys) == "table" then
		for _, k in ipairs(db.aggregate.characterKeys) do
			if k and not seen[k] then
				seen[k] = true
				table.insert(keys, k)
			end
		end
	end
	for k in pairs(db.characters or {}) do
		if not seen[k] then
			seen[k] = true
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	return keys
end

function AuctionHelper:GetDashboardSidebarCharacterLabel(characterKey, charData, currentKey)
	if characterKey == currentKey then
		local base = characterKey
		local meta = charData and charData.meta
		if meta and meta.name and meta.realm then
			base = string.format("%s — %s", tostring(meta.name), tostring(meta.realm))
		end
		return base .. "  " .. self:Colorize("(you)", "33ff99")
	end
	local meta = charData and charData.meta
	if meta and meta.name and meta.realm then
		return string.format("%s — %s", tostring(meta.name), tostring(meta.realm))
	end
	return tostring(characterKey)
end

-- Character name without realm, in its class color when known.
function AuctionHelper:GetCharacterNameMarkup(characterKey)
	local data = self.db and self.db.characters and self.db.characters[characterKey]
	local meta = data and data.meta
	local name = meta and meta.name or (tostring(characterKey or "?"):match("^([^%-]+)") or "?")
	local color = meta and meta.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[meta.class]
	if color then
		return self:Colorize(name, color)
	end
	return name
end

-- "today 14:32", "yesterday 21:40", else "2026-11-17 09:05"; "never" when missing.
function AuctionHelper:FormatScanTimestamp(ts)
	ts = tonumber(ts)
	if not ts or ts <= 0 then
		return "never"
	end
	local day = date("%Y-%m-%d", ts)
	if day == date("%Y-%m-%d") then
		return "today " .. date("%H:%M", ts)
	end
	if day == date("%Y-%m-%d", time() - 86400) then
		return "yesterday " .. date("%H:%M", ts)
	end
	return date("%Y-%m-%d %H:%M", ts)
end

-- Item names the client has not loaded yet come back empty. Ask the client for them once, show
-- "#id" meanwhile, and redraw the visible rows when the names arrive.
local itemNameCache = {}
local itemNameRequested = {}
local itemNameRefreshPending = false

-- `noRequest`: return "#id" for unknown items without asking the client (bulk list building).
function AuctionHelper:GetItemDisplayName(itemID, noRequest)
	if not itemID then
		return "?"
	end
	local id = tonumber(itemID) or itemID
	local cached = itemNameCache[id]
	if cached then
		return cached
	end
	local desc = self:ResolveItemDescriptor(id)
	if desc and desc.name and desc.name ~= "" then
		itemNameCache[id] = desc.name
		self:LearnItemName(id, desc.name)
		return desc.name
	end
	if not noRequest and type(id) == "number" and not itemNameRequested[id] and C_Item and C_Item.RequestLoadItemDataByID then
		itemNameRequested[id] = true
		pcall(C_Item.RequestLoadItemDataByID, id)
	end
	return "#" .. tostring(itemID)
end

-- Re-renders the rows of every visible table without rebuilding their data. Every table created with
-- `CreateReusableTable` is listed in `ReusableTables`, so new tabs need nothing here.
function AuctionHelper:RefreshVisibleItemRows()
	local ui = self.ui or {}
	for tableWidget in pairs(self.ReusableTables or {}) do
		if tableWidget.frame and tableWidget.frame:IsVisible() then
			tableWidget:RefreshRows()
		end
	end
	if ui.activeMainTab == "inventory" and ui.invSelectedItemID and ui.inventoryPanel and ui.inventoryPanel:IsVisible() then
		self:RenderInventoryDetails(ui.invSelectedItemID)
	end
end

local itemNameLoader = CreateFrame("Frame")
itemNameLoader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemNameLoader:SetScript("OnEvent", function(_, _, itemID)
	itemID = tonumber(itemID)
	if not itemID or not itemNameRequested[itemID] then
		return
	end
	itemNameRequested[itemID] = nil
	if itemNameRefreshPending then
		return
	end
	itemNameRefreshPending = true
	C_Timer.After(0.3, function()
		itemNameRefreshPending = false
		AuctionHelper:RefreshVisibleItemRows()
	end)
end)

function AuctionHelper:NotifyDashboardUpdate(skipRebuild)
	local ui = self.ui
	if ui and ui.mainFrame and ui.mainFrame:IsShown() then
		self:RefreshDashboard(skipRebuild)
	end
end

function AuctionHelper:DashboardRefreshInventory()
	local key, data = self:GetOrCreateCharacterDataForLiveUpdate()
	data.lastLiveInventoryUpdate = time()
	self:UpdateInventorySnapshot(data, {
		forceImmediate = false,
		onComplete = function()
			self:PatchAggregateInventorySummaryForCharacter(key, data)
			self:DebugLog("UI", "DashboardRefreshInventory", {
				string.format("characterKey=%s", key),
				string.format("itemTypesTracked=%s", tostring(data.inventorySnapshot and data.inventorySnapshot.itemTypesTracked)),
			})
			self:PrintMessage(string.format("Updated profession-relevant inventory snapshot for %s.", key))
			self:NotifyDashboardUpdate(true)
		end,
	})
end

function AuctionHelper:ExportProgressEncodeStageFrac(steps)
	local k = self.EXPORT_PROGRESS_ENCODE_PROGRESS_K or 80000
	local s = math.max(0, steps or 0)
	return s / (s + k)
end

function AuctionHelper:RefreshExportProgressPhaseLine(f)
	if not f or not f.phaseStr then
		return
	end
	local n = self.EXPORT_PROGRESS_STAGE_COUNT or 2
	if f.barMode == "gather" then
		f.phaseStr:SetText(string.format("Step 1 of %d · %s", n, f.gatherPhaseLabel or "Collecting export data"))
	elseif f.barMode == "encode" and f.phaseBaseText then
		f.phaseStr:SetText(string.format("Step 2 of %d · %s", n, f.phaseBaseText))
	end
end

function AuctionHelper:RefreshExportProgressPctLine(f)
	if not f or not f.pctStr or not f.bar then
		return
	end
	f.pctStr:SetText(string.format("%d%%", math.floor((f.bar:GetValue() or 0) * 100 + 0.5)))
end

--- Floating progress while export gathers data and packs compressed exports (staged monotonic bar).
function AuctionHelper:ShowExportProgress(scopeLabel)
	self.ui = self.ui or {}
	local ui = self.ui
	local f = ui.exportProgressFrame
	if not f then
		local theme = self:GetTheme()
		f = CreateFrame("Frame", addonName .. "ExportProgress", UIParent, "BackdropTemplate")
		f:SetSize(340, theme.size.header + 1 + 12 + 14 + 8 + 14 + 12)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
		f:SetFrameStrata("DIALOG")
		f:SetFrameLevel(500)
		f:SetClampedToScreen(true)
		self:StyleWindow(f)
		f.title = self:CreateText(f, "GameFontNormalLarge", "gold")
		f.title:SetPoint("LEFT", f, "TOPLEFT", 12, -(theme.size.header / 2) - 1)
		f.title:SetPoint("RIGHT", f, "TOPRIGHT", -12, -(theme.size.header / 2) - 1)
		local rule = f:CreateTexture(nil, "BORDER")
		rule:SetPoint("TOPLEFT", 1, -theme.size.header)
		rule:SetPoint("TOPRIGHT", -1, -theme.size.header)
		rule:SetHeight(1)
		rule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
		f.phaseStr = self:CreateText(f, "GameFontHighlightSmall")
		f.phaseStr:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(theme.size.header + 13))
		f.phaseStr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -(theme.size.header + 13))
		f.pctStr = self:CreateText(f, "GameFontHighlightSmall", "textMuted", "RIGHT")
		f.pctStr:SetPoint("TOPRIGHT", f.phaseStr, "BOTTOMRIGHT", 0, -8)
		f.pctStr:SetWidth(36)
		f.bar = CreateFrame("StatusBar", nil, f)
		f.bar:SetPoint("TOPLEFT", f.phaseStr, "BOTTOMLEFT", 0, -8)
		f.bar:SetPoint("RIGHT", f.pctStr, "LEFT", -8, 0)
		self:StyleProgressBar(f.bar)
		f.bar:SetValue(0)

		f:SetScript("OnUpdate", function(sf)
			if sf.barMode ~= "gather" or not sf:IsShown() then
				return
			end
			local wG = AuctionHelper.EXPORT_PROGRESS_GATHER_WEIGHT or 0.30
			local cap = AuctionHelper.EXPORT_PROGRESS_GATHER_CREEP_CAP or 0.95
			local tmax = AuctionHelper.EXPORT_PROGRESS_GATHER_CREEP_MAX_SEC or 5
			local t0 = sf.gatherStartTime or GetTime()
			local elapsed = GetTime() - t0
			local sliceFrac = math.min(cap, elapsed / math.max(0.001, tmax))
			local overall = wG * sliceFrac
			sf.lastOverall = math.max(sf.lastOverall or 0, overall)
			sf.bar:SetValue(sf.lastOverall)
			AuctionHelper:RefreshExportProgressPctLine(sf)
		end)

		ui.exportProgressFrame = f
	end

	f.scopeLabel = scopeLabel or "export"
	f.title:SetText("Exporting " .. tostring(f.scopeLabel))
	f.indeterminateBar = false
	f.barMode = "gather"
	f.gatherStartTime = GetTime()
	f.lastOverall = 0
	f.lastEncodeSteps = 0
	f.bar:SetMinMaxValues(0, 1)
	f.bar:SetValue(0)
	f:Show()
	self:SetExportProgressPhase("Collecting export data", false)
end

--- useStepSuffix: when true, text is a prefix; UpdateExportProgressSteps appends " (N steps)".
function AuctionHelper:SetExportProgressPhase(text, useStepSuffix)
	local f = self.ui and self.ui.exportProgressFrame
	if not f or not f.phaseStr then
		return
	end
	if useStepSuffix then
		local wG = self.EXPORT_PROGRESS_GATHER_WEIGHT or 0.30
		f.barMode = "encode"
		f.lastOverall = math.max(f.lastOverall or 0, wG)
		f.bar:SetValue(f.lastOverall)
		f.phaseBaseText = text or "Packing the export"
		self:UpdateExportProgressSteps(0)
	else
		f.phaseBaseText = nil
		f.gatherPhaseLabel = text or ""
		f.barMode = "gather"
		self:RefreshExportProgressPhaseLine(f)
		self:RefreshExportProgressPctLine(f)
	end
end

function AuctionHelper:UpdateExportProgressSteps(steps)
	local f = self.ui and self.ui.exportProgressFrame
	if not f or not f:IsShown() or not f.phaseStr or not f.phaseBaseText then
		return
	end
	f.lastEncodeSteps = steps or 0
	local wG = self.EXPORT_PROGRESS_GATHER_WEIGHT or 0.30
	local wE = 1 - wG
	local encFrac = math.min(0.999, self:ExportProgressEncodeStageFrac(f.lastEncodeSteps))
	local overall = wG + wE * encFrac
	f.lastOverall = math.max(f.lastOverall or 0, overall)
	f.bar:SetValue(f.lastOverall)
	self:RefreshExportProgressPhaseLine(f)
	self:RefreshExportProgressPctLine(f)
end

--- markComplete: set bar to 100%% before hiding (successful encode).
function AuctionHelper:HideExportProgress(markComplete)
	local f = self.ui and self.ui.exportProgressFrame
	if f then
		f.indeterminateBar = false
		if markComplete and f.bar and f:IsShown() then
			f.bar:SetValue(1)
			if f.pctStr then
				f.pctStr:SetText("100%")
			end
		end
		f.barMode = nil
		f.gatherStartTime = nil
		f.lastOverall = nil
		f.lastEncodeSteps = nil
		f.phaseBaseText = nil
		f.gatherPhaseLabel = nil
		if f.bar then
			f.bar:SetValue(0)
		end
		f:Hide()
	end
end
