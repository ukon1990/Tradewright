local addonName, ProfessionExporter = ...

local CALLER_ID = "AuctionHelper"
local MONEY_COLORS = {
	gold = "ffffd100",
	silver = "ffe6e8fa",
	copper = "ffc8602c",
	negative = "ffff6b6b",
}

local function colorText(hex, text)
	return string.format("|c%s%s|r", hex, tostring(text or ""))
end

local function groupDigits(numberText)
	local sign = ""
	local text = tostring(numberText or "0")
	if string.sub(text, 1, 1) == "-" then
		sign = "-"
		text = string.sub(text, 2)
	end
	local out = text
	while true do
		local nextText, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1 %2")
		out = nextText
		if count == 0 then
			break
		end
	end
	return sign .. out
end

function ProfessionExporter:IsTSMLoaded()
	return type(TSM_API) == "table"
		and type(TSM_API.ToItemString) == "function"
		and type(TSM_API.GetCustomPriceValue) == "function"
end

function ProfessionExporter:IsAuctionatorLoaded()
	return type(Auctionator) == "table"
		and type(Auctionator.API) == "table"
		and Auctionator.API.v1
		and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

function ProfessionExporter:GetTSMItemString(itemID)
	if not self:IsTSMLoaded() or not itemID then
		return nil
	end
	local ok, itemString = pcall(TSM_API.ToItemString, "item:" .. tostring(itemID))
	if ok and itemString and itemString ~= "" then
		return itemString
	end
	ok, itemString = pcall(TSM_API.ToItemString, itemID)
	if ok and itemString and itemString ~= "" then
		return itemString
	end
	return nil
end

--- @return number|nil copper
function ProfessionExporter:GetTSMCustomPriceCopper(customPriceStr, itemID)
	if not customPriceStr or customPriceStr == "" or not itemID then
		return nil
	end
	if not self:IsTSMLoaded() then
		return nil
	end
	local itemString = self:GetTSMItemString(itemID)
	if not itemString then
		return nil
	end
	local ok, value, err = pcall(TSM_API.GetCustomPriceValue, customPriceStr, itemString)
	if not ok or err or value == nil then
		return nil
	end
	local n = tonumber(value)
	if not n or n ~= n then
		return nil
	end
	return n
end

--- @return number|nil copper (per item auction scan estimate)
function ProfessionExporter:GetAuctionatorPriceCopper(itemID)
	if not itemID or not self:IsAuctionatorLoaded() then
		return nil
	end
	local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, CALLER_ID, itemID)
	if not ok or not price then
		return nil
	end
	local n = tonumber(price)
	if not n or n < 0 then
		return nil
	end
	return n
end

function ProfessionExporter:GetConfiguredFallbackTSMString()
	return tostring(self:GetSetting("integrations.economyTSMFallbackString", "DBMinBuyout"))
end

function ProfessionExporter:GetPreferredAddonPrice(itemID, opts)
	opts = type(opts) == "table" and opts or {}
	itemID = tonumber(itemID)
	if not itemID then
		return nil, nil, nil, nil
	end

	if not self.GetItemEconomySummary then
		return nil, nil, nil, nil
	end
	local summary = self:GetItemEconomySummary(itemID, {})
	if not summary then
		return nil, nil, nil, nil
	end
	if opts.requireFresh == true and summary.freshnessState ~= "fresh" then
		return nil, nil, nil, nil
	end

	local bestPrice, bestSource, bestSeenAt, bestQuantity = nil, nil, nil, nil
	local nativePrice, nativeSource, nativeSeenAt, nativeQuantity = nil, nil, nil, nil
	if self.GetNativeAhPrice then
		nativePrice, nativeSource, nativeSeenAt, nativeQuantity = self:GetNativeAhPrice(itemID)
	end
	if nativePrice and nativePrice > 0 and nativeSeenAt then
		bestPrice = nativePrice
		bestSource = nativeSource or "native"
		bestSeenAt = nativeSeenAt
		bestQuantity = tonumber(nativeQuantity)
	end

	local snapPrice = tonumber(summary.lastPrice)
	local snapSeenAt = tonumber(summary.lastSeenAt)
	if snapPrice and snapPrice > 0 then
		local snap = summary.snapshot
		local snapSource = (snap and snap.source and tostring(snap.source) ~= "") and tostring(snap.source) or "snapshot"
		local snapQuantity = tonumber(snap and (snap.sampleSize or snap.quantity))
		if snapSeenAt and ((not bestSeenAt) or snapSeenAt > bestSeenAt) then
			bestPrice = snapPrice
			bestSource = snapSource
			bestSeenAt = snapSeenAt
			bestQuantity = snapQuantity
		elseif not bestPrice then
			bestPrice = snapPrice
			bestSource = snapSource
			bestSeenAt = snapSeenAt
			bestQuantity = snapQuantity
		end
	end

	return bestPrice, bestSource, bestSeenAt, bestQuantity
