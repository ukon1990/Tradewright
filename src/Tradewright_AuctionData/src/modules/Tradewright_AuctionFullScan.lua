-- The full scan: starting it, its cooldown, waiting for the server and saving the replicate list in chunks.
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local shared = Tradewright.AuctionShared
local formatDurationShort = shared.formatDurationShort
local normalizeItemID = shared.normalizeItemID

local FULL_AH_DUMP_COOLDOWN_SEC = 15 * 60
local FULL_AH_DUMP_ROW_CHUNK = 250
local FULL_AH_DUMP_PERSIST_CHUNK = 150
local FULL_AH_DUMP_REQUEST_TIMEOUT_SEC = 45
local FULL_AH_DUMP_REQUEST_POLL_SEC = 1

function Tradewright:StopAuctionScanForDump()
	local state = self:GetState()
	local wasRunning = state.auctionRefreshRunning == true
	if wasRunning then
		self:DebugLog("AH", "scan stopped for dump", {
			string.format(L["mode=%s itemID=%s index=%s"], tostring(state.auctionScanMode), tostring(state.auctionActiveItemID), tostring(state.auctionRefreshIndex)),
		})
	end
	state.auctionSearchToken = (tonumber(state.auctionSearchToken) or 0) + 1
	state.auctionRefreshRunning = false
	state.auctionRefreshPaused = false
	state.auctionRefreshPausedForBulk = false
	state.auctionRefreshQueue = {}
	state.auctionRefreshScanList = nil
	state.auctionRefreshIndex = nil
	state.auctionSearchContext = nil
	state.auctionRefreshStartedAt = nil
	if wasRunning and not state.auctionRoiRunning then
		state.auctionScanMode = "idle"
		state.auctionScanTotal = 0
		state.auctionScanDone = 0
		state.auctionActiveItemID = nil
	end
	return wasRunning
end

-- The one record of when this realm's last full scan finished (saved, so it survives
-- /reload and relog). The badge, dashboard, AH panel and the cooldown all read it.
function Tradewright:GetLastFullAuctionScanAt()
	local auction = self:InitAuctionDB()
	local byRealm = auction and auction.lastFullScanAt
	local realmKey = self:GetAuctionRegionKey() .. ":" .. self:GetAuctionConnectedRealmID()
	return type(byRealm) == "table" and tonumber(byRealm[realmKey]) or nil
end

function Tradewright:SetLastFullAuctionScanAt(ts)
	local auction = self:InitAuctionDB()
	if not auction then
		return
	end
	auction.lastFullScanAt = type(auction.lastFullScanAt) == "table" and auction.lastFullScanAt or {}
	auction.lastFullScanAt[self:GetAuctionRegionKey() .. ":" .. self:GetAuctionConnectedRealmID()] = ts
end

--- The server answers one full scan request per cooldown, so the cooldown also runs from the last
--- request. That time is saved too: after a /reload in the middle of a scan the button shows the
--- wait instead of starting a scan the server will not answer.
function Tradewright:SetLastFullAuctionScanRequestAt(ts)
	local auction = self:InitAuctionDB()
	auction.lastFullScanRequestAt = type(auction.lastFullScanRequestAt) == "table" and auction.lastFullScanRequestAt or {}
	auction.lastFullScanRequestAt[self:GetAuctionRegionKey() .. ":" .. self:GetAuctionConnectedRealmID()] = ts
end

-- How long the server makes the player wait between two full scans.
function Tradewright:GetFullScanCooldownSec()
	return FULL_AH_DUMP_COOLDOWN_SEC
end

function Tradewright:GetFullAuctionDumpCooldownRemaining()
	local requests = self:InitAuctionDB().lastFullScanRequestAt
	local requestedAt = type(requests) == "table"
		and tonumber(requests[self:GetAuctionRegionKey() .. ":" .. self:GetAuctionConnectedRealmID()]) or 0
	local lastAt = math.max(self:GetLastFullAuctionScanAt() or 0, requestedAt)
	return math.max(0, lastAt + FULL_AH_DUMP_COOLDOWN_SEC - Tradewright:Now())
end

function Tradewright:IsFullAuctionDumpRunning()
	local dump = self:GetState().auctionDump
	return dump and dump.mode == "full" and dump.running == true
end

