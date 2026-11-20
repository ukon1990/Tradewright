local addonName, ProfessionExporter = ...

-- Mail panel: retail always; Forever when send-mail + bag APIs exist.
if not ProfessionExporter.IS_RETAIL then
	if not (ProfessionExporter.IS_FOREVER and C_Container and C_Container.GetContainerNumSlots and GetSendMailItem and ClickSendMailItemButton) then
		return
	end
end

local ATTACHMENTS_MAX = ATTACHMENTS_MAX_SEND or 12
local AUTO_SEND_DELAY = 0.5
local AUTO_SEND_TIMEOUT = 6
local MAIL_SUBJECT = "AuctionHelper mats"
local MAIL_BODY = "Materials from AuctionHelper shopping cart."

function ProfessionExporter:GetMailCharacterLabel(characterKey)
	if self.GetDashboardSidebarCharacterLabel then
		return self:GetDashboardSidebarCharacterLabel(characterKey, self.db and self.db.characters and self.db.characters[characterKey],
			self:GetCharacterKey())
	end
	return tostring(characterKey or "?"):match("^([^%-]+)") or tostring(characterKey or "?")
end


-- One line saying what this character is in the mail loop.
local function roleText(pe)
	local seller = pe.GetSellerCharacterKey and pe:GetSellerCharacterKey()
	if not seller then
		return "No auction house / bank character is set for this realm. Choose one in Settings."
	elseif seller == pe:GetCharacterKey() then
		return "This is your auction house / bank character."
	end
	return "Crafter. Your auction house / bank character is " .. pe:GetMailCharacterLabel(seller) .. "."
end

local function clearMailAttachments()
	for i = 1, ATTACHMENTS_MAX do
		if GetSendMailItem and GetSendMailItem(i) then
			ClickSendMailItemButton(i)
		end
	end
end

local function findBagSlotForItem(itemID)
	for bag = 0, 4 do
		local slots = C_Container.GetContainerNumSlots(bag)
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and tonumber(info.itemID) == tonumber(itemID) and (tonumber(info.stackCount) or 0) > 0 then
				return bag, slot, tonumber(info.stackCount) or 0
			end
		end
	end
	return nil
end

local function attachItemQuantity(itemID, quantity)
	quantity = math.max(1, math.floor(tonumber(quantity) or 0))
	local remaining = quantity
	while remaining > 0 do
		local bag, slot, stack = findBagSlotForItem(itemID)
		if not bag then
			return false, quantity - remaining
		end
		local take = math.min(remaining, stack)
		if take < stack and C_Container.SplitContainerItem then
			C_Container.SplitContainerItem(bag, slot, take)
			bag, slot = findBagSlotForItem(itemID)
			if not bag then
				return false, quantity - remaining
			end
		end
		C_Container.PickupContainerItem(bag, slot)
		ClickSendMailItemButton()
		remaining = remaining - take
	end
	return true, quantity
end

-- Largest stack of an item by ID. C_Item.GetItemMaxStackSize wants an item location, not an ID.
local function itemStackSize(itemID)
	local size = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
	if not size and GetItemInfo then
		size = select(8, GetItemInfo(itemID))
	end
	return tonumber(size)
end

function ProfessionExporter:GetItemStackSize(itemID)
	return itemStackSize(itemID)
end

local function buildMailParcels(destinations)
	local parcels = {}
	for _, dest in ipairs(destinations or {}) do
		local parcelItems = {}
		local parcelCount = 0
		local function flush()
			if #parcelItems > 0 then
				parcels[#parcels + 1] = {
					mailName = dest.mailName,
					characterKey = dest.characterKey,
					kind = dest.kind,
					items = parcelItems,
				}
				parcelItems = {}
				parcelCount = 0
			end
		end
		for _, item in ipairs(dest.items or {}) do
			local qtyLeft = tonumber(item.quantity) or 0
			while qtyLeft > 0 do
				if parcelCount >= ATTACHMENTS_MAX then
					flush()
				end
				local attachQty = math.min(qtyLeft, itemStackSize(item.itemID) or 200)
				parcelItems[#parcelItems + 1] = {
					itemID = item.itemID,
					quantity = attachQty,
					name = item.name,
				}
				parcelCount = parcelCount + 1
				qtyLeft = qtyLeft - attachQty
			end
		end
		flush()
	end
	return parcels
