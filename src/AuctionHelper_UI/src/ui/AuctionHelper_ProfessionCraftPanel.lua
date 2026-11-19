local addonName, ProfessionExporter = ...

local PROFESSION_PANEL_WATCHER_KEY = "professionCraftPanel"

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
		toggle:SetText(expanded and "Hide panel" or "Show panel")
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

local PANEL_WIDTH = 400
local PAD = 12
local TALL_ROW = 36

local function rankMarkup(rankIndex)
	rankIndex = tonumber(rankIndex)
	if not rankIndex or rankIndex <= 0 then
		return ""
	end
	return string.format(" |A:Professions-Icon-Quality-Tier%d-Small:14:14|a", rankIndex)
end

local function queueOpenRecipe(amount)
	local pe = ProfessionExporter
	local order = pe.GetOpenCraftingOrder and pe:GetOpenCraftingOrder() or nil
	if order and pe.AddCraftingOrderToWorkQueue then
		pe:PrintMessage(string.format("Queueing crafting order #%s...", tostring(order.orderID or "?")))
		pe:AddCraftingOrderToWorkQueue(order)
	elseif pe.QueueOpenProfessionRecipe then
		pe:QueueOpenProfessionRecipe(amount)
	elseif pe._lastProfessionEvalContext then
		pe:AddCraftToQueue(pe._lastProfessionEvalContext, amount)
	end
	if pe.CraftingOrderViewRefreshButtons then
		pe:CraftingOrderViewRefreshButtons(nil, order)
	end
end

