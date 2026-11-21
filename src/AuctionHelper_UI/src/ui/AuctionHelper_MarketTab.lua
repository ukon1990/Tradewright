local AuctionHelper = select(2, ...)

local MarketTab = {}
AuctionHelper.MarketTab = MarketTab

function MarketTab:Create(container, uiState)
	AuctionHelper:EnsureMarketPanel(container)
	local panel = uiState.marketPanel
	if panel then
		panel:SetAllPoints()
		panel:Show()
	end
	return panel
end

function MarketTab:ApplyTheme()
	local ui = AuctionHelper.ui
	if not ui or not ui.marketPanel then
		return
	end
	AuctionHelper:LayoutMarketPanel(ui.marketPanel)
end

function MarketTab:Refresh()
	if AuctionHelper.ui and AuctionHelper.ui.marketPanel then
		AuctionHelper.ui.marketPanel:Show()
	end
	AuctionHelper:RefreshMarketTab()
end
