local _, Tradewright = ...

-- Loot sightings: every loot window the player opens is written to the sightings store, so the pack
-- learns which creatures, nodes and fishing waters yield which crafting materials and recipes.
-- Only crafting-relevant items are counted (see SourceLogic.IsTalliedClass). Reads the window only.

local SourceLogic = Tradewright.SourceLogic

-- Skinning, Mining and Herb Gathering. Every rank of a profession's gathering spell carries the same
-- name as these, and names are what the cast event can be matched on across clients.
local GATHER_SPELL_IDS = { 8613, 2575, 2366 }
-- A corpse's loot window that opens this soon after a gathering cast holds what was gathered.
local GATHER_WINDOW_SEC = 3
-- Sources already counted this session. The game reports a window more than once, and a corpse can
-- be opened again; neither is a new loot.
local MAX_REMEMBERED_SOURCES = 5000

local lastGatherAt = 0
local countedSources, countedTotal = {}, 0
local gatherSpellNames

local function spellName(spellID)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellID)
	end
	return GetSpellInfo and (GetSpellInfo(spellID)) or nil
end

local function isGatherSpell(spellID)
	if not gatherSpellNames then
		gatherSpellNames = {}
		for _, id in ipairs(GATHER_SPELL_IDS) do
			local name = spellName(id)
			if name then
				gatherSpellNames[name] = true
			end
		end
	end
	local name = spellName(spellID)
	return name ~= nil and gatherSpellNames[name] == true
end

-- The guids one loot slot came from. GetLootSourceInfo returns guid, quantity pairs.
local function slotSources(slot)
	local guids, info = {}, { GetLootSourceInfo(slot) }
	for index = 1, #info, 2 do
		guids[#guids + 1] = info[index]
	end
	return guids
end

-- The open loot window as SourceLogic.LootBySource reads it. Recipe items found are recorded on the way.
local function readLootSlots(pe)
	local slots = {}
	for slot = 1, GetNumLootItems() or 0 do
		local link = GetLootSlotLink and GetLootSlotLink(slot)
		local itemID = link and tonumber(link:match("item:(%d+)"))
		local classID = itemID and pe:GetItemClassID(itemID)
		if itemID and GetLootSlotInfo then
			pe:RecordRecipeItem(itemID, (select(2, GetLootSlotInfo(slot))), classID)
		end
		slots[#slots + 1] = { itemID = itemID, tallied = SourceLogic.IsTalliedClass(classID), guids = slotSources(slot) }
	end
	return slots
end

-- The creature's name, when the player has it targeted or under the cursor. The loot window does not
-- name what it came from; a later vendor-style sighting of the same creature fills the name in.
local function nameOfCreature(guid)
	for _, unit in ipairs({ "target", "mouseover" }) do
		if UnitGUID(unit) == guid then
			return UnitName(unit)
		end
	end
	return nil
end

-- True the first time a source is seen this session under `kind`.
local function countOnce(kind, guid)
	local key = kind .. guid
	if countedSources[key] then
		return false
	end
	if countedTotal >= MAX_REMEMBERED_SOURCES then
		countedSources, countedTotal = {}, 0
	end
	countedSources[key], countedTotal = true, countedTotal + 1
	return true
end

-- "kill" for a corpse's own loot; "gather" when it follows a gathering cast or the corpse was
-- already looted once; "object" for a node or chest. nil for anything else (an item being opened).
local function lootKind(guid, gathering)
	local sourceKind = SourceLogic.SourceOfGUID(guid)
	if sourceKind == "object" then
		return "object"
	elseif sourceKind == "npc" then
		return (gathering or countedSources["kill" .. guid]) and "gather" or "kill"
	end
	return nil
end

local function recordFishing(pe, bySource)
	local guid, itemIDs = next(bySource)
	local mapID = pe:GetPlayerPlace().mapID
	if guid and mapID and countOnce("fishing", guid) then
		pe:RecordLootSighting({ kind = "fishing", id = mapID, itemIDs = itemIDs })
	end
end

local function recordLootWindow(pe)
	local bySource = SourceLogic.LootBySource(readLootSlots(pe))
	if IsFishingLoot and IsFishingLoot() then
		recordFishing(pe, bySource)
		return
	end
	local gathering = (pe:Now() - lastGatherAt) <= GATHER_WINDOW_SEC
	for guid, itemIDs in pairs(bySource) do
		local kind = lootKind(guid, gathering)
		if kind and countOnce(kind, guid) then
			local _, id = SourceLogic.SourceOfGUID(guid)
			pe:RecordLootSighting({ kind = kind, id = id, name = kind ~= "object" and nameOfCreature(guid) or nil, itemIDs = itemIDs })
		end
	end
end

local frame = CreateFrame("Frame")
-- pcall: an event name the client does not know raises an error. LOOT_READY comes before auto-loot
-- empties the window; LOOT_OPENED stands in where it is missing.
for _, event in ipairs({ "LOOT_READY", "LOOT_OPENED", "UNIT_SPELLCAST_SUCCEEDED" }) do
	pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit == "player" and isGatherSpell(spellID) then
			lastGatherAt = Tradewright:Now()
		end
	elseif Tradewright.db and GetNumLootItems and GetLootSourceInfo then
		recordLootWindow(Tradewright)
	end
end)
