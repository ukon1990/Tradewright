local _, AuctionHelper = ...

local MarketLogic = AuctionHelper.MarketLogic

-- Market insights for the gold dashboard: deals, movers and supply per scanned item.
-- Built in chunks after each new scan so large snapshots never stall a frame.

local CHUNK = 150
local DAY = 24 * 3600

function AuctionHelper:GetGoldDashboardOptions()
	return {
		dealThreshold = tonumber(self:GetSetting("gold.dealThreshold", 0.3)) or 0.3,
		moverThreshold = tonumber(self:GetSetting("gold.moverThreshold", 0.15)) or 0.15,
		externalReference = self:GetSetting("gold.reference", "best") ~= "own",
		usualDays = tonumber(self:GetSetting("auction.usualPriceDays", 14)) or 14,
		minHours = 3,
		ahCut = 0.05,
	}
end

-- TSM market value only: Auctionator and our own snapshot hold the current price, not a baseline.
local function externalReference(pe, itemID)
	if not (pe.IsTSMLoaded and pe:IsTSMLoaded() and pe.GetTSMCustomPriceCopper) then
		return nil
	end
	local value = pe:GetTSMCustomPriceCopper(pe:GetTsmPriceStrings().market, itemID)
	return value and value > 0 and value or nil
end

-- What an item's price is compared with. Movers use `price` (the usual price once an item has enough
-- daily history, else the 7-day average); deals use `ref`: TSM when allowed, else that same price.
local function resolveBaseline(pe, opts, itemID, storageKey, summary)
	local usual = pe:GetUsualPrice(storageKey)
	local base = { price = summary.avg7d, low = summary.low7d, high = summary.high7d, refSource = "7-day avg" }
	if usual then
		base = { price = usual.usual, low = usual.low, high = usual.high, days = usual.days, refSource = "daily middle" }
	end
	base.ref = base.price
	local external = opts.externalReference and externalReference(pe, itemID)
	if external then
		base.ref, base.refSource = external, "TSM"
	end
	if not base.ref then
		base.refSource = nil
	end
	return base
end

