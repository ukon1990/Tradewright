local addonName, AuctionHelper = ...

function AuctionHelper:ADDON_LOADED(loadedAddonName)
	local tracked = {
		[addonName] = true,
		["AuctionHelper_AuctionData"] = true,
		["AuctionHelper_Professions"] = true,
		["AuctionHelper_Inventory"] = true,
		["AuctionHelper_UI"] = true,
		["AuctionHelper_Bags"] = true,
	}
	if not tracked[loadedAddonName] then
		return
	end

	self:InitDB()
	AuctionHelperLastExport = AuctionHelperLastExport or {}
	self.baseDb.meta.familyLoaded = self.baseDb.meta.familyLoaded or {}
	self.baseDb.meta.familyLoaded[loadedAddonName] = time()
	if loadedAddonName == addonName then
		self.baseDb.meta.lastLoad = {
			loadedAt = time(),
			addonVersion = self.VERSION,
			schemaVersion = self.SCHEMA_VERSION,
			build = self:GetBuildMetadata(),
		}
	end
end

function AuctionHelper:PLAYER_LOGIN()
	if self.RecordWalletObservation then
		C_Timer.After(0.5, function()
			AuctionHelper:RecordWalletObservation(AuctionHelper:GetCharacterKey(), GetMoney(), time())
		end)
	end
	SLASH_AUCTIONHELPER1 = "/ah"
	SLASH_AUCTIONHELPER2 = "/auctionhelper"
	SlashCmdList.AUCTIONHELPER = function(input)
		AuctionHelper:HandleSlash(input)
	end

	self:EnsureMinimapButton()
	self:RegisterBlizzardSettings()
	self:InitProfessionCraftEconomyHooks()
	if self.InitItemTooltipPricingHooks then
		self:InitItemTooltipPricingHooks()
	end
	if self.InitCraftingOrdersFilters then
		self:InitCraftingOrdersFilters()
	end
	if self.InitDynamicLayeringHooks then
		self:InitDynamicLayeringHooks()
	end
	if self.InitMailPanelHooks then
		self:InitMailPanelHooks()
	end
	self:PrintMessage("Loaded. /ah (or /auctionhelper) opens the main window. Exports are compact AuctionHelper packages and can be written to AuctionHelperLastExport on /reload.")
end

function AuctionHelper:TRADE_SKILL_SHOW()
	if self.InitCraftingOrdersFilters then
		self:InitCraftingOrdersFilters()
	end
	self:TryScanCurrentProfession()
	self:RememberOpenProfessionSkillLineID()
	self:InitProfessionCraftEconomyHooks()
	if self.ScheduleRefreshProfessionCraftEconomyPanel then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
	if self.RecordExternalFrameInteraction then
		self:RecordExternalFrameInteraction("ProfessionsFrame", "trade_skill_show")
	end
end

function AuctionHelper:TRADE_SKILL_LIST_UPDATE()
	self:TryScanCurrentProfession()
	self:RememberOpenProfessionSkillLineID()
	if self.ScheduleRefreshProfessionCraftEconomyPanel then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
	if self.UpdateDynamicPanelLayering then
		self:UpdateDynamicPanelLayering("trade_skill_list_update")
	end
end

function AuctionHelper:UPDATE_TRADESKILL_CAST_STOPPED()
	if self.ScheduleRefreshProfessionCraftEconomyPanel then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
	if self.UpdateDynamicPanelLayering then
		self:UpdateDynamicPanelLayering("trade_skill_cast_stopped")
	end
end

function AuctionHelper:TRADE_SKILL_CLOSE()
	self:TryScanCurrentProfession()
	self:ApplyLiveProfessionMergeOnWindowClose()
	if self.ScheduleRefreshProfessionCraftEconomyPanel then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
	if self.UpdateDynamicPanelLayering then
		self:UpdateDynamicPanelLayering("trade_skill_close")
	end
end

function AuctionHelper:PLAYER_INTERACTION_MANAGER_FRAME_SHOW(interactionType)
	if self.UpdateDynamicPanelLayering then
		self:UpdateDynamicPanelLayering("interaction_show_" .. tostring(interactionType))
	end
end

function AuctionHelper:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(interactionType)
	if self.UpdateDynamicPanelLayering then
		self:UpdateDynamicPanelLayering("interaction_hide_" .. tostring(interactionType))
	end
end

