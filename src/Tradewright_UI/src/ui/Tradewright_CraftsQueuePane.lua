local _, Tradewright = ...

-- Crafts tab queue pane: the queued crafts, what to buy on this character and where to mail it.

local LAYOUT = Tradewright.CraftsLayout
local MAX_VISIBLE_QUEUE_ROWS = 4

-- Recipe name over the crafter's name.
local function createRecipeCell(pe, rowFrame)
	local cell = CreateFrame("Frame", nil, rowFrame)
	cell.name = pe:CreateText(cell, "GameFontHighlightSmall")
	cell.name:SetPoint("BOTTOMLEFT", cell, "LEFT", 5, 1)
	cell.name:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
	cell.detail = pe:CreateText(cell, "GameFontHighlightSmall", "textMuted")
	cell.detail:SetPoint("TOPLEFT", cell, "LEFT", 5, -1)
	cell.detail:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
	return cell
end

local function createRemoveCell(pe, rowFrame)
	local cell = CreateFrame("Frame", nil, rowFrame)
	cell.button = CreateFrame("Button", nil, cell, "UIPanelCloseButton")
	cell.button:ClearAllPoints()
	cell.button:SetPoint("CENTER")
	pe:SkinCloseButton(cell.button)
	return cell
end

function Tradewright:GetCraftQueueColumns()
	local pe = self
	return {
		{ id = "recipe", label = "Recipe", width = 100, flex = 1, minWidth = 80,
			createCell = function(rowFrame) return createRecipeCell(pe, rowFrame) end,
			updateCell = function(cell, entry)
				cell.name:SetText(entry.recipeName or "?")
				cell.detail:SetText(pe:GetCrafterName(entry.characterKey))
			end },
		{ id = "qty", label = "Qty", width = 34, justifyH = "RIGHT", getText = function(entry) return tostring(entry.quantity or 0) end },
		{ id = "profit", label = "Profit", width = 76, justifyH = "RIGHT",
			getText = function(entry)
				local profit = entry.snapshot and tonumber(entry.snapshot.profit)
				return profit and pe:FormatSignedMoney(profit * (tonumber(entry.quantity) or 0)) or "-"
			end },
		{ id = "remove", label = "", width = 30,
			createCell = function(rowFrame) return createRemoveCell(pe, rowFrame) end,
			updateCell = function(cell, entry)
				cell.button:SetScript("OnClick", function()
					pe:RemoveCraftFromQueue(entry.queueKey)
				end)
			end },
	}
end

function Tradewright:GetCraftQueueBuyColumns()
	local pe = self
	return {
		self:CreateItemColumn({ label = "Reagent", sortable = false,
			getItemID = function(line) return line.itemID end,
			getName = function(line) return line.name end }),
		{ id = "buy", label = "Buy", width = 40, justifyH = "RIGHT", getText = function(line) return pe:FormatNumberGrouped(line.quantityToBuy or 0) end },
		{ id = "cost", label = "Cost", width = 76, justifyH = "RIGHT",
			getText = function(line) return line.estimatedBuyCost and pe:FormatCopperShort(line.estimatedBuyCost) or "-" end },
	}
end

-- A heading `gap` below `anchor` and an auto-fitting table below the heading.
function Tradewright:AddCraftQueueSection(view, anchor, gap, heading, tableOptions)
	local title = self:CreateHeading(view, heading)
	title:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
	title:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -gap)
	tableOptions.autoFitToScroll = true
	local sectionTable = self:CreateReusableTable(view, tableOptions)
	sectionTable.frame:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	return title, sectionTable
end

function Tradewright:CreateCraftQueueFooter(view)
	local pe = self
	local danger = self:GetTheme().danger
	view.footer = CreateFrame("Frame", nil, view)
	view.footer:SetPoint("BOTTOMLEFT")
	view.footer:SetPoint("BOTTOMRIGHT")
	view.footer:SetHeight(26)
	view.clearButton = self:CreateButton(view.footer, "Clear queue", function() pe:ClearCraftQueue() end)
	view.clearButton:SetPoint("RIGHT")
	view.clearButton:GetFontString():SetTextColor(danger.r, danger.g, danger.b)
	view.clearOrdersButton = self:CreateButton(view.footer, "Clear orders", function()
		if pe.ClearCraftingOrderQueue then
			pe:ClearCraftingOrderQueue()
		end
	end)
	view.clearOrdersButton:SetPoint("RIGHT", view.clearButton, "LEFT", -8, 0)
	view.clearOrdersButton:SetShown(self.IS_RETAIL == true)
	view.hint = self:CreateText(view.footer, "GameFontHighlightSmall", "textMuted")
	view.hint:SetPoint("LEFT")
	view.hint:SetPoint("RIGHT", self.IS_RETAIL and view.clearOrdersButton or view.clearButton, "LEFT", -8, 0)
	view.hint:SetText("Buy from the auction house panel")
