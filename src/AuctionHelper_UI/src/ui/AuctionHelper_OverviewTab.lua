local addonName, ProfessionExporter = ...

local ACCT_KEY = ProfessionExporter.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"

local OverviewTab = {}
ProfessionExporter.OverviewTab = OverviewTab

local GAP = 12
local SIDEBAR_WIDTH = 220
local GRAPH_HEIGHT = 120

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

local function characterName(charData, key)
	local meta = charData and charData.meta or {}
	if meta.name then
		return meta.realm and (meta.name .. " · " .. meta.realm) or meta.name
	end
	return tostring(key or "?")
end

local function sumInventory(pe, selectedKey, selectedData)
	local totals = { tracked = 0, inStock = 0, quantity = 0 }
	local function add(inv)
		inv = inv or {}
		totals.tracked = totals.tracked + (tonumber(inv.itemTypesTracked) or 0)
		totals.inStock = totals.inStock + (tonumber(inv.itemTypesWithStock) or 0)
		totals.quantity = totals.quantity + (tonumber(inv.totalQuantity) or 0)
	end
	if selectedKey == ACCT_KEY then
		for _, charData in pairs(pe.db.characters or {}) do
			add(charData.inventorySnapshot)
		end
	else
		add(selectedData and selectedData.inventorySnapshot)
	end
	return totals
end

local function createHistoryColumns(pe)
	return {
		{ id = "when", label = "Finished", width = 130, getText = function(row) return pe:FormatScanTimestamp(row.finishedAt) end },
		{ id = "character", label = "Character", width = 120, flex = 1, minWidth = 100, getText = function(row) return row.character end },
		{ id = "professions", label = "Professions", width = 84, justifyH = "RIGHT", getText = function(row) return tostring(row.count) end },
	}
end

function OverviewTab:Layout(panel)
	if not panel then
		return
	end
	local pe = ProfessionExporter
	pe:LayoutEvenRow(panel.statsRow, panel.stats, 0, GAP)
	local detailWidth = panel.detail:GetWidth()
	panel.goldGraph:SetWidth(math.max(80, detailWidth - 20))
end

