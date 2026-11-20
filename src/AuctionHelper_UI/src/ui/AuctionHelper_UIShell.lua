local addonName, ProfessionExporter = ...

local ADDON_FOREGROUND_STRATA = "HIGH"
local ADDON_BACKGROUND_STRATA = "MEDIUM"
local ADDON_FOREGROUND_LEVEL = 240
local ADDON_BACKGROUND_LEVEL = 100

local TRACKED_BLIZZARD_FRAMES = {
	"ProfessionsFrame",
	"AuctionHouseFrame",
	"CharacterFrame",
	"PlayerSpellsFrame",
	"CollectionsJournal",
	"EncounterJournal",
	"QuestMapFrame",
	"FriendsFrame",
	"GuildFrame",
	"AchievementFrame",
	"PVEFrame",
	"MerchantFrame",
	"MailFrame",
	"TradeFrame",
	"BankFrame",
	"GossipFrame",
	"ClassTrainerFrame",
	"ScrappingMachineFrame",
}

local TAB_ORDER = {
	{ id = "overview", label = "Overview", module = function() return ProfessionExporter.OverviewTab end },
	{ id = "inventory", label = "Inventory", module = function() return ProfessionExporter.InventoryTab end },
	{ id = "market", label = "Market", module = function() return ProfessionExporter.MarketTab end },
	{ id = "crafts", label = "Crafts", module = function() return ProfessionExporter.CraftsTab end },
	{ id = "export", label = "Export", module = function() return ProfessionExporter.ExportTab end },
	{ id = "docs", label = "Docs", module = function() return ProfessionExporter.DocsTab end },
	{ id = "settings", label = "Settings", module = function() return ProfessionExporter.SettingsTab end },
}

local ADDON_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local function addRule(frame, edge, color)
	local rule = frame:CreateTexture(nil, "BORDER")
	rule:SetPoint(edge .. "LEFT")
	rule:SetPoint(edge .. "RIGHT")
	rule:SetHeight(1)
	rule:SetColorTexture(color.r, color.g, color.b, color.a or 1)
	return rule
end

local function characterLabel()
	local name = UnitName and UnitName("player") or nil
	local realm = GetRealmName and GetRealmName() or nil
	if name and realm and realm ~= "" then
		return name .. " · " .. realm
	end
	return name or ""
end

-- A tab: text only, muted; selected tab is gold with a 2px gold underline.
local function createTabButton(parent, label)
	local theme = ProfessionExporter:GetTheme()
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(theme.size.tabs)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER", 0, 1)
	text:SetText(label)
	button:SetFontString(text)
	button:SetWidth(math.ceil(text:GetStringWidth()) + 20)
	button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
	button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.04)
	button.underline = button:CreateTexture(nil, "OVERLAY")
	button.underline:SetPoint("BOTTOMLEFT")
	button.underline:SetPoint("BOTTOMRIGHT")
	button.underline:SetHeight(2)
	button.underline:SetColorTexture(theme.gold.r, theme.gold.g, theme.gold.b, 1)
	button:SetScript("OnEnter", function(self)
		if not self.selected then
			self:GetFontString():SetTextColor(theme.textPrimary.r, theme.textPrimary.g, theme.textPrimary.b)
		end
	end)
	button:SetScript("OnLeave", function(self)
		ProfessionExporter:StyleDashboardTab(self, self.selected)
	end)
	return button
end

function ProfessionExporter:StyleDashboardTab(button, selected)
	local theme = self:GetTheme()
	local color = selected and theme.gold or theme.textMuted
	button.selected = selected and true or nil
	button:GetFontString():SetTextColor(color.r, color.g, color.b)
	button.underline:SetShown(selected and true or false)
end

local function showPanel(frame, shown)
	if frame then
		frame:SetShown(shown)
	end
end

