local _, ProfessionExporter = ...

-- Queue view of the profession side panel: the queued crafts, and the shopping list of materials
-- this character still misses, with the other characters that hold them.

local TALL_ROW = 36
local MAX_HOLDERS_SHOWN = 3

local function rankMarkup(rankIndex)
	return ProfessionExporter:GetRankMarkup(rankIndex)
end

local function buttonCell(pe, label, width)
	return function(rowFrame)
		local cell = CreateFrame("Frame", nil, rowFrame)
		cell.button = pe:CreateButton(cell, label, nil, { small = true, width = width })
		cell.button:SetPoint("CENTER")
		return cell
	end
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

local function recipeNameCell(pe)
	return function(rowFrame)
		local cell = CreateFrame("Frame", nil, rowFrame)
		cell.name = pe:CreateText(cell, "GameFontHighlightSmall")
		cell.name:SetPoint("BOTTOMLEFT", cell, "LEFT", 5, 1)
		cell.name:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
		cell.detail = pe:CreateText(cell, "GameFontHighlightSmall", "textMuted")
		cell.detail:SetPoint("TOPLEFT", cell, "LEFT", 5, -1)
		cell.detail:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
		return cell
	end
end

local function removeCell(pe)
	return function(rowFrame)
		local cell = CreateFrame("Frame", nil, rowFrame)
		cell.button = CreateFrame("Button", nil, cell, "UIPanelCloseButton")
		cell.button:ClearAllPoints()
		cell.button:SetPoint("CENTER")
		pe:SkinCloseButton(cell.button)
		return cell
	end
end

