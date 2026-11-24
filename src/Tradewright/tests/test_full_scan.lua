-- Run with: lua5.1 tests/test_full_scan.lua (from Tradewright root)
-- The classic (page by page) full scan against a fake auction house: every listing must be saved,
-- even when the answer to another search arrives while the scan runs.
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

-- Fake classic auction house: 120 listings of 120 different items, 50 per page. A query is
-- answered only when the test says so (the server answers later, in order).
local PAGE_SIZE = 50
local LINEN_CLOTH = 2589
local listings = {}
for i = 1, 120 do
	local itemID = i == 7 and LINEN_CLOTH or 10000 + i
	listings[i] = { itemID = itemID, name = itemID == LINEN_CLOTH and "Linen Cloth" or ("Item " .. i), count = 1, buyout = 100 + i }
end
local shownList, shownTotal = {}, 0
local pendingQueries = {}
local canSend = true

_G.QueryAuctionItems = function(name, _, _, page)
	pendingQueries[#pendingQueries + 1] = { name = name, page = page or 0 }
end
_G.CanSendAuctionQuery = function() return canSend end
_G.GetNumAuctionItems = function() return #shownList, shownTotal end
_G.GetAuctionItemInfo = function(_, index)
	local row = shownList[index]
	if not row then
		return nil
	end
	return row.name, nil, row.count, nil, nil, nil, nil, nil, nil, row.buyout, nil, nil, nil, nil, nil, nil, row.itemID
end

local pe = {}
local function load(path)
	local chunk, err = loadfile(repo .. "/" .. path)
	assert(chunk, err)
	chunk("Tradewright", pe)
end
load("Tradewright/src/core/Tradewright.lua")
load("Tradewright/src/util/Tradewright_ForeverLogic.lua")
load("Tradewright/src/util/Tradewright_AuctionLogic.lua")
load("Tradewright/src/util/Tradewright_MarketSignals.lua")
load("Tradewright/src/util/Tradewright_CoreHelpers.lua")
load("Tradewright/src/util/Tradewright_Util.lua")
load("Tradewright/src/util/Tradewright_ItemInfo.lua")
load("Tradewright/src/core/Tradewright_Data.lua")
for _, path in ipairs(dofile(root .. "/tests/auction_data_files.lua")(repo)) do
	load(path)
end
load("Tradewright_AuctionData/src/modules/Tradewright_PriceSteps.lua")

local saved = {}
pe.PrintMessage = function() end
pe.RefreshAuctionHousePanel = function() end
pe.FormatNumberGrouped = function(_, value) return tostring(value) end
pe.PrimeAuctionPanelRows = function() end
pe.TrimFullDumpMarketHistory = function() end
pe.StopAuctionScanForDump = function() end
pe.IsAuctionHouseFrameOpen = function() return true end
pe.CanUseReplicateAuctionDump = function() return false end
pe.GetFullAuctionDumpCooldownRemaining = function() return 0 end
pe.SetLastFullAuctionScanAt = function() end
pe.PersistDumpAggregate = function(_, itemID) saved[#saved + 1] = itemID end

-- The server answers the oldest open query and the client fires AUCTION_ITEM_LIST_UPDATE.
local function answerNextQuery()
	local query = table.remove(pendingQueries, 1)
	local matches = {}
	for _, row in ipairs(listings) do
		if query.name == "" or row.name == query.name then
			matches[#matches + 1] = row
		end
	end
	shownList, shownTotal = {}, #matches
	for i = query.page * PAGE_SIZE + 1, math.min(#matches, (query.page + 1) * PAGE_SIZE) do
		shownList[#shownList + 1] = matches[i]
	end
	pe:OnAuctionItemListUpdate()
end

-- Let the scan run to its end: the server answers each query in turn, faster than any timer.
local function runScan()
	for _ = 1, 200 do
		if #pendingQueries > 0 then
			answerNextQuery()
		elseif #timers > 0 then
			table.remove(timers, 1)()
		else
			return
		end
	end
end

local function startScan()
	saved, timers, pendingQueries = {}, {}, {}
	pe:GetState().auctionDump = nil
	return pe:StartAuctionDump("full")
end

-- Plain run: nothing else searches the auction house.
check("Full scan starts", startScan())
runScan()
check("Plain full scan saves every item", #saved == #listings, #saved .. " of " .. #listings)

-- A search for one profession reagent (the player, the AH window or another addon) went out just
-- before the full scan, so the server throttles the scan's first query. The reagent answer then
-- arrives while the scan waits to send page 0.
canSend = false
startScan()
pendingQueries = { { name = "Linen Cloth", page = 0 } }
answerNextQuery() -- the scan is waiting to send page 0 when the reagent answer arrives
canSend = true
runScan()
check("Full scan started while throttled saves every item, not just the reagent search", #saved == #listings,
	#saved .. " of " .. #listings .. " saved")

-- The scan sent page 0, but the answer to a reagent search sent just before arrives first.
startScan()
table.insert(pendingQueries, 1, { name = "Linen Cloth", page = 0 })
runScan()
check("Full scan ignores the answer to an earlier reagent search", #saved == #listings,
	#saved .. " of " .. #listings .. " saved")

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All full scan tests passed")
