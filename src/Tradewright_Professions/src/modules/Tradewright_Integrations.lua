local _, Tradewright = ...

local MONEY_COLORS = {
	negative = "ffe36361",
}

local function colorText(hex, text)
	return string.format("|c%s%s|r", hex, tostring(text or ""))
end

local function groupDigits(numberText)
	local sign = ""
	local text = tostring(numberText or "0")
	if string.sub(text, 1, 1) == "-" then
		sign = "-"
		text = string.sub(text, 2)
	end
	local out = text
	while true do
		local nextText, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = nextText
		if count == 0 then
			break
		end
	end
	return sign .. out
end

local function nativeAhObservation(self, itemID)
	if not self.GetNativeAhPrice then
		return nil
	end
	local price, source, seenAt, quantity = self:GetNativeAhPrice(itemID)
	if price and price > 0 and seenAt then
		return { price = price, source = source or "native", seenAt = seenAt, quantity = tonumber(quantity) }
	end
	return nil
end

local function snapshotObservation(summary)
	local price = tonumber(summary.lastPrice)
	if not price or price <= 0 then
		return nil
	end
	local snap = summary.snapshot
	local source = (snap and snap.source and tostring(snap.source) ~= "") and tostring(snap.source) or "snapshot"
	return {
		price = price, source = source, seenAt = tonumber(summary.lastSeenAt),
		quantity = tonumber(snap and (snap.sampleSize or snap.quantity)),
	}
end

-- The newer of the two; a snapshot without a time only counts when there is no own AH price.
local function latestObservation(native, snapshot)
	if not native or not snapshot then
		return native or snapshot
	end
	if snapshot.seenAt and snapshot.seenAt > native.seenAt then
		return snapshot
	end
	return native
end

--- Latest AH price seen for the item (own AH scan or stored snapshot, whichever is newer):
--- price, source, seenAt, quantity. opts.requireFresh: nil unless the item's economy summary is fresh.
function Tradewright:GetLatestObservedAhPrice(itemID, opts)
	opts = type(opts) == "table" and opts or {}
	itemID = tonumber(itemID)
	local summary = itemID and self.GetItemEconomySummary and self:GetItemEconomySummary(itemID, {})
	if not summary or (opts.requireFresh == true and summary.freshnessState ~= "fresh") then
		return nil, nil, nil, nil
	end
	local latest = latestObservation(nativeAhObservation(self, itemID), snapshotObservation(summary))
	if not latest then
		return nil, nil, nil, nil
	end
	return latest.price, latest.source, latest.seenAt, latest.quantity
end

function Tradewright:GetFreshAddonCachedPrice(itemID)
	return self:GetLatestObservedAhPrice(itemID, { requireFresh = true })
end

--- Market price of an item from the pack's own auction data (scan or stored snapshot): copper and
--- its source, or nil when the item was never seen or price columns are switched off.
function Tradewright:GetMarketEstimateCopper(itemID)
	local st = self.db and self.db.settings or {}
	if st.economyShowColumns == false then
		return nil, nil
	end
	local cachedPrice, cachedSource = self:GetLatestObservedAhPrice(itemID, { requireFresh = false })
	if cachedPrice and cachedPrice > 0 then
		return cachedPrice, "cache:" .. tostring(cachedSource or "addon")
	end
	return nil, nil
end

function Tradewright:FormatNumberGrouped(value)
	if value == nil or value ~= value then
		return "-"
	end
	local n = tonumber(value)
	if not n then
		return tostring(value)
	end
	local rounded = math.floor(math.abs(n) + 0.5)
	local text = groupDigits(tostring(rounded))
	if n < 0 then
		return "-" .. text
	end
	return text
end

local COIN_ICONS = {
	gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t",
	silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t",
	copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t",
}

-- "12[g] 40[s]": a number then its coin icon, zero parts dropped. `short` drops copper from 100g and
-- silver from 10,000g so a price fits an 86px column. Negative amounts lead with a red minus.
local function formatCoins(self, copper, short)
	local n = tonumber(copper)
	if copper == nil or copper ~= copper or not n then
		return "-"
	end
	local total = math.floor(math.abs(n) + 0.5)
	local gold = math.floor(total / 10000)
	local silver = math.floor((total % 10000) / 100)
	local bronze = total % 100
	if short then
		if gold >= 100 then
			bronze = 0
		end
		if gold >= 10000 then
			silver = 0
		end
	end
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = self:FormatNumberGrouped(gold) .. COIN_ICONS.gold
	end
	if silver > 0 then
		parts[#parts + 1] = tostring(silver) .. COIN_ICONS.silver
	end
	if bronze > 0 or #parts == 0 then
		parts[#parts + 1] = tostring(bronze) .. COIN_ICONS.copper
	end
	local text = table.concat(parts, " ")
	if n < 0 and total > 0 then
		return colorText(MONEY_COLORS.negative, "-") .. text
	end
	return text
end

function Tradewright:FormatCopperFull(copper)
	return formatCoins(self, copper, false)
end

function Tradewright:FormatCopperShort(copper)
	return formatCoins(self, copper, true)
end
