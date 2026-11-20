local ProfessionExporter = select(2, ...)

-- Crafts tab columns for planning (F61): how many of an item sell a day, and how many to make.

-- Sells a day and the restock quantity for one output item, recomputed at most every 10 seconds.
local function planFor(pe, row)
	local itemID = tonumber(row.outputItemID)
	if not itemID then
		return {}
	end
	local state = pe:GetState()
	local stamp = math.floor(time() / 10)
	if state.craftPlanStamp ~= stamp then
		state.craftPlanStamp, state.craftPlans = stamp, {}
	end
	local plan = state.craftPlans[itemID]
	if not plan then
		local _, sells = pe:GetItemPriceSignals(itemID)
		local owned = pe:BuildAccountItemInventoryTotals(itemID).total
		plan = { sellsPerDay = sells and sells.perDay, owned = owned }
		plan.make = pe.MaterialLogic.RestockQuantity({
			sellsPerDay = plan.sellsPerDay, owned = owned, profit = row.profit,
			days = tonumber(pe:GetSetting("crafts.restockDays", 1)) or 1,
		})
		state.craftPlans[itemID] = plan
	end
	return plan
end

-- "12" for a busy item, "0.4" for a slow one.
local function perDayText(pe, perDay)
	if perDay >= 10 then
		return pe:FormatNumberGrouped(math.floor(perDay + 0.5))
	end
	return string.format("%.1f", perDay)
end

--- Append "Sells a day" and "Make" to the Crafts table columns.
function ProfessionExporter:AddCraftPlanningColumns(columns)
	local pe = self
	columns[#columns + 1] = {
		id = "sellsPerDay", label = "Sells a day", justifyH = "RIGHT", width = 66, sortable = true, defaultSort = "desc", optional = true,
		tooltipTitle = "Sells a day, estimated",
		tooltipText = "From how the listed quantity changes between your scans. It runs high: cancelled and expired auctions count too.",
		sortValue = function(row) return planFor(pe, row).sellsPerDay or -1 end,
		getText = function(row)
			local perDay = planFor(pe, row).sellsPerDay
			return perDay and perDayText(pe, perDay) or "-"
		end,
	}
	columns[#columns + 1] = {
		id = "make", label = "Make", justifyH = "RIGHT", width = 46, sortable = true, defaultSort = "desc",
		tooltipTitle = "How many to make",
		tooltipText = "Enough for the chosen days of sales, less what your characters already own. "
			.. "0 when you have enough or the craft loses gold; - when it is not known to sell.",
		sortValue = function(row) return planFor(pe, row).make or -1 end,
		getText = function(row)
			local make = planFor(pe, row).make
			return make and pe:FormatNumberGrouped(make) or "-"
		end,
	}
	return columns
end
