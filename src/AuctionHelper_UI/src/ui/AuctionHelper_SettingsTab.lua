local addonName, ProfessionExporter = ...

local SettingsTab = {}
ProfessionExporter.SettingsTab = SettingsTab

local CATEGORY_WIDTH = 220
local GAP = 12
local PAD = 12
local CONTENT_MAX_WIDTH = 640
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

local function refreshOpportunities(pe)
	if pe.OpportunitiesTab then
		pe.OpportunitiesTab:Refresh()
	end
end

-- Visibility rules: a setting only shows on the client and with the addons where it does something.
local function isRetail(pe)
	return pe.IS_RETAIL == true
end

local function hasTSM(pe)
	return pe.IsTSMLoaded ~= nil and pe:IsTSMLoaded() == true
end

local function hasAuctionator(pe)
	return pe.IsAuctionatorLoaded ~= nil and pe:IsAuctionatorLoaded() and true or false
end

local function hasNoPriceAddon(pe)
	return not hasTSM(pe) and not hasAuctionator(pe)
end

local function hasProfessionSpecs()
	return C_ProfSpecs ~= nil and C_ProfSpecs.GetConfigIDForSkillLine ~= nil
end

-- `scale` multiplies the value before formatting (0.25 -> "25%").
local function choices(values, format, scale)
	local options = {}
	for _, value in ipairs(values) do
		options[#options + 1] = { value = value, label = string.format(format, value * (scale or 1)) }
	end
	return options
end

local function generalSection(pe)
	return { title = "General", items = {
		{ kind = "check", label = "Show minimap button", path = "general.showMinimapButton", default = true,
			onChange = function() pe:EnsureMinimapButton() end },
		{ kind = "select", label = "Window scale", path = "appearance.windowScale", default = 1,
			options = pe:GetWindowScaleOptions(), onChange = function() pe:ApplyWindowScale() end },
	} }
end

local function farmingSection()
	return { title = "Farming", items = {
		{ kind = "check", label = "Show the farm window when a farm starts", path = "farm.showWindow", default = true },
		{ kind = "note", text = "Start a farm with /ahfarm start, pause with /ahfarm pause, save with /ahfarm stop." },
	} }
end

local function troubleshootingSection()
	return { title = "Troubleshooting", items = {
		{ kind = "check", label = "Write debug messages to chat", path = "debug.enabled", default = false },
	} }
end

local function auctionHouseSection(pe)
	return { title = "Auction house", items = {
		{ kind = "select", label = "Keep price history for", path = "auction.historyRetentionDays", default = 30,
			options = choices({ 7, 14, 30, 60, 90 }, "%d days"),
			onChange = function() if pe.TrimFullDumpMarketHistory then pe:TrimFullDumpMarketHistory() end end },
		{ kind = "select", label = "Usual price looks back", path = "auction.usualPriceDays", default = 14,
			options = choices({ 7, 14, 30 }, "%d days"), onChange = refreshEconomy },
		{ kind = "select", label = "Keep daily prices for", path = "auction.dailyRetentionDays", default = 180,
			options = choices({ 90, 180, 365 }, "%d days") },
		{ kind = "check", label = "Keep the cheapest price steps of each item from a full scan", path = "auction.keepPriceSteps",
			default = true },
		{ kind = "select", label = "Refresh prices older than", path = "auction.priceFreshnessMinutes", default = 15,
			options = choices({ 5, 15, 30, 60, 180 }, "%d minutes") },
		{ kind = "check", label = "Count the lost deposit when cancelling undercut auctions", path = "auction.repostIncludeDeposit",
			default = true },
	} }
end

local function goldSection()
	return { title = "Gold dashboard", items = {
		{ kind = "select", label = "Deal when below usual price by", path = "gold.dealThreshold", default = 0.3,
			options = choices({ 0.2, 0.3, 0.4, 0.5 }, "%d%%", 100) },
		{ kind = "select", label = "Mover when price changed by", path = "gold.moverThreshold", default = 0.15,
			options = choices({ 0.1, 0.15, 0.25 }, "%d%%", 100) },
		{ kind = "select", label = "Usual price", path = "gold.reference", default = "best", visible = hasTSM,
			options = { { value = "best", label = "TSM, else my scans" }, { value = "own", label = "My scans only" } } },
	} }
end

local function tsmSourcesText(pe)
	return string.format("TSM sources in use: market %s, materials %s, sale rate %s.",
		tostring(pe:GetSetting("integrations.economyTSMMarketString", "dbmarket")),
		tostring(pe:GetSetting("integrations.economyTSMMatString", "Crafting")),
		tostring(pe:GetSetting("integrations.economyTSMSaleRateString", "DBRegionSaleRate")))
end

local function priceSourcesSection()
	return { title = "Other price sources", items = {
		{ kind = "check", label = "Use Auctionator when there is no scanned price", path = "integrations.economyUseAuctionatorFallback",
			default = true, onChange = refreshEconomy, visible = hasAuctionator },
		{ kind = "select", label = "TSM fallback price", path = "integrations.economyTSMFallbackString", default = "DBMinBuyout",
			options = { { value = "DBMinBuyout", label = "DBMinBuyout" }, { value = "dbmarket", label = "dbmarket" },
				{ value = "DBRecent", label = "DBRecent" } }, onChange = refreshEconomy, visible = hasTSM },
		{ kind = "note", text = tsmSourcesText, visible = hasTSM },
		{ kind = "note", text = "TradeSkillMaster or Auctionator prices are used here when either addon is enabled.",
			visible = hasNoPriceAddon },
	} }
end

local function opportunitiesSection()
	return { title = "Opportunities", items = {
		{ kind = "select", label = "Count as a flip when under the usual price by", path = "opportunities.minDiscount", default = 0.25,
			options = choices({ 0.15, 0.2, 0.25, 0.3, 0.4 }, "%d%% or more", 100), onChange = refreshOpportunities },
		{ kind = "select", label = "Smallest profit worth showing", path = "opportunities.minProfitGold", default = 5,
			options = choices({ 1, 5, 10, 25, 50 }, "%dg"), onChange = refreshOpportunities },
		{ kind = "select", label = "An item must sell at least", path = "opportunities.minSellsPerDay", default = 1,
			options = choices({ 0.5, 1, 5, 20 }, "%s a day"), onChange = refreshOpportunities },
		{ kind = "check", label = "Show items listed under their vendor price", path = "opportunities.showVendor", default = true,
			onChange = refreshOpportunities },
		{ kind = "check", label = "Show price gaps, marked as risky", path = "opportunities.showGaps", default = true,
			onChange = refreshOpportunities },
		{ kind = "select", label = "Price gaps cost at most", path = "opportunities.gapMaxCostGold", default = 100,
			options = choices({ 25, 100, 500, 2000 }, "%dg to clear"), onChange = refreshOpportunities },
		{ kind = "select", label = "Buy no more than", path = "opportunities.dayShare", default = 0.34,
			options = { { value = 0.1, label = "A tenth of a day's sales" }, { value = 0.34, label = "A third of a day's sales" },
				{ value = 1, label = "A day's sales" } }, onChange = refreshOpportunities },
	} }
end

local function craftsSection()
	return { title = "Crafts", items = {
		{ kind = "select", label = "Make enough for", path = "crafts.restockDays", default = 1,
			options = choices({ 1, 2, 3, 7 }, "%d days of sales"), onChange = refreshEconomy },
		{ kind = "check", label = "Use my own recipes when a material is cheaper to craft", path = "crafts.useCheapestSource",
			default = true, onChange = function(pe)
				pe:InvalidateCraftOpportunityCaches()
				refreshEconomy(pe)
			end },
		{ kind = "check", label = "Include optional reagents in the craft scan", path = "auction.craftScanIncludeOptionalSlots",
			default = false, visible = isRetail },
	} }
end

local function professionScanSection()
	return { title = "Profession scan", items = {
		{ kind = "check", label = "Capture specialization tree", path = "capture.captureSpecializationTree", default = true,
			visible = hasProfessionSpecs },
		{ kind = "check", label = "Include detailed recipe output data", path = "capture.includeRecipeOutputItemData", default = false },
	} }
end

local function craftingOrdersSection()
	return { title = "Crafting orders", visible = isRetail, items = {
		{ kind = "check", label = "Hide unlearned recipes in the orders list", path = "craftingOrders.hideUnlearned", default = false,
			onChange = refreshCraftingOrders },
		{ kind = "check", label = "Patron orders: only recipes that give knowledge", path = "craftingOrders.patronKnowledgeOnly",
			default = false, onChange = refreshCraftingOrders },
		{ kind = "note", text = "Uses the recipe list in the addon's data file. When that list is empty, the option does nothing." },
	} }
end

local function inventorySection()
	return { title = "Inventory", items = {
		{ kind = "check", label = "Show price and profit columns by default", path = "inventory.economyShowColumns", default = true,
			onChange = refreshEconomy },
		{ kind = "check", label = "Estimate material cost", path = "inventory.economyShowMatCost", default = true, onChange = refreshEconomy },
		{ kind = "check", label = "Show TSM sale rate", path = "inventory.economyShowSaleRate", default = true, onChange = refreshEconomy,
			visible = hasTSM },
		{ kind = "select", label = "Inventory items read per frame", path = "capture.inventorySnapshotBatchSize", default = 0,
			options = { { value = 0, label = "Automatic" }, { value = 50, label = "50" }, { value = 100, label = "100" } } },
	} }
end

-- The auction house / bank character is chosen per realm (on Forever, one for all characters), from
-- the characters known there, by full name on Forever.
local function mailSection(pe)
	local sellerOptions = { { value = "", label = "None" } }
	local realmKeys, realm = {}, "?"
	if pe.GetRealmCharacterKeys then
		realmKeys, realm = pe:GetRealmCharacterKeys()
	end
	for _, characterKey in ipairs(realmKeys) do
		sellerOptions[#sellerOptions + 1] = { value = characterKey, label = pe:GetMailRecipient(characterKey) }
	end
	return { title = "Mail", items = {
		{ kind = "select", label = "Auction house / bank character", path = "mail.sellerByRealm." .. realm, default = "",
			options = sellerOptions },
		{ kind = "check", label = "Mail collected materials to crafters when the mailbox opens", path = "mail.autoSendMaterials", default = true },
	} }
end

-- The bags module is its own addon; its settings only show when it is loaded.
local function hasBagsModule(pe)
	return pe.ApplyBagTakeover ~= nil
end

local function refreshBags(pe)
	pe:RefreshBagWindow()
end

local function bagsSection()
	return { title = "Bags", visible = hasBagsModule, items = {
		{ kind = "check", label = "Use AuctionHelper bags instead of the game's bag window", path = "bags.enabled", default = true,
			onChange = function(pe) pe:ApplyBagTakeover() end },
		{ kind = "note", text = "Off: the bag key and bag buttons open the game's own bags, or your other bag addon."
			.. " Applies at once. Also /ah bags, or right-click the Bags title bar." },
		{ kind = "check", label = "Show my other characters as tabs", path = "bags.showCharacters", default = true,
			onChange = refreshBags },
		{ kind = "check", label = "Show the sell value of junk", path = "bags.showJunkValue", default = true, onChange = refreshBags },
		{ kind = "check", label = "Keep the bag row open", path = "bags.showBagRow", default = false, onChange = refreshBags },
		{ kind = "select", label = "Slots per row", path = "bags.columns", default = 10, options = choices({ 8, 10, 12, 14 }, "%d"),
			onChange = refreshBags },
		{ kind = "select", label = "Slot size", path = "bags.slotSize", default = 36, onChange = refreshBags,
			options = { { value = 30, label = "Small" }, { value = 36, label = "Normal" }, { value = 42, label = "Large" } } },
	} }
end

-- Every setting, grouped into the categories listed on the left. Item kind: check | select | note.
-- A section or item with `visible(pe)` is hidden when it returns false; empty sections and categories hide too.
local function buildCategories(pe)
	return {
		{ key = "general", label = "General", sections = { generalSection(pe), farmingSection(), troubleshootingSection() } },
		{ key = "prices", label = "Prices", sections = { auctionHouseSection(pe), goldSection(), priceSourcesSection() } },
		{ key = "opportunities", label = "Opportunities", sections = { opportunitiesSection() } },
		{ key = "crafting", label = "Crafting", sections = { craftsSection(), professionScanSection(), craftingOrdersSection() } },
		{ key = "inventory", label = "Inventory & mail", sections = { inventorySection(), mailSection(pe), bagsSection() } },
	}
end

local function runOnChange(pe, item)
	if item.onChange then
		item.onChange(pe)
	end
end

local function createCheck(pe, parent, item)
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
		runOnChange(pe, item)
	end)
	return check
end

local function createSelect(pe, parent, item)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(26)
	row.select = pe:CreateSingleSelectDropdown(row, {
		width = SELECT_WIDTH,
		getOptions = function() return item.options end,
		getValue = function() return pe:GetSetting(item.path, item.default) end,
		setValue = function(value) pe:SetSetting(item.path, value) end,
		onChanged = function()
			runOnChange(pe, item)
			SettingsTab:Refresh()
		end,
	})
	row.select:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.label = pe:CreateText(row, "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.label:SetPoint("RIGHT", row.select, "LEFT", -12, 0)
	row.label:SetText(item.label)
	return row
end

local function createItem(pe, parent, item)
	if item.kind == "check" then
		item.control = createCheck(pe, parent, item)
	elseif item.kind == "select" then
		item.control = createSelect(pe, parent, item)
	else
		item.control = pe:CreateParagraph(parent)
	end
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

local function isShown(pe, entry)
	return not entry.visible or entry.visible(pe)
end

-- Marks which items of `section` are shown on this client. Returns true when any is.
local function resolveSection(pe, section)
	local sectionShown, any = isShown(pe, section), false
	for _, item in ipairs(section.items) do
		item.shown = sectionShown and isShown(pe, item)
		any = any or item.shown
	end
	section.shown = any
	return any
end

local function categoryShown(pe, category)
	local any = false
	for _, section in ipairs(category.sections) do
		any = resolveSection(pe, section) or any
	end
	return any
end

local function placeItem(item, frame, width, top)
	local control = item.control
	control:ClearAllPoints()
	if item.kind == "check" then
		control:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, -top)
	elseif item.kind == "select" then
		control:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top)
		control:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -top)
	else
		control:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top)
		control:SetWidth(width)
	end
	return top + itemHeight(item) + ROW_GAP
