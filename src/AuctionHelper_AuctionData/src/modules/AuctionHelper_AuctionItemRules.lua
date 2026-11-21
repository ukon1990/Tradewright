-- Per-item auction rules (keep in bags, ignore) and the small Keep in bags window.
local addonName, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local normalizeItemID = shared.normalizeItemID
local shallowCopy = shared.shallowCopy

function AuctionHelper:GetAuctionItemRule(itemID)
	local auction = self:InitAuctionDB()
	itemID = normalizeItemID(itemID)
	if not auction or not itemID then
		return nil
	end
	local rules = auction.rules and auction.rules.byItemID or nil
	local rule = rules and rules[tostring(itemID)] or nil
	return rule and shallowCopy(rule) or nil
end

function AuctionHelper:SetAuctionItemRule(itemID, updates)
	local auction = self:InitAuctionDB()
	itemID = normalizeItemID(itemID)
	if not auction or not itemID then
		return false
	end
	auction.rules = auction.rules or {}
	auction.rules.byItemID = auction.rules.byItemID or {}
	local key = tostring(itemID)
	local rule = auction.rules.byItemID[key] or {}
	for field, value in pairs(updates or {}) do
		if value == nil then
			rule[field] = nil
		else
			rule[field] = value
		end
	end
	if rule.ignore ~= true then
		rule.ignore = nil
	end
	local reserveQty = tonumber(rule.reserveQty)
	if reserveQty and reserveQty > 0 then
		rule.reserveQty = math.max(0, math.floor(reserveQty))
	else
		rule.reserveQty = nil
	end
	if next(rule) == nil then
		auction.rules.byItemID[key] = nil
	else
		rule.updatedAt = AuctionHelper:Now()
		auction.rules.byItemID[key] = rule
	end
	return true
end

function AuctionHelper:ClearAuctionItemRule(itemID)
	local auction = self:InitAuctionDB()
	itemID = normalizeItemID(itemID)
	if not auction or not itemID or not auction.rules or not auction.rules.byItemID then
		return false
	end
	auction.rules.byItemID[tostring(itemID)] = nil
	return true
end

function AuctionHelper:GetSelectedAuctionPanelItemID()
	local state = self:GetState()
	return normalizeItemID(state and (state.auctionPanelSelectedItemID or state.auctionLastSellSelectionItemID))
end

function AuctionHelper:RefreshAuctionPanelRules()
	local selectedItemID = self:GetSelectedAuctionPanelItemID()
	local rowState = self:GetAuctionRowProtectionState(selectedItemID, 0)
	local panel = self.ui and self.ui.auctionPanel or nil
	if not panel then
		return
	end
	if panel.btnIgnoreItem then
		panel.btnIgnoreItem:SetEnabled(selectedItemID ~= nil)
		panel.btnIgnoreItem:SetText((rowState.ignored == true) and "Unignore" or "Ignore")
	end
	if panel.btnReserveItem then
		panel.btnReserveItem:SetEnabled(selectedItemID ~= nil)
		if rowState.reserveQty and rowState.reserveQty > 0 then
			panel.btnReserveItem:SetText("Keep " .. tostring(rowState.reserveQty))
		else
			panel.btnReserveItem:SetText("Keep...")
		end
	end
	if panel.btnClearRule then
		panel.btnClearRule:SetEnabled(selectedItemID ~= nil and (rowState.ignored == true or (rowState.reserveQty or 0) > 0))
	end
end

function AuctionHelper:ApplyAuctionReserve(itemID, value)
	local qty = math.max(0, math.floor(tonumber(value) or 0))
	self:SetAuctionItemRule(itemID, { reserveQty = qty > 0 and qty or nil })
	self:DebugLog("AH", "rule reserve set", { string.format("itemID=%d reserveQty=%d", itemID, qty) })
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
end

