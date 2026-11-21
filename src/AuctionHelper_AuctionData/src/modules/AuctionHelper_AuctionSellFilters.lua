-- The sell tab's filter widgets: search box, check buttons, class and expansion dropdowns, and their reset.
local _, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local panelButton = shared.panelButton

-- Check button that stores its checked state in ui[uiKey] and refreshes the panel.
local function filterCheckButton(panel, ui, point, label, uiKey)
	local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	check:SetPoint(point[1], point[2], point[3], point[4], point[5])
	local text = check.Text or (check.GetName and check:GetName() and _G[check:GetName() .. "Text"]) or nil
	if text then
		text:SetText(label)
	end
	check:SetScript("OnClick", function(btn)
		ui[uiKey] = btn:GetChecked() == true
		AuctionHelper:RefreshAuctionHousePanel()
	end)
	return check
end

-- Search box plus the crafted-only / profitable-only check buttons.
local function buildSellSearchFilters(panel, ui, w)
	local search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	search:SetSize(118, 20)
	search:SetAutoFocus(false)
	search:SetPoint("TOPLEFT", w.btnPostProfitable, "BOTTOMLEFT", 6, -8)
	search:SetScript("OnTextChanged", function(box)
		ui.ahFilterText = box:GetText() or ""
		AuctionHelper:RefreshAuctionHousePanel()
	end)
	panel.searchBox = search
	w.search = search
	w.craftedOnly = filterCheckButton(panel, ui, { "LEFT", search, "RIGHT", 6, -1 }, "Crafted only", "ahCraftedOnly")
	panel.craftedOnly = w.craftedOnly
	w.profitableOnly = filterCheckButton(panel, ui, { "LEFT", w.craftedOnly, "RIGHT", 54, 0 }, "Profitable only", "ahProfitableOnly")
	panel.profitableOnly = w.profitableOnly
end

local function buildClassDropdowns(self, panel, ui, w)
	ui.ahClassDropdown = self:CreateFilterDropdown(panel, {
		label = "Class",
		allLabel = "All classes",
		width = 114,
		uiKey = "ahClassFilterValues",
		onChanged = function()
			ui.ahSubclassFilterValues = {}
			AuctionHelper:RefreshAuctionHousePanel()
		end,
	})
	ui.ahClassDropdown:SetPoint("TOPLEFT", w.search, "BOTTOMLEFT", 0, -8)
	panel.classDropdown = ui.ahClassDropdown
	ui.ahSubclassDropdown = self:CreateFilterDropdown(panel, {
		label = "Subclass",
		allLabel = "All subclasses",
		width = 114,
		uiKey = "ahSubclassFilterValues",
		onChanged = function()
			AuctionHelper:RefreshAuctionHousePanel()
		end,
	})
	ui.ahSubclassDropdown:SetPoint("TOPLEFT", ui.ahClassDropdown, "TOPRIGHT", 4, 0)
	panel.subclassDropdown = ui.ahSubclassDropdown
end

local function copyBoolMap(t)
	local out = {}
	if type(t) == "table" then
		for k, v in pairs(t) do
			if v then
				out[k] = true
			end
		end
	end
	return out
end

local function buildExpansionDropdown(self, panel, ui)
	ui.ahExpansionFilterValues = copyBoolMap(self:GetSetting("auction.selectedExpansions", {}))
	ui.ahExpansionDropdown = self:CreateFilterDropdown(panel, {
		label = "Expansion",
		width = 114,
		allLabel = "All expansions",
		uiKey = "ahExpansionFilterValues",
		setting = "auction.selectedExpansions",
		getOptions = function()
			return AuctionHelper:GetExpansionFilterOptions()
		end,
		onChanged = function()
			AuctionHelper:RefreshAuctionHousePanel()
		end,
	})
	ui.ahExpansionDropdown:SetPoint("TOPLEFT", ui.ahSubclassDropdown, "TOPRIGHT", 4, 0)
	panel.expansionDropdown = ui.ahExpansionDropdown
end

local function resetSellFilters(panel, ui)
	ui.ahFilterText = ""
	ui.ahCraftedOnly = false
	ui.ahProfitableOnly = false
	ui.ahClassFilterValues = {}
	ui.ahSubclassFilterValues = {}
	ui.ahExpansionFilterValues = {}
	panel.searchBox:SetText("")
	panel.craftedOnly:SetChecked(false)
	panel.profitableOnly:SetChecked(false)
	AuctionHelper:SetSetting("auction.selectedExpansions", {})
	if ui.ahClassDropdown then
		ui.ahClassDropdown:RefreshText()
	end
	if ui.ahSubclassDropdown then
		ui.ahSubclassDropdown:RefreshText()
	end
	if ui.ahExpansionDropdown then
		ui.ahExpansionDropdown:RefreshText()
	end
	AuctionHelper:RefreshAuctionHousePanel()
end

function AuctionHelper:BuildAuctionSellFilters(panel, ui, w)
	buildSellSearchFilters(panel, ui, w)
	buildClassDropdowns(self, panel, ui, w)
	buildExpansionDropdown(self, panel, ui)
	w.clearBtn = panelButton(panel, { 52, 18 }, "Reset filters", { "LEFT", w.profitableOnly, "RIGHT", 48, 0 }, function()
		resetSellFilters(panel, ui)
	end)
	panel.clearBtn = w.clearBtn
end

function AuctionHelper:ApplyAuctionSellFilterDefaults(ui)
	ui.ahSortKey = ui.ahSortKey or "potentialROI"
	if ui.ahSortAsc == nil then
		ui.ahSortAsc = false
	end
	if ui.ahFilterText == nil then
		ui.ahFilterText = ""
	end
	if ui.ahCraftedOnly == nil then
		ui.ahCraftedOnly = false
	end
	if ui.ahProfitableOnly == nil then
		ui.ahProfitableOnly = false
	end
	ui.ahClassFilterValues = ui.ahClassFilterValues or {}
	ui.ahSubclassFilterValues = ui.ahSubclassFilterValues or {}
	ui.ahExpansionFilterValues = ui.ahExpansionFilterValues or {}
end

function AuctionHelper:SyncAuctionSellFilterWidgets(panel, ui)
	panel.searchBox:SetText(ui.ahFilterText or "")
	panel.craftedOnly:SetChecked(ui.ahCraftedOnly == true)
	panel.profitableOnly:SetChecked(ui.ahProfitableOnly == true)
	panel.classDropdown:RefreshText()
	panel.subclassDropdown:RefreshText()
	if panel.expansionDropdown then
		panel.expansionDropdown:RefreshText()
	end
	self:RefreshAuctionPanelRules()
end
