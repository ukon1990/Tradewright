local addonName, ProfessionExporter = ...

local ACCT_KEY = ProfessionExporter.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"

local OverviewTab = {}
ProfessionExporter.OverviewTab = OverviewTab

local function getCurrentSelection(pe)
	local ui = pe.ui
	local db = pe.db or {}
	local currentKey = pe:GetCharacterKey()
	local keys = pe:GetDashboardCharacterKeyList(db)
	local selected = ui.selectedCharacterKey
	if selected == ACCT_KEY then
		return selected, db.aggregate or {}, currentKey, keys
	end
	if selected and db.characters and db.characters[selected] then
		return selected, db.characters[selected], currentKey, keys
	end
	if db.characters and db.characters[currentKey] then
		ui.selectedCharacterKey = currentKey
		return currentKey, db.characters[currentKey], currentKey, keys
	end
	if keys[1] then
		ui.selectedCharacterKey = keys[1]
		return keys[1], db.characters[keys[1]], currentKey, keys
	end
	ui.selectedCharacterKey = ACCT_KEY
	return ACCT_KEY, db.aggregate or {}, currentKey, keys
end

local function setSelection(pe, key)
	pe.ui.selectedCharacterKey = key
	pe:RefreshDashboard(true)
end

function OverviewTab:Layout(panel)
	if not panel then
		return
	end
	local width = math.max(640, panel:GetWidth() - 24)
	local height = math.max(420, panel:GetHeight() - 80)
	local gap = 12
	local topCardH = 110
	local topWidths

	if width >= 860 then
		topWidths = {
			240,
			math.floor((width - 240 - (gap * 2)) / 2),
			width - 240 - math.floor((width - 240 - (gap * 2)) / 2) - (gap * 2),
		}
	else
		topWidths = {
			math.floor((width - gap) / 2),
			width - math.floor((width - gap) / 2) - gap,
			width,
		}
	end

	panel.subtitle:SetWidth(width - 12)
	panel.summaryCard:ClearAllPoints()
	panel.summaryCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -58)
	panel.summaryCard:SetSize(topWidths[1], topCardH)
	panel.summaryBody:SetWidth(topWidths[1] - 22)

	panel.quickCard:ClearAllPoints()
	panel.quickCard:SetSize(topWidths[2], topCardH)
	panel.statusCard:ClearAllPoints()

	if width >= 860 then
		panel.quickCard:SetPoint("TOPLEFT", panel.summaryCard, "TOPRIGHT", gap, 0)
		panel.statusCard:SetPoint("TOPLEFT", panel.quickCard, "TOPRIGHT", gap, 0)
		panel.statusCard:SetSize(topWidths[3], topCardH)
	else
		panel.quickCard:SetPoint("TOPLEFT", panel.summaryCard, "TOPRIGHT", gap, 0)
		panel.statusCard:SetPoint("TOPLEFT", panel.summaryCard, "BOTTOMLEFT", 0, -gap)
		panel.statusCard:SetSize(topWidths[3], topCardH)
	end

	panel.statusBody:SetWidth(panel.statusCard:GetWidth() - 24)

	local lowerTopAnchor = width >= 860 and panel.summaryCard or panel.statusCard
	local lowerTopOffset = width >= 860 and -12 or -12
	local sidebarWidth = width >= 860 and 250 or math.max(210, math.floor(width * 0.32))
	local detailWidth = width - sidebarWidth - gap
	local lowerHeight = height - (lowerTopAnchor:GetHeight() * (width >= 860 and 1 or 2)) - 24
	lowerHeight = math.max(420, lowerHeight)

	panel.sidebarCard:ClearAllPoints()
	panel.sidebarCard:SetPoint("TOPLEFT", lowerTopAnchor, "BOTTOMLEFT", 0, lowerTopOffset)
	panel.sidebarCard:SetSize(sidebarWidth, lowerHeight)
	panel.sidebarContent:SetWidth(sidebarWidth - 40)

	panel.detailCard:ClearAllPoints()
	panel.detailCard:SetPoint("TOPLEFT", panel.sidebarCard, "TOPRIGHT", gap, 0)
	panel.detailCard:SetSize(detailWidth, lowerHeight)
	panel.detailTitle:SetWidth(detailWidth - 44)
	panel.detailMeta:SetWidth(detailWidth - 44)
	panel.profCard:SetWidth(detailWidth - 34)
	panel.profContent:SetWidth(detailWidth - 64)
	panel.detailContent:SetWidth(detailWidth - 54)
	panel.detailBody:SetWidth(detailWidth - 64)
	if panel.goldGraphSection then
		panel.goldGraphSection:SetWidth(detailWidth - 20)
		if panel.goldSummary then
			panel.goldSummary:SetWidth(detailWidth - 40)
		end
	end
	if panel.detailScroll and panel.goldGraphSection and panel.profCard then
		panel.detailScroll:ClearAllPoints()
		if panel._overviewScrollUnderProf then
			panel.detailScroll:SetPoint("TOPLEFT", panel.profCard, "BOTTOMLEFT", 0, -10)
		else
			panel.detailScroll:SetPoint("TOPLEFT", panel.goldGraphSection, "BOTTOMLEFT", 0, -10)
		end
		panel.detailScroll:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -28, 10)
	end
