local ProfessionExporter = select(2, ...)

-- "What to farm" (E09 F72): trade goods ranked by the gold that changes hands in them each day, with
-- the farm where you looted each one before. The addon ships no drop data: the last two columns come
-- only from your own saved farms.

local GAP = 12
local TRADE_GOODS_CLASS = 7
local VIEWS = { { id = "farms", label = "My farms" }, { id = "targets", label = "What to farm" } }

local function isTradeGood(itemID)
	local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	return getInstant ~= nil and select(6, getInstant(itemID)) == TRADE_GOODS_CLASS
end

local HELP = "Trade goods ranked by the gold that changes hands in them each day, from your auction house scans."
	.. " An item needs full scans on 5 different days, about a day apart, before it shows up.\n\n"
	.. "Your saved farms fill the last two columns: where you looted the item and what that earns an hour."
	.. " AuctionHelper ships no drop data or routes."

-- One candidate per scanned trade good with a usual price and a sells-a-day estimate, plus how many
-- trade goods were scanned at all.
local function targetCandidates(pe, insights)
	local materials = pe:GetRecipeMaterialSet()
	local items, tradeGoods = {}, 0
	for itemID, row in pairs(insights.byItemID or {}) do
		local tradeGood = isTradeGood(itemID)
		tradeGoods = tradeGoods + (tradeGood and 1 or 0)
		local usual = tradeGood and pe:GetUsualPrice(row.storageKey)
		local sells = usual and pe:GetSellsPerDay(row.storageKey)
		if sells then
			items[#items + 1] = {
				itemID = itemID, storageKey = row.storageKey, usual = usual.usual, sellsPerDay = sells.perDay,
				quantity = row.quantity, supplyChange = row.supplyChange, usedByRecipes = materials[itemID] == true,
			}
		end
	end
	return items, tradeGoods
end

--- Rows for "What to farm" and the empty-list title and hint, or nil while the market insights are being built.
function ProfessionExporter:GetFarmTargetRows(onReady)
	local insights = self:GetMarketInsights(onReady)
	if not insights then
		return nil
	end
	local Farm = self.FarmLogic
	local ledger = self:InitLedger()
	local lootIndex = Farm.BuildLootIndex(ledger and ledger.farm and ledger.farm.farms or {})
	local candidates, tradeGoods = targetCandidates(self, insights)
	local opts = {
		cut = self.GetCraftsAhCutFraction and self:GetCraftsAhCutFraction() or 0.05,
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

local function targetDetail(row)
	local supply = row.daysOfSupply < 1 and "Supply lasts under a day" or string.format("Supply lasts %d days", math.floor(row.daysOfSupply + 0.5))
	return supply .. (row.usedByRecipes and " · used by your recipes" or "")
end

local function targetColumns(pe)
	local function money(id, label, field, width)
		return {
			id = id, label = label, justifyH = "RIGHT", width = width, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row[field] or -1 end,
			getText = function(row) return row[field] and pe:FormatCopperShort(row[field]) or "-" end,
		}
	end
	return {
		pe:CreateItemColumn({
			label = "Item", defaultSort = "asc",
			getItemID = function(row) return row.itemID end,
			getName = function(row) return pe:GetItemDisplayName(row.itemID) end,
			getDetail = targetDetail,
		}),
		money("usual", "Usual price", "usual", 80),
		{
			id = "sellsPerDay", label = "Sells a day", justifyH = "RIGHT", width = 70, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.sellsPerDay end,
			getText = function(row) return perDayText(pe, row.sellsPerDay) end,
		},
		money("traded", "Traded a day", "tradedPerDay", 86),
		{
			id = "listed", label = "Listed", justifyH = "RIGHT", width = 56, sortable = true, defaultSort = "asc", optional = true,
			sortValue = function(row) return row.supplyChange or 0 end,
			getText = function(row) return row.supplyChange and string.format("%+d%%", math.floor(row.supplyChange * 100 + 0.5)) or "-" end,
		},
		{
			id = "source", label = "Where you got it", width = 190, minWidth = 120, sortable = true, defaultSort = "asc",
			sortValue = function(row) return row.source or "~" end,
			getText = function(row)
				if not row.source then
					return "Not looted in a farm yet"
				end
				return string.format("%s, %.1f an hour", row.source, row.sourcePerHour)
			end,
		},
		money("yours", "Yours, an hour", "yoursPerHour", 90),
	}
end

-- Two toggle buttons at the top right.
local function buildTargetFilters(pe, view)
	view.filters = {}
	local previous
	for _, filter in ipairs({ { "farming.onlyFarmed", "Only farmed before" }, { "farming.onlyRecipes", "My recipes use it" } }) do
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

--- The "What to farm" view: a note, two filter buttons and the table. Call `:Refresh()` when shown.
function ProfessionExporter:CreateFarmTargetsView(panel)
	local pe = self
	local view = CreateFrame("Frame", nil, panel)
	view.note = pe:CreateText(view, "GameFontHighlightSmall", "textMuted")
	view.note:SetPoint("TOPLEFT")
	view.note:SetText("Trade goods that move the most gold a day.")
	buildTargetFilters(pe, view)
	view.help = pe:CreateButton(view, "?", nil, { small = true, width = 22, tooltip = HELP })
	view.help:SetPoint("LEFT", view.note, "RIGHT", 6, 0)
	view.table = pe:CreateReusableTable(view, {
		footer = true, rowHeight = 36, autoFitToScroll = true, sortKey = "traded", sortAsc = false,
		onRowEnter = function(rowFrame, row)
			pe:ShowItemRowTooltip(rowFrame, row and row.itemID, nil, "Shift-click to link")
		end,
		onRowLeave = function() GameTooltip:Hide() end,
		onRowClick = function(_, row) pe:HandleItemRowModifiedClick(row and row.itemID) end,
	})
	view.table.frame:SetPoint("TOPLEFT", 0, -(22 + GAP))
	view.table.frame:SetPoint("BOTTOMRIGHT")
	view.table:SetColumns(targetColumns(pe))
	function view:Refresh()
		for _, button in ipairs(self.filters) do
			pe:StyleShellButton(button, pe:GetSetting(button.setting, false) == true)
		end
		local rows, emptyTitle, emptyHint = pe:GetFarmTargetRows(function() if self:IsVisible() then self:Refresh() end end)
		self.table:SetEmptyText(emptyTitle or "Reading the last scan…", emptyHint or "")
		self.table:SetRows(rows or {})
		self.table:SetFooterText(rows and "Traded a day = usual price times estimated sales, a ranking and not income" or "Reading the last scan…",
			rows and string.format("%d materials", #rows) or "")
		self.table:Refresh()
	end
	return view
end

--- The two list buttons at the left of the Farming toolbar. Returns the last button, for anchoring.
function ProfessionExporter:BuildFarmViewButtons(panel, onChanged)
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
function ProfessionExporter:ApplyFarmView(panel)
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
