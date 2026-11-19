local addonName, ProfessionExporter = ...

local PROFESSION_PANEL_WATCHER_KEY = "professionCraftPanel"
local RANK_BADGE_PX = 16
local RANK_ICON_GAP = 4

local function applyRankBadge(texture, text, rankIndex)
	if not texture or not text or not rankIndex or rankIndex <= 0 then
		if texture then texture:Hide() end
		if text then text:Hide() end
		return
	end
	local atlas = "Professions-Icon-Quality-Tier" .. tostring(rankIndex) .. "-Inv"
	if texture.SetAtlas then
		texture:SetAtlas(atlas, true)
	end
	texture:SetSize(RANK_BADGE_PX, RANK_BADGE_PX)
	texture:Show()
	text:SetText(tostring(rankIndex))
	text:Show()
end

function ProfessionExporter:GetProfessionCraftOperationSignature()
	if not self.IS_SUPPORTED then
		return nil
	end
	local recipeID = self:GetOpenProfessionRecipeID()
	if not recipeID then
		return nil
	end

	local scenario = self:GetOpenProfessionScenario()
	local form = self.GetOpenProfessionSchematicForm and self:GetOpenProfessionSchematicForm() or nil
	local transaction = form and form.GetTransaction and form:GetTransaction() or nil
	local openOrder = self.GetOpenCraftingOrder and self:GetOpenCraftingOrder() or nil
	local orderPart = openOrder and tostring(openOrder.orderID) or "0"
	if not transaction then
		return tostring(recipeID) .. "|" .. tostring(scenario) .. "|" .. orderPart
	end

	local parts = { tostring(recipeID), tostring(scenario), orderPart }
	if type(transaction.IsApplyingConcentration) == "function" then
		parts[#parts + 1] = transaction:IsApplyingConcentration() and "conc1" or "conc0"
	end
	return table.concat(parts, "|")
end

function ProfessionExporter:ScheduleRefreshProfessionCraftEconomyPanel(delaySeconds)
	if not self.IS_SUPPORTED then
		return
	end
	if self._professionCraftRefreshPending then
		return
	end
	self._professionCraftRefreshPending = true
	C_Timer.After(math.max(0, tonumber(delaySeconds) or 0.05), function()
		ProfessionExporter._professionCraftRefreshPending = false
		ProfessionExporter:RefreshProfessionCraftEconomyPanel(true)
	end)
end

function ProfessionExporter:JumpToProfessionRecipe(recipeID, skillLineID)
	recipeID = tonumber(recipeID)
	skillLineID = tonumber(skillLineID)
	if not self.IS_SUPPORTED or not recipeID then
		return false
	end

	local function selectRecipeNow()
		if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
			local ok = pcall(C_TradeSkillUI.OpenRecipe, recipeID)
			if ok then
				return true
			end
		end
		local pf = _G.ProfessionsFrame
		local page = pf and pf.CraftingPage
		if not page then
			return false
		end
		if type(rawget(page, "SetSelectedRecipeID")) == "function" then
			local ok = pcall(page.SetSelectedRecipeID, page, recipeID)
			if ok then
				return true
			end
		end
		if type(page.SelectRecipe) == "function" then
			local ok = pcall(page.SelectRecipe, page, recipeID)
			if ok then
				return true
			end
		end
		return false
	end

	local currentSkillLineID = nil
	if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
		local info = C_TradeSkillUI.GetBaseProfessionInfo()
		currentSkillLineID = tonumber(info and (info.professionID or info.profession or info.skillLineID))
	end

	if skillLineID and currentSkillLineID ~= skillLineID and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
		local ok = pcall(C_TradeSkillUI.OpenTradeSkill, skillLineID)
		if not ok then
			return false
		end
		C_Timer.After(0.10, function() selectRecipeNow() end)
		C_Timer.After(0.25, function() selectRecipeNow() end)
		C_Timer.After(0.45, function() selectRecipeNow() end)
		return true
	end

	if selectRecipeNow() then
		return true
	end
	C_Timer.After(0.05, function() selectRecipeNow() end)
	C_Timer.After(0.20, function() selectRecipeNow() end)
	return true
end

local function safeGetObjectType(node)
	if not node or type(node) ~= "table" or type(node.GetObjectType) ~= "function" then
		return nil
	end
	local ok, objectType = pcall(node.GetObjectType, node)
	if ok then
		return objectType
	end
	return nil
end

local function recursiveFindFrameByPred(root, predicate, seen)
	if not root or type(root) ~= "table" or seen[root] then
		return nil
	end
	seen[root] = true
	local ok, matches = pcall(predicate, root)
	if ok and matches then
		return root
	end
	if type(root.GetChildren) == "function" then
		local childResults = { pcall(root.GetChildren, root) }
		if childResults[1] then
			for index = 2, #childResults do
				local child = childResults[index]
				local found = recursiveFindFrameByPred(child, predicate, seen)
				if found then
					return found
				end
			end
		end
	end
	for _, value in pairs(root) do
		if type(value) == "table" then
			local found = recursiveFindFrameByPred(value, predicate, seen)
			if found then
				return found
			end
		end
	end
	return nil
end

function ProfessionExporter:TrySetCurrentProfessionCraftQuantity(amount)
	amount = math.max(1, math.floor(tonumber(amount) or 0))
	if amount <= 0 or not self.IS_SUPPORTED then
		return false
	end
	local pf = _G.ProfessionsFrame
	local form = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
	if not form or not form.IsShown or not form:IsShown() then
		return false
	end
	local candidatePaths = {
		{ "QuantityInput", "InputBox" },
		{ "QuantityInput" },
		{ "Details", "QuantityInput", "InputBox" },
		{ "Details", "QuantityInput" },
		{ "Footer", "QuantityInput", "InputBox" },
		{ "Footer", "QuantityInput" },
	}
	local input = nil
	for _, path in ipairs(candidatePaths) do
		local node = form
		for _, key in ipairs(path) do
			node = node and node[key] or nil
		end
		if node and node.SetText and (not node.IsShown or node:IsShown()) then
			input = node
			break
		end
	end
	if not input then
		return false
	end
	input:SetText(tostring(amount))
	if input.OnTextChanged then
		pcall(input.OnTextChanged, input, true)
	elseif input.GetScript and input:GetScript("OnTextChanged") then
		pcall(input:GetScript("OnTextChanged"), input, true)
	end
	if input.ClearFocus then
		input:ClearFocus()
	end
	return true
end

function ProfessionExporter:BuildCurrentProfessionCraftingReagentInfo(recipeID)
	if not self.IS_SUPPORTED then
		return nil, false, nil
	end
	local pf = _G.ProfessionsFrame
	local form = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
	local transaction = form and form.GetTransaction and form:GetTransaction() or nil
	if not form or not transaction then
		return nil, false, nil
	end
	local isRecraft = type(transaction.GetRecraftAllocation) == "function" and transaction:GetRecraftAllocation() ~= nil
	local reagentInfo = nil
	if type(transaction.CreateCraftingReagentInfoTbl) == "function" then
		local ok, value = pcall(transaction.CreateCraftingReagentInfoTbl, transaction)
		if ok then
			reagentInfo = value
		end
	end
	local allocationGUID = nil
	if type(transaction.GetAllocationItemGUID) == "function" then
		local ok, value = pcall(transaction.GetAllocationItemGUID, transaction)
		if ok then
			allocationGUID = value
		end
	end
	return reagentInfo, isRecraft, allocationGUID
end

function ProfessionExporter:FindCurrentProfessionCreateButton()
	local pf = _G.ProfessionsFrame
	local form = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
	if not form or not form.IsShown or not form:IsShown() then
		return nil
	end
	local candidatePaths = {
		{ "CreateButton" },
		{ "CraftButton" },
		{ "CreateAllButton" },
		{ "Footer", "CreateButton" },
		{ "Footer", "CraftButton" },
		{ "Details", "CreateButton" },
		{ "DetailsView", "CreateButton" },
		{ "Schematic", "CreateButton" },
	}
	for _, path in ipairs(candidatePaths) do
		local node = form
		for _, key in ipairs(path) do
			node = node and node[key] or nil
		end
		if node and node.IsShown and node:IsShown() and node.IsEnabled and node:IsEnabled() and node.Click then
			return node
		end
	end
	return nil
end

function ProfessionExporter:TryTriggerCurrentProfessionCraft(recipeID, amount)
	if not self.IS_SUPPORTED then
		return false
	end
	recipeID = tonumber(recipeID)
	amount = math.max(1, math.floor(tonumber(amount) or 1))

	local createButton = self:FindCurrentProfessionCreateButton()
	if createButton then
		local ok = pcall(createButton.Click, createButton)
		if ok then
			return true
		end
		if type(createButton.GetScript) == "function" then
			local onClick = createButton:GetScript("OnClick")
			if type(onClick) == "function" then
				local clicked = pcall(onClick, createButton, "LeftButton")
				if clicked then
					return true
				end
			end
		end
	end

	if recipeID and C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
		local reagentInfo, isRecraft = self:BuildCurrentProfessionCraftingReagentInfo(recipeID)
		if not isRecraft then
			local concentrating = false
			local pf = _G.ProfessionsFrame
			local form = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
			local transaction = form and form.GetTransaction and form:GetTransaction() or nil
			if transaction and type(transaction.IsApplyingConcentration) == "function" then
				concentrating = transaction:IsApplyingConcentration() and true or false
			end
			local ok = pcall(C_TradeSkillUI.CraftRecipe, recipeID, amount, reagentInfo, nil, nil, concentrating)
			if ok then
				return true
			end
			-- Forever / older clients: craft without concentration or optional reagent args.
			ok = pcall(C_TradeSkillUI.CraftRecipe, recipeID, amount)
			if ok then
				return true
			end
		end
	end
	return false
end

function ProfessionExporter:CraftProfessionQueueRecipe(row)
	row = type(row) == "table" and row or nil
	local recipeSpellID = tonumber(row and (row.recipeSpellID or row.recipeID))
	if not recipeSpellID then
		return false
	end
	self._pendingProfessionQueueCraft = {
		queueKey = row and row.queueKey or nil,
		recipeID = recipeSpellID,
		outputItemID = tonumber(row and row.outputItemID),
		startedAt = GetTime and GetTime() or 0,
	}
	local craftAmount = math.max(1, math.floor(tonumber(row and row.quantity) or 1))
	local function attemptCraftSequence()
		if ProfessionExporter:GetOpenProfessionRecipeID() ~= recipeSpellID then
			return false
		end
		ProfessionExporter:TrySetCurrentProfessionCraftQuantity(craftAmount)
		C_Timer.After(0.08, function()
			if ProfessionExporter:GetOpenProfessionRecipeID() == recipeSpellID then
				ProfessionExporter:TrySetCurrentProfessionCraftQuantity(craftAmount)
			end
		end)
		C_Timer.After(0.16, function()
			if ProfessionExporter:GetOpenProfessionRecipeID() == recipeSpellID then
				ProfessionExporter:TryTriggerCurrentProfessionCraft(recipeSpellID, craftAmount)
			end
		end)
		return true
	end
	local openRecipeID = tonumber(self:GetOpenProfessionRecipeID())
	if openRecipeID ~= recipeSpellID then
		self:JumpToProfessionRecipe(recipeSpellID, row and row.skillLineID)
		C_Timer.After(0.18, attemptCraftSequence)
		C_Timer.After(0.40, attemptCraftSequence)
		return true
	end
	return attemptCraftSequence()
end

function ProfessionExporter:OnProfessionRecipeCraftedResult(craftingItemResultData)
	local craftedQuantity = 0
	local resultItemID = nil
	if type(craftingItemResultData) ~= "table" then
		return
	end
	if craftingItemResultData.hyperlink then
		resultItemID = select(1, C_Item.GetItemInfoInstant(craftingItemResultData.hyperlink))
	end
	if not resultItemID and craftingItemResultData.itemID then
		resultItemID = tonumber(craftingItemResultData.itemID)
	end
	craftedQuantity = tonumber(craftingItemResultData.quantity) or 0
	if craftedQuantity <= 0 then
		return
	end

	local storage = self.GetCraftQueueStorage and self:GetCraftQueueStorage() or nil
	if not storage then
		return
	end

	local pending = self._pendingProfessionQueueCraft
	if pending and pending.startedAt and (GetTime and (GetTime() - pending.startedAt) or 0) > 20 then
		self._pendingProfessionQueueCraft = nil
		pending = nil
	end

	local targetKey = pending and pending.queueKey or nil
	if targetKey and storage[targetKey] then
		local entry = storage[targetKey]
		if pending.outputItemID == nil or resultItemID == nil or tonumber(resultItemID) == tonumber(pending.outputItemID) then
			local orderID = entry and tonumber(entry.orderID)
			self:UpdateCraftQueueQuantity(targetKey, (tonumber(entry.quantity) or 0) - craftedQuantity)
			if orderID and self.RemoveCraftingOrderFromWorkQueue then
				self:RemoveCraftingOrderFromWorkQueue(orderID)
			end
			if not storage[targetKey] then
				self._pendingProfessionQueueCraft = nil
			end
			return
		end
	end

	if resultItemID ~= nil then
		for queueKey, entry in pairs(storage) do
			if tonumber(entry and entry.outputItemID) == tonumber(resultItemID) then
				local orderID = entry and tonumber(entry.orderID)
				self:UpdateCraftQueueQuantity(queueKey, (tonumber(entry.quantity) or 0) - craftedQuantity)
				if orderID and self.RemoveCraftingOrderFromWorkQueue then
					self:RemoveCraftingOrderFromWorkQueue(orderID)
				end
				return
			end
		end
	end

	if self.IsCraftingOrderInWorkQueue and self.RemoveCraftingOrderFromWorkQueue then
		local pf = _G.ProfessionsFrame
		local orderView = pf and pf.OrdersPage and pf.OrdersPage.OrderView
		local openOrder = orderView and orderView.order
		local orderID = openOrder and tonumber(openOrder.orderID)
		if orderID and self:IsCraftingOrderInWorkQueue(orderID) then
			local woEntry = self.GetCraftingOrderWorkQueueStorage and self:GetCraftingOrderWorkQueueStorage()[tostring(orderID)]
			local matches = false
			if woEntry then
				if resultItemID and tonumber(woEntry.itemID) == tonumber(resultItemID) then
					matches = true
				elseif openOrder and tonumber(openOrder.spellID) and tonumber(woEntry.spellID) == tonumber(openOrder.spellID) then
					matches = true
				end
			end
			if matches then
				self:RemoveCraftingOrderFromWorkQueue(orderID)
			end
		end
	end
end

function ProfessionExporter:SetProfessionPanelActiveTab(tabId, persist)
	tabId = tostring(tabId or "info")
	if tabId ~= "queue" then
		tabId = "info"
	end
	self.ui = self.ui or {}
	self.ui.professionPanelActiveTab = tabId
	if persist ~= false then
		self:SetSetting("professions.sidePanelTab", tabId)
	end
	local panel = self._professionCraftPanel
	if not panel then
		return
	end
	local isInfo = tabId == "info"
	if panel.infoHost then
		panel.infoHost:SetShown(isInfo)
	end
	if panel.queueHost then
		panel.queueHost:SetShown(not isInfo)
	end
	if panel.tabInfo then
		self:StyleShellButton(panel.tabInfo, isInfo)
	end
	if panel.tabQueue then
		self:StyleShellButton(panel.tabQueue, not isInfo)
	end
end

function ProfessionExporter:ApplyProfessionPanelExpanded(expanded)
	local panel = self._professionCraftPanel
	if not panel then
		return
	end
	expanded = expanded ~= false
	self:SetSetting("professions.sidePanelExpanded", expanded)
	panel:SetShown(expanded)
	self:UpdateProfessionPanelToggleButton(expanded)
end

function ProfessionExporter:UpdateProfessionPanelToggleButton(expanded)
	local panel = self._professionCraftPanel
	if not panel then
		return
	end
	if expanded == nil then
		expanded = self:GetSetting("professions.sidePanelExpanded", true) ~= false
	end
	local toggle = panel.panelToggleBtn
	if toggle then
		toggle:Show()
		toggle:SetText(expanded and "Hide AH" or "Show AH")
	end
	-- Legacy skinny side tab (kept hidden; toggle lives on the profession title bar).
	if panel.collapseTab then
		panel.collapseTab:Hide()
	end
end

local function anchorProfessionPanelToggleButton(toggle, pf)
	if not toggle or not pf then
		return
	end
	toggle:SetParent(pf)
	toggle:ClearAllPoints()
	local close = pf.CloseButton
	if close then
		toggle:SetPoint("RIGHT", close, "LEFT", -6, 0)
	elseif pf.TitleContainer and pf.TitleContainer.CloseButton then
		toggle:SetPoint("RIGHT", pf.TitleContainer.CloseButton, "LEFT", -6, 0)
	else
		toggle:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -36, -4)
	end
	toggle:SetFrameStrata(pf:GetFrameStrata() or "MEDIUM")
	local baseLevel = pf.GetFrameLevel and pf:GetFrameLevel() or 100
	toggle:SetFrameLevel(baseLevel + 50)
