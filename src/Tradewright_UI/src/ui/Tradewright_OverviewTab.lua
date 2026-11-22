local _, Tradewright = ...

local ACCT_KEY = Tradewright.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"

local OverviewTab = {}
Tradewright.OverviewTab = OverviewTab

-- Overview views drawn by a dashboard: key, button label, constructor, note shown beside the buttons.
local DASHBOARD_VIEWS = {
	{ key = "gold", label = "Gold", create = "CreateGoldDashboard",
		note = "Usual prices come from your scans · hover a row for details" },
	{ key = "sales", label = "Sales", create = "CreateSalesDashboard",
		note = "Sales are added when you collect auction gold from the mailbox · earned is after the auction house cut" },
	{ key = "income", label = "Income", create = "CreateIncomeDashboard",
		note = "Every change of gold, by where it came from · hover a row for details" },
}

local GAP = 12
local SIDEBAR_WIDTH = 220
local GRAPH_HEIGHT = 120

-- The key the Overview shows: the saved choice while it still exists, else this character,
-- the first stored one, or the account.
local function resolveSelectedKey(characters, selected, currentKey, keys)
	if selected == ACCT_KEY or (selected and characters[selected]) then
		return selected
	end
	if characters[currentKey] then
		return currentKey
	end
	return keys[1] or ACCT_KEY
end

local function getCurrentSelection(pe)
	local ui = pe.ui
	local db = pe.db or {}
	local currentKey = pe:GetCharacterKey()
	local keys = pe:GetDashboardCharacterKeyList(db)
	local characters = db.characters or {}
	local selected = resolveSelectedKey(characters, ui.selectedCharacterKey, currentKey, keys)
	ui.selectedCharacterKey = selected
	if selected == ACCT_KEY then
		return selected, db.aggregate or {}, currentKey, keys
	end
	return selected, characters[selected], currentKey, keys
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
	local pe = Tradewright
	pe:LayoutEvenRow(panel.statsRow, panel.stats, 0, GAP)
	local detailWidth = panel.detail:GetWidth()
	panel.goldGraph:SetWidth(math.max(80, detailWidth - 20))
end

