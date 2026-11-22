-- Small helpers and constants the Tradewright_AuctionData files share; loaded first.
local _, Tradewright = ...

local function normalizeItemID(item)
	if type(item) == "number" then
		return item > 0 and math.floor(item) or nil
	end
	if type(item) == "string" then
		local number = tonumber(item)
		return number and number > 0 and math.floor(number) or nil
	end
	if type(item) == "table" then
		local itemID = tonumber(item.itemID)
		return itemID and itemID > 0 and math.floor(itemID) or nil
	end
	return nil
end

local function shallowCopy(source)
	if type(source) ~= "table" then
		return source
	end
	local out = {}
	for key, value in pairs(source) do
		out[key] = value
	end
	return out
end

local function formatPercent(value)
	if not value then
		return "-"
	end
	return string.format("%.1f%%", value)
end

function Tradewright:FormatPercent(value)
	return formatPercent(value)
end

local function containsText(haystack, needle)
	return string.find(string.lower(tostring(haystack or "")), string.lower(tostring(needle or "")), 1, true) ~= nil
end

local function formatDurationShort(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local minutes = math.floor(seconds / 60)
	local remaining = seconds % 60
	if minutes <= 0 then
		return string.format("%ds", remaining)
	end
	return string.format("%dm %02ds", minutes, remaining)
end

function Tradewright:FormatDurationShort(seconds)
	return formatDurationShort(seconds)
end

local function attachSimpleTooltip(widget, title, body)
	if not widget then
		return
	end
	widget:SetScript("OnEnter", function(self)
		local theme = Tradewright:GetTheme()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(title or "", 1, 1, 1)
		if body and body ~= "" then
			GameTooltip:AddLine(body, theme.textMuted.r, theme.textMuted.g, theme.textMuted.b, true)
		end
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- UIPanelButtonTemplate button: size {w, h}, label, five-value anchor and click handler.
local function panelButton(panel, size, text, point, onClick)
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(size[1], size[2])
	button:SetPoint(point[1], point[2], point[3], point[4], point[5])
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function normalizeSearchEventItemID(eventArg)
	if type(eventArg) == "number" or type(eventArg) == "string" then
		return normalizeItemID(eventArg)
	end
	if type(eventArg) ~= "table" then
		return nil
	end
	if eventArg.itemKey then
		return normalizeItemID(eventArg.itemKey)
	end
	return normalizeItemID(eventArg)
end

-- A badge-like word in its own colour, for the Flag column.
local function flagText(pe, text, colorKey)
	return pe:Colorize(string.upper(text), colorKey)
end

-- Throttle for bulk actions: seconds between an item landing in the sell frame and its post being
-- accepted, and between two auction cancels.
local AUCTION_BULK_MIN_INTERVAL = 1.0

-- Every session-only auction key on GetState(), in one place. Each starts unset (nil) and the code
-- tests for that, so this is a list of names, not starting values. tests/test_auction_state.lua fails
-- when a file uses a key missing here.
local AUCTION_STATE_KEYS = {
	-- Refresh queue: live AH searches one item at a time.
	"auctionRefreshRunning", -- true while the queue is searching
	"auctionRefreshPaused", -- the player (or a manual buy) paused the queue
	"auctionRefreshPausedForBulk", -- the queue is paused while bulk post runs
	"auctionRefreshQueue", -- item ID -> queued target waiting for a search
	"auctionRefreshQueueOrderCounter", -- insertion counter that keeps queued targets in order
	"auctionRefreshScanList", -- ordered targets of the current run
	"auctionRefreshIndex", -- position of the current target in that list
	"auctionRefreshStartedAt", -- when the current run started
	"auctionRefreshDelay", -- seconds between two queued searches, from the throttle setting
	"auctionActiveItemID", -- item the queue or bulk post is working on now
	"auctionSearchContext", -- the search waiting for results: item, key fields, token
	"auctionSearchToken", -- id of the latest search; timeouts of older ones are ignored
	"auctionScanMode", -- what the queue is doing: "idle", "price", "mixed", ...
	"auctionPendingPriceScanMode", -- mode the next queue run starts in
	"auctionPricesWaitingForFullScan", -- stale craft and inventory prices left for a full scan
	"auctionScanTotal", -- progress: targets in this run
	"auctionScanDone", -- progress: targets finished
	"auctionScanHoldUntil", -- GetTime() until which a cancelled scan stays held
	"auctionScanHoldTimer", -- a timer to end that hold is scheduled
	"auctionSourceCounts", -- this run's row prices by source (native, snapshot, fallback)
	"auctionInvalidateCraftsAfterRefresh", -- rebuild craft caches when the run ends
	"auctionLastQueueScanCompletedAt", -- when a queue run last finished
	"auctionSearchedTargets", -- item keys searched this AH visit
	"auctionSearchedTargetsMeta", -- when and why each of those was searched
	"auctionLivePriceByItem", -- item ID -> AH price fetched this visit
	"auctionNativePriceByItem", -- item ID -> AH price this session, with source and time
	-- ROI enrichment of sell rows.
	"auctionRoiRunning", -- true while craft ROI estimates are being filled in
	"auctionRoiQueue", -- item IDs still waiting for an estimate
	"auctionRoiCache", -- item ID -> craft ROI estimate
	-- Full scan.
	"auctionDump", -- the running or last full scan: mode, rows, progress
	"auctionDumpToken", -- id of the latest full scan; callbacks of older ones stop
	-- Store.
	"auctionDataRevision", -- bumped on every saved observation; views cache on it
	"auctionHistoryTrimmedAt", -- last history trim, which runs at most every 10 minutes
	-- Sell tab and bulk post.
	"auctionOwnedBagState", -- cached sellable bag contents
	"auctionViewRevision", -- bumped when the sellable bag contents change
	"auctionPanelRows", -- cached sell rows
	"auctionPanelRowsBagSignature", -- bag signature the cached rows were built for
	"auctionPanelRowsViewRevision", -- view revision the cached rows were built for
	"auctionVisibleRows", -- sell rows left after the filters
	"auctionPanelSelectedItemID", -- row the player selected on the sell tab
	"auctionLastSellSelectionItemID", -- item last put into the sell frame
	"auctionBulk", -- the running bulk post job
	-- Own auctions.
	"auctionCancelRequestedAt", -- auction ID -> GetTime() of its cancel click
	"auctionNextCancelAt", -- earliest GetTime() for the next cancel
	-- Cart.
	"auctionCartSelectedItemID", -- row the player selected on the cart tab
	"auctionCartPurchaseCredits", -- item ID -> bought quantity the bags do not show yet
	"auctionCartExtras", -- item ID -> { quantity, unitPrice, reason }: items put in the cart by hand
	"auctionCartPendingConfirm", -- commodity purchase waiting for the server's answer
	"auctionCartPurchaseRefreshPending", -- a cart refresh after a purchase is scheduled
	"auctionPendingBrowseSearch", -- browse search whose result should be selected when it arrives
}

-- The other Tradewright_AuctionData files import these as upvalues.
Tradewright.AuctionShared = {
	AUCTION_BULK_MIN_INTERVAL = AUCTION_BULK_MIN_INTERVAL,
	AUCTION_STATE_KEYS = AUCTION_STATE_KEYS,
	attachSimpleTooltip = attachSimpleTooltip,
	containsText = containsText,
	flagText = flagText,
	formatDurationShort = formatDurationShort,
	formatPercent = formatPercent,
	normalizeItemID = normalizeItemID,
	normalizeSearchEventItemID = normalizeSearchEventItemID,
	panelButton = panelButton,
	shallowCopy = shallowCopy,
}
