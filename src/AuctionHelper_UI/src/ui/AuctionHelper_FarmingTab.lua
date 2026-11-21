local AuctionHelper = select(2, ...)

-- Farming tab (E09 F71, F72): saved farms with their gold an hour when run and at today's prices,
-- and the "What to farm" list from AuctionHelper_FarmTargets.lua.

local FarmingTab = {}
AuctionHelper.FarmingTab = FarmingTab

local GAP = 12
local PAD = 10
local DETAIL_WIDTH = 300
local ROW_HEIGHT = 24
local MAX_ITEM_ROWS = 7

local function duration(seconds)
	local minutes = math.floor((seconds or 0) / 60 + 0.5)
	if minutes >= 60 then
		return string.format("%dh %dm", math.floor(minutes / 60), minutes % 60)
	end
	return minutes .. "m"
end

local function signedPercent(fraction)
	if not fraction then
		return "-"
	end
	return string.format("%+d%%", math.floor(fraction * 100 + 0.5))
end

local function farmColumns(pe)
	local function perHour(id, label, field)
		return {
			id = id, label = label, justifyH = "RIGHT", width = 74, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row[field] or 0 end,
			getText = function(row) return pe:FormatCopperShort(row[field]) end,
		}
	end
	return {
		{
			id = "name", label = "Farm", width = 200, minWidth = 140, flex = 1, sortable = true, defaultSort = "asc",
			sortValue = function(row) return row.name end,
			getText = function(row)
				return string.format("%s  |cff99a1ab%s · last run %s|r", row.name, row.zone ~= "" and row.zone or "Unknown zone",
					pe:FormatScanTimestamp(row.lastRunAt))
			end,
		},
		{
			id = "runs", label = "Runs", justifyH = "RIGHT", width = 44, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.runs end,
			getText = function(row) return tostring(row.runs) end,
		},
		{
			id = "time", label = "Time", justifyH = "RIGHT", width = 64, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.activeSeconds end,
			getText = function(row) return duration(row.activeSeconds) end,
		},
		perHour("then", "Then", "thenPerHour"),
		perHour("now", "Now", "nowPerHour"),
		{
			id = "change", label = "Change", justifyH = "RIGHT", width = 60, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.changePct or 0 end,
			getText = function(row) return signedPercent(row.changePct) end,
		},
	}
end

