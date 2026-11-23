-- The export copy box: the SavedVariables copy, page splitting and the window that shows the package text.
local addonName, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
--- Persist compressed export package for pickup after /reload.
function Tradewright:SaveExportToSavedVariables(payload, meta)
	if type(payload) ~= "string" or payload == "" then
		return false
	end
	TradewrightLastExport = TradewrightLastExport or {}
	TradewrightLastExport.savedAt = time()
	TradewrightLastExport.byteLength = #payload
	TradewrightLastExport.scope = meta and meta.scope or nil
	TradewrightLastExport.module = meta and meta.module or nil
	TradewrightLastExport.characterKey = meta and meta.characterKey or nil
	TradewrightLastExport.professionIdentifier = meta and meta.professionIdentifier or nil
	TradewrightLastExport.payload = nil
	local isLua = type(payload) == "string" and payload:sub(1, 7) == "AHLUA1:"
	TradewrightLastExport.format = isLua and "AHLUA1" or (self.EXPORT_FORMAT or "AHCBOR1")
	TradewrightLastExport.encoding = isLua and "lua-text" or "cbor+deflate+base64"
	local persistFull = self:GetSetting("general.persistLastExport", true) == true
	if not persistFull then
		TradewrightLastExport.persisted = false
		return false
	end
	if #payload > self.MAX_SAVEDEXPORT_BYTES then
		TradewrightLastExport.persisted = false
		return false
	end
	TradewrightLastExport.persisted = true
	TradewrightLastExport.payload = payload
	return true
end

function Tradewright:CopyBoxBuildFooterText(opts)
	opts = opts or {}
	if opts.unsavedHint and opts.unsavedHint ~= "" then
		return opts.unsavedHint
	end
	if opts.savedToVariables then
		return L["Also saved for /reload: SavedVariables/Tradewright.lua, TradewrightLastExport"]
	end
	return ""
end

function Tradewright:BuildCopyBoxPagedWrapperJson(pageIndex, pageCount, payloadFragment)
	return string.format("AHPAGE:%d/%d\n%s", pageIndex, pageCount, payloadFragment)
end

--- Build segment list: each { startPos, length } into fullJson; each wrapped page <= maxWrappedBytes.
--- Uses byte-length estimates in the binary search (no JsonEscape per probe), verifies with one Build per page.
--- Must run inside a coroutine; yields to spread work across frames.
function Tradewright:ComputeCopyBoxPagingSegmentsYielding(fullJson, maxWrappedBytes)
	local placeholder = self.COPYBOX_PAGING_PLACEHOLDER_PAGE_COUNT or 9999999
	local yieldInnerEvery = self.COPYBOX_PAGING_YIELD_INNER_STEPS or 32
	local segments = {}
	local len = #fullJson
	local pos = 1
	local pageIdx = 1
	local innerSteps = 0
	local function maybeYieldInner()
		innerSteps = innerSteps + 1
		if innerSteps >= yieldInnerEvery then
			innerSteps = 0
			coroutine.yield()
		end
	end

	while pos <= len do
		coroutine.yield()
		local remain = len - pos + 1
		local lo, hi = 1, remain
		local best = 1
		while lo <= hi do
			maybeYieldInner()
			local mid = math.floor((lo + hi) / 2)
			local frag = string.sub(fullJson, pos, pos + mid - 1)
			local est = self:EstimateCopyBoxWrappedPagingByteLength(pageIdx, placeholder, frag)
			if est <= maxWrappedBytes then
				best = mid
				lo = mid + 1
			else
				hi = mid - 1
			end
		end
		best = math.max(best, 1)
		while best >= 1 do
			local frag = string.sub(fullJson, pos, pos + best - 1)
			if #self:BuildCopyBoxPagedWrapperJson(pageIdx, placeholder, frag) <= maxWrappedBytes then
				break
			end
			best = best - 1
		end
		best = math.max(best, 1)
		table.insert(segments, { pos, best })
		pos = pos + best
		pageIdx = pageIdx + 1
	end
	return segments
end

