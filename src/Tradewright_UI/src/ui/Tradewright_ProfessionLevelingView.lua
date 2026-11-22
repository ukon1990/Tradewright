local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Leveling view of the profession side panel: the cheapest route from the current skill as a list of
-- steps, with totals, the choice of what crafted items count for, and a Queue button per step that
-- puts the step's crafts in the craft queue. Buying happens from the Queue view.

local SkillUpLogic = Tradewright.SkillUpLogic

local TALL_ROW = 36
local STATS_ROW_HEIGHT = 58
local SECTION_GAP = 10

local GIVE_BACK_OPTIONS = {
	{ value = "vendor", label = L["Sell to vendor"] },
	{ value = "auction", label = L["Sell at auction"] },
	{ value = "none", label = L["Worth nothing"] },
}
local RECIPE_SCOPE_OPTIONS = {
	{ value = "trainer", label = L["Trainer recipes first"] },
	{ value = "all", label = L["All recipes"] },
	{ value = "known", label = L["Known recipes only"] },
}
local GIVE_BACK_STAT_LABEL = { vendor = L["Sold to vendor"], auction = L["Sold at auction"], none = L["Crafted items"] }

-- Title and hint of the empty table, per reason GetLevelingRoute gives for having no route.
local EMPTY_TEXT = {
	no_data = { L["Profession not scanned yet"], L["Press Scan on the Recipe view, then come back."] },
	unsupported = { L["Not available here"], L["This game version does not report when recipes stop giving skill."] },
	no_prices = { L["No prices for a route yet"],
		L["No recipe that can still give skill has a price for all its reagents. Run a full scan at the auction house."] },
	finished = { L["Nothing left to level"], L["None of this profession's recipes can give a skill point any more."] },
}

local function loadingNote()
	local _, reason, progress = Tradewright:GetOpenProfessionLevelingRoute()
	if reason == "not_ready" and progress then
		return string.format(L["Working out the route · %d of %d recipes priced"], progress.done, progress.total)
	end
	return nil
end

-- Whether every craft of the step is sure to give a point, so its craft count is exact.
local function craftCountIsExact(step)
	return not step.estimated and SkillUpLogic.SkillUpChance(step.candidate.bounds, step.toSkill - 1) >= 1
end

-- "an unknown creature" stands in until the creature is met with its name showing.
local function dropSourceName(dropSource)
	return dropSource.name or L["an unknown creature"]
end

-- The skill needed to learn a recipe is only known once a trainer has been seen teaching it; the
-- trainer's price is in the row's tooltip.
local function learnSourceText(pe, candidate)
	if candidate.source == "trainer" then
		return string.format(L["trainer, skill %d"], candidate.learnSkill or 0)
	elseif candidate.source == "vendor" then
		return L["vendor, "] .. pe:FormatCopperShort(candidate.learnCost or 0)
	elseif candidate.source == "drop" then
		return L["drops from "] .. dropSourceName(candidate.dropSource)
	end
	return L["source unknown"]
end

