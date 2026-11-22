local addonName, Tradewright = ...

-- Farm window: a small movable window that shows the run in progress. It appears when a run
-- starts and hides when the run stops; `/twfarm` toggles it.

local PAD = 10
local WIDTH = 250
local HEIGHT = 232

local function clock(seconds)
	seconds = math.floor(seconds)
	return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

-- Farm name dialogs: one to save the run in progress, one to rename a saved farm. Both hand the
-- typed name to `data.onAccept`.
local function popupEditBox(popup)
	return popup.EditBox or popup.editBox -- the field was renamed between client versions
end

local function acceptName(popup)
	popup.data.onAccept(popupEditBox(popup):GetText())
end

local function nameDialog(acceptLabel, discardLabel)
	return {
		text = "%s", button1 = acceptLabel, button2 = "Cancel", button3 = discardLabel,
		hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
		OnShow = function(popup, data)
			popupEditBox(popup):SetText(data.name or "")
			popupEditBox(popup):HighlightText()
		end,
		OnAccept = acceptName,
		OnAlt = function(popup) popup.data.onDiscard() end,
		EditBoxOnEnterPressed = function(editBox)
			acceptName(editBox:GetParent())
			editBox:GetParent():Hide()
		end,
		EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
	}
end

StaticPopupDialogs["TRADEWRIGHT_FARM_SAVE"] = nameDialog("Save farm", "Discard")
StaticPopupDialogs["TRADEWRIGHT_FARM_RENAME"] = nameDialog("Rename")

--- Asks what to call the run in progress, then saves it, discards it, or (Cancel) lets it run on.
function Tradewright:AskToSaveFarmRun()
	local run = self:GetCurrentFarmRun()
	if not run then
		return
	end
	local summary = self:SummarizeFarmRun(run)
	local text = string.format("Farm finished: %s in %s, %s an hour.\nSave it as:", self:FormatCopperShort(summary.total),
		clock(summary.activeSeconds), self:FormatCopperShort(summary.perHour))
	StaticPopup_Show("TRADEWRIGHT_FARM_SAVE", text, nil, {
		name = run.name,
		onAccept = function(name)
			local _, saved = self:StopFarmRun(name)
			self:PrintMessage(string.format("Farm \"%s\" saved.", saved.name))
		end,
		onDiscard = function() self:DiscardFarmRun() end,
	})
end

--- Asks for a new name for the saved farm `name`; `onRenamed(newName)` runs when it changed.
function Tradewright:AskToRenameFarm(name, onRenamed)
	StaticPopup_Show("TRADEWRIGHT_FARM_RENAME", string.format("Rename the farm \"%s\" to:", name), nil, {
		name = name,
		onAccept = function(newName)
			newName = self:Trim(newName or "")
			if self:RenameFarm(name, newName) then
				onRenamed(newName)
			end
		end,
	})
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
	f.stop = pe:CreateButton(f, "Stop and save", function() pe:AskToSaveFarmRun() end)
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

local function pauseNote(run)
	if run.pausedForIdling then
		return " · paused, idle"
	end
	return run.pausedAt and " · paused" or ""
end

--- Redraw the farm window from the run in progress. Hidden windows are left alone.
function Tradewright:RefreshFarmWindow()
	local f = self.ui and self.ui.farmWindow
	local run = self:GetCurrentFarmRun()
	if not f or not f:IsShown() then
		return
	end
	if not run then
		f.name:SetText("No farm running")
		f.rate:SetText("-")
		f.clock:SetText("")
		f.facts:SetRows({ { "Start one with", "/twfarm start" } })
		f.pause:SetEnabled(false)
		f.stop:SetEnabled(false)
		return
	end
	local summary = self:SummarizeFarmRun(run)
	f.name:SetText(run.name)
	f.rate:SetText(self:FormatCopperShort(summary.perHour) .. " an hour")
	f.clock:SetText(clock(summary.activeSeconds) .. pauseNote(run))
	f.facts:SetRows(factRows(self, run, summary))
	f.pause:SetText(run.pausedAt and "Resume" or "Pause")
	f.pause:SetEnabled(true)
	f.stop:SetEnabled(true)
end

--- Show or hide the farm window.
function Tradewright:ToggleFarmWindow()
	local f = ensureWindow(self)
	f:SetShown(not f:IsShown())
	self:RefreshFarmWindow()
end

--- Show the farm window (a run just started).
function Tradewright:ShowFarmWindow()
	ensureWindow(self):Show()
	self:RefreshFarmWindow()
end
