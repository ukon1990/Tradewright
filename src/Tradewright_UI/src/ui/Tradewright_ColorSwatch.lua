local _, Tradewright = ...

-- A small colour box that opens the game's colour picker.

local SWATCH_WIDTH, SWATCH_HEIGHT = 44, 18

-- Opens the game's colour picker on `color`. Every colour tried there goes to onPick({ r, g, b }),
-- and `color` again when the player cancels.
local function openColorPicker(color, onPick)
	local function picked()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		onPick({ r = r, g = g, b = b })
	end
	local function cancelled()
		onPick({ r = color.r, g = color.g, b = color.b })
	end
	-- Newer clients take one setup call; older ones read fields set on the frame. Forever is checked
	-- by capability because it may carry either.
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = color.r, g = color.g, b = color.b, hasOpacity = false, swatchFunc = picked, cancelFunc = cancelled,
		})
		return
	end
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.func, ColorPickerFrame.cancelFunc = picked, cancelled
	ColorPickerFrame:SetColorRGB(color.r, color.g, color.b)
	ShowUIPanel(ColorPickerFrame)
end

--- A colour box showing getColor(). A click opens the colour picker, which calls setColor({ r, g, b })
--- for every colour tried. Call swatch:Refresh() when the colour changed elsewhere.
function Tradewright:CreateColorSwatch(parent, getColor, setColor)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(SWATCH_WIDTH, SWATCH_HEIGHT)
	local surface = self:AddSurface(swatch, getColor(), self:GetTheme().borderControl)
	function swatch:Refresh()
		surface:SetColors(getColor())
	end
	swatch:SetScript("OnClick", function()
		openColorPicker(getColor(), function(color)
			setColor(color)
			swatch:Refresh()
		end)
	end)
	return swatch
end