end

function ProfessionExporter:InitProfessionCraftEconomyHooks()
	if self._professionCraftEconomyHooks or not self.IS_SUPPORTED then
		return
	end
	local pf = _G.ProfessionsFrame
	if not pf then
		return
	end
	self._professionCraftEconomyHooks = true
	local function scheduleRefresh()
		ProfessionExporter:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
	local page = pf.CraftingPage
	if page then
		if type(page.SelectRecipe) == "function" then
			hooksecurefunc(page, "SelectRecipe", scheduleRefresh)
		end
		if type(rawget(page, "SetSelectedRecipeID")) == "function" then
			hooksecurefunc(page, "SetSelectedRecipeID", scheduleRefresh)
		end
		page:HookScript("OnShow", scheduleRefresh)
	end
	pf:HookScript("OnShow", scheduleRefresh)
	pf:HookScript("OnHide", function()
		if ProfessionExporter._professionCraftPanel then
			ProfessionExporter._professionCraftPanel:Hide()
			if ProfessionExporter._professionCraftPanel.panelToggleBtn then
				ProfessionExporter._professionCraftPanel.panelToggleBtn:Hide()
			end
			if ProfessionExporter._professionCraftPanel.collapseTab then
				ProfessionExporter._professionCraftPanel.collapseTab:Hide()
			end
		end
	end)

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("ProfessionsFrame.TabSet", function()
			scheduleRefresh()
		end, ProfessionExporter)
	end

	-- Watch live operation state so concentration/reagent makeup changes refresh immediately.
	self:StartStateWatcher(PROFESSION_PANEL_WATCHER_KEY, 0.5, function()
		local form = ProfessionExporter.GetOpenProfessionSchematicForm and ProfessionExporter:GetOpenProfessionSchematicForm() or nil
		if not form or (form.IsShown and not form:IsShown()) then
			local openOrder = ProfessionExporter.GetOpenCraftingOrder and ProfessionExporter:GetOpenCraftingOrder() or nil
			if openOrder then
				return ProfessionExporter:GetProfessionCraftOperationSignature()
			end
			return nil
		end
		return ProfessionExporter:GetProfessionCraftOperationSignature()
	end, function()
		ProfessionExporter:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end)
