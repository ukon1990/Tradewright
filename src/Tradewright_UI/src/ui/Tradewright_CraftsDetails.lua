local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Crafts tab details: the selected craft's header, badge, facts and materials, and the row tooltip.

local MAX_TOOLTIP_REAGENTS = 6
local LAYOUT = Tradewright.CraftsLayout
local PAD = LAYOUT.pad

function Tradewright:GetCraftMaterialColumns()
	local pe = self
	return {
		self:CreateItemColumn({ label = L["Reagent"], sortable = false,
			getItemID = function(slot) return slot.itemID end,
			getName = function(slot) return pe:GetItemDisplayName(slot.itemID) end }),
		{ id = "need", label = L["Need"], width = 38, justifyH = "RIGHT", getText = function(slot) return tostring(slot.need) end },
		{ id = "have", label = L["Have"], width = 40, justifyH = "RIGHT", tooltipTitle = L["Have"], tooltipText = L["On all your characters."],
			getText = function(slot)
				if slot.have == nil then
					return "-"
				end
				return slot.have < slot.need and pe:Colorize(tostring(slot.have), "danger") or tostring(slot.have)
			end },
		{ id = "from", label = L["From"], width = 50, getText = function(slot) return slot.from or "-" end },
		pe:MoneyColumn({ id = "cost", label = L["Cost"], width = 70, sortable = false }),
	}
end

-- Bottom of the details: quantity box, Add to queue and Remove.
function Tradewright:CreateCraftsDetailActions(panel)
	local pe, ui = self, self.ui
	panel.detailActions = CreateFrame("Frame", nil, panel.detailsBody)
	panel.detailActions:SetPoint("BOTTOMLEFT")
	panel.detailActions:SetPoint("BOTTOMRIGHT")
	panel.detailActions:SetHeight(26)
	local quantity = CreateFrame("EditBox", nil, panel.detailActions, "InputBoxTemplate")
	quantity:SetSize(32, 22)
	quantity:SetPoint("LEFT", 6, 0)
	quantity:SetAutoFocus(false)
	quantity:SetNumeric(true)
	quantity:SetMaxLetters(4)
	quantity:SetJustifyH("RIGHT")
	quantity:SetText("1")
	self:SkinEditBox(quantity)
	quantity:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	panel.detailQueueQty = quantity
	panel.detailQueueRemove = self:CreateButton(panel.detailActions, L["Remove"], function()
		if ui.craftsSelectedRowData then
			pe:RemoveCraftQueueLinesForOpportunityRow(ui.craftsSelectedRowData)
		end
	end)
	panel.detailQueueRemove:SetPoint("RIGHT")
	panel.detailQueueAddN = self:CreateButton(panel.detailActions, L["Add to queue"], function()
		local count = tonumber(quantity:GetText()) or 1
		if ui.craftsSelectedRowData and count > 0 then
			pe:AddCraftWithMaterialCraftsToQueue(ui.craftsSelectedRowData, count)
		end
	end, { primary = true })
	panel.detailQueueAddN:SetPoint("LEFT", quantity, "RIGHT", 10, 0)
	panel.detailQueueAddN:SetPoint("RIGHT", panel.detailQueueRemove, "LEFT", -8, 0)
end

