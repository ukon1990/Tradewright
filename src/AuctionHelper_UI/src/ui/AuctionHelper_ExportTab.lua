local addonName, ProfessionExporter = ...

local ExportTab = {}
ProfessionExporter.ExportTab = ExportTab

local function buildProfessionList(pe)
	local list = {}
	local key = pe:GetCharacterKey()
	local data = pe.db and pe.db.characters and pe.db.characters[key]
	for _, profession in pairs(data and data.professions or {}) do
		table.insert(list, profession)
	end
	table.sort(list, function(left, right)
		return pe:SortByNameThenId(
			{ professionName = left.professionName, skillLineID = left.skillLineID },
			{ professionName = right.professionName, skillLineID = right.skillLineID }
		)
	end)
	return list
end

function ExportTab:Layout(panel)
	if not panel then
		return
	end
	local width = math.max(620, panel:GetWidth() - 24)
	panel.subtitle:SetWidth(width - 12)

	local gap = 12
	local colWidth = math.floor((width - (gap * 2)) / 3)
	colWidth = math.max(190, colWidth)
	local topY = -58

	panel.accountCard:ClearAllPoints()
	panel.accountCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, topY)
	panel.accountCard:SetWidth(colWidth)

	panel.charCard:ClearAllPoints()
	panel.charCard:SetPoint("TOPLEFT", panel.accountCard, "TOPRIGHT", gap, 0)
	panel.charCard:SetWidth(colWidth)

	panel.helpCard:ClearAllPoints()
	panel.helpCard:SetPoint("TOPLEFT", panel.charCard, "TOPRIGHT", gap, 0)
	panel.helpCard:SetWidth(width - (colWidth * 2) - (gap * 2))

	panel.accountBody:SetWidth(colWidth - 30)
	panel.charBody:SetWidth(colWidth - 30)
	panel.helpBody:SetWidth(panel.helpCard:GetWidth() - 30)

	panel.profCard:ClearAllPoints()
	panel.profCard:SetPoint("TOPLEFT", panel.accountCard, "BOTTOMLEFT", 0, -12)
	panel.profCard:SetWidth(width)
	panel.profBody:SetWidth(width - 44)
	panel.profContent:SetWidth(width - 48)
end

