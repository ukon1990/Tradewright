local Tradewright = select(2, ...)

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- "What to farm": trade goods ranked by the gold that changes hands in them each day, with
-- the farm where you looted each one before. The addon ships no drop data: the last two columns come
-- only from your own saved farms.

local GAP = 12
local TRADE_GOODS_CLASS = 7
local VIEWS = { { id = "farms", label = L["My farms"] }, { id = "targets", label = L["What to farm"] } }

local function isTradeGood(itemID)
	local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	return getInstant ~= nil and select(6, getInstant(itemID)) == TRADE_GOODS_CLASS
end

local HELP = L["Trade goods ranked by the gold that changes hands in them each day, from your auction house scans."]
	.. L[" An item needs full scans on 5 different days, about a day apart, before it shows up."]
	.. L[" Early estimates lists the rest now, from fewer scans, below the ranked ones.\n\n"]
	.. L["Your saved farms fill the last two columns: where you looted the item and what that earns an hour."]
	.. L[" Tradewright ships no drop data or routes."]

-- A candidate for one scanned trade good: full when it has a usual price and sales a day, an early estimate
-- (latest price, sales if known) when `early` is on, otherwise nil.
local function targetCandidate(pe, itemID, row, early)
	local usual = pe:GetUsualPrice(row.storageKey)
	local sells = pe:GetSellsPerDay(row.storageKey)
	local item = { itemID = itemID, storageKey = row.storageKey, quantity = row.quantity, supplyChange = row.supplyChange }
	if usual and sells then
		item.usual, item.sellsPerDay = usual.usual, sells.perDay
		return item
	end
	if not early then
		return nil
	end
	local partial = pe:GetEarlyUsualPrice(row.storageKey)
	item.usual = partial and partial.usual or row.price
	item.sellsPerDay, item.early, item.days = sells and sells.perDay, true, partial and partial.days or 0
	return item
end

