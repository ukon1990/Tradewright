local AuctionHelper = select(2, ...)

local InventoryTab = {}
AuctionHelper.InventoryTab = InventoryTab

function InventoryTab:Create(container, uiState)
	AuctionHelper:EnsureInventoryPanel(container)
	uiState.inventoryPanel:Show()
	uiState.inventoryPanel:SetAllPoints()
	return uiState.inventoryPanel
end

function InventoryTab:ApplyTheme()
	local ui = AuctionHelper.ui
	if not ui or not ui.inventoryPanel then
		return
	end
end

function InventoryTab:Refresh()
	if AuctionHelper.ui and AuctionHelper.ui.inventoryPanel then
		AuctionHelper.ui.inventoryPanel:Show()
	end
	AuctionHelper:RefreshInventoryTab()
end
