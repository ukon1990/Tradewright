-- Run with: lua5.1 tests/test_auction_data.lua (from AuctionHelper root)
-- Loads the real core and auction module files with stubbed WoW globals.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local repo = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local timers = {}
_G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
_G.GetBuildInfo = function() return "1.16.1", "1", "", 16001 end
_G.CreateFrame = function() return {} end
_G.GetServerTime = function() return 1700000000 end

local pe = {}
local function load(path)
	local chunk, err = loadfile(repo .. "/" .. path)
	assert(chunk, err)
	chunk("AuctionHelper", pe)
end
load("AuctionHelper/src/core/AuctionHelper.lua")
load("AuctionHelper/src/util/AuctionHelper_ForeverLogic.lua")
load("AuctionHelper/src/util/AuctionHelper_CoreHelpers.lua")
load("AuctionHelper/src/util/AuctionHelper_Util.lua")
load("AuctionHelper/src/core/AuctionHelper_Data.lua")
load("AuctionHelper_AuctionData/src/modules/AuctionHelper_Auction.lua")

local messages = {}
pe.PrintMessage = function(_, message) messages[#messages + 1] = message end
local function printed(pattern)
	for _, message in ipairs(messages) do
		if message:find(pattern) then
			return true
		end
	end
	return false
end
local function runTimers()
	while #timers > 0 do
		table.remove(timers, 1)()
	end
end

-- Shared clock
check("Now uses server time", pe:Now() == 1700000000)

-- /ah auction dump
pe.RefreshAuctionHousePanel = function() end
pe.FormatNumberGrouped = function(_, value) return tostring(value) end
pe.PrimeAuctionPanelRows = function() end
pe.StopAuctionScanForDump = function() end
pe.GetSetting = function(_, _, default) return default end
pe.PersistAuctionDumpObservation = function() return true end
local dumpRows = { { itemID = 2589, currentPrice = 100 } }
pe.CollectVisibleAuctionDumpRows = function() return dumpRows end

pe:HandleAuctionSlash("dump")
check("Dump prints started", printed("^Auction dump started"), messages[1])
check("Dump is not complete before it ran", not printed("complete"))
runTimers()
check("Dump prints complete after it ran", printed("^Dump complete: 1 items"), messages[#messages])

messages = {}
pe:GetState().auctionDump.running = true
pe:HandleAuctionSlash("dump")
check("Refused dump prints the reason", printed("already running"))
check("Refused dump prints no started or completed line", #messages == 1, table.concat(messages, " | "))
pe:GetState().auctionDump.running = false

messages = {}
dumpRows = {}
pe:HandleAuctionSlash("dump")
check("Empty dump completes without a started line", printed("^Dump complete: 0") and not printed("started"))

messages = {}
pe.QueueCraftEconomyAuctionRefresh = function() end
pe:HandleAuctionSlash("refresh crafts")
check("Refresh crafts confirms", printed("^Queued craft refresh%."))

-- Commodity purchase from the shopping cart
local purchaseCalls = 0
_G.C_AuctionHouse = {
	StartCommoditiesPurchase = function() purchaseCalls = purchaseCalls + 1 end,
	ConfirmCommoditiesPurchase = function() purchaseCalls = purchaseCalls + 1 end,
}
pe.PauseAuctionScanForManualBuy = function() end
pe.SearchAuctionCartRow = function() return false end
pe.GetLiveAuctionSearchAggregate = function() return { kind = "commodity" } end
pe.GetItemDisplayName = function() return "Item" end
pe.ScheduleAuctionCartPurchaseRefresh = function() end
local cartRow = { itemID = 2589, quantityToBuy = 3 }

pe.IS_RETAIL = false
check("Forever cart buy is refused", pe:TryBuyAuctionCartRow(cartRow) == false)
check("Forever cart buy calls no purchase API", purchaseCalls == 0, purchaseCalls)

pe.IS_RETAIL = true
check("Retail cart buy goes through", pe:TryBuyAuctionCartRow(cartRow) == true)
check("Retail cart buy starts and confirms", purchaseCalls == 2, purchaseCalls)

-- The two item key formats in use today: the auction session key and the stored ForeverLogic key.
local zeroFields = { itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
check("Session key, plain item", pe:SerializeAuctionItemKeyFields(2589, nil) == "2589:")
check("Session key, all-zero fields", pe:SerializeAuctionItemKeyFields(2589, zeroFields) == "2589:0:0:0")
check("Session key, item level", pe:SerializeAuctionItemKeyFields(19019, { itemLevel = 71 }) == "19019:71:0:0")
check("Stored key, plain item", pe.ForeverLogic.SerializeItemKey(nil, 2589) == "2589")
zeroFields.itemID = 2589
check("Stored key, all-zero fields", pe.ForeverLogic.SerializeItemKey(zeroFields) == "2589")

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All auction data tests passed")
