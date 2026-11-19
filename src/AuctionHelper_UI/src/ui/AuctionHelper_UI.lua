local addonName, ProfessionExporter = ...

local DASHBOARD_ACCOUNT_KEY = ProfessionExporter.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__"

ProfessionExporter.ui = ProfessionExporter.ui or {}

function ProfessionExporter:GetDashboardCharacterKeyList(db)
	db = db or self.db
	local seen = {}
	local keys = {}
	if type(db.aggregate) == "table" and type(db.aggregate.characterKeys) == "table" then
		for _, k in ipairs(db.aggregate.characterKeys) do
			if k and not seen[k] then
				seen[k] = true
				table.insert(keys, k)
			end
		end
	end
	for k in pairs(db.characters or {}) do
		if not seen[k] then
			seen[k] = true
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	return keys
end

function ProfessionExporter:GetDashboardSidebarCharacterLabel(characterKey, charData, currentKey)
	if characterKey == currentKey then
		local base = characterKey
		local meta = charData and charData.meta
		if meta and meta.name and meta.realm then
			base = string.format("%s — %s", tostring(meta.name), tostring(meta.realm))
		end
		return base .. "  |cFF33FF99(you)|r"
	end
	local meta = charData and charData.meta
	if meta and meta.name and meta.realm then
		return string.format("%s — %s", tostring(meta.name), tostring(meta.realm))
	end
	return tostring(characterKey)
end

function ProfessionExporter:DashboardAnchorInventoryScroll(ui)
	local right = ui.rightPane
	if not right or not ui.rightScroll or not ui.detailMeta then
		return
	end
	ui.rightScroll:ClearAllPoints()
	if ui.profPanel and ui.profPanel:IsShown() then
		ui.rightScroll:SetPoint("TOPLEFT", ui.profPanel, "BOTTOMLEFT", -4, -6)
	else
		ui.rightScroll:SetPoint("TOPLEFT", ui.detailMeta, "BOTTOMLEFT", -4, -10)
	end
	ui.rightScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -28, 0)
end

function ProfessionExporter:FormatScanTimestamp(ts)
	if not ts or ts <= 0 then
		return "—"
	end
	return date("%Y-%m-%d %H:%M", ts)
end

function ProfessionExporter:GetItemDisplayName(itemID)
	if not itemID then
		return "?"
	end
	local desc = self:ResolveItemDescriptor(itemID)
	if desc and desc.name and desc.name ~= "" then
		return desc.name
	end
	return "#" .. tostring(itemID)
end

function ProfessionExporter:NotifyDashboardUpdate(skipRebuild)
	local ui = self.ui
	if ui and ui.mainFrame and ui.mainFrame:IsShown() then
		self:RefreshDashboard(skipRebuild)
	end
end

function ProfessionExporter:ToggleDashboard()
	self:InitDB()
	local ui = self.ui
	if not ui.mainFrame then
		self:CreateDashboardFrame()
	end
	local f = ui.mainFrame
	if f:IsShown() then
		self:DebugLog("UI", "Dashboard closed")
		f:Hide()
	else
		if not ui.selectedCharacterKey then
			ui.selectedCharacterKey = self:GetCharacterKey()
		end
		self:RefreshDashboard()
		self:DebugLog("UI", "Dashboard opened", {
			string.format("selectedCharacterKey=%s", tostring(ui.selectedCharacterKey)),
		})
		f:Show()
		self:ShowDashboardTab(ui.activeMainTab or "dashboard")
	end
end

