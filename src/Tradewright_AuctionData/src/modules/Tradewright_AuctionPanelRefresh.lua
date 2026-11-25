-- Auction house side panel: per-refresh widget state (tabs, scan/bulk progress, sell table, reagent cart).
-- Panel construction lives in Tradewright_AuctionPanelBuild.lua (EnsureAuctionHousePanel).
local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
local function formatDurationShort(seconds)
	return Tradewright:FormatDurationShort(seconds)
end

local function setFontColor(fontString, color)
	if not fontString or not color then
		return
	end
	fontString:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
end

local POST_BUTTON_LABELS = { post_all = L["Post all"], post_profitable = L["Post profitable"] }
local SCAN_BUTTONS = { "btnScanCraftPrices", "btnScanAccountInv", "btnScanCraftAndAccount", "btnScanChoice" }
local CART_ONLY_CONTROLS = { "btnCartSearch", "btnCartRefresh", "btnCartBuy", "btnCartRemove", "btnCartClear", "cartTableHost" }
local CART_SUMMARY_TEXT = L["Reagents for your queued crafts. Buy them on this character; the mailbox panel sends the rest to your other characters."]

local function showOrHide(frame, shown)
	if shown then
		frame:Show()
	else
		frame:Hide()
	end
end

local function setControlsShown(controls, shown)
	for _, control in ipairs(controls or {}) do
		if control and control.SetShown then
			control:SetShown(shown)
		elseif control and control.Show and control.Hide then
			showOrHide(control, shown)
		end
	end
end

local function countKeys(t)
	local count = 0
	for _ in pairs(t or {}) do
		count = count + 1
	end
	return count
end

local function queuedHint(queued, idleText)
	return queued > 0 and string.format(L["%d prices queued"], queued) or idleText
end

local function applyAuctionPanelTheme(panel, theme)
	if not theme then
		return
	end
	setFontColor(panel.title, theme.textPrimary)
	setFontColor(panel.subtitle, theme.textMuted)
	if panel.cartSummary then
		setFontColor(panel.cartSummary, theme.textMuted)
	end
end

-- Outstanding reagent lines, total quantity and estimated cost ("+" when some lines have no price).
local function summarizeAuctionCart(pe, cartRows)
	local cart = { outstanding = 0, quantity = 0, cost = 0, costKnown = true }
	for _, row in ipairs(cartRows or {}) do
		local qty = tonumber(row.quantityToBuy) or 0
		if qty > 0 then
			local cost = tonumber(row.estimatedBuyCost)
			cart.outstanding = cart.outstanding + 1
			cart.quantity = cart.quantity + qty
			cart.cost = cart.cost + (cost or 0)
			cart.costKnown = cart.costKnown and cost ~= nil
		end
	end
	if cart.cost > 0 then
		cart.costHint = string.format(L["About %s"], pe:FormatCopperShort(cart.cost) .. (cart.costKnown and "" or "+"))
	end
	return cart
end

local function annotateAuctionPanelRows(pe, rows, state)
	local roiCache = state.auctionRoiCache or {}
	for _, row in ipairs(rows) do
		local roi = roiCache[row.itemID] or {}
		row.potentialROI = roi.potentialROI
		row.recipeName = roi.recipeName
		row.qualityIndex = row.qualityIndex or roi.qualityIndex
		row.postGain = pe:GetAuctionRowPostGain(row)
		pe:UpdateAuctionRowDumpState(row) -- follows a changed warning share in Settings
		row._isScanning = tonumber(state.auctionActiveItemID) == tonumber(row.itemID)
		local scanTs = pe:GetItemLastAuctionScanAt(row.itemID)
		row.lastAuctionScanAtTs = scanTs
		row.auctionScanAgeDisplay = pe:FormatAuctionScanAge(scanTs)
	end
end

