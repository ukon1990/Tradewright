local addonName, ProfessionExporter = ...

-- Market insights for the gold dashboard: deals, movers and supply per scanned item.
-- Built in chunks after each new scan so large snapshots never stall a frame.

local CHUNK = 150
local DAY = 24 * 3600

local function now()
	return (GetServerTime and GetServerTime()) or time()
end

function ProfessionExporter:GetGoldDashboardOptions()
	return {
		dealThreshold = tonumber(self:GetSetting("gold.dealThreshold", 0.3)) or 0.3,
		moverThreshold = tonumber(self:GetSetting("gold.moverThreshold", 0.15)) or 0.15,
		externalReference = self:GetSetting("gold.reference", "best") ~= "own",
		minHours = 3,
		ahCut = 0.05,
	}
end

-- TSM market value only: Auctionator and our own snapshot hold the current price, not a baseline.
local function externalReference(pe, itemID)
	if not (pe.IsTSMLoaded and pe:IsTSMLoaded() and pe.GetTSMCustomPriceCopper) then
		return nil
	end
	local value = pe:GetTSMCustomPriceCopper(tostring(pe:GetSetting("integrations.economyTSMMarketString", "dbmarket")), itemID)
	return value and value > 0 and value or nil
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
	local snap = FL.NormalizeMarketSnapshotFields(item.entry)
	if not itemID or not snap or not snap.price or snap.price <= 0 then
		return
	end
	local summary = FL.SummarizeHourlyHistory(auction.history and auction.history.hourly and auction.history.hourly[item.storageKey], ts)
	local previous = byItemID[itemID]
	-- Several variants (item level, suffix) share an item ID: keep the one with the most history.
	if previous and (previous.hours or 0) >= summary.hours then
		return
	end
	local ref, refSource = nil, nil
	if opts.externalReference then
		ref = externalReference(pe, itemID)
		refSource = ref and "TSM" or nil
	end
	if not ref and summary.avg7d then
		ref, refSource = summary.avg7d, "7-day avg"
	end
	local flags = FL.ClassifyMarketItem(snap.price, summary, ref, {
		refExternal = refSource == "TSM",
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
		avg7d = summary.avg7d,
		low7d = summary.low7d,
		high7d = summary.high7d,
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

local function finish(pe, byItemID, ts)
	local FL = pe.ForeverLogic
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
		deals = FL.TopN(deals, 50, "gain"),
		dealCount = #deals,
		risers = FL.TopN(risers, 50, "change"),
		fallers = FL.TopN(fallers, 50, "change", true),
		supply = FL.TopN(supply, 50, "supplyChange", true),
	}
end

--- Cached insights, or nil while the first build runs. Starts a rebuild when scan data or settings changed;
--- `onDone(insights)` fires when that rebuild finishes. Progress is `state.marketInsightsProgress` (0..1).
function ProfessionExporter:GetMarketInsights(onDone)
	local state = self:GetState()
	local opts = self:GetGoldDashboardOptions()
	local revision = string.format("%d:%s:%s:%s", state.auctionDataRevision or 0, opts.dealThreshold, opts.moverThreshold, tostring(opts.externalReference))
	local cached = state.marketInsights
	if (cached and state.marketInsightsRevision == revision) or state.marketInsightsBuilding then
		return cached
	end
	-- Scans bump the revision per observation; rebuild at most every 30 seconds meanwhile.
	if cached and now() - (cached.builtAt or 0) < 30 then
		return cached
	end

	local FL = self.ForeverLogic
	local auction = self:InitAuctionDB()
	local keys = collectKeys(auction)
	local byItemID, index, ts = {}, 1, now()
	state.marketInsightsBuilding = revision
	state.marketInsightsProgress = 0

	local function step()
		local last = math.min(#keys, index + CHUNK - 1)
		local ok, err = pcall(function()
			for i = index, last do
				evaluateKey(self, FL, auction, keys[i], opts, ts, byItemID)
			end
		end)
		if not ok then
			state.marketInsightsBuilding = nil
			geterrorhandler()(err)
			return
		end
		index = last + 1
		state.marketInsightsProgress = #keys > 0 and (index - 1) / #keys or 1
		if index <= #keys then
			C_Timer.After(0, step)
			return
		end
		state.marketInsights = finish(self, byItemID, ts)
		state.marketInsightsRevision = revision
		state.marketInsightsBuilding = nil
		if onDone then
			onDone(state.marketInsights)
		end
	end
	C_Timer.After(0, step)
	return cached
end

--- Item IDs used as reagents by any stored recipe on any character.
function ProfessionExporter:GetRecipeMaterialSet()
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