end

--- Dock to the right of ProfessionsFrame (same pattern as AH / Mail side panels).
function ProfessionExporter:LayoutProfessionCraftEconomyPanel(panel)
	if not panel then
		return
	end
	local pf = _G.ProfessionsFrame
	if not pf then
		return
	end
	panel:SetParent(pf)
	panel:SetFrameStrata(pf:GetFrameStrata() or "MEDIUM")
	local baseLevel = pf.GetFrameLevel and pf:GetFrameLevel() or 100
	panel:SetFrameLevel(baseLevel + 20)
	panel:ClearAllPoints()
	panel:SetWidth(400)
	panel:SetPoint("TOPLEFT", pf, "TOPRIGHT", 8, -20)
	panel:SetPoint("BOTTOMLEFT", pf, "BOTTOMRIGHT", 8, 16)
	if panel.panelToggleBtn then
		anchorProfessionPanelToggleButton(panel.panelToggleBtn, pf)
	end
	if panel.collapseTab then
		panel.collapseTab:Hide()
	end
end

function ProfessionExporter:EnsureProfessionCraftEconomyPanel()
	if self._professionCraftPanel then
		self:LayoutProfessionCraftEconomyPanel(self._professionCraftPanel)
		return self._professionCraftPanel
	end
	if not self.IS_SUPPORTED then
		return nil
	end
	local pf = _G.ProfessionsFrame
	if not pf then
		return nil
	end

	local f = CreateFrame("Frame", addonName .. "ProfessionEconomyBlock", pf, "BackdropTemplate")
	f:SetFrameStrata("MEDIUM")
	f:SetWidth(400)
	self:LayoutProfessionCraftEconomyPanel(f)
	self:StylePanel(f, "surface2")
	local theme = self:GetTheme()

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText("AuctionHelper")
	f.title = title

	local tabQueue = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	tabQueue:SetSize(64, 20)
	tabQueue:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
	tabQueue:SetText("Queue")
	tabQueue:SetScript("OnClick", function()
		ProfessionExporter:SetProfessionPanelActiveTab("queue", true)
	end)
	f.tabQueue = tabQueue

	local tabInfo = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	tabInfo:SetSize(96, 20)
	tabInfo:SetPoint("RIGHT", tabQueue, "LEFT", -4, 0)
	tabInfo:SetText("Crafting info")
	tabInfo:SetScript("OnClick", function()
		ProfessionExporter:SetProfessionPanelActiveTab("info", true)
	end)
	f.tabInfo = tabInfo

	-- Visible toggle next to the profession window close button (not a skinny side tab).
	local panelToggle = CreateFrame("Button", addonName .. "ProfessionPanelToggle", pf, "UIPanelButtonTemplate")
	panelToggle:SetSize(72, 22)
	panelToggle:SetText("Hide AH")
	anchorProfessionPanelToggleButton(panelToggle, pf)
	panelToggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("AuctionHelper profession panel", 1, 1, 1)
		GameTooltip:AddLine("Show or hide the side panel (shopping cart, crafting info).", 1, 0.9, 0.6, true)
		GameTooltip:Show()
	end)
	panelToggle:SetScript("OnLeave", GameTooltip_Hide)
	panelToggle:SetScript("OnClick", function()
		local wasExpanded = ProfessionExporter:GetSetting("professions.sidePanelExpanded", true) ~= false
		ProfessionExporter:ApplyProfessionPanelExpanded(not wasExpanded)
		if not wasExpanded then
			ProfessionExporter:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
		end
	end)
	f.panelToggleBtn = panelToggle

	-- Keep legacy frame name for any external references; never shown.
	local collapseTab = CreateFrame("Button", addonName .. "ProfessionPanelTab", pf)
	collapseTab:SetSize(1, 1)
	collapseTab:Hide()
	f.collapseTab = collapseTab
	f.collapseTabText = nil

	local infoHost = CreateFrame("Frame", nil, f)
	infoHost:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -36)
	infoHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
	f.infoHost = infoHost

	local status = infoHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPRIGHT", infoHost, "TOPRIGHT", -2, -2)
	status:SetJustifyH("RIGHT")

	local scanBtn = CreateFrame("Button", nil, infoHost, "UIPanelButtonTemplate")
	scanBtn:SetSize(52, 20)
	scanBtn:SetPoint("RIGHT", status, "LEFT", -6, 0)
	scanBtn:SetText("Scan")
	scanBtn:SetScript("OnClick", function()
		ProfessionExporter:ScanOpenProfession()
	end)

	local exportBtn = CreateFrame("Button", nil, infoHost, "UIPanelButtonTemplate")
	exportBtn:SetSize(58, 20)
	exportBtn:SetPoint("RIGHT", scanBtn, "LEFT", -4, 0)
	exportBtn:SetText("Export")
	exportBtn:SetScript("OnClick", function()
		local openInfo = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
		local skillLineID = openInfo and tonumber(openInfo.professionID or openInfo.profession or openInfo.skillLineID)
		if not skillLineID then
			ProfessionExporter:PrintMessage("Open a profession window first.")
			return
		end
		ProfessionExporter:ScanOpenProfession({ exportTalents = true })
	end)
	f.scanBtn = scanBtn
	f.exportBtn = exportBtn

	local summary = infoHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", infoHost, "TOPLEFT", 2, -28)
	summary:SetPoint("TOPRIGHT", infoHost, "TOPRIGHT", -2, -28)
	summary:SetJustifyH("LEFT")
	summary:SetWordWrap(true)

	local details = infoHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	details:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -6)
	details:SetPoint("TOPRIGHT", infoHost, "TOPRIGHT", -2, 0)
	details:SetJustifyH("LEFT")
	details:SetWordWrap(true)

	local crafter = infoHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	crafter:SetPoint("TOPLEFT", details, "BOTTOMLEFT", 0, -6)
	crafter:SetPoint("TOPRIGHT", infoHost, "TOPRIGHT", -2, 0)
	crafter:SetJustifyH("LEFT")
	crafter:SetWordWrap(true)

	local queueHost = CreateFrame("Frame", nil, f)
	queueHost:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -36)
	queueHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
	queueHost:Hide()
	f.queueHost = queueHost

	local orderNav = CreateFrame("Frame", nil, queueHost)
	orderNav:SetPoint("TOPLEFT", queueHost, "TOPLEFT", 0, 0)
	orderNav:SetPoint("TOPRIGHT", queueHost, "TOPRIGHT", 0, 0)
	orderNav:SetHeight(48)
	orderNav:Hide()
	f.orderNav = orderNav

	local addOrder = CreateFrame("Button", nil, orderNav, "UIPanelButtonTemplate")
	addOrder:SetSize(120, 22)
	addOrder:SetPoint("TOPLEFT", orderNav, "TOPLEFT", 0, 0)
	addOrder:SetText("Add to shopping")
	addOrder:Hide()
	f.peAddWorkOrderBtn = addOrder

	local remOrder = CreateFrame("Button", nil, orderNav, "UIPanelButtonTemplate")
	remOrder:SetSize(72, 22)
	remOrder:SetPoint("LEFT", addOrder, "RIGHT", 6, 0)
	remOrder:SetText("Remove")
	remOrder:Hide()
	f.peRemoveWorkOrderBtn = remOrder

	local prevOrder = CreateFrame("Button", nil, orderNav, "UIPanelButtonTemplate")
	prevOrder:SetSize(52, 22)
	prevOrder:SetPoint("TOPLEFT", addOrder, "BOTTOMLEFT", 0, -4)
	prevOrder:SetText("Prev")
	prevOrder:Hide()
	f.pePrevOrderBtn = prevOrder

	local nextOrder = CreateFrame("Button", nil, orderNav, "UIPanelButtonTemplate")
	nextOrder:SetSize(52, 22)
	nextOrder:SetPoint("LEFT", prevOrder, "RIGHT", 6, 0)
	nextOrder:SetText("Next")
	nextOrder:Hide()
	f.peNextOrderBtn = nextOrder

	local orderStatus = orderNav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	orderStatus:SetPoint("LEFT", nextOrder, "RIGHT", 8, 0)
	orderStatus:SetJustifyH("LEFT")
	orderStatus:Hide()
	f.peQueueStatusText = orderStatus

	addOrder:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("AuctionHelper", 1, 1, 1)
		GameTooltip:AddLine(
			"Adds this crafting order to AuctionHelper shopping without starting the order. Only crafter-supplied reagents are included.",
			1,
			0.9,
			0.6,
			true
		)
		GameTooltip:Show()
	end)
	addOrder:SetScript("OnLeave", GameTooltip_Hide)

	local queueCard = CreateFrame("Frame", nil, queueHost, "BackdropTemplate")
	queueCard:SetPoint("TOPLEFT", queueHost, "TOPLEFT", 0, 0)
	queueCard:SetPoint("TOPRIGHT", queueHost, "TOPRIGHT", 0, 0)
	queueCard:SetPoint("BOTTOMLEFT", queueHost, "BOTTOMLEFT", 0, 30)
	ProfessionExporter:ApplyBackdrop(queueCard, theme.surface3, theme.borderSubtle)

	local queueTitle = queueCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	queueTitle:SetPoint("TOPLEFT", 8, -8)
	queueTitle:SetText("Shopping cart")

	local queueOverview = queueCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	queueOverview:SetPoint("TOPLEFT", queueTitle, "BOTTOMLEFT", 0, -4)
	queueOverview:SetPoint("TOPRIGHT", queueCard, "TOPRIGHT", -8, 0)
	queueOverview:SetJustifyH("LEFT")
	queueOverview:SetWordWrap(true)

	local queueFooter = queueCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	queueFooter:SetPoint("BOTTOMLEFT", queueCard, "BOTTOMLEFT", 8, 8)
	queueFooter:SetPoint("BOTTOMRIGHT", queueCard, "BOTTOMRIGHT", -8, 8)
	queueFooter:SetJustifyH("LEFT")
	queueFooter:SetWordWrap(true)

	local recipeTitle = queueCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	recipeTitle:SetPoint("TOPLEFT", queueOverview, "BOTTOMLEFT", 0, -8)
	recipeTitle:SetText("Recipes to craft")

	local recipeTableHost = CreateFrame("Frame", nil, queueCard)
	recipeTableHost:SetPoint("TOPLEFT", recipeTitle, "BOTTOMLEFT", -2, -4)
	recipeTableHost:SetPoint("TOPRIGHT", queueCard, "TOPRIGHT", -8, 0)
	recipeTableHost:SetHeight(86)

	local recipeActions = CreateFrame("Frame", nil, queueCard)
	recipeActions:SetPoint("TOPLEFT", recipeTableHost, "BOTTOMLEFT", 0, -4)
	recipeActions:SetPoint("TOPRIGHT", queueCard, "TOPRIGHT", -8, 0)
	recipeActions:SetHeight(22)

	local reagentTitle = queueCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	reagentTitle:SetPoint("TOPLEFT", recipeTableHost, "BOTTOMLEFT", 0, -8)
	reagentTitle:SetText("Reagents to buy")

	local reagentTableHost = CreateFrame("Frame", nil, queueCard)
	reagentTableHost:SetPoint("TOPLEFT", reagentTitle, "BOTTOMLEFT", -2, -4)
	reagentTableHost:SetPoint("BOTTOMRIGHT", queueFooter, "TOPRIGHT", 2, 8)

	local btnRow = CreateFrame("Frame", nil, queueHost)
	btnRow:SetHeight(24)
	btnRow:SetPoint("BOTTOMLEFT", queueHost, "BOTTOMLEFT", 0, 0)
	btnRow:SetPoint("BOTTOMRIGHT", queueHost, "BOTTOMRIGHT", 0, 0)

	local x = 0
	local function mkBtn(label, w, onClick)
		local b = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
		b:SetSize(w, 22)
		b:SetPoint("LEFT", btnRow, "LEFT", x, 0)
		b:SetText(label)
		b:SetScript("OnClick", onClick)
		x = x + w + 4
		return b
	end

	local addQ = mkBtn("Add to queue", 96, function()
		local order = ProfessionExporter.GetOpenCraftingOrder and ProfessionExporter:GetOpenCraftingOrder() or nil
		if order and ProfessionExporter.AddCraftingOrderToWorkQueue then
			ProfessionExporter:PrintMessage(string.format("Queueing crafting order #%s...", tostring(order.orderID or "?")))
			ProfessionExporter:AddCraftingOrderToWorkQueue(order)
			if ProfessionExporter.CraftingOrderViewRefreshButtons then
				ProfessionExporter:CraftingOrderViewRefreshButtons(nil, order)
			end
			return
		end
		if ProfessionExporter.QueueOpenProfessionRecipe then
			ProfessionExporter:QueueOpenProfessionRecipe(1)
			if ProfessionExporter.CraftingOrderViewRefreshButtons then
				ProfessionExporter:CraftingOrderViewRefreshButtons()
			end
			return
		end
		local ctx = ProfessionExporter._lastProfessionEvalContext
		if ctx then
			ProfessionExporter:AddCraftToQueue(ctx, 1)
		end
	end)
	mkBtn("+1", 36, function()
		local order = ProfessionExporter.GetOpenCraftingOrder and ProfessionExporter:GetOpenCraftingOrder() or nil
		if order and ProfessionExporter.AddCraftingOrderToWorkQueue then
			ProfessionExporter:AddCraftingOrderToWorkQueue(order)
			return
		end
		if ProfessionExporter.QueueOpenProfessionRecipe then
			ProfessionExporter:QueueOpenProfessionRecipe(1)
			if ProfessionExporter.CraftingOrderViewRefreshButtons then
				ProfessionExporter:CraftingOrderViewRefreshButtons()
			end
			return
		end
		local ctx = ProfessionExporter._lastProfessionEvalContext
		if ctx then
			ProfessionExporter:AddCraftToQueue(ctx, 1)
		end
	end)
	mkBtn("+5", 36, function()
		local order = ProfessionExporter.GetOpenCraftingOrder and ProfessionExporter:GetOpenCraftingOrder() or nil
		if order and ProfessionExporter.AddCraftingOrderToWorkQueue then
			ProfessionExporter:AddCraftingOrderToWorkQueue(order)
			return
		end
		if ProfessionExporter.QueueOpenProfessionRecipe then
			ProfessionExporter:QueueOpenProfessionRecipe(5)
			if ProfessionExporter.CraftingOrderViewRefreshButtons then
				ProfessionExporter:CraftingOrderViewRefreshButtons()
			end
			return
		end
		local ctx = ProfessionExporter._lastProfessionEvalContext
		if ctx then
			ProfessionExporter:AddCraftToQueue(ctx, 5)
		end
	end)
	mkBtn("Open queue", 92, function()
		ProfessionExporter:OpenCraftsTabWithQueueFocus()
	end)

	local recipeTable = ProfessionExporter:CreateReusableTable(recipeTableHost, {
		rowHeight = 20,
		maxRows = 4,
		sortKey = "recipeName",
		sortAsc = true,
		onRowClick = function(_, rowData)
			if not rowData then
				return
			end
			local orderID = tonumber(rowData.orderID)
			if orderID and ProfessionExporter.OpenCraftingOrderWorkQueueEntry then
				local entry = ProfessionExporter.GetCraftingOrderWorkQueueStorage
					and ProfessionExporter:GetCraftingOrderWorkQueueStorage()[tostring(orderID)]
				if type(entry) == "table" then
					ProfessionExporter:OpenCraftingOrderWorkQueueEntry(entry)
					return
				end
				ProfessionExporter:OpenCraftingOrderWorkQueueEntry({ orderID = orderID, spellID = rowData.recipeID, itemID = rowData.outputItemID })
				return
			end
			ProfessionExporter:JumpToProfessionRecipe(rowData.recipeID, rowData.skillLineID)
		end,
	})
	if recipeTable and recipeTable.frame then
		recipeTable.frame:ClearAllPoints()
		recipeTable.frame:SetPoint("TOPLEFT", recipeTableHost, "TOPLEFT", 0, 0)
		recipeTable.frame:SetPoint("BOTTOMRIGHT", recipeTableHost, "BOTTOMRIGHT", 0, 0)
		recipeTable:SetColumns({
			{
				id = "recipe",
				label = "Recipe",
				width = 110,
				sortable = true,
				defaultSort = "asc",
				sortValue = function(row) return row and row.recipeName or "" end,
				createCell = function(rowFrame)
					local root = CreateFrame("Frame", nil, rowFrame)
					root:SetHeight(20)
					local rankIcon = root:CreateTexture(nil, "OVERLAY")
					rankIcon:SetSize(RANK_BADGE_PX, RANK_BADGE_PX)
					rankIcon:SetPoint("LEFT", root, "LEFT", 0, 0)
					rankIcon:Hide()
					local rankText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					rankText:SetPoint("CENTER", rankIcon, "CENTER", 0, 0)
					rankText:SetTextColor(1, 1, 1)
					rankText:Hide()
					local icon = root:CreateTexture(nil, "ARTWORK")
					icon:SetSize(16, 16)
					icon:SetPoint("LEFT", rankIcon, "RIGHT", RANK_ICON_GAP, 0)
					local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
					text:SetPoint("RIGHT", root, "RIGHT", 0, 0)
					text:SetJustifyH("LEFT")
					text:SetWordWrap(false)
					return { root = root, rankIcon = rankIcon, rankText = rankText, icon = icon, text = text }
				end,
				updateCell = function(cell, row)
					applyRankBadge(cell.rankIcon, cell.rankText, row and row.qualityIndex)
					cell.icon:SetTexture((row and row.outputIcon) or 134400)
					cell.text:SetText(row and row.recipeLabel or "-")
				end,
			},
			{
				id = "quantityEdit",
				label = "Qty",
				width = 110,
				sortable = true,
				defaultSort = "desc",
				sortValue = function(row) return tonumber(row and row.quantity) or 0 end,
				createCell = function(rowFrame)
					local root = CreateFrame("Frame", nil, rowFrame)
					root:SetHeight(20)
					local minus = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
					minus:SetSize(20, 18)
					minus:SetPoint("LEFT", root, "LEFT", 0, 0)
					minus:SetText("-")
					local input = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
					input:SetSize(34, 18)
					input:SetPoint("LEFT", minus, "RIGHT", 4, 0)
					input:SetAutoFocus(false)
					input:SetNumeric(true)
					input:SetMaxLetters(4)
					local plus = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
					plus:SetSize(20, 18)
					plus:SetPoint("LEFT", input, "RIGHT", 4, 0)
					plus:SetText("+")
					local remove = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
					remove:SetSize(20, 18)
					remove:SetPoint("LEFT", plus, "RIGHT", 6, 0)
					remove:SetText("X")
					local function applyQuantity(queueKey, quantity)
						if queueKey then
							ProfessionExporter:UpdateCraftQueueQuantity(queueKey, tonumber(quantity) or 0)
						end
					end
					minus:SetScript("OnClick", function(self)
						applyQuantity(self.queueKey, (tonumber(input:GetText()) or 0) - 1)
					end)
					plus:SetScript("OnClick", function(self)
						applyQuantity(self.queueKey, (tonumber(input:GetText()) or 0) + 1)
					end)
					remove:SetScript("OnClick", function(self)
						if self.queueKey then
							ProfessionExporter:RemoveCraftFromQueue(self.queueKey)
						end
					end)
					input:SetScript("OnEnterPressed", function(self)
						applyQuantity(self.queueKey, self:GetText())
						self:ClearFocus()
					end)
					input:SetScript("OnEditFocusLost", function(self)
						applyQuantity(self.queueKey, self:GetText())
					end)
					return { root = root, minus = minus, input = input, plus = plus, remove = remove }
				end,
				updateCell = function(cell, row)
					local queueKey = row and row.queueKey or nil
					cell.minus.queueKey = queueKey
					cell.plus.queueKey = queueKey
					cell.remove.queueKey = queueKey
					cell.input.queueKey = queueKey
					local value = tostring(tonumber(row and row.quantity) or 0)
					if cell.input:GetText() ~= value then
						cell.input:SetText(value)
						cell.input:HighlightText(0, 0)
					end
				end,
			},
			{
				id = "scenario",
				label = "Mode",
				width = 46,
				sortable = true,
				defaultSort = "asc",
				sortValue = function(row) return row and row.scenario or "" end,
				getText = function(row) return row and row.scenarioLabel or "-" end,
			},
			{
				id = "craft",
				label = "Do",
				width = 46,
				sortable = false,
				createCell = function(rowFrame)
					local button = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
					button:SetSize(42, 18)
					button:SetText("Craft")
					button:SetScript("OnClick", function(self)
						if self.rowData then
							ProfessionExporter:CraftProfessionQueueRecipe(self.rowData)
						end
					end)
					return button
				end,
				updateCell = function(cell, row)
					cell.rowData = row
					cell:SetEnabled(row and row.recipeID ~= nil)
					cell:SetText("Craft")
				end,
			},
			{
				id = "profit",
				label = "Profit",
				width = 80,
				sortable = true,
				defaultSort = "desc",
				sortValue = function(row) return tonumber(row and row.totalProfitValue) or -1e15 end,
				getText = function(row) return row and row.totalProfitText or "-" end,
			},
		})
	end

	local reagentTable = ProfessionExporter:CreateReusableTable(reagentTableHost, {
		rowHeight = 20,
		maxRows = 6,
		sortKey = "totalCost",
		sortAsc = false,
		onRowEnter = function(_, rowData)
			if not rowData or not rowData.itemID then
				return
			end
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			if GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(rowData.itemID)
			else
				GameTooltip:SetText("#" .. tostring(rowData.itemID))
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format("Buy %s @ %s each", ProfessionExporter:FormatNumberGrouped(rowData.quantity or 0), rowData.unitPrice and ProfessionExporter:FormatCopperShort(rowData.unitPrice) or "-"), 0.82, 0.88, 0.96)
			GameTooltip:AddLine(string.format("Total: %s", rowData.totalCost and ProfessionExporter:FormatCopperShort(rowData.totalCost) or "-"), 0.82, 0.88, 0.96)
			if rowData.recipeRefs and #rowData.recipeRefs > 0 then
				GameTooltip:AddLine("Used by:", 0.95, 0.85, 0.55)
				for i = 1, math.min(#rowData.recipeRefs, 5) do
					GameTooltip:AddLine("  " .. tostring(rowData.recipeRefs[i]), 0.75, 0.82, 0.88)
				end
			end
			GameTooltip:AddLine("Click to search this reagent in the AH shopping cart.", 0.75, 0.82, 0.9, true)
			GameTooltip:Show()
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData)
			if not rowData or not rowData.itemID then
				return
			end
			local itemID = tonumber(rowData.itemID)
			if not itemID then
				return
			end
			local state = ProfessionExporter:GetState()
			state.auctionCartSelectedItemID = itemID
			if ProfessionExporter.SetAuctionPanelActiveTab then
				ProfessionExporter:SetAuctionPanelActiveTab("cart", true)
			end
			local ok = ProfessionExporter.SearchAuctionCartRow and ProfessionExporter:SearchAuctionCartRow({ itemID = itemID, quantity = rowData.quantity })
			if ok then
				ProfessionExporter:PrintMessage(string.format("Searching AH for %s.", ProfessionExporter:GetItemDisplayName(itemID)))
			elseif not (_G.AuctionHouseFrame and _G.AuctionHouseFrame.IsShown and _G.AuctionHouseFrame:IsShown()) then
				ProfessionExporter:PrintMessage("Open the Auction House to search reagents from the shopping cart.")
			end
		end,
	})
	if reagentTable and reagentTable.frame then
		reagentTable.frame:ClearAllPoints()
		reagentTable.frame:SetPoint("TOPLEFT", reagentTableHost, "TOPLEFT", 0, 0)
		reagentTable.frame:SetPoint("BOTTOMRIGHT", reagentTableHost, "BOTTOMRIGHT", 0, 0)
		reagentTable:SetColumns({
			{
				id = "item",
				label = "Reagent",
				width = 150,
				sortable = true,
				defaultSort = "asc",
				sortValue = function(row) return row and row.name or "" end,
				createCell = function(rowFrame)
					local root = CreateFrame("Frame", nil, rowFrame)
					root:SetHeight(20)
					local rankIcon = root:CreateTexture(nil, "OVERLAY")
					rankIcon:SetSize(RANK_BADGE_PX, RANK_BADGE_PX)
					rankIcon:SetPoint("LEFT", root, "LEFT", 0, 0)
					rankIcon:Hide()
					local rankText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					rankText:SetPoint("CENTER", rankIcon, "CENTER", 0, 0)
					rankText:SetTextColor(1, 1, 1)
					rankText:Hide()
					local icon = root:CreateTexture(nil, "ARTWORK")
					icon:SetSize(16, 16)
					icon:SetPoint("LEFT", rankIcon, "RIGHT", RANK_ICON_GAP, 0)
					local text = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
					text:SetPoint("RIGHT", root, "RIGHT", 0, 0)
					text:SetJustifyH("LEFT")
					text:SetWordWrap(false)
					return { root = root, rankIcon = rankIcon, rankText = rankText, icon = icon, text = text }
				end,
				updateCell = function(cell, row)
					applyRankBadge(cell.rankIcon, cell.rankText, row and row.qualityIndex)
					cell.icon:SetTexture((row and row.icon) or 134400)
					cell.text:SetText(row and row.name or "-")
				end,
			},
			{
				id = "quantity",
				label = "Qty",
				width = 34,
				sortable = true,
				defaultSort = "desc",
				sortValue = function(row) return tonumber(row and row.quantity) or 0 end,
				getText = function(row) return ProfessionExporter:FormatNumberGrouped(row and row.quantity or 0) end,
			},
			{
				id = "unitPrice",
				label = "Each",
				width = 52,
				sortable = true,
				defaultSort = "desc",
				sortValue = function(row) return tonumber(row and row.unitPrice) or -1 end,
				getText = function(row) return row and row.unitPrice and ProfessionExporter:FormatCopperShort(row.unitPrice) or "-" end,
			},
			{
				id = "totalCost",
				label = "Total",
				width = 56,
				sortable = true,
				defaultSort = "desc",
				sortValue = function(row) return tonumber(row and row.totalCost) or -1 end,
				getText = function(row) return row and row.totalCost and ProfessionExporter:FormatCopperShort(row.totalCost) or "-" end,
			},
		})
	end

	f.statusText = status
	f.summaryText = summary
	f.detailsText = details
	f.crafterText = crafter
	f.queueCard = queueCard
	f.queueTitle = queueTitle
	f.queueOverviewText = queueOverview
	f.queueFooterText = queueFooter
	f.recipeTitle = recipeTitle
	f.recipeTable = recipeTable
	f.reagentTitle = reagentTitle
	f.reagentTable = reagentTable
	f.addButton = addQ

	self._professionCraftPanel = f
	local savedTab = self:GetSetting("professions.sidePanelTab", "info")
	self:SetProfessionPanelActiveTab(savedTab, false)

	local function showEconomicsTooltip(owner)
		local ctx = ProfessionExporter._lastProfessionEvalContext
		if not ctx or not ctx.eval then
			return
		end
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:SetText("Economics detail", 1, 1, 1)
		local ev = ctx.eval
		local cutPct = math.floor((ProfessionExporter:GetCraftsAhCutFraction() or 0) * 100 + 0.5)
		GameTooltip:AddLine(string.format("AH cut setting: %d%% (applied to gross sale).", cutPct), 0.85, 0.9, 0.95, true)
		GameTooltip:AddLine(string.format("Sale (gross est.): %s", ev.saleGross and ProfessionExporter:FormatCopperShort(ev.saleGross) or "—"), 0.8, 0.9, 1)
		GameTooltip:AddLine(string.format("Sale (net est.): %s", ev.saleNet and ProfessionExporter:FormatCopperShort(ev.saleNet) or "—"), 0.8, 0.9, 1)
		local planLabel = ev.liveSelectedPlan and "live setup" or "required slots"
		GameTooltip:AddLine(string.format("Materials (market): %s", ev.matCost and ProfessionExporter:FormatCopperShort(ev.matCost) or "—"), 0.8, 0.9, 1)
		if ev.outOfPocketMatCost and ev.outOfPocketMatCost ~= ev.matCost then
			GameTooltip:AddLine(string.format("Materials (%s out-of-pocket): %s", planLabel, ProfessionExporter:FormatCopperShort(ev.outOfPocketMatCost)), 0.8, 0.9, 1)
		end
		GameTooltip:AddLine(string.format("Inventory coverage: %.0f%%", (ev.coverage or 0) * 100), 0.8, 0.9, 1)
		if ev.requiredTargetReagent and ev.requiredTargetReagentItemID then
			GameTooltip:AddLine(
				string.format(
					"Required target reagent: %s (%s).",
					ProfessionExporter:GetItemDisplayName(ev.requiredTargetReagentItemID),
					ev.requiredTargetReagentAuto and "auto-selected" or "live-selected"
				),
				0.85, 0.82, 0.62
			)
		end
		if ev.qualityReachable == false then
			if ev.concentrationNeeded then
				GameTooltip:AddLine(string.format("+%s conc", ProfessionExporter:FormatNumberGrouped(ev.concentrationNeeded)), 1, 0.82, 0.45)
			elseif ev.concentrationCost and ev.concentrationCost > 0 then
				GameTooltip:AddLine("+conc", 1, 0.82, 0.45)
			else
				GameTooltip:AddLine("Unreachable", 1, 0.5, 0.5)
			end
		end
		if ev.reagentPlan then
			GameTooltip:AddLine(" ", 1, 1, 1)
			GameTooltip:AddLine("Reagents per craft:", 0.95, 0.85, 0.55)
			for _, slot in ipairs(ev.reagentPlan) do
				local nm = ProfessionExporter:GetItemDisplayName(slot.itemID)
				local inv = ProfessionExporter:BuildAccountItemInventoryTotals(slot.itemID)
				local note = ""
				if slot.slotClass == "required_target" then
					note = slot.liveSelected and " [target selected]" or " [target auto]"
				elseif slot.slotClass == "optional" then
					note = " [optional selected]"
				end
				local costSuffix = ProfessionExporter:FormatReagentSlotEconomicsTooltipSuffix(slot)
				GameTooltip:AddLine(string.format("  %s x%s  %s  (account %s)%s", nm, ProfessionExporter:FormatNumberGrouped(tonumber(slot.quantityRequired) or 0), costSuffix, ProfessionExporter:FormatNumberGrouped(tonumber(inv.total) or 0), note), 0.75, 0.82, 0.88)
			end
		end
		GameTooltip:Show()
	end
	infoHost:EnableMouse(true)
	infoHost:SetScript("OnEnter", function(self)
		showEconomicsTooltip(self)
	end)
	infoHost:SetScript("OnLeave", GameTooltip_Hide)

	return f
