-- Run with: lua5.1 tests/test_locale.lua (from Tradewright root)
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

local function load(file, pe)
	local chunk, err = loadfile(root .. "/src/" .. file)
	assert(chunk, err)
	chunk("Tradewright", pe)
	return pe
end

-- A German client.
_G.GetLocale = function() return "deDE" end
local pe = load("util/Tradewright_CoreHelpers.lua", load("core/Tradewright_Locale.lua", {}))
local L = pe.L
check("Untranslated text comes back unchanged", L["Sales a day"] == "Sales a day")
pe:AddLocale("frFR", { ["Sales a day"] = "Ventes par jour" })
check("Another language is ignored", L["Sales a day"] == "Sales a day")
pe:AddLocale("deDE", { ["Sales a day"] = "Verkäufe pro Tag", ["Cart"] = "", ["mail"] = "Brief", ["mails"] = "Briefe" })
check("The client's language is used", L["Sales a day"] == "Verkäufe pro Tag")
check("An empty translation stays English", L["Cart"] == "Cart")
check("Plural words are translated", pe:Plural(1, "mail") == "Brief" and pe:Plural(2, "mail") == "Briefe")
check("Plural without a translation", pe:Plural(2, "farm") == "farms" and pe:Plural(2, "item has", "items have") == "items have")

local topic = { id = "start", title = "Getting started", body = "English" }
check("Help topic without a translation", pe:LocalizeHelpTopic(topic) == topic)
pe:AddHelpLocale("deDE", { start = { title = "Erste Schritte" } })
local translated = pe:LocalizeHelpTopic(topic)
check("Help topic: translated title, English body kept", translated.title == "Erste Schritte" and translated.body == "English" and translated.id == "start")

-- A file loaded alone, as the other offline tests do, still shows English.
local alone = load("util/Tradewright_CoreHelpers.lua", {})
check("Plural works without the locale table", alone:Plural(2, "mail") == "mails")

if failed > 0 then
	print(failed .. " locale check(s) failed")
	os.exit(1)
end
print("All locale checks passed")
