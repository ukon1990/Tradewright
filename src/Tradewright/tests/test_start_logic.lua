-- Run with: lua5.1 tests/test_start_logic.lua (from Tradewright root)
-- The Get started steps tick off from saved data, and the first open one is marked as next.
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

local pe = {}
assert(loadfile(root .. "/src/util/Tradewright_StartLogic.lua"))("Tradewright", pe)
local StartLogic = pe.StartLogic

local new = StartLogic.Progress({ hasFullScan = false, hasProfessionScan = false, scanDays = 0 })
check("New player: nothing done, the full scan is next", new.doneCount == 0 and new.nextIndex == 1)

local scanned = StartLogic.Progress({ hasFullScan = true, hasProfessionScan = false, scanDays = 1 })
check("After the first full scan: the profession scan is next", scanned.doneCount == 1 and scanned.nextIndex == 2)

local professionFirst = StartLogic.Progress({ hasFullScan = false, hasProfessionScan = true, scanDays = 0 })
check("Profession scanned first: the full scan is still next", professionFirst.doneCount == 1 and professionFirst.nextIndex == 1)

local waiting = StartLogic.Progress({ hasFullScan = true, hasProfessionScan = true, scanDays = StartLogic.SCAN_DAYS_NEEDED - 1 })
check("One scan day short: the last step stays open", waiting.doneCount == 2 and waiting.nextIndex == 3)

local done = StartLogic.Progress({ hasFullScan = true, hasProfessionScan = true, scanDays = StartLogic.SCAN_DAYS_NEEDED })
check("Enough scan days: every step is done", done.doneCount == 3 and done.nextIndex == nil)

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All start logic tests passed")
