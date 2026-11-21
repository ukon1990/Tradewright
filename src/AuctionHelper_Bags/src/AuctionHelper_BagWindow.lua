local _, AuctionHelper = ...

-- Bag window (E11 F92, F94; E12 F101): header, character tabs, search, category headings with item
-- slots (or the item log), an optional bag row and a footer. The logged-in character's bags are live, and with the
-- bank open so are its bank and the warband bank; everything else is a read-only list from the
-- holdings in the inventory database.

local FRAME_NAME = "AuctionHelperBagsWindow"
local PAD = 12
local GAP = 4
local HEADING = 18
local HEADING_GAP = 4
local GROUP_GAP = 8
local SECTION_GAP = 8
local MAX_TABS = 6
local MAX_SCREEN_SHARE = 0.85
local WHEEL_STEP = 40
local MODES = {
	{ key = "bags", label = "Bags" }, { key = "bank", label = "Bank" }, { key = "both", label = "Both" }, { key = "log", label = "Log" },
}
local MODE_TEXT = { bags = "bags", bank = "bank", both = "bags and bank" }
local EMPTY_TEXT = "Nothing saved here yet. The bank is saved when this character opens it."
local LOG_EMPTY_TEXT = "Nothing logged. Items are listed here from now on as they enter or leave this character's bags."

local refreshPending = false

local function restorePosition(pe, f)
	local saved = pe:GetSetting("bags.windowPosition", nil)
	local x, y = -90, 110
	if type(saved) == "table" and saved.x and saved.y then
		x, y = saved.x, saved.y
	end
	f:ClearAllPoints()
	f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, y)
end

-- Anchored by its bottom right corner, so the window grows upwards as items come and go.
local function savePosition(pe, f)
	pe:SetSetting("bags.windowPosition", { x = f:GetRight() - UIParent:GetRight(), y = f:GetBottom() - UIParent:GetBottom() })
	restorePosition(pe, f)
end

local function addDivider(pe, parent, point)
	local color = pe:GetTheme().borderSubtle
	local line = parent:CreateTexture(nil, "BORDER")
	line:SetHeight(1)
	line:SetPoint(point .. "LEFT")
	line:SetPoint(point .. "RIGHT")
	line:SetColorTexture(color.r, color.g, color.b, 1)
end

local function buildHeader(pe, f)
	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(pe:GetTheme().size.header)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() f:StartMoving() end)
	header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		savePosition(pe, f)
	end)
	header:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then
			pe:SetBagWindowEnabled(false)
		end
	end)
	addDivider(pe, header, "BOTTOM")
	f.close = pe:CreateIconButton(header, "close", function() f:Hide() end)
	f.close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
	f.rowButton = pe:CreateButton(header, "Bag row", function()
		pe:SetSetting("bags.showBagRow", not pe:GetSetting("bags.showBagRow", false))
		pe:RefreshBagWindow()
	end, { small = true, tooltip = "Show your equipped bags, to swap or replace them." })
	f.rowButton:SetPoint("RIGHT", f.close, "LEFT", -6, 0)
	f.title = pe:CreateText(header, "GameFontNormalLarge", "gold")
	f.title:SetPoint("LEFT", header, "LEFT", PAD - 1, -1)
	f.title:SetText("Bags")
	f.meta = pe:CreateText(header, "GameFontHighlightSmall", "textMuted", "RIGHT")
	f.meta:SetPoint("RIGHT", f.rowButton, "LEFT", -8, 0)
	f.meta:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
end

local function buildTabs(pe, f)
	local theme = pe:GetTheme()
	f.tabs = CreateFrame("Frame", nil, f)
	f.tabs:SetPoint("TOPLEFT", 0, -theme.size.header)
	f.tabs:SetPoint("TOPRIGHT", 0, -theme.size.header)
	f.tabs:SetHeight(theme.size.tabs)
	addDivider(pe, f.tabs, "BOTTOM")
	f.tabButtons = {}
	-- Measures a tab label before its button exists.
	f.measure = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.measure:Hide()
end