-- The Details view: empty state, or header, facts, materials and the queue actions.
function Tradewright:CreateCraftsDetailsView(panel)
	panel.detailsView = CreateFrame("Frame", nil, panel.detailCard)
	panel.detailsView:SetPoint("TOPLEFT", panel.detailsTab, "BOTTOMLEFT", 0, -10)
	panel.detailsView:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -PAD, PAD)
	panel.detailsEmpty = self:CreateEmptyState(panel.detailsView)
	panel.detailsEmpty:SetAllPoints()
	panel.detailsEmpty:SetMessage(L["Select a craft"], L["Click a row to see its reagents and profit."])
	panel.detailsBody = CreateFrame("Frame", nil, panel.detailsView)
	panel.detailsBody:SetAllPoints()
	panel.detailHeader = self:CreateDetailHeader(panel.detailsBody)
	panel.detailHeader:SetPoint("TOPLEFT")
	panel.detailHeader:SetPoint("TOPRIGHT")
	panel.detailFacts = self:CreateKeyValueList(panel.detailsBody)
	panel.detailFacts:SetPoint("TOPLEFT", panel.detailHeader, "BOTTOMLEFT", 0, -10)
	panel.detailFacts:SetPoint("TOPRIGHT", panel.detailHeader, "BOTTOMRIGHT", 0, -10)
	panel.materialsHeading = self:CreateHeading(panel.detailsBody, L["Reagents per craft"])
	panel.materialsHeading:SetPoint("TOPLEFT", panel.detailFacts, "BOTTOMLEFT", 0, -10)
	panel.materialsHeading:SetPoint("TOPRIGHT", panel.detailFacts, "BOTTOMRIGHT", 0, -10)
	self:CreateCraftsDetailActions(panel)
	panel.materialsTable = self:CreateReusableTable(panel.detailsBody, {
		autoFitToScroll = true,
		emptyTitle = L["No reagents"],
		emptyHint = L["This recipe has no saved reagents."],
	})
	panel.materialsTable.frame:SetPoint("TOPLEFT", panel.materialsHeading, "BOTTOMLEFT", 0, -6)
	panel.materialsTable.frame:SetPoint("BOTTOMRIGHT", panel.detailActions, "TOPRIGHT", 0, 10)
	panel.materialsTable:SetColumns(self:GetCraftMaterialColumns())
end

-- The card at the right of the Crafts tab, with Details / Queue tabs.
function Tradewright:CreateCraftsDetailCard(panel)
	local pe, ui = self, self.ui
	local width = LAYOUT.detailWidth
	panel.detailCard = self:CreateInset(panel)
	panel.detailCard:SetPoint("TOPRIGHT", panel.options, "BOTTOMRIGHT", 0, -LAYOUT.gap)
	panel.detailCard:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
	panel.detailCard:SetWidth(width)
	if panel.detailCard.SetClipsChildren then
		panel.detailCard:SetClipsChildren(true)
	end
	local inner = width - PAD * 2
	panel.detailsTab = self:CreateButton(panel.detailCard, L["Details"], function()
		ui.craftsDetailView = "details"
		pe:LayoutCraftsPanel(panel)
	end, { small = true, width = math.floor(inner / 2) + 1 })
	panel.detailsTab:SetPoint("TOPLEFT", PAD, -PAD)
	panel.queueTab = self:CreateButton(panel.detailCard, L["Queue"], function()
		ui.craftsDetailView = "queue"
		pe:LayoutCraftsPanel(panel)
	end, { small = true, width = inner - math.floor(inner / 2) })
	panel.queueTab:SetPoint("LEFT", panel.detailsTab, "RIGHT", -1, 0)
	self:CreateCraftsDetailsView(panel)
	panel.queueView = self:CreateCraftsQueueView(panel.detailCard)
	panel.queueView:SetPoint("TOPLEFT", panel.detailsTab, "BOTTOMLEFT", 0, -10)
	panel.queueView:SetPoint("BOTTOMRIGHT", panel.detailCard, "BOTTOMRIGHT", -PAD, PAD)
end

-- Header badge: no price, can craft, out of reach, or how many materials are still missing.
function Tradewright:CraftBadge(row, evaluation)
	if not row.matCost then
		return L["No price"], "warning"
	elseif row.canCraftNow then
		return L["Can craft"], "success"
	elseif row.qualityReachable == false then
		return L["Out of reach"], "warning"
	end
	local missing = 0
	for _, slot in ipairs(evaluation.reagentPlan or {}) do
		missing = missing + math.max(0, tonumber(slot.purchasedQuantity) or 0)
	end
	return missing > 0 and (string.format(L["Missing %s"], missing)) or "Missing", "danger"
end

local function moneyOrDash(pe, copper)
	return copper and pe:FormatCopperFull(copper) or "-"
end

local function percentOrDash(value)
	return value and string.format("%.0f%%", value) or "-"
end

function Tradewright:CraftDetailFacts(row, evaluation)
	return {
		{ string.format(L["Sale after %.3g%% cut"], self:GetAuctionCut() * 100), moneyOrDash(self, row.saleNet) },
		{ L["Reagents at market price"], moneyOrDash(self, row.matCost) },
		{ L["Profit per craft"], self:FormatSignedMoney(row.profit) },
		{ "Return", percentOrDash(row.roi) },
		{ L["Reagents you already own"], percentOrDash(evaluation.coverage and evaluation.coverage * 100) },
		{ L["Still to buy"], moneyOrDash(self, row.outOfPocketMatCost) },
	}
