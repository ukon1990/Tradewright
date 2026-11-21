local _, AuctionHelper = ...

-- Item detail data: recipe links, account totals, crafting and economy snapshots, and the analytics columns of inventory rows.

local isCharacterSelected = AuctionHelper.ItemHistory.isCharacterSelected

function AuctionHelper:GetItemRecipeRelationships(itemID, selectedCharacters)
	self:InitDB()
	itemID = tonumber(itemID)
	local relationships = {
		producedBy = {},
		usedBy = {},
	}
	if not itemID then
		return relationships
	end

	for characterKey, characterData in pairs(self.db.characters or {}) do
		if isCharacterSelected(selectedCharacters, characterKey) then
			local meta = characterData.meta or {}
			local characterLabel = (meta.name and meta.realm) and (tostring(meta.name) .. " - " .. tostring(meta.realm)) or characterKey
			for _, professionData in pairs(characterData.professions or {}) do
				for recipeID, recipeData in pairs(professionData.recipes or {}) do
					local info = self:RecipeDataInfo(recipeData) or {}
					local outputs = recipeData.outputs or {}
					local primaryItemID = self:RecipeOutputsPrimaryItemId(outputs)
					local recipeName = info.name or ("Recipe #" .. tostring(recipeID))
					if tonumber(primaryItemID) == itemID then
						relationships.producedBy[#relationships.producedBy + 1] = {
							characterKey = characterKey,
							characterLabel = characterLabel,
							professionName = professionData.professionName or "?",
							recipeID = tonumber(recipeID) or recipeID,
							recipeName = recipeName,
						}
					end
					for _, slot in ipairs(self:RecipeDataSlots(recipeData) or {}) do
						for _, reagent in ipairs(slot.reagents or {}) do
							if tonumber(reagent.itemID) == itemID then
								relationships.usedBy[#relationships.usedBy + 1] = {
									characterKey = characterKey,
									characterLabel = characterLabel,
									professionName = professionData.professionName or "?",
									recipeID = tonumber(recipeID) or recipeID,
									recipeName = recipeName,
									quantityRequired = tonumber(slot.quantityRequired) or 0,
								}
								break
							end
						end
					end
				end
			end
		end
	end

	local function byProfessionThenRecipe(left, right)
		if left.professionName == right.professionName then
			return tostring(left.recipeName) < tostring(right.recipeName)
		end
		return tostring(left.professionName) < tostring(right.professionName)
	end
	table.sort(relationships.producedBy, byProfessionThenRecipe)
	table.sort(relationships.usedBy, byProfessionThenRecipe)

	return relationships
end

