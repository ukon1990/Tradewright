local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Bag row of the bag window: the backpack, the bags and the reagent bag as cells.
-- Hovering a bag lights its items; dropping a bag swaps it in; right-click lists replacements.
-- The calls are the ones the game's own bag bar makes, so the game's rules apply.

local ICON = 36
local CELL_PAD = 6
local TEXT_HEIGHT = 14
local CELL_HEIGHT = CELL_PAD + ICON + 2 + TEXT_HEIGHT * 2 + 4
local HEADING = 18
local GAP = 4
local REAGENT_GAP = 8
local BACKPACK = 0
local BACKPACK_ICON = "Interface\\Buttons\\Button-Backpack-Up"
local HINT = L["Drop a bag here to swap it in. Right-click to pick one you carry. Drag it off to unequip."]

Tradewright.BAG_ROW_HEIGHT = HEADING + GAP + CELL_HEIGHT

local pickerMenu

local function cursorHasItem()
	return CursorHasItem ~= nil and CursorHasItem() == true
end

local function equipFromBags(item, inventorySlot)
	ClearCursor()
	C_Container.PickupContainerItem(item.bag, item.slot)
	PutItemInBag(inventorySlot)
end

local function addMenuButton(text, icon, onClick)
	local info = UIDropDownMenu_CreateInfo()
	info.text, info.icon, info.func = text, icon, onClick
	info.notCheckable = true
	info.isTitle = onClick == nil
	UIDropDownMenu_AddButton(info)
end

