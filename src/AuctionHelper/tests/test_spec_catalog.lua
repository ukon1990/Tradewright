-- Run with: lua5.1 tests/test_spec_catalog.lua (from AuctionHelper root)
-- Spec catalog metadata on a stored profession: node ranks per tier, which catalogs apply,
-- and the per-recipe spec skill breakdown.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addons = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local BLACKSMITHING, TAILORING = 1, 2
local professionNames = { "Blacksmithing", "Leatherworking", "Alchemy", "Herbalism", "Cooking", "Mining", "Tailoring",
	"Engineering", "Enchanting", "Fishing", "Skinning", "Jewelcrafting", "Inscription" }
local professionEnum = {}
for i, name in ipairs(professionNames) do
	professionEnum[name] = i + 100
end
professionEnum.Blacksmithing = BLACKSMITHING
professionEnum.Tailoring = TAILORING

local unlockRanks = { [1000] = 0, [1001] = 20, [2000] = 0, [3000] = 0 }
local wowGlobals = {
	Enum = { Profession = professionEnum },
	C_ProfSpecs = {
		GetUnlockRankForPerk = function(perkID)
			return unlockRanks[perkID]
		end,
	},
}
for name, value in pairs(wowGlobals) do
	rawset(_G, name, value)
end

local function newAddon(settings)
	settings = settings or {}
	local pe = { configIDs = {} }
	function pe:GetSetting(key, default)
		if settings[key] ~= nil then
			return settings[key]
		end
		return default
	end
	function pe:TableCount(t)
		local n = 0
		for _ in pairs(t) do
			n = n + 1
		end
		return n
	end
	function pe:GetRecipeSpellID(recipeData)
		return recipeData.spellID
	end
	function pe:GetRecipeExportID(recipeData)
		return recipeData.exportID
	end
	local chunk, err = loadfile(addons .. "/AuctionHelper_Professions/src/modules/AuctionHelper_SpecCatalog.lua")
	assert(chunk, err)
	chunk("AuctionHelper", pe)

	local compute = pe.ComputeSpecBreakdownForRecipe
	function pe:ComputeSpecBreakdownForRecipe(recipeID, catalog, nodeRanks, configID)
		self.configIDs[recipeID] = configID or false
		return compute(self, recipeID, catalog, nodeRanks, configID)
	end

	pe:RegisterSpecCatalog(11, BLACKSMITHING, {
		recipeMapping = { [500] = { 1000, 1001 } },
		nodeData = {
			[77] = { maxRank = 30, name = "Hammers", stats = { skill = 1 } },
			[1000] = { nodeID = 77, maxRank = 1, stats = { skill = 5 } },
			[1001] = { nodeID = 77, maxRank = 1, stats = { multicraft = 10 } },
		},
	})
	pe:RegisterSpecCatalog(10, BLACKSMITHING, {
		recipeMapping = { [600] = { 2000 } },
		nodeData = { [2000] = { nodeID = 88, maxRank = 1, stats = { skill = 3 } } },
	})
	pe:RegisterSpecCatalog(11, TAILORING, {
		recipeMapping = { [900] = { 3000 } },
		nodeData = { [3000] = { nodeID = 99, maxRank = 1, stats = { skill = 2 } } },
	})
	return pe
end

local function tree(skillLineID, activeRank, configID)
	return {
		skillLineID = skillLineID,
		configID = configID,
		tabs = { { nodes = { { nodeID = 77, nodeInfo = { maxRanks = 30, activeRank = activeRank } } } } },
	}
end

local function professionData()
	return {
		primarySpecializationSkillLineID = 2907,
		specializationTrees = { ["2907"] = tree(2907, 11, 9), ["2918"] = tree(2918, 3, 8) },
		recipes = {
			["500"] = { spellID = 500, exportID = 5000, crafting = {} },
			["600"] = { spellID = 600 },
			["700"] = { spellID = 700, crafting = {} },
			["900"] = { crafting = {} },
		},
	}
end

