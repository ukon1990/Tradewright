-- Run with: lua5.1 tests/test_theme_apply.lua (from Tradewright root)
-- Switching theme: the palette changes in place and what is already coloured follows.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

-- Timers run at once, so a redraw asked for by RecolorUI has happened when it returns.
_G.C_Timer = { After = function(_, callback) callback() end }
_G.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 } }

local settings = { appearance = {} }
local pe = { db = { settings = settings }, InitDB = function() end }
for _, path in ipairs({ "/src/util/Tradewright_ThemeLogic.lua", "/src/ui/Tradewright_Theme.lua" }) do
	local chunk, err = loadfile(root .. path)
	assert(chunk, err)
	chunk("Tradewright", pe)
end
local redraws = 0
function pe:RefreshThemedWindows()
	redraws = redraws + 1
end

-- A label stub that remembers its last colour and shadow.
local function newLabel()
	return {
		SetTextColor = function(self, r, g, b) self.r, self.g, self.b = r, g, b end,
		SetShadowColor = function(self, _, _, _, alpha) self.shadowAlpha = alpha end,
	}
end

local theme = pe:GetTheme()
local textPrimary, surface1 = theme.textPrimary, theme.surface1
local label = newLabel()
pe:ColorText(label, "textPrimary")
check("label gets the dark theme's text colour", label.r == 0.95 and label.shadowAlpha == 1)
check("common items keep the game's white on a dark theme", pe:GetQualityColor(1) == ITEM_QUALITY_COLORS[1])

settings.appearance.theme = "parchment"
pe:ApplyThemeChange()
check("palette tables are kept, only their values change", theme.textPrimary == textPrimary and theme.surface1 == surface1)
check("window colour is the theme's", surface1.r == 0.93)
check("theme is marked light", theme.isLight == true)
check("label already built follows the theme", label.r == textPrimary.r and label.r < 0.5, label.r)
check("label drops its shadow on a light theme", label.shadowAlpha == 0)
check("open windows are redrawn", redraws == 1)
check("common items are darkened on a light theme", pe:GetQualityColor(1).r < 0.5)
check("unknown quality has no colour", pe:GetQualityColor(9) == nil)

settings.appearance.theme = "custom"
pe:ApplyThemeChange()
local custom = settings.appearance.customTheme
check("custom theme starts from the theme shown before", custom and custom.background.r == 0.93 and custom.highlight.r == 0.55)
check("custom colours are copies, not the preset's tables", custom.background ~= pe.ThemeLogic.GetSeed("parchment").background)
check("the look is unchanged until a colour is picked", surface1.r == 0.93)

pe:SetSetting("appearance.customTheme.background", { r = 0, g = 0, b = 0 })
pe:ApplyThemeChange()
check("picked background is used", surface1.r == 0 and theme.isLight == false)
check("highlight is kept when only the background changes", settings.appearance.customTheme.highlight.r == 0.55)
check("label turns light again on a dark background", label.r > 0.5 and label.shadowAlpha == 1)

if failed > 0 then
	os.exit(1)
end
