local _, Tradewright = ...

-- Daily price history and the usual price built from it.
-- `auction.history.daily[storageKey][dayTs] = { p, lo, hi, q, n }`; `auction.history.dailyThrough` is the
-- start of the first day that has not been rolled up yet.

local DAY = 24 * 3600
local MIN_USUAL_DAYS = 5

-- Copy each day's fields into `byDay`, keeping fields other rollups already wrote.
local function mergeDays(byDay, days)
	for dayTs, entry in pairs(days) do
		local day = byDay[dayTs] or {}
		for field, value in pairs(entry) do
			day[field] = value
		end
		byDay[dayTs] = day
	end
end

local function rollupFinishedDays(history, MS, from, today)
	for storageKey, hourly in pairs(history.hourly or {}) do
		local byDay = history.daily[storageKey] or {}
		mergeDays(byDay, MS.RollupItemDays(hourly, from, today))
		mergeDays(byDay, MS.EstimateSoldByDay(hourly, from, today))
		if next(byDay) ~= nil then
			history.daily[storageKey] = byDay
		end
	end
end

local function trimDailyHistory(daily, cutoff)
	for storageKey, byDay in pairs(daily) do
		for dayKey in pairs(byDay) do
			if (tonumber(dayKey) or 0) < cutoff then
				byDay[dayKey] = nil
			end
		end
		if next(byDay) == nil then
			daily[storageKey] = nil
		end
	end
end

--- Fold every finished day of hourly history into daily history, then drop days past their retention.
--- Runs once at load; a day is rolled up the first time the addon loads after it ended.
function Tradewright:RollupDailyAuctionHistory()
	local auction = self:InitAuctionDB()
	local MS = self.MarketSignals
	if not (auction and MS) then
		return
	end
	local history = auction.history
	history.daily = history.daily or {}
	local today = MS.DayStart(Tradewright:Now())
	local from = tonumber(history.dailyThrough) or 0
	if from < today then
		rollupFinishedDays(history, MS, from, today)
		history.dailyThrough = today
	end
	local keepDays = math.max(7, tonumber(self:GetSetting("auction.dailyRetentionDays", 180)) or 180)
	trimDailyHistory(history.daily, today - keepDays * DAY)
	self:TrimPriceSteps()
end

--- On how many different days the player has scanned prices, counted up to `limit`: the finished
--- days in daily history, plus today once a full scan ran today (today is rolled up tomorrow).
--- Walking every item's history is slow with little history, so the answer is kept until a new
--- day is rolled up or another full scan ends.
function Tradewright:GetScanDayCount(limit)
	local auction = self:InitAuctionDB()
	if not auction then
		return 0
	end
	local state = self:GetState()
	local lastFullScanAt = self:GetLastFullAuctionScanAt()
	local cacheKey = string.format("%s:%s:%s", tostring(auction.history.dailyThrough), tostring(lastFullScanAt), tostring(limit))
	if state.scanDayCountKey ~= cacheKey then
		local days = self.MarketSignals.CountHistoryDays(auction.history.daily, limit)
		if lastFullScanAt and lastFullScanAt >= self.MarketSignals.DayStart(Tradewright:Now()) then
			days = days + 1
		end
		state.scanDayCount, state.scanDayCountKey = days, cacheKey
	end
	return state.scanDayCount
end

local function dailyHistory(pe, storageKey)
	local auction = pe:InitAuctionDB()
	local daily = auction and auction.history.daily
	return daily and daily[storageKey]
end

-- The usual price from saved daily history, or false when an item has fewer than 5 days.
local function computeUsualPrice(pe, storageKey, window)
	local usual = pe.MarketSignals.UsualPrice(dailyHistory(pe, storageKey), Tradewright:Now(), window)
	if usual and usual.days >= MIN_USUAL_DAYS then
		return usual
	end
	return false
end

-- Units of one item the player sold per day over the window, from the ledger. Rebuilt at most once a minute.
local function ownSalesPerDay(pe, itemID, window)
	if not (itemID and pe.GetSalesSummary) then
		return nil
	end
	local state = pe:GetState()
	local cache = state.ownSalesPerDay
	if not cache or cache.window ~= window or Tradewright:Now() - cache.at > 60 then
		cache = { at = Tradewright:Now(), window = window, byItem = {} }
		for _, item in ipairs(pe:GetSalesSummary(window).items) do
			if tonumber(item.itemID) then
				cache.byItem[tonumber(item.itemID)] = item.units / window
			end
		end
		state.ownSalesPerDay = cache
	end
	return cache.byItem[itemID]
end

