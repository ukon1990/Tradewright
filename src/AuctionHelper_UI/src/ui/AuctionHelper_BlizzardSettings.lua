local _, AuctionHelper = ...

-- The AuctionHelper page in the game's own Settings window: a button that opens the addon and the most used options.

local function addHeader(frame)
	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -18)
	title:SetText("AuctionHelper")
	local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetWidth(760)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Open the AuctionHelper window. Every option is on its Settings tab; the most used ones are also here.")
	local openButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	openButton:SetSize(180, 24)
	openButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
	openButton:SetText("Open AuctionHelper")
	openButton:SetScript("OnClick", function()
		AuctionHelper:OpenSettingsTab()
	end)
	return openButton
end

-- A Settings-style check button below `anchor` bound to a boolean setting; `onChange(value)` runs after saving.
local function addSettingCheckbox(anchor, offsetY, spec)
	local check = CreateFrame("CheckButton", nil, anchor:GetParent(), "SettingsCheckBoxTemplate")
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
	local labelRegion = check.Text or check.text
	if not labelRegion then
		labelRegion = check:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		labelRegion:SetPoint("LEFT", check, "RIGHT", 4, 0)
		check.Text = labelRegion
	end
	labelRegion:SetText(spec.label)
	check:SetChecked(AuctionHelper:GetSetting(spec.setting, spec.default))
	check:SetScript("OnClick", function(self)
		local value = self:GetChecked() == true
		AuctionHelper:SetSetting(spec.setting, value)
		if spec.onChange then
			spec.onChange(value)
		end
	end)
	return check
end

local CHECKBOXES = {
	{ label = "Show minimap button", setting = "general.showMinimapButton", default = true,
		onChange = function() AuctionHelper:EnsureMinimapButton() end },
	{ label = "Capture specialization tree", setting = "capture.captureSpecializationTree", default = true },
	{ label = "Include detailed recipe output data", setting = "capture.includeRecipeOutputItemData", default = false },
}

local function windowScaleText()
	local scale = AuctionHelper:GetSetting("appearance.windowScale", 1) or 1
	return string.format("Window scale: %d%%", math.floor(scale * 100 + 0.5))
end

-- The next window scale option after the current one, wrapping round.
local function nextWindowScale()
	local options = AuctionHelper:GetWindowScaleOptions()
	local current = tonumber(AuctionHelper:GetSetting("appearance.windowScale", 1)) or 1
	for index, option in ipairs(options) do
		if math.abs(option.value - current) < 0.001 then
			return options[(index % #options) + 1].value
		end
	end
	return options[1].value
end

local function addScaleButton(anchor)
	local scaleButton = CreateFrame("Button", nil, anchor:GetParent(), "UIPanelButtonTemplate")
	scaleButton:SetSize(180, 24)
	scaleButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -12)
	scaleButton:SetText(windowScaleText())
	scaleButton:SetScript("OnClick", function()
		AuctionHelper:SetSetting("appearance.windowScale", nextWindowScale())
		AuctionHelper:ApplyWindowScale()
		scaleButton:SetText(windowScaleText())
	end)
end

function AuctionHelper:OpenBlizzardSettings()
	if not self.settingsCategoryId then
		self:RegisterBlizzardSettings()
	end
	if not self.settingsCategoryId then
		return
	end
	if Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.settingsCategoryId)
		Settings.OpenToCategory(self.settingsCategoryId)
	end
end

function AuctionHelper:RegisterBlizzardSettings()
	if self.settingsCategoryId or not Settings or not Settings.RegisterCanvasLayoutCategory then
		return
	end
	local frame = CreateFrame("Frame", nil, nil, "VerticalLayoutFrame")
	frame.name = "AuctionHelper"
	frame.spacing = 8
	frame:SetSize(820, 520)
	local anchor = addHeader(frame)
	for index, spec in ipairs(CHECKBOXES) do
		anchor = addSettingCheckbox(anchor, index == 1 and -14 or -8, spec)
	end
	addScaleButton(anchor)
	local category = Settings.RegisterCanvasLayoutCategory(frame, "AuctionHelper")
	self.settingsCategoryId = category:GetID()
	Settings.RegisterAddOnCategory(category)
end
