-- Run with: lua5.1 tests/test_profession_recipe_view.lua (from Tradewright root)
-- Profession side panel Recipe view: which status badge a recipe gets, the money values,
-- the facts list (Forever vs retail) and the material rows.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addons = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local wowGlobals = {
	GetTime = function()
		return 0
	end,
	ProfessionsFrame = { IsShown = function() return true end },
}
for name, value in pairs(wowGlobals) do
	rawset(_G, name, value)
end

local function recorder()
	local w = {}
	function w:Show() self.shown = true end
	function w:Hide() self.shown = false end
	function w:SetEnabled(v) self.enabled = v end
	function w:SetText(text) self.text = text end
	function w:SetItem(itemID, title, subtitle, icon)
		self.item = { itemID = itemID, title = title, subtitle = subtitle, icon = icon }
	end
	function w:SetBadge(label, tone)
		self.label, self.tone = label, tone
	end
	function w:SetValues(label, value, _, tone)
		self.label, self.value, self.tone = label, value, tone
	end
	function w:SetRows(rows) self.rows = rows end
	function w:Refresh() end
	function w:SetFooterText(text, value)
		self.footer, self.footerValue = text, value
	end
	function w:SetMessage() end
	return w
end

local function newPanel()
	local header = recorder()
	header.badge = recorder()
	return recorder(), {
		empty = recorder(),
		body = recorder(),
		header = header,
		stats = { saleAfterCut = recorder(), materials = recorder(), profit = recorder() },
		statsRow = recorder(),
		facts = recorder(),
		materials = recorder(),
	}
end

local function newAddon(isRetail, ctx)
	local panel, host = newPanel()
	panel.infoHost = host
	panel.footerText = recorder()
	panel.addButton = recorder()
	local pe = { IS_SUPPORTED = true, IS_RETAIL = isRetail, ui = {} }
	local function money(n)
		return "c" .. tostring(n)
	end
	local stubs = {
		GetSetting = function(_, _, default) return default end,
		EnsureProfessionCraftEconomyPanel = function() return panel end,
		LayoutProfessionCraftEconomyPanel = function() end,
		UpdateProfessionPanelToggleButton = function() end,
		RefreshProfessionQueueCard = function() end,
		RefreshProfessionLevelingView = function() end,
		EvaluateSelectedProfessionRecipe = function() return ctx end,
		GetRankMarkup = function(_, rank) return rank and ("|R" .. rank) or "" end,
		GetItemDisplayName = function(_, itemID) return "Item " .. tostring(itemID) end,
		FormatCopperShort = function(_, n) return money(n) end,
		FormatCopperFull = function(_, n) return "full" .. tostring(n) end,
		FormatSignedMoney = function(_, n) return "signed" .. tostring(n) end,
		FormatNumberGrouped = function(_, n) return "n" .. tostring(n) end,
		FormatScanTimestamp = function(_, at) return "at" .. tostring(at) end,
		LayoutEvenRow = function() end,
		GetAuctionCut = function() return 0.05 end,
		BuildAccountItemInventoryTotals = function(_, itemID) return { total = itemID == 10 and 4 or nil } end,
	}
	local chunk, err = loadfile(addons .. "/Tradewright_UI/src/ui/Tradewright_ProfessionCraftPanel.lua")
	assert(chunk, err)
	chunk("Tradewright", pe)
	for name, fn in pairs(stubs) do
		pe[name] = fn
	end
	pe.SetProfessionPanelActiveTab = function() end
	pe.CraftingOrderViewRefreshButtons = nil
	return pe, panel, host
end

local function render(ctx, isRetail)
	local pe, panel, host = newAddon(isRetail, ctx)
	pe:RefreshProfessionCraftEconomyPanel(true)
	return host, panel
end

local function badge(eval, confidence)
	local host = render({ eval = eval, confidence = confidence })
	return host.header.badge.label, host.header.badge.tone
end

local function checkBadge(name, eval, confidence, label, tone)
	local gotLabel, gotTone = badge(eval, confidence)
	check(name, gotLabel == label and gotTone == tone, tostring(gotLabel) .. "/" .. tostring(gotTone))
end

checkBadge("Badge: missing sale price", { canCraftNow = true }, "missing_sale_price", "No price", "warning")
checkBadge("Badge: missing mat price", {}, "missing_mat_price", "No price", "warning")
checkBadge("Badge: old scan", { canCraftNow = true }, "stale_scan", "Old scan", "warning")
checkBadge("Badge: can craft", { canCraftNow = true }, nil, "Can craft", "success")
checkBadge("Badge: needs concentration", { qualityReachable = false, concentrationCost = 30 }, "ok", "Needs concentration", "warning")
checkBadge("Badge: quality out of reach", { qualityReachable = false }, "ok", "Out of reach", "warning")
checkBadge("Badge: missing count sums purchases", { reagentPlan = { { purchasedQuantity = 2 }, { purchasedQuantity = "3" },
	{ purchasedQuantity = -1 }, {} } }, "ok", "Missing 5", "danger")
checkBadge("Badge: missing without purchases", { reagentPlan = {} }, "ok", "Missing", "danger")

local fullEval = {
	outputItemID = 77, recipeName = "Blade", qualityIndex = 3, professionName = "Blacksmithing", outputIcon = 123,
	saleNet = 900, matCost = 400, profit = -50, roi = 12.4, coverage = 0.25, outOfPocketMatCost = 300, saleGross = 1000,
	concentrationNeeded = 1200, requiredTargetReagent = true, requiredTargetReagentItemID = 55, scanAt = 42,
	reagentPlan = {
		{ itemID = 10, quantityRequired = 3, lineCost = 120 },
		{ itemID = 11, quantityRequired = "2" },
	},
}