local function buildToolbar(pe, f)
	f.toolbar = CreateFrame("Frame", nil, f)
	f.toolbar:SetHeight(pe:GetTheme().size.control)
	f.modeButtons = {}
	for index, mode in ipairs(MODES) do
		f.modeButtons[index] = pe:CreateButton(f.toolbar, mode.label, function()
			f.view.mode = mode.key
			f.scroll:SetVerticalScroll(0)
			pe:RefreshBagWindow()
		end)
	end
	f.search = pe:CreateSearchBox(f.toolbar, "Name, type, quality…", function(text)
		f.view.query = text
		pe:RefreshBagWindow()
	end)
	f.search:SetPoint("LEFT", f.toolbar, "LEFT", 4, 0)
	f.search:SetPoint("RIGHT", f.modeButtons[1], "LEFT", -8, 0)
end

local function updateThumb(f)
	local visible, total = f.scroll:GetHeight(), f.content:GetHeight()
	if total <= visible + 1 then
		f.thumb:Hide()
		return
	end
	local height = math.max(16, visible * visible / total)
	local offset = (visible - height) * f.scroll:GetVerticalScroll() / (total - visible)
	f.thumb:SetHeight(height)
	f.thumb:ClearAllPoints()
	f.thumb:SetPoint("TOPRIGHT", f.scroll, "TOPRIGHT", 6, -offset)
	f.thumb:Show()
end

local function buildBody(pe, f)
	local theme = pe:GetTheme()
	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.scroll:SetScrollChild(f.content)
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, f.content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * WHEEL_STEP)))
		updateThumb(f)
	end)
	f.thumb = f:CreateTexture(nil, "OVERLAY")
	f.thumb:SetWidth(2)
	f.thumb:SetColorTexture(theme.borderControl.r, theme.borderControl.g, theme.borderControl.b, 1)
	f.empty = pe:CreateParagraph(f.content, "textMuted")
	f.empty:SetPoint("TOPLEFT")
	f.empty:SetPoint("TOPRIGHT")
	f.empty:SetText(EMPTY_TEXT)
	f.headings = {}
	f.placed = {}
	f.selectBar = pe:CreateBagSelectBar(f)
	f.bagRow = pe:CreateBagRow(f)
	f.bagRow:SetPoint("BOTTOMLEFT", PAD, theme.size.footer + PAD)
	f.bagRow:SetPoint("BOTTOMRIGHT", -PAD, theme.size.footer + PAD)
end

-- Tooltip of the gold in the footer: every character's gold, richest first, and the total.
local function showGoldTooltip(owner)
	local pe = AuctionHelper
	local theme = pe:GetTheme()
	local muted, text, gold = theme.textMuted, theme.textPrimary, theme.gold
	local rows, total = pe.BagLogic.GoldByCharacter(pe:GetBagHoldings())
	GameTooltip:SetOwner(owner, "ANCHOR_TOPRIGHT")
	GameTooltip:SetText("Gold", gold.r, gold.g, gold.b)
	for _, row in ipairs(rows) do
		GameTooltip:AddDoubleLine(row.name, pe:FormatCopperShort(row.money), muted.r, muted.g, muted.b, text.r, text.g, text.b)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("All characters", pe:FormatCopperShort(total), gold.r, gold.g, gold.b, gold.r, gold.g, gold.b)
	GameTooltip:Show()
end

local function buildFooter(pe, f)
	local footer = CreateFrame("Frame", nil, f)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(pe:GetTheme().size.footer)
	addDivider(pe, footer, "TOP")
	f.footRight = pe:CreateText(footer, "GameFontHighlightSmall", "textMuted", "RIGHT")
	f.footRight:SetPoint("RIGHT", footer, "RIGHT", -PAD, 0)
	local goldHover = CreateFrame("Frame", nil, footer)
	goldHover:SetAllPoints(f.footRight)
	goldHover:EnableMouse(true)
	goldHover:SetScript("OnEnter", showGoldTooltip)
	goldHover:SetScript("OnLeave", GameTooltip_Hide)
	f.dropButton = pe:CreateBagDropButton(footer)
	f.dropButton:SetPoint("LEFT", footer, "LEFT", PAD, 0)
	f.footLeft = pe:CreateText(footer, "GameFontHighlightSmall", "textMuted")
	f.footLeft:SetPoint("RIGHT", f.footRight, "LEFT", -PAD, 0)
end

