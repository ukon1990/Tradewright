local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
--- Pure client flags, auction storage keys and the AHLUA1 export encoding (offline-testable).
local ForeverLogic = {}
Tradewright.ForeverLogic = ForeverLogic

--- Detect Forever vs true retail. Forever shares WOW_PROJECT_MAINLINE; use interface band 16000-16999.
function ForeverLogic.DetectClientFlags(interfaceVersion, projectId, mainlineId)
	interfaceVersion = tonumber(interfaceVersion) or 0
	local isForever = interfaceVersion >= 16000 and interfaceVersion < 17000
	local isRetail = (projectId == mainlineId) and not isForever
	return {
		IS_FOREVER = isForever,
		IS_RETAIL = isRetail,
		IS_SUPPORTED = isRetail or isForever,
	}
end

function ForeverLogic.ApplyClientFlags(target)
	target = target or Tradewright
	local flags = ForeverLogic.DetectClientFlags(
		select(4, GetBuildInfo()),
		WOW_PROJECT_ID,
		WOW_PROJECT_MAINLINE
	)
	target.IS_FOREVER = flags.IS_FOREVER
	target.IS_RETAIL = flags.IS_RETAIL
	target.IS_SUPPORTED = flags.IS_SUPPORTED
	return flags
end

if type(GetBuildInfo) == "function" then
	ForeverLogic.ApplyClientFlags(Tradewright)
end

--- Item ID from auction storage keys (`region:itemID` or `region:realm:itemID`).
--- Storage keys: commodities "<region>:<itemID>"; items "<region>:<realmID>:<itemID>[:<ilvl>:<suffix>:<pet>]".
--- The item ID sits at a fixed position; keys that do not have one there (such as legacy keys built
--- from a table's address, "<region>:<realm>:table: 0x…") return nil.
function ForeverLogic.ParseItemIDFromStorageKey(storageKey)
	if type(storageKey) ~= "string" or storageKey == "" then
		return nil
	end
	local parts = {}
	for part in (storageKey .. ":"):gmatch("([^:]*):") do
		parts[#parts + 1] = part
	end
	local idPart = #parts == 2 and parts[2] or parts[3]
	local itemID = idPart and idPart:match("^%d+$") and tonumber(idPart)
	if itemID and itemID > 0 then
		return itemID
	end
	return nil
end

--- The item part of an item storage key. A C_AuctionHouse item key table becomes
--- "<itemID>:<ilvl>:<suffix>:<pet>"; anything else becomes the plain item ID.
function ForeverLogic.SerializeItemKey(itemKey, itemID)
	if type(itemKey) == "table" then
		local id = tonumber(itemKey.itemID) or tonumber(itemID) or 0
		local ilvl = math.floor(tonumber(itemKey.itemLevel) or 0)
		local suffix = math.floor(tonumber(itemKey.itemSuffix) or 0)
		local pet = math.floor(tonumber(itemKey.battlePetSpeciesID) or 0)
		if ilvl == 0 and suffix == 0 and pet == 0 then
			return tostring(id)
		end
		return string.format("%d:%d:%d:%d", id, ilvl, suffix, pet)
	end
	if itemKey ~= nil and tostring(itemKey):match("^%d+[%d:]*$") then
		return tostring(itemKey)
	end
	return tostring(tonumber(itemID) or 0)
end

--- One-time repair of item snapshot / history entries stored under a table address. The item ID is
--- recovered from `indexes.byItemID`; `buildKey(itemID)` returns the correct key. Entries that cannot
--- be traced back to an item are dropped. Returns the number of entries moved.
function ForeverLogic.RepairAuctionStorageKeys(auction, buildKey)
	if type(auction) ~= "table" or type(buildKey) ~= "function" then
		return 0
	end
	local snapshot = auction.snapshot and auction.snapshot.items or {}
	local hourly = auction.history and auction.history.hourly or {}
	local byItemID = auction.indexes and auction.indexes.byItemID or {}
	local function isBroken(key)
		return type(key) == "string" and key:find("table:", 1, true) ~= nil
	end
	local moved = 0
	for itemIDText, keys in pairs(byItemID) do
		local itemID = tonumber(itemIDText)
		local brokenKeys = {}
		if itemID and type(keys) == "table" then
			for key in pairs(keys) do
				if isBroken(key) then
					brokenKeys[#brokenKeys + 1] = key
				end
			end
		end
		for _, oldKey in ipairs(brokenKeys) do
			local newKey = buildKey(itemID)
			local entry = snapshot[oldKey]
			if entry then
				local existing = snapshot[newKey]
				local entryAt = tonumber(entry.t or entry.seenAt) or 0
				local existingAt = existing and (tonumber(existing.t or existing.seenAt) or 0) or -1
				if entryAt >= existingAt then
					snapshot[newKey] = entry
				end
				moved = moved + 1
			end
			if hourly[oldKey] and not hourly[newKey] then
				hourly[newKey] = hourly[oldKey]
			end
			keys[oldKey] = nil
			keys[newKey] = true
		end
	end
	for _, root in ipairs({ snapshot, hourly }) do
		for key in pairs(root) do
			if isBroken(key) then
				root[key] = nil
			end
		end
	end
	return moved
end

local function encodeLuaValue(value, depth)
	depth = (depth or 0) + 1
	if depth > 24 then
		return "nil"
	end
	local valueType = type(value)
	if valueType == "nil" then
		return "nil"
	elseif valueType == "boolean" then
		return value and "true" or "false"
	elseif valueType == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "nil"
		end
		return tostring(value)
	elseif valueType == "string" then
		return string.format("%q", value)
	elseif valueType ~= "table" then
		return string.format("%q", tostring(value))
	end

	local parts = {}
	local n = #value
	local isArray = n > 0
	if isArray then
		for i = 1, n do
			if value[i] == nil then
				isArray = false
				break
			end
		end
	end
	if isArray then
		for i = 1, n do
			parts[#parts + 1] = encodeLuaValue(value[i], depth)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end

	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)
	for _, key in ipairs(keys) do
		local keyLiteral
		if type(key) == "string" and key:match("^[%a_][%w_]*$") then
			keyLiteral = key
		elseif type(key) == "number" then
			keyLiteral = "[" .. tostring(key) .. "]"
		else
			keyLiteral = "[" .. string.format("%q", tostring(key)) .. "]"
		end
		parts[#parts + 1] = keyLiteral .. "=" .. encodeLuaValue(value[key], depth)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

ForeverLogic.EncodeLuaValue = encodeLuaValue

--- Build AHLUA1 plain-text export package body (including prefix).
function ForeverLogic.BuildPlainLuaExportPayload(exportData)
	if type(exportData) ~= "table" then
		return nil, L["invalid export data"]
	end
	local ok, body = pcall(encodeLuaValue, exportData, 0)
	if not ok or type(body) ~= "string" or body == "" then
		return nil, body or L["Lua encode failed"]
	end
	return "AHLUA1:return " .. body, nil
end

return ForeverLogic
