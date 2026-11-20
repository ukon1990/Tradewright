local _, ProfessionExporter = ...

local CALLER_ID = "AuctionHelper"
local MONEY_COLORS = {
	negative = "ffe36361",
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
		local nextText, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
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

local COIN_ICONS = {
	gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t",
	silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t",
	copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t",
}

-- "12[g] 40[s]": a number then its coin icon, zero parts dropped. `short` drops copper from 100g and
-- silver from 10,000g so a price fits an 86px column. Negative amounts lead with a red minus.
local function formatCoins(self, copper, short)
	local n = tonumber(copper)
	if copper == nil or copper ~= copper or not n then
		return "-"
	end
	local total = math.floor(math.abs(n) + 0.5)
	local gold = math.floor(total / 10000)
	local silver = math.floor((total % 10000) / 100)
	local bronze = total % 100
	if short then
		if gold >= 100 then
			bronze = 0
		end
		if gold >= 10000 then
			silver = 0
		end
	end
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = self:FormatNumberGrouped(gold) .. COIN_ICONS.gold
	end
	if silver > 0 then
		parts[#parts + 1] = tostring(silver) .. COIN_ICONS.silver
	end
	if bronze > 0 or #parts == 0 then
		parts[#parts + 1] = tostring(bronze) .. COIN_ICONS.copper
	end
	local text = table.concat(parts, " ")
	if n < 0 and total > 0 then
		return colorText(MONEY_COLORS.negative, "-") .. text
	end
	return text
end

function ProfessionExporter:FormatCopperFull(copper)
	return formatCoins(self, copper, false)
end

function ProfessionExporter:FormatCopperShort(copper)
	return formatCoins(self, copper, true)
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

-- Tooltip colours: labels muted on the left, values white on the right, the addon name in gold.
local TIP_LABEL = { 0.60, 0.63, 0.67 }
local TIP_VALUE = { 0.95, 0.94, 0.92 }

local function addPair(tooltip, label, value)
	tooltip:AddDoubleLine(label, value, TIP_LABEL[1], TIP_LABEL[2], TIP_LABEL[3], TIP_VALUE[1], TIP_VALUE[2], TIP_VALUE[3])
end

local TIP_SUCCESS = { 0.40, 0.73, 0.42 }
local TIP_DANGER = { 0.89, 0.39, 0.38 }
local TIP_WARNING = { 0.95, 0.65, 0.30 }
local TIP_INFO = { 0.39, 0.71, 0.96 }

local function addToned(tooltip, label, value, tone)
	tone = tone or TIP_VALUE
	tooltip:AddDoubleLine(label, value, TIP_LABEL[1], TIP_LABEL[2], TIP_LABEL[3], tone[1], tone[2], tone[3])
end

local function ageText(seconds)
	seconds = math.max(0, tonumber(seconds) or 0)
	if seconds < 3600 then
		return string.format("%d min ago", math.max(1, math.floor(seconds / 60)))
	end
	if seconds < 2 * 86400 then
		return string.format("%d h ago", math.floor(seconds / 3600))
	end
	return string.format("%d days ago", math.floor(seconds / 86400))
end

local function percentText(value)
	return string.format("%s%.0f%%", value >= 0 and "+" or "", value)
end

--- What a gold maker needs about an item, from every source the addon has. All fields may be nil.
function ProfessionExporter:BuildItemGoldSummary(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	local summary = self.GetItemEconomySummary and self:GetItemEconomySummary(itemID, {}) or {}
	local cachedPrice, _, cachedSeenAt
	if self.GetFreshAddonCachedPrice then
		cachedPrice, _, cachedSeenAt = self:GetFreshAddonCachedPrice(itemID)
	end
	local nativePrice, _, nativeSeenAt
	if self.GetNativeAhPrice then
		nativePrice, _, nativeSeenAt = self:GetNativeAhPrice(itemID)
	end
	local out = {}
	if cachedPrice and cachedPrice > 0 then
		out.price, out.priceAt = cachedPrice, tonumber(cachedSeenAt)
	elseif nativePrice and nativePrice > 0 then
		out.price, out.priceAt = nativePrice, tonumber(nativeSeenAt)
	elseif tonumber(summary.lastPrice) and summary.lastPrice > 0 then
		out.price, out.priceAt = summary.lastPrice, tonumber(summary.lastSeenAt)
	end
	if not out.price and self.GetMarketEstimateCopper then
		out.estimate = self:GetMarketEstimateCopper(itemID, nil, nil)
	end
	local freshness = (tonumber(self:GetSetting("auction.priceFreshnessMinutes", 15)) or 15) * 60
	out.priceAge = out.priceAt and (time() - out.priceAt) or nil
	out.priceStale = out.priceAge ~= nil and out.priceAge > math.max(freshness, 6 * 3600)

	local snap = summary.snapshot or {}
	out.listed = tonumber(snap.sampleSize)
	out.listings = tonumber(snap.listingCount)

	if self.GetItemHistorySeries then
		local points = self:GetItemHistorySeries(itemID, "market", "7d")
		local total, count = 0, 0
		for _, p in ipairs(points) do
			local v = tonumber(p.avg or p.last)
			if v and v > 0 then
				total, count = total + v, count + 1
				local low, high = tonumber(p.min) or v, tonumber(p.max) or v
				out.low = out.low and math.min(out.low, low) or low
				out.high = out.high and math.max(out.high, high) or high
			end
		end
		if count >= 2 then
			out.average = total / count
			if out.price then
				out.trend = (out.price - out.average) / out.average * 100
			end
		end
	end

	local craft = self.GetItemHistoryStats and self:GetItemHistoryStats(itemID, "crafting", "30d") or {}
	out.craftCost = tonumber(craft.average) or tonumber(craft.latest)
	local unitPrice = out.price or out.estimate
	if out.craftCost and out.craftCost > 0 and unitPrice then
		local cut = self.GetCraftsAhCutFraction and self:GetCraftsAhCutFraction() or 0.05
		out.profit = unitPrice * (1 - cut) - out.craftCost
		out.margin = out.profit / out.craftCost * 100
	end

	if self.IsTSMLoaded and self:IsTSMLoaded() then
		local srString = self:GetSetting("integrations.economyTSMSaleRateString", "DBRegionSaleRate")
		out.saleRate = self:GetTSMCustomPriceCopper(srString, itemID)
	end
	out.avgSale = tonumber(summary.avgSale)
	out.avgBuy = tonumber(summary.avgBuy)

	if self.GetItemCountByLocation then
		out.bags, out.bank, out.warband, out.owned = self:GetItemCountByLocation(itemID)
	end
	return out
end

-- The AuctionHelper block on item tooltips: price and how fresh it is, how it compares to the past
-- week, how much is listed, craft profit, what you own, and a one-line verdict. Shift adds detail.
function ProfessionExporter:AppendPricingToItemTooltip(tooltip, itemID)
	itemID = tonumber(itemID)
	if not tooltip or not itemID or itemID <= 0 or tooltipHasProfessionExporterSection(tooltip) then
		return false
	end
	local g = self:BuildItemGoldSummary(itemID)
	if not g or not (g.price or g.estimate or g.craftCost or g.avgSale) then
		return false
	end
	local shift = IsShiftKeyDown and IsShiftKeyDown()
	tooltip:AddLine(" ")
	tooltip:AddLine("AuctionHelper", 1, 0.82, 0)

	if g.price then
		addPair(tooltip, "Auction price", self:FormatCopperFull(g.price))
		if g.priceAge then
			addToned(tooltip, "Seen", ageText(g.priceAge), g.priceStale and TIP_WARNING or nil)
		end
	elseif g.estimate then
		addPair(tooltip, "Estimate", self:FormatCopperFull(g.estimate))
	end
	if g.average then
		local tone = g.trend and (g.trend >= 10 and TIP_SUCCESS or g.trend <= -10 and TIP_INFO) or nil
		addToned(tooltip, "7-day average", self:FormatCopperShort(g.average) .. (g.trend and ("  " .. percentText(g.trend)) or ""), tone)
		if g.low and g.high and g.high > g.low then
			addPair(tooltip, "7-day range", self:FormatCopperShort(g.low) .. " – " .. self:FormatCopperShort(g.high))
		end
	end
	if g.listed and g.listed > 0 then
		local listed = self:FormatNumberGrouped(g.listed)
		if g.listings and g.listings > 0 then
			listed = listed .. " in " .. self:FormatNumberGrouped(g.listings) .. " auctions"
		end
		addPair(tooltip, "Listed", listed)
	end
	if g.saleRate then
		addPair(tooltip, "Sale rate", self:FormatSaleRateDisplay(g.saleRate))
	end
	if g.craftCost then
		addPair(tooltip, "Craft cost", self:FormatCopperFull(g.craftCost))
		if g.profit then
			addToned(tooltip, "Profit after cut", (g.profit >= 0 and "+" or "") .. self:FormatCopperFull(g.profit) .. string.format("  %s", percentText(g.margin)),
				g.profit >= 0 and TIP_SUCCESS or TIP_DANGER)
		end
	end
	local owned = tonumber(g.owned) or 0
	local unit = g.price or g.estimate
	if owned > 0 then
		addPair(tooltip, "You own", self:FormatNumberGrouped(owned) .. (unit and ("  ·  worth " .. self:FormatCopperShort(unit * owned)) or ""))
	end

	-- One-line verdict, most useful first.
	local verdict, tone
	if g.priceStale then
		verdict, tone = "Price is old. Scan at the auction house to refresh it.", TIP_WARNING
	elseif g.trend and g.trend <= -15 then
		verdict, tone = "Well below its usual price: a good time to buy.", TIP_INFO
	elseif g.trend and g.trend >= 15 then
		verdict, tone = "Well above its usual price: a good time to sell.", TIP_SUCCESS
	elseif g.profit and g.margin and g.margin >= 10 then
		verdict, tone = "Crafting it is profitable.", TIP_SUCCESS
	elseif g.profit and g.profit < 0 then
		verdict, tone = "Costs more to craft than it sells for.", TIP_DANGER
	end
	if verdict then
		tooltip:AddLine(verdict, tone[1], tone[2], tone[3], true)
	end

	if shift then
		if owned > 0 then
			local where = string.format("%s bags · %s bank", self:FormatNumberGrouped(g.bags or 0), self:FormatNumberGrouped(g.bank or 0))
			if (tonumber(g.warband) or 0) > 0 then
				where = where .. " · " .. self:FormatNumberGrouped(g.warband) .. " warband"
			end
			addPair(tooltip, "Where", where)
		end
		if g.avgSale and g.avgSale > 0 then
			addPair(tooltip, "Your average sale", self:FormatCopperFull(g.avgSale))
		end
		if g.avgBuy and g.avgBuy > 0 then
			addPair(tooltip, "Your average buy", self:FormatCopperFull(g.avgBuy))
		end
	elseif owned > 0 or g.avgSale or g.avgBuy then
		tooltip:AddLine("Shift: where you keep it and your own sales", TIP_LABEL[1], TIP_LABEL[2], TIP_LABEL[3])
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