-- Right-click menu of a bag cell: the bags carried that fit the slot, and taking the bag off.
local function showPicker(cell)
	local pe = Tradewright
	if not cell.inventorySlot then
		return
	end
	local bags = pe.BagLogic.ReplacementBags(pe:ScanBags().items, cell.isReagent)
	pickerMenu = pickerMenu or CreateFrame("Frame", "TradewrightBagPickerMenu", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(pickerMenu, function()
		addMenuButton(#bags > 0 and L["Replace with"] or L["No other bag for this slot in your bags"])
		for _, item in ipairs(bags) do
			addMenuButton(item.name, item.icon, function() equipFromBags(item, cell.inventorySlot) end)
		end
		if cell.equipped then
			addMenuButton(L["Take this bag off"], nil, function() PickupBagFromSlot(cell.inventorySlot) end)
		end
	end, "MENU")
	ToggleDropDownMenu(1, nil, pickerMenu, cell, 0, 0)
end

local function onClick(cell, mouseButton)
	if mouseButton == "RightButton" then
		showPicker(cell)
	elseif cell.bag == BACKPACK then
		if cursorHasItem() and PutItemInBackpack then
			PutItemInBackpack()
		end
	elseif cell.inventorySlot and cursorHasItem() then
		PutItemInBag(cell.inventorySlot)
	elseif cell.inventorySlot then
		PickupBagFromSlot(cell.inventorySlot)
	end
end

local function onDragStart(cell)
	if cell.inventorySlot then
		PickupBagFromSlot(cell.inventorySlot)
	end
end

local function onReceiveDrag(cell)
	onClick(cell, "LeftButton")
end

local function onEnter(cell)
	local pe = Tradewright
	local theme = pe:GetTheme()
	pe:ApplyBackdrop(cell, theme.surface2, theme.tick)
	pe:SetBagHover(cell.bag)
	GameTooltip:SetOwner(cell, "ANCHOR_TOP")
	if cell.equipped then
		GameTooltip:SetInventoryItem("player", cell.inventorySlot)
	else
		GameTooltip:SetText(cell.name:GetText() or "", 1, 1, 1)
	end
	if cell.bag ~= BACKPACK then
		GameTooltip:AddLine(HINT, theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, true)
	end
	GameTooltip:Show()
end

local function onLeave(cell)
	local pe = Tradewright
	pe:StylePanel(cell, "surface2")
	pe:SetBagHover(nil)
	GameTooltip:Hide()
end

local function createCell(pe, row)
	local cell = CreateFrame("Button", nil, row, "BackdropTemplate")
	cell:SetHeight(CELL_HEIGHT)
	pe:StylePanel(cell, "surface2")
	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.icon:SetSize(ICON, ICON)
	cell.icon:SetPoint("TOP", 0, -CELL_PAD)
	cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cell.name = pe:CreateText(cell, "GameFontHighlightSmall", "textMuted", "CENTER")
	cell.name:SetPoint("TOPLEFT", 2, -(CELL_PAD + ICON + 2))
	cell.name:SetPoint("TOPRIGHT", -2, -(CELL_PAD + ICON + 2))
	cell.count = pe:CreateText(cell, "GameFontHighlightSmall", "textPrimary", "CENTER")
	cell.count:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", 0, 0)
	cell.count:SetPoint("TOPRIGHT", cell.name, "BOTTOMRIGHT", 0, 0)
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell:RegisterForDrag("LeftButton")
	cell:SetScript("OnClick", onClick)
	cell:SetScript("OnDragStart", onDragStart)
	cell:SetScript("OnReceiveDrag", onReceiveDrag)
	cell:SetScript("OnEnter", onEnter)
	cell:SetScript("OnLeave", onLeave)
	return cell
end

local function cellName(info, link)
	if info.bag == BACKPACK then
		return "Backpack"
	end
	return link and string.match(link, "%[(.-)%]") or (info.isReagent and L["No reagent bag"] or "Empty")
end

-- The inventory slot a bag is equipped in; the backpack has none.
local function inventorySlotOf(bag)
	local slotOf = C_Container.ContainerIDToInventoryID
	return bag ~= BACKPACK and slotOf and slotOf(bag) or nil
end

-- `info`: one entry of ScanBags().bags.
local function refreshCell(cell, info)
	cell.bag, cell.isReagent = info.bag, info.isReagent
	cell.inventorySlot = inventorySlotOf(info.bag)
	local link = cell.inventorySlot and GetInventoryItemLink("player", cell.inventorySlot)
	local texture = cell.inventorySlot and GetInventoryItemTexture("player", cell.inventorySlot)
	cell.equipped = link ~= nil
	cell.icon:SetTexture(info.bag == BACKPACK and BACKPACK_ICON or texture)
	cell.icon:SetShown(info.bag == BACKPACK or texture ~= nil)
	cell.name:SetText(cellName(info, link))
	cell.count:SetText(info.slots > 0 and string.format("%d / %d", info.slots - info.free, info.slots) or "-")
end

function Tradewright:CreateBagRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(self.BAG_ROW_HEIGHT)
	row.heading = self:CreateHeading(row, L["Equipped bags"])
	row.heading:SetPoint("TOPLEFT")
	row.heading:SetPoint("TOPRIGHT")
	row.divider = row:CreateTexture(nil, "ARTWORK")
	Tradewright:ColorTexture(row.divider, "borderStrong", 1)
	row.divider:SetSize(1, CELL_HEIGHT)
	row.cells = {}
	return row
end

--- Lay the cells out over `width` and fill them from `bags` (ScanBags().bags). The reagent bag is
--- set apart by a divider.
function Tradewright:RefreshBagRow(row, bags, width)
	local hasReagent = bags[#bags] and bags[#bags].isReagent
	local cellWidth = (width - (#bags - 1) * GAP - (hasReagent and REAGENT_GAP or 0)) / #bags
	local x = 0
	row.divider:Hide()
	for index, info in ipairs(bags) do
		row.cells[index] = row.cells[index] or createCell(self, row)
		local cell = row.cells[index]
		if info.isReagent then
			row.divider:ClearAllPoints()
			row.divider:SetPoint("TOPLEFT", row, "TOPLEFT", x + 2, -(HEADING + GAP))
			row.divider:Show()
			x = x + REAGENT_GAP
		end
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", row, "TOPLEFT", x, -(HEADING + GAP))
		cell:SetWidth(cellWidth)
		refreshCell(cell, info)
		cell:Show()
		x = x + cellWidth + GAP
	end
	for index = #bags + 1, #row.cells do
		row.cells[index]:Hide()
	end
end
