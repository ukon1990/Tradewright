local _, AuctionHelper = ...

-- Gold dashboard (Overview → Gold): five headline numbers and four cards that answer
-- "what should I buy, craft and sell right now". Market numbers come from GetMarketInsights,
-- which builds in the background; crafts come from the cached crafts engine (never forced).

local GAP = 12
local ROW = 36
local MIN_CARD_HEIGHT = 150
local ACCT_KEY = AuctionHelper.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"

local function ageText(ts)
	if not ts then
		return "never seen"
	end
	local age = math.max(0, time() - ts)
	if age < 3600 then
		return string.format("seen %dm ago", math.floor(age / 60))
	elseif age < 48 * 3600 then
		return string.format("seen %dh ago", math.floor(age / 3600))
	end
	return string.format("seen %dd ago", math.floor(age / 86400))
end

local function itemColumn(pe, getDetail)
	return pe:ItemColumn({ sortable = false, minWidth = 120, getDetail = getDetail })
end

local function moneyColumn(pe, spec)
	spec.sortable = false
	return pe:MoneyColumn(spec)
end

-- Item rows: the tooltip lists `opts.tooltipPairs(row)` under `opts.hint`; a click that is not a
-- modified click (link, dress up) goes to `opts.onClick(row, button)`.
local function itemTableOptions(pe, opts)
	return {
		rowHeight = ROW,
		emptyTitle = opts.emptyTitle,
		emptyHint = opts.emptyHint,
		onRowEnter = function(rowFrame, row)
			if row then
				local hint = type(opts.hint) == "function" and opts.hint() or opts.hint
				pe:ShowItemRowTooltip(rowFrame, row.itemID, opts.tooltipPairs and opts.tooltipPairs(row), hint)
			end
		end,
		onRowClick = function(_, row, button)
			if not row or pe:HandleItemRowModifiedClick(row.itemID) then
				return
			end
			opts.onClick(row, button)
		end,
	}
end

local function openMarket(pe, row)
	pe:OpenMarketItem(row.storageKey)
end

-- Left click shows the item details window. Right click on a deal or mover opens its auction
-- house buy page while the auction house is open; otherwise (and always for owned items) Market.
local function canBuyNow(pe, buyable)
	return buyable and pe.IsAuctionHouseFrameOpen and pe.OpenItemInAuctionHouse and pe:IsAuctionHouseFrameOpen() or false
end

--- Click on an item row `{ itemID, storageKey }`: details window, auction house buy page or Market.
--- `buyable` rows go to the auction house on right-click while it is open. Shared with other item lists.
function AuctionHelper:HandleDealRowClick(row, button, buyable)
	local target = self.ForeverLogic.ResolveDealRowClick(button, canBuyNow(self, buyable))
	if target == "details" then
		self:ShowItemDetailsWindow(row.itemID, row.storageKey)
	elseif target == "auction" then
		self:OpenItemInAuctionHouse(row.itemID)
	else
		openMarket(self, row)
	end
end

--- The tooltip line naming what a click on such a row does.
function AuctionHelper:DealRowHint(buyable)
	return "Click for price history · Right-click to "
		.. (canBuyNow(self, buyable) and "buy at the auction house" or "open in Market")
		.. " · Shift-click to link"
end

local function rowClickHandler(pe, buyable)
	return function(row, button)
		pe:HandleDealRowClick(row, button, buyable)
	end
end

local function rowHint(pe, buyable)
	return function()
		return pe:DealRowHint(buyable)
	end
end

