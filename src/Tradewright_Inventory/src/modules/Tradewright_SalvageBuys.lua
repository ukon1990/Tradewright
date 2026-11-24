local _, Tradewright = ...

-- Gear in the last scan listed below what disenchanting it gives: the "Below disenchant value" view
-- of the Destroying tab. It needs the scan (AuctionData) and the yields (Professions), so it lives in
-- this module, which loads after both.

local SalvageLogic = Tradewright.SalvageLogic

-- Share of the value kept back by default, for prices that move and yields that vary.
local DEFAULT_MARGIN = 0.15
-- Item info loads on demand: rebuild at most this often to pick up gear whose level was not known yet.
local REBUILD_SEC = 30

--- The share of the disenchant value a buy must stay under, from Settings (0.15 = 15%).
function Tradewright:GetSalvageBuyMargin()
	return tonumber(self:GetSetting("salvage.buyMargin", DEFAULT_MARGIN)) or DEFAULT_MARGIN
end

-- Every scanned item that disenchants to a known value, ready for SalvageLogic.BuyBelowValue.
local function buyCandidates(pe, insights)
	local items = {}
	for itemID, scanned in pairs(insights.byItemID or {}) do
		local input = pe:GetSalvageInput("disenchant", itemID)
		local worth = input and pe:GetSalvageValue("disenchant", input)
		if worth then
			items[#items + 1] = {
				itemID = itemID, storageKey = scanned.storageKey, price = scanned.price, steps = pe:GetPriceSteps(itemID),
				value = worth.value, basis = worth.basis, casts = worth.casts, input = input,
			}
		end
	end
	return items
end

--- Scanned gear listed below its disenchant value less the margin: `rows, check`, or nil while the
--- market insights are being built (`onReady` fires once they are). Rows are
--- SalvageLogic.BuyBelowValue rows with `basis` and `casts` of the yield. `check` is
--- CheckSalvageValues over every scanned item with a disenchant value, so it judges the data the
--- search rests on, not only the rows that passed.
function Tradewright:GetSalvageBuyRows(onReady)
	local insights = self:GetMarketInsights(onReady)
	if not insights then
		return nil
	end
	local state = self:GetState()
	local margin = self:GetSalvageBuyMargin()
	local revision = table.concat({ insights.builtAt or 0, margin, math.floor(self:Now() / REBUILD_SEC) }, ":")
	if state.salvageBuyRevision ~= revision then
		local candidates, inputs = buyCandidates(self, insights), {}
		for _, candidate in ipairs(candidates) do
			inputs[#inputs + 1] = candidate.input
		end
		state.salvageBuyRows = SalvageLogic.BuyBelowValue(candidates, margin)
		state.salvageBuyCheck = self:CheckSalvageValues("disenchant", inputs)
		state.salvageBuyRevision = revision
	end
	return state.salvageBuyRows, state.salvageBuyCheck
end