local function refreshAuctionPanelFilters(pe, panel, ui, rows)
	local classOptions = pe:GetAuctionClassFilterOptions(rows)
	ui.ahClassFilterValues = pe:NormalizeFilterSelection(ui.ahClassFilterValues or {}, classOptions)
	if panel.classDropdown then
		panel.classDropdown:SetOptions(classOptions)
	end
	local subclassOptions = pe:GetAuctionSubclassFilterOptions(rows, ui.ahClassFilterValues)
	ui.ahSubclassFilterValues = pe:NormalizeFilterSelection(ui.ahSubclassFilterValues or {}, subclassOptions)
	if panel.subclassDropdown then
		panel.subclassDropdown:SetOptions(subclassOptions)
	end
	local expOpts = pe:GetExpansionFilterOptions()
	ui.ahExpansionFilterValues = pe:NormalizeFilterSelection(ui.ahExpansionFilterValues or {}, expOpts)
	if panel.expansionDropdown then
		panel.expansionDropdown:SetOptions(expOpts)
		panel.expansionDropdown:RefreshText()
	end
end

-- Annotated rows after the panel filters, plus the row count before filtering.
local function prepareAuctionPanelRows(pe, panel, ui, state)
	local rows = state.auctionPanelRows
	if type(rows) ~= "table" then
		rows = pe:PrimeAuctionPanelRows() or {}
		state.auctionPanelRows = rows
	end
	annotateAuctionPanelRows(pe, rows, state)
	refreshAuctionPanelFilters(pe, panel, ui, rows)
	local visible = pe:FilterAuctionPanelRows(rows)
	state.auctionVisibleRows = visible
	return visible, #rows
end

local function setAuctionScanFlags(scan, state)
	local busy = scan.running or state.auctionRoiRunning == true
	local pending = scan.done < scan.total
	scan.scanActive = (busy and (scan.total <= 0 or pending)) or (scan.total > 0 and pending)
	scan.scanPaused = state.auctionRefreshPaused == true and scan.running
end

-- While a bulk post runs (and no full scan), the progress row counts posts instead of scans.
local function auctionDisplayCounts(scan)
	if scan.bulkActive and not scan.fullDumpActive then
		return tonumber(scan.bulk.total) or 0, tonumber(scan.bulk.done) or 0
	end
	return scan.total, scan.done
end

-- Snapshot of full-scan, price-scan and bulk-post progress for the panel widgets.
local function getAuctionPanelScanStatus(pe, state)
	local dump, bulk = state.auctionDump, state.auctionBulk
	local scan = {
		queued = countKeys(state.auctionRefreshQueue),
		dump = dump,
		bulk = bulk,
		cooldown = pe:GetFullAuctionDumpCooldownRemaining(),
		lastFullScanAt = pe:GetLastFullAuctionScanAt(),
		lastFullScanLabel = pe:FormatScanTimestamp(pe:GetLastFullAuctionScanAt()),
		fullDumpActive = dump and dump.mode == "full" and dump.running == true,
		running = state.auctionRefreshRunning == true,
		total = tonumber(state.auctionScanTotal) or 0,
		done = tonumber(state.auctionScanDone) or 0,
		bulkActive = bulk and bulk.running == true,
		startedAt = state.auctionRefreshStartedAt,
	}
	setAuctionScanFlags(scan, state)
	scan.displayTotal, scan.displayDone = auctionDisplayCounts(scan)
	return scan
end

local function refreshFullScanFooter(panel, scan)
	if panel.footerText then
		local footer = scan.fullDumpActive and L["Full scan running"]
			or scan.cooldown > 0 and (string.format(L["Full scan ready in %s"], formatDurationShort(scan.cooldown)))
			or L["Full scan ready"]
		panel.footerText:SetText(string.format(L["%s · Last full scan %s"], footer, scan.lastFullScanLabel))
	end
end