end

--- How many mails the destinations take (12 attachments each, stacks split at their size).
function ProfessionExporter:CountMailParcels(destinations)
	return #buildMailParcels(destinations)
end

function ProfessionExporter:EnsureMailSendQueueState()
	self._mailSendQueue = self._mailSendQueue or {
		parcels = {},
		index = 0,
		running = false,
		cancel = false,
		sent = 0,
		total = 0,
	}
	return self._mailSendQueue
end

--- Stops the queue at once. A send the client never answers would otherwise leave it running.
function ProfessionExporter:CancelMailSendQueue()
	local st = self:EnsureMailSendQueueState()
	st.cancel = true
	st.running = false
	if self.ui and self.ui.mailPanel and self.ui.mailPanel:IsShown() then
		self:RefreshMailPanel()
	end
end

function ProfessionExporter:AdvanceMailSendQueue(success)
	local st = self:EnsureMailSendQueueState()
	if not st.running then
		return
	end
	if success then
		st.sent = (st.sent or 0) + 1
		local parcel = st.parcels and st.parcels[st.index]
		if parcel and self.OnMailParcelSent then
			self:OnMailParcelSent(parcel)
		end
	end
	st.index = (st.index or 0) + 1
	if st.cancel or st.index > #(st.parcels or {}) then
		st.running = false
		if st.auto and MailFrameTab1 and MailFrameTab1.Click then
			MailFrameTab1:Click()
		end
		if self.RefreshMailPanel then
			self:RefreshMailPanel()
		end
		if st.sent and st.sent > 0 then
			self:PrintMessage(string.format("AuctionHelper mailed %d parcel(s).", st.sent))
		end
		if self.ScheduleLiveInventoryRefresh then
			self:ScheduleLiveInventoryRefresh()
		end
		return
	end
	C_Timer.After(0.35, function()
		ProfessionExporter:ProcessNextMailParcel()
	end)
end

function ProfessionExporter:ProcessNextMailParcel()
	local st = self:EnsureMailSendQueueState()
	if st.cancel or not st.running then
		st.running = false
		return
	end
	local parcel = st.parcels and st.parcels[st.index]
	if not parcel then
		self:AdvanceMailSendQueue(false)
		return
	end
	if self.RefreshMailPanel then
		self:RefreshMailPanel()
	end
	if not MailFrame or not MailFrame:IsShown() then
		self:PrintMessage("Open the mailbox to send materials.")
		st.running = false
		st.cancel = true
		return
	end
	if MailFrameTab2 and MailFrameTab2.Click then
		MailFrameTab2:Click()
	end
	clearMailAttachments()
	for _, item in ipairs(parcel.items or {}) do
		local ok = attachItemQuantity(item.itemID, item.quantity)
		if not ok then
			self:PrintMessage(string.format("Could not attach all of %s for %s.", tostring(item.name or item.itemID), tostring(parcel.mailName)))
		end
	end
	if SendMail then
		SendMail(parcel.mailName, MAIL_SUBJECT, MAIL_BODY)
	end
	-- An automatic send has no click behind it. If the client ignores it, hand back to the buttons.
	if st.auto then
		local index = st.index
		C_Timer.After(AUTO_SEND_TIMEOUT, function()
			if st.running and st.auto and st.index == index then
				clearMailAttachments()
				ProfessionExporter:CancelMailSendQueue()
				ProfessionExporter:PrintMessage("Could not mail the materials automatically. Use Send all in the mail panel.")
			end
		end)
	end
end

function ProfessionExporter:StartMailSendQueue(destinations, auto)
	local parcels = buildMailParcels(destinations)
	if #parcels == 0 then
		if not auto then
			self:PrintMessage("No materials to mail from your bags.")
		end
		return false
	end
	local st = self:EnsureMailSendQueueState()
	st.parcels = parcels
	st.index = 1
	st.sent = 0
	st.total = #parcels
	st.running = true
	st.cancel = false
	st.auto = auto == true
	self:ProcessNextMailParcel()
	return true