local function computeSellsPerDay(pe, storageKey, window)
	local itemID = tonumber(pe.ForeverLogic.ParseItemIDFromStorageKey(storageKey))
	local own = ownSalesPerDay(pe, itemID, window)
	return pe.MarketSignals.SellsPerDay(dailyHistory(pe, storageKey), Tradewright:Now(), window, own) or false
end

-- One cached value per stored listing and kind, dropped at the next scan observation or window change.
local function cachedSignal(pe, kind, storageKey, compute)
	local state = pe:GetState()
	local window = tonumber(pe:GetSetting("auction.usualPriceDays", 14)) or 14
	local revision = (state.auctionDataRevision or 0) .. ":" .. window
	if state.priceSignalRevision ~= revision then
		state.priceSignalRevision, state.priceSignalCache = revision, {}
	end
	local cache = state.priceSignalCache[kind] or {}
	state.priceSignalCache[kind] = cache
	if cache[storageKey] == nil then
		cache[storageKey] = compute(pe, storageKey, window)
	end
	return cache[storageKey] or nil
end

local function computeWeekdayPattern(pe, storageKey)
	return pe.WeekdayPattern.Build(dailyHistory(pe, storageKey)) or false
end

--- Weekday price pattern of one stored listing (see Tradewright_WeekdayPattern.lua), or nil when the
--- scans do not show one.
function Tradewright:GetWeekdayPattern(storageKey)
	return cachedSignal(self, "weekday", storageKey, computeWeekdayPattern)
end

--- Usual price of one stored listing: `{ usual, mad, low, high, days }`, or nil with fewer than 5 days.
function Tradewright:GetUsualPrice(storageKey)
	return cachedSignal(self, "usual", storageKey, computeUsualPrice)
end

--- The price over however many days of history an item has (fewer than 5 allowed): `{ usual, days, … }`, or nil.
--- For early estimates only; everything else uses `GetUsualPrice`.
function Tradewright:GetEarlyUsualPrice(storageKey)
	local window = tonumber(self:GetSetting("auction.usualPriceDays", 14)) or 14
	return self.MarketSignals.UsualPrice(dailyHistory(self, storageKey), Tradewright:Now(), window)
end

--- Estimated units sold per day of one stored listing: `{ perDay, confidence, pairs }`, or nil when the
--- scans do not say. Built from finished days, so it appears the day after two scans of an item.
function Tradewright:GetSellsPerDay(storageKey)
	return cachedSignal(self, "sells", storageKey, computeSellsPerDay)
end

-- The stored listing of an item with the most daily history (items can have several variants).
local function bestStorageKey(pe, itemID)
	local auction = pe:InitAuctionDB()
	local keys = auction and auction.indexes.byItemID[tostring(itemID)]
	local best, bestDays
	for storageKey in pairs(keys or {}) do
		local days = 0
		for _ in pairs(dailyHistory(pe, storageKey) or {}) do
			days = days + 1
		end
		if not best or days > bestDays then
			best, bestDays = storageKey, days
		end
	end
	return best
end

--- Usual price and sells per day for an item ID (tooltip, Inventory): `usual, sells`, either may be nil.
function Tradewright:GetItemPriceSignals(itemID)
	local storageKey = bestStorageKey(self, itemID)
	if not storageKey then
		return nil, nil
	end
	return self:GetUsualPrice(storageKey), self:GetSellsPerDay(storageKey)
end

-- 7-day average, low and high of an item's own price history.
local function sevenDayBaseline(pe, out, itemID)
	local total, count = 0, 0
	for _, p in ipairs(pe:GetItemHistorySeries(itemID, "market", "7d")) do
		local v = tonumber(p.avg or p.last)
		if v and v > 0 then
			total, count = total + v, count + 1
			out.low = math.min(out.low or v, tonumber(p.min) or v)
			out.high = math.max(out.high or v, tonumber(p.max) or v)
		end
	end
	if count >= 2 then
		out.average = total / count
	end
end

--- Fill a tooltip summary with what the price is compared with: the usual price once an item has enough daily history
-- (usualDays is then set), else the 7-day average. Also notes how many sell a day when the scans say.
function Tradewright:FillPriceBaseline(out, itemID)
	local pe = self
	local usual, sells = pe:GetItemPriceSignals(itemID)
	if usual then
		out.usualDays = usual.days
		out.average, out.low, out.high = usual.usual, usual.low, usual.high
	elseif pe.GetItemHistorySeries then
		sevenDayBaseline(pe, out, itemID)
	end
	if out.average and out.price then
		out.trend = (out.price - out.average) / out.average * 100
	end
	out.sellsPerDay = sells and sells.perDay or nil
end