local function clamp(value, minValue, maxValue)
	value = tonumber(value) or minValue
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function registerEscClosableFrame(frame)
	if not frame or not frame.GetName then
		return
	end
	local frameName = frame:GetName()
	if not frameName or frameName == "" then
		return
	end
	for i = 1, #UISpecialFrames do
		if UISpecialFrames[i] == frameName then
			return
		end
	end
	UISpecialFrames[#UISpecialFrames + 1] = frameName
end

function ProfessionExporter:GetActiveMainTab()
	local ui = self.ui or {}
	return ui.activeMainTab or self:GetSetting("general.lastActiveTab", "overview")
end

function ProfessionExporter:EnsureDynamicLayeringState()
	self.ui = self.ui or {}
	local state = self.ui.dynamicLayering
	if state then
		return state
	end
	state = {
		lastClickedOwner = "addon",
		hookedFrames = {},
		hasRetry = false,
		activeFrameOwner = nil,
		currentStrata = nil,
		currentLevel = nil,
	}
	self.ui.dynamicLayering = state
	return state
end

function ProfessionExporter:IsTrackedExternalOwnerVisible(owner)
	if type(owner) ~= "string" or owner == "" or owner == "addon" then
		return false
	end
	local frame = _G[owner]
	return frame and frame.IsShown and frame:IsShown() or false
end

function ProfessionExporter:RecordExternalFrameInteraction(owner, reason)
	local state = self:EnsureDynamicLayeringState()
	if not owner or owner == "" then
		return
	end
	state.lastClickedOwner = owner
	state.activeFrameOwner = owner ~= "addon" and owner or nil
	self:UpdateDynamicPanelLayering(reason or "interaction")
end

function ProfessionExporter:UpdateDynamicPanelLayering(_reason)
	local ui = self.ui
	local frame = ui and ui.mainFrame
	if not frame then
		return
	end

	local state = self:EnsureDynamicLayeringState()
	local showForeground = true
	if state.lastClickedOwner ~= "addon" and self:IsTrackedExternalOwnerVisible(state.lastClickedOwner) then
		showForeground = false
	end

	local desiredStrata = showForeground and ADDON_FOREGROUND_STRATA or ADDON_BACKGROUND_STRATA
	local desiredLevel = showForeground and ADDON_FOREGROUND_LEVEL or ADDON_BACKGROUND_LEVEL
	if state.currentStrata ~= desiredStrata then
		frame:SetFrameStrata(desiredStrata)
		state.currentStrata = desiredStrata
	end
	if state.currentLevel ~= desiredLevel then
		frame:SetFrameLevel(desiredLevel)
		state.currentLevel = desiredLevel
	end
end

function ProfessionExporter:HookExternalFrameForDynamicLayering(owner)
	if type(owner) ~= "string" or owner == "" then
		return false
	end
	local frame = _G[owner]
	if not frame or not frame.HookScript then
		return false
	end

	local state = self:EnsureDynamicLayeringState()
	if state.hookedFrames[owner] then
		return true
	end

	frame:HookScript("OnMouseDown", function()
		ProfessionExporter:RecordExternalFrameInteraction(owner, "external_mouse_down")
	end)
	frame:HookScript("OnShow", function()
		ProfessionExporter:RecordExternalFrameInteraction(owner, "external_show")
	end)
	frame:HookScript("OnHide", function()
		local layerState = ProfessionExporter:EnsureDynamicLayeringState()
		if layerState.lastClickedOwner == owner then
			layerState.lastClickedOwner = "addon"
		end
		if layerState.activeFrameOwner == owner then
			layerState.activeFrameOwner = nil
		end
		ProfessionExporter:UpdateDynamicPanelLayering("external_hide")
	end)
	state.hookedFrames[owner] = true
	return true
end

function ProfessionExporter:InitDynamicLayeringHooks()
	local state = self:EnsureDynamicLayeringState()
	local missing = false
	for _, owner in ipairs(TRACKED_BLIZZARD_FRAMES) do
		if not self:HookExternalFrameForDynamicLayering(owner) then
			missing = true
		end
	end
	if missing and not state.hasRetry then
		state.hasRetry = true
		C_Timer.After(3, function()
			ProfessionExporter:InitDynamicLayeringHooks()
		end)
	end
	self:UpdateDynamicPanelLayering("init_dynamic_hooks")
end

function ProfessionExporter:CreateDashboardFrame()
	local ui = self.ui
	if ui.mainFrame then
		return ui.mainFrame
	end

	local frame = CreateFrame("Frame", addonName .. "Dashboard", UIParent, "BackdropTemplate")
	registerEscClosableFrame(frame)
	local initialWidth = clamp(self:GetSetting("appearance.windowWidth", 940), 860, 1400)
	local initialHeight = clamp(self:GetSetting("appearance.windowHeight", 640), 580, 980)
	frame:SetSize(initialWidth, initialHeight)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata(ADDON_BACKGROUND_STRATA)
	frame:SetFrameLevel(ADDON_BACKGROUND_LEVEL)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(860, 580, 1400, 980)
	elseif frame.SetMinResize and frame.SetMaxResize then
		frame:SetMinResize(860, 580)
		frame:SetMaxResize(1400, 980)
	end
	frame:SetUserPlaced(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:EnableMouse(true)
	frame:SetScript("OnDragStart", function(self)
		ProfessionExporter:RecordExternalFrameInteraction("addon", "dashboard_drag_start")
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		ProfessionExporter:SetSetting("appearance.windowWidth", self:GetWidth())
		ProfessionExporter:SetSetting("appearance.windowHeight", self:GetHeight())
	end)
	self:StyleWindow(frame)

	ui.mainFrame = frame

	local theme = self:GetTheme()
	local size = theme.size
	local inset = theme.spacing.md

	-- Header: drag handle, icon, gold title, character name, close button.
	frame.titleBar = CreateFrame("Frame", nil, frame)
	frame.titleBar:SetPoint("TOPLEFT", 1, -1)
	frame.titleBar:SetPoint("TOPRIGHT", -1, -1)
	frame.titleBar:SetHeight(size.header)
	frame.titleBar:RegisterForDrag("LeftButton")
	frame.titleBar:EnableMouse(true)
	frame.titleBar:SetScript("OnDragStart", function()
		ProfessionExporter:RecordExternalFrameInteraction("addon", "title_drag_start")
		frame:StartMoving()
	end)
	frame.titleBar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
	end)
	addRule(frame.titleBar, "BOTTOM", theme.borderSubtle)

	frame.icon = frame.titleBar:CreateTexture(nil, "ARTWORK")
	frame.icon:SetTexture(ADDON_ICON)
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.icon:SetSize(16, 16)
	frame.icon:SetPoint("LEFT", 11, 0)

	frame.closeButton = CreateFrame("Button", nil, frame.titleBar, "UIPanelCloseButton")
	frame.closeButton:ClearAllPoints()
	frame.closeButton:SetPoint("RIGHT", -6, 0)
	self:SkinCloseButton(frame.closeButton)
	frame.closeButton:SetScript("OnClick", function()
		frame:Hide()
	end)

	frame.subtitle = frame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("RIGHT", frame.closeButton, "LEFT", -10, 0)
	frame.subtitle:SetJustifyH("RIGHT")
	frame.subtitle:SetWordWrap(false)
	frame.subtitle:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	frame.subtitle:SetText(characterLabel())

	frame.title = frame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
	frame.title:SetPoint("RIGHT", frame.subtitle, "LEFT", -12, 0)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)
	frame.title:SetText("AuctionHelper")

	frame:HookScript("OnMouseDown", function()
		ProfessionExporter:RecordExternalFrameInteraction("addon", "dashboard_mouse_down")
	end)
	frame.titleBar:HookScript("OnMouseDown", function()
		ProfessionExporter:RecordExternalFrameInteraction("addon", "title_mouse_down")
	end)
	frame:HookScript("OnShow", function()
		ProfessionExporter:UpdateDynamicPanelLayering("dashboard_show")
	end)

	-- Tab strip.
	frame.tabBar = CreateFrame("Frame", nil, frame)
	frame.tabBar:SetPoint("TOPLEFT", frame.titleBar, "BOTTOMLEFT", 0, 0)
	frame.tabBar:SetPoint("TOPRIGHT", frame.titleBar, "BOTTOMRIGHT", 0, 0)
	frame.tabBar:SetHeight(size.tabs)
	addRule(frame.tabBar, "BOTTOM", theme.borderSubtle)

	-- Footer: status on the left, stored data on the right, resize grip in the corner.
	frame.statusBar = CreateFrame("Frame", nil, frame)
	frame.statusBar:SetPoint("BOTTOMLEFT", 1, 1)
	frame.statusBar:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.statusBar:SetHeight(size.footer)
	addRule(frame.statusBar, "TOP", theme.borderSubtle)

	frame.resizeHandle = CreateFrame("Button", nil, frame.statusBar)
	frame.resizeHandle:SetSize(14, 14)
	frame.resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.resizeHandle:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
	frame.resizeHandle:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
	frame.resizeHandle:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
	frame.resizeHandle:RegisterForDrag("LeftButton")
	frame.resizeHandle:SetScript("OnDragStart", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	frame.resizeHandle:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		ProfessionExporter:SetSetting("appearance.windowWidth", frame:GetWidth())
		ProfessionExporter:SetSetting("appearance.windowHeight", frame:GetHeight())
	end)
	frame.resizeHandle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText("Drag to resize", 1, 1, 1)
		GameTooltip:Show()
	end)
	frame.resizeHandle:SetScript("OnLeave", GameTooltip_Hide)

	frame.statusRight = frame.statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.statusRight:SetPoint("RIGHT", frame.resizeHandle, "LEFT", -8, 0)
	frame.statusRight:SetJustifyH("RIGHT")
	frame.statusRight:SetWordWrap(false)
	frame.statusText = frame.statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.statusText:SetPoint("LEFT", inset, 0)
	frame.statusText:SetPoint("RIGHT", frame.statusRight, "LEFT", -12, 0)
	frame.statusText:SetJustifyH("LEFT")
	frame.statusText:SetWordWrap(false)
	for _, text in ipairs({ frame.statusText, frame.statusRight }) do
		text:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	end

	-- Content: everything between the tab strip and the footer, inset on every side.
	frame.contentHost = CreateFrame("Frame", nil, frame)
	frame.contentHost:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", inset, -inset)
	frame.contentHost:SetPoint("BOTTOMRIGHT", frame.statusBar, "TOPRIGHT", -inset, inset)
	if frame.contentHost.SetClipsChildren then
		frame.contentHost:SetClipsChildren(true)
	end

	ui.tabButtons = {}
	ui.tabPanels = {}
	ui.tabModules = {}
	ui.tabInited = {}
	local previous
	for _, tab in ipairs(TAB_ORDER) do
		local button = createTabButton(frame.tabBar, tab.label)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", theme.spacing.xs, 0)
		else
			button:SetPoint("LEFT", frame.tabBar, "LEFT", inset, 0)
		end
		previous = button
		button:SetScript("OnClick", function()
			ProfessionExporter:ShowDashboardTab(tab.id)
		end)
		ui.tabButtons[tab.id] = button

		local panel = CreateFrame("Frame", nil, frame.contentHost)
		panel:SetAllPoints()
		panel:Hide()
		ui.tabPanels[tab.id] = panel

		local module = tab.module()
		ui.tabModules[tab.id] = module
	end

	self:ApplyWindowScale()
	self:ApplyThemeToUI()
	self:UpdateDynamicPanelLayering("dashboard_created")
	frame:Hide()
	return frame
