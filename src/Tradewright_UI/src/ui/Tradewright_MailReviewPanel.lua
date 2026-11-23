local addonName, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Surplus review (mailbox panel → Review… on the surplus row): every item the surplus mail could send,
-- docked to the right of the mailbox panel. Keep amounts are edited in the row and saved per
-- character; unticking an item skips it for this mailbox visit only. Rows come from
-- MailLogic.BuildReviewRows, the same rows the surplus mail is built from.

local PAD = 12
local WIDTH = 520
local FILTERS = { { id = "sending", label = L["Sending"] }, { id = "kept", label = L["Kept"] }, { id = "all", label = L["All"] } }
local REASONS = {
	held = L["For your crafts"], kept = L["All kept"], skipped = L["Not this time"], othersOff = L["No keep amount set"],
	notReagent = L["Not a reagent"],
}
local KEEP_HINT = L["Type a number; while typing, mouse wheel adds or removes one stack. Shift-click: keep all. Ctrl-click: clear the keep amount."]

-- Numbers in rows that send nothing are greyed out.
local function cellText(pe, row, value)
	if row.group then
		return ""
	end
	return row.send > 0 and value or pe:Colorize(value, "textMuted")
end

local function showRowTooltip(pe, owner, row)
	if not row or row.group then
		return
	end
	local n = function(v) return pe:FormatNumberGrouped(v or 0) end
	pe:ShowItemRowTooltip(owner, row.itemID, {
		{ L["In bags"], n(row.bags) },
		{ L["Held for your queued crafts"], n(row.held) },
		{ L["Keep on this character"], row.keep and n(row.keep) or "-" },
		{ L["Sends to the bank character"], n(row.send) },
	}, KEEP_HINT)
end

-- Saves a keep amount and shows it in the box at once. The mouse wheel keeps typing focus.
local function setKeep(pe, box, amount, keepFocus)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	box.shown = amount > 0 and tostring(amount) or ""
	box:SetText(box.shown)
	if not keepFocus then
		box:ClearFocus()
	end
	pe:SetMailKeepAmount(box.row.itemID, amount)
	pe:RefreshMailPanel()
end

local function stackSize(pe, itemID)
	return math.max(1, pe:GetItemStackSize(itemID) or 1)
end

local function createKeepCell(pe, rowFrame)
	local box = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(6)
	box:SetJustifyH("RIGHT")
	pe:SkinEditBox(box)
	box:EnableMouseWheel(false)
	box:SetScript("OnEditFocusGained", function(self) self:EnableMouseWheel(true) end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(self.shown or "")
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self:EnableMouseWheel(false)
		if self.row and self:GetText() ~= (self.shown or "") then
			setKeep(pe, self, self:GetText())
		end
	end)
	box:SetScript("OnMouseWheel", function(self, delta)
		setKeep(pe, self, (tonumber(self:GetText()) or 0) + delta * stackSize(pe, self.row.itemID), true)
	end)
	box:SetScript("OnMouseDown", function(self)
		if IsShiftKeyDown() then
			setKeep(pe, self, math.max(self.row.bags, self.row.keep or 0))
		elseif IsControlKeyDown() then
			setKeep(pe, self, 0)
		end
	end)
	box:SetScript("OnEnter", function(self) showRowTooltip(pe, self, self.row) end)
	box:SetScript("OnLeave", GameTooltip_Hide)
	return box
end

local function keepColumn(pe)
	return {
		id = "keep", label = L["Keep"], justifyH = "RIGHT", width = 58,
		tooltipTitle = L["Keep on this character"], tooltipText = KEEP_HINT,
		createCell = function(rowFrame) return createKeepCell(pe, rowFrame) end,
		updateCell = function(box, row)
			box:SetShown(not row.group)
			box:SetHeight(18)
			-- While typing, the box stays bound to its item even if a refresh moves the rows.
			if box:HasFocus() then
				return
			end
			box.row = row
			if not row.group then
				box.shown = row.keep and tostring(row.keep) or ""
				box:SetText(box.shown)
			end
		end,
	}
end

