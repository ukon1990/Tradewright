-- The player's own auctions: the Auctions tab, undercut checks, deposits and cancelling the most undercut.
local _, Tradewright = ...

local shared = Tradewright.AuctionShared
local AUCTION_BULK_MIN_INTERVAL = shared.AUCTION_BULK_MIN_INTERVAL
local attachSimpleTooltip = shared.attachSimpleTooltip
local flagText = shared.flagText
local normalizeItemID = shared.normalizeItemID

function Tradewright:OnOwnedAuctionsUpdated()
	if self:GetAuctionPanelActiveTab() == "auctions" then
		self:RefreshAuctionHousePanel()
	end
	local state = self:GetState()
	local bulk = state.auctionBulk
	if not bulk or bulk.running ~= true or bulk.phase ~= "waiting_confirmation" then
		return
	end
	local elapsed = (GetTime and GetTime() or 0) - (tonumber(bulk.confirmationStartedAt) or 0)
	if elapsed >= 0.20 then
		self:DebugLog("AH", "owned auctions updated confirm", {
			string.format("itemID=%s elapsed=%.2f", tostring(bulk.currentItemID), elapsed),
		})
		self:ConfirmAuctionBulkCurrent("owned_auctions_updated")
	end
end

-- The item a post call was made for; nil once the whole stack has left the bags.
local function postedItemID(item)
	local ok, itemID = pcall(C_Item.GetItemID, item)
	return ok and normalizeItemID(itemID) or nil
end

-- Tell the bulk job on the next frame, so its panel redraw runs outside the game's post click.
local function notePost(itemID)
	C_Timer.After(0, function()
		Tradewright:OnAuctionPostCalled(itemID)
	end)
end

-- A non-commodity item's deposit can only be asked for while the item is in the bags, so it is
-- remembered per item whenever one is posted and reused later for repost maths. Every post also
-- tells the bulk job, which moves on to its next item.
if C_AuctionHouse and C_AuctionHouse.PostItem and hooksecurefunc then
	hooksecurefunc(C_AuctionHouse, "PostItem", function(item, duration, quantity)
		local itemID = postedItemID(item)
		pcall(function()
			local deposit = tonumber(C_AuctionHouse.CalculateItemDeposit(item, duration, quantity))
			if itemID and deposit and quantity > 0 then
				Tradewright:InitAuctionDB().itemDepositPerUnit[tostring(itemID)] = deposit / quantity
			end
		end)
		notePost(itemID)
	end)
end
if C_AuctionHouse and C_AuctionHouse.PostCommodity and hooksecurefunc then
	hooksecurefunc(C_AuctionHouse, "PostCommodity", function(item)
		notePost(postedItemID(item))
	end)
end

--- The deposit cancelling this auction forfeits, taken as what posting it again would cost at the
--- sell frame's current duration. Nil when unknown (an item posted before deposits were recorded)
--- or when the player has turned deposits off.
function Tradewright:GetOwnedAuctionDeposit(info, itemID)
	if self:GetSetting("auction.repostIncludeDeposit", true) == false then
		return nil
	end
	local keyInfo = C_AuctionHouse.GetItemKeyInfo(info.itemKey)
	if keyInfo and keyInfo.isCommodity then
		local duration = tonumber(GetCVar("auctionHouseDurationDropdown")) or 2
		return tonumber(C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, info.quantity))
	end
	local perUnit = tonumber(self:InitAuctionDB().itemDepositPerUnit[tostring(itemID)])
	return perUnit and math.floor(perUnit * info.quantity + 0.5) or nil
end

--- The client only has the player's auctions after they are asked for; the answer arrives as
--- OWNED_AUCTIONS_UPDATED.
function Tradewright:RequestOwnedAuctions()
	if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
		pcall(C_AuctionHouse.QueryOwnedAuctions, {})
	end
end

function Tradewright:OnAuctionCanceled()
	if self:GetAuctionPanelActiveTab() == "auctions" then
		self:RequestOwnedAuctions()
	end
end

local OWNED_CANCEL_TIP = "Each click cancels one undercut auction, the most undercut first. "
	.. "The deposit is not refunded, and the item comes back by mail. Skips auctions with a bid, "
	.. "and ones where reposting at the lowest price would pay nothing after the cut and deposit."
local OWNED_CHECK_TIP = "Looks up the current lowest price of every item you have listed, to show which are undercut."