end

function ProfessionExporter:RefreshShellStatus()
	local ui = self.ui
	if not (ui and ui.mainFrame and ui.mainFrame.statusText) then
		return
	end
	local state = self:GetState()
	local currentKey = self:GetCharacterKey()
	local charData = self.db and self.db.characters and self.db.characters[currentKey]
	-- Left: what is running now, else how fresh the AH prices are.
	local leftText = ""
	if state.scanInProgress then
		leftText = "Scanning " .. tostring(state.currentProfession and state.currentProfession.professionName or "professions") .. "…"
	elseif self.GetLastFullAuctionScanAt then
		local lastScanAt = self:GetLastFullAuctionScanAt()
		leftText = lastScanAt and ("Prices from full AH scan " .. self:FormatScanTimestamp(lastScanAt))
			or "No full AH scan yet · open the auction house to get prices"
	end
	local stored = self:TableCount(self.db and self.db.characters or {})
	ui.mainFrame.statusText:SetText(leftText)
	local text = string.format("%d %s stored", stored, stored == 1 and "character" or "characters")
	-- Profession scan time only matters when this character has a profession to scan.
	if #self:GetPlayerProfessions() > 0 then
		local scannedAt = charData and charData.scanFinishedAt
		text = text .. ((scannedAt and scannedAt > 0)
			and (" · Professions scanned " .. self:FormatScanTimestamp(scannedAt))
			or " · Professions not scanned yet")
	end
	ui.mainFrame.statusRight:SetText(text)
