local AuctionHelper = select(2, ...)

local CraftsTab = {}
AuctionHelper.CraftsTab = CraftsTab

function CraftsTab:Create(container, uiState)
	AuctionHelper:EnsureCraftsPanel(container)
	local panel = uiState.craftsPanel
	if panel then
		panel:SetAllPoints()
		panel:Show()
	end
	return panel
end

function CraftsTab:ApplyTheme()
	local ui = AuctionHelper.ui
	if not ui or not ui.craftsPanel then
		return
	end
	AuctionHelper:LayoutCraftsPanel(ui.craftsPanel)
end

function CraftsTab:Refresh()
	if AuctionHelper.ui and AuctionHelper.ui.craftsPanel then
		AuctionHelper.ui.craftsPanel:Show()
	end
	AuctionHelper:RefreshCraftsTab()
end
