local addonName, ProfessionExporter = ...

local DocsTab = {}
ProfessionExporter.DocsTab = DocsTab

function DocsTab:Layout(panel)
	if not panel then
		return
	end
	local width = math.max(620, panel:GetWidth() - 24)
	local height = math.max(320, panel:GetHeight() - 70)
	local topicWidth = math.max(180, math.floor(width * 0.24))
	local bodyWidth = width - topicWidth - 12

	panel.subtitle:SetWidth(width - 12)

	panel.topicCard:ClearAllPoints()
	panel.topicCard:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -58)
	panel.topicCard:SetWidth(topicWidth)
	panel.topicCard:SetHeight(height)
	panel.topicContent:SetWidth(topicWidth - 44)

	panel.bodyCard:ClearAllPoints()
	panel.bodyCard:SetPoint("TOPLEFT", panel.topicCard, "TOPRIGHT", 12, 0)
	panel.bodyCard:SetWidth(bodyWidth)
	panel.bodyCard:SetHeight(height)
	panel.bodyContent:SetWidth(bodyWidth - 46)
	panel.body:SetWidth(bodyWidth - 66)
end

function DocsTab:Create(container, uiState)
	local pe = ProfessionExporter
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.docsPanel = panel

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("TOPLEFT", 12, -10)
	panel.title:SetText("Docs")

	panel.subtitle = pe:CreateMutedText(panel, 860)
	panel.subtitle:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
	panel.subtitle:SetText("Reference for scopes, export structure, and operational notes.")

	panel.topicCard = pe:CreateCard(panel, 220, 470, "surface2")
	panel.topicCard:SetPoint("TOPLEFT", panel.subtitle, "BOTTOMLEFT", 0, -10)
	panel.topicTitle = pe:CreateSectionTitle(panel.topicCard, "Topics")
	panel.topicTitle:SetPoint("TOPLEFT", 10, -10)
	panel.topicScroll = CreateFrame("ScrollFrame", addonName .. "DocsTopicListScroll", panel.topicCard, "UIPanelScrollFrameTemplate")
	panel.topicScroll:SetPoint("TOPLEFT", panel.topicTitle, "BOTTOMLEFT", 0, -8)
	panel.topicScroll:SetPoint("BOTTOMRIGHT", panel.topicCard, "BOTTOMRIGHT", -28, 10)
	panel.topicContent = CreateFrame("Frame", nil, panel.topicScroll)
	panel.topicContent:SetWidth(176)
	panel.topicContent:SetHeight(420)
	panel.topicScroll:SetScrollChild(panel.topicContent)
	panel.topicButtons = {}

	panel.bodyCard = pe:CreateCard(panel, 656, 470, "surface2")
	panel.bodyCard:SetPoint("TOPLEFT", panel.topicCard, "TOPRIGHT", 12, 0)
	panel.bodyTitle = pe:CreateSectionTitle(panel.bodyCard, "Reference")
	panel.bodyTitle:SetPoint("TOPLEFT", 10, -10)
	panel.bodyScroll = CreateFrame("ScrollFrame", addonName .. "DocsBodyPanelScroll", panel.bodyCard, "UIPanelScrollFrameTemplate")
	panel.bodyScroll:SetPoint("TOPLEFT", panel.bodyTitle, "BOTTOMLEFT", 0, -8)
	panel.bodyScroll:SetPoint("BOTTOMRIGHT", panel.bodyCard, "BOTTOMRIGHT", -28, 10)
	panel.bodyContent = CreateFrame("Frame", nil, panel.bodyScroll)
	panel.bodyContent:SetWidth(610)
	panel.bodyContent:SetHeight(400)
	panel.bodyScroll:SetScrollChild(panel.bodyContent)
	panel.body = pe:CreateMutedText(panel.bodyContent, 590)
	panel.body:SetPoint("TOPLEFT", 4, -4)
	panel:SetScript("OnSizeChanged", function()
		DocsTab:Layout(panel)
	end)
	DocsTab:Layout(panel)

	return panel
end

function DocsTab:ApplyTheme()
	local panel = ProfessionExporter.ui.docsPanel
	if not panel then
		return
	end
	local pe = ProfessionExporter
	pe:StylePanel(panel.topicCard, "surface2")
	pe:StylePanel(panel.bodyCard, "surface2")
end

function DocsTab:Refresh()
	local pe = ProfessionExporter
	local panel = pe.ui.docsPanel
	if not panel then
		return
	end
	local sections = pe.GetDocumentationSections and pe:GetDocumentationSections() or {}
	self:Layout(panel)
	for _, button in ipairs(panel.topicButtons) do
		button:Hide()
	end
	for index, section in ipairs(sections) do
		local button = panel.topicButtons[index]
		if not button then
			button = CreateFrame("Button", nil, panel.topicContent, "UIPanelButtonTemplate")
			button:SetSize(176, 22)
			panel.topicButtons[index] = button
		end
		button:SetPoint("TOPLEFT", 0, -((index - 1) * 24))
		button:SetText(section.title or ("Topic " .. index))
		button:SetScript("OnClick", function()
			panel.selectedIndex = index
			DocsTab:Refresh()
		end)
		button:Show()
	end
	panel.topicContent:SetHeight(math.max(200, #sections * 24))
	panel.selectedIndex = math.min(panel.selectedIndex or 1, math.max(1, #sections))
	local selected = sections[panel.selectedIndex]
	panel.body:SetText(selected and selected.body or "No documentation available.")
	panel.bodyContent:SetHeight(math.max(400, panel.body:GetStringHeight() + 16))
end
