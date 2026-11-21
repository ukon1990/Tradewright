-- Run with: lua5.1 tests/test_events.lua (from AuctionHelper root)
-- Loads AuctionHelper_Events.lua against a fake frame: which events get registered, and how they reach handlers.
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

local registered = {}
local frame = {}
function frame:RegisterEvent(event)
	registered[#registered + 1] = event
end
function frame:SetScript(_, script)
	self.onEvent = script
end

local pe = { frame = frame }
local chunk, err = loadfile(root .. "/src/core/AuctionHelper_Events.lua")
assert(chunk, err)
chunk("AuctionHelper", pe)

local function fire(event, ...)
	frame.onEvent(frame, event, ...)
end

-- Registration: exactly the events the addon listened to before the handler table existed.
local EXPECTED_EVENTS = {
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_MONEY", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
	"UPDATE_TRADESKILL_CAST_STOPPED", "TRADE_SKILL_CLOSE", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED",
	"AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_AUCTION_SOLD",
	"OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED", "MAIL_INBOX_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
	"REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE", "COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED", "COMMODITY_PURCHASED", "ITEM_PURCHASED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
	"TRADE_SKILL_ITEM_CRAFTED_RESULT", "NEW_RECIPE_LEARNED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
	"PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE",
	"CRAFTINGORDERS_RELEASE_ORDER_RESPONSE", "CRAFTINGORDERS_REJECT_ORDER_RESPONSE", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
}

local function sortedCopy(list)
	local copy = {}
	for index, value in ipairs(list) do
		copy[index] = value
	end
	table.sort(copy)
	return copy
end

local registeredText = table.concat(sortedCopy(registered), ",")
check("Registers exactly the expected events", registeredText == table.concat(sortedCopy(EXPECTED_EVENTS), ","),
	registeredText)

local tableEvents = {}
for event in pairs(pe.EVENT_HANDLERS or {}) do
	tableEvents[#tableEvents + 1] = event
end
check("Registers exactly the events in the handler table", table.concat(sortedCopy(tableEvents), ",") == registeredText)

-- Dispatch
local calls = {}
local function spy(name)
	pe[name] = function(_, ...)
		calls[#calls + 1] = { name = name, args = { ... } }
	end
end
local function lastCall()
	return calls[#calls] or {}
end

local ok, dispatchErr = pcall(fire, "AUCTION_HOUSE_SHOW")
check("An event whose method is missing is a no-op", ok and #calls == 0, dispatchErr)
ok = pcall(fire, "SOME_UNKNOWN_EVENT")
check("An event without a handler is ignored", ok and #calls == 0)

spy("OnAuctionHouseShow")
fire("AUCTION_HOUSE_SHOW")
check("Event reaches its method", lastCall().name == "OnAuctionHouseShow")

spy("OnAuctionHouseBrowseResultsUpdated")
fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "a", "b")
check("Event arguments are passed through", lastCall().name == "OnAuctionHouseBrowseResultsUpdated"
	and lastCall().args[1] == "a" and lastCall().args[2] == "b")

spy("DebugLogEvent")
calls = {}
fire("MAIL_FAILED", 7)
check("Every event is passed to the debug log when it exists", calls[1] and calls[1].name == "DebugLogEvent"
	and calls[1].args[1] == "MAIL_FAILED" and calls[1].args[2] == 7)
pe.DebugLogEvent = nil

-- Crafting order responses only count when the server says Ok.
_G.Enum = { CraftingOrderResult = { Ok = 0 } }
spy("OnCraftingOrderFulfilled")
calls = {}
fire("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 3, 99)
check("Failed crafting order response is ignored", #calls == 0)
fire("CRAFTINGORDERS_REJECT_ORDER_RESPONSE", 0, 99)
check("Ok crafting order response reaches the handler with the order id",
	lastCall().name == "OnCraftingOrderFulfilled" and lastCall().args[1] == 99)

-- Handlers with more than one step.
_G.time = function() return 1000 end
_G.GetMoney = function() return 5 end
spy("RecordWalletObservation")
spy("RefreshShellStatus")
pe.GetCharacterKey = function() return "Me" end
calls = {}
fire("PLAYER_MONEY")
check("PLAYER_MONEY records the wallet and refreshes the shell",
	calls[1] and calls[1].name == "RecordWalletObservation" and calls[1].args[1] == "Me" and calls[1].args[2] == 5
	and calls[2] and calls[2].name == "RefreshShellStatus")

spy("UpdateDynamicPanelLayering")
fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
check("Interaction show passes a tagged reason", lastCall().args[1] == "interaction_show_21")

spy("ScheduleLiveInventoryRefresh")
calls = {}
fire("BANKFRAME_OPENED")
check("Bank open schedules an inventory refresh", lastCall().name == "ScheduleLiveInventoryRefresh")

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All event checks passed")
