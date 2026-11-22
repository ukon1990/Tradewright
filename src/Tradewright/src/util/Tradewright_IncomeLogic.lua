local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Pure income helpers: which source a change of gold belongs to, and the per-day totals it
-- is kept in, and the sales summary of the ledger. No WoW API here, so the offline tests can load this file on its own.
local IncomeLogic = {}
Tradewright.IncomeLogic = IncomeLogic

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

--- PruneDays for every map in `byKey` ({ [key] = days }), dropping keys left empty.
function IncomeLogic.PruneAllDays(byKey, firstDay)
	for key, days in pairs(byKey) do
		IncomeLogic.PruneDays(days, firstDay)
		if next(days) == nil then
			byKey[key] = nil
		end
	end
end

-- Item chat lines -------------------------------------------------------------------------------

--- A Lua pattern for a GlobalStrings format ("You create: %sx%d." → "^You create: (.+)x(%d+)%.$").
function IncomeLogic.FormatToPattern(format)
	local pattern = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. pattern .. "$"
end

--- Reads one of the player's own item chat lines. `patterns` is a list of { pattern, kind }, the
--- "x%d" forms first. Returns kind, itemID, quantity, or nil when no pattern matches.
function IncomeLogic.ParseItemMessage(message, patterns)
	for _, entry in ipairs(patterns) do
		local link, count = message:match(entry[1])
		local itemID = link and tonumber(link:match("item:(%d+)"))
		if itemID then
			return entry[2], itemID, tonumber(count) or 1
		end
	end
	return nil
end

-- Where sold items came from -------------------------------------------------------------------

local ORIGIN_OF_KIND = { craft = "crafted", loot = "farmed", buy = "resold" }

--- Adds `quantity` of `kind` (craft or loot) to `acquired[itemID][day][kind]`.
function IncomeLogic.AddAcquired(acquired, itemID, day, kind, quantity)
	acquired[itemID] = acquired[itemID] or {}
	local days = acquired[itemID]
	days[day] = days[day] or {}
	days[day][kind] = (days[day][kind] or 0) + quantity
end

