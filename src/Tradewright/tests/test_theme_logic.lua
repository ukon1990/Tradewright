-- Run with: lua5.1 tests/test_theme_logic.lua (from Tradewright root)
-- Theme palettes: the shipped dark look is unchanged, and every theme keeps its text readable.
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

local pe = {}
local chunk, err = loadfile(root .. "/src/util/Tradewright_ThemeLogic.lua")
assert(chunk, err)
chunk("Tradewright", pe)
local TL = pe.ThemeLogic
assert(TL, "ThemeLogic missing")

local function near(a, b)
	return type(a) == "number" and math.abs(a - b) < 1e-9
end

local function sameColor(color, r, g, b, a)
	return near(color.r, r) and near(color.g, g) and near(color.b, b) and (a == nil and color.a == nil or near(color.a, a))
end

-- Contrast maths.
local white, black = { r = 1, g = 1, b = 1 }, { r = 0, g = 0, b = 0 }
check("black on white is 21:1", near(TL.ContrastRatio(white, black), 21))
check("contrast ignores argument order", near(TL.ContrastRatio(black, white), 21))
check("same colour is 1:1", near(TL.ContrastRatio(white, white), 1))

local yellow = { r = 1, g = 0.82, b = 0 }
local onWhite = TL.ReadableOn(yellow, white, 4.5)
check("yellow is darkened on white", TL.ContrastRatio(onWhite, white) >= 4.5 and onWhite.r < 1)
local onBlack = TL.ReadableOn(yellow, black, 4.5)
check("readable colour is left alone", sameColor(onBlack, 1, 0.82, 0))

-- The dark preset is the look players already have.
local dark = TL.ResolvePalette("dark")
check("dark window fill", sameColor(dark.surface1, 0.043, 0.051, 0.071, 0.92))
check("dark raised fill", sameColor(dark.surface2, 0.067, 0.078, 0.106, 1))
check("dark track fill", sameColor(dark.surface3, 0.094, 0.110, 0.145, 1))
check("dark strong border", sameColor(dark.borderStrong, 0.23, 0.25, 0.28, 1))
check("dark control border", sameColor(dark.borderControl, 0.41, 0.44, 0.48, 1))
check("dark subtle border", sameColor(dark.borderSubtle, 0.15, 0.16, 0.19, 1))
check("dark gold", sameColor(dark.gold, 1, 0.82, 0))
check("dark tick", sameColor(dark.tick, 0.79, 0.64, 0.15))
check("dark text", sameColor(dark.textPrimary, 0.95, 0.94, 0.92))
check("dark muted text", sameColor(dark.textMuted, 0.60, 0.63, 0.67))
check("dark disabled text", sameColor(dark.textDisabled, 0.5, 0.5, 0.5))
check("dark success", sameColor(dark.success, 0.40, 0.73, 0.42))
check("dark warning", sameColor(dark.warning, 0.95, 0.65, 0.30))
check("dark danger", sameColor(dark.danger, 0.89, 0.39, 0.38))
check("dark accent", sameColor(dark.accent, 0.39, 0.71, 0.96, 0.95))
check("dark solid button label is the window colour", sameColor(dark.textOnAccent, 0.043, 0.051, 0.071))
check("dark is not light", dark.isLight == false)
check("dark hover is a white wash", sameColor(dark.hover, 1, 1, 1, 0.04))

check("unknown theme falls back to dark", sameColor(TL.ResolvePalette("nope").surface1, 0.043, 0.051, 0.071, 0.92))
check("custom without colours falls back to dark colours", near(TL.ResolvePalette("custom", {}).surface1.r, 0.043))
check("each call returns its own tables", TL.ResolvePalette("dark").gold ~= TL.ResolvePalette("dark").gold)

-- Readability: text tokens on every surface, in every preset and for hostile custom colours.
local TEXT_TOKENS = { "textPrimary", "textMuted", "gold", "success", "warning", "danger" }
local MARK_TOKENS = { "textDisabled", "tick", "accent" }
local SURFACES = { "surface1", "surface2", "surface3" }
local SLACK = 1e-6

local function lowestContrast(palette, tokens)
	local lowest, where = math.huge, nil
	for _, token in ipairs(tokens) do
		for _, surface in ipairs(SURFACES) do
			local ratio = TL.ContrastRatio(palette[token], palette[surface])
			if ratio < lowest then
				lowest, where = ratio, token .. " on " .. surface
			end
		end
	end
	return lowest, where
end

local function checkReadable(label, palette)
	local textRatio, textWhere = lowestContrast(palette, TEXT_TOKENS)
	check(label .. ": text is readable", textRatio >= 4.5 - SLACK, string.format("%s is %.2f", textWhere, textRatio))
	local markRatio, markWhere = lowestContrast(palette, MARK_TOKENS)
	check(label .. ": marks are visible", markRatio >= 3 - SLACK, string.format("%s is %.2f", markWhere, markRatio))
	local solidRatio = TL.ContrastRatio(palette.textOnAccent, palette.tick)
	check(label .. ": solid button label is readable", solidRatio >= 4.5 - SLACK, string.format("%.2f", solidRatio))
end

for _, preset in ipairs(TL.PRESETS) do
	checkReadable("preset " .. preset.id, TL.ResolvePalette(preset.id))
end
check("parchment is light", TL.ResolvePalette("parchment").isLight == true)
check("light hover is a black wash", sameColor(TL.ResolvePalette("parchment").hover, 0, 0, 0, 0.06))

local function grey(level)
	return { r = level, g = level, b = level }
end
local HOSTILE_SEEDS = {
	["white on white"] = { background = white, highlight = white },
	["black on black"] = { background = black, highlight = black },
	["highlight equals background"] = { background = grey(0.3), highlight = grey(0.3) },
	["pure red on pure blue"] = { background = { r = 0, g = 0, b = 1 }, highlight = { r = 1, g = 0, b = 0 } },
	["yellow on white"] = { background = white, highlight = yellow },
}
for label, seed in pairs(HOSTILE_SEEDS) do
	checkReadable("custom " .. label, TL.ResolvePalette("custom", seed))
end
-- Mid greys are the hardest backgrounds: neither black nor white text has much room.
for level = 0.30, 0.60, 0.02 do
	local seed = { background = grey(level), highlight = grey(level) }
	checkReadable(string.format("custom grey %.2f", level), TL.ResolvePalette("custom", seed))
end

check("custom seed is used once it has both colours", TL.GetSeed("custom", HOSTILE_SEEDS["yellow on white"]).highlight == yellow)
check("custom seed falls back while a colour is missing", TL.GetSeed("custom", { background = white }) == TL.PRESETS[1].seed)
check("preset seed ignores custom colours", TL.GetSeed("blue", HOSTILE_SEEDS["yellow on white"]).background.b == 0.17)

if failed > 0 then
	os.exit(1)
end
