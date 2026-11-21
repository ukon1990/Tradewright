-- Run with: lua5.1 tests/test_spec_tree.lua (from AuctionHelper root)
-- Pins the profession specialization tree read from a fake C_ProfSpecs / C_Traits: gating, tab
-- header, paths, milestones, perks with their unlock ranks, names and the path graph.
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
load("AuctionHelper/src/util/AuctionHelper_JsonCodec.lua")
load("AuctionHelper/src/util/AuctionHelper_ItemInfo.lua")
load("AuctionHelper/src/core/AuctionHelper_Data.lua")
load("AuctionHelper/src/core/AuctionHelper_ProfessionSpecTree.lua")
load("AuctionHelper/src/core/AuctionHelper_ProfessionScan.lua")
load("AuctionHelper/src/core/AuctionHelper_ExportBuild.lua")
load("AuctionHelper/src/core/AuctionHelper_CopyBox.lua")
load("AuctionHelper/src/core/AuctionHelper_SlashCommands.lua")

-- Tree 900: path 10 (children: path 11, milestone 20, unknown 99), path 11, milestone 20.
local nodes = {
	[10] = { maxRanks = 30, entryIDs = { 100 } },
	[11] = { totalMaxRanks = 10, entryIDs = { 110, 111 } },
	[20] = { maxRanks = 1, entryIDs = { 200 } },
}
local entries = {
	[100] = { definitionID = 1000 }, [110] = { definitionID = 1100 }, [111] = { definitionID = 1110 },
	[200] = { definitionID = 2000 },
}
local definitions = {
	[1000] = { overrideName = "Smelting" }, [1100] = {}, [1110] = { overrideName = "Late", overrideDescription = "Late text" },
	[2000] = { overrideDescription = "Milestone text" },
}
local unlockRanks = { [500] = 5, [10] = 1, [11] = 2, [20] = 15, [110] = 7, [200] = 9 }
_G.C_ProfSpecs = {
	GetConfigIDForSkillLine = function(skillLineID) return skillLineID == 2916 and 77 or 0 end,
	GetCurrencyInfoForSkillLine = function() return { numAvailable = 12, currencyName = "Knowledge" } end,
	GetTabInfo = function(treeID) return { name = "Tab " .. treeID } end,
	GetStateForTab = function() return "unlocked" end,
	GetRootPathForTab = function() return 10 end,
	GetDescriptionForPath = function(nodeID)
		if nodeID == 11 then
			return "Alloys|nMore text"
		elseif nodeID == 20 then
			error("no path")
		end
		return nil
	end,
	GetChildrenForPath = function(nodeID) return nodeID == 10 and { 11, 20, 99 } or nil end,
	GetPerksForPath = function(nodeID)
		if nodeID == 10 then
			return { { perkID = 500 } }
		elseif nodeID == 11 then
			return { 501, 502 }
		end
	end,
	GetDescriptionForPerk = function(perkID) return perkID == 500 and "Perk 500 text" or nil end,
	GetUnlockRankForPerk = function(id) return unlockRanks[id] end,
}
_G.C_Traits = {
	GetConfigInfo = function() return { treeIDs = { 900 } } end,
	GetTreeNodes = function() return { 10, 11, 20 } end,
	GetNodeInfo = function(_, nodeID) return nodes[nodeID] end,
	GetEntryInfo = function(_, entryID) return entries[entryID] end,
	GetDefinitionInfo = function(definitionID) return definitions[definitionID] end,
}
_G.C_TradeSkillUI = {
	GetProfessionInfoBySkillLineID = function() return { professionName = "Midnight Mining", parentProfessionID = 186 } end,
}
pe.ResolveSpecCatalogForTierSkillLine = function(_, skillLineID) return skillLineID == 2916 and 11 or nil end

check("No skill line gives nothing", pe:CollectSpecializationTreeForSkillLine(nil) == nil)
check("Skill line without a config gives nothing", pe:CollectSpecializationTreeForSkillLine(186) == nil)