local function createRecipeView(pe, f)
	local host = CreateFrame("Frame", nil, f)
	host:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(pe:GetTheme().size.header + 1 + PAD))
	host:SetPoint("BOTTOMRIGHT", f.footer, "TOPRIGHT", -(PAD - 1), PAD)
	f.infoHost = host

	host.empty = pe:CreateEmptyState(host)
	host.empty:SetAllPoints()
	host.body = CreateFrame("Frame", nil, host)
	host.body:SetAllPoints()

	host.header = pe:CreateDetailHeader(host.body)
	host.header:SetPoint("TOPLEFT")
	host.header:SetPoint("TOPRIGHT")
	host.statsRow = CreateFrame("Frame", nil, host.body)
	host.statsRow:SetPoint("TOPLEFT", host.header, "BOTTOMLEFT", 0, -10)
	host.statsRow:SetPoint("TOPRIGHT", host.header, "BOTTOMRIGHT", 0, -10)
	host.statsRow:SetHeight(58)
	host.stats = { pe:CreateStat(host.statsRow), pe:CreateStat(host.statsRow), pe:CreateStat(host.statsRow) }
	host.statsRow:SetScript("OnSizeChanged", function()
		pe:LayoutEvenRow(host.statsRow, host.stats, 0, 8)
	end)
	host.facts = pe:CreateKeyValueList(host.body)
	host.facts:SetPoint("TOPLEFT", host.statsRow, "BOTTOMLEFT", 0, -10)
	host.facts:SetPoint("TOPRIGHT", host.statsRow, "BOTTOMRIGHT", 0, -10)
	host.materialsHeading = pe:CreateHeading(host.body, "Materials per craft")
	host.materialsHeading:SetPoint("TOPLEFT", host.facts, "BOTTOMLEFT", 0, -10)
	host.materialsHeading:SetPoint("TOPRIGHT", host.facts, "BOTTOMRIGHT", 0, -10)

	host.actions = CreateFrame("Frame", nil, host)
	host.actions:SetPoint("BOTTOMLEFT")
	host.actions:SetPoint("BOTTOMRIGHT")
	host.actions:SetHeight(26)
	host.qty = CreateFrame("EditBox", nil, host.actions, "InputBoxTemplate")
	host.qty:SetSize(32, 22)
	host.qty:SetPoint("LEFT", 6, 0)
	host.qty:SetAutoFocus(false)
	host.qty:SetNumeric(true)
	host.qty:SetMaxLetters(4)
	host.qty:SetJustifyH("RIGHT")
	host.qty:SetText("1")
	host.qty:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	pe:SkinEditBox(host.qty)
	f.addButton = pe:CreateButton(host.actions, "Add to queue", function()
		queueOpenRecipe(math.max(1, tonumber(host.qty:GetText()) or 1))
	end, { primary = true })
	f.addButton:SetPoint("LEFT", host.qty, "RIGHT", 10, 0)
	f.exportBtn = pe:CreateButton(host.actions, "Export", function()
		local info = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
		if not (info and tonumber(info.professionID or info.profession or info.skillLineID)) then
			pe:PrintMessage("Open a profession window first.")
			return
		end
		pe:ScanOpenProfession({ exportTalents = true })
	end, { tooltip = "Scan this profession, then open the export window." })
	f.exportBtn:SetPoint("RIGHT")
	f.scanBtn = pe:CreateButton(host.actions, "Scan", function()
		pe:ScanOpenProfession()
	end, { tooltip = "Store every recipe and reagent of this profession." })
	f.scanBtn:SetPoint("RIGHT", f.exportBtn, "LEFT", -8, 0)

	host.materials = pe:CreateReusableTable(host.body, {
		autoFitToScroll = true,
		footer = true,
		emptyTitle = "No materials",
		emptyHint = "This recipe has no stored reagents.",
	})
	host.materials.frame:SetPoint("TOPLEFT", host.materialsHeading, "BOTTOMLEFT", 0, -6)
	host.materials.frame:SetPoint("BOTTOMRIGHT", host.actions, "TOPRIGHT", 0, 10)
	host.materials:SetColumns({
		pe:CreateItemColumn({ label = "Reagent", sortable = false,
			getItemID = function(slot) return slot.itemID end,
			getName = function(slot) return pe:GetItemDisplayName(slot.itemID) end }),
		{ id = "need", label = "Need", width = 40, justifyH = "RIGHT", getText = function(slot) return tostring(slot.need) end },
		{ id = "have", label = "Have", width = 46, justifyH = "RIGHT",
			getText = function(slot)
				local danger = pe:GetTheme().danger
				if slot.have < slot.need then
					return string.format("|cff%02x%02x%02x%s|r", danger.r * 255, danger.g * 255, danger.b * 255, pe:FormatNumberGrouped(slot.have))
				end
				return pe:FormatNumberGrouped(slot.have)
			end },
		{ id = "cost", label = "Cost", width = 76, justifyH = "RIGHT", getText = function(slot) return slot.cost and pe:FormatCopperShort(slot.cost) or "-" end },
	})
	return host
end

local function stepperCell(pe)
	return function(rowFrame)
		local cell = CreateFrame("Frame", nil, rowFrame)
		cell.minus = pe:CreateButton(cell, "-", nil, { small = true, width = 22 })
		cell.minus:SetPoint("LEFT", 5, 0)
		cell.value = pe:CreateText(cell, "NumberFontNormalSmall", "textPrimary", "CENTER")
		cell.value:SetPoint("LEFT", cell.minus, "RIGHT", 0, 0)
		cell.value:SetWidth(26)
		cell.plus = pe:CreateButton(cell, "+", nil, { small = true, width = 22 })
		cell.plus:SetPoint("LEFT", cell.value, "RIGHT", 0, 0)
		return cell
	end
end

