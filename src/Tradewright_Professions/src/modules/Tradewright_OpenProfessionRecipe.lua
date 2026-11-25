local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Reads the open Blizzard profession window (selected recipe, live reagent picks, order form) and queues its recipe.

local ReagentPlan = Tradewright.CraftReagentPlan
local ENCHANTING_VELLUM_ITEM_ID = ReagentPlan.ENCHANTING_VELLUM_ITEM_ID
local enchantGoesOnVellum = ReagentPlan.enchantGoesOnVellum
local classifyCraftReagentSlot = ReagentPlan.classifyCraftReagentSlot
local planEnchantTarget = ReagentPlan.planEnchantTarget
local cloneReagentPlan = ReagentPlan.cloneReagentPlan

-- Prefer OrderView schematic when Crafting Orders tab is showing an order.
function Tradewright:GetOpenProfessionSchematicForm()
	if not self.IS_SUPPORTED then
		return nil
	end
	local pf = _G.ProfessionsFrame
	if not pf then
		return nil
	end
	if self.IS_RETAIL then
		local ordersPage = pf.OrdersPage
		if ordersPage and ordersPage.IsShown and ordersPage:IsShown() then
			local orderView = ordersPage.OrderView
			local orderForm = orderView and orderView.OrderDetails and orderView.OrderDetails.SchematicForm
			if orderForm and (not orderForm.IsShown or orderForm:IsShown()) then
				return orderForm
			end
		end
	end
	local form = pf.CraftingPage and pf.CraftingPage.SchematicForm
	if form and (not form.IsShown or form:IsShown()) then
		return form
	end
	return form
end

function Tradewright:GetOpenCraftingOrder()
	if not self.IS_RETAIL then
		return nil
	end
	local pf = _G.ProfessionsFrame
	local ordersPage = pf and pf.OrdersPage
	if not (ordersPage and ordersPage.IsShown and ordersPage:IsShown()) then
		return nil
	end
	local orderView = ordersPage.OrderView
	local order = orderView and orderView.order
	if type(order) == "table" and tonumber(order.orderID) and tonumber(order.spellID) then
		return order
	end
	return nil
end

-- Build reagent plan from currently selected allocations in Blizzard's transaction.
-- Returns nil when no usable live allocations are available.
function Tradewright:BuildLiveSelectedReagentPlanForOpenRecipe(recipeData)
	if not self.IS_SUPPORTED then
		return nil
	end
	local form = self:GetOpenProfessionSchematicForm()
	if not form or not form.GetTransaction then
		return nil
	end
	local transaction = form:GetTransaction()
	if not transaction or type(transaction.GetAllocations) ~= "function" then
		return nil
	end

	local slots = self:RecipeDataSlots(recipeData)
	if type(slots) ~= "table" or #slots == 0 then
		return nil
	end

	local plan = {}
	for _, slot in ipairs(slots) do
		local slotIndex = slot and slot.slotIndex
		local qty = tonumber(slot and slot.quantityRequired) or 0
		if slotIndex and qty > 0 then
			local allocations = transaction:GetAllocations(slotIndex)
			if type(allocations) == "table" and #allocations > 0 then
				local first = allocations[1]
				local reagent = first and first.GetReagent and first:GetReagent() or nil
				local itemID = reagent and tonumber(reagent.itemID)
				if itemID then
					plan[#plan + 1] = {
						itemID = itemID,
						quantityRequired = qty,
						slotIndex = slotIndex,
						slotClass = classifyCraftReagentSlot(recipeData, slot),
						liveSelected = true,
					}
				end
			end
		end
	end
	if #plan == 0 then
		return nil
	end
	return plan
end

local function recipeDataHasUsableOutput(recipeData)
	if not recipeData then
		return false
	end
	local outs = recipeData.outputs
	if not outs then
		return false
	end
	if tonumber(Tradewright:RecipeOutputsPrimaryItemId(outs)) then
		return true
	end
	for _, variant in ipairs(outs.qualityVariants or {}) do
		if tonumber(variant and variant.itemID) then
			return true
		end
	end
	return false
end

