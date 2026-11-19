local addonName, ProfessionExporter = ...

ProfessionExporter.ui = ProfessionExporter.ui or {}

local function copyColor(color, fallback)
	color = color or fallback or {}
	return {
		r = color.r or 0,
		g = color.g or 0,
		b = color.b or 0,
		a = color.a,
	}
end

function ProfessionExporter:GetSetting(path, defaultValue)
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

function ProfessionExporter:SetSetting(path, value)
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

function ProfessionExporter:GetThemePresetOptions()
	return {
		{ value = "slate", label = "Slate" },
		{ value = "ember", label = "Ember" },
		{ value = "storm", label = "Storm" },
	}
end

function ProfessionExporter:GetWindowScaleOptions()
	return {
		{ value = 0.9, label = "90%" },
		{ value = 1.0, label = "100%" },
		{ value = 1.1, label = "110%" },
		{ value = 1.2, label = "120%" },
	}
end

function ProfessionExporter:GetTheme()
	self:InitDB()
	local presetId = self:GetSetting("appearance.themePreset", "slate")
	local accent = copyColor(self:GetSetting("appearance.accentColor"), { r = 0.24, g = 0.66, b = 0.74 })
	local surfaceTint = copyColor(self:GetSetting("appearance.surfaceTint"), { r = 0.10, g = 0.12, b = 0.16 })

	local presets = {
		slate = {
			surface1 = { r = 0.07, g = 0.09, b = 0.12, a = 0.98 },
			surface2 = { r = 0.10, g = 0.12, b = 0.16, a = 0.98 },
			surface3 = { r = 0.13, g = 0.16, b = 0.21, a = 0.98 },
			borderStrong = { r = 0.24, g = 0.30, b = 0.38, a = 1 },
			borderSubtle = { r = 0.16, g = 0.20, b = 0.26, a = 1 },
			textPrimary = { r = 0.95, g = 0.97, b = 0.99 },
			textMuted = { r = 0.67, g = 0.73, b = 0.80 },
			success = { r = 0.35, g = 0.80, b = 0.56 },
			warning = { r = 0.95, g = 0.76, b = 0.32 },
			danger = { r = 0.89, g = 0.39, b = 0.38 },
		},
		ember = {
			surface1 = { r = 0.10, g = 0.08, b = 0.08, a = 0.98 },
			surface2 = { r = 0.14, g = 0.10, b = 0.10, a = 0.98 },
			surface3 = { r = 0.19, g = 0.13, b = 0.12, a = 0.98 },
			borderStrong = { r = 0.40, g = 0.28, b = 0.20, a = 1 },
			borderSubtle = { r = 0.28, g = 0.19, b = 0.16, a = 1 },
			textPrimary = { r = 0.99, g = 0.96, b = 0.92 },
			textMuted = { r = 0.83, g = 0.72, b = 0.64 },
			success = { r = 0.42, g = 0.78, b = 0.56 },
			warning = { r = 0.98, g = 0.80, b = 0.35 },
			danger = { r = 0.89, g = 0.41, b = 0.31 },
		},
		storm = {
			surface1 = { r = 0.06, g = 0.08, b = 0.11, a = 0.98 },
			surface2 = { r = 0.09, g = 0.12, b = 0.17, a = 0.98 },
			surface3 = { r = 0.12, g = 0.16, b = 0.22, a = 0.98 },
			borderStrong = { r = 0.20, g = 0.30, b = 0.42, a = 1 },
			borderSubtle = { r = 0.15, g = 0.21, b = 0.29, a = 1 },
			textPrimary = { r = 0.95, g = 0.98, b = 1.00 },
			textMuted = { r = 0.67, g = 0.77, b = 0.84 },
			success = { r = 0.35, g = 0.80, b = 0.64 },
			warning = { r = 0.93, g = 0.76, b = 0.34 },
			danger = { r = 0.90, g = 0.45, b = 0.42 },
		},
	}

	local base = presets[presetId] or presets.slate
	return {
		id = presetId,
		accent = accent,
		success = base.success,
		warning = base.warning,
		danger = base.danger,
		textPrimary = base.textPrimary,
		textMuted = base.textMuted,
		surface1 = base.surface1,
		surface2 = surfaceTint.a and surfaceTint or {
			r = surfaceTint.r or base.surface2.r,
			g = surfaceTint.g or base.surface2.g,
			b = surfaceTint.b or base.surface2.b,
			a = base.surface2.a,
		},
		surface3 = base.surface3,
		borderStrong = base.borderStrong,
		borderSubtle = base.borderSubtle,
		spacing = {
			xs = 4,
			sm = 8,
			md = 12,
			lg = 16,
			xl = 24,
		},
	}
end

function ProfessionExporter:ApplyBackdrop(frame, bg, border, inset)
	if not frame then
		return
	end
	frame:SetBackdrop({
		bgFile = "Interface/ChatFrame/ChatFrameBackground",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 12,
		insets = inset or { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(bg.r or 0, bg.g or 0, bg.b or 0, bg.a or 1)
	frame:SetBackdropBorderColor(border.r or 0, border.g or 0, border.b or 0, border.a or 1)
end

function ProfessionExporter:StylePanel(frame, tone)
	local theme = self:GetTheme()
	self:ApplyBackdrop(frame, theme[tone or "surface2"], theme.borderSubtle)
end

function ProfessionExporter:StyleShellButton(button, selected)
	local theme = self:GetTheme()
	if not button then
		return
	end
	local font = button.GetFontString and button:GetFontString()
	if font then
		if selected then
			font:SetTextColor(theme.textPrimary.r, theme.textPrimary.g, theme.textPrimary.b)
		else
			font:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
		end
	end
	button:SetNormalFontObject(selected and "GameFontNormal" or "GameFontHighlightSmall")
	button:SetAlpha(selected and 1 or 0.95)
end

function ProfessionExporter:ApplyWindowScale()
	local ui = self.ui
	if ui and ui.mainFrame then
		ui.mainFrame:SetScale(self:GetSetting("appearance.windowScale", 1))
	end
end
