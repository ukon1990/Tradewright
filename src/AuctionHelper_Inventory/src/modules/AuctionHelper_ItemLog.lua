local _, ProfessionExporter = ...

-- Item log: a short list of what entered and left the logged-in character's bags, and why, kept
-- per character in the inventory database (AuctionHelperInventoryDB.itemLog[characterKey]). It
-- only watches: each time the bags change, the saved counts before and after are compared and the
-- difference is labelled by what was open or had just happened. The bags module shows it.

local IncomeLogic = ProfessionExporter.IncomeLogic
local RECENT_SECONDS = 2
local QUIET_SECONDS = 5
local MAX_ROWS = 500

-- Windows: event -> { context key, opened }.
local WINDOWS = {
	MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
	MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
	TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
	AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
	LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot", false },
}
-- Things that happen in a moment: event -> context key.
local MOMENTS = {
	QUEST_TURNED_IN = "quest", QUEST_LOOT_RECEIVED = "quest", PLAYER_EQUIPMENT_CHANGED = "equip", LOOT_READY = "loot",
	TRADE_SKILL_ITEM_CRAFTED_RESULT = "craft",
}

-- The player's own "You create" and "You receive loot" chat lines, in the client's language.
local CHAT_LINES = {}
for _, entry in ipairs({
	{ LOOT_ITEM_CREATED_SELF_MULTIPLE, "craft" }, { LOOT_ITEM_CREATED_SELF, "craft" },
	{ LOOT_ITEM_SELF_MULTIPLE, "loot" }, { LOOT_ITEM_SELF, "loot" },
}) do
	if entry[1] and IncomeLogic then
		CHAT_LINES[#CHAT_LINES + 1] = { IncomeLogic.FormatToPattern(entry[1]), entry[2] }
	end
end

local open, stamps = {}, {} -- context key -> window is open / when it last happened (GetTime)
local previous -- the counts at the last look: { bags, warband }
local quietUntil = 0 -- bag contents arrive in pieces after a loading screen: nothing is logged then
local pending = false
local mailFrom, mailTo

local function mark(key)
	stamps[key] = GetTime()
end

local function active(key)
	return open[key] == true or (stamps[key] ~= nil and GetTime() - stamps[key] <= RECENT_SECONDS)
end

local function context(pe)
	local now = { bank = pe:IsBankOpen() }
	for _, key in ipairs({ "craft", "quest", "loot", "mail", "trade", "merchant", "auction", "destroy", "equip" }) do
		now[key] = active(key)
	end
	return now
end

--- The logged-in character's log, oldest entry first.
function ProfessionExporter:GetItemLog(characterKey)
	if not self.inventoryDb then
		self:InitDB()
	end
	local logs = self.inventoryDb.itemLog or {}
	self.inventoryDb.itemLog = logs
	characterKey = characterKey or self:GetCharacterKey()
	logs[characterKey] = logs[characterKey] or {}
	return logs[characterKey]
end

function ProfessionExporter:GetItemLogLimits()
	return { rows = MAX_ROWS, days = tonumber(self:GetSetting("bags.logDays", 14)) or 14 }
end

local WHO = { mail_in = function() return mailFrom end, mail_out = function() return mailTo end }

local function record(pe, before, now)
	local logic, log, limits, current = pe.ItemLogLogic, pe:GetItemLog(), pe:GetItemLogLimits(), context(pe)
	for _, change in ipairs(logic.Diff(before.bags, now.bags)) do
		local warbandDelta = (now.warband[change.itemID] or 0) - (before.warband[change.itemID] or 0)
		local why = logic.Reason(change.delta, current, warbandDelta)
		if why then
			logic.Add(log, { t = time(), id = change.itemID, n = change.delta, why = why, who = WHO[why] and WHO[why]() or nil }, limits)
		end
	end
end

-- Runs a frame after the bags changed, once the holdings have been saved.
local function look()
	local pe = ProfessionExporter
	pending = false
	local warband = pe:GetWarbandHoldings()
	local now = { bags = pe:GetOwnItemHoldings().bags or {}, warband = warband and warband.bank or {} }
	if previous and GetTime() >= quietUntil then
		record(pe, previous, now)
		if pe.RequestBagWindowRefresh then
			pe:RequestBagWindowRefresh()
		end
	end
	previous = now
end

local function requestLook()
	if not pending then
		pending = true
		C_Timer.After(0, look)
	end
end

local function onChatLoot(message)
	for _, line in ipairs(CHAT_LINES) do
		if string.match(message or "", line[1]) then
			mark(line[2])
			return
		end
	end
end

local function onEvent(_, event, ...)
	local window = WINDOWS[event]
	if window then
		open[window[1]] = window[2]
		mark(window[1])
	elseif MOMENTS[event] then
		mark(MOMENTS[event])
	elseif event == "CHAT_MSG_LOOT" then
		onChatLoot(...)
	elseif event == "PLAYER_ENTERING_WORLD" then
		quietUntil = GetTime() + QUIET_SECONDS
		ProfessionExporter.ItemLogLogic.Trim(ProfessionExporter:GetItemLog(), time(), ProfessionExporter:GetItemLogLimits())
		requestLook()
	else
		requestLook()
	end
end

-- Who a mail is from or to, and deleting: remembered as the game's own functions are called.
local HOOKS = {
	DeleteCursorItem = function() mark("destroy") end,
	TakeInboxItem = function(index) mailFrom = select(3, GetInboxHeaderInfo(index)) end,
	AutoLootMailItem = function(index) mailFrom = select(3, GetInboxHeaderInfo(index)) end,
	SendMail = function(recipient) mailTo = recipient end,
}
for name, hook in pairs(HOOKS) do
	if type(_G[name]) == "function" then
		hooksecurefunc(name, hook)
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", onEvent)
for _, list in ipairs({ WINDOWS, MOMENTS, { CHAT_MSG_LOOT = true, PLAYER_ENTERING_WORLD = true, BAG_UPDATE_DELAYED = true } }) do
	for event in pairs(list) do
		-- Not every client has every event.
		pcall(events.RegisterEvent, events, event)
	end
end
