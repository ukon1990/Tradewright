local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Pure item-tooltip helpers: which lines the Tradewright block shows for an item, and who holds
-- it. No WoW API here, so the offline tests can load this file on its own.
local TooltipLogic = {}
Tradewright.TooltipLogic = TooltipLogic

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
		return string.format(L["%d min ago"], math.max(1, math.floor(seconds / 60)))
	end
	if seconds < 2 * 86400 then
		return string.format(L["%d h ago"], math.floor(seconds / 3600))
	end
	return string.format(L["%d days ago"], math.floor(seconds / 86400))
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
		local trend = g.trend and ("  " .. string.format(L["%s usual"], percentText(g.trend))) or ""
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
		value = value .. SEP .. string.format(L["~%s sold/day"], perDay)
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
		parts[#parts + 1] = string.format(L["worth %s"], f.moneyShort(unit * owned))
	end
	if listed > 0 then
		parts[#parts + 1] = string.format(L["%s listed"], f.number(listed))
	end
	add(lines, L["You own"], table.concat(parts, SEP))
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
		add(lines, string.format(L["and %s more"], (#owners - MAX_OWNER_LINES)), "")
	end
end

local function craftLines(lines, g, f)
	if not g.craftCost then
		return
	end
	add(lines, L["Craft cost"], f.money(g.craftCost))
	if g.profit then
		local value = (g.profit >= 0 and "+" or "") .. f.money(g.profit) .. "  " .. percentText(g.margin or 0)
		add(lines, L["Profit after cut"], value, g.profit >= 0 and "success" or "danger")
	end
end

local function recipeLines(lines, g)
	local use = g.recipeUse
	if not use then
		return
	end
	if use.usedCount > 0 then
		local recipes = use.usedCount .. " " .. Tradewright:Plural(use.usedCount, "recipe")
		add(lines, L["Used in"], string.format("%s (%s)", recipes, table.concat(use.professions, ", ")))
	end
	if #use.crafters > 0 then
		add(lines, L["Crafted by"], table.concat(use.crafters, ", "))
	end
end

--- "62% of posted" for a sale rate of 0.62 (sold / posted).
function TooltipLogic.SaleRateText(rate)
	return string.format(L["%.0f%% of posted"], rate * 100)
end

local function ownSalesLines(lines, g, f)
	if g.saleRate then
		add(lines, L["You sold"], TooltipLogic.SaleRateText(g.saleRate))
	end
	if g.avgSale and g.avgSale > 0 then
		add(lines, L["Your average sale"], f.money(g.avgSale))
	end
end

local function detailLines(lines, g, f)
	craftLines(lines, g, f)
	ownerLines(lines, g, f)
	if g.rule and g.rule.ignore then
		add(lines, "Rule", L["never posted in bulk"])
	elseif g.rule and (tonumber(g.rule.reserveQty) or 0) > 0 then
		add(lines, "Rule", string.format(L["keep %s"], f.number(g.rule.reserveQty)))
	end
	if g.vendor and not g.vendorBeatsAh then
		add(lines, L["Vendor pays"], f.money(g.vendor))
	end
	recipeLines(lines, g)
	ownSalesLines(lines, g, f)
end

local SALVAGE_LABEL = { disenchant = L["Disenchant value"], prospect = L["Prospecting value"], mill = L["Milling value"] }
-- A prospect or mill destroys several items; the label says for how many the value is.
local SALVAGE_LABEL_FOR_SEVERAL = { prospect = L["Prospecting value, for %d"], mill = L["Milling value, for %d"] }

local function salvageLabel(salvage)
	local forSeveral = (salvage.perCast or 1) > 1 and SALVAGE_LABEL_FOR_SEVERAL[salvage.action]
	return forSeveral and string.format(forSeveral, salvage.perCast) or SALVAGE_LABEL[salvage.action]
end

-- "Prospecting value, for 5   62s · 32 counted": what one cast gives on average, and whether that
-- rests on researched yields ("estimate") or on counted outcomes.
local function salvageLines(lines, g, f)
	for _, salvage in ipairs(g.salvage or {}) do
		local origin = salvage.basis == "researched" and L["estimate"] or string.format(L["%s counted"], f.number(salvage.casts))
		add(lines, salvageLabel(salvage), f.money(salvage.value) .. SEP .. origin)
	end
end

local MAX_SALVAGE_SOURCES = 3
local SALVAGE_SOURCE_LABEL = { prospect = L["Prospected from"], mill = L["Milled from"] }

-- "Milled from   Mageroyal · 2.9 per 5 · 1g 20s each": where the item comes from, what one cast
-- gives on average, and what one of the item then costs. The list arrives cheapest first.
local function salvageSourceLines(lines, g, f)
	for index, source in ipairs(g.salvageSources or {}) do
		if index > MAX_SALVAGE_SOURCES then
			break
		end
		local value = source.name .. SEP .. string.format(L["%.1f per %d"], source.quantity, source.perCast)
		if source.costEach then
			value = value .. SEP .. string.format(L["%s each"], f.money(source.costEach))
		end
		add(lines, SALVAGE_SOURCE_LABEL[source.action], value)
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
	return g ~= nil and (g.price or g.estimate or g.craftCost or g.avgSale or g.saleRate or g.salvage or g.salvageSources) ~= nil
end

--- The Tradewright block for an item summary (BuildItemGoldSummary), or nil when there is
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
		add(lines, L["Vendor pays"], opts.money(g.vendor) .. SEP .. L["more than the AH"], "warning")
	end
	salvageLines(lines, g, opts)
	salvageSourceLines(lines, g, opts)
	if opts.detail then
		detailLines(lines, g, opts)
	end
	if #lines == 0 then
		return nil
	end
	return { header = headerOf(g), lines = lines }
end
