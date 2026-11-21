-- Run with: lua5.1 tests/test_overview_tab.lua (from AuctionHelper root)
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

local ACCT = "__ACCOUNT__"
local state, gold, currentKey, keyList = {}, {}, "Me", {}
local pe = { DASHBOARD_ACCOUNT_KEY = ACCT, ui = {}, db = { characters = {}, aggregate = { updatedAt = 1 } } }
function pe:GetState() return state end
function pe:GetCharacterKey() return currentKey end
function pe:GetDashboardCharacterKeyList() return keyList end
function pe:GetCurrentGoldSummaryForOverview(key) return gold[key] end
function pe:Plural(n, word) return n == 1 and word or word .. "s" end
function pe:TableCount(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function pe:FormatCopperShort(c) return c .. "c" end
function pe:FormatNumberGrouped(n) return tostring(n) end
function pe:FormatScanTimestamp(at) return "t" .. tostring(at) end
local chunk, err = loadfile(root .. "/../AuctionHelper_UI/src/ui/AuctionHelper_OverviewTab.lua")
assert(chunk, err)
chunk("AuctionHelper_UI", pe)
local OverviewTab = pe.OverviewTab

-- Stats cards
local function card()
	return { SetValues = function(self, ...) self.values = { ... } end }
end
local panel = { stats = { characters = card(), gold = card(), itemTypes = card(), professionScan = card() } }
pe.db.characters = {
	Me = { meta = { name = "Me" }, professions = { a = {}, b = {} } },
	Alt = { professions = { c = {} } },
}
gold[ACCT], gold.Me = 500, 300
OverviewTab:RefreshStats(panel, ACCT, pe.db.aggregate, { "Me", "Alt" })
local scan = panel.stats.professionScan.values
check("account counts every profession", scan[2] == "Ready" and scan[3] == "3 professions stored" and scan[4] == "success", scan[3])
check("account gold detail spans characters", panel.stats.gold.values[3] == "Across 2 characters", panel.stats.gold.values[3])
check("account gold value", panel.stats.gold.values[2] == "500c")
OverviewTab:RefreshStats(panel, "Me", pe.db.characters.Me, { "Me", "Alt" })
check("character gold detail", panel.stats.gold.values[3] == "Me has 300c", panel.stats.gold.values[3])
check("character profession count", panel.stats.professionScan.values[3] == "2 professions stored")
OverviewTab:RefreshStats(panel, "Alt", pe.db.characters.Alt, { "Me", "Alt" })
check("character without gold falls back", panel.stats.gold.values[3] == "Across 2 characters")
state.scanInProgress, state.queue = true, { 1, 2 }
OverviewTab:RefreshStats(panel, "Me", pe.db.characters.Me, { "Me" })
scan = panel.stats.professionScan.values
check("scan in progress", scan[2] == "Scanning" and scan[3] == "starting, 2 left" and scan[4] == "warning", scan[3])
gold[ACCT] = 0
OverviewTab:RefreshStats(panel, ACCT, pe.db.aggregate, {})
check("no account gold shows dash", panel.stats.gold.values[2] == "-")

-- Selection
local seen
local function button() return { SetEnabled = function(self, on) self.enabled = on end } end
local selectionPanel = { refreshInvButton = button(), exportCharacterButton = button() }
function OverviewTab:RefreshStats(_, key, data) seen = { key = key, data = data } end
function OverviewTab:RefreshCharacterList() end
function OverviewTab:RefreshDetail() end
function OverviewTab:RefreshGold() end
function OverviewTab:Layout() end
local function selectedAfter(saved)
	pe.ui.selectedCharacterKey = saved
	OverviewTab:RefreshCharactersView(selectionPanel)
	return seen.key, pe.ui.selectedCharacterKey
end
keyList = { "Alt", "Me" }
check("keeps a saved character", selectedAfter("Alt") == "Alt" and selectionPanel.refreshInvButton.enabled == false)
check("keeps the account", selectedAfter(ACCT) == ACCT and seen.data == pe.db.aggregate)
local key, stored = selectedAfter("Gone")
check("unknown falls back to this character", key == "Me" and stored == "Me" and selectionPanel.exportCharacterButton.enabled == true)
currentKey = "New"
check("then the first stored character", selectedAfter(nil) == "Alt")
keyList, pe.db.characters = {}, {}
key, stored = selectedAfter(nil)
check("then the account", key == ACCT and stored == ACCT)

if failed > 0 then
	print(failed .. " overview tab check(s) failed")
	os.exit(1)
end
print("All overview tab checks passed")
