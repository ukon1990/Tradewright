-- Bulk post from the sell tab: the job of rows to post, one sell-frame item at a time, pause and resume.
local _, AuctionHelper = ...

local shared = AuctionHelper.AuctionShared
local AUCTION_BULK_MIN_INTERVAL = shared.AUCTION_BULK_MIN_INTERVAL
local normalizeItemID = shared.normalizeItemID

-- Pauses between bulk steps, in seconds. Each step redraws the panel first.
local BULK_NEXT_STEP_SEC = 0.05
local BULK_AFTER_FAILURE_SEC = 0.08
local BULK_AFTER_POST_SEC = 0.18 -- the bags and owned list catch up with the post
local BULK_RETRY_SEC = 0.20
local BULK_CONFIRMATION_POLL_SEC = 0.25
local BULK_CONFIRMATION_TIMEOUT_SEC = 2.5
local BULK_WAIT_FOR_SEARCH_SEC = 0.10 -- a queued search still owns the AH

function AuctionHelper:BuildAuctionBulkRows(mode)
	mode = tostring(mode or "post_all")
	local state = self:GetState()
	local rows = {}
	local sourceRows = self:FilterAuctionPanelRows(state.auctionPanelRows or {})
	state.auctionVisibleRows = sourceRows
	for _, row in ipairs(sourceRows) do
		local keep = row and row.itemID and (tonumber(row.quantitySellable) or tonumber(row.quantityOwned) or 0) > 0
		if keep and row.isIgnoredByRule == true then
			keep = false
		end
		if keep and row.canBulkPost == false then
			keep = false
		end
		if keep and mode == "post_profitable" then
			keep = (tonumber(row.potentialROI) or -999) > 0
		end
		if keep then
			rows[#rows + 1] = row
		end
	end
	return rows
end

function AuctionHelper:MaybeStartDeferredAuctionBulk()
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or bulk.awaitingScan ~= true then
		return
	end
	if state.auctionRefreshRunning or state.auctionRoiRunning then
		return
	end
	local rows = self:BuildAuctionBulkRows(bulk.mode)
	if #rows == 0 then
		self:PrintMessage(bulk.mode == "post_profitable" and "No profitable visible rows to post." or "No visible auction rows to post.")
		state.auctionBulk = nil
		self:RefreshAuctionHousePanel()
		return
	end
	bulk.awaitingScan = false
	bulk.rows = rows
	bulk.total = #rows
	bulk.done = 0
	bulk.selected = 0
	bulk.posted = 0
	bulk.skippedDumped = 0
	bulk.failed = 0
	bulk.index = 1
	bulk.phase = "selecting"
	bulk.status = "Starting..."
	bulk.currentItemID = nil
	bulk.retryCount = 0
	bulk.currentSelectionCounted = false
	bulk.paused = false
	self:RefreshAuctionHousePanel()
	C_Timer.After(BULK_NEXT_STEP_SEC, function()
		AuctionHelper:ContinueAuctionBulkPost()
	end)
end

function AuctionHelper:FinishAuctionBulkJob()
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk then
		return
	end
	local modeLabel = bulk.mode == "post_profitable" and "profitable" or "all"
	bulk.running = false
	bulk.phase = nil
	bulk.currentItemID = nil
	bulk.status = "Completed"
	bulk.paused = false
	self:PrintMessage(string.format(
		"Auction bulk post (%s) complete: selected %d/%d, posted %d, skipped dumped %d, failed %d.",
		modeLabel,
		tonumber(bulk.selected) or 0,
		tonumber(bulk.total) or 0,
		tonumber(bulk.posted) or 0,
		tonumber(bulk.skippedDumped) or 0,
		tonumber(bulk.failed) or 0
	))
	self:ResumeAuctionScanAfterBulkPost()
	self:RefreshAuctionHousePanel()
end

function AuctionHelper:FailAuctionBulkCurrent(reason)
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true then
		return
	end
	local itemID = normalizeItemID(bulk.currentItemID)
	bulk.failed = (tonumber(bulk.failed) or 0) + 1
	bulk.done = math.min(tonumber(bulk.total) or 0, tonumber(bulk.index) or 1)
	bulk.status = string.format("%s: %s", tostring(reason or "Failed"), itemID and self:GetItemDisplayName(itemID) or "?")
	bulk.index = (tonumber(bulk.index) or 1) + 1
	bulk.phase = "selecting"
	bulk.currentItemID = nil
	bulk.retryCount = 0
	bulk.currentSelectionCounted = false
	bulk.paused = false
	self:DebugLog("AH", "bulk failed current", {
		string.format("reason=%s itemID=%s index=%s", tostring(reason), tostring(itemID), tostring(bulk.index)),
	})
	self:RefreshAuctionHousePanel()
	C_Timer.After(BULK_AFTER_FAILURE_SEC, function()
		AuctionHelper:ContinueAuctionBulkPost()
	end)
end

function AuctionHelper:ConfirmAuctionBulkCurrent(source)
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or bulk.phase ~= "waiting_confirmation" then
		return false
	end
	local itemID = normalizeItemID(bulk.currentItemID)
	if not itemID then
		return false
	end
	self:RecordAuctionTransaction({
		kind = "posted",
		itemID = itemID,
		quantity = 1,
		source = tostring(source or "auction_event"),
	})
	bulk.posted = (tonumber(bulk.posted) or 0) + 1
	bulk.done = math.min(tonumber(bulk.total) or 0, tonumber(bulk.index) or 1)
	bulk.status = string.format("Confirmed: %s", self:GetItemDisplayName(itemID))
	bulk.index = (tonumber(bulk.index) or 1) + 1
	bulk.phase = "selecting"
	bulk.currentItemID = nil
	bulk.retryCount = 0
	bulk.currentSelectionCounted = false
	bulk.paused = false
	state.recentAuctionBulkConfirmation = {
		itemID = itemID,
		at = GetTime and GetTime() or 0,
	}
	self:DebugLog("AH", "bulk confirmed", {
		string.format("itemID=%d source=%s posted=%d/%d", itemID, tostring(source), tonumber(bulk.posted) or 0, tonumber(bulk.total) or 0),
	})
	self:PrimeAuctionPanelRows()
	self:RefreshAuctionHousePanel()
	C_Timer.After(BULK_AFTER_POST_SEC, function()
		AuctionHelper:ContinueAuctionBulkPost()
	end)
	return true
end

function AuctionHelper:ProcessAuctionBulkPhase(token)
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or tonumber(bulk.token) ~= tonumber(token) then
		return
	end
	if bulk.paused == true then
		return
	end
	if bulk.phase == "waiting_confirmation" then
		local elapsed = (GetTime and GetTime() or 0) - (tonumber(bulk.confirmationStartedAt) or 0)
		if elapsed >= BULK_CONFIRMATION_TIMEOUT_SEC then
			bulk.retryCount = (tonumber(bulk.retryCount) or 0) + 1
			if (tonumber(bulk.retryCount) or 0) >= (tonumber(bulk.maxRetries) or 8) then
				self:FailAuctionBulkCurrent("Timed out")
				return
			end
			bulk.phase = "selecting"
			bulk.status = string.format("Timed out, retrying (%d/%d): %s", bulk.retryCount, bulk.maxRetries, self:GetItemDisplayName(bulk.currentItemID))
			self:DebugLog("AH", "bulk confirmation timeout", {
				string.format("itemID=%s retry=%d/%d", tostring(bulk.currentItemID), bulk.retryCount, bulk.maxRetries),
			})
			self:RefreshAuctionHousePanel()
			C_Timer.After(BULK_RETRY_SEC, function()
				AuctionHelper:ContinueAuctionBulkPost()
			end)
			return
		end
		self:RefreshAuctionHousePanel()
		C_Timer.After(BULK_CONFIRMATION_POLL_SEC, function()
			AuctionHelper:ProcessAuctionBulkPhase(token)
		end)
	end
end

function AuctionHelper:ContinueAuctionBulkPost()
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true then
		return
	end
	if bulk.paused == true or bulk.awaitingScan == true or bulk.phase == "waiting_confirmation" then
		return
	end
	local row = bulk.rows and bulk.rows[bulk.index] or nil
	if not row then
		self:FinishAuctionBulkJob()
		return
	end
	bulk.currentItemID = row.itemID
	if row.isDumpedLow == true then
		bulk.skippedDumped = (tonumber(bulk.skippedDumped) or 0) + 1
		bulk.done = math.min(tonumber(bulk.total) or 0, tonumber(bulk.index) or 1)
		bulk.status = string.format("Skipped dumped: %s", self:GetItemDisplayName(row.itemID))
		bulk.index = (tonumber(bulk.index) or 1) + 1
		bulk.phase = "selecting"
		bulk.currentItemID = nil
		bulk.retryCount = 0
		bulk.currentSelectionCounted = false
		self:DebugLog("AH", "bulk skip dumped", {
			string.format("itemID=%s index=%s", tostring(row.itemID), tostring(bulk.index)),
		})
		self:RefreshAuctionHousePanel()
		C_Timer.After(BULK_NEXT_STEP_SEC, function()
			AuctionHelper:ContinueAuctionBulkPost()
		end)
		return
	end
	bulk.status = string.format("Selecting: %s", self:GetItemDisplayName(row.itemID))
	self:DebugLog("AH", "bulk select", {
		string.format("itemID=%s index=%s/%s retry=%s", tostring(row.itemID), tostring(bulk.index), tostring(bulk.total), tostring(bulk.retryCount or 0)),
	})
	local ok = self:TrySendItemToAuctionSellFrame(row.itemID)
	if not ok then
		self:FailAuctionBulkCurrent("Could not select")
		return
	end
	state.auctionActiveItemID = row.itemID
	state.auctionLastSellSelectionItemID = row.itemID
	if bulk.currentSelectionCounted ~= true then
		bulk.selected = (tonumber(bulk.selected) or 0) + 1
		bulk.currentSelectionCounted = true
	end
	bulk.phase = "waiting_button"
	bulk.token = (tonumber(bulk.token) or 0) + 1
	bulk.status = string.format("Click Post next: %s", self:GetItemDisplayName(row.itemID))
	-- Throttle: "Post next" unlocks a moment after the item lands in the sell frame, which also
	-- gives Blizzard's price lookup time to fill in the going price.
	bulk.nextPostAt = GetTime() + AUCTION_BULK_MIN_INTERVAL
	self:RefreshAuctionHousePanel()
	C_Timer.After(AUCTION_BULK_MIN_INTERVAL, function()
		AuctionHelper:RefreshAuctionHousePanel()
	end)
end

--- Posts the item waiting in the sell frame. Must run from a real click: the client rejects
--- auction posts that don't come from a hardware event, so bulk posting is one click per auction.
function AuctionHelper:PostAuctionBulkCurrent()
	local bulk = self:GetState().auctionBulk
	if not bulk or bulk.running ~= true or bulk.paused == true or bulk.phase ~= "waiting_button" then
		return
	end
	local nowSec = GetTime()
	if nowSec < (bulk.nextPostAt or 0) then
		return
	end
	local name = self:GetItemDisplayName(bulk.currentItemID)
	if not self:TryClickAuctionPostButton() then
		bulk.status = string.format("Auction house not ready, click again: %s", name)
		self:RefreshAuctionHousePanel()
		return
	end
	local token = bulk.token
	bulk.phase = "waiting_confirmation"
	bulk.confirmationStartedAt = nowSec
	bulk.status = string.format("Waiting for confirmation: %s", name)
	self:DebugLog("AH", "bulk click post", {
		string.format("itemID=%s token=%s", tostring(bulk.currentItemID), tostring(token)),
	})
	self:RefreshAuctionHousePanel()
	C_Timer.After(BULK_CONFIRMATION_POLL_SEC, function()
		AuctionHelper:ProcessAuctionBulkPhase(token)
	end)
end

function AuctionHelper:ToggleAuctionBulkPause()
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true then
		return
	end
	bulk.paused = bulk.paused ~= true
	if bulk.paused then
		bulk.status = string.format("Paused: %s", bulk.currentItemID and self:GetItemDisplayName(bulk.currentItemID) or "idle")
		self:DebugLog("AH", "bulk paused", {
			string.format("phase=%s itemID=%s", tostring(bulk.phase), tostring(bulk.currentItemID)),
		})
	else
		bulk.status = string.format("Resuming: %s", bulk.currentItemID and self:GetItemDisplayName(bulk.currentItemID) or "next item")
		self:DebugLog("AH", "bulk resumed", {
			string.format("phase=%s itemID=%s", tostring(bulk.phase), tostring(bulk.currentItemID)),
		})
		if bulk.phase == "waiting_confirmation" then
			local token = tonumber(bulk.token)
			if token then
				C_Timer.After(BULK_NEXT_STEP_SEC, function()
					AuctionHelper:ProcessAuctionBulkPhase(token)
				end)
			end
		else
			C_Timer.After(BULK_NEXT_STEP_SEC, function()
				AuctionHelper:ContinueAuctionBulkPost()
			end)
		end
	end
	self:RefreshAuctionHousePanel()
end

function AuctionHelper:PauseAuctionScanForBulkPost()
	local state = self:GetState()
	if self:PauseAuctionScanForManualBuy("bulk_post") then
		state.auctionRefreshPausedForBulk = true
		return true
	end
	return false
end

function AuctionHelper:ResumeAuctionScanAfterBulkPost()
	local state = self:GetState()
	if state.auctionRefreshPausedForBulk ~= true then
		return false
	end
	state.auctionRefreshPausedForBulk = false
	if state.auctionRefreshRunning ~= true or state.auctionRefreshPaused ~= true then
		return false
	end
	state.auctionRefreshPaused = false
	self:DebugLog("AH", "scan resumed after bulk", {
		string.format("mode=%s itemID=%s index=%s", tostring(state.auctionScanMode), tostring(state.auctionActiveItemID), tostring(state.auctionRefreshIndex)),
	})
	if state.auctionSearchContext then
		return true
	end
	C_Timer.After(BULK_NEXT_STEP_SEC, function()
		AuctionHelper:ContinueQueuedAuctionRefresh()
	end)
	return true
end

function AuctionHelper:RunAuctionPanelBulkAction(mode)
	mode = tostring(mode or "post_all")
	local state = self:GetState()
	if state.auctionBulk and state.auctionBulk.running == true then
		-- The button that started the job is its "Post next" button while it runs.
		if state.auctionBulk.mode == mode then
			self:PostAuctionBulkCurrent()
		end
		return
	end
	if not self:CanStartFullAuctionSideActions(true) then
		return
	end
	if state.auctionRefreshRunning == true then
		if self:PauseAuctionScanForBulkPost() then
			self:PrintMessage("Paused auction scan to start bulk posting.")
		end
	end
	local rows = self:BuildAuctionBulkRows(mode)
	if #rows == 0 then
		self:PrintMessage(mode == "post_profitable" and "No profitable visible rows to post." or "No visible auction rows to post.")
		self:ResumeAuctionScanAfterBulkPost()
		return
	end
	state.auctionBulk = {
		running = true,
		mode = mode,
		awaitingScan = false,
		rows = rows,
		index = 1,
		total = #rows,
		done = 0,
		selected = 0,
		posted = 0,
		skippedDumped = 0,
		failed = 0,
		maxRetries = 8,
		retryCount = 0,
		currentSelectionCounted = false,
		phase = "selecting",
		status = "Starting...",
		currentItemID = nil,
	}
	self:RefreshAuctionHousePanel()
	-- If a queued scan has an in-flight search, wait for it to complete once.
	-- Pausing prevents the scan from scheduling the next search query, but we still need
	-- the sell UI to catch up (post button enabling depends on it).
	local function waitAndStart()
		local s = self:GetState()
		local b = s and s.auctionBulk or nil
		if not b or b.running ~= true then
			return
		end
		if s.auctionSearchContext then
			C_Timer.After(BULK_WAIT_FOR_SEARCH_SEC, waitAndStart)
			return
		end
		b.awaitingScan = false
		b.status = "Starting..."
		self:RefreshAuctionHousePanel()
		AuctionHelper:ContinueAuctionBulkPost()
	end
	if state.auctionSearchContext then
		state.auctionBulk.awaitingScan = true
		state.auctionBulk.status = "Waiting for scan step to finish..."
		self:RefreshAuctionHousePanel()
		C_Timer.After(BULK_WAIT_FOR_SEARCH_SEC, waitAndStart)
		return
	end
	C_Timer.After(BULK_NEXT_STEP_SEC, function()
		AuctionHelper:ContinueAuctionBulkPost()
	end)
end