end

function ProfessionExporter:ApplyThemeToUI()
	local ui = self.ui
	local theme = self:GetTheme()
	if ui.mainFrame then
		for tabId, button in pairs(ui.tabButtons or {}) do
			self:StyleDashboardTab(button, tabId == self:GetActiveMainTab())
		end
	end
	for tabId, module in pairs(ui.tabModules or {}) do
		if ui.tabInited and ui.tabInited[tabId] and module and module.ApplyTheme then
			module:ApplyTheme(theme)
		end
	end
	self:SkinTree(ui.mainFrame)
end

function ProfessionExporter:EnsureDashboardTabCreated(tabId)
	local ui = self.ui
	if not ui or not tabId then
		return
	end
	ui.tabInited = ui.tabInited or {}
	if ui.tabInited[tabId] then
		return
	end
	local module = ui.tabModules and ui.tabModules[tabId]
	if not module then
		for _, tab in ipairs(TAB_ORDER) do
			if tab.id == tabId then
				module = tab.module and tab.module() or nil
				ui.tabModules = ui.tabModules or {}
				ui.tabModules[tabId] = module
				break
			end
		end
	end
	local panel = ui.tabPanels and ui.tabPanels[tabId]
	if module and module.Create and panel then
		local ok, err = pcall(module.Create, module, panel, ui)
		if not ok then
			if self.PrintMessage then
				self:PrintMessage("Tab '" .. tostring(tabId) .. "' failed to create: " .. tostring(err))
			end
			return
		end
	end
	ui.tabInited[tabId] = true
