local _, Tradewright = ...

Tradewright.ui = Tradewright.ui or {}

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- One look for every Tradewright frame, shared with QuestPlanner (UI/PlanCard.lua):
-- flat near-black panels, 1px outlines, gold corner ticks. Read-only: callers must not mutate it.
local THEME = {
	surface1 = { r = 0.043, g = 0.051, b = 0.071, a = 0.92 }, -- window
	surface2 = { r = 0.067, g = 0.078, b = 0.106, a = 1 }, -- raised: table header, fields, tiles
	surface3 = { r = 0.094, g = 0.110, b = 0.145, a = 1 }, -- icon placeholder, progress track
	borderStrong = { r = 0.23, g = 0.25, b = 0.28, a = 1 }, -- window and button outline
	borderControl = { r = 0.41, g = 0.44, b = 0.48, a = 1 }, -- edit box, dropdown, checkbox outline
	borderSubtle = { r = 0.15, g = 0.16, b = 0.19, a = 1 }, -- dividers, table and tile outline
	gold = { r = 1, g = 0.82, b = 0 }, -- title, selected tab, sorted column, primary action
	tick = { r = 0.79, g = 0.64, b = 0.15 }, -- corner ticks, primary outline, progress fill
	textPrimary = { r = 0.95, g = 0.94, b = 0.92 },
	textMuted = { r = 0.60, g = 0.63, b = 0.67 },
	textDisabled = { r = 0.5, g = 0.5, b = 0.5 },
	success = { r = 0.40, g = 0.73, b = 0.42 },
	warning = { r = 0.95, g = 0.65, b = 0.30 },
	danger = { r = 0.89, g = 0.39, b = 0.38 },
	accent = { r = 0.39, g = 0.71, b = 0.96, a = 0.95 }, -- neutral status and graph line
	spacing = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 },
	size = {
		header = 34,
		tabs = 30,
		control = 26,
		controlSmall = 22,
		tableHead = 22,
		row = 24,
		rowTall = 36,
		footer = 24,
		icon = 18,
		scrollGutter = 14,
	},
}

function Tradewright:GetSetting(path, defaultValue)
	self:InitDB()
	local node = self.db and self.db.settings
	for segment in string.gmatch(path or "", "[^%.]+") do
		if type(node) ~= "table" then
			return defaultValue
		end
		node = node[segment]
	end
	if node == nil then
		return defaultValue
	end
	return node
end

