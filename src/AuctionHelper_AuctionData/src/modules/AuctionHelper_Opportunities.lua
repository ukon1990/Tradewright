local _, ProfessionExporter = ...

-- Flip rows for the Opportunities tab (F50), built from the market insights of the last scans.

--- Thresholds for flips, from Settings. `minProfit` is in copper.
function ProfessionExporter:GetFlipOptions()
	return {
		minDiscount = tonumber(self:GetSetting("opportunities.minDiscount", 0.25)) or 0.25,
		minProfit = (tonumber(self:GetSetting("opportunities.minProfitGold", 5)) or 5) * 10000,
		minSellsPerDay = tonumber(self:GetSetting("opportunities.minSellsPerDay", 1)) or 1,
		dayShare = tonumber(self:GetSetting("opportunities.dayShare", 0.34)) or 0.34,
		cut = self.GetCraftsAhCutFraction and self:GetCraftsAhCutFraction() or 0.05,
	}
end

-- One candidate per scanned item that has a usual price and a sells-a-day estimate.
local function flipCandidates(pe, insights)
	local items = {}
	for itemID, row in pairs(insights.byItemID or {}) do
		local usual = pe:GetUsualPrice(row.storageKey)
		local sells = usual and pe:GetSellsPerDay(row.storageKey)
		if sells then
			items[#items + 1] = {
				itemID = itemID, storageKey = row.storageKey, price = row.price, usual = usual.usual,
				usualLow = usual.low, usualHigh = usual.high, usualDays = usual.days,
				sellsPerDay = sells.perDay, confidence = sells.confidence, steps = pe:GetPriceSteps(itemID),
			}
		end
	end
	return items
end

local function optionsKey(opts)
	return table.concat({ opts.minDiscount, opts.minProfit, opts.minSellsPerDay, opts.dayShare, opts.cut }, ":")
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
		local byItem = {}
		local candidates = flipCandidates(self, insights)
		for _, item in ipairs(candidates) do
			byItem[item.itemID] = item
		end
		local rows = self.FlipLogic.BuildFlipRows(candidates, opts)
		for _, row in ipairs(rows) do
			local item = byItem[row.itemID]
			row._rowIdentity = tostring(row.itemID)
			row.usualLow, row.usualHigh, row.usualDays = item.usualLow, item.usualHigh, item.usualDays
		end
		state.flipRows, state.flipRowsRevision = rows, revision
	end
	return state.flipRows, insights
end