end

function Tradewright:CreateCraftsQueueView(parent)
	local view = CreateFrame("Frame", nil, parent)
	view.summary = self:CreateParagraph(view)
	view.summary:SetPoint("TOPLEFT")
	view.summary:SetPoint("TOPRIGHT")
	view.craftHeading, view.craftTable = self:AddCraftQueueSection(view, view.summary, 8, "To craft", {
		rowHeight = LAYOUT.tallRow,
		emptyTitle = "Nothing queued",
		emptyHint = "Pick a craft and press Add to queue.",
	})
	view.craftTable.frame:SetPoint("TOPRIGHT", view.craftHeading, "BOTTOMRIGHT", 0, -6)
	view.craftTable:SetColumns(self:GetCraftQueueColumns())
	view.buyHeading, view.buyTable = self:AddCraftQueueSection(view, view.craftTable.frame, 10, "Cart", {
		footer = true,
		emptyTitle = "Nothing to buy",
		emptyHint = "This character has every reagent the queue needs.",
	})
	view.buyTable:SetColumns(self:GetCraftQueueBuyColumns())
	self:CreateCraftQueueFooter(view)
	view.buyTable.frame:SetPoint("BOTTOMRIGHT", view.footer, "TOPRIGHT", 0, 8)
	return view
end

function Tradewright:FocusCraftsQueuePanel()
	local panel = self.ui and self.ui.craftsPanel
	if not panel then
		return
	end
	self.ui.craftsDetailView = "queue"
	self:LayoutCraftsPanel(panel)
	if UIFrameFlash then
		UIFrameFlash(panel.queueView, 0.4, 0.4, 0.6, false, 0, 0)
	end
end

-- Reagents this character still has to buy, and the mail-to notes among them.
local function linesToBuy(summary)
	local buy, mail = {}, {}
	for _, line in ipairs(summary.reagentLines or {}) do
		if (tonumber(line.quantityToBuy) or 0) > 0 then
			line._rowIdentity = line.itemID
			buy[#buy + 1] = line
			if line.mailToText and line.mailToText ~= "" then
				mail[#mail + 1] = line.mailToText
			end
		end
	end
	return buy, mail
end

function Tradewright:CraftQueueSummaryText(summary)
	local lines = summary.lines or {}
	if #lines == 0 then
		return "The queue is empty."
	end
	local crafts = 0
	for _, entry in ipairs(lines) do
		crafts = crafts + (tonumber(entry.quantity) or 0)
	end
	local profit = summary.totalProfit and self:FormatSignedMoney(summary.totalProfit) or "unknown"
	return string.format("%d crafts of %d recipes · potential profit %s", crafts, #lines, profit)
end

function Tradewright:RefreshCraftQueueBuyTable(view, summary)
	local buy, mail = linesToBuy(summary)
	view.buyHeading:SetText("Cart for " .. self:GetCrafterName(self:GetCharacterKey()))
	view.buyTable:SetRows(buy)
	view.buyTable:Refresh()
	local buyCost = summary.totalCurrentCharacterBuyCost
	view.buyTable:SetFooterText(#mail > 0 and ("Mail: " .. table.concat(mail, ", ")) or nil, buyCost and self:FormatCopperShort(buyCost) or nil)
end

function Tradewright:RefreshCraftsQueuePanel()
	local panel = self.ui and self.ui.craftsPanel
	if not panel or not panel.queueView then
		return
	end
	local view = panel.queueView
	local summary = self:BuildCraftQueueSummary()
	local lines = summary.lines or {}
	self:SetButtonLabel(panel.queueTab, #lines > 0 and string.format("Queue (%d)", #lines) or "Queue", true)
	panel.queueTab:SetWidth(LAYOUT.detailWidth - LAYOUT.pad * 2 - panel.detailsTab:GetWidth() + 1)
	view.summary:SetText(self:CraftQueueSummaryText(summary))
	for index, entry in ipairs(lines) do
		entry._rowIdentity = index
	end
	view.craftTable:SetRows(lines)
	view.craftTable:Refresh()
	view.craftTable.frame:SetHeight(22 + 2 + LAYOUT.tallRow * math.max(1, math.min(#lines, MAX_VISIBLE_QUEUE_ROWS)))
	self:RefreshCraftQueueBuyTable(view, summary)
	view.clearButton:SetEnabled(#lines > 0)
end
