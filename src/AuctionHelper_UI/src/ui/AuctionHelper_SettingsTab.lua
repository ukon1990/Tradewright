local _, ProfessionExporter = ...

local SettingsTab = {}
ProfessionExporter.SettingsTab = SettingsTab

local COLUMN_GAP = 24
local SECTION_GAP = 16
local ROW_GAP = 6
local SELECT_WIDTH = 150

local function refreshEconomy(pe)
	pe:RefreshInventoryTabIfVisible()
	pe:RefreshCraftsTabIfVisible()
end

local function refreshCraftingOrders(pe)
	if pe.RefreshCraftingOrdersPageRecipeList then
		pe:RefreshCraftingOrdersPageRecipeList()
	end
	if pe.SyncCraftingOrdersFilterBarFromSettings then
		pe:SyncCraftingOrdersFilterBarFromSettings()
	end
end

local function numberOptions(values, format)
	local options = {}
	for _, value in ipairs(values) do
		options[#options + 1] = { value = value, label = string.format(format, value) }
	end
	return options
end

local function auctionHouseItems(pe)
	return {
		{ kind = "select", label = "Keep price history for", path = "auction.historyRetentionDays", default = 30,
			options = numberOptions({ 7, 14, 30, 60, 90 }, "%d days"),
			onChange = function() if pe.TrimFullDumpMarketHistory then pe:TrimFullDumpMarketHistory() end end },
		{ kind = "select", label = "Usual price looks back", path = "auction.usualPriceDays", default = 14,
			options = numberOptions({ 7, 14, 30 }, "%d days"), onChange = refreshEconomy },
		{ kind = "select", label = "Keep daily prices for", path = "auction.dailyRetentionDays", default = 180,
			options = numberOptions({ 90, 180, 365 }, "%d days") },
		{ kind = "check", label = "Keep the cheapest price steps of each item from a full scan", path = "auction.keepPriceSteps",
			default = true },
		{ kind = "select", label = "Refresh prices older than", path = "auction.priceFreshnessMinutes", default = 15,
			options = numberOptions({ 5, 15, 30, 60, 180 }, "%d minutes") },
		{ kind = "check", label = "Scan craft and reagent prices when the auction house opens",
			path = "auction.autoCraftEconomyRefreshOnOpen", default = false },
		{ kind = "check", label = "Include optional reagents in the craft scan", path = "auction.craftScanIncludeOptionalSlots", default = false },
		{ kind = "check", label = "Count the lost deposit when cancelling undercut auctions", path = "auction.repostIncludeDeposit", default = true },
	}
end

-- Every setting on the tab. kind: check | select | note. Sections go in `column` 1 or 2.
local function buildSections(pe)
	-- The auction house / bank character is chosen per realm, from the characters known there.
	local sellerOptions = { { value = "", label = "None" } }
	local realmKeys, realm = {}, "?"
	if pe.GetRealmCharacterKeys then
		realmKeys, realm = pe:GetRealmCharacterKeys()
	end
	for _, characterKey in ipairs(realmKeys) do
		sellerOptions[#sellerOptions + 1] = { value = characterKey, label = characterKey:match("^([^%-]+)") or characterKey }
	end
	local sections = {
		{ column = 1, title = "General", items = {
			{ kind = "check", label = "Show minimap button", path = "general.showMinimapButton", default = true,
				onChange = function() pe:EnsureMinimapButton() end },
			{ kind = "select", label = "Window scale", path = "appearance.windowScale", default = 1,
				options = pe:GetWindowScaleOptions(), onChange = function() pe:ApplyWindowScale() end },
		} },
		{ column = 1, title = "Profession scan", items = {
			{ kind = "check", label = "Capture specialization tree", path = "capture.captureSpecializationTree", default = true },
			{ kind = "check", label = "Include detailed recipe output data", path = "capture.includeRecipeOutputItemData", default = false },
			{ kind = "select", label = "Inventory items read per frame", path = "capture.inventorySnapshotBatchSize", default = 0,
				options = { { value = 0, label = "Automatic" }, { value = 50, label = "50" }, { value = 100, label = "100" } } },
		} },
		{ column = 1, title = "Inventory", items = {
			{ kind = "check", label = "Show price and profit columns by default", path = "inventory.economyShowColumns", default = true,
				onChange = refreshEconomy },
			{ kind = "check", label = "Estimate material cost", path = "inventory.economyShowMatCost", default = true, onChange = refreshEconomy },
			{ kind = "check", label = "Show TSM sale rate", path = "inventory.economyShowSaleRate", default = true, onChange = refreshEconomy },
		} },
		{ column = 1, title = "Troubleshooting", items = {
			{ kind = "check", label = "Write debug messages to chat", path = "debug.enabled", default = false },
		} },
		{ column = 2, title = "Auction house", items = auctionHouseItems(pe) },
		{ column = 2, title = "Mail", items = {
			{ kind = "select", label = "Auction house / bank character", path = "mail.sellerByRealm." .. realm, default = "",
				options = sellerOptions },
			{ kind = "check", label = "Mail collected materials to crafters when the mailbox opens", path = "mail.autoSendMaterials", default = true },
		} },
		{ column = 2, title = "Other price sources", items = {
			{ kind = "check", label = "Use Auctionator when there is no scanned price", path = "integrations.economyUseAuctionatorFallback",
				default = true, onChange = refreshEconomy },
			{ kind = "select", label = "TSM fallback price", path = "integrations.economyTSMFallbackString", default = "DBMinBuyout",
				options = { { value = "DBMinBuyout", label = "DBMinBuyout" }, { value = "dbmarket", label = "dbmarket" },
					{ value = "DBRecent", label = "DBRecent" } }, onChange = refreshEconomy },
			{ kind = "note", text = function()
				return string.format("TSM sources in use: market %s, materials %s, sale rate %s.",
					tostring(pe:GetSetting("integrations.economyTSMMarketString", "dbmarket")),
					tostring(pe:GetSetting("integrations.economyTSMMatString", "Crafting")),
					tostring(pe:GetSetting("integrations.economyTSMSaleRateString", "DBRegionSaleRate")))
			end },
		} },
	}
	local function percentOptions(values)
		local options = {}
		for _, value in ipairs(values) do
			options[#options + 1] = { value = value, label = string.format("%d%%", value * 100) }
		end
		return options
	end
	table.insert(sections, 3, { column = 1, title = "Gold dashboard", items = {
		{ kind = "select", label = "Deal when below usual price by", path = "gold.dealThreshold", default = 0.3,
			options = percentOptions({ 0.2, 0.3, 0.4, 0.5 }) },
		{ kind = "select", label = "Mover when price changed by", path = "gold.moverThreshold", default = 0.15,
			options = percentOptions({ 0.1, 0.15, 0.25 }) },
		{ kind = "select", label = "Usual price", path = "gold.reference", default = "best",
			options = { { value = "best", label = "TSM, else my scans" }, { value = "own", label = "My scans only" } } },
	} })
	if pe.IS_RETAIL then
		sections[#sections + 1] = { column = 2, title = "Crafting orders", items = {
			{ kind = "check", label = "Hide unlearned recipes in the orders list", path = "craftingOrders.hideUnlearned", default = false,
				onChange = refreshCraftingOrders },
			{ kind = "check", label = "Patron orders: only recipes that give knowledge", path = "craftingOrders.patronKnowledgeOnly",
				default = false, onChange = refreshCraftingOrders },
			{ kind = "note", text = "Uses the recipe list in the addon's data file. When that list is empty, the option does nothing." },
		} }
	end
	return sections
end

local function createItem(pe, parent, item)
	if item.kind == "check" then
		local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
		pe:SkinCheckButton(check)
		local label = check.Text or check.text
		if not label then
			label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			check.Text = label
		end
		label:ClearAllPoints()
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
		label:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(true)
		label:SetText(item.label)
		check:SetScript("OnClick", function(self)
			pe:SetSetting(item.path, self:GetChecked() == true)
			if item.onChange then
				item.onChange(pe)
			end
		end)
		item.control = check
		return
	end
	if item.kind == "select" then
		local row = CreateFrame("Frame", nil, parent)
		row:SetHeight(26)
		row.select = pe:CreateSingleSelectDropdown(row, {
			width = SELECT_WIDTH,
			getOptions = function() return item.options end,
			getValue = function() return pe:GetSetting(item.path, item.default) end,
			setValue = function(value) pe:SetSetting(item.path, value) end,
			onChanged = function()
				if item.onChange then
					item.onChange(pe)
				end
				SettingsTab:Refresh()
			end,
		})
		row.select:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.label = pe:CreateText(row, "GameFontHighlightSmall")
		row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.label:SetPoint("RIGHT", row.select, "LEFT", -12, 0)
		row.label:SetText(item.label)
		item.control = row
		return
	end
	item.control = pe:CreateParagraph(parent)
end

local function itemHeight(item)
	if item.kind == "check" then
		local label = item.control.Text
		return math.max(22, math.ceil(label and label:GetStringHeight() or 0) + 8)
	end
	if item.kind == "select" then
		return 26
	end
	return math.ceil(item.control:GetStringHeight())
end

function SettingsTab:Layout(panel)
	if not panel then
		return
	end
	local width = math.floor((panel:GetWidth() - COLUMN_GAP) / 2)
	local columns = { panel.columnLeft, panel.columnRight }
	for _, column in ipairs(columns) do
		column:SetWidth(width)
	end
	local y = { 0, 0 }
	for _, section in ipairs(panel.sections) do
		local column = columns[section.column]
		local top = y[section.column]
		section.heading:ClearAllPoints()
		section.heading:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -top)
		section.heading:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -top)
		top = top + 18 + 8
		for _, item in ipairs(section.items) do
			local control = item.control
			control:ClearAllPoints()
			if item.kind == "check" then
				control:SetPoint("TOPLEFT", column, "TOPLEFT", -4, -top)
			elseif item.kind == "select" then
				control:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -top)
				control:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -top)
			else
				control:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -top)
				control:SetWidth(width)
			end
			top = top + itemHeight(item) + ROW_GAP
		end
		y[section.column] = top + SECTION_GAP - ROW_GAP
	end
