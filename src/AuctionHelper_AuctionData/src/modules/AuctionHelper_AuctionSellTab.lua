-- The sell tab's rows: columns, class and subclass filters, the row filter and priming rows when the panel opens.
local _, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local containsText = shared.containsText
local flagText = shared.flagText
local formatPercent = shared.formatPercent

-- Rows can be empty right after the AH opens (bag info not in yet): try again a few times.
local PRIME_ROWS_RETRY_SEC = 0.2
local PRIME_ROWS_MAX_ATTEMPTS = 6

function AuctionHelper:GetAuctionClassFilterOptions(rows)
	local seen = {}
	local options = {
		{ value = "all", label = "All classes" },
	}
	for _, row in ipairs(rows or {}) do
		local label = tostring(row and row.itemClassLabel or "")
		if label ~= "" and not seen[label] then
			seen[label] = true
			options[#options + 1] = {
				value = label,
				label = label,
			}
		end
	end
	table.sort(options, function(left, right)
		if left.value == "all" then
			return true
		end
		if right.value == "all" then
			return false
		end
		return tostring(left.label) < tostring(right.label)
	end)
	return options
end

function AuctionHelper:GetAuctionSubclassFilterOptions(rows, classSelection)
	local seen = {}
	local options = {
		{ value = "all", label = "All subclasses" },
	}
	for _, row in ipairs(rows or {}) do
		local classLabel = tostring(row and row.itemClassLabel or "")
		local subclassLabel = tostring(row and row.itemSubclassLabel or "")
		local classMatches = self:IsFilterSelectionEmpty(classSelection) or classSelection[classLabel] == true
		if classMatches and subclassLabel ~= "" and not seen[subclassLabel] then
			seen[subclassLabel] = true
			options[#options + 1] = {
				value = subclassLabel,
				label = subclassLabel,
			}
		end
	end
	table.sort(options, function(left, right)
		if left.value == "all" then
			return true
		end
		if right.value == "all" then
			return false
		end
		return tostring(left.label) < tostring(right.label)
	end)
	return options
end

local function rankMarkup(rankIndex)
	return AuctionHelper:GetRankMarkup(rankIndex)
end

function AuctionHelper:BuildAuctionPanelColumns()
	local pe = self
	return {
		self:CreateItemColumn({
			id = "itemRecipe",
			label = "Item",
			defaultSort = "asc",
			minWidth = 120,
			getItemID = function(row) return row and row.itemID end,
			getIcon = function(row) return row and row.itemIcon end,
			getName = function(row)
				local marker = (row and row._isScanning) and "› " or ""
				return marker .. tostring(row and row.itemName or "-") .. rankMarkup(row and row.qualityIndex)
			end,
			sortValue = function(row) return row and row.itemName end,
		}),
		{
			id = "quantityOwned", label = "Qty", justifyH = "RIGHT", width = 58, sortable = true, defaultSort = "desc",
			tooltipTitle = "Quantity", tooltipText = "Sellable / owned when a keep rule holds some back.",
			sortValue = function(row) return tonumber(row and row.quantityOwned) or 0 end,
			getText = function(row)
				local owned = pe:FormatNumberGrouped(row and row.quantityOwned or 0)
				if row and row.isIgnoredByRule then
					return "0/" .. owned
				end
				if (tonumber(row and row.reserveQty) or 0) > 0 then
					return pe:FormatNumberGrouped(tonumber(row.quantitySellable) or 0) .. "/" .. owned
				end
				return owned
			end,
		},
		{
			id = "currentPrice", label = "Price", justifyH = "RIGHT", width = 84, sortable = true, defaultSort = "desc",
			tooltipTitle = "Price", tooltipText = "Live lowest buyout. Grey when it comes from an older scan or another addon.",
			sortValue = function(row) return tonumber(row and row.currentPrice) or -1 end,
			getText = function(row)
				if not row or not row.currentPrice then
					return "-"
				end
				local text = pe:FormatCopperShort(row.currentPrice)
				if row.currentPriceIsNative ~= true then
					return pe:Colorize(text, "textMuted")
				end
				return text
			end,
		},
		{
			id = "lastAuctionScan", label = "Scan", justifyH = "RIGHT", width = 60, sortable = true, defaultSort = "desc", optional = true,
			tooltipTitle = "Last scanned",
			sortValue = function(row) return tonumber(row and row.lastAuctionScanAtTs) or 0 end,
			getText = function(row) return row and row.auctionScanAgeDisplay or "never" end,
		},
		{
			id = "potentialROI", label = "ROI", justifyH = "RIGHT", width = 46, sortable = true, defaultSort = "desc",
			tooltipTitle = "Return", tooltipText = "Profit over material cost for crafted items.",
			sortValue = function(row) return tonumber(row and row.potentialROI) or -9999 end,
			getText = function(row) return formatPercent(row and row.potentialROI) end,
		},
		{
			id = "personalSaleRate", label = "Sold", justifyH = "RIGHT", width = 44, sortable = true, defaultSort = "desc", optional = true,
			tooltipTitle = "Your sale rate", tooltipText = "Share of your own past listings of this item that sold.",
			sortValue = function(row) return tonumber(row and row.personalSaleRateValue) or -1 end,
			getText = function(row) return row and row.personalSaleRateDisplay or "-" end,
		},
		{
			id = "dumpAlert", label = "Flag", width = 64, sortable = true, defaultSort = "desc",
			tooltipTitle = "Flag", tooltipText = "Keep and Ignore rules, and prices that look dumped.",
			sortValue = function(row)
				return (row and row.isDumpedLow and 4 or 0) + (row and row.isIgnoredByRule and 2 or 0) + ((tonumber(row and row.reserveQty) or 0) > 0 and 1 or 0)
			end,
			getText = function(row)
				if not row then
					return ""
				end
				if row.isDumpedLow then
					return flagText(pe, "Low", "warning")
				end
				if row.isIgnoredByRule then
					return flagText(pe, "Ignored", "textMuted")
				end
				if (tonumber(row.reserveQty) or 0) > 0 then
					return flagText(pe, "Keep " .. tostring(row.reserveQty), "gold")
				end
				return ""
			end,
		},
	}