end

-- Where a material's price comes from, in the reader's words; other sources are auction prices.
local FROM_LABELS = { Craft = "Craft", Vendor = "Vendor", Ledger = "Bought" }

local function materialRows(evaluation)
	local materials = {}
	for index, slot in ipairs(evaluation.reagentPlan or {}) do
		materials[index] = {
			_rowIdentity = index,
			itemID = slot.itemID,
			need = tonumber(slot.quantityRequired) or 0,
			have = tonumber(slot.ownedQuantity),
			cost = tonumber(slot.lineCost),
			from = slot.priceSource and (FROM_LABELS[slot.priceSource] or "Buy") or nil,
		}
	end
	return materials
end

-- An item picked elsewhere that is not in the craft list: its name and a hint, nothing else.
function Tradewright:RenderCraftsItemOnly(panel, itemID)
	panel.detailHeader:SetItem(itemID, self:GetItemDisplayName(itemID), L["Not in the current list. Check the filters."])
	panel.detailHeader.badge:SetBadge(nil)
	panel.detailFacts:SetRows({})
	panel.materialsTable:SetRows({})
	panel.materialsTable:Refresh()
end

function Tradewright:RenderCraftRow(panel, row)
	local evaluation = self:GetBestCraftEvaluation(row) or {}
	local crafter = row.bestCharacterKey and self:GetCrafterName(row.bestCharacterKey) or "-"
	local subtitle = string.format(L["%s · best crafter %s"], row.professionName or "?", crafter)
	panel.detailHeader:SetItem(row.outputItemID, self:GetCraftRowName(row), subtitle, row.outputIcon)
	panel.detailHeader.badge:SetBadge(self:CraftBadge(row, evaluation))
	panel.detailFacts:SetRows(self:CraftDetailFacts(row, evaluation))
	panel.materialsTable:SetRows(materialRows(evaluation))
	panel.materialsTable:Refresh()
end

--- Shows `row` in the details pane, or the item picked elsewhere (`ui.craftsItemDetailOnlyItemID`) when `row` is nil.
function Tradewright:RenderCraftsDetails(row)
	local panel = self.ui and self.ui.craftsPanel
	if not panel then
		return
	end
	local ui = self.ui
	ui.craftsSelectedRowData = row
	if row then
		ui.craftsItemDetailOnlyItemID = nil
		self:RenderCraftRow(panel, row)
	elseif ui.craftsItemDetailOnlyItemID and tonumber(ui.craftsItemDetailOnlyItemID) then
		self:RenderCraftsItemOnly(panel, tonumber(ui.craftsItemDetailOnlyItemID))
	end
	self:LayoutCraftsPanel(panel)
end

-- "  Item x3   12g" lines for the first MAX_TOOLTIP_REAGENTS reagents.
function Tradewright:AddReagentTooltipLines(lines, plan)
	for index = 1, math.min(MAX_TOOLTIP_REAGENTS, #plan) do
		local slot = plan[index]
		lines[#lines + 1] = {
			string.format("  %s × %s", self:GetItemDisplayName(slot.itemID), self:FormatNumberGrouped(slot.quantityRequired or 0)),
			slot.lineCost and self:FormatCopperShort(slot.lineCost) or "-",
		}
	end
end

function Tradewright:ShowCraftRowTooltip(rowFrame, row)
	if not row or not row.outputItemID then
		return
	end
	local evaluation = self:GetBestCraftEvaluation(row) or {}
	local lines = {
		{ "Recipe", row.recipeName or "-" },
		{ L["Best crafter"], row.bestCharacterKey and self:GetCrafterName(row.bestCharacterKey) or "-" },
		{ L["Sale, net"], moneyOrDash(self, row.saleNet) },
		{ "Reagents", moneyOrDash(self, row.matCost) },
		{ "Profit", self:FormatSignedMoney(row.profit) },
	}
	self:AddReagentTooltipLines(lines, evaluation.reagentPlan or {})
	self:ShowItemRowTooltip(rowFrame, row.outputItemID, lines, L["Click for details · Shift-click to link"])
end
