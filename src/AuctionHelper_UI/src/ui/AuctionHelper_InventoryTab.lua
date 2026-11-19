local ProfessionExporter = select(2, ...)

local InventoryTab = {}
ProfessionExporter.InventoryTab = InventoryTab

function InventoryTab:Create(container, uiState)
	ProfessionExporter:EnsureInventoryPanel(container)
	uiState.inventoryPanel:Show()
	uiState.inventoryPanel:SetAllPoints()
	return uiState.inventoryPanel
end

function InventoryTab:ApplyTheme()
	local ui = ProfessionExporter.ui
	if not ui or not ui.inventoryPanel then
		return
	end
end

function InventoryTab:Refresh()
	if ProfessionExporter.ui and ProfessionExporter.ui.inventoryPanel then
		ProfessionExporter.ui.inventoryPanel:Show()
	end
	ProfessionExporter:RefreshInventoryTab()
end