--- Runs ComputeCopyBoxPagingSegmentsYielding via C_Timer (same pattern as RunEncodeJsonAsync).
function Tradewright:RunComputeCopyBoxPagingAsync(fullJson, maxWrappedBytes, onComplete)
	if type(onComplete) ~= "function" then
		return
	end

	local co = coroutine.create(function()
		return self:ComputeCopyBoxPagingSegmentsYielding(fullJson, maxWrappedBytes)
	end)

	local function oneStep()
		local ok, ret = coroutine.resume(co)
		if not ok then
			onComplete(nil, ret)
			return
		end
		if coroutine.status(co) == "dead" then
			onComplete(ret, nil)
			return
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(0, oneStep)
		else
			oneStep()
		end
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(0, oneStep)
	else
		while true do
			local ok2, ret2 = coroutine.resume(co)
			if not ok2 then
				onComplete(nil, ret2)
				return
			end
			if coroutine.status(co) == "dead" then
				onComplete(ret2, nil)
				return
			end
		end
	end
end

function Tradewright:EncodeCopyBoxWrappedPage(fullJson, seg, pageIndex, totalPages)
	local frag = string.sub(fullJson, seg[1], seg[1] + seg[2] - 1)
	return self:BuildCopyBoxPagedWrapperJson(pageIndex, totalPages, frag)
end

function Tradewright:LayoutCopyFrameScroll(copyFrame, useEnvelopePaging)
	if not copyFrame or not copyFrame.pageHintStr then
		return
	end
	local intro = L["The text is selected. Press Ctrl+C, then paste it where you need it."]
	if useEnvelopePaging then
		intro = intro .. L[" This package has several pages: copy each page and join them in order."]
	end
	copyFrame.pageHintStr:SetText(intro)
	local pages = copyFrame._numPages or 1
	copyFrame.metaStr:SetText(string.format(L["%s bytes%s"],
		self.FormatNumberGrouped and self:FormatNumberGrouped(copyFrame._fullLen or 0) or tostring(copyFrame._fullLen or 0),
		useEnvelopePaging and pages > 1 and string.format(L[" · %d pages"], pages) or ""))
end

function Tradewright:CopyBoxApplyCurrentPage()
	local state = self:GetState()
	local cf = state.copyFrame
	if not cf or not cf._fullJson then
		return
	end
	if cf._pagingSegmentsPending then
		cf.editBox:SetText(L["Preparing paged export…"])
		if cf.pageLabel then
			cf.pageLabel:SetText("…")
		end
		if cf.btnPrev then
			cf.btnPrev:SetEnabled(false)
		end
		if cf.btnNext then
			cf.btnNext:SetEnabled(false)
		end
		if cf.pageBar then
			cf.pageBar:SetShown(true)
		end
		return
	end
	local p = cf._pageIndex
	local numPages = cf._numPages
	local body
	if cf._pagingMode == "envelope" and cf._segments and cf._segments[p] then
		body = self:EncodeCopyBoxWrappedPage(cf._fullJson, cf._segments[p], p, numPages)
	elseif cf._pagingMode == "raw" then
		body = cf._fullJson
	else
		body = cf._fullJson or ""
	end
	cf.editBox:SetText(body)
	if cf.pageLabel then
		if cf._pagingMode == "envelope" and numPages > 1 then
			cf.pageLabel:SetText(string.format(L["Page %d of %d"], p, numPages))
		else
			cf.pageLabel:SetText(L["Page 1 of 1"])
		end
	end
	if cf.btnPrev then
		cf.btnPrev:SetEnabled(cf._pagingMode == "envelope" and p > 1)
	end
	if cf.btnNext then
		cf.btnNext:SetEnabled(cf._pagingMode == "envelope" and p < numPages)
	end
	if cf.pageBar then
		cf.pageBar:SetShown(cf._pagingMode == "envelope" and numPages > 1)
	end
	cf.editBox:HighlightText()
	cf.editBox:SetFocus()
end

function Tradewright:CopyBoxGoPage(delta)
	local state = self:GetState()
	local cf = state.copyFrame
	if not cf or cf._pagingMode ~= "envelope" or not cf._segments or cf._numPages <= 1 then
		return
	end
	cf._pageIndex = math.max(1, math.min(cf._numPages, cf._pageIndex + delta))
	self:CopyBoxApplyCurrentPage()
end