local function createDealsCard(pe, dash)
	dash.deals = pe:CreateTableCard(dash, {
		title = "Deals to buy",
		viewAllLabel = "Market",
		onViewAll = function() pe:ShowDashboardTab("market") end,
		columns = {
			itemColumn(pe, function(row)
				local parts = { "vs " .. (row.refSource or "usual"), ageText(row.seenAt) }
				if dash.materials and dash.materials[row.itemID] then
					parts[#parts + 1] = pe:Colorize("your material", "gold")
				end
				return table.concat(parts, " · ")
			end),
			moneyColumn(pe, { id = "price", label = "Price", width = 70 }),
			moneyColumn(pe, { id = "ref", label = "Usual", width = 70, optional = true }),
			{ id = "off", label = "Off", justifyH = "RIGHT", width = 48,
				getText = function(row) return pe:FormatPercentChange(row.discount and -row.discount, true) end },
		},
		table = itemTableOptions(pe, {
			emptyTitle = "No deals right now",
			emptyHint = "Deals show when an item is listed well below its usual price. Scan the auction house a few times to learn usual prices.",
			hint = rowHint(pe, true),
			onClick = rowClickHandler(pe, true),
			tooltipPairs = function(row)
				return {
					{ "Usual price (" .. (row.refSource or "?") .. ")", pe:FormatCopperFull(row.ref) },
					{ "Resale profit after cut", pe:FormatSignedMoney(row.gain) },
					{ "Listed", string.format("%s in %s auctions", pe:FormatNumberGrouped(row.quantity), pe:FormatNumberGrouped(row.listed)) },
				}
			end,
		}),
	})
end

-- Craft rows carry the output in outputItemID, so they get their own row handlers.
local function createCraftsCard(pe, dash)
	dash.crafts = pe:CreateTableCard(dash, {
		title = "Best crafts now",
		viewAllLabel = "Crafts",
		onViewAll = function() pe:ShowDashboardTab("crafts") end,
		columns = {
			pe:CreateItemColumn({
				sortable = false,
				minWidth = 120,
				getItemID = function(row) return row.outputItemID end,
				getIcon = function(row) return row.outputIcon end,
				getName = function(row) return (pe:GetCraftRowLabels(row)) end,
				getDetail = function(row) return select(2, pe:GetCraftRowLabels(row)) end,
			}),
			{ id = "profit", label = "Profit", justifyH = "RIGHT", width = 80,
				getText = function(row) return pe:FormatSignedMoney(row.profit) end },
			-- roi is already a percent (not a fraction), so it skips PercentColumn.
			{ id = "roi", label = "ROI", justifyH = "RIGHT", width = 48, optional = true,
				getText = function(row) return row.roi and string.format("%.0f%%", row.roi) or "-" end },
		},
		table = {
			rowHeight = ROW,
			emptyTitle = "No profitable crafts",
			emptyHint = "Scan your professions and the auction house to compare material cost with sale price.",
			onRowEnter = function(rowFrame, row)
				if row then
					pe:ShowCraftRowTooltip(rowFrame, row)
				end
			end,
			onRowClick = function(_, row)
				if row and not pe:HandleItemRowModifiedClick(row.outputItemID) then
					pe:OpenCraftRow(row)
				end
			end,
		},
	})
end

local function createSellCard(pe, dash)
	dash.sell = pe:CreateTableCard(dash, {
		title = "Sell what I own",
		viewAllLabel = "Inventory",
		onViewAll = function() pe:ShowDashboardTab("inventory") end,
		columns = {
			itemColumn(pe, function(row)
				local note = row.change and (row.change >= 0.1 and "above its usual price" or "near its usual price") or "no price history yet"
				return string.format("%s owned · %s", pe:FormatNumberGrouped(row.total), note)
			end),
			moneyColumn(pe, { id = "price", label = "Price", width = 70, optional = true }),
			{ id = "change", label = "Vs usual", justifyH = "RIGHT", width = 60,
				getText = function(row) return pe:FormatPercentChange(row.change) end },
			moneyColumn(pe, { id = "value", label = "Worth", width = 76 }),
		},
		table = itemTableOptions(pe, {
			emptyTitle = "Nothing to sell yet",
			emptyHint = "Refresh your inventory and scan the auction house to price what you own.",
			hint = rowHint(pe, false),
			onClick = rowClickHandler(pe, false),
			tooltipPairs = function(row)
				return {
					{ "You own", string.format("%s (bags %s, bank %s)", pe:FormatNumberGrouped(row.total),
						pe:FormatNumberGrouped(row.bags or 0), pe:FormatNumberGrouped(row.bank or 0)) },
					{ "Worth now", pe:FormatCopperFull(row.value) },
				}
			end,
		}),
	})
end

local function moversColumns(pe)
	local function supplyView()
		return pe:GetSetting("gold.moversView", "risers") == "supply"
	end
	return {
		itemColumn(pe, function(row)
			if supplyView() then
				return string.format("%s listed, usually %s", pe:FormatNumberGrouped(row.qtyNow or 0), pe:FormatNumberGrouped(row.qtyAvg7d or 0))
			end
			return (row.usualDays and "Usual price " or "7-day average ") .. pe:FormatCopperShort(row.avg7d or 0)
		end),
		moneyColumn(pe, { id = "price", label = "Price", width = 70 }),
		{ id = "change", label = "Change", justifyH = "RIGHT", width = 60,
			getText = function(row)
				if supplyView() then
					return pe:FormatPercentChange(row.supplyChange, true)
				end
				return pe:FormatPercentChange(row.change)
			end },
	}
end

-- Supply / Falling / Rising switch between the heading and the Market button.
local function createMoverButtons(pe, dash)
	dash.moverButtons = {}
	local previous
	for _, mode in ipairs({ { "supply", "Supply" }, { "fallers", "Falling" }, { "risers", "Rising" } }) do
		local button = pe:CreateButton(dash.movers, mode[2], function()
			pe:SetSetting("gold.moversView", mode[1])
			dash:RefreshMovers()
		end, { small = true })
		button.mode = mode[1]
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", 1, 0)
		else
			button:SetPoint("RIGHT", dash.movers.viewAll, "LEFT", -8, 0)
		end
		previous = button
		dash.moverButtons[#dash.moverButtons + 1] = button
	end
	dash.movers.heading:SetPoint("RIGHT", previous, "LEFT", -8, 0)
end

local function createMoversCard(pe, dash)
	dash.movers = pe:CreateTableCard(dash, {
		title = "Market movers",
		viewAllLabel = "Market",
		onViewAll = function() pe:ShowDashboardTab("market") end,
		columns = moversColumns(pe),
		table = itemTableOptions(pe, {
			emptyTitle = "No big moves",
			emptyHint = "Movers compare today's price and supply with the usual level in your scans.",
			hint = rowHint(pe, true),
			onClick = rowClickHandler(pe, true),
			tooltipPairs = function(row)
				return {
					{ row.usualDays and "Usual price" or "7-day average", pe:FormatCopperFull(row.avg7d) },
					{ row.usualDays and "Usual range" or "7-day range",
						string.format("%s – %s", pe:FormatCopperShort(row.low7d or 0), pe:FormatCopperShort(row.high7d or 0)) },
					{ "Listed now", string.format("%s, usually %s", pe:FormatNumberGrouped(row.qtyNow or 0), pe:FormatNumberGrouped(row.qtyAvg7d or 0)) },
				}
			end,
		}),
	})
	createMoverButtons(pe, dash)
end

function AuctionHelper:CreateGoldDashboard(parent)
	local pe = self
	local dash = CreateFrame("Frame", nil, parent)
	dash:SetAllPoints()
	pe.ui.goldDashboard = dash

	dash.statsRow = CreateFrame("Frame", nil, dash)
	dash.statsRow:SetPoint("TOPLEFT")
	dash.statsRow:SetPoint("TOPRIGHT")
	dash.statsRow:SetHeight(58)
	dash.stats = pe:CreateStats(dash.statsRow, { "gold", "stockValue", "profitableCrafts", "deals", "marketData" })

	createDealsCard(pe, dash)
	createCraftsCard(pe, dash)
	createSellCard(pe, dash)
	createMoversCard(pe, dash)

	function dash:Layout()
		local width, height = self:GetWidth(), self:GetHeight()
		pe:LayoutEvenRow(self.statsRow, self.stats, 0, GAP)
		local cardWidth = math.max(200, (width - GAP) / 2)
		local cardHeight = math.max(MIN_CARD_HEIGHT, (height - 58 - GAP * 2) / 2)
		for index, card in ipairs({ self.deals, self.crafts, self.sell, self.movers }) do
			local col, row = (index - 1) % 2, math.floor((index - 1) / 2)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", self.statsRow, "BOTTOMLEFT", col * (cardWidth + GAP), -GAP - row * (cardHeight + GAP))
			card:SetSize(cardWidth, cardHeight)
		end
	end

	function dash:RefreshCrafts()
		local rows = pe:BuildCraftOpportunityRows() or {}
		local profitable = {}
		for _, row in ipairs(rows) do
			if (tonumber(row.profit) or 0) > 0 and row.matCost then
				row._rowIdentity = row.rowKey or tostring(row.recipeID)
				profitable[#profitable + 1] = row
			end
		end
		local top = pe.ForeverLogic.TopN(profitable, 30, "profit")
		local state = pe:GetState()
		local tbl = self.crafts.table
		if #top == 0 and state.craftEvalInProgress and state.craftEvalWorkList and #state.craftEvalWorkList > 0 then
			local done = math.max(0, (state.craftEvalIdx or 1) - 1)
			tbl:SetEmptyText("Working out craft profit", string.format("%d of %d recipes checked…", done, #state.craftEvalWorkList))
		else
			tbl:SetEmptyText("No profitable crafts", "Scan your professions and the auction house to compare material cost with sale price.")
		end
		tbl:SetRows(top)
		tbl:Refresh()
		local best = top[1]
		self.stats.profitableCrafts:SetValues("Profitable crafts", pe:FormatNumberGrouped(#profitable),
			best and ("Best " .. pe:FormatCopperShort(best.profit) .. " each") or "None found yet", #profitable > 0 and "success" or nil)
	end

	function dash:RefreshMovers()
		local mode = pe:GetSetting("gold.moversView", "risers")
		for _, button in ipairs(dash.moverButtons) do
			pe:StyleShellButton(button, button.mode == mode)
		end
		local insights = self.insights
		self.movers.table:SetRows(insights and insights[mode] or {})
		self.movers.table:Refresh()
	end

	function dash:RefreshSell(insights)
		local rows, stockValue, priced, anyHistory = {}, 0, 0, false
		for _, inv in ipairs(pe:BuildInventoryRowsAggregatedByItem(pe.db, {}, "") or {}) do
			local market = insights and insights.byItemID[tonumber(inv.itemID)]
			local total = tonumber(inv.total) or 0
			if market and total > 0 then
				local value = market.price * total
				stockValue = stockValue + value
				priced = priced + 1
				anyHistory = anyHistory or market.change ~= nil
				rows[#rows + 1] = {
					_rowIdentity = tostring(inv.itemID),
					itemID = tonumber(inv.itemID),
					storageKey = market.storageKey,
					name = inv.name,
					total = total, bags = inv.bags, bank = inv.bank,
					price = market.price,
					change = market.change,
					value = value,
				}
			end
		end
		-- With history: items selling above their usual price. Without: what is worth the most.
		if anyHistory then
			local above = {}
			for _, row in ipairs(rows) do
				if row.change and row.change >= 0.1 then
					above[#above + 1] = row
				end
			end
			rows = above
		end
		self.sell.table:SetRows(pe.ForeverLogic.TopN(rows, 30, "value"))
		self.sell.table:Refresh()
		self.stats.stockValue:SetValues("Stock value", insights and pe:FormatCopperShort(stockValue) or "…",
			string.format("%s item types priced", pe:FormatNumberGrouped(priced)))
	end

	function dash:Refresh()
		-- Market insights live in the Auction Data module; without it the market cards stay empty.
		self.materials = pe.GetRecipeMaterialSet and pe:GetRecipeMaterialSet() or {}
		local insights = pe.GetMarketInsights and pe:GetMarketInsights(function()
			if self:IsVisible() then
				self:Refresh()
			end
		end) or nil
		self.insights = insights

		-- Account gold and its 7-day change.
		local gold = pe:GetCurrentGoldSummaryForOverview(ACCT_KEY) or 0
		local series = pe:GetOverviewWalletGraphSeries(ACCT_KEY, "7d", "balance") or {}
		local first = series[1] and tonumber(series[1].value)
		local note = "No history yet"
		if first then
			local delta = gold - first
			note = (delta >= 0 and pe:Colorize("+" .. pe:FormatCopperShort(delta), "success") or pe:Colorize(pe:FormatCopperShort(delta), "danger")) .. " in 7 days"
		end
		self.stats.gold:SetValues("Gold, all characters", pe:FormatCopperShort(gold), note)

		-- Deals and data freshness.
		if insights then
			local best = insights.deals[1]
			self.stats.deals:SetValues("Deals found", pe:FormatNumberGrouped(insights.dealCount),
				best and string.format("Best %s below usual", pe:FormatPercent(best.discount)) or "None right now",
				insights.dealCount > 0 and "gold" or nil)
			local lastScanAt = pe.GetLastFullAuctionScanAt and pe:GetLastFullAuctionScanAt()
			local stale = not lastScanAt or time() - lastScanAt > 24 * 3600
			self.stats.marketData:SetValues("Market data", lastScanAt and pe:FormatScanTimestamp(lastScanAt) or "No full scan",
				string.format("%s items", pe:FormatNumberGrouped(insights.itemCount)), stale and "warning" or nil)
		else
			local progress = pe:GetState().marketInsightsProgress or 0
			local working = string.format("Reading scans %d%%", progress * 100)
			self.stats.deals:SetValues("Deals found", "…", working)
			self.stats.marketData:SetValues("Market data", "…", working)
		end

		self.deals.table:SetRows(insights and insights.deals or {})
		self.deals.table:Refresh()
		self:RefreshSell(insights)
		self:RefreshMovers()
		self:RefreshCrafts()
		self:Layout()
	end

	dash:SetScript("OnSizeChanged", function()
		dash:Layout()
	end)
	dash:Layout()
	return dash
end
