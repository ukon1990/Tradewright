local _, Tradewright = ...

-- Salvage sightings: each time the player disenchants, prospects or mills, what was destroyed and
-- what came of it is written to the sightings store, so the pack learns the yields (see
-- Tradewright_SalvageLogic.lua). The outcome is read from the bags: the item counts when the cast
-- starts against the counts once the results are in. Only watches; it casts nothing.

local SalvageLogic = Tradewright.SalvageLogic

-- Disenchant is one spell on both clients.
local ACTION_BY_SPELL = { [13262] = "disenchant" }
-- Prospecting and Milling exist on retail only, as salvage recipes of Jewelcrafting and Inscription.
local ACTION_BY_PROFESSION = SalvageLogic.ACTION_BY_PROFESSION
local WEAPON_CLASS, ARMOR_CLASS = 2, 4
-- Results reach the bags in more than one step (the item goes, then the loot arrives); the bags are
-- read this long after the last change.
local SETTLE_SEC = 0.5
-- A watch with no outcome after this long is dropped: the loot was left, or the bags were full.
local WATCH_SEC = 20

-- The casts being watched: `{ action, before = item counts, casts = finished casts, startedAt }`, or nil.
local watch
-- Whether a salvage cast has started and not yet finished or stopped.
local castUnderWay = false
local lootWindowOpen = false
local settleQueued = false
local actionBySpell = {}

-- The action a retail salvage recipe stands for, or false.
local function recipeAction(spellID)
	local api = C_TradeSkillUI
	local info = Tradewright.IS_RETAIL and api and api.GetRecipeInfo and api.GetRecipeInfo(spellID)
	if not (info and info.isSalvageRecipe and api.GetTradeSkillLineForRecipe) then
		return false
	end
	local skillLineID, _, parentSkillLineID = api.GetTradeSkillLineForRecipe(spellID)
	return ACTION_BY_PROFESSION[parentSkillLineID or skillLineID] or false
end

-- "disenchant", "prospect" or "mill" for a salvage spell, nil for any other. Remembered per spell,
-- as every spell the player casts is asked about.
local function actionOfSpell(spellID)
	if actionBySpell[spellID] == nil then
		actionBySpell[spellID] = ACTION_BY_SPELL[spellID] or recipeAction(spellID)
	end
	return actionBySpell[spellID] or nil
end

local function bagCounts(pe)
	local counts = {}
	pe:ForEachBagSlot(nil, function(_, _, info)
		if info and info.itemID then
			counts[info.itemID] = (counts[info.itemID] or 0) + (tonumber(info.stackCount) or 1)
		end
	end)
	return counts
end

--- How the yield records name an item for `action` (see SalvageLogic): the item itself for ore and
--- herbs; for gear its expansion, quality, item level and whether it is a weapon. nil for something
--- that cannot be disenchanted, or while the game has not loaded the item.
function Tradewright:GetSalvageInput(action, itemID)
	if action ~= "disenchant" then
		return { itemID = itemID }
	end
	local item = self:ItemDescriptorFromID(itemID)
	if not (item and item.quality and item.itemLevel and (item.classID == WEAPON_CLASS or item.classID == ARMOR_CLASS)) then
		return nil
	end
	return { expansionID = item.expansionID or 0, quality = item.quality, itemLevel = item.itemLevel, isWeapon = item.classID == WEAPON_CLASS }
end

local function newWatch(action, before)
	return { action = action, before = before, casts = 0, startedAt = GetTime() }
end

-- Records the watched casts when the bags show their outcome. Returns whether they did.
local function settle(pe)
	local now = bagCounts(pe)
	local change = watch and watch.casts > 0 and SalvageLogic.OutcomeBetween(watch.before, now)
	if not change then
		return false
	end
	local input = pe:GetSalvageInput(watch.action, change.inputItemID)
	if input then
		pe:RecordSalvageOutcome(watch.action, { input = input, inputCount = change.inputCount, results = change.results, casts = watch.casts })
	end
	-- A cast still under way is watched from the bags as they are now.
	watch = castUnderWay and newWatch(watch.action, now) or nil
	return true
end

local function settleSoon()
	if settleQueued or not watch then
		return
	end
	settleQueued = true
	C_Timer.After(SETTLE_SEC, function()
		settleQueued = false
		if watch and not lootWindowOpen and not settle(Tradewright) and GetTime() - watch.startedAt > WATCH_SEC then
			watch = nil
		end
	end)
end

-- Whether the watch can take one more cast of `action`: same action, not gone stale, and holding
-- finished casts whose results are still to come.
local function watchTakes(action)
	return watch ~= nil and watch.action == action and watch.casts > 0 and GetTime() - watch.startedAt <= WATCH_SEC
end

-- A salvage cast begins. Casts made back to back (a queued batch of prospects) share one watch while
-- the results of the one before are not in the bags yet; they are then recorded together.
local function onCastStart(pe, action)
	castUnderWay = false
	if not watchTakes(action) then
		watch = nil
	elseif settle(pe) then
		watch = nil
	end
	watch = watch or newWatch(action, bagCounts(pe))
	watch.startedAt = GetTime()
	castUnderWay = true
end

local function onCastSucceeded(pe, action)
	if not (watch and watch.action == action) then
		-- No start was seen (a cast without a cast time): the bags are still as before the outcome.
		onCastStart(pe, action)
	end
	castUnderWay = false
	watch.casts = watch.casts + 1
	settleSoon()
end

-- A cast that did not finish. The watch stays only for earlier casts still waiting for results.
local function onCastStopped()
	castUnderWay = false
	if watch and watch.casts == 0 then
		watch = nil
	end
end

local CAST_HANDLERS = {
	UNIT_SPELLCAST_START = onCastStart,
	UNIT_SPELLCAST_SUCCEEDED = onCastSucceeded,
	UNIT_SPELLCAST_INTERRUPTED = onCastStopped,
	UNIT_SPELLCAST_FAILED = onCastStopped,
}

local function onEvent(_, event, unit, _, spellID)
	local onCast = CAST_HANDLERS[event]
	if onCast then
		local action = unit == "player" and Tradewright.db and actionOfSpell(spellID)
		if action then
			onCast(Tradewright, action)
		end
	elseif event == "LOOT_OPENED" then
		lootWindowOpen = true
	else
		lootWindowOpen = event ~= "LOOT_CLOSED" and lootWindowOpen
		settleSoon()
	end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", onEvent)
-- pcall: an event name the client does not know raises an error.
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
	"LOOT_OPENED", "LOOT_CLOSED", "BAG_UPDATE_DELAYED" }) do
	pcall(frame.RegisterEvent, frame, event)
end