end

function SettingsTab:Create(container, uiState)
	local pe = ProfessionExporter
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.settingsPanel = panel

	panel.footer = CreateFrame("Frame", nil, panel)
	panel.footer:SetPoint("BOTTOMLEFT")
	panel.footer:SetPoint("BOTTOMRIGHT")
	panel.footer:SetHeight(26)
	panel.openGameSettings = pe:CreateButton(panel.footer, "Open game settings", function()
		pe:OpenBlizzardSettings()
	end)
	panel.openGameSettings:SetPoint("RIGHT")
	panel.footerNote = pe:CreateText(panel.footer, "GameFontHighlightSmall", "textMuted")
	panel.footerNote:SetPoint("LEFT")
	panel.footerNote:SetPoint("RIGHT", panel.openGameSettings, "LEFT", -12, 0)
	panel.footerNote:SetText("Changes apply at once and are saved for the whole account.")

	panel.columnLeft = CreateFrame("Frame", nil, panel)
	panel.columnLeft:SetPoint("TOPLEFT")
	panel.columnLeft:SetPoint("BOTTOM", panel.footer, "TOP", 0, 12)
	panel.columnRight = CreateFrame("Frame", nil, panel)
	panel.columnRight:SetPoint("TOPRIGHT")
	panel.columnRight:SetPoint("BOTTOM", panel.footer, "TOP", 0, 12)

	panel.sections = buildSections(pe)
	for _, section in ipairs(panel.sections) do
		local parent = section.column == 1 and panel.columnLeft or panel.columnRight
		section.heading = pe:CreateHeading(parent, section.title)
		for _, item in ipairs(section.items) do
			createItem(pe, parent, item)
		end
	end

	panel:SetScript("OnSizeChanged", function()
		SettingsTab:Layout(panel)
	end)
	return panel
end

function SettingsTab:ApplyTheme()
end

function SettingsTab:Refresh()
	local pe = ProfessionExporter
	local panel = pe.ui.settingsPanel
	if not panel then
		return
	end
	for _, section in ipairs(panel.sections) do
		for _, item in ipairs(section.items) do
			if item.kind == "check" then
				item.control:SetChecked(pe:GetSetting(item.path, item.default) and true or false)
			elseif item.kind == "select" then
				item.control.select:RefreshText()
			else
				item.control:SetText(type(item.text) == "function" and item.text() or item.text)
			end
		end
	end
	self:Layout(panel)
end