local function recipeColumns(pe)
	return {
		{ id = "recipe", label = "Recipe", width = 100, flex = 1, minWidth = 90, createCell = recipeNameCell(pe),
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
		{ id = "craft", label = "", width = 56, createCell = buttonCell(pe, "Craft", 46),
			updateCell = function(cell, row)
				cell.button:SetScript("OnClick", function() pe:CraftProfessionQueueRecipe(row) end)
				cell.button:SetEnabled(row.recipeID ~= nil and row.canCraftNow == true)
				pe:SetButtonPrimary(cell.button, row.canCraftNow == true)
			end },
		{ id = "remove", label = "", width = 30, createCell = removeCell(pe),
			updateCell = function(cell, row)
				cell.button:SetScript("OnClick", function() pe:RemoveCraftFromQueue(row.queueKey) end)
			end },
	}
end

--- A queued craft opens its recipe in the profession window; a queued crafting order opens the order.
--- Used by a row click and by the Craft button's first click on a crafting order.
function ProfessionExporter:OpenProfessionQueueRow(row)
	if not row then
		return
	end
	local orderID = tonumber(row.orderID)
	if orderID and self.OpenCraftingOrderWorkQueueEntry then
		local storage = self.GetCraftingOrderWorkQueueStorage and self:GetCraftingOrderWorkQueueStorage() or {}
		local stored = storage[tostring(orderID)]
		self:OpenCraftingOrderWorkQueueEntry(type(stored) == "table" and stored
			or { orderID = orderID, spellID = row.recipeID, itemID = row.outputItemID })
		return
	end
	self:JumpToProfessionRecipe(row.recipeID, row.skillLineID)
end

local function showQueueRowTooltip(pe, rowFrame, row)
	if not row or row.orderID then
		return
	end
	local muted = pe:GetTheme().textMuted
	GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
	GameTooltip:SetText(row.recipeLabel, 1, 1, 1)
	GameTooltip:AddLine("Click to show this recipe in the profession window", muted.r, muted.g, muted.b, true)
	GameTooltip:Show()
end

local function findAtAuctionHouse(pe, row)
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
end

local function showReagentTooltip(pe, rowFrame, row)
	if not row then
		return
	end
	local pairs = {
		{ "Needed", pe:FormatNumberGrouped(row.needed) },
		{ "On this character", pe:FormatNumberGrouped(row.have) },
	}
	for _, holder in ipairs(row.holders) do
		pairs[#pairs + 1] = { "On " .. pe:GetCharacterNameMarkup(holder.characterKey), pe:FormatNumberGrouped(holder.quantity) }
	end
	pairs[#pairs + 1] = { "Buy", pe:FormatNumberGrouped(row.quantity) }
	pairs[#pairs + 1] = { "Each", row.unitPrice and pe:FormatCopperFull(row.unitPrice) or "-" }
	pairs[#pairs + 1] = { "Used by", table.concat(row.recipeRefs or {}, ", ") }
	local hint = "Click to find it at the auction house"
	pe:ShowItemRowTooltip(rowFrame, row.itemID, pairs, pe.AppendCartVendorLines and pe:AppendCartVendorLines(pairs, row, hint) or hint)
end

-- "Vendor" button on materials a vendor sells: points the way to the nearest one.
local function vendorColumn(pe)
	return { id = "vendor", label = "", width = 52, createCell = buttonCell(pe, "Vendor", 46),
		updateCell = function(cell, row)
			cell.button:SetShown(row.vendorNote ~= nil)
			cell.button:SetScript("OnClick", function() pe:ShowVendorWaypoint(row.itemID) end)
		end }
end

local function numberColumn(pe, id, label, width)
	return { id = id, label = label, width = width, justifyH = "RIGHT", sortable = true, defaultSort = "desc",
		sortValue = function(row) return row[id] end,
		getText = function(row) return pe:FormatNumberGrouped(row[id]) end }
end

local function reagentColumns(pe)
	return {
		pe:CreateItemColumn({ label = "Material", sortable = true, minWidth = 100,
			getItemID = function(row) return row.itemID end,
			getName = function(row) return row.name .. rankMarkup(row.qualityIndex) end,
			getDetail = function(row) return row.detailText end }),
		numberColumn(pe, "needed", "Need", 36),
		numberColumn(pe, "have", "Have", 36),
		numberColumn(pe, "quantity", "Buy", 34),
		{ id = "totalCost", label = "Cost", width = 68, justifyH = "RIGHT", sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.totalCost or -1 end,
			getText = function(row) return row.totalCost and pe:FormatCopperShort(row.totalCost) or "-" end },
		vendorColumn(pe),
	}
end

-- Crafting order navigation (retail): placed by the crafting orders module.
local function createOrderNav(pe, f, host)
	local orderNav = CreateFrame("Frame", nil, host)
	orderNav:SetPoint("TOPLEFT")
	orderNav:SetPoint("TOPRIGHT")
	orderNav:SetHeight(48)
	orderNav:Hide()
	f.orderNav = orderNav
	f.peAddWorkOrderBtn = pe:CreateButton(orderNav, "Add to shopping", nil,
		{ tooltip = "Adds this order's crafter-supplied reagents to the cart without starting the order." })
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
end

local function createActions(pe, f, host)
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
	return actions
end

local function createRecipeTable(pe, f, card)
	f.recipeTitle = pe:CreateHeading(card, "To craft")
	f.recipeTitle:SetPoint("TOPLEFT", f.queueOverviewText, "BOTTOMLEFT", 0, -8)
	f.recipeTitle:SetPoint("TOPRIGHT", f.queueOverviewText, "BOTTOMRIGHT", 0, -8)
	f.recipeTable = pe:CreateReusableTable(card, {
		rowHeight = TALL_ROW,
		autoFitToScroll = true,
		emptyTitle = "Nothing queued",
		emptyHint = "Pick a recipe and press Add to queue.",
		onRowClick = function(_, row) pe:OpenProfessionQueueRow(row) end,
		onRowEnter = function(rowFrame, row) showQueueRowTooltip(pe, rowFrame, row) end,
		onRowLeave = function() GameTooltip:Hide() end,
	})
	f.recipeTable.frame:SetPoint("TOPLEFT", f.recipeTitle, "BOTTOMLEFT", 0, -6)
	f.recipeTable.frame:SetPoint("TOPRIGHT", f.recipeTitle, "BOTTOMRIGHT", 0, -6)
	f.recipeTable:SetColumns(recipeColumns(pe))
end

-- The table fills the space down to the action row. It is anchored to that row directly, the same
-- way the Recipe view's materials table is.
local function createReagentTable(pe, f, card, actions)
	f.reagentTitle = pe:CreateHeading(card, "Shopping list")
	f.reagentTitle:SetPoint("TOPLEFT", f.recipeTable.frame, "BOTTOMLEFT", 0, -10)
	f.reagentTitle:SetPoint("TOPRIGHT", f.recipeTable.frame, "BOTTOMRIGHT", 0, -10)
	f.reagentTable = pe:CreateReusableTable(card, {
		rowHeight = TALL_ROW,
		autoFitToScroll = true,
		footer = true,
		sortKey = "totalCost",
		sortAsc = false,
		emptyTitle = "Nothing missing",
		emptyHint = "This character has every material the queue needs.",
		onRowEnter = function(rowFrame, row) showReagentTooltip(pe, rowFrame, row) end,
		onRowLeave = function() GameTooltip:Hide() end,
		onRowClick = function(_, row, button)
			if button == "RightButton" and row and pe.ShowVendorWaypoint then
				pe:ShowVendorWaypoint(row.itemID)
			else
				findAtAuctionHouse(pe, row)
			end
		end,
	})
	f.reagentTable.frame:SetPoint("TOPLEFT", f.reagentTitle, "BOTTOMLEFT", 0, -6)
	f.reagentTable.frame:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", 0, 4)
	f.reagentTable:SetColumns(reagentColumns(pe))
end

function ProfessionExporter:CreateProfessionQueueView(f)
	local host = CreateFrame("Frame", nil, f)
	host:SetPoint("TOPLEFT", f.infoHost, "TOPLEFT")
	host:SetPoint("BOTTOMRIGHT", f.infoHost, "BOTTOMRIGHT")
	host:Hide()
	f.queueHost = host
	createOrderNav(self, f, host)
	local actions = createActions(self, f, host)

	local card = CreateFrame("Frame", nil, host)
	card:SetPoint("TOPLEFT")
	card:SetPoint("TOPRIGHT")
	card:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 30)
	f.queueCard = card
	f.queueOverviewText = self:CreateParagraph(card)
	f.queueOverviewText:SetPoint("TOPLEFT")
	f.queueOverviewText:SetPoint("TOPRIGHT")
	createRecipeTable(self, f, card)
	createReagentTable(self, f, card, actions)
	return host
end

local function queueRecipeName(pe, entry)
	local name = entry.recipeName
	local function missing()
		return not name or name == "" or name == "?"
	end
	if missing() and tonumber(entry.recipeID) and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
		local info = C_TradeSkillUI.GetRecipeInfo(tonumber(entry.recipeID))
		name = info and info.name or name
	end
	if missing() and tonumber(entry.outputItemID) then
		name = pe:GetItemDisplayName(entry.outputItemID)
	end
	return tostring(name or "?")
end

-- Whether a queued craft can be started now, from what is in this character's bags at this moment
-- (the queue's saved snapshot is from when the craft was added). Returns ready and a note for the row.
local function craftReadiness(pe, entry, quantity)
	local characterKey = pe:GetCharacterKey()
	local craftable = pe.MaterialLogic.CraftableCount(entry.reagentPlan, function(itemID)
		return pe:GetCharacterItemTotal(characterKey, itemID)
	end)
	if craftable == nil then
		local ready = (entry.snapshot or {}).canCraftNow == true
		return ready, ready and "ready" or nil
	end
	if craftable >= quantity then
		return true, "ready"
	end
	return craftable > 0, craftable > 0 and string.format("materials for %d of %d", craftable, quantity) or nil
end

local function queueRecipeRow(pe, entry, index)
	local snapshot = entry.snapshot or {}
	local quantity = tonumber(entry.quantity) or 0
	local perProfit = tonumber(snapshot.profit)
	local orderID = tonumber(entry.orderID)
	local detail = {}
	if orderID then
		detail[#detail + 1] = "Order #" .. orderID
	end
	detail[#detail + 1] = "Profit " .. (perProfit and pe:FormatSignedMoney(perProfit * quantity) or "unknown")
	local ready, readyNote = craftReadiness(pe, entry, quantity)
	detail[#detail + 1] = readyNote
	return {
		_rowIdentity = index,
		queueKey = entry.queueKey,
		orderID = orderID,
		recipeID = tonumber(entry.recipeID),
		outputItemID = tonumber(entry.outputItemID),
		skillLineID = tonumber(entry.skillLineID),
		recipeLabel = queueRecipeName(pe, entry),
		qualityIndex = tonumber(entry.qualityIndex),
		quantity = quantity,
		scenario = tostring(entry.scenario or "default"),
		canCraftNow = ready,
		detailText = table.concat(detail, " · "),
	}
end

local function recipeRefs(reagent)
	local refs, seen = {}, {}
	for _, src in ipairs(reagent.sources or {}) do
		local label = tostring(src and src.recipeName or "")
		if label ~= "" and not seen[label] then
			seen[label] = true
			refs[#refs + 1] = label
		end
	end
	table.sort(refs)
	return refs
end

-- "On alts: Name 20, Other 5", or nil when no other character has the item.
local function holdersText(pe, holders)
	local parts = {}
	for index = 1, math.min(#holders, MAX_HOLDERS_SHOWN) do
		local holder = holders[index]
		parts[index] = pe:GetCharacterNameMarkup(holder.characterKey) .. " " .. pe:FormatNumberGrouped(holder.quantity)
	end
	if #holders > MAX_HOLDERS_SHOWN then
		parts[#parts + 1] = "+" .. (#holders - MAX_HOLDERS_SHOWN)
	end
	return #parts > 0 and ("On alts: " .. table.concat(parts, ", ")) or nil
end

-- Cost of buying `buy` units: 0 when nothing is bought, nil when the price is unknown.
local function buyCost(unitPrice, buy)
	if buy == 0 then
		return 0
	end
	return unitPrice and unitPrice * buy or nil
end

-- The vendor note of a material (see GetVendorNote), nil when no vendor sells it.
local function vendorNoteFor(pe, itemID, unitPrice)
	return pe.GetVendorNote and pe:GetVendorNote({ itemID = itemID, estimatedUnitPrice = unitPrice }) or nil
end

local function joinNotes(first, second)
	if first and second then
		return first .. " · " .. second
	end
	return first or second
end

local function shoppingFooter(pe, rows)
	return (pe.CartVendorHint and pe:CartVendorHint(rows) or "") .. "Click a material to find it at the auction house"
end

-- One shopping-list row for a material this character misses.
local function shoppingRow(pe, reagent, missing)
	local holders = pe.GetItemHoldersOnOtherCharacters and pe:GetItemHoldersOnOtherCharacters(reagent.itemID) or {}
	local _, buy
	_, buy, holders = pe.MaterialLogic.CoverFromHolders(missing, holders)
	local unitPrice = tonumber(reagent.estimatedUnitPrice) or tonumber(reagent.priceUnit)
	local vendorNote = vendorNoteFor(pe, reagent.itemID, unitPrice)
	local holdersLine = holdersText(pe, holders)
	return {
		vendorNote = vendorNote,
		estimatedUnitPrice = unitPrice,
		detailText = joinNotes(vendorNote, holdersLine),
		_rowIdentity = reagent.itemID,
		itemID = tonumber(reagent.itemID),
		name = reagent.name or pe:GetItemDisplayName(reagent.itemID),
		qualityIndex = pe:GetItemDisplayProfessionQualityRank(reagent.itemID),
		needed = tonumber(reagent.quantityNeeded) or missing,
		have = tonumber(reagent.currentCharacterQuantity) or 0,
		quantity = buy,
		holders = holders,
		holdersText = holdersLine,
		unitPrice = unitPrice,
		totalCost = buyCost(unitPrice, buy),
		recipeRefs = recipeRefs(reagent),
	}
end

local function addToTotals(totals, row)
	if row.quantity > 0 then
		totals.toBuy = totals.toBuy + 1
	end
	if #row.holders > 0 then
		totals.onAlts = totals.onAlts + 1
	end
	if totals.cost and row.totalCost then
		totals.cost = totals.cost + row.totalCost
	else
		totals.cost = nil
	end
end

-- Rows for the materials this character misses, plus what the list adds up to:
-- { toBuy, onAlts, cost (nil when a price is missing) }.
local function shoppingRows(pe, summary)
	local rows, totals = {}, { toBuy = 0, onAlts = 0, cost = 0 }
	for _, reagent in ipairs(summary.reagentLines or {}) do
		local missing = tonumber(reagent.quantityToBuy) or 0
		if missing > 0 then
			rows[#rows + 1] = shoppingRow(pe, reagent, missing)
			addToTotals(totals, rows[#rows])
		end
	end
	return rows, totals
end

local function overviewText(pe, summary, recipeRows, totals)
	if #recipeRows == 0 then
		return "The queue is empty."
	end
	local crafts = 0
	for _, row in ipairs(recipeRows) do
		crafts = crafts + row.quantity
	end
	local text = string.format("%d crafts of %d recipes · potential profit %s · %d materials to buy",
		crafts, #recipeRows, summary.totalProfit and pe:FormatSignedMoney(summary.totalProfit) or "unknown", totals.toBuy)
	if totals.onAlts > 0 then
		text = text .. string.format(" · %d on alts", totals.onAlts)
	end
	return text
end

function ProfessionExporter:RefreshProfessionQueueCard(panel)
	if not panel or not panel.recipeTable then
		return
	end
	local summary = self:BuildCraftQueueSummary()
	local recipeRows = {}
	for index, entry in ipairs(summary.lines or {}) do
		recipeRows[index] = queueRecipeRow(self, entry, index)
	end
	local reagentRows, totals = shoppingRows(self, summary)
	self:SetButtonLabel(panel.tabQueue, #recipeRows > 0 and string.format("Queue (%d)", #recipeRows) or "Queue", true)
	panel.queueOverviewText:SetText(overviewText(self, summary, recipeRows, totals))
	panel.recipeTable:SetRows(recipeRows)
	panel.recipeTable:Refresh()
	panel.recipeTable.frame:SetHeight(22 + 2 + TALL_ROW * math.max(1, math.min(#recipeRows, 3)))
	panel.reagentTable:SetRows(reagentRows)
	panel.reagentTable:Refresh()
	panel.reagentTable:SetFooterText(shoppingFooter(self, reagentRows),
		totals.cost and self:FormatCopperShort(totals.cost) or nil)
	panel.clearQueueButton:SetEnabled(#recipeRows > 0)
end
