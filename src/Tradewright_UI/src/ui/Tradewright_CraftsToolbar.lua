local _, Tradewright = ...

-- Crafts tab toolbar: the search and filter row, and the row of pricing options under it.

local PROFIT_CHOICES = {
	{ value = "all", label = "All crafts" }, { value = "profitable", label = "Profitable" }, { value = "negative", label = "Losing money" },
	{ value = "missing_price", label = "Missing price" }, { value = "uncraftable", label = "Can't craft now" },
	{ value = "cooldown", label = "Cooldowns" },
}
local SOURCE_CHOICES = {
	{ value = "owned_first", label = "Use what I own" }, { value = "market_only", label = "Buy everything" }, { value = "mixed", label = "Mixed" },
}
local BASIS_CHOICES = { { value = "auto", label = "Auto" }, { value = "market", label = "Auction house" }, { value = "ledger", label = "My own sales" } }
local SCENARIO_CHOICES = { { value = "default", label = "No concentration" }, { value = "concentration", label = "With concentration" } }

local function refreshCrafts(pe)
	return function() pe:RefreshCraftsTab() end
end

-- A craft filter whose selection is kept in `ui[uiKey]` and saved in `setting`.
local function createFilter(pe, parent, options)
	options.onChanged = refreshCrafts(pe)
	return pe:CreateFilterDropdown(parent, options)
end

-- A label to the left of a control, as one 26px-high group.
local function labelled(pe, parent, label, control)
	local group = CreateFrame("Frame", nil, parent)
	group:SetHeight(26)
	group.label = pe:CreateText(group, "GameFontHighlightSmall", "textMuted")
	group.label:SetPoint("LEFT")
	group.label:SetText(label)
	control:SetParent(group)
	control:ClearAllPoints()
	control:SetPoint("LEFT", group.label, "RIGHT", 6, 0)
	group:SetWidth(math.ceil(group.label:GetStringWidth()) + 6 + control:GetWidth())
	return group
end

local function copyBoolMap(t)
	local out = {}
	for k, v in pairs(type(t) == "table" and t or {}) do
		if v then
			out[k] = true
		end
	end
	return out
end

-- The saved filter selections, copied into `ui` where the dropdowns read and change them.
function Tradewright:RestoreCraftsFilterSelections()
	local ui = self.ui
	ui.craftsCharacterFilterValues = copyBoolMap(self:GetSetting("crafts.characterFilter", {}))
	ui.craftsProfessionFilterValues = copyBoolMap(self:GetSetting("crafts.professionFilter", {}))
	ui.craftsExpansionFilterValues = copyBoolMap(self:GetSetting("crafts.selectedExpansions", {}))
	ui.craftsCategoryFilterValues = copyBoolMap(self:GetSetting("crafts.categoryFilter", {}))
end

function Tradewright:ResetCraftsFilters()
	local ui = self.ui
	ui.craftsCharacterFilterValues = {}
	ui.craftsProfessionFilterValues = {}
	ui.craftsExpansionFilterValues = {}
	ui.craftsCategoryFilterValues = {}
	ui.craftsSearchBox:SetText("")
	ui.craftsSearchBox:UpdatePlaceholder()
	for _, key in ipairs({ "crafts.characterFilter", "crafts.professionFilter", "crafts.categoryFilter", "crafts.selectedExpansions" }) do
		self:SetSetting(key, {})
	end
	self:SetSetting("crafts.profitState", "all")
	self:RefreshCraftsTab()
end