end

--- On the auction house / bank character, mails every crafter whose materials are all in the bags.
--- Runs once per mailbox visit; incomplete sets wait for the Send buttons.
function ProfessionExporter:AutoSendReadyMaterials()
	if not (self.IsSellerCharacter and self:IsSellerCharacter()) or self:GetSetting("mail.autoSendMaterials", true) == false
		or self:EnsureMailSendQueueState().running then
		return
	end
	local ready, names = {}, {}
	for _, dest in ipairs(self:BuildShoppingMailSendPlan()) do
		if dest.complete then
			ready[#ready + 1] = dest
			names[#names + 1] = string.format("%s (%s)", self:GetMailCharacterLabel(dest.characterKey), self:FormatNumberGrouped(dest.totalQuantity))
		end
	end
	if self:StartMailSendQueue(ready, true) then
		self:PrintMessage("Mailing collected materials to " .. table.concat(names, ", ") .. ".")
	end
end

function ProfessionExporter:StartMailSendAll()
	return self:StartMailSendQueue(self:BuildMailPanelPlan())
end

local MAIL_PAD = 12
local MAIL_ROW = 48
local ROW_TITLES = { crafts = "Crafted items to ", surplus = "Surplus to " }

-- Tooltip lines for a list of items: name in `color`, count in `valueColor`, `suffix` after each name.
local function addItemLines(pe, items, color, valueColor, suffix)
	for _, it in ipairs(items or {}) do
		GameTooltip:AddDoubleLine((it.name or "?") .. suffix, pe:FormatNumberGrouped(it.quantity or 0),
			color.r, color.g, color.b, valueColor.r, valueColor.g, valueColor.b)
	end
end

local function showDestTooltip(pe, row)
	if not row.dest then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText("To " .. pe:GetMailCharacterLabel(row.dest.characterKey), 1, 1, 1)
	local muted = pe:GetTheme().textMuted
	local danger = pe:GetTheme().danger
	addItemLines(pe, row.dest.items, muted, { r = 1, g = 1, b = 1 }, "")
	addItemLines(pe, row.dest.missing, danger, danger, " (not in bags)")
	if row.dest.kind == "surplus" then
		GameTooltip:AddLine("Click to review and change what goes.", muted.r, muted.g, muted.b, true)
	end
	GameTooltip:Show()
end

-- One destination: character and item count, the first items, and a Send button.
local function createMailRow(pe, parent)
	local row = pe:CreateInset(parent)
	row:SetHeight(MAIL_ROW - 6)
	row.send = pe:CreateButton(row, "Send", nil, { small = true })
	row.send:SetPoint("RIGHT", -8, 0)
	row.name = pe:CreateText(row, "GameFontHighlightSmall")
	row.name:SetPoint("TOPLEFT", 10, -8)
	row.name:SetPoint("RIGHT", row.send, "LEFT", -10, 0)
	row.items = pe:CreateText(row, "GameFontHighlightSmall", "textMuted")
	row.items:SetPoint("BOTTOMLEFT", 10, 8)
	row.items:SetPoint("RIGHT", row.send, "LEFT", -10, 0)
	-- The surplus row opens the review panel; gold outline while it is open.
	local gold = pe:GetTheme().gold
	row.openFill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.openFill:SetAllPoints()
	row.openFill:SetColorTexture(gold.r, gold.g, gold.b, 0.07)
	row:EnableMouse(true)
	row:SetScript("OnMouseUp", function(self)
		if self.dest and self.dest.kind == "surplus" then
			pe:ToggleMailReviewPanel()
		end
	end)
	row:SetScript("OnEnter", function(self) showDestTooltip(pe, self) end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

-- "Surplus to Bånkey · 214 items · ready" with the count muted and the state coloured.
local function destTitle(pe, dest)
	local theme = pe:GetTheme()
	local muted, state = theme.textMuted, dest.complete ~= false and theme.success or theme.warning
	local title = (ROW_TITLES[dest.kind] or "") .. pe:GetMailCharacterLabel(dest.characterKey)
	return string.format("%s |cff%02x%02x%02x· %s items|r |cff%02x%02x%02x· %s|r", title,
		muted.r * 255, muted.g * 255, muted.b * 255, pe:FormatNumberGrouped(dest.totalQuantity or 0),
		state.r * 255, state.g * 255, state.b * 255, dest.complete ~= false and "ready" or (#dest.missing .. " still missing"))
end

-- "Runecloth x100, Heavy Leather x60 and 36 more".
local function destItemsText(pe, items)
	local parts = {}
	for j = 1, math.min(3, #items) do
		parts[#parts + 1] = string.format("%s x%s", items[j].name or "?", pe:FormatNumberGrouped(items[j].quantity or 0))
	end
	if #items > 3 then
		parts[#parts + 1] = string.format("and %d more", #items - 3)
	end
	return table.concat(parts, ", ")
end

-- Fills one destination row: title, count and state, the first three items, and Send.
local function fillMailRow(pe, row, dest)
	row.dest = dest
	row.name:SetText(destTitle(pe, dest))
	row.items:SetText(destItemsText(pe, dest.items or {}))
	row.send:SetScript("OnClick", function()
		ProfessionExporter:StartMailSendQueue({ dest })
	end)
	row.openFill:SetShown(dest.kind == "surplus" and pe:IsMailReviewPanelShown())
	row:Show()
end

function ProfessionExporter:EnsureMailPanel()
	self.ui = self.ui or {}
	if self.ui.mailPanel and self.ui.mailPanel:IsObjectType("Frame") then
		return self.ui.mailPanel
	end
	local mail = _G.MailFrame
	if not mail then
		return nil
	end
	local pe = self
	local theme = self:GetTheme()
	local panel = CreateFrame("Frame", addonName .. "MailPanel", mail, "BackdropTemplate")
	panel:SetWidth(320)
	panel:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, -20)
	panel:SetPoint("BOTTOMLEFT", mail, "BOTTOMRIGHT", 8, 16)
	self:StyleWindow(panel)
	panel:SetClampedToScreen(true)
	panel:Hide()

	-- Header: title and the collapse button.
	local collapse = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	collapse:ClearAllPoints()
	collapse:SetPoint("RIGHT", panel, "TOPRIGHT", -6, -(theme.size.header / 2))
	self:SkinCloseButton(collapse)
	collapse:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Collapse the mail panel", 1, 1, 1)
		GameTooltip:Show()
	end)
	collapse:SetScript("OnLeave", GameTooltip_Hide)
	panel.toggleBtn = collapse
	local title = self:CreateText(panel, "GameFontNormalLarge", "gold")
	title:SetPoint("LEFT", panel, "TOPLEFT", MAIL_PAD, -(theme.size.header / 2) - 1)
	title:SetPoint("RIGHT", collapse, "LEFT", -12, 0)
	title:SetText("AuctionHelper mail")
	local headerRule = panel:CreateTexture(nil, "BORDER")
	headerRule:SetPoint("TOPLEFT", 1, -theme.size.header)
	headerRule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	headerRule:SetHeight(1)
	headerRule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)

	-- Shown in place of the panel when it is collapsed: one small button at the mailbox edge.
	local expand = self:CreateButton(mail, "AuctionHelper", nil, { small = true })
	expand:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, -20)
	expand:Hide()
	panel.collapseTab = expand

	-- Footer: how much is ready.
	panel.footer = CreateFrame("Frame", nil, panel)
	panel.footer:SetPoint("BOTTOMLEFT", 1, 1)
	panel.footer:SetPoint("BOTTOMRIGHT", -1, 1)
	panel.footer:SetHeight(theme.size.footer)
	local footerRule = panel.footer:CreateTexture(nil, "BORDER")
	footerRule:SetPoint("TOPLEFT")
	footerRule:SetPoint("TOPRIGHT")
	footerRule:SetHeight(1)
	footerRule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	panel.footerText = self:CreateText(panel.footer, "GameFontHighlightSmall", "textMuted")
	panel.footerText:SetPoint("LEFT", MAIL_PAD, 0)
	panel.footerText:SetPoint("RIGHT", -MAIL_PAD, 0)

	-- Actions above the footer: Send all and Cancel; progress above them while sending.
	local actions = CreateFrame("Frame", nil, panel)
	actions:SetPoint("BOTTOMLEFT", panel.footer, "TOPLEFT", MAIL_PAD - 1, MAIL_PAD)
	actions:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(MAIL_PAD - 1), MAIL_PAD)
	actions:SetHeight(26)
	panel.cancelBtn = self:CreateButton(actions, "Cancel", function() pe:CancelMailSendQueue() end)
	panel.cancelBtn:SetPoint("RIGHT")
	panel.sendAllBtn = self:CreateButton(actions, "Send all", function() pe:StartMailSendAll() end, { primary = true })
	panel.sendAllBtn:SetPoint("LEFT")
	panel.sendAllBtn:SetPoint("RIGHT", panel.cancelBtn, "LEFT", -8, 0)
	panel.progressRow = CreateFrame("Frame", nil, panel)
	panel.progressRow:SetPoint("BOTTOMLEFT", actions, "TOPLEFT", 0, 8)
	panel.progressRow:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", 0, 8)
	panel.progressRow:SetHeight(18)
	panel.progressText = self:CreateText(panel.progressRow, "GameFontHighlightSmall")
	panel.progressText:SetPoint("LEFT")
	panel.progressText:SetWidth(110)
	panel.progressBar = CreateFrame("StatusBar", nil, panel.progressRow)
	panel.progressBar:SetPoint("LEFT", panel.progressText, "RIGHT", 8, 0)
	panel.progressBar:SetPoint("RIGHT")
	self:StyleProgressBar(panel.progressBar)

	-- Body: one sentence, then the destination list.
	panel.summary = self:CreateParagraph(panel)
	panel.summary:SetPoint("TOPLEFT", panel, "TOPLEFT", MAIL_PAD, -(theme.size.header + 1 + MAIL_PAD))
	panel.summary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MAIL_PAD, -(theme.size.header + 1 + MAIL_PAD))
	panel.summary:SetText("Reagents in your bags that your queue needs on other characters.")
	-- Crafters only: what else goes to the seller. Collapses to nothing on the seller.
	panel.surplusRow = CreateFrame("Frame", nil, panel)
	panel.surplusRow:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -8)
	panel.surplusRow:SetPoint("TOPRIGHT", panel.summary, "BOTTOMRIGHT", 0, -8)
	panel.sendOthers = self:CreateCheckbox(panel.surplusRow, "Send other sellable items", function(checked)
		pe:SetMailSendOthers(checked)
		pe:RefreshMailPanel()
	end)
	panel.sendOthers:SetPoint("LEFT")
	local scroll = CreateFrame("ScrollFrame", addonName .. "MailPanelScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel.surplusRow, "BOTTOMLEFT", 0, -10)
	scroll:SetPoint("BOTTOMRIGHT", panel.progressRow, "TOPRIGHT", -14, 10)
	panel.scroll = scroll
	panel.content = CreateFrame("Frame", nil, scroll)
	panel.content:SetSize(260, 200)
	scroll:SetScrollChild(panel.content)
	scroll:SetScript("OnSizeChanged", function(_, width)
		panel.content:SetWidth(width)
	end)
	panel.empty = self:CreateEmptyState(panel)
	panel.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT")
	panel.empty:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 14, 0)
	panel.empty:SetMessage("Nothing to mail", "Your bags hold nothing to send to another character.")
	panel.rows = {}
	self:SkinTree(panel)

	local function applyExpanded(expanded)
		expanded = expanded ~= false
		pe:SetSetting("mail.sidePanelExpanded", expanded)
		panel:SetShown(expanded)
		expand:SetShown(not expanded)
	end
	collapse:SetScript("OnClick", function() applyExpanded(false) end)
	expand:SetScript("OnClick", function()
		applyExpanded(true)
		pe:RefreshMailPanel()
	end)

	panel.applyExpanded = applyExpanded
	self.ui.mailPanel = panel
	return panel
end

function ProfessionExporter:RefreshMailPanel()
	local panel = self:EnsureMailPanel()
	if not panel then
		return
	end
	if not _G.MailFrame or not MailFrame:IsShown() then
		panel:Hide()
		panel.collapseTab:Hide()
		return
	end
	local expanded = self:GetSetting("mail.sidePanelExpanded", true)
	panel.applyExpanded(expanded)

	panel.summary:SetText(roleText(self))
	local seller = self:GetSellerCharacterKey()
	local crafter = seller ~= nil and seller ~= self:GetCharacterKey()
	panel.surplusRow:SetShown(crafter)
	panel.surplusRow:SetHeight(crafter and 26 or 1)
	if crafter then
		panel.sendOthers.check:SetChecked(self:GetMailSendOthers())
	end
	local plan = self:BuildMailPanelPlan()
	local itemCount = 0
	for index, dest in ipairs(plan) do
		itemCount = itemCount + (tonumber(dest.totalQuantity) or 0)
		local row = panel.rows[index]
		if not row then
			row = createMailRow(self, panel.content)
			panel.rows[index] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -((index - 1) * MAIL_ROW))
		row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0, -((index - 1) * MAIL_ROW))
		fillMailRow(self, row, dest)
	end
	for index = #plan + 1, #panel.rows do
		panel.rows[index]:Hide()
	end
	panel.content:SetHeight(math.max(MAIL_ROW, #plan * MAIL_ROW))
	panel.empty:SetShown(#plan == 0)
	panel.footerText:SetText(#plan == 0 and "No mail pending" or string.format("%d %s · %s items ready",
		#plan, #plan == 1 and "character" or "characters", self:FormatNumberGrouped(itemCount)))

	local st = self:EnsureMailSendQueueState()
	local sending = st.running and st.total and st.total > 0
	panel.progressRow:SetShown(sending and true or false)
	if sending then
		local done = math.min(st.total, math.max(0, (st.index or 1) - 1))
		panel.progressBar:SetMinMaxValues(0, st.total)
		panel.progressBar:SetValue(done)
		panel.progressText:SetText(string.format("Sending %d of %d", done, st.total))
	end
	panel.sendAllBtn:SetEnabled(#plan > 0 and not sending)
	panel.cancelBtn:SetEnabled(st.running == true)
	self:RefreshMailReviewPanel(plan)
end

function ProfessionExporter:OnMailFrameShow()
	if self.EnsureMailPanel then
		self:EnsureMailPanel()
	end
	if self.RefreshMailPanel then
		self:RefreshMailPanel()
	end
	C_Timer.After(AUTO_SEND_DELAY, function()
		if MailFrame:IsShown() then
			ProfessionExporter:AutoSendReadyMaterials()
		end
	end)
end

function ProfessionExporter:OnMailFrameHide()
	local panel = self.ui and self.ui.mailPanel
	if panel then
		panel:Hide()
	end
	self:ClearMailSkipped()
	if panel and self.ui.mailReviewPanel then
		self.ui.mailReviewPanel:Hide()
	end
	if self.CancelMailSendQueue then
		self:CancelMailSendQueue()
	end
end

function ProfessionExporter:OnMailSendSuccess()
	self:AdvanceMailSendQueue(true)
end

function ProfessionExporter:OnMailSendFailed()
	self:PrintMessage("Mail send failed.")
	self:AdvanceMailSendQueue(false)
end

function ProfessionExporter:InitMailPanelHooks()
	if self._mailPanelHooks then
		return
	end
	self._mailPanelHooks = true
	local mail = _G.MailFrame
	if mail and mail.HookScript then
		mail:HookScript("OnShow", function()
			ProfessionExporter:OnMailFrameShow()
		end)
		mail:HookScript("OnHide", function()
			ProfessionExporter:OnMailFrameHide()
		end)
	end
end
