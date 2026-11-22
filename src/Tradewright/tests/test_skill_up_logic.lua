-- Run with: lua5.1 tests/test_skill_up_logic.lua (from Tradewright root)
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
local chunk, err = loadfile(root .. "/src/util/Tradewright_SkillUpLogic.lua")
assert(chunk, err)
chunk("Tradewright", pe)
local SL = pe.SkillUpLogic
assert(SL, "SkillUpLogic missing")

local GREY = 240

-- The game's difficulty numbers
do
	check("Names: 0 is optimal", SL.DifficultyName(0) == "optimal")
	check("Names: 1 is medium", SL.DifficultyName(1) == "medium")
	check("Names: 2 is easy", SL.DifficultyName(2) == "easy")
	check("Names: 3 is trivial", SL.DifficultyName(3) == "trivial")
	check("Names: unknown value", SL.DifficultyName(7) == nil and SL.DifficultyName(nil) == nil)
end

-- Bounds from the grey level alone
do
	local bounds = SL.DifficultyBounds(GREY, nil)
	check("Guess: yellow start is the default span below grey", bounds.yellowStart == GREY - SL.DEFAULT_YELLOW_SPAN)
	check("Guess: green start is halfway", bounds.greenStart == math.ceil((bounds.yellowStart + GREY) / 2))
	check("Guess: flagged estimated", bounds.estimated == true and bounds.greyStart == GREY)
end

-- Chance and colour at the boundaries
do
	local bounds = { yellowStart = 180, greenStart = 210, greyStart = 240 }
	check("Chance: certain while orange", SL.SkillUpChance(bounds, 179) == 1)
	check("Chance: still certain at the yellow start", SL.SkillUpChance(bounds, 180) == 1)
	check("Chance: half way down at the green start", SL.SkillUpChance(bounds, 210) == 0.5)
	check("Chance: none at grey", SL.SkillUpChance(bounds, 240) == 0 and SL.SkillUpChance(bounds, 300) == 0)
	check("Colour: orange, yellow, green, grey",
		SL.DifficultyAt(bounds, 179) == "optimal" and SL.DifficultyAt(bounds, 180) == "medium"
		and SL.DifficultyAt(bounds, 210) == "easy" and SL.DifficultyAt(bounds, 240) == "trivial")
end

-- Sightings narrow the yellow start
do
	local seenOrange = SL.RecordObservation(nil, GREY, 228, "optimal")
	local bounds = SL.DifficultyBounds(GREY, seenOrange)
	check("Orange above the guess moves the yellow start up", bounds.yellowStart == 229, bounds.yellowStart)
	check("Order kept: yellow <= green <= grey", bounds.yellowStart <= bounds.greenStart and bounds.greenStart <= bounds.greyStart)

	local seenGreen = SL.RecordObservation(nil, GREY, 212, "easy")
	check("Green at 212 caps the yellow start at 184", seenGreen.yellowStartMax == 184, seenGreen.yellowStartMax)
	check("Green below the guess moves the yellow start down", SL.DifficultyBounds(GREY, seenGreen).yellowStart == 184)

	local seenYellow = SL.RecordObservation(nil, GREY, 200, "medium")
	check("Yellow at 200: yellow start between 161 and 200",
		seenYellow.yellowStartMin == 161 and seenYellow.yellowStartMax == 200)

	local pinned = SL.RecordObservation(SL.RecordObservation(nil, GREY, 179, "optimal"), GREY, 180, "medium")
	local exact = SL.DifficultyBounds(GREY, pinned)
	check("Orange at 179 and yellow at 180 pin the start", exact.yellowStart == 180 and exact.estimated == false)
	check("Pinned start gives the green start", exact.greenStart == 210)

	local unchanged = SL.RecordObservation(pinned, GREY, 250, "trivial")
	check("A grey sighting changes nothing", unchanged.yellowStartMin == 180 and unchanged.yellowStartMax == 180)
	check("The stored observation is not modified", seenOrange.yellowStartMax == nil and pinned.yellowStartMin == 180)
end

-- Sightings that contradict each other
do
	local old = SL.RecordObservation(nil, GREY, 200, "optimal")
	local newer = SL.RecordObservation(old, GREY, 190, "easy")
	check("Newest sighting wins over a contradicting one", newer.yellowStartMax == 140 and newer.yellowStartMin == nil,
		tostring(newer.yellowStartMin) .. ".." .. tostring(newer.yellowStartMax))
	local bounds = SL.DifficultyBounds(GREY, newer)
	check("Bounds stay ordered after a contradiction", bounds.yellowStart <= bounds.greenStart and bounds.greenStart <= GREY)
end

if failed > 0 then
	os.exit(1)
end
