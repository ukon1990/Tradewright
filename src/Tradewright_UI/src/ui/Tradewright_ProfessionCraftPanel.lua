local addonName, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local PROFESSION_PANEL_WATCHER_KEY = "professionCraftPanel"

local function openCraftingOrderPart(pe)
	local openOrder = pe.GetOpenCraftingOrder and pe:GetOpenCraftingOrder() or nil
	return openOrder and tostring(openOrder.orderID) or "0"
end

local function openProfessionTransaction(pe)
	local form = pe.GetOpenProfessionSchematicForm and pe:GetOpenProfessionSchematicForm() or nil
	return form and form.GetTransaction and form:GetTransaction() or nil
end

-- "recipe|scenario|order[|conc0/conc1]": changes whenever the open craft would evaluate differently.
function Tradewright:GetProfessionCraftOperationSignature()
	if not self.IS_SUPPORTED then
		return nil
	end
	local recipeID = self:GetOpenProfessionRecipeID()
	if not recipeID then
		return nil
	end
	local parts = { tostring(recipeID), tostring(self:GetOpenProfessionScenario()), openCraftingOrderPart(self) }
	local transaction = openProfessionTransaction(self)
	if transaction and type(transaction.IsApplyingConcentration) == "function" then
		parts[#parts + 1] = transaction:IsApplyingConcentration() and "conc1" or "conc0"
	end
	return table.concat(parts, "|")
end

function Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(delaySeconds)
	if not self.IS_SUPPORTED then
		return
	end
	if self._professionCraftRefreshPending then
		return
	end
	self._professionCraftRefreshPending = true
	C_Timer.After(math.max(0, tonumber(delaySeconds) or 0.05), function()
		Tradewright._professionCraftRefreshPending = false
		Tradewright:RefreshProfessionCraftEconomyPanel(true)
	end)
end

-- The first rank of a recipe that has ranks (separate spells linked by previousRecipeID). The
-- profession window lists a ranked recipe under its first rank and shows the highest known rank
-- when that one is opened; opening any other rank selects nothing.
local function firstRankRecipeID(recipeID)
	local getInfo = C_TradeSkillUI.GetRecipeInfo
	-- No recipe has more than a few ranks; the bound only guards against a link that loops.
	for _ = 1, 10 do
		local info = getInfo and getInfo(recipeID)
		local previousID = info and tonumber(info.previousRecipeID)
		if not previousID then
			break
		end
		recipeID = previousID
	end
	return recipeID
end

-- Selects a recipe in the open profession window. On Forever the crafting page is told directly:
-- C_TradeSkillUI.OpenRecipe alone returns without selecting anything there.
local function selectProfessionRecipe(recipeID)
	recipeID = firstRankRecipeID(recipeID)
	local page = not Tradewright.IS_RETAIL and _G.ProfessionsFrame and _G.ProfessionsFrame.CraftingPage
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
function Tradewright:JumpToProfessionRecipe(recipeID, skillLineID)
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

-- The panel's views by their saved name: the panel fields that hold each one's frame and header button.
local PANEL_VIEWS = {
	info = { host = "infoHost", button = "tabInfo" },
	leveling = { host = "levelingHost", button = "tabLeveling" },
	queue = { host = "queueHost", button = "tabQueue" },
}

function Tradewright:SetProfessionPanelActiveTab(tabId, persist)
	tabId = PANEL_VIEWS[tostring(tabId)] and tostring(tabId) or "info"
	self.ui = self.ui or {}
	self.ui.professionPanelActiveTab = tabId
	if persist ~= false then
		self:SetSetting("professions.sidePanelTab", tabId)
	end
	local panel = self._professionCraftPanel
	if not panel then
		return
	end
	for viewId, view in pairs(PANEL_VIEWS) do
		local selected = viewId == tabId
		if panel[view.host] then
			panel[view.host]:SetShown(selected)
		end
		if panel[view.button] then
			self:StyleShellButton(panel[view.button], selected)
		end
	end
end

-- Hides the panel and its rail.
local function hideProfessionPanel(panel)
	Tradewright:ShowPanelDock(panel.dock, false)
end

local function hookRecipeSelection(page, scheduleRefresh)
	if type(page.SelectRecipe) == "function" then
		hooksecurefunc(page, "SelectRecipe", scheduleRefresh)
	end
	if type(rawget(page, "SetSelectedRecipeID")) == "function" then
		hooksecurefunc(page, "SetSelectedRecipeID", scheduleRefresh)
	end
	page:HookScript("OnShow", scheduleRefresh)
end

-- The signature the state watcher compares: the open craft's, while its form or a crafting order is open.
local function watchedOperationSignature()
	local pe = Tradewright
	local form = pe.GetOpenProfessionSchematicForm and pe:GetOpenProfessionSchematicForm() or nil
	local formShown = form and not (form.IsShown and not form:IsShown())
	if formShown or (pe.GetOpenCraftingOrder and pe:GetOpenCraftingOrder()) then
		return pe:GetProfessionCraftOperationSignature()
	end
	return nil
end

function Tradewright:InitProfessionCraftEconomyHooks()
	if self._professionCraftEconomyHooks or not self.IS_SUPPORTED then
		return
	end
	local pf = _G.ProfessionsFrame
	if not pf then
		return
	end
	self._professionCraftEconomyHooks = true
	local function scheduleRefresh()
		Tradewright:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
	if pf.CraftingPage then
		hookRecipeSelection(pf.CraftingPage, scheduleRefresh)
	end
	pf:HookScript("OnShow", scheduleRefresh)
	pf:HookScript("OnHide", function()
		if Tradewright._professionCraftPanel then
			hideProfessionPanel(Tradewright._professionCraftPanel)
		end
	end)
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("ProfessionsFrame.TabSet", function()
			scheduleRefresh()
		end, Tradewright)
		-- Retail: another expansion of the profession was picked in the window's dropdown.
		EventRegistry:RegisterCallback("Professions.ProfessionSelected", function()
			scheduleRefresh()
		end, Tradewright)
	end
	-- Watch live operation state so concentration/reagent makeup changes refresh immediately.
	self:StartStateWatcher(PROFESSION_PANEL_WATCHER_KEY, 0.5, watchedOperationSignature, scheduleRefresh)
end

--- Dock to the right of ProfessionsFrame (same pattern as AH / Mail side panels).
function Tradewright:LayoutProfessionCraftEconomyPanel(panel)
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
	if panel.dock then
		self:SetPanelDockOffset(panel.dock, x)
	end
end

local PANEL_WIDTH = 400
local PAD = 12

local function rankMarkup(rankIndex)
	return Tradewright:GetRankMarkup(rankIndex)
end

local function queueOpenRecipe(amount)
	local pe = Tradewright
	local order = pe.GetOpenCraftingOrder and pe:GetOpenCraftingOrder() or nil
	if order and pe.AddCraftingOrderToQueue then
		pe:PrintMessage(string.format(L["Adding crafting order #%s to the queue…"], tostring(order.orderID or "?")))
		pe:AddCraftingOrderToQueue(order)
	elseif pe.QueueOpenProfessionRecipe then
		pe:QueueOpenProfessionRecipe(amount)
	elseif pe._lastProfessionEvalContext then
		pe:AddCraftToQueue(pe._lastProfessionEvalContext, amount)
	end
	if pe.CraftingOrderViewRefreshButtons then
		pe:CraftingOrderViewRefreshButtons(nil, order)
	end
end

-- Item header, sale / materials / profit stats, key facts and the materials heading.
local function createRecipeSummary(pe, host)
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
	host.materialsHeading = pe:CreateHeading(host.body, L["Reagents per craft"])
	host.materialsHeading:SetPoint("TOPLEFT", host.facts, "BOTTOMLEFT", 0, -10)
	host.materialsHeading:SetPoint("TOPRIGHT", host.facts, "BOTTOMRIGHT", 0, -10)
end

-- Bottom row: quantity box and Add to queue on the left, Scan on the right.
local function createRecipeActions(pe, f, host)
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
	f.addButton = pe:CreateButton(host.actions, L["Add to queue"], function()
		queueOpenRecipe(math.max(1, tonumber(host.qty:GetText()) or 1))
	end, { primary = true })
	f.addButton:SetPoint("LEFT", host.qty, "RIGHT", 10, 0)
end

local function createRecipeMaterials(pe, host)
	host.materials = pe:CreateReusableTable(host.body, {
		autoFitToScroll = true,
		footer = true,
		emptyTitle = L["No reagents"],
		emptyHint = L["This recipe has no saved reagents."],
		onRowEnter = function(rowFrame, row) pe:ShowItemTooltip(rowFrame, row and row.itemID) end,
		onRowLeave = function() GameTooltip:Hide() end,
	})
	host.materials.frame:SetPoint("TOPLEFT", host.materialsHeading, "BOTTOMLEFT", 0, -6)
	host.materials.frame:SetPoint("BOTTOMRIGHT", host.actions, "TOPRIGHT", 0, 10)
	host.materials:SetColumns({
		pe:CreateItemColumn({ label = L["Reagent"], sortable = false,
			getItemID = function(slot) return slot.itemID end,
			getName = function(slot) return pe:GetItemDisplayName(slot.itemID) end }),
		{ id = "need", label = L["Need"], width = 40, justifyH = "RIGHT", getText = function(slot) return tostring(slot.need) end },
		{ id = "have", label = L["Have"], width = 46, justifyH = "RIGHT", tooltipTitle = L["Have"], tooltipText = L["On all your characters."],
			getText = function(slot)
				if slot.have < slot.need then
					return pe:Colorize(pe:FormatNumberGrouped(slot.have), "danger")
				end
				return pe:FormatNumberGrouped(slot.have)
			end },
		pe:MoneyColumn({ id = "cost", label = L["Cost"], width = 76, sortable = false }),
	})
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
	createRecipeSummary(pe, host)
	createRecipeActions(pe, f, host)
	createRecipeMaterials(pe, host)
	return host
end

-- The fold button and the rail that stands in for the panel while it is folded.
local function createPanelDock(pe, f, pf)
	f.dock = pe:CreatePanelDock({
		panel = f,
		gameWindow = pf,
		setting = "professions.sidePanelExpanded",
		onExpand = function() pe:ScheduleRefreshProfessionCraftEconomyPanel(0.05) end,
	})
	f.dock.collapseButton:SetPoint("RIGHT", f, "TOPRIGHT", -6, -(pe:GetTheme().size.header / 2))
end

-- Title bar: the title, the Recipe / Leveling / Queue switch and the fold button.
local function createPanelHeader(pe, f)
	f.tabQueue = pe:CreateButton(f, L["Queue"], function()
		pe:SetProfessionPanelActiveTab("queue", true)
	end, { small = true })
	f.tabQueue:SetPoint("RIGHT", f.dock.collapseButton, "LEFT", -8, 0)
	f.tabLeveling = pe:CreateButton(f, L["Leveling"], function()
		pe:SetProfessionPanelActiveTab("leveling", true)
	end, { small = true })
	f.tabLeveling:SetPoint("RIGHT", f.tabQueue, "LEFT", 1, 0)
	f.tabInfo = pe:CreateButton(f, L["Recipe"], function()
		pe:SetProfessionPanelActiveTab("info", true)
	end, { small = true })
	f.tabInfo:SetPoint("RIGHT", f.tabLeveling, "LEFT", 1, 0)
	f.title = pe:CreateText(f, "GameFontNormalLarge", "gold")
	local theme = pe:GetTheme()
	f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(theme.size.header / 2) - 1)
	f.title:SetPoint("RIGHT", f.tabInfo, "LEFT", -12, 0)
	f.title:SetText(Tradewright.DISPLAY_NAME)
	local headerRule = f:CreateTexture(nil, "BORDER")
	headerRule:SetPoint("TOPLEFT", 1, -theme.size.header)
	headerRule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	headerRule:SetHeight(1)
	Tradewright:ColorTexture(headerRule, "borderSubtle", 1)
