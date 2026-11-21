local _, AuctionHelper = ...

-- The AuctionHelper block on the game's item tooltips: price and how fresh it is, how it compares
-- with the usual price, how much is listed and what you own. Shift adds craft profit, who holds
-- it, your rule, the vendor price, the recipes it is part of and your own sales.
-- Which lines show is decided in TooltipLogic (pure, tested offline); this file gathers the data
-- and draws the lines. Rows in the addon's own windows skip the block (ShowItemRowTooltip).

local HEADER = "AuctionHelper"
local STALE_FLOOR_SECONDS = 6 * 3600
local RECIPE_USE_TTL_SECONDS = 60
local TONE_COLOURS = { success = "success", danger = "danger", warning = "warning", info = "accent" }

local function positive(value)
	value = tonumber(value)
	return value and value > 0 and value or nil
end

-- The addon's own price: fresh cache, this session's scan, else the last snapshot.
local function ownPrice(pe, itemID, summary)
	local price, seenAt, _
	if pe.GetFreshAddonCachedPrice then
		price, _, seenAt = pe:GetFreshAddonCachedPrice(itemID)
	end
	if not positive(price) and pe.GetNativeAhPrice then
		price, _, seenAt = pe:GetNativeAhPrice(itemID)
	end
	if not positive(price) then
		price, seenAt = summary.lastPrice, summary.lastSeenAt
	end
	return positive(price), tonumber(seenAt)
end

-- The addon's own price and its age, else another addon's as an estimate.
local function fillPrice(pe, out, itemID, summary)
	local seenAt
	out.price, seenAt = ownPrice(pe, itemID, summary)
	if not out.price then
		out.estimate = pe.GetMarketEstimateCopper and pe:GetMarketEstimateCopper(itemID, nil, nil) or nil
	elseif seenAt then
		local freshness = pe.GetAuctionPriceFreshnessWindowSeconds and pe:GetAuctionPriceFreshnessWindowSeconds() or 0
		out.priceAge = pe:Now() - seenAt
		out.priceStale = out.priceAge > math.max(freshness, STALE_FLOOR_SECONDS)
	end
end

local function fillCraft(pe, out, itemID)
	local craft = pe.GetItemHistoryStats and pe:GetItemHistoryStats(itemID, "crafting", "30d") or {}
	out.craftCost = positive(craft.average) or positive(craft.latest)
	local unit = out.price or out.estimate
	if out.craftCost and unit then
		out.profit = unit * (1 - out.cut) - out.craftCost
		out.margin = out.profit / out.craftCost * 100
	end
end

-- The logged-in character is counted live; the others come from their saved holdings.
local function fillOwned(pe, out, itemID)
	local owners, total = {}, 0
	if pe.GetItemHoldings then
		owners, total = pe.TooltipLogic.Owners(pe:GetItemHoldings(), itemID, pe:GetCharacterKey())
	end
	if pe.GetItemCountByLocation then
		local bags, bank, warband, own = pe:GetItemCountByLocation(itemID)
		if positive(own) then
			table.insert(owners, 1, { name = UnitName("player") or "You", bags = bags, bank = bank, warband = warband })
			total = total + own
		end
	end
	out.owners, out.ownedAll = owners, total
	out.listedByYou = pe.GetOwnedActiveAuctionQuantityForItem and pe:GetOwnedActiveAuctionQuantityForItem(itemID) or 0
end

local function fillExtras(pe, out, itemID, summary)
	out.vendor = pe.GetItemVendorSellCopper and pe:GetItemVendorSellCopper(itemID) or nil
	local unit = out.price or out.estimate
	out.vendorBeatsAh = out.vendor ~= nil and unit ~= nil and out.vendor > unit * (1 - out.cut)
	out.rule = pe.GetAuctionItemRule and pe:GetAuctionItemRule(itemID) or nil
	out.avgSale = tonumber(summary.avgSale)
end

-- Finding the recipes of an item walks every saved recipe, so the answer is kept for a minute.
local recipeUseCache, recipeUseAt = {}, 0
local function recipeUse(pe, itemID)
	if not pe.GetItemRecipeRelationships then
		return nil
	end
	local now = time()
	if now - recipeUseAt > RECIPE_USE_TTL_SECONDS then
		recipeUseCache, recipeUseAt = {}, now
	end
	recipeUseCache[itemID] = recipeUseCache[itemID] or pe.TooltipLogic.RecipeUse(pe:GetItemRecipeRelationships(itemID))
	return recipeUseCache[itemID]
end

--- What a gold maker needs about an item, from every source the addon has. All fields may be nil.
--- `detail` also looks up the recipes the item is part of.
function AuctionHelper:BuildItemGoldSummary(itemID, detail)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	local summary = self.GetItemEconomySummary and self:GetItemEconomySummary(itemID, {}) or {}
	local out = { cut = self.GetCraftsAhCutFraction and self:GetCraftsAhCutFraction() or 0.05 }
	fillPrice(self, out, itemID, summary)
	out.listed = tonumber((summary.snapshot or {}).sampleSize)
	if self.FillPriceBaseline then
		self:FillPriceBaseline(out, itemID)
	end
	fillCraft(self, out, itemID)
	fillOwned(self, out, itemID)
	fillExtras(self, out, itemID, summary)
	if detail then
		out.recipeUse = recipeUse(self, itemID)
	end
	return out
end

