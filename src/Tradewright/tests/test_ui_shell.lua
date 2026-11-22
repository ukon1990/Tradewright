-- Run with: lua5.1 tests/test_ui_shell.lua (from Tradewright root)
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

local state, professions, lastScanAt, messages = {}, {}, nil, {}
local createdModules = 0
local pe = {
	ui = {},
	db = { characters = {} },
	DASHBOARD_TABS = {
		{ id = "overview", module = function() createdModules = createdModules + 1 return { name = "overview" } end },
		{ id = "docs" },
	},
}
function pe:GetState() return state end
function pe:GetCharacterKey() return "Me" end
function pe:GetPlayerProfessions() return professions end
function pe:GetLastFullAuctionScanAt() return lastScanAt end
function pe:FormatScanTimestamp(at) return "t" .. tostring(at) end
function pe:TableCount(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function pe:Plural(n, word) return n == 1 and word or word .. "s" end
function pe:PrintMessage(text) messages[#messages + 1] = text end
local chunk, err = loadfile(root .. "/../Tradewright_UI/src/ui/Tradewright_UIShell.lua")
assert(chunk, err)
chunk("Tradewright_UI", pe)

-- Activity text
check("activity: no scan yet", pe:GetShellActivityText() == "No full AH scan yet · open the auction house to get prices")
lastScanAt = 50
check("activity: price freshness", pe:GetShellActivityText() == "Prices from full AH scan t50")
state.scanInProgress = true
check("activity: scanning without profession", pe:GetShellActivityText() == "Scanning professions…")
state.currentProfession = { professionName = "Alchemy" }
check("activity: scanning a profession", pe:GetShellActivityText() == "Scanning Alchemy…")
state.scanInProgress = false
local getLast = pe.GetLastFullAuctionScanAt
pe.GetLastFullAuctionScanAt = nil
check("activity: no auction module", pe:GetShellActivityText() == "")
pe.GetLastFullAuctionScanAt = getLast

-- Stored text
check("stored: no professions, no scan note", pe:GetShellStoredText() == "0 characters saved", pe:GetShellStoredText())
professions = { "Alchemy" }
pe.db.characters.Me = {}
check("stored: not scanned yet", pe:GetShellStoredText() == "1 character saved · Professions not scanned yet", pe:GetShellStoredText())
pe.db.characters.Me.scanFinishedAt = 99
check("stored: scan time", pe:GetShellStoredText() == "1 character saved · Professions scanned t99", pe:GetShellStoredText())

-- Layering
local visible = {}
function pe:IsTrackedExternalOwnerVisible(owner) return visible[owner] == true end
check("layer: addon clicked last", pe:ShouldShowAddonForeground({ lastClickedOwner = "addon" }))
check("layer: closed Blizzard window", pe:ShouldShowAddonForeground({ lastClickedOwner = "ProfessionsFrame" }))
visible.ProfessionsFrame = true
check("layer: open Blizzard window clicked last", not pe:ShouldShowAddonForeground({ lastClickedOwner = "ProfessionsFrame" }))

-- Tab modules
local overview = pe:GetDashboardTabModule("overview")
check("module: built from the tab list", overview and overview.name == "overview")
pe:GetDashboardTabModule("overview")
check("module: cached", createdModules == 1)
check("module: tab without module", pe:GetDashboardTabModule("docs") == nil and pe:GetDashboardTabModule("nope") == nil)
check("call: missing method counts as done", pe:CallDashboardTabModule("overview", "Refresh") == true)
function overview:Create() error("boom", 0) end
pe.ui.tabPanels = { overview = {} }
pe:EnsureDashboardTabCreated("overview")
check("create: error is reported", messages[1] == "Tab 'overview' failed to create: boom", messages[1])
check("create: failed tab is retried later", not pe.ui.tabInited.overview)
function overview:Create(panel, ui) self.created = panel == ui.tabPanels.overview end
pe:EnsureDashboardTabCreated("overview")
check("create: module gets its panel", overview.created and pe.ui.tabInited.overview)
function overview:Refresh() error("bad", 0) end
check("refresh: error returns false", pe:CallDashboardTabModule("overview", "Refresh") == false
	and messages[2] == "Tab 'overview' failed to refresh: bad", messages[2])

if failed > 0 then
	print(failed .. " UI shell check(s) failed")
	os.exit(1)
end
print("All UI shell checks passed")
