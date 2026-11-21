local AuctionHelper = select(2, ...)

--- A dashboard tab showing one panel, named after `id` ("crafts"): Ensure<Id>Panel builds ui.<id>Panel,
--- Layout<Id>Panel lays it out again when the theme changes and Refresh<Id>Tab fills it.
function AuctionHelper:MakePanelTab(id)
	local name = id:sub(1, 1):upper() .. id:sub(2)
	local panelKey = id .. "Panel"
	local pe = self
	local tab = {}
	function tab:Create(container, ui)
		pe["Ensure" .. name .. "Panel"](pe, container)
		local panel = ui[panelKey]
		if panel then
			panel:SetAllPoints()
			panel:Show()
		end
		return panel
	end
	function tab:ApplyTheme()
		local panel = pe.ui and pe.ui[panelKey]
		if panel then
			pe["Layout" .. name .. "Panel"](pe, panel)
		end
	end
	function tab:Refresh()
		local panel = pe.ui and pe.ui[panelKey]
		if panel then
			panel:Show()
		end
		pe["Refresh" .. name .. "Tab"](pe)
	end
	return tab
end

-- The dashboard tabs, left to right. Each module is looked up (or made) when the tab is first shown.
AuctionHelper.DASHBOARD_TABS = {
	{ id = "overview", label = "Overview", module = function() return AuctionHelper.OverviewTab end },
	{ id = "opportunities", label = "Opportunities", module = function() return AuctionHelper.OpportunitiesTab end },
	{ id = "inventory", label = "Inventory", module = function() return AuctionHelper:MakePanelTab("inventory") end },
	{ id = "market", label = "Market", module = function() return AuctionHelper:MakePanelTab("market") end },
	{ id = "crafts", label = "Crafts", module = function() return AuctionHelper:MakePanelTab("crafts") end },
	{ id = "farming", label = "Farming", module = function() return AuctionHelper.FarmingTab end },
	{ id = "export", label = "Export", module = function() return AuctionHelper.ExportTab end },
	{ id = "docs", label = "Docs", module = function() return AuctionHelper.DocsTab end },
	{ id = "settings", label = "Settings", module = function() return AuctionHelper.SettingsTab end },
}
