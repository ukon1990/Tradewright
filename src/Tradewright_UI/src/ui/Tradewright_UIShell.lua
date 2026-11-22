local addonName, Tradewright = ...

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

local TAB_ORDER = Tradewright.DASHBOARD_TABS

local ADDON_ICON = "Interface\\AddOns\\Tradewright\\media\\logo"
Tradewright.ADDON_ICON = ADDON_ICON -- also the minimap button icon

local function addRule(frame, edge, color)
	local rule = frame:CreateTexture(nil, "BORDER")
	rule:SetPoint(edge .. "LEFT")
	rule:SetPoint(edge .. "RIGHT")
	rule:SetHeight(1)
	rule:SetColorTexture(color.r, color.g, color.b, color.a or 1)
	return rule
end

-- A tab: text only, muted; selected tab is gold with a 2px gold underline.
local function createTabButton(parent, label)
	local theme = Tradewright:GetTheme()
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
		Tradewright:StyleDashboardTab(self, self.selected)
	end)
	return button
end

function Tradewright:StyleDashboardTab(button, selected)
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

function Tradewright:GetActiveMainTab()
	local ui = self.ui or {}
	return ui.activeMainTab or self:GetSetting("general.lastActiveTab", "overview")
end

function Tradewright:EnsureDynamicLayeringState()
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

function Tradewright:IsTrackedExternalOwnerVisible(owner)
	if type(owner) ~= "string" or owner == "" or owner == "addon" then
		return false
	end
	local frame = _G[owner]
	return frame and frame.IsShown and frame:IsShown() or false
end

function Tradewright:RecordExternalFrameInteraction(owner, reason)
	local state = self:EnsureDynamicLayeringState()
	if not owner or owner == "" then
		return
	end
	state.lastClickedOwner = owner
	state.activeFrameOwner = owner ~= "addon" and owner or nil
	self:UpdateDynamicPanelLayering(reason or "interaction")
end

-- The dashboard goes behind a tracked Blizzard window the player clicked last, while that window is open.
function Tradewright:ShouldShowAddonForeground(state)
	return state.lastClickedOwner == "addon" or not self:IsTrackedExternalOwnerVisible(state.lastClickedOwner)
end

function Tradewright:UpdateDynamicPanelLayering(_reason)
	local ui = self.ui
	local frame = ui and ui.mainFrame
	if not frame then
		return
	end
	local state = self:EnsureDynamicLayeringState()
	local showForeground = self:ShouldShowAddonForeground(state)
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

function Tradewright:HookExternalFrameForDynamicLayering(owner)
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
		Tradewright:RecordExternalFrameInteraction(owner, "external_mouse_down")
	end)
	frame:HookScript("OnShow", function()
		Tradewright:RecordExternalFrameInteraction(owner, "external_show")
	end)
	frame:HookScript("OnHide", function()
		local layerState = Tradewright:EnsureDynamicLayeringState()
		if layerState.lastClickedOwner == owner then
			layerState.lastClickedOwner = "addon"
		end
		if layerState.activeFrameOwner == owner then
			layerState.activeFrameOwner = nil
		end
		Tradewright:UpdateDynamicPanelLayering("external_hide")
	end)
	state.hookedFrames[owner] = true
	return true
end

function Tradewright:InitDynamicLayeringHooks()
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
			Tradewright:InitDynamicLayeringHooks()
		end)
	end
	self:UpdateDynamicPanelLayering("init_dynamic_hooks")
end

local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 860, 580, 1400, 980

local function createWindow()
	local pe = Tradewright
	local frame = CreateFrame("Frame", addonName .. "Dashboard", UIParent, "BackdropTemplate")
	registerEscClosableFrame(frame)
	frame:SetSize(clamp(pe:GetSetting("appearance.windowWidth", 940), MIN_WIDTH, MAX_WIDTH),
		clamp(pe:GetSetting("appearance.windowHeight", 640), MIN_HEIGHT, MAX_HEIGHT))
	frame:SetPoint("CENTER")
	frame:SetFrameStrata(ADDON_BACKGROUND_STRATA)
	frame:SetFrameLevel(ADDON_BACKGROUND_LEVEL)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	elseif frame.SetMinResize and frame.SetMaxResize then
		frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
		frame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
	end
	frame:SetUserPlaced(true)
	frame:SetClampedToScreen(true)
	pe:MakeWindowDraggable(frame, frame)
	pe:StyleWindow(frame)
	return frame