local function createQueueView(pe, f)
	local host = CreateFrame("Frame", nil, f)
	host:SetPoint("TOPLEFT", f.infoHost, "TOPLEFT")
	host:SetPoint("BOTTOMRIGHT", f.infoHost, "BOTTOMRIGHT")
	host:Hide()
	f.queueHost = host

	-- Crafting order navigation (retail): placed by the crafting orders module.
	local orderNav = CreateFrame("Frame", nil, host)
	orderNav:SetPoint("TOPLEFT")
	orderNav:SetPoint("TOPRIGHT")
	orderNav:SetHeight(48)
	orderNav:Hide()
	f.orderNav = orderNav
	f.peAddWorkOrderBtn = pe:CreateButton(orderNav, "Add to shopping", nil, { tooltip = "Adds this order's crafter-supplied reagents to the cart without starting the order." })
	f.peAddWorkOrderBtn:SetPoint("TOPLEFT")
	f.peAddWorkOrderBtn:Hide()
	f.peRemoveWorkOrderBtn = pe:CreateButton(orderNav, "Remove")
	f.peRemoveWorkOrderBtn:SetPoint("LEFT", f.peAddWorkOrderBtn, "RIGHT", 8, 0)
	f.peRemoveWorkOrderBtn:Hide()
	f.pePrevOrderBtn = pe:CreateButton(orderNav, "Previous", nil, { small = true })
	f.pePrevOrderBtn:SetPoint("TOPLEFT", f.peAddWorkOrderBtn, "BOTTOMLEFT", 0, -4)
	f.pePrevOrderBtn:Hide()
	f.peNextOrderBtn = pe:CreateButton(orderNav, "Next", nil, { small = true })
	f.peNextOrderBtn:SetPoint("LEFT", f.pePrevOrderBtn, "RIGHT", 8, 0)
	f.peNextOrderBtn:Hide()
	f.peQueueStatusText = pe:CreateText(orderNav, "GameFontHighlightSmall", "textMuted")
	f.peQueueStatusText:SetPoint("LEFT", f.peNextOrderBtn, "RIGHT", 8, 0)
	f.peQueueStatusText:Hide()

	local card = CreateFrame("Frame", nil, host)
	card:SetPoint("TOPLEFT")
	card:SetPoint("TOPRIGHT")
	card:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 30)
	f.queueCard = card

	f.queueOverviewText = pe:CreateParagraph(card)
	f.queueOverviewText:SetPoint("TOPLEFT")
	f.queueOverviewText:SetPoint("TOPRIGHT")
	f.recipeTitle = pe:CreateHeading(card, "To craft")
	f.recipeTitle:SetPoint("TOPLEFT", f.queueOverviewText, "BOTTOMLEFT", 0, -8)
	f.recipeTitle:SetPoint("TOPRIGHT", f.queueOverviewText, "BOTTOMRIGHT", 0, -8)
	f.recipeTable = pe:CreateReusableTable(card, {
		rowHeight = TALL_ROW,
		autoFitToScroll = true,
		emptyTitle = "Nothing queued",
		emptyHint = "Pick a recipe and press Add to queue.",
		onRowClick = function(_, row)
			if not row then
				return
			end
			local orderID = tonumber(row.orderID)
			if orderID and pe.OpenCraftingOrderWorkQueueEntry then
				local storage = pe.GetCraftingOrderWorkQueueStorage and pe:GetCraftingOrderWorkQueueStorage() or {}
				pe:OpenCraftingOrderWorkQueueEntry(type(storage[tostring(orderID)]) == "table" and storage[tostring(orderID)]
					or { orderID = orderID, spellID = row.recipeID, itemID = row.outputItemID })
				return
			end
			pe:JumpToProfessionRecipe(row.recipeID, row.skillLineID)
		end,
	})
	f.recipeTable.frame:SetPoint("TOPLEFT", f.recipeTitle, "BOTTOMLEFT", 0, -6)
	f.recipeTable.frame:SetPoint("TOPRIGHT", f.recipeTitle, "BOTTOMRIGHT", 0, -6)
	f.recipeTable:SetColumns({
		{ id = "recipe", label = "Recipe", width = 100, flex = 1, minWidth = 90,
			createCell = function(rowFrame)
				local cell = CreateFrame("Frame", nil, rowFrame)
				cell.name = pe:CreateText(cell, "GameFontHighlightSmall")
				cell.name:SetPoint("BOTTOMLEFT", cell, "LEFT", 5, 1)
				cell.name:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
				cell.detail = pe:CreateText(cell, "GameFontHighlightSmall", "textMuted")
				cell.detail:SetPoint("TOPLEFT", cell, "LEFT", 5, -1)
				cell.detail:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
				return cell
			end,
			updateCell = function(cell, row)
				cell.name:SetText(row.recipeLabel .. rankMarkup(row.qualityIndex))
				cell.detail:SetText(row.detailText)
			end },
		{ id = "qty", label = "Qty", width = 80, createCell = stepperCell(pe),
			updateCell = function(cell, row)
				cell.value:SetText(tostring(row.quantity))
				cell.minus:SetScript("OnClick", function() pe:UpdateCraftQueueQuantity(row.queueKey, row.quantity - 1) end)
				cell.plus:SetScript("OnClick", function() pe:UpdateCraftQueueQuantity(row.queueKey, row.quantity + 1) end)
			end },
		{ id = "craft", label = "", width = 56,
			createCell = function(rowFrame)
				local cell = CreateFrame("Frame", nil, rowFrame)
				cell.button = pe:CreateButton(cell, "Craft", nil, { small = true, width = 46 })
				cell.button:SetPoint("CENTER")
				return cell
			end,
			updateCell = function(cell, row)
				cell.button:SetScript("OnClick", function() pe:CraftProfessionQueueRecipe(row) end)
				cell.button:SetEnabled(row.recipeID ~= nil and row.canCraftNow == true)
				pe:SetButtonPrimary(cell.button, row.canCraftNow == true)
			end },
		{ id = "remove", label = "", width = 30,
			createCell = function(rowFrame)
				local cell = CreateFrame("Frame", nil, rowFrame)
				cell.button = CreateFrame("Button", nil, cell, "UIPanelCloseButton")
				cell.button:ClearAllPoints()
				cell.button:SetPoint("CENTER")
				pe:SkinCloseButton(cell.button)
				return cell
			end,
			updateCell = function(cell, row)
				cell.button:SetScript("OnClick", function() pe:RemoveCraftFromQueue(row.queueKey) end)
			end },
	})

	f.reagentTitle = pe:CreateHeading(card, "To buy")
	f.reagentTitle:SetPoint("TOPLEFT", f.recipeTable.frame, "BOTTOMLEFT", 0, -10)
	f.reagentTitle:SetPoint("TOPRIGHT", f.recipeTable.frame, "BOTTOMRIGHT", 0, -10)
	f.reagentTable = pe:CreateReusableTable(card, {
		autoFitToScroll = true,
		footer = true,
		sortKey = "totalCost",
		sortAsc = false,
		emptyTitle = "Nothing to buy",
		emptyHint = "This character has every material the queue needs.",
		onRowEnter = function(rowFrame, row)
			if row then
				pe:ShowItemRowTooltip(rowFrame, row.itemID, {
					{ "Buy", pe:FormatNumberGrouped(row.quantity) },
					{ "Each", row.unitPrice and pe:FormatCopperFull(row.unitPrice) or "-" },
					{ "Used by", table.concat(row.recipeRefs or {}, ", ") },
				}, "Click to find it at the auction house")
			end
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, row)
			local itemID = row and tonumber(row.itemID)
			if not itemID then
				return
			end
			pe:GetState().auctionCartSelectedItemID = itemID
			if pe.SetAuctionPanelActiveTab then
				pe:SetAuctionPanelActiveTab("cart", true)
			end
			if pe.SearchAuctionCartRow and pe:SearchAuctionCartRow({ itemID = itemID, quantity = row.quantity }) then
				pe:PrintMessage(string.format("Searching AH for %s.", pe:GetItemDisplayName(itemID)))
			elseif not (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown()) and not (_G.AuctionFrame and _G.AuctionFrame:IsShown()) then
				pe:PrintMessage("Open the auction house to find reagents from the cart.")
			end
		end,
	})
	f.reagentTable.frame:SetPoint("TOPLEFT", f.reagentTitle, "BOTTOMLEFT", 0, -6)
	f.reagentTable.frame:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
	f.reagentTable:SetColumns({
		pe:CreateItemColumn({ label = "Reagent", sortable = true,
			getItemID = function(row) return row.itemID end,
			getName = function(row) return row.name .. rankMarkup(row.qualityIndex) end }),
		{ id = "quantity", label = "Buy", width = 40, justifyH = "RIGHT", sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.quantity end, getText = function(row) return pe:FormatNumberGrouped(row.quantity) end },
		{ id = "unitPrice", label = "Each", width = 70, justifyH = "RIGHT", optional = true, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.unitPrice or -1 end,
			getText = function(row) return row.unitPrice and pe:FormatCopperShort(row.unitPrice) or "-" end },
		{ id = "totalCost", label = "Total", width = 76, justifyH = "RIGHT", sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.totalCost or -1 end,
			getText = function(row) return row.totalCost and pe:FormatCopperShort(row.totalCost) or "-" end },
	})

	local actions = CreateFrame("Frame", nil, host)
	actions:SetPoint("BOTTOMLEFT")
	actions:SetPoint("BOTTOMRIGHT")
	actions:SetHeight(26)
	local open = pe:CreateButton(actions, "Open in dashboard", function() pe:OpenCraftsTabWithQueueFocus() end)
	open:SetPoint("LEFT")
	f.clearQueueButton = pe:CreateButton(actions, "Clear queue", function() pe:ClearCraftQueue() end)
	f.clearQueueButton:SetPoint("RIGHT")
	local danger = pe:GetTheme().danger
	f.clearQueueButton:GetFontString():SetTextColor(danger.r, danger.g, danger.b)
	return host
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
	local pe = self
	local theme = self:GetTheme()

	local f = CreateFrame("Frame", addonName .. "ProfessionEconomyBlock", pf, "BackdropTemplate")
	f:SetFrameStrata("MEDIUM")
	f:SetWidth(PANEL_WIDTH)
	self:LayoutProfessionCraftEconomyPanel(f)
	self:StyleWindow(f)
	f:SetClampedToScreen(true)

	-- Header: title and the Recipe / Queue switch.
	f.tabQueue = self:CreateButton(f, "Queue", function()
		pe:SetProfessionPanelActiveTab("queue", true)
	end, { small = true })
	f.tabQueue:SetPoint("RIGHT", f, "TOPRIGHT", -PAD, -(theme.size.header / 2))
	f.tabInfo = self:CreateButton(f, "Recipe", function()
		pe:SetProfessionPanelActiveTab("info", true)
	end, { small = true })
	f.tabInfo:SetPoint("RIGHT", f.tabQueue, "LEFT", 1, 0)
	f.title = self:CreateText(f, "GameFontNormalLarge", "gold")
	f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(theme.size.header / 2) - 1)
	f.title:SetPoint("RIGHT", f.tabInfo, "LEFT", -12, 0)
	f.title:SetText("AuctionHelper")
	local headerRule = f:CreateTexture(nil, "BORDER")
	headerRule:SetPoint("TOPLEFT", 1, -theme.size.header)
	headerRule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	headerRule:SetHeight(1)
	headerRule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)

	-- Footer: when this profession was scanned.
	f.footer = CreateFrame("Frame", nil, f)
	f.footer:SetPoint("BOTTOMLEFT", 1, 1)
	f.footer:SetPoint("BOTTOMRIGHT", -1, 1)
	f.footer:SetHeight(theme.size.footer)
	local footerRule = f.footer:CreateTexture(nil, "BORDER")
	footerRule:SetPoint("TOPLEFT")
	footerRule:SetPoint("TOPRIGHT")
	footerRule:SetHeight(1)
	footerRule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	f.footerText = self:CreateText(f.footer, "GameFontHighlightSmall", "textMuted")
	f.footerText:SetPoint("LEFT", PAD, 0)
	f.footerText:SetPoint("RIGHT", -PAD, 0)

	-- Toggle on the profession window's title bar, left of its close button.
	local panelToggle = CreateFrame("Button", addonName .. "ProfessionPanelToggle", pf, "UIPanelButtonTemplate")
	panelToggle:SetText("Hide panel")
	self:SkinButton(panelToggle)
	panelToggle:SetSize(80, theme.size.controlSmall)
	anchorProfessionPanelToggleButton(panelToggle, pf)
	panelToggle:HookScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
		GameTooltip:SetText("AuctionHelper panel", 1, 1, 1)
		GameTooltip:AddLine("Show or hide recipe profit and the craft queue.", theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, true)
		GameTooltip:Show()
	end)
	panelToggle:HookScript("OnLeave", GameTooltip_Hide)
	panelToggle:SetScript("OnClick", function()
		local wasExpanded = pe:GetSetting("professions.sidePanelExpanded", true) ~= false
		pe:ApplyProfessionPanelExpanded(not wasExpanded)
		if not wasExpanded then
			pe:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
		end
	end)
	f.panelToggleBtn = panelToggle

	createRecipeView(self, f)
	createQueueView(self, f)
	self:SkinTree(f)

	self._professionCraftPanel = f
	self:SetProfessionPanelActiveTab(self:GetSetting("professions.sidePanelTab", "info"), false)
	return f