local function craftStepDetail(pe, step, queued, isNextStep)
	-- "~" for an expected count; the detail line has little room at this panel width.
	local parts = { string.format(craftCountIsExact(step) and L["%d crafts"] or L["~%d crafts"], step.crafts) }
	if isNextStep then
		parts[#parts + 1] = L["next step"]
	end
	if queued > 0 then
		parts[#parts + 1] = string.format(L["%d in queue"], queued)
	end
	if not step.learned then
		parts[#parts + 1] = learnSourceText(pe, step.candidate)
	end
	return table.concat(parts, " · ")
end

-- What the row's last column offers: "queue" or "learn" (buttons), or "queued" (a badge).
local function craftStepAction(step, queued)
	if not step.learned then
		return "learn"
	end
	return queued >= step.crafts and "queued" or "queue"
end

-- Who to go to for a recipe not learned: the trainers teaching it, else the vendors selling it.
local function learnPlaces(candidate)
	if next(candidate.trainers or {}) then
		return candidate.trainers, false
	end
	return candidate.vendors or {}, true
end

-- Why a recipe cannot be learned right now: "no_trainer" (no trainer or vendor seen with it),
-- "skill" (the trainer asks for more skill than the player has), or nil when it can or is already
-- known. A vendor recipe's skill is an estimate, so it never blocks.
local function learnBlockedBy(route, step)
	local candidate = step.candidate
	if step.learned then
		return nil
	elseif not next((learnPlaces(candidate))) then
		return "no_trainer"
	elseif candidate.source == "trainer" and (candidate.learnSkill or 0) > route.fromSkill then
		return "skill"
	end
	return nil
end

-- Why the Trainer button of a rank step is off: "no_trainer" (none seen offering the rank), "skill"
-- (the rank asks for more skill than the player has), or nil when it can show the way.
local function rankBlockedBy(route)
	local nextRank = route.nextRank
	if not (nextRank and next(nextRank.trainers or {})) then
		return "no_trainer"
	elseif (nextRank.skillRequired or 0) > route.fromSkill then
		return "skill"
	end
	return nil
end

local function rankCapRow(route, step, index, isNextStep)
	local nextRank = route.nextRank
	local detail = nextRank and string.format(L["%s · skill %d"], nextRank.name, nextRank.skillRequired or 0)
		or string.format(L["at a %s trainer"], route.professionName or "profession")
	return {
		_rowIdentity = index, kind = "rankCap", route = route, skillText = tostring(step.skill), name = L["Train the next rank"],
		detailText = detail .. (isNextStep and L[" · next step"] or ""),
		action = "trainer", learnBlockedBy = rankBlockedBy(route),
	}
end

--- One table row for a route step. `isNextStep` marks the step the player is on.
function Tradewright:LevelingStepRow(route, step, index, isNextStep)
	if step.kind == "rankCap" then
		return rankCapRow(route, step, index, isNextStep)
	end
	local queued = self:GetLevelingQueuedQuantity(route, step.recipeID)
	return {
		_rowIdentity = index, kind = "craft", step = step, route = route, name = step.name or "?",
		skillText = string.format("%d–%d", step.fromSkill, step.toSkill),
		detailText = craftStepDetail(self, step, queued, isNextStep),
		cost = route.giveBackMode == "none" and step.materials or step.net,
		action = craftStepAction(step, queued),
		learnBlockedBy = learnBlockedBy(route, step),
	}
end

local function routeRows(pe, route)
	local rows = {}
	for index, step in ipairs(route.steps) do
		rows[index] = pe:LevelingStepRow(route, step, index, index == 1)
	end
	return rows
end

local function stepNameCell(pe)
	return function(rowFrame)
		local cell = CreateFrame("Frame", nil, rowFrame)
		cell.name = pe:CreateText(cell, "GameFontHighlightSmall")
		cell.name:SetPoint("BOTTOMLEFT", cell, "LEFT", 5, 1)
		cell.name:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
		cell.name:SetWordWrap(false)
		cell.detail = pe:CreateText(cell, "GameFontHighlightSmall", "textMuted")
		cell.detail:SetPoint("TOPLEFT", cell, "LEFT", 5, -1)
		cell.detail:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
		cell.detail:SetWordWrap(false)
		return cell
	end
end

local function actionCell(pe)
	return function(rowFrame)
		local cell = CreateFrame("Frame", nil, rowFrame)
		cell.button = pe:CreateButton(cell, L["Queue"], nil, { small = true, width = 52 })
		cell.button:SetPoint("RIGHT", -4, 0)
		cell.badge = pe:CreateBadge(cell)
		cell.badge:SetPoint("RIGHT", -4, 0)
		return cell
	end
end

-- The button of a step by its action: its label and what a click does.
local ACTION_BUTTON = {
	queue = { label = L["Queue"], onClick = function(pe, row)
		pe:QueueLevelingStep(row.route, row.step)
	end },
	learn = { label = L["Learn"], onClick = function(pe, row)
		pe:ShowRecipeTrainerWaypoint(row.name, learnPlaces(row.step.candidate))
	end },
	trainer = { label = L["Trainer"], onClick = function(pe, row)
		pe:ShowRecipeTrainerWaypoint(row.route.nextRank.name, row.route.nextRank.trainers)
	end },
}

local function updateActionCell(pe, cell, row)
	local action = ACTION_BUTTON[row.action]
	cell.button:SetShown(action ~= nil)
	cell.badge:SetBadge(row.action == "queued" and "Queued" or nil, "success")
	if action then
		cell.button:SetText(action.label)
		cell.button:SetEnabled(row.learnBlockedBy == nil)
		cell.button:SetScript("OnClick", function()
			action.onClick(pe, row)
		end)
	end
end

local function routeColumns(pe)
	local warning = pe:GetTheme().warning
	return {
		{ id = "skill", label = L["Skill"], width = 58, getText = function(row) return row.skillText end },
		{ id = "recipe", label = L["Recipe"], width = 100, flex = 1, minWidth = 90, createCell = stepNameCell(pe),
			updateCell = function(cell, row)
				cell.name:SetText(row.name)
				if row.kind == "rankCap" then
					cell.name:SetTextColor(warning.r, warning.g, warning.b)
				else
					cell.name:SetTextColor(1, 1, 1)
				end
				cell.detail:SetText(row.detailText)
			end },
		{ id = "cost", label = L["Cost"], width = 92, justifyH = "RIGHT",
			getText = function(row) return row.cost and pe:FormatCopperShort(row.cost) or "" end },
		{ id = "action", label = "", width = 62, createCell = actionCell(pe),
			updateCell = function(cell, row) updateActionCell(pe, cell, row) end },
	}
end

local function addMoneyLine(pe, label, copper)
	local muted = pe:GetTheme().textMuted
	GameTooltip:AddDoubleLine(label, pe:FormatCopperShort(copper), muted.r, muted.g, muted.b, 1, 1, 1)
end

local function addFactLine(pe, label, value)
	local muted = pe:GetTheme().textMuted
	GameTooltip:AddDoubleLine(label, value, muted.r, muted.g, muted.b, 1, 1, 1)
end

local function addMaterialLines(pe, candidate)
	for _, reagent in ipairs(candidate.evaluation and candidate.evaluation.reagentPlan or {}) do
		local quantity = tonumber(reagent.quantityRequired) or 1
		local label = string.format("%d %s", quantity, pe:GetItemDisplayName(reagent.itemID))
		if reagent.priceUnit then
			addMoneyLine(pe, label, reagent.priceUnit * quantity)
		else
			addFactLine(pe, label, "-")
		end
	end
	addMoneyLine(pe, L["Reagents per craft"], candidate.materialCost)
end

-- Under a recipe not learned: where it comes from, and whether Learn can show the way now.
local LEARN_HINT = {
	no_trainer = L["No trainer or vendor has been seen with it. Recipes show up here once seen at a vendor or in loot."],
	skill = L["Your skill is too low to learn it yet."],
}

local function learnText(pe, candidate)
	if candidate.source == "trainer" then
		return string.format(L["Not learned yet. Trainer: %s, needs skill %d."],
			pe:FormatCopperShort(candidate.learnCost or 0), candidate.learnSkill or 0)
	elseif candidate.source == "vendor" then
		return string.format(L["Not learned yet. A vendor sells the recipe for %s."], pe:FormatCopperShort(candidate.learnCost or 0))
	elseif candidate.source == "drop" then
		local drop = candidate.dropSource
		return string.format(L["Not learned yet. The recipe drops from %s (%d of %d loots)."], dropSourceName(drop), drop.held, drop.opened)
	end
	return L["Not learned yet. Where it comes from is not known."]
end

local function addLearnLines(pe, row)
	local candidate, theme = row.step.candidate, pe:GetTheme()
	GameTooltip:AddLine(learnText(pe, candidate), theme.accent.r, theme.accent.g, theme.accent.b, true)
	GameTooltip:AddLine(LEARN_HINT[row.learnBlockedBy] or L["Press Learn to show the way to the nearest one."],
		theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, true)
end

local function percentText(chance, estimated)
	return string.format(estimated and L["about %d%%"] or "%d%%", math.floor(chance * 100 + 0.5))
end

-- Under a rank step: whether the Trainer button can show the way, or why not.
local RANK_HINT = {
	no_trainer = L["No trainer has been seen offering this rank. Higher ranks are taught by few trainers; "]
		.. L["open one that does and it is remembered."],
	skill = L["Your skill is too low to train this rank yet."],
}

-- "Karolek in Orgrimmar" for each trainer seen offering the rank.
local function addRankTrainerLines(pe, trainers)
	for trainerName, place in pairs(trainers or {}) do
		local zone = place.zone and place.zone ~= "" and (" in " .. place.zone) or ""
		addFactLine(pe, L["Taught by"], trainerName .. zone)
	end
end

local function showRankTooltip(pe, rowFrame, row)
	local nextRank, muted = row.route.nextRank, pe:GetTheme().textMuted
	GameTooltip:SetOwner(rowFrame, "ANCHOR_LEFT")
	GameTooltip:SetText(nextRank and nextRank.name or row.name, 1, 0.82, 0)
	GameTooltip:AddLine(string.format(L["Your skill stops at %s until you train the next rank."], row.skillText), muted.r, muted.g, muted.b, true)
	if nextRank then
		addFactLine(pe, L["Needs skill"], tostring(nextRank.skillRequired or 0))
		addMoneyLine(pe, "Costs", nextRank.cost or 0)
		addRankTrainerLines(pe, nextRank.trainers)
	end
	GameTooltip:AddLine(RANK_HINT[row.learnBlockedBy] or L["Press Trainer to show the way to the nearest one."], muted.r, muted.g, muted.b, true)
	GameTooltip:Show()
end

local function showStepTooltip(pe, rowFrame, row)
	if row and row.kind == "rankCap" then
		return showRankTooltip(pe, rowFrame, row)
	end
	local step = row and row.step
	if not step then
		return
	end
	local candidate = step.candidate
	GameTooltip:SetOwner(rowFrame, "ANCHOR_LEFT")
	GameTooltip:SetText(row.name, 1, 0.82, 0)
	GameTooltip:AddLine(string.format(L["Skill %d to %d · %s"], step.fromSkill, step.toSkill, row.detailText), 0.6, 0.63, 0.67, true)
	addMaterialLines(pe, candidate)
	if candidate.vendorGiveBack then
		addMoneyLine(pe, L["Sells to a vendor for"], candidate.vendorGiveBack)
	end
	if (step.reusedQuantity or 0) > 0 then
		addMoneyLine(pe, string.format(L["%d used as a reagent by later steps, saving"], step.reusedQuantity), step.reuseValue)
	end
	addFactLine(pe, string.format(L["Skill-up chance at %d"], step.fromSkill),
		percentText(SkillUpLogic.SkillUpChance(candidate.bounds, step.fromSkill), step.estimated))
	addFactLine(pe, string.format(L["Skill-up chance at %d"], step.toSkill - 1),
		percentText(SkillUpLogic.SkillUpChance(candidate.bounds, step.toSkill - 1), step.estimated))
	addFactLine(pe, L["Turns grey at"], tostring(candidate.bounds.greyStart))
	if not step.learned then
		addLearnLines(pe, row)
	end
	GameTooltip:Show()
end

local function refreshPanel(pe)
	pe:RefreshProfessionCraftEconomyPanel(true)
end

-- Profession name, skill, a bar from the current skill to the route's end, and the rank-cap badge.
local function createProgressLine(pe, host)
	local theme = pe:GetTheme()
	local line = CreateFrame("Frame", nil, host)
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(18)
	host.professionText = pe:CreateText(line, "GameFontHighlightSmall")
	host.professionText:SetPoint("LEFT")
	host.rankCapBadge = pe:CreateBadge(line)
	host.rankCapBadge:SetPoint("RIGHT")
	host.endSkillText = pe:CreateText(line, "NumberFontNormalSmall", "textPrimary", "RIGHT")
	host.endSkillText:SetPoint("RIGHT", host.rankCapBadge, "LEFT", -8, 0)
	host.skillBar = CreateFrame("StatusBar", nil, line)
	host.skillBar:SetHeight(10)
	host.skillBar:SetPoint("LEFT", host.professionText, "RIGHT", 8, 0)
	host.skillBar:SetPoint("RIGHT", host.endSkillText, "LEFT", -8, 0)
	host.skillBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	host.skillBar:SetStatusBarColor(theme.tick.r, theme.tick.g, theme.tick.b)
	local barBackground = host.skillBar:CreateTexture(nil, "BACKGROUND")
	barBackground:SetAllPoints()
	barBackground:SetColorTexture(theme.surface2.r, theme.surface2.g, theme.surface2.b, 1)
	return line
end

local function createControls(pe, host, above)
	local controls = CreateFrame("Frame", nil, host)
	controls:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_GAP)
	controls:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -SECTION_GAP)
	controls:SetHeight(26)
	host.giveBackDropdown = pe:CreateSingleSelectDropdown(controls, {
		width = 150, options = GIVE_BACK_OPTIONS, tooltip = L["What the items you craft while leveling are worth."],
		getValue = function() return pe:GetLevelingSettings().giveBackMode end,
		setValue = function(value) pe:SetSetting("professions.leveling.giveBack", value) end,
		onChanged = function() refreshPanel(pe) end,
	})
	host.giveBackDropdown:SetPoint("LEFT")
	host.recipeScopeDropdown = pe:CreateSingleSelectDropdown(controls, {
		width = 150, options = RECIPE_SCOPE_OPTIONS,
		tooltip = L["Trainer recipes first: recipes you know and ones a trainer teaches; others only where none of those gives skill. "]
			.. L["Trainer recipes are known after you have opened a trainer of this profession."],
		getValue = function() return pe:GetLevelingSettings().recipeScope end,
		setValue = function(value) pe:SetSetting("professions.leveling.recipes", value) end,
		onChanged = function() refreshPanel(pe) end,
	})
	host.recipeScopeDropdown:SetPoint("RIGHT")
	return controls
end

-- The skill typed in the "queue up to" box, kept between the current skill and the route's end.
-- Empty or not a number: the current rank's cap, which is as far as crafting gets without a trainer.
local function queueTargetSkill(host, route)
	local typed = tonumber(host.queueToSkillBox:GetText())
	local target = typed or route.rankCap or route.toSkill
	return math.max(route.fromSkill, math.min(target, route.toSkill))
end

local function queueRouteUpToTarget(pe, host)
	local route = pe:GetOpenProfessionLevelingRoute()
	if not route then
		return
	end
	local target = queueTargetSkill(host, route)
	local added = pe:QueueLevelingRange(route, target)
	pe:PrintMessage(added > 0 and string.format(L["Queued %d crafts to reach %s skill %d."], added, route.professionName or "", target)
		or string.format(L["The route to skill %d is already in the queue."], target))
end

-- "Queue the route up to skill [150] [Queue]".
local function createQueueRange(pe, host, above)
	local row = CreateFrame("Frame", nil, host)
	row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_GAP)
	row:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -SECTION_GAP)
	row:SetHeight(26)
	local label = pe:CreateText(row, "GameFontHighlightSmall", "textMuted")
	label:SetPoint("LEFT")
	label:SetText(L["Queue the route up to skill"])
	host.queueToSkillBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	host.queueToSkillBox:SetSize(40, 22)
	host.queueToSkillBox:SetPoint("LEFT", label, "RIGHT", 12, 0)
	host.queueToSkillBox:SetAutoFocus(false)
	host.queueToSkillBox:SetNumeric(true)
	host.queueToSkillBox:SetMaxLetters(3)
	host.queueToSkillBox:SetJustifyH("RIGHT")
	host.queueToSkillBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	pe:SkinEditBox(host.queueToSkillBox)
	host.queueRangeButton = pe:CreateButton(row, L["Queue"], function() queueRouteUpToTarget(pe, host) end, {
		tooltip = L["Adds every step up to that skill to the craft queue. Recipes you still have to learn are included and marked."],
	})
	host.queueRangeButton:SetPoint("LEFT", host.queueToSkillBox, "RIGHT", 10, 0)
	return row
