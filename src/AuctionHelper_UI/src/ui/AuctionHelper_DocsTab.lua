local addonName, AuctionHelper = ...

local DocsTab = {}
AuctionHelper.DocsTab = DocsTab

local GAP = 12
local TOPIC_WIDTH = 220
local PAD = 12

-- Lines written in capitals are section headings in the docs text: draw them gold.
local function formatBody(pe, body)
	local lines = {}
	for line in string.gmatch((body or "") .. "\n", "(.-)\n") do
		if #line > 3 and line == string.upper(line) and string.find(line, "%u") then
			line = pe:Colorize(line, "gold")
		end
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

function DocsTab:Layout(panel)
	if not panel then
		return
	end
	local width = math.max(100, panel.bodyScroll:GetWidth())
	panel.bodyContent:SetWidth(width)
	panel.bodyTitle:SetWidth(width)
	panel.body:SetWidth(width)
	panel.bodyContent:SetHeight(math.ceil(panel.bodyTitle:GetStringHeight() + panel.body:GetStringHeight()) + 24)
end

-- The topic column on the left: a heading over a selectable list.
local function createTopicList(pe, panel)
	panel.topics = CreateFrame("Frame", nil, panel)
	panel.topics:SetPoint("TOPLEFT")
	panel.topics:SetPoint("BOTTOMLEFT")
	panel.topics:SetWidth(TOPIC_WIDTH)
	panel.topicHeading = pe:CreateHeading(panel.topics, "Topics")
	panel.topicHeading:SetPoint("TOPLEFT")
	panel.topicHeading:SetPoint("TOPRIGHT")
	panel.topicList = pe:CreateSelectList(panel.topics, function(key)
		panel.selectedIndex = key
		DocsTab:Refresh()
	end, function()
		return panel.selectedIndex
	end)
	panel.topicList.frame:SetPoint("TOPLEFT", panel.topicHeading, "BOTTOMLEFT", 0, -8)
	panel.topicList.frame:SetPoint("BOTTOMRIGHT", panel.topics, "BOTTOMRIGHT", 0, 0)
end

-- The article on the right: a scrolling title and body.
local function createArticle(pe, panel)
	panel.article = pe:CreateInset(panel)
	panel.article:SetPoint("TOPLEFT", panel.topics, "TOPRIGHT", GAP, 0)
	panel.article:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	if panel.article.SetClipsChildren then
		panel.article:SetClipsChildren(true)
	end
	panel.bodyScroll = CreateFrame("ScrollFrame", addonName .. "DocsBodyPanelScroll", panel.article, "UIPanelScrollFrameTemplate")
	panel.bodyScroll:SetPoint("TOPLEFT", PAD + 4, -PAD)
	panel.bodyScroll:SetPoint("BOTTOMRIGHT", -(PAD + 10), PAD)
	panel.bodyContent = CreateFrame("Frame", nil, panel.bodyScroll)
	panel.bodyContent:SetSize(400, 400)
	panel.bodyScroll:SetScrollChild(panel.bodyContent)
	panel.bodyTitle = pe:CreateText(panel.bodyContent, "GameFontHighlightLarge")
	panel.bodyTitle:SetPoint("TOPLEFT")
	panel.body = pe:CreateParagraph(panel.bodyContent, "textPrimary")
	panel.body:SetPoint("TOPLEFT", panel.bodyTitle, "BOTTOMLEFT", 0, -10)
	panel.body:SetSpacing(2)
end

function DocsTab:Create(container, uiState)
	local pe = AuctionHelper
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.docsPanel = panel
	createTopicList(pe, panel)
	createArticle(pe, panel)
	panel:SetScript("OnSizeChanged", function()
		DocsTab:Layout(panel)
	end)
	return panel
end

function DocsTab:ApplyTheme()
end

local function topicItems(sections)
	local items = {}
	for index, section in ipairs(sections) do
		items[index] = { key = index, label = section.title or ("Topic " .. index) }
	end
	return items
end

function DocsTab:Refresh()
	local pe = AuctionHelper
	local panel = pe.ui.docsPanel
	if not panel then
		return
	end
	local sections = pe.GetDocumentationSections and pe:GetDocumentationSections() or {}
	panel.selectedIndex = math.max(1, math.min(panel.selectedIndex or 1, #sections))
	panel.topicList:SetItems(topicItems(sections))

	local selected = sections[panel.selectedIndex]
	panel.bodyTitle:SetText(selected and selected.title or "Docs")
	panel.body:SetText(selected and formatBody(pe, selected.body) or "No documentation available.")
	panel.bodyScroll:SetVerticalScroll(0)
	self:Layout(panel)
end