end

-- Header: drag handle, icon, gold title, character name, close button.
function Tradewright:CreateDashboardTitleBar(frame)
	local theme = self:GetTheme()
	frame.titleBar = CreateFrame("Frame", nil, frame)
	frame.titleBar:SetPoint("TOPLEFT", 1, -1)
	frame.titleBar:SetPoint("TOPRIGHT", -1, -1)
	frame.titleBar:SetHeight(theme.size.header)
	self:MakeWindowDraggable(frame, frame.titleBar)
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
	frame.title = frame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
	frame.title:SetPoint("RIGHT", frame.subtitle, "LEFT", -12, 0)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)
	frame.title:SetText(Tradewright.DISPLAY_NAME)
end

-- Clicks on the window raise it above Blizzard frames it shares the screen with.
local function bindLayeringScripts(frame)
	frame:HookScript("OnMouseDown", function()
		Tradewright:RecordExternalFrameInteraction("addon", "dashboard_mouse_down")
	end)
	frame.titleBar:HookScript("OnMouseDown", function()
		Tradewright:RecordExternalFrameInteraction("addon", "title_mouse_down")
	end)
	frame:HookScript("OnShow", function()
		Tradewright:UpdateDynamicPanelLayering("dashboard_show")
	end)
end

-- Resize grip in the footer corner; the new size is saved when the drag ends.
local function createResizeHandle(frame)
	local handle = CreateFrame("Button", nil, frame.statusBar)
	handle:SetSize(14, 14)
	handle:SetPoint("BOTTOMRIGHT", -2, 2)
	handle:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
	handle:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
	handle:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	handle:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		Tradewright:SetSetting("appearance.windowWidth", frame:GetWidth())
		Tradewright:SetSetting("appearance.windowHeight", frame:GetHeight())
	end)
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText("Drag to resize", 1, 1, 1)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", GameTooltip_Hide)
	frame.resizeHandle = handle
end

-- Footer: status on the left, stored data on the right, resize grip in the corner.
function Tradewright:CreateDashboardStatusBar(frame)
	local theme = self:GetTheme()
	frame.statusBar = CreateFrame("Frame", nil, frame)
	frame.statusBar:SetPoint("BOTTOMLEFT", 1, 1)
	frame.statusBar:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.statusBar:SetHeight(theme.size.footer)
	addRule(frame.statusBar, "TOP", theme.borderSubtle)
	createResizeHandle(frame)
	frame.statusRight = frame.statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.statusRight:SetPoint("RIGHT", frame.resizeHandle, "LEFT", -8, 0)
	frame.statusRight:SetJustifyH("RIGHT")
	frame.statusText = frame.statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.statusText:SetPoint("LEFT", theme.spacing.md, 0)
	frame.statusText:SetPoint("RIGHT", frame.statusRight, "LEFT", -12, 0)
	frame.statusText:SetJustifyH("LEFT")
	for _, text in ipairs({ frame.statusText, frame.statusRight }) do
		text:SetWordWrap(false)
		text:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	end
end

function Tradewright:IsDashboardTabShown(tabId)
	for _, tab in ipairs(TAB_ORDER) do
		if tab.id == tabId then
			return not tab.shown or tab.shown()
		end
	end
	return false
end

-- The tab to show for `tabId`: itself while it is offered, else Overview.
function Tradewright:ResolveDashboardTab(tabId)
	return tabId and self:IsDashboardTabShown(tabId) and tabId or "overview"
end

-- Lines up the buttons of the tabs on offer and hides the rest.
local function layoutTabButtons(pe, frame, buttons)
	local spacing = pe:GetTheme().spacing
	local previous
	for _, tab in ipairs(TAB_ORDER) do
		local button, shown = buttons[tab.id], pe:IsDashboardTabShown(tab.id)
		button:SetShown(shown)
		if shown then
			button:ClearAllPoints()
			if previous then
				button:SetPoint("LEFT", previous, "RIGHT", spacing.xs, 0)
			else
				button:SetPoint("LEFT", frame.tabBar, "LEFT", spacing.md, 0)
			end
			previous = button
		end
	end
