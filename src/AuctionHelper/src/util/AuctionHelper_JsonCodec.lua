-- JSON codec for exports: array detection, string escaping and the plain, coroutine and timer-driven encoders.
local _, AuctionHelper = ...

function AuctionHelper:IsArray(tbl)
	if type(tbl) ~= "table" then
		return false
	end

	local index = 0
	for key in pairs(tbl) do
		if type(key) ~= "number" or key <= 0 or math.floor(key) ~= key then
			return false
		end
		if key > index then
			index = key
		end
	end

	for i = 1, index do
		if tbl[i] == nil then
			return false
		end
	end

	return true
end

function AuctionHelper:JsonEscape(text)
	text = tostring(text)
	text = text:gsub("\\", "\\\\")
	text = text:gsub('"', '\\"')
	text = text:gsub("\b", "\\b")
	text = text:gsub("\f", "\\f")
	text = text:gsub("\n", "\\n")
	text = text:gsub("\r", "\\r")
	text = text:gsub("\t", "\\t")
	return text
end

--- Byte length of BuildCopyBoxPagedWrapperJson(pageIndex, pageCount, payloadFragment).
function AuctionHelper:EstimateCopyBoxWrappedPagingByteLength(pageIndex, pageCount, payloadFragment)
	local head = string.format("AHPAGE:%d/%d\n", pageIndex, pageCount)
	return #head + #(payloadFragment or "")
end

local function encodeJsonCore(self, value, stepFn)
	stepFn = stepFn or function()
	end

	local valueType = type(value)

	if valueType == "nil" then
		return "null"
	elseif valueType == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		return tostring(value)
	elseif valueType == "boolean" then
		return value and "true" or "false"
	elseif valueType == "string" then
		return '"' .. self:JsonEscape(value) .. '"'
	elseif valueType ~= "table" then
		return '"' .. self:JsonEscape(tostring(value)) .. '"'
	end

	if self:IsArray(value) then
		stepFn()
		local parts = {}
		for index = 1, #value do
			stepFn()
			parts[index] = encodeJsonCore(self, value[index], stepFn)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end

	stepFn()
	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)

	local parts = {}
	for _, key in ipairs(keys) do
		stepFn()
		table.insert(parts, '"' .. self:JsonEscape(tostring(key)) .. '":' .. encodeJsonCore(self, value[key], stepFn))
	end

	return "{" .. table.concat(parts, ",") .. "}"
end

function AuctionHelper:EncodeJson(value)
	return encodeJsonCore(self, value, nil)
end

--- Same output as EncodeJson; must run inside a coroutine. Yields every JSON_ENCODE_YIELD_STEPS stepFn calls to spread work across frames.
--- progressTbl: optional { steps = 0 }; incremented on every encoding step for UI progress.
function AuctionHelper:EncodeJsonYielding(value, progressTbl)
	local every = self.JSON_ENCODE_YIELD_STEPS or 1000
	local n = 0
	progressTbl = progressTbl or { steps = 0 }
	local function stepFn()
		progressTbl.steps = progressTbl.steps + 1
		n = n + 1
		if n >= every then
			n = 0
			coroutine.yield()
		end
	end
	return encodeJsonCore(self, value, stepFn)
end

--- Runs EncodeJsonYielding across frames via C_Timer (fallback: tight synchronous coroutine loop).
--- onProgress: optional function(stepCount) called after each yield; also once with final count when encoding completes.
function AuctionHelper:RunEncodeJsonAsync(value, onComplete, onProgress)
	if type(onComplete) ~= "function" then
		return
	end

	local progress = { steps = 0 }
	local co = coroutine.create(function()
		return self:EncodeJsonYielding(value, progress)
	end)

	local function oneStep()
		local ok, first = coroutine.resume(co)
		if not ok then
			onComplete(nil, first)
			return
		end
		if coroutine.status(co) == "dead" then
			if onProgress then
				onProgress(progress.steps)
			end
			onComplete(first, nil)
			return
		end
		if onProgress then
			onProgress(progress.steps)
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(0, oneStep)
		end
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(0, oneStep)
	else
		while true do
			local ok, first = coroutine.resume(co)
			if not ok then
				onComplete(nil, first)
				return
			end
			if coroutine.status(co) == "dead" then
				if onProgress then
					onProgress(progress.steps)
				end
				onComplete(first, nil)
				return
			end
			if onProgress then
				onProgress(progress.steps)
			end
		end
	end
end
