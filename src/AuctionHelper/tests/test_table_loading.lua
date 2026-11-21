-- Run with: lua5.1 tests/test_table_loading.lua (from AuctionHelper root); npm test runs it too.
-- A table whose rows are still being worked out must show its loading state, never the
-- empty-state message that says there is nothing to show.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

-- Frame stub: remembers whether it is shown and its text; every other call does nothing.
local function newRegion()
	local region = { shown = true }
	return setmetatable(region, { __index = function(_, key)
		if key == "SetShown" then
			return function(self, show) self.shown = show == true end
		elseif key == "Hide" then
			return function(self) self.shown = false end
		elseif key == "SetText" then
			return function(self, text) self.text = text end
		elseif key == "CreateTexture" or key == "CreateFontString" or key == "CreateAnimationGroup" or key == "CreateAnimation" then
			return function() return newRegion() end
		end
		return function() end
	end })
end
_G.CreateFrame = function() return newRegion() end

local color = { r = 0.5, g = 0.5, b = 0.5 }
local pe = { GetTheme = function() return { textMuted = color, surface3 = color } end }
for _, path in ipairs({ "/src/util/AuctionHelper_FilterLogic.lua", "/../AuctionHelper_UI/src/ui/AuctionHelper_Table.lua",
	"/../AuctionHelper_UI/src/ui/AuctionHelper_TableLoading.lua" }) do
	local chunk, err = loadfile(root .. path)
	assert(chunk, err)
	chunk("AuctionHelper", pe)
end

local function newTable(rows)
	local widget = setmetatable({ displayRows = rows, rowHeight = 20, frame = newRegion(), scrollFrame = newRegion() },
		{ __index = pe.TableMixin })
	widget.emptyFrame = newRegion()
	widget.emptyFrame.title, widget.emptyFrame.hint = newRegion(), newRegion()
	return widget
end

local waiting = newTable({})
waiting:SetLoading("Reading auction scans · 40%")
check("Loading table hides the empty-state message", waiting.emptyFrame.shown == false)
check("Loading table shows its placeholder rows", waiting.loadingFrame and waiting.loadingFrame.shown == true)
check("Loading note is shown", waiting.loadingFrame.note.text == "Reading auction scans · 40%")

local progress = 10
waiting:SetLoading(function() return string.format("%d of 50 recipes", progress) end)
progress = 25
waiting:UpdateLoadingNote()
check("A function note is read again for live progress", waiting.loadingFrame.note.text == "25 of 50 recipes")

waiting:SetLoading(nil)
check("Done loading with no rows: empty-state message", waiting.emptyFrame.shown == true)
check("Done loading: placeholder rows hidden", waiting.loadingFrame.shown == false)

local filling = newTable({})
filling:SetLoading("Reading auction scans · 90%")
filling.displayRows = { { itemID = 2 } } -- what Refresh leaves after SetRows
filling:UpdateEmptyState()
check("Rows arriving replace the placeholder rows", filling.loadingFrame.shown == false and filling.emptyFrame.shown == false)

local stale = newTable({ { itemID = 1 } })
stale:SetLoading("Working out craft profit")
check("Rows already shown stay while loading", stale.emptyFrame.shown == false)
check("No placeholder rows over real rows", stale.loadingFrame == nil)

if failed > 0 then
	print(failed .. " table loading check(s) failed")
	os.exit(1)
end
print("All table loading checks passed")