end

-- Footer: when this profession was scanned.
local function createPanelFooter(pe, f)
	local theme = pe:GetTheme()
	f.footer = CreateFrame("Frame", nil, f)
	f.footer:SetPoint("BOTTOMLEFT", 1, 1)
	f.footer:SetPoint("BOTTOMRIGHT", -1, 1)
	f.footer:SetHeight(theme.size.footer)
	local footerRule = f.footer:CreateTexture(nil, "BORDER")
	footerRule:SetPoint("TOPLEFT")
	footerRule:SetPoint("TOPRIGHT")
	footerRule:SetHeight(1)
	Tradewright:ColorTexture(footerRule, "borderSubtle", 1)
	f.footerText = pe:CreateText(f.footer, "GameFontHighlightSmall", "textMuted")
	f.footerText:SetPoint("LEFT", PAD, 0)
	f.footerText:SetPoint("RIGHT", -PAD, 0)
end

function Tradewright:EnsureProfessionCraftEconomyPanel()
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
	f:SetWidth(PANEL_WIDTH)
	self:LayoutProfessionCraftEconomyPanel(f)
	self:StyleWindow(f)
	f:SetClampedToScreen(true)
	createPanelDock(self, f, pf)
	createPanelHeader(self, f)
	createPanelFooter(self, f)

	createRecipeView(self, f)
	self:CreateProfessionQueueView(f)
	self:CreateProfessionLevelingView(f)
	self:SkinTree(f)

	self._professionCraftPanel = f
	self:SetProfessionPanelActiveTab(self:GetSetting("professions.sidePanelTab", "info"), false)
	return f
