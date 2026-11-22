local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Pure item-log helpers: what changed in the bags, why, and how the short log is kept. No WoW API
-- here, so the offline tests can load this file on its own.
--
-- An entry: { t = time, id = itemID, n = count (negative: left the bags), why = reason key,
--             who = other character, for mail }
local ItemLogLogic = {}
Tradewright.ItemLogLogic = ItemLogLogic

local MERGE_SECONDS = 60
local DAY = 86400

-- What was going on, most telling first, and the reason it gives a change.
local INCOMING = {
	{ "craft", "crafted" }, { "quest", "quest" }, { "loot", "looted" }, { "mail", "mail_in" }, { "trade", "trade_in" },
	{ "merchant", "bought" }, { "auction", "auction_in" },
}
local OUTGOING = {
	{ "destroy", "destroyed" }, { "mail", "mail_out" }, { "trade", "trade_out" }, { "merchant", "sold" }, { "auction", "listed" },
}

local LABELS = {
	crafted = "Crafted", quest = L["Quest reward"], looted = "Looted", mail_in = L["From mail"], trade_in = L["Traded to you"],
	bought = L["Bought from a vendor"], auction_in = L["Bought at auction"], from_bank = L["Taken from the bank"],
	from_warband = L["Taken from the warband bank"], received = "Received",
	destroyed = "Destroyed", mail_out = "Mailed", trade_out = L["Traded away"], sold = L["Sold to a vendor"],
	listed = L["Listed at auction"], to_bank = L["Moved to the bank"], to_warband = L["Moved to the warband bank"],
}

--- What changed between two { [itemID] = count } tables: { { itemID, delta } }, lowest item ID first.
function ItemLogLogic.Diff(before, after)
	local changes, seen = {}, {}
	for _, counts in ipairs({ before, after }) do
		for itemID in pairs(counts) do
			local delta = (after[itemID] or 0) - (before[itemID] or 0)
			if not seen[itemID] and delta ~= 0 then
				changes[#changes + 1] = { itemID = itemID, delta = delta }
			end
			seen[itemID] = true
		end
	end
	table.sort(changes, function(a, b) return a.itemID < b.itemID end)
	return changes
end

local function firstActive(list, context)
	for _, pair in ipairs(list) do
		if context[pair[1]] then
			return pair[2]
		end
	end
	return nil
end

-- At the bank with nothing else going on: the warband bank when its count moved the other way.
local function bankReason(delta, warbandDelta)
	local side = (warbandDelta or 0) * delta < 0 and "warband" or "bank"
	return (delta > 0 and "from_" or "to_") .. side
end

--- Why the bags changed by `delta` of an item, or nil when it is not worth a line. `context`: what
--- was open or just happened (craft, quest, loot, mail, trade, merchant, auction, destroy, equip,
--- bank). `warbandDelta`: how the warband bank's count of the item changed at the same time.
--- Not logged: putting gear on or off, and items that left for no known reason (used up).
function ItemLogLogic.Reason(delta, context, warbandDelta)
	if context.equip then
		return nil
	end
	local incoming = delta > 0
	local reason = firstActive(incoming and INCOMING or OUTGOING, context)
	if not reason and context.bank then
		return bankReason(delta, warbandDelta)
	end
	if not reason and incoming then
		return "received"
	end
	return reason
end

--- Drop the oldest entries beyond `limits.rows` and those older than `limits.days`.
function ItemLogLogic.Trim(log, now, limits)
	while #log > 0 and (#log > limits.rows or log[1].t < now - limits.days * DAY) do
		table.remove(log, 1)
	end
end

--- Append an entry (oldest first). The same item for the same reason within a minute is added to
--- the last entry instead, so a stack looted in pieces is one line.
function ItemLogLogic.Add(log, entry, limits)
	local last = log[#log]
	if last and last.id == entry.id and last.why == entry.why and last.who == entry.who and entry.t - last.t <= MERGE_SECONDS then
		last.n, last.t = last.n + entry.n, entry.t
	else
		log[#log + 1] = entry
	end
	ItemLogLogic.Trim(log, entry.t, limits)
end

--- "Looted", "Mail from Bankey", "Mailed to Bankey".
function ItemLogLogic.Describe(entry)
	if entry.who and entry.why == "mail_in" then
		return L["Mail from "] .. entry.who
	elseif entry.who and entry.why == "mail_out" then
		return L["Mailed to "] .. entry.who
	end
	return LABELS[entry.why] or "Changed"
end

--- The entries to show, newest first, at most `limit`: those whose item name (`nameOf(itemID)`) or
--- reason holds `query` (any case, plain text).
function ItemLogLogic.Visible(log, nameOf, query, limit)
	local rows = {}
	query = string.lower(query or "")
	for index = #log, 1, -1 do
		local entry = log[index]
		local text = string.lower((nameOf(entry.id) or "") .. " " .. ItemLogLogic.Describe(entry))
		if query == "" or string.find(text, query, 1, true) then
			rows[#rows + 1] = entry
		end
		if #rows >= limit then
			break
		end
	end
	return rows
end