function OverviewTab:Create(container, uiState)
	local pe = ProfessionExporter
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.overviewPanel = panel

	-- Gold | Sales | Characters switch. Gold is the money dashboard, Sales the auction sales ledger,
	-- Characters per-character detail.
	panel.viewBar = CreateFrame("Frame", nil, panel)
	panel.viewBar:SetPoint("TOPLEFT")
	panel.viewBar:SetPoint("TOPRIGHT")
	panel.viewBar:SetHeight(22)
	panel.viewButtons = {}
	local previous
	for _, view in ipairs({ { "gold", "Gold" }, { "sales", "Sales" }, { "characters", "Characters" } }) do
		local button = pe:CreateButton(panel.viewBar, view[2], function()
			pe:SetSetting("overview.view", view[1])
			OverviewTab:Refresh()
		end, { small = true })
		button.view = view[1]
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", -1, 0)
		else
			button:SetPoint("LEFT")
		end
		previous = button
		panel.viewButtons[#panel.viewButtons + 1] = button
	end
	panel.viewNote = pe:CreateText(panel.viewBar, "GameFontHighlightSmall", "textMuted", "RIGHT")
	panel.viewNote:SetPoint("RIGHT")
	panel.viewNote:SetPoint("LEFT", previous, "RIGHT", 12, 0)

	local function viewHost()
		local host = CreateFrame("Frame", nil, panel)
		host:SetPoint("TOPLEFT", panel.viewBar, "BOTTOMLEFT", 0, -GAP)
		host:SetPoint("BOTTOMRIGHT")
		return host
	end
	panel.goldView = viewHost()
	panel.goldDashboard = pe:CreateGoldDashboard(panel.goldView)
	panel.salesView = viewHost()
	panel.salesDashboard = pe:CreateSalesDashboard(panel.salesView)
	panel.charactersView = viewHost()
	local host = panel.charactersView

	panel.statsRow = CreateFrame("Frame", nil, host)
	panel.statsRow:SetPoint("TOPLEFT")
	panel.statsRow:SetPoint("TOPRIGHT")
	panel.statsRow:SetHeight(58)
	panel.stats = {}
	for index = 1, 4 do
		panel.stats[index] = pe:CreateStat(panel.statsRow)
	end

	panel.toolbar = CreateFrame("Frame", nil, host)
	panel.toolbar:SetPoint("TOPLEFT", panel.statsRow, "BOTTOMLEFT", 0, -GAP)
	panel.toolbar:SetPoint("TOPRIGHT", panel.statsRow, "BOTTOMRIGHT", 0, -GAP)
	panel.toolbar:SetHeight(26)
	panel.scanButton = pe:CreateButton(panel.toolbar, "Scan professions", function() pe:StartScan() end, { primary = true })
	panel.scanButton:SetPoint("LEFT")
	panel.refreshInvButton = pe:CreateButton(panel.toolbar, "Refresh inventory", function() pe:DashboardRefreshInventory() end)
	pe:ChainRight({ panel.scanButton, panel.refreshInvButton })
	panel.exportAccountButton = pe:CreateButton(panel.toolbar, "Export account", function() pe:Export("account") end)
	panel.exportAccountButton:SetPoint("RIGHT")
	panel.exportCharacterButton = pe:CreateButton(panel.toolbar, "Export character", function() pe:Export("character") end)
	pe:ChainLeft({ panel.exportAccountButton, panel.exportCharacterButton })

	-- Left: character list.
	panel.sidebar = CreateFrame("Frame", nil, host)
	panel.sidebar:SetPoint("TOPLEFT", panel.toolbar, "BOTTOMLEFT", 0, -GAP)
	panel.sidebar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
	panel.sidebar:SetWidth(SIDEBAR_WIDTH)
	panel.sidebarTitle = pe:CreateHeading(panel.sidebar, "Characters")
	panel.sidebarTitle:SetPoint("TOPLEFT")
	panel.sidebarTitle:SetPoint("TOPRIGHT")
	panel.characterList = pe:CreateSelectList(panel.sidebar, function(key)
		pe.ui.selectedCharacterKey = key
		pe:RefreshDashboard(true)
	end, function()
		return pe.ui.selectedCharacterKey
	end)
	panel.characterList.frame:SetPoint("TOPLEFT", panel.sidebarTitle, "BOTTOMLEFT", 0, -8)
	panel.characterList.frame:SetPoint("BOTTOMRIGHT", panel.sidebar, "BOTTOMRIGHT", 0, 0)

	-- Right: selected character or account.
	panel.detail = CreateFrame("Frame", nil, host)
	panel.detail:SetPoint("TOPLEFT", panel.sidebar, "TOPRIGHT", GAP, 0)
	panel.detail:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)

	panel.detailTitle = pe:CreateText(panel.detail, "GameFontHighlight")
	panel.detailTitle:SetPoint("TOPLEFT")
	panel.detailTitle:SetPoint("TOPRIGHT")
	panel.detailMeta = pe:CreateText(panel.detail, "GameFontHighlightSmall", "textMuted")
	panel.detailMeta:SetPoint("TOPLEFT", panel.detailTitle, "BOTTOMLEFT", 0, -2)
	panel.detailMeta:SetPoint("TOPRIGHT", panel.detailTitle, "BOTTOMRIGHT", 0, -2)

	panel.goldInset = pe:CreateInset(panel.detail)
	panel.goldInset:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -10)
	panel.goldInset:SetPoint("TOPRIGHT", panel.detailMeta, "BOTTOMRIGHT", 0, -10)
	panel.goldInset:SetHeight(GRAPH_HEIGHT + 64)
	panel.goldRange = pe:CreateText(panel.goldInset, "GameFontHighlightSmall", "textMuted", "RIGHT")
	panel.goldRange:SetPoint("TOPRIGHT", -10, -12)
	panel.goldEarned = pe:CreateButton(panel.goldInset, "Gold earned", function()
		pe:SetSetting("overview.walletGraphMetric", "earned")
		OverviewTab:Refresh()
	end, { small = true })
	panel.goldEarned:SetPoint("RIGHT", panel.goldRange, "LEFT", -8, 0)
	panel.goldCurrent = pe:CreateButton(panel.goldInset, "Current gold", function()
		pe:SetSetting("overview.walletGraphMetric", "balance")
		OverviewTab:Refresh()
	end, { small = true })
	panel.goldCurrent:SetPoint("RIGHT", panel.goldEarned, "LEFT", 1, 0)
	panel.goldHeading = pe:CreateHeading(panel.goldInset, "Gold")
	panel.goldHeading:SetPoint("TOPLEFT", 10, -10)
	panel.goldHeading:SetPoint("RIGHT", panel.goldCurrent, "LEFT", -12, 0)
	panel.goldSummary = pe:CreateText(panel.goldInset, "GameFontHighlightSmall", "textMuted")
	panel.goldSummary:SetPoint("TOPLEFT", panel.goldHeading, "BOTTOMLEFT", 0, -6)
	panel.goldSummary:SetPoint("RIGHT", panel.goldInset, "RIGHT", -10, 0)
	panel.goldGraph = pe:CreateTimeSeriesGraph(panel.goldInset, {
		showTitle = false,
		plotHeight = GRAPH_HEIGHT - 28,
		emptyText = "No gold recorded in this range yet.",
	})
	panel.goldGraph:SetPoint("BOTTOMLEFT", panel.goldInset, "BOTTOMLEFT", 10, 8)

	panel.listHeading = pe:CreateHeading(panel.detail, "Professions")
	panel.listHeading:SetPoint("TOPLEFT", panel.goldInset, "BOTTOMLEFT", 0, -GAP)
	panel.listHeading:SetPoint("TOPRIGHT", panel.goldInset, "BOTTOMRIGHT", 0, -GAP)
	panel.listTable = pe:CreateReusableTable(panel.detail, { autoFitToScroll = true })
	panel.listTable.frame:SetPoint("TOPLEFT", panel.listHeading, "BOTTOMLEFT", 0, -8)
	panel.listTable.frame:SetPoint("BOTTOMRIGHT", panel.detail, "BOTTOMRIGHT", 0, 0)
	panel.professionColumns = pe:CreateProfessionColumns()
	panel.professionColumnsReadOnly = pe:CreateProfessionColumns(true)
	panel.historyColumns = createHistoryColumns(pe)

	panel:SetScript("OnSizeChanged", function()
		OverviewTab:Layout(panel)
	end)
	OverviewTab:Layout(panel)
	return panel
