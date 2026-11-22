-- Which items the refresh queue should look up: shown crafts, prioritized auto-scan targets and account inventory.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local FL = Tradewright.ForeverLogic
local shared = Tradewright.AuctionShared
local normalizeItemID = shared.normalizeItemID
local shallowCopy = shared.shallowCopy

function Tradewright:BuildVisibleCraftsTabAuctionTargets()
	local ui = self.ui or nil
	local rows = ui and ui.craftsTable and ui.craftsTable.GetVisibleRows and ui.craftsTable:GetVisibleRows() or nil
	if type(rows) ~= "table" or #rows == 0 then
		rows = ui and ui.craftsWorkingRows or nil
	end
	if type(rows) ~= "table" then
		return {}
	end
	local targets = {}
	local seen = {}
	local function addTarget(itemID, itemKeyFields)
		local id = normalizeItemID(itemID)
		if not id then
			return
		end
		local fields = self:NormalizeAuctionItemKeyFields(itemKeyFields)
		local key = FL.SerializeItemKey(fields, id)
		if seen[key] then
			return
		end
		seen[key] = true
		targets[#targets + 1] = {
			itemID = id,
			itemKeyFields = fields,
		}
	end
	for _, row in ipairs(rows) do
		addTarget(row and row.outputItemID, row and (row.itemKeyFields or row.auctionItemKey) or nil)
		local bestCharacterKey = row and row.bestCharacterKey or nil
		local eval = row and row.perChar and bestCharacterKey and row.perChar[bestCharacterKey] or nil
		for _, slot in ipairs(eval and eval.reagentPlan or {}) do
			addTarget(slot and slot.itemID, nil)
		end
	end
	return targets
end