end

local function createRouteTable(pe, host, above)
	host.heading = pe:CreateHeading(host, L["Cheapest route"])
	host.heading:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_GAP)
	host.heading:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -SECTION_GAP)
	host.routeTable = pe:CreateReusableTable(host, {
		rowHeight = TALL_ROW, autoFitToScroll = true, footer = true,
		onRowClick = function(_, row)
			if row.step then
				pe:JumpToProfessionRecipe(row.step.recipeID, row.route.skillLineID)
			end
		end,
		onRowEnter = function(rowFrame, row) showStepTooltip(pe, rowFrame, row) end,
		onRowLeave = function() GameTooltip:Hide() end,
	})
	host.routeTable.frame:SetPoint("TOPLEFT", host.heading, "BOTTOMLEFT", 0, -6)
	host.routeTable.frame:SetPoint("BOTTOMRIGHT")
	host.routeTable:SetColumns(routeColumns(pe))
end

function Tradewright:CreateProfessionLevelingView(panel)
	local host = CreateFrame("Frame", nil, panel)
	host:SetPoint("TOPLEFT", panel.infoHost, "TOPLEFT")
	host:SetPoint("BOTTOMRIGHT", panel.infoHost, "BOTTOMRIGHT")
	host:Hide()
	panel.levelingHost = host
	local progressLine = createProgressLine(self, host)
	host.statsRow = CreateFrame("Frame", nil, host)
	host.statsRow:SetPoint("TOPLEFT", progressLine, "BOTTOMLEFT", 0, -SECTION_GAP)
	host.statsRow:SetPoint("TOPRIGHT", progressLine, "BOTTOMRIGHT", 0, -SECTION_GAP)
	host.statsRow:SetHeight(STATS_ROW_HEIGHT)
	host.stats = self:CreateStats(host.statsRow, { "materials", "giveBack", "net" })
	host.statsRow:SetScript("OnSizeChanged", function()
		self:LayoutEvenRow(host.statsRow, host.stats, 0, 8)
	end)
	createRouteTable(self, host, createQueueRange(self, host, createControls(self, host, host.statsRow)))
	-- The route is only worked out while this view shows, so it is redrawn when switched to.
	host:SetScript("OnShow", function()
		self:RefreshProfessionLevelingView(panel)
	end)
	return host