local function tickColumn(pe)
	return {
		id = "tick", label = "", width = 24,
		createCell = function(rowFrame)
			local check = CreateFrame("CheckButton", nil, rowFrame, "UICheckButtonTemplate")
			pe:SkinCheckButton(check)
			check:SetScript("OnClick", function(self)
				pe:SetMailSkipped(self.row.itemID, not self:GetChecked())
				pe:RefreshMailPanel()
			end)
			return check
		end,
		updateCell = function(check, row)
			check:SetShown(not row.group)
			check:SetSize(18, 18)
			check.row = row
			check:SetChecked(row.reason ~= "skipped")
		end,
	}
end

-- The item column, with group rows ("Trade Goods · 24 items") in gold in place of an item.
local function itemColumn(pe)
	local column = pe:ItemColumn({ minWidth = 120, sortable = false })
	local update = column.updateCell
	column.updateCell = function(cell, row)
		cell.icon:SetShown(not row.group)
		if not row.group then
			return update(cell, row)
		end
		local gold = pe:GetTheme().gold
		cell.name:ClearAllPoints()
		cell.name:SetPoint("LEFT", cell, "LEFT", 5, 0)
		cell.name:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
		cell.name:SetText(string.format("%s · %d %s", row.label, row.count, pe:Plural(row.count, "item")))
		Tradewright:ColorText(cell.name, gold)
		cell.detail:Hide()
	end
	return column
end

local function worthText(pe, row)
	if row.group then
		return ""
	elseif row.send == 0 then
		return pe:Colorize(REASONS[row.reason] or "-", "textMuted")
	end
	return row.unitPrice and pe:FormatCopperShort(row.unitPrice * row.send) or "-"
end

local function numberColumn(pe, id, label, width, field)
	return { id = id, label = label, justifyH = "RIGHT", width = width,
		getText = function(row) return cellText(pe, row, row[field] and pe:FormatNumberGrouped(row[field]) or "-") end }
end

local function createTable(pe, f)
	f.table = pe:CreateReusableTable(f, {
		autoFitToScroll = true, rowHeight = 24, footer = true,
		emptyTitle = L["Nothing to review"], emptyHint = L["Your bags hold no sellable items."],
		onRowEnter = function(rowFrame, row) showRowTooltip(pe, rowFrame, row) end,
		onRowLeave = GameTooltip_Hide,
	})
	f.table:SetColumns({
		tickColumn(pe), itemColumn(pe),
		numberColumn(pe, "bags", "Bags", 44, "bags"),
		numberColumn(pe, "held", "Held", 44, "held"),
		keepColumn(pe),
		numberColumn(pe, "send", "Send", 48, "send"),
		{ id = "worth", label = L["Worth"], justifyH = "RIGHT", width = 96, getText = function(row) return worthText(pe, row) end },
	})
end

local function createHeader(pe, f)
	local theme = pe:GetTheme()
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -(theme.size.header / 2))
	pe:SkinCloseButton(close)
	close:SetScript("OnClick", function() pe:ToggleMailReviewPanel(false) end)
	f.meta = pe:CreateText(f, "GameFontHighlightSmall", "textMuted", "RIGHT")
	f.meta:SetPoint("RIGHT", close, "LEFT", -8, 0)
	f.title = pe:CreateText(f, "GameFontNormalLarge", "gold")
	f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(theme.size.header / 2) - 1)
	f.title:SetPoint("RIGHT", f.meta, "LEFT", -12, 0)
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", 1, -theme.size.header)
	rule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	rule:SetHeight(1)
	Tradewright:ColorTexture(rule, "borderSubtle", 1)
end

-- "Only crafting reagents" narrows the surplus for this mailbox visit, to stash reagents on the
-- bank character; the second box picks which reagents and is shared with the bag window's deposit.
local function createReagentChecks(pe, f)
	f.reagentsOnly = pe:CreateCheckbox(f, L["Only crafting reagents"], function(checked)
		pe:SetMailReagentsOnly(checked)
		pe:RefreshMailPanel()
	end)
	f.reagentsOnly:SetPoint("TOPLEFT", f.sendOthers, "BOTTOMLEFT", 0, 0)
	f.ownProfessions = pe:CreateCheckbox(f, L["only ones my professions use"], function(checked)
		pe:SetStashOnlyOwnProfessions(checked)
		pe:RefreshMailPanel()
	end)
	f.ownProfessions:SetPoint("LEFT", f.reagentsOnly, "RIGHT", 8, 0)