function Tradewright:CanStartFullAuctionSideActions(announce)
	if self:IsFullAuctionDumpRunning() then
		if announce then
			self:PrintMessage(L["Full scan in progress. Wait for it to finish before starting another AH scan."])
		end
		return false
	end
	return true
end

function Tradewright:CanUseClassicAuctionDump()
	return type(QueryAuctionItems) == "function"
		and type(GetNumAuctionItems) == "function"
		and type(GetAuctionItemInfo) == "function"
end

function Tradewright:CanUseReplicateAuctionDump()
	return C_AuctionHouse
		and type(C_AuctionHouse.ReplicateItems) == "function"
		and type(C_AuctionHouse.GetNumReplicateItems) == "function"
		and type(C_AuctionHouse.GetReplicateItemInfo) == "function"
end

function Tradewright:FailFullAuctionDump(reason)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" then
		return
	end
	-- Prefer classic paging when replicate fails/times out and classic APIs exist.
	if dump.classic ~= true and self:CanUseClassicAuctionDump() then
		self:PrintMessage(L["Full scan unavailable ("] .. tostring(reason or "unknown") .. L["); reading the auction house page by page instead."])
		local token = tonumber(dump.token)
		dump.running = false
		if self:StartClassicFullAuctionDump(token) then
			return
		end
		-- Fall through and mark failed if classic start also rejected.
		dump = state.auctionDump or dump
	end
	dump.running = false
	dump.status = "failed"
	dump.error = tostring(reason or "unknown")
	dump.finishedAt = Tradewright:Now()
	self:PrintMessage(string.format(L["Full scan failed: %s"], tostring(reason or "unknown")))
	self:RefreshAuctionHousePanel()
end

function Tradewright:FinishFullAuctionDump()
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" then
		return
	end
	dump.running = false
	dump.status = "complete"
	dump.finishedAt = Tradewright:Now()
	self:SetLastFullAuctionScanAt(dump.finishedAt)
	self:PrintMessage(string.format(L["Full scan done: %s items priced."], self:FormatNumberGrouped(tonumber(dump.persistTotal) or 0)))
	self:RefreshAuctionHousePanel()
	if self.RefreshMarketTab then
		self:RefreshMarketTab()
	end
	if self.RefreshShellStatus then
		self:RefreshShellStatus()
	end
end

