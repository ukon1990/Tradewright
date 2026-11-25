local addonName, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Methods that live in another module (Bags, retail-only files) may be missing; skip them silently.
local function callOptional(self, method, ...)
	if self[method] then
		self[method](self, ...)
	end
end

local function onAddonLoaded(self, loadedAddonName)
	local tracked = {
		[addonName] = true,
		["Tradewright_AuctionData"] = true,
		["Tradewright_Professions"] = true,
		["Tradewright_Inventory"] = true,
		["Tradewright_UI"] = true,
		["Tradewright_Bags"] = true,
	}
	if not tracked[loadedAddonName] then
		return
	end

	self:InitDB()
	TradewrightLastExport = TradewrightLastExport or {}
	self.baseDb.meta.familyLoaded = self.baseDb.meta.familyLoaded or {}
	self.baseDb.meta.familyLoaded[loadedAddonName] = time()
	if loadedAddonName == addonName then
		self:ApplyThemeSetting()
		self.baseDb.meta.lastLoad = {
			loadedAt = time(),
			addonVersion = self.VERSION,
			schemaVersion = self.SCHEMA_VERSION,
			build = self:GetBuildMetadata(),
		}
	end
end

local function onPlayerLogin(self)
	if self.RecordWalletObservation then
		C_Timer.After(0.5, function()
			Tradewright:RecordWalletObservation(Tradewright:GetCharacterKey(), GetMoney(), time())
		end)
	end
	SLASH_TRADEWRIGHT1 = "/tw"
	SLASH_TRADEWRIGHT2 = "/tradewright"
	SlashCmdList.TRADEWRIGHT = function(input)
		Tradewright:HandleSlash(input)
	end

	self:EnsureMinimapButton()
	self:RegisterBlizzardSettings()
	self:InitProfessionCraftEconomyHooks()
	callOptional(self, "InitItemTooltipPricingHooks")
	callOptional(self, "InitCraftingOrdersFilters")
	callOptional(self, "InitDynamicLayeringHooks")
	callOptional(self, "InitMailPanelHooks")
	-- Turns the finished days of hourly scans into daily prices, which usual prices and price days read.
	callOptional(self, "RollupDailyAuctionHistory")
	-- Without a full scan every price is missing, so the first step matters more than the commands.
	if self.GetLastFullAuctionScanAt and not self:GetLastFullAuctionScanAt() then
		self:PrintMessage(L["No prices yet. Open the auction house and press Full scan."])
	else
		self:PrintMessage(L["Loaded. /tw opens the window, /tw help lists the commands."])
	end
end

local PROFESSION_PANEL_REFRESH_DELAY = 0.05

local function refreshProfessionPanel(self, layeringReason)
	callOptional(self, "ScheduleRefreshProfessionCraftEconomyPanel", PROFESSION_PANEL_REFRESH_DELAY)
	if layeringReason then
		callOptional(self, "UpdateDynamicPanelLayering", layeringReason)
	end
end

local function onTradeSkillShow(self)
	callOptional(self, "InitCraftingOrdersFilters")
	self:TryScanCurrentProfession()
	self:RememberOpenProfessionSkillLineID()
	callOptional(self, "StoreOpenProfessionIfNew")
	self:InitProfessionCraftEconomyHooks()
	refreshProfessionPanel(self)
	callOptional(self, "RecordExternalFrameInteraction", "ProfessionsFrame", "trade_skill_show")
end

local function onTradeSkillListUpdate(self)
	self:TryScanCurrentProfession()
	self:RememberOpenProfessionSkillLineID()
	callOptional(self, "StoreOpenProfessionIfNew")
	refreshProfessionPanel(self, "trade_skill_list_update")
end

local function onTradeSkillCastStopped(self)
	refreshProfessionPanel(self, "trade_skill_cast_stopped")
end

local function onTradeSkillClose(self)
	self:TryScanCurrentProfession()
	self:ApplyLiveProfessionMergeOnWindowClose()
	refreshProfessionPanel(self, "trade_skill_close")
end

local function onInteractionFrameShow(self, interactionType)
	callOptional(self, "UpdateDynamicPanelLayering", "interaction_show_" .. tostring(interactionType))
end

local function onInteractionFrameHide(self, interactionType)
	callOptional(self, "UpdateDynamicPanelLayering", "interaction_hide_" .. tostring(interactionType))
end

local function onBagUpdateDelayed(self)
	self:ScheduleLiveInventoryRefresh()
	callOptional(self, "ClearSettledAuctionCartPurchaseCredits")
	callOptional(self, "OnAuctionBagUpdate")
	if self.RefreshAuctionHousePanel and self.IsAuctionHouseFrameOpen and self:IsAuctionHouseFrameOpen() then
		self:RefreshAuctionHousePanel()
	end
	if self.RefreshMailPanel and _G.MailFrame and MailFrame:IsShown() then
		self:RefreshMailPanel()
	end
end

local function onAuctionCreated(self)
	self:DebugLog("AH", "event: AUCTION_HOUSE_AUCTION_CREATED", { "source=auction_created" })
	callOptional(self, "OnAuctionHouseAuctionCreated")
end

local function onAuctionSold(self)
	self:DebugLog("AH", "event: AUCTION_HOUSE_AUCTION_SOLD", { "source=auction_sold" })
	callOptional(self, "OnAuctionHouseAuctionSold")
