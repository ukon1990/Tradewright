local ProfessionExporter = select(2, ...)

local CraftsTab = {}
ProfessionExporter.CraftsTab = CraftsTab

function CraftsTab:Create(container, uiState)
	ProfessionExporter:EnsureCraftsPanel(container)
	local panel = uiState.craftsPanel
	if panel then
		panel:SetAllPoints()
		panel:Show()
	end
	return panel
end

function CraftsTab:ApplyTheme()
	local ui = ProfessionExporter.ui
	if not ui or not ui.craftsPanel then
		return
	end
	ProfessionExporter:LayoutCraftsPanel(ui.craftsPanel)
end

function CraftsTab:Refresh()
	if ProfessionExporter.ui and ProfessionExporter.ui.craftsPanel then
		ProfessionExporter.ui.craftsPanel:Show()
	end
	ProfessionExporter:RefreshCraftsTab()
end
