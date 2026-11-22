local _, Tradewright = ...

-- Small helpers every module shares. Pure Lua apart from ForEachBagSlot (C_Container) and
-- Colorize's theme lookup, so the offline tests can load this file with stubs.

function Tradewright:Trim(text)
	if not text then
		return ""
	end
	return (string.gsub(tostring(text), "^%s*(.-)%s*$", "%1"))
end

--- `singular` when `count` is 1, else `plural` (default: `singular .. "s"`). Only the word, not the count.
function Tradewright:Plural(count, singular, plural)
	if tonumber(count) == 1 then
		return singular
	end
	return plural or (singular .. "s")
end

local function colorChannel(value)
	return math.floor((tonumber(value) or 0) * 255)
end

--- `text` wrapped in a colour escape. `color` is a theme key ("warning"), an { r, g, b } table with
--- channels from 0 to 1 (theme entries, class and quality colours), or a hex string "rrggbb".
--- An unknown colour leaves the text as it is.
function Tradewright:Colorize(text, color)
	if type(color) == "string" then
		local themed = self.GetTheme and self:GetTheme()[color]
		if themed then
			color = themed
		elseif color:match("^%x%x%x%x%x%x$") then
			return "|cff" .. color .. tostring(text) .. "|r"
		end
	end
	if type(color) ~= "table" then
		return tostring(text)
	end
	return string.format("|cff%02x%02x%02x%s|r", colorChannel(color.r), colorChannel(color.g), colorChannel(color.b), tostring(text))
end

--- The TSM custom price strings from settings: { market, fallback, material, saleRate }.
function Tradewright:GetTsmPriceStrings()
	local function read(key, default)
		return tostring(self:GetSetting("integrations." .. key, default))
	end
	return {
		market = read("economyTSMMarketString", "dbmarket"),
		fallback = read("economyTSMFallbackString", "DBMinBuyout"),
		material = read("economyTSMMatString", "Crafting"),
		saleRate = read("economyTSMSaleRateString", "DBRegionSaleRate"),
	}
end

--- Probe an object whose shape differs between client builds (Blizzard frames, mixins). Calls each
--- of `methodNames` that exists (inside pcall, so a throwing method is skipped), then reads each of
--- `fieldNames`. `accept(value)` returns the value to use, or nil to keep looking; it may convert
--- (tonumber) and may return false. Returns nil when nothing was accepted or `object` is not a table.
function Tradewright:FirstValueFrom(object, methodNames, fieldNames, accept)
	if type(object) ~= "table" then
		return nil
	end
	for _, name in ipairs(methodNames or {}) do
		local method = object[name]
		if type(method) == "function" then
			local ok, value = pcall(method, object)
			if ok then
				value = accept(value)
				if value ~= nil then
					return value
				end
			end
		end
	end
	for _, name in ipairs(fieldNames or {}) do
		local value = accept(object[name])
		if value ~= nil then
			return value
		end
	end
	return nil
end

--- Call `fn(bag, slot, info)` for every slot of `bagIDs` (default: the carried bags, 0 to the last
--- bag index). `info` is C_Container.GetContainerItemInfo's table, nil for an empty slot. When `fn`
--- returns true the walk stops and this returns true.
function Tradewright:ForEachBagSlot(bagIDs, fn)
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
		return false
	end
	if not bagIDs then
		bagIDs = {}
		for bag = 0, self:GetLastBagIndex() do
			bagIDs[#bagIDs + 1] = bag
		end
	end
	for _, bag in ipairs(bagIDs) do
		for slot = 1, tonumber(C_Container.GetContainerNumSlots(bag)) or 0 do
			if fn(bag, slot, C_Container.GetContainerItemInfo(bag, slot)) == true then
				return true
			end
		end
	end
	return false
end