end

local function buildProfessionQueueRecipeRows(pe, queueSummary)
	local rows = {}
	for _, entry in ipairs(queueSummary and queueSummary.lines or {}) do
		local perProfit = tonumber(entry.snapshot and entry.snapshot.profit)
		local totalProfitValue = perProfit and (perProfit * (tonumber(entry.quantity) or 0)) or nil
		local orderID = tonumber(entry.orderID)
		local isOrder = orderID ~= nil or entry.scenario == "craftingOrder" or entry.source == "craftingOrder"
		local recipeName = entry.recipeName
		if (not recipeName or recipeName == "" or recipeName == "?") and tonumber(entry.recipeID) and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
			local ri = C_TradeSkillUI.GetRecipeInfo(tonumber(entry.recipeID))
			recipeName = ri and ri.name or recipeName
		end
		if (not recipeName or recipeName == "" or recipeName == "?") and tonumber(entry.outputItemID) then
			recipeName = pe:GetItemDisplayName(entry.outputItemID)
		end
		recipeName = tostring(recipeName or "?")
		local recipeLabel = recipeName
		local outputIcon = entry.outputIcon
		if (not outputIcon or outputIcon == 134400) and tonumber(entry.outputItemID) then
			local desc = pe.ResolveItemDescriptor and pe:ResolveItemDescriptor(entry.outputItemID)
			outputIcon = desc and desc.icon or outputIcon
		end
		rows[#rows + 1] = {
			queueKey = entry.queueKey,
			orderID = orderID,
			recipeID = tonumber(entry.recipeID),
			outputItemID = tonumber(entry.outputItemID),
			skillLineID = tonumber(entry.skillLineID),
			recipeName = recipeName,
			recipeLabel = recipeLabel,
			outputIcon = outputIcon,
			qualityIndex = tonumber(entry.qualityIndex),
			quantity = tonumber(entry.quantity) or 0,
			scenario = tostring(entry.scenario or "default"),
			scenarioLabel = isOrder and "Order" or ((entry.scenario == "concentration") and "Conc" or "Default"),
			totalProfitValue = totalProfitValue,
			totalProfitText = totalProfitValue and pe:FormatCopperShort(totalProfitValue) or "-",
		}
	end
	return rows