local function collectKeys(auction)
	local keys = {}
	for _, root in ipairs({ auction.snapshot and auction.snapshot.commodities, auction.snapshot and auction.snapshot.items }) do
		for storageKey, entry in pairs(root or {}) do
			keys[#keys + 1] = { storageKey = storageKey, entry = entry }
		end
	end
	return keys
end

local function evaluateKey(pe, FL, auction, item, opts, ts, byItemID)
	local itemID = tonumber(FL.ParseItemIDFromStorageKey(item.storageKey))
	local snap = MarketLogic.NormalizeMarketSnapshotFields(item.entry)
	if not itemID or not snap or not snap.price or snap.price <= 0 then
		return
	end
	local summary = MarketLogic.SummarizeHourlyHistory(auction.history and auction.history.hourly and auction.history.hourly[item.storageKey], ts)
	local previous = byItemID[itemID]
	-- Several variants (item level, suffix) share an item ID: keep the one with the most history.
	if previous and (previous.hours or 0) >= summary.hours then
		return
	end
	local base = resolveBaseline(pe, opts, itemID, item.storageKey, summary)
	local ref, refSource = base.ref, base.refSource
	local classified = { hours = summary.hours, avg7d = base.price, qtyNow = summary.qtyNow, qtyAvg7d = summary.qtyAvg7d }
	local flags = MarketLogic.ClassifyMarketItem(snap.price, classified, ref, {
		refExternal = refSource ~= "7-day avg",
		dealThreshold = opts.dealThreshold,
		moverThreshold = opts.moverThreshold,
		minHours = opts.minHours,
		ahCut = opts.ahCut,
	})
	byItemID[itemID] = {
		_rowIdentity = tostring(itemID),
		itemID = itemID,
		storageKey = item.storageKey,
		price = snap.price,
		listed = snap.listingCount or 0,
		quantity = snap.sampleSize or 0,
		seenAt = snap.seenAt,
		hours = summary.hours,
		avg7d = base.price,
		low7d = base.low,
		high7d = base.high,
		usualDays = base.days,
		qtyNow = summary.qtyNow,
		qtyAvg7d = summary.qtyAvg7d,
		ref = ref,
		refSource = refSource,
		discount = flags.discount,
		gain = flags.gain,
		isDeal = flags.isDeal,
		change = flags.change,
		isRiser = flags.isRiser,
		isFaller = flags.isFaller,
		supplyChange = flags.supplyChange,
	}
end

local function finish(byItemID, ts)
	local all, deals, risers, fallers, supply = {}, {}, {}, {}, {}
	local lastSeen
	for _, row in pairs(byItemID) do
		all[#all + 1] = row
		if row.isDeal and row.seenAt and row.seenAt >= ts - 7 * DAY then
			deals[#deals + 1] = row
		end
		if row.isRiser then
			risers[#risers + 1] = row
		elseif row.isFaller then
			fallers[#fallers + 1] = row
		end
		if row.supplyChange and row.supplyChange <= -0.25 then
			supply[#supply + 1] = row
		end
		if row.seenAt and (not lastSeen or row.seenAt > lastSeen) then
			lastSeen = row.seenAt
		end
	end
	return {
		byItemID = byItemID,
		itemCount = #all,
		lastSeenAt = lastSeen,
		builtAt = ts,
		deals = MarketLogic.TopN(deals, 50, "gain"),
		dealCount = #deals,
		risers = MarketLogic.TopN(risers, 50, "change"),
		fallers = MarketLogic.TopN(fallers, 50, "change", true),
		supply = MarketLogic.TopN(supply, 50, "supplyChange", true),
	}
end

local function insightsRevision(state, opts)
	return table.concat({ state.auctionDataRevision or 0, opts.dealThreshold, opts.moverThreshold,
		tostring(opts.externalReference), opts.usualDays }, ":")
end

--- The loading line of tables waiting for the insights. A function without arguments, so a table's
--- SetLoading can read it again while the build moves on.
function AuctionHelper.MarketInsightsLoadingNote()
	local progress = AuctionHelper:GetState().marketInsightsProgress or 0
	return string.format("Reading auction scans · %d%%", math.floor(progress * 100))
end

-- Every caller that asked while a build ran is told when it ends, not only the one that started it:
-- each of them may be showing a loading state that only its callback clears.
local function notifyWaiting(state, insights)
	local waiting = state.marketInsightsWaiting or {}
	state.marketInsightsWaiting = nil
	for _, onDone in ipairs(waiting) do
		onDone(insights)
	end
end

-- Evaluates every scanned item, CHUNK per frame so a large database does not freeze the game, then
-- stores the insights for `revision` and tells the waiting callers.
local function buildInsights(pe, state, opts, revision)
	local FL = pe.ForeverLogic
	local auction = pe:InitAuctionDB()
	local keys = collectKeys(auction)
	local byItemID, index, ts = {}, 1, AuctionHelper:Now()
	local function step()
		local last = math.min(#keys, index + CHUNK - 1)
		local ok, err = pcall(function()
			for i = index, last do
				evaluateKey(pe, FL, auction, keys[i], opts, ts, byItemID)
			end
		end)
		if not ok then
			-- Not told: their refresh would start the failing build again at once, in a loop.
			state.marketInsightsBuilding = nil
			state.marketInsightsWaiting = nil
			geterrorhandler()(err)
			return
		end
		index = last + 1
		state.marketInsightsProgress = #keys > 0 and (index - 1) / #keys or 1
		if index <= #keys then
			C_Timer.After(0, step)
			return
		end
		state.marketInsights = finish(byItemID, ts)
		state.marketInsightsRevision = revision
		state.marketInsightsBuilding = nil
		notifyWaiting(state, state.marketInsights)
	end
	C_Timer.After(0, step)
end

--- Cached insights, or nil while the first build runs. Starts a rebuild when scan data or settings changed;
--- `onDone(insights)` fires when that rebuild finishes. Progress is `state.marketInsightsProgress` (0..1).
function AuctionHelper:GetMarketInsights(onDone)
	local state = self:GetState()
	local opts = self:GetGoldDashboardOptions()
	local revision = insightsRevision(state, opts)
	local cached = state.marketInsights
	if state.marketInsightsBuilding and onDone then
		table.insert(state.marketInsightsWaiting, onDone)
	end
	if (cached and state.marketInsightsRevision == revision) or state.marketInsightsBuilding then
		return cached
	end
	-- Scans bump the revision per observation; rebuild at most every 30 seconds meanwhile,
	-- unless a single live search asked for a rebuild.
	if cached and not state.marketInsightsForceRebuild and AuctionHelper:Now() - (cached.builtAt or 0) < 30 then
		return cached
	end
	state.marketInsightsForceRebuild = nil
	state.marketInsightsBuilding = revision
	state.marketInsightsProgress = 0
	state.marketInsightsWaiting = { onDone }
	buildInsights(self, state, opts, revision)
	return cached
end

--- Item IDs used as reagents by any stored recipe on any character.
function AuctionHelper:GetRecipeMaterialSet()
	local state = self:GetState()
	local revision = tostring(self.db and self.db.aggregate and self.db.aggregate.updatedAt or 0)
	if state.recipeMaterialSet and state.recipeMaterialSetRevision == revision then
		return state.recipeMaterialSet
	end
	local set = {}
	for _, charData in pairs(self.db and self.db.characters or {}) do
		for _, profession in pairs(charData.professions or {}) do
			for _, recipeData in pairs(profession.recipes or {}) do
				for _, slot in ipairs(self:RecipeDataSlots(recipeData) or {}) do
					for _, reagent in ipairs(slot.reagents or {}) do
						if reagent.itemID then
							set[tonumber(reagent.itemID)] = true
						end
					end
				end
			end
		end
	end
	state.recipeMaterialSet, state.recipeMaterialSetRevision = set, revision
	return set
end
