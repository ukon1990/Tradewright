local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local ExportTab = {}
Tradewright.ExportTab = ExportTab

local GAP = 12
local LEFT_WIDTH = 420
local PAD = 10

-- A raised group with a heading, a wrapping explanation, wrapping buttons and an optional note.
local function createGroup(pe, parent, title, buttons, note)
	local group = pe:CreateInset(parent)
	group.heading = pe:CreateHeading(group, title)
	group.heading:SetPoint("TOPLEFT", PAD, -PAD)
	group.heading:SetPoint("TOPRIGHT", -PAD, -PAD)
	group.body = pe:CreateParagraph(group)
	group.body:SetPoint("TOPLEFT", group.heading, "BOTTOMLEFT", 0, -6)
	group.body:SetPoint("TOPRIGHT", group.heading, "BOTTOMRIGHT", 0, -6)
	group.buttonHost = CreateFrame("Frame", nil, group)
	group.buttons = {}
	for _, spec in ipairs(buttons) do
		group.buttons[#group.buttons + 1] = pe:CreateButton(group.buttonHost, spec[1], spec[2], spec[3])
	end
	if note then
		group.note = pe:CreateParagraph(group)
		group.note:SetText(note)
	end
	return group
end

local function layoutGroup(pe, group, width)
	local inner = width - PAD * 2
	local y = PAD + 18 + 6 + math.ceil(group.body:GetStringHeight()) + 10
	group.buttonHost:ClearAllPoints()
	group.buttonHost:SetPoint("TOPLEFT", group, "TOPLEFT", PAD, -y)
	group.buttonHost:SetSize(inner, 1)
	local buttonsHeight = pe:FlowButtons(group.buttonHost, group.buttons, inner, 8)
	group.buttonHost:SetHeight(buttonsHeight)
	y = y + buttonsHeight
	if group.note then
		group.note:ClearAllPoints()
		group.note:SetPoint("TOPLEFT", group, "TOPLEFT", PAD, -(y + 8))
		group.note:SetWidth(inner)
		y = y + 8 + math.ceil(group.note:GetStringHeight())
	end
	group:SetHeight(y + PAD)
end

function ExportTab:Layout(panel)
	if not panel then
		return
	end
	local pe = Tradewright
	local leftWidth = math.min(LEFT_WIDTH, math.floor((panel:GetWidth() - GAP) / 2))
	panel.left:SetWidth(leftWidth)
	local previous
	for _, group in ipairs(panel.groups) do
		layoutGroup(pe, group, leftWidth)
		group:ClearAllPoints()
		if previous then
			group:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -GAP)
		else
			group:SetPoint("TOPLEFT", panel.left, "TOPLEFT", 0, 0)
		end
		group:SetWidth(leftWidth)
		previous = group
	end
end

-- The left column: one group of export buttons each for this character, the account and compact packages.
local function createExportGroups(pe, panel)
	panel.left = CreateFrame("Frame", nil, panel)
	panel.left:SetPoint("TOPLEFT", panel.intro, "BOTTOMLEFT", 0, -GAP)
	panel.left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)

	panel.characterGroup = createGroup(pe, panel.left, L["This character"], {
		{ L["Scan and export everything"], function() pe:StartFullCharacterDump() end, { primary = true,
			tooltip = L["Rescans every learned profession first, then exports recipes, specialization data and talent choices."] } },
		{ "Character", function() pe:Export("character") end },
		{ "Inventory", function() pe:Export("inventory") end },
		{ L["Character info"], function() pe:Export("character_meta") end },
	}, L["Scan and export everything rescans every learned profession first."])
	panel.accountGroup = createGroup(pe, panel.left, "Account", {
		{ L["Export account"], function() pe:Export("account") end },
		{ L["Account summary"], function() pe:Export("account_summary") end },
	})
	panel.accountGroup.body:SetText(L["Every saved character. The summary is smaller and easier to read."])
	panel.compactGroup = createGroup(pe, panel.left, L["Compact packages"], {
		{ "Inventory", function() pe:Export("inventory_compact") end },
		{ "Professions", function() pe:Export("professions_compact") end },
		{ L["Auction prices"], function() pe:Export("auction_snapshot") end },
		{ L["Auction history"], function() pe:Export("auction_history") end },
		{ L["Craft costs"], function() pe:Export("crafting_costs") end },
	})
	panel.compactGroup.body:SetText(L["Smaller packages for the website, one topic each."])
	panel.groups = { panel.characterGroup, panel.accountGroup, panel.compactGroup }
end

-- The right column: the scanned professions of this character, each exportable on its own.
local function createProfessionTable(pe, panel)
	panel.right = CreateFrame("Frame", nil, panel)
	panel.right:SetPoint("TOPLEFT", panel.left, "TOPRIGHT", GAP, 0)
	panel.right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	panel.profHeading = pe:CreateHeading(panel.right, L["One profession"])
	panel.profHeading:SetPoint("TOPLEFT")
	panel.profHeading:SetPoint("TOPRIGHT")
	panel.profTable = pe:CreateReusableTable(panel.right, {
		autoFitToScroll = true,
		footer = true,
		emptyTitle = L["No professions scanned"],
		emptyHint = L["Open a profession window and press Scan."],
	})
	panel.profTable.frame:SetPoint("TOPLEFT", panel.profHeading, "BOTTOMLEFT", 0, -8)
	panel.profTable.frame:SetPoint("BOTTOMRIGHT", panel.right, "BOTTOMRIGHT", 0, 0)
	panel.profTable:SetColumns(pe:CreateProfessionColumns())
end

function ExportTab:Create(container, uiState)
	local pe = Tradewright
	local panel = CreateFrame("Frame", nil, container)
	panel:SetAllPoints()
	uiState.exportPanel = panel

	panel.intro = pe:CreateParagraph(panel)
	panel.intro:SetPoint("TOPLEFT")
	panel.intro:SetPoint("TOPRIGHT")
	panel.intro:SetText(
		L["Each button opens the export window with a compressed package to copy. The same package is written to the addon's saved data on /reload."])
	createExportGroups(pe, panel)
	createProfessionTable(pe, panel)

	panel:SetScript("OnSizeChanged", function()
		ExportTab:Layout(panel)
	end)
	ExportTab:Layout(panel)
	return panel
end

function ExportTab:ApplyTheme()
end

-- "Name · Realm, 3 professions stored." for the character group.
local function characterSummary(pe, key, charData)
	local meta = charData and charData.meta or {}
	local professionCount = pe:TableCount(charData and charData.professions or {})
	return string.format(L["%s, %d %s saved."],
		meta.name and meta.realm and (meta.name .. " · " .. meta.realm) or tostring(key),
		professionCount, pe:Plural(professionCount, "profession"))
end

function ExportTab:Refresh()
	local pe = Tradewright
	local panel = pe.ui.exportPanel
	if not panel then
		return
	end
	local key = pe:GetCharacterKey()
	local charData = pe.db and pe.db.characters and pe.db.characters[key]
	panel.characterGroup.body:SetText(characterSummary(pe, key, charData))

	local rows = pe:BuildProfessionRows(charData)
	panel.profTable:SetRows(rows)
	panel.profTable:Refresh()
	panel.profTable:SetFooterText(string.format(L["%d %s scanned on this character"], #rows, pe:Plural(#rows, "profession")))
	self:Layout(panel)
end
