local _, Tradewright = ...

-- Fills the item detail window's time-series graph (price, crafting cost or quantity history) from Tradewright_Inventory data.

local function graphTimestampForSeries(at)
	if not at or at <= 0 then
		return "—"
	end
	return date("%Y-%m-%d %H:%M", at)
end

function Tradewright:ApplyItemDetailTimeSeriesGraph(itemID, graphWidget, config)
	config = config or {}
	if not graphWidget or not graphWidget.SetSeries then
		return
	end
	itemID = tonumber(itemID)
	if not itemID then
		return
	end
	local graphItemID = tonumber(config.graphItemID) or itemID
	local metric = self:GetSetting(config.metricSettingKey or "inventory.detailsGraphMetric", "market")
	local rangeKey = config.rangeKey or self:GetInventoryMetricRange()
	local qtyFilter = config.quantityCharacterFilter or {}
	local emptyQty = config.quantityEmptyHint
		or "No quantity history in this range yet. Run an inventory refresh while this item is tracked."
	graphWidget:SetAccentColor(self:GetTheme().accent)
	if graphWidget.SetSecondaryAccentColor then
		graphWidget:SetSecondaryAccentColor(self:GetTheme().warning)
	end
	if graphWidget.SetQuantityAccentColor then
		graphWidget:SetQuantityAccentColor(self:GetTheme().success)
	end
	local series
	local secondarySeries = {}
	local quantitySeries = {}
	local yFormatter
	local emptyExtra = "No observations in this range."
	local tooltipBuilder
	local function qtyTooltip(tip, pt)
		tip:AddLine(graphTimestampForSeries(pt.at), 1, 1, 1)
		local m = pt.meta or {}
		if m.ahHistory then
			tip:AddLine(
				string.format("AH sample quantity: %s", Tradewright:FormatNumberGrouped(tonumber(pt.value) or 0)),
				0.85,
				0.92,
				1
			)
			if (m.sampleCount or 0) > 0 then
				tip:AddLine(string.format("Price observations in hour: %d", m.sampleCount), 0.72, 0.8, 0.88)
			end
		else
			tip:AddLine(string.format("Total quantity: %s", Tradewright:FormatNumberGrouped(tonumber(pt.value) or 0)), 0.85, 0.92, 1)
			if (m.sampleCount or 0) > 0 then
				tip:AddLine(
					string.format(
						"Bags %s  |  Bank %s  |  Warband %s",
						Tradewright:FormatNumberGrouped(m.bags or 0),
						Tradewright:FormatNumberGrouped(m.bank or 0),
						Tradewright:FormatNumberGrouped(m.warband or 0)
					),
					0.72,
					0.8,
					0.88
				)
			end
		end
	end
	local function craftingTooltip(tip, pt)
		tip:AddLine(graphTimestampForSeries(pt.at), 1, 1, 1)
		tip:AddLine("|cffffcc00Crafting cost|r  " .. Tradewright:FormatCopperFull(pt.value), 0.85, 0.92, 1)
		local m = pt.meta or {}
		if m.flat then
			tip:AddLine("Current estimate (flat)", 0.72, 0.8, 0.88)
		end
		if m.count and m.count > 0 then
			tip:AddLine(string.format("Samples in hour: %d", m.count), 0.72, 0.8, 0.88)
		end
		if m.min and m.max then
			tip:AddLine(
				string.format(
					"Min %s  |  Max %s",
					Tradewright:FormatCopperFull(m.min),
					Tradewright:FormatCopperFull(m.max)
				),
				0.72,
				0.8,
				0.88
			)
		end
	end
	local function marketTooltip(tip, pt)
		tip:AddLine(graphTimestampForSeries(pt.at), 1, 1, 1)
		tip:AddLine("|cffffffffMarket|r  " .. Tradewright:FormatCopperFull(pt.value), 0.85, 0.92, 1)
		local m = pt.meta or {}
		if m.source then
			tip:AddLine(string.format("Source: %s", tostring(m.source)), 0.72, 0.8, 0.88)
		end
		if m.count and m.count > 0 then
			tip:AddLine(string.format("Samples in hour: %d", m.count), 0.72, 0.8, 0.88)
		end
		if m.min and m.max then
			tip:AddLine(
				string.format(
					"Min %s  |  Max %s",
					Tradewright:FormatCopperFull(m.min),
					Tradewright:FormatCopperFull(m.max)
				),
				0.72,
				0.8,
				0.88
			)
		end
	end
	if metric == "quantity" then
		local qtyRaw = self:GetItemQuantityHistorySeries(graphItemID, qtyFilter, rangeKey)
		series = self:ItemQuantitySeriesToGraphPoints(qtyRaw)
		yFormatter = function(v)
			return Tradewright:FormatNumberGrouped(math.floor(tonumber(v) or 0))
		end
		emptyExtra = emptyQty
		tooltipBuilder = function(tip, hit)
			local pt = hit and hit.pt or hit
			qtyTooltip(tip, pt)
		end
	elseif metric == "crafting" then
		series = self:ItemHistoryBucketsToGraphSeries(graphItemID, "crafting", rangeKey)
		yFormatter = function(v)
			return Tradewright:FormatCopperShort(tonumber(v) or 0)
		end
		if config.quantityOverlay then
			local qtyRaw = self:GetAuctionHistoryQuantitySeriesForItem(graphItemID, rangeKey)
			quantitySeries = self:ItemQuantitySeriesToGraphPoints(qtyRaw)
		end
		tooltipBuilder = function(tip, hit)
			local pt = hit and hit.pt or hit
			local kind = hit and hit.kind or "primary"
			if kind == "quantity" then
				qtyTooltip(tip, pt)
			else
				craftingTooltip(tip, pt)
			end
		end
	else
		series = self:ItemHistoryBucketsToGraphSeries(graphItemID, "market", rangeKey)
		yFormatter = function(v)
			return Tradewright:FormatCopperShort(tonumber(v) or 0)
		end
		if config.secondaryCraftingOverlay then
			secondarySeries = self:ItemHistoryBucketsToGraphSeries(graphItemID, "crafting", rangeKey)
			local flatCost = tonumber(config.currentCraftCostCopper)
			if (#secondarySeries == 0) and flatCost and flatCost > 0 and #series >= 1 then
				local t0, t1 = series[1].at, series[#series].at
				secondarySeries = {
					{ at = t0, value = flatCost, meta = { flat = true } },
					{ at = t1, value = flatCost, meta = { flat = true } },
				}
			end
		end
		if config.quantityOverlay then
			local qtyRaw = self:GetAuctionHistoryQuantitySeriesForItem(graphItemID, rangeKey)
			quantitySeries = self:ItemQuantitySeriesToGraphPoints(qtyRaw)
		end
		tooltipBuilder = function(tip, hit)
			local pt = hit and hit.pt or hit
			local kind = hit and hit.kind or "primary"
			if kind == "quantity" then
				qtyTooltip(tip, pt)
			elseif kind == "secondary" then
				craftingTooltip(tip, pt)
			else
				marketTooltip(tip, pt)
			end
		end
	end
	if graphWidget.SetRightYFormatter then
		graphWidget:SetRightYFormatter(function(v)
			return Tradewright:FormatNumberGrouped(math.floor(tonumber(v) or 0))
		end)
	end
	graphWidget:SetEmptyText(emptyExtra)
	graphWidget:SetSeries(series)
	if graphWidget.SetSecondarySeries then
		graphWidget:SetSecondarySeries(secondarySeries)
	end
	if graphWidget.SetQuantitySeries then
		graphWidget:SetQuantitySeries(quantitySeries)
	end
	graphWidget:SetYFormatter(yFormatter)
	-- The chart's shared tooltip shows every series at the hovered hour; only the labels differ.
	if graphWidget.SetSeriesLabels then
		if metric == "quantity" then
			graphWidget:SetSeriesLabels("Owned", nil, nil, nil)
		elseif metric == "crafting" then
			graphWidget:SetSeriesLabels("Craft cost", nil, "Listed", nil)
		else
			graphWidget:SetSeriesLabels("Price", "Craft cost", "Listed", "Margin")
		end
		graphWidget:SetTooltipBuilder(nil)
	else
		graphWidget:SetTooltipBuilder(tooltipBuilder)
	end
	graphWidget:Refresh()
end
