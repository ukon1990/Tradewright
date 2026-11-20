local addonName, ProfessionExporter = ...

if not ProfessionExporter.IS_RETAIL then
	return
end

local CraftingOrderTypeNpc = Enum.CraftingOrderType and Enum.CraftingOrderType.Npc

local _craftingOrdersInitPatched

local function craftingOrdersSettings()
	ProfessionExporter:InitDB()
	return ProfessionExporter.db and ProfessionExporter.db.settings and ProfessionExporter.db.settings.craftingOrders
end

function ProfessionExporter:CraftingOrdersPatronKnowledgeDataReady()
	local t = self.CRAFTING_ORDERS_PATRON_KNOWLEDGE_RECIPE_IDS
	if type(t) ~= "table" then
		return false
	end
	return next(t) ~= nil
end

function ProfessionExporter:CraftingOrdersRecipeShouldShow(ordersPage, recipeInfo)
	if not recipeInfo or type(recipeInfo.recipeID) ~= "number" then
		return true
	end
	local rid = recipeInfo.recipeID
	local st = craftingOrdersSettings()
	if not st then
		return true
	end
	if st.hideUnlearned == true and recipeInfo.learned == false then
		return false
	end
	if st.patronKnowledgeOnly == true and ordersPage and CraftingOrderTypeNpc and ordersPage.orderType == CraftingOrderTypeNpc then
		if not self:CraftingOrdersPatronKnowledgeDataReady() then
			return true
		end
		local map = self.CRAFTING_ORDERS_PATRON_KNOWLEDGE_RECIPE_IDS
		return map[rid] == true
	end
	return true
end