-- Gold an hour now and then, the shares, then what dropped per hour.
local function detailRows(pe, row)
	local rows = {
		{ "Gold an hour, today's prices", pe:FormatCopperShort(row.nowPerHour) },
		{ "When you farmed it", pe:FormatCopperShort(row.thenPerHour) },
		{ "Share from items known to sell", string.format("%d%%", math.floor(row.liquidShare * 100 + 0.5)) },
		{ "Share from coin and vendor value", string.format("%d%%", math.floor(row.coinShare * 100 + 0.5)) },
		{ "", "" },
	}
	for index = 1, math.min(#row.perHourByItem, MAX_ITEM_ROWS) do
		local item = row.perHourByItem[index]
		rows[#rows + 1] = {
			string.format("%s, %.1f an hour", pe:GetItemDisplayName(item.itemID), item.qtyPerHour),
			pe:FormatCopperShort(item.valuePerHour),
		}
	end
	return rows
end

-- "Start this farm" and Delete at the bottom of the side pane.
local function buildDetailButtons(pe, panel, card)
	card.start = pe:CreateButton(card.body, "Start this farm", function()
		if panel.selected then
			pe:StartFarmRun(panel.selected.name)
			FarmingTab:Refresh()
		end
	end, { tooltip = "Starts a new run under this name. Saving it adds it to this farm's totals. It records loot, not a route." })
	card.start:SetPoint("BOTTOMLEFT")
	card.delete = pe:CreateButton(card.body, "Delete", function()
		local row = panel.selected
		if not row then
			return
		end
		-- A second click on the same farm confirms.
		if panel.deleteArmed ~= row.name then
			panel.deleteArmed = row.name
			card.delete:SetText("Click again to delete")
			return
		end
		pe:DeleteFarm(row.name)
		panel.selected, panel.deleteArmed = nil, nil
		FarmingTab:Refresh()
	end)
	card.delete:SetPoint("BOTTOMRIGHT")
	card.start:SetPoint("RIGHT", card.delete, "LEFT", -6, 0)
end

local function buildDetail(pe, panel)
	local card = pe:CreateInset(panel)
	card:SetWidth(DETAIL_WIDTH)
	card.empty = pe:CreateEmptyState(card)
	card.empty:SetAllPoints()
	card.empty:SetMessage("Select a farm", "Click a farm to see what dropped and what it is worth today.")
	card.body = CreateFrame("Frame", nil, card)
	card.body:SetPoint("TOPLEFT", PAD, -PAD)
	card.body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	card.title = pe:CreateText(card.body, "GameFontHighlight")
	card.title:SetPoint("TOPLEFT")
	card.title:SetPoint("TOPRIGHT")
	card.subtitle = pe:CreateText(card.body, "GameFontHighlightSmall", "textMuted")
	card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)
	card.subtitle:SetPoint("TOPRIGHT", card.title, "BOTTOMRIGHT", 0, -2)
	card.facts = pe:CreateKeyValueList(card.body)
	card.facts:SetPoint("TOPLEFT", card.subtitle, "BOTTOMLEFT", 0, -10)
	card.facts:SetPoint("TOPRIGHT", card.subtitle, "BOTTOMRIGHT", 0, -10)
	card.facts:SetHeight((5 + MAX_ITEM_ROWS) * 16)
	card.note = pe:CreateParagraph(card.body)
	card.note:SetPoint("TOPLEFT", card.facts, "BOTTOMLEFT", 0, -10)
	card.note:SetPoint("TOPRIGHT", card.facts, "BOTTOMRIGHT", 0, -10)
	card.note:SetText("Worth now is the usual price after the cut for items known to sell, and vendor price for the rest.")
	buildDetailButtons(pe, panel, card)
	return card
end

local function showDetail(pe, panel, row)
	local card = panel.detail
	panel.selected, panel.deleteArmed = row, nil
	card.empty:SetShown(row == nil)
	card.body:SetShown(row ~= nil)
	if not row then
		return
	end
	card.title:SetText(row.name)
	card.subtitle:SetText(string.format("%s · %d runs · %s", row.zone ~= "" and row.zone or "Unknown zone", row.runs, duration(row.activeSeconds)))
	card.facts:SetRows(detailRows(pe, row))
	card.delete:SetText("Delete")
	card.start:SetEnabled(pe:GetCurrentFarmRun() == nil)
end

-- Status text on the left, Start farm on the right.
local function buildToolbar(pe, panel)
	panel.toolbar = CreateFrame("Frame", nil, panel)
	panel.toolbar:SetPoint("TOPLEFT")
	panel.toolbar:SetPoint("TOPRIGHT")
	panel.toolbar:SetHeight(26)
	panel.status = pe:CreateText(panel.toolbar, "GameFontHighlightSmall", "textMuted")
	local lastViewButton = pe:BuildFarmViewButtons(panel, function() FarmingTab:Refresh() end)
	panel.status:SetPoint("LEFT", lastViewButton, "RIGHT", GAP, 0)
	panel.startButton = pe:CreateButton(panel.toolbar, "Start farm", function()
		if pe:GetCurrentFarmRun() then
			pe:ToggleFarmWindow()
		else
			pe:StartFarmRun()
		end
		FarmingTab:Refresh()
	end)
	panel.startButton:SetPoint("RIGHT")
	panel.status:SetPoint("RIGHT", panel.startButton, "LEFT", -GAP, 0)
end

local function buildTable(pe, panel)
	return pe:CreateReusableTable(panel, {
		footer = true,
		rowHeight = ROW_HEIGHT,
		autoFitToScroll = true,
		sortKey = "now",
		sortAsc = false,
		emptyTitle = "No farms yet",
		emptyHint = "Press Start farm, loot for a while, then stop it from the farm window.",
		isRowSelected = function(row)
			return panel.selected ~= nil and row ~= nil and row.name == panel.selected.name
		end,
		onRowClick = function(_, row, _, tableWidget)
			tableWidget:SetSelectedRow(row)
			showDetail(pe, panel, row)
		end,
	})
