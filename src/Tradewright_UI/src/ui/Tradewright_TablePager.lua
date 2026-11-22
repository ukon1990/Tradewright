local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Table footer and pager: the footer texts and Prev / Page N of M / Next (methods of the reusable table).

local TableMixin = Tradewright.TableMixin

--- Shows another page of a table that has more rows than its page size.
function TableMixin:SetPage(page)
	self.page = page
	self:Refresh({ resetVerticalScroll = true })
end

-- Footer text: `left` is replaced by "Showing A-B of M" when the rows span more than one page.
function TableMixin:SetFooterText(left, right)
	if not self.footer then
		return
	end
	self.footerLeftOverride = left
	self.footer.right:SetText(right or "")
	self:UpdateFooter()
end

function TableMixin:UpdateFooter()
	if not self.footer then
		return
	end
	local pe = Tradewright
	local left, right = self.footer.left, self.footer.right
	local paged = (self.pageCount or 1) > 1
	left:SetText(paged and string.format(L["Showing %s-%s of %s"], pe:FormatNumberGrouped(self.pageFirst), pe:FormatNumberGrouped(self.pageLast),
		pe:FormatNumberGrouped(self.totalRowCount)) or self.footerLeftOverride or "")
	local pager = self.pager
	if not pager then
		return
	end
	pager:SetShown(paged)
	left:ClearAllPoints()
	right:ClearAllPoints()
	left:SetPoint("LEFT", 8, 0)
	if paged then
		-- Pager at the right edge. "Showing A-B of N" keeps its full width, and the caller's text
		-- gets what is left between the two, cut short when the table is narrow.
		pager.label:SetText(string.format(L["Page %d of %d"], self.page, self.pageCount))
		pager.prev:SetEnabled(self.page > 1)
		pager.next:SetEnabled(self.page < self.pageCount)
		pager:SetWidth(pager.prev:GetWidth() + pager.next:GetWidth() + math.ceil(pager.label:GetStringWidth()) + 16)
		right:SetPoint("LEFT", left, "RIGHT", 12, 0)
		right:SetPoint("RIGHT", pager, "LEFT", -12, 0)
	else
		right:SetPoint("RIGHT", self.footer, "RIGHT", -pe:GetTheme().size.scrollGutter, 0)
		left:SetPoint("RIGHT", right, "LEFT", -12, 0)
	end
end

function TableMixin:CreateFooter(footerHeight)
	local theme = Tradewright:GetTheme()
	local footer = CreateFrame("Frame", nil, self.frame)
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(footerHeight)
	local fill = footer:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(theme.surface2.r, theme.surface2.g, theme.surface2.b, 1)
	local rule = footer:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT")
	rule:SetPoint("TOPRIGHT")
	rule:SetHeight(1)
	rule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	footer.right = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footer.right:SetPoint("RIGHT", -theme.size.scrollGutter, 0)
	footer.right:SetJustifyH("RIGHT")
	footer.left = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footer.left:SetPoint("LEFT", 8, 0)
	footer.left:SetPoint("RIGHT", footer.right, "LEFT", -12, 0)
	footer.left:SetJustifyH("LEFT")
	for _, text in ipairs({ footer.left, footer.right }) do
		text:SetWordWrap(false)
		text:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	end
	self.footer = footer
	-- Tables with a page size get Prev / "Page N of M" / Next, shown once there is a second page.
	if self.maxRows then
		self:CreatePager(footerHeight)
	end
end

function TableMixin:CreatePager(footerHeight)
	local theme = Tradewright:GetTheme()
	local pager = CreateFrame("Frame", nil, self.footer)
	pager:SetPoint("RIGHT", -theme.size.scrollGutter, 0)
	pager:SetHeight(footerHeight)
	pager.next = Tradewright:CreateButton(pager, L["Next"], function() self:SetPage(self.page + 1) end, { small = true })
	pager.next:SetPoint("RIGHT")
	pager.label = pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pager.label:SetPoint("RIGHT", pager.next, "LEFT", -8, 0)
	pager.label:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	pager.prev = Tradewright:CreateButton(pager, L["Previous"], function() self:SetPage(self.page - 1) end, { small = true })
	pager.prev:SetPoint("RIGHT", pager.label, "LEFT", -8, 0)
	for _, button in ipairs({ pager.prev, pager.next }) do
		button:SetHeight(footerHeight - 6)
	end
	pager:Hide()
	self.pager = pager
end