function Tradewright:QueueVisibleCraftsTabAuctionRefresh(force)
	if not self:CanStartFullAuctionSideActions(false) then
		return 0
	end
	local ui = self.ui or {}
	local targets = self:BuildVisibleCraftsTabAuctionTargets()
	if #targets == 0 then
		return 0
	end
	local signatureParts = {}
	for _, target in ipairs(targets) do
		signatureParts[#signatureParts + 1] = FL.SerializeItemKey(target.itemKeyFields, normalizeItemID(target.itemID))
	end
	local signature = table.concat(signatureParts, ",")
	if force ~= true and ui.craftsVisibleAuctionTargetsSignature == signature then
		return 0
	end
	ui.craftsVisibleAuctionTargetsSignature = signature

	local freshnessWindowSeconds = self:GetAuctionPriceFreshnessWindowSeconds()
	local currentTs = Tradewright:Now()
	local filtered = {}
	for _, target in ipairs(targets) do
		local itemID = normalizeItemID(target.itemID)
		local fields = self:NormalizeAuctionItemKeyFields(target.itemKeyFields)
		if itemID and (force == true or (not self:HasAuctionTargetBeenSearchedThisSession(itemID, fields) and self:IsItemAuctionScanStale(itemID, freshnessWindowSeconds, currentTs))) then
			filtered[#filtered + 1] = {
				itemID = itemID,
				itemKeyFields = fields,
			}
		end
	end
	if #filtered == 0 then
		return 0
	end
	local state = self:GetState()
		state.auctionPendingPriceScanMode = "crafts"
	state.auctionInvalidateCraftsAfterRefresh = true
	self:QueueAuctionScanTargets(filtered, { skipSessionSearched = true })
	return #filtered
end

function Tradewright:BuildPrioritizedAuctionAutoScanTargets(opts)
	opts = type(opts) == "table" and opts or {}
	self:InitDB()
	local currentCharacterKey = tostring(self:GetCharacterKey() or "")
	local includeVisibleBags = opts.includeVisibleBags ~= false
	local includeCrafts = opts.includeCrafts ~= false
	local includeAccountInventory = opts.includeAccountInventory ~= false
	local includeSessionSearched = opts.includeSessionSearched == true
	local requireStaleNonVisible = opts.requireStaleNonVisible == true
	local freshnessWindowSeconds = tonumber(opts.freshnessWindowSeconds) or self:GetAuctionPriceFreshnessWindowSeconds()
	local currentTs = Tradewright:Now()
	local targets = {}
	local seen = {}
	local function addTarget(target, _sourceKind)
		if type(target) ~= "table" then
			return
		end
		local itemID = normalizeItemID(target.itemID)
		if not itemID then
			return
		end
		local fields = self:NormalizeAuctionItemKeyFields(target.itemKeyFields or target.auctionItemKey)
		local key = FL.SerializeItemKey(fields, itemID)
		if seen[key] then
			return
		end
		if includeSessionSearched ~= true and self:HasAuctionTargetBeenSearchedThisSession(itemID, fields) then
			return
		end
		if requireStaleNonVisible == true then
			if not self:IsItemAuctionScanStale(itemID, freshnessWindowSeconds, currentTs) then
				return
			end
		end
		seen[key] = true
		targets[#targets + 1] = {
			itemID = itemID,
			itemKeyFields = fields,
		}
	end

	if includeVisibleBags then
		for _, itemID in ipairs(self:BuildAuctionVisibleItemIDs() or {}) do
			addTarget({ itemID = itemID }, "visible")
		end
	end

	if includeCrafts and self.BuildCraftEconomyAuctionTargets then
		for _, t in ipairs(self:BuildCraftEconomyAuctionTargets({ characterKey = currentCharacterKey })) do
			addTarget(t, "craft")
		end
		local otherCharacterKeys = {}
		for rawCharacterKey in pairs(self.db.characters or {}) do
			local characterKey = tostring(rawCharacterKey)
			if characterKey ~= "" and characterKey ~= currentCharacterKey then
				otherCharacterKeys[#otherCharacterKeys + 1] = characterKey
			end
		end
		table.sort(otherCharacterKeys)
		for _, characterKey in ipairs(otherCharacterKeys) do
			for _, t in ipairs(self:BuildCraftEconomyAuctionTargets({ characterKey = characterKey })) do
				addTarget(t, "craft")
			end
		end
	end

	if includeAccountInventory then
		for _, t in ipairs(self:BuildAccountTradableInventoryAuctionTargets()) do
			addTarget(t, "account")
		end
	end

	return targets
end

--- Unique AH queue targets from saved snapshots: any item with stock on any character, tradable by static bind type.
function Tradewright:BuildAccountTradableInventoryAuctionTargets()
	self:InitDB()
	local seenQty = {}
	for _, characterData in pairs(self.db.characters or {}) do
		local inv = characterData.inventorySnapshot
		if inv and type(inv.items) == "table" then
			for itemKey, entry in pairs(inv.items) do
				local id = tonumber(itemKey)
				if id and (tonumber(entry.total) or 0) > 0 then
					seenQty[id] = (seenQty[id] or 0) + (tonumber(entry.total) or 0)
				end
			end
		end
	end
	local targets = {}
	for id in pairs(seenQty) do
		if self.IsItemLikelyTradeableOnAuctionByStaticInfo and self:IsItemLikelyTradeableOnAuctionByStaticInfo(id) then
			targets[#targets + 1] = { itemID = id, itemKeyFields = nil }
		end
	end
	table.sort(targets, function(a, b)
		return (tonumber(a.itemID) or 0) < (tonumber(b.itemID) or 0)
	end)
	return targets
end

--- opts.crafts / opts.accountInventory: queue AH lookups (deduped). Crafts refresh invalidates craft caches when opts.crafts.
function Tradewright:QueueAuctionEconomyScan(opts)
	opts = type(opts) == "table" and opts or {}
	if self:GetSetting("auction.enabled", true) == false then
		self:PrintMessage(L["Auction data is switched off."])
		return
	end
	local ah = _G.AuctionHouseFrame
	if not ah or not ah.IsShown or not ah:IsShown() then
		self:PrintMessage(L["Open the auction house first."])
		return
	end
	if not self:CanStartFullAuctionSideActions(true) then
		return
	end
	local state = self:GetState()
	if state.auctionRefreshRunning then
		self:PrintMessage(L["A price check is already running. Wait for it to finish."])
		return
	end
	local wantCrafts = opts.crafts == true
	local wantInv = opts.accountInventory == true
	if not wantCrafts and not wantInv then
		return
	end
	local merged = self:BuildPrioritizedAuctionAutoScanTargets({
		includeVisibleBags = false,
		includeCrafts = wantCrafts,
		includeAccountInventory = wantInv,
		includeSessionSearched = false,
		requireStaleNonVisible = false,
	})
	if #merged == 0 then
		if wantCrafts and not wantInv then
			self:PrintMessage(L["Every craft price is already checked this visit. If recipes are missing, scan your professions first."])
		elseif wantInv and not wantCrafts then
			self:PrintMessage(L["Every price of your items is already checked this visit."])
		else
			self:PrintMessage(L["Every price is already checked this visit."])
		end
		return
	end
	if wantCrafts and wantInv then
		state.auctionPendingPriceScanMode = "mixed"
	elseif wantInv then
		state.auctionPendingPriceScanMode = "account_inv"
	else
		state.auctionPendingPriceScanMode = "crafts"
	end
	state.auctionInvalidateCraftsAfterRefresh = wantCrafts == true
	state.auctionRefreshQueue = {}
	state.auctionRefreshQueueOrderCounter = 0
	self:QueueAuctionScanTargets(merged, { skipSessionSearched = true })
	self:PrintMessage(string.format(L["Checking %d prices. Keep the auction house open until it ends."], #merged))
	self:RefreshAuctionHousePanel()
end

function Tradewright:QueueCraftEconomyAuctionRefresh(opts)
	opts = type(opts) == "table" and opts or {}
	opts.crafts = true
	opts.accountInventory = false
	self:QueueAuctionEconomyScan(opts)
end

function Tradewright:StartAuctionRoiEnrichment(itemIDs)
	if not self:CanStartFullAuctionSideActions(false) then
		return
	end
	local state = self:GetState()
	local shareMainProgress = state.auctionRefreshRunning ~= true
	if state.auctionRoiRunning then
		return
	end
	state.auctionRoiQueue = {}
	for _, itemID in ipairs(itemIDs or {}) do
		local id = normalizeItemID(itemID)
		if id then
			state.auctionRoiQueue[#state.auctionRoiQueue + 1] = id
		end
	end
	if #state.auctionRoiQueue == 0 then
		return
	end
	if shareMainProgress then
		state.auctionScanMode = "roi"
		state.auctionScanTotal = #state.auctionRoiQueue
		state.auctionScanDone = 0
	end
	state.auctionRoiCache = state.auctionRoiCache or {}
	state.auctionRoiRunning = true
	local i = 1
	local throttleMs = math.max(20, tonumber(self:GetSetting("auction.visibleRefreshThrottleMs", 150)) or 150)
	local delay = throttleMs / 1000
	local function step()
		local itemID = state.auctionRoiQueue[i]
		if not itemID then
			state.auctionRoiRunning = false
			if shareMainProgress and not state.auctionRefreshRunning then
				state.auctionScanMode = "idle"
				state.auctionScanTotal = 0
				state.auctionScanDone = 0
				state.auctionActiveItemID = nil
			end
			self:MaybeStartDeferredAuctionBulk()
			self:RefreshAuctionHousePanel()
			return
		end
		state.auctionActiveItemID = itemID
		local roi = self:EstimateCraftROIForItem(itemID)
		state.auctionRoiCache[itemID] = roi
		local panelRows = state.auctionPanelRows or {}
		for _, row in ipairs(panelRows) do
			if tonumber(row.itemID) == tonumber(itemID) then
				row.potentialROI = roi and roi.potentialROI or nil
				row.recipeName = roi and roi.recipeName or nil
				row.qualityIndex = row.qualityIndex or (roi and roi.qualityIndex or nil)
				break
			end
		end
		if shareMainProgress then
			state.auctionScanDone = i
		end
		if i % 2 == 0 then
			self:RefreshAuctionHousePanel()
		end
		i = i + 1
		C_Timer.After(delay, step)
	end
	step()
end

function Tradewright:BuildAuctionVisibleItemIDs()
	local bagState = self:GetAuctionOwnedBagState(false)
	return shallowCopy(bagState and bagState.orderedItemIDs or {})
end