function ExportTab:Create(container, uiState)
	local pe = ProfessionExporter
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.exportPanel = panel

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("TOPLEFT", 12, -10)
	panel.title:SetText("Export")

	panel.subtitle = pe:CreateMutedText(panel, 860)
	panel.subtitle:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
	panel.subtitle:SetText("Export account, character, or profession-specific compact packages for script ingestion. Full exports still use the copy box and SavedVariables flow.")

	panel.accountCard = pe:CreateCard(panel, 280, 156, "surface2")
	panel.accountCard:SetPoint("TOPLEFT", panel.subtitle, "BOTTOMLEFT", 0, -10)
	panel.accountTitle = pe:CreateSectionTitle(panel.accountCard, "Account")
	panel.accountTitle:SetPoint("TOPLEFT", 10, -10)
	panel.accountBody = pe:CreateMutedText(panel.accountCard, 250)
	panel.accountBody:SetPoint("TOPLEFT", panel.accountTitle, "BOTTOMLEFT", 0, -8)
	panel.exportAccount = CreateFrame("Button", nil, panel.accountCard, "UIPanelButtonTemplate")
	panel.exportAccount:SetSize(116, 22)
	panel.exportAccount:SetPoint("BOTTOMLEFT", 10, 10)
	panel.exportAccount:SetText("Export account")
	panel.exportAccount:SetScript("OnClick", function()
		pe:Export("account")
	end)
	panel.exportSummary = CreateFrame("Button", nil, panel.accountCard, "UIPanelButtonTemplate")
	panel.exportSummary:SetSize(126, 22)
	panel.exportSummary:SetPoint("LEFT", panel.exportAccount, "RIGHT", 8, 0)
	panel.exportSummary:SetText("Account summary")
	panel.exportSummary:SetScript("OnClick", function()
		pe:Export("account_summary")
	end)

	panel.charCard = pe:CreateCard(panel, 280, 156, "surface2")
	panel.charCard:SetPoint("LEFT", panel.accountCard, "RIGHT", 12, 0)
	panel.charTitle = pe:CreateSectionTitle(panel.charCard, "Current Character")
	panel.charTitle:SetPoint("TOPLEFT", 10, -10)
	panel.charBody = pe:CreateMutedText(panel.charCard, 250)
	panel.charBody:SetPoint("TOPLEFT", panel.charTitle, "BOTTOMLEFT", 0, -8)
	panel.exportCharacter = CreateFrame("Button", nil, panel.charCard, "UIPanelButtonTemplate")
	panel.exportCharacter:SetSize(116, 22)
	panel.exportCharacter:SetPoint("BOTTOMLEFT", 10, 10)
	panel.exportCharacter:SetText("Character")
	panel.exportCharacter:SetScript("OnClick", function()
		pe:Export("character")
	end)
	panel.fullDump = CreateFrame("Button", nil, panel.charCard, "UIPanelButtonTemplate")
	panel.fullDump:SetSize(244, 22)
	panel.fullDump:SetPoint("BOTTOMLEFT", 10, 38)
	panel.fullDump:SetText("Fresh scan + full dump")
	panel.fullDump:SetScript("OnClick", function()
		pe:StartFullCharacterDump()
	end)
	panel.fullDump:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText("Fresh scan + full dump", 1, 0.82, 0.2)
		GameTooltip:AddLine("Scans every learned profession, then exports the complete current-character payload.", 1, 1, 1, true)
		GameTooltip:AddLine("Includes recipes, full known and unknown specialization definitions, descriptions, and current talent allocations.", 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	panel.fullDump:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	panel.exportInventory = CreateFrame("Button", nil, panel.charCard, "UIPanelButtonTemplate")
	panel.exportInventory:SetSize(80, 22)
	panel.exportInventory:SetPoint("LEFT", panel.exportCharacter, "RIGHT", 8, 0)
	panel.exportInventory:SetText("Inventory")
	panel.exportInventory:SetScript("OnClick", function()
		pe:Export("inventory")
	end)
	panel.exportMeta = CreateFrame("Button", nil, panel.charCard, "UIPanelButtonTemplate")
	panel.exportMeta:SetSize(54, 22)
	panel.exportMeta:SetPoint("LEFT", panel.exportInventory, "RIGHT", 8, 0)
	panel.exportMeta:SetText("Meta")
	panel.exportMeta:SetScript("OnClick", function()
		pe:Export("character_meta")
	end)

	panel.helpCard = pe:CreateCard(panel, 304, 156, "surface2")
	panel.helpCard:SetPoint("LEFT", panel.charCard, "RIGHT", 12, 0)
	panel.helpTitle = pe:CreateSectionTitle(panel.helpCard, "Export Guidance")
	panel.helpTitle:SetPoint("TOPLEFT", 10, -10)
	panel.helpBody = pe:CreateMutedText(panel.helpCard, 274)
	panel.helpBody:SetPoint("TOPLEFT", panel.helpTitle, "BOTTOMLEFT", 0, -8)

	panel.exportInvCompact = CreateFrame("Button", nil, panel.helpCard, "UIPanelButtonTemplate")
	panel.exportInvCompact:SetSize(84, 20)
	panel.exportInvCompact:SetText("Inv compact")
	panel.exportInvCompact:SetScript("OnClick", function()
		pe:Export("inventory_compact")
	end)
	panel.exportProfCompact = CreateFrame("Button", nil, panel.helpCard, "UIPanelButtonTemplate")
	panel.exportProfCompact:SetSize(84, 20)
	panel.exportProfCompact:SetText("Prof compact")
	panel.exportProfCompact:SetScript("OnClick", function()
		pe:Export("professions_compact")
	end)
	panel.exportAuctionSnapshot = CreateFrame("Button", nil, panel.helpCard, "UIPanelButtonTemplate")
	panel.exportAuctionSnapshot:SetSize(84, 20)
	panel.exportAuctionSnapshot:SetText("AH snap")
	panel.exportAuctionSnapshot:SetScript("OnClick", function()
		pe:Export("auction_snapshot")
	end)
	panel.exportAuctionHistory = CreateFrame("Button", nil, panel.helpCard, "UIPanelButtonTemplate")
	panel.exportAuctionHistory:SetSize(84, 20)
	panel.exportAuctionHistory:SetText("AH hist")
	panel.exportAuctionHistory:SetScript("OnClick", function()
		pe:Export("auction_history")
	end)
	panel.exportCraftCosts = CreateFrame("Button", nil, panel.helpCard, "UIPanelButtonTemplate")
	panel.exportCraftCosts:SetSize(174, 20)
	panel.exportCraftCosts:SetText("Craft costs")
	panel.exportCraftCosts:SetScript("OnClick", function()
		pe:Export("crafting_costs")
	end)

	panel.profCard = pe:CreateCard(panel, 888, 360, "surface2")
	panel.profCard:SetPoint("TOPLEFT", panel.accountCard, "BOTTOMLEFT", 0, -12)
	panel.profTitle = pe:CreateSectionTitle(panel.profCard, "Per-Profession")
	panel.profTitle:SetPoint("TOPLEFT", 10, -10)
	panel.profBody = pe:CreateMutedText(panel.profCard, 844)
	panel.profBody:SetPoint("TOPLEFT", panel.profTitle, "BOTTOMLEFT", 0, -8)
	panel.profScroll = CreateFrame("ScrollFrame", addonName .. "ExportProfessionScroll", panel.profCard, "UIPanelScrollFrameTemplate")
	panel.profScroll:SetPoint("TOPLEFT", panel.profBody, "BOTTOMLEFT", 0, -8)
	panel.profScroll:SetPoint("BOTTOMRIGHT", panel.profCard, "BOTTOMRIGHT", -28, 10)
	panel.profContent = CreateFrame("Frame", nil, panel.profScroll)
	panel.profContent:SetWidth(840)
	panel.profContent:SetHeight(220)
	panel.profScroll:SetScrollChild(panel.profContent)
	panel.profRows = {}
	panel:SetScript("OnSizeChanged", function()
		ExportTab:Layout(panel)
	end)
	panel.exportInvCompact:SetPoint("BOTTOMLEFT", 10, 58)
	panel.exportProfCompact:SetPoint("LEFT", panel.exportInvCompact, "RIGHT", 6, 0)
	panel.exportAuctionSnapshot:SetPoint("BOTTOMLEFT", 10, 34)
	panel.exportAuctionHistory:SetPoint("LEFT", panel.exportAuctionSnapshot, "RIGHT", 6, 0)
	panel.exportCraftCosts:SetPoint("BOTTOMLEFT", 10, 10)

	ExportTab:Layout(panel)

	return panel
end

function ExportTab:ApplyTheme()
	local panel = ProfessionExporter.ui.exportPanel
	if not panel then
		return
	end
	local pe = ProfessionExporter
	pe:StylePanel(panel.accountCard, "surface2")
	pe:StylePanel(panel.charCard, "surface2")
	pe:StylePanel(panel.helpCard, "surface2")
	pe:StylePanel(panel.profCard, "surface2")
end

function ExportTab:Refresh()
	local pe = ProfessionExporter
	pe:InitDB()
	local panel = pe.ui.exportPanel
	if not panel then
		return
	end
	local key = pe:GetCharacterKey()
	local charData = pe.db.characters[key]
	self:Layout(panel)
	panel.accountBody:SetText("Account export includes all stored characters.\nSummary is smaller and easier to inspect.")
	panel.charBody:SetText(string.format(
		"Character key: %s\nProfessions stored: %d",
		tostring(key),
		pe:TableCount(charData and charData.professions or {})
	))
	panel.helpBody:SetText("Exports are emitted as compressed AuctionHelper packages (CBOR + Deflate + Base64). Use the website-oriented compact buttons below for smaller auction, inventory, profession, and crafting-cost payloads.")

	for _, row in ipairs(panel.profRows) do
		row:Hide()
	end

	local profList = buildProfessionList(pe)
	for index, profession in ipairs(profList) do
		local row = panel.profRows[index]
		if not row then
			row = CreateFrame("Frame", nil, panel.profContent, "BackdropTemplate")
			row:SetHeight(26)
			pe:StylePanel(row, "surface3")
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.name:SetPoint("LEFT", 10, 0)
			row.name:SetJustifyH("LEFT")
			row.allButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.allButton:SetSize(64, 20)
			row.allButton:SetPoint("RIGHT", -140, 0)
			row.allButton:SetText("All")
			row.recipesButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.recipesButton:SetSize(64, 20)
			row.recipesButton:SetPoint("RIGHT", -72, 0)
			row.recipesButton:SetText("Recipes")
			row.talentsButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.talentsButton:SetSize(64, 20)
			row.talentsButton:SetPoint("RIGHT", -4, 0)
			row.talentsButton:SetText("Talents")
			panel.profRows[index] = row
		end
		row:SetWidth(panel.profContent:GetWidth() - 20)
		row:SetPoint("TOPLEFT", 0, -((index - 1) * 30))
		row.name:SetWidth(math.max(200, row:GetWidth() - 230))
		row.name:SetText(string.format(
			"%s  |  skill %d/%d  |  recipes %d",
			tostring(profession.professionName or "?"),
			tonumber(profession.skillLevel) or 0,
			tonumber(profession.maxSkillLevel) or 0,
			tonumber(profession.recipeCount) or 0
		))
		local skillLineID = tostring(profession.skillLineID or "")
		row.allButton:SetScript("OnClick", function()
			pe:Export("profession", skillLineID)
		end)
		row.recipesButton:SetScript("OnClick", function()
			pe:Export("profession_recipes", skillLineID)
		end)
		row.talentsButton:SetScript("OnClick", function()
			pe:Export("profession_talents", skillLineID)
		end)
		row:Show()
	end
	panel.profContent:SetHeight(math.max(220, #profList * 30))
end
