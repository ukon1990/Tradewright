local addonName, Tradewright = ...

-- Mail panel: retail always; Forever when send-mail + bag APIs exist.
if not Tradewright.IS_RETAIL then
	if not (Tradewright.IS_FOREVER and C_Container and C_Container.GetContainerNumSlots and GetSendMailItem and ClickSendMailItemButton) then
		return
	end
end

local AUTO_SEND_DELAY = 0.5

function Tradewright:GetMailCharacterLabel(characterKey)
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
		return "No bank character is set. Choose one in Settings, Mail."
	elseif seller == pe:GetCharacterKey() then
		return "This is your bank character. Reagents your queued crafts need go from here to the crafters."
	end
	return "Everything sellable here can go to your bank character, " .. pe:GetMailCharacterLabel(seller) .. "."
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

-- "Crafted items to Bånkey · 6 items · ready" with the count muted and the state coloured. The
-- surplus row has no state: what goes is decided in its review panel.
local function destTitle(pe, dest)
	local text = (ROW_TITLES[dest.kind] or "") .. pe:GetMailCharacterLabel(dest.characterKey)
	if dest.kind == "surplus" then
		return text
	end
	text = text .. " " .. pe:Colorize("· " .. pe:FormatNumberGrouped(dest.totalQuantity or 0) .. " items", "textMuted")
	local ready = dest.complete ~= false
	return text .. " " .. pe:Colorize("· " .. (ready and "ready" or (#dest.missing .. " still missing")), ready and "success" or "warning")
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
		parts[#parts + 1] = string.format("%s × %s", items[j].name or "?", pe:FormatNumberGrouped(items[j].quantity or 0))
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
	pe:SetButtonLabel(row.send, open and "Hide review" or (surplus and "Review…" or "Attach"), true)
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
	local ready, items = pe:GetReadyMailDestinations(plan), 0
	for _, dest in ipairs(ready) do
		items = items + dest.totalQuantity
	end
	if #ready > 0 then
		return string.format("%d %s · %s items to attach", #ready, pe:Plural(#ready, "mail"), pe:FormatNumberGrouped(items))
	end
	return #plan > 0 and "Use Review… to choose what surplus goes" or "No mail pending"
end

-- Progress text: a count beside the bar for automatic sends, a prompt for a prepared mail.
local function progressLabel(panel, queueState, done)
	if queueState.auto then
		panel.progressText:SetPoint("RIGHT", panel.progressBar, "LEFT", -8, 0)
		return string.format("Sending %d of %d", done, queueState.total)
	end
	panel.progressText:SetPoint("RIGHT", panel.progressRow, "RIGHT")
	return string.format("Mail %d of %d ready: press Send in the mailbox", queueState.index, queueState.total)
end

-- Progress while a queue runs; returns whether one does.
local function refreshProgress(panel, queueState)
	local active = queueState.running == true and (queueState.total or 0) > 0
	panel.progressRow:SetShown(active)
	if not active then
		return false
	end
	local done = math.min(queueState.total, math.max(0, (queueState.index or 1) - 1))
	panel.progressBar:SetShown(queueState.auto == true)
	panel.progressBar:SetMinMaxValues(0, queueState.total)
	panel.progressBar:SetValue(done)
	panel.progressText:SetText(progressLabel(panel, queueState, done))
	return true
end

-- A 1px rule across `parent`, `offsetY` below its top and `inset` in from each side.
local function addRule(parent, inset, offsetY)
	local border = Tradewright:GetTheme().borderSubtle
	local rule = parent:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", inset, offsetY)
	rule:SetPoint("TOPRIGHT", -inset, offsetY)
	rule:SetHeight(1)
	rule:SetColorTexture(border.r, border.g, border.b, 1)
end

-- Header: title and the collapse button.
function Tradewright:CreateMailPanelHeader(panel)
	local header = self:GetTheme().size.header
	local collapse = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	collapse:ClearAllPoints()
	collapse:SetPoint("RIGHT", panel, "TOPRIGHT", -6, -(header / 2))
	self:SkinCloseButton(collapse)
	collapse:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Collapse the mail panel", 1, 1, 1)
		GameTooltip:Show()
	end)
	collapse:SetScript("OnLeave", GameTooltip_Hide)
	panel.toggleBtn = collapse
	local title = self:CreateText(panel, "GameFontNormalLarge", "gold")
	title:SetPoint("LEFT", panel, "TOPLEFT", MAIL_PAD, -(header / 2) - 1)
	title:SetPoint("RIGHT", collapse, "LEFT", -12, 0)
	title:SetText("Tradewright mail")
	addRule(panel, 1, -header)
end

-- Footer with how much is ready; Prepare all and Cancel above it, and the progress above those.
function Tradewright:CreateMailPanelFooter(panel)
	local pe = self
	panel.footer = CreateFrame("Frame", nil, panel)
	panel.footer:SetPoint("BOTTOMLEFT", 1, 1)
	panel.footer:SetPoint("BOTTOMRIGHT", -1, 1)
	panel.footer:SetHeight(self:GetTheme().size.footer)
	addRule(panel.footer, 0, 0)
	panel.footerText = self:CreateText(panel.footer, "GameFontHighlightSmall", "textMuted")
	panel.footerText:SetPoint("LEFT", MAIL_PAD, 0)
	panel.footerText:SetPoint("RIGHT", -MAIL_PAD, 0)
	local actions = CreateFrame("Frame", nil, panel)
	actions:SetPoint("BOTTOMLEFT", panel.footer, "TOPLEFT", MAIL_PAD - 1, MAIL_PAD)
	actions:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", -(MAIL_PAD - 1), MAIL_PAD)
	actions:SetHeight(26)
	panel.cancelBtn = self:CreateButton(actions, "Cancel", function() pe:CancelMailSendQueue() end)
	panel.cancelBtn:SetPoint("RIGHT")
	panel.sendAllBtn = self:CreateButton(actions, "Attach all", function() pe:StartMailSendAll() end, { primary = true })
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
end

-- Body: one sentence, then the scrolling destination list (or its empty state).
function Tradewright:CreateMailPanelBody(panel)
	local top = -(self:GetTheme().size.header + 1 + MAIL_PAD)
	panel.summary = self:CreateParagraph(panel)
	panel.summary:SetPoint("TOPLEFT", panel, "TOPLEFT", MAIL_PAD, top)
	panel.summary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MAIL_PAD, top)
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
end

-- Collapsed, the panel is replaced by one small button at the mailbox edge.
function Tradewright:BindMailPanelCollapse(panel, mail)
	local pe = self
	local expand = self:CreateButton(mail, Tradewright.DISPLAY_NAME, nil, { small = true })
	expand:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, -20)
	expand:Hide()
	panel.collapseTab = expand
	local function applyExpanded(expanded)
		expanded = expanded ~= false
		pe:SetSetting("mail.sidePanelExpanded", expanded)
		panel:SetShown(expanded)
		expand:SetShown(not expanded)
	end
	panel.toggleBtn:SetScript("OnClick", function() applyExpanded(false) end)
	expand:SetScript("OnClick", function()
		applyExpanded(true)
		pe:RefreshMailPanel()
	end)
	panel.applyExpanded = applyExpanded
end

function Tradewright:EnsureMailPanel()
	self.ui = self.ui or {}
	if self.ui.mailPanel and self.ui.mailPanel:IsObjectType("Frame") then
		return self.ui.mailPanel
	end
	local mail = _G.MailFrame
	if not mail then
		return nil
	end
	local panel = CreateFrame("Frame", addonName .. "MailPanel", mail, "BackdropTemplate")
	panel:SetWidth(320)
	panel:SetPoint("TOPLEFT", mail, "TOPRIGHT", 8, -20)
	panel:SetPoint("BOTTOMLEFT", mail, "BOTTOMRIGHT", 8, 16)
	self:StyleWindow(panel)
	panel:SetClampedToScreen(true)
	panel:Hide()
	self:CreateMailPanelHeader(panel)
	self:CreateMailPanelFooter(panel)
	self:CreateMailPanelBody(panel)
	self:SkinTree(panel)
	self:BindMailPanelCollapse(panel, mail)
	self.ui.mailPanel = panel
	return panel
end

function Tradewright:RefreshMailPanel()
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
	local queueState = self:EnsureMailSendQueueState()
	local sending = refreshProgress(panel, queueState)
	panel.sendAllBtn:SetEnabled(#self:GetReadyMailDestinations(plan) > 0 and not sending)
	panel.cancelBtn:SetEnabled(queueState.running == true)
	self:RefreshMailReviewPanel(plan)
end

function Tradewright:OnMailFrameShow()
	if self.EnsureMailPanel then
		self:EnsureMailPanel()
	end
	if self.RefreshMailPanel then
		self:RefreshMailPanel()
	end
	C_Timer.After(AUTO_SEND_DELAY, function()
		if MailFrame:IsShown() then
			Tradewright:AutoSendReadyMaterials()
		end
	end)
end

function Tradewright:OnMailFrameHide()
	local panel = self.ui and self.ui.mailPanel
	if panel then
		panel:Hide()
	end
	self:ClearMailSkipped()
	self:SetMailReagentsOnly(false)
	if panel and self.ui.mailReviewPanel then
		self.ui.mailReviewPanel:Hide()
	end
	if self.CancelMailSendQueue then
		self:CancelMailSendQueue()
	end
end

function Tradewright:InitMailPanelHooks()
	if self._mailPanelHooks then
		return
	end
	self._mailPanelHooks = true
	hooksecurefunc("SendMail", function(recipient)
		Tradewright._lastMailTo = recipient
	end)
	local mail = _G.MailFrame
	if mail and mail.HookScript then
		mail:HookScript("OnShow", function()
			Tradewright:OnMailFrameShow()
		end)
		mail:HookScript("OnHide", function()
			Tradewright:OnMailFrameHide()
		end)
	end
end
