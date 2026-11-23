local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })

--- Pure colour maths for themes: builds a whole palette from two picked colours and keeps every
--- text colour readable on it. No WoW API. Colours are { r, g, b [, a] } with channels 0..1.
local ThemeLogic = {}
Tradewright.ThemeLogic = ThemeLogic

local WHITE = { r = 1, g = 1, b = 1 }
local BLACK = { r = 0, g = 0, b = 0 }

-- WCAG contrast ratios: 4.5 for body text, 3 for large or decorative marks.
local TEXT_CONTRAST = 4.5
local MARK_CONTRAST = 3
-- A background brighter than this reads better with black text than with white (where the two ratios cross).
local LIGHT_LUMINANCE = 0.179
-- Raised surfaces step toward the text colour only while the text keeps this much contrast on them;
-- on a mid-tone background they step away from it instead, so text stays readable.
local SURFACE_STEP_CONTRAST = 7
local CORRECTION_STEPS = 20

-- How far each token sits from the background (0) toward the text pole (1).
local SURFACE2_STEP, SURFACE3_STEP = 0.03, 0.065
local BORDER_SUBTLE_STEP, BORDER_STRONG_STEP, BORDER_CONTROL_STEP = 0.11, 0.20, 0.39
local TEXT_PRIMARY_STEP, TEXT_MUTED_STEP, TEXT_DISABLED_STEP = 0.93, 0.60, 0.45
local TICK_TONE_DOWN = 0.25
local WINDOW_ALPHA = 0.92
local HOVER_ALPHA_DARK, HOVER_ALPHA_LIGHT = 0.04, 0.06

-- Status colours keep their hue in every theme; only their lightness is corrected.
local STATUS_HUES = {
	success = { r = 0.40, g = 0.73, b = 0.42 },
	warning = { r = 0.95, g = 0.65, b = 0.30 },
	danger = { r = 0.89, g = 0.39, b = 0.38 },
}
local INFO_HUE = { r = 0.39, g = 0.71, b = 0.96 }
local INFO_ALPHA = 0.95

local function copyColor(color, alpha)
	return { r = color.r, g = color.g, b = color.b, a = alpha or color.a }
end

local function mix(from, to, amount)
	return {
		r = from.r + (to.r - from.r) * amount,
		g = from.g + (to.g - from.g) * amount,
		b = from.b + (to.b - from.b) * amount,
	}
end

local function linearChannel(value)
	if value <= 0.03928 then
		return value / 12.92
	end
	return ((value + 0.055) / 1.055) ^ 2.4
end

--- WCAG relative luminance, 0 (black) to 1 (white). Alpha is ignored.
function ThemeLogic.Luminance(color)
	return 0.2126 * linearChannel(color.r) + 0.7152 * linearChannel(color.g) + 0.0722 * linearChannel(color.b)
end

--- WCAG contrast ratio between two colours, 1 (same) to 21 (black on white).
function ThemeLogic.ContrastRatio(first, second)
	local lighter, darker = ThemeLogic.Luminance(first), ThemeLogic.Luminance(second)
	if lighter < darker then
		lighter, darker = darker, lighter
	end
	return (lighter + 0.05) / (darker + 0.05)
end

local function isLightBackground(background)
	return ThemeLogic.Luminance(background) > LIGHT_LUMINANCE
end

local function readableOnAll(color, backgrounds, minRatio)
	for _, background in ipairs(backgrounds) do
		if ThemeLogic.ContrastRatio(color, background) < minRatio then
			return false
		end
	end
	return true
end

-- Moves `color` toward `pole` in small steps until it has `minRatio` on every background.
local function correctToward(color, pole, backgrounds, minRatio)
	for step = 0, CORRECTION_STEPS do
		local candidate = mix(color, pole, step / CORRECTION_STEPS)
		if readableOnAll(candidate, backgrounds, minRatio) then
			return candidate
		end
	end
	return copyColor(pole)
end

--- `color` made readable on `background`: unchanged when it already has `minRatio` contrast, otherwise
--- shifted toward white or black (whichever suits the background) just far enough.
function ThemeLogic.ReadableOn(color, background, minRatio)
	local pole = isLightBackground(background) and BLACK or WHITE
	local readable = correctToward(color, pole, { background }, minRatio or TEXT_CONTRAST)
	readable.a = color.a
	return readable
end

local function buildSurfaces(background, pole, antiPole)
	local raisedToward = mix(background, pole, SURFACE3_STEP)
	local stepTarget = ThemeLogic.ContrastRatio(pole, raisedToward) >= SURFACE_STEP_CONTRAST and pole or antiPole
	return {
		copyColor(background, WINDOW_ALPHA),
		copyColor(mix(background, stepTarget, SURFACE2_STEP), 1),
		copyColor(mix(background, stepTarget, SURFACE3_STEP), 1),
	}
end