-- Candidates for every scanned trade good, plus how many trade goods were scanned at all.
local function targetCandidates(pe, insights, early)
	local materials = pe:GetRecipeMaterialSet()
	local items, tradeGoods = {}, 0
	for itemID, row in pairs(insights.byItemID or {}) do
		if isTradeGood(itemID) then
			tradeGoods = tradeGoods + 1
			local item = targetCandidate(pe, itemID, row, early)
			if item then
				item.usedByRecipes = materials[itemID] == true
				items[#items + 1] = item
			end
		end
	end
	return items, tradeGoods
end

--- Rows for "What to farm" and the empty-list title and hint, or nil while the market insights are being built.
function Tradewright:GetFarmTargetRows(onReady)
	local insights = self:GetMarketInsights(onReady)
	if not insights then
		return nil
	end
	local Farm = self.FarmLogic
	local ledger = self:InitLedger()
	local lootIndex = Farm.BuildLootIndex(ledger and ledger.farm and ledger.farm.farms or {})
	local candidates, tradeGoods = targetCandidates(self, insights, self:GetSetting("farming.early", false))
	local opts = {
		cut = self:GetAuctionCut(),
		onlyRecipes = self:GetSetting("farming.onlyRecipes", false),
		onlyFarmed = self:GetSetting("farming.onlyFarmed", false),
	}
	local rows = Farm.BuildFarmTargets(candidates, lootIndex, opts)
	for _, row in ipairs(rows) do
		row._rowIdentity = tostring(row.itemID)
	end
	return rows, Farm.FarmTargetsEmptyText({ tradeGoods = tradeGoods, priced = #candidates }, opts)
end

local function perDayText(pe, perDay)
	if perDay >= 10 then
		return pe:FormatNumberGrouped(math.floor(perDay + 0.5))
	end
	return string.format("%.1f", perDay)
end

local function targetDetail(pe, row)
	if row.early then
		local basis = (row.days or 0) > 0 and string.format(L["%d of 5 days"], row.days) or L["latest scan only"]
		return pe:Colorize(L["Early estimate: "] .. basis, "warning")
	end
	local supply = row.daysOfSupply < 1 and L["Supply lasts under a day"] or string.format(L["Supply lasts %d days"], math.floor(row.daysOfSupply + 0.5))
	return supply .. (row.usedByRecipes and L[" · used by your recipes"] or "")
end

-- "Sales a day" and "Traded a day"; early estimates may lack both.
local function salesColumns(pe)
	local sells = {
		id = "sellsPerDay", label = L["Sales a day"], justifyH = "RIGHT", width = 70, sortable = true, defaultSort = "desc",
		sortValue = function(row) return row.sellsPerDay or -1 end,
		getText = function(row) return row.sellsPerDay and perDayText(pe, row.sellsPerDay) or "?" end,
	}
	local traded = pe:MoneyColumn({ id = "traded", label = L["Traded a day"], field = "tradedPerDay", width = 86, sortValue = pe.FarmLogic.TargetRank })
	return sells, traded
end

local function targetColumns(pe)
	local sells, traded = salesColumns(pe)
	return {
		pe:CreateItemColumn({
			label = L["Item"], defaultSort = "asc",
			getItemID = function(row) return row.itemID end,
			getName = function(row) return pe:GetItemDisplayName(row.itemID) end,
			getDetail = function(row) return targetDetail(pe, row) end,
		}),
		pe:MoneyColumn({ id = "usual", label = L["Usual price"], width = 80 }),
		sells, traded,
		{
			id = "listed", label = L["Listed"], justifyH = "RIGHT", width = 56, sortable = true, defaultSort = "asc", optional = true,
			sortValue = function(row) return row.supplyChange or 0 end,
			getText = function(row) return pe:FormatSignedPercent(row.supplyChange) end,
		},
		{
			id = "source", label = L["Where you got it"], width = 190, minWidth = 120, sortable = true, defaultSort = "asc",
			sortValue = function(row) return row.source or "~" end,
			getText = function(row)
				if not row.source then
					return L["Not looted in a farm yet"]
				end
				return string.format(L["%s, %.1f an hour"], row.source, row.sourcePerHour)
			end,
		},
		pe:MoneyColumn({ id = "yours", label = L["Yours, an hour"], field = "yoursPerHour", width = 90 }),
	}
end

-- Two toggle buttons at the top right.
local function buildTargetFilters(pe, view)
	view.filters = {}
	local previous
	for _, filter in ipairs({
		{ "farming.onlyFarmed", L["Only farmed before"] }, { "farming.onlyRecipes", L["My recipes use it"] }, { "farming.early", L["Early estimates"] },
	}) do
		local button = pe:CreateButton(view, filter[2], function()
			pe:SetSetting(filter[1], not pe:GetSetting(filter[1], false))
			view:Refresh()
		end, { small = true })
		button.setting = filter[1]
		button:SetPoint("TOPRIGHT", previous or view, previous and "TOPLEFT" or "TOPRIGHT", previous and -6 or 0, 0)
		previous = button
		view.filters[#view.filters + 1] = button
	end
end

local function materialCount(rows)
	local early = 0
	for _, row in ipairs(rows) do
		early = early + (row.early and 1 or 0)
	end
	return early > 0 and string.format(L["%d trade goods · %d early"], #rows, early) or string.format(L["%d trade goods"], #rows)
end

--- The "What to farm" view: a note, two filter buttons and the table. Call `:Refresh()` when shown.
function Tradewright:CreateFarmTargetsView(panel)
	local pe = self
	local view = CreateFrame("Frame", nil, panel)
	view.note = pe:CreateText(view, "GameFontHighlightSmall", "textMuted")
	view.note:SetPoint("TOPLEFT")
	view.note:SetText(L["Trade goods that move the most gold a day."])
	buildTargetFilters(pe, view)
	view.help = pe:CreateButton(view, "?", nil, { small = true, width = 22, tooltip = HELP })
	view.help:SetPoint("LEFT", view.note, "RIGHT", 6, 0)
	view.table = pe:CreateReusableTable(view, {
		footer = true, rowHeight = 36, autoFitToScroll = true, sortKey = "traded", sortAsc = false,
		onRowEnter = function(rowFrame, row)
			pe:ShowItemRowTooltip(rowFrame, row and row.itemID, nil, pe:DealRowHint(true))
		end,
		onRowLeave = function() GameTooltip:Hide() end,
		onRowClick = function(_, row, button)
			if row and not pe:HandleItemRowModifiedClick(row.itemID) then
				pe:HandleDealRowClick(row, button, true)
			end
		end,
	})
	view.table.frame:SetPoint("TOPLEFT", 0, -(22 + GAP))
	view.table.frame:SetPoint("BOTTOMRIGHT")
	view.table:SetColumns(targetColumns(pe))
	function view:Refresh()
		for _, button in ipairs(self.filters) do
			pe:StyleShellButton(button, pe:GetSetting(button.setting, false) == true)
		end
		local rows, emptyTitle, emptyHint = pe:GetFarmTargetRows(function() if self:IsVisible() then self:Refresh() end end)
		self.table:SetEmptyText(emptyTitle, emptyHint)
		self.table:SetLoading(not rows and pe.MarketInsightsLoadingNote or nil)
		self.table:SetRows(rows or {})
		self.table:SetFooterText(rows and L["Traded a day = usual price times estimated sales, a ranking and not income"] or L["Reading the last scan…"],
			rows and materialCount(rows) or "")
		self.table:Refresh()
	end
	return view
end

--- The two list buttons at the left of the Farming toolbar. Returns the last button, for anchoring.
function Tradewright:BuildFarmViewButtons(panel, onChanged)
	local pe = self
	panel.viewButtons = {}
	local previous
	for _, view in ipairs(VIEWS) do
		local button = pe:CreateButton(panel.toolbar, view.label, function()
			pe:SetSetting("farming.view", view.id)
			onChanged()
		end)
		button.viewId = view.id
		button:SetPoint("LEFT", previous or panel.toolbar, previous and "RIGHT" or "LEFT", previous and -1 or 0, 0)
		previous = button
		panel.viewButtons[#panel.viewButtons + 1] = button
	end
	return previous
end

--- Show the chosen list of the Farming tab and hide the other. Returns true for "What to farm".
function Tradewright:ApplyFarmView(panel)
	local current = self:GetSetting("farming.view", "farms")
	local showTargets = current == "targets"
	for _, button in ipairs(panel.viewButtons or {}) do
		self:StyleShellButton(button, button.viewId == current)
	end
	panel.statsRow:SetShown(not showTargets)
	panel.detail:SetShown(not showTargets)
	panel.table.frame:SetShown(not showTargets)
	panel.targets:SetShown(showTargets)
	return showTargets
end