end

local function createToolbar(pe, f)
	local top = -(pe:GetTheme().size.header + 1 + PAD)
	f.filterButtons = {}
	local previous
	for i = #FILTERS, 1, -1 do
		local filter = FILTERS[i]
		local button = pe:CreateButton(f, filter.label, function()
			f.filter = filter.id
			pe:RefreshMailReviewPanel()
		end, { small = true, width = 84 })
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
		else
			button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, top)
		end
		button.filter = filter
		f.filterButtons[i], previous = button, button
	end
	f.search = pe:CreateSearchBox(f, L["Search items"], function(text)
		f.searchText = text
		pe:RefreshMailReviewPanel()
	end)
	f.search:SetPoint("LEFT", f, "TOPLEFT", PAD + 6, top - 11)
	f.search:SetPoint("RIGHT", previous, "LEFT", -10, 0)
	f.sendOthers = pe:CreateCheckbox(f, L["Send everything sellable, not just items with a keep amount"], function(checked)
		pe:SetMailSendOthers(checked)
		pe:RefreshMailPanel()
	end)
	f.sendOthers:SetPoint("TOPLEFT", f.search, "BOTTOMLEFT", -6, -8)
	createReagentChecks(pe, f)
end

-- Clear keeps asks for a second click within a few seconds.
local function confirmClearKeeps(pe, button)
	if button.armed then
		button.armed = nil
		pe:SetButtonLabel(button, L["Clear keep amounts"], false)
		pe:ClearMailKeepAmounts()
		pe:RefreshMailPanel()
		return
	end
	button.armed = true
	pe:SetButtonLabel(button, L["Click again to clear"], false)
	C_Timer.After(4, function()
		if button.armed then
			button.armed = nil
			pe:SetButtonLabel(button, L["Clear keep amounts"], false)
		end
	end)
end

local function createActions(pe, f)
	f.sendBtn = pe:CreateButton(f, L["Attach"], function()
		if f.dest then
			pe:StartMailSendQueue({ f.dest })
		end
	end, { primary = true })
	f.sendBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
	local clear = pe:CreateButton(f, L["Clear keep amounts"])
	clear:SetScript("OnClick", function(button) confirmClearKeeps(pe, button) end)
	clear:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
	local keepAll = pe:CreateButton(f, L["Keep what I have now"], function()
		pe:KeepCurrentMailBags()
		pe:RefreshMailPanel()
	end, { tooltip = L["Keep everything the bags hold now, so nothing goes until you have more."] })
	keepAll:SetPoint("LEFT", clear, "RIGHT", 8, 0)
	f.hint = pe:CreateText(f, "GameFontHighlightSmall", "textMuted")
	f.hint:SetPoint("BOTTOMLEFT", clear, "TOPLEFT", 0, 8)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
	f.hint:SetWordWrap(false)
	f.hint:SetText(L["Keep is saved for this character. Unticked items are skipped this visit only."])
end

local function ensurePanel(pe)
	if pe.ui.mailReviewPanel then
		return pe.ui.mailReviewPanel
	end
	local panel = pe.ui.mailPanel
	-- Parented to the mailbox, not the mail panel: the mail panel clips its children (StyleWindow),
	-- which would cut away a panel docked beside it. It still closes with the mail panel.
	local f = CreateFrame("Frame", addonName .. "MailReviewPanel", panel:GetParent(), "BackdropTemplate")
	panel:HookScript("OnHide", function() f:Hide() end)
	f:SetWidth(WIDTH)
	f:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
	f:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", 8, 0)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	pe:StyleWindow(f)
	f.filter, f.searchText = "all", ""
	createHeader(pe, f)
	createToolbar(pe, f)
	createActions(pe, f)
	createTable(pe, f)
	f.table.frame:SetPoint("TOPLEFT", f.reagentsOnly, "BOTTOMLEFT", 0, -6)
	f.table.frame:SetPoint("BOTTOMRIGHT", f.hint, "TOPRIGHT", 0, 8)
	pe:SkinTree(f)
	f:Hide()
	pe.ui.mailReviewPanel = f
	return f