end

local function renderProgressOfRoute(host, route, professionData)
	local rankCap = tonumber(professionData.maxSkillLevel)
	local crossesRankCap = rankCap and route.toSkill > rankCap
	host.professionText:SetText(string.format("%s  %d", professionData.professionName or "", route.fromSkill))
	host.endSkillText:SetText(tostring(route.toSkill))
	host.rankCapBadge:SetBadge(crossesRankCap and string.format(L["Rank cap %d"], rankCap) or nil, "warning")
	host.skillBar:SetMinMaxValues(0, math.max(1, route.toSkill))
	host.skillBar:SetValue(route.fromSkill)
end

-- Without a route the line still names the profession and its skill; the bar stays empty.
local function renderProgressWithoutRoute(host, professionData)
	host.professionText:SetText(string.format("%s  %d", professionData.professionName or "", tonumber(professionData.skillLevel) or 0))
	host.endSkillText:SetText("")
	host.rankCapBadge:SetBadge(nil)
	host.skillBar:SetMinMaxValues(0, 1)
	host.skillBar:SetValue(0)
end

local function renderStats(pe, host, route)
	local totals = route and route.totals
	local mode = route and route.giveBackMode or pe:GetLevelingSettings().giveBackMode
	local function money(copper)
		return totals and pe:FormatCopperShort(copper) or "-"
	end
	local giveBackText = mode == "none" and L["not counted"] or money(totals and totals.giveBack)
	host.stats.materials:SetValues(L["Reagents"], money(totals and totals.materials))
	host.stats.giveBack:SetValues(GIVE_BACK_STAT_LABEL[mode] or GIVE_BACK_STAT_LABEL.none, giveBackText)
	host.stats.net:SetValues(L["Net cost"], money(totals and totals.net), nil, "gold")
	pe:LayoutEvenRow(host.statsRow, host.stats, 0, 8)