end

function OverviewTab:Create(container, uiState)
	local pe = ProfessionExporter
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.overviewPanel = panel

	panel.header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.header:SetPoint("TOPLEFT", 12, -10)
	panel.header:SetText("Overview")

	panel.subtitle = pe:CreateMutedText(panel, 760)
	panel.subtitle:SetPoint("TOPLEFT", panel.header, "BOTTOMLEFT", 0, -6)

	panel.summaryCard = pe:CreateCard(panel, 240, 110, "surface2")
	panel.summaryCard:SetPoint("TOPLEFT", panel.subtitle, "BOTTOMLEFT", 0, -10)
	panel.summaryTitle = pe:CreateSectionTitle(panel.summaryCard, "Account")
	panel.summaryTitle:SetPoint("TOPLEFT", 10, -10)
	panel.summaryBody = pe:CreateMutedText(panel.summaryCard, 218)
	panel.summaryBody:SetPoint("TOPLEFT", panel.summaryTitle, "BOTTOMLEFT", 0, -8)

	panel.quickCard = pe:CreateCard(panel, 310, 110, "surface2")
	panel.quickCard:SetPoint("LEFT", panel.summaryCard, "RIGHT", 12, 0)
	panel.quickTitle = pe:CreateSectionTitle(panel.quickCard, "Quick Actions")
	panel.quickTitle:SetPoint("TOPLEFT", 10, -10)
	panel.scanButton = CreateFrame("Button", nil, panel.quickCard, "UIPanelButtonTemplate")
	panel.scanButton:SetSize(132, 24)
	panel.scanButton:SetPoint("TOPLEFT", panel.quickTitle, "BOTTOMLEFT", 0, -8)
	panel.scanButton:SetText("Scan professions")
	panel.scanButton:SetScript("OnClick", function()
		pe:StartScan()
	end)
	panel.refreshInvButton = CreateFrame("Button", nil, panel.quickCard, "UIPanelButtonTemplate")
	panel.refreshInvButton:SetSize(146, 24)
	panel.refreshInvButton:SetPoint("LEFT", panel.scanButton, "RIGHT", 8, 0)
	panel.refreshInvButton:SetText("Refresh inventory")
	panel.refreshInvButton:SetScript("OnClick", function()
		pe:DashboardRefreshInventory()
	end)
	panel.exportCharacterButton = CreateFrame("Button", nil, panel.quickCard, "UIPanelButtonTemplate")
	panel.exportCharacterButton:SetSize(132, 22)
	panel.exportCharacterButton:SetPoint("TOPLEFT", panel.scanButton, "BOTTOMLEFT", 0, -8)
	panel.exportCharacterButton:SetText("Export character")
	panel.exportCharacterButton:SetScript("OnClick", function()
		pe:Export("character")
	end)
	panel.exportAccountButton = CreateFrame("Button", nil, panel.quickCard, "UIPanelButtonTemplate")
	panel.exportAccountButton:SetSize(146, 22)
	panel.exportAccountButton:SetPoint("LEFT", panel.exportCharacterButton, "RIGHT", 8, 0)
	panel.exportAccountButton:SetText("Export account")
	panel.exportAccountButton:SetScript("OnClick", function()
		pe:Export("account")
	end)

	panel.statusCard = pe:CreateCard(panel, 310, 110, "surface2")
	panel.statusCard:SetPoint("LEFT", panel.quickCard, "RIGHT", 12, 0)
	panel.statusTitle = pe:CreateSectionTitle(panel.statusCard, "Status")
	panel.statusTitle:SetPoint("TOPLEFT", 10, -10)
	panel.statusBadge = pe:CreateStatusBadge(panel.statusCard, "Ready", "success")
	panel.statusBadge:SetPoint("TOPLEFT", panel.statusTitle, "BOTTOMLEFT", 0, -8)
	panel.statusBody = pe:CreateMutedText(panel.statusCard, 286)
	panel.statusBody:SetPoint("TOPLEFT", panel.statusBadge, "BOTTOMLEFT", 0, -8)

	panel.sidebarCard = pe:CreateCard(panel, 250, 360, "surface2")
	panel.sidebarCard:SetPoint("TOPLEFT", panel.summaryCard, "BOTTOMLEFT", 0, -12)
	panel.sidebarTitle = pe:CreateSectionTitle(panel.sidebarCard, "Characters")
	panel.sidebarTitle:SetPoint("TOPLEFT", 10, -10)
	panel.sidebarScroll = CreateFrame("ScrollFrame", addonName .. "OverviewSidebarScroll", panel.sidebarCard, "UIPanelScrollFrameTemplate")
	panel.sidebarScroll:SetPoint("TOPLEFT", panel.sidebarTitle, "BOTTOMLEFT", 0, -8)
	panel.sidebarScroll:SetPoint("BOTTOMRIGHT", panel.sidebarCard, "BOTTOMRIGHT", -28, 10)
	panel.sidebarContent = CreateFrame("Frame", nil, panel.sidebarScroll)
	panel.sidebarContent:SetWidth(210)
	panel.sidebarContent:SetHeight(320)
	panel.sidebarScroll:SetScrollChild(panel.sidebarContent)
	panel.charButtons = {}

	panel.detailCard = pe:CreateCard(panel, 644, 360, "surface2")
	panel.detailCard:SetPoint("TOPLEFT", panel.sidebarCard, "TOPRIGHT", 12, 0)
	panel.detailTitle = panel.detailCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.detailTitle:SetPoint("TOPLEFT", 10, -10)
	panel.detailTitle:SetWidth(600)
	panel.detailTitle:SetJustifyH("LEFT")
	panel.detailMeta = pe:CreateMutedText(panel.detailCard, 600)
	panel.detailMeta:SetPoint("TOPLEFT", panel.detailTitle, "BOTTOMLEFT", 0, -6)

	panel.goldGraphSection = pe:CreateCard(panel.detailCard, 610, 208, "surface3")
	panel.goldGraphSection:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -8)
	panel.goldSummaryTitle = pe:CreateSectionTitle(panel.goldGraphSection, "Gold")
	panel.goldSummaryTitle:SetPoint("TOPLEFT", 10, -8)
	panel.goldSummary = pe:CreateMutedText(panel.goldGraphSection, 560)
	panel.goldSummary:SetPoint("TOPLEFT", panel.goldSummaryTitle, "BOTTOMLEFT", 0, -4)

	panel.overviewWalletDropdown = pe:CreateSingleSelectDropdown(panel.goldGraphSection, {
		label = "Series",
		width = 200,
		getOptions = function()
			return {
				{ value = "balance", label = "Current gold" },
				{ value = "earned", label = "Gold earned" },
			}
		end,
		getValue = function()
			return ProfessionExporter:GetSetting("overview.walletGraphMetric", "balance")
		end,
		setValue = function(value)
			ProfessionExporter:SetSetting("overview.walletGraphMetric", value)
		end,
		onChanged = function()
			OverviewTab:Refresh()
		end,
	})
	panel.overviewWalletDropdown:SetPoint("TOPLEFT", panel.goldSummary, "BOTTOMLEFT", -16, -6)

	panel.overviewWalletGraph = pe:CreateTimeSeriesGraph(panel.goldGraphSection, {
		showTitle = false,
		plotHeight = 102,
		emptyText = "No wallet snapshots in this range yet.",
	})
	panel.overviewWalletGraph:SetPoint("TOPLEFT", panel.overviewWalletDropdown, "BOTTOMLEFT", -16, -4)
	panel.overviewWalletGraph:SetPoint("TOPRIGHT", panel.goldGraphSection, "TOPRIGHT", -10, -74)

	panel.profCard = pe:CreateCard(panel.detailCard, 610, 90, "surface3")
	panel.profCard:SetPoint("TOPLEFT", panel.goldGraphSection, "BOTTOMLEFT", 0, -10)
	panel.profTitle = pe:CreateSectionTitle(panel.profCard, "Per-profession exports")
	panel.profTitle:SetPoint("TOPLEFT", 10, -10)
	panel.profScroll = CreateFrame("ScrollFrame", addonName .. "OverviewProfessionScroll", panel.profCard, "UIPanelScrollFrameTemplate")
	panel.profScroll:SetPoint("TOPLEFT", panel.profTitle, "BOTTOMLEFT", 0, -8)
	panel.profScroll:SetPoint("BOTTOMRIGHT", panel.profCard, "BOTTOMRIGHT", -28, 8)
	panel.profContent = CreateFrame("Frame", nil, panel.profScroll)
	panel.profContent:SetWidth(580)
	panel.profContent:SetHeight(60)
	panel.profScroll:SetScrollChild(panel.profContent)
	panel.profRows = {}

	panel.detailScroll = CreateFrame("ScrollFrame", addonName .. "OverviewDetailScroll", panel.detailCard, "UIPanelScrollFrameTemplate")
	panel.detailScroll:SetPoint("TOPLEFT", panel.profCard, "BOTTOMLEFT", 0, -10)
	panel.detailScroll:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -28, 10)
	panel.detailContent = CreateFrame("Frame", nil, panel.detailScroll)
	panel.detailContent:SetWidth(600)
	panel.detailContent:SetHeight(220)
	panel.detailScroll:SetScrollChild(panel.detailContent)
	panel.detailBody = pe:CreateMutedText(panel.detailContent, 580)
	panel.detailBody:SetPoint("TOPLEFT", 4, -4)
	panel:SetScript("OnSizeChanged", function()
		OverviewTab:Layout(panel)
	end)
	panel.profCard:Hide()
	panel._overviewScrollUnderProf = false
	OverviewTab:Layout(panel)

	return panel
