local Tradewright = select(2, ...)

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Crafts tab columns for planning: sales a day, how many to make, and recipe cooldowns.

-- A cooldown recipe can be made once when ready and not at all while waiting.
local COOLDOWN_CAP = { ready = 1, waiting = 0 }

local function cooldownText(pe, cooldown)
	if cooldown.state == "ready" then
		return "Ready"
	elseif cooldown.state == "waiting" then
		return pe.MaterialLogic.FormatCooldown(cooldown.secondsLeft)
	end
	return ""
end

-- Sales a day, restock quantity and cooldown for one craft row, recomputed at most every 10 seconds.
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
	local key = row.rowKey or itemID
	local plan = state.craftPlans[key]
	if not plan then
		local _, sells = pe:GetItemPriceSignals(itemID)
		local owned = pe:BuildAccountItemInventoryTotals(itemID).total
		local cooldown = pe:GetCraftRowCooldown(row)
		plan = { sellsPerDay = sells and sells.perDay, owned = owned, cooldown = cooldown }
		plan.make = pe.MaterialLogic.RestockQuantity({
			sellsPerDay = plan.sellsPerDay, owned = owned, profit = row.profit,
			days = tonumber(pe:GetSetting("crafts.restockDays", 1)) or 1,
			cap = COOLDOWN_CAP[cooldown.state],
		})
		state.craftPlans[key] = plan
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

--- Append "Sales a day", "Make" and "Cooldown" to the Crafts table columns.
function Tradewright:AddCraftPlanningColumns(columns)
	local pe = self
	columns[#columns + 1] = {
		id = "sellsPerDay", label = L["Sales a day"], justifyH = "RIGHT", width = 66, sortable = true, defaultSort = "desc", optional = true,
		tooltipTitle = L["Sales a day, estimated"],
		tooltipText = L["From how the listed quantity changes between your scans. It runs high: cancelled and expired auctions count too."],
		sortValue = function(row) return planFor(pe, row).sellsPerDay or -1 end,
		getText = function(row)
			local perDay = planFor(pe, row).sellsPerDay
			return perDay and perDayText(pe, perDay) or "-"
		end,
	}
	columns[#columns + 1] = {
		id = "make", label = L["Make"], justifyH = "RIGHT", width = 46, sortable = true, defaultSort = "desc",
		tooltipTitle = L["How many to make"],
		tooltipText = L["Enough for the chosen days of sales, less what your characters already own. "]
			.. L["0 when you have enough or the craft loses gold; - when it is not known to sell."],
		sortValue = function(row) return planFor(pe, row).make or -1 end,
		getText = function(row)
			local make = planFor(pe, row).make
			return make and pe:FormatNumberGrouped(make) or "-"
		end,
	}
	columns[#columns + 1] = {
		id = "cooldown", label = L["Cooldown"], justifyH = "RIGHT", width = 96, sortable = true, defaultSort = "asc", optional = true,
		tooltipTitle = L["Cooldown"],
		tooltipText = L["For the best crafter, from the last time that character's profession window was open. "]
			.. L["Empty for recipes that have not been seen on cooldown."],
		sortValue = function(row)
			local cooldown = planFor(pe, row).cooldown
			return cooldown and cooldown.state ~= "none" and cooldown.secondsLeft or 1e15
		end,
		getText = function(row)
			local cooldown = planFor(pe, row).cooldown
			return cooldown and cooldownText(pe, cooldown) or ""
		end,
	}
	return columns
end