function Tradewright:SetSetting(path, value)
	self:InitDB()
	local node = self.db.settings

	local segments = {}
	for segment in string.gmatch(path or "", "[^%.]+") do
		table.insert(segments, segment)
	end
	if #segments == 0 then
		return
	end
	for index = 1, #segments - 1 do
		local segment = segments[index]
		node[segment] = node[segment] or {}
		node = node[segment]
	end
	node[segments[#segments]] = value
	if self.SyncLegacySettingAlias then
		self:SyncLegacySettingAlias(path, value)
	end
	self:InitDB()
end

function Tradewright:GetWindowScaleOptions()
	return {
		{ value = 0.9, label = "90%" },
		{ value = 1.0, label = "100%" },
		{ value = 1.1, label = "110%" },
		{ value = 1.2, label = "120%" },
	}
end

function Tradewright:GetTheme()
	return THEME
end

function Tradewright:ApplyBackdrop(frame, bg, border)
	if not frame then
		return
	end
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
	frame:SetBackdropBorderColor(border.r, border.g, border.b, border.a or 1)
end

-- A raised region inside a window (never a second window outline).
function Tradewright:StylePanel(frame, tone)
	self:ApplyBackdrop(frame, THEME[tone or "surface2"], THEME.borderSubtle)
end

local function addCornerTicks(frame)
	if frame.ahCornerTicks then
		return
	end
	frame.ahCornerTicks = true
	local tick = THEME.tick
	for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
		for _, size in ipairs({ { 10, 2 }, { 2, 10 } }) do
			local texture = frame:CreateTexture(nil, "OVERLAY")
			texture:SetColorTexture(tick.r, tick.g, tick.b, 1)
			texture:SetSize(size[1], size[2])
			texture:SetPoint(corner)
		end
	end
end

-- The outer frame of a window or docked panel: window fill, 1px outline, gold corner ticks, clipped.
function Tradewright:StyleWindow(frame)
	if not frame then
		return
	end
	self:ApplyBackdrop(frame, THEME.surface1, THEME.borderStrong)
	addCornerTicks(frame)
	if frame.SetClipsChildren then
		frame:SetClipsChildren(true)
	end
end

-- Skinning: flat 1px controls drawn over Blizzard templates. Template art is hidden with alpha 0
-- (template scripts swap textures on press, but never restore alpha).

local function colorTexture(texture, color, alpha)
	texture:SetColorTexture(color.r, color.g, color.b, alpha or color.a or 1)
end

local function hideRegions(frame, keys)
	for _, key in ipairs(keys) do
		local region = frame[key]
		if region and region.SetAlpha then
			region:SetAlpha(0)
		end
	end
end

-- Fill plus four 1px edges, inset by `pad` (x, y) around the frame. Returns the surface table.
function Tradewright:AddSurface(frame, fill, edge, padX, padY)
	if frame.ahSurface then
		return frame.ahSurface
	end
	padX, padY = padX or 0, padY or 0
	local surface = { edges = {} }
	surface.fill = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	surface.fill:SetPoint("TOPLEFT", -padX, padY)
	surface.fill:SetPoint("BOTTOMRIGHT", padX, -padY)
	colorTexture(surface.fill, fill)
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = frame:CreateTexture(nil, "BORDER", nil, -7)
		if side == "TOP" or side == "BOTTOM" then
			local y = side == "TOP" and padY or -padY
			line:SetPoint(side .. "LEFT", frame, side .. "LEFT", -padX, y)
			line:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", padX, y)
			line:SetHeight(1)
		else
			local x = side == "LEFT" and -padX or padX
			line:SetPoint("TOP" .. side, frame, "TOP" .. side, x, padY)
			line:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, x, -padY)
			line:SetWidth(1)
		end
		colorTexture(line, edge)
		surface.edges[#surface.edges + 1] = line
	end
	function surface:SetColors(newFill, newEdge)
		if newFill then
			colorTexture(self.fill, newFill)
		end
		for _, line in ipairs(self.edges) do
			colorTexture(line, newEdge or edge)
		end
	end
	frame.ahSurface = surface
	return surface
end

local function isPanelButton(frame)
	return frame.Left and frame.Middle and frame.Right and frame.GetFontString and frame:GetFontString() ~= nil
end

local CLEAR = { r = 0, g = 0, b = 0, a = 0 }

local function setFontColor(font, color)
	if font then
		font:SetTextColor(color.r, color.g, color.b)
	end
end

-- Button state -> fill, outline and label colour. Primary or selected buttons are "marked";
-- "solid" is the gold-filled button for the one thing to press now.
local BUTTON_STATE_COLORS = {
	solid = { fill = THEME.tick, border = THEME.gold, text = THEME.surface1 },
	disabled = { fill = CLEAR, border = THEME.borderStrong, text = THEME.textDisabled },
	marked = { fill = THEME.surface2, border = THEME.tick, text = THEME.gold },
	tab = { fill = CLEAR, border = THEME.borderStrong, text = THEME.textMuted },
	normal = { fill = CLEAR, border = THEME.borderStrong, text = THEME.textPrimary },
}

local function buttonState(button)
	if not button:IsEnabled() then
		return "disabled"
	end
	if button.ahSolid then
		return "solid"
	end
	if button.ahPrimary or button.ahSelected then
		return "marked"
	end
	return button.ahTab and "tab" or "normal"
end

local function applyButtonState(button)
	local surface = button.ahSurface
	if not surface then
		return
	end
	local colors = BUTTON_STATE_COLORS[buttonState(button)]
	surface:SetColors(colors.fill, colors.border)
	local label = button:GetFontString()
	setFontColor(label, colors.text)
	-- The game's fonts carry a dark drop shadow. Behind a dark label on the gold fill it only
	-- smears the letters, so a solid button drops it.
	label:SetShadowColor(0, 0, 0, colors == BUTTON_STATE_COLORS.solid and 0 or 1)
end

-- The game swaps in the highlight font on hover, which resets the label, so it is styled again:
-- gold for most buttons, while a solid one keeps its dark label (gold would vanish on the fill).
local function onButtonEnter(button)
	if button.ahSolid then
		applyButtonState(button)
	elseif button:IsEnabled() then
		setFontColor(button:GetFontString(), THEME.gold)
	end
end

-- Any Button with a font string: transparent fill, 1px outline, gold wash on hover.
function Tradewright:SkinButton(button)
	if not button or button.ahSkinned then
		return button
	end
	button.ahSkinned = true
	hideRegions(button, { "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" })
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
		local texture = button[getter] and button[getter](button)
		if texture then
			texture:SetAlpha(0)
		end
	end
	button:SetHighlightTexture(WHITE)
	local highlight = button:GetHighlightTexture()
	if highlight then
		highlight:SetVertexColor(THEME.gold.r, THEME.gold.g, THEME.gold.b, 0.09)
		highlight:SetAllPoints()
	end
	button:SetNormalFontObject("GameFontHighlightSmall")
	button:SetHighlightFontObject("GameFontHighlightSmall")
	button:SetDisabledFontObject("GameFontDisableSmall")
	self:AddSurface(button, THEME.surface2, THEME.borderStrong)
	button:HookScript("OnEnable", applyButtonState)
	button:HookScript("OnDisable", applyButtonState)
	button:HookScript("OnShow", applyButtonState)
	button:HookScript("OnEnter", onButtonEnter)
	button:HookScript("OnLeave", applyButtonState)
	applyButtonState(button)
	return button
end

-- The one main action of a region: gold label, gold outline.
function Tradewright:SetButtonPrimary(button, primary)
	self:SkinButton(button)
	button.ahPrimary = primary and true or nil
	applyButtonState(button)
end

-- The one thing to press right now: gold fill, dark label. Stronger than primary; use it sparingly.
function Tradewright:SetButtonSolid(button, solid)
	self:SkinButton(button)
	button.ahSolid = solid and true or nil
	applyButtonState(button)
end

-- Tab and segment buttons: the selected one is gold with a gold outline, the rest muted.
function Tradewright:StyleShellButton(button, selected)
	if not button then
		return
	end
	self:SkinButton(button)
	button.ahTab = true
	button.ahSelected = selected and true or nil
	applyButtonState(button)
end

function Tradewright:SkinEditBox(editBox)
	if not editBox or editBox.ahSkinned then
		return editBox
	end
	editBox.ahSkinned = true
	hideRegions(editBox, { "Left", "Middle", "Right" })
	local name = editBox.GetName and editBox:GetName()
	if name then
		for _, suffix in ipairs({ "Left", "Middle", "Right", "Mid" }) do
			local region = _G[name .. suffix]
			if region and region.SetAlpha then
				region:SetAlpha(0)
			end
		end
	end
	self:AddSurface(editBox, THEME.surface2, THEME.borderControl, 6, 2)
	editBox:SetFontObject("GameFontHighlightSmall")
	editBox:SetTextColor(THEME.textPrimary.r, THEME.textPrimary.g, THEME.textPrimary.b)
	return editBox
end

-- 14px square box with an 8px gold check; the label sits to the right, muted text colour.
function Tradewright:SkinCheckButton(check)
	if not check or check.ahSkinned then
		return check
	end
	check.ahSkinned = true
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local texture = check[getter] and check[getter](check)
		if texture then
			texture:SetAlpha(0)
		end
	end
	check:SetSize(22, 22)
	-- Box drawn on the button itself (inset 4px): a child frame would render above the check mark.
	self:AddSurface(check, THEME.surface2, THEME.borderControl, -4, -4)
	check:SetCheckedTexture(WHITE)
	local mark = check:GetCheckedTexture()
	mark:ClearAllPoints()
	mark:SetSize(8, 8)
	mark:SetPoint("CENTER")
	mark:SetVertexColor(THEME.gold.r, THEME.gold.g, THEME.gold.b, 1)
	mark:SetDrawLayer("OVERLAY")
	local disabledMark = check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture()
	if disabledMark then
		disabledMark:SetAlpha(0)
	end
	local name = check.GetName and check:GetName()
	local label = check.Text or (name and _G[name .. "Text"])
	if label then
		label:ClearAllPoints()
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
		label:SetFontObject("GameFontHighlightSmall")
		label:SetTextColor(THEME.textPrimary.r, THEME.textPrimary.g, THEME.textPrimary.b)
	end
	return check
end

local function skinScrollBar(scrollFrame)
	local name = scrollFrame.GetName and scrollFrame:GetName()
	local bar = scrollFrame.ScrollBar or (name and _G[name .. "ScrollBar"])
	if not bar or bar.ahSkinned or not bar.GetThumbTexture then
		return
	end
	bar.ahSkinned = true
	local barName = bar.GetName and bar:GetName()
	for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
		local button = bar[key] or (barName and _G[barName .. key])
		if button then
			button:SetAlpha(0)
			button:EnableMouse(false)
			button:SetSize(1, 1)
		end
	end
	for _, region in ipairs({ bar:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= bar:GetThumbTexture() then
			region:SetAlpha(0)
		end
	end
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 0)
	bar:SetWidth(6)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	colorTexture(track, THEME.surface2)
	bar:SetThumbTexture(WHITE)
	local thumb = bar:GetThumbTexture()
	thumb:SetSize(6, 32)
	thumb:SetVertexColor(THEME.borderStrong.r, THEME.borderStrong.g, THEME.borderStrong.b, 1)
end

-- Glyphs drawn on 22px icon buttons, one texture per line: { width, height, x, y, rotation }.
local GLYPHS = {
	close = { { 11, 1.5, 0, 0, math.pi / 4 }, { 11, 1.5, 0, 0, -math.pi / 4 } },
	-- A window outline with a thick title bar: "open in a window".
	window = { { 11, 2, 0, 4.5 }, { 11, 1, 0, -5 }, { 1, 10, -5, 0 }, { 1, 10, 5, 0 } },
}

-- Replaces the red close button art with a 22px outlined square holding a drawn glyph (X by default).
function Tradewright:SkinCloseButton(button, glyph)
	if not button or button.ahSkinned then
		return button
	end
	button.ahSkinned = true
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
		local texture = button[getter] and button[getter](button)
		if texture then
			texture:SetAlpha(0)
		end
	end
	button:SetSize(22, 22)
	button:SetHighlightTexture(WHITE)
	button:GetHighlightTexture():SetVertexColor(THEME.gold.r, THEME.gold.g, THEME.gold.b, 0.09)
	self:AddSurface(button, { r = 0, g = 0, b = 0, a = 0 }, THEME.borderStrong)
	for _, spec in ipairs(GLYPHS[glyph or "close"]) do
		local line = button:CreateTexture(nil, "ARTWORK")
		line:SetSize(spec[1], spec[2])
		line:SetPoint("CENTER", spec[3], spec[4])
		colorTexture(line, THEME.textMuted)
		if spec[5] and line.SetRotation then
			line:SetRotation(spec[5])
		end
	end
	return button
end

-- 22px square header button with a drawn glyph ("close" or "window"); `tooltip` is optional.
function Tradewright:CreateIconButton(parent, glyph, onClick, tooltip)
	local button = CreateFrame("Button", nil, parent, glyph == "close" and "UIPanelCloseButton" or nil)
	button:ClearAllPoints()
	self:SkinCloseButton(button, glyph)
	button:SetScript("OnClick", onClick)
	if tooltip then
		button:SetScript("OnEnter", function(owner)
			GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
			GameTooltip:SetText(tooltip, 1, 1, 1)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
	end
	return button
end

-- Walks a frame tree once per call and skins every template control it finds. Safe to repeat:
-- each control is skinned once; new children added since the last call get skinned too.
function Tradewright:SkinTree(root)
	if not root or not root.GetChildren then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if not child.ahNoSkin then
			local kind = child:GetObjectType()
			if kind == "CheckButton" then
				self:SkinCheckButton(child)
			elseif kind == "Button" and isPanelButton(child) then
				self:SkinButton(child)
			elseif kind == "EditBox" and (child.Left or child.Middle or (child:GetName() and _G[child:GetName() .. "Left"])) then
				self:SkinEditBox(child)
			elseif kind == "ScrollFrame" then
				skinScrollBar(child)
			end
			if kind ~= "Slider" then
				self:SkinTree(child)
			end
		end
	end
end

-- Retail profession quality tier as an inline icon after an item name. Forever has no quality tiers,
-- so it draws nothing there.
function Tradewright:GetRankMarkup(rankIndex)
	rankIndex = tonumber(rankIndex)
	if not self.IS_RETAIL or not rankIndex or rankIndex <= 0 then
		return ""
	end
	return string.format(" |A:Professions-Icon-Quality-Tier%d-Small:14:14|a", rankIndex)
end

function Tradewright:ApplyWindowScale()
	local ui = self.ui
	if ui and ui.mainFrame then
		ui.mainFrame:SetScale(self:GetSetting("appearance.windowScale", 1))
	end
end

-- Moves `frame` with the cursor, keeping the exact point grabbed on mouse-down under the cursor.
-- StartMoving() from OnDragStart only begins after the drag threshold (often a frame late), so the
-- grab point slipped and the window popped to a new offset; manual moves avoid that and any scale skew.
local dragDriver
function Tradewright:MakeWindowDraggable(frame, handle)
	dragDriver = dragDriver or CreateFrame("Frame")
	local function stop()
		dragDriver:SetScript("OnUpdate", nil)
	end
	handle:EnableMouse(true)
	handle:HookScript("OnMouseDown", function(_, button)
		local left, top = frame:GetLeft(), frame:GetTop()
		if button ~= "LeftButton" or not left then
			return
		end
		local scale = frame:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		local dx, dy = left - cx / scale, top - cy / scale
		dragDriver:SetScript("OnUpdate", function()
			if not IsMouseButtonDown("LeftButton") then
				return stop()
			end
			local x, y = GetCursorPosition()
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + dx, y / scale + dy)
		end)
	end)
	handle:HookScript("OnMouseUp", stop)
	handle:HookScript("OnHide", stop)
end
