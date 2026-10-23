--!strict
--[[
	SettingsPanel: only settings that really do something.
	  UI size        Scale.setUserMultiplier (every Scale root resizes)
	  Reduce motion  Tweens.reducedMotion (camera shake, shine sweeps, flying effects)
	Settings last for this session (not saved between visits yet).
]]

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Scale = require(script.Parent.Scale)
local Tweens = require(script.Parent.Parent.Feel.Tweens)

local SettingsPanel = {}

-- Set by UIController: re-renders this panel after a change.
SettingsPanel.refresh = function() end

local SIZES = {
	{ text = "Small", value = 0.85 },
	{ text = "Normal", value = 1 },
	{ text = "Big", value = 1.15 },
}
local uiSize = 1

local function choice(text: string, selected: boolean, onClick: () -> ()): TextButton
	return UIKit.button(text, onClick, {
		BackgroundColor3 = if selected then Theme.Colors.Info else Theme.Colors.Surface,
	})
end

function SettingsPanel.render(body: ScrollingFrame, _data: { [string]: any })
	local sizeButtons = {}
	for _, option in SIZES do
		table.insert(sizeButtons, choice(option.text, uiSize == option.value, function()
			uiSize = option.value
			Scale.setUserMultiplier(option.value)
			SettingsPanel.refresh()
		end))
	end
	local sizeRow = UIKit.row("UI size", "Make buttons and text bigger or smaller", sizeButtons)
	sizeRow.LayoutOrder = 1
	sizeRow.Parent = body

	local reduced = Tweens.reducedMotion
	local motionRow = UIKit.row("Reduce motion", "Less screen shake and flashy effects", {
		choice("On", reduced, function()
			Tweens.reducedMotion = true
			SettingsPanel.refresh()
		end),
		choice("Off", not reduced, function()
			Tweens.reducedMotion = false
			SettingsPanel.refresh()
		end),
	})
	motionRow.LayoutOrder = 2
	motionRow.Parent = body

	UIKit.paragraph("Settings reset when you leave the game.", {
		LayoutOrder = 3,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextMuted,
	}).Parent = body
end

return SettingsPanel
