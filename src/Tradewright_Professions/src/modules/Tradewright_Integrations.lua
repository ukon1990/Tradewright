local _, Tradewright = ...

local CALLER_ID = "Tradewright"
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

function Tradewright:IsTSMLoaded()
	return type(TSM_API) == "table"
		and type(TSM_API.ToItemString) == "function"
		and type(TSM_API.GetCustomPriceValue) == "function"
end

function Tradewright:IsAuctionatorLoaded()
	return type(Auctionator) == "table"
		and type(Auctionator.API) == "table"
		and Auctionator.API.v1
		and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

function Tradewright:GetTSMItemString(itemID)
	if not self:IsTSMLoaded() or not itemID then
		return nil
	end
	local ok, itemString = pcall(TSM_API.ToItemString, "item:" .. tostring(itemID))
	if ok and itemString and itemString ~= "" then
		return itemString
	end
	ok, itemString = pcall(TSM_API.ToItemString, itemID)
	if ok and itemString and itemString ~= "" then
		return itemString
	end
	return nil
end

--- Price in copper, or nil.
function Tradewright:GetTSMCustomPriceCopper(customPriceStr, itemID)
	if not customPriceStr or customPriceStr == "" or not itemID then
		return nil
	end
	if not self:IsTSMLoaded() then
		return nil
	end
	local itemString = self:GetTSMItemString(itemID)
	if not itemString then
		return nil
	end
	local ok, value, err = pcall(TSM_API.GetCustomPriceValue, customPriceStr, itemString)
	if not ok or err or value == nil then
		return nil
	end
	local n = tonumber(value)
	if not n or n ~= n then
		return nil
	end
	return n
end

--- Per-item auction scan estimate in copper, or nil.
function Tradewright:GetAuctionatorPriceCopper(itemID)
	if not itemID or not self:IsAuctionatorLoaded() then
		return nil
	end
	local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, CALLER_ID, itemID)
	if not ok or not price then
		return nil
	end
	local n = tonumber(price)
	if not n or n < 0 then
		return nil
	end
	return n
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

--- Market column: primary TSM string, configurable fallback TSM string, else Auctionator.
function Tradewright:GetMarketEstimateCopper(itemID, tsmCustomStr, fallbackTSMStr)
	local st = self.db and self.db.settings or {}
	if st.economyShowColumns == false then
		return nil, nil
	end
	local cachedPrice, cachedSource = self:GetLatestObservedAhPrice(itemID, { requireFresh = false })
	if cachedPrice and cachedPrice > 0 then
		return cachedPrice, "cache:" .. tostring(cachedSource or "addon")
	end
	if tsmCustomStr and tsmCustomStr ~= "" then
		local c = self:GetTSMCustomPriceCopper(tsmCustomStr, itemID)
		if c then
			return c, "TSM"
		end
	end
	fallbackTSMStr = fallbackTSMStr or self:GetTsmPriceStrings().fallback
	if fallbackTSMStr and fallbackTSMStr ~= "" and fallbackTSMStr ~= tsmCustomStr then
		local c = self:GetTSMCustomPriceCopper(fallbackTSMStr, itemID)
		if c then
			return c, "TSM fallback"
		end
	end
	if st.economyUseAuctionatorFallback ~= false then
		local a = self:GetAuctionatorPriceCopper(itemID)
		if a then
			return a, "Auc"
		end
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

--- Sale rate from TSM custom price (often 0-1).
function Tradewright:FormatSaleRateDisplay(value)
	if value == nil or value ~= value then
		return "-"
	end
	local n = tonumber(value)
	if not n then
		return "-"
	end
	if n >= 0 and n <= 1 then
		return string.format("%.0f%%", n * 100)
	end
	if n > 1 and n <= 100 then
		return string.format("%.0f%%", n)
	end
	return self:FormatCopperShort(n)
end
