local _, Tradewright = ...

-- Translation of the text the player sees.
--
-- Code writes its English text as `L["Sales a day"]`. A text without a translation comes back
-- unchanged, so English is both the key and the fallback and no English table is needed.
--
-- Every file starts with
--     local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- The second half only matters to the offline tests, which load one file at a time without this one.
--
-- Not translated: debug output, export errors and slash command syntax.

local L = setmetatable({}, { __index = function(_, text) return text end })
Tradewright.L = L

local clientLocale = GetLocale and GetLocale() or "enUS"

--- Add the translations of one language: `{ ["Sales a day"] = "Verkäufe pro Tag" }`.
--- Ignored unless `locale` ("deDE", "frFR", ...) is the client's language.
function Tradewright:AddLocale(locale, translations)
	if locale ~= clientLocale then
		return
	end
	for text, translation in pairs(translations) do
		if translation ~= "" then
			L[text] = translation
		end
	end
end

-- Help topics are too long to be keys, so a language replaces them by topic id.
local helpTopics = {}

--- Translate Help topics: `{ start = { title = "...", body = "..." } }`, keyed by the topic's `id`
--- in Tradewright_Docs.lua. Ignored unless `locale` is the client's language.
function Tradewright:AddHelpLocale(locale, topics)
	if locale ~= clientLocale then
		return
	end
	for id, topic in pairs(topics) do
		helpTopics[id] = topic
	end
end

--- A Help topic with its translated title and body, where the client's language has them.
function Tradewright:LocalizeHelpTopic(topic)
	local translated = helpTopics[topic.id]
	if not translated then
		return topic
	end
	return { id = topic.id, title = translated.title or topic.title, body = translated.body or topic.body }
end