end

function Tradewright:IsMailReviewPanelShown()
	local f = self.ui and self.ui.mailReviewPanel
	return f ~= nil and f:IsShown()
end

--- Opens or closes the review panel; `show` nil toggles. The choice is saved, so the panel opens
--- with the mailbox next time. The mailbox panel highlights its surplus row while it is open.
function Tradewright:ToggleMailReviewPanel(show)
	if not (self.ui and self.ui.mailPanel) then
		return
	end
	local f = ensurePanel(self)
	if show == nil then
		show = not f:IsShown()
	end
	self:SetSetting("mail.reviewPanelOpen", show)
	f:SetShown(show)
	self:RefreshMailPanel()
end

-- Shows the review panel again when it was open last time the mailbox closed: on opening the
-- mailbox, and on expanding a collapsed mailbox panel. Not on the seller (it has no surplus row).
local function restorePanel(pe, plan)
	local panel = pe.ui and pe.ui.mailPanel
	if not (pe:GetSetting("mail.reviewPanelOpen", false) and panel and panel:IsShown()) then
		return
	end
	local _, dest = pe:BuildMailReviewRows(plan)
	if dest then
		pe:ToggleMailReviewPanel(true)
	end
end

local function refreshControls(pe, f, sum)
	local counts = { sending = sum.sending, kept = sum.kept, all = sum.all }
	for _, button in ipairs(f.filterButtons) do
		button:SetText(string.format("%s (%d)", button.filter.label, counts[button.filter.id]))
		pe:StyleShellButton(button, f.filter == button.filter.id)
	end
	local sending = pe:EnsureMailSendQueueState().running
	local mails = f.dest and pe:CountMailParcels({ f.dest }) or 0
	pe:SetButtonLabel(f.sendBtn, string.format(L["Attach %s items · %d %s"], pe:FormatNumberGrouped(sum.send), mails,
		pe:Plural(mails, "mail")), false)
	f.sendBtn:SetEnabled(sum.send > 0 and not sending)
	f.sendOthers.check:SetChecked(pe:GetMailSendOthers())
	f.reagentsOnly.check:SetChecked(pe:GetMailReagentsOnly())
	f.ownProfessions.check:SetChecked(pe:GetStashOnlyOwnProfessions())
	f.ownProfessions:SetShown(pe:GetMailReagentsOnly())
end

-- Title "Surplus to <seller>", items and mails in the header, totals in the table footer.
local function refreshTexts(pe, f, sum, seller)
	f.title:SetText(string.format(L["Surplus to %s"], pe:GetMailCharacterLabel(seller)))
	f.meta:SetText(string.format(L["%d different items"], sum.all))
	local skipped = sum.skipped > 0 and string.format(L[" · %d skipped this time"], sum.skipped) or ""
	f.table:SetFooterText(string.format(L["%s to send%s"], pe:FormatNumberGrouped(sum.send), skipped),
		sum.worth > 0 and (string.format(L["about %s"], pe:FormatCopperShort(sum.worth))) or "")
end

--- Fills the panel when it is open; the mailbox panel calls this on every refresh with its plan.
function Tradewright:RefreshMailReviewPanel(plan)
	local f = self.ui and self.ui.mailReviewPanel
	if not f or not f:IsShown() then
		return restorePanel(self, plan)
	end
	local seller = self:GetSellerCharacterKey()
	if not seller or seller == self:GetCharacterKey() then
		f:Hide()
		return
	end
	local rows, dest = self:BuildMailReviewRows(plan)
	f.dest = dest
	local sum = dest and dest.summary or self.MailLogic.SummarizeReviewRows(rows)
	refreshControls(self, f, sum)
	f.table:SetRows(self.MailLogic.ListReviewRows(rows, f.filter, f.searchText, function(row)
		return self:GetItemFilterInfo(row.itemID).classLabel
	end))
	f.table:Refresh()
	refreshTexts(self, f, sum, seller)
end
