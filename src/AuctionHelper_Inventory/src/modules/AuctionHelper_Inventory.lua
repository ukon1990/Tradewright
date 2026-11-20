local _, ProfessionExporter = ...

--- Collect distinct item IDs referenced by scanned profession data (reagents + outputs).
function ProfessionExporter:CollectTrackedItemIdsFromCharacterData(characterData)
	local seen = {}
	local function add(itemID)
		local id = tonumber(itemID)
		if id and id > 0 then
			seen[id] = true
		end
	end

	if not characterData or type(characterData.professions) ~= "table" then
		return {}
	end

	for _, professionData in pairs(characterData.professions) do
		for _, recipeData in pairs(professionData.recipes or {}) do
			local outputs = recipeData.outputs
			if outputs then
				add(ProfessionExporter:RecipeOutputsPrimaryItemId(outputs))
				if type(outputs.qualityVariants) == "table" then
					for _, variant in ipairs(outputs.qualityVariants) do
						add(variant.itemID)
					end
				end
			end
			local slots = ProfessionExporter:RecipeDataSlots(recipeData)
			if type(slots) == "table" then
				for _, slot in ipairs(slots) do
					if type(slot.reagents) == "table" then
						for _, reagent in ipairs(slot.reagents) do
							add(reagent.itemID)
						end
					end
				end
			end
		end
	end

	local list = {}
	for id in pairs(seen) do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

--- Sum of this item's quantity in the player's active (unsold) auctions, if AH data is loaded.
function ProfessionExporter:GetOwnedActiveAuctionQuantityForItem(itemID)
	itemID = tonumber(itemID)
	if not itemID or not C_AuctionHouse or not C_AuctionHouse.GetNumOwnedAuctions or not C_AuctionHouse.GetOwnedAuctionInfo then
		return 0
	end
	if C_AuctionHouse.HasFullOwnedAuctionResults and C_AuctionHouse.HasFullOwnedAuctionResults() == false then
		return 0
	end
	local n = C_AuctionHouse.GetNumOwnedAuctions() or 0
	local activeStatus = Enum.AuctionStatus and Enum.AuctionStatus.Active or 0
	local sum = 0
	for i = 1, n do
		local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
		if info and info.itemKey and tonumber(info.itemKey.itemID) == itemID then
			local st = info.status
			if st == nil or st == activeStatus then
				sum = sum + (tonumber(info.quantity) or 0)
			end
		end
	end
	return sum
end

--- Remove listed-auction qty from API counts (GetItemCount often still includes items up for sale).
local function subtractAuctionListedFromSplit(bags, bank, warband, listedQty)
	bags = math.max(0, tonumber(bags) or 0)
	bank = math.max(0, tonumber(bank) or 0)
	warband = math.max(0, tonumber(warband) or 0)
	listedQty = math.max(0, tonumber(listedQty) or 0)
	if listedQty <= 0 then
		return bags, bank, warband, bags + bank + warband
	end
	local rem = listedQty
	local function take(from)
		if rem <= 0 or from <= 0 then
			return from
		end
		local d = math.min(rem, from)
		rem = rem - d
		return from - d
	end
	warband = take(warband)
	bank = take(bank)
	bags = take(bags)
	return bags, bank, warband, bags + bank + warband
end

