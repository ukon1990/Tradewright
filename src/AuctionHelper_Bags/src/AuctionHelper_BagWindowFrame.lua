local _, AuctionHelper = ...

-- Bag window frame: builds the window once (header, tabs, toolbar, scrolling body, footer) and keeps its position.

local FRAME_NAME = "AuctionHelperBagsWindow"
local PAD = 12
local WHEEL_STEP = 40
local MODES = {
	{ key = "bags", label = "Bags" }, { key = "bank", label = "Bank" }, { key = "both", label = "Both" }, { key = "log", label = "Log" },
}
local EMPTY_TEXT = "Nothing saved here yet. The bank is saved when this character opens it."
-- Shared with the bag window drawing code.
AuctionHelper.BagWindowLayout = { pad = PAD, modes = MODES, emptyText = EMPTY_TEXT }

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
	f.stashButton = pe:CreateBagStashButton(header, f.rowButton)
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

-- Scroll thumb of the body: sized to the visible share and placed by the scroll offset.
function AuctionHelper.UpdateBagWindowThumb(f)
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
		AuctionHelper.UpdateBagWindowThumb(f)
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

--- The bag window frame, built on first use.
function AuctionHelper:EnsureBagWindow()
	local pe = self
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