end

-- Stacks the shown sections of `category` in one column. Returns the height used.
local function layoutCategory(category, width)
	local frame, top = category.frame, 0
	frame:SetWidth(width)
	for _, section in ipairs(category.sections) do
		section.heading:SetShown(section.shown)
		for _, item in ipairs(section.items) do
			item.control:SetShown(item.shown)
		end
		if section.shown then
			section.heading:ClearAllPoints()
			section.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -top)
			section.heading:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -top)
			top = top + 18 + 8
			for _, item in ipairs(section.items) do
				top = item.shown and placeItem(item, frame, width, top) or top
			end
			top = top + SECTION_GAP - ROW_GAP
		end
	end
	frame:SetHeight(math.max(1, top))
	return top
end

function SettingsTab:Layout(panel)
	if not panel then
		return
	end
	local width = math.max(200, math.min(CONTENT_MAX_WIDTH, panel.scroll:GetWidth()))
	panel.content:SetWidth(math.max(width, panel.scroll:GetWidth()))
	local selected
	for _, category in ipairs(panel.categories) do
		category.frame:SetShown(category.key == panel.selectedKey)
		selected = category.key == panel.selectedKey and category or selected
	end
	panel.content:SetHeight(math.max(1, selected and layoutCategory(selected, width) or 0))
