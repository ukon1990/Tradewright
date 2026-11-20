local _, ProfessionExporter = ...

-- Daily price history and the usual price built from it (F40).
-- `auction.history.daily[storageKey][dayTs] = { p, lo, hi, q, n }`; `auction.history.dailyThrough` is the
-- start of the first day that has not been rolled up yet.

local DAY = 24 * 3600
local MIN_USUAL_DAYS = 5

local function now()
	return (GetServerTime and GetServerTime()) or time()
end

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
function ProfessionExporter:RollupDailyAuctionHistory()
	local auction = self:InitAuctionDB()
	local MS = self.MarketSignals
	if not (auction and MS) then
		return
	end
	local history = auction.history
	history.daily = history.daily or {}
	local today = MS.DayStart(now())
	local from = tonumber(history.dailyThrough) or 0
	if from < today then
		rollupFinishedDays(history, MS, from, today)
		history.dailyThrough = today
	end
	local keepDays = math.max(7, tonumber(self:GetSetting("auction.dailyRetentionDays", 180)) or 180)
	trimDailyHistory(history.daily, today - keepDays * DAY)
end

local function dailyHistory(pe, storageKey)
	local auction = pe:InitAuctionDB()
	local daily = auction and auction.history.daily
	return daily and daily[storageKey]
end

-- The usual price from saved daily history, or false when an item has fewer than 5 days.
local function computeUsualPrice(pe, storageKey, window)
	local usual = pe.MarketSignals.UsualPrice(dailyHistory(pe, storageKey), now(), window)
	if usual and usual.days >= MIN_USUAL_DAYS then
		return usual
	end
	return false
end

local function computeSellsPerDay(pe, storageKey, window)
	return pe.MarketSignals.SellsPerDay(dailyHistory(pe, storageKey), now(), window) or false
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

--- Usual price of one stored listing: `{ usual, mad, low, high, days }`, or nil with fewer than 5 days.
function ProfessionExporter:GetUsualPrice(storageKey)
	return cachedSignal(self, "usual", storageKey, computeUsualPrice)
end

--- Estimated units sold per day of one stored listing: `{ perDay, confidence, pairs }`, or nil when the
--- scans do not say. Built from finished days, so it appears the day after two scans of an item.
function ProfessionExporter:GetSellsPerDay(storageKey)
	return cachedSignal(self, "sells", storageKey, computeSellsPerDay)
end
