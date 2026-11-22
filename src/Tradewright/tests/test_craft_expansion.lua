-- Run with: lua5.1 tests/test_craft_expansion.lua (from Tradewright root)
-- The expansion of a craft must not depend on the client language: names are translated, IDs are not.
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

local itemExpansion = {}
local pe = {}
function pe:ResolveItemDescriptor(itemID) return itemExpansion[itemID] and { expansionID = itemExpansion[itemID] } or nil end
function pe:ExpansionLeToFilterTag(expansionID) return ({ [9] = "df", [10] = "tww", [11] = "midnight" })[expansionID] or "legacy" end
local chunk, err = loadfile(root .. "/../Tradewright_Professions/src/modules/Tradewright_CraftsEngine.lua")
assert(chunk, err)
chunk("Tradewright_Professions", pe)

local function tag(professionData, itemID) return pe:GetCraftExpansionTag(professionData, nil, itemID) end

itemExpansion[100] = 10
check("Output item's expansion wins", tag({ skillLineID = 2906 }, 100) == "tww")

local german = { skillLineID = 171, professionName = "Alchemie", currentLevelName = "Alchemie von Khaz Algar",
	childProfessionInfo = { professionID = 2871, professionName = "Alchemie von Khaz Algar" } }
check("German client: tier by child profession ID", tag(german) == "tww", tag(german))
check("Specialization line", tag({ skillLineID = 164, primarySpecializationSkillLineID = 2907 }) == "midnight")
check("Dragon Isles line", tag({ skillLineID = 2822 }) == "df")
check("Khaz Algar line", tag({ skillLineID = 2883 }) == "tww")
check("Midnight line", tag({ skillLineID = 2918 }) == "midnight")
check("Bare skill line ID", tag(2916) == "midnight")
check("English name alone decides nothing", tag({ skillLineID = 171, professionName = "Midnight Alchemy" }) == "legacy")
check("Base line is older content", tag({ skillLineID = 171 }) == "legacy")
check("No data", tag(nil) == "legacy")

if failed > 0 then
	print(failed .. " craft expansion check(s) failed")
	os.exit(1)
end
print("All craft expansion checks passed")