end

function ProfessionExporter:OpenCraftsTabWithQueueFocus()
	self:InitDB()
	if not self.ui.mainFrame then
		self:CreateDashboardFrame()
	end
	self.ui.craftsFocusQueue = true
	self.ui.mainFrame:Show()
	self:RecordExternalFrameInteraction("addon", "open_crafts_tab")
	self:ApplyWindowScale()
	self:ShowDashboardTab("crafts")
end

function ProfessionExporter:ShowDashboardTab(tabId)
	local ui = self.ui
	if not ui.mainFrame then
		self:CreateDashboardFrame()
	end
	tabId = tabId or "overview"
	ui.activeMainTab = tabId
	self:SetSetting("general.lastActiveTab", tabId)

	-- Swap visibility before create/refresh so a tab Create error cannot leave the previous panel up.
	for id, panel in pairs(ui.tabPanels or {}) do
		showPanel(panel, id == tabId)
	end
	for id, button in pairs(ui.tabButtons or {}) do
		self:StyleDashboardTab(button, id == tabId)
	end

	self:EnsureDashboardTabCreated(tabId)

	local module = ui.tabModules and ui.tabModules[tabId]
	if module and module.Refresh then
		local ok, err = pcall(module.Refresh, module, ui, self.db)
		if not ok and self.PrintMessage then
			self:PrintMessage("Tab '" .. tostring(tabId) .. "' failed to refresh: " .. tostring(err))
		end
	end
	if tabId == "crafts" and ui.craftsFocusQueue and self.FocusCraftsQueuePanel then
		ui.craftsFocusQueue = false
		self:FocusCraftsQueuePanel()
	end
	self:RefreshShellStatus()
	self:ApplyThemeToUI()
end

function ProfessionExporter:RefreshDashboard(skipRebuild)
	self:InitDB()
	if not skipRebuild and self:AggregateNeedsRebuild() then
		self:BuildAggregate()
	end
	self:RefreshShellStatus()
	local active = self:GetActiveMainTab()
	self:EnsureDashboardTabCreated(active)
	local module = self.ui and self.ui.tabModules and self.ui.tabModules[active]
	if module and module.Refresh then
		module:Refresh(self.ui, self.db)
	end
	if active == "inventory" then
		self:RefreshInventoryTab()
	end
	if active == "crafts" then
		self:RefreshCraftsTab()
	end
	self:SkinTree(self.ui and self.ui.mainFrame)
