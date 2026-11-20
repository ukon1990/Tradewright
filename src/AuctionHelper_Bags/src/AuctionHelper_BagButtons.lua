local _, ProfessionExporter = ...

-- Item slots of the bag window (E11 F92, F94). Live slots are the game's own item buttons, so use,
-- drag, split and tooltips run the game's code; read-only slots are plain buttons.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local DIM_ALPHA = 0.22
local SELECT_ALPHA = 0.35
local NEW_MARK = 7

local live = {} -- [bag][slot] = button; a button keeps its bag and slot for life
local bagParents = {} -- [bag] = frame whose ID is the bag, as the item button template expects
local readOnly = {}

-- Flat look over any button: 1px outline, dark fill, cropped icon, count bottom right.
local function addLook(pe, button)
	local theme = pe:GetTheme()
	local name = button:GetName()
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal then
		normal:SetAlpha(0)
	end
	button.ahBorder = button:CreateTexture(nil, "BACKGROUND")
	button.ahBorder:SetAllPoints()
	button.ahFill = button:CreateTexture(nil, "BACKGROUND", nil, 1)
	button.ahFill:SetPoint("TOPLEFT", 1, -1)
	button.ahFill:SetPoint("BOTTOMRIGHT", -1, 1)
	button.ahFill:SetColorTexture(theme.surface3.r, theme.surface3.g, theme.surface3.b, 1)
	button.ahIcon = button.icon or (name and _G[name .. "IconTexture"]) or button:CreateTexture(nil, "ARTWORK")
	button.ahIcon:ClearAllPoints()
	button.ahIcon:SetPoint("TOPLEFT", 1, -1)
	button.ahIcon:SetPoint("BOTTOMRIGHT", -1, 1)
	button.ahIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.ahCount = button.Count or (name and _G[name .. "Count"]) or button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.ahCount:ClearAllPoints()
	button.ahCount:SetPoint("BOTTOMRIGHT", -2, 2)
	button.ahSelect = button:CreateTexture(nil, "OVERLAY")
	button.ahSelect:SetAllPoints()
	button.ahSelect:SetColorTexture(theme.gold.r, theme.gold.g, theme.gold.b, SELECT_ALPHA)
	button.ahSelect:Hide()
	-- New item: a small gold corner, top left.
	button.ahNew = button:CreateTexture(nil, "OVERLAY", nil, 1)
	button.ahNew:SetSize(NEW_MARK, NEW_MARK)
	button.ahNew:SetPoint("TOPLEFT", 1, -1)
	button.ahNew:SetColorTexture(theme.gold.r, theme.gold.g, theme.gold.b, 1)
	button.ahNew:Hide()
end

-- Hovering a new item is seeing it: the game's own bags forget it the same way.
local function forgetNew(button)
	local item = button.ahItem
	if item and item.isNew then
		item.isNew = nil
		button.ahNew:Hide()
		C_NewItems.RemoveNewItem(item.bag, item.slot)
	end
end

local function bagParent(content, bag)
	if not bagParents[bag] then
		local parent = CreateFrame("Frame", nil, content)
		parent:SetAllPoints(content)
		parent:SetID(bag)
		bagParents[bag] = parent
	end
	return bagParents[bag]
end

-- The template's own glows (store item, new item, flash). The game hides them per item from its
-- bag frame code, which never runs for these buttons, so they would stay lit until hovered.
local function hideGameGlows(button)
	for _, key in ipairs({ "BattlepayItemTexture", "NewItemTexture", "flash" }) do
		local glow = button[key] or _G[button:GetName() .. key]
		if glow then
			glow:Hide()
		end
	end
end