-- Small "Keep in bags" window beside the auction panel. It always acts on the item it was last opened
-- for (the old StaticPopup kept the first item it was ever shown with).
function AuctionHelper:EnsureAuctionReserveWindow()
	if self._auctionReserveWindow then
		return self._auctionReserveWindow
	end
	local pe = self
	local theme = self:GetTheme()
	local f = CreateFrame("Frame", addonName .. "AuctionReserveWindow", UIParent, "BackdropTemplate")
	f:SetSize(300, theme.size.header + 1 + 12 + 18 + 10 + 14 + 4 + 26 + 12 + 26 + 12)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	self:StyleWindow(f)
	tinsert(UISpecialFrames, f:GetName())
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:ClearAllPoints()
	f.close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -(theme.size.header / 2))
	self:SkinCloseButton(f.close)
	f.close:SetScript("OnClick", function() f:Hide() end)
	f.title = self:CreateText(f, "GameFontNormalLarge", "gold")
	f.title:SetPoint("LEFT", f, "TOPLEFT", 12, -(theme.size.header / 2) - 1)
	f.title:SetPoint("RIGHT", f.close, "LEFT", -12, 0)
	f.title:SetText("Keep in bags")
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", 1, -theme.size.header)
	rule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	rule:SetHeight(1)
	rule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)

	f.icon = self:CreateItemIcon(f)
	f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(theme.size.header + 13))
	f.itemName = self:CreateText(f, "GameFontHighlightSmall")
	f.itemName:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
	f.itemName:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	f.label = self:CreateText(f, "GameFontHighlightSmall", "textMuted")
	f.label:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", 0, -10)
	f.input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.input:SetHeight(22)
	f.input:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 6, -6)
	f.input:SetPoint("RIGHT", f, "RIGHT", -18, 0)
	f.input:SetAutoFocus(false)
	f.input:SetNumeric(true)
	f.input:SetMaxLetters(6)
	self:SkinEditBox(f.input)
	local function accept()
		if f.itemID and f.onAccept then
			f.onAccept(f.itemID, f.input:GetText())
		end
		f:Hide()
	end
	f.input:SetScript("OnEnterPressed", accept)
	f.input:SetScript("OnEscapePressed", function() f:Hide() end)
	f.keep = self:CreateButton(f, "Keep", accept, { primary = true })
	f.keep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
	f.cancel = self:CreateButton(f, "Cancel", function() f:Hide() end)
	f.cancel:SetPoint("RIGHT", f.keep, "LEFT", -8, 0)
	f.input:HookScript("OnTextChanged", function()
		local keepQuantity = tonumber(f.input:GetText()) or 0
		pe:SetButtonLabel(f.keep, keepQuantity > 0 and ("Keep " .. keepQuantity) or "Remove keep")
	end)
	f:Hide()
	self._auctionReserveWindow = f
	return f
end

function AuctionHelper:ShowAuctionReservePrompt(itemID)
	itemID = normalizeItemID(itemID)
	if not itemID then
		self:PrintMessage("Select an auction row first.")
		return
	end
	local current = tonumber((self:GetAuctionItemRule(itemID) or {}).reserveQty) or 0
	self:ShowKeepPrompt(itemID, "Never post below this many", current, self.ui and self.ui.auctionPanel, function(id, text)
		self:ApplyAuctionReserve(id, text)
	end)
end

--- The "Keep in bags" prompt for any keep rule: `label` under the item, the `current` amount, shown
--- over `anchor` when that is visible, and `onAccept(itemID, text)` when the player confirms.
function AuctionHelper:ShowKeepPrompt(itemID, label, current, anchor, onAccept)
	local f = self:EnsureAuctionReserveWindow()
	f.itemID = itemID
	f.onAccept = onAccept
	f.label:SetText(label)
	f.icon:SetItem(itemID)
	local _, color = self:GetItemLook(itemID)
	f.itemName:SetText(self:GetItemDisplayName(itemID))
	f.itemName:SetTextColor(color.r, color.g, color.b)
	f.input:SetText(current > 0 and tostring(current) or "")
	f:ClearAllPoints()
	if anchor and anchor:IsShown() then
		f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 40, -120)
	else
		f:SetPoint("CENTER")
	end
	f:Show()
	f.input:SetFocus()
	f.input:HighlightText()
end