end

function ProfessionExporter:GetFreshAddonCachedPrice(itemID)
	return self:GetPreferredAddonPrice(itemID, { requireFresh = true })
end

--- Market column: primary TSM string, configurable fallback TSM string, else Auctionator.
function ProfessionExporter:GetMarketEstimateCopper(itemID, tsmCustomStr, fallbackTSMStr)
	local st = self.db and self.db.settings or {}
	if st.economyShowColumns == false then
		return nil, nil
	end
	local cachedPrice, cachedSource = self:GetPreferredAddonPrice(itemID, { requireFresh = false })
	if cachedPrice and cachedPrice > 0 then
		return cachedPrice, "cache:" .. tostring(cachedSource or "addon")
	end
	if tsmCustomStr and tsmCustomStr ~= "" then
		local c = self:GetTSMCustomPriceCopper(tsmCustomStr, itemID)
		if c then
			return c, "TSM"
		end
	end
	fallbackTSMStr = fallbackTSMStr or self:GetConfiguredFallbackTSMString()
	if fallbackTSMStr and fallbackTSMStr ~= "" and fallbackTSMStr ~= tsmCustomStr then
		local c = self:GetTSMCustomPriceCopper(fallbackTSMStr, itemID)
		if c then
			return c, "TSM fallback"
		end
	end
	if st.economyUseAuctionatorFallback ~= false then
		local a = self:GetAuctionatorPriceCopper(itemID)
		if a then
			return a, "Auc"
		end
	end
	return nil, nil
end

function ProfessionExporter:FormatNumberGrouped(value)
	if value == nil or value ~= value then
		return "-"
	end
	local n = tonumber(value)
	if not n then
		return tostring(value)
	end
	local rounded = math.floor(math.abs(n) + 0.5)
	local text = groupDigits(tostring(rounded))
	if n < 0 then
		return "-" .. text
	end
	return text
end

