local _, AuctionHelper = ...

-- Gold dashboard (Overview → Gold): five headline numbers and four cards that answer
-- "what should I buy, craft and sell right now". Market numbers come from GetMarketInsights,
-- which builds in the background; crafts come from the cached crafts engine (never forced).

local GAP = 12
local PAD = 10
local ROW = 36
local MIN_CARD_HEIGHT = 150
local ACCT_KEY = AuctionHelper.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"

local function colorize(pe, colorKey, text)
	local c = pe:GetTheme()[colorKey]
	return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text)
end

-- "+18%" in green or "-12%" in red; `invert` swaps the colours (a lower price is good when buying).
local function percent(pe, fraction, invert)
	if not fraction then
		return "-"
	end
	local text = string.format("%+.0f%%", fraction * 100)
	if math.abs(fraction) < 0.005 then
		return text
	end
	local good = fraction > 0
	if invert then
		good = not good
	end
	return colorize(pe, good and "success" or "danger", text)
end

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

local function moneyColumn(pe, id, label, field, width, optional)
	return {
		id = id, label = label, justifyH = "RIGHT", width = width, optional = optional,
		getText = function(row) return row[field] and pe:FormatCopperShort(row[field]) or "-" end,
	}
end

local function itemColumn(pe, getDetail)
	return pe:CreateItemColumn({
		sortable = false,
		minWidth = 120,
		getItemID = function(row) return row.itemID end,
		getName = function(row) return row.name or pe:GetItemDisplayName(row.itemID) end,
		getDetail = getDetail,
	})
end

local function createCard(pe, parent, title, viewAllLabel, onViewAll)
	local card = pe:CreateInset(parent)
	card.viewAll = pe:CreateButton(card, viewAllLabel, onViewAll, { small = true })
	card.viewAll:SetPoint("TOPRIGHT", -PAD, -7)
	card.heading = pe:CreateHeading(card, title)
	card.heading:SetPoint("TOPLEFT", PAD, -PAD)
	card.heading:SetPoint("RIGHT", card.viewAll, "LEFT", -8, 0)
	return card
end

local function attachTable(pe, card, columns, opts)
	local tbl = pe:CreateReusableTable(card, {
		autoFitToScroll = true,
		rowHeight = ROW,
		emptyTitle = opts.emptyTitle,
		emptyHint = opts.emptyHint,
		onRowEnter = function(rowFrame, row)
			if row then
				local hint = type(opts.hint) == "function" and opts.hint() or opts.hint
				pe:ShowItemRowTooltip(rowFrame, row.itemID, opts.tooltipPairs and opts.tooltipPairs(row), hint)
			end
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, row, button)
			if not row or pe:HandleItemRowModifiedClick(row.itemID) then
				return
			end
			opts.onClick(row, button)
		end,
	})
	tbl:SetColumns(columns)
	tbl.frame:SetPoint("TOPLEFT", card.heading, "BOTTOMLEFT", 0, -10)
	tbl.frame:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PAD, PAD)
	card.table = tbl
	return tbl
end

local function openMarket(pe, row)
	pe:OpenMarketItem(row.storageKey)
end

-- F30: left click shows the item details window. Right click on a deal or mover opens its auction
-- house buy page while the auction house is open; otherwise (and always for owned items) Market.
local function canBuyNow(pe, buyable)
	return buyable and pe.IsAuctionHouseFrameOpen and pe.OpenItemInAuctionHouse and pe:IsAuctionHouseFrameOpen() or false
end

--- Click on an item row `{ itemID, storageKey }`: details window, auction house buy page or Market (F30).
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

