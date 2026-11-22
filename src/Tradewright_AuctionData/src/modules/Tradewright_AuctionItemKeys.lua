-- Item keys for AH searches: normalizing key fields, matching search events and remembering what was searched.
local _, Tradewright = ...

local FL = Tradewright.ForeverLogic
local shared = Tradewright.AuctionShared
local normalizeItemID = shared.normalizeItemID
local normalizeSearchEventItemID = shared.normalizeSearchEventItemID

--- Normalize optional fields for C_AuctionHouse.MakeItemKey(itemID, itemLevel, itemSuffix, battlePetSpeciesID).
--- Returns nil when no narrowing fields are present (use generic item key / commodity path).
function Tradewright:NormalizeAuctionItemKeyFields(fields)
	if type(fields) ~= "table" then
		return nil
	end
	local ilvl = fields.itemLevel
	local suffix = fields.itemSuffix
	local pet = fields.battlePetSpeciesID
	if ilvl == nil and suffix == nil and pet == nil then
		return nil
	end
	return {
		itemLevel = math.max(0, math.floor(tonumber(ilvl) or 0)),
		itemSuffix = math.max(0, math.floor(tonumber(suffix) or 0)),
		battlePetSpeciesID = math.max(0, math.floor(tonumber(pet) or 0)),
	}
end

function Tradewright:DoesAuctionSearchEventMatchItem(scanItemID, eventArg, scanKeyFields)
	scanItemID = normalizeItemID(scanItemID)
	if not scanItemID then
		return false
	end
	if type(eventArg) == "number" or type(eventArg) == "string" then
		return tonumber(normalizeItemID(eventArg)) == tonumber(scanItemID)
	end
	if type(eventArg) ~= "table" then
		return false
	end
	local evKey = eventArg.itemKey or eventArg
	local evId = normalizeSearchEventItemID(evKey)
	if evId == nil then
		evId = normalizeSearchEventItemID(eventArg)
	end
	if tonumber(evId) ~= tonumber(scanItemID) then
		return false
	end
	if not scanKeyFields or not self:NormalizeAuctionItemKeyFields(scanKeyFields) then
		return true
	end
	-- Item keys are tables: compare what they hold, never the tables themselves.
	return FL.SerializeItemKey(scanKeyFields, scanItemID) == FL.SerializeItemKey(evKey, evId)
end

function Tradewright:MakeAuctionHouseItemKey(itemID, keyFields)
	itemID = normalizeItemID(itemID)
	if not itemID or not C_AuctionHouse then
		return nil
	end
	local normalizedFields = self:NormalizeAuctionItemKeyFields(keyFields)
	if C_AuctionHouse.MakeItemKey then
		if normalizedFields then
			local ok, key = pcall(C_AuctionHouse.MakeItemKey, itemID, normalizedFields.itemLevel, normalizedFields.itemSuffix, normalizedFields.battlePetSpeciesID)
			if ok and key then
				return key
			end
		end
		local ok, key = pcall(C_AuctionHouse.MakeItemKey, itemID)
		if ok and key then
			return key
		end
	end
	if ItemKeyMixin and ItemKeyMixin.CreateFromItemID then
		return ItemKeyMixin:CreateFromItemID(itemID)
	end
	return nil
end

function Tradewright:GetAuctionSearchedTargetsState()
	local state = self:GetState()
	state.auctionSearchedTargets = state.auctionSearchedTargets or {}
	state.auctionSearchedTargetsMeta = state.auctionSearchedTargetsMeta or {}
	return state.auctionSearchedTargets, state.auctionSearchedTargetsMeta
end

function Tradewright:HasAuctionTargetBeenSearchedThisSession(itemID, keyFields)
	local searched = self:GetAuctionSearchedTargetsState()
	local key = FL.SerializeItemKey(keyFields, normalizeItemID(itemID))
	return searched[key] == true
end

function Tradewright:MarkAuctionTargetSearched(itemID, keyFields, source, seenAt)
	itemID = normalizeItemID(itemID)
	if not itemID then
		return false
	end
	local searched, meta = self:GetAuctionSearchedTargetsState()
	local ts = tonumber(seenAt) or Tradewright:Now()
	local key = FL.SerializeItemKey(keyFields, itemID)
	searched[key] = true
	meta[key] = {
		itemID = itemID,
		itemKeyFields = self:NormalizeAuctionItemKeyFields(keyFields),
		source = tostring(source or "session"),
		seenAt = ts,
	}
	return true
end

function Tradewright:ExtractAuctionItemKeyFieldsFromEventArg(eventArg)
	if type(eventArg) ~= "table" then
		return nil
	end
	local itemKey = eventArg.itemKey or eventArg
	if type(itemKey) ~= "table" then
		return nil
	end
	return self:NormalizeAuctionItemKeyFields({
		itemLevel = itemKey.itemLevel,
		itemSuffix = itemKey.itemSuffix,
		battlePetSpeciesID = itemKey.battlePetSpeciesID,
	})
end