end

local function buildProfessionQueueReagentRows(pe, queueSummary)
	local rows = {}
	for _, reagent in ipairs(queueSummary and queueSummary.reagentLines or {}) do
		local qty = tonumber(reagent.quantityToBuy) or 0
		if qty > 0 then
			local desc = pe:ResolveItemDescriptor(reagent.itemID) or nil
			rows[#rows + 1] = {
				itemID = tonumber(reagent.itemID),
				name = reagent.name or pe:GetItemDisplayName(reagent.itemID),
				icon = desc and desc.icon or 134400,
				qualityIndex = pe:GetItemDisplayProfessionQualityRank(reagent.itemID),
				quantity = qty,
				mailToText = reagent.mailToText,
				unitPrice = tonumber(reagent.estimatedUnitPrice) or tonumber(reagent.priceUnit),
				totalCost = tonumber(reagent.estimatedBuyCost),
				recipeRefs = (function()
					local seen = {}
					local out = {}
					for _, src in ipairs(reagent.sources or {}) do
						local label = tostring(src and src.recipeName or "")
						if label ~= "" and not seen[label] then
							seen[label] = true
							out[#out + 1] = label
						end
					end
					table.sort(out)
					return out
				end)(),
			}
		end
	end
	return rows
end

local function refreshProfessionQueueCard(pe, panel)
	if not panel or not panel.queueOverviewText or not panel.queueFooterText or not panel.recipeTable or not panel.reagentTable then
		return
	end
	local queueSummary = pe:BuildCraftQueueSummary()
	local recipeRows = buildProfessionQueueRecipeRows(pe, queueSummary)
	local reagentRows = buildProfessionQueueReagentRows(pe, queueSummary)
	panel.queueOverviewText:SetText(string.format(
		"%d recipes queued  |  Reagents to buy %d  |  Buy total %s",
		tonumber(queueSummary.lineCount) or 0,
		#reagentRows,
		queueSummary.totalCurrentCharacterBuyCostKnown and pe:FormatCopperShort(queueSummary.totalCurrentCharacterBuyCostValue or 0) or "—"
	))
	panel.recipeTable:SetRows(recipeRows)
	panel.reagentTable:SetRows(reagentRows)
	local profitText = pe:FormatCopperShort(queueSummary.totalProfitValue or 0)
	if #reagentRows == 0 then
		panel.queueFooterText:SetText(string.format(
			"Potential profit %s  |  No reagents to buy on this character.",
			profitText
		))
	else
		panel.queueFooterText:SetText(string.format(
			"Potential profit %s  |  Buy total %s",
			profitText,
			queueSummary.totalCurrentCharacterBuyCostKnown and pe:FormatCopperShort(queueSummary.totalCurrentCharacterBuyCostValue or 0) or "—"
		))
		end
end

function ProfessionExporter:RefreshProfessionCraftEconomyPanel(force)
	if not self.IS_SUPPORTED then
		return
	end
	local now = GetTime and GetTime() or 0
	if self._refreshingProfessionCraftPanel then
		return
	end
	if not force and self._lastProfessionCraftRefreshAt and (now - self._lastProfessionCraftRefreshAt) < 0.10 then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0.10)
		return
	end
	self._refreshingProfessionCraftPanel = true
	self._lastProfessionCraftRefreshAt = now

	local pf = _G.ProfessionsFrame
	if not pf or not pf:IsShown() then
		if self._professionCraftPanel then
			self._professionCraftPanel:Hide()
			if self._professionCraftPanel.panelToggleBtn then
				self._professionCraftPanel.panelToggleBtn:Hide()
			end
			if self._professionCraftPanel.collapseTab then
				self._professionCraftPanel.collapseTab:Hide()
			end
		end
		self._lastProfessionEvalContext = nil
		self._refreshingProfessionCraftPanel = nil
		return
	end

	local panel = self:EnsureProfessionCraftEconomyPanel()
	if not panel then
		self._refreshingProfessionCraftPanel = nil
		return
	end
	self:LayoutProfessionCraftEconomyPanel(panel)

	local expanded = self:GetSetting("professions.sidePanelExpanded", true) ~= false
	self:UpdateProfessionPanelToggleButton(expanded)
	if not expanded then
		panel:Hide()
		refreshProfessionQueueCard(self, panel)
		if self.CraftingOrderViewRefreshButtons then
			self:CraftingOrderViewRefreshButtons()
		end
		self._refreshingProfessionCraftPanel = nil
		return
	end

	local activeTab = self.ui and self.ui.professionPanelActiveTab
		or self:GetSetting("professions.sidePanelTab", "info")
	self:SetProfessionPanelActiveTab(activeTab, false)

	local ctx, reason = self:EvaluateSelectedProfessionRecipe()
	self._lastProfessionEvalContext = ctx

	if not ctx then
		panel:Show()
		local msg = "Select a recipe to see economics."
		if reason == "no_data" then
			msg = "No stored data for this recipe — run a profession scan on this character or wait for the recipe list to finish loading."
		elseif reason == "no_recipe" then
			msg = "No recipe selected."
		elseif reason == "not_ready" then
			msg = "Profession UI not ready yet."
		elseif reason == "no_eval" then
			msg = "Could not resolve economics for the selected recipe yet. Try reselecting the recipe or rescanning this profession."
		elseif reason == "no_profession" then
			msg = "Could not resolve the active profession for the selected recipe."
		elseif reason == "not_retail" then
			panel:Hide()
			if panel.panelToggleBtn then
				panel.panelToggleBtn:Hide()
			end
			if panel.collapseTab then
				panel.collapseTab:Hide()
			end
			self._refreshingProfessionCraftPanel = nil
			return
		end
		panel.statusText:SetText(msg)
		panel.summaryText:SetText("")
		panel.detailsText:SetText("")
		panel.crafterText:SetText("")
		refreshProfessionQueueCard(self, panel)
		panel.addButton:SetEnabled(false)
		if self.CraftingOrderViewRefreshButtons then
			self:CraftingOrderViewRefreshButtons()
		end
		self._refreshingProfessionCraftPanel = nil
		return
	end

	panel.addButton:SetEnabled(true)
	local ev = ctx.eval
	local conf = ctx.confidence or "ok"

	local statusMsg
	if conf == "missing_sale_price" or conf == "missing_mat_price" then
		statusMsg = "|cffff9900Missing price data|r"
	elseif conf == "stale_scan" then
		statusMsg = "|cffcccc55Using last scan (live recipe API unavailable)|r"
	elseif ev.canCraftNow then
		statusMsg = "|cff88ff88Can craft now|r"
	elseif ev.qualityReachable == false and ev.concentrationNeeded then
		statusMsg = string.format("|cffffff80+%s conc|r", self:FormatNumberGrouped(ev.concentrationNeeded))
	elseif ev.qualityReachable == false and ev.concentrationCost and ev.concentrationCost > 0 then
		statusMsg = "|cffffff80+conc|r"
	elseif ev.qualityReachable == false then
		statusMsg = "|cffff6666Unreachable|r"
	else
		statusMsg = "|cffff6666Missing materials|r"
	end
	panel.statusText:SetText(statusMsg)

	panel.summaryText:SetText(string.format(
		"Sale (net) %s  |  Mats %s  |  Profit %s",
		ev.saleNet and self:FormatCopperShort(ev.saleNet) or "—",
		ev.matCost and self:FormatCopperShort(ev.matCost) or "—",
		ev.profit and self:FormatCopperShort(ev.profit) or "—"
	))
	local detailParts = {
		string.format("Coverage %.0f%%", (ev.coverage or 0) * 100),
	}
	if ev.outOfPocketMatCost and ev.outOfPocketMatCost ~= ev.matCost then
		detailParts[#detailParts + 1] = string.format("Buy-only %s", self:FormatCopperShort(ev.outOfPocketMatCost))
	end
	if ev.concentrationNeeded then
		detailParts[#detailParts + 1] = string.format("+%s conc", self:FormatNumberGrouped(ev.concentrationNeeded))
	elseif ev.qualityReachable == false and ev.concentrationCost and ev.concentrationCost > 0 then
		detailParts[#detailParts + 1] = "+conc"
	end
	if ev.requiredTargetReagent and ev.requiredTargetReagentItemID then
		detailParts[#detailParts + 1] = string.format(
			"Target %s (%s)",
			self:GetItemDisplayName(ev.requiredTargetReagentItemID),
			ev.requiredTargetReagentAuto and "auto" or "live"
		)
	end
	panel.detailsText:SetText(table.concat(detailParts, "  |  "))
	panel.crafterText:SetText(string.format("Recommended crafter: %s", ctx.recommendedCrafterLabel or "—"))

	refreshProfessionQueueCard(self, panel)
	if self.CraftingOrderViewRefreshButtons then
		self:CraftingOrderViewRefreshButtons()
	end
	panel:Show()
	self._refreshingProfessionCraftPanel = nil
end