end

local function createFooter(pe, panel)
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
end

local function createCategoryList(pe, panel)
	panel.categoryColumn = CreateFrame("Frame", nil, panel)
	panel.categoryColumn:SetPoint("TOPLEFT")
	panel.categoryColumn:SetPoint("BOTTOM", panel.footer, "TOP", 0, GAP)
	panel.categoryColumn:SetWidth(CATEGORY_WIDTH)
	local heading = pe:CreateHeading(panel.categoryColumn, "Categories")
	heading:SetPoint("TOPLEFT")
	heading:SetPoint("TOPRIGHT")
	panel.categoryList = pe:CreateSelectList(panel.categoryColumn, function(key)
		panel.selectedKey = key
		panel.scroll:SetVerticalScroll(0)
		SettingsTab:Refresh()
	end, function()
		return panel.selectedKey
	end)
	panel.categoryList.frame:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
	panel.categoryList.frame:SetPoint("BOTTOMRIGHT", panel.categoryColumn, "BOTTOMRIGHT", 0, 0)
end

local function createSettingsPane(pe, panel)
	panel.article = pe:CreateInset(panel)
	panel.article:SetPoint("TOPLEFT", panel.categoryColumn, "TOPRIGHT", GAP, 0)
	panel.article:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", 0, GAP)
	if panel.article.SetClipsChildren then
		panel.article:SetClipsChildren(true)
	end
	panel.scroll = CreateFrame("ScrollFrame", addonName .. "SettingsScroll", panel.article, "UIPanelScrollFrameTemplate")
	panel.scroll:SetPoint("TOPLEFT", PAD + 4, -PAD)
	panel.scroll:SetPoint("BOTTOMRIGHT", -(PAD + 10), PAD)
	panel.content = CreateFrame("Frame", nil, panel.scroll)
	panel.content:SetSize(400, 400)
	panel.scroll:SetScrollChild(panel.content)
	panel.categories = buildCategories(pe)
	for _, category in ipairs(panel.categories) do
		category.frame = CreateFrame("Frame", nil, panel.content)
		category.frame:SetPoint("TOPLEFT")
		category.frame:SetHeight(1)
		for _, section in ipairs(category.sections) do
			section.heading = pe:CreateHeading(category.frame, section.title)
			for _, item in ipairs(section.items) do
				createItem(pe, category.frame, item)
			end
		end
	end
