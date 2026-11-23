-- Run with: lua5.1 tests/test_bag_buttons.lua (from Tradewright root); npm test runs it too.
-- Live bag slots are the game's own item buttons. Addon code must not write their bag ID: the
-- game's click code would pass that tainted value to protected calls (Pick Lock on a lockbox).
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

-- The frame and texture calls BagButtons makes that need no result; any other missing key is nil.
local NO_OP = {}
for _, name in ipairs({ "SetAllPoints", "SetPoint", "ClearAllPoints", "SetTexCoord", "SetAlpha",
	"SetColorTexture", "SetTexture", "SetSize", "Hide", "Show", "HookScript" }) do
	NO_OP[name] = function() end
end

local function noOpMethods(methods)
	return function(_, key)
		return methods[key] or NO_OP[key]
	end
end

local function newTexture()
	return setmetatable({}, { __index = noOpMethods({}) })
end

-- A frame stub: IDs and fields the addon sets land on the table, so the test can read them back.
local function newFrame(name, parent, template)
	local frame = { name = name, parent = parent, template = template }
	local methods = {
		SetID = function(self, id) rawset(self, "id", id) end,
		GetID = function(self) return rawget(self, "id") end,
		GetParent = function(self) return rawget(self, "parent") end,
		GetName = function(self) return rawget(self, "name") end,
		SetBagID = function(self, bag) rawset(self, "bagID", bag) end,
		CreateTexture = newTexture,
		CreateFontString = newTexture,
	}
	return setmetatable(frame, { __index = noOpMethods(methods) })
end

_G.CreateFrame = function(_, name, parent, template)
	return newFrame(name, parent, template)
end

local pe = {}
for _, path in ipairs({ "/src/util/Tradewright_ThemeLogic.lua", "/src/ui/Tradewright_Theme.lua",
	"/../Tradewright_Bags/src/Tradewright_BagButtons.lua" }) do
	local chunk, err = loadfile(root .. path)
	assert(chunk, err)
	chunk("Tradewright_Bags", pe)
end

local content = newFrame(nil, nil)
local button = pe:AcquireLiveBagSlot(content, 3, 7)
check("Live slot uses the game's item button template", button.template == "ContainerFrameItemButtonTemplate")
check("Live slot ID is the slot", button:GetID() == 7)
check("Live slot's parent ID is the bag", button:GetParent():GetID() == 3)
check("Addon never writes the bag ID onto the game's button", rawget(button, "bagID") == nil)
check("Same slot gives the same button", pe:AcquireLiveBagSlot(content, 3, 7) == button)

if failed > 0 then
	print(failed .. " bag button check(s) failed")
	os.exit(1)
end
print("All bag button checks passed")
