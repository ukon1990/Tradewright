local Tradewright = select(2, ...)

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- The views of the Destroying tab (Tradewright_SalvageTab.lua): "Owned", the items the characters hold,
-- and "Below disenchant value", gear in the last scan worth buying to disenchant. Each view supplies
-- its rows, columns and side-pane facts; the tab draws them. What one disenchant gives (chances and
-- counts) is shared by both views, in the side pane and in the row tooltip.

local ACTION_LABEL = { disenchant = L["Disenchant"], prospect = L["Prospecting"], mill = L["Milling"] }
local USE_LABEL = { vendor = L["Vendor"], auction = L["Auction"] }

local function money(pe, copper)
	return copper and pe:FormatCopperShort(copper) or "-"
end

-- "~12g 40s" for a value that rests on researched yields rather than counted outcomes.
local function estimateText(pe, copper, basis)
	local text = pe:FormatCopperShort(copper)
	return basis == "researched" and ("~" .. text) or text
end

local function salvageColumn(pe, id, label, field)
	return {
		id = id, label = label, justifyH = "RIGHT", width = 100, sortable = true, defaultSort = "desc",
		sortValue = function(row) return row[field] end,
		getText = function(row) return estimateText(pe, row[field], row.basis) end,
	}
end

-- "Armor · item level 29 · Uncommon": what a disenchant yield depends on. nil for ore and herbs.
local function kindText(row)
	local input = row.input
	if not (input and input.itemLevel) then
		return nil
	end
	return table.concat({
		input.isWeapon and L["Weapon"] or L["Armor"],
		string.format(L["item level %d"], input.itemLevel),
		_G["ITEM_QUALITY" .. tostring(input.quality) .. "_DESC"] or "",
	}, " · ")
end

local function itemColumn(pe)
	return pe:ItemColumn({ width = 200, minWidth = 140, flex = 1, getDetail = kindText })
end

-- "75% · 1–2 Soul Dust" for a researched chance, "75% · 1.6 Soul Dust" for a counted one, and
-- "1.13 × Soul Dust" when only the average is known.
local function materialText(pe, itemID, average, chance)
	local name = pe:GetItemDisplayName(itemID)
	if not chance then
		return string.format("%.2f × %s", average, name)
	end
	local count = chance.min and (chance.min == chance.max and tostring(chance.min) or (chance.min .. "–" .. chance.max))
		or string.format("%.1f", chance.each)
	return string.format("%s · %s %s", pe:FormatPercent(chance.chance), count, name)
end