end

-- Shows only the tabs on offer, and leaves the open tab when it is no longer offered.
function Tradewright:ApplyDashboardTabVisibility()
	local ui = self.ui
	local frame = ui and ui.mainFrame
	if not (frame and ui.tabButtons) then
		return
	end
	layoutTabButtons(self, frame, ui.tabButtons)
	local active = ui.activeMainTab
	if active and frame:IsShown() and self:ResolveDashboardTab(active) ~= active then
		self:ShowDashboardTab("overview")
	end
end

-- One tab button and one hidden content panel per dashboard tab.
function Tradewright:CreateDashboardTabs(frame)
	local ui = self.ui
	ui.tabButtons, ui.tabPanels, ui.tabModules, ui.tabInited = {}, {}, {}, {}
	for _, tab in ipairs(TAB_ORDER) do
		local button = createTabButton(frame.tabBar, tab.label)
		button:SetScript("OnClick", function()
			Tradewright:ShowDashboardTab(tab.id)
		end)
		ui.tabButtons[tab.id] = button
		local panel = CreateFrame("Frame", nil, frame.contentHost)
		panel:SetAllPoints()
		panel:Hide()
		ui.tabPanels[tab.id] = panel
		ui.tabModules[tab.id] = tab.module()
	end
end

function Tradewright:CreateDashboardFrame()
	local ui = self.ui
	if ui.mainFrame then
		return ui.mainFrame
	end
	local frame = createWindow()
	ui.mainFrame = frame
	local theme = self:GetTheme()
	local inset = theme.spacing.md
	self:CreateDashboardTitleBar(frame)
	bindLayeringScripts(frame)
	frame.tabBar = CreateFrame("Frame", nil, frame)
	frame.tabBar:SetPoint("TOPLEFT", frame.titleBar, "BOTTOMLEFT", 0, 0)
	frame.tabBar:SetPoint("TOPRIGHT", frame.titleBar, "BOTTOMRIGHT", 0, 0)
	frame.tabBar:SetHeight(theme.size.tabs)
	addRule(frame.tabBar, "BOTTOM", theme.borderSubtle)
	self:CreateDashboardStatusBar(frame)
	-- Content: everything between the tab strip and the footer, inset on every side.
	frame.contentHost = CreateFrame("Frame", nil, frame)
	frame.contentHost:SetPoint("TOPLEFT", frame.tabBar, "BOTTOMLEFT", inset, -inset)
	frame.contentHost:SetPoint("BOTTOMRIGHT", frame.statusBar, "TOPRIGHT", -inset, inset)
	if frame.contentHost.SetClipsChildren then
		frame.contentHost:SetClipsChildren(true)
	end
	self:CreateDashboardTabs(frame)
	self:ApplyDashboardTabVisibility()
	self:ApplyWindowScale()
	self:ApplyThemeToUI()
	self:UpdateDynamicPanelLayering("dashboard_created")
	frame:Hide()
	return frame
end

-- Title bar: gold on every stored character (this one live, the others as last seen).
function Tradewright:AccountGoldLabel()
	if not self.GetCurrentGoldSummaryForOverview then
		return ""
	end
	local gold = self:GetCurrentGoldSummaryForOverview(self.DASHBOARD_ACCOUNT_KEY or "__PE_ACCOUNT__")
	return gold and ("Gold on all characters " .. self:FormatCopperShort(gold)) or ""
end

-- Status bar, left: what is running now, else how fresh the AH prices are.
function Tradewright:GetShellActivityText()
	local state = self:GetState()
	if state.scanInProgress then
		return "Scanning " .. tostring(state.currentProfession and state.currentProfession.professionName or "professions") .. "…"
	end
	if not self.GetLastFullAuctionScanAt then
		return ""
	end
	local lastScanAt = self:GetLastFullAuctionScanAt()
	return lastScanAt and ("Prices from full AH scan " .. self:FormatScanTimestamp(lastScanAt))
		or "No full AH scan yet · open the auction house to get prices"
end