do
	local host, panel = render({ eval = fullEval, recommendedCrafterLabel = "Alt", confidence = "ok" }, true)
	check("Header: name with rank, profession and crafter", host.header.item.title == "Blade|R3" and host.header.item.itemID == 77
		and host.header.item.subtitle == "Blacksmithing · best crafter Alt" and host.header.item.icon == 123)
	check("Stats: sale and materials", host.stats.saleAfterCut.value == "c900" and host.stats.materials.value == "c400")
	check("Stats: negative profit is danger", host.stats.profit.value == "signed-50" and host.stats.profit.tone == "danger")
	local facts = host.facts.rows
	check("Facts: return, owned share, still to buy, gross", #facts == 6 and facts[1][2] == "12%" and facts[2][2] == "25%"
		and facts[3][2] == "full300" and facts[4][1] == "Sale before the 5% auction cut" and facts[4][2] == "full1000")
	check("Facts: retail concentration", facts[5][1] == "Concentration needed" and facts[5][2] == "n1200")
	check("Facts: target reagent", facts[6][1] == "Target reagent" and facts[6][2] == "Item 55")
	local rows = host.materials.rows
	check("Materials: one row per plan slot", #rows == 2 and rows[1]._rowIdentity == 1 and rows[2]._rowIdentity == 2)
	check("Materials: need, have, cost", rows[1].itemID == 10 and rows[1].need == 3 and rows[1].have == 4 and rows[1].cost == 120)
	check("Materials: missing counts are zero, no cost", rows[2].need == 2 and rows[2].have == 0 and rows[2].cost == nil)
	check("Materials: footer total", host.materials.footer == "Have counts all your characters" and host.materials.footerValue == "c400")
	check("Footer: scan time", panel.footerText.text == "Blacksmithing scanned at42")
	check("Panel: body shown, add enabled", host.body.shown and host.empty.shown == false and panel.addButton.enabled == true)
end

do
	local host = render({ eval = fullEval }, false)
	check("Facts: Forever has no concentration line", #host.facts.rows == 5 and host.facts.rows[5][1] == "Target reagent")
end

do
	local host, panel = render({ eval = { outputItemID = 5, profit = 10 } }, true)
	check("Empty eval: name from item, placeholders", host.header.item.title == "Item 5" and host.stats.saleAfterCut.value == "-"
		and host.stats.materials.value == "-")
	check("Empty eval: subtitle placeholders", host.header.item.subtitle == "? · best crafter -")
	check("Empty eval: positive profit is success", host.stats.profit.tone == "success")
	local facts = host.facts.rows
	check("Empty eval: four facts with placeholders", #facts == 4 and facts[1][2] == "-" and facts[2][2] == "0%" and facts[3][2] == "-"
		and facts[4][2] == "-")
	check("Empty eval: no materials, no footer total", #host.materials.rows == 0 and host.materials.footerValue == nil)
	check("Empty eval: footer default profession", panel.footerText.text == "Profession scanned atnil")
end

do
	local pe = newAddon(true, {})
	local recipeID, order, transaction = 101, nil, nil
	pe.GetOpenProfessionRecipeID = function() return recipeID end
	pe.GetOpenProfessionScenario = function() return "best" end
	pe.GetOpenCraftingOrder = function() return order end
	pe.GetOpenProfessionSchematicForm = function()
		return { GetTransaction = function() return transaction end }
	end
	check("Signature: recipe, scenario, no order", pe:GetProfessionCraftOperationSignature() == "101|best|0")
	order = { orderID = 7 }
	check("Signature: open order id", pe:GetProfessionCraftOperationSignature() == "101|best|7")
	transaction = { IsApplyingConcentration = function() return true end }
	check("Signature: concentration on", pe:GetProfessionCraftOperationSignature() == "101|best|7|conc1")
	transaction = { IsApplyingConcentration = function() return false end }
	check("Signature: concentration off", pe:GetProfessionCraftOperationSignature() == "101|best|7|conc0")
	transaction = {}
	check("Signature: transaction without concentration", pe:GetProfessionCraftOperationSignature() == "101|best|7")
	recipeID = nil
	check("Signature: no recipe open", pe:GetProfessionCraftOperationSignature() == nil)
	pe.IS_SUPPORTED, recipeID = false, 101
	check("Signature: unsupported client", pe:GetProfessionCraftOperationSignature() == nil)
end

-- Showing a recipe that has ranks: the profession window lists it under its first rank
do
	local pe = newAddon(true, {})
	local RANK_ONE, RANK_TWO, UNRANKED = 190868, 190994, 500
	local previousRank = { [RANK_TWO] = RANK_ONE }
	local opened = {}
	rawset(_G, "C_Timer", { After = function() end })
	rawset(_G, "C_TradeSkillUI", {
		GetRecipeInfo = function(recipeID) return { recipeID = recipeID, previousRecipeID = previousRank[recipeID] } end,
		OpenRecipe = function(recipeID) opened[#opened + 1] = recipeID end,
	})
	pe:JumpToProfessionRecipe(RANK_TWO)
	check("Jump: a higher rank opens the first rank", opened[1] == RANK_ONE, opened[1])
	pe:JumpToProfessionRecipe(UNRANKED)
	check("Jump: a recipe without ranks opens as it is", opened[2] == UNRANKED, opened[2])
	previousRank[RANK_ONE] = RANK_TWO
	pe:JumpToProfessionRecipe(RANK_TWO)
	check("Jump: ranks that link in a circle still open a recipe", opened[3] ~= nil)
end

if failed > 0 then
	print(string.format("%d check(s) failed", failed))
	os.exit(1)
end
print("All profession recipe view checks passed")
