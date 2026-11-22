local _, Tradewright = ...

-- Farm runs: while a run is active, the player's own loot, looted coin and vendor sales are
-- recorded. This only listens to what the player does; it never moves, loots or sells for them.
-- The run lives in `ledger.farm.current` so it survives a reload; saved runs go to `ledger.farm.farms`.

local IncomeLogic = Tradewright.IncomeLogic
local COIN_WINDOW = 1
local LATEST = 3
local IDLE_CHECK_SEC = 30

local merchantOpen = false
local lootCoinAt, lastMoney
-- GetTime() of the player's last move or loot, nil until the first one; a run pauses itself when
-- that is too long ago.
local lastActiveAt

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
function Tradewright:GetCurrentFarmRun()
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
function Tradewright:StartFarmRun(name)
	local store = farmStore(self)
	if not store then
		return nil
	end
	if not store.current then
		store.current = newRun(self, name)
		lastActiveAt = GetTime()
		if self.ShowFarmWindow and self:GetSetting("farm.showWindow", true) then
			self:ShowFarmWindow()
		end
		changed(self)
	end
	return store.current
end

--- Pause or resume the run; paused time is not counted.
function Tradewright:ToggleFarmPause()
	local run = self:GetCurrentFarmRun()
	if not run then
		return
	end
	if run.pausedAt then
		run.pausedSeconds = (run.pausedSeconds or 0) + math.max(0, time() - run.pausedAt)
		run.pausedAt, run.pausedForIdling = nil, nil
		lastActiveAt = GetTime()
	else
		run.pausedAt = time()
	end
	changed(self)
end

-- Moving or looting: a run that paused itself for idling carries on.
local function noteActivity(pe)
	lastActiveAt = GetTime()
	local run = pe:GetCurrentFarmRun()
	if run and run.pausedForIdling then
		pe:ToggleFarmPause()
	end
end

-- Pauses the run once the player has stood still, looting nothing, for the minutes chosen in
-- Settings (0 turns it off). The idle time itself is not farming either, so the pause starts
-- where the idling did.
local function pauseWhenIdle(pe)
	local run = activeRun(pe)
	local limit = (tonumber(pe:GetSetting("farm.idlePauseMinutes", 5)) or 0) * 60
	lastActiveAt = lastActiveAt or GetTime()
	local idle = GetTime() - lastActiveAt
	if run and limit > 0 and idle >= limit then
		run.pausedAt = math.max(tonumber(run.startedAt) or 0, time() - math.floor(idle))
		run.pausedForIdling = true
		changed(pe)
	end
end

--- Price facts for the farm value rule: vendor price, usual price and sales a day of an item.
function Tradewright:GetFarmItemPrice(itemID)
	local usual, sells
	if self.GetItemPriceSignals then
		usual, sells = self:GetItemPriceSignals(itemID)
	end
	return { vendor = self:GetItemVendorSellCopper(itemID), usual = usual and usual.usual, sellsPerDay = sells and sells.perDay }
end

--- Value of a run at today's prices (see FarmLogic.SummarizeRun).
function Tradewright:SummarizeFarmRun(run)
	local cut = self:GetAuctionCut()
	return self.FarmLogic.SummarizeRun(run, function(itemID)
		return self:GetFarmItemPrice(itemID)
	end, time(), { cut = cut })
end

--- Stop the run and save it under `name` (default: the name it was started with); a farm of that
--- name gets one more run. Returns the summary.
function Tradewright:StopFarmRun(name)
	local store = farmStore(self)
	local run = store and store.current
	if not run then
		return nil
	end
	name = self:Trim(name or "")
	run.name = name ~= "" and name or run.name
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

--- Throw the run in progress away without saving it.
function Tradewright:DiscardFarmRun()
	local store = farmStore(self)
	if store and store.current then
		store.current = nil
		changed(self)
	end
end

--- Saved farms as table rows, each with its summary at today's prices (see FarmLogic.SummarizeFarm).
--- With `days` only runs from the last that many days count, and farms without one are left out.
function Tradewright:GetFarmRows(days)
	local store = farmStore(self)
	local opts = { cut = self:GetAuctionCut(), since = days and days > 0 and (time() - days * 86400) or nil }
	local rows = {}
	for name, farm in pairs(store and store.farms or {}) do
		local row = self.FarmLogic.SummarizeFarm(farm, function(itemID)
			return self:GetFarmItemPrice(itemID)
		end, opts)
		if row.runs > 0 then
			row.name, row.zone, row._rowIdentity = name, farm.zone or "", name
			rows[#rows + 1] = row
		end
	end
	return rows
end

--- Rename a saved farm; a farm already called `newName` takes its runs. Returns whether it changed.
function Tradewright:RenameFarm(oldName, newName)
	local store = farmStore(self)
	return store ~= nil and self.FarmLogic.RenameFarm(store.farms, oldName, self:Trim(newName or ""))
end

--- Remove a saved farm and all its runs.
function Tradewright:DeleteFarm(name)
	local store = farmStore(self)
	if store then
		store.farms[name] = nil
	end
end

local function onLoot(pe, message)
	local run = activeRun(pe)
	local kind, itemID, quantity = IncomeLogic.ParseItemMessage(tostring(message or ""), LOOT_PATTERNS)
	if not (run and kind and itemID) then
		return
	end
	quantity = tonumber(quantity) or 1
	run.items[itemID] = (run.items[itemID] or 0) + quantity
	lastActiveAt = GetTime()
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
	local run = merchantOpen and activeRun(Tradewright)
	if not (run and C_Container and C_Container.GetContainerItemInfo) then
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info and info.itemID then
		Tradewright.FarmLogic.RemoveItems(run, info.itemID, info.stackCount or 1)
	end
end

local idleTicker

-- Entering the world happens on every loading screen; the idle check starts on the first.
local function onEnteringWorld(pe)
	lastMoney = GetMoney()
	idleTicker = idleTicker or C_Timer.NewTicker(IDLE_CHECK_SEC, function() pauseWhenIdle(pe) end)
end

local HANDLERS = {
	CHAT_MSG_LOOT = function(pe, message) onLoot(pe, message) end,
	CHAT_MSG_MONEY = function() lootCoinAt = GetTime() end,
	PLAYER_MONEY = function(pe) onMoney(pe) end,
	PLAYER_ENTERING_WORLD = onEnteringWorld,
	MERCHANT_SHOW = function() merchantOpen = true end,
	MERCHANT_CLOSED = function() merchantOpen = false end,
	PLAYER_STARTED_MOVING = function(pe) noteActivity(pe) end,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, message)
	if Tradewright.db then
		HANDLERS[event](Tradewright, message)
	end
end)
for event in pairs(HANDLERS) do
	pcall(frame.RegisterEvent, frame, event)
end
if hooksecurefunc and C_Container and C_Container.UseContainerItem then
	hooksecurefunc(C_Container, "UseContainerItem", onBagItemUsed)
end

local function farmSlash(input)
	local pe = Tradewright
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

SLASH_TWFARM1 = "/twfarm"
SlashCmdList["TWFARM"] = farmSlash