-- A yield's materials, `{ itemID, average, chance }`, the most likely first (the largest average
-- when chances are not known).
local function materialsByLikelihood(yield)
	local materials = {}
	for itemID, average in pairs(yield.perInput) do
		local chance = yield.chances and yield.chances[itemID]
		materials[#materials + 1] = { itemID = itemID, average = average, chance = chance, order = chance and chance.chance or average }
	end
	table.sort(materials, function(a, b) return a.order > b.order end)
	return materials
end

--- What one destroy of the row's item gives, as key-value rows: one per material, the most likely
--- first, with what it is worth on average; nil when no yield is known.
local function yieldRows(pe, row, action)
	local yield = row.input and pe:GetSalvageYield(action, row.input)
	if not yield then
		return nil, nil
	end
	local rows = {}
	for _, material in ipairs(materialsByLikelihood(yield)) do
		local each = pe:GetSalvagedItemValue(material.itemID)
		rows[#rows + 1] = { materialText(pe, material.itemID, material.average, material.chance),
			each and money(pe, each * material.average) or L["no price"] }
	end
	return rows, yield
end

--- Where the yield comes from, in one sentence for the side pane and tooltip.
local function yieldSource(pe, yield)
	if yield.basis == "researched" then
		return string.format(L["Researched chances for this kind of gear. Counted results take over after %d of your own disenchants of it (you have %d)."],
			pe.SalvageLogic.TRUSTED_CASTS, yield.ownCasts or 0)
	end
	return string.format(L["From %d counted disenchants of this kind of gear."], yield.casts or 0)
end

local function tooltipPairs(pe, row, action)
	local rows, yield = yieldRows(pe, row, action)
	if not rows then
		return {}
	end
	table.insert(rows, 1, { string.format(L["%s one"], ACTION_LABEL[action]), estimateText(pe, row.salvage or row.value, row.basis) })
	rows[#rows + 1] = { yield.basis == "researched" and L["Researched"] or string.format(L["%d counted"], yield.casts or 0), "" }
	return rows
end

-- ---------- Owned: what the characters hold ----------

local function useLabel(row, action)
	return USE_LABEL[row.bestUse] or ACTION_LABEL[action]
end

local owned = {
	id = "owned", label = L["Owned"], sortKey = "gain", hideRowsWhenNone = false,
	emptyTitle = L["Nothing to destroy"],
	emptyHint = L["None of the items your characters hold has a known value when destroyed. Log in on each character once so its bags are known."],
	selectHint = L["Click a row to compare selling and destroying it."],
}

function owned.getRows(pe, action)
	return pe:GetSalvageHoldingRows(action)
end

function owned.columns(pe, action)
	return {
		itemColumn(pe),
		{
			id = "holder", label = L["Held by"], width = 110, sortable = true, defaultSort = "asc",
			sortValue = function(row) return row.characterName .. row.where end,
			getText = function(row) return row.characterName .. (row.where == "bank" and (" · " .. L["bank"]) or "") end,
		},
		pe:NumberColumn({ id = "count", label = L["Qty"], width = 36, format = tostring }),
		{
			id = "auction", label = L["Auction"], justifyH = "RIGHT", width = 84, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.auction or -1 end,
			getText = function(row) return row.bound and pe:Colorize(L["bound"], "textMuted") or money(pe, row.auction) end,
		},
		pe:MoneyColumn({ id = "vendor", label = L["Vendor"], width = 78 }),
		salvageColumn(pe, "salvage", ACTION_LABEL[action], "salvage"),
		{
			id = "best", label = L["Best"], width = 76, sortable = true, defaultSort = "asc",
			sortValue = function(row) return useLabel(row, action) end,
			getText = function(row) return pe:Colorize(useLabel(row, action), row.bestUse == "salvage" and "success" or "textPrimary") end,
		},
		pe:MoneyColumn({ id = "gain", label = L["Gain"], width = 90 }),
	}
end

-- The same stack of the same character, so a selection survives a refresh.
function owned.sameRow(a, b)
	return a.itemID == b.itemID and a.characterKey == b.characterKey and a.where == b.where
end

function owned.subtitle(_, row)
	local where = row.where == "bank" and L["bank"] or L["bags"]
	local text = string.format(L["%d in %s's %s"], row.count, row.characterName, where)
	return row.bound and (text .. " · " .. L["soulbound"]) or text
end

-- Who of the player's characters can disenchant the stack: anyone with Enchanting, or only the
-- holder when it is soulbound. Returns the text and its colour.
local function disenchanterText(pe, row)
	local enchanters = pe:GetEnchanters()
	if row.bound then
		for _, enchanter in ipairs(enchanters) do
			if enchanter.characterKey == row.characterKey then
				return string.format(L["%s, Enchanting %d"], enchanter.name, enchanter.skillLevel), "textPrimary"
			end
		end
		return string.format(L["Only %s, who lacks Enchanting"], row.characterName), "warning"
	end
	local names = {}
	for _, enchanter in ipairs(enchanters) do
		names[#names + 1] = string.format("%s %d", enchanter.name, enchanter.skillLevel)
	end
	if #names == 0 then
		return L["None of your characters"], "warning"
	end
	return table.concat(names, ", "), "textPrimary"
end

-- What each use gets for one item, the best first and in green; a use that is not open says why.
function owned.detailRows(pe, row, action)
	local uses = {
		{ ACTION_LABEL[action], row.salvage, estimateText(pe, row.salvage, row.basis), "salvage" },
		{ L["Vendor"], row.vendor, money(pe, row.vendor), "vendor" },
		{ L["Auction, after the cut"], row.auction, row.bound and L["Soulbound, can't be sold"] or money(pe, row.auction), "auction" },
	}
	table.sort(uses, function(a, b) return (a[2] or -1) > (b[2] or -1) end)
	local rows = {}
	for _, use in ipairs(uses) do
		rows[#rows + 1] = { use[1], use[3], use[4] == row.bestUse and "success" or (use[2] and "textPrimary" or "textMuted") }
	end
	rows[#rows + 1] = { string.format(L["Gain for %d over the next best"], row.count), money(pe, row.gain) }
	if action == "disenchant" then
		local text, color = disenchanterText(pe, row)
		rows[#rows + 1] = { L["Who can disenchant it"], text, color }
	end
	return rows
end

function owned.footer(_, rows)
	return L["~ marks a value from researched yields · other characters as of their last login"], string.format(L["%d items"], #rows)
end

-- ---------- Below disenchant value: gear to buy and disenchant ----------

local buy = {
	id = "buy", label = L["Below disenchant value"], sortKey = "gain", hideRowsWhenNone = true, canSearch = true,
	emptyTitle = L["Nothing below its disenchant value"],
	emptyHint = L["No gear in the last scan is listed below what disenchanting it gives, less the margin."],
	selectHint = L["Click a row to see what buying and disenchanting it gives. Right-click searches the auction house."],
}

function buy.getRows(pe, _, onReady)
	return pe:GetSalvageBuyRows(onReady)
end

function buy.columns(pe)
	return {
		itemColumn(pe),
		pe:MoneyColumn({ id = "price", label = L["Buyout"], width = 90 }),
		salvageColumn(pe, "value", L["Disenchant"], "value"),
		pe:MoneyColumn({ id = "gain", label = L["Gain"], width = 100 }),
		pe:PercentColumn({ id = "gainShare", label = L["Gain %"], width = 56 }),
		pe:NumberColumn({ id = "quantity", label = L["Listed"], width = 50, format = tostring }),
	}
end

function buy.sameRow(a, b)
	return a.itemID == b.itemID
end

function buy.subtitle(_, row)
	return kindText(row) or ""
end

function buy.detailRows(pe, row)
	local margin = pe:GetSalvageBuyMargin()
	return {
		{ L["Cheapest buyout"], money(pe, row.price) },
		{ L["One disenchant, on average"], estimateText(pe, row.value, row.basis) },
		{ string.format(L["Worth paying up to, keeping %s"], pe:FormatPercent(margin)), money(pe, row.limit) },
		{ L["Gain each"], money(pe, row.value - row.price) .. " · " .. pe:FormatPercent((row.value - row.price) / row.price), "success" },
		{ L["Listed below that price"], tostring(row.quantity) },
		{ string.format(L["Gain for all %d"], row.quantity), money(pe, row.gain), "success" },
	}
end

function buy.footer(pe, rows)
	return L["~ marks a value from researched yields"],
		string.format(L["%d items · keeping %s back"], #rows, pe:FormatPercent(pe:GetSalvageBuyMargin()))
end

owned.tooltipPairs, buy.tooltipPairs = tooltipPairs, tooltipPairs

Tradewright.SalvageViews = { owned, buy }
Tradewright.SalvageActionLabel = ACTION_LABEL
--- What one destroy gives and where that comes from, for the side pane: see yieldRows and yieldSource.
Tradewright.SalvageYield = { rows = yieldRows, source = yieldSource }