end

local function onOwnedAuctionsUpdated(self)
	self:DebugLog("AH", "event: OWNED_AUCTIONS_UPDATED", { "source=owned_auctions_updated" })
	callOptional(self, "OnOwnedAuctionsUpdated")
	-- Retail-safe fallback signal for AH post/sold/cancel changes.
	callOptional(self, "PrimeAuctionPanelRows")
	callOptional(self, "RefreshAuctionHousePanel")
end

local function onPlayerMoney(self)
	if self.RecordWalletObservation then
		self:RecordWalletObservation(self:GetCharacterKey(), GetMoney(), time())
	end
	callOptional(self, "RefreshShellStatus")
end

-- Fulfil, release and reject all close the order on our side, but only when the server accepted it.
local function onCraftingOrderResponse(self, result, orderID)
	if Enum.CraftingOrderResult and result == Enum.CraftingOrderResult.Ok then
		callOptional(self, "OnCraftingOrderFulfilled", orderID)
	end
end

-- Event -> handler. A string names a Tradewright method that gets the event's arguments;
-- it is looked up when the event fires and skipped while missing. A function is called with (self, ...).
local EVENT_HANDLERS = {
	ADDON_LOADED = onAddonLoaded,
	PLAYER_LOGIN = onPlayerLogin,
	PLAYER_MONEY = onPlayerMoney,
	NEW_RECIPE_LEARNED = "ScheduleLiveProfessionRefresh",

	TRADE_SKILL_SHOW = onTradeSkillShow,
	TRADE_SKILL_LIST_UPDATE = onTradeSkillListUpdate,
	UPDATE_TRADESKILL_CAST_STOPPED = onTradeSkillCastStopped,
	TRADE_SKILL_CLOSE = onTradeSkillClose,
	TRADE_SKILL_ITEM_CRAFTED_RESULT = "OnProfessionRecipeCraftedResult",
	UNIT_SPELLCAST_SUCCEEDED = "OnUnitSpellcastSucceeded",
	PLAYER_INTERACTION_MANAGER_FRAME_SHOW = onInteractionFrameShow,
	PLAYER_INTERACTION_MANAGER_FRAME_HIDE = onInteractionFrameHide,

	BAG_UPDATE_DELAYED = onBagUpdateDelayed,
	BANKFRAME_OPENED = "ScheduleLiveInventoryRefresh",

	AUCTION_HOUSE_SHOW = "OnAuctionHouseShow",
	AUCTION_HOUSE_CLOSED = "OnAuctionHouseClosed",
	AUCTION_HOUSE_AUCTION_CREATED = onAuctionCreated,
	AUCTION_HOUSE_AUCTION_SOLD = onAuctionSold,
	OWNED_AUCTIONS_UPDATED = onOwnedAuctionsUpdated,
	AUCTION_CANCELED = "OnAuctionCanceled",
	AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = "OnAuctionHouseBrowseResultsUpdated",
	AUCTION_HOUSE_BROWSE_RESULTS_ADDED = "OnAuctionHouseBrowseResultsUpdated",
	COMMODITY_SEARCH_RESULTS_UPDATED = "OnCommoditySearchResultsUpdated",
	ITEM_SEARCH_RESULTS_UPDATED = "OnItemSearchResultsUpdated",
	REPLICATE_ITEM_LIST_UPDATE = "OnReplicateItemListUpdate",
	AUCTION_ITEM_LIST_UPDATE = "OnAuctionItemListUpdate",
	COMMODITY_PURCHASE_SUCCEEDED = "OnCommodityPurchaseSucceeded",
	COMMODITY_PURCHASE_FAILED = "OnCommodityPurchaseFailed",
	COMMODITY_PURCHASED = "OnCommodityPurchased",
	ITEM_PURCHASED = "OnItemPurchased",
	AUCTION_HOUSE_PURCHASE_COMPLETED = "OnAuctionHousePurchaseCompleted",

	CRAFTINGORDERS_FULFILL_ORDER_RESPONSE = onCraftingOrderResponse,
	CRAFTINGORDERS_RELEASE_ORDER_RESPONSE = onCraftingOrderResponse,
	CRAFTINGORDERS_REJECT_ORDER_RESPONSE = onCraftingOrderResponse,

	MAIL_INBOX_UPDATE = function(self)
		callOptional(self, "OnMailInboxUpdate")
		callOptional(self, "DeleteEmptiedPackMail")
	end,
	MAIL_SEND_SUCCESS = "OnMailSendSuccess",
	MAIL_FAILED = "OnMailSendFailed",
}
Tradewright.EVENT_HANDLERS = EVENT_HANDLERS

Tradewright.frame:SetScript("OnEvent", function(_, event, ...)
	callOptional(Tradewright, "DebugLogEvent", event, ...)
	local handler = EVENT_HANDLERS[event]
	if type(handler) == "string" then
		callOptional(Tradewright, handler, ...)
	elseif handler then
		handler(Tradewright, ...)
	end
end)

for event in pairs(EVENT_HANDLERS) do
	-- pcall: some events do not exist on every client (Forever lacks the retail AH and crafting orders).
	pcall(Tradewright.frame.RegisterEvent, Tradewright.frame, event)
end
