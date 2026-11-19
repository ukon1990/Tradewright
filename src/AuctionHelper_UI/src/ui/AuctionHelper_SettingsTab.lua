local addonName, ProfessionExporter = ...

local SettingsTab = {}
ProfessionExporter.SettingsTab = SettingsTab

local ACCENT_SWATCHES = {
	{ id = "teal", label = "Teal", color = { r = 0.24, g = 0.66, b = 0.74 } },
	{ id = "gold", label = "Gold", color = { r = 0.82, g = 0.64, b = 0.23 } },
	{ id = "ember", label = "Ember", color = { r = 0.80, g = 0.38, b = 0.28 } },
	{ id = "ice", label = "Ice", color = { r = 0.36, g = 0.62, b = 0.85 } },
}

local function setCheck(button, value)
	button:SetChecked(value and true or false)
end

local function createCheckbox(parent, name, label, onClick)
	local button = CreateFrame("CheckButton", addonName .. name, parent, "UICheckButtonTemplate")
	local text = _G[button:GetName() .. "Text"]
	if text then
		text:SetText(label)
	end
	button:SetScript("OnClick", function(self)
		onClick(self:GetChecked() == true)
	end)
	return button
end

local function createCycleButton(parent, width, text, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 180, 22)
	button:SetText(text or "")
	button:SetScript("OnClick", onClick)
	return button
end

local function openColorPicker(initial, onCommit)
	local info = {
		r = initial.r,
		g = initial.g,
		b = initial.b,
		hasOpacity = false,
		swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			onCommit({ r = r, g = g, b = b })
		end,
		cancelFunc = function(previous)
			if previous and previous.r then
				onCommit({ r = previous.r, g = previous.g, b = previous.b })
			end
		end,
	}
	ColorPickerFrame.func = info.swatchFunc
	ColorPickerFrame.cancelFunc = info.cancelFunc
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.opacity = 1
	ColorPickerFrame:SetColorRGB(info.r, info.g, info.b)
	ColorPickerFrame.previousValues = { r = info.r, g = info.g, b = info.b }
	ColorPickerFrame:Show()
end