--- Full palette for a seed `{ background, highlight }`. Every text token has at least 4.5:1 contrast on
--- all three surfaces, whatever the seed.
function ThemeLogic.BuildPalette(seed)
	local background = seed.background
	local isLight = isLightBackground(background)
	local pole, antiPole = isLight and BLACK or WHITE, isLight and WHITE or BLACK
	local surfaces = buildSurfaces(background, pole, antiPole)
	local function fromBackground(step, alpha)
		return copyColor(mix(background, pole, step), alpha)
	end
	local function text(color, minRatio)
		return correctToward(color, pole, surfaces, minRatio or TEXT_CONTRAST)
	end

	local gold = text(seed.highlight)
	local tick = text(mix(gold, background, TICK_TONE_DOWN), MARK_CONTRAST)
	local palette = {
		isLight = isLight,
		surface1 = surfaces[1],
		surface2 = surfaces[2],
		surface3 = surfaces[3],
		borderSubtle = fromBackground(BORDER_SUBTLE_STEP, 1),
		borderStrong = fromBackground(BORDER_STRONG_STEP, 1),
		borderControl = fromBackground(BORDER_CONTROL_STEP, 1),
		gold = gold,
		tick = tick,
		textPrimary = text(fromBackground(TEXT_PRIMARY_STEP)),
		textMuted = text(fromBackground(TEXT_MUTED_STEP)),
		textDisabled = text(fromBackground(TEXT_DISABLED_STEP), MARK_CONTRAST),
		textOnAccent = ThemeLogic.ReadableOn(background, tick, TEXT_CONTRAST),
		accent = copyColor(text(INFO_HUE, MARK_CONTRAST), INFO_ALPHA),
		hover = copyColor(pole, isLight and HOVER_ALPHA_LIGHT or HOVER_ALPHA_DARK),
	}
	for token, hue in pairs(STATUS_HUES) do
		palette[token] = text(hue)
	end
	return palette
end

-- The look Tradewright shipped with, shared with QuestPlanner (UI/PlanCard.lua): flat near-black panels,
-- 1px outlines, gold corner ticks. Hand-tuned, so these values replace the derived ones for this preset.
local DARK_TOKENS = {
	surface1 = { r = 0.043, g = 0.051, b = 0.071, a = WINDOW_ALPHA }, -- window
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
	textOnAccent = { r = 0.043, g = 0.051, b = 0.071 }, -- label on a gold-filled button
	success = STATUS_HUES.success,
	warning = STATUS_HUES.warning,
	danger = STATUS_HUES.danger,
	accent = { r = INFO_HUE.r, g = INFO_HUE.g, b = INFO_HUE.b, a = INFO_ALPHA }, -- neutral status and graph line
}

ThemeLogic.DEFAULT_THEME = "dark"
ThemeLogic.CUSTOM_THEME = "custom"

local GOLD = { r = 1, g = 0.82, b = 0 }

--- The ready-made themes, in the order the settings list shows them.
ThemeLogic.PRESETS = {
	{ id = "dark", name = L["Dark"], seed = { background = DARK_TOKENS.surface1, highlight = GOLD }, tokens = DARK_TOKENS },
	{ id = "grey", name = L["Grey"], seed = { background = { r = 0.12, g = 0.12, b = 0.13 }, highlight = GOLD } },
	{ id = "blue", name = L["Blue"], seed = { background = { r = 0.04, g = 0.08, b = 0.17 }, highlight = GOLD } },
	{ id = "red", name = L["Red"], seed = { background = { r = 0.15, g = 0.04, b = 0.05 }, highlight = GOLD } },
	{
		id = "parchment",
		name = L["Parchment"],
		seed = { background = { r = 0.93, g = 0.88, b = 0.76 }, highlight = { r = 0.55, g = 0.33, b = 0.08 } },
	},
	{
		id = "light",
		name = L["Light"],
		seed = { background = { r = 0.90, g = 0.91, b = 0.92 }, highlight = { r = 0.10, g = 0.36, b = 0.70 } },
	},
}

--- What a theme dropdown offers: every ready-made theme, then the player's own, as `{ value, label }`.
function ThemeLogic.Choices()
	local choices = {}
	for _, preset in ipairs(ThemeLogic.PRESETS) do
		choices[#choices + 1] = { value = preset.id, label = preset.name }
	end
	choices[#choices + 1] = { value = ThemeLogic.CUSTOM_THEME, label = L["Custom"] }
	return choices
end

local function findPreset(themeId)
	for _, preset in ipairs(ThemeLogic.PRESETS) do
		if preset.id == themeId then
			return preset
		end
	end
	return ThemeLogic.PRESETS[1]
end

local function isColor(value)
	return type(value) == "table" and tonumber(value.r) and tonumber(value.g) and tonumber(value.b) and true or false
end

--- True when `seed` holds the two colours a custom theme is built from.
function ThemeLogic.IsSeed(seed)
	return type(seed) == "table" and isColor(seed.background) and isColor(seed.highlight)
end

--- The two colours a theme is built from: the player's own for the custom theme (once picked),
--- otherwise the preset's. An unknown id gives the default theme's.
function ThemeLogic.GetSeed(themeId, customSeed)
	if themeId == ThemeLogic.CUSTOM_THEME and ThemeLogic.IsSeed(customSeed) then
		return customSeed
	end
	return findPreset(themeId).seed
end

--- Palette for a saved theme choice. A new table on every call; the caller may keep or change it.
function ThemeLogic.ResolvePalette(themeId, customSeed)
	local palette = ThemeLogic.BuildPalette(ThemeLogic.GetSeed(themeId, customSeed))
	local preset = themeId ~= ThemeLogic.CUSTOM_THEME and findPreset(themeId) or nil
	for token, color in pairs(preset and preset.tokens or {}) do
		palette[token] = copyColor(color)
	end
	return palette
end
