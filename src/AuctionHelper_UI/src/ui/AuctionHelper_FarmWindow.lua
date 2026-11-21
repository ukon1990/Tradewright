local addonName, AuctionHelper = ...

-- Farm window (E09 F70): a small movable window that shows the run in progress. It appears when a run
-- starts and hides when the run stops; `/ahfarm` toggles it.

local PAD = 10
local WIDTH = 250
local HEIGHT = 232

local function clock(seconds)
	seconds = math.floor(seconds)
	return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

local function savePosition(pe, f)
	local point, _, relativePoint, x, y = f:GetPoint(1)
	pe:SetSetting("farm.windowPosition", { point = point, relativePoint = relativePoint, x = x, y = y })
end

local function restorePosition(pe, f)
	local saved = pe:GetSetting("farm.windowPosition", nil)
	f:ClearAllPoints()
	if type(saved) == "table" and saved.point then
		f:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
	else
		f:SetPoint("RIGHT", UIParent, "RIGHT", -120, 60)
	end
end

local function buildHeader(pe, f)
	local theme = pe:GetTheme()
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -(theme.size.header / 2))
	pe:SkinCloseButton(close)
	close:SetScript("OnClick", function() f:Hide() end)
	f.title = pe:CreateText(f, "GameFontNormalLarge", "gold")
	f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(theme.size.header / 2) - 1)
	f.title:SetText("Farm")
	f.clock = pe:CreateText(f, "GameFontHighlightSmall", "textMuted", "RIGHT")
	f.clock:SetPoint("RIGHT", close, "LEFT", -6, 0)
	f.clock:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
	return theme.size.header
end

local function buildBody(pe, f, top)
	f.name = pe:CreateText(f, "GameFontHighlight")
	f.name:SetPoint("TOPLEFT", PAD, -(top + PAD))
	f.name:SetPoint("TOPRIGHT", -PAD, -(top + PAD))
	f.rate = pe:CreateText(f, "NumberFontNormalLarge")
	f.rate:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -6)
	f.rate:SetPoint("TOPRIGHT", f.name, "BOTTOMRIGHT", 0, -6)
	f.facts = pe:CreateKeyValueList(f)
	f.facts:SetPoint("TOPLEFT", f.rate, "BOTTOMLEFT", 0, -8)
	f.facts:SetPoint("TOPRIGHT", f.rate, "BOTTOMRIGHT", 0, -8)
	f.facts:SetHeight(6 * 16)
	f.pause = pe:CreateButton(f, "Pause", function() pe:ToggleFarmPause() end)
	f.pause:SetPoint("BOTTOMLEFT", PAD, PAD)
	f.pause:SetWidth(70)
	f.stop = pe:CreateButton(f, "Stop and save", function()
		local summary, run = pe:StopFarmRun()
		if summary then
			pe:PrintMessage(string.format("Farm \"%s\" saved: %s in %s, %s an hour.", run.name,
				pe:FormatCopperShort(summary.total), clock(summary.activeSeconds), pe:FormatCopperShort(summary.perHour)))
		end
	end)
	f.stop:SetPoint("BOTTOMLEFT", f.pause, "BOTTOMRIGHT", 6, 0)
	f.stop:SetPoint("BOTTOMRIGHT", -PAD, PAD)
end

local function ensureWindow(pe)
	if pe.ui.farmWindow then
		return pe.ui.farmWindow
	end
	local f = CreateFrame("Frame", addonName .. "FarmWindow", UIParent, "BackdropTemplate")
	f:SetSize(WIDTH, HEIGHT)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition(pe, self)
	end)
	pe:StyleWindow(f)
	buildBody(pe, f, buildHeader(pe, f))
	pe:SkinTree(f)
	restorePosition(pe, f)
	-- The clock and rate move while nothing else changes.
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 1 then
			elapsed = 0
			pe:RefreshFarmWindow()
		end
	end)
	f:Hide()
	pe.ui.farmWindow = f
	return f
end

-- Label and value pairs: the value's three parts, then the latest pickups.
local function factRows(pe, run, summary)
	local rows = {
		{ "Auction estimate", pe:FormatCopperShort(summary.auctionValue) },
		{ "Vendor items", pe:FormatCopperShort(summary.vendorValue + summary.vendorSold) },
		{ "Coin", pe:FormatCopperShort(summary.coin) },
	}
	for _, pickup in ipairs(run.latest or {}) do
		rows[#rows + 1] = { pe:GetItemDisplayName(pickup.itemID), "x" .. pe:FormatNumberGrouped(pickup.qty) }
	end
	return rows
end

--- Redraw the farm window from the run in progress. Hidden windows are left alone.
function AuctionHelper:RefreshFarmWindow()
	local f = self.ui and self.ui.farmWindow
	local run = self:GetCurrentFarmRun()
	if not f or not f:IsShown() then
		return
	end
	if not run then
		f.name:SetText("No farm running")
		f.rate:SetText("-")
		f.clock:SetText("")
		f.facts:SetRows({ { "Start one with", "/ahfarm start" } })
		f.pause:SetEnabled(false)
		f.stop:SetEnabled(false)
		return
	end
	local summary = self:SummarizeFarmRun(run)
	f.name:SetText(run.name)
	f.rate:SetText(self:FormatCopperShort(summary.perHour) .. " an hour")
	f.clock:SetText(clock(summary.activeSeconds) .. (run.pausedAt and " · paused" or ""))
	f.facts:SetRows(factRows(self, run, summary))
	f.pause:SetText(run.pausedAt and "Resume" or "Pause")
	f.pause:SetEnabled(true)
	f.stop:SetEnabled(true)
end

--- Show or hide the farm window.
function AuctionHelper:ToggleFarmWindow()
	local f = ensureWindow(self)
	f:SetShown(not f:IsShown())
	self:RefreshFarmWindow()
end

--- Show the farm window (a run just started).
function AuctionHelper:ShowFarmWindow()
	ensureWindow(self):Show()
	self:RefreshFarmWindow()
end