--- Prefer live C_TradeSkillUI data when the profession window is open; else last scanned recipe blob for this character.
function Tradewright:GetLiveOrScannedRecipeDataForOpenProfession(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then
		return nil, nil
	end
	local rd = self:CollectRecipeData(recipeID)
	if rd and recipeDataHasUsableOutput(rd) then
		return rd, "live"
	end
	self:InitDB()
	local ck = self:GetCharacterKey()
	local charData = self.db.characters[ck]
	if not charData then
		return nil, nil
	end
	local profInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	local lineId = profInfo and tonumber(profInfo.professionID or profInfo.skillLineID)
	local professionData = lineId and charData.professions[tostring(lineId)]
	if not professionData or type(professionData.recipes) ~= "table" then
		for _, pdata in pairs(charData.professions or {}) do
			local _, found = self:FindStoredRecipe(pdata, recipeID)
			if found then
				professionData = pdata
				break
			end
		end
	end
	if not professionData or type(professionData.recipes) ~= "table" then
		return nil, nil
	end
	local _, stored = self:FindStoredRecipe(professionData, recipeID)
	if stored then
		local ds = "scan"
		if C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady() then
			ds = "scan_fallback_live"
		end
		return stored, ds
	end
	return nil, nil
end

function Tradewright:GetProfessionDescriptorForOpenRecipe(recipeID)
	recipeID = tonumber(recipeID)
	if not recipeID then
		return nil
	end
	local profByRecipe = C_TradeSkillUI.GetProfessionInfoByRecipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	local targetLine = profByRecipe and tonumber(profByRecipe.professionID or profByRecipe.skillLineID)
	if not targetLine then
		local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
		targetLine = tonumber(baseInfo and (baseInfo.professionID or baseInfo.profession or baseInfo.skillLineID))
	end
	if not targetLine then
		return nil
	end
	for _, desc in ipairs(self:GetPlayerProfessions()) do
		if tonumber(desc.skillLineID) == targetLine then
			return {
				professionIndex = desc.professionIndex,
				skillLineID = desc.skillLineID,
				professionName = desc.professionName,
				currentLevelName = desc.currentLevelName,
				skillLevel = desc.skillLevel,
				maxSkillLevel = desc.maxSkillLevel,
				bonusSkill = desc.bonusSkill,
				icon = desc.icon,
			}
		end
	end
	return {
		skillLineID = targetLine,
		professionName = tostring(profByRecipe and profByRecipe.professionName or "Profession"),
		currentLevelName = "",
		skillLevel = 0,
		maxSkillLevel = 0,
		bonusSkill = 0,
		icon = nil,
	}
end

--- UI may expose a spell/skill-line ability id; scans and C_TradeSkillUI use TradeSkillRecipe id. Prefer info.recipeID when GetRecipeInfo succeeds.
function Tradewright:NormalizeTradeSkillRecipeId(candidate)
	candidate = tonumber(candidate)
	if not candidate or candidate <= 0 then
		return nil
	end
	if C_TradeSkillUI.GetRecipeInfo then
		local info = C_TradeSkillUI.GetRecipeInfo(candidate)
		if info then
			local rid = tonumber(info.recipeID)
			if rid and rid > 0 then
				return rid
			end
		end
	end
	return candidate
end

local function positiveNumber(value)
	value = tonumber(value)
	return value and value > 0 and value or nil
end

function Tradewright:GetOpenProfessionRecipeID()
	if not self.IS_SUPPORTED then
		return nil
	end
	-- Crafting Orders tab: prefer the open order's spell, not the stale Recipes-tab selection.
	local openOrder = self.GetOpenCraftingOrder and self:GetOpenCraftingOrder() or nil
	if openOrder and tonumber(openOrder.spellID) then
		return self:NormalizeTradeSkillRecipeId(openOrder.spellID)
	end
	local form = self.GetOpenProfessionSchematicForm and self:GetOpenProfessionSchematicForm() or nil
	if form then
		if form.GetRecipeInfo then
			local info = form:GetRecipeInfo()
			local recipeID = info and tonumber(info.recipeID)
			if recipeID and recipeID > 0 then
				return self:NormalizeTradeSkillRecipeId(recipeID)
			end
		end
		local transaction = form.GetTransaction and form:GetTransaction() or nil
		local recipeID = self:FirstValueFrom(transaction, { "GetRecipeID", "GetRecipeSchematicID" }, nil, positiveNumber)
			or self:FirstValueFrom(form, nil, { "recipeID", "selectedRecipeID" }, positiveNumber)
		if recipeID then
			return self:NormalizeTradeSkillRecipeId(recipeID)
		end
	end
	if C_TradeSkillUI.GetSelectedRecipeID then
		local selected = tonumber(C_TradeSkillUI.GetSelectedRecipeID())
		if selected and selected > 0 then
			return self:NormalizeTradeSkillRecipeId(selected)
		end
	end
	local page = _G.ProfessionsFrame and _G.ProfessionsFrame.CraftingPage
	local pageRecipeID = self:FirstValueFrom(page, nil, { "selectedRecipeID", "recipeID" }, positiveNumber)
	return pageRecipeID and self:NormalizeTradeSkillRecipeId(pageRecipeID) or nil
end

--- Live evaluation for the recipe selected in Blizzard's profession UI (same rules as Crafts tab).
function Tradewright:EvaluateSelectedProfessionRecipe()
	self:InitDB()
	if not self.IS_SUPPORTED then
		return nil, "not_supported"
	end
	if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then
		return nil, "not_ready"
	end
	local recipeID = self:GetOpenProfessionRecipeID()
	if not recipeID then
		return nil, "no_recipe"
	end

	local recipeData, dataSource = self:GetLiveOrScannedRecipeDataForOpenProfession(recipeID)
	if not recipeData then
		return nil, "no_data", { recipeID = recipeID }
	end

	local professionData = self:GetProfessionDescriptorForOpenRecipe(recipeID)
	if not professionData then
		return nil, "no_profession"
	end

	local ck = self:GetCharacterKey()
	local liveScenario = self:GetOpenProfessionScenario()
	local opts = {
		scenario = liveScenario,
		sourceMode = self:GetSetting("crafts.reagentSourceMode", "owned_first"),
		costBasis = self:GetSetting("crafts.costBasis", "auto"),
		saleBasis = self:GetSetting("crafts.saleBasis", "auto"),
	}
	local livePlan = self:BuildLiveSelectedReagentPlanForOpenRecipe(recipeData)
	if livePlan and #livePlan > 0 then
		opts.reagentPlanOverride = livePlan
	end
	local eval = self:EvaluateCraftScenario(ck, professionData, recipeID, recipeData, opts)
	if not eval then
		return nil, "no_eval"
	end

	local opportunityRow = self:FindCraftOpportunityRowForRecipe(recipeID, eval.outputItemID)
	local recommendedLabel, recommendedReason
	if opportunityRow then
		recommendedLabel, recommendedReason = self:GetCraftRecommendedCrafter(opportunityRow)
	else
		recommendedLabel = self:GetDashboardSidebarCharacterLabel(ck, self.db.characters and self.db.characters[ck], ck)
	end

	local confidence = self:ResolveCraftConfidenceState(eval, dataSource)

	return {
		recipeID = recipeID,
		professionData = professionData,
		characterKey = ck,
		scenario = liveScenario,
		eval = eval,
		opportunityRow = opportunityRow,
		recommendedCrafterLabel = recommendedLabel,
		recommendedCrafterReason = recommendedReason,
		dataSource = dataSource,
		confidence = confidence,
	}, "ok"
end

--- Build an eval context for shopping/queue for a recipe (forces Enchanting Vellum for enchants).
--- `opts`: { skillLineID, skipSelect }. Returns the context and "ok", or nil and a reason.
function Tradewright:BuildProfessionRecipeQueueContext(recipeID, opts)
	self:InitDB()
	opts = opts or {}
	if not self.IS_SUPPORTED then
		return nil, "not_supported"
	end
	recipeID = tonumber(recipeID) or self:GetOpenProfessionRecipeID()
	if not recipeID then
		return nil, "no_recipe"
	end

	if not opts.skipSelect then
		local openID = self:GetOpenProfessionRecipeID()
		if openID ~= recipeID and self.JumpToProfessionRecipe then
			self:JumpToProfessionRecipe(recipeID, opts.skillLineID)
		end
	end

	if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then
		return nil, "not_ready"
	end

	local recipeData, dataSource = self:GetLiveOrScannedRecipeDataForOpenProfession(recipeID)
	if not recipeData then
		return nil, "no_data"
	end

	local professionData = self:GetProfessionDescriptorForOpenRecipe(recipeID)
	if not professionData then
		return nil, "no_profession"
	end

	local ck = self:GetCharacterKey()
	local liveScenario = (self.GetOpenProfessionScenario and self:GetOpenProfessionScenario())
		or self:GetSetting("crafts.scenario", "default")
	local evalOpts = {
		scenario = liveScenario,
		sourceMode = self:GetSetting("crafts.reagentSourceMode", "owned_first"),
		costBasis = self:GetSetting("crafts.costBasis", "auto"),
		saleBasis = self:GetSetting("crafts.saleBasis", "auto"),
		forceEnchantingVellum = true,
		allowMissingOutput = true,
	}
	-- Keep live selections for mandatory mats, but forceEnchantingVellum strips target overrides.
	local livePlan = self:BuildLiveSelectedReagentPlanForOpenRecipe(recipeData)
	if livePlan and #livePlan > 0 then
		evalOpts.reagentPlanOverride = livePlan
	end

	local eval = self:EvaluateCraftScenario(ck, professionData, recipeID, recipeData, evalOpts)
	if not eval then
		-- Fall back to the side-panel eval (same recipe) and force vellum onto its plan.
		local last = self._lastProfessionEvalContext
		if type(last) == "table"
			and tonumber(last.recipeID) == tonumber(recipeID)
			and type(last.eval) == "table"
		then
			eval = last.eval
			if type(eval.reagentPlan) == "table" then
				eval.reagentPlan = cloneReagentPlan(eval.reagentPlan)
			else
				eval.reagentPlan = {}
			end
		else
			return nil, "no_eval"
		end
	end

	-- Where enchants go on a vellum, shopping always assumes one, whichever eval the plan came from.
	if enchantGoesOnVellum(recipeData) and type(eval.reagentPlan) == "table" then
		planEnchantTarget(eval.reagentPlan, recipeData, true)
		eval.requiredTargetReagent = true
		eval.requiredTargetReagentItemID = ENCHANTING_VELLUM_ITEM_ID
		eval.requiredTargetReagentAuto = true
		eval.enchantUsesVellum = true
	end

	local opportunityRow = self:FindCraftOpportunityRowForRecipe(recipeID, eval.outputItemID)
	local recommendedLabel
	if opportunityRow then
		recommendedLabel = select(1, self:GetCraftRecommendedCrafter(opportunityRow))
	else
		recommendedLabel = self:GetDashboardSidebarCharacterLabel(ck, self.db.characters and self.db.characters[ck], ck)
	end

	return {
		recipeID = recipeID,
		professionData = professionData,
		characterKey = ck,
		scenario = liveScenario,
		eval = eval,
		opportunityRow = opportunityRow,
		recommendedCrafterLabel = recommendedLabel,
		dataSource = dataSource,
		confidence = self:ResolveCraftConfidenceState(eval, dataSource),
		recipeName = eval.recipeName,
		professionName = eval.professionName,
		skillLineID = eval.skillLineID or opts.skillLineID,
	}, "ok"
end

--- Add the open (or given) profession recipe to the craft/shopping queue.
--- Enchant recipes always queue Enchanting Vellum as the target reagent.
--- `opts`: { recipeID, skillLineID, quiet }. Returns the queue key, or nil and an error.
function Tradewright:QueueOpenProfessionRecipe(quantity, opts)
	opts = opts or {}
	quantity = math.max(1, math.floor(tonumber(quantity) or 1))
	local recipeID = tonumber(opts.recipeID) or self:GetOpenProfessionRecipeID()
	local ctx, reason = self:BuildProfessionRecipeQueueContext(recipeID, opts)
	if not ctx then
		if not opts.quiet then
			local msg = L["Could not add the recipe to the queue."]
			if reason == "no_recipe" then
				msg = L["Select a recipe first."]
			elseif reason == "no_data" then
				msg = L["No saved data for this recipe — run a profession scan first."]
			elseif reason == "no_eval" then
				msg = L["The reagents of this recipe are not known yet. Try again in a moment."]
			elseif reason == "not_ready" then
				msg = L["Profession UI not ready yet."]
			end
			self:PrintMessage(msg)
		end
		return nil, reason or "failed"
	end

	if not self.AddCraftToQueue then
		return nil, "no_queue"
	end
	local key, err = self:AddCraftToQueue(ctx, quantity)
	if not key then
		if not opts.quiet then
			self:PrintMessage(L["Could not add the recipe to the queue."])
		end
		return nil, err or "add_failed"
	end

	if not opts.quiet then
		local name = ctx.recipeName or ctx.eval and ctx.eval.recipeName or ("#" .. tostring(ctx.recipeID))
		self:PrintMessage(string.format(L["Added %s × %d to the queue."], tostring(name), quantity))
	end
	if self.ScheduleRefreshProfessionCraftEconomyPanel then
		self:ScheduleRefreshProfessionCraftEconomyPanel(0.05)
	end
	return key, nil
end
