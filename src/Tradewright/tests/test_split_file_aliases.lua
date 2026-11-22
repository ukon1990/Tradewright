-- Run with: lua5.1 tests/test_split_file_aliases.lua (from Tradewright root)
-- Files split out of one module share helpers through tables such as Tradewright.CraftReagentPlan and copy
-- them into locals at load time; this loads each addon's modules in TOC order and checks every such local is set.
local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]") or "."
local addonsRoot = root .. "/.."

local failed = 0
local function check(name, cond, detail)
	if cond then
		print("OK  " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local function readFile(path)
	local f = assert(io.open(path, "r"), path)
	local text = f:read("*a")
	f:close()
	return text
end

-- Module files of one addon, in the order its fallback TOC lists them.
local function tocModules(addon)
	local files = {}
	for line in readFile(addonsRoot .. "/" .. addon .. "/" .. addon .. ".toc"):gmatch("[^\r\n]+") do
		if line:match("^src\\modules\\.+%.lua$") then
			files[#files + 1] = addon .. "/" .. line:gsub("\\", "/")
		end
	end
	return files
end

-- Each `local name = Shared.key` (or `= Tradewright.Shared.key`) where Shared is a table on the addon object.
local function sharedAliases(text)
	local tableAliases, out = {}, {}
	for alias, tableName in text:gmatch("\nlocal (%w+) = Tradewright%.(%u%w+)\n") do
		tableAliases[alias] = tableName
	end
	for line in text:gmatch("[^\n]+") do
		local tableName, key = line:match("^local [%w_]+ = Tradewright%.(%u%w+)%.([%w_]+)$")
		if not tableName then
			local alias
			alias, key = line:match("^local [%w_]+ = (%w+)%.([%w_]+)$")
			tableName = alias and tableAliases[alias]
		end
		if tableName then
			out[#out + 1] = { tableName = tableName, key = key }
		end
	end
	return out
end

-- Just enough WoW for files that build an event frame, register a slash command or read Enum at load time.
local function anything()
	return setmetatable({}, { __index = function()
		return function() end
	end })
end
local enumValues = 0
local function enumGroup()
	return setmetatable({}, { __index = function(group, key)
		enumValues = enumValues + 1
		rawset(group, key, enumValues)
		return enumValues
	end })
end
_G.Enum = setmetatable({}, { __index = function(enum, key)
	rawset(enum, key, enumGroup())
	return rawget(enum, key)
end })
_G.CreateFrame = anything
_G.SlashCmdList = {}

-- Retail, so the retail-only files run past their early return.
local pe = { IS_RETAIL = true }
for _, addon in ipairs({ "Tradewright_Professions", "Tradewright_Inventory" }) do
	for _, file in ipairs(tocModules(addon)) do
		local chunk, err = loadfile(addonsRoot .. "/" .. file)
		check(file .. " compiles", chunk ~= nil, err)
		if chunk then
			local ok, loadErr = pcall(chunk, "Tradewright", pe)
			check(file .. " loads", ok, loadErr)
			for _, alias in ipairs(sharedAliases(readFile(addonsRoot .. "/" .. file))) do
				local shared = pe[alias.tableName]
				check(file .. " finds " .. alias.tableName .. "." .. alias.key,
					type(shared) == "table" and shared[alias.key] ~= nil)
			end
		end
	end
end

if failed > 0 then
	print(failed .. " split file alias check(s) failed")
	os.exit(1)
end
print("All split file alias checks passed")
