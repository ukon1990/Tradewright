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
local MAIL_SUBJECTS = { materials = "AuctionHelper mats", crafts = "AuctionHelper crafts", surplus = "AuctionHelper surplus" }
local MAIL_BODY = "Sent with AuctionHelper."

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
		return "This is your auction house / bank character. Materials your queued crafts need go from here to the crafters."
	end
	return "Everything sellable here can go to your auction house / bank character, " .. pe:GetMailCharacterLabel(seller) .. "."
end

local function clearMailAttachments()
	for i = 1, ATTACHMENTS_MAX do
		if GetSendMailItem and GetSendMailItem(i) then
			ClickSendMailItemButton(i, true)
		end
	end
end

local function setMailField(box, text)
	if box and box.SetText then
		box:SetText(text)
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

-- An automatic send has no click behind it. If the client ignores it, hand back to the buttons.
local function watchAutoSend(st)
	local index = st.index
	C_Timer.After(AUTO_SEND_TIMEOUT, function()
		if st.running and st.auto and st.index == index then
			ProfessionExporter:CancelMailSendQueue()
			ProfessionExporter:PrintMessage("Could not mail the materials automatically. Use Prepare all in the mail panel.")
		end
	end)
end

-- Attaches a parcel and fills in To, Subject and body in the game's Send Mail window. Automatic
-- sends go out at once; the buttons leave the mail for the player to check and send.
local function fillParcel(pe, parcel, st)
	clearMailAttachments()
	for _, item in ipairs(parcel.items or {}) do
		if not attachItemQuantity(item.itemID, item.quantity) then
			pe:PrintMessage(string.format("Could not attach all of %s for %s.", tostring(item.name or item.itemID), tostring(parcel.mailName)))
		end
	end
	local subject = string.format("%s %d/%d", MAIL_SUBJECTS[parcel.kind] or MAIL_SUBJECTS.materials, st.index, st.total)
	setMailField(SendMailNameEditBox, parcel.mailName)
	setMailField(SendMailSubjectEditBox, subject)
	setMailField(SendMailBodyEditBox, MAIL_BODY)
	if st.auto and SendMail then
		SendMail(parcel.mailName, subject, MAIL_BODY)
		watchAutoSend(st)
	end
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
	if MailFrame and MailFrame:IsShown() then
		clearMailAttachments()
		for _, box in ipairs({ SendMailNameEditBox, SendMailSubjectEditBox, SendMailBodyEditBox }) do
			setMailField(box, "")
		end
	end
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
	fillParcel(self, parcel, st)
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

