local _, ProfessionExporter = ...

-- Pure income helpers (E10): which source a change of gold belongs to, and the per-day totals it
-- is kept in. No WoW API here, so the offline tests can load this file on its own.
local IncomeLogic = {}
ProfessionExporter.IncomeLogic = IncomeLogic

IncomeLogic.SOURCES = { "vendor", "quest", "loot", "auction", "mail", "trade", "other" }
IncomeLogic.KEEP_DAYS = 400

-- Seconds within which an event explains a gold change. The event and PLAYER_MONEY can arrive in
-- either order, and trade gold lands just after the trade window closes.
IncomeLogic.EVENT_WINDOW = 2

-- One-off events, checked first: { context.at key, source }.
local MOMENTS = { { "auctionMail", "auction" }, { "quest", "quest" }, { "loot", "loot" } }
-- Windows, checked next: { context.open / context.closedAt key, source }.
local WINDOWS = { { "trade", "trade" }, { "merchant", "vendor" }, { "auctionHouse", "auction" }, { "mailbox", "mail" } }

local function near(at, changeAt)
	return at ~= nil and math.abs(changeAt - at) <= IncomeLogic.EVENT_WINDOW
end

--- Which source a gold change belongs to. `context` holds what was going on when it landed:
--- `open[window]` (open when the change landed), `closedAt[window]` and `at[moment]` (times on the
--- same clock as `changeAt`). Windows: trade, merchant, auctionHouse, mailbox; moments:
--- auctionMail (auction gold taken from a mail), quest (turned in), loot (coin looted).
function IncomeLogic.ClassifyMoneyChange(context, changeAt)
	local at, open, closedAt = context.at or {}, context.open or {}, context.closedAt or {}
	for _, moment in ipairs(MOMENTS) do
		if near(at[moment[1]], changeAt) then
			return moment[2]
		end
	end
	for _, window in ipairs(WINDOWS) do
		if open[window[1]] or near(closedAt[window[1]], changeAt) then
			return window[2]
		end
	end
	return "other"
end

local function sameDayItemEvent(event, entry, day)
	return event.kind == entry.kind and event.itemID == entry.itemID and event.characterKey == entry.characterKey
		and IncomeLogic.DayOf(event.ts) == day
end

--- Adds `entry` (kind, itemID, characterKey, ts, quantity, totalCopper) to a ledger event of the
--- same kind, item, character and day among the latest `lookBack` events, so vendoring the same
--- item all day does not crowd sales out of the ledger. Returns true when merged.
function IncomeLogic.MergeIntoDayEvent(events, entry, lookBack)
	local day = IncomeLogic.DayOf(entry.ts)
	for index = #events, math.max(1, #events - lookBack + 1), -1 do
		local event = events[index]
		if sameDayItemEvent(event, entry, day) then
			event.quantity = (tonumber(event.quantity) or 0) + entry.quantity
			event.totalCopper = (tonumber(event.totalCopper) or 0) + entry.totalCopper
			event.unitCopper = event.totalCopper / event.quantity
			return true
		end
	end
	return false
end

function IncomeLogic.DayOf(ts)
	return math.floor((tonumber(ts) or 0) / 86400)
end

--- Adds a gold change to `days[day][source]` = { gain, spend } (copper, both positive).
function IncomeLogic.AddToDay(days, day, source, delta)
	delta = tonumber(delta) or 0
	if delta == 0 then
		return
	end
	days[day] = days[day] or {}
	local entry = days[day][source] or { gain = 0, spend = 0 }
	days[day][source] = entry
	if delta > 0 then
		entry.gain = entry.gain + delta
	else
		entry.spend = entry.spend - delta
	end
end

--- Drops the days before `firstDay`.
function IncomeLogic.PruneDays(days, firstDay)
	for day in pairs(days) do
		if tonumber(day) < firstDay then
			days[day] = nil
		end
	end
end