local function refreshAuctionPanelFooters(panel, scan, rowCount, preFilterCount)
	refreshFullScanFooter(panel, scan)
	if panel.table and panel.table.SetFooterText then
		panel.table:SetFooterText(string.format(L["%d of %d items"], rowCount, preFilterCount),
			queuedHint(scan.queued, L["Click a row to put it in the sell slot"]))
	end
end

local function fullScanButtonLabel(scan)
	if scan.fullDumpActive then
		return "Scanning…"
	end
	if scan.cooldown > 0 then
		return formatDurationShort(scan.cooldown)
	end
	return L["Full scan"]
end

local function refreshAuctionPanelScanButtons(panel, scan)
	if panel.btnDumpFull then
		panel.btnDumpFull:SetEnabled(not scan.fullDumpActive and scan.cooldown <= 0)
		panel.btnDumpFull:SetText(fullScanButtonLabel(scan))
		Tradewright:SetButtonSolid(panel.btnDumpFull, Tradewright.AuctionLogic.FullScanStandsOut({
			active = scan.fullDumpActive,
			cooldown = scan.cooldown,
			lastFullScanAt = scan.lastFullScanAt,
			now = Tradewright:Now(),
			waiting = Tradewright:GetAuctionPricesWaitingForFullScan(),
		}))
	end
	if panel.btnDumpVisible then
		panel.btnDumpVisible:SetEnabled(not scan.fullDumpActive)
	end
	local canScan = not scan.fullDumpActive and not scan.running
	for _, key in ipairs(SCAN_BUTTONS) do
		if panel[key] then
			panel[key]:SetEnabled(canScan)
		end
	end
end

-- Updates only the full-scan countdown (button label and footer line), so a once-a-second timer
-- can keep it current without rebuilding the sell table.
function Tradewright:RefreshFullScanCountdown(panel)
	local dump = self:GetState().auctionDump
	local scan = {
		cooldown = self:GetFullAuctionDumpCooldownRemaining(),
		fullDumpActive = dump and dump.mode == "full" and dump.running == true,
		lastFullScanAt = self:GetLastFullAuctionScanAt(),
		lastFullScanLabel = self:FormatScanTimestamp(self:GetLastFullAuctionScanAt()),
	}
	refreshAuctionPanelScanButtons(panel, scan)
	refreshFullScanFooter(panel, scan)
end

-- While a bulk job runs, the button that started it posts the item waiting in the sell frame.
local function isBulkPostReady(scan)
	local bulk = scan.bulk
	return scan.bulkActive and bulk.paused ~= true and bulk.phase == "waiting_button"
		and GetTime() >= (bulk.nextPostAt or 0)
end

local function refreshAuctionPanelPostButtons(panel, scan)
	local postReady = isBulkPostReady(scan)
	for mode, button in pairs({ post_profitable = panel.btnPostProfitable, post_all = panel.btnPostAll }) do
		local isJob = scan.bulkActive and scan.bulk.mode == mode
		local label = POST_BUTTON_LABELS[mode]
		if scan.bulkActive then
			label = isJob and L["Post next"] or L["Skip"]
		end
		button:SetText(label)
		button:SetEnabled(not scan.bulkActive or postReady)
	end
end

local function refreshAuctionPanelPauseButtons(panel, scan)
	if panel.btnPauseBulk then
		if scan.bulkActive then
			panel.btnPauseBulk:SetText((scan.bulk.paused == true) and L["Resume"] or "Pause")
		end
		showOrHide(panel.btnPauseBulk, scan.bulkActive)
	end
	if panel.btnPauseScan then
		local shown = scan.running or scan.scanPaused
		if shown then
			panel.btnPauseScan:SetText(scan.scanPaused and L["Resume"] or "Pause")
		end
		showOrHide(panel.btnPauseScan, shown)
	end
end

-- Done/total for a full scan: the save phase once it has a total, else the download.
local function fullDumpProgress(dump)
	local persistTotal = tonumber(dump.persistTotal) or 0
	if persistTotal > 0 then
		return tonumber(dump.persistDone) or 0, persistTotal
	end
	return tonumber(dump.done) or 0, tonumber(dump.total) or 0
