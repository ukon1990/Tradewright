local _, Tradewright = ...

-- What the items the player's characters own are worth destroyed, next to selling them: the rows
-- of the Destroying tab. Reads the holdings every character saved when last played
-- (Tradewright_Holdings.lua), so other characters' items are as of their last login.

local SalvageLogic = Tradewright.SalvageLogic

local ENCHANTING = 333 -- skill line
-- The actions and the profession (skill line) each takes. Prospecting and milling are retail only:
-- Forever has no Jewelcrafting or Inscription.
local ACTIONS = {
	{ action = "disenchant", skillLineID = ENCHANTING },
	{ action = "prospect", skillLineID = 755, retailOnly = true },
	{ action = "mill", skillLineID = 773, retailOnly = true },
}
local PLACES = { "bags", "bank" }

--- The actions the Destroying tab offers: disenchanting always, since its values need no enchanter
--- of the player's; prospecting and milling on retail once one of the characters has the profession.
function Tradewright:GetSalvageActions()
	local actions = {}
	for _, entry in ipairs(ACTIONS) do
		if not entry.retailOnly or (self.IS_RETAIL and self:SomeCharacterHasProfession(entry.skillLineID)) then
			actions[#actions + 1] = entry.action
		end
	end
	return actions
end

--- The player's characters with Enchanting, as their last profession scan saved them:
--- `{ { characterKey, name, skillLevel } }`, the highest skill first.
function Tradewright:GetEnchanters()
	local enchanters = {}
	for characterKey, character in pairs(self.db and self.db.characters or {}) do
		local profession = character.professions and character.professions[tostring(ENCHANTING)]
		if profession then
			enchanters[#enchanters + 1] = {
				characterKey = characterKey, name = character.meta and character.meta.name or characterKey,
				skillLevel = tonumber(profession.skillLevel) or 0,
			}
		end
	end
	table.sort(enchanters, function(a, b)
		if a.skillLevel ~= b.skillLevel then
			return a.skillLevel > b.skillLevel
		end
		return a.name < b.name
	end)
	return enchanters
end

-- Every stack a character holds, as `{ itemID, count, where, characterKey, characterName, bound }`.
-- Only banked copies are known to be soulbound (see Tradewright_Holdings.lua); a stack counts as
-- bound when all its copies are.
local function eachHeldStack(pe, visit)
	for characterKey, held in pairs(pe:GetItemHoldings()) do
		for _, where in ipairs(PLACES) do
			for itemID, count in pairs(held[where] or {}) do
				local boundCount = where == "bank" and held.boundInBank and held.boundInBank[itemID] or 0
				visit({
					itemID = tonumber(itemID), count = count, where = where, characterKey = characterKey,
					characterName = held.name or characterKey, bound = boundCount >= count,
				})
			end
		end
	end
end

-- What one item fetches at the auction house after the cut, nil when it cannot be sold there.
local function auctionValue(pe, stack)
	if stack.bound or not pe:IsItemLikelyTradeableOnAuctionByStaticInfo(stack.itemID) then
		return nil
	end
	local price = pe:GetMarketEstimateCopper(stack.itemID)
	return price and price > 0 and pe:ApplyAhCutToSaleCopper(price) or nil
end

-- A row for one held stack, or nil when destroying it has no known value.
local function salvageRow(pe, action, stack)
	local input = pe:GetSalvageInput(action, stack.itemID)
	local worth = input and pe:GetSalvageValue(action, input)
	if not worth then
		return nil
	end
	local vendor = pe:GetItemVendorSellCopper(stack.itemID)
	stack.input, stack.salvage, stack.basis, stack.casts = input, worth.value, worth.basis, worth.casts
	stack.vendor = vendor and vendor > 0 and vendor or nil
	stack.auction = auctionValue(pe, stack)
	local use, gain = SalvageLogic.BestUse({ vendor = stack.vendor, auction = stack.auction, salvage = stack.salvage })
	stack.bestUse, stack.gain = use, gain * stack.count
	return stack
end

--- The owned items `action` can destroy with a known value, one row per character and place:
--- `rows, check`. A row is `{ itemID, count, where = "bags" | "bank", characterKey, characterName,
--- bound, salvage, basis, casts, vendor, auction, bestUse, gain }`: values per item in copper (nil
--- when that use is not open), `bestUse` "vendor", "auction" or "salvage", and `gain` what the best
--- use gets for the whole stack over the next best. `check` is CheckSalvageValues over the rows.
function Tradewright:GetSalvageHoldingRows(action)
	local rows, inputs = {}, {}
	eachHeldStack(self, function(stack)
		local row = salvageRow(self, action, stack)
		if row then
			rows[#rows + 1] = row
			inputs[#inputs + 1] = row.input
		end
	end)
	return rows, self:CheckSalvageValues(action, inputs)
end
