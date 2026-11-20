local _, ProfessionExporter = ...

-- Pure mail helpers (F23, F24): what a character's surplus mail sends, and the rows of the review
-- panel that shows and changes it. No WoW API here, so the offline tests can load this file alone.
local MailLogic = {}
ProfessionExporter.MailLogic = MailLogic

local function listable(bag)
	return bag.sellable and (tonumber(bag.quality) or 0) >= 1
end

local function sendAndReason(quantity, kept, held)
	local send = math.max(0, quantity - (kept or 0) - held)
	if send > 0 then
		return send, nil
	end
	return 0, (kept or 0) >= quantity and "kept" or "held"
end

-- One review row: how many of an item go to the seller, and why the rest stays.
local function surplusRow(itemID, bag, kept, held, opts)
	kept, held = tonumber(kept), tonumber(held) or 0
	local quantity = tonumber(bag.quantity) or 0
	local row = { itemID = itemID, name = bag.name, bags = quantity, keep = kept, held = held, send = 0 }
	if opts.skip and opts.skip[itemID] then
		row.reason = "skipped"
	elseif not kept and not opts.sendOthers then
		row.reason = "othersOff"
	else
		row.send, row.reason = sendAndReason(quantity, kept, held)
	end
	return row
end

--- Every item the surplus mail could send, with what it sends. bagItems[itemID] = { quantity,
--- quality, sellable, name }; keep[itemID] is how many this character keeps; held[itemID] is already
--- spoken for (its own queued crafts, other mail rows); skip[itemID] skips an item this visit.
--- An item with a keep amount sends above keep + held; one without sends above held only when
--- `sendOthers` is on. Items that are not sellable or are poor quality are left out; kept items
--- not in the bags are listed with nothing to send. Rows: { itemID, name, bags, keep, held, send,
--- reason } where reason is nil when it sends, else "skipped", "othersOff", "kept" or "held".
function MailLogic.BuildReviewRows(bagItems, keep, held, sendOthers, skip)
	local rows, opts = {}, { sendOthers = sendOthers, skip = skip }
	keep, held, bagItems = keep or {}, held or {}, bagItems or {}
	for itemID, bag in pairs(bagItems) do
		if listable(bag) then
			rows[#rows + 1] = surplusRow(itemID, bag, keep[itemID], held[itemID], opts)
		end
	end
	for itemID, kept in pairs(keep) do
		if not bagItems[itemID] then
			rows[#rows + 1] = surplusRow(itemID, { quantity = 0 }, kept, held[itemID], opts)
		end
	end
	return rows
end

--- The review rows that send something, as { { itemID, quantity, name } } sorted by name.
function MailLogic.SurplusItems(rows)
	local items = {}
	for _, row in ipairs(rows) do
		if row.send > 0 then
			items[#items + 1] = { itemID = row.itemID, quantity = row.send, name = row.name }
		end
	end
	table.sort(items, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return items
end

--- What a character can spare from its bags (see BuildReviewRows and SurplusItems).
function MailLogic.BuildSurplusPlan(bagItems, keep, held, sendOthers, skip)
	return MailLogic.SurplusItems(MailLogic.BuildReviewRows(bagItems, keep, held, sendOthers, skip))
end

--- Counts and totals for the review panel: rows sending and not, units to send, rows skipped,
--- and what the units are worth at each row's `unitPrice` (rows without one add nothing).
function MailLogic.SummarizeReviewRows(rows)
	local sum = { sending = 0, kept = 0, all = #(rows or {}), send = 0, skipped = 0, worth = 0 }
	for _, row in ipairs(rows or {}) do
		if row.send > 0 then
			sum.sending = sum.sending + 1
			sum.send = sum.send + row.send
			sum.worth = sum.worth + row.send * (tonumber(row.unitPrice) or 0)
		else
			sum.kept = sum.kept + 1
		end
		sum.skipped = sum.skipped + (row.reason == "skipped" and 1 or 0)
	end
	return sum
end

local function reviewRowShown(row, filter, search)
	if (filter == "sending" and row.send == 0) or (filter == "kept" and row.send > 0) then
		return false
	end
	return search == "" or tostring(row.name or ""):lower():find(search, 1, true) ~= nil
end

local function byName(a, b)
	return tostring(a.name) < tostring(b.name)
end

--- Review rows to show for a filter ("sending", "kept" or "all") and a search text, grouped by
--- `classOf(row)` (groups and the rows in them sorted by name). Each group starts with
--- { group = true, label, count }.
function MailLogic.ListReviewRows(rows, filter, search, classOf)
	search = tostring(search or ""):lower()
	local groups, labels = {}, {}
	for _, row in ipairs(rows or {}) do
		if reviewRowShown(row, filter, search) then
			local label = classOf(row) or "Other"
			if not groups[label] then
				groups[label] = {}
				labels[#labels + 1] = label
			end
			table.insert(groups[label], row)
		end
	end
	table.sort(labels)
	local out = {}
	for _, label in ipairs(labels) do
		table.sort(groups[label], byName)
		out[#out + 1] = { group = true, label = label, count = #groups[label] }
		for _, row in ipairs(groups[label]) do
			out[#out + 1] = row
		end
	end
	return out
end