end

-- Left and right text of the table footer: step count and what was left out, and the route's cost.
local function routeFooterTexts(pe, route)
	if not route then
		return "", nil
	end
	local left = string.format(L["%d steps"], #route.steps)
	if route.skippedForPrice > 0 then
		left = left .. string.format(L[" · %d recipes without a price"], route.skippedForPrice)
	end
	return left, pe:FormatCopperShort(route.giveBackMode == "none" and route.totals.materials or route.totals.net)
end

-- Everything a row shows, as one string: two lists of rows with the same text draw the same.
local function rowsSignature(rows, reason)
	local parts = { tostring(reason) }
	for index, row in ipairs(rows) do
		parts[index + 1] = table.concat({ row.skillText, row.name, row.detailText, tostring(row.cost), tostring(row.action), tostring(row.learnBlockedBy) }, "\031")
	end
	return table.concat(parts, "\030")
end

-- The panel refreshes on every craft and bag change. The table is only given new rows when what it
-- shows has changed, so it does not flicker in between.
local function renderRoute(pe, host, route, reason)
	local routeTable = host.routeTable
	local rows = route and routeRows(pe, route) or {}
	local signature = rowsSignature(rows, reason)
	if signature == host.shownSignature then
		return
	end
	host.shownSignature = signature
	local emptyText = EMPTY_TEXT[reason] or EMPTY_TEXT.no_data
	routeTable:SetEmptyText(emptyText[1], emptyText[2])
	routeTable:SetRows(rows)
	routeTable:SetLoading(reason == "not_ready" and loadingNote or nil)
	routeTable:Refresh()
	routeTable:SetFooterText(routeFooterTexts(pe, route))
end

-- The box starts at the current rank's cap; what the player typed is kept.
local function renderQueueRange(host, route)
	host.queueRangeButton:SetEnabled(route ~= nil)
	if route and host.queueToSkillBox:GetText() == "" then
		host.queueToSkillBox:SetText(tostring(math.min(route.rankCap or route.toSkill, route.toSkill)))
	end
end

-- The stored data of the profession whose window is open, or an empty table.
local function openProfessionData(pe)
	local characterData = pe.db.characters and pe.db.characters[pe:GetCharacterKey()] or {}
	local skillLineID = pe:GetState().liveProfessionSkillLineID
	return characterData.professions and characterData.professions[tostring(skillLineID)] or {}
end

--- Redraws the Leveling view. While it is hidden the route is still kept up when the craft queue
--- holds route crafts, so a skill-up that came early lowers them.
function Tradewright:RefreshProfessionLevelingView(panel)
	local host = panel and panel.levelingHost
	if not host or not self.GetOpenProfessionLevelingRoute then
		return
	end
	if not host:IsShown() then
		if self.HasLevelingCraftQueueLines and self:HasLevelingCraftQueueLines() then
			self:GetOpenProfessionLevelingRoute()
		end
		return
	end
	local route, reason = self:GetOpenProfessionLevelingRoute()
	if route then
		renderProgressOfRoute(host, route, openProfessionData(self))
	else
		renderProgressWithoutRoute(host, openProfessionData(self))
	end
	renderStats(self, host, route)
	host.giveBackDropdown:RefreshText()
	host.recipeScopeDropdown:RefreshText()
	renderQueueRange(host, route)
	renderRoute(self, host, route, reason)
end