function ProfessionExporter:CreateDashboardFrame()
	local ui = self.ui
	local f = CreateFrame("Frame", addonName .. "Dashboard", UIParent, "BackdropTemplate")
	f:SetSize(920, 600)
	f:SetPoint("CENTER")
	f:SetFrameStrata("MEDIUM")
	f:SetFrameLevel(100)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:SetBackdrop({
		bgFile = "Interface/ChatFrame/ChatFrameBackground",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0.06, 0.06, 0.09, 0.98)
	f:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("AuctionHelper")

	local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -8, -8)
	closeBtn:SetScript("OnClick", function()
		f:Hide()
	end)

	ui.tabDashBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ui.tabDashBtn:SetSize(118, 24)
	ui.tabDashBtn:SetPoint("TOP", title, "BOTTOM", -124, -8)
	ui.tabDashBtn:SetText("Dashboard")
	ui.tabDashBtn:SetScript("OnClick", function()
		ProfessionExporter:ShowDashboardTab("dashboard")
	end)

	ui.tabInvBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ui.tabInvBtn:SetSize(118, 24)
	ui.tabInvBtn:SetPoint("LEFT", ui.tabDashBtn, "RIGHT", 8, 0)
	ui.tabInvBtn:SetText("Inventory")
	ui.tabInvBtn:SetScript("OnClick", function()
		ProfessionExporter:ShowDashboardTab("inventory")
	end)

	ui.tabDocsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ui.tabDocsBtn:SetSize(118, 24)
	ui.tabDocsBtn:SetPoint("LEFT", ui.tabInvBtn, "RIGHT", 8, 0)
	ui.tabDocsBtn:SetText("Documentation")
	ui.tabDocsBtn:SetScript("OnClick", function()
		ProfessionExporter:ShowDashboardTab("docs")
	end)

	local dashboardPanel = CreateFrame("Frame", nil, f)
	dashboardPanel:SetPoint("TOPLEFT", 12, -82)
	dashboardPanel:SetPoint("BOTTOMRIGHT", -12, 12)
	ui.dashboardPanel = dashboardPanel

	-- Left column
	local left = CreateFrame("Frame", nil, dashboardPanel)
	left:SetPoint("TOPLEFT", 2, -2)
	left:SetPoint("BOTTOMLEFT", 2, 2)
	left:SetWidth(268)

	ui.summaryText = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.summaryText:SetPoint("TOPLEFT", 0, 0)
	ui.summaryText:SetWidth(260)
	ui.summaryText:SetJustifyH("LEFT")

	-- UICheckButtonTemplate is always present; InterfaceOptionsSmallCheckButtonTemplate may be unavailable until options UI loads.
	ui.debugCheckbox = CreateFrame("CheckButton", addonName .. "DashDebugCB", left, "UICheckButtonTemplate")
	ui.debugCheckbox:SetPoint("TOPLEFT", ui.summaryText, "BOTTOMLEFT", -2, -6)
	local debugLabel = _G[ui.debugCheckbox:GetName() .. "Text"]
	if debugLabel then
		debugLabel:SetText("Debug logging (chat)")
	end
	ui.debugCheckbox:SetScript("OnClick", function(cb)
		ProfessionExporter:SetDebugEnabled(cb:GetChecked())
		ProfessionExporter:RefreshDashboard(true)
	end)

	ui.specCheckbox = CreateFrame("CheckButton", addonName .. "DashSpecCB", left, "UICheckButtonTemplate")
	ui.specCheckbox:SetPoint("TOPLEFT", ui.debugCheckbox, "BOTTOMLEFT", 0, -2)
	local specLabel = _G[ui.specCheckbox:GetName() .. "Text"]
	if specLabel then
		specLabel:SetText("Capture specialization tree")
	end
	ui.specCheckbox:SetScript("OnClick", function(cb)
		ProfessionExporter:SetSetting("capture.captureSpecializationTree", cb:GetChecked() and true or false)
		ProfessionExporter:RefreshDashboard(true)
	end)

	ui.recipeOutputCheckbox = CreateFrame("CheckButton", addonName .. "DashRecipeOutCB", left, "UICheckButtonTemplate")
	ui.recipeOutputCheckbox:SetPoint("TOPLEFT", ui.specCheckbox, "BOTTOMLEFT", 0, -2)
	local recipeOutLabel = _G[ui.recipeOutputCheckbox:GetName() .. "Text"]
	if recipeOutLabel then
		recipeOutLabel:SetText("Verbose recipe output API (larger export payload)")
	end
	ui.recipeOutputCheckbox:SetScript("OnClick", function(cb)
		ProfessionExporter:SetSetting("capture.includeRecipeOutputItemData", cb:GetChecked() and true or false)
		ProfessionExporter:RefreshDashboard(true)
	end)

	local leftScroll = CreateFrame("ScrollFrame", addonName .. "DashCharScroll", left, "UIPanelScrollFrameTemplate")
	leftScroll:SetPoint("TOPLEFT", ui.recipeOutputCheckbox, "BOTTOMLEFT", 2, -6)
	leftScroll:SetPoint("BOTTOMLEFT", 0, 112)
	leftScroll:SetWidth(260)

	local leftContent = CreateFrame("Frame", nil, leftScroll)
	leftContent:SetWidth(240)
	leftContent:SetHeight(400)
	leftScroll:SetScrollChild(leftContent)

	ui.historyLabel = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ui.historyLabel:SetPoint("BOTTOMLEFT", 0, 88)
	ui.historyLabel:SetText("Recent scans")

	ui.historyText = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.historyText:SetPoint("TOPLEFT", ui.historyLabel, "BOTTOMLEFT", 0, -4)
	ui.historyText:SetWidth(260)
	ui.historyText:SetJustifyH("LEFT")

	-- Right column
	local right = CreateFrame("Frame", nil, dashboardPanel)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
	right:SetPoint("BOTTOMRIGHT", dashboardPanel, "BOTTOMRIGHT", -2, 2)
	ui.rightPane = right

	ui.exportHeadingAccount = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.exportHeadingAccount:SetPoint("TOPLEFT", 0, -6)
	ui.exportHeadingAccount:SetText("Account export")

	ui.btnExportAccount = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnExportAccount:SetSize(124, 24)
	ui.btnExportAccount:SetPoint("TOPLEFT", ui.exportHeadingAccount, "BOTTOMLEFT", 0, -4)
	ui.btnExportAccount:SetText("Export account")
	ui.btnExportAccount:SetScript("OnClick", function()
		ProfessionExporter:Export("account")
	end)

	ui.btnExportAccountSummary = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnExportAccountSummary:SetSize(124, 24)
	ui.btnExportAccountSummary:SetPoint("LEFT", ui.btnExportAccount, "RIGHT", 6, 0)
	ui.btnExportAccountSummary:SetText("Account summary")
	ui.btnExportAccountSummary:SetScript("OnClick", function()
		ProfessionExporter:Export("account_summary")
	end)

	ui.exportHeadingCharacter = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.exportHeadingCharacter:SetPoint("TOPLEFT", ui.btnExportAccount, "BOTTOMLEFT", 0, -8)
	ui.exportHeadingCharacter:SetText("This character (logged in only)")

	ui.btnExportChar = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnExportChar:SetSize(102, 24)
	ui.btnExportChar:SetPoint("TOPLEFT", ui.exportHeadingCharacter, "BOTTOMLEFT", 0, -4)
	ui.btnExportChar:SetText("Export char")
	ui.btnExportChar:SetScript("OnClick", function()
		ProfessionExporter:Export("character")
	end)

	ui.btnExportProfessions = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnExportProfessions:SetSize(100, 24)
	ui.btnExportProfessions:SetPoint("LEFT", ui.btnExportChar, "RIGHT", 6, 0)
	ui.btnExportProfessions:SetText("Professions")
	ui.btnExportProfessions:SetScript("OnClick", function()
		ProfessionExporter:Export("professions")
	end)

	ui.btnExportInventory = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnExportInventory:SetSize(92, 24)
	ui.btnExportInventory:SetPoint("LEFT", ui.btnExportProfessions, "RIGHT", 6, 0)
	ui.btnExportInventory:SetText("Inventory")
	ui.btnExportInventory:SetScript("OnClick", function()
		ProfessionExporter:Export("inventory")
	end)

	ui.btnExportMeta = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnExportMeta:SetSize(84, 24)
	ui.btnExportMeta:SetPoint("LEFT", ui.btnExportInventory, "RIGHT", 6, 0)
	ui.btnExportMeta:SetText("Char meta")
	ui.btnExportMeta:SetScript("OnClick", function()
		ProfessionExporter:Export("character_meta")
	end)

	ui.btnExportProfRecipes = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnExportProfRecipes:SetSize(118, 24)
	ui.btnExportProfRecipes:SetPoint("TOPLEFT", ui.btnExportChar, "BOTTOMLEFT", 0, -4)
	ui.btnExportProfRecipes:SetText("Prof. recipes")
	ui.btnExportProfRecipes:SetScript("OnClick", function()
		ProfessionExporter:Export("professions_recipes")
	end)

	ui.btnExportProfTalents = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnExportProfTalents:SetSize(118, 24)
	ui.btnExportProfTalents:SetPoint("LEFT", ui.btnExportProfRecipes, "RIGHT", 6, 0)
	ui.btnExportProfTalents:SetText("Prof. talents")
	ui.btnExportProfTalents:SetScript("OnClick", function()
		ProfessionExporter:Export("professions_talents")
	end)

	ui.exportHeadingActions = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.exportHeadingActions:SetPoint("TOPLEFT", ui.btnExportProfRecipes, "BOTTOMLEFT", 0, -8)
	ui.exportHeadingActions:SetText("Scan & inventory snapshot")

	ui.btnScan = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnScan:SetSize(128, 24)
	ui.btnScan:SetPoint("TOPLEFT", ui.exportHeadingActions, "BOTTOMLEFT", 0, -4)
	ui.btnScan:SetText("Scan professions")
	ui.btnScan:SetScript("OnClick", function()
		ProfessionExporter:StartScan()
	end)

	ui.btnRefreshInv = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	ui.btnRefreshInv:SetSize(140, 24)
	ui.btnRefreshInv:SetPoint("LEFT", ui.btnScan, "RIGHT", 6, 0)
	ui.btnRefreshInv:SetText("Refresh inventory")
	ui.btnRefreshInv:SetScript("OnClick", function()
		ProfessionExporter:DashboardRefreshInventory()
	end)

	ui.detailTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	ui.detailTitle:SetPoint("TOPLEFT", ui.btnScan, "BOTTOMLEFT", 0, -10)
	ui.detailTitle:SetWidth(520)
	ui.detailTitle:SetJustifyH("LEFT")

	ui.detailMeta = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.detailMeta:SetPoint("TOPLEFT", ui.detailTitle, "BOTTOMLEFT", 0, -8)
	ui.detailMeta:SetWidth(520)
	ui.detailMeta:SetJustifyH("LEFT")

	ui.profPanel = CreateFrame("Frame", nil, right)
	ui.profPanel:SetPoint("TOPLEFT", ui.detailMeta, "BOTTOMLEFT", -4, -6)
	ui.profPanel:SetWidth(548)
	ui.profPanel:SetHeight(130)
	ui.profPanel:Hide()

	ui.profPanelHeading = ui.profPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.profPanelHeading:SetPoint("TOPLEFT", 4, -2)
	ui.profPanelHeading:SetText("Per profession (smaller package — logged in only)")

	ui.profExportScroll = CreateFrame("ScrollFrame", addonName .. "ProfExportScroll", ui.profPanel, "UIPanelScrollFrameTemplate")
	ui.profExportScroll:SetPoint("TOPLEFT", ui.profPanelHeading, "BOTTOMLEFT", -8, -4)
	ui.profExportScroll:SetPoint("BOTTOMRIGHT", ui.profPanel, "BOTTOMRIGHT", -28, 4)

	ui.profExportContent = CreateFrame("Frame", nil, ui.profExportScroll)
	ui.profExportContent:SetWidth(460)
	ui.profExportContent:SetHeight(400)
	ui.profExportScroll:SetScrollChild(ui.profExportContent)

	ui.profExportRows = {}

	local rightScroll = CreateFrame("ScrollFrame", addonName .. "DashDetailScroll", right, "UIPanelScrollFrameTemplate")
	rightScroll:SetPoint("TOPLEFT", ui.detailMeta, "BOTTOMLEFT", -4, -10)
	rightScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -28, 0)

	local rightContent = CreateFrame("Frame", nil, rightScroll)
	rightContent:SetWidth(500)
	rightContent:SetHeight(800)
	rightScroll:SetScrollChild(rightContent)

	ui.detailBody = rightContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.detailBody:SetPoint("TOPLEFT", 8, -4)
	ui.detailBody:SetWidth(484)
	ui.detailBody:SetJustifyH("LEFT")
	ui.detailBody:SetWordWrap(true)

	local docsPanel = CreateFrame("Frame", nil, f)
	docsPanel:SetPoint("TOPLEFT", 12, -82)
	docsPanel:SetPoint("BOTTOMRIGHT", -12, 12)
	docsPanel:Hide()
	ui.docsPanel = docsPanel

	local docsHeading = docsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	docsHeading:SetPoint("TOPLEFT", 10, -8)
	docsHeading:SetText("Export packages — structure & scopes")

	local docsHint = docsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	docsHint:SetPoint("TOPLEFT", docsHeading, "BOTTOMLEFT", 0, -6)
	docsHint:SetWidth(800)
	docsHint:SetJustifyH("LEFT")
	docsHint:SetText("Full reference: |cffffffffInterface/AddOns/AuctionHelper/docs/EXPORT_PACKAGE_FORMAT.md|r — decode flow, compact scope legends, paging notes, and SavedVariables details. Dashboard: All characters (account) sidebar + per-profession Export when on your character.")

	ui.docsTopicScroll = CreateFrame("ScrollFrame", addonName .. "DocsTopicScroll", docsPanel, "UIPanelScrollFrameTemplate")
	ui.docsTopicScroll:SetPoint("TOPLEFT", docsHint, "BOTTOMLEFT", -4, -10)
	ui.docsTopicScroll:SetPoint("BOTTOMLEFT", 8, 10)
	ui.docsTopicScroll:SetWidth(172)

	ui.docsTopicList = CreateFrame("Frame", nil, ui.docsTopicScroll)
	ui.docsTopicList:SetWidth(152)
	ui.docsTopicScroll:SetScrollChild(ui.docsTopicList)

	ui.docsBodyScroll = CreateFrame("ScrollFrame", addonName .. "DocsBodyScroll", docsPanel, "UIPanelScrollFrameTemplate")
	ui.docsBodyScroll:SetPoint("TOPLEFT", ui.docsTopicScroll, "TOPRIGHT", 10, 0)
	ui.docsBodyScroll:SetPoint("BOTTOMRIGHT", docsPanel, "BOTTOMRIGHT", -28, 10)

	ui.docsBodyContent = CreateFrame("Frame", nil, ui.docsBodyScroll)
	ui.docsBodyContent:SetWidth(620)
	ui.docsBody = ui.docsBodyContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.docsBody:SetPoint("TOPLEFT", 6, -6)
	ui.docsBody:SetWidth(600)
	ui.docsBody:SetJustifyH("LEFT")
	ui.docsBody:SetWordWrap(true)
	ui.docsBodyScroll:SetScrollChild(ui.docsBodyContent)

	ui.mainFrame = f
	ui.leftContent = leftContent
	ui.leftScroll = leftScroll
	ui.rightScroll = rightScroll
	ui.rightContent = rightContent
	ui.charButtons = {}
	ui.docsPanelInited = false
	ui.activeMainTab = "dashboard"

	self:EnsureInventoryPanel(f)
	self:ShowDashboardTab("dashboard")
	-- Frames default to shown; start hidden so /profexport and the minimap button open on first use.
	f:Hide()
