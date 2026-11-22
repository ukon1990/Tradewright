local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Inventory table columns: their definitions, the saved column order and which columns are shown.

-- Fixed column widths: money columns fit a short amount such as "1,240[g] 35[s]".
local COL = {
	qty = 52,
	holders = 170,
	loc = 92,
	currentAh = 86,
	lastSeen = 86,
	avgSeen = 86,
	avgCraft = 86,
	lastCraft = 86,
	profitUnit = 90,
	profitStack = 90,
	seenAt = 56,
	sellsPerDay = 66,
}
local MONEY_MIN_WIDTH = 56

-- -1, 0 or 1 comparing (a, b, c) triples in order; missing numbers count as 0.
local function compareTriple(left, right)
	for index = 1, 3 do
		local a, b = tonumber(left[index]) or 0, tonumber(right[index]) or 0
		if a ~= b then
			return a < b and -1 or 1
		end
	end
	return 0
end

-- "Bånkey 30, Alt 10": who holds the item (bags + bank), most first.
local function holdersText(pe, row)
	local parts = {}
	for _, holder in ipairs(row.holders or {}) do
		parts[#parts + 1] = pe:GetCharacterNameMarkup(holder.key) .. " " .. pe:Colorize(pe:FormatNumberGrouped(holder.count), "textMuted")
	end
	return #parts > 0 and table.concat(parts, ", ") or "-"
end

local function storedText(pe, row)
	local text = pe:FormatNumberGrouped(row.bags or 0) .. " / " .. pe:FormatNumberGrouped(row.bank or 0)
	if pe.IS_RETAIL and (row.warband or 0) > 0 then
		text = text .. " / " .. pe:FormatNumberGrouped(row.warband)
	end
	return text
end

-- Estimated units sold per day at the auction house, or nil when the scans do not say (or the
-- AuctionData module is not loaded).
local function sellsPerDay(pe, row)
	if not pe.GetItemPriceSignals then
		return nil
	end
	local _, sells = pe:GetItemPriceSignals(row.itemID)
	return sells and sells.perDay
end

local function sellsPerDayColumn(pe)
	return {
		id = "sellsPerDay", label = L["Sales a day"], optional = true, justifyH = "RIGHT", width = COL.sellsPerDay, minWidth = 56, flex = 0,
		sortable = true, defaultSort = "desc", defaultVisible = false,
		tooltipTitle = L["Sales a day, estimated"],
		tooltipText = L["From how the listed quantity changes between your scans. It runs high: cancelled and expired auctions count too."],
		sortValue = function(row) return sellsPerDay(pe, row) or -1 end,
		getText = function(row)
			local perDay = sellsPerDay(pe, row)
			return perDay and string.format(perDay >= 10 and "%.0f" or "%.1f", perDay) or "-"
		end,
	}
end

-- An optional copper column that never shrinks below MONEY_MIN_WIDTH.
local MONEY_COLUMN_TIPS = {
	currentAh = L["Lowest price in your latest auction house scan."],
	lastSeen = L["The latest price seen in the chosen time range."],
	avgSeen = L["Average of the prices seen in the chosen time range."],
	avgCraft = L["Average reagent cost to craft one, in the chosen time range."],
	lastCraft = L["Reagent cost to craft one at the latest prices."],
	profitUnit = L["What one earns after the auction cut, minus its craft cost."],
	profitStack = L["Profit each, times the quantity you own."],
}

function Tradewright:InventoryMoneyColumn(id, label, field, defaultVisible)
	local column = self:MoneyColumn({ id = id, label = label, field = field, optional = true, width = COL[id] })
	column.tooltipTitle, column.tooltipText = label, MONEY_COLUMN_TIPS[id]
	column.minWidth = MONEY_MIN_WIDTH
	column.flex = 0
	column.defaultVisible = defaultVisible
	return column
end

function Tradewright:InventoryStockColumns()
	local pe = self
	return {
		pe:CreateItemColumn({
			label = L["Item"],
			defaultSort = "asc",
			getItemID = function(row) return row.itemID end,
			getName = function(row) return pe:GetItemDisplayName(row.itemID) .. pe:GetRankMarkup(row.rankIndex) end,
			getIcon = function(row) return row.icon end,
			sortValue = function(row) return row.name or "" end,
		}),
		{
			id = "qty", label = L["Qty"], justifyH = "RIGHT", width = COL.qty, minWidth = 40, flex = 0,
			sortable = true, defaultSort = "desc", defaultVisible = true,
			tooltipTitle = L["Qty"],
			tooltipText = L["How many you can sell. Soulbound copies and the ones you wear are left out; hover a row for everything you hold."],
			sortValue = function(row) return row.sellable or 0 end,
			getText = function(row) return pe:FormatNumberGrouped(row.sellable or 0) end,
		},
		{
			id = "holders", label = L["Characters"], optional = true,
			dropFirst = true, -- first column to go when the window is narrow
			tooltipTitle = L["Characters"],
			tooltipText = L["Who holds the item in bags and bank, most first. Hover a row for the full list."],
			width = COL.holders, minWidth = 100, flex = 0, sortable = true, defaultSort = "desc", defaultVisible = true,
			sortValue = function(row) return #(row.holders or {}) end,
			getText = function(row) return holdersText(pe, row) end,
		},
		{
			id = "loc", label = L["Bags / bank"], optional = true, justifyH = "RIGHT", width = COL.loc, minWidth = 56, flex = 0,
			sortable = true, defaultSort = "desc", defaultVisible = false,
			compare = function(left, right)
				return compareTriple({ left.bags, left.bank, left.warband }, { right.bags, right.bank, right.warband })
			end,
			getText = function(row) return storedText(pe, row) end,
		},
	}
end

function Tradewright:InventoryMarketColumns()
	local pe = self
	return {
		pe:InventoryMoneyColumn("currentAh", L["Current AH"], "currentAhCopper", true),
		pe:InventoryMoneyColumn("lastSeen", L["Last AH"], "lastObservedPrice", false),
		pe:InventoryMoneyColumn("avgSeen", L["Avg AH"], "avgObservedPrice", false),
		pe:InventoryMoneyColumn("avgCraft", L["Avg craft"], "avgCraftCost", true),
		pe:InventoryMoneyColumn("lastCraft", L["Last craft"], "lastCraftCost", false),
		pe:InventoryMoneyColumn("profitUnit", L["Profit each"], "profitCopperPerUnit", true),
		pe:InventoryMoneyColumn("profitStack", L["Profit, all"], "profitCopperStack", false),
		sellsPerDayColumn(pe),
		{
			id = "seenAt", label = L["Seen"], optional = true, justifyH = "RIGHT", width = COL.seenAt, minWidth = 88, flex = 0,
			sortable = true, defaultSort = "desc", defaultVisible = false,
			sortValue = function(row) return row.currentAhAt or 0 end,
			getText = function(row) return pe:FormatShortTime(row.currentAhAt) end,
		},
	}
end

function Tradewright:GetInventoryColumnDefinitions()
	local columns = self:InventoryStockColumns()
	for _, column in ipairs(self:InventoryMarketColumns()) do
		columns[#columns + 1] = column
	end
	return columns
end

-- The saved column order, with columns missing from it (new ones) appended in definition order.
function Tradewright:GetInventoryColumnOrder()
	local savedOrder = self:GetSetting("inventory.columnOrder", {})
	local definitions = self:GetInventoryColumnDefinitions()
	local byId = {}
	local ordered = {}
	for _, definition in ipairs(definitions) do
		byId[definition.id] = definition
	end
	for _, columnId in ipairs(savedOrder or {}) do
		if byId[columnId] then
			ordered[#ordered + 1] = byId[columnId]
			byId[columnId] = nil
		end
	end
	for _, definition in ipairs(definitions) do
		if byId[definition.id] then
			ordered[#ordered + 1] = definition
		end
	end
	return ordered
end

function Tradewright:SaveInventoryColumnOrder(columns)
	local order = {}
	for _, column in ipairs(columns or {}) do
		order[#order + 1] = column.id
	end
	self:SetSetting("inventory.columnOrder", order)
end

function Tradewright:GetInventoryColumnDefaultVisible(columnId)
	for _, definition in ipairs(self:GetInventoryColumnDefinitions()) do
		if definition.id == columnId then
			return definition.defaultVisible ~= false
		end
	end
	return true
end

function Tradewright:IsInventoryColumnVisible(columnId)
	local hidden = self:GetSetting("inventory.hiddenColumns", {})
	if hidden[columnId] == nil then
		return self:GetInventoryColumnDefaultVisible(columnId)
	end
	return hidden[columnId] ~= true
end

-- Only a choice that differs from the column's default is saved.
function Tradewright:SetInventoryColumnVisible(columnId, visible)
	local hidden = self:GetSetting("inventory.hiddenColumns", {})
	if visible == self:GetInventoryColumnDefaultVisible(columnId) then
		hidden[columnId] = nil
	else
		hidden[columnId] = not visible
	end
	self:SetSetting("inventory.hiddenColumns", hidden)
end

local function isShown(hidden, definition, context)
	if hidden[definition.id] == true or (hidden[definition.id] == nil and definition.defaultVisible == false) then
		return false
	end
	if type(definition.visible) == "function" then
		return definition.visible(context) ~= false
	end
	return definition.visible ~= false
end

-- Copies of the ordered definitions whose `visible` also honours the saved hidden-column choices.
function Tradewright:BuildInventoryTableColumns()
	local hidden = self:GetSetting("inventory.hiddenColumns", {})
	local columns = {}
	for _, definition in ipairs(self:GetInventoryColumnOrder()) do
		local column = {}
		for key, value in pairs(definition) do
			column[key] = value
		end
		column.visible = function(context)
			return isShown(hidden, definition, context)
		end
		columns[#columns + 1] = column
	end
	return columns
end