end

local function fullDumpProgressText(pe, dump)
	if dump.status == "requesting" then
		return L["Full scan: asking the server…"]
	end
	local done, total = fullDumpProgress(dump)
	local label = (tonumber(dump.persistTotal) or 0) > 0 and "Saving" or L["Full scan"]
	return string.format("%s %s of %s", label, pe:FormatNumberGrouped(math.min(done, total)), pe:FormatNumberGrouped(total))
end

local function auctionProgressText(pe, scan)
	if scan.fullDumpActive then
		return fullDumpProgressText(pe, scan.dump)
	end
	if scan.bulkActive then
		return string.format(L["Posting %d of %d"], math.min(scan.displayDone, scan.displayTotal), scan.displayTotal)
	end
	if (scan.scanActive or scan.scanPaused) and scan.total > 0 then
		local verb = scan.scanPaused and "Paused" or "Scanning"
		return string.format("%s %d of %d", verb, math.min(scan.done, scan.total), scan.total)
	end
	return nil
end

local function bulkFooterText(bulk)
	return string.format(L["%s · posted %d, skipped %d, failed %d"], tostring(bulk.status or "Posting"),
		tonumber(bulk.posted) or 0, tonumber(bulk.skipped) or 0, tonumber(bulk.failed) or 0)
end

-- Progress bar fraction, or nil when nothing with a known total is running.
local function auctionProgressFraction(scan)
	local done, total
	if scan.fullDumpActive then
		done, total = fullDumpProgress(scan.dump)
	elseif scan.bulkActive then
		done, total = scan.displayDone, scan.displayTotal
	else
		done, total = scan.done, scan.total
	end
	local shown = (scan.fullDumpActive and total > 0) or (scan.bulkActive and scan.displayTotal > 0)
		or (scan.scanActive and scan.total > 0)
	if not shown then
		return nil
	end
	return math.max(0, math.min(1, done / total))
end

local function scanEtaText(elapsed, done, total)
	if done > 0 and total > done then
		return formatDurationShort((elapsed / done) * (total - done))
	end
	if total > 0 and done >= total then
		return "0s"
	end
	return "…"
end

local function refreshAuctionPanelTiming(panel, scan)
	if not panel.progressTiming then
		return
	end
	local timing = panel.progressTiming
	if not ((scan.scanActive or scan.scanPaused) and scan.total > 0 and scan.running) then
		timing:Hide()
		return
	end
	if scan.scanPaused then
		timing:SetText("paused")
	else
		local gt = GetTime and GetTime() or 0
		local elapsed = math.max(0, gt - (tonumber(scan.startedAt) or gt))
		timing:SetText(string.format(L["about %s left"], scanEtaText(elapsed, scan.done, scan.total)))
	end
	timing:Show()
end

local function refreshAuctionPanelProgress(pe, panel, scan)
	if panel.progressText then
		local text = auctionProgressText(pe, scan)
		panel.progressText:SetText(text or "")
		if scan.bulkActive and not scan.fullDumpActive and panel.footerText then
			panel.footerText:SetText(bulkFooterText(scan.bulk))
		end
		showOrHide(panel.progressText, text ~= nil)
	end
	if panel.progressBar then
		local frac = auctionProgressFraction(scan)
		panel.progressBar:SetValue(frac or 0)
		showOrHide(panel.progressBar, frac ~= nil)
		if panel.progressBarBg then
			showOrHide(panel.progressBarBg, frac ~= nil)
		end
	end
	refreshAuctionPanelTiming(panel, scan)
end

