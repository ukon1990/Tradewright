local addonName, ProfessionExporter = ...

-- Mail panel: retail always; Forever when send-mail + bag APIs exist.
if not ProfessionExporter.IS_RETAIL then
	if not (ProfessionExporter.IS_FOREVER and C_Container and C_Container.GetContainerNumSlots and GetSendMailItem and ClickSendMailItemButton) then
		return
	end
end

local ATTACHMENTS_MAX = ATTACHMENTS_MAX_SEND or 12
local MAIL_SUBJECT = "AuctionHelper mats"
local MAIL_BODY = "Materials from AuctionHelper shopping cart."

local function characterLabel(pe, characterKey)
	if pe.GetDashboardSidebarCharacterLabel then
		return pe:GetDashboardSidebarCharacterLabel(characterKey, pe.db and pe.db.characters and pe.db.characters[characterKey], pe:GetCharacterKey())
	end
	return tostring(characterKey or "?"):match("^([^%-]+)") or tostring(characterKey or "?")
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
			bag, slot, stack = findBagSlotForItem(itemID)
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
				local attachQty = qtyLeft
				local maxStack = 200
				if C_Item and C_Item.GetItemMaxStackSize then
					maxStack = C_Item.GetItemMaxStackSize(item.itemID) or maxStack
				end
				attachQty = math.min(attachQty, maxStack)
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

function ProfessionExporter:CancelMailSendQueue()
	local st = self:EnsureMailSendQueueState()
	st.cancel = true
end

function ProfessionExporter:AdvanceMailSendQueue(success)
	local st = self:EnsureMailSendQueueState()
	if not st.running then
		return
	end
	if success then
		st.sent = (st.sent or 0) + 1
	end
	st.index = (st.index or 0) + 1
	if st.cancel or st.index > #(st.parcels or {}) then
		st.running = false
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
end

function ProfessionExporter:StartMailSendQueue(destinations)
	local parcels = buildMailParcels(destinations)
	if #parcels == 0 then
		self:PrintMessage("No materials to mail from your bags.")
		return false
	end
	local st = self:EnsureMailSendQueueState()
	st.parcels = parcels
	st.index = 1
	st.sent = 0
	st.total = #parcels
	st.running = true
	st.cancel = false
	self:ProcessNextMailParcel()
	return true
end

function ProfessionExporter:StartMailSendAll()
	local plan = self.BuildShoppingMailSendPlan and self:BuildShoppingMailSendPlan() or {}
	return self:StartMailSendQueue(plan)
end

function ProfessionExporter:StartMailSendForCharacter(characterKey)
	characterKey = tostring(characterKey or "")
	local plan = self.BuildShoppingMailSendPlan and self:BuildShoppingMailSendPlan() or {}
	local filtered = {}
	for _, dest in ipairs(plan) do
		if tostring(dest.characterKey) == characterKey then
			filtered[#filtered + 1] = dest
		end
	end
	return self:StartMailSendQueue(filtered)
end

local MAIL_PAD = 12
local MAIL_ROW = 48

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
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if not self.dest then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(characterLabel(pe, self.dest.characterKey), 1, 1, 1)
		local muted = pe:GetTheme().textMuted
		for _, it in ipairs(self.dest.items or {}) do
			GameTooltip:AddDoubleLine(it.name or "?", pe:FormatNumberGrouped(it.quantity or 0), muted.r, muted.g, muted.b, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
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
	local scroll = CreateFrame("ScrollFrame", addonName .. "MailPanelScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -10)
	scroll:SetPoint("BOTTOMRIGHT", panel.progressRow, "TOPRIGHT", -14, 10)
	panel.scroll = scroll
	panel.content = CreateFrame("Frame", nil, scroll)
	panel.content:SetSize(260, 200)
	scroll:SetScrollChild(panel.content)
	scroll:SetScript("OnSizeChanged", function(frame, width)
		panel.content:SetWidth(width)
	end)
	panel.empty = self:CreateEmptyState(panel)
	panel.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT")
	panel.empty:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 14, 0)
	panel.empty:SetMessage("Nothing to mail", "Your bags hold nothing the queue needs on another character.")
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

	local plan = self.BuildShoppingMailSendPlan and self:BuildShoppingMailSendPlan() or {}
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
		row.dest = dest
		local muted = self:GetTheme().textMuted
		row.name:SetText(string.format("%s |cff%02x%02x%02x· %s items|r", characterLabel(self, dest.characterKey),
			muted.r * 255, muted.g * 255, muted.b * 255, self:FormatNumberGrouped(dest.totalQuantity or 0)))
		local parts = {}
		for j = 1, math.min(3, #(dest.items or {})) do
			local it = dest.items[j]
			parts[#parts + 1] = string.format("%s x%s", it.name or "?", self:FormatNumberGrouped(it.quantity or 0))
		end
		if #(dest.items or {}) > 3 then
			parts[#parts + 1] = string.format("and %d more", #dest.items - 3)
		end
		row.items:SetText(table.concat(parts, ", "))
		local ck = dest.characterKey
		row.send:SetScript("OnClick", function()
			ProfessionExporter:StartMailSendForCharacter(ck)
		end)
		row:Show()
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
end

function ProfessionExporter:OnMailFrameShow()
	if self.EnsureMailPanel then
		self:EnsureMailPanel()
	end
	if self.RefreshMailPanel then
		self:RefreshMailPanel()
	end
end

function ProfessionExporter:OnMailFrameHide()
	local panel = self.ui and self.ui.mailPanel
	if panel then
		panel:Hide()
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