function ProfessionExporter:FormatCopperFull(copper)
	if copper == nil or copper ~= copper then
		return "-"
	end
	local n = tonumber(copper)
	if not n then
		return "-"
	end
	local sign = n < 0 and "-" or ""
	local total = math.floor(math.abs(n) + 0.5)
	local gold = math.floor(total / 10000)
	local silver = math.floor((total % 10000) / 100)
	local bronze = total % 100
	local parts = {}

	if gold > 0 then
		parts[#parts + 1] = colorText(MONEY_COLORS.gold, self:FormatNumberGrouped(gold) .. "g")
	end
	if silver > 0 or gold > 0 then
		parts[#parts + 1] = colorText(MONEY_COLORS.silver, tostring(silver) .. "s")
	end
	parts[#parts + 1] = colorText(MONEY_COLORS.copper, tostring(bronze) .. "c")

	local text = table.concat(parts, " ")
	if sign ~= "" then
		return colorText(MONEY_COLORS.negative, sign) .. text
	end
	return text
end

function ProfessionExporter:FormatCopperShort(copper)
	if copper == nil or copper ~= copper then
		return "-"
	end
	return self:FormatCopperFull(copper)
end

local function formatTooltipTimestamp(ts)
	ts = tonumber(ts)
	if not ts or ts <= 0 then
		return nil
	end
	if date then
		return date("%Y-%m-%d %H:%M", ts)
	end
	return tostring(ts)
end

local function tooltipHasProfessionExporterSection(tooltip)
	if not tooltip or not tooltip.GetName then
		return false
	end
	local name = tooltip:GetName()
	if not name or name == "" then
		return false
	end
	for i = 1, tooltip:NumLines() or 0 do
		local left = _G[name .. "TextLeft" .. tostring(i)]
		local text = left and left.GetText and left:GetText() or nil
		if text == "AuctionHelper" then
			return true
		end
	end
	return false
end

local function appendShiftTooltipTotalLine(self, tooltip, label, unitPrice, quantity, colorR, colorG, colorB)
	unitPrice = tonumber(unitPrice)
	quantity = math.max(0, tonumber(quantity) or 0)
	if not tooltip or not unitPrice or unitPrice <= 0 or quantity <= 0 then
		return
	end
	tooltip:AddLine(
		string.format("%s x%s: %s", label, self:FormatNumberGrouped(quantity), self:FormatCopperShort(unitPrice * quantity)),
		colorR or 0.78, colorG or 0.86, colorB or 0.96,
		true
	)
end

function ProfessionExporter:AppendPricingToItemTooltip(tooltip, itemID)
	itemID = tonumber(itemID)
	if not tooltip or not itemID or itemID <= 0 or tooltipHasProfessionExporterSection(tooltip) then
		return false
	end

	local summary = self.GetItemEconomySummary and self:GetItemEconomySummary(itemID, {}) or nil
	local nativePrice, nativeSource, nativeSeenAt = nil, nil, nil
	if self.GetNativeAhPrice then
		nativePrice, nativeSource, nativeSeenAt = self:GetNativeAhPrice(itemID)
	end
	local cachedPrice, cachedSource, cachedSeenAt = nil, nil, nil
	if self.GetFreshAddonCachedPrice then
		cachedPrice, cachedSource, cachedSeenAt = self:GetFreshAddonCachedPrice(itemID)
	end
	local marketEstimate, marketSource = nil, nil
	if self.GetMarketEstimateCopper then
		marketEstimate, marketSource = self:GetMarketEstimateCopper(itemID, nil, nil)
	end
	local craftStats = self.GetItemHistoryStats and self:GetItemHistoryStats(itemID, "crafting", "30d") or {}
	local lastObservedPrice = summary and tonumber(summary.lastPrice) or nil
	local lastObservedAt = summary and tonumber(summary.lastSeenAt) or nil
	local avgSale = summary and tonumber(summary.avgSale) or nil
	local avgBuy = summary and tonumber(summary.avgBuy) or nil
	local craftAvg = craftStats and tonumber(craftStats.average) or nil
	local craftLatest = craftStats and tonumber(craftStats.latest) or nil
	local bags, bank, warband, totalOwned = 0, 0, 0, 0
	if self.GetItemCountByLocation then
		bags, bank, warband, totalOwned = self:GetItemCountByLocation(itemID)
	end

	local hasAnyData = (cachedPrice and cachedPrice > 0)
		or (nativePrice and nativePrice > 0)
		or (lastObservedPrice and lastObservedPrice > 0)
		or (marketEstimate and marketEstimate > 0)
		or (avgSale and avgSale > 0)
		or (avgBuy and avgBuy > 0)
		or (craftAvg and craftAvg > 0)
		or (craftLatest and craftLatest > 0)
	if not hasAnyData then
		return false
	end

	tooltip:AddLine(" ")
	tooltip:AddLine("AuctionHelper", 0.30, 1.00, 0.60)

	if cachedPrice and cachedPrice > 0 then
		local line = string.format("AH: %s", self:FormatCopperShort(cachedPrice))
		if cachedSource and cachedSource ~= "" then
			line = string.format("%s (%s)", line, tostring(cachedSource))
		end
		tooltip:AddLine(line, 0.82, 0.88, 0.96, true)
		local seenLabel = formatTooltipTimestamp(cachedSeenAt)
		if seenLabel then
			tooltip:AddLine("Seen: " .. seenLabel, 0.68, 0.74, 0.82, true)
		end
	elseif lastObservedPrice and lastObservedPrice > 0 then
		local source = summary and summary.snapshot and summary.snapshot.source or "snapshot"
		tooltip:AddLine(
			string.format("Last observed: %s (%s)", self:FormatCopperShort(lastObservedPrice), tostring(source or "snapshot")),
			0.82, 0.88, 0.96, true
		)
		local seenLabel = formatTooltipTimestamp(lastObservedAt)
		if seenLabel then
			tooltip:AddLine("Seen: " .. seenLabel, 0.68, 0.74, 0.82, true)
		end
	end

	if nativePrice and nativePrice > 0 and (not cachedPrice or tonumber(nativeSeenAt) ~= tonumber(cachedSeenAt)) then
		local line = string.format("Native AH: %s", self:FormatCopperShort(nativePrice))
		if nativeSource and nativeSource ~= "" then
			line = string.format("%s (%s)", line, tostring(nativeSource))
		end
		tooltip:AddLine(line, 0.75, 0.90, 0.78, true)
	end

	if marketEstimate and marketEstimate > 0 and (not cachedPrice or tonumber(marketEstimate) ~= tonumber(cachedPrice)) then
		tooltip:AddLine(
			string.format("Estimate: %s (%s)", self:FormatCopperShort(marketEstimate), tostring(marketSource or "market")),
			0.82, 0.88, 0.96, true
		)
	end
	if avgSale and avgSale > 0 then
		tooltip:AddLine("Avg sale: " .. self:FormatCopperShort(avgSale), 0.82, 0.88, 0.96, true)
	end
	if avgBuy and avgBuy > 0 then
		tooltip:AddLine("Avg buy: " .. self:FormatCopperShort(avgBuy), 0.82, 0.88, 0.96, true)
	end
	if craftAvg and craftAvg > 0 then
		tooltip:AddLine("Craft avg (30d): " .. self:FormatCopperShort(craftAvg), 0.82, 0.88, 0.96, true)
	elseif craftLatest and craftLatest > 0 then
		tooltip:AddLine("Craft latest: " .. self:FormatCopperShort(craftLatest), 0.82, 0.88, 0.96, true)
	end
	if IsShiftKeyDown and IsShiftKeyDown() and (tonumber(totalOwned) or 0) > 0 then
		local qtyLabel = string.format(
			"Held now: %s total (%s bags, %s bank, %s warband)",
			self:FormatNumberGrouped(totalOwned),
			self:FormatNumberGrouped(bags),
			self:FormatNumberGrouped(bank),
			self:FormatNumberGrouped(warband)
		)
		tooltip:AddLine(qtyLabel, 0.95, 0.85, 0.55, true)
		appendShiftTooltipTotalLine(self, tooltip, "AH total", cachedPrice or nativePrice or lastObservedPrice or marketEstimate, totalOwned, 0.82, 0.88, 0.96)
		appendShiftTooltipTotalLine(self, tooltip, "Avg sale total", avgSale, totalOwned, 0.82, 0.88, 0.96)
		appendShiftTooltipTotalLine(self, tooltip, "Avg buy total", avgBuy, totalOwned, 0.82, 0.88, 0.96)
		appendShiftTooltipTotalLine(self, tooltip, "Craft total", craftAvg or craftLatest, totalOwned, 0.82, 0.88, 0.96)
	end
	return true
end

function ProfessionExporter:AppendPricingToTooltipFromData(tooltip, data)
	if not tooltip then
		return
	end
	local getItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	local itemID = nil
	if type(data) == "table" then
		itemID = tonumber(data.id or data.itemID)
		if (not itemID or itemID <= 0) and data.hyperlink and getItemInfoInstant then
			itemID = select(1, getItemInfoInstant(data.hyperlink))
		end
	end
	if (not itemID or itemID <= 0) and tooltip.GetItem then
		local _, itemLink = tooltip:GetItem()
		if itemLink and getItemInfoInstant then
			itemID = select(1, getItemInfoInstant(itemLink))
		end
	end
	self:AppendPricingToItemTooltip(tooltip, itemID)
end

function ProfessionExporter:InitItemTooltipPricingHooks()
	if self._itemTooltipPricingHooksInit then
		return
	end
	self._itemTooltipPricingHooksInit = true

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			ProfessionExporter:AppendPricingToTooltipFromData(tooltip, data)
		end)
		return
	end

	local function hookTooltip(tooltip)
		if tooltip and tooltip.HookScript and not tooltip._professionExporterPricingHooked then
			tooltip:HookScript("OnTooltipSetItem", function(tip)
				ProfessionExporter:AppendPricingToTooltipFromData(tip, nil)
			end)
			tooltip._professionExporterPricingHooked = true
		end
	end

	hookTooltip(GameTooltip)
	hookTooltip(ItemRefTooltip)
	hookTooltip(ShoppingTooltip1)
	hookTooltip(ShoppingTooltip2)
	hookTooltip(ItemRefShoppingTooltip1)
	hookTooltip(ItemRefShoppingTooltip2)
	hookTooltip(EmbeddedItemTooltip)
end

--- Sale rate from TSM custom price (often 0-1).
function ProfessionExporter:FormatSaleRateDisplay(value)
	if value == nil or value ~= value then
		return "-"
	end
	local n = tonumber(value)
	if not n then
		return "-"
	end
	if n >= 0 and n <= 1 then
		return string.format("%.0f%%", n * 100)
	end
	if n > 1 and n <= 100 then
		return string.format("%.0f%%", n)
	end
	return self:FormatCopperShort(n)
end

function ProfessionExporter:EstimateRecipeMatCostCopper(recipeData, getUnitPriceCopper)
	if not recipeData or type(getUnitPriceCopper) ~= "function" then
		return nil
	end
	local slots = self:RecipeDataSlots(recipeData)
	if type(slots) ~= "table" then
		return nil
	end
	local total = 0
	for _, slot in ipairs(slots) do
		local qty = tonumber(slot.quantityRequired) or 0
		if qty > 0 and type(slot.reagents) == "table" and #slot.reagents > 0 then
			local bestId, bestQual = nil, -1
			for _, reagent in ipairs(slot.reagents) do
				if reagent.itemID then
					local q = tonumber(reagent.quality) or 0
					if q >= bestQual then
						bestQual = q
						bestId = reagent.itemID
					end
				end
			end
			if bestId then
				local p = getUnitPriceCopper(bestId)
				if not p then
					return nil
				end
				total = total + qty * p
			end
		end
	end
	return total
end

function ProfessionExporter:GetRecipeOutputQuantityForCost(recipeData)
	local outs = recipeData and recipeData.outputs
	if not outs then
		return 1
	end
	local mn = tonumber(outs.quantityMin)
	local mx = tonumber(outs.quantityMax)
	if mn and mn > 0 then
		return mn
	end
	if mx and mx > 0 then
		return mx
	end
	return 1
end

--- Per-unit material cost estimate for a craft output item (copper), using TSM/Auc unit prices for reagents.
function ProfessionExporter:EstimateMatCostPerUnitForItem(characterData, itemID)
	if not characterData or not itemID then
		return nil
	end
	local st = self.db and self.db.settings or {}
	if st.economyShowMatCost == false then
		return nil
	end
	local marketStr = st.economyTSMMarketString or "dbmarket"
	local fallbackStr = st.economyTSMFallbackString or "DBMinBuyout"
	local matStr = st.economyTSMMatString or "Crafting"
	local function unitPrice(rid)
		local addonPrice = self.GetPreferredAddonPrice and self:GetPreferredAddonPrice(rid, { requireFresh = false }) or nil
		if addonPrice then
			return addonPrice
		end
		local c = self:GetTSMCustomPriceCopper(matStr, rid)
		if c then
			return c
		end
		c = self:GetTSMCustomPriceCopper(fallbackStr, rid)
		if c then
			return c
		end
		c = self:GetTSMCustomPriceCopper(marketStr, rid)
		if c then
			return c
		end
		return self:GetAuctionatorPriceCopper(rid)
	end

	local _, bestCostOrRecipe = self:FindBestRecipeForOutputItem(characterData, itemID, function(recipeData)
		local matTotal = self:EstimateRecipeMatCostCopper(recipeData, unitPrice)
		if not matTotal then
			return math.huge
		end
		local outQty = self:GetRecipeOutputQuantityForCost(recipeData)
		return matTotal / math.max(1, outQty)
	end)
	if type(bestCostOrRecipe) == "number" and bestCostOrRecipe < math.huge then
		return bestCostOrRecipe
	end
	return nil
end

--- Lowest per-unit mat cost among selected characters that can craft itemID (learned output on their scan).
--- perCharacterRoleMaps optional: characterKey -> BuildItemRoleMap result (avoids O(rows*chars) full rescans per refresh).
function ProfessionExporter:EstimateBestMatCostPerUnitAmongSelection(db, itemID, characterSelection, perCharacterRoleMaps)
	if not db or not itemID or type(db.characters) ~= "table" then
		return nil
	end
	local best = nil
	for characterKey, characterData in pairs(db.characters) do
		if self:IsFilterSelectionEmpty(characterSelection) or characterSelection[characterKey] == true then
			local rm = perCharacterRoleMaps and perCharacterRoleMaps[characterKey] or self:BuildItemRoleMap(characterData)
			local re = rm[itemID]
			if re and re.output then
				local c = self:EstimateMatCostPerUnitForItem(characterData, itemID)
				if c and (not best or c < best) then
					best = c
				end
			end
		end
	end
	return best
end

--- Market/sale rate like ApplyEconomyToInventoryRow; mat cost = best among selected crafters when merged role has output.
function ProfessionExporter:ApplyEconomyToAggregatedInventoryRow(row, characterSelection, mergedRoleMap, perCharacterRoleMaps)
	self:ApplyEconomyToInventoryRow(row, nil, nil)
	if not row or not row.itemID then
		return
	end
	local st = self.db and self.db.settings or {}
	if st.economyShowColumns == false or st.economyShowMatCost == false then
		return
	end
	local re = mergedRoleMap and mergedRoleMap[row.itemID]
	if re and re.output then
		row.matCopperPerUnit = self:EstimateBestMatCostPerUnitAmongSelection(self.db, row.itemID, characterSelection, perCharacterRoleMaps)
		if row.marketCopper and row.matCopperPerUnit then
			row.marginCopperPerUnit = row.marketCopper - row.matCopperPerUnit
		end
	end
end

--- Fills row table with economy fields: marketCopper, marketSource, matCopperPerUnit, marginCopperPerUnit, saleRateDisplay
--- roleMap optional: from BuildItemRoleMap(characterData) to avoid rebuilding per row.
function ProfessionExporter:ApplyEconomyToInventoryRow(row, characterData, roleMap)
	if not row then
		return
	end
	row.marketCopper = nil
	row.marketSource = nil
	row.matCopperPerUnit = nil
	row.marginCopperPerUnit = nil
	row.saleRateDisplay = nil
	row.saleRateValue = nil

	local st = self.db and self.db.settings or {}
	if st.economyShowColumns == false then
		return
	end

	local itemID = row.itemID
	local tsmMarket = st.economyTSMMarketString or "dbmarket"
	local mkt, src = self:GetMarketEstimateCopper(itemID, tsmMarket)
	row.marketCopper = mkt
	row.marketSource = src

	if st.economyShowSaleRate ~= false and self:IsTSMLoaded() then
		local srStr = st.economyTSMSaleRateString or "DBRegionSaleRate"
		if srStr ~= "" then
			local v = self:GetTSMCustomPriceCopper(srStr, itemID)
			row.saleRateValue = v
			row.saleRateDisplay = self:FormatSaleRateDisplay(v)
		end
	end

	if st.economyShowMatCost ~= false and characterData then
		roleMap = roleMap or self:BuildItemRoleMap(characterData)
		local re = roleMap[itemID]
		if re and re.output then
			row.matCopperPerUnit = self:EstimateMatCostPerUnitForItem(characterData, itemID)
			if row.marketCopper and row.matCopperPerUnit then
				row.marginCopperPerUnit = row.marketCopper - row.matCopperPerUnit
			end
		end
	end
end
