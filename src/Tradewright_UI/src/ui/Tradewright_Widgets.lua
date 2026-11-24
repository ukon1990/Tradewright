local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local function setColor(fontString, color)
	Tradewright:ColorText(fontString, color)
end

local function newText(parent, font, color, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	setColor(text, color or Tradewright:GetTheme().textPrimary)
	return text
end

-- A single-line text that truncates with an ellipsis. Anchor it with two points.
function Tradewright:CreateText(parent, font, colorKey, justify)
	return newText(parent, font, self:GetTheme()[colorKey or "textPrimary"], justify)
end

-- HookScript keeps the skin's hover colour handlers.
local function addButtonTooltip(button, label, tooltip)
	button:HookScript("OnEnter", function(self)
		local muted = Tradewright:GetTheme().textMuted
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(self:GetText() or label or "", 1, 1, 1)
		GameTooltip:AddLine(tooltip, muted.r, muted.g, muted.b, true)
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", GameTooltip_Hide)
end

-- A 26px flat button sized to its label (or `opts.width`); `opts.small` is 22px, `opts.primary` gold,
-- `opts.solid` gold-filled.
function Tradewright:CreateButton(parent, label, onClick, opts)
	opts = opts or {}
	local sizes = self:GetTheme().size
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(label or "")
	self:SkinButton(button)
	local height, padding = sizes.control, 24
	if opts.small then
		height, padding = sizes.controlSmall, 16
	end
	button:SetSize(opts.width or (math.ceil(button:GetFontString():GetStringWidth()) + padding), height)
	if opts.primary then
		self:SetButtonPrimary(button, true)
	end
	if opts.solid then
		self:SetButtonSolid(button, true)
	end
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	if opts.tooltip then
		addButtonTooltip(button, label, opts.tooltip)
	end
	return button
end

-- Re-fits a button created by CreateButton after its label changes.
function Tradewright:SetButtonLabel(button, label, small)
	button:SetText(label or "")
	button:SetWidth(math.ceil(button:GetFontString():GetStringWidth()) + (small and 16 or 24))
end

-- Lays frames out left to right from `first`'s current anchor, `gap` apart, vertically centred.
function Tradewright:ChainRight(frames, gap)
	for index = 2, #frames do
		frames[index]:ClearAllPoints()
		frames[index]:SetPoint("LEFT", frames[index - 1], "RIGHT", gap or 8, 0)
	end
end

-- Right to left: frames[1] is the rightmost and keeps its anchor.
function Tradewright:ChainLeft(frames, gap)
	for index = 2, #frames do
		frames[index]:ClearAllPoints()
		frames[index]:SetPoint("RIGHT", frames[index - 1], "LEFT", -(gap or 8), 0)
	end
end

-- Section heading: gold text followed by a 1px rule to the right edge. 18px tall.
function Tradewright:CreateHeading(parent, label)
	local theme = self:GetTheme()
	local heading = CreateFrame("Frame", nil, parent)
	heading:SetHeight(18)
	heading.text = newText(heading, "GameFontNormal", theme.gold)
	heading.text:SetPoint("LEFT", 0, 0)
	heading.text:SetText(label or "")
	heading.rule = heading:CreateTexture(nil, "BORDER")
	heading.rule:SetHeight(1)
	heading.rule:SetPoint("LEFT", heading.text, "RIGHT", 8, 0)
	heading.rule:SetPoint("RIGHT", heading, "RIGHT", 0, 0)
	Tradewright:ColorTexture(heading.rule, "borderSubtle", 1)
	function heading:SetText(text)
		self.text:SetText(text or "")
	end
	return heading
end

-- A raised group: surface2 fill with a subtle outline. Content is placed by the caller with 10px padding.
function Tradewright:CreateInset(parent)
	local inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	self:StylePanel(inset, "surface2")
	return inset
end

-- Summary tile: muted label, one large value, one muted note. 58px tall; width from anchors.
function Tradewright:CreateStat(parent)
	local theme = self:GetTheme()
	local stat = self:CreateInset(parent)
	stat:SetHeight(58)
	stat.label = newText(stat, "GameFontHighlightSmall", theme.textMuted)
	stat.label:SetPoint("TOPLEFT", 10, -8)
	stat.label:SetPoint("TOPRIGHT", -10, -8)
	stat.value = newText(stat, "NumberFontNormalLarge", theme.textPrimary)
	stat.value:SetPoint("TOPLEFT", stat.label, "BOTTOMLEFT", 0, -4)
	stat.value:SetPoint("TOPRIGHT", stat.label, "BOTTOMRIGHT", 0, -4)
	stat.note = newText(stat, "GameFontHighlightSmall", theme.textMuted)
	stat.note:SetPoint("BOTTOMLEFT", 10, 8)
	stat.note:SetPoint("BOTTOMRIGHT", -10, 8)
	function stat:SetValues(label, value, note, colorKey)
		self.label:SetText(label or "")
		self.value:SetText(value or "-")
		setColor(self.value, theme[colorKey or "textPrimary"] or theme.textPrimary)
		self.note:SetText(note or "")
	end
	return stat
end

-- Places `frames` side by side across `parent`'s width, `gap` apart, sharing the width equally.
function Tradewright:LayoutEvenRow(parent, frames, top, gap)
	gap = gap or 12
	local count = #frames
	if count == 0 then
		return
	end
	local width = (parent:GetWidth() - gap * (count - 1)) / count
	for index, frame in ipairs(frames) do
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", parent, "TOPLEFT", (index - 1) * (width + gap), -(top or 0))
		frame:SetWidth(math.max(40, width))
	end
end

-- Muted placeholder text shown while an edit box is empty and not focused. Keeps existing scripts.
function Tradewright:AddSearchPlaceholder(box, placeholder)
	self:SkinEditBox(box)
	if not box.placeholder then
		box.placeholder = newText(box, "GameFontHighlightSmall", self:GetTheme().textMuted)
		box.placeholder:SetPoint("LEFT", 0, 0)
		box.placeholder:SetPoint("RIGHT", 0, 0)
		local function update()
			box.placeholder:SetShown((box:GetText() or "") == "" and not box:HasFocus())
		end
		box:HookScript("OnEditFocusGained", update)
		box:HookScript("OnEditFocusLost", update)
		box:HookScript("OnTextChanged", update)
		box.UpdatePlaceholder = update
	end
	box.placeholder:SetText(placeholder or L["Search"])
	box:UpdatePlaceholder()
	return box
end

-- An edit box with placeholder text, skinned 26px tall. `onChanged(text)` fires after `delay` seconds.
function Tradewright:CreateSearchBox(parent, placeholder, onChanged, delay)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetAutoFocus(false)
	box:SetMaxLetters(64)
	box:SetHeight(self:GetTheme().size.control - 4)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	local pending = 0
	box:SetScript("OnTextChanged", function(self, userInput)
		if not userInput or type(onChanged) ~= "function" then
			return
		end
		pending = pending + 1
		local token = pending
		C_Timer.After(delay or 0.2, function()
			if token == pending then
				onChanged(self:GetText() or "")
			end
		end)
	end)
	self:AddSearchPlaceholder(box, placeholder)
	return box
end

-- Restyles a StatusBar: flat gold fill on a dark track with a 1px outline, 14px tall.
function Tradewright:StyleProgressBar(bar)
	local theme = self:GetTheme()
	bar:SetHeight(14)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	Tradewright:ColorStatusBar(bar, "tick", 1)
	bar:SetMinMaxValues(0, 1)
	if not bar.ahTrack then
		bar.ahTrack = bar:CreateTexture(nil, "BACKGROUND")
		bar.ahTrack:SetAllPoints()
		Tradewright:ColorTexture(bar.ahTrack, "surface3", 1)
		self:AddSurface(bar, { r = 0, g = 0, b = 0, a = 0 }, theme.borderStrong, 1, 1)
	end
	return bar
end

-- Label/value pairs, label muted on the left and value on the right, 16px rows. Returns its height.
function Tradewright:CreateKeyValueList(parent)
	local theme = self:GetTheme()
	local list = CreateFrame("Frame", nil, parent)
	list.rows = {}
	local function getLine(index)
		local line = list.rows[index]
		if not line then
			line = {}
			line.value = newText(list, "GameFontHighlightSmall", theme.textPrimary, "RIGHT")
			line.value:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -((index - 1) * 16))
			line.label = newText(list, "GameFontHighlightSmall", theme.textMuted)
			line.label:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((index - 1) * 16))
			line.label:SetPoint("RIGHT", line.value, "LEFT", -12, 0)
			list.rows[index] = line
		end
		return line
	end
	function list:SetRows(rows)
		rows = rows or {}
		for index, row in ipairs(rows) do
			local line = getLine(index)
			line.label:SetText(row[1] or "")
			line.value:SetText(row[2] or "")
			setColor(line.value, theme[row[3] or "textPrimary"] or theme.textPrimary)
			line.label:Show()
			line.value:Show()
		end
		for index = #rows + 1, #self.rows do
			self.rows[index].label:Hide()
			self.rows[index].value:Hide()
		end
		local height = math.max(1, #rows * 16)
		self:SetHeight(height)
		return height
	end
	return list
end

-- A selectable one-column list (character list, docs topics) built on the shared table.
-- items: { { key, label } }; `onSelect(key)`; `getSelected()` returns the selected key.
function Tradewright:CreateSelectList(parent, onSelect, getSelected)
	local list = self:CreateReusableTable(parent, {
		headerHeight = 0,
		autoFitToScroll = true,
		isRowSelected = function(row)
			return row and row.key == getSelected()
		end,
		onRowClick = function(_, row)
			if row then
				onSelect(row.key)
			end
		end,
	})
	list.header:Hide()
	list:SetColumns({ { id = "label", label = "", width = 100, flex = 1, minWidth = 40 } })
	function list:SetItems(items)
		self:SetRows(items or {})
		self:Refresh()
	end
	return list
end

-- Lays `buttons` out left to right inside `width`, wrapping to new rows. Returns the total height.
function Tradewright:FlowButtons(container, buttons, width, gap, top)
	gap = gap or 8
	local x, y, rowHeight = 0, -(top or 0), 0
	for _, button in ipairs(buttons) do
		local w, h = button:GetWidth(), button:GetHeight()
		if x > 0 and x + w > width then
			x = 0
			y = y - rowHeight - gap
			rowHeight = 0
		end
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
		x = x + w + gap
		rowHeight = math.max(rowHeight, h)
	end
	return -y + rowHeight
end

-- Wrapping muted text for explanations. Anchor with two points; read height with GetStringHeight.
function Tradewright:CreateParagraph(parent, colorKey)
	local text = self:CreateText(parent, "GameFontHighlightSmall", colorKey or "textMuted")
	text:SetWordWrap(true)
	text:SetNonSpaceWrap(true)
	return text
end

-- Professions of one character as table rows, sorted by name.
function Tradewright:BuildProfessionRows(charData)
	local rows = {}
	for _, profession in pairs(charData and charData.professions or {}) do
		rows[#rows + 1] = {
			_rowIdentity = tostring(profession.skillLineID or ""),
			name = tostring(profession.professionName or "?"),
			skill = tonumber(profession.skillLevel) or 0,
			maxSkill = tonumber(profession.maxSkillLevel) or 0,
			recipes = tonumber(profession.recipeCount) or 0,
			skillLineID = tostring(profession.skillLineID or ""),
		}
	end
	table.sort(rows, function(left, right)
		return left.name < right.name
	end)
	return rows
end

-- Profession, Skill, Recipes and (unless `withoutExport`) All / Recipes / Talents export buttons.
function Tradewright:CreateProfessionColumns(withoutExport)
	local pe = self
	local columns = {
		{ id = "name", label = L["Profession"], width = 120, flex = 1, minWidth = 100,
			getText = function(row) return row.name end },
		{ id = "skill", label = L["Skill"], width = 64, justifyH = "RIGHT",
			getText = function(row) return string.format("%d/%d", row.skill, row.maxSkill) end },
		{ id = "recipes", label = L["Recipes"], width = 64, justifyH = "RIGHT",
			getText = function(row) return pe:FormatNumberGrouped(row.recipes) end },
	}
	if withoutExport then
		return columns
	end
	columns[#columns + 1] = { id = "export", label = L["Export"], width = 196,
		createCell = function(rowFrame)
			local cell = CreateFrame("Frame", nil, rowFrame)
			cell:SetHeight(22)
			cell.all = pe:CreateButton(cell, L["All"], nil, { small = true })
			cell.all:SetPoint("LEFT", 5, 0)
			cell.recipes = pe:CreateButton(cell, L["Recipes"], nil, { small = true })
			cell.talents = pe:CreateButton(cell, L["Talents"], nil, { small = true })
			pe:ChainRight({ cell.all, cell.recipes, cell.talents }, 4)
			return cell
		end,
		updateCell = function(cell, row)
			cell.all:SetScript("OnClick", function() pe:Export("profession", row.skillLineID) end)
			cell.recipes:SetScript("OnClick", function() pe:Export("profession_recipes", row.skillLineID) end)
			cell.talents:SetScript("OnClick", function() pe:Export("profession_talents", row.skillLineID) end)
		end }
	return columns
end

local DEFAULT_ITEM_ICON = 134400

-- Quality colour of an item (white when unknown) and its icon.
function Tradewright:GetItemLook(itemID)
	local desc = itemID and self:ResolveItemDescriptor(tonumber(itemID) or itemID) or nil
	local color = self:GetQualityColor(desc and desc.quality)
	return desc and desc.icon or DEFAULT_ITEM_ICON, color or self:GetTheme().textPrimary
end

-- An 18px item icon outlined in its quality colour. `size` overrides (32 for detail headers).
function Tradewright:CreateItemIcon(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size or 18, size or 18)
	holder.border = holder:CreateTexture(nil, "BORDER")
	holder.border:SetAllPoints()
	holder.icon = holder:CreateTexture(nil, "ARTWORK")
	holder.icon:SetPoint("TOPLEFT", 1, -1)
	holder.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	function holder:SetItem(itemID, iconOverride)
		local icon, color = Tradewright:GetItemLook(itemID)
		self.icon:SetTexture(iconOverride or icon)
		Tradewright:ColorTexture(self.border, color, 0.9)
	end
	return holder
end

local function createItemCell(pe, rowFrame)
	local cell = CreateFrame("Frame", nil, rowFrame)
	cell:SetHeight(rowFrame:GetHeight())
	cell.icon = pe:CreateItemIcon(cell)
	cell.icon:SetPoint("LEFT", 5, 0)
	cell.name = pe:CreateText(cell, "GameFontHighlightSmall")
	cell.detail = pe:CreateText(cell, "GameFontHighlightSmall", "textMuted")
	cell.name:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
	cell.detail:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
	return cell
end

-- Tall rows show the detail under the name; short rows (or no detail) centre the name alone.
local function setItemCellDetail(cell, detail)
	cell.name:ClearAllPoints()
	cell.name:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
	if detail and detail ~= "" and cell:GetHeight() >= 30 then
		cell.name:SetPoint("BOTTOMLEFT", cell.icon, "RIGHT", 6, 1)
		cell.detail:ClearAllPoints()
		cell.detail:SetPoint("TOPLEFT", cell.icon, "RIGHT", 6, -1)
		cell.detail:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
		cell.detail:SetText(detail)
		cell.detail:Show()
	else
		cell.name:SetPoint("LEFT", cell.icon, "RIGHT", 6, 0)
		cell.detail:Hide()
	end
end

-- Table column: item icon + quality-coloured name, with an optional muted second line
-- (`getDetail(row)`) when the table uses tall rows. `getItemID`, `getName` read the row.
function Tradewright:CreateItemColumn(spec)
	local pe = self
	local column = {
		id = spec.id or "name",
		label = spec.label or "Item",
		width = spec.width or 200,
		minWidth = spec.minWidth or 140,
		flex = spec.flex or 1,
		sortable = spec.sortable ~= false,
		defaultSort = spec.defaultSort,
		sortValue = spec.sortValue or function(row) return spec.getName(row) or "" end,
		tooltipTitle = spec.tooltipTitle,
		tooltipText = spec.tooltipText,
	}
	column.createCell = function(rowFrame)
		return createItemCell(pe, rowFrame)
	end
	column.updateCell = function(cell, row)
		local itemID = spec.getItemID(row)
		local _, color = pe:GetItemLook(itemID)
		cell.icon:SetItem(itemID, spec.getIcon and spec.getIcon(row) or nil)
		cell.name:SetText(spec.getName(row) or ("#" .. tostring(itemID or "?")))
		Tradewright:ColorText(cell.name, color)
		setItemCellDetail(cell, spec.getDetail and spec.getDetail(row) or nil)
	end
	return column
end

-- Uppercase status word with a 1px outline in its colour. `colorKey`: success, danger, warning, accent, gold.
function Tradewright:CreateBadge(parent)
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetHeight(16)
	badge.text = self:CreateText(badge, "GameFontNormalSmall")
	badge.text:SetPoint("CENTER", 0, 0)
	badge.surface = self:AddSurface(badge, { r = 0, g = 0, b = 0, a = 0 }, self:GetTheme().textMuted)
	function badge:SetBadge(text, colorKey)
		local theme = Tradewright:GetTheme()
		local color = theme[colorKey or "textMuted"] or theme.textMuted
		self.text:SetText(string.upper(text or ""))
		Tradewright:ColorText(self.text, color)
		self.surface:SetColors(nil, color)
		self:SetWidth(math.ceil(self.text:GetStringWidth()) + 12)
		self:SetShown(text ~= nil and text ~= "")
	end
	return badge
end

-- Detail pane header: 32px item icon, name, muted second line, optional close and pop-out buttons.
-- `header.itemID` is the item last passed to SetItem.
function Tradewright:CreateDetailHeader(parent, onClose, onPopOut)
	local header = CreateFrame("Frame", nil, parent)
	header:SetHeight(32)
	header.icon = self:CreateItemIcon(header, 32)
	header.icon:SetPoint("LEFT")
	local right, point, gap = header, "TOPRIGHT", 0 -- buttons and badge line up right to left
	for _, spec in ipairs({ { "close", "close", onClose }, { "popOut", "window", onPopOut, L["Open in item details window"] } }) do
		if spec[3] then
			header[spec[1]] = self:CreateIconButton(header, spec[2], spec[3], spec[4])
			header[spec[1]]:SetPoint("TOPRIGHT", right, point, gap, 0)
			right, point, gap = header[spec[1]], "TOPLEFT", -6
		end
	end
	header.badge = self:CreateBadge(header)
	header.badge:SetPoint("TOPRIGHT", right, point, gap, -2)
	header.badge:Hide()
	header.title = self:CreateText(header, "GameFontHighlight")
	header.title:SetPoint("TOPLEFT", header.icon, "TOPRIGHT", 8, -1)
	header.title:SetPoint("RIGHT", header, "RIGHT", -60, 0)
	header.subtitle = self:CreateText(header, "GameFontHighlightSmall", "textMuted")
	header.subtitle:SetPoint("BOTTOMLEFT", header.icon, "BOTTOMRIGHT", 8, 1)
	header.subtitle:SetPoint("RIGHT", header, "RIGHT", 0, 0)
	function header:SetItem(itemID, title, subtitle, iconOverride)
		local _, color = Tradewright:GetItemLook(itemID)
		self.itemID = itemID
		self.icon:SetItem(itemID, iconOverride)
		self.icon:Show()
		self.title:SetText(title or "")
		Tradewright:ColorText(self.title, color)
		self.subtitle:SetText(subtitle or "")
	end
	return header
end

-- Centered "nothing here" message: title plus a muted sentence. Fill the area it covers.
function Tradewright:CreateEmptyState(parent)
	local empty = CreateFrame("Frame", nil, parent)
	empty.title = self:CreateText(empty, "GameFontHighlight", "textPrimary", "CENTER")
	empty.title:SetPoint("BOTTOMLEFT", empty, "LEFT", 16, 4)
	empty.title:SetPoint("BOTTOMRIGHT", empty, "RIGHT", -16, 4)
	empty.hint = self:CreateParagraph(empty)
	empty.hint:SetJustifyH("CENTER")
	empty.hint:SetPoint("TOPLEFT", empty, "LEFT", 16, -4)
	empty.hint:SetPoint("TOPRIGHT", empty, "RIGHT", -16, -4)
	function empty:SetMessage(title, hint)
		self.title:SetText(title or "")
		self.hint:SetText(hint or "")
	end
	return empty
end

-- Item class, subclass and quality for filters, cached per item. Class and subclass come from the
-- instant item API; quality is only known once the client has the item, so it is retried until then.
local itemFilterInfoCache = {}

local function itemClassInfo(itemID)
	local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	if not getInstant then
		return {}
	end
	local _, classLabel, subclassLabel = getInstant(itemID)
	return { classLabel = classLabel, subclassLabel = subclassLabel }
end

-- nil until the client has loaded the item.
local function itemQuality(itemID)
	local getQuality = C_Item and C_Item.GetItemQualityByID
	local quality = getQuality and getQuality(itemID)
	if quality ~= nil then
		return quality
	end
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	return getInfo and select(3, getInfo(itemID))
end

function Tradewright:GetItemFilterInfo(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return {}
	end
	local info = itemFilterInfoCache[itemID]
	if info and info.quality ~= nil then
		return info
	end
	if not info then
		info = itemClassInfo(itemID)
		itemFilterInfoCache[itemID] = info
	end
	info.quality = itemQuality(itemID)
	return info
end

-- Item quality choices for filter dropdowns, coloured like item names.
function Tradewright:GetQualityFilterOptions()
	-- The game's own quality names, so they match item tooltips in every language.
	local names = { [0] = L["Poor"], L["Common"], L["Uncommon"], L["Rare"], L["Epic"], L["Legendary"] }
	for quality = 0, 5 do
		names[quality] = _G["ITEM_QUALITY" .. quality .. "_DESC"] or names[quality]
	end
	local options = {}
	for quality = 0, 5 do
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		options[#options + 1] = { value = quality, label = color and self:Colorize(names[quality], color) or names[quality] }
	end
	return options
end

-- Class or subclass choices from a list of item IDs: { value = label, label = label }, sorted.
function Tradewright:BuildItemClassOptions(itemIDs, field, classSelection)
	local seen, options = {}, {}
	local filterByClass = classSelection and not self:IsFilterSelectionEmpty(classSelection)
	for _, itemID in ipairs(itemIDs or {}) do
		local info = self:GetItemFilterInfo(itemID)
		local label = info[field]
		if label and label ~= "" and not seen[label] and (not filterByClass or classSelection[info.classLabel]) then
			seen[label] = true
			options[#options + 1] = { value = label, label = label }
		end
	end
	table.sort(options, function(a, b) return a.label < b.label end)
	return options
end

-- A checkbox with its label as one frame, sized to fit, so it can sit in a row of controls.
-- `onChange(checked)` runs on click; read or set the state through group.check.
function Tradewright:CreateCheckbox(parent, label, onChange)
	local group = CreateFrame("Frame", nil, parent)
	group:SetHeight(26)
	local check = CreateFrame("CheckButton", nil, group, "UICheckButtonTemplate")
	self:SkinCheckButton(check)
	check:ClearAllPoints()
	check:SetPoint("LEFT", -4, 0)
	local text = check.Text or check.text
	if not text then
		text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		check.Text = text
	end
	text:ClearAllPoints()
	text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	text:SetFontObject("GameFontHighlightSmall")
	text:SetWordWrap(false)
	text:SetText(label)
	check:SetScript("OnClick", function(button)
		if onChange then
			onChange(button:GetChecked() == true)
		end
	end)
	group:SetWidth(18 + 2 + math.ceil(text:GetStringWidth()) + 4)
	group.check = check
	return group
end

-- Signed money: "+3g 15s" with a green plus, negative amounts with a red minus, "-" when unknown.
function Tradewright:FormatSignedMoney(copper)
	local n = tonumber(copper)
	if not n then
		return "-"
	end
	if n < 0 then
		return self:FormatCopperShort(n)
	end
	return self:Colorize("+", "success") .. self:FormatCopperShort(n)
end

-- "today 14:32" style time for table cells: time only for today, else month and day.
function Tradewright:FormatShortTime(ts)
	ts = tonumber(ts)
	if not ts or ts <= 0 then
		return "-"
	end
	if date("%Y-%m-%d", ts) == date("%Y-%m-%d") then
		return date("%H:%M", ts)
	end
	return date("%b %d", ts)
end

-- Shift-click links the item in chat. Returns true when the click was used.
function Tradewright:HandleItemRowModifiedClick(itemID)
	if not itemID or not IsModifiedClick or not IsModifiedClick("CHATLINK") then
		return false
	end
	local desc = self:ResolveItemDescriptor(tonumber(itemID) or itemID)
	local link = desc and desc.link
	if link and ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
		return true
	end
	return false
end

