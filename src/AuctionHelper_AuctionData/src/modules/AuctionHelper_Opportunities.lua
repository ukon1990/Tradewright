local _, ProfessionExporter = ...

-- Flip rows for the Opportunities tab (F50), built from the market insights of the last scans.

local FULL_DAYS, EARLY_DAYS = 5, 2

local function allowEarly(pe)
	return pe:GetSetting("opportunities.allowEarly", false) == true
end

--- Usual price for the Opportunities lists: the full one (5+ days) or, with early rows allowed in Settings,
--- one from 2 to 4 days. Returns the usual price, or nil, and whether it is early (F56).
function ProfessionExporter:GetOpportunityUsual(storageKey)
	local usual = self:GetUsualPrice(storageKey)
	if usual or not (allowEarly(self) and self.GetEarlyUsualPrice) then
		return usual, false
	end
	local partial = self:GetEarlyUsualPrice(storageKey)
	if partial and partial.days >= EARLY_DAYS then
		return partial, true
	end
	return nil, false
end

-- Days of prices behind one item (early ones included), and 1 when it has a full usual price and sells a day.
local function itemHistory(pe, storageKey)
	local full = pe:GetUsualPrice(storageKey)
	local usual = full or (pe.GetEarlyUsualPrice and pe:GetEarlyUsualPrice(storageKey))
	local sells = full and pe:GetSellsPerDay(storageKey)
	return usual and usual.days or 0, sells and 1 or 0
end

--- How many items of the last scan have enough days of prices (`FlipLogic.HistoryCoverage`), plus
--- `withSells`: those with a full usual price that also have a sells-a-day estimate. Cached per scan.
function ProfessionExporter:GetHistoryCoverage(insights)
	local state = self:GetState()
	if state.historyCoverageAt ~= insights.builtAt then
		local dayCounts, withSells = {}, 0
		for _, row in pairs(insights.byItemID or {}) do
			local days, sells = itemHistory(self, row.storageKey)
			dayCounts[#dayCounts + 1] = days
			withSells = withSells + sells
		end
		state.historyCoverage = self.FlipLogic.HistoryCoverage(dayCounts, FULL_DAYS, EARLY_DAYS)
		state.historyCoverage.withSells = withSells
		state.historyCoverageAt = insights.builtAt
	end
	return state.historyCoverage
end

--- Thresholds for flips, from Settings. `minProfit` is in copper.
function ProfessionExporter:GetFlipOptions()
	return {
		minDiscount = tonumber(self:GetSetting("opportunities.minDiscount", 0.25)) or 0.25,
		minProfit = tonumber(self:GetSetting("opportunities.minProfitCopper", 10000)) or 10000,
		minSellsPerDay = tonumber(self:GetSetting("opportunities.minSellsPerDay", 1)) or 1,
		dayShare = tonumber(self:GetSetting("opportunities.dayShare", 0.34)) or 0.34,
		cut = self.GetCraftsAhCutFraction and self:GetCraftsAhCutFraction() or 0.05,
		allowEarly = allowEarly(self),
	}
end

-- One candidate per scanned item that has a usual price and a sells-a-day estimate.
local function flipCandidates(pe, insights)
	local items = {}
	for itemID, row in pairs(insights.byItemID or {}) do
		local usual, early = pe:GetOpportunityUsual(row.storageKey)
		local sells = usual and pe:GetSellsPerDay(row.storageKey)
		if sells then
			items[#items + 1] = pe.FlipLogic.SetSells({
				itemID = itemID, storageKey = row.storageKey, price = row.price, usual = usual.usual,
				usualLow = usual.low, usualHigh = usual.high, usualDays = usual.days, early = early or nil,
				confidence = sells.confidence, steps = pe:GetPriceSteps(itemID),
			}, sells)
		end
	end
	return items
end

local function optionsKey(opts)
	return table.concat({ opts.minDiscount, opts.minProfit, opts.minSellsPerDay, opts.dayShare, opts.cut, tostring(opts.allowEarly) }, ":")
end

