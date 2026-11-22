local addonName, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local SettingsTab = {}
Tradewright.SettingsTab = SettingsTab

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

-- Copper amounts as plain "25s" / "1g" labels.
local function moneyChoices(values)
	local options = {}
	for _, copper in ipairs(values) do
		local label = copper >= 10000 and string.format("%dg", copper / 10000) or string.format("%ds", copper / 100)
		options[#options + 1] = { value = copper, label = label }
	end
	return options
end

local function generalSection(pe)
	return { title = L["General"], items = {
		{ kind = "check", label = L["Show minimap button"], path = "general.showMinimapButton", default = true,
			onChange = function() pe:EnsureMinimapButton() end },
		{ kind = "select", label = L["Window scale"], path = "appearance.windowScale", default = 1,
			options = pe:GetWindowScaleOptions(), onChange = function() pe:ApplyWindowScale() end },
	} }
end

local function farmingSection()
	return { title = L["Farming"], items = {
		{ kind = "check", label = L["Show the farm window when a farm starts"], path = "farm.showWindow", default = true },
		{ kind = "select", label = L["Pause a farm after standing still for"], path = "farm.idlePauseMinutes", default = 5,
			options = { { value = 0, label = L["Never"] }, { value = 2, label = L["2 minutes"] }, { value = 5, label = L["5 minutes"] },
				{ value = 10, label = L["10 minutes"] } } },
		{ kind = "note", text = L["Start a farm with /twfarm start, pause with /twfarm pause, save with /twfarm stop."] },
	} }
end

local function troubleshootingSection()
	return { title = L["Troubleshooting"], items = {
		{ kind = "check", label = L["Write debug messages to chat"], path = "debug.enabled", default = false },
	} }
end

local function auctionHouseSection(pe)
	return { title = L["Auction house"], items = {
		{ kind = "select", label = L["Keep hourly prices for"], path = "auction.historyRetentionDays", default = 30,
			options = choices({ 7, 14, 30, 60, 90 }, L["%d days"]),
			onChange = function() if pe.TrimFullDumpMarketHistory then pe:TrimFullDumpMarketHistory() end end },
		{ kind = "select", label = L["Usual price uses the last"], path = "auction.usualPriceDays", default = 14,
			options = choices({ 7, 14, 30 }, L["%d days"]), onChange = refreshEconomy },
		{ kind = "select", label = L["Keep daily prices for"], path = "auction.dailyRetentionDays", default = 180,
			options = choices({ 90, 180, 365 }, L["%d days"]) },
		{ kind = "check", label = L["Keep the cheapest price steps of each item from a full scan"], path = "auction.keepPriceSteps",
			default = true },
		{ kind = "note", text = L["Price steps: the cheapest prices of an item and how many are listed at each. Price gaps use them."] },
		{ kind = "select", label = L["Refresh prices older than"], path = "auction.priceFreshnessMinutes", default = 15,
			options = choices({ 5, 15, 30, 60, 180 }, L["%d minutes"]) },
		{ kind = "check", label = L["Suggest a full scan when one is ready"], path = "auction.suggestFullScan", default = true },
		{ kind = "note", text = L["Off: every price older than an hour is checked one by one when the auction house opens."] },
		{ kind = "check", label = L["Count the lost deposit when cancelling undercut auctions"], path = "auction.repostIncludeDeposit",
			default = true },
		{ kind = "check", label = L["Show prices and what you own on item tooltips (hold Shift for more)"], path = "auction.tooltipEnabled",
			default = true },
	} }
end

local function goldSection()
	return { title = L["Gold view"], items = {
		{ kind = "select", label = L["Count as a deal when below the usual price by"], path = "gold.dealThreshold", default = 0.3,
			options = choices({ 0.2, 0.3, 0.4, 0.5 }, "%d%%", 100) },
		{ kind = "select", label = L["Count as a mover when the price changed by"], path = "gold.moverThreshold", default = 0.15,
			options = choices({ 0.1, 0.15, 0.25 }, "%d%%", 100) },
	} }
end

local function refreshAfterFeeChange(pe)
	pe:InvalidateCraftOpportunityCaches()
	refreshEconomy(pe)
	refreshOpportunities(pe)
end

local function measuredCutNote(pe)
	local measured = pe.LedgerMeasuredAuctionCut and pe:LedgerMeasuredAuctionCut() or { sales = 0 }
	if measured.cut then
		return string.format(L["Measured from your last %d sales: the auction house kept %.3g%%."], measured.sales, measured.cut * 100)
	end
	return string.format(L["Not measured yet: %d of %d sale mails collected. Until then %.3g%% is used."],
		measured.sales, pe.IncomeLogic.CUT_MIN_SALES, pe.DEFAULT_AUCTION_CUT * 100)
end

local function feesSection()
	return { title = L["Fees"], items = {
		{ kind = "select", label = L["Auction cut"], path = "fees.auctionCut", default = "measured",
			options = { { value = "measured", label = L["Measured from my sales"] }, { value = 5, label = "5%" },
				{ value = 10, label = "10%" }, { value = 15, label = "15%" } }, onChange = refreshAfterFeeChange },
		{ kind = "note", text = measuredCutNote },
	} }
end

local function opportunitiesSection()
	return { title = L["Opportunities"], items = {
		{ kind = "select", label = L["Count as a flip when below the usual price by"], path = "opportunities.minDiscount", default = 0.25,
			options = choices({ 0.15, 0.2, 0.25, 0.3, 0.4 }, L["%d%% or more"], 100), onChange = refreshOpportunities },
		{ kind = "select", label = L["Smallest profit worth showing"], path = "opportunities.minProfitCopper", default = 10000,
			options = moneyChoices({ 1000, 2500, 5000, 10000, 50000, 100000, 250000, 500000 }), onChange = refreshOpportunities },
		{ kind = "select", label = L["An item must sell at least"], path = "opportunities.minSellsPerDay", default = 1,
			options = choices({ 0.5, 1, 5, 20 }, L["%s a day"]), onChange = refreshOpportunities },
		{ kind = "check", label = L["Also show items with only 2 to 4 days of prices, marked Early"], path = "opportunities.allowEarly",
			default = false, onChange = refreshOpportunities },
		{ kind = "check", label = L["Show items listed below their vendor price"], path = "opportunities.showVendor", default = true,
			onChange = refreshOpportunities },
		{ kind = "check", label = L["Show price gaps, marked as risky"], path = "opportunities.showGaps", default = true,
			onChange = refreshOpportunities },
		{ kind = "select", label = L["Price gaps cost at most"], path = "opportunities.gapMaxCostGold", default = 100,
			options = choices({ 25, 100, 500, 2000 }, L["%dg to clear"]), onChange = refreshOpportunities },
		{ kind = "select", label = L["Buy no more than"], path = "opportunities.dayShare", default = 0.34,
			options = { { value = 0.1, label = L["A tenth of a day's sales"] }, { value = 0.34, label = L["A third of a day's sales"] },
				{ value = 1, label = L["A day's sales"] } }, onChange = refreshOpportunities },
	} }
end

local function craftsSection()
	return { title = L["Crafts"], items = {
		{ kind = "select", label = L["Make enough for"], path = "crafts.restockDays", default = 1,
			options = choices({ 1, 2, 3, 7 }, L["%d days of sales"]), onChange = refreshEconomy },
		{ kind = "check", label = L["Use my own recipes when a reagent is cheaper to craft"], path = "crafts.useCheapestSource",
			default = true, onChange = function(pe)
				pe:InvalidateCraftOpportunityCaches()
				refreshEconomy(pe)
			end },
		{ kind = "check", label = L["Tell me at login when a cooldown craft is ready"], path = "crafts.announceCooldowns", default = true },
		{ kind = "check", label = L["Include optional reagents in the craft scan"], path = "auction.craftScanIncludeOptionalSlots",
			default = false, visible = isRetail },
	} }
end

local function professionScanSection()
	return { title = L["Profession scan"], items = {
		{ kind = "check", label = L["Also scan specialization trees (for export)"], path = "capture.captureSpecializationTree", default = true,
			visible = hasProfessionSpecs },
		{ kind = "check", label = L["Also save detailed recipe results (for export)"], path = "capture.includeRecipeOutputItemData", default = false },
	} }
end

local function craftingOrdersSection()
	return { title = L["Crafting orders"], visible = isRetail, items = {
		{ kind = "check", label = L["Hide unlearned recipes in the orders list"], path = "craftingOrders.hideUnlearned", default = false,
			onChange = refreshCraftingOrders },
		{ kind = "check", label = L["Patron orders: only recipes that give knowledge"], path = "craftingOrders.patronKnowledgeOnly",
			default = false, onChange = refreshCraftingOrders },
		{ kind = "note", text = L["Uses the recipe list in the addon's data file. When that list is empty, the option does nothing."] },
	} }
end

local function inventorySection()
	return { title = L["Inventory"], items = {
		{ kind = "check", label = L["Show price and profit columns by default"], path = "inventory.economyShowColumns", default = true,
			onChange = refreshEconomy },
		{ kind = "check", label = L["Work out craft cost from reagent prices"], path = "inventory.economyShowMatCost", default = true, onChange = refreshEconomy },
		{ kind = "select", label = L["Inventory reading speed"], path = "capture.inventorySnapshotBatchSize", default = 0,
			options = { { value = 0, label = L["Automatic"] }, { value = 50, label = "50" }, { value = 100, label = "100" } } },
	} }
end

-- The bank character is chosen per realm (on Forever, one for all characters), from
-- the characters known there, by full name on Forever.
local function mailSection(pe)
	local sellerOptions = { { value = "", label = L["None"] } }
	local realmKeys, realm = {}, "?"
	if pe.GetRealmCharacterKeys then
		realmKeys, realm = pe:GetRealmCharacterKeys()
	end
	for _, characterKey in ipairs(realmKeys) do
		sellerOptions[#sellerOptions + 1] = { value = characterKey, label = pe:GetMailRecipient(characterKey) }
	end
	return { title = L["Mail"], items = {
		{ kind = "select", label = L["Bank character"], path = "mail.sellerByRealm." .. realm, default = "",
			options = sellerOptions },
		{ kind = "note", text = L["The character that sells at the auction house and holds your reagents."] },
		{ kind = "check", label = L["Mail reagents to my crafters when the mailbox opens"], path = "mail.autoSendMaterials", default = true },
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
	return { title = L["Bags"], visible = hasBagsModule, items = {
		{ kind = "check", label = L["Use Tradewright bags instead of the game's bag window"], path = "bags.enabled", default = true,
			onChange = function(pe) pe:ApplyBagTakeover() end },
		{ kind = "note", text = L["Off: the bag key and bag buttons open the game's own bags, or your other bag addon."]
			.. L[" Applies at once. Also /tw bags, or right-click the Bags title bar."] },
		{ kind = "check", label = L["Use Tradewright for the bank too"], path = "bags.bank", default = true,
			onChange = function(pe) pe:ApplyBankTakeover() end },
		{ kind = "note", text = L["At a banker the bag window opens on its Bank view. Off: the game's bank window opens."]
			.. L[" Use that one to buy bank tabs or deposit gold."] },
		{ kind = "check", label = L["Show my other characters as tabs"], path = "bags.showCharacters", default = true,
			onChange = refreshBags },
		{ kind = "check", label = L["Split gear into \"in a set\" and \"not in a set\""], path = "bags.splitGearSets", default = true,
			onChange = refreshBags },
		{ kind = "check", label = L["Mark new items with a gold corner"], path = "bags.markNew", default = true, onChange = refreshBags },
		{ kind = "check", label = L["Show the sell value of junk"], path = "bags.showJunkValue", default = true, onChange = refreshBags },
		{ kind = "check", label = L["Keep the bag row open"], path = "bags.showBagRow", default = false, onChange = refreshBags },
		{ kind = "check", label = L["When loot does not fit, offer to swap it for my cheapest item"], path = "bags.lootSwap",
			default = true },
		{ kind = "select", label = L["Keep the item log for"], path = "bags.logDays", default = 14,
			options = choices({ 7, 14, 30, 90 }, L["%d days"]), onChange = refreshBags },
		{ kind = "select", label = L["Slots per row"], path = "bags.columns", default = 10, options = choices({ 8, 10, 12, 14 }, "%d"),
			onChange = refreshBags },
		{ kind = "select", label = L["Slot size"], path = "bags.slotSize", default = 36, onChange = refreshBags,
			options = { { value = 30, label = L["Small"] }, { value = 36, label = L["Normal"] }, { value = 42, label = L["Large"] } } },
	} }
end

-- Every setting, grouped into the categories listed on the left. Item kind: check | select | note.
-- A section or item with `visible(pe)` is hidden when it returns false; empty sections and categories hide too.
local function buildCategories(pe)
	return {
		{ key = "general", label = L["General"], sections = { generalSection(pe), farmingSection(), troubleshootingSection() } },
		{ key = "prices", label = L["Prices"], sections = { auctionHouseSection(pe), feesSection(), goldSection() } },
		{ key = "opportunities", label = L["Opportunities"], sections = { opportunitiesSection() } },
		{ key = "crafting", label = L["Crafting"], sections = { craftsSection(), professionScanSection(), craftingOrdersSection() } },
		{ key = "inventory", label = L["Inventory & mail"], sections = { inventorySection(), mailSection(pe), bagsSection() } },
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
	row.select = pe:CreateSettingDropdown(row, {
		setting = item.path,
		default = item.default,
		width = SELECT_WIDTH,
		getChoices = function() return item.options end,
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
	panel.openGameSettings = pe:CreateButton(panel.footer, L["Open game settings"], function()
		pe:OpenBlizzardSettings()
	end)
	panel.openGameSettings:SetPoint("RIGHT")
	panel.footerNote = pe:CreateText(panel.footer, "GameFontHighlightSmall", "textMuted")
	panel.footerNote:SetPoint("LEFT")
	panel.footerNote:SetPoint("RIGHT", panel.openGameSettings, "LEFT", -12, 0)
	panel.footerNote:SetText(L["Changes apply at once and are saved for the whole account."])
end

local function createCategoryList(pe, panel)
	panel.categoryColumn = CreateFrame("Frame", nil, panel)
	panel.categoryColumn:SetPoint("TOPLEFT")
	panel.categoryColumn:SetPoint("BOTTOM", panel.footer, "TOP", 0, GAP)
	panel.categoryColumn:SetWidth(CATEGORY_WIDTH)
	local heading = pe:CreateHeading(panel.categoryColumn, L["Categories"])
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
	local pe = Tradewright
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
	local pe = Tradewright
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