local function recheckOwnedAuctionPrices()
	local ids = {}
	for _, row in ipairs(Tradewright:BuildOwnedAuctionRows()) do
		if not row.sold then
			ids[#ids + 1] = row.itemID
		end
	end
	Tradewright:QueuePriorityAuctionRefresh(ids)
end

local function buildOwnedButtons(panel)
	panel.ownedSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.ownedSummary:SetJustifyH("LEFT")
	panel.btnOwnedCheck = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnOwnedCheck:SetText("Check prices")
	panel.btnOwnedCheck:SetScript("OnClick", recheckOwnedAuctionPrices)
	panel.btnOwnedCancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.btnOwnedCancel:SetText("Cancel undercut")
	panel.btnOwnedCancel:SetScript("OnClick", function()
		Tradewright:CancelUndercutHoldingScan()
	end)
	attachSimpleTooltip(panel.btnOwnedCancel, "Cancel undercut", OWNED_CANCEL_TIP)
	attachSimpleTooltip(panel.btnOwnedCheck, "Check prices", OWNED_CHECK_TIP)
end

local function appendOwnedUndercutLines(pe, lines, rowData)
	lines[4] = { "Undercut by", string.format("%s each (%d%%)", pe:FormatCopperFull(rowData.undercutBy), math.max(1, math.floor(rowData.undercutPct + 0.5))) }
	if pe:GetSetting("auction.repostIncludeDeposit", true) ~= false then
		lines[#lines + 1] = { "Deposit lost on cancel", rowData.deposit and pe:FormatCopperFull(rowData.deposit) or "unknown, not counted" }
	end
	lines[#lines + 1] = { "If cancelled and reposted at lowest", rowData.repostNet > 0
		and string.format("%s (%s less)", pe:FormatCopperFull(rowData.repostNet), pe:FormatCopperFull(rowData.net - rowData.repostNet))
		or "not worth it" }
end

local function ownedRowTooltipLines(pe, panel, rowData)
	local lines = {}
	if not rowData.sold then
		local cutLabel = string.format("After %.3g%% cut", (panel.ownedCut or pe.DEFAULT_AUCTION_CUT) * 100)
		lines[1] = { "Lowest scanned", rowData.marketPrice and pe:FormatCopperFull(rowData.marketPrice) or "not scanned this visit" }
		lines[2] = { "Scanned", pe:FormatAuctionScanAge(pe:GetItemLastAuctionScanAt(rowData.itemID)) }
		lines[3] = { cutLabel, pe:FormatCopperFull(rowData.net) }
		if rowData.undercut then
			appendOwnedUndercutLines(pe, lines, rowData)
		end
	end
	return lines
end

local function buildOwnedTable(self, panel)
	panel.ownedTableHost = CreateFrame("Frame", nil, panel)
	panel.ownedTable = self:CreateReusableTable(panel.ownedTableHost, {
		rowHeight = 24,
		footer = true,
		emptyTitle = "No auctions",
		emptyHint = "Items you post show up here.",
		maxRows = 200,
		sortKey = "status",
		sortAsc = false,
		autoFitToScroll = true,
		onRowEnter = function(rowFrame, rowData)
			local pe = Tradewright
			local lines = ownedRowTooltipLines(pe, panel, rowData)
			pe:ShowItemRowTooltip(rowFrame, rowData.itemID, lines, not rowData.sold and "Click to recheck its price" or nil)
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, rowData)
			if not rowData.sold then
				Tradewright:QueuePriorityAuctionRefresh({ rowData.itemID })
			end
		end,
	})
	panel.ownedTable.frame:SetAllPoints(panel.ownedTableHost)
	panel.ownedTable:SetColumns(self:BuildOwnedAuctionColumns())
end

-- Auctions tab: totals, a price recheck and the player's own auctions.
function Tradewright:BuildAuctionPanelOwnedTab(panel)
	buildOwnedButtons(panel)
	buildOwnedTable(self, panel)
end

function Tradewright:BuildOwnedAuctionColumns()
	local pe = self
	return {
		self:CreateItemColumn({
			id = "item",
			label = "Item",
			defaultSort = "asc",
			minWidth = 110,
			getItemID = function(row) return row and row.itemID end,
			getIcon = function(row) return row and row.itemIcon end,
			getName = function(row)
				return tostring(row and row.itemName or "-") .. (row and row.quantity > 1 and (" x" .. row.quantity) or "")
			end,
			sortValue = function(row) return row and row.itemName end,
		}),
		pe:MoneyColumn({ id = "unitPrice", label = "Each", width = 78, optional = true }),
		pe:MoneyColumn({ id = "value", label = "Total", width = 78 }),
		{
			id = "status", label = "Status", width = 104, sortable = true, defaultSort = "desc",
			tooltipTitle = "Status", tooltipText = "Sold, or how your price compares with the lowest one scanned this visit.",
			-- Descending: most undercut first, then lowest, unchecked, sold.
			sortValue = function(row)
				return row.sold and -1 or (row.undercut and 1 + row.undercutPct) or (row.undercut == false and 0.5) or 0
			end,
			getText = function(row)
				if row.sold then
					return flagText(pe, "Sold", "success")
				elseif row.canceling then
					return flagText(pe, "Cancelling", "textMuted")
				elseif row.undercut then
					return flagText(pe, string.format("Undercut %d%%", math.max(1, math.floor(row.undercutPct + 0.5))), "danger")
				elseif row.undercut == false then
					return flagText(pe, "Lowest", "textMuted")
				end
				return "-"
			end,
		},
	}
end

--- The player's own auctions with totals; undercut compares against prices scanned this visit.
function Tradewright:BuildOwnedAuctionRows()
	local owned, lowest = {}, {}
	local soldStatus = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold
	for _, info in ipairs(C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and C_AuctionHouse.GetOwnedAuctions() or {}) do
		local itemID = normalizeItemID(info.itemKey and info.itemKey.itemID)
		if itemID then
			owned[#owned + 1] = {
				auctionID = info.auctionID,
				itemID = itemID,
				quantity = info.quantity,
				sold = soldStatus ~= nil and info.status == soldStatus,
				buyout = info.buyoutAmount,
				bid = info.bidAmount,
				deposit = soldStatus ~= info.status and self:GetOwnedAuctionDeposit(info, itemID) or nil,
			}
			lowest[itemID] = lowest[itemID] or self:GetNativeAhPrice(itemID)
		end
	end
	local cut = self:GetAuctionCut()
	local rows, totals = self.AuctionLogic.SummarizeOwnedAuctions(owned, lowest, cut)
	local cancelRequestedAt = self:GetState().auctionCancelRequestedAt or {}
	for _, row in ipairs(rows) do
		local desc = self:ResolveItemDescriptor(row.itemID)
		row.itemName = self:GetItemDisplayName(row.itemID)
		row.itemIcon = desc and desc.icon or 134400
		-- A cancel shows as pending until the client drops the auction (or 10s pass without that).
		row.canceling = GetTime() - (cancelRequestedAt[row.auctionID] or -100) < 10
	end
	return rows, totals, cut
end

--- Undercut auctions a bulk cancel may take, most undercut first. Left alone: auctions with a
--- cancel fee (someone has bid), and ones where a repost at the lowest price would pay nothing
--- after the cut and the forfeited deposit.
function Tradewright:GetCancelableUndercutAuctions(rows)
	local out = {}
	for _, row in ipairs(rows) do
		if row.undercut and not row.canceling and row.repostNet > 0 and C_AuctionHouse.CanCancelAuction(row.auctionID)
			and (tonumber(C_AuctionHouse.GetCancelCost(row.auctionID)) or 0) == 0 then
			out[#out + 1] = row
		end
	end
	table.sort(out, function(a, b) return a.undercutPct > b.undercutPct end)
	return out
end

--- Cancels the most undercut auction. Must run from a real click: like posting, the client
--- rejects cancels that don't come from a hardware event, so it is one click per auction.
function Tradewright:CancelNextUndercutAuction()
	local state = self:GetState()
	local nowSec = GetTime()
	if nowSec < (state.auctionNextCancelAt or 0) or not C_AuctionHouse.IsThrottledMessageSystemReady() then
		return
	end
	local target = self:GetCancelableUndercutAuctions((self:BuildOwnedAuctionRows()))[1]
	if not target then
		return
	end
	C_AuctionHouse.CancelAuction(target.auctionID)
	state.auctionCancelRequestedAt = state.auctionCancelRequestedAt or {}
	state.auctionCancelRequestedAt[target.auctionID] = nowSec
	state.auctionNextCancelAt = nowSec + AUCTION_BULK_MIN_INTERVAL
	self:RefreshAuctionHousePanel()
	C_Timer.After(AUCTION_BULK_MIN_INTERVAL, function()
		Tradewright:RefreshAuctionHousePanel()
	end)
end