end

--- Minimap anchor angle in degrees (0 = east, counterclockwise); persisted via integrations.minimapButtonAngle.
function ProfessionExporter:UpdateMinimapButtonPosition(button)
	if not button or not Minimap then
		return
	end
	self:InitDB()
	local deg = tonumber(self:GetSetting("integrations.minimapButtonAngle", 225)) or 225
	local rad = math.rad(deg)
	local cosA, sinA = math.cos(rad), math.sin(rad)
	local m = Minimap
	local radius = (math.min(m:GetWidth(), m:GetHeight()) * 0.5) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", m, "CENTER", cosA * radius, sinA * radius)
end

function ProfessionExporter:EnsureMinimapButton()
	if not Minimap then
		return
	end
	self:InitDB()
	local ui = self.ui
	if ui.minimapButton then
		self:UpdateMinimapButtonPosition(ui.minimapButton)
		return
	end

	local btn = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
	btn:SetSize(24, 24)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight", "ADD")

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER", 0, 0)
	icon:SetTexture("Interface/Icons/INV_Misc_Book_09")

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
	border:SetSize(52, 52)
	border:SetPoint("TOPLEFT", -9, 7)

	btn:RegisterForClicks("LeftButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnClick", function()
		ProfessionExporter:ToggleDashboard()
	end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local angle = math.deg(math.atan2(py - my, px - mx))
			local settings = ProfessionExporter.db and ProfessionExporter.db.settings
			local integrations = settings and settings.integrations
			if integrations then
				integrations.minimapButtonAngle = angle
			end
			if ProfessionExporter.SyncLegacySettingAlias then
				ProfessionExporter:SyncLegacySettingAlias("integrations.minimapButtonAngle", angle)
			end
			ProfessionExporter:UpdateMinimapButtonPosition(self)
		end)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("AuctionHelper", 1, 1, 1)
		GameTooltip:AddLine("Click to open or close the window. Use the Inventory tab for the item table.", nil, nil, nil, true)
		GameTooltip:AddLine("Drag to move this button.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)

	ui.minimapButton = btn
	self:UpdateMinimapButtonPosition(btn)
end

function ProfessionExporter:ShowDashboardTab(tabId)
	local ui = self.ui
	if not ui or not ui.mainFrame then
		return
	end
	ui.activeMainTab = tabId
	local isDash = tabId == "dashboard"
	local isInv = tabId == "inventory"
	if ui.dashboardPanel then
		ui.dashboardPanel:SetShown(isDash)
	end
	if ui.inventoryPanel then
		ui.inventoryPanel:SetShown(isInv)
	end
	if ui.docsPanel then
		ui.docsPanel:SetShown(tabId == "docs")
	end
	if ui.tabDashBtn then
		ui.tabDashBtn:SetAlpha(isDash and 1 or 0.65)
	end
	if ui.tabInvBtn then
		ui.tabInvBtn:SetAlpha(isInv and 1 or 0.65)
	end
	if ui.tabDocsBtn then
		ui.tabDocsBtn:SetAlpha(tabId == "docs" and 1 or 0.65)
	end
	if tabId == "docs" then
		if not ui.docsPanelInited then
			self:InitDocumentationPanel()
			ui.docsPanelInited = true
		end
		self:RefreshDocumentationLayout()
	end
	if isInv then
		self:RefreshInventoryTab()
	end
end

function ProfessionExporter:InitDocumentationPanel()
	local ui = self.ui
	if ui.docsTopicButtons then
		return
	end
	local sections = self.GetDocumentationSections and self:GetDocumentationSections() or {}
	if #sections == 0 then
		return
	end
	ui.docsTopicButtons = {}
	local rowH = 24
	for i, sec in ipairs(sections) do
		local btn = CreateFrame("Button", nil, ui.docsTopicList, "UIPanelButtonTemplate")
		btn:SetSize(156, rowH - 2)
		btn:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
		btn:SetText(sec.title)
		local idx = i
		btn:SetScript("OnClick", function()
			ProfessionExporter:SelectDocumentationSection(idx)
		end)
		ui.docsTopicButtons[i] = btn
	end
	ui.docsTopicList:SetHeight(math.max(320, #sections * rowH + 8))
	self:SelectDocumentationSection(1)
end

function ProfessionExporter:SelectDocumentationSection(index)
	local ui = self.ui
	local sections = self.GetDocumentationSections and self:GetDocumentationSections() or {}
	local sec = sections[index]
	if not sec or not ui.docsBody then
		return
	end
	ui.docsSelectedIndex = index
	ui.docsBody:SetText(sec.body or "")
	local h = ui.docsBody:GetStringHeight() + 24
	ui.docsBodyContent:SetHeight(math.max(h, ui.docsBodyScroll:GetHeight() or 400))
	ui.docsBodyScroll:SetVerticalScroll(0)
end

function ProfessionExporter:RefreshDocumentationLayout()
	local ui = self.ui
	if not ui.docsBodyScroll or not ui.docsBody then
		return
	end
	local idx = ui.docsSelectedIndex or 1
	self:SelectDocumentationSection(idx)
end

function ProfessionExporter:OpenDocumentationTab()
	self:InitDB()
	if not self.ui or not self.ui.mainFrame then
		self:CreateDashboardFrame()
	end
	self.ui.mainFrame:Show()
	self:ShowDashboardTab("docs")
end

function ProfessionExporter:DashboardRefreshInventory()
	local key, data = self:GetOrCreateCharacterDataForLiveUpdate()
	data.lastLiveInventoryUpdate = time()
	self:UpdateInventorySnapshot(data, {
		forceImmediate = false,
		onComplete = function()
			self:PatchAggregateInventorySummaryForCharacter(key, data)
			self:DebugLog("UI", "DashboardRefreshInventory", {
				string.format("characterKey=%s", key),
				string.format("itemTypesTracked=%s", tostring(data.inventorySnapshot and data.inventorySnapshot.itemTypesTracked)),
			})
			self:PrintMessage(string.format("Updated profession-relevant inventory snapshot for %s.", key))
			self:NotifyDashboardUpdate(true)
		end,
	})
end

function ProfessionExporter:RefreshDashboard(skipRebuild)
	self:InitDB()
	if not skipRebuild or self:AggregateNeedsRebuild() then
		self:BuildAggregate()
	end

	local ui = self.ui
	if ui.debugCheckbox then
		ui.debugCheckbox:SetChecked(self:IsDebugEnabled())
	end
	if ui.specCheckbox then
		ui.specCheckbox:SetChecked(self:GetSetting("capture.captureSpecializationTree", true) ~= false)
	end
	if ui.recipeOutputCheckbox then
		ui.recipeOutputCheckbox:SetChecked(self:GetSetting("capture.includeRecipeOutputItemData", false) == true)
	end
	local db = self.db
	local agg = db.aggregate or {}
	local keys = self:GetDashboardCharacterKeyList(db)
	local numChars = #keys
	local aggTime = self:FormatScanTimestamp(agg.updatedAt)
	ui.summaryText:SetText(string.format(
		"|cffffffffAccount overview|r\nCharacters scanned: %d\nAggregate rebuilt: %s",
		numChars,
		aggTime
	))

	local currentKey = self:GetCharacterKey()
	local function dashboardSelectionValid(k)
		return k == DASHBOARD_ACCOUNT_KEY or (k and db.characters[k])
	end
	if not dashboardSelectionValid(ui.selectedCharacterKey) then
		if db.characters[currentKey] then
			ui.selectedCharacterKey = currentKey
		elseif #keys > 0 then
			ui.selectedCharacterKey = keys[1]
		else
			ui.selectedCharacterKey = DASHBOARD_ACCOUNT_KEY
		end
	end

	local rowH = 24
	if not ui.sidebarAccountBtn then
		ui.sidebarAccountBtn = CreateFrame("Button", nil, ui.leftContent, "UIPanelButtonTemplate")
		ui.sidebarAccountBtn:SetSize(236, rowH - 2)
	end
	ui.sidebarAccountBtn:SetPoint("TOPLEFT", 4, -4)
	ui.sidebarAccountBtn:SetText("All characters (account)")
	ui.sidebarAccountBtn:SetScript("OnClick", function()
		ui.selectedCharacterKey = DASHBOARD_ACCOUNT_KEY
		ProfessionExporter:RefreshDashboard(true)
	end)
	ui.sidebarAccountBtn:Show()
	if ui.selectedCharacterKey == DASHBOARD_ACCOUNT_KEY then
		ui.sidebarAccountBtn:LockHighlight()
	else
		ui.sidebarAccountBtn:UnlockHighlight()
	end

	if not ui.sidebarCharHeading then
		ui.sidebarCharHeading = ui.leftContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ui.sidebarCharHeading:SetWidth(232)
		ui.sidebarCharHeading:SetJustifyH("LEFT")
	end
	ui.sidebarCharHeading:SetPoint("TOPLEFT", ui.sidebarAccountBtn, "BOTTOMLEFT", 0, -6)
	ui.sidebarCharHeading:SetText(string.format("Characters (%d)", numChars))

	for i, btn in ipairs(ui.charButtons) do
		btn:Hide()
	end
	for i = 1, #keys do
		local key = keys[i]
		local btn = ui.charButtons[i]
		if not btn then
			btn = CreateFrame("Button", nil, ui.leftContent, "UIPanelButtonTemplate")
			btn:SetSize(236, rowH - 2)
			ui.charButtons[i] = btn
		end
		local cd = db.characters[key]
		btn:SetText(self:GetDashboardSidebarCharacterLabel(key, cd, currentKey))
		btn:SetPoint("TOPLEFT", ui.sidebarCharHeading, "BOTTOMLEFT", 0, -4 - (i - 1) * rowH)
		btn:Show()
		btn:SetScript("OnClick", function()
			ui.selectedCharacterKey = key
			ProfessionExporter:RefreshDashboard(true)
		end)
		if ui.selectedCharacterKey == key then
			btn:LockHighlight()
		else
			btn:UnlockHighlight()
		end
	end
	local leftListH = 4 + rowH + 6 + 14 + 4 + math.max(0, #keys) * rowH + 8
	ui.leftContent:SetHeight(math.max(48, leftListH))

	-- History
	local histLines = {}
	for hi = 1, math.min(5, #(db.history or {})) do
		local h = db.history[hi]
		if h then
			table.insert(histLines, string.format(
				"%s  %s  (%d prof.)",
				self:FormatScanTimestamp(h.finishedAt),
				h.characterKey or "?",
				h.professionCount or 0
			))
		end
	end
	ui.historyText:SetText(#histLines > 0 and table.concat(histLines, "\n") or "—")

	-- Detail pane
	local sel = ui.selectedCharacterKey
	local charData = (sel and sel ~= DASHBOARD_ACCOUNT_KEY) and db.characters[sel] or nil
	local isCurrent = sel == currentKey

	if sel == DASHBOARD_ACCOUNT_KEY then
		ui.btnRefreshInv:SetEnabled(false)
		ui.btnExportChar:SetEnabled(false)
		ui.btnExportProfessions:SetEnabled(false)
		ui.btnExportInventory:SetEnabled(false)
		ui.btnExportMeta:SetEnabled(false)
		ui.btnExportAccount:SetEnabled(true)
		ui.btnExportAccountSummary:SetEnabled(true)
		ui.btnScan:SetEnabled(true)
		if ui.profPanel then
			ui.profPanel:Hide()
		end
		for _, row in ipairs(ui.profExportRows or {}) do
			row:Hide()
		end
		self:DashboardAnchorInventoryScroll(ui)

		ui.detailTitle:SetText("Account — all stored characters")
		ui.detailMeta:SetText(string.format(
			"%d character(s) in database  |  Aggregate rebuilt: %s",
			numChars,
			self:FormatScanTimestamp(agg.updatedAt)
		))
		local roster = { "|cffffffffStored characters|r" }
		if #keys == 0 then
			table.insert(roster, "No scans yet. Log in and run |cffffffff/profexport scan|r.")
		else
			for _, k in ipairs(keys) do
				local cd = db.characters[k]
				local m = cd and cd.meta or {}
				local nm = (m.name and m.realm) and string.format("%s — %s", tostring(m.name), tostring(m.realm)) or k
				local nProf = self:TableCount(cd and cd.professions or {})
				table.insert(roster, string.format(
					"• %s  |  %d prof.  |  scan finished %s",
					nm,
					nProf,
					self:FormatScanTimestamp(cd and cd.scanFinishedAt)
				))
			end
		end
		table.insert(roster, "")
		table.insert(
			roster,
			"|cffffffffTip|r Use |cffffffffExport account|r, |cffffffffAccount summary|r, or the compact export buttons for website/script imports. Pick a character on the left for detail and per-character exports."
		)
		ui.detailBody:SetText(table.concat(roster, "\n"))
		local hAcc = ui.detailBody:GetStringHeight() + 24
		ui.rightContent:SetHeight(math.max(hAcc, ui.rightScroll:GetHeight() or 200))
		ui.rightScroll:SetVerticalScroll(0)
		self:RefreshInventoryTabIfVisible()
		return
	end

	ui.btnRefreshInv:SetEnabled(isCurrent)
	ui.btnExportChar:SetEnabled(isCurrent)
	local canPartialCharExport = isCurrent and charData ~= nil
	if ui.btnExportProfessions then
		ui.btnExportProfessions:SetEnabled(canPartialCharExport)
		ui.btnExportInventory:SetEnabled(canPartialCharExport)
		ui.btnExportMeta:SetEnabled(canPartialCharExport)
	end

	if not charData then
		ui.detailTitle:SetText("No character data")
		ui.detailMeta:SetText("")
		ui.detailBody:SetText("Run |cffffffff/profexport scan|r on a character to store profession data.")
		if ui.profPanel then
			ui.profPanel:Hide()
		end
		self:DashboardAnchorInventoryScroll(ui)
		ui.rightContent:SetHeight(120)
		ui.rightScroll:SetVerticalScroll(0)
		if ui.btnExportProfessions then
			ui.btnExportProfessions:SetEnabled(false)
			ui.btnExportInventory:SetEnabled(false)
			ui.btnExportMeta:SetEnabled(false)
		end
		self:RefreshInventoryTabIfVisible()
		return
	end

	local meta = charData.meta or {}
	ui.detailTitle:SetText(string.format("%s — %s", tostring(meta.name or "?"), tostring(meta.realm or "?")))
	local liveProf = charData.lastLiveProfessionUpdate and self:FormatScanTimestamp(charData.lastLiveProfessionUpdate) or "—"
	local liveInv = charData.lastLiveInventoryUpdate and self:FormatScanTimestamp(charData.lastLiveInventoryUpdate) or "—"
	ui.detailMeta:SetText(string.format(
		"Class: %s  |  Faction: %s  |  Level: %s\nScan: started %s  |  finished %s\nLive profession refresh: %s  |  Live inventory refresh: %s\nAddon v%s  schema %s  |  Professions: %d",
		tostring(meta.class or "?"),
		tostring(meta.faction or "?"),
		tostring(meta.level or "?"),
		self:FormatScanTimestamp(charData.scanStartedAt),
		self:FormatScanTimestamp(charData.scanFinishedAt),
		liveProf,
		liveInv,
		tostring(charData.addonVersion or "?"),
		tostring(charData.schemaVersion or "?"),
		self:TableCount(charData.professions or {})
	))

	local profList = {}
	for _, p in pairs(charData.professions or {}) do
		table.insert(profList, p)
	end
	table.sort(profList, function(a, b)
		return self:SortByNameThenId(
			{ professionName = a.professionName, skillLineID = a.skillLineID },
			{ professionName = b.professionName, skillLineID = b.skillLineID }
		)
	end)

	local showProfPanel = canPartialCharExport and #profList > 0 and ui.profPanel
	if showProfPanel then
		ui.profPanel:Show()
		local rowH = 24
		for i = 1, math.max(#profList, #(ui.profExportRows or {})) do
			local row = ui.profExportRows[i]
			if not row then
				row = CreateFrame("Frame", nil, ui.profExportContent)
				row:SetSize(440, rowH)
				row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.label:SetPoint("LEFT", 4, 0)
				row.label:SetWidth(218)
				row.label:SetJustifyH("LEFT")
				row.exportTalentsBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
				row.exportTalentsBtn:SetSize(56, 20)
				row.exportTalentsBtn:SetPoint("RIGHT", -4, 0)
				row.exportTalentsBtn:SetText("Talents")
				row.exportRecipesBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
				row.exportRecipesBtn:SetSize(56, 20)
				row.exportRecipesBtn:SetPoint("RIGHT", row.exportTalentsBtn, "LEFT", -4, 0)
				row.exportRecipesBtn:SetText("Recipes")
				row.exportBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
				row.exportBtn:SetSize(52, 20)
				row.exportBtn:SetPoint("RIGHT", row.exportRecipesBtn, "LEFT", -4, 0)
				row.exportBtn:SetText("All")
				ui.profExportRows[i] = row
			end
			if i <= #profList then
				local p = profList[i]
				local sid = p.skillLineID
				row:SetPoint("TOPLEFT", ui.profExportContent, "TOPLEFT", 0, -(i - 1) * rowH)
				row.label:SetText(string.format(
					"%s  |  skill %d / %d  |  recipes: %d",
					tostring(p.professionName or "?"),
					tonumber(p.skillLevel) or 0,
					tonumber(p.maxSkillLevel) or 0,
					tonumber(p.recipeCount) or 0
				))
				row.exportBtn:SetScript("OnClick", function()
					ProfessionExporter:Export("profession", tostring(sid))
				end)
				row.exportRecipesBtn:SetScript("OnClick", function()
					ProfessionExporter:Export("profession_recipes", tostring(sid))
				end)
				row.exportTalentsBtn:SetScript("OnClick", function()
					ProfessionExporter:Export("profession_talents", tostring(sid))
				end)
				row.exportBtn:Enable()
				row.exportRecipesBtn:Enable()
				row.exportTalentsBtn:Enable()
				row:Show()
			else
				row:Hide()
			end
		end
		ui.profExportContent:SetHeight(math.max(rowH, #profList * rowH + 4))
		ui.profExportScroll:SetVerticalScroll(0)
	else
		if ui.profPanel then
			ui.profPanel:Hide()
		end
		for _, row in ipairs(ui.profExportRows or {}) do
			row:Hide()
		end
	end
	self:DashboardAnchorInventoryScroll(ui)

	local inv = charData.inventorySnapshot
	local invLines = { "|cffffffffProfession-relevant inventory|r" }
	if not inv then
		table.insert(invLines, "No snapshot yet. Finish a scan or click Refresh inventory (this character only).")
	elseif not isCurrent then
		table.insert(invLines, string.format(
			"Last captured (on that character): %s\nTracked item types: %d  |  Types with stock: %d  |  Sum of counts: %d\n|cffffcc00Stored snapshot — log in on this character and use Refresh inventory to update counts.|r",
			self:FormatScanTimestamp(inv.capturedAt),
			tonumber(inv.itemTypesTracked) or 0,
			tonumber(inv.itemTypesWithStock) or 0,
			tonumber(inv.totalQuantity) or 0
		))
		local sortedAlt = {}
		for itemKey, entry in pairs(inv.items or {}) do
			local id = tonumber(itemKey)
			table.insert(sortedAlt, {
				id = id,
				total = entry.total or 0,
				bags = entry.bags or 0,
				bank = entry.bank or 0,
				warband = entry.warband or 0,
			})
		end
		table.sort(sortedAlt, function(a, b)
			if a.total == b.total then
				return (a.id or 0) < (b.id or 0)
			end
			return a.total > b.total
		end)
		local maxAlt = 80
		for idx, row in ipairs(sortedAlt) do
			if row.total > 0 and idx <= maxAlt then
				local nm = self:GetItemDisplayName(row.id)
				table.insert(invLines, string.format(
					"  %s  x%d  (bags %d, bank %d, warband %d)",
					nm,
					row.total,
					row.bags,
					row.bank,
					row.warband
				))
			end
		end
	else
		table.insert(invLines, string.format(
			"Captured: %s\nTracked item types: %d  |  Types with stock: %d  |  Sum of counts: %d",
			self:FormatScanTimestamp(inv.capturedAt),
			tonumber(inv.itemTypesTracked) or 0,
			tonumber(inv.itemTypesWithStock) or 0,
			tonumber(inv.totalQuantity) or 0
		))

		local sorted = {}
		for itemKey, entry in pairs(inv.items or {}) do
			local id = tonumber(itemKey)
			table.insert(sorted, {
				id = id,
				total = entry.total or 0,
				bags = entry.bags or 0,
				bank = entry.bank or 0,
				warband = entry.warband or 0,
			})
		end
		table.sort(sorted, function(a, b)
			if a.total == b.total then
				return (a.id or 0) < (b.id or 0)
			end
			return a.total > b.total
		end)

		local maxLines = 80
		for idx, row in ipairs(sorted) do
			if row.total > 0 and idx <= maxLines then
				local nm = self:GetItemDisplayName(row.id)
				table.insert(invLines, string.format(
					"  %s  x%d  (bags %d, bank %d, warband %d)",
					nm,
					row.total,
					row.bags,
					row.bank,
					row.warband
				))
			end
		end
		if #sorted > maxLines then
			table.insert(invLines, string.format("  … and more (showing top %d by total count)", maxLines))
		end
	end

	local bodyText = table.concat(invLines, "\n")
	ui.detailBody:SetText(bodyText)
	local h = ui.detailBody:GetStringHeight() + 24
	ui.rightContent:SetHeight(math.max(h, ui.rightScroll:GetHeight() or 200))
	ui.rightScroll:SetVerticalScroll(0)
	self:RefreshInventoryTabIfVisible()
end

local function formatExportStepCount(n)
	if type(FormatLargeNumber) == "function" then
		return FormatLargeNumber(n)
	end
	return tostring(n)
end

function ProfessionExporter:ExportProgressEncodeStageFrac(steps)
	local k = self.EXPORT_PROGRESS_ENCODE_PROGRESS_K or 80000
	local s = math.max(0, steps or 0)
	return s / (s + k)
end

function ProfessionExporter:RefreshExportProgressPhaseLine(f)
	if not f or not f.phaseStr then
		return
	end
	local n = self.EXPORT_PROGRESS_STAGE_COUNT or 2
	if f.barMode == "gather" then
		local msg = f.gatherPhaseLabel or "…"
		f.phaseStr:SetText(string.format("Stage 1 of %d — %s", n, msg))
	elseif f.barMode == "encode" and f.phaseBaseText then
		local steps = f.lastEncodeSteps or 0
		f.phaseStr:SetText(string.format(
			"Stage 2 of %d — %s  (%s steps)",
			n,
			f.phaseBaseText,
			formatExportStepCount(steps)
		))
	end
end

function ProfessionExporter:RefreshExportProgressPctLine(f)
	if not f or not f.pctStr or not f.bar then
		return
	end
	local wG = self.EXPORT_PROGRESS_GATHER_WEIGHT or 0.30
	local wE = math.max(1e-6, 1 - wG)
	local overall = f.bar:GetValue() or 0
	local stagePct
	if f.barMode == "gather" then
		local gFrac = (wG > 0) and math.min(1, overall / wG) or 0
		stagePct = gFrac * 100
	elseif f.barMode == "encode" then
		local enc = (overall - wG) / wE
		enc = math.max(0, math.min(1, enc))
		stagePct = enc * 100
	else
		stagePct = 0
	end
	f.pctStr:SetText(string.format(
		"Overall %d%% · Stage %d%%",
		math.floor(overall * 100 + 0.5),
		math.floor(stagePct + 0.5)
	))
end

--- Floating progress while export gathers data and packs compressed exports (staged monotonic bar).
function ProfessionExporter:ShowExportProgress(scopeLabel)
	self.ui = self.ui or {}
	local ui = self.ui
	local f = ui.exportProgressFrame
	if not f then
		f = CreateFrame("Frame", addonName .. "ExportProgress", UIParent, "BackdropTemplate")
		f:SetSize(340, 124)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
		f:SetFrameStrata("DIALOG")
		f:SetFrameLevel(500)
		f:SetClampedToScreen(true)
		f:SetBackdrop({
			bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
		f:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", 0, -14)
		title:SetText("AuctionHelper")

		local scopeStr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		scopeStr:SetPoint("TOP", title, "BOTTOM", 0, -4)
		scopeStr:SetWidth(310)
		scopeStr:SetJustifyH("CENTER")
		f.scopeStr = scopeStr

		local phaseStr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		phaseStr:SetPoint("TOP", scopeStr, "BOTTOM", 0, -6)
		phaseStr:SetWidth(310)
		phaseStr:SetJustifyH("CENTER")
		f.phaseStr = phaseStr

		local pctStr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		pctStr:SetPoint("TOP", phaseStr, "BOTTOM", 0, -4)
		pctStr:SetWidth(310)
		pctStr:SetJustifyH("CENTER")
		f.pctStr = pctStr

		local bar = CreateFrame("StatusBar", nil, f)
		bar:SetSize(300, 18)
		bar:SetPoint("TOP", pctStr, "BOTTOM", 0, -8)
		bar:SetStatusBarTexture("Interface/TARGETINGFRAME/UI-StatusBar")
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		local r, g, b = 0.2, 0.75, 0.35
		bar:SetStatusBarColor(r, g, b)
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.12, 0.12, 0.14, 1)
		f.bar = bar

		f:SetScript("OnUpdate", function(sf)
			if sf.barMode ~= "gather" or not sf:IsShown() then
				return
			end
			local wG = ProfessionExporter.EXPORT_PROGRESS_GATHER_WEIGHT or 0.30
			local cap = ProfessionExporter.EXPORT_PROGRESS_GATHER_CREEP_CAP or 0.95
			local tmax = ProfessionExporter.EXPORT_PROGRESS_GATHER_CREEP_MAX_SEC or 5
			local t0 = sf.gatherStartTime or GetTime()
			local elapsed = GetTime() - t0
			local sliceFrac = math.min(cap, elapsed / math.max(0.001, tmax))
			local overall = wG * sliceFrac
			sf.lastOverall = math.max(sf.lastOverall or 0, overall)
			sf.bar:SetValue(sf.lastOverall)
			ProfessionExporter:RefreshExportProgressPctLine(sf)
		end)

		ui.exportProgressFrame = f
	end

	f.scopeLabel = scopeLabel or "export"
	f.scopeStr:SetText(string.format("Scope: |cffffffff%s|r", f.scopeLabel))
	f.indeterminateBar = false
	f.barMode = "gather"
	f.gatherStartTime = GetTime()
	f.lastOverall = 0
	f.lastEncodeSteps = 0
	f.bar:SetMinMaxValues(0, 1)
	f.bar:SetValue(0)
	f:Show()
	self:SetExportProgressPhase("Collecting export data…", false)
end

--- useStepSuffix: when true, text is a prefix; UpdateExportProgressSteps appends " (N steps)".
function ProfessionExporter:SetExportProgressPhase(text, useStepSuffix)
	local f = self.ui and self.ui.exportProgressFrame
	if not f or not f.phaseStr then
		return
	end
	if useStepSuffix then
		local wG = self.EXPORT_PROGRESS_GATHER_WEIGHT or 0.30
		f.barMode = "encode"
		f.lastOverall = math.max(f.lastOverall or 0, wG)
		f.bar:SetValue(f.lastOverall)
		f.phaseBaseText = text or "Packing export package…"
		self:UpdateExportProgressSteps(0)
	else
		f.phaseBaseText = nil
		f.gatherPhaseLabel = text or ""
		f.barMode = "gather"
		self:RefreshExportProgressPhaseLine(f)
		self:RefreshExportProgressPctLine(f)
	end
end

function ProfessionExporter:UpdateExportProgressSteps(steps)
	local f = self.ui and self.ui.exportProgressFrame
	if not f or not f:IsShown() or not f.phaseStr or not f.phaseBaseText then
		return
	end
	f.lastEncodeSteps = steps or 0
	local wG = self.EXPORT_PROGRESS_GATHER_WEIGHT or 0.30
	local wE = 1 - wG
	local encFrac = math.min(0.999, self:ExportProgressEncodeStageFrac(f.lastEncodeSteps))
	local overall = wG + wE * encFrac
	f.lastOverall = math.max(f.lastOverall or 0, overall)
	f.bar:SetValue(f.lastOverall)
	self:RefreshExportProgressPhaseLine(f)
	self:RefreshExportProgressPctLine(f)
end

--- markComplete: set bar to 100%% before hiding (successful encode).
function ProfessionExporter:HideExportProgress(markComplete)
	local f = self.ui and self.ui.exportProgressFrame
	if f then
		f.indeterminateBar = false
		if markComplete and f.bar and f:IsShown() then
			f.bar:SetValue(1)
			if f.pctStr then
				f.pctStr:SetText("Overall 100% · Stage 100%")
			end
		end
		f.barMode = nil
		f.gatherStartTime = nil
		f.lastOverall = nil
		f.lastEncodeSteps = nil
		f.phaseBaseText = nil
		f.gatherPhaseLabel = nil
		if f.bar then
			f.bar:SetValue(0)
		end
		f:Hide()
	end
end
