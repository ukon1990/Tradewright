local _, Tradewright = ...

-- Pure mail helpers: what a character's surplus mail sends, and the rows of the review
-- panel that shows and changes it. No WoW API here, so the offline tests can load this file alone.
local MailLogic = {}
Tradewright.MailLogic = MailLogic

--- The To line for a character key ("First-Second"). On WoW Forever there are no realms: the
--- second part is the surname and mail needs the full name, "First Second". On retail it is the
--- realm, and the name alone reaches a character on the same realm.
function MailLogic.MailRecipient(characterKey, fullName)
	local first, second = tostring(characterKey or ""):match("^([^%-]+)%-(.+)$")
	if not first then
		return tostring(characterKey or "")
	end
	return fullName and (first .. " " .. second) or first
end

--- Forever's bank character used to be saved per surname, read as a realm. The first of those
--- choices (by surname) that is still a known character, or nil. known[characterKey] = true.
function MailLogic.EarlierForeverSeller(sellerByRealm, known)
	local groups = {}
	for group in pairs(sellerByRealm or {}) do
		groups[#groups + 1] = group
	end
	table.sort(groups)
	for _, group in ipairs(groups) do
		local key = sellerByRealm[group]
		if type(key) == "string" and known[key] then
			return key
		end
	end
	return nil
end

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

--- The review rows for the items worth more destroyed: like BuildReviewRows with everything sendable,
--- over the items `isDestroyed(itemID)` accepts only, and keep amounts of those items only (an item
--- kept elsewhere is no row here).
function MailLogic.BuildDestroyRows(bagItems, isDestroyed, keep, held, skip)
	local wanted, kept = {}, {}
	for itemID, bag in pairs(bagItems or {}) do
		if listable(bag) and isDestroyed(itemID) then
			wanted[itemID] = bag
			kept[itemID] = keep and keep[itemID]
		end
	end
	return MailLogic.BuildReviewRows(wanted, kept, held, true, skip)
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

--- Narrows the surplus to the items `isWanted(itemID)` accepts: every other row sends nothing and
--- gets `reason`. Rows skipped by hand keep saying so.
function MailLogic.SendOnly(rows, isWanted, reason)
	for _, row in ipairs(rows) do
		if row.reason ~= "skipped" and not isWanted(row.itemID) then
			row.send, row.reason = 0, reason
		end
	end
	return rows
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

--- The bank character chosen for `realm`, or nil when none is chosen or the
--- chosen character is no longer known. sellerByRealm[realm] = characterKey ("" means none).
function MailLogic.ResolveSellerCharacter(sellerByRealm, realm, knownCharacters)
	local key = type(sellerByRealm) == "table" and realm and sellerByRealm[realm] or nil
	if type(key) ~= "string" or key == "" or not (knownCharacters and knownCharacters[key]) then
		return nil
	end
	return key
end

--- The character that destroys items for one action (disenchant, prospect, mill): the one chosen,
--- else, while nothing is chosen, the first of `candidates` (the characters with the profession, best
--- first). `chosen` "" means none, as does a chosen character no longer in `knownCharacters`.
function MailLogic.ResolveDestroyerCharacter(chosen, candidates, knownCharacters)
	if chosen == nil then
		return candidates and candidates[1] or nil
	end
	if type(chosen) ~= "string" or chosen == "" or not (knownCharacters and knownCharacters[chosen]) then
		return nil
	end
	return chosen
end

--- Shares the bag stock out over the characters that need materials mailed to them.
--- lines: { { itemID, name, allocations = { { characterKey, mailQuantity } } } }; stock[itemID] is
--- what the bags hold. Returns the destinations that get at least one item, sorted by character:
--- { characterKey, mailName, items = { { itemID, quantity, name } }, totalQuantity,
--- missing = { { itemID, quantity, name } }, complete }. A destination is complete when everything
--- it needs mailed is in the bags; earlier lines and characters are served first.
function MailLogic.BuildMailPlan(lines, stock)
	local left, byKey, out = {}, {}, {}
	for _, line in ipairs(lines or {}) do
		local itemID = line.itemID
		left[itemID] = left[itemID] or tonumber(stock and stock[itemID]) or 0
		for _, alloc in ipairs(line.allocations or {}) do
			local key = tostring(alloc.characterKey or "")
			local need = tonumber(alloc.mailQuantity) or 0
			if key ~= "" and need > 0 then
				local dest = byKey[key]
				if not dest then
					dest = { characterKey = key, mailName = key:match("^([^%-]+)") or key, items = {}, missing = {}, totalQuantity = 0 }
					byKey[key] = dest
				end
				local send = math.min(need, left[itemID])
				left[itemID] = left[itemID] - send
				if send > 0 then
					dest.items[#dest.items + 1] = { itemID = itemID, quantity = send, name = line.name }
					dest.totalQuantity = dest.totalQuantity + send
				end
				if send < need then
					dest.missing[#dest.missing + 1] = { itemID = itemID, quantity = need - send, name = line.name }
				end
			end
		end
	end
	for _, dest in pairs(byKey) do
		if #dest.items > 0 then
			dest.complete = #dest.missing == 0
			out[#out + 1] = dest
		end
	end
	table.sort(out, function(a, b) return a.characterKey < b.characterKey end)
	return out
end

--- Crafted items waiting to go back to the seller, clamped to what the bags still hold.
--- toSeller[itemID] = quantity owed, bagItems[itemID] = { quantity, name }. Returns no destination
--- without a seller or without anything to send, else one: { kind = "crafts", characterKey,
--- mailName, items = { { itemID, quantity, name } }, totalQuantity }, items sorted by name.
function MailLogic.BuildReturnToSellerPlan(toSeller, bagItems, sellerKey)
	local dest = { kind = "crafts", characterKey = sellerKey, mailName = tostring(sellerKey or ""):match("^([^%-]+)"),
		items = {}, totalQuantity = 0 }
	for itemID, owed in pairs(toSeller or {}) do
		local bag = bagItems and bagItems[itemID]
		local quantity = math.min(tonumber(owed) or 0, bag and tonumber(bag.quantity) or 0)
		if quantity > 0 then
			dest.items[#dest.items + 1] = { itemID = itemID, quantity = quantity, name = bag.name }
			dest.totalQuantity = dest.totalQuantity + quantity
		end
	end
	if not sellerKey or #dest.items == 0 then
		return {}
	end
	table.sort(dest.items, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return { dest }
end

