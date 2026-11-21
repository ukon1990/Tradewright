local addonName, AuctionHelper = ...

local PROFESSION_PANEL_WATCHER_KEY = "professionCraftPanel"

function AuctionHelper:GetProfessionCraftOperationSignature()
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

function AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(delaySeconds)
	if not self.IS_SUPPORTED then
		return
	end
	if self._professionCraftRefreshPending then
		return
	end
	self._professionCraftRefreshPending = true
	C_Timer.After(math.max(0, tonumber(delaySeconds) or 0.05), function()
		AuctionHelper._professionCraftRefreshPending = false
		AuctionHelper:RefreshProfessionCraftEconomyPanel(true)
	end)
end

-- Selects a recipe in the open profession window. On Forever the crafting page is told directly:
-- C_TradeSkillUI.OpenRecipe alone returns without selecting anything there.
local function selectProfessionRecipe(recipeID)
	local page = not AuctionHelper.IS_RETAIL and _G.ProfessionsFrame and _G.ProfessionsFrame.CraftingPage
	local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
	if page and info and type(page.SelectRecipe) == "function" and pcall(page.SelectRecipe, page, info) then
		return true
	end
	return C_TradeSkillUI.OpenRecipe ~= nil and pcall(C_TradeSkillUI.OpenRecipe, recipeID)
end

local function openProfessionSkillLine(skillLineID)
	local api = C_TradeSkillUI
	if not (skillLineID and api and api.OpenTradeSkill and api.GetBaseProfessionInfo) then
		return false
	end
	local info = api.GetBaseProfessionInfo()
	if tonumber(info and (info.professionID or info.profession or info.skillLineID)) == skillLineID then
		return false
	end
	return pcall(api.OpenTradeSkill, skillLineID)
end

--- Shows a recipe in the profession window, switching profession first when it belongs to another.
function AuctionHelper:JumpToProfessionRecipe(recipeID, skillLineID)
	recipeID = tonumber(recipeID)
	if not self.IS_SUPPORTED or not recipeID or not C_TradeSkillUI then
		return false
	end
	local function retry()
		selectProfessionRecipe(recipeID)
	end
	if openProfessionSkillLine(tonumber(skillLineID)) then
		-- The other profession's recipe list loads over the next frames.
		for _, delay in ipairs({ 0.10, 0.25, 0.45 }) do
			C_Timer.After(delay, retry)
		end
	elseif not selectProfessionRecipe(recipeID) then
		C_Timer.After(0.10, retry)
	end
	return true
end

function AuctionHelper:OnProfessionRecipeCraftedResult(craftingItemResultData)
	local craftedQuantity
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
			if not orderID and self.NoteCraftForSeller then
				self:NoteCraftForSeller(resultItemID or entry.outputItemID, craftedQuantity)
			end
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
				if not orderID and self.NoteCraftForSeller then
					self:NoteCraftForSeller(resultItemID, craftedQuantity)
				end
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

function AuctionHelper:SetProfessionPanelActiveTab(tabId, persist)
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

function AuctionHelper:ApplyProfessionPanelExpanded(expanded)
	local panel = self._professionCraftPanel
	if not panel then
		return
	end
	expanded = expanded ~= false
	self:SetSetting("professions.sidePanelExpanded", expanded)
	panel:SetShown(expanded)
	self:UpdateProfessionPanelToggleButton(expanded)
end

function AuctionHelper:UpdateProfessionPanelToggleButton(expanded)
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
	-- The side tab stays hidden: the toggle lives on the profession title bar.
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

