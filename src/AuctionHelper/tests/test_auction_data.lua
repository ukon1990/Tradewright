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
load("AuctionHelper/src/util/AuctionHelper_JsonCodec.lua")
load("AuctionHelper/src/util/AuctionHelper_ItemInfo.lua")
load("AuctionHelper/src/core/AuctionHelper_Data.lua")
load("AuctionHelper/src/core/AuctionHelper_ProfessionSpecTree.lua")
load("AuctionHelper/src/core/AuctionHelper_ProfessionScan.lua")
load("AuctionHelper/src/core/AuctionHelper_ExportBuild.lua")
load("AuctionHelper/src/core/AuctionHelper_CopyBox.lua")
load("AuctionHelper/src/core/AuctionHelper_SlashCommands.lua")
for _, path in ipairs(dofile(root .. "/tests/auction_data_files.lua")(repo)) do
	load(path)
end

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

-- Session lookups use the same item key as the saved data, so a plain item and an all-zero key match.
local zeroFields = { itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
pe:MarkAuctionTargetSearched(2589, zeroFields, "test")
check("All-zero key counts as the plain item searched", pe:HasAuctionTargetBeenSearchedThisSession(2589, nil))
check("Session key is the saved item key", pe:GetAuctionSearchedTargetsState()["2589"] == true)
pe:MarkAuctionTargetSearched(19019, { itemLevel = 71 }, "test")
check("Item level key is kept apart", pe:HasAuctionTargetBeenSearchedThisSession(19019, { itemLevel = 71 })
	and not pe:HasAuctionTargetBeenSearchedThisSession(19019, nil))
check("Search event matches its item key", pe:DoesAuctionSearchEventMatchItem(19019, { itemKey = { itemID = 19019, itemLevel = 71 } }, { itemLevel = 71 }))
check("Search event of another item level does not match",
	not pe:DoesAuctionSearchEventMatchItem(19019, { itemKey = { itemID = 19019, itemLevel = 60 } }, { itemLevel = 71 }))

-- Queued refresh: each priced item adds to one source counter.
pe.MarkAuctionTargetSearched = function() end
pe.DebugLog = function() end
pe.GetItemDisplayName = function() return "Item" end
pe.GetItemEconomySummary = function() return nil end
pe.UpdateAuctionPanelRowPrice = function() end
pe.ContinueQueuedAuctionRefresh = function() end
local refreshState = pe:GetState()
refreshState.auctionSourceCounts = nil
local function finishWith(priceState)
	pe.ProcessAuctionRefreshItem = function() return priceState end
	pe:FinishQueuedAuctionRefreshItem(2589)
end
finishWith({ currentPrice = 100, currentPriceIsNative = true, currentPriceSource = "snapshot" })
finishWith({ currentPrice = 100, currentPriceSource = "snapshot" })
finishWith({ currentPrice = 100, currentPriceSource = "tsm" })
finishWith({ currentPrice = 100 })
finishWith({ currentPrice = 0, currentPriceIsNative = true })
local counts = refreshState.auctionSourceCounts or {}
check("Native price counts as native even when its source says snapshot", counts.native == 1, counts.native)
check("Snapshot price counts as snapshot", counts.snapshot == 1, counts.snapshot)
check("Any other or missing source counts as fallback", counts.fallback == 2, counts.fallback)
check("Unpriced item is not counted and the last price stays", refreshState.auctionLivePriceByItem[2589] == 100)

-- Bulk post: a post from either button (Post next or the game's Create Auction) moves the job on
_G.GetTime = _G.GetTime or function() return 100 end
pe.RecordAuctionTransaction = function() end
local function bulkWaitingFor(itemID, phase)
	pe:GetState().auctionBulk = { running = true, phase = phase, currentItemID = itemID, index = 1, total = 2,
		posted = 0, rows = { { itemID = itemID }, { itemID = 999 } } }
	return pe:GetState().auctionBulk
end
local bulk = bulkWaitingFor(2589, "waiting_button")
pe:OnAuctionPostCalled(2589)
check("Bulk: Create Auction on the waiting item counts as posted", bulk.posted == 1 and bulk.index == 2 and bulk.phase == "selecting")
bulk = bulkWaitingFor(2589, "waiting_confirmation")
pe:OnAuctionPostCalled(nil)
check("Bulk: a post whose stack is gone still confirms the waiting item", bulk.posted == 1 and bulk.index == 2)
bulk = bulkWaitingFor(2589, "waiting_button")
pe:OnAuctionPostCalled(4306)
check("Bulk: posting another item leaves the job waiting", bulk.posted == 0 and bulk.index == 1 and bulk.phase == "waiting_button")
bulk = bulkWaitingFor(2589, "selecting")
pe:OnAuctionPostCalled(2589)
check("Bulk: a post while the job is still selecting is not counted", bulk.posted == 0)
-- Post next: the post hook fires inside the button click; the job must not fall back to waiting
bulk = bulkWaitingFor(2589, "waiting_button")
bulk.nextPostAt = 0
pe.TryClickAuctionPostButton = function()
	pe:OnAuctionPostCalled(2589)
	return true
end
pe:PostAuctionBulkCurrent()
check("Bulk: Post next confirmed by the hook moves on, not back to waiting", bulk.posted == 1 and bulk.phase == "selecting")
pe.TryClickAuctionPostButton = function() return false end
bulk = bulkWaitingFor(2589, "waiting_button")
bulk.nextPostAt = 0
pe:PostAuctionBulkCurrent()
check("Bulk: a click on a button that is not ready keeps the job waiting for Post next", bulk.phase == "waiting_button")
-- A late "auction created" event for the item just posted must not count the next one
bulk = bulkWaitingFor(2589, "waiting_button")
pe:OnAuctionPostCalled(2589)
bulk.phase, bulk.currentItemID = "waiting_button", 999
pe:OnAuctionHouseAuctionCreated()
check("Bulk: a late created event leaves the next item waiting", bulk.index == 2 and bulk.posted == 1 and bulk.phase == "waiting_button")
pe:GetState().auctionBulk = nil
timers = {}

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All auction data tests passed")