local function countItemInBagsViaContainer(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return 0
	end
	local total = 0
	for bag = 0, ProfessionExporter:GetLastBagIndex() do
		local slots = nil
		if C_Container and C_Container.GetContainerNumSlots then
			slots = C_Container.GetContainerNumSlots(bag)
		elseif GetContainerNumSlots then
			slots = GetContainerNumSlots(bag)
		end
		slots = tonumber(slots) or 0
		for slot = 1, slots do
			local count, foundID = nil, nil
			if C_Container and C_Container.GetContainerItemInfo then
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if type(info) == "table" then
					foundID = tonumber(info.itemID)
					count = tonumber(info.stackCount or info.quantity)
				end
			elseif GetContainerItemInfo then
				local _, itemCount, _, _, _, _, itemLink, _, _, itemID2 = GetContainerItemInfo(bag, slot)
				foundID = tonumber(itemID2)
				count = tonumber(itemCount)
				if not foundID and type(itemLink) == "string" then
					foundID = tonumber(itemLink:match("item:(%d+)"))
				end
			end
			if foundID == itemID then
				total = total + math.max(0, count or 0)
			end
		end
	end
	return total
end

--- Bag / bank / warband split using the same pattern as CraftSim (retail C_Item.GetItemCount).
--- Forever / older clients may reject the warband flag; fall back to bags+bank only.
function ProfessionExporter:GetItemCountByLocation(itemID)
	if not itemID then
		return 0, 0, 0, 0
	end

	if C_Item and C_Item.GetItemCount then
		local bags, withBank, withWarband
		local okBags, bagsResult = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
		if okBags then
			bags = tonumber(bagsResult) or 0
		else
			local okSimple, simpleBags = pcall(C_Item.GetItemCount, itemID, false)
			bags = (okSimple and tonumber(simpleBags)) or 0
		end
		local okBank, bankResult = pcall(C_Item.GetItemCount, itemID, true, false, true, false)
		if okBank then
			withBank = tonumber(bankResult) or bags
		else
			local okSimpleBank, simpleBank = pcall(C_Item.GetItemCount, itemID, true)
			withBank = (okSimpleBank and tonumber(simpleBank)) or bags
		end
		local okWarband, warbandResult = pcall(C_Item.GetItemCount, itemID, false, false, false, true)
		if okWarband then
			withWarband = tonumber(warbandResult) or bags
		end
		local resolve = self.ForeverLogic and self.ForeverLogic.ResolveLocationCounts
		local bank, warband
		if resolve then
			bags, bank, warband = resolve(bags, withBank, withWarband)
		else
			bank = math.max(0, withBank - bags)
			warband = withWarband and math.max(0, withWarband - bags) or 0
		end
		local listed = self:GetOwnedActiveAuctionQuantityForItem(itemID)
		bags, bank, warband = subtractAuctionListedFromSplit(bags, bank, warband, listed)
		return bags, bank, warband, bags + bank + warband
	end

	-- Container walk when C_Item is unavailable.
	local bags = countItemInBagsViaContainer(itemID)
	local total = bags
	if GetItemCount then
		local withBank = tonumber(GetItemCount(itemID, true)) or bags
		local bank = math.max(0, withBank - bags)
		local listed = self:GetOwnedActiveAuctionQuantityForItem(itemID)
		bags, bank = subtractAuctionListedFromSplit(bags, bank, 0, listed)
		return bags, bank, 0, bags + bank
	end
	local listed = self:GetOwnedActiveAuctionQuantityForItem(itemID)
	total = math.max(0, total - listed)
	return total, 0, 0, total
end

function ProfessionExporter:_UpdateInventorySnapshotImmediate(characterData)
	local ids = self:CollectTrackedItemIdsFromCharacterData(characterData)
	local items = {}
	local totalQuantity = 0
	local capturedAt = time()

	for _, itemID in ipairs(ids) do
		local bags, bank, warband, total = self:GetItemCountByLocation(itemID)
		if total > 0 then
			totalQuantity = totalQuantity + total
		end
		items[tostring(itemID)] = {
			bags = bags,
			bank = bank,
			warband = warband,
			total = total,
		}
	end

	local itemTypesWithStock = 0
	for _, entry in pairs(items) do
		if (entry.total or 0) > 0 then
			itemTypesWithStock = itemTypesWithStock + 1
		end
	end

	characterData.inventorySnapshot = {
		capturedAt = capturedAt,
		itemTypesTracked = #ids,
		itemTypesWithStock = itemTypesWithStock,
		totalQuantity = totalQuantity,
		items = items,
	}
	if ProfessionExporter.OnInventorySnapshotWritten then
		ProfessionExporter:OnInventorySnapshotWritten(characterData)
	end
end

function ProfessionExporter:_InventorySnapshotProcessChunk()
	local state = self:GetState()
	local p = state.invSnapshotPending
	if not p or p.cancelled then
		return
	end

	local ids = p.ids
	local batch = p.batchSize
	local endIdx = math.min(p.idx + batch - 1, #ids)

	for i = p.idx, endIdx do
		local itemID = ids[i]
		local bags, bank, warband, total = self:GetItemCountByLocation(itemID)
		if total > 0 then
			p.totalQuantity = p.totalQuantity + total
		end
		p.items[tostring(itemID)] = {
			bags = bags,
			bank = bank,
			warband = warband,
			total = total,
		}
	end

	if endIdx >= #ids then
		local itemTypesWithStock = 0
		for _, entry in pairs(p.items) do
			if (entry.total or 0) > 0 then
				itemTypesWithStock = itemTypesWithStock + 1
			end
		end
		p.characterData.inventorySnapshot = {
			capturedAt = p.capturedAt,
			itemTypesTracked = #ids,
			itemTypesWithStock = itemTypesWithStock,
			totalQuantity = p.totalQuantity,
			items = p.items,
		}
		if ProfessionExporter.OnInventorySnapshotWritten then
			ProfessionExporter:OnInventorySnapshotWritten(p.characterData)
		end
		state.invSnapshotPending = nil
		self:BumpDataRevision()
		local cb = p.onComplete
		if cb then
			cb()
		end
		return
	end

	p.idx = endIdx + 1
	C_Timer.After(0, function()
		self:_InventorySnapshotProcessChunk()
	end)
end

--- Build and attach inventorySnapshot to characterData (mutates in place).
--- opts: { forceImmediate = bool, onComplete = function }
function ProfessionExporter:UpdateInventorySnapshot(characterData, opts)
	if not characterData then
		if opts and opts.onComplete then
			opts.onComplete()
		end
		return
	end

	opts = opts or {}
	self:InitDB()
	local batchSize = tonumber(self:GetSetting("capture.inventorySnapshotBatchSize", 0)) or 0
	local forceImmediate = opts.forceImmediate == true or batchSize <= 0

	if forceImmediate then
		self:_UpdateInventorySnapshotImmediate(characterData)
		self:BumpDataRevision()
		if opts.onComplete then
			opts.onComplete()
		end
		return
	end

	local ids = self:CollectTrackedItemIdsFromCharacterData(characterData)
	if #ids <= batchSize then
		self:_UpdateInventorySnapshotImmediate(characterData)
		self:BumpDataRevision()
		if opts.onComplete then
			opts.onComplete()
		end
		return
	end

	local state = self:GetState()
	if state.invSnapshotPending then
		state.invSnapshotPending.cancelled = true
	end

	local capturedAt = time()
	state.invSnapshotPending = {
		characterData = characterData,
		ids = ids,
		idx = 1,
		batchSize = batchSize,
		items = {},
		totalQuantity = 0,
		capturedAt = capturedAt,
		onComplete = opts.onComplete,
		cancelled = false,
	}
	self:_InventorySnapshotProcessChunk()
end
