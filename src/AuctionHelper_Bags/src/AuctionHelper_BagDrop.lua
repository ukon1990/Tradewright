local _, ProfessionExporter = ...

-- "Make room" button of the bag window (E11 F95): when no normal bag slot is free, it deletes the
-- stack worth least, one stack per click. Junk goes on the first click; anything else must be
-- clicked twice. The stack is picked again at the moment of the click, never from an old redraw.

local CONFIRM_SECONDS = 5

local function auctionPriceOf(itemID)
	local pe = ProfessionExporter
	return pe.GetNativeAhPrice and pe:GetNativeAhPrice(itemID) or nil
end

--- Auction price of an item in copper, or nil when unknown.
function ProfessionExporter:GetBagItemAuctionPrice(itemID)
	return auctionPriceOf(itemID)
end

--- The stack that would be deleted to make room right now (BagLogic.CheapestToDrop), or nil.
function ProfessionExporter:GetBagDropCandidate()
	return self.BagLogic.CheapestToDrop(self:ScanBags().items, auctionPriceOf)
end

--- "Name x3 (30c)" for a stack to delete.
function ProfessionExporter:DescribeBagDrop(drop)
	local count = drop.item.count > 1 and (" x" .. drop.item.count) or ""
	return string.format("%s%s (%s)", drop.item.name, count, self:FormatCopperShort(drop.value))
end

--- Delete a stack. Only ever called from a click of the player.
function ProfessionExporter:DeleteBagStack(drop)
	ClearCursor()
	C_Container.PickupContainerItem(drop.item.bag, drop.item.slot)
	if CursorHasItem() then
		DeleteCursorItem()
		self:PrintMessage("Deleted " .. self:DescribeBagDrop(drop) .. ".")
	end
end

-- Junk is deleted at once. Another item is armed by the first click and deleted by a second click
-- on the same stack within CONFIRM_SECONDS.
local function onClick(button)
	local pe = ProfessionExporter
	local drop = pe:GetBagDropCandidate()
	if not drop then
		return
	end
	local key = drop.item.bag * 1000 + drop.item.slot
	local armed = button.armedKey == key and button.armedItem == drop.item.itemID and GetTime() - button.armedAt <= CONFIRM_SECONDS
	button.armedKey = nil
	if drop.isJunk or armed then
		pe:DeleteBagStack(drop)
	else
		button.armedKey, button.armedItem, button.armedAt = key, drop.item.itemID, GetTime()
		pe:PrintMessage("Not junk: click Make room again to delete " .. pe:DescribeBagDrop(drop) .. ".")
	end
	if GameTooltip:IsOwned(button) then
		button:GetScript("OnEnter")(button)
	end
end

local function onEnter(button)
	local pe = ProfessionExporter
	local theme = pe:GetTheme()
	local muted, danger = theme.textMuted, theme.danger
	local drop = pe:GetBagDropCandidate()
	GameTooltip:SetOwner(button, "ANCHOR_TOPLEFT")
	GameTooltip:SetText("Make room", 1, 1, 1)
	if not drop then
		GameTooltip:AddLine("Nothing here is safe to delete.", muted.r, muted.g, muted.b, true)
	else
		GameTooltip:AddLine("Deletes " .. pe:DescribeBagDrop(drop) .. ".", danger.r, danger.g, danger.b, true)
		GameTooltip:AddLine(drop.isJunk and "The junk stack a vendor pays least for. It cannot be undone."
			or "You have no junk, so this is your cheapest other stack. Click twice. It cannot be undone.",
			muted.r, muted.g, muted.b, true)
	end
	GameTooltip:Show()
end

--- The button, hidden until the bags are full.
function ProfessionExporter:CreateBagDropButton(parent)
	local button = self:CreateButton(parent, "Make room", onClick, { small = true })
	button:SetScript("OnEnter", onEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	return button
end