local function themedText(parent, font, colorKey, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", font)
	local color = Tradewright:GetTheme()[colorKey or "textPrimary"]
	Tradewright:ColorText(text, color)
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	return text
end

local function themedButton(parent, label, onClick, primary)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(label)
	Tradewright:SkinButton(button)
	button:SetSize(math.ceil(button:GetFontString():GetStringWidth()) + 24, Tradewright:GetTheme().size.control)
	if primary then
		Tradewright:SetButtonPrimary(button, true)
	end
	button:SetScript("OnClick", onClick)
	return button
end

-- The export window: header, one-line instructions, the selectable package text, page controls and
-- a footer saying where else the package was saved. Uses only core theme helpers.
function Tradewright:CreateCopyFrame()
	local theme = self:GetTheme()
	local pad = theme.spacing.md
	local f = CreateFrame("Frame", addonName .. "CopyFrame", UIParent, "BackdropTemplate")
	f:SetPoint("CENTER")
	f:SetSize(720, 560)
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(200)
	self:StyleWindow(f)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, f:GetName())

	local headerY = -(theme.size.header / 2)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:ClearAllPoints()
	close:SetPoint("RIGHT", f, "TOPRIGHT", -6, headerY)
	self:SkinCloseButton(close)
	close:SetScript("OnClick", function() f:Hide() end)
	f.closeXButton = close
	f.metaStr = themedText(f, "GameFontHighlightSmall", "textMuted", "RIGHT")
	f.metaStr:SetPoint("RIGHT", close, "LEFT", -10, 0)
	f.copyTitle = themedText(f, "GameFontNormalLarge", "gold")
	f.copyTitle:SetPoint("LEFT", f, "TOPLEFT", pad, headerY - 1)
	f.copyTitle:SetPoint("RIGHT", f.metaStr, "LEFT", -12, 0)
	f.copyTitle:SetText(L["Export"])
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", 1, -theme.size.header)
	rule:SetPoint("TOPRIGHT", -1, -theme.size.header)
	rule:SetHeight(1)
	Tradewright:ColorTexture(rule, "borderSubtle", 1)

	local footer = CreateFrame("Frame", nil, f)
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(theme.size.footer)
	local footerRule = footer:CreateTexture(nil, "BORDER")
	footerRule:SetPoint("TOPLEFT")
	footerRule:SetPoint("TOPRIGHT")
	footerRule:SetHeight(1)
	Tradewright:ColorTexture(footerRule, "borderSubtle", 1)
	f.footerStr = themedText(footer, "GameFontHighlightSmall", "textMuted")
	f.footerStr:SetPoint("LEFT", pad, 0)
	f.footerStr:SetPoint("RIGHT", -pad, 0)

	f.pageHintStr = themedText(f, "GameFontHighlightSmall", "textMuted")
	f.pageHintStr:SetWordWrap(true)
	f.pageHintStr:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(theme.size.header + 1 + pad))
	f.pageHintStr:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -(theme.size.header + 1 + pad))

	local actions = CreateFrame("Frame", nil, f)
	actions:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", pad - 1, pad)
	actions:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -(pad - 1), pad)
	actions:SetHeight(theme.size.control)
	local done = themedButton(actions, "Close", function() f:Hide() end, true)
	done:SetPoint("RIGHT")
	local selectAll = themedButton(actions, L["Select all"], function()
		f.editBox:SetFocus()
		f.editBox:HighlightText()
	end)
	selectAll:SetPoint("RIGHT", done, "LEFT", -8, 0)
	f.pageBar = CreateFrame("Frame", nil, actions)
	f.pageBar:SetPoint("TOPLEFT")
	f.pageBar:SetPoint("BOTTOMLEFT")
	f.pageBar:SetWidth(260)
	f.btnPrev = themedButton(f.pageBar, "Previous", function() Tradewright:CopyBoxGoPage(-1) end)
	f.btnPrev:SetPoint("LEFT")
	f.pageLabel = themedText(f.pageBar, "GameFontHighlightSmall", "textMuted", "CENTER")
	f.pageLabel:SetPoint("LEFT", f.btnPrev, "RIGHT", 8, 0)
	f.pageLabel:SetWidth(76)
	f.btnNext = themedButton(f.pageBar, "Next", function() Tradewright:CopyBoxGoPage(1) end)
	f.btnNext:SetPoint("LEFT", f.pageLabel, "RIGHT", 8, 0)

	-- The package text sits in a raised, clipped box; the edit box follows the scroll width.
	local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
	box:SetPoint("TOPLEFT", f.pageHintStr, "BOTTOMLEFT", 0, -10)
	box:SetPoint("BOTTOMRIGHT", actions, "TOPRIGHT", 0, pad)
	self:ApplyBackdrop(box, theme.surface2, theme.borderControl)
	if box.SetClipsChildren then
		box:SetClipsChildren(true)
	end
	local scrollFrame = CreateFrame("ScrollFrame", addonName .. "CopyScrollFrame", box, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 8, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", -18, 8)
	local editBox = CreateFrame("EditBox", addonName .. "CopyEditBox", scrollFrame)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(true)
	editBox:SetFontObject(ChatFontNormal)
	Tradewright:ColorText(editBox, "textMuted")
	editBox:SetWidth(600)
	editBox:SetScript("OnEscapePressed", function() f:Hide() end)
	scrollFrame:SetScrollChild(editBox)
	scrollFrame:SetScript("OnSizeChanged", function(_, width)
		editBox:SetWidth(math.max(100, width))
	end)
	f.scrollFrame = scrollFrame
	f.editBox = editBox
	self:SkinTree(f)
	return f
end

--- opts: fullByteLength, savedToVariables, unsavedHint
function Tradewright:ShowCopyBox(text, opts)
	opts = opts or {}
	local state = self:GetState()
	local copyFrame = state.copyFrame
	local fullJson = text or ""
	local fullLen = opts.fullByteLength or #fullJson
	local rawSingleLimit = self.COPYBOX_PAGE_BYTES or self.COPYBOX_JSON_PREVIEW_BYTES or (48 * 1024)
	local maxWrapped = self.COPYBOX_WRAPPED_PAGE_MAX_BYTES or rawSingleLimit
	if maxWrapped < 4096 then
		maxWrapped = 4096
	end

	local useEnvelope = fullLen > rawSingleLimit
	local segments
	local numPages
	local pagingMode
	local footerText

	if useEnvelope then
		pagingMode = "envelope"
		numPages = 1
		segments = nil
		footerText = self:CopyBoxBuildFooterText(opts)
	else
		numPages = 1
		pagingMode = "raw"
		footerText = self:CopyBoxBuildFooterText(opts)
	end

	if not copyFrame then
		copyFrame = self:CreateCopyFrame()
		state.copyFrame = copyFrame
	end

	copyFrame._fullJson = fullJson
	copyFrame._fullLen = fullLen
	copyFrame._segments = segments
	copyFrame._numPages = numPages
	copyFrame._pageIndex = 1
	copyFrame._pagingMode = pagingMode
	copyFrame._opts = opts
	copyFrame._pagingSegmentsPending = useEnvelope and true or false

	self:LayoutCopyFrameScroll(copyFrame, useEnvelope)

	if footerText ~= "" then
		copyFrame.footerStr:SetText(footerText)
		copyFrame.footerStr:Show()
	else
		copyFrame.footerStr:SetText("")
		copyFrame.footerStr:Hide()
	end

	copyFrame:Show()
	Tradewright:SkinTree(copyFrame)
	self:CopyBoxApplyCurrentPage()

	if useEnvelope then
		copyFrame._pagingToken = (copyFrame._pagingToken or 0) + 1
		local myToken = copyFrame._pagingToken
		self:RunComputeCopyBoxPagingAsync(fullJson, maxWrapped, function(computedSegments, err)
			if not copyFrame or copyFrame._pagingToken ~= myToken then
				return
			end
			copyFrame._pagingSegmentsPending = false
			if err or type(computedSegments) ~= "table" then
				copyFrame._pagingMode = "raw"
				copyFrame._segments = nil
				copyFrame._numPages = 1
				self:LayoutCopyFrameScroll(copyFrame, false)
				copyFrame.editBox:SetText(
					L["Paging failed: "]
						.. tostring(err or L["unknown error"])
						.. L["\n\nTry exporting a smaller scope (for example one profession or compact auction/inventory data)."]
				)
				return
			end
			local np = math.max(#computedSegments, 1)
			local useEnv = np > 1
			if not useEnv then
				copyFrame._pagingMode = "raw"
				copyFrame._segments = nil
				copyFrame._numPages = 1
				self:LayoutCopyFrameScroll(copyFrame, false)
			else
				copyFrame._pagingMode = "envelope"
				copyFrame._segments = computedSegments
				copyFrame._numPages = np
				self:LayoutCopyFrameScroll(copyFrame, true)
			end
			copyFrame._pageIndex = 1
			local ft = self:CopyBoxBuildFooterText(copyFrame._opts or {})
			if ft ~= "" then
				copyFrame.footerStr:SetText(ft)
				copyFrame.footerStr:Show()
			end
			self:CopyBoxApplyCurrentPage()
		end)
	end
end