end

function ProfessionExporter:ToggleDashboard()
	self:InitDB()
	if not self.ui.mainFrame then
		self:CreateDashboardFrame()
	end
	local frame = self.ui.mainFrame
	if frame:IsShown() then
		frame:Hide()
		return
	end
	if not self.ui.selectedCharacterKey then
		self.ui.selectedCharacterKey = self:GetCharacterKey()
	end
	frame:Show()
	self:RecordExternalFrameInteraction("addon", "toggle_dashboard_show")
	self:ApplyWindowScale()
	self:ShowDashboardTab(self:GetActiveMainTab())
end

function ProfessionExporter:OpenDocumentationTab()
	self:InitDB()
	if not self.ui.mainFrame then
		self:CreateDashboardFrame()
	end
	self.ui.mainFrame:Show()
	self:RecordExternalFrameInteraction("addon", "open_docs_tab")
	self:ShowDashboardTab("docs")
end

function ProfessionExporter:OpenSettingsTab()
	self:InitDB()
	if not self.ui.mainFrame then
		self:CreateDashboardFrame()
	end
	self.ui.mainFrame:Show()
	self:RecordExternalFrameInteraction("addon", "open_settings_tab")
	self:ShowDashboardTab("settings")
end

function ProfessionExporter:EnsureMinimapButton()
	if not Minimap then
		return
	end
	self:InitDB()
	local ui = self.ui
	local showButton = self:GetSetting("general.showMinimapButton", true)
	if ui.minimapButton then
		ui.minimapButton:SetShown(showButton)
		if showButton then
			self:UpdateMinimapButtonPosition(ui.minimapButton)
		end
		return
	end

	local btn = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
	-- Standard minimap-button layout (same offsets as LibDBIcon): the tracking-border
	-- ring sits in the top-left of its texture, so everything anchors TOPLEFT, not CENTER.
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight", "ADD")
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")

	local background = btn:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface/Minimap/UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(ADDON_ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	btn:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			ProfessionExporter:OpenSettingsTab()
		else
			ProfessionExporter:ToggleDashboard()
		end
	end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			ProfessionExporter:InitDB()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			px, py = px / scale, py / scale
			local angle = math.deg(math.atan2(py - my, px - mx))
			ProfessionExporter:SetSetting("integrations.minimapButtonAngle", angle)
			ProfessionExporter:UpdateMinimapButtonPosition(self)
		end)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	btn:SetScript("OnEnter", function(self)
		local theme = ProfessionExporter:GetTheme()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("AuctionHelper", theme.gold.r, theme.gold.g, theme.gold.b)
		for _, pair in ipairs({ { "Click", "Open the dashboard" }, { "Right-click", "Open settings" }, { "Drag", "Move this button" } }) do
			GameTooltip:AddDoubleLine(pair[1], pair[2], theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)

	ui.minimapButton = btn
	btn:SetShown(showButton)
	self:UpdateMinimapButtonPosition(btn)
end

function ProfessionExporter:UpdateMinimapButtonPosition(button)
	if not button or not Minimap then
		return
	end
	local deg = tonumber(self:GetSetting("integrations.minimapButtonAngle", 225)) or 225
	local rad = math.rad(deg)
	local radius = (math.min(Minimap:GetWidth(), Minimap:GetHeight()) * 0.5) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

function ProfessionExporter:OpenBlizzardSettings()
	if not self.settingsCategoryId then
		self:RegisterBlizzardSettings()
	end
	if not self.settingsCategoryId then
		return
	end
	if Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.settingsCategoryId)
		Settings.OpenToCategory(self.settingsCategoryId)
	end
end

