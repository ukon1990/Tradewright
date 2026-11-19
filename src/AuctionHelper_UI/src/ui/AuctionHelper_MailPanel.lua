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

function ProfessionExporter:EnsureMailPanel()
	self.ui = self.ui or {}
	if self.ui.mailPanel and self.ui.mailPanel:IsObjectType("Frame") then
		return self.ui.mailPanel
	end
	local mail = _G.MailFrame
	if not mail then
		return nil
	end
	local panel = CreateFrame("Frame", addonName .. "MailPanel", mail, "BackdropTemplate")
	panel:SetSize(320, 420)
	panel:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, -20)
	panel:SetPoint("BOTTOMLEFT", mail, "BOTTOMRIGHT", 8, 16)
	self:StylePanel(panel, "surface2")
	panel:Hide()

	local collapseTab = CreateFrame("Button", addonName .. "MailPanelTab", mail)
	collapseTab:SetSize(18, 64)
	collapseTab:SetPoint("TOPRIGHT", panel, "TOPLEFT", 0, -40)
	local tabText = collapseTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tabText:SetPoint("CENTER")
	tabText:SetText("<")
	panel.collapseTab = collapseTab
	panel.collapseTabText = tabText

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText("AuctionHelper Mail")

	local toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	toggle:SetSize(72, 20)
	toggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -8)
	toggle:SetText("Collapse")
	panel.toggleBtn = toggle

	local summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	summary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -6)
	summary:SetJustifyH("LEFT")
	summary:SetWordWrap(true)
	panel.summary = summary

	local scroll = CreateFrame("ScrollFrame", addonName .. "MailPanelScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -4, -8)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 56)
	panel.scroll = scroll
	panel.content = CreateFrame("Frame", nil, scroll)
	panel.content:SetWidth(270)
	panel.content:SetHeight(200)
	scroll:SetScrollChild(panel.content)
	panel.rows = {}

	local sendAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	sendAll:SetSize(88, 22)
	sendAll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 34)
	sendAll:SetText("Send all")
	panel.sendAllBtn = sendAll
	sendAll:SetScript("OnClick", function()
		ProfessionExporter:StartMailSendAll()
	end)

	local cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	cancel:SetSize(72, 22)
	cancel:SetPoint("LEFT", sendAll, "RIGHT", 6, 0)
	cancel:SetText("Cancel")
	panel.cancelBtn = cancel
	cancel:SetScript("OnClick", function()
		ProfessionExporter:CancelMailSendQueue()
	end)

	panel.progressText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.progressText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 22)
	panel.progressText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 22)
	panel.progressText:SetJustifyH("LEFT")

	panel.progressBar = CreateFrame("StatusBar", nil, panel)
	panel.progressBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 8)
	panel.progressBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
	panel.progressBar:SetHeight(12)
	panel.progressBar:SetStatusBarTexture("Interface/TARGETINGFRAME/UI-StatusBar")
	panel.progressBar:SetMinMaxValues(0, 1)
	panel.progressBar:SetValue(0)
	local bg = panel.progressBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.1, 0.12, 0.8)
	panel.progressBar.bg = bg

	local function applyExpanded(expanded)
		expanded = expanded ~= false
		ProfessionExporter:SetSetting("mail.sidePanelExpanded", expanded)
		panel:SetShown(expanded)
		if panel.collapseTab then
			panel.collapseTab:Show()
		end
		if panel.collapseTabText then
			panel.collapseTabText:SetText(expanded and "<" or ">")
		end
		if panel.toggleBtn then
			panel.toggleBtn:SetText(expanded and "Collapse" or "")
		end
	end

	toggle:SetScript("OnClick", function()
		applyExpanded(false)
	end)
	collapseTab:SetScript("OnClick", function()
		local expanded = ProfessionExporter:GetSetting("mail.sidePanelExpanded", true)
		applyExpanded(not expanded)
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
	local expanded = self:GetSetting("mail.sidePanelExpanded", true)
	if panel.applyExpanded then
		panel.applyExpanded(expanded)
	end
	if not _G.MailFrame or not MailFrame:IsShown() then
		panel:Hide()
		return
	end
	if expanded then
		panel:Show()
	end

	local plan = self.BuildShoppingMailSendPlan and self:BuildShoppingMailSendPlan() or {}
	local destCount = #plan
	local itemCount = 0
	for _, dest in ipairs(plan) do
		itemCount = itemCount + (tonumber(dest.totalQuantity) or 0)
	end
	panel.summary:SetText(string.format(
		"%d destination(s)  |  %s items ready to mail from your bags",
		destCount,
		self:FormatNumberGrouped(itemCount)
	))

	for _, row in ipairs(panel.rows or {}) do
		row:Hide()
		row:SetParent(nil)
	end
	wipe(panel.rows)

	local y = 0
	for i, dest in ipairs(plan) do
		local row = CreateFrame("Frame", nil, panel.content)
		row:SetSize(260, 52)
		row:SetPoint("TOPLEFT", 0, -y)
		y = y + 56

		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 4, -2)
		label:SetJustifyH("LEFT")
		label:SetText(string.format("%s  (%s items)", characterLabel(self, dest.characterKey), self:FormatNumberGrouped(dest.totalQuantity or 0)))

		local detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		detail:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
		detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, 0)
		detail:SetJustifyH("LEFT")
		detail:SetWordWrap(true)
		local parts = {}
		for j = 1, math.min(3, #(dest.items or {})) do
			local it = dest.items[j]
			parts[#parts + 1] = string.format("%s x%s", it.name or "?", self:FormatNumberGrouped(it.quantity or 0))
		end
		if #(dest.items or {}) > 3 then
			parts[#parts + 1] = string.format("+%d more", #dest.items - 3)
		end
		detail:SetText(table.concat(parts, ", "))

		local sendBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		sendBtn:SetSize(56, 18)
		sendBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
		sendBtn:SetText("Send")
		local ck = dest.characterKey
		sendBtn:SetScript("OnClick", function()
			ProfessionExporter:StartMailSendForCharacter(ck)
		end)
		panel.rows[#panel.rows + 1] = row
	end
	panel.content:SetHeight(math.max(80, y + 8))

	local st = self:EnsureMailSendQueueState()
	if st.running and st.total and st.total > 0 then
		local done = math.max(0, (st.index or 1) - 1)
		if st.index > st.total then
			done = st.total
		end
		panel.progressBar:SetMinMaxValues(0, st.total)
		panel.progressBar:SetValue(done)
		local current = st.parcels and st.parcels[st.index]
		panel.progressText:SetText(string.format(
			"Sending %d/%d%s",
			done,
			st.total,
			current and (" — " .. tostring(current.mailName)) or ""
		))
		panel.sendAllBtn:Disable()
	else
		panel.progressBar:SetMinMaxValues(0, 1)
		panel.progressBar:SetValue(0)
		panel.progressText:SetText(destCount > 0 and "Ready to send purchased materials." or "No mail pending.")
		panel.sendAllBtn:SetEnabled(destCount > 0)
	end
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