end

local function buildProfessionQueueRecipeRows(pe, queueSummary)
	local rows = {}
	for index, entry in ipairs(queueSummary and queueSummary.lines or {}) do
		local perProfit = tonumber(entry.snapshot and entry.snapshot.profit)
		local quantity = tonumber(entry.quantity) or 0
		local totalProfit = perProfit and perProfit * quantity or nil
		local orderID = tonumber(entry.orderID)
		local recipeName = entry.recipeName
		if (not recipeName or recipeName == "" or recipeName == "?") and tonumber(entry.recipeID) and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
			local info = C_TradeSkillUI.GetRecipeInfo(tonumber(entry.recipeID))
			recipeName = info and info.name or recipeName
		end
		if (not recipeName or recipeName == "" or recipeName == "?") and tonumber(entry.outputItemID) then
			recipeName = pe:GetItemDisplayName(entry.outputItemID)
		end
		local detail = {}
		if orderID then
			detail[#detail + 1] = "Order #" .. orderID
		end
		detail[#detail + 1] = "Profit " .. (totalProfit and pe:FormatSignedMoney(totalProfit) or "unknown")
		if entry.snapshot and entry.snapshot.canCraftNow then
			detail[#detail + 1] = "ready"
		end
		rows[#rows + 1] = {
			_rowIdentity = index,
			queueKey = entry.queueKey,
			orderID = orderID,
			recipeID = tonumber(entry.recipeID),
			outputItemID = tonumber(entry.outputItemID),
			skillLineID = tonumber(entry.skillLineID),
			recipeLabel = tostring(recipeName or "?"),
			qualityIndex = tonumber(entry.qualityIndex),
			quantity = quantity,
			scenario = tostring(entry.scenario or "default"),
			canCraftNow = entry.snapshot and entry.snapshot.canCraftNow == true,
			detailText = table.concat(detail, " · "),
		}
	end
	return rows
end

local function buildProfessionQueueReagentRows(pe, queueSummary)
	local rows = {}
	for _, reagent in ipairs(queueSummary and queueSummary.reagentLines or {}) do
		local qty = tonumber(reagent.quantityToBuy) or 0
		if qty > 0 then
			local refs, seen = {}, {}
			for _, src in ipairs(reagent.sources or {}) do
				local label = tostring(src and src.recipeName or "")
				if label ~= "" and not seen[label] then
					seen[label] = true
					refs[#refs + 1] = label
				end
			end
			table.sort(refs)
			rows[#rows + 1] = {
				_rowIdentity = reagent.itemID,
				itemID = tonumber(reagent.itemID),
				name = reagent.name or pe:GetItemDisplayName(reagent.itemID),
				qualityIndex = pe:GetItemDisplayProfessionQualityRank(reagent.itemID),
				quantity = qty,
				unitPrice = tonumber(reagent.estimatedUnitPrice) or tonumber(reagent.priceUnit),
				totalCost = tonumber(reagent.estimatedBuyCost),
				recipeRefs = refs,
			}
		end
	end
	return rows
end

local function refreshProfessionQueueCard(pe, panel)
	if not panel or not panel.recipeTable then
		return
	end
	local summary = pe:BuildCraftQueueSummary()
	local recipeRows = buildProfessionQueueRecipeRows(pe, summary)
	local reagentRows = buildProfessionQueueReagentRows(pe, summary)
	local crafts = 0
	for _, row in ipairs(recipeRows) do
		crafts = crafts + row.quantity
	end
	pe:SetButtonLabel(panel.tabQueue, #recipeRows > 0 and string.format("Queue (%d)", #recipeRows) or "Queue", true)
	panel.queueOverviewText:SetText(#recipeRows == 0 and "The queue is empty." or string.format(
		"%d crafts of %d recipes · potential profit %s · %d reagents to buy",
		crafts, #recipeRows, summary.totalProfit and pe:FormatSignedMoney(summary.totalProfit) or "unknown", #reagentRows))
	panel.recipeTable:SetRows(recipeRows)
	panel.recipeTable:Refresh()
	panel.recipeTable.frame:SetHeight(22 + 2 + TALL_ROW * math.max(1, math.min(#recipeRows, 3)))
	panel.reagentTable:SetRows(reagentRows)
	panel.reagentTable:Refresh()
	panel.reagentTable:SetFooterText("Click a reagent to find it at the auction house",
		summary.totalCurrentCharacterBuyCostKnown and pe:FormatCopperShort(summary.totalCurrentCharacterBuyCostValue or 0) or nil)
	panel.clearQueueButton:SetEnabled(#recipeRows > 0)
end

-- Fills the Recipe view from the selected recipe's evaluation.
local function renderProfessionRecipe(pe, panel, ctx)
	local host = panel.infoHost
	local ev = ctx.eval or {}
	local theme = pe:GetTheme()
	host.empty:Hide()
	host.body:Show()
	host.header:SetItem(ev.outputItemID, (ev.recipeName or pe:GetItemDisplayName(ev.outputItemID)) .. rankMarkup(ev.qualityIndex),
		string.format("%s · best crafter %s", tostring(ev.professionName or "?"), tostring(ctx.recommendedCrafterLabel or "-")), ev.outputIcon)

	local conf = ctx.confidence or "ok"
	if conf == "missing_sale_price" or conf == "missing_mat_price" then
		host.header.badge:SetBadge("No price", "warning")
	elseif conf == "stale_scan" then
		host.header.badge:SetBadge("Old scan", "warning")
	elseif ev.canCraftNow then
		host.header.badge:SetBadge("Can craft", "success")
	elseif ev.qualityReachable == false then
		host.header.badge:SetBadge((ev.concentrationNeeded or ev.concentrationCost) and "Needs concentration" or "Out of reach", "warning")
	else
		local missing = 0
		for _, slot in ipairs(ev.reagentPlan or {}) do
			missing = missing + math.max(0, tonumber(slot.purchasedQuantity) or 0)
		end
		host.header.badge:SetBadge(missing > 0 and ("Missing " .. missing) or "Missing", "danger")
	end

	host.stats[1]:SetValues("Sale after cut", ev.saleNet and pe:FormatCopperShort(ev.saleNet) or "-")
	host.stats[2]:SetValues("Materials", ev.matCost and pe:FormatCopperShort(ev.matCost) or "-")
	host.stats[3]:SetValues("Profit", pe:FormatSignedMoney(ev.profit), nil, (tonumber(ev.profit) or 0) < 0 and "danger" or "success")
	pe:LayoutEvenRow(host.statsRow, host.stats, 0, 8)

	local cut = math.floor((pe:GetCraftsAhCutFraction() or 0) * 100 + 0.5)
	local facts = {
		{ "Return", ev.roi and string.format("%.0f%%", ev.roi) or "-" },
		{ "Materials you already own", string.format("%.0f%%", (ev.coverage or 0) * 100) },
		{ "Still to buy", ev.outOfPocketMatCost and pe:FormatCopperFull(ev.outOfPocketMatCost) or "-" },
		{ string.format("Sale before the %d%% auction cut", cut), ev.saleGross and pe:FormatCopperFull(ev.saleGross) or "-" },
	}
	if pe.IS_RETAIL and ev.concentrationNeeded then
		facts[#facts + 1] = { "Concentration needed", pe:FormatNumberGrouped(ev.concentrationNeeded) }
	end
	if ev.requiredTargetReagent and ev.requiredTargetReagentItemID then
		facts[#facts + 1] = { "Target reagent", pe:GetItemDisplayName(ev.requiredTargetReagentItemID) }
	end
	host.facts:SetRows(facts)

	local materials = {}
	for index, slot in ipairs(ev.reagentPlan or {}) do
		local inv = pe:BuildAccountItemInventoryTotals(slot.itemID)
		materials[#materials + 1] = {
			_rowIdentity = index,
			itemID = slot.itemID,
			need = tonumber(slot.quantityRequired) or 0,
			have = tonumber(inv and inv.total) or 0,
			cost = tonumber(slot.lineCost),
		}
	end
	host.materials:SetRows(materials)
	host.materials:Refresh()
	host.materials:SetFooterText("Have counts every character", ev.matCost and pe:FormatCopperShort(ev.matCost) or nil)
	panel.footerText:SetText(string.format("%s scanned %s", tostring(ev.professionName or "Profession"), pe:FormatScanTimestamp(ev.scanAt)))
end

local function renderProfessionEmpty(panel, message)
	local host = panel.infoHost
	host.body:Hide()
	host.empty:Show()
	host.empty:SetMessage("No recipe to show", message)
	panel.footerText:SetText("")
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
		local msg = "Select a recipe to see its profit and materials."
		if reason == "no_data" then
			msg = "This recipe is not stored yet. Press Scan, or wait for the recipe list to finish loading."
		elseif reason == "no_recipe" then
			msg = "Select a recipe to see its profit and materials."
		elseif reason == "not_ready" then
			msg = "The profession window is still loading."
		elseif reason == "no_eval" then
			msg = "Profit for this recipe could not be worked out yet. Select it again or press Scan."
		elseif reason == "no_profession" then
			msg = "The profession for this recipe could not be found. Press Scan."
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
		renderProfessionEmpty(panel, msg)
		refreshProfessionQueueCard(self, panel)
		panel.addButton:SetEnabled(false)
		if self.CraftingOrderViewRefreshButtons then
			self:CraftingOrderViewRefreshButtons()
		end
		self._refreshingProfessionCraftPanel = nil
		return
	end

	panel.addButton:SetEnabled(true)
	renderProfessionRecipe(self, panel, ctx)

	refreshProfessionQueueCard(self, panel)
	if self.CraftingOrderViewRefreshButtons then
		self:CraftingOrderViewRefreshButtons()
	end
	panel:Show()
	self._refreshingProfessionCraftPanel = nil
end