-- Gold | Sales | Income | Characters switch above the views, with a note on the active one.
local function createViewBar(pe, panel)
	panel.viewBar = CreateFrame("Frame", nil, panel)
	panel.viewBar:SetPoint("TOPLEFT")
	panel.viewBar:SetPoint("TOPRIGHT")
	panel.viewBar:SetHeight(22)
	panel.viewButtons = {}
	local views = { unpack(DASHBOARD_VIEWS) }
	views[#views + 1] = { key = "characters", label = "Characters" }
	local previous
	for _, view in ipairs(views) do
		local button = pe:CreateButton(panel.viewBar, view.label, function()
			pe:SetSetting("overview.view", view.key)
			OverviewTab:Refresh()
		end, { small = true })
		button.view = view.key
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
end

-- Stats row and the Scan / Refresh / Export toolbar of the Characters view.
function OverviewTab:CreateCharactersToolbar(panel, host)
	local pe = Tradewright
	panel.statsRow = CreateFrame("Frame", nil, host)
	panel.statsRow:SetPoint("TOPLEFT")
	panel.statsRow:SetPoint("TOPRIGHT")
	panel.statsRow:SetHeight(58)
	panel.stats = pe:CreateStats(panel.statsRow, { "characters", "gold", "itemTypes", "professionScan" })
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
end

-- Left: character list.
function OverviewTab:CreateCharacterSidebar(panel, host)
	local pe = Tradewright
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
end

local function goldMetricButton(parent, label, metric)
	return Tradewright:CreateButton(parent, label, function()
		Tradewright:SetSetting("overview.walletGraphMetric", metric)
		OverviewTab:Refresh()
	end, { small = true })
end

-- The gold card: heading, Current gold / Gold earned switch, range, summary and the graph.
function OverviewTab:CreateGoldCard(panel)
	local pe = Tradewright
	panel.goldInset = pe:CreateInset(panel.detail)
	panel.goldInset:SetPoint("TOPLEFT", panel.detailMeta, "BOTTOMLEFT", 0, -10)
	panel.goldInset:SetPoint("TOPRIGHT", panel.detailMeta, "BOTTOMRIGHT", 0, -10)
	panel.goldInset:SetHeight(GRAPH_HEIGHT + 64)
	panel.goldRange = pe:CreateText(panel.goldInset, "GameFontHighlightSmall", "textMuted", "RIGHT")
	panel.goldRange:SetPoint("TOPRIGHT", -10, -12)
	panel.goldEarned = goldMetricButton(panel.goldInset, "Gold earned", "earned")
	panel.goldEarned:SetPoint("RIGHT", panel.goldRange, "LEFT", -8, 0)
	panel.goldCurrent = goldMetricButton(panel.goldInset, "Current gold", "balance")
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
end

-- Right: selected character or account, with its gold card and a professions / history table.
function OverviewTab:CreateCharacterDetail(panel, host)
	local pe = Tradewright
	panel.detail = CreateFrame("Frame", nil, host)
	panel.detail:SetPoint("TOPLEFT", panel.sidebar, "TOPRIGHT", GAP, 0)
	panel.detail:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
	panel.detailTitle = pe:CreateText(panel.detail, "GameFontHighlight")
	panel.detailTitle:SetPoint("TOPLEFT")
	panel.detailTitle:SetPoint("TOPRIGHT")
	panel.detailMeta = pe:CreateText(panel.detail, "GameFontHighlightSmall", "textMuted")
	panel.detailMeta:SetPoint("TOPLEFT", panel.detailTitle, "BOTTOMLEFT", 0, -2)
	panel.detailMeta:SetPoint("TOPRIGHT", panel.detailTitle, "BOTTOMRIGHT", 0, -2)
	OverviewTab:CreateGoldCard(panel)
	panel.listHeading = pe:CreateHeading(panel.detail, "Professions")
	panel.listHeading:SetPoint("TOPLEFT", panel.goldInset, "BOTTOMLEFT", 0, -GAP)
	panel.listHeading:SetPoint("TOPRIGHT", panel.goldInset, "BOTTOMRIGHT", 0, -GAP)
	panel.listTable = pe:CreateReusableTable(panel.detail, { autoFitToScroll = true })
	panel.listTable.frame:SetPoint("TOPLEFT", panel.listHeading, "BOTTOMLEFT", 0, -8)
	panel.listTable.frame:SetPoint("BOTTOMRIGHT", panel.detail, "BOTTOMRIGHT", 0, 0)
	panel.professionColumns = pe:CreateProfessionColumns()
	panel.professionColumnsReadOnly = pe:CreateProfessionColumns(true)
	panel.historyColumns = createHistoryColumns(pe)
end

function OverviewTab:Create(container, uiState)
	local pe = Tradewright
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.overviewPanel = panel
	createViewBar(pe, panel)
	local function viewHost()
		local host = CreateFrame("Frame", nil, panel)
		host:SetPoint("TOPLEFT", panel.viewBar, "BOTTOMLEFT", 0, -GAP)
		host:SetPoint("BOTTOMRIGHT")
		return host
	end
	panel.dashboards = {}
	for _, view in ipairs(DASHBOARD_VIEWS) do
		local viewFrame = viewHost()
		panel.dashboards[view.key] = { frame = viewFrame, dashboard = pe[view.create](pe, viewFrame), note = view.note }
	end
	panel.charactersView = viewHost()
	OverviewTab:CreateCharactersToolbar(panel, panel.charactersView)
	OverviewTab:CreateCharacterSidebar(panel, panel.charactersView)
	OverviewTab:CreateCharacterDetail(panel, panel.charactersView)
	panel:SetScript("OnSizeChanged", function()
		OverviewTab:Layout(panel)
	end)
	OverviewTab:Layout(panel)
	return panel
end

function OverviewTab:ApplyTheme()
end

local function countProfessions(pe, selectedKey, selectedData)
	if selectedKey ~= ACCT_KEY then
		return pe:TableCount(selectedData and selectedData.professions or {})
	end
	local count = 0
	for _, charData in pairs(pe.db.characters or {}) do
		count = count + pe:TableCount(charData.professions or {})
	end
	return count
end

-- Gold card detail: the selected character's gold, or how many characters the account total spans.
local function goldStatDetail(pe, selectedKey, selectedData, characterCount)
	local gold = selectedKey ~= ACCT_KEY and pe:GetCurrentGoldSummaryForOverview(selectedKey) or nil
	if gold == nil then
		return string.format("Across %d %s", characterCount, pe:Plural(characterCount, "character"))
	end
	local name = selectedData and selectedData.meta and selectedData.meta.name or "This character"
	return name .. " has " .. pe:FormatCopperShort(gold)
end

-- Profession scan card: value, detail and tone while a scan runs, or the stored count when idle.
local function professionScanStat(pe, professionCount)
	local state = pe:GetState()
	if state.scanInProgress then
		local current = state.currentProfession and state.currentProfession.professionName or "starting"
		return "Scanning", string.format("%s, %d left", tostring(current), #(state.queue or {})), "warning"
	end
	return "Ready", string.format("%d %s stored", professionCount, pe:Plural(professionCount, "profession")), "success"
end

function OverviewTab:RefreshStats(panel, selectedKey, selectedData, keys)
	local pe = Tradewright
	local agg = pe.db.aggregate or {}
	local accountGold = pe:GetCurrentGoldSummaryForOverview(ACCT_KEY)
	local inv = sumInventory(pe, selectedKey, selectedData)
	panel.stats.characters:SetValues("Characters scanned", tostring(#keys), "Last rebuilt " .. pe:FormatScanTimestamp(agg.updatedAt))
	panel.stats.gold:SetValues("Gold, all characters", accountGold and accountGold > 0 and pe:FormatCopperShort(accountGold) or "-",
		goldStatDetail(pe, selectedKey, selectedData, #keys))
	panel.stats.itemTypes:SetValues("Item types tracked", pe:FormatNumberGrouped(inv.tracked),
		string.format("%s in stock, %s items", pe:FormatNumberGrouped(inv.inStock), pe:FormatNumberGrouped(inv.quantity)))
	panel.stats.professionScan:SetValues("Profession scan", professionScanStat(pe, countProfessions(pe, selectedKey, selectedData)))
end

function OverviewTab:RefreshCharacterList(panel, currentKey, keys)
	local pe = Tradewright
	local items = { { key = ACCT_KEY, label = "All characters" } }
	for _, key in ipairs(keys) do
		local label = characterName(pe.db.characters[key], key)
		if key == currentKey then
			label = label .. " " .. pe:Colorize("(you)", "success")
		end
		items[#items + 1] = { key = key, label = label }
	end
	panel.characterList:SetItems(items)
end

-- The newest 20 scans across all characters, for the account view.
local function recentScanRows(db)
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
	return rows
end

function OverviewTab:RefreshAccountDetail(panel, keys)
	panel.detailTitle:SetText("All characters")
	panel.detailMeta:SetText(string.format("%d characters stored", #keys))
	panel.listHeading:SetText("Recent scans")
	panel.listTable:SetColumns(panel.historyColumns)
	panel.listTable:SetEmptyText("No scans yet", "Open a profession window and press Scan professions.")
	panel.listTable:SetRows(recentScanRows(Tradewright.db))
	panel.listTable:Refresh()
end

-- Professions can only be scanned on the logged-in character; other characters get read-only columns.
function OverviewTab:RefreshCharacterDetail(panel, selectedKey, selectedData, currentKey)
	local pe = Tradewright
	local charData = selectedData or {}
	local meta = charData.meta or {}
	panel.detailTitle:SetText(characterName(charData, selectedKey))
	panel.detailMeta:SetText(string.format("Level %s %s · Professions scanned %s · Inventory read %s",
		tostring(meta.level or "?"), tostring(meta.class or ""),
		pe:FormatScanTimestamp(charData.scanFinishedAt), pe:FormatScanTimestamp(charData.lastLiveInventoryUpdate)))
	panel.listHeading:SetText("Professions")

	local isCurrent = selectedKey == currentKey
	panel.listTable:SetColumns(isCurrent and panel.professionColumns or panel.professionColumnsReadOnly)
	panel.listTable:SetEmptyText("No professions stored", isCurrent and "Open a profession window and press Scan professions."
		or "Log in on this character to scan and refresh it.")
	panel.listTable:SetRows(pe:BuildProfessionRows(charData))
	panel.listTable:Refresh()
end

function OverviewTab:RefreshDetail(panel, selectedKey, selectedData, currentKey, keys)
	if selectedKey == ACCT_KEY then
		self:RefreshAccountDetail(panel, keys)
	else
		self:RefreshCharacterDetail(panel, selectedKey, selectedData, currentKey)
	end
end

local function configureEarnedGraph(pe, graph, theme)
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
end

local function configureBalanceGraph(pe, graph)
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

-- Gold graph metric -> how its axis and tooltip read.
local GOLD_GRAPH_SETUP = { earned = configureEarnedGraph, balance = configureBalanceGraph }

function OverviewTab:RefreshGold(panel, selectedKey)
	local pe = Tradewright
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
	GOLD_GRAPH_SETUP[mode](pe, graph, theme)
	graph:SetSeries(pe:GetOverviewWalletGraphSeries(selectedKey, rangeKey, mode))
	graph:SetSecondarySeries({})
	graph:SetQuantitySeries({})
	graph:Refresh()
end

-- Shows the saved view (a dashboard or the characters view) and styles its button; returns its key.
local function showSavedView(pe, panel)
	local view = pe:GetSetting("overview.view", "gold")
	view = (view == "characters" or panel.dashboards[view]) and view or "gold"
	for _, button in ipairs(panel.viewButtons) do
		pe:StyleShellButton(button, button.view == view)
	end
	panel.charactersView:SetShown(view == "characters")
	for key, entry in pairs(panel.dashboards) do
		entry.frame:SetShown(key == view)
	end
	return view
end

function OverviewTab:RefreshCharactersView(panel)
	local pe = Tradewright
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

function OverviewTab:Refresh()
	local pe = Tradewright
	pe:InitDB()
	if pe:AggregateNeedsRebuild() then
		pe:BuildAggregate()
	end
	local panel = pe.ui.overviewPanel
	if not panel then
		return
	end
	local active = panel.dashboards[showSavedView(pe, panel)]
	if active then
		panel.viewNote:SetText(type(active.note) == "function" and active.note(pe) or active.note)
		active.dashboard:Refresh()
		return
	end
	panel.viewNote:SetText("")
	self:RefreshCharactersView(panel)
end