function Tradewright:PersistFullAuctionDumpChunk(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.running ~= true or tonumber(dump.token) ~= tonumber(token) then
		return
	end
	local keys = dump.persistKeys or {}
	local index = tonumber(dump.persistIndex) or 1
	if index > #keys then
		self:TrimFullDumpMarketHistory()
		self:PrimeAuctionPanelRows()
		self:FinishFullAuctionDump()
		return
	end
	dump.status = "processing"
	local last = math.min(#keys, index + FULL_AH_DUMP_PERSIST_CHUNK - 1)
	local seenAt = tonumber(dump.seenAt) or Tradewright:Now()
	for i = index, last do
		local itemID = tonumber(keys[i])
		local aggregate = itemID and dump.aggregate and dump.aggregate[itemID] or nil
		if itemID and aggregate then
			self:PersistDumpAggregate(itemID, aggregate, dump, seenAt)
		end
	end
	dump.persistIndex = last + 1
	dump.persistDone = last
	if dump.persistIndex > #keys then
		dump.aggregate = nil
		dump.persistKeys = nil
		self:TrimFullDumpMarketHistory()
		self:PrimeAuctionPanelRows()
		self:FinishFullAuctionDump()
		return
	end
	self:RefreshAuctionHousePanel()
	C_Timer.After(0, function()
		Tradewright:PersistFullAuctionDumpChunk(token)
	end)
end

function Tradewright:ProcessFullAuctionDumpChunk(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or dump.running ~= true or tonumber(dump.token) ~= tonumber(token) then
		return
	end
	if dump.status == "requesting" then
		return
	end
	local total = tonumber(dump.total) or 0
	local index = tonumber(dump.index) or 0
	if index >= total then
		dump.persistKeys = {}
		for itemID in pairs(dump.aggregate or {}) do
			dump.persistKeys[#dump.persistKeys + 1] = itemID
		end
		table.sort(dump.persistKeys)
		dump.persistIndex = 1
		dump.persistDone = 0
		dump.persistTotal = #dump.persistKeys
		self:PersistFullAuctionDumpChunk(token)
		return
	end
	dump.status = "processing"
	dump.aggregate = dump.aggregate or {}
	local aggregateRow = self.AggregateAuctionRow
	local last = math.min(total - 1, index + FULL_AH_DUMP_ROW_CHUNK - 1)
	for i = index, last do
		local _, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
		itemID = normalizeItemID(itemID)
		aggregateRow(dump.aggregate, itemID, count, buyoutPrice)
	end
	dump.index = last + 1
	dump.done = dump.index
	self:RefreshAuctionHousePanel()
	C_Timer.After(0, function()
		Tradewright:ProcessFullAuctionDumpChunk(token)
	end)
end

-- A fingerprint of the replicate list the client holds: its length and a few sampled rows.
-- The client keeps the list from the previous full scan, so "there is a list" does not mean the
-- server has answered the new request; a changed fingerprint does.
local function replicateListMark()
	local total = tonumber(C_AuctionHouse.GetNumReplicateItems()) or 0
	local parts = { total }
	for step = 0, total > 0 and 4 or -1 do
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(math.floor((total - 1) * step / 4))
		parts[#parts + 1] = string.format("%s/%s/%s", tostring(itemID), tostring(count), tostring(buyout))
	end
	return table.concat(parts, ":"), total
end

--- Polls once a second while a full scan waits for the server. Processing starts only when the
--- answer to this request is in (the list event fired, or the list changed) and the list has
--- stopped changing for one poll; a list left over from an earlier scan is never processed.
function Tradewright:OnFullAuctionDumpTimeout(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.mode ~= "full" or tonumber(dump.token) ~= tonumber(token) or dump.status ~= "requesting" or dump.running ~= true then
		return
	end
	local mark, total = replicateListMark()
	if total > 0 and (dump.listUpdated or mark ~= dump.listMarkAtRequest) then
		if mark == dump.listMarkSettling then
			dump.total = total
			dump.done = 0
			dump.index = 0
			dump.seenAt = Tradewright:Now()
			dump.aggregate = {}
			dump.status = "processing"
			self:RefreshAuctionHousePanel()
			self:ProcessFullAuctionDumpChunk(token)
			return
		end
		dump.listMarkSettling = mark
	end
	local startedAt = tonumber(dump.requestStartedAt) or Tradewright:Now()
	if not dump.listMarkSettling and (Tradewright:Now() - startedAt) >= FULL_AH_DUMP_REQUEST_TIMEOUT_SEC then
		self:FailFullAuctionDump(L["the server did not answer. It allows one full scan every "]
			.. formatDurationShort(FULL_AH_DUMP_COOLDOWN_SEC) .. L[", so try again later"])
		return
	end
	C_Timer.After(FULL_AH_DUMP_REQUEST_POLL_SEC, function()
		Tradewright:OnFullAuctionDumpTimeout(token)
	end)
end

--- REPLICATE_ITEM_LIST_UPDATE: the server answered the full scan request. The poll picks it up.
function Tradewright:OnReplicateItemListUpdate()
	local dump = self:GetState().auctionDump
	if dump and dump.mode == "full" and dump.running == true and dump.status == "requesting" then
		dump.listUpdated = true
	end
end

function Tradewright:TrimFullDumpMarketHistory()
	self:InitDB()
	local settings = self.db and self.db.settings and self.db.settings.auction or nil
	local retentionDays = tonumber(settings and settings.historyRetentionDays) or 30
	retentionDays = math.max(1, retentionDays)
	local cutoff = Tradewright:Now() - (retentionDays * 24 * 3600)
	for _, itemHistory in pairs(self.db.itemHistory or {}) do
		local market = itemHistory and itemHistory.market or nil
		if market and market.buckets then
			for bucketAt in pairs(market.buckets) do
				local ts = tonumber(bucketAt)
				if ts and ts < cutoff then
					market.buckets[bucketAt] = nil
				end
			end
		end
	end
end

-- The last saved row of a shown-prices dump: stop, drop the rows and say how many were saved.
local function finishDumpRows(pe, dump)
	dump.running = false
	dump.finishedAt = pe:Now()
	dump.remaining = 0
	dump.rows = nil
	dump.index = nil
	pe:PrimeAuctionPanelRows()
	pe:RefreshAuctionHousePanel()
	pe:PrintMessage(string.format(L["Shown prices saved: %s."], pe:FormatNumberGrouped(tonumber(dump.persistedCount) or tonumber(dump.total) or 0)))
end

function Tradewright:ContinueAuctionDump(token)
	local state = self:GetState()
	local dump = state.auctionDump
	if not dump or dump.running ~= true or tonumber(dump.token) ~= tonumber(token) then
		return
	end

	local rows = dump.rows or {}
	local index = tonumber(dump.index) or 1
	if index > #rows then
		finishDumpRows(self, dump)
		return
	end

	local batchSize = math.max(1, tonumber(dump.batchSize) or 1)
	local last = math.min(#rows, index + batchSize - 1)
	for i = index, last do
		local row = rows[i]
		if row and row.itemID then
			if self:PersistAuctionDumpObservation({
				itemID = row.itemID,
				isCommodity = row.isCommodity == true,
				itemKey = row.itemKey,
				itemKeyFields = row.itemKeyFields,
				marketLow = row.currentPrice,
				minBuyout = row.currentPrice,
				sampleSize = tonumber(row.sampleSize) or 1,
				source = tostring(row.source or ("dump_" .. tostring(dump.mode or "visible"))),
			}) then
				dump.persistedCount = (tonumber(dump.persistedCount) or 0) + 1
			end
		end
	end

	dump.index = last + 1
	dump.remaining = math.max(0, #rows - last)
	if dump.remaining <= 0 then
		finishDumpRows(self, dump)
	else
		if ((tonumber(dump.total) or 0) - dump.remaining) % (batchSize * 2) == 0 then
			self:RefreshAuctionHousePanel()
		end
		C_Timer.After(0, function()
			Tradewright:ContinueAuctionDump(token)
		end)
	end
end

function Tradewright:StartAuctionDump(mode)
	mode = tostring(mode or "visible")
	local state = self:GetState()
	local activeDump = state.auctionDump
	if activeDump and activeDump.running == true then
		self:PrintMessage(L["A scan is already running."])
		return false
	end
	if mode == "full" then
		local cooldownRemaining = self:GetFullAuctionDumpCooldownRemaining()
		if cooldownRemaining > 0 then
			self:PrintMessage(string.format(L["Full scan is on cooldown for %s."], formatDurationShort(cooldownRemaining)))
			self:RefreshAuctionHousePanel()
			return false
		end
		if self:CanUseReplicateAuctionDump() then
			self:StopAuctionScanForDump()
			local token = (tonumber(state.auctionDumpToken) or 0) + 1
			state.auctionDumpToken = token
			state.auctionDump = {
				token = token,
				running = true,
				mode = "full",
				status = "requesting",
				startedAt = Tradewright:Now(),
				requestStartedAt = Tradewright:Now(),
				total = 0,
				done = 0,
				index = 0,
				persistDone = 0,
				persistTotal = 0,
				listMarkAtRequest = replicateListMark(),
			}
			local ok = pcall(C_AuctionHouse.ReplicateItems)
			if not ok then
				return self:StartClassicFullAuctionDump(token)
			end
			self:SetLastFullAuctionScanRequestAt(Tradewright:Now())
			self:RefreshAuctionHousePanel()
			C_Timer.After(FULL_AH_DUMP_REQUEST_POLL_SEC, function()
				Tradewright:OnFullAuctionDumpTimeout(token)
			end)
			return true
		end
		return self:StartClassicFullAuctionDump()
	end
	self:StopAuctionScanForDump()
	local rows = self:CollectVisibleAuctionDumpRows()
	local batchSize = tonumber(self:GetSetting("auction.dumpBatchSize", 50)) or 50
	batchSize = math.max(1, math.floor(batchSize))
	local token = (tonumber(state.auctionDumpToken) or 0) + 1
	state.auctionDumpToken = token
	state.auctionDump = {
		token = token,
		running = true,
		mode = mode,
		startedAt = Tradewright:Now(),
		batchSize = batchSize,
		rows = rows,
		index = 1,
		total = #rows,
		remaining = #rows,
		persistedCount = 0,
	}
	if #rows == 0 then
		state.auctionDump.running = false
		state.auctionDump.finishedAt = Tradewright:Now()
		self:RefreshAuctionHousePanel()
		self:PrintMessage(L["No shown prices to save."])
		return true
	end
	self:RefreshAuctionHousePanel()
	C_Timer.After(0, function()
		Tradewright:ContinueAuctionDump(token)
	end)
	return true
end
