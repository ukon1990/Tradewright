-- The /tradewright slash commands, status line, and Export() — the export run that slash and the Export tab start.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Export scope -> what the progress window calls it. Profession slices fill in the profession at %s.
local EXPORT_SCOPE_LABELS = {
	account = "account", account_summary = L["account summary"],
	professions = L["professions (character)"], professions_compact = L["professions compact"],
	professions_recipes = L["professions recipes (character)"], professions_talents = L["professions talents (character)"],
	inventory = L["inventory (character)"], inventory_compact = L["inventory compact"],
	auction_snapshot = L["auction snapshot"], auction_history = L["auction history"], crafting_costs = L["crafting costs"],
	spec_catalog = L["spec catalog (Midnight bundled)"], character_meta = L["character meta"],
	profession = L["profession (%s)"], profession_recipes = L["profession recipes (%s)"], profession_talents = L["profession talents (%s)"],
}

local function exportScopeLabel(scope, identifier)
	local label = EXPORT_SCOPE_LABELS[scope]
	return label and string.format(label, tostring(identifier or "?")) or tostring(scope or "character")
end

function Tradewright:Export(scope, identifier)
	local st = self:GetState()
	if st.exportJsonBusy then
		self:PrintMessage(L["Export already in progress."])
		return
	end

	self:ShowExportProgress(exportScopeLabel(scope, identifier))

	local dbg = self:IsDebugEnabled()
	debugprofilestart()
	local exportData, err = self:GetExportData(scope, identifier)
	local msGather = debugprofilestop()
	if not exportData then
		self:HideExportProgress()
		self:PrintMessage(err or L["Nothing to export."])
		return
	end

	local meta = exportData.meta or {}
	st.exportJsonBusy = true
	self:SetExportProgressPhase(L["Packing the export"], true)
	self:UpdateExportProgressSteps(1)
	debugprofilestart()
	local payload, encodeErr = self:BuildCompactExportPayload(exportData)
	local msEncode = debugprofilestop()
	self:HideExportProgress(payload and not encodeErr)
	st.exportJsonBusy = false

	if encodeErr or not payload then
		self:PrintMessage(string.format(L["Package export failed: %s"], tostring(encodeErr or "unknown error")))
		if dbg then
			self:PrintMessage(string.format(L["Export timing: gather=%.1fms pack=%.1fms (failed)"], msGather, msEncode))
		end
		return
	end

	if #payload > self.MAX_EXPORT_BYTES then
		self:PrintMessage(string.format(L["Compressed export is %d bytes. Use a smaller scope if needed."], #payload))
	end

	local savedOk = self:SaveExportToSavedVariables(payload, meta)
	local unsavedHint
	if not savedOk and #payload > self.MAX_SAVEDEXPORT_BYTES then
		unsavedHint = string.format(L["Full compressed export was not saved (over %d byte SavedVariables limit). Try smaller scopes"]
			.. " such as professions_recipes, profession_talents, inventory, or a single profession.", self.MAX_SAVEDEXPORT_BYTES)
	end

	debugprofilestart()
	self:ShowCopyBox(payload, { fullByteLength = #payload, savedToVariables = savedOk, unsavedHint = unsavedHint })
	local msUi = debugprofilestop()

	if dbg then
		self:PrintMessage(string.format(L["Export timing: gather=%.1fms pack=%.1fms copyUI=%.1fms (package %d bytes)"],
			msGather, msEncode, msUi, #payload))
	end

	local formatLabel = (meta and meta.format) or (type(payload) == "string" and payload:sub(1, 7) == "AHLUA1:" and "AHLUA1") or self.EXPORT_FORMAT or "AHCBOR1"
	self:PrintMessage(string.format(L["Exported %s package (%d bytes, %s)."], tostring(meta.scope or scope or "character"), #payload, formatLabel))
	if savedOk then
		self:PrintMessage("Compressed export queued for SavedVariables — |cffffffff/reload|r or log out to write WTF\\Account\\…\\SavedVariables\\Tradewright.lua (TradewrightLastExport.payload).")
	elseif #payload > self.MAX_SAVEDEXPORT_BYTES then
		self:PrintMessage(L["SavedVariables copy skipped (compressed export still exceeds size limit)."])
	end
end

function Tradewright:PrintStatus()
	self:InitDB()
	local characterKey = self:GetCharacterKey()
	local characterData = self.db.characters[characterKey]
	local state = self:GetState()

	if state.scanInProgress then
		local currentName = state.currentProfession and state.currentProfession.professionName or "pending"
		self:PrintMessage(string.format(L["Scanning %s. %d professions left."], currentName, #state.queue))
		return
	end

	if not characterData then
		self:PrintMessage(L["No saved scan for this character yet."])
		return
	end

	self:PrintMessage(string.format(L["Last scan for %s finished at %s with %d professions."],
		characterKey,
		date("%Y-%m-%d %H:%M:%S", characterData.scanFinishedAt or 0),
		self:TableCount(characterData.professions)))
end

local ON_OFF_ARGS = { on = true, ["1"] = true, ["true"] = true, off = false, ["0"] = false, ["false"] = false }

-- `/tradewright settings <usageName> on|off` for one boolean setting.
local function onOffSetting(key, default, usageName, label)
	return function(self, arg)
		local value = ON_OFF_ARGS[arg]
		if value == nil then
			self:PrintMessage(string.format("Usage: /tw settings %s on|off", usageName))
			return
		end
		self:SetSetting(key, value)
		self:PrintMessage(string.format("%s: %s.", label, self:GetSetting(key, default) and "on" or "off"))
	end
end

local setSpecTreeCapture = onOffSetting("capture.captureSpecializationTree", true, "spectree", "Specialization tree capture")
local setRecipeOutputCapture = onOffSetting("capture.includeRecipeOutputItemData", false, "recipeoutput", "Recipe output item API dump")

local function setInventoryBatchSize(self, arg)
	local size = tonumber(arg)
	if not size or size < 0 then
		self:PrintMessage("Usage: /tw settings invbatch <n>  (0 = one frame; 50–100 spreads GetItemCount work)")
		return
	end
	self:SetSetting("capture.inventorySnapshotBatchSize", math.floor(size))
	self:PrintMessage(string.format(L["Inventory snapshot batch size: %d."], self:GetSetting("capture.inventorySnapshotBatchSize", 0)))
end

-- `/tradewright settings <sub> <arg>` (sub lower-cased) -> handler(self, arg).
local SETTINGS_SUBCOMMANDS = {
	spectree = setSpecTreeCapture, specialization = setSpecTreeCapture,
	recipeoutput = setRecipeOutputCapture, rawoutput = setRecipeOutputCapture,
	invbatch = setInventoryBatchSize, inventorybatch = setInventoryBatchSize,
}

function Tradewright:HandleSettingsSlash(rest)
	self:InitDB()
	local sub, arg = rest:match("^(%S+)%s*(.*)$")
	local handler = SETTINGS_SUBCOMMANDS[string.lower(sub or "")]
	if handler then
		handler(self, self:Trim(arg or ""))
		return
	end
	self:PrintMessage("Usage: /tw settings spectree on|off | recipeoutput on|off | invbatch <n>")
end

-- The auction subcommand handlers return true when they ran; false falls through to the usage line.
local function printAuctionStatus(self)
	local enabled = self:GetSetting("auction.enabled", true)
	local rows = self.BuildAuctionInventoryRows and self:BuildAuctionInventoryRows() or {}
	self:PrintMessage(string.format(L["Auction data is %s. %d items in the sell list."], enabled and "on" or "off", #rows))
	return true
end

local function setAuctionModuleEnabled(self, enabled)
	self:SetSetting("auction.enabled", enabled)
	self:PrintMessage(enabled and L["Auction data switched on."] or L["Auction data switched off."])
	return true
end

local function refreshAuctionPrices(self, target)
	target = string.lower(target)
	if (target == "crafts" or target == "craft") and self.QueueCraftEconomyAuctionRefresh then
		self:QueueCraftEconomyAuctionRefresh({})
		self:PrintMessage(L["Checking craft prices."])
		return true
	end
	if self.BuildAuctionVisibleItemIDs and self.QueueVisibleAuctionRefresh then
		self:QueueVisibleAuctionRefresh(self:BuildAuctionVisibleItemIDs())
		self:PrintMessage(L["Checking the shown prices."])
		return true
	end
	return false
end

local function runAuctionDump(self, mode)
	if not self.StartAuctionDump then
		return false
	end
	self:RunAuctionDumpSlash(mode)
	return true
end

-- `/tradewright auction <sub> <arg>` (sub lower-cased) -> handler(self, arg).
local AUCTION_SUBCOMMANDS = {
	[""] = printAuctionStatus, status = printAuctionStatus,
	enable = function(self) return setAuctionModuleEnabled(self, true) end,
	disable = function(self) return setAuctionModuleEnabled(self, false) end,
	refresh = refreshAuctionPrices,
	dump = runAuctionDump,
}

function Tradewright:HandleAuctionSlash(rest)
	local sub, arg = self:Trim(rest or ""):match("^(%S+)%s*(.*)$")
	local handler = AUCTION_SUBCOMMANDS[string.lower(sub or "")]
	if handler and handler(self, self:Trim(arg or "")) then
		return
	end
	self:PrintMessage("Usage: /tw auction [status|enable|disable|refresh [crafts]|dump [visible|full]]")
end

--- The dump runs asynchronously and prints its own "complete" line when it ends. When it refuses
--- to start, StartAuctionDump prints why; an empty dump finishes at once and is not "started".
function Tradewright:RunAuctionDumpSlash(mode)
	mode = mode ~= "" and mode or "visible"
	local dump = self:StartAuctionDump(mode) and self:GetState().auctionDump
	if dump and dump.running == true then
		self:PrintMessage(mode == "full" and L["Full scan started."] or L["Saving the shown prices."])
	end
end

local SLASH_HELP_LINES = {
	"/tw opens the window (/tradewright works too) | /tw scan: scan your professions | /tw status: the last scan"
		.. " | /tw bags on|off: Tradewright bags | /twfarm start|pause|stop: run a farm | /tw docs: open Help"
		.. " | /tw intro: show Get started",
	"Advanced: /tw debug [on|off|toggle] | /tw settings spectree on|off | recipeoutput on|off | invbatch <n>"
		.. " | /tw auction status|enable|disable|refresh [crafts]|dump [visible|full] | /tw sources [seal] | /tw intro reset",
}

-- Shown in help only while export is switched on; the format itself is described in docs/export-format.md.
local EXPORT_HELP_LINES = {
	"Export: /tw export … | /tw full (fresh scan, then full character export) | /tw dev export off",
	"Export scopes: character | account | account_summary | professions | professions_recipes | professions_talents"
		.. " | professions_compact | inventory | inventory_compact | auction_snapshot | auction_history | crafting_costs"
		.. " | spec_catalog | meta | profession <id|name> | profession_recipes <id|name> | profession_talents <id|name>",
}

local EXPORT_USAGE = "Usage: /tw export [character|account|account_summary|professions|professions_recipes"
	.. "|professions_talents|professions_compact|inventory|inventory_compact|auction_snapshot|auction_history|crafting_costs"
	.. L["|spec_catalog|meta|profession <id|name>|profession_recipes <id|name>|profession_talents <id|name>]"]

-- `/tradewright export <arg>` (lower-cased) -> export scope.
local EXPORT_SCOPE_BY_ARG = {
	[""] = "character", character = "character",
	account = "account",
	account_summary = "account_summary", summary = "account_summary", aggregates = "account_summary", aggregate = "account_summary",
	professions = "professions",
	professions_recipes = "professions_recipes",
	professions_talents = "professions_talents",
	professions_compact = "professions_compact", profcompact = "professions_compact",
	inventory = "inventory", items = "inventory",
	inventory_compact = "inventory_compact", invcompact = "inventory_compact",
	auction_snapshot = "auction_snapshot", auctionsnapshot = "auction_snapshot",
	auction_history = "auction_history", auctionhistory = "auction_history",
	crafting_costs = "crafting_costs", craftcosts = "crafting_costs",
	spec_catalog = "spec_catalog", speccatalog = "spec_catalog", spec_catalog_midnight = "spec_catalog",
	meta = "character_meta", charmeta = "character_meta", character_meta = "character_meta",
}

local function handleExportSlash(self, rest)
	local scope = EXPORT_SCOPE_BY_ARG[string.lower(rest or "")]
	if scope then
		self:Export(scope)
		return
	end
	local sliceScope, identifier = rest:match("^(%S+)%s+(.+)$")
	sliceScope = string.lower(sliceScope or "")
	if (sliceScope == "profession_recipes" or sliceScope == "profession_talents") and identifier then
		self:Export(sliceScope, self:Trim(identifier))
		return
	end
	if sliceScope == "profession" and identifier then
		self:Export("profession", identifier)
		return
	end
	self:PrintMessage(EXPORT_USAGE)
end

--- Export is a developer tool for the author's own scripts, so players never see it unless they switch it on.
function Tradewright:IsExportEnabled()
	return self:GetSetting("developer.export", false) == true
end

function Tradewright:SetExportEnabled(enabled)
	self:SetSetting("developer.export", enabled)
	self:PrintMessage(enabled and L["Export switched on: Export tab and /tw export."] or L["Export switched off."])
	if self.ApplyDashboardTabVisibility then
		self:ApplyDashboardTabVisibility()
	end
end

local EXPORT_OFF_HINT = L["Export is switched off. Turn it on with /tw dev export on."]

-- Runs `handler` only while export is switched on.
local function whenExportEnabled(handler)
	return function(self, rest)
		if not self:IsExportEnabled() then
			self:PrintMessage(EXPORT_OFF_HINT)
			return
		end
		handler(self, rest)
	end
end

-- `/tradewright dev export on|off`.
local function handleDeveloperSlash(self, rest)
	local feature, arg = self:Trim(rest or ""):match("^(%S+)%s*(.*)$")
	local value = ON_OFF_ARGS[string.lower(arg or "")]
	if string.lower(feature or "") ~= "export" or value == nil then
		self:PrintMessage(string.format("Usage: /tw dev export on|off  (now %s)", self:IsExportEnabled() and "on" or "off"))
		return
	end
	self:SetExportEnabled(value)
end

local function setDebugOn(self)
	self:SetDebugEnabled(true)
end

local function setDebugOff(self)
	self:SetDebugEnabled(false)
end

local function clearDebugLog(self)
	self:ClearDebugLog()
	self:PrintMessage(L["Persistent debug log cleared."])
end

local function printDebugLogPath(self)
	self:PrintMessage(L["Persistent debug log is saved in TradewrightDB.settings.debug.lines and written to"]
		.. " WTF\\Account\\...\\SavedVariables\\Tradewright.lua on /reload or logout.")
end

local function printDebugStatus(self)
	self:InitDB()
	local count = self.db and self.db.debug and self.db.debug.lines and #self.db.debug.lines or 0
	self:PrintMessage(string.format(L["Debug logging: %s. Persistent lines buffered: %d."], self:IsDebugEnabled() and "on" or "off", count))
end

local function toggleDebug(self)
	self:SetDebugEnabled(not self:IsDebugEnabled())
end

-- `/tradewright debug <sub>` (lower-cased); anything else toggles.
local DEBUG_SUBCOMMANDS = {
	on = setDebugOn, ["1"] = setDebugOn, ["true"] = setDebugOn,
	clear = clearDebugLog, reset = clearDebugLog,
	where = printDebugLogPath, path = printDebugLogPath,
	status = printDebugStatus,
	off = setDebugOff, ["0"] = setDebugOff, ["false"] = setDebugOff,
}

local function handleDebugSlash(self, rest)
	local handler = DEBUG_SUBCOMMANDS[string.lower(rest or "")] or toggleDebug
	handler(self)
	if self.ui and self.ui.mainFrame and self.ui.mainFrame:IsShown() then
		self:RefreshDashboard(true)
	end
end

local function printSlashHelp(self)
	for _, line in ipairs(SLASH_HELP_LINES) do
		self:PrintMessage(line)
	end
	if self:IsExportEnabled() then
		for _, line in ipairs(EXPORT_HELP_LINES) do
			self:PrintMessage(line)
		end
	end
end

local function openDocumentation(self)
	self:OpenDocumentationTab()
end

local function handleAuctionSlash(self, rest)
	self:HandleAuctionSlash(rest)
end

local startFullCharacterDump = whenExportEnabled(function(self)
	self:StartFullCharacterDump()
end)

-- `/tradewright <command> <rest>` (command lower-cased) -> handler(self, rest).
local SLASH_COMMANDS = {
	[""] = function(self) self:ToggleDashboard() end,
	docs = openDocumentation, documentation = openDocumentation,
	intro = function(self, rest) self:HandleGetStartedSlash(rest) end,
	help = printSlashHelp,
	settings = function(self, rest) self:HandleSettingsSlash(rest) end,
	auction = handleAuctionSlash, ah = handleAuctionSlash,
	debug = handleDebugSlash,
	scan = function(self) self:StartScan() end,
	full = startFullCharacterDump, dumpfull = startFullCharacterDump,
	status = function(self) self:PrintStatus() end,
	export = whenExportEnabled(handleExportSlash),
	dev = handleDeveloperSlash, developer = handleDeveloperSlash,
	sources = function(self, rest) self:HandleSourcesSlash(rest) end,
}

function Tradewright:HandleSlash(input)
	input = self:Trim(input)
	local command, rest = input:match("^(%S+)%s*(.-)$")
	command = string.lower(command or "")
	rest = self:Trim(rest)
	local handler = SLASH_COMMANDS[command]
	if handler then
		handler(self, rest)
		return
	end
	self:PrintMessage(L["Unknown command. /tw help lists the commands."])
end