--- Materials and crafted items; the surplus only goes from its review panel.
local function readyDestinations(plan)
	local ready = {}
	for _, dest in ipairs(plan) do
		if dest.kind ~= "surplus" and (tonumber(dest.totalQuantity) or 0) > 0 then
			ready[#ready + 1] = dest
		end
	end
	return ready
end

function ProfessionExporter:StartMailSendAll()
	return self:StartMailSendQueue(readyDestinations(self:BuildMailPanelPlan()))
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
		GameTooltip:AddLine("Review… lists every item, what goes and what stays.", muted.r, muted.g, muted.b, true)
	end
	GameTooltip:Show()
end

-- One destination: character and item count, the first items, and its button.
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
	row:SetScript("OnEnter", function(self) showDestTooltip(pe, self) end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function colorize(color, text)
	return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
end

-- "Crafted items to Bånkey · 6 items · ready" with the count muted and the state coloured. The
-- surplus row has no state: what goes is decided in its review panel.
local function destTitle(pe, dest)
	local theme = pe:GetTheme()
	local text = (ROW_TITLES[dest.kind] or "") .. pe:GetMailCharacterLabel(dest.characterKey)
	if dest.kind == "surplus" then
		return text
	end
	text = text .. " " .. colorize(theme.textMuted, "· " .. pe:FormatNumberGrouped(dest.totalQuantity or 0) .. " items")
	local ready = dest.complete ~= false
	return text .. " " .. colorize(ready and theme.success or theme.warning, "· " .. (ready and "ready" or (#dest.missing .. " still missing")))
end

-- "214 to send · 12 stay · 4 skipped" for the surplus row.
local function surplusText(pe, sum)
	local text = sum.send > 0 and (pe:FormatNumberGrouped(sum.send) .. " to send") or "Nothing to send"
	local stay = sum.kept - sum.skipped
	if stay > 0 then
		text = text .. string.format(" · %d stay", stay)
	end
	if sum.skipped > 0 then
		text = text .. string.format(" · %d skipped", sum.skipped)
	end
	return text
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

-- Fills one destination row: title, count and state, the first three items, and its button:
-- Prepare for materials and crafts, Review… for the surplus.
local function fillMailRow(pe, row, dest)
	local surplus = dest.kind == "surplus"
	row.dest = dest
	row.name:SetText(destTitle(pe, dest))
	row.items:SetText(surplus and surplusText(pe, dest.summary) or destItemsText(pe, dest.items or {}))
	local open = surplus and pe:IsMailReviewPanelShown()
	pe:SetButtonLabel(row.send, open and "Hide review" or (surplus and "Review…" or "Prepare"), true)
	row.send:SetEnabled(surplus or not pe:EnsureMailSendQueueState().running)
	row.send:SetScript("OnClick", function()
		if surplus then
			pe:ToggleMailReviewPanel()
		else
			pe:StartMailSendQueue({ dest })
		end
	end)
	row.openFill:SetShown(open)
	row:Show()
end

-- Footer: what Prepare all covers, or where the surplus goes from.
local function footerText(pe, plan)
	local ready, items = readyDestinations(plan), 0
	for _, dest in ipairs(ready) do
		items = items + dest.totalQuantity
	end
	if #ready > 0 then
		return string.format("%d %s · %s items to prepare", #ready, #ready == 1 and "mail row" or "mail rows", pe:FormatNumberGrouped(items))
	end
	return #plan > 0 and "Use Review… to choose what surplus goes" or "No mail pending"
end

-- Progress text: a count beside the bar for automatic sends, a prompt for a prepared mail.
local function progressLabel(panel, st, done)
	if st.auto then
		panel.progressText:SetPoint("RIGHT", panel.progressBar, "LEFT", -8, 0)
		return string.format("Sending %d of %d", done, st.total)
	end
	panel.progressText:SetPoint("RIGHT", panel.progressRow, "RIGHT")
	return string.format("Mail %d of %d ready: press Send in the mailbox", st.index, st.total)
end

-- Progress while a queue runs; returns whether one does.
local function refreshProgress(panel, st)
	local active = st.running == true and (st.total or 0) > 0
	panel.progressRow:SetShown(active)
	if not active then
		return false
	end
	local done = math.min(st.total, math.max(0, (st.index or 1) - 1))
	panel.progressBar:SetShown(st.auto == true)
	panel.progressBar:SetMinMaxValues(0, st.total)
	panel.progressBar:SetValue(done)
	panel.progressText:SetText(progressLabel(panel, st, done))
	return true
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
	panel.sendAllBtn = self:CreateButton(actions, "Prepare all", function() pe:StartMailSendAll() end, { primary = true })
	panel.sendAllBtn:SetPoint("LEFT")
	panel.sendAllBtn:SetPoint("RIGHT", panel.cancelBtn, "LEFT", -8, 0)
	panel.progressRow = CreateFrame("Frame", nil, panel)
	panel.progressRow:SetPoint("BOTTOMLEFT", actions, "TOPLEFT", 0, 8)
	panel.progressRow:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", 0, 8)
	panel.progressRow:SetHeight(18)
	panel.progressText = self:CreateText(panel.progressRow, "GameFontHighlightSmall")
	panel.progressText:SetPoint("LEFT")
	panel.progressBar = CreateFrame("StatusBar", nil, panel.progressRow)
	panel.progressBar:SetPoint("LEFT", 118, 0)
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
	local plan = self:BuildMailPanelPlan()
	for index, dest in ipairs(plan) do
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
	panel.footerText:SetText(footerText(self, plan))
	local st = self:EnsureMailSendQueueState()
	local sending = refreshProgress(panel, st)
	panel.sendAllBtn:SetEnabled(#readyDestinations(plan) > 0 and not sending)
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

local function nameOnly(name)
	return tostring(name or ""):match("^[^%-]+") or ""
end

--- A send went through. While mails are prepared, a mail the player sent to someone else is not
--- the prepared parcel: that parcel is filled in again instead of counted as sent.
function ProfessionExporter:OnMailSendSuccess()
	local st = self:EnsureMailSendQueueState()
	local parcel = st.running and st.parcels and st.parcels[st.index]
	if parcel and not st.auto and nameOnly(self._lastMailTo):lower() ~= nameOnly(parcel.mailName):lower() then
		C_Timer.After(0.35, function() ProfessionExporter:ProcessNextMailParcel() end)
		return
	end
	self:AdvanceMailSendQueue(true)
end

--- A failed automatic send moves on; a prepared mail stays as it is for the player to fix or cancel.
function ProfessionExporter:OnMailSendFailed()
	self:PrintMessage("Mail send failed.")
	if self:EnsureMailSendQueueState().auto then
		self:AdvanceMailSendQueue(false)
	end
end

function ProfessionExporter:InitMailPanelHooks()
	if self._mailPanelHooks then
		return
	end
	self._mailPanelHooks = true
	hooksecurefunc("SendMail", function(recipient)
		ProfessionExporter._lastMailTo = recipient
	end)
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