local tree = pe:CollectSpecializationTreeForSkillLine("2916")
check("Tree header", tree and tree.configID == 77 and tree.skillLineID == 2916 and tree.tierName == "Midnight Mining"
	and tree.parentProfessionID == 186 and tree.expansionID == 11)
check("Tree keeps tree IDs and config", #tree.treeIDs == 1 and tree.treeIDs[1] == 900 and tree.configInfo.treeIDs[1] == 900)
check("Unspent knowledge from the currency", tree.unspentKnowledge.numAvailable == 12)
check("One tab per tree", #tree.tabs == 1)
local tab = tree.tabs[1]
check("Tab header", tab.treeID == 900 and tab.rootPathID == 10 and tab.tabInfo.name == "Tab 900" and tab.state == "unlocked")
check("Raw nodes are replaced by the graph", tab.nodes == nil)
check("Paths sort by node ID", #tab.paths == 2 and tab.paths[1].nodeID == 10 and tab.paths[2].nodeID == 11)
check("Milestones are split out", #tab.milestones == 1 and tab.milestones[1].nodeID == 20)
check("Path edges only link paths", #tab.edges == 1 and tab.edges[1].fromPathID == 10 and tab.edges[1].toPathID == 11)

local smelting, alloys, milestone = tab.paths[1], tab.paths[2], tab.milestones[1]
check("Path keeps its child paths", #smelting.childPathIDs == 1 and smelting.childPathIDs[1] == 11)
check("Path name from the definition", smelting.nodeName == "Smelting")
check("Path description from the perk", smelting.nodeDescription == "Perk 500 text")
check("Path unlock rank", smelting.unlockRank == 1 and smelting.milestoneRank == nil)
local perk = smelting.entries[1]
check("Entry carries its perk", perk.entryID == 100 and perk.perkID == 500 and perk.perkDescription == "Perk 500 text")
check("Entry unlock rank from the perk", perk.unlockRank == 5)
check("Entry keeps entry and definition info", perk.entryInfo.definitionID == 1000 and perk.definitionInfo.overrideName == "Smelting")

check("Name falls back to the first path line", alloys.nodeName == "Alloys", alloys.nodeName)
check("Description falls back to the path text", alloys.nodeDescription == "Alloys|nMore text")
check("Path has no children without a child list", alloys.childPathIDs == nil)
check("Entries follow the node order", #alloys.entries == 2 and alloys.entries[2].entryID == 111
	and alloys.entries[2].perkID == 502)
check("Perk without a rank falls back to the entry rank", alloys.entries[1].perkID == 501
	and alloys.entries[1].unlockRank == 7)
check("No rank at all is nil", alloys.entries[2].unlockRank == nil)
check("First entry names the node", alloys.nodeName ~= "Late")

check("Milestone hangs under its path", milestone.parentPathID == 10 and milestone.parentPathName == "Smelting")
check("Milestone rank is its unlock rank", milestone.milestoneRank == 15 and milestone.unlockRank == 15)
check("Failing path description is nil", milestone.pathDescription == nil)
check("Milestone has no perk", milestone.entries[1].perkID == nil and milestone.entries[1].unlockRank == 9)
check("Milestone description from its definition", milestone.nodeDescription == "Milestone text"
	and milestone.nodeName == nil)

-- Optional API functions missing
_G.C_ProfSpecs = { GetConfigIDForSkillLine = function() return 5 end }
_G.C_Traits = { GetConfigInfo = function() return { treeIDs = { 1 } } end }
_G.C_TradeSkillUI = nil
pe.ResolveSpecCatalogForTierSkillLine = nil
local bare = pe:CollectSpecializationTreeForSkillLine(2916)
check("Bare API still gives a tree", bare and bare.configID == 5 and bare.tierName == nil and bare.expansionID == nil
	and bare.unspentKnowledge == nil)
check("Bare API tab is empty", #bare.tabs == 1 and bare.tabs[1].rootPathID == nil and bare.tabs[1].tabInfo == nil
	and #bare.tabs[1].paths == 0)

_G.C_ProfSpecs = nil
check("No C_ProfSpecs gives nothing", pe:CollectSpecializationTreeForSkillLine(2916) == nil)

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All spec tree tests passed")