function AuctionHelper:BuildInventoryItemTotals(itemID, selectedCharacters)
	self:InitDB()
	local totals = {
		bags = 0,
		bank = 0,
		warband = 0,
		total = 0,
		holders = {}, -- { { key = characterKey, count = n }, ... }, most first
	}
	for characterKey, characterData in pairs(self.db.characters or {}) do
		if isCharacterSelected(selectedCharacters, characterKey) then
			local itemEntry = characterData.inventorySnapshot
				and characterData.inventorySnapshot.items
				and characterData.inventorySnapshot.items[tostring(itemID)]
				or nil
			if itemEntry then
				totals.bags = totals.bags + (tonumber(itemEntry.bags) or 0)
				totals.bank = totals.bank + (tonumber(itemEntry.bank) or 0)
				totals.warband = totals.warband + (tonumber(itemEntry.warband) or 0)
				totals.total = totals.total + (tonumber(itemEntry.total) or 0)
				-- Bags + bank only: the warband bank is shared, so it belongs to no one character.
				local own = (tonumber(itemEntry.bags) or 0) + (tonumber(itemEntry.bank) or 0)
				if own > 0 then
					totals.holders[#totals.holders + 1] = { key = characterKey, count = own }
				end
			end
		end
	end
	table.sort(totals.holders, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.key < b.key
	end)
	return totals
end

function AuctionHelper:BuildItemCraftingSnapshot(itemID, selectedCharacters, rangeKey)
	local stats = self:GetItemHistoryStats(itemID, "crafting", rangeKey)
	local relationships = self:GetItemRecipeRelationships(itemID, selectedCharacters)
	return {
		lastCraftCost = stats.latest,
		avgCraftCost = stats.average,
		count = stats.count,
		change = stats.change,
		producedBy = relationships.producedBy,
		usedBy = relationships.usedBy,
		series = self:GetItemHistorySeries(itemID, "crafting", rangeKey),
	}
end

function AuctionHelper:BuildItemEconomySnapshot(itemID, selectedCharacters, rangeKey)
	local marketStats = self:GetItemHistoryStats(itemID, "market", rangeKey)
	local itemHistory = self.db and self.db.itemHistory and self.db.itemHistory[tostring(itemID)] or {}
	local latestMarket = itemHistory.market and itemHistory.market.latest or nil
	return {
		currentMarket = latestMarket and latestMarket.value or nil,
		currentMarketAt = latestMarket and latestMarket.at or nil,
		currentMarketSource = latestMarket and latestMarket.source or nil,
		lastObservedPrice = marketStats.latest,
		avgObservedPrice = marketStats.average,
		count = marketStats.count,
		change = marketStats.change,
		series = self:GetItemHistorySeries(itemID, "market", rangeKey),
		inventoryTotals = self:BuildInventoryItemTotals(itemID, selectedCharacters),
	}
end

function AuctionHelper:BuildItemDetailSnapshot(itemID, context)
	context = context or {}
	local selectedCharacters = context.selectedCharacters
	local rangeKey = context.rangeKey or self:GetInventoryMetricRange()
	local desc = self:ResolveItemDescriptor(itemID) or {}
	local economy = self:BuildItemEconomySnapshot(itemID, selectedCharacters, rangeKey)
	local crafting = self:BuildItemCraftingSnapshot(itemID, selectedCharacters, rangeKey)
	local rid = tonumber(itemID)
	return {
		itemID = rid,
		name = desc.name or self:GetItemDisplayName(itemID),
		icon = desc.icon,
		rankIndex = self:GetItemDisplayProfessionQualityRank(itemID, selectedCharacters, context.rankIndex),
		itemType = desc.itemType,
		itemSubType = desc.itemSubType,
		classID = desc.classID,
		subclassID = desc.subclassID,
		economy = economy,
		crafting = crafting,
		rangeKey = rangeKey,
	}
end

function AuctionHelper:EnrichInventoryRowAnalytics(row, characterData, roleMap, selectedCharacters, rangeKey, rankIndex, historyStatsMemo, perCharacterRoleMaps)
	if row.aggregatedInventory then
		self:ApplyEconomyToAggregatedInventoryRow(row, selectedCharacters, roleMap, perCharacterRoleMaps)
	else
		self:ApplyEconomyToInventoryRow(row, characterData, roleMap)
	end
	rangeKey = rangeKey or self:GetInventoryMetricRange()
	if row.marketCopper then
		self:RecordItemHistoryObservation(row.itemID, "market", row.marketCopper, row.marketSource, time())
	end
	if row.matCopperPerUnit then
		self:RecordItemHistoryObservation(row.itemID, "crafting", row.matCopperPerUnit, "Crafting", time())
	end

	local marketStats = self:GetItemHistoryStatsMemo(row.itemID, "market", rangeKey, historyStatsMemo)
	local craftStats = self:GetItemHistoryStatsMemo(row.itemID, "crafting", rangeKey, historyStatsMemo)
	local latestMarket = self.db.itemHistory
		and self.db.itemHistory[tostring(row.itemID)]
		and self.db.itemHistory[tostring(row.itemID)].market
		and self.db.itemHistory[tostring(row.itemID)].market.latest
		or nil

	row.currentAhCopper = row.marketCopper
	row.currentAhAt = latestMarket and latestMarket.at or nil
	row.currentAhSource = row.marketSource
	row.lastObservedPrice = marketStats.latest
	row.avgObservedPrice = marketStats.average
	row.lastCraftCost = craftStats.latest or row.matCopperPerUnit
	row.avgCraftCost = craftStats.average or row.matCopperPerUnit
	row.profitCopperPerUnit = row.currentAhCopper and row.avgCraftCost and (row.currentAhCopper - row.avgCraftCost) or nil
	row.profitCopperStack = row.profitCopperPerUnit and row.total and (row.profitCopperPerUnit * row.total) or nil
	row.historyPoints = marketStats.count
	row.craftingPoints = craftStats.count
	row.selectedCharacters = selectedCharacters
	row.rankIndex = self:GetItemDisplayProfessionQualityRank(row.itemID, selectedCharacters, rankIndex)
end

function AuctionHelper:OpenItemDetails(itemID, context)
	local ui = self.ui or {}
	ui.invSelectedItemID = tonumber(itemID)
	ui.invDetailsContext = context or ui.invDetailsContext or {}
	local tab = ui.activeMainTab
	if tab == "inventory" and ui.inventoryPanel then
		self:SetSetting("inventory.detailsOpen", true)
		self:LayoutInventoryPanel(ui.inventoryPanel)
		self:RenderInventoryDetails(ui.invSelectedItemID)
	elseif tab == "crafts" and ui.craftsPanel then
		self:SetSetting("crafts.detailsOpen", true)
		local row = self:SelectCraftOpportunityByOutputItemID(ui.invSelectedItemID)
		ui.craftsItemDetailOnlyItemID = nil
		if row then
			ui.craftsSelectedRowKey = row.rowKey
			ui.craftsSelectedRowData = row
			self:SetSetting("crafts.selectedRowKey", row.rowKey)
		else
			ui.craftsSelectedRowKey = nil
			ui.craftsSelectedRowData = nil
			self:SetSetting("crafts.selectedRowKey", nil)
			if ui.invSelectedItemID then
				ui.craftsItemDetailOnlyItemID = ui.invSelectedItemID
			end
		end
		self:RenderCraftsDetails(row)
		self:LayoutCraftsPanel(ui.craftsPanel)
	end
end
