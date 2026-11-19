local ProfessionExporter = select(2, ...)

local MarketTab = {}
ProfessionExporter.MarketTab = MarketTab

function MarketTab:Create(container, uiState)
	ProfessionExporter:EnsureMarketPanel(container)
	local panel = uiState.marketPanel
	if panel then
		panel:SetAllPoints()
		panel:Show()
	end
	return panel
end

function MarketTab:ApplyTheme()
	local ui = ProfessionExporter.ui
	if not ui or not ui.marketPanel then
		return
	end
	ProfessionExporter:LayoutMarketPanel(ui.marketPanel)
end

function MarketTab:Refresh()
	if ProfessionExporter.ui and ProfessionExporter.ui.marketPanel then
		ProfessionExporter.ui.marketPanel:Show()
	end
	ProfessionExporter:RefreshMarketTab()
end
