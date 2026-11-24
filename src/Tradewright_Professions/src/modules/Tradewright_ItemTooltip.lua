local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- The Tradewright block on the game's item tooltips: price and how fresh it is, how it compares
-- with the usual price, how much is listed, what you own and which character holds it where.
-- Shift adds craft profit, your rule, the vendor price, the recipes it is part of, how much of
-- what you posted sold and your average sale.
-- Which lines show is decided in TooltipLogic (pure, tested offline); this file gathers the data
-- and draws the lines. Rows in the addon's own windows skip the block (ShowItemRowTooltip), except
-- reagent rows, which show it in full (ShowItemTooltip).

local HEADER = Tradewright.DISPLAY_NAME
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

-- The logged-in character is counted live; the others come from their saved holdings. Only the
-- others carry a `key`, which is how TooltipLogic tells them from the logged-in character.
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

-- The actions and the profession (skill line) each one takes: Enchanting, Jewelcrafting, Inscription.
local SALVAGE_ACTIONS = { { action = "disenchant", skillLineID = 333 }, { action = "prospect", skillLineID = 755 }, { action = "mill", skillLineID = 773 } }

--- Whether the logged-in character or any saved character has the profession. A saved character
--- counts once its profession has been scanned.
function Tradewright:SomeCharacterHasProfession(skillLineID)
	for _, profession in ipairs(self:GetPlayerProfessions()) do
		if profession.skillLineID == skillLineID then
			return true
		end
	end
	for _, character in pairs(self.db.characters or {}) do
		if character.professions and character.professions[tostring(skillLineID)] then
			return true
		end
	end
	return false
end

-- A prospect or mill destroys several items at once and is valued for that many; gear is
-- disenchanted one piece at a time.
local function salvageLine(action, worth)
	local perCast = action ~= "disenchant" and worth.inputsPerCast and math.floor(worth.inputsPerCast + 0.5) or 1
	return { action = action, value = worth.value * perCast, perCast = perCast, basis = worth.basis, casts = worth.casts }
end

