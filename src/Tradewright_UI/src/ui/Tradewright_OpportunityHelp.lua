local Tradewright = select(2, ...)

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- Help for the Opportunities lists: "How this list works" in the side pane with no row selected,
-- and an empty list's funnel, which names the rule that left nothing and the setting or step that fixes it.
-- A step's `label` and `fix` are text or `function(pe, insights)`.

local SCAN_FIX = L["Open the auction house and run a full scan."]
local KNOWN_FIX = L["Prices need scans on 5 different days; sales need two scans of an item within a day."]

local function money(pe, copper)
	return pe:FormatCopperShort(copper)
end

local function usualFix(pe, insights)
	local coverage = pe:GetHistoryCoverage(insights)
	local text = string.format(L["A usual price needs scans on 5 different days. Your best item has %d. Today's scans count from tomorrow."],
		coverage.bestDays)
	if coverage.early > 0 and not pe:GetSetting("opportunities.allowEarly", false) then
		text = text .. L[" Or turn on \"Also show items with only 2 to 4 days of prices\" in Settings, Opportunities."]
	end
	return text
end

local OFF = { label = L["This list is turned off"], fix = L["Turn it on in Settings, Opportunities."] }

local HELP = {
	flips = {
		title = L["How flips work"],
		body = L["Items listed well below their usual price that also sell, so you can buy them and list them again.\n\n"]
			.. L["Usual price: the middle of your daily scan prices over the last 14 days. It needs scans on 5 different days.\n\n"]
			.. L["Sales a day: guessed from how many listings vanish between two of your scans. It needs two scans within a day.\n\n"]
			.. L["Profit is after the auction cut. Buy is capped at a third of a day's sales so they can sell at the usual price.\n\n"]
			.. L["Settings, Opportunities changes how cheap, how busy and how profitable a flip must be."],
		steps = {
			scanned = { label = L["items in the last scan"], fix = SCAN_FIX },
			usual = { label = L["have a usual price"], fix = usualFix },
			sells = { label = L["also have a sales estimate"], fix = L["Sales are guessed from two scans of an item within a day. Scan again later today."] },
			under = {
				label = function(pe) return string.format(L["are %d%% or more below it"], math.floor(pe:GetFlipOptions().minDiscount * 100 + 0.5)) end,
				fix = L["Nothing is cheap enough now. Scan again later, or lower \"Count as a flip when below the usual price by\" in Settings."],
			},
			sellEnough = {
				label = function(pe) return string.format(L["sell %s or more a day"], pe:GetFlipOptions().minSellsPerDay) end,
				fix = L["Lower \"An item must sell at least\" in Settings."],
			},
			worth = {
				label = function(pe) return string.format(L["make %s or more"], money(pe, pe:GetFlipOptions().minProfit)) end,
				fix = L["Lower \"Smallest profit worth showing\" in Settings."],
			},
		},
	},
	vendor = {
		title = L["How sure things work"],
		body = L["Items listed for less than a vendor pays for them. Buy them and sell them to any vendor: no auction cut, no waiting.\n\n"]
			.. L["Needs only one scan. The game learns vendor prices as items are seen, so the list can grow for a minute after you open it.\n\n"]
			.. L["Someone else may buy them first."],
		steps = {
			scanned = { label = L["items in the last scan"], fix = SCAN_FIX },
			vendorKnown = { label = L["have a known vendor price"], fix = L["Vendor prices load as items are seen. Look again in a minute."] },
			under = { label = L["are listed below it"], fix = L["Nobody lists below vendor price right now. Check after the next scan."] },
			worth = { label = L["make 10s or more"], fix = L["Only tiny profits right now. Check after the next scan."] },
		},
	},
	gaps = {
		title = L["How price gaps work"],
		body = L["A few cheap listings below a much higher next price. Buy the cheap ones and list them just below the next price.\n\n"]
			.. L["Risky: anyone can list under you before yours sell. Only items that sell 5 or more a day are shown.\n\n"]
			.. L["Needs price steps from a full scan, a usual price (5 scan days) and a sales estimate.\n\n"]
			.. L["Settings, Opportunities sets the most you spend to clear one gap."],
		steps = {
			scanned = { label = L["items in the last scan"], fix = SCAN_FIX },
			steps = { label = L["have price steps"], fix = L["Price steps come from a full scan. Run one."] },
			known = { label = L["have a usual price and a sales estimate"], fix = KNOWN_FIX },
			worth = {
				label = L["have a gap that fits"],
				fix = function(pe)
					return string.format(L["A gap needs listings 25%% below the next price, 5+ sales a day and at most %s to clear."]
						.. L[" Raise \"Price gaps cost at most\" in Settings."], money(pe, pe:GetGapOptions().maxCost))
				end,
			},
		},
	},
	sell = {
		title = L["How sell now works"],
		body = L["Things you own whose lowest price now is 10% or more above usual and that sell, so now is a good time to list them.\n\n"]
			.. L["Counts bags and bank of this character. Worth is at today's lowest price, after the auction cut.\n\n"]
			.. L["Needs a usual price (5 scan days) and a sales estimate for each item."],
		steps = {
			owned = { label = L["items you own"], fix = L["Open your bags and bank once so they are saved."] },
			scanned = { label = L["are in the last scan"], fix = SCAN_FIX },
			known = { label = L["have a usual price and a sales estimate"], fix = KNOWN_FIX },
			worth = { label = L["are 10% or more above usual"], fix = L["Nothing you own is priced high right now."] },
		},
	},
}

local function resolve(pe, value, insights)
	if type(value) == "function" then
		return value(pe, insights)
	end
	return value
end

-- "312 have a usual price"; the turned-off step has no count.
local function stepLine(pe, info, step, insights)
	local label = resolve(pe, info.label, insights)
	return step.key == "off" and label or pe:FormatNumberGrouped(step.count) .. " " .. label
end

--- Title and text for the side pane of a list with no row selected.
function Tradewright:GetOpportunityHelp(view)
	local help = HELP[view.id]
	if not help then
		return L["Select a row"], L["Click a row to see the sums behind it and what could go wrong."]
	end
	return help.title, help.body .. L["\n\nClick a row to see its sums and what could go wrong."]
end

--- Title and hint for an empty list: each step of the funnel down to the first that kept nothing, that
--- step in the warning colour, then how to get past it. Without a funnel the view's fixed text.
function Tradewright:GetOpportunityEmptyText(view, funnel, insights)
	local help = HELP[view.id]
	local stuck = self.FlipLogic.FirstEmptyStep(funnel)
	if not (help and stuck) then
		return view.emptyTitle, view.emptyHint
	end
	local lines = {}
	for _, step in ipairs(funnel) do
		if step == stuck then
			break
		end
		lines[#lines + 1] = stepLine(self, help.steps[step.key], step, insights)
	end
	local info = stuck.key == "off" and OFF or help.steps[stuck.key]
	lines[#lines + 1] = self:Colorize(stepLine(self, info, stuck, insights), "warning")
	return view.emptyTitle, table.concat(lines, "\n") .. "\n\n" .. resolve(self, info.fix, insights)
end