-- Status bar, right: stored characters, and when this character's professions were scanned.
function Tradewright:GetShellStoredText()
	local characters = self.db and self.db.characters or {}
	local stored = self:TableCount(characters)
	local text = string.format("%d %s stored", stored, self:Plural(stored, "character"))
	-- Profession scan time only matters when this character has a profession to scan.
	if #self:GetPlayerProfessions() == 0 then
		return text
	end
	local charData = characters[self:GetCharacterKey()]
	local scannedAt = charData and charData.scanFinishedAt
	if scannedAt and scannedAt > 0 then
		return text .. " · Professions scanned " .. self:FormatScanTimestamp(scannedAt)
	end
	return text .. " · Professions not scanned yet"
end

function Tradewright:RefreshShellStatus()
	local ui = self.ui
	if not (ui and ui.mainFrame and ui.mainFrame.statusText) then
		return
	end
	ui.mainFrame.statusText:SetText(self:GetShellActivityText())
	ui.mainFrame.statusRight:SetText(self:GetShellStoredText())
	ui.mainFrame.subtitle:SetText(self:AccountGoldLabel())
end

function Tradewright:ApplyThemeToUI()
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

-- The module drawing a tab (from TAB_ORDER), cached in ui.tabModules.
function Tradewright:GetDashboardTabModule(tabId)
	local ui = self.ui
	ui.tabModules = ui.tabModules or {}
	if ui.tabModules[tabId] then
		return ui.tabModules[tabId]
	end
	for _, tab in ipairs(TAB_ORDER) do
		if tab.id == tabId then
			ui.tabModules[tabId] = tab.module and tab.module() or nil
			return ui.tabModules[tabId]
		end
	end
	return nil
end

-- Runs a tab module's method guarded, so one broken tab cannot break the window. Returns false on error.
function Tradewright:CallDashboardTabModule(tabId, action, ...)
	local module = self.ui.tabModules and self.ui.tabModules[tabId]
	local method = module and module[action]
	if not method then
		return true
	end
	local ok, err = pcall(method, module, ...)
	if not ok and self.PrintMessage then
		self:PrintMessage("Tab '" .. tostring(tabId) .. "' failed to " .. string.lower(action) .. ": " .. tostring(err))
	end
	return ok
end

function Tradewright:EnsureDashboardTabCreated(tabId)
	local ui = self.ui
	if not ui or not tabId then
		return
	end
	ui.tabInited = ui.tabInited or {}
	if ui.tabInited[tabId] then
		return
	end
	self:GetDashboardTabModule(tabId)
	local panel = ui.tabPanels and ui.tabPanels[tabId]
	if panel and not self:CallDashboardTabModule(tabId, "Create", panel, ui) then
		return
	end
	ui.tabInited[tabId] = true
end

function Tradewright:OpenCraftsTabWithQueueFocus()
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

function Tradewright:ShowDashboardTab(tabId)
	local ui = self.ui
	if not ui.mainFrame then
		self:CreateDashboardFrame()
	end
	tabId = self:ResolveDashboardTab(tabId)
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
	self:CallDashboardTabModule(tabId, "Refresh", ui, self.db)
	if tabId == "crafts" and ui.craftsFocusQueue and self.FocusCraftsQueuePanel then
		ui.craftsFocusQueue = false
		self:FocusCraftsQueuePanel()
	end
	self:RefreshShellStatus()
	self:ApplyThemeToUI()
end

function Tradewright:RefreshDashboard(skipRebuild)
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

function Tradewright:ToggleDashboard()
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

function Tradewright:OpenDocumentationTab()
	self:InitDB()
	if not self.ui.mainFrame then
		self:CreateDashboardFrame()
	end
	self.ui.mainFrame:Show()
	self:RecordExternalFrameInteraction("addon", "open_docs_tab")
	self:ShowDashboardTab("docs")
end

function Tradewright:OpenSettingsTab()
	self:InitDB()
	if not self.ui.mainFrame then
		self:CreateDashboardFrame()
	end
	self.ui.mainFrame:Show()
	self:RecordExternalFrameInteraction("addon", "open_settings_tab")
	self:ShowDashboardTab("settings")
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
	if type(Tradewright[method]) == "function" then
		local original = Tradewright[method]
		Tradewright[method] = function(self, ...)
			local result = original(self, ...)
			self:SkinTree(getFrame(self, result))
			return result
		end
	end
end
