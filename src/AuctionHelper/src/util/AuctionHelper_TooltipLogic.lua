local _, AuctionHelper = ...

-- Pure item-tooltip helpers: which lines the AuctionHelper block shows for an item, and who holds
-- it. No WoW API here, so the offline tests can load this file on its own.
local TooltipLogic = {}
AuctionHelper.TooltipLogic = TooltipLogic

local MAX_OWNER_LINES = 5
local MAX_NAMES = 3
local SEP = " · "

--- Who holds an item: { { key, name, bags, bank } } with the largest holder first, and the total.
--- `skipKey` leaves one character out (the logged-in one, which is counted live instead).
function TooltipLogic.Owners(characters, itemID, skipKey)
	local owners, total = {}, 0
	for key, snapshot in pairs(characters or {}) do
		local bags = snapshot.bags and snapshot.bags[itemID] or 0
		local bank = snapshot.bank and snapshot.bank[itemID] or 0
		if key ~= skipKey and bags + bank > 0 then
			owners[#owners + 1] = { key = key, name = snapshot.name or key, bags = bags, bank = bank }
			total = total + bags + bank
		end
	end
	table.sort(owners, function(a, b)
		local ta, tb = a.bags + a.bank, b.bags + b.bank
		if ta ~= tb then
			return ta > tb
		end
		return a.name < b.name
	end)
	return owners, total
end

--- "3 min ago", "5 h ago", "4 days ago".
function TooltipLogic.AgeText(seconds)
	seconds = math.max(0, tonumber(seconds) or 0)
	if seconds < 3600 then
		return string.format("%d min ago", math.max(1, math.floor(seconds / 60)))
	end
	if seconds < 2 * 86400 then
		return string.format("%d h ago", math.floor(seconds / 3600))
	end
	return string.format("%d days ago", math.floor(seconds / 86400))
end

local function percentText(value)
	return string.format("%s%.0f%%", value >= 0 and "+" or "", value)
end

-- Unique values of `field` over `rows`, in order, at most MAX_NAMES; and how many were left out.
local function uniqueNames(rows, field)
	local seen, names, extra = {}, {}, 0
	for _, row in ipairs(rows) do
		local name = row[field]
		if name and not seen[name] then
			seen[name] = true
			if #names < MAX_NAMES then
				names[#names + 1] = name
			else
				extra = extra + 1
			end
		end
	end
	return names, extra
end

local function crafterNames(producedBy)
	local crafters = {}
	for _, row in ipairs(producedBy) do
		local label = tostring(row.characterLabel or row.characterKey or "?")
		local name = label:match("^(.-) %- ") or label
		crafters[#crafters + 1] = { text = string.format("%s (%s)", name, tostring(row.professionName or "?")) }
	end
	return (uniqueNames(crafters, "text"))
end

--- Sum up GetItemRecipeRelationships for the tooltip: how many different recipes use the item, in
--- which professions, and who crafts it ("Name (Profession)").
function TooltipLogic.RecipeUse(relationships)
	local usedBy = relationships.usedBy or {}
	local out = { usedCount = 0, crafters = crafterNames(relationships.producedBy or {}) }
	local recipes = {}
	for _, row in ipairs(usedBy) do
		if not recipes[row.recipeID] then
			recipes[row.recipeID] = true
			out.usedCount = out.usedCount + 1
		end
	end
	out.professions = uniqueNames(usedBy, "professionName")
	return out
end

local function add(lines, label, value, tone)
	lines[#lines + 1] = { label = label, value = value, tone = tone }
end

local function trendTone(trend)
	if not trend then
		return nil
	end
	return trend >= 10 and "success" or trend <= -10 and "info" or nil
end

local function priceLine(lines, g, f)
	local unit = g.price or g.estimate
	if unit then
		local trend = g.trend and ("  " .. percentText(g.trend) .. " usual") or ""
		add(lines, "Price", f.money(unit) .. trend, trendTone(g.trend))
	end
end

local function usualLine(lines, g, f)
	if not g.average then
		return
	end
	local value = f.moneyShort(g.average)
	if (g.high or 0) > (g.low or math.huge) then
		value = value .. string.format("  (%s – %s)", f.moneyShort(g.low), f.moneyShort(g.high))
	end
	add(lines, g.usualDays and "Usual" or "7-day avg", value)
end

local function listedLine(lines, g, f)
	if (g.listed or 0) <= 0 then
		return
	end
	local value = f.number(g.listed)
	if g.sellsPerDay then
		local perDay = g.sellsPerDay >= 10 and f.number(g.sellsPerDay) or string.format("%.1f", g.sellsPerDay)
		value = value .. SEP .. "~" .. perDay .. " sold/day"
	end
	add(lines, "Listed", value)
end

local function ownedLine(lines, g, f)
	local owned, listed = tonumber(g.ownedAll) or 0, tonumber(g.listedByYou) or 0
	if owned <= 0 and listed <= 0 then
		return
	end
	local parts = { f.number(owned) }
	local unit = g.price or g.estimate
	if unit and owned > 0 then
		parts[#parts + 1] = "worth " .. f.moneyShort(unit * owned)
	end
	if listed > 0 then
		parts[#parts + 1] = f.number(listed) .. " listed"
	end
	add(lines, "You own", table.concat(parts, SEP))
end

local function ownerText(owner, f)
	local parts = {}
	for _, place in ipairs({ "bags", "bank", "warband" }) do
		if (tonumber(owner[place]) or 0) > 0 then
			parts[#parts + 1] = f.number(owner[place]) .. " " .. place
		end
	end
	return table.concat(parts, SEP)
end

local function ownerLines(lines, g, f)
	local owners = g.owners or {}
	for i = 1, math.min(#owners, MAX_OWNER_LINES) do
		add(lines, owners[i].name, ownerText(owners[i], f))
	end
	if #owners > MAX_OWNER_LINES then
		add(lines, "and " .. (#owners - MAX_OWNER_LINES) .. " more", "")
	end
end

local function craftLines(lines, g, f)
	if not g.craftCost then
		return
	end
	add(lines, "Craft cost", f.money(g.craftCost))
	if g.profit then
		local value = (g.profit >= 0 and "+" or "") .. f.money(g.profit) .. "  " .. percentText(g.margin or 0)
		add(lines, "Profit after cut", value, g.profit >= 0 and "success" or "danger")
	end
end

local function recipeLines(lines, g)
	local use = g.recipeUse
	if not use then
		return
	end
	if use.usedCount > 0 then
		local recipes = use.usedCount .. " " .. AuctionHelper:Plural(use.usedCount, "recipe")
		add(lines, "Used in", string.format("%s (%s)", recipes, table.concat(use.professions, ", ")))
	end
	if #use.crafters > 0 then
		add(lines, "Crafted by", table.concat(use.crafters, ", "))
	end
end

local function detailLines(lines, g, f)
	craftLines(lines, g, f)
	ownerLines(lines, g, f)
	if g.rule and g.rule.ignore then
		add(lines, "Rule", "never posted in bulk")
	elseif g.rule and (tonumber(g.rule.reserveQty) or 0) > 0 then
		add(lines, "Rule", "keep " .. f.number(g.rule.reserveQty))
	end
	if g.vendor and not g.vendorBeatsAh then
		add(lines, "Vendor pays", f.money(g.vendor))
	end
	recipeLines(lines, g)
	if g.avgSale and g.avgSale > 0 then
		add(lines, "Your average sale", f.money(g.avgSale))
	end
end

local function headerOf(g)
	if not g.price then
		return { right = g.estimate and "estimate" or nil }
	end
	if not g.priceAge then
		return {}
	end
	return { right = TooltipLogic.AgeText(g.priceAge), tone = g.priceStale and "warning" or nil }
end

local function hasData(g)
	return g ~= nil and (g.price or g.estimate or g.craftCost or g.avgSale) ~= nil
end

--- The AuctionHelper block for an item summary (BuildItemGoldSummary), or nil when there is
--- nothing worth showing. `opts`: detail (Shift held), money / moneyShort / number formatters.
--- Returns { header = { right, tone }, lines = { { label, value, tone } } }; a tone is a theme
--- colour name ("success", "danger", "warning", "info") or nil for the plain value colour.
function TooltipLogic.BuildLines(g, opts)
	if not hasData(g) then
		return nil
	end
	local lines = {}
	priceLine(lines, g, opts)
	usualLine(lines, g, opts)
	listedLine(lines, g, opts)
	ownedLine(lines, g, opts)
	if g.vendorBeatsAh then
		add(lines, "Vendor pays", opts.money(g.vendor) .. SEP .. "more than the AH", "warning")
	end
	if opts.detail then
		detailLines(lines, g, opts)
	end
	if #lines == 0 then
		return nil
	end
	return { header = headerOf(g), lines = lines }
end
