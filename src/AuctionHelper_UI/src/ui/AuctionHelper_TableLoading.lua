local _, AuctionHelper = ...

-- Loading state of a table whose rows are still being worked out in the background (market
-- insights, craft profit): grey placeholder rows that pulse, under a line saying what is being
-- read and how far it got. It replaces the empty-state message, which would wrongly say there is
-- nothing to show.

local TableMixin = AuctionHelper.TableMixin

local PLACEHOLDER_ROWS = 8
local NOTE_HEIGHT = 22
local PULSE_SEC = 0.7
local NOTE_UPDATE_SEC = 0.25
-- Name bar widths per placeholder row, uneven so the rows read as items rather than stripes.
local NAME_WIDTHS = { 150, 110, 175, 125, 160, 100, 140, 120 }

local function placeholderBar(parent, color, width, height)
	local bar = parent:CreateTexture(nil, "ARTWORK")
	bar:SetColorTexture(color.r, color.g, color.b, 1)
	bar:SetSize(width, height)
	return bar
end

local function createPlaceholderRow(bars, index, rowHeight, color)
	local row = CreateFrame("Frame", nil, bars)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
	row:SetPoint("RIGHT")
	row:SetHeight(rowHeight)
	local iconSize = math.max(10, rowHeight - 14)
	local icon = placeholderBar(row, color, iconSize, iconSize)
	icon:SetPoint("LEFT", 8, 0)
	local name = placeholderBar(row, color, NAME_WIDTHS[index], 8)
	name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	local value = placeholderBar(row, color, 56, 8)
	value:SetPoint("RIGHT", -12, 0)
end

-- Fades the bars down and back up for as long as they are shown.
local function addPulse(bars)
	local pulse = bars:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(PULSE_SEC)
	bars:SetScript("OnShow", function() pulse:Play() end)
	bars:SetScript("OnHide", function() pulse:Stop() end)
end

-- A function note is read again every NOTE_UPDATE_SEC, so progress moves while nothing redraws the table.
local function keepNoteCurrent(widget, loading)
	local sinceUpdate = 0
	loading:SetScript("OnUpdate", function(_, elapsed)
		sinceUpdate = sinceUpdate + elapsed
		if sinceUpdate >= NOTE_UPDATE_SEC then
			sinceUpdate = 0
			widget:UpdateLoadingNote()
		end
	end)
end

function TableMixin:CreateLoadingState()
	local theme = AuctionHelper:GetTheme()
	local loading = CreateFrame("Frame", nil, self.frame)
	loading:SetAllPoints(self.scrollFrame)
	loading.note = loading:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	loading.note:SetPoint("TOPLEFT", 10, -6)
	loading.note:SetPoint("TOPRIGHT", -10, -6)
	loading.note:SetJustifyH("LEFT")
	loading.note:SetTextColor(theme.textMuted.r, theme.textMuted.g, theme.textMuted.b)
	local bars = CreateFrame("Frame", nil, loading)
	bars:SetPoint("TOPLEFT", 0, -NOTE_HEIGHT)
	bars:SetPoint("BOTTOMRIGHT")
	if bars.SetClipsChildren then
		bars:SetClipsChildren(true) -- rows that don't fit must not draw over the table's footer
	end
	for index = 1, PLACEHOLDER_ROWS do
		createPlaceholderRow(bars, index, self.rowHeight, theme.surface3)
	end
	addPulse(bars)
	keepNoteCurrent(self, loading)
	loading:Hide()
	self.loadingFrame = loading
end

--- Shows placeholder rows while the rows are still being worked out. `note` is the line above them,
--- a string or a function returning one (read again while shown, for live progress). Pass nil once
--- the rows are known: an empty table then shows its empty-state message. Rows already in the table
--- stay visible while loading.
function TableMixin:SetLoading(note)
	self.loadingNote = note
	self:UpdateEmptyState()
end

function TableMixin:UpdateLoadingNote()
	local note = self.loadingNote
	if type(note) == "function" then
		note = note()
	end
	self.loadingFrame.note:SetText(note or "Loading…")
end

-- Called by UpdateEmptyState: the loading state is built the first time a table needs it.
function TableMixin:ShowLoadingState(show)
	if not show and not self.loadingFrame then
		return
	end
	if not self.loadingFrame then
		self:CreateLoadingState()
	end
	self.loadingFrame:SetShown(show)
	if show then
		self:UpdateLoadingNote()
	end
end
