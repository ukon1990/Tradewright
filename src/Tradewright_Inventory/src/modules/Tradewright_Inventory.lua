local _, Tradewright = ...

--- Collect distinct item IDs referenced by scanned profession data (reagents + outputs).
function Tradewright:CollectTrackedItemIdsFromCharacterData(characterData)
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
				add(Tradewright:RecipeOutputsPrimaryItemId(outputs))
				if type(outputs.qualityVariants) == "table" then
					for _, variant in ipairs(outputs.qualityVariants) do
						add(variant.itemID)
					end
				end
			end
			local slots = Tradewright:RecipeDataSlots(recipeData)
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
function Tradewright:GetOwnedActiveAuctionQuantityForItem(itemID)
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
	Tradewright:ForEachBagSlot(nil, function(_, _, info)
		if info and tonumber(info.itemID) == itemID then
			total = total + math.max(0, tonumber(info.stackCount or info.quantity) or 0)
		end
	end)
	return total
end

--- Bag / bank / warband split using the same pattern as CraftSim (retail C_Item.GetItemCount).
--- Forever / older clients may reject the warband flag; fall back to bags+bank only.
function Tradewright:GetItemCountByLocation(itemID)
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
		local bank, warband
		bags, bank, warband = self.MaterialLogic.ResolveLocationCounts(bags, withBank, withWarband)
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

-- The last inventory slot that holds worn gear. Retail adds profession tools and accessories after
-- the 19 gear slots. Equipped bags sit elsewhere, at slots that differ per client.
local LAST_GEAR_SLOT = 19
local LAST_PROFESSION_GEAR_SLOT = 30

-- The inventory slots of everything worn: gear, profession gear and the equipped bags (the reagent
-- bag too). The game's item count includes all of them.
local function wornSlots(pe)
	local slots = {}
	for slot = 1, pe.IS_RETAIL and LAST_PROFESSION_GEAR_SLOT or LAST_GEAR_SLOT do
		slots[#slots + 1] = slot
	end
	local slotOfBag = C_Container and C_Container.ContainerIDToInventoryID
	for bag = 1, slotOfBag and pe:GetLastBagIndex() or 0 do
		slots[#slots + 1] = slotOfBag(bag)
	end
	return slots
end

-- Copies the character has but cannot sell, by item ID: soulbound ones in the bags, soulbound ones
-- in the bank (as saved at the last bank visit) and everything worn.
local function countBoundOrWornCopies(pe)
	local counts = {}
	local function add(itemID, quantity)
		itemID = tonumber(itemID)
		if itemID then
			counts[itemID] = (counts[itemID] or 0) + (tonumber(quantity) or 1)
		end
	end
	pe:ForEachBagSlot(nil, function(_, _, info)
		if info and info.isBound then
			add(info.itemID, info.stackCount)
		end
	end)
	for _, slot in ipairs(wornSlots(pe)) do
		add(GetInventoryItemID("player", slot), 1)
	end
	for itemID, quantity in pairs(pe:GetOwnItemHoldings().boundInBank or {}) do
		add(itemID, quantity)
	end
	return counts
end

-- One item's entry in inventorySnapshot.items. `unsellable` is only counted for an item that can
-- be traded by nature: of a bind-on-pickup item every copy is bound, and that says nothing new.
local function buildSnapshotEntry(pe, itemID, boundOrWornCopies)
	local bags, bank, warband, total = pe:GetItemCountByLocation(itemID)
	local boundOrWorn = boundOrWornCopies[itemID] or 0
	local unsellable = 0
	if boundOrWorn > 0 and pe:IsItemLikelyTradeableOnAuctionByStaticInfo(itemID) then
		unsellable = math.min(boundOrWorn, total)
	end
	return { bags = bags, bank = bank, warband = warband, total = total, unsellable = unsellable }
end

function Tradewright:_UpdateInventorySnapshotImmediate(characterData)
	local ids = self:CollectTrackedItemIdsFromCharacterData(characterData)
	local boundOrWornCopies = countBoundOrWornCopies(self)
	local items = {}
	local totalQuantity = 0
	local capturedAt = time()

	for _, itemID in ipairs(ids) do
		local entry = buildSnapshotEntry(self, itemID, boundOrWornCopies)
		totalQuantity = totalQuantity + entry.total
		items[tostring(itemID)] = entry
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
	if Tradewright.OnInventorySnapshotWritten then
		Tradewright:OnInventorySnapshotWritten(characterData)
	end
end

function Tradewright:_InventorySnapshotProcessChunk()
	local state = self:GetState()
	local pending = state.invSnapshotPending
	if not pending or pending.cancelled then
		return
	end

	local ids = pending.ids
	local batch = pending.batchSize
	local endIdx = math.min(pending.idx + batch - 1, #ids)

	for i = pending.idx, endIdx do
		local itemID = ids[i]
		local entry = buildSnapshotEntry(self, itemID, pending.boundOrWornCopies)
		pending.totalQuantity = pending.totalQuantity + entry.total
		pending.items[tostring(itemID)] = entry
	end

	if endIdx >= #ids then
		local itemTypesWithStock = 0
		for _, entry in pairs(pending.items) do
			if (entry.total or 0) > 0 then
				itemTypesWithStock = itemTypesWithStock + 1
			end
		end
		pending.characterData.inventorySnapshot = {
			capturedAt = pending.capturedAt,
			itemTypesTracked = #ids,
			itemTypesWithStock = itemTypesWithStock,
			totalQuantity = pending.totalQuantity,
			items = pending.items,
		}
		if Tradewright.OnInventorySnapshotWritten then
			Tradewright:OnInventorySnapshotWritten(pending.characterData)
		end
		state.invSnapshotPending = nil
		self:BumpDataRevision()
		local cb = pending.onComplete
		if cb then
			cb()
		end
		return
	end

	pending.idx = endIdx + 1
	C_Timer.After(0, function()
		self:_InventorySnapshotProcessChunk()
	end)
end

--- Build and attach inventorySnapshot to characterData (mutates in place).
--- opts: { forceImmediate = bool, onComplete = function }
function Tradewright:UpdateInventorySnapshot(characterData, opts)
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

	state.invSnapshotPending = {
		characterData = characterData,
		ids = ids,
		idx = 1,
		batchSize = batchSize,
		items = {},
		boundOrWornCopies = countBoundOrWornCopies(self),
		totalQuantity = 0,
		capturedAt = time(),
		onComplete = opts.onComplete,
		cancelled = false,
	}
	self:_InventorySnapshotProcessChunk()
end