end

function OverviewTab:ApplyTheme()
end

function OverviewTab:RefreshStats(panel, selectedKey, selectedData, keys)
	local pe = ProfessionExporter
	local agg = pe.db.aggregate or {}
	local state = pe:GetState()
	local accountGold = pe:GetCurrentGoldSummaryForOverview(ACCT_KEY)
	local gold = selectedKey ~= ACCT_KEY and pe:GetCurrentGoldSummaryForOverview(selectedKey) or nil
	local inv = sumInventory(pe, selectedKey, selectedData)
	local professionCount = 0
	if selectedKey == ACCT_KEY then
		for _, charData in pairs(pe.db.characters or {}) do
			professionCount = professionCount + pe:TableCount(charData.professions or {})
		end
	else
		professionCount = pe:TableCount(selectedData and selectedData.professions or {})
	end

	panel.stats[1]:SetValues("Characters scanned", tostring(#keys), "Last rebuilt " .. pe:FormatScanTimestamp(agg.updatedAt))
	local goldDetail = string.format("Across %d %s", #keys, #keys == 1 and "character" or "characters")
	if gold ~= nil then
		local name = selectedData and selectedData.meta and selectedData.meta.name or "This character"
		goldDetail = name .. " has " .. pe:FormatCopperShort(gold)
	end
	panel.stats[2]:SetValues("Gold, all characters", accountGold and accountGold > 0 and pe:FormatCopperShort(accountGold) or "-", goldDetail)
	panel.stats[3]:SetValues("Item types tracked", pe:FormatNumberGrouped(inv.tracked),
		string.format("%s in stock, %s items", pe:FormatNumberGrouped(inv.inStock), pe:FormatNumberGrouped(inv.quantity)))
	if state.scanInProgress then
		panel.stats[4]:SetValues("Profession scan", "Scanning",
			string.format("%s, %d left", tostring(state.currentProfession and state.currentProfession.professionName or "starting"), #(state.queue or {})), "warning")
	else
		panel.stats[4]:SetValues("Profession scan", "Ready",
			string.format("%d %s stored", professionCount, professionCount == 1 and "profession" or "professions"), "success")
	end
end

function OverviewTab:RefreshCharacterList(panel, currentKey, keys)
	local pe = ProfessionExporter
	local theme = pe:GetTheme()
	local items = { { key = ACCT_KEY, label = "All characters" } }
	for _, key in ipairs(keys) do
		local label = characterName(pe.db.characters[key], key)
		if key == currentKey then
			label = label .. string.format(" |cff%02x%02x%02x(you)|r", theme.success.r * 255, theme.success.g * 255, theme.success.b * 255)
		end
		items[#items + 1] = { key = key, label = label }
	end
	panel.characterList:SetItems(items)
end

function OverviewTab:RefreshDetail(panel, selectedKey, selectedData, currentKey, keys)
	local pe = ProfessionExporter
	local db = pe.db
	if selectedKey == ACCT_KEY then
		panel.detailTitle:SetText("All characters")
		panel.detailMeta:SetText(string.format("%d characters stored", #keys))
		panel.listHeading:SetText("Recent scans")
		local rows = {}
		for index = 1, math.min(20, #(db.history or {})) do
			local entry = db.history[index]
			rows[#rows + 1] = {
				_rowIdentity = index,
				finishedAt = entry.finishedAt,
				character = characterName(db.characters and db.characters[entry.characterKey], entry.characterKey),
				count = tonumber(entry.professionCount) or 0,
			}
		end
		panel.listTable:SetColumns(panel.historyColumns)
		panel.listTable:SetEmptyText("No scans yet", "Open a profession window and press Scan professions.")
		panel.listTable:SetRows(rows)
		panel.listTable:Refresh()
		return
	end

	local charData = selectedData or {}
	local meta = charData.meta or {}
	panel.detailTitle:SetText(characterName(charData, selectedKey))
	panel.detailMeta:SetText(string.format("Level %s %s · Professions scanned %s · Inventory read %s",
		tostring(meta.level or "?"), tostring(meta.class or ""),
		pe:FormatScanTimestamp(charData.scanFinishedAt), pe:FormatScanTimestamp(charData.lastLiveInventoryUpdate)))
	panel.listHeading:SetText("Professions")

	local rows = pe:BuildProfessionRows(charData)
	local columns = selectedKey == currentKey and panel.professionColumns or panel.professionColumnsReadOnly
	panel.listTable:SetColumns(columns)
	if selectedKey ~= currentKey then
		panel.listTable:SetEmptyText("No professions stored", "Log in on this character to scan and refresh it.")
	else
		panel.listTable:SetEmptyText("No professions stored", "Open a profession window and press Scan professions.")
	end
	panel.listTable:SetRows(rows)
	panel.listTable:Refresh()
end

function OverviewTab:RefreshGold(panel, selectedKey)
	local pe = ProfessionExporter
	local theme = pe:GetTheme()
	local graph = panel.goldGraph
	local rangeKey = pe:GetInventoryMetricRange()
	local mode = pe:GetSetting("overview.walletGraphMetric", "balance") == "earned" and "earned" or "balance"
	pe:StyleShellButton(panel.goldCurrent, mode == "balance")
	pe:StyleShellButton(panel.goldEarned, mode == "earned")
	panel.goldRange:SetText(pe:GetRangeLabel(rangeKey))

	local gold = pe:GetCurrentGoldSummaryForOverview(selectedKey)
	panel.goldSummary:SetText(gold ~= nil and ("Now " .. pe:FormatCopperFull(gold)) or "No gold recorded for this view yet.")
	graph:SetAccentColor(theme.accent)
	if mode == "earned" then
		graph:SetEmptyText("Two gold readings in this range are needed to chart gold earned.")
		graph:SetYFormatter(function(v)
			local n = tonumber(v) or 0
			return (n >= 0 and "+" or "-") .. pe:FormatCopperShort(math.abs(n))
		end)
		graph:SetTooltipBuilder(function(tip, hit)
			local pt = hit and hit.pt or hit
			tip:AddLine(pe:FormatScanTimestamp(pt.at), 1, 1, 1)
			local n = tonumber(pt.value) or 0
			tip:AddLine((n >= 0 and "+" or "") .. pe:FormatCopperFull(n))
			if pt.meta and pt.meta.current then
				tip:AddLine("Balance after " .. pe:FormatCopperFull(pt.meta.current), theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
			end
		end)
	else
		graph:SetEmptyText("No gold recorded in this range yet.")
		graph:SetYFormatter(function(v)
			return pe:FormatCopperShort(tonumber(v) or 0)
		end)
		graph:SetTooltipBuilder(function(tip, hit)
			local pt = hit and hit.pt or hit
			tip:AddLine(pe:FormatScanTimestamp(pt.at), 1, 1, 1)
			tip:AddLine(pe:FormatCopperFull(tonumber(pt.value) or 0))
		end)
	end
	graph:SetSeries(pe:GetOverviewWalletGraphSeries(selectedKey, rangeKey, mode))
	graph:SetSecondarySeries({})
	graph:SetQuantitySeries({})
	graph:Refresh()
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

	local view = pe:GetSetting("overview.view", "gold")
	view = (view == "characters" or view == "sales") and view or "gold"
	for _, button in ipairs(panel.viewButtons) do
		pe:StyleShellButton(button, button.view == view)
	end
	panel.goldView:SetShown(view == "gold")
	panel.salesView:SetShown(view == "sales")
	panel.charactersView:SetShown(view == "characters")
	if view == "gold" then
		panel.viewNote:SetText("Usual prices come from " .. (pe:GetSetting("gold.reference", "best") == "own" and "your scans" or "TSM when installed, else your scans") .. " · hover a row for details")
		panel.goldDashboard:Refresh()
		return
	elseif view == "sales" then
		panel.viewNote:SetText("Sales are added when you collect auction gold from the mailbox · earned is after the auction house cut")
		panel.salesDashboard:Refresh()
		return
	end
	panel.viewNote:SetText("")

	local selectedKey, selectedData, currentKey, keys = getCurrentSelection(pe)
	local isCurrent = selectedKey ~= ACCT_KEY and selectedKey == currentKey
	panel.refreshInvButton:SetEnabled(isCurrent)
	panel.exportCharacterButton:SetEnabled(isCurrent)

	self:RefreshStats(panel, selectedKey, selectedData, keys)
	self:RefreshCharacterList(panel, currentKey, keys)
	self:RefreshDetail(panel, selectedKey, selectedData, currentKey, keys)
	self:RefreshGold(panel, selectedKey)
	self:Layout(panel)
end