-- Profit, category, profession, (retail) expansion and character filters, right to left after `chain`.
function Tradewright:CreateCraftsFilterDropdowns(parent, chain)
	local pe, ui = self, self.ui
	ui.craftsProfitDropdown = self:CreateSettingDropdown(parent, {
		setting = "crafts.profitState", default = "all", width = 112, choices = PROFIT_CHOICES, onChanged = refreshCrafts(self),
	})
	ui.craftsCategoryDropdown = createFilter(self, parent, { width = 120, allLabel = "All categories",
		getOptions = function() return pe:GetCraftCategoryFilterOptions(ui.craftsUnfilteredRows or {}) end,
		uiKey = "craftsCategoryFilterValues", setting = "crafts.categoryFilter" })
	ui.craftsProfessionDropdown = createFilter(self, parent, { width = 128, allLabel = "All professions",
		getOptions = function() return pe:GetCraftProfessionFilterOptions() end,
		uiKey = "craftsProfessionFilterValues", setting = "crafts.professionFilter" })
	ui.craftsCharacterDropdown = createFilter(self, parent, { width = 132, allLabel = "All characters",
		getOptions = function() return pe:GetInventoryCharacterFilterOptions() end,
		uiKey = "craftsCharacterFilterValues", setting = "crafts.characterFilter" })
	for _, dropdown in ipairs({ ui.craftsProfitDropdown, ui.craftsCategoryDropdown, ui.craftsProfessionDropdown }) do
		chain[#chain + 1] = dropdown
	end
	if self.IS_RETAIL then
		ui.craftsExpansionDropdown = createFilter(self, parent, { width = 120, allLabel = "All expansions",
			getOptions = function() return pe:GetExpansionFilterOptions() end,
			uiKey = "craftsExpansionFilterValues", setting = "crafts.selectedExpansions" })
		chain[#chain + 1] = ui.craftsExpansionDropdown
	end
	chain[#chain + 1] = ui.craftsCharacterDropdown
	self:ChainLeft(chain, 8)
end

-- Row 1: Refresh and Reset at the right, the filter dropdowns, and the search box filling the rest.
function Tradewright:CreateCraftsFilterRow(panel)
	local pe, ui = self, self.ui
	panel.filters = CreateFrame("Frame", nil, panel)
	panel.filters:SetPoint("TOPLEFT")
	panel.filters:SetPoint("TOPRIGHT")
	panel.filters:SetHeight(26)
	panel.refreshButton = self:CreateButton(panel.filters, "Refresh", function() pe:RefreshCraftsTab() end, { primary = true })
	panel.refreshButton:SetPoint("RIGHT")
	ui.craftsClearBtn = self:CreateButton(panel.filters, "Reset", function() pe:ResetCraftsFilters() end,
		{ tooltip = "Clear the search and every filter." })
	self:CreateCraftsFilterDropdowns(panel.filters, { panel.refreshButton, ui.craftsClearBtn })
	ui.craftsSearchBox = self:CreateSearchBox(panel.filters, "Search item or recipe", function()
		pe:RefreshCraftsTab()
	end)
	ui.craftsSearchBox:SetPoint("LEFT", 6, 0)
	ui.craftsSearchBox:SetPoint("RIGHT", ui.craftsCharacterDropdown, "LEFT", -14, 0)
end

-- Materials source, price basis and history range (and on retail the concentration scenario), each labelled.
function Tradewright:CreateCraftsPriceDropdowns(panel)
	local pe, ui = self, self.ui
	panel.sourceDropdown = self:CreateSettingDropdown(panel, {
		setting = "crafts.reagentSourceMode", default = "owned_first", width = 110, choices = SOURCE_CHOICES,
		onChanged = refreshCrafts(self), tooltip = "Use what I own: reagents you hold cost nothing. Buy everything: all are priced at the auction house.",
	})
	panel.basisDropdown = self:CreateSettingDropdown(panel, {
		setting = "crafts.costBasis", default = "auto", width = 92, choices = BASIS_CHOICES,
		onChanged = function(value)
			pe:SetSetting("crafts.saleBasis", value == "market" and "market" or value == "ledger" and "ledger" or "auto")
			pe:RefreshCraftsTab()
		end,
		tooltip = "Auction house: prices from your scans. My own sales: what you sold and bought for. Auto: your own where known.",
	})
	panel.craftsRangeDropdown = self:CreateSettingDropdown(panel, {
		setting = "inventory.metricRange", default = "30d", width = 92, choices = self:GetInventoryMetricRangeOptions(),
		onChanged = function() pe:RenderCraftsDetails(ui.craftsSelectedRowData) end, tooltip = "Time range for price history",
	})
	local groups = {
		labelled(self, panel.options, "Reagents", panel.sourceDropdown),
		labelled(self, panel.options, "Prices from", panel.basisDropdown),
		labelled(self, panel.options, "History", panel.craftsRangeDropdown),
	}
	if self.IS_RETAIL then
		panel.scenarioDropdown = self:CreateSettingDropdown(panel, {
			setting = "crafts.scenario", default = "default", width = 140, choices = SCENARIO_CHOICES, onChanged = refreshCrafts(self),
		})
		groups[#groups + 1] = labelled(self, panel.options, "Concentration", panel.scenarioDropdown)
	end
	return groups
end

-- Row 2: how prices are worked out, with a note at the right.
function Tradewright:CreateCraftsOptionsRow(panel)
	panel.options = CreateFrame("Frame", nil, panel)
	panel.options:SetPoint("TOPLEFT", panel.filters, "BOTTOMLEFT", 0, -8)
	panel.options:SetPoint("TOPRIGHT", panel.filters, "BOTTOMRIGHT", 0, -8)
	panel.options:SetHeight(26)
	local groups = self:CreateCraftsPriceDropdowns(panel)
	groups[1]:SetPoint("LEFT")
	self:ChainRight(groups, 16)
	panel.optionsNote = self:CreateText(panel.options, "GameFontHighlightSmall", "textMuted", "RIGHT")
	panel.optionsNote:SetPoint("RIGHT")
	panel.optionsNote:SetPoint("LEFT", groups[#groups], "RIGHT", 16, 0)
end
