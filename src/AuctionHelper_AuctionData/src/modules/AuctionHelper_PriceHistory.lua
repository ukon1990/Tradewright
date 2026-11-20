local _, ProfessionExporter = ...

-- Daily price history and the usual price built from it (F40).
-- `auction.history.daily[storageKey][dayTs] = { p, lo, hi, q, n }`; `auction.history.dailyThrough` is the
-- start of the first day that has not been rolled up yet.

local DAY = 24 * 3600
local MIN_USUAL_DAYS = 5

local function now()
	return (GetServerTime and GetServerTime()) or time()
end

local function rollupFinishedDays(history, MS, from, today)
	for storageKey, hourly in pairs(history.hourly or {}) do
		for dayTs, entry in pairs(MS.RollupItemDays(hourly, from, today)) do
			history.daily[storageKey] = history.daily[storageKey] or {}
			history.daily[storageKey][dayTs] = entry
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

-- The usual price from saved daily history, or false when an item has fewer than 5 days.
local function computeUsualPrice(pe, storageKey, window)
	local auction = pe:InitAuctionDB()
	local daily = auction and auction.history.daily
	local usual = pe.MarketSignals.UsualPrice(daily and daily[storageKey], now(), window)
	if usual and usual.days >= MIN_USUAL_DAYS then
		return usual
	end
	return false
end

--- Usual price of one stored listing: `{ usual, mad, low, high, days }`, or nil with fewer than 5 days.
--- Cached until the next scan observation or settings change.
function ProfessionExporter:GetUsualPrice(storageKey)
	local state = self:GetState()
	local window = tonumber(self:GetSetting("auction.usualPriceDays", 14)) or 14
	local revision = (state.auctionDataRevision or 0) .. ":" .. window
	if state.usualPriceRevision ~= revision then
		state.usualPriceRevision, state.usualPriceCache = revision, {}
	end
	local cached = state.usualPriceCache[storageKey]
	if cached == nil then
		cached = computeUsualPrice(self, storageKey, window)
		state.usualPriceCache[storageKey] = cached
	end
	return cached or nil
end
