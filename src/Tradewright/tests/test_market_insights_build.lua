-- Run with: lua5.1 tests/test_market_insights_build.lua (from Tradewright root); npm test runs it too.
-- Market insights build in the background. Every list that asked for them while the build ran shows a
-- loading state until its callback fires, so every caller must be told when the build ends, not only
-- the one that started it.
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

-- Timers run only when the test says so, like frames passing.
local timers = {}
_G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function runTimers()
	while #timers > 0 do
		table.remove(timers, 1)()
	end
end

local state = {}
local pe = {
	MarketLogic = { TopN = function() return {} end },
	ForeverLogic = {},
	GetState = function() return state end,
	GetSetting = function(_, _, default) return default end,
	InitAuctionDB = function() return { snapshot = {} } end,
	Now = function() return 1000 end,
}
local chunk, err = loadfile(root .. "/../Tradewright_AuctionData/src/modules/Tradewright_MarketInsights.lua")
assert(chunk, err)
chunk("Tradewright_AuctionData", pe)

local calls = {}
local function waiter(name)
	return function(insights) calls[#calls + 1] = { name = name, insights = insights } end
end

check("First ask starts a build and has nothing yet", pe:GetMarketInsights(waiter("overview")) == nil)
check("Ask during the build has nothing yet", pe:GetMarketInsights(waiter("opportunities")) == nil)
check("Progress note while building", pe.MarketInsightsLoadingNote() == "Reading auction scans · 0%")
runTimers()
check("Both callers told when the build ends", #calls == 2, #calls)
check("Starter told first", calls[1] and calls[1].name == "overview")
check("Later caller gets the insights", calls[2] and calls[2].name == "opportunities" and calls[2].insights == state.marketInsights)

calls = {}
check("Built insights come back at once", pe:GetMarketInsights(waiter("farming")) == state.marketInsights)
runTimers()
check("No callback when nothing was built", #calls == 0, #calls)

if failed > 0 then
	print(failed .. " market insights build check(s) failed")
	os.exit(1)
end
print("All market insights build checks passed")