end

function SettingsTab:Create(container, uiState)
	local pe = ProfessionExporter
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.settingsPanel = panel
	createFooter(pe, panel)
	createCategoryList(pe, panel)
	createSettingsPane(pe, panel)
	pe:SkinTree(panel)
	panel:SetScript("OnSizeChanged", function()
		SettingsTab:Layout(panel)
	end)
	return panel
end

function SettingsTab:ApplyTheme()
end

local function refreshItem(pe, item)
	if item.kind == "check" then
		item.control:SetChecked(pe:GetSetting(item.path, item.default) and true or false)
	elseif item.kind == "select" then
		item.control.select:RefreshText()
	else
		item.control:SetText(type(item.text) == "function" and item.text(pe) or item.text)
	end
end

-- Lists the categories that have something to show on this client and keeps the selection on one of them.
local function refreshCategoryList(pe, panel)
	local items, selectedVisible = {}, false
	for _, category in ipairs(panel.categories) do
		if categoryShown(pe, category) then
			items[#items + 1] = { key = category.key, label = category.label }
			selectedVisible = selectedVisible or category.key == panel.selectedKey
		end
	end
	if not selectedVisible then
		panel.selectedKey = items[1] and items[1].key
	end
	panel.categoryList:SetItems(items)
end

function SettingsTab:Refresh()
	local pe = ProfessionExporter
	local panel = pe.ui.settingsPanel
	if not panel then
		return
	end
	refreshCategoryList(pe, panel)
	for _, category in ipairs(panel.categories) do
		for _, section in ipairs(category.sections) do
			for _, item in ipairs(section.items) do
				refreshItem(pe, item)
			end
		end
	end
	self:Layout(panel)
end
