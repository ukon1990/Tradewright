local _, AuctionHelper = ...

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

function AuctionHelper:IsTSMLoaded()
	return type(TSM_API) == "table"
		and type(TSM_API.ToItemString) == "function"
		and type(TSM_API.GetCustomPriceValue) == "function"
end

function AuctionHelper:IsAuctionatorLoaded()
	return type(Auctionator) == "table"
		and type(Auctionator.API) == "table"
		and Auctionator.API.v1
		and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

function AuctionHelper:GetTSMItemString(itemID)
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

--- Price in copper, or nil.
function AuctionHelper:GetTSMCustomPriceCopper(customPriceStr, itemID)
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

--- Per-item auction scan estimate in copper, or nil.
function AuctionHelper:GetAuctionatorPriceCopper(itemID)
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

function AuctionHelper:GetPreferredAddonPrice(itemID, opts)
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

function AuctionHelper:GetFreshAddonCachedPrice(itemID)
	return self:GetPreferredAddonPrice(itemID, { requireFresh = true })
end

--- Market column: primary TSM string, configurable fallback TSM string, else Auctionator.
function AuctionHelper:GetMarketEstimateCopper(itemID, tsmCustomStr, fallbackTSMStr)
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
	fallbackTSMStr = fallbackTSMStr or self:GetTsmPriceStrings().fallback
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

function AuctionHelper:FormatNumberGrouped(value)
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

function AuctionHelper:FormatCopperFull(copper)
	return formatCoins(self, copper, false)
end

function AuctionHelper:FormatCopperShort(copper)
	return formatCoins(self, copper, true)
end

--- Sale rate from TSM custom price (often 0-1).
function AuctionHelper:FormatSaleRateDisplay(value)
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

function AuctionHelper:EstimateRecipeMatCostCopper(recipeData, getUnitPriceCopper)
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

function AuctionHelper:GetRecipeOutputQuantityForCost(recipeData)
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
function AuctionHelper:EstimateMatCostPerUnitForItem(characterData, itemID)
	if not characterData or not itemID then
		return nil
	end
	local st = self.db and self.db.settings or {}
	if st.economyShowMatCost == false then
		return nil
	end
	local tsm = self:GetTsmPriceStrings()
	local function unitPrice(rid)
		local addonPrice = self.GetPreferredAddonPrice and self:GetPreferredAddonPrice(rid, { requireFresh = false }) or nil
		if addonPrice then
			return addonPrice
		end
		local c = self:GetTSMCustomPriceCopper(tsm.material, rid)
		if c then
			return c
		end
		c = self:GetTSMCustomPriceCopper(tsm.fallback, rid)
		if c then
			return c
		end
		c = self:GetTSMCustomPriceCopper(tsm.market, rid)
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
function AuctionHelper:EstimateBestMatCostPerUnitAmongSelection(db, itemID, characterSelection, perCharacterRoleMaps)
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
function AuctionHelper:ApplyEconomyToAggregatedInventoryRow(row, characterSelection, mergedRoleMap, perCharacterRoleMaps)
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
function AuctionHelper:ApplyEconomyToInventoryRow(row, characterData, roleMap)
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
	local tsm = self:GetTsmPriceStrings()
	local mkt, src = self:GetMarketEstimateCopper(itemID, tsm.market)
	row.marketCopper = mkt
	row.marketSource = src

	if st.economyShowSaleRate ~= false and self:IsTSMLoaded() then
		if tsm.saleRate ~= "" then
			local v = self:GetTSMCustomPriceCopper(tsm.saleRate, itemID)
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
