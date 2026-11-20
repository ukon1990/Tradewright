local ProfessionExporter = select(2, ...)

-- The dashboard tabs, left to right. Each module is looked up when the tab is first shown.
ProfessionExporter.DASHBOARD_TABS = {
	{ id = "overview", label = "Overview", module = function() return ProfessionExporter.OverviewTab end },
	{ id = "opportunities", label = "Opportunities", module = function() return ProfessionExporter.OpportunitiesTab end },
	{ id = "inventory", label = "Inventory", module = function() return ProfessionExporter.InventoryTab end },
	{ id = "market", label = "Market", module = function() return ProfessionExporter.MarketTab end },
	{ id = "crafts", label = "Crafts", module = function() return ProfessionExporter.CraftsTab end },
	{ id = "export", label = "Export", module = function() return ProfessionExporter.ExportTab end },
	{ id = "docs", label = "Docs", module = function() return ProfessionExporter.DocsTab end },
	{ id = "settings", label = "Settings", module = function() return ProfessionExporter.SettingsTab end },
}