local function ensureWindow(pe)
	if pe.ui.bagWindow then
		return pe.ui.bagWindow
	end
	local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
	f:Hide()
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetToplevel(true)
	f.view = { tab = pe:GetCharacterKey(), mode = "bags", query = "" }
	pe:StyleWindow(f)
	buildHeader(pe, f)
	buildTabs(pe, f)
	buildToolbar(pe, f)
	buildBody(pe, f)
	buildFooter(pe, f)
	restorePosition(pe, f)
	f:SetScript("OnHide", function(self)
		-- Not when the whole UI is hidden: only when the window itself was closed.
		if not self:IsShown() then
			pe:OnBagWindowClosed()
		end
	end)
	tinsert(UISpecialFrames, FRAME_NAME)
	pe.ui.bagWindow = f
	return f
end

-- Which containers the view shows live: "bags", or with the bank open "bank" (the logged-in
-- character's Bank view) or "warband" (the Warband bank tab). nil: a saved, read-only list.
local function livePlace(pe, view)
	local bankOpen = pe:IsBankOpen()
	if view.tab == pe.BAG_WARBAND_KEY then
		return bankOpen and "warband" or nil
	elseif view.tab ~= view.current then
		return nil
	elseif view.mode == "bags" then
		return "bags"
	end
	return view.mode == "bank" and bankOpen and "bank" or nil
end

-- Modes that the tab does not have fall back: the warband bank is only a bank, All has no log,
-- and the logged-in character has no Both (its bags are live).
local function settleMode(pe, view)
	if view.tab == pe.BAG_WARBAND_KEY then
		view.mode = "bank"
	elseif view.tab == "all" and view.mode == "log" then
		view.mode = "both"
	elseif view.tab == view.current and view.mode == "both" then
		view.mode = "bags"
	end
end

local function scanView(pe, view)
	if view.place == "bank" then
		return pe:ScanBags(pe:GetBankBagIDs())
	elseif view.place == "warband" then
		return pe:ScanBags(pe:GetWarbandBagIDs())
	end
	return pe:ScanBags()
end

-- Settles what is being shown: falls back to the logged-in character and to modes that exist.
local function currentView(pe, f)
	local view = f.view
	view.current = pe:GetCharacterKey()
	local known = view.tab == "all" or pe:GetBagHoldings()[view.tab] ~= nil
	if not known or not pe:GetSetting("bags.showCharacters", true) then
		view.tab = view.current
	end
	settleMode(pe, view)
	view.place = livePlace(pe, view)
	view.live = view.place ~= nil
	view.columns = pe:GetSetting("bags.columns", 10)
	view.slot = pe:GetSetting("bags.slotSize", 36)
	view.innerWidth = view.columns * view.slot + (view.columns - 1) * GAP
	return view
end

-- The groups to draw. The live view ends with one tile standing for every free normal slot.
local function buildGroups(pe, view, scan)
	local items = view.live and scan.items or pe:GetSavedBagItems(view.tab, view.mode)
	local groups = pe.BagLogic.GroupItems(items)
	if view.live and scan.firstFree then
		if #groups == 0 then
			groups[1] = { key = "free", label = "Empty bags", items = {} }
		end
		groups[#groups].extra = { { free = true, bag = scan.firstFree.bag, slot = scan.firstFree.slot } }
	end
	return groups, #items
end

local function tabEntries(pe, view)
	local characters = pe:GetBagHoldings()
	local keys = pe.BagLogic.TabOrder(characters, view.current, MAX_TABS, pe.BAG_WARBAND_KEY)
	if #keys < 2 or not pe:GetSetting("bags.showCharacters", true) then
		return {}
	end
	local entries = {}
	for _, key in ipairs(keys) do
		entries[#entries + 1] = { key = key, label = characters[key] and characters[key].name or key }
	end
	entries[#entries + 1] = { key = "all", label = "All" }
	return entries
end

-- Drops the least recently seen characters until the tabs fit; "All" stays last.
local function trimTabs(f, entries)
	local total = 0
	for _, entry in ipairs(entries) do
		f.measure:SetText(entry.label)
		entry.width = math.ceil(f.measure:GetStringWidth()) + 16
		total = total + entry.width + GAP
	end
	while total > f:GetWidth() - 2 * PAD and #entries > 2 do
		total = total - table.remove(entries, #entries - 1).width - GAP
	end
end

local function createTab(pe, f)
	local button
	button = pe:CreateButton(f.tabs, "", function()
		f.view.tab = button.tabKey
		f.scroll:SetVerticalScroll(0)
		pe:RefreshBagWindow()
	end, { small = true })
	return button
end

-- Returns true when the tab row is shown.
local function refreshTabs(pe, f, view)
	local entries = tabEntries(pe, view)
	trimTabs(f, entries)
	local x = PAD
	for index, entry in ipairs(entries) do
		f.tabButtons[index] = f.tabButtons[index] or createTab(pe, f)
		local button = f.tabButtons[index]
		pe:SetButtonLabel(button, entry.label, true)
		button.tabKey = entry.key
		button:ClearAllPoints()
		button:SetPoint("LEFT", f.tabs, "LEFT", x, 0)
		pe:StyleShellButton(button, entry.key == view.tab)
		button:Show()
		x = x + button:GetWidth() + GAP
	end
	for index = #entries + 1, #f.tabButtons do
		f.tabButtons[index]:Hide()
	end
	f.tabs:SetShown(#entries > 0)
	return #entries > 0
end

-- The logged-in character has no Both (its bags are live); the warband bank is only a bank.
local function modeShown(pe, view, key)
	if view.tab == pe.BAG_WARBAND_KEY then
		return key == "bank"
	elseif key == "log" then
		return view.tab ~= "all"
	end
	return not (view.tab == view.current and key == "both")
end

-- Bags | Bank | Both, right-aligned.
local function refreshModes(pe, f, view)
	local previous
	for index = #MODES, 1, -1 do
		local button = f.modeButtons[index]
		local shown = modeShown(pe, view, MODES[index].key)
		button:SetShown(shown)
		if shown then
			button:ClearAllPoints()
			if previous then
				button:SetPoint("RIGHT", previous, "LEFT", 1, 0)
			else
				button:SetPoint("RIGHT", f.toolbar, "RIGHT", 0, 0)
			end
			pe:StyleShellButton(button, MODES[index].key == view.mode)
			previous = button
		end
	end
end

local function headingText(pe, group, view)
	local muted = pe:GetTheme().textMuted
	local text = string.format("%s  |cff%02x%02x%02x%d|r", group.label, muted.r * 255, muted.g * 255, muted.b * 255, #group.items)
	if group.key == "junk" and view.live and pe:GetSetting("bags.showJunkValue", true) then
		local value = pe.BagLogic.JunkValue(group.items)
		if value > 0 then
			text = text .. "  " .. pe:FormatCopperShort(value)
		end
	end
	return text
end

local function drawHeadings(pe, f, layout, view)
	for index, placed in ipairs(layout.headings) do
		f.headings[index] = f.headings[index] or pe:CreateHeading(f.content, "")
		local heading = f.headings[index]
		heading:ClearAllPoints()
		heading:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -placed.y)
		heading:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, -placed.y)
		heading:SetText(headingText(pe, placed.group, view))
		heading:Show()
	end
	for index = #layout.headings + 1, #f.headings do
		f.headings[index]:Hide()
	end
end

local function slotLook(pe, view, item)
	local otherBag = view.hoverBag ~= nil and item.bag ~= view.hoverBag
	return {
		dim = otherBag or not pe.BagLogic.Matches(item, view.query),
		glow = view.hoverBag ~= nil and not otherBag,
		selected = pe:IsBagSlotSelected(item),
	}
end

local function drawSlots(pe, f, layout, view, freeCount)
	pe:HideBagSlots()
	f.placed = {}
	for index, placed in ipairs(layout.slots) do
		local item = placed.item
		local button = view.live and pe:AcquireLiveBagSlot(f.content, item.bag, item.slot)
			or pe:AcquireReadOnlyBagSlot(f.content, index)
		button:SetSize(view.slot, view.slot)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", f.content, "TOPLEFT", placed.x, -placed.y)
		if item.free then
			pe:SetBagSlotFree(button, freeCount)
		else
			pe:SetBagSlotItem(button, item, slotLook(pe, view, item))
		end
		button:Show()
		f.placed[index] = { button = button, item = item }
	end
	f.empty:SetShown(#layout.slots == 0)
end

-- Footer gold: this character's, and the total when there is more than one character.
local function goldText(pe, money)
	local rows, total = pe.BagLogic.GoldByCharacter(pe:GetBagHoldings())
	if #rows < 2 then
		return pe:FormatCopperShort(money)
	end
	return string.format("%s  ·  All %s", pe:FormatCopperShort(money), pe:FormatCopperShort(total))
end

-- Right of the footer on a read-only tab: when it was seen, and its gold (All: the total).
local function savedFootText(pe, view, record)
	if not record then
		return "All " .. pe:FormatCopperShort(select(2, pe.BagLogic.GoldByCharacter(pe:GetBagHoldings())))
	end
	local seenAt = view.mode == "bank" and record.bankSeenAt or record.seenAt
	local seen = seenAt and ("Seen " .. pe:FormatShortTime(seenAt)) or "Bank not seen yet"
	return record.money and (seen .. "  ·  " .. pe:FormatCopperShort(record.money)) or seen
end

-- Make room sits left of the footer text once no normal slot is left.
local function showDropButton(f, full)
	f.dropButton:SetShown(full)
	f.footLeft:SetPoint("LEFT", f.footLeft:GetParent(), "LEFT", PAD + (full and f.dropButton:GetWidth() + 8 or 0), 0)
end

local function freeText(totals, full)
	local free = full and "Bags full" or string.format("%d free", totals.free)
	if totals.reagentFree > 0 then
		free = free .. string.format(" · %d in reagent bag", totals.reagentFree)
	end
	return free
end

local function refreshLogTexts(pe, f, view, rowCount)
	local record = pe:GetBagHoldings()[view.tab]
	f.meta:SetText((record and record.name or view.tab) .. " · item log")
	local entries = rowCount == 1 and "1 entry" or (rowCount .. " entries")
	f.footLeft:SetText(string.format("%s · last %d days", entries, pe:GetItemLogLimits().days))
	f.footRight:SetText(view.tab == view.current and goldText(pe, GetMoney()) or "")
end

-- Header and footer lines. `totals`: BagLogic.BagTotals of the carried bags.
local function refreshTexts(pe, f, view, totals, itemCount)
	local full = view.place == "bags" and totals.free == 0
	showDropButton(f, full)
	if view.mode == "log" then
		refreshLogTexts(pe, f, view, itemCount)
		return
	end
	if view.live then
		f.meta:SetText(string.format("%d / %d slots", totals.used, totals.slots))
		f.footLeft:SetText(freeText(totals, full))
		f.footRight:SetText(goldText(pe, GetMoney()))
		return
	end
	local record = pe:GetBagHoldings()[view.tab]
	local name = view.tab == "all" and "All characters" or (record and record.name or view.tab)
	f.meta:SetText(name .. " · read-only")
	f.footLeft:SetText(string.format("%d items · %s", itemCount, MODE_TEXT[view.mode]))
	f.footRight:SetText(savedFootText(pe, view, record))
end

-- Sizes the window around the content: `parts` = { hasTabs, hasBar, showRow, contentHeight, bags }.
local function applyLayout(pe, f, view, parts)
	local size = pe:GetTheme().size
	local top = size.header + (parts.hasTabs and size.tabs or 0) + PAD
	f.toolbar:ClearAllPoints()
	f.toolbar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
	f.toolbar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -top)
	top = top + size.control + SECTION_GAP
	if parts.hasBar then
		f.selectBar:ClearAllPoints()
		f.selectBar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
		f.selectBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -top)
		top = top + size.control + SECTION_GAP
	end
	local bottom = size.footer + PAD + (parts.showRow and (pe.BAG_ROW_HEIGHT + SECTION_GAP) or 0)
	local room = UIParent:GetHeight() * MAX_SCREEN_SHARE - top - bottom
	local bodyHeight = math.max(view.slot, math.min(parts.contentHeight, room))
	f.scroll:ClearAllPoints()
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
	f.scroll:SetSize(view.innerWidth, bodyHeight)
	f.content:SetSize(view.innerWidth, math.max(parts.contentHeight, bodyHeight))
	local maxScroll = f.content:GetHeight() - bodyHeight
	if f.scroll:GetVerticalScroll() > maxScroll then
		f.scroll:SetVerticalScroll(maxScroll)
	end
	f.bagRow:SetShown(parts.showRow)
	if parts.showRow then
		pe:RefreshBagRow(f.bagRow, parts.bags, view.innerWidth)
	end
	f:SetHeight(top + bodyHeight + bottom)
	updateThumb(f)
end

-- Draws the view's item slots under their headings. Returns the content height and the item count.
local function drawItems(pe, f, view, scan, totals)
	local groups, itemCount = buildGroups(pe, view, scan)
	local layout = pe.BagLogic.Layout(groups, {
		columns = view.columns, slot = view.slot, gap = GAP, heading = HEADING, headingGap = HEADING_GAP, groupGap = GROUP_GAP,
	})
	pe:HideBagLog()
	f.empty:SetText(EMPTY_TEXT)
	drawHeadings(pe, f, layout, view)
	drawSlots(pe, f, layout, view, totals.free)
	return layout.height, itemCount
end

-- Draws the item log in place of the slots. Returns the content height and the row count.
local function drawLog(pe, f, view)
	drawHeadings(pe, f, { headings = {} }, view)
	drawSlots(pe, f, { slots = {} }, view, 0)
	local height, rowCount = pe:DrawBagLog(f, view)
	f.empty:SetText(LOG_EMPTY_TEXT)
	f.empty:SetShown(rowCount == 0)
	return height, rowCount
end

--- Redraw the bag window from the bags or the saved lists. A hidden window is left alone.
function AuctionHelper:RefreshBagWindow()
	local f = self.ui.bagWindow
	if not f or not f:IsShown() then
		return
	end
	local view = currentView(self, f)
	local scan = scanView(self, view)
	self:SyncBagSelection(view, scan.items)
	local totals = self.BagLogic.BagTotals(scan.bags)
	local showRow = view.place == "bags" and self:GetSetting("bags.showBagRow", false) == true
	f:SetWidth(view.innerWidth + 2 * PAD)
	local hasTabs = refreshTabs(self, f, view)
	refreshModes(self, f, view)
	local draw = view.mode == "log" and drawLog or drawItems
	local contentHeight, itemCount = draw(self, f, view, scan, totals)
	refreshTexts(self, f, view, totals, itemCount)
	f.rowButton:SetEnabled(view.place == "bags")
	self:SetButtonPrimary(f.rowButton, showRow)
	applyLayout(self, f, view, {
		hasTabs = hasTabs, hasBar = self:RefreshBagSelectBar(f.selectBar), showRow = showRow, contentHeight = contentHeight,
		bags = scan.bags,
	})
	self:UpdateBagCatcher()
end

--- Redraw on the next frame, once, however many events asked for it.
function AuctionHelper:RequestBagWindowRefresh()
	local f = self.ui.bagWindow
	if refreshPending or not f or not f:IsShown() then
		return
	end
	refreshPending = true
	C_Timer.After(0, function()
		refreshPending = false
		AuctionHelper:RefreshBagWindow()
	end)
end

--- Show or hide the window. Opening always starts on the logged-in character's bags.
function AuctionHelper:SetBagWindowShown(shown)
	local f = self.ui.bagWindow
	if not shown then
		if f then
			f:Hide()
		end
		return
	end
	f = ensureWindow(self)
	if not f:IsShown() then
		f.view.tab, f.view.mode, f.view.hoverBag = self:GetCharacterKey(), "bags", nil
		f.scroll:SetVerticalScroll(0)
		f:Show()
	end
	self:RefreshBagWindow()
end

--- The bank was opened: show the window on the logged-in character's Bank view.
function AuctionHelper:ShowBagBank()
	self:SetBagWindowShown(true)
	local f = self.ui.bagWindow
	f.view.tab, f.view.mode = self:GetCharacterKey(), "bank"
	f.scroll:SetVerticalScroll(0)
	self:RefreshBagWindow()
end

--- The bank was closed: a view of the bank goes back to the bags.
function AuctionHelper:LeaveBagBank()
	local f = self.ui.bagWindow
	if f and f.view.place ~= "bags" and f.view.live then
		f.view.tab, f.view.mode = self:GetCharacterKey(), "bags"
	end
	self:RequestBagWindowRefresh()
end

--- Light the items of one bag (the bag row is hovered), or none with nil.
function AuctionHelper:SetBagHover(bag)
	local f = self.ui.bagWindow
	if f and f.view.hoverBag ~= bag then
		f.view.hoverBag = bag
		self:RequestBagWindowRefresh()
	end
end