function AuctionHelper:BAG_UPDATE_DELAYED()
	self:ScheduleLiveInventoryRefresh()
	if self.ClearSettledAuctionCartPurchaseCredits then
		self:ClearSettledAuctionCartPurchaseCredits()
	end
	if self.OnAuctionBagUpdate then
		self:OnAuctionBagUpdate()
	end
	if self.RefreshAuctionHousePanel and self.IsAuctionHouseFrameOpen and self:IsAuctionHouseFrameOpen() then
		self:RefreshAuctionHousePanel()
	end
	if self.RefreshMailPanel and _G.MailFrame and MailFrame:IsShown() then
		self:RefreshMailPanel()
	end
end

function AuctionHelper:BANKFRAME_OPENED()
	self:ScheduleLiveInventoryRefresh()
end

function AuctionHelper:AUCTION_HOUSE_SHOW()
	if self.OnAuctionHouseShow then
		self:OnAuctionHouseShow()
	end
end

function AuctionHelper:AUCTION_HOUSE_CLOSED()
	if self.OnAuctionHouseClosed then
		self:OnAuctionHouseClosed()
	end
end

function AuctionHelper:AUCTION_HOUSE_AUCTION_CREATED()
	self:DebugLog("AH", "event: AUCTION_HOUSE_AUCTION_CREATED", {
		"source=auction_created",
	})
	if self.OnAuctionHouseAuctionCreated then
		self:OnAuctionHouseAuctionCreated()
	end
end

function AuctionHelper:AUCTION_HOUSE_AUCTION_SOLD()
	self:DebugLog("AH", "event: AUCTION_HOUSE_AUCTION_SOLD", {
		"source=auction_sold",
	})
	if self.OnAuctionHouseAuctionSold then
		self:OnAuctionHouseAuctionSold()
	end
end

function AuctionHelper:MAIL_INBOX_UPDATE()
	if self.OnMailInboxUpdate then
		self:OnMailInboxUpdate()
	end
end

function AuctionHelper:AUCTION_CANCELED()
	if self.OnAuctionCanceled then
		self:OnAuctionCanceled()
	end
end

function AuctionHelper:OWNED_AUCTIONS_UPDATED()
	self:DebugLog("AH", "event: OWNED_AUCTIONS_UPDATED", {
		"source=owned_auctions_updated",
	})
	if self.OnOwnedAuctionsUpdated then
		self:OnOwnedAuctionsUpdated()
	end
	-- Retail-safe fallback signal for AH post/sold/cancel changes.
	if self.PrimeAuctionPanelRows then
		self:PrimeAuctionPanelRows()
	end
	if self.RefreshAuctionHousePanel then
		self:RefreshAuctionHousePanel()
	end
end

function AuctionHelper:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED(...)
	if self.OnAuctionHouseBrowseResultsUpdated then
		self:OnAuctionHouseBrowseResultsUpdated(...)
	end
end

function AuctionHelper:AUCTION_HOUSE_BROWSE_RESULTS_ADDED(...)
	if self.OnAuctionHouseBrowseResultsUpdated then
		self:OnAuctionHouseBrowseResultsUpdated(...)
	end
end

function AuctionHelper:COMMODITY_SEARCH_RESULTS_UPDATED(...)
	if self.OnCommoditySearchResultsUpdated then
		self:OnCommoditySearchResultsUpdated(...)
	end
end

function AuctionHelper:ITEM_SEARCH_RESULTS_UPDATED(...)
	if self.OnItemSearchResultsUpdated then
		self:OnItemSearchResultsUpdated(...)
	end
end

function AuctionHelper:REPLICATE_ITEM_LIST_UPDATE(...)
	if self.OnReplicateItemListUpdate then
		self:OnReplicateItemListUpdate(...)
	end
end

function AuctionHelper:AUCTION_ITEM_LIST_UPDATE(...)
	if self.OnAuctionItemListUpdate then
		self:OnAuctionItemListUpdate(...)
	end
end

function AuctionHelper:COMMODITY_PURCHASE_SUCCEEDED(...)
	if self.OnCommodityPurchaseSucceeded then
		self:OnCommodityPurchaseSucceeded(...)
	end
end

function AuctionHelper:COMMODITY_PURCHASED(...)
	if self.OnCommodityPurchased then
		self:OnCommodityPurchased(...)
	end
end

function AuctionHelper:ITEM_PURCHASED(...)
	if self.OnItemPurchased then
		self:OnItemPurchased(...)
	end
end

function AuctionHelper:AUCTION_HOUSE_PURCHASE_COMPLETED(...)
	if self.OnAuctionHousePurchaseCompleted then
		self:OnAuctionHousePurchaseCompleted(...)
	end
end

