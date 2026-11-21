local AuctionHelper = select(2, ...)

-- The dashboard tabs, left to right. Each module is looked up when the tab is first shown.
AuctionHelper.DASHBOARD_TABS = {
	{ id = "overview", label = "Overview", module = function() return AuctionHelper.OverviewTab end },
	{ id = "opportunities", label = "Opportunities", module = function() return AuctionHelper.OpportunitiesTab end },
	{ id = "inventory", label = "Inventory", module = function() return AuctionHelper.InventoryTab end },
	{ id = "market", label = "Market", module = function() return AuctionHelper.MarketTab end },
	{ id = "crafts", label = "Crafts", module = function() return AuctionHelper.CraftsTab end },
	{ id = "farming", label = "Farming", module = function() return AuctionHelper.FarmingTab end },
	{ id = "export", label = "Export", module = function() return AuctionHelper.ExportTab end },
	{ id = "docs", label = "Docs", module = function() return AuctionHelper.DocsTab end },
	{ id = "settings", label = "Settings", module = function() return AuctionHelper.SettingsTab end },
}