do
	local pe = newAddon()
	local data = professionData()
	check("Attach: returns the same table", pe:AttachSpecCatalogMetadata(data, 164) == data)
	check("Ranks: active rank minus one per tier", data.specNodeRanksByTier["2907"]["77"] == 10 and data.specNodeRanksByTier["2918"]["77"] == 2)
	check("Ranks: primary tier ranks exposed", data.specNodeRanks == data.specNodeRanksByTier["2907"])

	local byTier = data.specCatalog.byTier
	check("Catalog: available with version", data.specCatalog.available == true and data.specCatalog.version == 1)
	check("Catalog: own Midnight tier", byTier["2907"] and byTier["2907"].expansionID == 11 and byTier["2907"].tierSkillLineID == 2907
		and byTier["2907"].nodeCount == 3 and byTier["2907"].recipeMappingCount == 1)
	check("Catalog: own TWW tier", byTier["2872"] and byTier["2872"].expansionID == 10 and byTier["2872"].nodeCount == 1)
	check("Catalog: tier without catalog left out", byTier["2822"] == nil)
	check("Catalog: ranked tier of another profession resolved", byTier["2918"] and byTier["2918"].expansionID == 11
		and byTier["2918"].tierSkillLineID == 2918 and byTier["2918"].available == true)

	local b500 = data.recipes["500"].specBreakdown
	check("Breakdown: base node rank plus unlocked perk", b500 and b500.totals.skill == 15, b500 and b500.totals.skill)
	check("Breakdown: locked perk adds nothing", b500.totals.multicraft == 0)
	check("Breakdown: identifiers", b500.recipeID == 5000 and b500.recipeSpellID == 500 and b500.expansionID == 11
		and b500.profession == BLACKSMITHING and b500.tierSkillLineID == 2907 and b500.catalogMatched == true)
	check("Breakdown: crafting skill copied", data.recipes["500"].crafting.specSkillFromCatalog == 15
		and data.recipes["500"].crafting.bonusSkillFromCatalog == 15)
	check("Breakdown: config from the tier tree", pe.configIDs[500] == 9)

	local b600 = data.recipes["600"].specBreakdown
	check("Breakdown: older tier, no ranks, perk at rank 0", b600 and b600.totals.skill == 3 and b600.tierSkillLineID == 2872)
	check("Breakdown: recipe id falls back to the key", b600.recipeID == 600)
	check("Breakdown: no tree for tier means no config", pe.configIDs[600] == false)
	check("Breakdown: recipe without catalog untouched", data.recipes["700"].specBreakdown == nil
		and data.recipes["700"].crafting.specSkillFromCatalog == nil)
	check("Breakdown: other profession recipe not matched", data.recipes["900"].specBreakdown == nil)
end

do
	local pe = newAddon()
	local data = { specializationTree = tree(2907, 6, 4), recipes = { ["500"] = { spellID = 500 } } }
	pe:AttachSpecCatalogMetadata(data, 164)
	check("Single tree: ranks from the legacy tree", data.specNodeRanksByTier["2907"]["77"] == 5)
	check("Single tree: no primary means empty ranks", next(data.specNodeRanks) == nil)
	check("Single tree: config from the legacy tree", pe.configIDs[500] == 4)
	check("Single tree: rank scales base node", data.recipes["500"].specBreakdown.totals.skill == 10)
end

do
	local pe = newAddon({ ["capture.specBreakdownPerRecipe"] = false })
	local data = professionData()
	pe:AttachSpecCatalogMetadata(data, 164)
	check("Setting off: catalogs still listed", data.specCatalog.byTier["2907"] ~= nil)
	check("Setting off: no recipe breakdowns", data.recipes["500"].specBreakdown == nil)
end

do
	local pe = newAddon()
	local data = { recipes = { ["500"] = { spellID = 500 } } }
	pe:AttachSpecCatalogMetadata(data, 999)
	check("Unknown profession: no catalogs", data.specCatalog.available == false and next(data.specCatalog.byTier) == nil)
	check("Unknown profession: no breakdowns", data.recipes["500"].specBreakdown == nil)
	check("Not a table: passed through", pe:AttachSpecCatalogMetadata("x", 164) == "x")
end

if failed > 0 then
	print(string.format("%d check(s) failed", failed))
	os.exit(1)
end
print("All spec catalog checks passed")
