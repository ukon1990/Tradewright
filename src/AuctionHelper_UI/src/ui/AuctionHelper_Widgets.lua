local addonName, ProfessionExporter = ...

local function copySelection(selection)
	local out = {}
	if type(selection) ~= "table" then
		return out
	end
	for key, value in pairs(selection) do
		if value then
			out[key] = true
		end
	end
	return out
end

function ProfessionExporter:IsFilterSelectionEmpty(selection)
	return type(selection) ~= "table" or next(selection) == nil
end

function ProfessionExporter:CountFilterSelection(selection)
	local count = 0
	if type(selection) ~= "table" then
		return count
	end
	for _, value in pairs(selection) do
		if value then
			count = count + 1
		end
	end
	return count
end

function ProfessionExporter:GetFilterSelectionSummary(options, selection, allLabel)
	if self:IsFilterSelectionEmpty(selection) then
		return allLabel
	end

	local selectedLabels = {}
	for _, option in ipairs(options or {}) do
		if option.value ~= "all" and selection[option.value] then
			table.insert(selectedLabels, option.label)
		end
	end

	if #selectedLabels == 0 then
		return allLabel
	end
	if #selectedLabels <= 2 then
		return table.concat(selectedLabels, ", ")
	end
	return string.format("%d selected", #selectedLabels)
end

function ProfessionExporter:NormalizeFilterSelection(selection, options)
	local valid = {}
	for _, option in ipairs(options or {}) do
		if option.value ~= "all" then
			valid[option.value] = true
		end
	end

	local normalized = {}
	for key, value in pairs(selection or {}) do
		if value and valid[key] then
			normalized[key] = true
		end
	end
	return normalized
end

local DROPDOWN_HEIGHT = 26
local DROPDOWN_LABEL_GAP = 18

-- A flat 26px dropdown button with an optional label above it. The Blizzard menu frame is only used to
-- show the option list, anchored under the button. Holder height: 26, or 44 with a label.
local function createDropdownShell(parent, config)
	local holder = CreateFrame("Frame", nil, parent)
	local hasLabel = config.label ~= false and config.label ~= nil
	holder.width = config.width or 210
	holder:SetSize(holder.width, DROPDOWN_HEIGHT + (hasLabel and DROPDOWN_LABEL_GAP or 0))

	if hasLabel then
		local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		title:SetPoint("TOPLEFT", 0, 0)
		title:SetPoint("TOPRIGHT", 0, 0)
		title:SetJustifyH("LEFT")
		title:SetWordWrap(false)
		local muted = ProfessionExporter:GetTheme().textMuted
		title:SetTextColor(muted.r, muted.g, muted.b)
		title:SetText(config.label)
		holder.title = title
	end

	local button = CreateFrame("Button", nil, holder)
	button:SetPoint("BOTTOMLEFT", 0, 0)
	button:SetPoint("BOTTOMRIGHT", 0, 0)
	button:SetHeight(DROPDOWN_HEIGHT)
	local theme = ProfessionExporter:GetTheme()
	ProfessionExporter:AddSurface(button, theme.surface2, theme.borderControl)
	button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
	button:GetHighlightTexture():SetVertexColor(theme.gold.r, theme.gold.g, theme.gold.b, 0.09)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", 8, 0)
	text:SetPoint("RIGHT", -22, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	local caret = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caret:SetPoint("RIGHT", -8, 0)
	caret:SetText("v")
	caret:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	holder.button = button
	holder.text = text

	local menu = CreateFrame("Frame", nil, holder, "UIDropDownMenuTemplate")
	menu:Hide()
	holder.dropdown = menu
	button:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, menu, button, 0, 0)
	end)

	function holder:SetDisplayText(label)
		self.text:SetText(label or "")
	end
	if config.tooltip then
		button:SetScript("OnEnter", function()
			GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
			GameTooltip:SetText(config.tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
	end
	return holder, menu
end

local function resolveOptions(holder)
	if holder.currentOptions then
		return holder.currentOptions
	end
	if type(holder.getOptions) == "function" then
		return holder.getOptions() or {}
	end
	return holder.options or {}
end

function ProfessionExporter:CreateMultiSelectDropdown(parent, config)
	config = config or {}
	local holder, menu = createDropdownShell(parent, config)
	holder.allLabel = config.allLabel or "All"
	holder.options = config.options or {}
	holder.getOptions = config.getOptions
	holder.getSelection = config.getSelection
	holder.setSelection = config.setSelection
	holder.onChanged = config.onChanged

	local function getSelection()
		return type(holder.getSelection) == "function" and holder.getSelection() or {}
	end

	local function applySelection(selection)
		selection = copySelection(selection)
		if type(holder.setSelection) == "function" then
			holder.setSelection(selection)
		end
		holder:RefreshText()
		if type(holder.onChanged) == "function" then
			holder.onChanged(selection)
		end
	end

	function holder:RefreshText()
		self:SetDisplayText(ProfessionExporter:GetFilterSelectionSummary(resolveOptions(self), getSelection(), self.allLabel))
	end
	function holder:SetOptions(options)
		self.currentOptions = options or {}
		self:RefreshText()
	end

	UIDropDownMenu_Initialize(menu, function(_, level)
		if level ~= 1 then
			return
		end
		local allInfo = UIDropDownMenu_CreateInfo()
		allInfo.text = holder.allLabel
		allInfo.isNotRadio = true
		allInfo.keepShownOnClick = true
		allInfo.checked = function()
			return ProfessionExporter:IsFilterSelectionEmpty(getSelection())
		end
		allInfo.func = function()
			applySelection({})
		end
		UIDropDownMenu_AddButton(allInfo, level)

		for _, option in ipairs(resolveOptions(holder)) do
			if option.value ~= "all" then
				local info = UIDropDownMenu_CreateInfo()
				info.text = option.label
				info.isNotRadio = true
				info.keepShownOnClick = true
				info.checked = function()
					return getSelection()[option.value] == true
				end
				info.func = function()
					local nextSelection = copySelection(getSelection())
					nextSelection[option.value] = not nextSelection[option.value] or nil
					applySelection(nextSelection)
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end, "MENU")

	holder:RefreshText()
	return holder
end

function ProfessionExporter:CreateSingleSelectDropdown(parent, config)
	config = config or {}
	local holder, menu = createDropdownShell(parent, config)
	holder.options = config.options or {}
	holder.getOptions = config.getOptions
	holder.getValue = config.getValue
	holder.setValue = config.setValue
	holder.onChanged = config.onChanged

	local function getValue()
		return type(holder.getValue) == "function" and holder.getValue() or nil
	end

	function holder:RefreshText()
		local current = getValue()
		local label = config.placeholder or "Select"
		for _, option in ipairs(resolveOptions(self)) do
			if option.value == current then
				label = option.label
				break
			end
		end
		self:SetDisplayText(label)
	end
	function holder:SetOptions(options)
		self.currentOptions = options or {}
		self:RefreshText()
	end

	UIDropDownMenu_Initialize(menu, function(_, level)
		if level ~= 1 then
			return
		end
		local current = getValue()
		for _, option in ipairs(resolveOptions(holder)) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = option.label
			info.checked = current == option.value
			info.func = function()
				if type(holder.setValue) == "function" then
					holder.setValue(option.value)
				end
				holder:RefreshText()
				if type(holder.onChanged) == "function" then
					holder.onChanged(option.value)
				end
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end, "MENU")

	holder:RefreshText()
	return holder
end

function ProfessionExporter:CreateMenuDropdown(parent, config)
	config = config or {}
	local holder, menu = createDropdownShell(parent, config)
	holder.getText = config.getText
	holder.initializeMenu = config.initializeMenu

	function holder:RefreshText()
		self:SetDisplayText(type(self.getText) == "function" and self.getText() or (config.placeholder or "Menu"))
	end

	UIDropDownMenu_Initialize(menu, function(_, level)
		if type(holder.initializeMenu) == "function" then
			holder.initializeMenu(level, holder)
		end
	end, "MENU")

	holder:RefreshText()
	return holder
end

function ProfessionExporter:CreateCard(parent, width, height, tone)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	card:SetSize(width or 100, height or 100)
	self:StylePanel(card, tone or "surface2")
	return card
end

function ProfessionExporter:CreateSectionTitle(parent, text)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetText(text or "")
	label:SetJustifyH("LEFT")
	return label
end

function ProfessionExporter:CreateMutedText(parent, width)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetWidth(width or 200)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(true)
	local muted = self:GetTheme().textMuted
	label:SetTextColor(muted.r, muted.g, muted.b)
	return label
end

function ProfessionExporter:CreateStatusBadge(parent, text, colorKey)
	local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	badge:SetSize(120, 20)
	local theme = self:GetTheme()
	local border = theme[colorKey or "accent"] or theme.accent
	self:ApplyBackdrop(badge, theme.surface3, border)
	badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge.text:SetPoint("CENTER")
	badge.text:SetText(text or "")
	return badge
end

local function setColor(fontString, color)
	fontString:SetTextColor(color.r, color.g, color.b)
end

local function newText(parent, font, color, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	setColor(text, color or ProfessionExporter:GetTheme().textPrimary)
	return text
end

-- A single-line text that truncates with an ellipsis. Anchor it with two points.
function ProfessionExporter:CreateText(parent, font, colorKey, justify)
	return newText(parent, font, self:GetTheme()[colorKey or "textPrimary"], justify)
end

-- A 26px flat button sized to its label (or `opts.width`); `opts.small` is 22px, `opts.primary` gold.
function ProfessionExporter:CreateButton(parent, label, onClick, opts)
	opts = opts or {}
	local sizes = self:GetTheme().size
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(label or "")
	self:SkinButton(button)
	local height = opts.small and sizes.controlSmall or sizes.control
	local padding = opts.small and 16 or 24
	button:SetSize(opts.width or (math.ceil(button:GetFontString():GetStringWidth()) + padding), height)
	if opts.primary then
		self:SetButtonPrimary(button, true)
	end
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	if opts.tooltip then
		-- HookScript keeps the skin's hover colour handlers.
		button:HookScript("OnEnter", function(self)
			local muted = ProfessionExporter:GetTheme().textMuted
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self:GetText() or label or "", 1, 1, 1)
			GameTooltip:AddLine(opts.tooltip, muted.r, muted.g, muted.b, true)
			GameTooltip:Show()
		end)
		button:HookScript("OnLeave", GameTooltip_Hide)
	end
	return button
end

-- Re-fits a button created by CreateButton after its label changes.
function ProfessionExporter:SetButtonLabel(button, label, small)
	button:SetText(label or "")
	button:SetWidth(math.ceil(button:GetFontString():GetStringWidth()) + (small and 16 or 24))
end

-- Lays frames out left to right from `first`'s current anchor, `gap` apart, vertically centred.
function ProfessionExporter:ChainRight(frames, gap)
	for index = 2, #frames do
		frames[index]:ClearAllPoints()
		frames[index]:SetPoint("LEFT", frames[index - 1], "RIGHT", gap or 8, 0)
	end
end

-- Right to left: frames[1] is the rightmost and keeps its anchor.
function ProfessionExporter:ChainLeft(frames, gap)
	for index = 2, #frames do
		frames[index]:ClearAllPoints()
		frames[index]:SetPoint("RIGHT", frames[index - 1], "LEFT", -(gap or 8), 0)
	end
end

-- Section heading: gold text followed by a 1px rule to the right edge. 18px tall.
function ProfessionExporter:CreateHeading(parent, label)
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
	heading.rule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	function heading:SetText(text)
		self.text:SetText(text or "")
	end
	return heading
end

-- A raised group: surface2 fill with a subtle outline. Content is placed by the caller with 10px padding.
function ProfessionExporter:CreateInset(parent)
	local inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	self:StylePanel(inset, "surface2")
	return inset
end

-- Summary tile: muted label, one large value, one muted note. 58px tall; width from anchors.
function ProfessionExporter:CreateStat(parent)
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
function ProfessionExporter:LayoutEvenRow(parent, frames, top, gap)
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
function ProfessionExporter:AddSearchPlaceholder(box, placeholder)
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
	box.placeholder:SetText(placeholder or "Search")
	box:UpdatePlaceholder()
	return box
end

-- An edit box with placeholder text, skinned 26px tall. `onChanged(text)` fires after `delay` seconds.
function ProfessionExporter:CreateSearchBox(parent, placeholder, onChanged, delay)
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
function ProfessionExporter:StyleProgressBar(bar)
	local theme = self:GetTheme()
	bar:SetHeight(14)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(theme.tick.r, theme.tick.g, theme.tick.b, 1)
	bar:SetMinMaxValues(0, 1)
	if not bar.ahTrack then
		bar.ahTrack = bar:CreateTexture(nil, "BACKGROUND")
		bar.ahTrack:SetAllPoints()
		bar.ahTrack:SetColorTexture(theme.surface3.r, theme.surface3.g, theme.surface3.b, 1)
		self:AddSurface(bar, { r = 0, g = 0, b = 0, a = 0 }, theme.borderStrong, 1, 1)
	end
	return bar
end

-- Label/value pairs, label muted on the left and value on the right, 16px rows. Returns its height.
function ProfessionExporter:CreateKeyValueList(parent)
	local theme = self:GetTheme()
	local list = CreateFrame("Frame", nil, parent)
	list.rows = {}
	function list:SetRows(rows)
		for index, row in ipairs(rows or {}) do
			local line = self.rows[index]
			if not line then
				line = {}
				line.value = newText(self, "GameFontHighlightSmall", theme.textPrimary, "RIGHT")
				line.value:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -((index - 1) * 16))
				line.label = newText(self, "GameFontHighlightSmall", theme.textMuted)
				line.label:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -((index - 1) * 16))
				line.label:SetPoint("RIGHT", line.value, "LEFT", -12, 0)
				self.rows[index] = line
			end
			line.label:SetText(row[1] or "")
			line.value:SetText(row[2] or "")
			setColor(line.value, theme[row[3] or "textPrimary"] or theme.textPrimary)
			line.label:Show()
			line.value:Show()
		end
		for index = #(rows or {}) + 1, #self.rows do
			self.rows[index].label:Hide()
			self.rows[index].value:Hide()
		end
		local height = math.max(1, #(rows or {}) * 16)
		self:SetHeight(height)
		return height
	end
	return list
end

-- A selectable one-column list (character list, docs topics) built on the shared table.
-- items: { { key, label } }; `onSelect(key)`; `getSelected()` returns the selected key.
function ProfessionExporter:CreateSelectList(parent, onSelect, getSelected)
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
function ProfessionExporter:FlowButtons(container, buttons, width, gap, top)
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
function ProfessionExporter:CreateParagraph(parent, colorKey)
	local text = self:CreateText(parent, "GameFontHighlightSmall", colorKey or "textMuted")
	text:SetWordWrap(true)
	text:SetNonSpaceWrap(true)
	return text
end

-- Professions of one character as table rows, sorted by name.
function ProfessionExporter:BuildProfessionRows(charData)
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
function ProfessionExporter:CreateProfessionColumns(withoutExport)
	local pe = self
	local columns = {
		{ id = "name", label = "Profession", width = 120, flex = 1, minWidth = 100,
			getText = function(row) return row.name end },
		{ id = "skill", label = "Skill", width = 64, justifyH = "RIGHT",
			getText = function(row) return string.format("%d/%d", row.skill, row.maxSkill) end },
		{ id = "recipes", label = "Recipes", width = 64, justifyH = "RIGHT",
			getText = function(row) return pe:FormatNumberGrouped(row.recipes) end },
	}
	if withoutExport then
		return columns
	end
	columns[#columns + 1] = { id = "export", label = "Export", width = 196,
		createCell = function(rowFrame)
			local cell = CreateFrame("Frame", nil, rowFrame)
			cell:SetHeight(22)
			cell.all = pe:CreateButton(cell, "All", nil, { small = true })
			cell.all:SetPoint("LEFT", 5, 0)
			cell.recipes = pe:CreateButton(cell, "Recipes", nil, { small = true })
			cell.talents = pe:CreateButton(cell, "Talents", nil, { small = true })
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
function ProfessionExporter:GetItemLook(itemID)
	local desc = itemID and self:ResolveItemDescriptor(tonumber(itemID) or itemID) or nil
	local quality = desc and desc.quality
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return desc and desc.icon or DEFAULT_ITEM_ICON, color or { r = 1, g = 1, b = 1 }
end

-- An 18px item icon outlined in its quality colour. `size` overrides (32 for detail headers).
function ProfessionExporter:CreateItemIcon(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size or 18, size or 18)
	holder.border = holder:CreateTexture(nil, "BORDER")
	holder.border:SetAllPoints()
	holder.icon = holder:CreateTexture(nil, "ARTWORK")
	holder.icon:SetPoint("TOPLEFT", 1, -1)
	holder.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	function holder:SetItem(itemID, iconOverride)
		local icon, color = ProfessionExporter:GetItemLook(itemID)
		self.icon:SetTexture(iconOverride or icon)
		self.border:SetColorTexture(color.r, color.g, color.b, 0.9)
	end
	return holder
end

-- Table column: item icon + quality-coloured name, with an optional muted second line
-- (`getDetail(row)`) when the table uses tall rows. `getItemID`, `getName` read the row.
function ProfessionExporter:CreateItemColumn(spec)
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
	column.updateCell = function(cell, row)
		local itemID = spec.getItemID(row)
		local _, color = pe:GetItemLook(itemID)
		cell.icon:SetItem(itemID, spec.getIcon and spec.getIcon(row) or nil)
		cell.name:SetText(spec.getName(row) or ("#" .. tostring(itemID or "?")))
		cell.name:SetTextColor(color.r, color.g, color.b)
		local detail = spec.getDetail and spec.getDetail(row) or nil
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
	return column
end

-- Uppercase status word with a 1px outline in its colour. `colorKey`: success, danger, warning, accent, gold.
function ProfessionExporter:CreateBadge(parent)
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetHeight(16)
	badge.text = self:CreateText(badge, "GameFontNormalSmall")
	badge.text:SetPoint("CENTER", 0, 0)
	badge.surface = self:AddSurface(badge, { r = 0, g = 0, b = 0, a = 0 }, self:GetTheme().textMuted)
	function badge:SetBadge(text, colorKey)
		local theme = ProfessionExporter:GetTheme()
		local color = theme[colorKey or "textMuted"] or theme.textMuted
		self.text:SetText(string.upper(text or ""))
		self.text:SetTextColor(color.r, color.g, color.b)
		self.surface:SetColors(nil, color)
		self:SetWidth(math.ceil(self.text:GetStringWidth()) + 12)
		self:SetShown(text ~= nil and text ~= "")
	end
	return badge
end

-- Detail pane header: 32px item icon, name, muted second line, optional close button.
function ProfessionExporter:CreateDetailHeader(parent, onClose)
	local header = CreateFrame("Frame", nil, parent)
	header:SetHeight(32)
	header.icon = self:CreateItemIcon(header, 32)
	header.icon:SetPoint("LEFT")
	local right = header
	if onClose then
		header.close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
		header.close:ClearAllPoints()
		header.close:SetPoint("TOPRIGHT", 0, 0)
		self:SkinCloseButton(header.close)
		header.close:SetScript("OnClick", onClose)
		right = header.close
	end
	header.badge = self:CreateBadge(header)
	header.badge:SetPoint("TOPRIGHT", right, right == header and "TOPRIGHT" or "TOPLEFT", right == header and 0 or -6, -2)
	header.badge:Hide()
	header.title = self:CreateText(header, "GameFontHighlight")
	header.title:SetPoint("TOPLEFT", header.icon, "TOPRIGHT", 8, -1)
	header.title:SetPoint("RIGHT", header, "RIGHT", -60, 0)
	header.subtitle = self:CreateText(header, "GameFontHighlightSmall", "textMuted")
	header.subtitle:SetPoint("BOTTOMLEFT", header.icon, "BOTTOMRIGHT", 8, 1)
	header.subtitle:SetPoint("RIGHT", header, "RIGHT", 0, 0)
	function header:SetItem(itemID, title, subtitle, iconOverride)
		local _, color = ProfessionExporter:GetItemLook(itemID)
		self.icon:SetItem(itemID, iconOverride)
		self.icon:Show()
		self.title:SetText(title or "")
		self.title:SetTextColor(color.r, color.g, color.b)
		self.subtitle:SetText(subtitle or "")
	end
	return header
end

-- Centered "nothing here" message: title plus a muted sentence. Fill the area it covers.
function ProfessionExporter:CreateEmptyState(parent)
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

-- Signed money: "+3g 15s" with a green plus, negative amounts with a red minus, "-" when unknown.
function ProfessionExporter:FormatSignedMoney(copper)
	local n = tonumber(copper)
	if not n then
		return "-"
	end
	if n < 0 then
		return self:FormatCopperShort(n)
	end
	local c = self:GetTheme().success
	return string.format("|cff%02x%02x%02x+|r", c.r * 255, c.g * 255, c.b * 255) .. self:FormatCopperShort(n)
end

-- "today 14:32" style time for table cells: time only for today, else month and day.
function ProfessionExporter:FormatShortTime(ts)
	ts = tonumber(ts)
	if not ts or ts <= 0 then
		return "-"
	end
	if date("%Y-%m-%d", ts) == date("%Y-%m-%d") then
		return date("%H:%M", ts)
	end
	return date("%b %d", ts)
end

-- Item tooltip for a table row: anchored to the row's right edge, the game's item tooltip, then
-- AuctionHelper's label/value pairs and a muted hint. `pairs`: { { label, value }, ... }.
function ProfessionExporter:ShowItemRowTooltip(owner, itemID, pairs, hint)
	if not owner then
		return
	end
	local theme = self:GetTheme()
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(itemID)
	end
	if pairs and #pairs > 0 then
		GameTooltip:AddLine(" ")
		for _, pair in ipairs(pairs) do
			GameTooltip:AddDoubleLine(pair[1], pair[2] or "-", theme.textMuted.r, theme.textMuted.g, theme.textMuted.b,
				theme.textPrimary.r, theme.textPrimary.g, theme.textPrimary.b)
		end
	end
	if hint then
		GameTooltip:AddLine(hint, theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, true)
	end
	GameTooltip:Show()
end

-- Shift-click links the item in chat. Returns true when the click was used.
function ProfessionExporter:HandleItemRowModifiedClick(itemID)
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

--- Reusable line chart: sorted points `{ at = unixHourOrTime, value = number, label?, meta? }`.
--- Optional `secondarySeries` (copper, left axis); optional `quantitySeries` (counts, right axis).
--- Tooltip callback: `builder(tip, hit)` where `hit = { kind = "primary"|"secondary"|"quantity", pt = point }`.
function ProfessionExporter:CreateTimeSeriesGraph(parent, opts)
	opts = opts or {}
	local plotH = tonumber(opts.plotHeight) or 118
	local padL = tonumber(opts.padLeft) or 58
	local padRBase = tonumber(opts.padRight) or 10
	local padQtyAxis = 34
	local padT = tonumber(opts.padTop) or 6
	local padB = tonumber(opts.padBottom) or 22

	local holder = CreateFrame("Frame", nil, parent)
	holder:SetHeight(plotH + padT + padB + (opts.showTitle ~= false and 16 or 0))

	local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	if opts.showTitle ~= false then
		title:SetPoint("TOPLEFT", holder, "TOPLEFT", 2, -2)
		title:SetJustifyH("LEFT")
	end

	local plot = CreateFrame("Frame", nil, holder)
	if opts.showTitle ~= false then
		plot:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -4)
	else
		plot:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	end
	plot:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
	plot:SetHeight(plotH)
	plot:EnableMouse(true)

	local theme = ProfessionExporter:GetTheme()
	local emptyText = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("LEFT", plot, "LEFT", 20, 0)
	emptyText:SetPoint("RIGHT", plot, "RIGHT", -20, 0)
	emptyText:SetJustifyH("CENTER")
	emptyText:SetWordWrap(true)
	emptyText:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	local function axisText()
		local fs = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetWordWrap(false)
		fs:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
		return fs
	end

	local innerPlotH = plotH - padT - padB
	local yLabels = {}
	for i = 1, 3 do
		local fs = axisText()
		fs:SetPoint("TOPRIGHT", plot, "TOPLEFT", padL - 4, -padT - (i - 1) * (innerPlotH / 2))
		fs:SetJustifyH("RIGHT")
		fs:SetWidth(padL - 2)
		yLabels[i] = fs
	end

	local yLabelsRight = {}
	for i = 1, 3 do
		local fs = axisText()
		fs:SetPoint("TOPRIGHT", plot, "TOPRIGHT", -4, -padT - (i - 1) * (innerPlotH / 2))
		fs:SetJustifyH("RIGHT")
		fs:SetWidth(padQtyAxis + padRBase - 4)
		yLabelsRight[i] = fs
		fs:Hide()
	end

	local xLabels = {}
	do
		local xl = axisText()
		xl:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", padL + 2, 2)
		xl:SetJustifyH("LEFT")
		xLabels[1] = xl
		local xr = axisText()
		xr:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -padRBase - 2, 2)
		xr:SetJustifyH("RIGHT")
		xLabels[2] = xr
	end

	local gridLines = {}
	local segmentLines = {}
	local markers = {}
	local secondarySegmentLines = {}
	local secondaryMarkers = {}
	local quantitySegmentLines = {}
	local quantityMarkers = {}

	local series = {}
	local secondarySeries = {}
	local quantitySeries = {}
	local yFormatter = opts.yFormatter or function(v)
		return tostring(math.floor(tonumber(v) or 0))
	end
	local rightYFormatter = function(v)
		return ProfessionExporter:FormatNumberGrouped(math.floor(tonumber(v) or 0))
	end
	local tooltipBuilder = opts.tooltipBuilder
	local emptyStateText = opts.emptyText or "No data in this range."
	local accent = opts.accentColor or ProfessionExporter:GetTheme().accent
	local secondaryAccent = theme.warning
	local quantityAccent = theme.success
	local canUseCreateLine = type(plot.CreateLine) == "function"

	local function hidePool(pool)
		for _, region in ipairs(pool) do
			region:Hide()
		end
	end

	local function getGridLine(i)
		local ln = gridLines[i]
		if not ln and canUseCreateLine then
			ln = plot:CreateLine()
			ln:SetThickness(1)
			gridLines[i] = ln
		end
		return ln
	end

	local function getSegmentLine(pool, i, thickness)
		local ln = pool[i]
		if not ln and canUseCreateLine then
			ln = plot:CreateLine()
			ln:SetThickness(thickness or 2)
			pool[i] = ln
		end
		return ln
	end

	local function getMarker(pool, i, size)
		local t = pool[i]
		if not t then
			t = plot:CreateTexture(nil, "ARTWORK")
			t:SetSize(size or 6, size or 6)
			pool[i] = t
		end
		return t
	end

	local function tsFmt(at)
		if not at or at <= 0 then
			return "—"
		end
		return date("%m-%d %H:%M", at)
	end

	local function expandTimeRange(pts, minT, maxT)
		for _, p in ipairs(pts or {}) do
			local t = p.at
			if t then
				if not minT or t < minT then
					minT = t
				end
				if not maxT or t > maxT then
					maxT = t
				end
			end
		end
		return minT, maxT
	end

	local function layoutGeometry(hasQty)
		local w = plot:GetWidth()
		local h = plot:GetHeight()
		if w < 40 or h < 40 then
			return nil
		end
		local padR = hasQty and (padRBase + padQtyAxis) or padRBase
		local innerW = w - padL - padR
		local innerH = h - padT - padB
		if innerW < 20 or innerH < 20 then
			return nil
		end
		return w, h, innerW, innerH, padR
	end

	local function paint()
		hidePool(gridLines)
		hidePool(segmentLines)
		hidePool(markers)
		hidePool(secondarySegmentLines)
		hidePool(secondaryMarkers)
		hidePool(quantitySegmentLines)
		hidePool(quantityMarkers)
		emptyText:Hide()
		for _, fs in ipairs(yLabels) do
			fs:SetText("")
		end
		for _, fs in ipairs(yLabelsRight) do
			fs:SetText("")
			fs:Hide()
		end
		for _, fs in ipairs(xLabels) do
			fs:SetText("")
		end

		local hasQty = quantitySeries and #quantitySeries > 0
		local plotW, ph, innerW, innerH, padR = layoutGeometry(hasQty)
		if not plotW or not innerW or not innerH then
			emptyText:SetText(emptyStateText)
			emptyText:Show()
			return
		end

		if not series or #series == 0 then
			emptyText:SetText(emptyStateText)
			emptyText:Show()
			return
		end

		local minT, maxT = expandTimeRange(series, nil, nil)
		minT, maxT = expandTimeRange(secondarySeries, minT, maxT)
		minT, maxT = expandTimeRange(quantitySeries, minT, maxT)
		if not minT or not maxT then
			emptyText:SetText(emptyStateText)
			emptyText:Show()
			return
		end
		if minT == maxT then
			minT = minT - 3600
			maxT = maxT + 3600
		end

		local minV, maxV = series[1].value, series[1].value
		for i = 2, #series do
			local p = series[i]
			minV = math.min(minV, p.value)
			maxV = math.max(maxV, p.value)
		end
		for _, p in ipairs(secondarySeries or {}) do
			minV = math.min(minV, p.value)
			maxV = math.max(maxV, p.value)
		end
		if minV == maxV then
			minV = minV - 1
			maxV = maxV + 1
		end
		if maxV <= minV then
			maxV = minV + 1
		end

		local minQ, maxQ = 0, 1
		if hasQty then
			minQ = quantitySeries[1].value
			maxQ = quantitySeries[1].value
			for i = 2, #quantitySeries do
				local p = quantitySeries[i]
				minQ = math.min(minQ, p.value)
				maxQ = math.max(maxQ, p.value)
			end
			if minQ == maxQ then
				minQ = math.max(0, minQ - 1)
				maxQ = maxQ + 1
			end
			if maxQ <= minQ then
				maxQ = minQ + 1
			end
			for _, fs in ipairs(yLabelsRight) do
				fs:Show()
			end
			yLabelsRight[1]:SetText(rightYFormatter(maxQ))
			yLabelsRight[2]:SetText(rightYFormatter((maxQ + minQ) / 2))
			yLabelsRight[3]:SetText(rightYFormatter(minQ))
		end

		xLabels[2]:ClearAllPoints()
		xLabels[2]:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -padR - 2, 2)

		local theme = ProfessionExporter:GetTheme()
		local gridColor = theme.borderSubtle or { r = 0.3, g = 0.32, b = 0.36, a = 0.45 }
		local gx, gy, ga = gridColor.r or 0.3, gridColor.g or 0.32, gridColor.b or 0.36
		local gaa = gridColor.a or 0.5

		for g = 1, 3 do
			local ln = getGridLine(g)
			if ln then
				local y = padB + (g - 1) * (innerH / 2)
				ln:SetColorTexture(gx, gy, ga, gaa)
				ln:SetStartPoint("BOTTOMLEFT", padL, y)
				ln:SetEndPoint("BOTTOMLEFT", padL + innerW, y)
				ln:Show()
			end
		end

		yLabels[1]:SetText(yFormatter(maxV))
		yLabels[2]:SetText(yFormatter((maxV + minV) / 2))
		yLabels[3]:SetText(yFormatter(minV))

		xLabels[1]:SetText(tsFmt(series[1].at))
		xLabels[2]:SetText(tsFmt(series[#series].at))

		local function xAt(at)
			return padL + ((at - minT) / (maxT - minT)) * innerW
		end
		local function yAt(val)
			return padB + ((val - minV) / (maxV - minV)) * innerH
		end
		local function yAtQ(val)
			if not hasQty then
				return padB
			end
			return padB + ((val - minQ) / (maxQ - minQ)) * innerH
		end

		local hitTargets = {}
		local function pushHits(pts, kind, yFn)
			for _, p in ipairs(pts or {}) do
				hitTargets[#hitTargets + 1] = {
					kind = kind,
					pt = p,
					x = xAt(p.at),
					y = yFn(p.value),
				}
			end
		end
		pushHits(series, "primary", yAt)
		pushHits(secondarySeries, "secondary", yAt)
		pushHits(quantitySeries, "quantity", yAtQ)

		plot._peGeom = {
			padL = padL,
			padR = padR,
			padT = padT,
			padB = padB,
			innerW = innerW,
			innerH = innerH,
			minT = minT,
			maxT = maxT,
			minV = minV,
			maxV = maxV,
			minQ = minQ,
			maxQ = maxQ,
			hasQty = hasQty,
			hitTargets = hitTargets,
			series = series,
		}

		local ar, ag, ab = accent.r or 0.35, accent.g or 0.75, accent.b or 0.85
		local aa = accent.a or 0.95

		for i = 1, #series - 1 do
			local a, b = series[i], series[i + 1]
			local x1, y1 = xAt(a.at), yAt(a.value)
			local x2, y2 = xAt(b.at), yAt(b.value)
			local ln = getSegmentLine(segmentLines, i, 2)
			if ln then
				ln:SetColorTexture(ar, ag, ab, aa)
				ln:SetStartPoint("BOTTOMLEFT", x1, y1)
				ln:SetEndPoint("BOTTOMLEFT", x2, y2)
				ln:Show()
			end
		end

		for i = 1, #series do
			local p = series[i]
			local mx, my = xAt(p.at), yAt(p.value)
			local t = getMarker(markers, i, 6)
			t:SetColorTexture(ar, ag, ab, aa)
			t:ClearAllPoints()
			t:SetPoint("CENTER", plot, "BOTTOMLEFT", mx, my)
			t:Show()
		end

		local sr, sg, sb = secondaryAccent.r or 0.92, secondaryAccent.g or 0.58, secondaryAccent.b or 0.18
		local sa = secondaryAccent.a or 0.95
		for i = 1, #(secondarySeries or {}) - 1 do
			local a, b = secondarySeries[i], secondarySeries[i + 1]
			local x1, y1 = xAt(a.at), yAt(a.value)
			local x2, y2 = xAt(b.at), yAt(b.value)
			local ln = getSegmentLine(secondarySegmentLines, i, 2)
			if ln then
				ln:SetColorTexture(sr, sg, sb, sa)
				ln:SetStartPoint("BOTTOMLEFT", x1, y1)
				ln:SetEndPoint("BOTTOMLEFT", x2, y2)
				ln:Show()
			end
		end
		for i = 1, #(secondarySeries or {}) do
			local p = secondarySeries[i]
			local mx, my = xAt(p.at), yAt(p.value)
			local t = getMarker(secondaryMarkers, i, 5)
			t:SetColorTexture(sr, sg, sb, sa)
			t:ClearAllPoints()
			t:SetPoint("CENTER", plot, "BOTTOMLEFT", mx, my)
			t:Show()
		end

		local qr, qg, qb = quantityAccent.r or 0.42, quantityAccent.g or 0.78, quantityAccent.b or 0.5
		local qa = quantityAccent.a or 0.9
		for i = 1, #(quantitySeries or {}) - 1 do
			local a, b = quantitySeries[i], quantitySeries[i + 1]
			local x1, y1 = xAt(a.at), yAtQ(a.value)
			local x2, y2 = xAt(b.at), yAtQ(b.value)
			local ln = getSegmentLine(quantitySegmentLines, i, 1)
			if ln then
				ln:SetColorTexture(qr, qg, qb, qa)
				ln:SetStartPoint("BOTTOMLEFT", x1, y1)
				ln:SetEndPoint("BOTTOMLEFT", x2, y2)
				ln:Show()
			end
		end
		for i = 1, #(quantitySeries or {}) do
			local p = quantitySeries[i]
			local mx, my = xAt(p.at), yAtQ(p.value)
			local t = getMarker(quantityMarkers, i, 4)
			t:SetColorTexture(qr, qg, qb, qa)
			t:ClearAllPoints()
			t:SetPoint("CENTER", plot, "BOTTOMLEFT", mx, my)
			t:Show()
		end
	end

	local hoverKey = nil
	plot:SetScript("OnUpdate", function()
		if not plot._peGeom or not plot:IsMouseOver() then
			if hoverKey then
				GameTooltip:Hide()
				hoverKey = nil
			end
			return
		end
		local g = plot._peGeom
		local mx, my = GetCursorPosition()
		local scale = plot:GetEffectiveScale()
		local lx, ly = plot:GetLeft(), plot:GetBottom()
		if not lx or not ly then
			return
		end
		local px = (mx / scale) - lx
		local py = (my / scale) - ly
		local bestIdx, bestDist = nil, 1e9
		local targets = g.hitTargets or {}
		for i = 1, #targets do
			local h = targets[i]
			local dx = px - h.x
			local dy = py - h.y
			local d = dx * dx + dy * dy
			if d < bestDist then
				bestDist = d
				bestIdx = i
			end
		end
		if not bestIdx or bestDist > 30 * 30 then
			if hoverKey then
				GameTooltip:Hide()
				hoverKey = nil
			end
			return
		end
		local hit = targets[bestIdx]
		local key = tostring(bestIdx) .. ":" .. tostring(hit.kind) .. ":" .. tostring(hit.pt.at)
		if hoverKey == key and GameTooltip:IsShown() then
			return
		end
		hoverKey = key
		GameTooltip:SetOwner(plot, "ANCHOR_CURSOR")
		if GameTooltip.ClearLines then
			GameTooltip:ClearLines()
		elseif GameTooltip_Clear then
			GameTooltip_Clear(GameTooltip)
		end
		if type(tooltipBuilder) == "function" then
			tooltipBuilder(GameTooltip, hit)
		else
			GameTooltip:AddLine(tsFmt(hit.pt.at), 1, 1, 1)
			GameTooltip:AddLine(yFormatter(hit.pt.value), 0.8, 0.9, 1)
		end
		GameTooltip:Show()
	end)

	plot:SetScript("OnLeave", function()
		GameTooltip:Hide()
		hoverKey = nil
	end)

	holder.plot = plot
	holder.title = title
	holder.SetTitle = function(_, text)
		title:SetText(text or "")
	end
	holder.SetEmptyText = function(_, text)
		emptyStateText = text or emptyStateText
	end
	holder.SetSeries = function(_, data)
		series = type(data) == "table" and data or {}
	end
	holder.SetSecondarySeries = function(_, data)
		secondarySeries = type(data) == "table" and data or {}
	end
	holder.SetQuantitySeries = function(_, data)
		quantitySeries = type(data) == "table" and data or {}
	end
	holder.SetYFormatter = function(_, fn)
		if type(fn) == "function" then
			yFormatter = fn
		end
	end
	holder.SetRightYFormatter = function(_, fn)
		if type(fn) == "function" then
			rightYFormatter = fn
		end
	end
	holder.SetTooltipBuilder = function(_, fn)
		tooltipBuilder = fn
	end
	holder.SetAccentColor = function(_, c)
		if type(c) == "table" then
			accent = c
		end
	end
	holder.SetSecondaryAccentColor = function(_, c)
		if type(c) == "table" then
			secondaryAccent = c
		end
	end
	holder.SetQuantityAccentColor = function(_, c)
		if type(c) == "table" then
			quantityAccent = c
		end
	end
	holder.Refresh = function()
		paint()
	end

	holder:SetScript("OnSizeChanged", function()
		paint()
	end)

	title:SetText(opts.title or "")
	holder:SetSeries(opts.series)
	holder:SetSecondarySeries({})
	holder:SetQuantitySeries({})
	holder:Refresh()
	return holder
end
