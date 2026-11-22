local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Filter selections and the flat dropdowns that edit them: multi-select, single-select and menu dropdowns.

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

function Tradewright:IsFilterSelectionEmpty(selection)
	return type(selection) ~= "table" or next(selection) == nil
end

function Tradewright:CountFilterSelection(selection)
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

function Tradewright:GetFilterSelectionSummary(options, selection, allLabel)
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
	return string.format(L["%d selected"], #selectedLabels)
end

function Tradewright:NormalizeFilterSelection(selection, options)
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

local function addDropdownLabel(holder, label)
	local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetPoint("TOPRIGHT", 0, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	local muted = Tradewright:GetTheme().textMuted
	title:SetTextColor(muted.r, muted.g, muted.b)
	title:SetText(label)
	holder.title = title
end

local function createDropdownButton(holder)
	local theme = Tradewright:GetTheme()
	local button = CreateFrame("Button", nil, holder)
	button:SetPoint("BOTTOMLEFT", 0, 0)
	button:SetPoint("BOTTOMRIGHT", 0, 0)
	button:SetHeight(DROPDOWN_HEIGHT)
	Tradewright:AddSurface(button, theme.surface2, theme.borderControl)
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
	return button
end

local function bindDropdownTooltip(button, tooltip)
	button:SetScript("OnEnter", function()
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
		GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

-- A flat 26px dropdown button with an optional label above it. The Blizzard menu frame is only used to
-- show the option list, anchored under the button. Holder height: 26, or 44 with a label.
local function createDropdownShell(parent, config)
	local holder = CreateFrame("Frame", nil, parent)
	local hasLabel = config.label ~= false and config.label ~= nil
	holder.width = config.width or 210
	holder:SetSize(holder.width, DROPDOWN_HEIGHT + (hasLabel and DROPDOWN_LABEL_GAP or 0))
	if hasLabel then
		addDropdownLabel(holder, config.label)
	end
	local button = createDropdownButton(holder)
	local menu = CreateFrame("Frame", nil, holder, "UIDropDownMenuTemplate")
	menu:Hide()
	holder.dropdown = menu
	button:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, menu, button, 0, 0)
	end)
	function holder:SetDisplayText(label)
		self.text:SetText(label or "")
	end
	function holder:SetOptions(options)
		self.currentOptions = options or {}
		self:RefreshText()
	end
	if config.tooltip then
		bindDropdownTooltip(button, config.tooltip)
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

local function currentSelection(holder)
	return type(holder.getSelection) == "function" and holder.getSelection() or {}
end

local function applySelection(holder, selection)
	selection = copySelection(selection)
	if type(holder.setSelection) == "function" then
		holder.setSelection(selection)
	end
	holder:RefreshText()
	if type(holder.onChanged) == "function" then
		holder.onChanged(selection)
	end
end

local function addCheckButton(level, text, checked, onClick)
	local info = UIDropDownMenu_CreateInfo()
	info.text = text
	info.isNotRadio = true
	info.keepShownOnClick = true
	info.checked = checked
	info.func = onClick
	UIDropDownMenu_AddButton(info, level)
end

-- "All" (clears the selection) followed by one check button per option.
local function initializeMultiSelectMenu(holder, level)
	if level ~= 1 then
		return
	end
	addCheckButton(level, holder.allLabel, function()
		return Tradewright:IsFilterSelectionEmpty(currentSelection(holder))
	end, function()
		applySelection(holder, {})
	end)
	for _, option in ipairs(resolveOptions(holder)) do
		if option.value ~= "all" then
			addCheckButton(level, option.label, function()
				return currentSelection(holder)[option.value] == true
			end, function()
				local nextSelection = copySelection(currentSelection(holder))
				nextSelection[option.value] = not nextSelection[option.value] or nil
				applySelection(holder, nextSelection)
			end)
		end
	end
end

--- `config`: label, width, tooltip, allLabel, options or getOptions, getSelection, setSelection, onChanged(selection).
function Tradewright:CreateMultiSelectDropdown(parent, config)
	config = config or {}
	local holder, menu = createDropdownShell(parent, config)
	holder.allLabel = config.allLabel or "All"
	holder.options = config.options or {}
	holder.getOptions = config.getOptions
	holder.getSelection = config.getSelection
	holder.setSelection = config.setSelection
	holder.onChanged = config.onChanged
	function holder:RefreshText()
		self:SetDisplayText(Tradewright:GetFilterSelectionSummary(resolveOptions(self), currentSelection(self), self.allLabel))
	end
	UIDropDownMenu_Initialize(menu, function(_, level)
		initializeMultiSelectMenu(holder, level)
	end, "MENU")
	holder:RefreshText()
	return holder
end

local function currentValue(holder)
	return type(holder.getValue) == "function" and holder.getValue() or nil
end

local function chooseValue(holder, value)
	if type(holder.setValue) == "function" then
		holder.setValue(value)
	end
	holder:RefreshText()
	if type(holder.onChanged) == "function" then
		holder.onChanged(value)
	end
end

local function initializeSingleSelectMenu(holder, level)
	if level ~= 1 then
		return
	end
	local current = currentValue(holder)
	for _, option in ipairs(resolveOptions(holder)) do
		local info = UIDropDownMenu_CreateInfo()
		info.text = option.label
		info.checked = current == option.value
		info.func = function()
			chooseValue(holder, option.value)
		end
		UIDropDownMenu_AddButton(info, level)
	end
end

--- `config`: label, width, tooltip, placeholder, options or getOptions, getValue, setValue, onChanged(value).
function Tradewright:CreateSingleSelectDropdown(parent, config)
	config = config or {}
	local holder, menu = createDropdownShell(parent, config)
	holder.options = config.options or {}
	holder.getOptions = config.getOptions
	holder.getValue = config.getValue
	holder.setValue = config.setValue
	holder.onChanged = config.onChanged
	function holder:RefreshText()
		local current = currentValue(self)
		local label = config.placeholder or "Select"
		for _, option in ipairs(resolveOptions(self)) do
			if option.value == current then
				label = option.label
				break
			end
		end
		self:SetDisplayText(label)
	end
	UIDropDownMenu_Initialize(menu, function(_, level)
		initializeSingleSelectMenu(holder, level)
	end, "MENU")
	holder:RefreshText()
	return holder
end

function Tradewright:CreateMenuDropdown(parent, config)
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
