local _, AuctionHelper = ...

-- Building blocks of the dashboard tabs: inset cards, cards holding a table, stat tiles, the period
-- switch, and dropdowns bound to a setting or to a filter selection.

local PAD = 10
local PERIODS = { { 7, "7 days" }, { 30, "30 days" }, { 90, "90 days" }, { 0, "All time" } }

local function hideTooltip()
	GameTooltip:Hide()
end

--- An inset card with a heading at its top left.
function AuctionHelper:CreateDashboardCard(parent, title)
	local card = self:CreateInset(parent)
	card.heading = self:CreateHeading(card, title)
	card.heading:SetPoint("TOPLEFT", PAD, -PAD)
	card.heading:SetPoint("RIGHT", -PAD, 0)
	return card
end

--- A dashboard card with a table (`card.table`) filling it below the heading. `options`: title, columns,
--- table (CreateReusableTable options; the table always fits its scroll area and, unless `onRowLeave` is
--- given, hides the tooltip when the mouse leaves a row), and optionally viewAllLabel with onViewAll for a
--- small button at the top right.
function AuctionHelper:CreateTableCard(parent, options)
	local card = self:CreateDashboardCard(parent, options.title)
	if options.viewAllLabel then
		card.viewAll = self:CreateButton(card, options.viewAllLabel, options.onViewAll, { small = true })
		card.viewAll:SetPoint("TOPRIGHT", -PAD, -7)
		card.heading:SetPoint("RIGHT", card.viewAll, "LEFT", -8, 0)
	end
	local tableOptions = options.table
	tableOptions.autoFitToScroll = true
	tableOptions.onRowLeave = tableOptions.onRowLeave or hideTooltip
	card.table = self:CreateReusableTable(card, tableOptions)
	card.table:SetColumns(options.columns)
	card.table.frame:SetPoint("TOPLEFT", card.heading, "BOTTOMLEFT", 0, -10)
	card.table.frame:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PAD, PAD)
	return card
end

--- One stat tile (CreateStat) per name, left to right. The result holds them in order (for LayoutEvenRow) and by name.
function AuctionHelper:CreateStats(parent, names)
	local stats = {}
	for index, name in ipairs(names) do
		stats[index] = self:CreateStat(parent)
		stats[name] = stats[index]
	end
	return stats
end

--- 7 days / 30 days / 90 days / All time at the card's top right, ending its heading. The choice
--- is one setting shared by the Sales and Income views; `onChange` redraws the view.
function AuctionHelper:CreatePeriodButtons(card, onChange)
	local buttons, previous = {}, nil
	for index = #PERIODS, 1, -1 do
		local days = PERIODS[index][1]
		local button = self:CreateButton(card, PERIODS[index][2], function()
			self:SetSetting("sales.periodDays", days)
			onChange()
		end, { small = true })
		button.days = days
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", 1, 0)
		else
			button:SetPoint("TOPRIGHT", -PAD, -7)
		end
		previous = button
		buttons[#buttons + 1] = button
	end
	card.heading:SetPoint("RIGHT", previous, "LEFT", -8, 0)
	return buttons
end

--- Highlights the chosen period and returns its days (0 = all time).
function AuctionHelper:StylePeriodButtons(buttons)
	local days = tonumber(self:GetSetting("sales.periodDays", 30)) or 30
	for _, button in ipairs(buttons) do
		self:StyleShellButton(button, button.days == days)
	end
	return days
end

--- A single-choice dropdown whose value is the setting `options.setting` (`options.default` when unset).
--- `options`: setting, default, width, choices (a list of { value, label }) or getChoices(), onChanged(value), tooltip.
function AuctionHelper:CreateSettingDropdown(parent, options)
	return self:CreateSingleSelectDropdown(parent, {
		width = options.width,
		options = options.choices,
		getOptions = options.getChoices,
		getValue = function() return self:GetSetting(options.setting, options.default) end,
		setValue = function(value) self:SetSetting(options.setting, value) end,
		onChanged = options.onChanged,
		tooltip = options.tooltip,
	})
end

--- A multi-choice filter whose selection lives in `ui[options.uiKey]` and, when `options.setting` is given,
--- is saved in that setting too. `options`: uiKey, setting, width, allLabel, getOptions, onChanged, label.
function AuctionHelper:CreateFilterDropdown(parent, options)
	return self:CreateMultiSelectDropdown(parent, {
		label = options.label,
		width = options.width,
		allLabel = options.allLabel,
		getOptions = options.getOptions,
		getSelection = function() return self.ui[options.uiKey] end,
		setSelection = function(selection)
			self.ui[options.uiKey] = selection
			if options.setting then
				self:SetSetting(options.setting, selection)
			end
		end,
		onChanged = options.onChanged,
	})
end