function AuctionHelper:InitProfessionCraftEconomyHooks()
	if self._professionCraftEconomyHooks or not self.IS_SUPPORTED then
		return
	end
	local pf = _G.ProfessionsFrame
	if not pf then
		return
	end
	self._professionCraftEconomyHooks = true
	local function scheduleRefresh()
		AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
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
		if AuctionHelper._professionCraftPanel then
			AuctionHelper._professionCraftPanel:Hide()
			if AuctionHelper._professionCraftPanel.panelToggleBtn then
				AuctionHelper._professionCraftPanel.panelToggleBtn:Hide()
			end
			if AuctionHelper._professionCraftPanel.collapseTab then
				AuctionHelper._professionCraftPanel.collapseTab:Hide()
			end
		end
	end)

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("ProfessionsFrame.TabSet", function()
			scheduleRefresh()
		end, AuctionHelper)
	end

	-- Watch live operation state so concentration/reagent makeup changes refresh immediately.
	self:StartStateWatcher(PROFESSION_PANEL_WATCHER_KEY, 0.5, function()
		local form = AuctionHelper.GetOpenProfessionSchematicForm and AuctionHelper:GetOpenProfessionSchematicForm() or nil
		if not form or (form.IsShown and not form:IsShown()) then
			local openOrder = AuctionHelper.GetOpenCraftingOrder and AuctionHelper:GetOpenCraftingOrder() or nil
			if openOrder then
				return AuctionHelper:GetProfessionCraftOperationSignature()
			end
			return nil
		end
		return AuctionHelper:GetProfessionCraftOperationSignature()
	end, function()
		AuctionHelper:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end)
end

--- Dock to the right of ProfessionsFrame (same pattern as AH / Mail side panels).
function AuctionHelper:LayoutProfessionCraftEconomyPanel(panel)
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
	-- Forever hangs its profession selector tabs off the frame's right edge; dock clear of them.
	local sideTab = pf.ProfessionsOverviewTab
	local x = 8 + (sideTab and math.ceil(sideTab:GetWidth()) or 0)
	panel:SetPoint("TOPLEFT", pf, "TOPRIGHT", x, -20)
	panel:SetPoint("BOTTOMLEFT", pf, "BOTTOMRIGHT", x, 16)
	if panel.panelToggleBtn then
		anchorProfessionPanelToggleButton(panel.panelToggleBtn, pf)
	end
	if panel.collapseTab then
		panel.collapseTab:Hide()
	end
end

local PANEL_WIDTH = 400
local PAD = 12

local function rankMarkup(rankIndex)
	return AuctionHelper:GetRankMarkup(rankIndex)
end

local function queueOpenRecipe(amount)
	local pe = AuctionHelper
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
	host.stats = pe:CreateStats(host.statsRow, { "saleAfterCut", "materials", "profit" })
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
				if slot.have < slot.need then
					return pe:Colorize(pe:FormatNumberGrouped(slot.have), "danger")
				end
				return pe:FormatNumberGrouped(slot.have)
			end },
		pe:MoneyColumn({ id = "cost", label = "Cost", width = 76, sortable = false }),
	})
	return host
end

function AuctionHelper:EnsureProfessionCraftEconomyPanel()
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
	self:CreateProfessionQueueView(f)
	self:SkinTree(f)

	self._professionCraftPanel = f
	self:SetProfessionPanelActiveTab(self:GetSetting("professions.sidePanelTab", "info"), false)
	return f
end

-- Fills the Recipe view from the selected recipe's evaluation.
local function renderProfessionRecipe(pe, panel, ctx)
	local host = panel.infoHost
	local ev = ctx.eval or {}
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

	host.stats.saleAfterCut:SetValues("Sale after cut", ev.saleNet and pe:FormatCopperShort(ev.saleNet) or "-")
	host.stats.materials:SetValues("Materials", ev.matCost and pe:FormatCopperShort(ev.matCost) or "-")
	host.stats.profit:SetValues("Profit", pe:FormatSignedMoney(ev.profit), nil, (tonumber(ev.profit) or 0) < 0 and "danger" or "success")
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

function AuctionHelper:RefreshProfessionCraftEconomyPanel(force)
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
		self:RefreshProfessionQueueCard(panel)
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
		self:RefreshProfessionQueueCard(panel)
		panel.addButton:SetEnabled(false)
		if self.CraftingOrderViewRefreshButtons then
			self:CraftingOrderViewRefreshButtons()
		end
		self._refreshingProfessionCraftPanel = nil
		return
	end

	panel.addButton:SetEnabled(true)
	renderProfessionRecipe(self, panel, ctx)

	self:RefreshProfessionQueueCard(panel)
	if self.CraftingOrderViewRefreshButtons then
		self:CraftingOrderViewRefreshButtons()
	end
	panel:Show()
	self._refreshingProfessionCraftPanel = nil
end