local function hasBlock(tooltip)
	local name = tooltip.GetName and tooltip:GetName()
	if not name or name == "" then
		return false
	end
	for i = 1, tooltip:NumLines() or 0 do
		local left = _G[name .. "TextLeft" .. i]
		if left and left:GetText() == HEADER then
			return true
		end
	end
	return false
end

-- No block when it is switched off, already there, or the tooltip belongs to one of the addon's
-- own rows, which show their own lines instead.
local function blockSkipped(pe, tooltip)
	if pe:GetSetting("auction.tooltipEnabled", true) == false then
		return true
	end
	if tooltip == GameTooltip and pe._rowTooltipOwner and tooltip:GetOwner() == pe._rowTooltipOwner then
		return true
	end
	return hasBlock(tooltip)
end

local function toneColour(theme, tone, plain)
	local c = tone and theme[TONE_COLOURS[tone]] or plain
	return c.r, c.g, c.b
end

function AuctionHelper:AppendPricingToItemTooltip(tooltip, itemID)
	itemID = tonumber(itemID)
	if not tooltip or not itemID or itemID <= 0 or blockSkipped(self, tooltip) then
		return false
	end
	local detail = IsShiftKeyDown and IsShiftKeyDown() or false
	local block = self.TooltipLogic.BuildLines(self:BuildItemGoldSummary(itemID, detail), {
		detail = detail,
		money = function(copper) return self:FormatCopperFull(copper) end,
		moneyShort = function(copper) return self:FormatCopperShort(copper) end,
		number = function(value) return self:FormatNumberGrouped(value) end,
	})
	if not block then
		return false
	end
	local theme = self:GetTheme()
	local gold, muted = theme.gold, theme.textMuted
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine(HEADER, block.header.right or "", gold.r, gold.g, gold.b, toneColour(theme, block.header.tone, muted))
	for _, line in ipairs(block.lines) do
		tooltip:AddDoubleLine(line.label, line.value, muted.r, muted.g, muted.b, toneColour(theme, line.tone, theme.textPrimary))
	end
	return true
end

local function itemIDFromLink(link)
	local getItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	return link and getItemInfoInstant and (getItemInfoInstant(link)) or nil
end

local function itemIDFromData(data)
	if type(data) ~= "table" then
		return nil
	end
	return positive(data.id or data.itemID) or itemIDFromLink(data.hyperlink)
end

function AuctionHelper:AppendPricingToTooltipFromData(tooltip, data)
	if not tooltip then
		return
	end
	local itemID = itemIDFromData(data)
	if not itemID and tooltip.GetItem then
		local _, itemLink = tooltip:GetItem()
		itemID = itemIDFromLink(itemLink)
	end
	self:AppendPricingToItemTooltip(tooltip, itemID)
end

--- Item tooltip for a row in one of the addon's windows: anchored to the row's right edge, the
--- game's item tooltip, then the row's own label/value pairs under the addon name and a muted
--- hint. The general block is left out (blockSkipped), so no fact shows twice.
--- `pairs`: { { label, value }, ... }.
function AuctionHelper:ShowItemRowTooltip(owner, itemID, pairs, hint)
	if not owner then
		return
	end
	local theme = self:GetTheme()
	local gold, muted, plain = theme.gold, theme.textMuted, theme.textPrimary
	self._rowTooltipOwner = owner
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(itemID)
	end
	if pairs and #pairs > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(HEADER, gold.r, gold.g, gold.b)
		for _, pair in ipairs(pairs) do
			GameTooltip:AddDoubleLine(pair[1], pair[2] or "-", muted.r, muted.g, muted.b, plain.r, plain.g, plain.b)
		end
	end
	if hint then
		GameTooltip:AddLine(hint, muted.r, muted.g, muted.b, true)
	end
	GameTooltip:Show()
end

-- Shift pressed or released over an item: show the tooltip again so the detail lines come and go.
local function refreshHoveredItem(pe)
	local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
	if not owner or owner == pe._rowTooltipOwner or not GameTooltip.GetItem or not select(2, GameTooltip:GetItem()) then
		return
	end
	local onEnter = owner.IsMouseOver and owner:IsMouseOver() and owner.GetScript and owner:GetScript("OnEnter")
	if onEnter then
		onEnter(owner, true)
	end
end

local function watchShift(pe)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("MODIFIER_STATE_CHANGED")
	frame:SetScript("OnEvent", function(_, _, key)
		if (key == "LSHIFT" or key == "RSHIFT") and pe:GetSetting("auction.tooltipEnabled", true) ~= false then
			refreshHoveredItem(pe)
		end
	end)
end

local function hookTooltip(tooltip)
	if tooltip and tooltip.HookScript and not tooltip._professionExporterPricingHooked then
		tooltip:HookScript("OnTooltipSetItem", function(tip)
			AuctionHelper:AppendPricingToTooltipFromData(tip, nil)
		end)
		tooltip._professionExporterPricingHooked = true
	end
end

function AuctionHelper:InitItemTooltipPricingHooks()
	if self._itemTooltipPricingHooksInit then
		return
	end
	self._itemTooltipPricingHooksInit = true
	watchShift(self)

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			AuctionHelper:AppendPricingToTooltipFromData(tooltip, data)
		end)
		return
	end

	hookTooltip(GameTooltip)
	hookTooltip(ItemRefTooltip)
	hookTooltip(ShoppingTooltip1)
	hookTooltip(ShoppingTooltip2)
	hookTooltip(ItemRefShoppingTooltip1)
	hookTooltip(ItemRefShoppingTooltip2)
	hookTooltip(EmbeddedItemTooltip)
end