end

function OverviewTab:ApplyTheme()
	local panel = ProfessionExporter.ui.overviewPanel
	if not panel then
		return
	end
	local pe = ProfessionExporter
	pe:StylePanel(panel.summaryCard, "surface2")
	pe:StylePanel(panel.quickCard, "surface2")
	pe:StylePanel(panel.statusCard, "surface2")
	pe:StylePanel(panel.sidebarCard, "surface2")
	pe:StylePanel(panel.detailCard, "surface2")
	pe:StylePanel(panel.profCard, "surface3")
	if panel.goldGraphSection then
		pe:StylePanel(panel.goldGraphSection, "surface3")
	end
end

function OverviewTab:Refresh()
	local pe = ProfessionExporter
	pe:InitDB()
	if pe:AggregateNeedsRebuild() then
		pe:BuildAggregate()
	end

	local panel = pe.ui.overviewPanel
	if not panel then
		return
	end

	local selectedKey, selectedData, currentKey, keys = getCurrentSelection(pe)
	local db = pe.db
	local agg = db.aggregate or {}
	panel._overviewScrollUnderProf = selectedKey ~= ACCT_KEY and selectedKey == currentKey
	if selectedKey == ACCT_KEY then
		panel.profCard:Hide()
	else
		panel.profCard:SetShown(selectedKey == currentKey)
	end
	self:Layout(panel)
	panel.subtitle:SetText("Account status, character detail, recent scans, and quick export actions.")
	panel.summaryBody:SetText(string.format(
		"Characters scanned: %d\nAggregate rebuilt: %s\nLast active tab: %s",
		#keys,
		pe:FormatScanTimestamp(agg.updatedAt),
		tostring(pe:GetSetting("general.lastActiveTab", "overview"))
	))

	local state = pe:GetState()
	if state.scanInProgress then
		panel.statusBadge.text:SetText("Scanning")
		panel.statusBody:SetText(string.format(
			"Current profession: %s\nRemaining queue: %d",
			tostring(state.currentProfession and state.currentProfession.professionName or "pending"),
			#(state.queue or {})
		))
	else
		panel.statusBadge.text:SetText("Ready")
		panel.statusBody:SetText("No scan in progress.\nUse Quick Actions to refresh exports or inventory.")
	end

	panel.refreshInvButton:SetEnabled(selectedKey ~= ACCT_KEY and selectedKey == currentKey)
	panel.exportCharacterButton:SetEnabled(selectedKey ~= ACCT_KEY and selectedKey == currentKey)

	local accountBtn = panel.accountButton
	if not accountBtn then
		accountBtn = CreateFrame("Button", nil, panel.sidebarContent, "UIPanelButtonTemplate")
		accountBtn:SetSize(210, 22)
		accountBtn:SetPoint("TOPLEFT", 0, -2)
		accountBtn:SetText("All characters")
		accountBtn:SetScript("OnClick", function()
			setSelection(pe, ACCT_KEY)
		end)
		panel.accountButton = accountBtn
	end
	if selectedKey == ACCT_KEY then
		accountBtn:LockHighlight()
	else
		accountBtn:UnlockHighlight()
	end

	for _, btn in ipairs(panel.charButtons) do
		btn:Hide()
	end

	for index, key in ipairs(keys) do
		local button = panel.charButtons[index]
		if not button then
			button = CreateFrame("Button", nil, panel.sidebarContent, "UIPanelButtonTemplate")
			button:SetSize(210, 22)
			panel.charButtons[index] = button
		end
		button:SetPoint("TOPLEFT", 0, -28 - ((index - 1) * 24))
		button:SetText(pe:GetDashboardSidebarCharacterLabel(key, db.characters[key], currentKey))
		button:SetScript("OnClick", function()
			setSelection(pe, key)
		end)
		button:Show()
		if selectedKey == key then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	panel.sidebarContent:SetHeight(math.max(60, 34 + (#keys * 24)))

	for _, row in ipairs(panel.profRows) do
		row:Hide()
	end

	if selectedKey == ACCT_KEY then
		panel.detailTitle:SetText("Account overview")
		panel.detailMeta:SetText(string.format("Stored characters: %d", #keys))
		local lines = { "|cffffffffRecent scans|r" }
		for index = 1, math.min(6, #(db.history or {})) do
			local entry = db.history[index]
			if entry then
				table.insert(lines, string.format(
					"%s  %s  (%d professions)",
					pe:FormatScanTimestamp(entry.finishedAt),
					tostring(entry.characterKey or "?"),
					tonumber(entry.professionCount) or 0
				))
			end
		end
		if #lines == 1 then
			table.insert(lines, "No scans stored yet.")
		end
		panel.detailBody:SetText(table.concat(lines, "\n"))
	else
		local charData = selectedData or {}
		local meta = charData.meta or {}
		panel.detailTitle:SetText(string.format("%s - %s", tostring(meta.name or "?"), tostring(meta.realm or "?")))
		panel.detailMeta:SetText(string.format(
			"Level %s %s | Scan finished %s | Live inventory %s",
			tostring(meta.level or "?"),
			tostring(meta.class or "?"),
			pe:FormatScanTimestamp(charData.scanFinishedAt),
			pe:FormatScanTimestamp(charData.lastLiveInventoryUpdate)
		))
		local inv = charData.inventorySnapshot or {}
		local lines = {
			string.format("Professions stored: %d", pe:TableCount(charData.professions or {})),
			string.format("Tracked item types: %s", tostring(inv.itemTypesTracked or 0)),
			string.format("Types with stock: %s", tostring(inv.itemTypesWithStock or 0)),
			string.format("Inventory quantity sum: %s", tostring(inv.totalQuantity or 0)),
		}
		if selectedKey ~= currentKey then
			table.insert(lines, "|cffffcc00Stored snapshot only. Log into this character to refresh inventory.|r")
		end
		panel.detailBody:SetText(table.concat(lines, "\n"))

		if selectedKey == currentKey then
			local profList = {}
			for _, profession in pairs(charData.professions or {}) do
				table.insert(profList, profession)
			end
			table.sort(profList, function(left, right)
				return pe:SortByNameThenId(
					{ professionName = left.professionName, skillLineID = left.skillLineID },
					{ professionName = right.professionName, skillLineID = right.skillLineID }
				)
			end)
			for index, profession in ipairs(profList) do
				local row = panel.profRows[index]
				if not row then
					row = CreateFrame("Frame", nil, panel.profContent)
					row:SetHeight(22)
					row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					row.label:SetPoint("LEFT", 0, 0)
					row.label:SetJustifyH("LEFT")
					row.allButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
					row.allButton:SetSize(56, 20)
					row.allButton:SetPoint("RIGHT", -120, 0)
					row.allButton:SetText("All")
					row.recipesButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
					row.recipesButton:SetSize(56, 20)
					row.recipesButton:SetPoint("RIGHT", -60, 0)
					row.recipesButton:SetText("Recipes")
					row.talentsButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
					row.talentsButton:SetSize(56, 20)
					row.talentsButton:SetPoint("RIGHT", 0, 0)
					row.talentsButton:SetText("Talents")
					panel.profRows[index] = row
				end
				row:SetWidth(panel.profContent:GetWidth() - 10)
				row:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
				row.label:SetWidth(math.max(180, row:GetWidth() - 190))
				row.label:SetText(string.format(
					"%s (%d/%d)",
					tostring(profession.professionName or "?"),
					tonumber(profession.skillLevel) or 0,
					tonumber(profession.maxSkillLevel) or 0
				))
				local skillLineID = tostring(profession.skillLineID or "")
				row.allButton:SetScript("OnClick", function()
					pe:Export("profession", skillLineID)
				end)
				row.recipesButton:SetScript("OnClick", function()
					pe:Export("profession_recipes", skillLineID)
				end)
				row.talentsButton:SetScript("OnClick", function()
					pe:Export("profession_talents", skillLineID)
				end)
				row:Show()
			end
			panel.profContent:SetHeight(math.max(40, #profList * 24))
		end
	end

	local rangeKey = pe:GetInventoryMetricRange()
	local mode = pe:GetSetting("overview.walletGraphMetric", "balance")
	if panel.overviewWalletGraph and panel.goldSummary then
		local series = pe:GetOverviewWalletGraphSeries(selectedKey, rangeKey, mode == "earned" and "earned" or "balance")
		local accent = pe:GetSetting("appearance.accentColor", {})
		panel.overviewWalletGraph:SetAccentColor({ r = accent.r, g = accent.g, b = accent.b, a = 0.95 })
		local goldAmt = pe:GetCurrentGoldSummaryForOverview(selectedKey)
		local goldLabel = goldAmt ~= nil and pe:FormatCopperFull(goldAmt) or "— (no stored wallet for this view yet)"
		panel.goldSummary:SetText(string.format(
			"Total for this view: %s\nTime range matches Inventory \"Range\": %s",
			goldLabel,
			tostring(rangeKey)
		))
		if mode == "earned" then
			panel.overviewWalletGraph:SetEmptyText("Need at least two wallet samples in this range to chart earned gold.")
			panel.overviewWalletGraph:SetYFormatter(function(v)
				local n = tonumber(v) or 0
				local sign = n >= 0 and "+" or ""
				return sign .. pe:FormatCopperShort(math.abs(n))
			end)
			panel.overviewWalletGraph:SetTooltipBuilder(function(tip, hit)
				local pt = hit and hit.pt or hit
				tip:AddLine(date("%Y-%m-%d %H:%M", pt.at), 1, 1, 1)
				local n = tonumber(pt.value) or 0
				tip:AddLine((n >= 0 and "+" or "") .. pe:FormatCopperFull(n), 0.85, 0.92, 1)
				local m = pt.meta or {}
				if m.current then
					tip:AddLine(string.format("Balance after: %s", pe:FormatCopperFull(m.current)), 0.72, 0.8, 0.88)
				end
			end)
		else
			panel.overviewWalletGraph:SetEmptyText("No wallet snapshots in this range yet.")
			panel.overviewWalletGraph:SetYFormatter(function(v)
				return pe:FormatCopperShort(tonumber(v) or 0)
			end)
			panel.overviewWalletGraph:SetTooltipBuilder(function(tip, hit)
				local pt = hit and hit.pt or hit
				tip:AddLine(date("%Y-%m-%d %H:%M", pt.at), 1, 1, 1)
				tip:AddLine(pe:FormatCopperFull(tonumber(pt.value) or 0), 0.85, 0.92, 1)
				local m = pt.meta or {}
				if m.count and m.count > 0 then
					tip:AddLine(string.format("Observations in hour: %d", m.count), 0.72, 0.8, 0.88)
				end
			end)
		end
		panel.overviewWalletGraph:SetSeries(series)
		panel.overviewWalletGraph:SetSecondarySeries({})
		panel.overviewWalletGraph:SetQuantitySeries({})
		panel.overviewWalletGraph:Refresh()
	end

	panel.detailContent:SetHeight(math.max(180, panel.detailBody:GetStringHeight() + 16))
	self:Layout(panel)
end