-- Counts on the rail that stands in for the panel while it is folded; they keep updating while folded.
local function refreshAuctionPanelRail(pe, panel, scan, cart)
	local details = {}
	if cart.outstanding > 0 then
		details[#details + 1] = { label = L["Cart"], value = string.format(L["%d items"], cart.outstanding) }
	end
	local progressText = auctionProgressText(pe, scan)
	if progressText then
		details[#details + 1] = { label = L["Progress"], value = progressText }
	end
	pe:SetPanelDockBadges(panel.dock, { gold = cart.outstanding, progress = auctionProgressFraction(scan), details = details })
end

local function styleAuctionPanelTab(pe, tab, active)
	tab:SetEnabled(true)
	if pe.StyleShellButton then
		pe:StyleShellButton(tab, active)
	end
	tab:SetAlpha(1)
	tab:EnableMouse(true)
	tab:RegisterForClicks("LeftButtonUp")
end

local function refreshAuctionPanelTabs(pe, panel, activeTab, cart)
	if panel.tabSell then
		styleAuctionPanelTab(pe, panel.tabSell, activeTab == "sell")
	end
	if panel.tabCart then
		styleAuctionPanelTab(pe, panel.tabCart, activeTab == "cart")
		pe:SetButtonLabel(panel.tabCart, cart.outstanding > 0 and string.format(L["Cart (%d)"], cart.outstanding) or "Cart", true)
	end
	if pe.StyleShellButton then
		pe:StyleShellButton(panel.tabAuctions, activeTab == "auctions")
	end
end

local function refreshOwnedAuctionsTab(pe, panel, state, queued)
	local ownedRows, owned, cut = pe:BuildOwnedAuctionRows()
	panel.ownedCut = cut
	panel.ownedSummary:SetText(string.format(L["Sold %s · %d\nListed %s · %d, %s after cut"],
		pe:FormatCopperShort(owned.soldValue), owned.soldCount,
		pe:FormatCopperShort(owned.listedValue), owned.listedCount, pe:FormatCopperShort(owned.listedNet)))
	local cancelable = #pe:GetCancelableUndercutAuctions(ownedRows)
	pe:SetButtonLabel(panel.btnOwnedCancel, cancelable > 0 and string.format(L["Cancel undercut (%d)"], cancelable) or L["Cancel undercut"])
	panel.btnOwnedCancel:SetEnabled(cancelable > 0 and GetTime() >= (state.auctionNextCancelAt or 0))
	panel.ownedTable:SetRows(ownedRows)
	panel.ownedTable:SetFooterText(string.format(L["%d auctions"], #ownedRows), queuedHint(queued, L["Click a row to recheck its price"]))
end

-- Price checks and cancels the player asks for while a price scan runs. The scan steps aside for
-- them and then carries on where it was.
local CANCEL_SCAN_HOLD_SEC = 3

local HOLD_END_MARGIN_SEC = 0.05 -- the hold timer fires just after the hold ends

-- Puts the items at position `at` of the scan list, skipping ones already waiting there as
-- priority checks. Returns how many were added.
local function insertPriorityChecks(list, at, itemIDs)
	local seen, added = {}, 0
	local index = at
	while list[index] and list[index].priority do
		seen[list[index].itemID] = true
		index = index + 1
	end
	for _, itemID in ipairs(itemIDs or {}) do
		local id = tonumber(itemID)
		if id and id > 0 and not seen[id] then
			seen[id] = true
			table.insert(list, at + added, { itemID = id, priority = true })
			added = added + 1
		end
	end
	return added
end

--- Price check the player asked for. During a scan it goes to the front of the scan list, so it
--- is answered next (also while the scan is paused) and the scan then continues.
function Tradewright:QueuePriorityAuctionRefresh(itemIDs)
	local state = self:GetState()
	local list = state.auctionRefreshScanList
	if state.auctionRefreshRunning ~= true or type(list) ~= "table" then
		return self:QueueVisibleAuctionRefresh(itemIDs)
	end
	-- The item being searched right now keeps its place.
	local at = (tonumber(state.auctionRefreshIndex) or 1) + (state.auctionSearchContext and 1 or 0)
	state.auctionScanTotal = (tonumber(state.auctionScanTotal) or 0) + insertPriorityChecks(list, at, itemIDs)
	self:ContinueQueuedAuctionRefresh()
	self:RefreshAuctionHousePanel()
end

--- True while the scan must not send its next search: it waits for a cancel click, or it is
--- paused. A paused scan still answers priority checks, except during a bulk post.
function Tradewright:IsAuctionScanHeld(state)
	local holdLeft = (state.auctionScanHoldUntil or 0) - GetTime()
	if holdLeft > 0 then
		if not state.auctionScanHoldTimer then
			state.auctionScanHoldTimer = true
			C_Timer.After(holdLeft + HOLD_END_MARGIN_SEC, function()
				state.auctionScanHoldTimer = nil
				Tradewright:ContinueQueuedAuctionRefresh()
			end)
		end
		return true
	end
	if state.auctionRefreshPaused ~= true then
		return false
	end
	local entry = (state.auctionRefreshScanList or {})[tonumber(state.auctionRefreshIndex) or 1]
	return not (entry and entry.priority) or state.auctionRefreshPausedForBulk == true
end

--- Cancel click on the Auctions tab. A running scan keeps the server busy, and the client then
--- drops the cancel, so the scan waits a moment. A click that came too early works on the next try.
function Tradewright:CancelUndercutHoldingScan()
	self:GetState().auctionScanHoldUntil = GetTime() + CANCEL_SCAN_HOLD_SEC
	self:CancelNextUndercutAuction()
end

local function syncSearchBoxText(box, text)
	if box:GetText() ~= text then
		box:SetText(text)
		box:HighlightText(0, 0)
	end
end

local function refreshAuctionCartChrome(pe, panel, onCart, cart, filterText)
	if panel.cartSummary then
		panel.cartSummary:SetShown(onCart)
		panel.cartSummary:SetText(CART_SUMMARY_TEXT)
		if panel.cartTable and panel.cartTable.SetFooterText then
			panel.cartTable:SetFooterText(string.format(L["%d items, %s to buy"], cart.outstanding,
				pe:FormatNumberGrouped(cart.quantity)), cart.costHint)
		end
	end
	if panel.cartSearchBox then
		panel.cartSearchBox:SetShown(onCart)
		syncSearchBoxText(panel.cartSearchBox, filterText)
	end
	for _, key in ipairs(CART_ONLY_CONTROLS) do
		if panel[key] then
			panel[key]:SetShown(onCart)
		end
	end
	if panel.cartTable and panel.cartTable.frame then
		panel.cartTable.frame:SetShown(onCart)
	end
end

-- Show the sell or cart widgets for the active tab and lay out the panel body.
local function refreshAuctionPanelVisibility(pe, panel, activeTab, cart, ui)
	local onSell = activeTab == "sell"
	setControlsShown(panel.sellControls, onSell)
	if panel.subtitle then panel.subtitle:SetShown(onSell) end
	if panel.stats then panel.stats:SetShown(onSell) end
	if panel.progressRow then
		local progressShown = panel.progressText:IsShown() and panel.progressText:GetText() ~= ""
		pe:LayoutAuctionSellRows(panel, onSell and pe:IsFirstFullScanHintDue())
		pe:LayoutAuctionPanelBody(panel, activeTab, progressShown)
	end
	if panel.tableHost then
		panel.tableHost:SetShown(onSell)
	end
	if panel.table and panel.table.frame then
		panel.table.frame:SetShown(onSell)
	end
	refreshAuctionCartChrome(pe, panel, activeTab == "cart", cart, ui.auctionCartFilterText or "")
end

local function findCartRow(rows, itemID)
	for _, row in ipairs(rows) do
		if tonumber(row.itemID) == tonumber(itemID) then
			return row
		end
	end
	return nil
end

-- Keep the cart selection on a visible row (first row when it went away); returns the selected row.
local function syncAuctionCartSelection(state, rows)
	local selectedID = state.auctionCartSelectedItemID
	if not findCartRow(rows, selectedID) then
		state.auctionCartSelectedItemID = rows[1] and rows[1].itemID or nil
	elseif not selectedID and rows[1] then
		state.auctionCartSelectedItemID = rows[1].itemID
	end
	return findCartRow(rows, state.auctionCartSelectedItemID)
end

local function unpricedCartHint(rows)
	local unpriced = 0
	for _, row in ipairs(rows) do
		if (tonumber(row.quantityToBuy) or 0) > 0 and not tonumber(row.estimatedBuyCost) then
			unpriced = unpriced + 1
		end
	end
	if unpriced == 0 then
		return ""
	end
	return string.format(L["%d %s no price yet. Press Check all."], unpriced, Tradewright:Plural(unpriced, "item has", "items have"))
end

local function refreshAuctionCartButtons(panel, rows, selectedRow)
	if panel.btnCartBuy then
		panel.btnCartBuy:SetEnabled(selectedRow ~= nil and (tonumber(selectedRow.quantityToBuy) or 0) > 0)
	end
	if panel.btnCartRemove then
		panel.btnCartRemove:SetEnabled(selectedRow ~= nil)
	end
	if panel.btnCartClear then
		panel.btnCartClear:SetEnabled(#rows > 0)
	end
	if panel.cartHint then
		panel.cartHint:SetText(Tradewright:CartVendorHint(rows) .. unpricedCartHint(rows))
	end
end

local function refreshAuctionCartTable(pe, panel, cartRows, state)
	local cartTable = panel.cartTable
	if not cartTable then
		return
	end
	if not panel.__ahCartLayoutV3 then
		panel.__ahCartLayoutV3 = true
		cartTable.autoFitToScroll = true
		cartTable:SetColumns(pe:BuildAuctionCartColumns())
	end
	local rows = pe:FilterAuctionCraftCartRows(cartRows)
	cartTable:SetRows(rows)
	refreshAuctionCartButtons(panel, rows, syncAuctionCartSelection(state, rows))
end

function Tradewright:RefreshAuctionHousePanel()
	local panel = self:EnsureAuctionHousePanel()
	if not panel then
		return
	end
	self:HideExtraAuctionHousePanels(panel)
	self:RefreshAuctionPanelRules()
	self.ui = self.ui or {}
	local ui = self.ui
	applyAuctionPanelTheme(panel, self.GetTheme and self:GetTheme() or nil)
	local state = self:GetState()
	local cartRows = self:BuildAuctionCraftCartRows()
	local cart = summarizeAuctionCart(self, cartRows)
	local defaultTab = cart.outstanding > 0 and "cart" or "sell"
	if ui.auctionPanelTabManual ~= true then
		ui.auctionPanelActiveTab = defaultTab
	end
	local activeTab = self:GetAuctionPanelActiveTab(defaultTab)
	local rows, preFilterCount = prepareAuctionPanelRows(self, panel, ui, state)
	local scan = getAuctionPanelScanStatus(self, state)
	refreshAuctionPanelFooters(panel, scan, #rows, preFilterCount)
	refreshAuctionPanelScanButtons(panel, scan)
	refreshAuctionPanelPostButtons(panel, scan)
	refreshAuctionPanelPauseButtons(panel, scan)
	refreshAuctionPanelProgress(self, panel, scan)
	refreshAuctionPanelRail(self, panel, scan, cart)
	refreshAuctionPanelTabs(self, panel, activeTab, cart)
	if activeTab == "auctions" then
		refreshOwnedAuctionsTab(self, panel, state, scan.queued)
	end
	refreshAuctionPanelVisibility(self, panel, activeTab, cart, ui)
	panel.table.sortKey = ui.ahSortKey or panel.table.sortKey
	panel.table.sortAsc = ui.ahSortAsc
	panel.table:SetRows(rows)
	refreshAuctionCartTable(self, panel, cartRows, state)
end
