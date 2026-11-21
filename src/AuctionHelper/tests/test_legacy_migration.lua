-- Run with: lua5.1 tests/test_legacy_migration.lua (from AuctionHelper root); npm test runs it too.
-- The one-time import of saved data from the addon's old name, ProfessionExporter.
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

_G.GetBuildInfo = function() return "1.16.1", "1", "", 16001 end
_G.time = function() return 1700000000 end
_G.CreateFrame = function() return {} end

local pe = {}
for _, path in ipairs({
	"AuctionHelper/src/core/AuctionHelper.lua",
	"AuctionHelper/src/core/AuctionHelper_DataInit.lua",
}) do
	local chunk, err = loadfile(repo .. "/" .. path)
	assert(chunk, err)
	chunk("AuctionHelper", pe)
end

local function freshStorage()
	AuctionHelperMigrationDB = nil
	AuctionHelperLastExport = nil
	return { settings = {} }, {}, {}, {}
end

-- Old data moves into empty new storage
local baseDb, professionsDb, inventoryDb, auctionDb = freshStorage()
ProfessionExporterDB = {
	settings = { minProfitCopper = 500 },
	characters = { ["Alice"] = { level = 60 } },
	ledger = { { kind = "sale" } },
	auction = { snapshot = { ["2589"] = { p = 100 } } },
}
ProfessionExporterLastExport = { json = "{}" }
check("Import runs when old data exists", pe:RunLegacyMigrationIfNeeded(baseDb, professionsDb, inventoryDb, auctionDb) == true)
check("Settings are adopted", baseDb.settings.minProfitCopper == 500)
check("Profession data is adopted", professionsDb.characters.Alice.level == 60)
check("Inventory ledger is adopted", inventoryDb.ledger[1].kind == "sale")
check("Auction data is adopted", auctionDb.auction.snapshot["2589"].p == 100)
check("Old export becomes the payload", AuctionHelperLastExport.payload == "{}" and AuctionHelperLastExport.format == "legacy-json")
check("Old saved variables are cleared", ProfessionExporterDB == nil and ProfessionExporterLastExport == nil)
check("Import is marked done", AuctionHelperMigrationDB.professionExporterImported == true)

-- A second run does nothing, even if old data shows up again
ProfessionExporterDB = { settings = { minProfitCopper = 1 } }
check("Second run does nothing", pe:RunLegacyMigrationIfNeeded(baseDb, professionsDb, inventoryDb, auctionDb) == false)
check("Second run keeps the imported settings", baseDb.settings.minProfitCopper == 500)

-- Existing new data is never overwritten
baseDb, professionsDb, inventoryDb, auctionDb = freshStorage()
baseDb.settings = { minProfitCopper = 900 }
professionsDb.characters = { ["Bob"] = { level = 70 } }
auctionDb.auction = { snapshot = { ["1"] = { p = 5 } } }
ProfessionExporterDB = {
	settings = { minProfitCopper = 500 },
	characters = { ["Alice"] = { level = 60 } },
	auction = { snapshot = { ["2589"] = { p = 100 } } },
}
pe:RunLegacyMigrationIfNeeded(baseDb, professionsDb, inventoryDb, auctionDb)
check("New settings win over old ones", baseDb.settings.minProfitCopper == 900)
check("New profession data wins", professionsDb.characters.Bob and not professionsDb.characters.Alice)
check("New auction data wins", auctionDb.auction.snapshot["1"] and not auctionDb.auction.snapshot["2589"])

-- Nothing to import
baseDb, professionsDb, inventoryDb, auctionDb = freshStorage()
ProfessionExporterDB, ProfessionExporterLastExport = nil, nil
check("No old data, no import", pe:RunLegacyMigrationIfNeeded(baseDb, professionsDb, inventoryDb, auctionDb) == false)

if failed > 0 then
	print(failed .. " legacy migration check(s) failed")
	os.exit(1)
end
print("All legacy migration checks passed")
