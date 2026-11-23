local _, Tradewright = ...

--- Pure helper for the Get started steps a new player goes through. No WoW API.
local StartLogic = {}
Tradewright.StartLogic = StartLogic

-- A usual price needs scans on this many different days; deals and Opportunities build on it.
StartLogic.SCAN_DAYS_NEEDED = 5

--- Where the player stands, from `status = { hasFullScan, hasProfessionScan, scanDays }`:
--- `{ steps = { { id, done } }, doneCount, nextIndex }`. Steps are in the order they are shown;
--- `nextIndex` is the first open one, nil when every step is done.
function StartLogic.Progress(status)
	local steps = {
		{ id = "fullScan", done = status.hasFullScan == true },
		{ id = "professionScan", done = status.hasProfessionScan == true },
		{ id = "scanDays", done = (tonumber(status.scanDays) or 0) >= StartLogic.SCAN_DAYS_NEEDED },
	}
	local progress = { steps = steps, doneCount = 0 }
	for index, step in ipairs(steps) do
		if step.done then
			progress.doneCount = progress.doneCount + 1
		elseif not progress.nextIndex then
			progress.nextIndex = index
		end
	end
	return progress
end

return StartLogic
