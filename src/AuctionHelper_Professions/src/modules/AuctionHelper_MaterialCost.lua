local _, AuctionHelper = ...

-- Material cost estimates per craft and per output item, and the economy columns (market, mat cost, margin) of inventory rows.

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
				local price = getUnitPriceCopper(bestId)
				if not price then
					return nil
				end
				total = total + qty * price
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
		local addonPrice = self.GetLatestObservedAhPrice and self:GetLatestObservedAhPrice(rid, { requireFresh = false }) or nil
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
