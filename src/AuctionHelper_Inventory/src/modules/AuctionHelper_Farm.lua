local _, ProfessionExporter = ...

-- Farm runs (E09 F70): while a run is active, the player's own loot, looted coin and vendor sales are
-- recorded. This only listens to what the player does; it never moves, loots or sells for them.
-- The run lives in `ledger.farm.current` so it survives a reload; saved runs go to `ledger.farm.farms`.

local IncomeLogic = ProfessionExporter.IncomeLogic
local COIN_WINDOW = 1
local LATEST = 3

local merchantOpen = false
local lootCoinAt, lastMoney

local LOOT_PATTERNS = {}
for _, format in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF }) do
	if type(format) == "string" then
		LOOT_PATTERNS[#LOOT_PATTERNS + 1] = { IncomeLogic.FormatToPattern(format), "loot" }
	end
end

local function farmStore(pe)
	local L = pe:InitLedger()
	if not L then
		return nil
	end
	L.farm = L.farm or { farms = {} }
	return L.farm
end

--- The run in progress (possibly paused), or nil.
function ProfessionExporter:GetCurrentFarmRun()
	local store = farmStore(self)
	return store and store.current or nil
end

local function activeRun(pe)
	local run = pe:GetCurrentFarmRun()
	if run and not run.pausedAt then
		return run
	end
	return nil
end

local function changed(pe)
	if pe.RefreshFarmWindow then
		pe:RefreshFarmWindow()
	end
end

local function newRun(pe, name)
	local zone = GetRealZoneText and GetRealZoneText() or ""
	name = pe:Trim(name or "")
	if name == "" then
		name = zone ~= "" and zone or "Farm"
	end
	return { name = name, zone = zone, startedAt = time(), pausedSeconds = 0, coin = 0, vendorSold = 0, items = {}, latest = {} }
end

--- Start a run named `name` (default: the zone). Does nothing while a run is in progress.
function ProfessionExporter:StartFarmRun(name)
	local store = farmStore(self)
	if not store then
		return nil
	end
	if not store.current then
		store.current = newRun(self, name)
		if self.ShowFarmWindow and self:GetSetting("farm.showWindow", true) then
			self:ShowFarmWindow()
		end
		changed(self)
	end
	return store.current
end

--- Pause or resume the run; paused time is not counted.
function ProfessionExporter:ToggleFarmPause()
	local run = self:GetCurrentFarmRun()
	if not run then
		return
	end
	if run.pausedAt then
		run.pausedSeconds = (run.pausedSeconds or 0) + math.max(0, time() - run.pausedAt)
		run.pausedAt = nil
	else
		run.pausedAt = time()
	end
	changed(self)
end

--- Price facts for the farm value rule: vendor price, usual price and sells a day of an item.
function ProfessionExporter:GetFarmItemPrice(itemID)
	local usual, sells
	if self.GetItemPriceSignals then
		usual, sells = self:GetItemPriceSignals(itemID)
	end
	return { vendor = self:GetItemVendorSellCopper(itemID), usual = usual and usual.usual, sellsPerDay = sells and sells.perDay }
end

--- Value of a run at today's prices (see FarmLogic.SummarizeRun).
function ProfessionExporter:SummarizeFarmRun(run)
	local cut = self.GetCraftsAhCutFraction and self:GetCraftsAhCutFraction() or 0.05
	return self.FarmLogic.SummarizeRun(run, function(itemID)
		return self:GetFarmItemPrice(itemID)
	end, time(), { cut = cut })
end

--- Stop the run and save it under its name; a farm of that name gets one more run. Returns the summary.
function ProfessionExporter:StopFarmRun()
	local store = farmStore(self)
	local run = store and store.current
	if not run then
		return nil
	end
	if run.pausedAt then
		self:ToggleFarmPause()
	end
	run.endedAt = time()
	local summary = self:SummarizeFarmRun(run)
	local farm = store.farms[run.name] or { zone = run.zone, runs = {} }
	farm.runs[#farm.runs + 1] = {
		items = run.items, coin = run.coin, vendorSold = run.vendorSold,
		activeSeconds = summary.activeSeconds, endedAt = run.endedAt, valueWhenSaved = summary.total,
	}
	store.farms[run.name] = farm
	store.current = nil
	changed(self)
	return summary, run
end

local function onLoot(pe, message)
	local run = activeRun(pe)
	local kind, itemID, quantity = IncomeLogic.ParseItemMessage(tostring(message or ""), LOOT_PATTERNS)
	if not (run and kind and itemID) then
		return
	end
	quantity = tonumber(quantity) or 1
	run.items[itemID] = (run.items[itemID] or 0) + quantity
	table.insert(run.latest, 1, { itemID = itemID, qty = quantity })
	run.latest[LATEST + 1] = nil
	changed(pe)
end

-- Gold gained with a merchant open is a vendor sale; gold gained right around a "You loot" coin
-- message is looted coin. Mail, auction, trade and quest gold match neither and is ignored.
local function onMoney(pe)
	local money = GetMoney()
	local delta = lastMoney and money - lastMoney or 0
	lastMoney = money
	local run = activeRun(pe)
	if not run or delta <= 0 then
		return
	end
	if merchantOpen then
		run.vendorSold = run.vendorSold + delta
		changed(pe)
		return
	end
	local changeAt = GetTime()
	C_Timer.After(COIN_WINDOW, function()
		if lootCoinAt and math.abs(lootCoinAt - changeAt) <= COIN_WINDOW and pe:GetCurrentFarmRun() == run then
			run.coin = run.coin + delta
			changed(pe)
		end
	end)
end

-- Selling a looted item to a vendor: its gold is counted as a vendor sale, so it leaves the item list.
local function onBagItemUsed(bag, slot)
	local run = merchantOpen and activeRun(ProfessionExporter)
	if not (run and C_Container and C_Container.GetContainerItemInfo) then
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info and info.itemID then
		ProfessionExporter.FarmLogic.RemoveItems(run, info.itemID, info.stackCount or 1)
	end
end

local HANDLERS = {
	CHAT_MSG_LOOT = function(pe, message) onLoot(pe, message) end,
	CHAT_MSG_MONEY = function() lootCoinAt = GetTime() end,
	PLAYER_MONEY = function(pe) onMoney(pe) end,
	PLAYER_ENTERING_WORLD = function() lastMoney = GetMoney() end,
	MERCHANT_SHOW = function() merchantOpen = true end,
	MERCHANT_CLOSED = function() merchantOpen = false end,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, message)
	if ProfessionExporter.db then
		HANDLERS[event](ProfessionExporter, message)
	end
end)
for event in pairs(HANDLERS) do
	pcall(frame.RegisterEvent, frame, event)
end
if hooksecurefunc and C_Container and C_Container.UseContainerItem then
	hooksecurefunc(C_Container, "UseContainerItem", onBagItemUsed)
end

local function farmSlash(input)
	local pe = ProfessionExporter
	local command, rest = pe:Trim(input or ""):match("^(%S*)%s*(.*)$")
	if command == "start" then
		pe:StartFarmRun(rest)
	elseif command == "pause" then
		pe:ToggleFarmPause()
	elseif command == "stop" then
		pe:StopFarmRun()
	elseif pe.ToggleFarmWindow then
		pe:ToggleFarmWindow()
	end
end

SLASH_AHFARM1 = "/ahfarm"
SlashCmdList["AHFARM"] = farmSlash