-- What destroying the item is worth, for each action one of the player's characters can do and that
-- has a known yield for it: `{ { action, value, perCast, basis, casts } }`, or nil.
local function fillSalvage(pe, out, itemID)
	if not (pe.GetSalvageInput and pe.GetSalvageValue) then
		return
	end
	for _, salvage in ipairs(SALVAGE_ACTIONS) do
		local input = pe:SomeCharacterHasProfession(salvage.skillLineID) and pe:GetSalvageInput(salvage.action, itemID)
		local worth = input and pe:GetSalvageValue(salvage.action, input)
		if worth then
			out.salvage = out.salvage or {}
			out.salvage[#out.salvage + 1] = salvageLine(salvage.action, worth)
		end
	end
end

-- The ore or herbs the item has come from when prospected or milled, the cheapest way to get one
-- first: `{ { action, name, perCast, quantity, costEach } }`. `quantity` is what one cast gives on
-- average; `costEach` what one of the item then costs at the input's AH price, nil without a price.
local function fillSalvageSources(pe, out, itemID)
	local sources = pe.GetSalvageSources and pe:GetSalvageSources(itemID) or {}
	if #sources == 0 then
		return
	end
	out.salvageSources = {}
	for index, source in ipairs(sources) do
		local price = pe.GetMarketEstimateCopper and (pe:GetMarketEstimateCopper(source.inputItemID))
		local perCast = math.floor(source.inputsPerCast + 0.5)
		out.salvageSources[index] = {
			-- The name lookup lives in the UI module, which loads after this one and may be off.
			action = source.action, perCast = perCast,
			name = pe.GetItemDisplayName and pe:GetItemDisplayName(source.inputItemID) or ("#" .. source.inputItemID),
			quantity = source.perInput * perCast, costEach = price and price / source.perInput or nil,
		}
	end
	table.sort(out.salvageSources, function(a, b)
		if (a.costEach ~= nil) ~= (b.costEach ~= nil) then
			return a.costEach ~= nil
		end
		return (a.costEach or -a.quantity) < (b.costEach or -b.quantity)
	end)
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
function Tradewright:BuildItemGoldSummary(itemID, detail)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	local summary = self.GetItemEconomySummary and self:GetItemEconomySummary(itemID, {}) or {}
	local out = { cut = self:GetAuctionCut() }
	fillPrice(self, out, itemID, summary)
	out.listed = tonumber((summary.snapshot or {}).sampleSize)
	if self.FillPriceBaseline then
		self:FillPriceBaseline(out, itemID)
	end
	fillCraft(self, out, itemID)
	fillOwned(self, out, itemID)
	fillExtras(self, out, itemID, summary)
	fillSalvage(self, out, itemID)
	fillSalvageSources(self, out, itemID)
	if detail then
		out.recipeUse = recipeUse(self, itemID)
		-- Optional dependency: the sale rate lives in AuctionData and walks the whole ledger,
		-- so it is only looked up while Shift is held.
		if self.GetAuctionPanelPersonalSaleRate then
			out.saleRate = self:GetAuctionPanelPersonalSaleRate(itemID)
		end
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

function Tradewright:AppendPricingToItemTooltip(tooltip, itemID)
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

function Tradewright:AppendPricingToTooltipFromData(tooltip, data)
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

-- The general block, which carries the sale rate, is left out on rows, so rows add it themselves.
local function withSaleRate(pe, pairs, itemID)
	local rate = itemID and pe.GetAuctionPanelPersonalSaleRate and pe:GetAuctionPanelPersonalSaleRate(itemID)
	if not rate then
		return pairs
	end
	local out = {}
	for i, pair in ipairs(pairs or {}) do
		out[i] = pair
	end
	out[#out + 1] = { L["You sold"], pe.TooltipLogic.SaleRateText(rate) }
	return out
end

-- Starts the game's item tooltip at the row's right edge. A row tooltip (`isRow`) is remembered,
-- so the general block is left out of it (blockSkipped).
local function startItemTooltip(pe, owner, itemID, isRow)
	pe._rowTooltipOwner = isRow and owner or nil
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(itemID)
	end
end

-- The row's label/value pairs, under the addon name unless the block already put it there, then
-- the muted hint.
local function finishItemTooltip(pe, pairs, hint)
	local theme = pe:GetTheme()
	local gold, muted, plain = theme.gold, theme.textMuted, theme.textPrimary
	if pairs and #pairs > 0 then
		if not hasBlock(GameTooltip) then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(HEADER, gold.r, gold.g, gold.b)
		end
		for _, pair in ipairs(pairs) do
			GameTooltip:AddDoubleLine(pair[1], pair[2] or "-", muted.r, muted.g, muted.b, plain.r, plain.g, plain.b)
		end
	end
	if hint then
		GameTooltip:AddLine(hint, muted.r, muted.g, muted.b, true)
	end
	GameTooltip:Show()
end

--- Item tooltip for a row in one of the addon's windows: anchored to the row's right edge, the
--- game's item tooltip, then the row's own label/value pairs under the addon name and a muted
--- hint. The general block is left out (blockSkipped), so no fact shows twice.
--- `pairs`: { { label, value }, ... }.
function Tradewright:ShowItemRowTooltip(owner, itemID, pairs, hint)
	if not owner then
		return
	end
	startItemTooltip(self, owner, itemID, true)
	finishItemTooltip(self, withSaleRate(self, pairs, itemID), hint)
end

--- Item tooltip for a reagent row: the same tooltip the item has everywhere else in the game, with
--- the whole Tradewright block (price, what you own and where), then the row's own pairs and hint.
--- Pairs should not repeat what the block says.
function Tradewright:ShowItemTooltip(owner, itemID, pairs, hint)
	if not owner then
		return
	end
	startItemTooltip(self, owner, itemID, false)
	finishItemTooltip(self, pairs, hint)
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
	if tooltip and tooltip.HookScript and not tooltip._tradewrightPricingHooked then
		tooltip:HookScript("OnTooltipSetItem", function(tip)
			Tradewright:AppendPricingToTooltipFromData(tip, nil)
		end)
		tooltip._tradewrightPricingHooked = true
	end
end

function Tradewright:InitItemTooltipPricingHooks()
	if self._itemTooltipPricingHooksInit then
		return
	end
	self._itemTooltipPricingHooksInit = true
	watchShift(self)

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			Tradewright:AppendPricingToTooltipFromData(tooltip, data)
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