end

local function missingReagentCount(reagentPlan)
	local missing = 0
	for _, slot in ipairs(reagentPlan or {}) do
		missing = missing + math.max(0, tonumber(slot.purchasedQuantity) or 0)
	end
	return missing
end

local CONFIDENCE_BADGES = {
	missing_sale_price = L["No price"],
	missing_mat_price = L["No price"],
	stale_scan = L["Old scan"],
}

-- Status badge label and tone for a recipe evaluation.
local function recipeBadge(confidence, ev)
	if CONFIDENCE_BADGES[confidence] then
		return CONFIDENCE_BADGES[confidence], "warning"
	elseif ev.canCraftNow then
		return L["Can craft"], "success"
	elseif ev.qualityReachable == false then
		return (ev.concentrationNeeded or ev.concentrationCost) and L["Needs concentration"] or L["Out of reach"], "warning"
	end
	local missing = missingReagentCount(ev.reagentPlan)
	return missing > 0 and (string.format(L["Missing %s"], missing)) or "Missing", "danger"
end

local function moneyOrDash(pe, copper, formatter)
	return copper and formatter(pe, copper) or "-"
end

local function recipeFacts(pe, ev)
	local cut = pe:GetAuctionCut() * 100
	local facts = {
		{ "Return", ev.roi and string.format("%.0f%%", ev.roi) or "-" },
		{ L["Reagents you already own"], string.format("%.0f%%", (ev.coverage or 0) * 100) },
		{ L["Still to buy"], moneyOrDash(pe, ev.outOfPocketMatCost, pe.FormatCopperFull) },
		{ string.format(L["Sale before the %.3g%% auction cut"], cut), moneyOrDash(pe, ev.saleGross, pe.FormatCopperFull) },
	}
	if pe.IS_RETAIL and ev.concentrationNeeded then
		facts[#facts + 1] = { L["Concentration needed"], pe:FormatNumberGrouped(ev.concentrationNeeded) }
	end
	if ev.requiredTargetReagent and ev.requiredTargetReagentItemID then
		facts[#facts + 1] = { L["Target reagent"], pe:GetItemDisplayName(ev.requiredTargetReagentItemID) }
	end
	return facts
end

local function recipeMaterialRows(pe, reagentPlan)
	local materials = {}
	for index, slot in ipairs(reagentPlan or {}) do
		local inv = pe:BuildAccountItemInventoryTotals(slot.itemID)
		materials[#materials + 1] = {
			_rowIdentity = index,
			itemID = slot.itemID,
			need = tonumber(slot.quantityRequired) or 0,
			have = tonumber(inv and inv.total) or 0,
			cost = tonumber(slot.lineCost),
		}
	end
	return materials
end

local function renderRecipeStats(pe, host, ev)
	host.stats.saleAfterCut:SetValues(L["Sale after cut"], moneyOrDash(pe, ev.saleNet, pe.FormatCopperShort))
	host.stats.materials:SetValues(L["Reagents"], moneyOrDash(pe, ev.matCost, pe.FormatCopperShort))
	host.stats.profit:SetValues(L["Profit"], pe:FormatSignedMoney(ev.profit), nil, (tonumber(ev.profit) or 0) < 0 and "danger" or "success")
	pe:LayoutEvenRow(host.statsRow, host.stats, 0, 8)
end

-- Fills the Recipe view from the selected recipe's evaluation.
local function renderProfessionRecipe(pe, panel, ctx)
	local host = panel.infoHost
	local ev = ctx.eval or {}
	host.empty:Hide()
	host.body:Show()
	host.header:SetItem(ev.outputItemID, (ev.recipeName or pe:GetItemDisplayName(ev.outputItemID)) .. rankMarkup(ev.qualityIndex),
		string.format(L["%s · best crafter %s"], tostring(ev.professionName or "?"), tostring(ctx.recommendedCrafterLabel or "-")), ev.outputIcon)
	host.header.badge:SetBadge(recipeBadge(ctx.confidence or "ok", ev))
	renderRecipeStats(pe, host, ev)
	host.facts:SetRows(recipeFacts(pe, ev))
	host.materials:SetRows(recipeMaterialRows(pe, ev.reagentPlan))
	host.materials:Refresh()
	host.materials:SetFooterText(L["Have counts all your characters"], ev.matCost and pe:FormatCopperShort(ev.matCost) or nil)
	panel.footerText:SetText(string.format(L["%s scanned %s"], tostring(ev.professionName or "Profession"), pe:FormatScanTimestamp(ev.scanAt)))
end

local function renderProfessionEmpty(panel, message)
	local host = panel.infoHost
	host.body:Hide()
	host.empty:Show()
	host.empty:SetMessage(L["No recipe to show"], message)
	panel.footerText:SetText("")
end

local REFRESH_THROTTLE_SEC = 0.10
local SELECT_RECIPE_TEXT = L["Select a recipe to see its profit and reagents."]
-- What the empty panel says for each reason EvaluateSelectedProfessionRecipe gives.
local EMPTY_REASON_TEXT = {
	no_data = L["This recipe is not saved yet. It is saved once the recipe list has loaded, or when you close the profession window."],
	no_recipe = SELECT_RECIPE_TEXT,
	not_ready = L["The profession window is still loading."],
	no_eval = L["Profit for this recipe could not be worked out yet. Select it again, or type /tw rescan."],
	no_profession = L["The profession for this recipe could not be found. Type /tw rescan."],
}

function Tradewright:RefreshProfessionSideParts(panel)
	-- Leveling first: a changed route may lower queued crafts, which the Queue view then shows.
	self:RefreshProfessionLevelingView(panel)
	self:RefreshProfessionQueueCard(panel)
	if self.CraftingOrderViewRefreshButtons then
		self:CraftingOrderViewRefreshButtons()
	end
end

-- No recipe to show: a message for the reason, or (Forever, no profit view) no panel at all.
function Tradewright:RenderProfessionPanelEmpty(panel, reason)
	if reason == "not_retail" then
		return hideProfessionPanel(panel)
	end
	self:ShowPanelDock(panel.dock, true)
	renderProfessionEmpty(panel, EMPTY_REASON_TEXT[reason] or SELECT_RECIPE_TEXT)
	self:RefreshProfessionSideParts(panel)
	panel.addButton:SetEnabled(false)
end

function Tradewright:RenderProfessionCraftEconomyPanel()
	local professionsFrame = _G.ProfessionsFrame
	if not professionsFrame or not professionsFrame:IsShown() then
		if self._professionCraftPanel then
			hideProfessionPanel(self._professionCraftPanel)
		end
		self._lastProfessionEvalContext = nil
		return
	end
	local panel = self:EnsureProfessionCraftEconomyPanel()
	if not panel then
		return
	end
	self:LayoutProfessionCraftEconomyPanel(panel)
	-- Folded: only the rail shows, but the side parts still refresh so its counts stay current.
	if not self:IsPanelDockExpanded(panel.dock) then
		self:ShowPanelDock(panel.dock, true)
		return self:RefreshProfessionSideParts(panel)
	end
	self:SetProfessionPanelActiveTab(self.ui and self.ui.professionPanelActiveTab or self:GetSetting("professions.sidePanelTab", "info"), false)
	local context, reason = self:EvaluateSelectedProfessionRecipe()
	self._lastProfessionEvalContext = context
	if not context then
		return self:RenderProfessionPanelEmpty(panel, reason)
	end
	panel.addButton:SetEnabled(true)
	renderProfessionRecipe(self, panel, context)
	self:RefreshProfessionSideParts(panel)
	self:ShowPanelDock(panel.dock, true)
end

--- Redraws the side panel of the profession window; calls closer than REFRESH_THROTTLE_SEC are
--- folded into one unless `force`.
function Tradewright:RefreshProfessionCraftEconomyPanel(force)
	if not self.IS_SUPPORTED or self._refreshingProfessionCraftPanel then
		return
	end
	local now = GetTime and GetTime() or 0
	if not force and self._lastProfessionCraftRefreshAt and (now - self._lastProfessionCraftRefreshAt) < REFRESH_THROTTLE_SEC then
		self:ScheduleRefreshProfessionCraftEconomyPanel(REFRESH_THROTTLE_SEC)
		return
	end
	self._refreshingProfessionCraftPanel = true
	self._lastProfessionCraftRefreshAt = now
	self:RenderProfessionCraftEconomyPanel()
	self._refreshingProfessionCraftPanel = nil
end
