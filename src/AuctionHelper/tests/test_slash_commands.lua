-- Run with: lua5.1 tests/test_slash_commands.lua (from AuctionHelper root)
-- Every /ah subcommand reaches its handler. Handlers are replaced by spies on the addon object.
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

_G.C_Timer = { After = function() end }
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

local calls, messages, settings = {}, {}, {}
local function spy(name)
	pe[name] = function(_, ...)
		calls[#calls + 1] = { name = name, args = { ... } }
		return true
	end
end
local function reset()
	calls, messages = {}, {}
end
local function called(name, firstArg)
	for _, call in ipairs(calls) do
		if call.name == name and (firstArg == nil or call.args[1] == firstArg) then
			return true
		end
	end
	return false
end
local function printed(pattern)
	for _, message in ipairs(messages) do
		if message:find(pattern) then
			return true
		end
	end
	return false
end

pe.PrintMessage = function(_, message) messages[#messages + 1] = message end
pe.InitDB = function() end
pe.SetSetting = function(_, key, value) settings[key] = value end
pe.GetSetting = function(_, key, default)
	if settings[key] == nil then
		return default
	end
	return settings[key]
end
for _, name in ipairs({ "ToggleDashboard", "OpenDocumentationTab", "StartScan", "StartFullCharacterDump", "PrintStatus",
	"Export", "SetDebugEnabled", "ClearDebugLog", "QueueCraftEconomyAuctionRefresh", "QueueVisibleAuctionRefresh",
	"StartAuctionDump" }) do
	spy(name)
end
pe.IsDebugEnabled = function() return false end
pe.BuildAuctionVisibleItemIDs = function() return { 1, 2 } end
pe.BuildAuctionInventoryRows = function() return { {}, {}, {} } end

-- Top-level commands
local TOP_LEVEL = {
	{ "", "ToggleDashboard" }, { "docs", "OpenDocumentationTab" }, { "documentation", "OpenDocumentationTab" },
	{ "scan", "StartScan" }, { "full", "StartFullCharacterDump" }, { "dumpfull", "StartFullCharacterDump" },
	{ "status", "PrintStatus" }, { "SCAN", "StartScan" },
}
for _, case in ipairs(TOP_LEVEL) do
	reset()
	pe:HandleSlash("  " .. case[1] .. " ")
	check("/ah " .. case[1] .. " -> " .. case[2], called(case[2]))
end
reset()
pe:HandleSlash("help")
check("/ah help prints the help lines", printed("^Commands:"))
reset()
pe:HandleSlash("nonsense")
check("/ah nonsense prints unknown command", printed("^Unknown command"))

-- Export
local EXPORTS = {
	{ "export", "character" }, { "export account", "account" }, { "export summary", "account_summary" },
	{ "export items", "inventory" }, { "export meta", "character_meta" }, { "export craftcosts", "crafting_costs" },
}
for _, case in ipairs(EXPORTS) do
	reset()
	pe:HandleSlash(case[1])
	check("/ah " .. case[1] .. " exports " .. case[2], called("Export", case[2]))
end
reset()
pe:HandleSlash("export profession_recipes  Tailoring ")
check("/ah export profession_recipes <name> passes the trimmed name",
	calls[1] and calls[1].args[1] == "profession_recipes" and calls[1].args[2] == "Tailoring")
reset()
pe:HandleSlash("export profession 197")
check("/ah export profession <id>", calls[1] and calls[1].args[1] == "profession" and calls[1].args[2] == "197")
reset()
pe:HandleSlash("export bogus")
check("/ah export bogus prints usage", printed("^Usage: /auctionhelper export") and #calls == 0)

-- Debug
local DEBUG = { { "debug on", true }, { "debug 1", true }, { "debug off", false }, { "debug false", false },
	{ "debug", true } }
for _, case in ipairs(DEBUG) do
	reset()
	pe:HandleSlash(case[1])
	check("/ah " .. case[1] .. " sets debug " .. tostring(case[2]), called("SetDebugEnabled", case[2]))
end
reset()
pe:HandleSlash("debug clear")
check("/ah debug clear clears the log", called("ClearDebugLog") and printed("cleared"))

-- Settings
local SETTINGS = {
	{ "spectree on", "capture.captureSpecializationTree", true, "^Specialization tree capture: on" },
	{ "specialization false", "capture.captureSpecializationTree", false, "^Specialization tree capture: off" },
	{ "recipeoutput 1", "capture.includeRecipeOutputItemData", true, "^Recipe output item API dump: on" },
	{ "rawoutput off", "capture.includeRecipeOutputItemData", false, "^Recipe output item API dump: off" },
	{ "invbatch 50.7", "capture.inventorySnapshotBatchSize", 50, "^Inventory snapshot batch size: 50" },
	{ "inventorybatch 0", "capture.inventorySnapshotBatchSize", 0, "^Inventory snapshot batch size: 0" },
}
for _, case in ipairs(SETTINGS) do
	reset()
	settings = {}
	pe:HandleSlash("settings " .. case[1])
	check("/ah settings " .. case[1], settings[case[2]] == case[3] and printed(case[4]), messages[1])
end
local SETTINGS_USAGE = {
	{ "spectree maybe", "^Usage: /auctionhelper settings spectree on|off$" },
	{ "recipeoutput", "^Usage: /auctionhelper settings recipeoutput on|off$" },
	{ "invbatch -1", "^Usage: /auctionhelper settings invbatch <n>" },
	{ "invbatch x", "^Usage: /auctionhelper settings invbatch <n>" },
	{ "", "^Usage: /auctionhelper settings spectree on|off | recipeoutput" },
	{ "bogus on", "^Usage: /auctionhelper settings spectree on|off | recipeoutput" },
}
for _, case in ipairs(SETTINGS_USAGE) do
	reset()
	settings = {}
	pe:HandleSlash("settings " .. case[1])
	check("/ah settings " .. case[1] .. " prints usage", printed(case[2]) and #messages == 1 and next(settings) == nil,
		messages[1])
end

-- Auction
reset()
pe:HandleSlash("auction")
check("/ah auction prints status", printed("^Auction module: enabled%. Inventory rows: 3%."))
reset()
pe:HandleSlash("ah status")
check("/ah ah status prints status", printed("^Auction module: enabled"))
reset()
pe:HandleSlash("auction disable")
check("/ah auction disable", settings["auction.enabled"] == false and printed("^Auction module disabled%."))
reset()
pe:HandleSlash("auction enable")
check("/ah auction enable", settings["auction.enabled"] == true and printed("^Auction module enabled%."))
reset()
pe:HandleSlash("auction refresh craft")
check("/ah auction refresh craft queues crafts", called("QueueCraftEconomyAuctionRefresh") and printed("^Queued craft refresh"))
reset()
pe:HandleSlash("auction refresh")
check("/ah auction refresh queues visible items", called("QueueVisibleAuctionRefresh") and printed("^Queued visible"))
reset()
pe:HandleSlash("auction dump full")
check("/ah auction dump full starts a full dump", called("StartAuctionDump", "full"))
reset()
pe:HandleSlash("auction dump")
check("/ah auction dump defaults to visible", called("StartAuctionDump", "visible"))
reset()
pe:HandleSlash("auction bogus")
check("/ah auction bogus prints usage", printed("^Usage: /auctionhelper auction") and #calls == 0)

-- Without the auction module loaded, refresh and dump fall through to the usage line.
pe.QueueCraftEconomyAuctionRefresh, pe.QueueVisibleAuctionRefresh, pe.StartAuctionDump = nil, nil, nil
for _, command in ipairs({ "auction refresh crafts", "auction refresh", "auction dump" }) do
	reset()
	pe:HandleSlash(command)
	check("/ah " .. command .. " without the module prints usage", printed("^Usage: /auctionhelper auction") and #messages == 1)
end

if failed > 0 then
	print(failed .. " check(s) failed")
	os.exit(1)
end
print("All slash command checks passed")