end

local function buildPanel(pe, container)
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	buildToolbar(pe, panel)
	panel.statsRow = CreateFrame("Frame", nil, panel)
	panel.statsRow:SetPoint("TOPLEFT", panel.toolbar, "BOTTOMLEFT", 0, -GAP)
	panel.statsRow:SetPoint("TOPRIGHT", panel.toolbar, "BOTTOMRIGHT", 0, -GAP)
	panel.statsRow:SetHeight(58)
	panel.stats = {}
	for index = 1, 4 do
		panel.stats[index] = pe:CreateStat(panel.statsRow)
	end
	panel.detail = buildDetail(pe, panel)
	panel.detail:SetPoint("TOPRIGHT", panel.statsRow, "BOTTOMRIGHT", 0, -GAP)
	panel.detail:SetPoint("BOTTOMRIGHT")
	panel.table = buildTable(pe, panel)
	panel.table.frame:SetPoint("TOPLEFT", panel.statsRow, "BOTTOMLEFT", 0, -GAP)
	panel.table.frame:SetPoint("BOTTOMRIGHT", panel.detail, "BOTTOMLEFT", -GAP, 0)
	panel.table:SetColumns(farmColumns(pe))
	panel.targets = pe:CreateFarmTargetsView(panel)
	panel.targets:SetPoint("TOPLEFT", panel.toolbar, "BOTTOMLEFT", 0, -GAP)
	panel.targets:SetPoint("BOTTOMRIGHT")
	panel:SetScript("OnSizeChanged", function(self)
		pe:LayoutEvenRow(self.statsRow, self.stats, 0, GAP)
	end)
	showDetail(pe, panel, nil)
	return panel
end

local function refreshStats(pe, panel, rows)
	local best, seconds, value, runs = nil, 0, 0, 0
	for _, row in ipairs(rows) do
		if not best or row.nowPerHour > best.nowPerHour then
			best = row
		end
		seconds, value, runs = seconds + row.activeSeconds, value + row.valueWhenSaved, runs + row.runs
	end
	panel.stats[1]:SetValues("Best farm at today's prices", best and (pe:FormatCopperShort(best.nowPerHour) .. " an hour") or "-", best and best.name or "")
	panel.stats[2]:SetValues("Farmed, all runs", pe:FormatCopperShort(value), "Worth when saved", "success")
	panel.stats[3]:SetValues("Time farming", duration(seconds), "Pauses not counted")
	panel.stats[4]:SetValues("Runs", tostring(runs), string.format("%d farms", #rows))
	pe:LayoutEvenRow(panel.statsRow, panel.stats, 0, GAP)
end

local function refreshStatus(pe, panel)
	local running = pe:GetCurrentFarmRun()
	panel.status:SetText(running and ("Farm running: " .. running.name) or "No farm running")
	panel.startButton:SetText(running and "Show farm window" or "Start farm")
end

function FarmingTab:Create(container, uiState)
	uiState.farmingPanel = uiState.farmingPanel or buildPanel(AuctionHelper, container)
	uiState.farmingPanel:Show()
	return uiState.farmingPanel
end

function FarmingTab:ApplyTheme() -- luacheck: ignore 212
end

function FarmingTab:Refresh() -- luacheck: ignore 212
	local pe = AuctionHelper
	local panel = pe.ui and pe.ui.farmingPanel
	if not panel then
		return
	end
	refreshStatus(pe, panel)
	if pe:ApplyFarmView(panel) then
		panel.targets:Refresh()
		return
	end
	local rows = pe:GetFarmRows()
	refreshStats(pe, panel, rows)
	panel.table:SetRows(rows)
	panel.table:SetFooterText("Gold an hour: Then at the day's prices, Now at today's", string.format("%d farms", #rows))
	panel.table:Refresh()
	local keep
	for _, row in ipairs(rows) do
		if panel.selected and row.name == panel.selected.name then
			keep = row
		end
	end
	showDetail(pe, panel, keep)
end
