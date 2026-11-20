local _, ProfessionExporter = ...

-- Log view of the bag window: the item log of the inventory module (AuctionHelper_ItemLog.lua) as
-- rows, newest first: count, item, why and when. Read-only; the search box filters it. A long log
-- is shown a page at a time, with "Show more" under the last row.

local ROW = 22
local ICON = 18
local COUNT_WIDTH = 44
local PAGE = 100
local MORE_GAP = 6
local WHITE = "Interface\\Buttons\\WHITE8X8"

local rows = {}
local shownLimit = PAGE -- how many rows are drawn; "Show more" raises it by a page
local shownFor -- the tab and search text the limit belongs to
local moreButton

local function showTooltip(row)
	local pe, entry = ProfessionExporter, row.entry
	pe:ShowItemRowTooltip(row, entry.id, {
		{ entry.n > 0 and "Entered the bags" or "Left the bags", pe:FormatNumberGrouped(math.abs(entry.n)) },
		{ "How", pe.ItemLogLogic.Describe(entry) },
		{ "When", date("%Y-%m-%d %H:%M", entry.t) },
	})
end

local function createRow(pe, content)
	local gold = pe:GetTheme().gold
	local row = CreateFrame("Button", nil, content)
	row:SetHeight(ROW)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.count = pe:CreateText(row, "GameFontHighlightSmall", "textPrimary", "RIGHT")
	row.count:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
	row.count:SetWidth(COUNT_WIDTH)
	row.why = pe:CreateText(row, "GameFontHighlightSmall", "textMuted", "RIGHT")
	row.why:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.name = pe:CreateText(row, "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.count, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.why, "LEFT", -8, 0)
	row.name:SetWordWrap(false)
	row:SetHighlightTexture(WHITE)
	row:GetHighlightTexture():SetVertexColor(gold.r, gold.g, gold.b, 0.12)
	row:SetScript("OnEnter", showTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", function(self)
		pe:HandleItemRowModifiedClick(self.entry.id)
	end)
	return row
end

local function fillRow(pe, row, entry)
	local theme = pe:GetTheme()
	local item = pe:DescribeBagItem(entry.id, { count = 1 })
	local tone = entry.n > 0 and theme.success or theme.danger
	local quality = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality] or theme.textPrimary
	row.entry = entry
	row.icon:SetTexture(item.icon)
	row.count:SetText(string.format("%+d", entry.n))
	row.count:SetTextColor(tone.r, tone.g, tone.b)
	row.name:SetText(item.name)
	row.name:SetTextColor(quality.r, quality.g, quality.b)
	row.why:SetText(pe.ItemLogLogic.Describe(entry) .. "  ·  " .. pe.TooltipLogic.AgeText(time() - entry.t))
end

local function hideRows()
	for _, row in ipairs(rows) do
		row:Hide()
	end
	if moreButton then
		moreButton:Hide()
	end
end

--- Leave the log view: hide its rows and go back to the first page.
function ProfessionExporter:HideBagLog()
	hideRows()
	shownLimit = PAGE
end

-- "Show more (212 left)" under the last row, when there are entries beyond the page.
local function placeMoreButton(pe, f, y, left)
	if left <= 0 then
		return y
	end
	moreButton = moreButton or pe:CreateButton(f.content, "", function()
		shownLimit = shownLimit + PAGE
		pe:RefreshBagWindow()
	end, { small = true })
	pe:SetButtonLabel(moreButton, string.format("Show more (%d left)", left), true)
	moreButton:ClearAllPoints()
	moreButton:SetPoint("TOP", f.content, "TOP", 0, -(y + MORE_GAP))
	moreButton:Show()
	return y + MORE_GAP + moreButton:GetHeight()
end

--- Draw the log of the character of `view.tab` into the window's content, filtered by the search
--- text. Returns the height used and the number of entries that fit the search.
function ProfessionExporter:DrawBagLog(f, view)
	local pe = self
	local entries = self.ItemLogLogic.Visible(self:GetItemLog(view.tab), function(itemID)
		return pe:DescribeBagItem(itemID, { count = 1 }).name
	end, view.query, math.huge)
	-- Another character or another search starts on the first page again.
	local key = view.tab .. "\n" .. (view.query or "")
	if key ~= shownFor then
		shownFor, shownLimit = key, PAGE
	end
	hideRows()
	local drawn = math.min(#entries, shownLimit)
	for index = 1, drawn do
		rows[index] = rows[index] or createRow(self, f.content)
		local row = rows[index]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(index - 1) * ROW)
		row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", 0, -(index - 1) * ROW)
		fillRow(self, row, entries[index])
		row:Show()
	end
	return placeMoreButton(self, f, drawn * ROW, #entries - drawn), #entries
end