function AuctionHelper:CreateGoldDashboard(parent)
	local pe = self
	local dash = CreateFrame("Frame", nil, parent)
	dash:SetAllPoints()
	pe.ui.goldDashboard = dash

	dash.statsRow = CreateFrame("Frame", nil, dash)
	dash.statsRow:SetPoint("TOPLEFT")
	dash.statsRow:SetPoint("TOPRIGHT")
	dash.statsRow:SetHeight(58)
	dash.stats = {}
	for index = 1, 5 do
		dash.stats[index] = pe:CreateStat(dash.statsRow)
	end

	-- Deals to buy.
	dash.deals = createCard(pe, dash, "Deals to buy", "Market", function() pe:ShowDashboardTab("market") end)
	attachTable(pe, dash.deals, {
		itemColumn(pe, function(row)
			local parts = { "vs " .. (row.refSource or "usual"), ageText(row.seenAt) }
			if dash.materials and dash.materials[row.itemID] then
				parts[#parts + 1] = colorize(pe, "gold", "your material")
			end
			return table.concat(parts, " · ")
		end),
		moneyColumn(pe, "price", "Price", "price", 70),
		moneyColumn(pe, "ref", "Usual", "ref", 70, true),
		{ id = "off", label = "Off", justifyH = "RIGHT", width = 48,
			getText = function(row) return percent(pe, row.discount and -row.discount, true) end },
	}, {
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
	})

	-- Best crafts now.
	dash.crafts = createCard(pe, dash, "Best crafts now", "Crafts", function() pe:ShowDashboardTab("crafts") end)
	attachTable(pe, dash.crafts, {
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
		{ id = "roi", label = "ROI", justifyH = "RIGHT", width = 48, optional = true,
			getText = function(row) return row.roi and string.format("%.0f%%", row.roi) or "-" end },
	}, {
		emptyTitle = "No profitable crafts",
		emptyHint = "Scan your professions and the auction house to compare material cost with sale price.",
		hint = "Click to open in Crafts. Shift-click to link.",
		onClick = function(row) pe:OpenCraftRow(row) end,
	})
	-- Craft rows carry the output in outputItemID; give the shared row handlers an itemID.
	dash.crafts.table.onRowEnter = function(rowFrame, row)
		if row then
			pe:ShowCraftRowTooltip(rowFrame, row)
		end
	end
	dash.crafts.table.onRowClick = function(_, row)
		if row and not pe:HandleItemRowModifiedClick(row.outputItemID) then
			pe:OpenCraftRow(row)
		end
	end

	-- Sell what I own.
	dash.sell = createCard(pe, dash, "Sell what I own", "Inventory", function() pe:ShowDashboardTab("inventory") end)
	attachTable(pe, dash.sell, {
		itemColumn(pe, function(row)
			local note = row.change and (row.change >= 0.1 and "above its usual price" or "near its usual price") or "no price history yet"
			return string.format("%s owned · %s", pe:FormatNumberGrouped(row.total), note)
		end),
		moneyColumn(pe, "price", "Price", "price", 70, true),
		{ id = "change", label = "Vs usual", justifyH = "RIGHT", width = 60,
			getText = function(row) return percent(pe, row.change) end },
		moneyColumn(pe, "value", "Worth", "value", 76),
	}, {
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
	})

	-- Market movers.
	dash.movers = createCard(pe, dash, "Market movers", "Market", function() pe:ShowDashboardTab("market") end)
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
	attachTable(pe, dash.movers, {
		itemColumn(pe, function(row)
			if pe:GetSetting("gold.moversView", "risers") == "supply" then
				return string.format("%s listed, usually %s", pe:FormatNumberGrouped(row.qtyNow or 0), pe:FormatNumberGrouped(row.qtyAvg7d or 0))
			end
			return (row.usualDays and "Usual price " or "7-day average ") .. pe:FormatCopperShort(row.avg7d or 0)
		end),
		moneyColumn(pe, "price", "Price", "price", 70),
		{ id = "change", label = "Change", justifyH = "RIGHT", width = 60,
			getText = function(row)
				if pe:GetSetting("gold.moversView", "risers") == "supply" then
					return percent(pe, row.supplyChange, true)
				end
				return percent(pe, row.change)
			end },
	}, {
		emptyTitle = "No big moves",
		emptyHint = "Movers compare today's price and supply with the usual level in your scans.",
		hint = rowHint(pe, true),
		onClick = rowClickHandler(pe, true),
		tooltipPairs = function(row)
			return {
				{ row.usualDays and "Usual price" or "7-day average", pe:FormatCopperFull(row.avg7d) },
				{ row.usualDays and "Usual range" or "7-day range", string.format("%s – %s", pe:FormatCopperShort(row.low7d or 0), pe:FormatCopperShort(row.high7d or 0)) },
				{ "Listed now", string.format("%s, usually %s", pe:FormatNumberGrouped(row.qtyNow or 0), pe:FormatNumberGrouped(row.qtyAvg7d or 0)) },
			}
		end,
	})

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
		self.stats[3]:SetValues("Profitable crafts", pe:FormatNumberGrouped(#profitable),
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
		self.stats[2]:SetValues("Stock value", insights and pe:FormatCopperShort(stockValue) or "…",
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

		-- 1. Account gold and its 7-day change.
		local gold = pe:GetCurrentGoldSummaryForOverview(ACCT_KEY) or 0
		local series = pe:GetOverviewWalletGraphSeries(ACCT_KEY, "7d", "balance") or {}
		local first = series[1] and tonumber(series[1].value)
		local note = "No history yet"
		if first then
			local delta = gold - first
			note = (delta >= 0 and colorize(pe, "success", "+" .. pe:FormatCopperShort(delta)) or colorize(pe, "danger", pe:FormatCopperShort(delta))) .. " in 7 days"
		end
		self.stats[1]:SetValues("Gold, all characters", pe:FormatCopperShort(gold), note)

		-- 4 and 5. Deals and data freshness.
		if insights then
			local best = insights.deals[1]
			self.stats[4]:SetValues("Deals found", pe:FormatNumberGrouped(insights.dealCount),
				best and string.format("Best %s below usual", string.format("%.0f%%", best.discount * 100)) or "None right now",
				insights.dealCount > 0 and "gold" or nil)
			local lastScanAt = pe.GetLastFullAuctionScanAt and pe:GetLastFullAuctionScanAt()
			local stale = not lastScanAt or time() - lastScanAt > 24 * 3600
			self.stats[5]:SetValues("Market data", lastScanAt and pe:FormatScanTimestamp(lastScanAt) or "No full scan",
				string.format("%s items", pe:FormatNumberGrouped(insights.itemCount)), stale and "warning" or nil)
		else
			local progress = pe:GetState().marketInsightsProgress or 0
			local working = string.format("Reading scans %d%%", progress * 100)
			self.stats[4]:SetValues("Deals found", "…", working)
			self.stats[5]:SetValues("Market data", "…", working)
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