local function createLiveSlot(pe, content, bag, slot)
	local name = string.format("AuctionHelperBagSlot%d_%d", bag, slot)
	local parent = bagParent(content, bag)
	-- Newer clients have an ItemButton frame type; older ones use a plain Button.
	local ok, button = pcall(CreateFrame, "ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
	if not ok then
		button = CreateFrame("Button", name, parent, "ContainerFrameItemButtonTemplate")
	end
	button:SetID(slot)
	if button.SetBagID then
		button:SetBagID(bag)
	end
	addLook(pe, button)
	hideGameGlows(button)
	button:HookScript("OnEnter", forgetNew)
	return button
end

--- The game's item button for one bag slot, parented under `content`.
function ProfessionExporter:AcquireLiveBagSlot(content, bag, slot)
	live[bag] = live[bag] or {}
	if not live[bag][slot] then
		live[bag][slot] = createLiveSlot(self, content, bag, slot)
	end
	return live[bag][slot]
end

local function ownerText(pe, owner)
	local parts = {}
	if owner.bags > 0 then
		parts[#parts + 1] = pe:FormatNumberGrouped(owner.bags) .. " bags"
	end
	if owner.bank > 0 then
		parts[#parts + 1] = pe:FormatNumberGrouped(owner.bank) .. " bank"
	end
	return table.concat(parts, " · ")
end

-- Tooltip of a read-only slot: the item, then who holds how many.
local function showSavedTooltip(button)
	local pe, item = ProfessionExporter, button.ahItem
	if not item then
		return
	end
	local owners, total = pe.TooltipLogic.Owners(pe:GetBagHoldings(), item.itemID)
	local rows = {}
	for _, owner in ipairs(owners) do
		rows[#rows + 1] = { owner.name, ownerText(pe, owner) }
	end
	rows[#rows + 1] = { "All characters", pe:FormatNumberGrouped(total) }
	local price = pe.GetNativeAhPrice and pe:GetNativeAhPrice(item.itemID)
	if price and price > 0 then
		rows[#rows + 1] = { "Auction price each", pe:FormatCopperShort(price) }
	end
	pe:ShowItemRowTooltip(button, item.itemID, rows, "Stacks are added up per item. Log in on that character to move or use them.")
end

--- A plain slot that only shows an item: tooltip and shift-click to link, nothing else.
function ProfessionExporter:AcquireReadOnlyBagSlot(content, index)
	if not readOnly[index] then
		local pe = self
		local gold = self:GetTheme().gold
		local button = CreateFrame("Button", nil, content)
		addLook(self, button)
		button:SetHighlightTexture(WHITE)
		button:GetHighlightTexture():SetVertexColor(gold.r, gold.g, gold.b, 0.12)
		button:SetScript("OnEnter", showSavedTooltip)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button:SetScript("OnClick", function(self)
			if self.ahItem then
				pe:HandleItemRowModifiedClick(self.ahItem.itemID)
			end
		end)
		readOnly[index] = button
	end
	return readOnly[index]
end

function ProfessionExporter:HideBagSlots()
	for _, slots in pairs(live) do
		for _, button in pairs(slots) do
			button:Hide()
		end
	end
	for _, button in ipairs(readOnly) do
		button:Hide()
	end
end

local function updateCooldown(button, item)
	local name = button:GetName()
	local cooldown = button.Cooldown or (name and _G[name .. "Cooldown"])
	if not (cooldown and item.bag and CooldownFrame_Set and C_Container.GetContainerItemCooldown) then
		return
	end
	local start, duration, enable = C_Container.GetContainerItemCooldown(item.bag, item.slot)
	CooldownFrame_Set(cooldown, start or 0, duration or 0, enable or 0)
end

--- Draw an item on a slot. `look.dim`: a search miss or an item of another bag than the hovered
--- one; `look.glow`: an item of the hovered bag; `look.selected`: a selected stack.
function ProfessionExporter:SetBagSlotItem(button, item, look)
	local theme = self:GetTheme()
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality] or theme.borderStrong
	if look.glow or look.selected then
		color = theme.gold
	end
	button.ahSelect:SetShown(look.selected == true)
	button.ahNew:SetShown(item.isNew == true)
	button.ahItem = item
	button.ahBorder:SetColorTexture(color.r, color.g, color.b, 1)
	button.ahFill:Show()
	button.ahIcon:SetTexture(item.icon)
	button.ahIcon:SetDesaturated(item.locked == true)
	button.ahIcon:Show()
	button.ahCount:SetTextColor(theme.textPrimary.r, theme.textPrimary.g, theme.textPrimary.b)
	button.ahCount:SetText(item.count > 1 and item.count or "")
	button.ahCount:Show()
	button:SetAlpha(look.dim and DIM_ALPHA or 1)
	updateCooldown(button, item)
end

--- Draw the free-slot tile: an empty slot showing how many normal slots are free.
function ProfessionExporter:SetBagSlotFree(button, freeCount)
	local theme = self:GetTheme()
	button.ahItem = nil
	button.ahSelect:Hide()
	button.ahNew:Hide()
	button.ahBorder:SetColorTexture(theme.borderStrong.r, theme.borderStrong.g, theme.borderStrong.b, 1)
	button.ahFill:Show()
	button.ahIcon:Hide()
	button.ahCount:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	button.ahCount:SetText(freeCount)
	button.ahCount:Show()
	button:SetAlpha(1)
end
