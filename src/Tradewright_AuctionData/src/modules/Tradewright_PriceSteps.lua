local _, Tradewright = ...

-- Cheapest price steps of each item, kept from a full scan and refreshed by a search for one commodity.
-- `auction.priceSteps[itemID] = { t = seenAt, l = { price1, qty1, price2, qty2, … } }`, cheapest first.
-- Full scans store one entry per item ID, so the steps are keyed the same way.

local MAX_STEPS = 8
local DAY = 24 * 3600

--- Fold one auction row of a full scan into its item's aggregate, and remember its price level.
--- Called as a plain function: `aggregateRow(aggregate, itemID, count, buyoutPrice)`.
function Tradewright.AggregateAuctionRow(aggregate, itemID, count, buyoutPrice)
	Tradewright.AuctionLogic.AggregateClassicAuctionRow(aggregate, itemID, count, buyoutPrice)
	local bucket = itemID and aggregate[itemID]
	local buyout = tonumber(buyoutPrice)
	if not bucket or not buyout or buyout <= 0 then
		return aggregate
	end
	local quantity = math.max(1, tonumber(count) or 1)
	bucket.levels = Tradewright.MarketSignals.AddPriceStep(bucket.levels or {}, buyout / quantity, quantity, MAX_STEPS)
	return aggregate
end

--- Cheapest price levels of a commodity from the rows of a search for it: `rows` is a list of
--- `{ unitPrice, quantity }` as the auction house reports them. nil when no row is priced.
function Tradewright:PriceLevelsFromSearchRows(rows)
	local levels
	for _, row in ipairs(rows) do
		local unitPrice = tonumber(row.unitPrice)
		if unitPrice and unitPrice > 0 then
			levels = self.MarketSignals.AddPriceStep(levels or {}, unitPrice, math.max(1, tonumber(row.quantity) or 1), MAX_STEPS)
		end
	end
	return levels
end

--- Keep an item's cheapest price levels (from MarketSignals.AddPriceStep) as its price steps, or
--- drop its steps when there are none or the setting is off.
function Tradewright:SavePriceSteps(itemID, levels, seenAt)
	local pe = self
	local auction = pe:InitAuctionDB()
	auction.priceSteps = auction.priceSteps or {}
	if not levels or not pe:GetSetting("auction.keepPriceSteps", true) then
		auction.priceSteps[itemID] = nil
		return
	end
	auction.priceSteps[itemID] = { t = seenAt, l = pe.MarketSignals.BuildPriceSteps(levels) }
end

--- Save one item's full-scan aggregate: its snapshot and hourly history, its item history point and
--- its cheapest price steps.
function Tradewright:PersistDumpAggregate(itemID, aggregate, dump, seenAt)
	local sourceLabel = tostring(dump.sourceLabel or (dump.classic and "classic_full" or "replicate_full"))
	self:PersistAuctionDumpObservation({
		itemID = itemID,
		isCommodity = false,
		itemKey = tostring(itemID),
		minBuyout = tonumber(aggregate.minBuyout),
		marketLow = tonumber(aggregate.marketLow),
		marketHigh = tonumber(aggregate.marketHigh),
		sampleSize = tonumber(aggregate.sampleSize) or 1,
		listingCount = tonumber(aggregate.listingCount),
		source = sourceLabel,
		seenAt = seenAt,
	})
	local weightedQty = tonumber(aggregate.weightedQty) or 0
	if weightedQty > 0 then
		self:RecordItemHistoryObservation(itemID, "market", tonumber(aggregate.weightedSum) / weightedQty, sourceLabel, seenAt)
	end
	self:SavePriceSteps(itemID, aggregate.levels, seenAt)
end

--- Price steps of an item from the last full scan: `steps, seenAt`, or nil when none are kept.
function Tradewright:GetPriceSteps(itemID)
	local auction = self:InitAuctionDB()
	local entry = auction and auction.priceSteps and auction.priceSteps[tonumber(itemID)]
	if not entry then
		return nil
	end
	return entry.l, entry.t
end

--- Drop price steps older than the hourly history is kept. Runs at load.
function Tradewright:TrimPriceSteps()
	local auction = self:InitAuctionDB()
	if not (auction and auction.priceSteps) then
		return
	end
	local keepDays = tonumber(self:GetSetting("auction.historyRetentionDays", 30)) or 30
	local cutoff = Tradewright:Now() - keepDays * DAY
	for itemID, entry in pairs(auction.priceSteps) do
		if (tonumber(entry.t) or 0) < cutoff then
			auction.priceSteps[itemID] = nil
		end
	end
end
