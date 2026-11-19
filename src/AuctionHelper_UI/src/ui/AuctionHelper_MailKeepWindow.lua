local addonName, ProfessionExporter = ...

-- Keep amounts (mailbox panel → Keep…): how many of each item this character keeps in its bags.
-- Anything above a keep amount is surplus the mailbox panel can send to the auction house / bank
-- character. Lists the sellable items in the bags and the items that already have a keep amount.

local PAD = 12

local function ensureWindow(pe)
	if pe.ui.mailKeepWindow then
		return pe.ui.mailKeepWindow
	end
	local theme = pe:GetTheme()
	local panel = pe.ui.mailPanel
	local f = CreateFrame("Frame", addonName .. "MailKeepWindow", panel, "BackdropTemplate")
	f:SetWidth(320)
	f:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
	f:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", 8, 0)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	pe:StyleWindow(f)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("RIGHT", f, "TOPRIGHT", -6, -(theme.size.header / 2))
	pe:SkinCloseButton(close)
	close:SetScript("OnClick", function() f:Hide() end)
	local title = pe:CreateText(f, "GameFontNormalLarge", "gold")
	title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(theme.size.header / 2) - 1)
	title:SetPoint("RIGHT", close, "LEFT", -PAD, 0)
	title:SetText("Keep on this character")
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", 1, -theme.size.header)
	rule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	rule:SetHeight(1)
	rule:SetColorTexture(theme.borderSubtle.r, theme.borderSubtle.g, theme.borderSubtle.b, 1)
	local intro = pe:CreateParagraph(f)
	intro:SetPoint("TOPLEFT", PAD, -(theme.size.header + 1 + PAD))
	intro:SetPoint("TOPRIGHT", -PAD, -(theme.size.header + 1 + PAD))
	intro:SetText("Click an item to set how many stay in this character's bags. Anything above that is surplus for the mailbox panel.")

	f.table = pe:CreateReusableTable(f, {
		autoFitToScroll = true,
		rowHeight = 24,
		sortKey = "name",
		sortAsc = true,
		emptyTitle = "Nothing to keep",
		emptyHint = "Your bags hold no sellable items.",
		onRowEnter = function(rowFrame, row)
			pe:ShowItemRowTooltip(rowFrame, row.itemID, nil, "Click to set how many to keep.")
		end,
		onRowLeave = function()
			GameTooltip:Hide()
		end,
		onRowClick = function(_, row)
			pe:ShowKeepPrompt(row.itemID, "Keep this many on this character", row.keep or 0, f, function(itemID, text)
				pe:SetMailKeepAmount(itemID, text)
				pe:RefreshMailPanel()
			end)
		end,
	})
	f.table:SetColumns({
		pe:CreateItemColumn({
			minWidth = 120,
			getItemID = function(row) return row.itemID end,
			getName = function(row) return row.name end,
		}),
		{ id = "quantity", label = "Bags", justifyH = "RIGHT", width = 50, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.quantity end,
			getText = function(row) return pe:FormatNumberGrouped(row.quantity) end },
		{ id = "keep", label = "Keep", justifyH = "RIGHT", width = 50, sortable = true, defaultSort = "desc",
			sortValue = function(row) return row.keep or -1 end,
			getText = function(row) return row.keep and pe:FormatNumberGrouped(row.keep) or "-" end },
	})
	f.table.frame:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	f.table.frame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
	pe:SkinTree(f)
	f:Hide()
	pe.ui.mailKeepWindow = f
	return f
end

--- Fills the window when it is open; the mailbox panel calls this on every refresh.
function ProfessionExporter:RefreshMailKeepWindow()
	local f = self.ui and self.ui.mailKeepWindow
	if not f or not f:IsShown() then
		return
	end
	f.table:SetRows(self:BuildMailKeepRows())
	f.table:Refresh()
end

function ProfessionExporter:ShowMailKeepWindow()
	local f = ensureWindow(self)
	f:SetShown(not f:IsShown())
	self:RefreshMailKeepWindow()
end