local function collectChildren(node)
	local list = {}
	if type(node.EnumerateNodes) == "function" then
		node:EnumerateNodes(function(child)
			list[#list + 1] = child
		end)
	elseif type(node.nodes) == "table" then
		for _, child in ipairs(node.nodes) do
			list[#list + 1] = child
		end
	end
	return list
end

local function pruneCraftingOrdersRecipeTree(rootNode, shouldRemoveRecipe)
	if not rootNode or type(shouldRemoveRecipe) ~= "function" then
		return
	end
	local function walk(node)
		if not node then
			return
		end
		local children = collectChildren(node)
		for _, child in ipairs(children) do
			walk(child)
		end
		local toRemove = {}
		for _, child in ipairs(children) do
			local data = child.GetData and child:GetData()
			if data and data.recipeInfo and shouldRemoveRecipe(data.recipeInfo) then
				toRemove[#toRemove + 1] = child
			end
		end
		for i = #toRemove, 1, -1 do
			local n = toRemove[i]
			if n and type(n.Remove) == "function" then
				n:Remove()
			end
		end
	end
	walk(rootNode)
end

function ProfessionExporter:OnCraftingOrdersGenerateDataProvider(ordersPage, dataProvider)
	if not dataProvider or type(dataProvider.GetRootNode) ~= "function" then
		return
	end
	local st = craftingOrdersSettings()
	local patronActive = st
		and st.patronKnowledgeOnly == true
		and ordersPage
		and CraftingOrderTypeNpc
		and ordersPage.orderType == CraftingOrderTypeNpc
		and self:CraftingOrdersPatronKnowledgeDataReady()
	local hideUL = st and st.hideUnlearned == true
	if not hideUL and not patronActive then
		return
	end
	local root = dataProvider:GetRootNode()
	if not root then
		return
	end
	local pe = ProfessionExporter
	pruneCraftingOrdersRecipeTree(root, function(recipeInfo)
		return not pe:CraftingOrdersRecipeShouldShow(ordersPage, recipeInfo)
	end)
end

function ProfessionExporter:RefreshCraftingOrdersPageRecipeList()
	local pf = _G.ProfessionsFrame
	local op = pf and pf.OrdersPage
	if not op or type(op.Init) ~= "function" or not op.professionInfo then
		return
	end
	op:Init(op.professionInfo)
end

local function ensureCraftingOrdersInitPatch()
	if _craftingOrdersInitPatched then
		return
	end
	local mixin = _G.ProfessionsCraftingOrderPageMixin
	local prof = _G.Professions
	if not mixin or not prof or type(mixin.Init) ~= "function" or type(prof.GenerateCraftingDataProvider) ~= "function" then
		return
	end
	_craftingOrdersInitPatched = true
	local origInit = mixin.Init
	mixin.Init = function(self, professionInfo)
		local oldGen = prof.GenerateCraftingDataProvider
		prof.GenerateCraftingDataProvider = function(professionID, searching, noStripCategories, collapses)
			local dp = oldGen(professionID, searching, noStripCategories, collapses)
			ProfessionExporter:OnCraftingOrdersGenerateDataProvider(self, dp)
			return dp
		end
		local ok, err = pcall(origInit, self, professionInfo)
		prof.GenerateCraftingDataProvider = oldGen
		if not ok then
			error(err)
		end
	end
end

local filterBarFrame

local function syncFilterBarFromSettings()
	if not filterBarFrame then
		return
	end
	local pe = ProfessionExporter
	local hideUnlearned = pe:GetSetting("craftingOrders.hideUnlearned", false) == true
	local patronOnly = pe:GetSetting("craftingOrders.patronKnowledgeOnly", false) == true
	if filterBarFrame.cbHideUnlearned then
		filterBarFrame.cbHideUnlearned:SetChecked(hideUnlearned)
	end
	if filterBarFrame.cbPatronKnowledge then
		filterBarFrame.cbPatronKnowledge:SetChecked(patronOnly)
	end
end

local function updatePatronCheckboxState()
	if not filterBarFrame or not filterBarFrame.cbPatronKnowledge then
		return
	end
	local pf = _G.ProfessionsFrame
	local op = pf and pf.OrdersPage
	local isNpc = op and CraftingOrderTypeNpc and op.orderType == CraftingOrderTypeNpc
	local hasData = ProfessionExporter:CraftingOrdersPatronKnowledgeDataReady()
	filterBarFrame.cbPatronKnowledge:SetEnabled(isNpc and hasData)
	local lab = filterBarFrame.cbPatronKnowledgeLabel
	if lab and lab.SetTextColor then
		local theme = ProfessionExporter:GetTheme()
		local color = (not isNpc and theme.textDisabled) or (not hasData and theme.warning) or theme.textPrimary
		lab:SetTextColor(color.r, color.g, color.b)
	end
end

function ProfessionExporter:EnsureCraftingOrdersFilterBar()
	if filterBarFrame then
		updatePatronCheckboxState()
		return filterBarFrame
	end
	local pf = _G.ProfessionsFrame
	local browse = pf and pf.OrdersPage and pf.OrdersPage.BrowseFrame
	if not browse then
		return nil
	end
	local f = CreateFrame("Frame", addonName .. "CraftingOrdersFilterBar", browse)
	f:SetHeight(24)
	if browse.RecipeList then
		f:SetPoint("BOTTOMLEFT", browse.RecipeList, "TOPLEFT", -2, 6)
		f:SetPoint("BOTTOMRIGHT", browse.RecipeList, "TOPRIGHT", 2, 6)
	else
		f:SetPoint("TOPLEFT", browse, "TOPLEFT", 6, -4)
		f:SetPoint("TOPRIGHT", browse, "TOPRIGHT", -6, -4)
	end

	local y = -2
	local cb1 = CreateFrame("CheckButton", addonName .. "COHideUnlearned", f, "UICheckButtonTemplate")
	cb1:SetPoint("TOPLEFT", 0, y)
	local t1 = _G[cb1:GetName() .. "Text"]
	if t1 then
		t1:SetText("Hide unlearned recipes")
	end
	cb1:SetScript("OnClick", function(self)
		ProfessionExporter:SetSetting("craftingOrders.hideUnlearned", self:GetChecked() == true)
		ProfessionExporter:RefreshCraftingOrdersPageRecipeList()
	end)

	local cb2 = CreateFrame("CheckButton", addonName .. "COPatronKnowledge", f, "UICheckButtonTemplate")
	local t2 = _G[cb2:GetName() .. "Text"]
	if t2 then
		t2:SetText("Only recipes that give knowledge")
	end
	ProfessionExporter:SkinCheckButton(cb1)
	ProfessionExporter:SkinCheckButton(cb2)
	cb2:SetPoint("LEFT", cb1, "RIGHT", (t1 and t1:GetStringWidth() or 140) + 18, 0)
	cb2:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local theme = ProfessionExporter:GetTheme()
		GameTooltip:SetText("Only recipes that give knowledge", 1, 1, 1)
		GameTooltip:AddLine("Works on the Patron orders tab. Uses the recipe list in the addon's data file; when that list is empty, it does nothing.",
			theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, true)
		GameTooltip:Show()
	end)
	cb2:SetScript("OnLeave", GameTooltip_Hide)
	cb2:SetScript("OnClick", function(self)
		ProfessionExporter:SetSetting("craftingOrders.patronKnowledgeOnly", self:GetChecked() == true)
		ProfessionExporter:RefreshCraftingOrdersPageRecipeList()
	end)

	f.cbHideUnlearned = cb1
	f.cbPatronKnowledge = cb2
	f.cbPatronKnowledgeLabel = t2
	filterBarFrame = f

	ProfessionExporter:SyncCraftingOrdersFilterBarFromSettings()
	return f
end

function ProfessionExporter:SyncCraftingOrdersFilterBarFromSettings()
	syncFilterBarFromSettings()
	updatePatronCheckboxState()
end

function ProfessionExporter:InitCraftingOrdersFilters()
	ensureCraftingOrdersInitPatch()
	local mixin = _G.ProfessionsCraftingOrderPageMixin
	if mixin and type(mixin.SetCraftingOrderType) == "function" and not mixin.__peCraftingOrdersTypeHooked then
		mixin.__peCraftingOrdersTypeHooked = true
		hooksecurefunc(mixin, "SetCraftingOrderType", function()
			C_Timer.After(0, function()
				updatePatronCheckboxState()
			end)
		end)
	end
	if mixin and type(mixin.OnShow) == "function" and not mixin.__peCraftingOrdersOnShowHooked then
		mixin.__peCraftingOrdersOnShowHooked = true
		hooksecurefunc(mixin, "OnShow", function(self)
			C_Timer.After(0, function()
				ProfessionExporter:EnsureCraftingOrdersFilterBar()
				ProfessionExporter:SyncCraftingOrdersFilterBarFromSettings()
			end)
		end)
	end
	if ProfessionExporter.InitCraftingOrdersMaterialsHooks then
		ProfessionExporter:InitCraftingOrdersMaterialsHooks()
	end
end