-- Everything that put an item in the account's hands, oldest first: { day, origin, left }.
local function supplyFor(itemID, acquired, buysByItem)
	local supply = {}
	for day, kinds in pairs(acquired[itemID] or {}) do
		for kind, quantity in pairs(kinds) do
			supply[#supply + 1] = { day = tonumber(day), origin = ORIGIN_OF_KIND[kind], left = quantity }
		end
	end
	for _, buy in ipairs(buysByItem[itemID] or {}) do
		supply[#supply + 1] = { day = IncomeLogic.DayOf(buy.ts), origin = "resold", left = tonumber(buy.quantity) or 0 }
	end
	table.sort(supply, function(a, b)
		return a.day < b.day
	end)
	return supply
end

-- Takes `units` out of the supply that came before `day`, oldest first, into `label`.
local function consume(supply, day, units, label)
	for _, lot in ipairs(supply) do
		if units <= 0 or lot.day > day then
			break
		end
		local take = math.min(units, lot.left)
		if take > 0 then
			lot.left, units = lot.left - take, units - take
			label[lot.origin] = (label[lot.origin] or 0) + take
		end
	end
	if units > 0 then
		label.unknown = (label.unknown or 0) + units
	end
end

local function byItem(events, kind)
	local out = {}
	for _, event in ipairs(events) do
		local itemID = tonumber(event.itemID)
		if event.kind == kind and itemID then
			out[itemID] = out[itemID] or {}
			table.insert(out[itemID], event)
		end
	end
	return out
end

--- Labels each auction sale with where its units came from: crafted, farmed (looted), resold
--- (bought) or unknown, matched oldest first per item against what came before the sale.
--- `acquired[itemID][day] = { craft = n, loot = n }`. Returns { [sale event] = { origin = units } }.
function IncomeLogic.LabelSaleOrigins(events, acquired)
	local labels, buysByItem = {}, byItem(events, "buy")
	for itemID, sales in pairs(byItem(events, "sell")) do
		table.sort(sales, function(a, b)
			return (tonumber(a.ts) or 0) < (tonumber(b.ts) or 0)
		end)
		local supply = supplyFor(itemID, acquired, buysByItem)
		for _, sale in ipairs(sales) do
			labels[sale] = {}
			consume(supply, IncomeLogic.DayOf(sale.ts), tonumber(sale.quantity) or 1, labels[sale])
		end
	end
	for _, event in ipairs(events) do
		if event.kind == "sell" and not labels[event] then
			labels[event] = { unknown = tonumber(event.quantity) or 1 }
		end
	end
	return labels
end

-- Income view -----------------------------------------------------------------------------------

local function addTo(target, gain, spend)
	target.gain = (target.gain or 0) + (tonumber(gain) or 0)
	target.spend = (target.spend or 0) + (tonumber(spend) or 0)
end

local function addDay(summary, byDay, day, sources)
	if not byDay[day] then
		byDay[day] = { day = day, gain = 0, spend = 0 }
		summary.daily[#summary.daily + 1] = byDay[day]
	end
	for source, entry in pairs(sources) do
		summary.sources[source] = summary.sources[source] or { gain = 0, spend = 0 }
		addTo(summary.sources[source], entry.gain, entry.spend)
		addTo(summary, entry.gain, entry.spend)
		addTo(byDay[day], entry.gain, entry.spend)
	end
end

--- Totals from `firstDay` on, for one character or all (characterKey nil).
--- incomeByCharacter: { [characterKey] = { [day] = { [source] = { gain, spend } } } }.
--- Returns { gain, spend, sources = { [source] = { gain, spend } }, daily = { { day, gain, spend } } oldest first }.
function IncomeLogic.SummarizeIncome(incomeByCharacter, characterKey, firstDay)
	local summary, byDay = { gain = 0, spend = 0, sources = {}, daily = {} }, {}
	for key, days in pairs(incomeByCharacter or {}) do
		for day, sources in pairs((not characterKey or key == characterKey) and days or {}) do
			if tonumber(day) >= firstDay then
				addDay(summary, byDay, tonumber(day), sources)
			end
		end
	end
	table.sort(summary.daily, function(a, b)
		return a.day < b.day
	end)
	return summary
end

--- One row per source with gold in or out: { source, gain, spend, net, share (of all gold in),
--- perDay }, most gold in first.
function IncomeLogic.SourceRows(summary, spanDays)
	local rows = {}
	for _, source in ipairs(IncomeLogic.SOURCES) do
		local entry = summary.sources[source]
		if entry and (entry.gain > 0 or entry.spend > 0) then
			rows[#rows + 1] = {
				source = source, gain = entry.gain, spend = entry.spend, net = entry.gain - entry.spend,
				share = summary.gain > 0 and entry.gain / summary.gain or 0,
				perDay = (entry.gain - entry.spend) / math.max(1, spanDays),
			}
		end
	end
	table.sort(rows, function(a, b)
		return a.gain > b.gain
	end)
	return rows
end

local function inScope(event, since, characterKey)
	return (tonumber(event.ts) or 0) >= since and (not characterKey or event.characterKey == characterKey)
end

--- Gold from auction sales split by where the units came from: { crafted = copper, ... }, each
--- sale's net shared out by its labelled units (see LabelSaleOrigins).
function IncomeLogic.SplitSalesByOrigin(events, labels, since, characterKey)
	local split = {}
	for _, event in ipairs(events) do
		local label = labels[event]
		if label and inScope(event, since, characterKey) then
			local net = tonumber(event.netCopper) or tonumber(event.totalCopper) or 0
			local units = math.max(1, tonumber(event.quantity) or 1)
			for origin, count in pairs(label) do
				split[origin] = (split[origin] or 0) + net * count / units
			end
		end
	end
	return split
end

local MISS_KINDS = { expired = true, cancelled = true }

local function typeRow(byType, rows, key, label)
	if not byType[key] then
		byType[key] = { key = key, label = label, sales = 0, units = 0, net = 0, misses = 0, items = {} }
		rows[#rows + 1] = byType[key]
	end
	return byType[key]
end

local function addSale(row, event)
	local net = tonumber(event.netCopper) or tonumber(event.totalCopper) or 0
	row.sales, row.units, row.net = row.sales + 1, row.units + (tonumber(event.quantity) or 1), row.net + net
	local itemKey = event.itemID or event.itemName
	row.items[itemKey] = (row.items[itemKey] or 0) + net
end

-- Adds one sale or miss to its type row; returns the sale's net (0 for a miss).
local function addTypeEvent(byType, rows, event, classOf)
	local key, label = classOf(event.itemID)
	local row = typeRow(byType, rows, key or "?", label or L["Unknown type"])
	if event.kind ~= "sell" then
		row.misses = row.misses + 1
		return 0
	end
	addSale(row, event)
	return tonumber(event.netCopper) or tonumber(event.totalCopper) or 0
end

local function finishTypeRows(rows, total, tracksMisses)
	for _, row in ipairs(rows) do
		row.share = total > 0 and row.net / total or 0
		local postings = row.sales + row.misses
		row.sellRate = tracksMisses and postings > 0 and row.sales / postings or nil
	end
	table.sort(rows, function(a, b)
		return a.net > b.net
	end)
end

--- Auction sales grouped by item type. classOf(itemID) → key, label (nil when unknown).
--- Returns rows { key, label, sales, units, net, share, sellRate, items = { [itemID or name] = net } },
--- most earned first. sellRate = sales / (sales + expired + cancelled), nil while the ledger
--- holds no expired or cancelled auctions at all.
function IncomeLogic.SummarizeItemTypes(events, since, characterKey, classOf)
	local byType, rows, total, tracksMisses = {}, {}, 0, false
	for _, event in ipairs(events) do
		local isMiss = MISS_KINDS[event.kind] == true
		tracksMisses = tracksMisses or isMiss
		if (event.kind == "sell" or isMiss) and inScope(event, since, characterKey) then
			total = total + addTypeEvent(byType, rows, event, classOf)
		end
	end
	finishTypeRows(rows, total, tracksMisses)
	return rows
end

-- Auction house mail ----------------------------------------------------------------------------

-- A sale invoice that still holds its gold.
local function saleEvent(mail)
	local bid = tonumber(mail.bid) or 0
	if mail.invoiceType ~= "seller" or not mail.itemName or bid <= 0 or (tonumber(mail.money) or 0) <= 0 then
		return nil
	end
	local quantity, kept = math.max(1, tonumber(mail.count) or 1), tonumber(mail.consignment)
	return {
		kind = "sell", itemName = mail.itemName, quantity = quantity, unitCopper = bid / quantity, totalCopper = bid,
		netCopper = bid - (kept or 0), consignmentCopper = kept, depositCopper = tonumber(mail.deposit),
		buyer = mail.buyer, source = "mail",
	}
end

-- A won auction that still holds its item.
local function buyEvent(mail)
	local bid = tonumber(mail.bid) or 0
	if mail.invoiceType ~= "buyer" or not mail.itemName or bid <= 0 or not mail.attachment then
		return nil
	end
	local quantity = math.max(1, tonumber(mail.attachment.count) or tonumber(mail.count) or 1)
	return {
		kind = "buy", itemID = mail.attachment.itemID, itemName = mail.itemName, quantity = quantity,
		unitCopper = bid / quantity, totalCopper = bid, source = "mail",
	}
end

-- An auction that came back unsold: the subject is one of the game's lines for it and the item is still attached.
local function returnedEvent(mail, returnSubjects)
	if mail.invoiceType or not (mail.attachment and mail.subject) then
		return nil
	end
	for _, entry in ipairs(returnSubjects or {}) do
		if mail.subject:match(entry[1]) then
			return {
				kind = entry[2], itemID = mail.attachment.itemID, itemName = mail.attachment.name,
				quantity = math.max(1, tonumber(mail.attachment.count) or 1), source = "mail",
			}
		end
	end
	return nil
end

--- What an auction house mail adds to the ledger, or nil for any other mail. `mail` holds what the
--- inbox reports: invoiceType, itemName, buyer, bid, deposit, consignment, count, money, subject,
--- ageSeconds and `attachment = { name, itemID, count }` (nil without an item). `returnSubjects` is
--- a list of { pattern, kind } for auctions that came back unsold.
--- Returns the event (ts counted back by the mail's age from `now`) and what the player takes from
--- the mail to settle it, "money" or "item": the event is written once, when that is taken.
function IncomeLogic.AuctionMailEvent(mail, returnSubjects, now)
	local sale = saleEvent(mail)
	local event = sale or buyEvent(mail) or returnedEvent(mail, returnSubjects)
	if not event then
		return nil
	end
	event.ts = now - math.max(0, tonumber(mail.ageSeconds) or 0)
	return event, sale and "money" or "item"
end

-- Per-item totals ---------------------------------------------------------------------------------

IncomeLogic.MIN_POSTINGS = 5
local TALLIED_KINDS = { sell = true, buy = true, expired = true, cancelled = true }

local function itemKeyOf(event)
	return event.itemID or event.itemName
end

local function kindTally(tallies, key, kind)
	tallies[key] = tallies[key] or {}
	tallies[key][kind] = tallies[key][kind] or { count = 0, units = 0, total = 0, net = 0, lastAt = 0 }
	return tallies[key][kind]
end

local function addEvent(tallies, event)
	local key = itemKeyOf(event)
	if not (key and TALLIED_KINDS[event.kind]) then
		return
	end
	local tally = kindTally(tallies, key, event.kind)
	local total = tonumber(event.totalCopper) or 0
	tally.count, tally.units = tally.count + 1, tally.units + (tonumber(event.quantity) or 1)
	tally.total, tally.net = tally.total + total, tally.net + (tonumber(event.netCopper) or total)
	tally.lastAt = math.max(tally.lastAt, tonumber(event.ts) or 0)
end

--- Adds an event that is leaving the ledger to `rolledOff`, the per-item totals of older events, so
--- averages and sale chances do not reset when the ledger reaches its size limit.
function IncomeLogic.AddRolledOff(rolledOff, event)
	addEvent(rolledOff, event)
end

--- Per item and event kind, what the ledger holds plus what has rolled off it:
--- `{ [itemID or itemName] = { [kind] = { count, units, total, net, lastAt } } }` for the kinds
--- sell, buy, expired and cancelled. `total` is copper paid or sold for, `net` after the cut.
function IncomeLogic.TallyByItem(events, rolledOff)
	local tallies = {}
	for key, kinds in pairs(rolledOff or {}) do
		for kind, old in pairs(kinds) do
			local tally = kindTally(tallies, key, kind)
			tally.count, tally.units, tally.total = old.count, old.units, old.total
			tally.net, tally.lastAt = old.net, old.lastAt
		end
	end
	for _, event in ipairs(events or {}) do
		addEvent(tallies, event)
	end
	return tallies
end

--- What was bought of one item: `{ units, avgUnit, lastAt }`, or nil when nothing was.
function IncomeLogic.PurchaseSummary(itemTally)
	local buys = itemTally and itemTally.buy
	if not buys or buys.units <= 0 then
		return nil
	end
	return { units = buys.units, avgUnit = buys.total / buys.units, lastAt = buys.lastAt }
end

--- The player's own chance that a posting of this item sells: sales / (sales + expired + cancelled),
--- nil below `minPostings` (default MIN_POSTINGS) postings.
function IncomeLogic.SaleChance(itemTally, minPostings)
	local function count(kind)
		return itemTally and itemTally[kind] and itemTally[kind].count or 0
	end
	local sales, postings = count("sell"), count("sell") + count("expired") + count("cancelled")
	if postings < (minPostings or IncomeLogic.MIN_POSTINGS) or postings == 0 then
		return nil
	end
	return sales / postings
end

--- Profit per unit on an item both bought and sold: the average sale after the cut less the average
--- price paid, and the units that could be matched. nil when it was never bought or never sold.
function IncomeLogic.RealizedProfit(itemTally)
	local buys, sales = itemTally and itemTally.buy, itemTally and itemTally.sell
	if not (buys and sales) or buys.units <= 0 or sales.units <= 0 then
		return nil
	end
	return { profitEach = sales.net / sales.units - buys.total / buys.units, units = math.min(buys.units, sales.units) }
end

--- The latest events of the given kinds since `since`, newest first, at most `limit`.
function IncomeLogic.LatestEvents(events, kinds, since, limit)
	local latest = {}
	for _, event in ipairs(events or {}) do
		if kinds[event.kind] and (tonumber(event.ts) or 0) >= since then
			latest[#latest + 1] = event
		end
	end
	table.sort(latest, function(a, b) return (tonumber(a.ts) or 0) > (tonumber(b.ts) or 0) end)
	for index = #latest, limit + 1, -1 do
		latest[index] = nil
	end
	return latest
end

IncomeLogic.CUT_MIN_SALES = 5
-- Only the latest sales count, so a change in the game's fee shows up within a few dozen sales.
local CUT_LATEST_SALES = 50

local function median(sorted)
	local middle = math.floor((#sorted + 1) / 2)
	if #sorted % 2 == 1 then
		return sorted[middle]
	end
	return (sorted[middle] + sorted[middle + 1]) / 2
end

--- The auction house's share of a sale, measured from the latest sale events that record what the
--- house kept (`consignmentCopper` of `totalCopper`). Returns `{ cut, sales }`: the median share and
--- the number of sales behind it; `cut` is nil below `minSales` (default CUT_MIN_SALES). Sales saved
--- before the share was recorded carry no `consignmentCopper` and are skipped.
function IncomeLogic.MeasureAuctionCut(events, minSales)
	local shares = {}
	for index = #(events or {}), 1, -1 do
		local event = events[index]
		local kept, total = tonumber(event.consignmentCopper), tonumber(event.totalCopper)
		if event.kind == "sell" and kept and total and total > 0 then
			shares[#shares + 1] = kept / total
			if #shares >= CUT_LATEST_SALES then
				break
			end
		end
	end
	if #shares < (minSales or IncomeLogic.CUT_MIN_SALES) then
		return { sales = #shares }
	end
	table.sort(shares)
	return { cut = median(shares), sales = #shares }
end

--- Sales statistics from ledger events (kind "sell": ts, itemID / itemName, quantity, totalCopper
--- gross, netCopper after the auction house cut). `days` limits to the last N days; nil is all time.
--- Returns { totals, items, daily, recent, spanDays }: items carry sales, units, net, avgUnit,
--- perWeek (sales per week over the span) and lastAt; daily is { at, value } net per day, oldest
--- first; recent is the matching events, newest first.
function IncomeLogic.SummarizeSales(events, now, days)
	local since = days and (now - days * 86400) or 0
	local totals = { net = 0, gross = 0, sales = 0, units = 0 }
	local itemByKey, items, byDay, daily, recent = {}, {}, {}, {}, {}
	local firstAt = now
	for _, event in ipairs(events or {}) do
		local ts = tonumber(event.ts) or 0
		if event.kind == "sell" and ts >= since then
			local gross = tonumber(event.totalCopper) or 0
			local net = tonumber(event.netCopper) or gross
			local units = tonumber(event.quantity) or 1
			local key = event.itemID or event.itemName
			local item = itemByKey[key]
			if not item then
				item = { itemID = event.itemID, name = event.itemName, sales = 0, units = 0, net = 0, gross = 0, lastAt = 0 }
				itemByKey[key] = item
				items[#items + 1] = item
			end
			item.sales, item.units = item.sales + 1, item.units + units
			item.net, item.gross = item.net + net, item.gross + gross
			item.lastAt = math.max(item.lastAt, ts)
			totals.sales, totals.units = totals.sales + 1, totals.units + units
			totals.net, totals.gross = totals.net + net, totals.gross + gross
			firstAt = math.min(firstAt, ts)
			local day = math.floor(ts / 86400)
			if not byDay[day] then
				byDay[day] = { at = day * 86400 + 43200, value = 0 }
				daily[#daily + 1] = byDay[day]
			end
			byDay[day].value = byDay[day].value + net
			recent[#recent + 1] = event
		end
	end
	local spanDays = days or math.max(1, (now - firstAt) / 86400)
	for _, item in ipairs(items) do
		item.avgUnit = item.units > 0 and item.gross / item.units or nil
		item.perWeek = item.sales / spanDays * 7
	end
	table.sort(daily, function(a, b) return a.at < b.at end)
	table.sort(recent, function(a, b) return (tonumber(a.ts) or 0) > (tonumber(b.ts) or 0) end)
	return { totals = totals, items = items, daily = daily, recent = recent, spanDays = spanDays }
end

