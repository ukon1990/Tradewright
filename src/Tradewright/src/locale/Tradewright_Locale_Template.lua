-- Template for a translation. Not loaded by the game: copy it to Tradewright_Locale_<language>.lua
-- (deDE, frFR, esES, ...), fill it in, and list the new file in the four Tradewright*.toc files
-- right after src\core\Tradewright_Locale.lua.
--
-- `python3 scripts/locale-keys.py` prints every text that can be translated. Keep "%s" and "%d"
-- in a translation: they stand for a name or a number. A text left out stays English.

local _, Tradewright = ...

Tradewright:AddLocale("deDE", {
	-- ["Sales a day"] = "Verkäufe pro Tag",
})

Tradewright:AddHelpLocale("deDE", {
	-- start = { title = "Erste Schritte", body = [=[...]=] },
})