end

function AuctionHelper:FilterAuctionPanelRows(rows)
	self.ui = self.ui or {}
	local ui = self.ui
	local text = string.lower(tostring(ui.ahFilterText or ""))
	local craftedOnly = ui.ahCraftedOnly == true
	local profitableOnly = ui.ahProfitableOnly == true
	local classSelection = ui.ahClassFilterValues or {}
	local subclassSelection = ui.ahSubclassFilterValues or {}
	local expSel = ui.ahExpansionFilterValues or {}
	local showAllExpansions = self:IsFilterSelectionEmpty(expSel)
	local out = {}
	for _, row in ipairs(rows or {}) do
		local keep = true
		if text ~= "" then
			keep = containsText(row.itemName, text) or containsText(row.itemID, text)
		end
		if keep and craftedOnly then
			keep = row.potentialROI ~= nil
		end
		if keep and profitableOnly then
			keep = tonumber(row.potentialROI) and tonumber(row.potentialROI) > 0
		end
		if keep and not self:IsFilterSelectionEmpty(classSelection) then
			keep = classSelection[tostring(row.itemClassLabel or "")] == true
		end
		if keep and not self:IsFilterSelectionEmpty(subclassSelection) then
			keep = subclassSelection[tostring(row.itemSubclassLabel or "")] == true
		end
		if keep and not showAllExpansions then
			local desc = row.itemID and self:ResolveItemDescriptor(row.itemID) or nil
			local expTag = self:ExpansionLeToFilterTag(desc and desc.expansionID) or "legacy"
			keep = expSel[expTag] == true
		end
		if keep then
			out[#out + 1] = row
		end
	end
	return out
end

function AuctionHelper:PrimeAuctionPanelRows()
	local state = self:GetState()
	local bagState = self:GetAuctionOwnedBagState(true)
	if type(state.auctionPanelRows) == "table"
		and state.auctionPanelRowsViewRevision == state.auctionViewRevision
		and state.auctionPanelRowsBagSignature == bagState.signature then
		return state.auctionPanelRows
	end
	state.auctionPanelRows = self:BuildAuctionInventoryRows({
		includeCraftEstimates = false,
		bagState = bagState,
	})
	state.auctionPanelRowsViewRevision = state.auctionViewRevision
	state.auctionPanelRowsBagSignature = bagState.signature
	return state.auctionPanelRows
end

function AuctionHelper:RetryPrimeAuctionPanelRows(attempt)
	attempt = tonumber(attempt) or 1
	local state = self:GetState()
	local rows = (state and state.auctionPanelRows) or {}
	if type(rows) == "table" and #rows > 0 then
		return
	end
	if attempt > PRIME_ROWS_MAX_ATTEMPTS then
		return
	end
	C_Timer.After(PRIME_ROWS_RETRY_SEC, function()
		AuctionHelper:PrimeAuctionPanelRows()
		AuctionHelper:RefreshAuctionHousePanel()
		AuctionHelper:RetryPrimeAuctionPanelRows(attempt + 1)
	end)
end
