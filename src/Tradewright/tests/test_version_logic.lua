-- Run with: lua5.1 tests/test_version_logic.lua (from Tradewright root)
-- Versions heard from other players' clients: compared as numbers, and anything odd is refused.
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
assert(loadfile(root .. "/src/util/Tradewright_VersionLogic.lua"))("Tradewright", pe)
local VersionLogic = pe.VersionLogic

check("A higher patch is newer", VersionLogic.IsNewer("1.0.2", "1.0.1"))
check("Parts compare as numbers, not as text", VersionLogic.IsNewer("1.10.0", "1.9.0") and not VersionLogic.IsNewer("1.9.0", "1.10.0"))
check("A higher major wins over lower minor and patch", VersionLogic.IsNewer("2.0.0", "1.9.9"))
check("The same version is not newer", not VersionLogic.IsNewer("1.0.1", "1.0.1"))
check("An older version is not newer", not VersionLogic.IsNewer("1.0.0", "1.0.1"))

for _, odd in ipairs({ "unknown", "1.2", "1.2.3.4", "1.2.3-beta", "v1.2.3", " 1.2.3", "1.2.x", "", ("9"):rep(30) .. ".0.0" }) do
	check("Not a version: '" .. odd .. "'", VersionLogic.Parse(odd) == nil and not VersionLogic.IsNewer(odd, "1.0.0"))
end
check("Not a version: a number or nothing", VersionLogic.Parse(12) == nil and VersionLogic.Parse(nil) == nil)
check("Nothing is newer than an unknown own version", not VersionLogic.IsNewer("9.9.9", "unknown"))

local message = VersionLogic.EncodeMessage("1.4.0")
check("A message carries the version back out", VersionLogic.DecodeMessage(message) == "1.4.0", message)
check("No message for an unknown version", VersionLogic.EncodeMessage("unknown") == nil)
for _, other in ipairs({ "1.4.0", "V abc", "V 1.4", "V1.4.0", "X 1.4.0", "V 1.4.0 extra", "" }) do
	check("Not a version message: '" .. other .. "'", VersionLogic.DecodeMessage(other) == nil)
end
check("Not a version message: not text", VersionLogic.DecodeMessage(nil) == nil and VersionLogic.DecodeMessage({}) == nil)

check("Group finder group: instance chat, also in a raid", VersionLogic.GroupChannel(true, true, true) == "INSTANCE_CHAT")
check("Raid: raid chat", VersionLogic.GroupChannel(false, true, true) == "RAID")
check("Party: party chat", VersionLogic.GroupChannel(false, false, true) == "PARTY")
check("Alone: no channel", VersionLogic.GroupChannel(false, false, false) == nil)

if failed > 0 then
	print(failed .. " test(s) failed")
	os.exit(1)
end
print("All version logic tests passed")