function AuctionHelper:COMMODITY_PURCHASE_FAILED(...)
	if self.OnCommodityPurchaseFailed then
		self:OnCommodityPurchaseFailed(...)
	end
end

function AuctionHelper:TRADE_SKILL_ITEM_CRAFTED_RESULT(...)
	if self.OnProfessionRecipeCraftedResult then
		self:OnProfessionRecipeCraftedResult(...)
	end
end

function AuctionHelper:NEW_RECIPE_LEARNED()
	self:ScheduleLiveProfessionRefresh()
end

function AuctionHelper:PLAYER_MONEY()
	if self.RecordWalletObservation then
		self:RecordWalletObservation(self:GetCharacterKey(), GetMoney(), time())
	end
	if self.RefreshShellStatus then
		self:RefreshShellStatus()
	end
end

function AuctionHelper:CRAFTINGORDERS_FULFILL_ORDER_RESPONSE(result, orderID)
	local ok = Enum.CraftingOrderResult and result == Enum.CraftingOrderResult.Ok
	if ok and self.OnCraftingOrderFulfilled then
		self:OnCraftingOrderFulfilled(orderID)
	end
end

function AuctionHelper:CRAFTINGORDERS_RELEASE_ORDER_RESPONSE(result, orderID)
	local ok = Enum.CraftingOrderResult and result == Enum.CraftingOrderResult.Ok
	if ok and self.OnCraftingOrderFulfilled then
		self:OnCraftingOrderFulfilled(orderID)
	end
end

function AuctionHelper:CRAFTINGORDERS_REJECT_ORDER_RESPONSE(result, orderID)
	local ok = Enum.CraftingOrderResult and result == Enum.CraftingOrderResult.Ok
	if ok and self.OnCraftingOrderFulfilled then
		self:OnCraftingOrderFulfilled(orderID)
	end
end

function AuctionHelper:MAIL_SEND_SUCCESS()
	if self.OnMailSendSuccess then
		self:OnMailSendSuccess()
	end
end

function AuctionHelper:MAIL_FAILED()
	if self.OnMailSendFailed then
		self:OnMailSendFailed()
	end
end

AuctionHelper.frame:SetScript("OnEvent", function(_, event, ...)
	if AuctionHelper.DebugLogEvent then
		AuctionHelper:DebugLogEvent(event, ...)
	end
	if AuctionHelper[event] then
		AuctionHelper[event](AuctionHelper, ...)
	end
end)

local function safeRegisterEvent(eventName)
	local ok = pcall(AuctionHelper.frame.RegisterEvent, AuctionHelper.frame, eventName)
	return ok
end

AuctionHelper.frame:RegisterEvent("ADDON_LOADED")
AuctionHelper.frame:RegisterEvent("PLAYER_LOGIN")
AuctionHelper.frame:RegisterEvent("PLAYER_MONEY")
AuctionHelper.frame:RegisterEvent("TRADE_SKILL_SHOW")
AuctionHelper.frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
AuctionHelper.frame:RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED")
AuctionHelper.frame:RegisterEvent("TRADE_SKILL_CLOSE")
AuctionHelper.frame:RegisterEvent("BAG_UPDATE_DELAYED")
AuctionHelper.frame:RegisterEvent("BANKFRAME_OPENED")
AuctionHelper.frame:RegisterEvent("AUCTION_HOUSE_SHOW")
AuctionHelper.frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
safeRegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
safeRegisterEvent("AUCTION_HOUSE_AUCTION_SOLD")
safeRegisterEvent("OWNED_AUCTIONS_UPDATED")
safeRegisterEvent("AUCTION_CANCELED")
safeRegisterEvent("MAIL_INBOX_UPDATE")
safeRegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
safeRegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
safeRegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
safeRegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
safeRegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
safeRegisterEvent("AUCTION_ITEM_LIST_UPDATE")
safeRegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
safeRegisterEvent("COMMODITY_PURCHASE_FAILED")
safeRegisterEvent("COMMODITY_PURCHASED")
safeRegisterEvent("ITEM_PURCHASED")
safeRegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
safeRegisterEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT")
AuctionHelper.frame:RegisterEvent("NEW_RECIPE_LEARNED")
AuctionHelper.frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
AuctionHelper.frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
safeRegisterEvent("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE")
safeRegisterEvent("CRAFTINGORDERS_RELEASE_ORDER_RESPONSE")
safeRegisterEvent("CRAFTINGORDERS_REJECT_ORDER_RESPONSE")
safeRegisterEvent("MAIL_SEND_SUCCESS")
safeRegisterEvent("MAIL_FAILED")