--- Flip rows, most profit first, or nil while the market insights are still being built
--- (`onReady` then fires once they are). Cached until the insights or the thresholds change.
function ProfessionExporter:GetFlipRows(onReady)
	local insights = self:GetMarketInsights(onReady)
	if not insights then
		return nil
	end
	local state = self:GetState()
	local opts = self:GetFlipOptions()
	local revision = tostring(insights.builtAt) .. ":" .. optionsKey(opts)
	if state.flipRowsRevision ~= revision then
		local candidates = flipCandidates(self, insights)
		local rows = self.FlipLogic.CarryOver(self.FlipLogic.BuildFlipRows(candidates, opts), candidates)
		for _, row in ipairs(rows) do
			row._rowIdentity = tostring(row.itemID)
		end
		state.flipRows, state.flipRowsRevision = rows, revision
	end
	return state.flipRows, insights
end

-- One candidate per scanned item whose vendor price the client already knows.
local function vendorCandidates(pe, insights)
	local items = {}
	for itemID, row in pairs(insights.byItemID or {}) do
		local vendorSell = pe:GetItemVendorSellCopper(itemID)
		if vendorSell and row.price < vendorSell then
			items[#items + 1] = {
				itemID = itemID, storageKey = row.storageKey, price = row.price, vendorSell = vendorSell,
				steps = pe:GetPriceSteps(itemID),
			}
		end
	end
	return items
end

--- Items listed under their vendor price, most gain first, or nil while the market insights are being
--- built. Vendor prices load on demand, so the list is rebuilt at most every 30 seconds to pick up
--- items whose price was not known yet.
function ProfessionExporter:GetVendorRows(onReady)
	local insights = self:GetMarketInsights(onReady)
	if not insights or not self:GetSetting("opportunities.showVendor", true) then
		return insights and {} or nil, insights
	end
	local state = self:GetState()
	local stamp = math.floor(time() / 30)
	local revision = tostring(insights.builtAt) .. ":" .. stamp
	if state.vendorRowsRevision ~= revision then
		local rows = self.FlipLogic.BuildVendorRows(vendorCandidates(self, insights), { minGain = 1000 })
		for _, row in ipairs(rows) do
			row._rowIdentity = tostring(row.itemID)
		end
		state.vendorRows, state.vendorRowsRevision = rows, revision
	end
	return state.vendorRows, insights
end

--- Thresholds for price gaps, from Settings. `maxCost` is in copper.
function ProfessionExporter:GetGapOptions()
	return {
		minGapPct = 0.25,
		maxCost = (tonumber(self:GetSetting("opportunities.gapMaxCostGold", 100)) or 100) * 10000,
		minSellsPerDay = tonumber(self:GetSetting("opportunities.gapMinSellsPerDay", 5)) or 5,
		cut = self.GetCraftsAhCutFraction and self:GetCraftsAhCutFraction() or 0.05,
	}
end

-- One candidate per scanned item that has price steps, a usual price and a sells-a-day estimate.
local function gapCandidates(pe, insights)
	local items = {}
	for itemID, row in pairs(insights.byItemID or {}) do
		local steps = pe:GetPriceSteps(itemID)
		local usual, early
		if steps then
			usual, early = pe:GetOpportunityUsual(row.storageKey)
		end
		local sells = usual and pe:GetSellsPerDay(row.storageKey)
		if sells then
			items[#items + 1] = pe.FlipLogic.SetSells({
				itemID = itemID, storageKey = row.storageKey, steps = steps,
				usualHigh = usual.high, early = early or nil, usualDays = usual.days,
			}, sells)
		end
	end
	return items
end

--- Price gaps, most gain first, or nil while the market insights are being built. Cached until the
--- insights or the thresholds change.
function ProfessionExporter:GetGapRows(onReady)
	local insights = self:GetMarketInsights(onReady)
	if not insights or not self:GetSetting("opportunities.showGaps", true) then
		return insights and {} or nil, insights
	end
	local state = self:GetState()
	local opts = self:GetGapOptions()
	local revision = table.concat({ tostring(insights.builtAt), opts.maxCost, opts.minSellsPerDay, opts.cut, tostring(allowEarly(self)) }, ":")
	if state.gapRowsRevision ~= revision then
		local candidates = gapCandidates(self, insights)
		local rows = self.FlipLogic.CarryOver(self.FlipLogic.BuildGapRows(candidates, opts), candidates)
		for _, row in ipairs(rows) do
			row._rowIdentity = tostring(row.itemID)
		end
		state.gapRows, state.gapRowsRevision = rows, revision
	end
	return state.gapRows, insights
end
