local _, Tradewright = ...

local L = Tradewright.L or setmetatable({}, { __index = function(_, text) return text end })
-- A button for one game key binding. It saves to the game's own key bindings, so the game's
-- Key Bindings window shows the same key.

local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true,
}

-- The game names a key with its modifiers in this order: ALT-CTRL-SHIFT-KEY.
local function pressedKey(key)
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

-- Unbinds every key bound to `binding` (GetBindingKey returns all of them).
local function clearBinding(binding)
	for _, key in ipairs({ GetBindingKey(binding) }) do
		SetBinding(key)
	end
end

local function bindKey(binding, key)
	clearBinding(binding)
	if key then
		SetBinding(key, binding)
	end
	SaveBindings(GetCurrentBindingSet())
end

--- Shows the key bound to `binding`. A click takes the next key pressed (Escape cancels), a
--- right-click clears it. Bindings can't change in combat, so clicks then do nothing.
function Tradewright:CreateKeyBindingButton(parent, binding, width)
	local button = self:CreateButton(parent, "", nil, { width = width })
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	function button:Refresh()
		local key = GetBindingKey(binding)
		self:SetText(self.capturing and L["Press a key…"] or key and GetBindingText(key) or L["Not set"])
	end
	local function stopCapture()
		button.capturing = false
		button:EnableKeyboard(false)
		button:Refresh()
	end
	button:SetScript("OnClick", function(self, mouseButton)
		if InCombatLockdown() then
			return
		end
		if mouseButton == "RightButton" then
			bindKey(binding, nil)
			return stopCapture()
		end
		self.capturing = true
		self:EnableKeyboard(true)
		self:SetPropagateKeyboardInput(false)
		self:Refresh()
	end)
	button:SetScript("OnKeyDown", function(_, key)
		if MODIFIER_KEYS[key] then
			return
		end
		if key ~= "ESCAPE" and not InCombatLockdown() then
			bindKey(binding, pressedKey(key))
		end
		stopCapture()
	end)
	button:SetScript("OnHide", stopCapture)
	button:EnableKeyboard(false)
	button:Refresh()
	return button
end