function ProfessionExporter:RegisterBlizzardSettings()
	if self.settingsCategoryId or not Settings or not Settings.RegisterCanvasLayoutCategory then
		return
	end

	local frame = CreateFrame("Frame", nil, nil, "VerticalLayoutFrame")
	frame.name = "AuctionHelper"
	frame.spacing = 8
	frame:SetSize(820, 520)

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -18)
	title:SetText("AuctionHelper")

	local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetWidth(760)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Open the AuctionHelper window. Every option is on its Settings tab; the most used ones are also here.")

	local openButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	openButton:SetSize(180, 24)
	openButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
	openButton:SetText("Open AuctionHelper")
	openButton:SetScript("OnClick", function()
		ProfessionExporter:OpenSettingsTab()
	end)

	local function createCheckbox(anchor, offsetY, label, getter, setter)
		local check = CreateFrame("CheckButton", nil, frame, "SettingsCheckBoxTemplate")
		check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
		local labelRegion = check.Text or check.text
		if not labelRegion then
			labelRegion = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			labelRegion:SetPoint("LEFT", check, "RIGHT", 4, 0)
			check.Text = labelRegion
		end
		labelRegion:SetText(label)
		check:SetChecked(getter())
		check:SetScript("OnClick", function(self)
			setter(self:GetChecked() == true)
		end)
		return check
	end

	local minimapCheck = createCheckbox(openButton, -14, "Show minimap button", function()
		return ProfessionExporter:GetSetting("general.showMinimapButton", true)
	end, function(value)
		ProfessionExporter:SetSetting("general.showMinimapButton", value)
		ProfessionExporter:EnsureMinimapButton()
	end)

	local specCheck = createCheckbox(minimapCheck, -8, "Capture specialization tree", function()
		return ProfessionExporter:GetSetting("capture.captureSpecializationTree", true)
	end, function(value)
		ProfessionExporter:SetSetting("capture.captureSpecializationTree", value)
	end)

	local outputCheck = createCheckbox(specCheck, -8, "Include detailed recipe output data", function()
		return ProfessionExporter:GetSetting("capture.includeRecipeOutputItemData", false)
	end, function(value)
		ProfessionExporter:SetSetting("capture.includeRecipeOutputItemData", value)
	end)

	local scaleButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scaleButton:SetSize(180, 24)
	scaleButton:SetPoint("TOPLEFT", outputCheck, "BOTTOMLEFT", 4, -12)
	local function refreshScaleButton()
		scaleButton:SetText(string.format(
			"Window scale: %d%%",
			math.floor((ProfessionExporter:GetSetting("appearance.windowScale", 1) or 1) * 100 + 0.5)
		))
	end
	scaleButton:SetScript("OnClick", function()
		local options = ProfessionExporter:GetWindowScaleOptions()
		local current = tonumber(ProfessionExporter:GetSetting("appearance.windowScale", 1)) or 1
		local nextIndex = 1
		for index, option in ipairs(options) do
			if math.abs(option.value - current) < 0.001 then
				nextIndex = (index % #options) + 1
				break
			end
		end
		ProfessionExporter:SetSetting("appearance.windowScale", options[nextIndex].value)
		ProfessionExporter:ApplyWindowScale()
		refreshScaleButton()
	end)
	refreshScaleButton()

	local category = Settings.RegisterCanvasLayoutCategory(frame, "AuctionHelper")
	self.settingsCategoryId = category:GetID()
	Settings.RegisterAddOnCategory(category)
end

-- Every docked panel and popup is re-skinned after it refreshes, so controls created during a refresh
-- get the same look. Hooks run after the original method returns.
local SKIN_AFTER_REFRESH = {
	RefreshAuctionHousePanel = function(pe) return pe.ui.auctionPanel end,
	RefreshProfessionCraftEconomyPanel = function(pe) return pe._professionCraftPanel end,
	RefreshMailPanel = function(pe) return pe.ui.mailPanel end,
	RefreshInventoryTab = function(pe) return pe.ui.mainFrame end,
	RefreshCraftsTab = function(pe) return pe.ui.mainFrame end,
	EnsureCraftingOrdersFilterBar = function(_, frame) return frame end,
}
for method, getFrame in pairs(SKIN_AFTER_REFRESH) do
	if type(ProfessionExporter[method]) == "function" then
		local original = ProfessionExporter[method]
		ProfessionExporter[method] = function(self, ...)
			local result = original(self, ...)
			self:SkinTree(getFrame(self, result))
			return result
		end
	end
end