function SettingsTab:Layout(panel)
	if not panel or not panel.scroll or not panel.content then
		return
	end

	local contentWidth = math.max(560, (panel.scroll:GetWidth() or 840) - 28)
	local cardWidth = contentWidth - 10
	local left = 10
	local top = -6
	local sectionGap = 12
	local innerGap = 8
	local controlHeight = 22

	panel.content:SetWidth(contentWidth)
	panel.subtitle:SetWidth(math.max(520, contentWidth - 24))

	local function placeCard(card, height)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, top)
		card:SetWidth(cardWidth)
		card:SetHeight(height)
		top = top - height - sectionGap
	end

	local function widthForText(margin)
		return math.max(320, cardWidth - (margin or 24))
	end

	panel.generalOpenBlizzard:ClearAllPoints()
	panel.generalOpenBlizzard:SetPoint("TOPLEFT", panel.generalMinimap, "BOTTOMLEFT", 4, -6)
	placeCard(panel.generalCard, 92)

	local buttonWidth = 220
	local rowCapacity = math.max(1, math.floor((cardWidth - 20 + innerGap) / (buttonWidth + innerGap)))
	local function positionButtonRow(buttons, anchorY)
		for index, button in ipairs(buttons) do
			local col = (index - 1) % rowCapacity
			local row = math.floor((index - 1) / rowCapacity)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", left + (col * (buttonWidth + innerGap)), anchorY - (row * (controlHeight + innerGap)))
		end
		return math.ceil(#buttons / rowCapacity)
	end

	local appearanceButtons = {
		panel.appearancePreset,
		panel.appearanceScale,
		panel.appearanceAccent,
	}
	local appearanceButtonRows = positionButtonRow(appearanceButtons, -34)
	local swatchY = -34 - (appearanceButtonRows * (controlHeight + innerGap)) - 8
	local swatchWidth = 96
	local swatchCapacity = math.max(1, math.floor((cardWidth - 20 + 6) / (swatchWidth + 6)))
	for index, button in ipairs(panel.appearanceSwatches) do
		local col = (index - 1) % swatchCapacity
		local row = math.floor((index - 1) / swatchCapacity)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", left + (col * (swatchWidth + 6)), swatchY - (row * 26))
	end
	local swatchRows = math.ceil(#panel.appearanceSwatches / swatchCapacity)
	panel.appearanceReduced:ClearAllPoints()
	panel.appearanceReduced:SetPoint("TOPLEFT", panel.appearanceCard, "TOPLEFT", left, swatchY - (swatchRows * 26) - 10)
	placeCard(panel.appearanceCard, 34 + (appearanceButtonRows * (controlHeight + innerGap)) + 8 + (swatchRows * 26) + 34)

	panel.captureBatch:ClearAllPoints()
	panel.captureBatch:SetPoint("TOPLEFT", panel.captureOutput, "BOTTOMLEFT", 4, -8)
	placeCard(panel.captureCard, 118)

	placeCard(panel.inventoryCard, 112)

	if panel.craftingOrdersCard then
		panel.coHideUnlearned:ClearAllPoints()
		panel.coHideUnlearned:SetPoint("TOPLEFT", 10, -34)
		panel.coPatronKnowledge:ClearAllPoints()
		panel.coPatronKnowledge:SetPoint("TOPLEFT", panel.coHideUnlearned, "BOTTOMLEFT", 0, -4)
		panel.coOrdersNote:ClearAllPoints()
		panel.coOrdersNote:SetPoint("TOPLEFT", panel.coPatronKnowledge, "BOTTOMLEFT", 4, -8)
		panel.coOrdersNote:SetWidth(widthForText(24))
		placeCard(panel.craftingOrdersCard, 32 + 22 + 22 + 8 + math.max(36, panel.coOrdersNote:GetStringHeight() or 36))
	end

	placeCard(panel.auctionCard, 158)

	panel.integrationText:SetWidth(widthForText(30))
	local integrationHeight = 64 + math.max(20, panel.integrationText:GetStringHeight() or 0)
	placeCard(panel.integrationCard, integrationHeight)

	placeCard(panel.debugCard, 76)

	panel.content:SetHeight(math.max(720, -top + 10))
end

function SettingsTab:Create(container, uiState)
	local pe = ProfessionExporter
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.settingsPanel = panel

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("TOPLEFT", 12, -10)
	panel.title:SetText("Settings")

	panel.subtitle = pe:CreateMutedText(panel, 860)
	panel.subtitle:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
	panel.subtitle:SetText("Theme, capture, inventory, integration, and debug settings. Changes apply immediately.")

	panel.scroll = CreateFrame("ScrollFrame", addonName .. "SettingsScroll", panel, "UIPanelScrollFrameTemplate")
	panel.scroll:SetPoint("TOPLEFT", panel.subtitle, "BOTTOMLEFT", 0, -10)
	panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 10)
	panel.content = CreateFrame("Frame", nil, panel.scroll)
	panel.content:SetWidth(850)
	panel.content:SetHeight(760)
	panel.scroll:SetScrollChild(panel.content)

	local function createSection(titleText, height)
		local card = pe:CreateCard(panel.content, 840, height, "surface2")
		local title = pe:CreateSectionTitle(card, titleText)
		title:SetPoint("TOPLEFT", 10, -10)
		return card, title
	end

	panel.generalCard = createSection("General", 96)
	panel.generalMinimap = createCheckbox(panel.generalCard, "SettingsMinimap", "Show minimap button", function(value)
		pe:SetSetting("general.showMinimapButton", value)
		pe:EnsureMinimapButton()
		SettingsTab:Refresh()
	end)
	panel.generalMinimap:SetPoint("TOPLEFT", 10, -34)
	panel.generalOpenBlizzard = createCycleButton(panel.generalCard, 180, "Open Blizzard Settings", function()
		pe:OpenBlizzardSettings()
	end)
	panel.generalOpenBlizzard:SetPoint("TOPLEFT", panel.generalMinimap, "BOTTOMLEFT", 4, -6)

	panel.appearanceCard = createSection("Appearance", 176)
	panel.appearancePreset = createCycleButton(panel.appearanceCard, 220, "", function()
		local options = pe:GetThemePresetOptions()
		local current = pe:GetSetting("appearance.themePreset", "slate")
		local nextIndex = 1
		for index, option in ipairs(options) do
			if option.value == current then
				nextIndex = (index % #options) + 1
				break
			end
		end
		pe:SetSetting("appearance.themePreset", options[nextIndex].value)
		pe:ApplyThemeToUI()
		SettingsTab:Refresh()
	end)
	panel.appearancePreset:SetPoint("TOPLEFT", 10, -34)
	panel.appearanceScale = createCycleButton(panel.appearanceCard, 220, "", function()
		local options = pe:GetWindowScaleOptions()
		local current = pe:GetSetting("appearance.windowScale", 1)
		local nextIndex = 1
		for index, option in ipairs(options) do
			if math.abs(option.value - current) < 0.001 then
				nextIndex = (index % #options) + 1
				break
			end
		end
		pe:SetSetting("appearance.windowScale", options[nextIndex].value)
		pe:ApplyWindowScale()
		SettingsTab:Refresh()
	end)
	panel.appearanceScale:SetPoint("LEFT", panel.appearancePreset, "RIGHT", 12, 0)
	panel.appearanceAccent = createCycleButton(panel.appearanceCard, 220, "Pick accent color", function()
		openColorPicker(pe:GetSetting("appearance.accentColor", { r = 0.24, g = 0.66, b = 0.74 }), function(color)
			pe:SetSetting("appearance.accentColor", color)
			pe:ApplyThemeToUI()
			SettingsTab:Refresh()
		end)
	end)
	panel.appearanceAccent:SetPoint("LEFT", panel.appearanceScale, "RIGHT", 12, 0)
	panel.appearanceSwatches = {}
	for index, swatch in ipairs(ACCENT_SWATCHES) do
		local button = CreateFrame("Button", nil, panel.appearanceCard, "UIPanelButtonTemplate")
		button:SetSize(96, 20)
		button:SetPoint("TOPLEFT", 10 + ((index - 1) * 102), -72)
		button:SetText(swatch.label)
		button:SetScript("OnClick", function()
			pe:SetSetting("appearance.accentColor", swatch.color)
			pe:ApplyThemeToUI()
			SettingsTab:Refresh()
		end)
		panel.appearanceSwatches[index] = button
	end
	panel.appearanceReduced = createCheckbox(panel.appearanceCard, "SettingsReduced", "Reduced ornament", function(value)
		pe:SetSetting("appearance.reducedOrnament", value)
		pe:ApplyThemeToUI()
	end)
	panel.appearanceReduced:SetPoint("TOPLEFT", 10, -108)

	panel.captureCard = createSection("Data Capture", 122)
	panel.captureTree = createCheckbox(panel.captureCard, "SettingsTree", "Capture specialization tree", function(value)
		pe:SetSetting("capture.captureSpecializationTree", value)
		SettingsTab:Refresh()
	end)
	panel.captureTree:SetPoint("TOPLEFT", 10, -34)
	panel.captureOutput = createCheckbox(panel.captureCard, "SettingsRecipeOutput", "Verbose recipe output API", function(value)
		pe:SetSetting("capture.includeRecipeOutputItemData", value)
		SettingsTab:Refresh()
	end)
	panel.captureOutput:SetPoint("TOPLEFT", panel.captureTree, "BOTTOMLEFT", 0, -4)
	panel.captureBatch = createCycleButton(panel.captureCard, 220, "", function()
		local values = { 0, 50, 100 }
		local current = tonumber(pe:GetSetting("capture.inventorySnapshotBatchSize", 0)) or 0
		local nextIndex = 1
		for index, value in ipairs(values) do
			if value == current then
				nextIndex = (index % #values) + 1
				break
			end
		end
		pe:SetSetting("capture.inventorySnapshotBatchSize", values[nextIndex])
		SettingsTab:Refresh()
	end)
	panel.captureBatch:SetPoint("TOPLEFT", panel.captureOutput, "BOTTOMLEFT", 4, -8)

	panel.inventoryCard = createSection("Inventory", 120)
	panel.invEconomy = createCheckbox(panel.inventoryCard, "SettingsInvEconomy", "Show economy columns by default", function(value)
		pe:SetSetting("inventory.economyShowColumns", value)
		pe:RefreshInventoryTabIfVisible()
		pe:RefreshCraftsTabIfVisible()
	end)
	panel.invEconomy:SetPoint("TOPLEFT", 10, -34)
	panel.invMat = createCheckbox(panel.inventoryCard, "SettingsInvMat", "Estimate material cost", function(value)
		pe:SetSetting("inventory.economyShowMatCost", value)
		pe:RefreshInventoryTabIfVisible()
		pe:RefreshCraftsTabIfVisible()
	end)
	panel.invMat:SetPoint("TOPLEFT", panel.invEconomy, "BOTTOMLEFT", 0, -4)
	panel.invSale = createCheckbox(panel.inventoryCard, "SettingsInvSale", "Show TSM sale rate", function(value)
		pe:SetSetting("inventory.economyShowSaleRate", value)
		pe:RefreshInventoryTabIfVisible()
		pe:RefreshCraftsTabIfVisible()
	end)
	panel.invSale:SetPoint("TOPLEFT", panel.invMat, "BOTTOMLEFT", 0, -4)

	if pe.IS_RETAIL then
		panel.craftingOrdersCard = createSection("Crafting orders (Blizzard)", 120)
		panel.coHideUnlearned = createCheckbox(panel.craftingOrdersCard, "SettingsCOHideUnlearned", "Hide unlearned recipes in orders list", function(value)
			pe:SetSetting("craftingOrders.hideUnlearned", value)
			if pe.RefreshCraftingOrdersPageRecipeList then
				pe:RefreshCraftingOrdersPageRecipeList()
			end
			if pe.SyncCraftingOrdersFilterBarFromSettings then
				pe:SyncCraftingOrdersFilterBarFromSettings()
			end
			SettingsTab:Refresh()
		end)
		panel.coHideUnlearned:SetPoint("TOPLEFT", 10, -34)
		panel.coPatronKnowledge = createCheckbox(panel.craftingOrdersCard, "SettingsCOPatronK", "Patron knowledge recipes only (NPC tab)", function(value)
			pe:SetSetting("craftingOrders.patronKnowledgeOnly", value)
			if pe.RefreshCraftingOrdersPageRecipeList then
				pe:RefreshCraftingOrdersPageRecipeList()
			end
			if pe.SyncCraftingOrdersFilterBarFromSettings then
				pe:SyncCraftingOrdersFilterBarFromSettings()
			end
			SettingsTab:Refresh()
		end)
		panel.coPatronKnowledge:SetPoint("TOPLEFT", panel.coHideUnlearned, "BOTTOMLEFT", 0, -4)
		panel.coOrdersNote = pe:CreateMutedText(panel.craftingOrdersCard, 800)
		panel.coOrdersNote:SetPoint("TOPLEFT", panel.coPatronKnowledge, "BOTTOMLEFT", 4, -8)
		panel.coOrdersNote:SetText(
			"Patron filter uses CRAFTING_ORDERS_PATRON_KNOWLEDGE_RECIPE_IDS in the data file (not first-craft). If the list is empty, that option has no effect."
		)
	end

	panel.auctionCard = createSection("Auction", 130)
	panel.auctionHistoryRetention = createCycleButton(panel.auctionCard, 220, "", function()
		local values = { 7, 14, 30, 60, 90 }
		local current = tonumber(pe:GetSetting("auction.historyRetentionDays", 30)) or 30
		local nextIndex = 1
		for index, value in ipairs(values) do
			if value == current then
				nextIndex = (index % #values) + 1
				break
			end
		end
		pe:SetSetting("auction.historyRetentionDays", values[nextIndex])
		if pe.TrimFullDumpMarketHistory then
			pe:TrimFullDumpMarketHistory()
		end
		SettingsTab:Refresh()
	end)
	panel.auctionHistoryRetention:SetPoint("TOPLEFT", 10, -34)
	panel.auctionFreshness = createCycleButton(panel.auctionCard, 220, "", function()
		local values = { 5, 15, 30, 60, 180 }
		local current = tonumber(pe:GetSetting("auction.priceFreshnessMinutes", 15)) or 15
		local nextIndex = 1
		for index, value in ipairs(values) do
			if value == current then
				nextIndex = (index % #values) + 1
				break
			end
		end
		pe:SetSetting("auction.priceFreshnessMinutes", values[nextIndex])
		SettingsTab:Refresh()
	end)
	panel.auctionFreshness:SetPoint("TOPLEFT", panel.auctionHistoryRetention, "BOTTOMLEFT", 0, -8)
	panel.auctionAutoCraftScan = createCheckbox(panel.auctionCard, "SettingsAuctionAutoCraft", "Auto-queue craft output/reagent AH prices when opening AH", function(value)
		pe:SetSetting("auction.autoCraftEconomyRefreshOnOpen", value)
		SettingsTab:Refresh()
	end)
	panel.auctionAutoCraftScan:SetPoint("TOPLEFT", panel.auctionFreshness, "BOTTOMLEFT", 0, -8)
	panel.auctionCraftOptionalSlots = createCheckbox(panel.auctionCard, "SettingsAuctionCraftOptional", "Craft scan: include optional reagent slots", function(value)
		pe:SetSetting("auction.craftScanIncludeOptionalSlots", value)
		SettingsTab:Refresh()
	end)
	panel.auctionCraftOptionalSlots:SetPoint("TOPLEFT", panel.auctionAutoCraftScan, "BOTTOMLEFT", 0, -4)

	panel.integrationCard = createSection("Integrations", 150)
	panel.integrationFallback = createCheckbox(panel.integrationCard, "SettingsFallback", "Use Auctionator fallback", function(value)
		pe:SetSetting("integrations.economyUseAuctionatorFallback", value)
		pe:RefreshInventoryTabIfVisible()
		pe:RefreshCraftsTabIfVisible()
	end)
	panel.integrationFallback:SetPoint("TOPLEFT", 10, -34)
	panel.integrationFallbackSource = createCycleButton(panel.integrationCard, 260, "", function()
		local values = { "DBMinBuyout", "dbmarket", "DBRecent" }
		local current = tostring(pe:GetSetting("integrations.economyTSMFallbackString", "DBMinBuyout"))
		local nextIndex = 1
		for index, value in ipairs(values) do
			if value == current then
				nextIndex = (index % #values) + 1
				break
			end
		end
		pe:SetSetting("integrations.economyTSMFallbackString", values[nextIndex])
		pe:RefreshInventoryTabIfVisible()
		pe:RefreshCraftsTabIfVisible()
		SettingsTab:Refresh()
	end)
	panel.integrationFallbackSource:SetPoint("TOPLEFT", panel.integrationFallback, "BOTTOMLEFT", 4, -8)
	panel.integrationText = pe:CreateMutedText(panel.integrationCard, 800)
	panel.integrationText:SetPoint("TOPLEFT", panel.integrationFallbackSource, "BOTTOMLEFT", 0, -8)

	panel.debugCard = createSection("Debug", 88)
	panel.debugEnabled = createCheckbox(panel.debugCard, "SettingsDebug", "Enable debug logging in chat", function(value)
		pe:SetSetting("debug.enabled", value)
		SettingsTab:Refresh()
	end)
	panel.debugEnabled:SetPoint("TOPLEFT", 10, -34)

	panel.scroll:SetScript("OnSizeChanged", function()
		SettingsTab:Layout(panel)
	end)
	panel:SetScript("OnShow", function()
		SettingsTab:Layout(panel)
	end)
	SettingsTab:Layout(panel)
	return panel
end

function SettingsTab:ApplyTheme()
	local panel = ProfessionExporter.ui.settingsPanel
	if not panel then
		return
	end
	local pe = ProfessionExporter
	pe:StylePanel(panel.generalCard, "surface2")
	pe:StylePanel(panel.appearanceCard, "surface2")
	pe:StylePanel(panel.captureCard, "surface2")
	pe:StylePanel(panel.inventoryCard, "surface2")
	pe:StylePanel(panel.auctionCard, "surface2")
	pe:StylePanel(panel.integrationCard, "surface2")
	pe:StylePanel(panel.debugCard, "surface2")
end

function SettingsTab:Refresh()
	local pe = ProfessionExporter
	local panel = pe.ui.settingsPanel
	if not panel then
		return
	end
	setCheck(panel.generalMinimap, pe:GetSetting("general.showMinimapButton", true))
	setCheck(panel.appearanceReduced, pe:GetSetting("appearance.reducedOrnament", false))
	setCheck(panel.captureTree, pe:GetSetting("capture.captureSpecializationTree", true))
	setCheck(panel.captureOutput, pe:GetSetting("capture.includeRecipeOutputItemData", false))
	setCheck(panel.invEconomy, pe:GetSetting("inventory.economyShowColumns", true))
	setCheck(panel.invMat, pe:GetSetting("inventory.economyShowMatCost", true))
	setCheck(panel.invSale, pe:GetSetting("inventory.economyShowSaleRate", true))
	setCheck(panel.integrationFallback, pe:GetSetting("integrations.economyUseAuctionatorFallback", true))
	setCheck(panel.debugEnabled, pe:GetSetting("debug.enabled", false))
	if panel.auctionAutoCraftScan then
		setCheck(panel.auctionAutoCraftScan, pe:GetSetting("auction.autoCraftEconomyRefreshOnOpen", false))
	end
	if panel.auctionCraftOptionalSlots then
		setCheck(panel.auctionCraftOptionalSlots, pe:GetSetting("auction.craftScanIncludeOptionalSlots", false))
	end
	if panel.coHideUnlearned then
		setCheck(panel.coHideUnlearned, pe:GetSetting("craftingOrders.hideUnlearned", false))
	end
	if panel.coPatronKnowledge then
		setCheck(panel.coPatronKnowledge, pe:GetSetting("craftingOrders.patronKnowledgeOnly", false))
	end

	local preset = pe:GetSetting("appearance.themePreset", "slate")
	local scale = tonumber(pe:GetSetting("appearance.windowScale", 1)) or 1
	local batch = tonumber(pe:GetSetting("capture.inventorySnapshotBatchSize", 0)) or 0
	local historyRetention = tonumber(pe:GetSetting("auction.historyRetentionDays", 30)) or 30
	local freshnessMinutes = tonumber(pe:GetSetting("auction.priceFreshnessMinutes", 15)) or 15
	panel.appearancePreset:SetText("Theme preset: " .. preset)
	panel.appearanceScale:SetText(string.format("Window scale: %d%%", math.floor(scale * 100 + 0.5)))
	panel.captureBatch:SetText("Inventory batch size: " .. tostring(batch))
	panel.auctionHistoryRetention:SetText(string.format("Market history retention: %d days", historyRetention))
	panel.auctionFreshness:SetText(string.format("Non-inventory AH refresh age: %d min", freshnessMinutes))
	panel.integrationFallbackSource:SetText("Fallback price string: " .. tostring(pe:GetSetting("integrations.economyTSMFallbackString", "DBMinBuyout")))
	panel.integrationText:SetText(string.format(
		"TSM source strings:\nMarket: %s | Fallback: %s | Materials: %s | Sale rate: %s",
		tostring(pe:GetSetting("integrations.economyTSMMarketString", "dbmarket")),
		tostring(pe:GetSetting("integrations.economyTSMFallbackString", "DBMinBuyout")),
		tostring(pe:GetSetting("integrations.economyTSMMatString", "Crafting")),
		tostring(pe:GetSetting("integrations.economyTSMSaleRateString", "DBRegionSaleRate"))
	))
	self:Layout(panel)
end
