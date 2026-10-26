--!strict
--[[
	ComboPopup: "COMBO x4!" when harvests come quickly one after another.

	Purely a feel effect: no rewards, no server state. Each harvest within
	Config.Rewards.comboWindowSeconds of the last one bumps the count; the
	text pops bigger and warmer as it climbs, then fades once you stop.
	The "Combo" sound hook plays a little higher each step.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local FeelController = require(script.Parent.Parent.Feel.FeelController)

local ComboPopup = {}

local label: TextLabel? = nil
local outline: UIStroke? = nil
local count = 0
local lastAt = 0
local token = 0

-- Colour climbs from green to gold to orange as the combo grows.
local function colorFor(n: number): Color3
	if n >= 8 then
		return Theme.Colors.Accent
	elseif n >= 4 then
		return Theme.Colors.Gold
	end
	return Theme.Colors.Primary
end

function ComboPopup.mount(parent: GuiObject)
	local text = UIKit.label("", Theme.TextSize.Huge, {
		Name = "Combo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		ZIndex = 20,
		Parent = parent,
	})
	outline = UIKit.outlineText(text, 3, true)
	if outline then
		outline.Transparency = 1
	end
	label = text
end

-- Call on every harvest of your own.
function ComboPopup.harvested()
	local now = os.clock()
	if now - lastAt <= Config.Rewards.comboWindowSeconds then
		count += 1
	else
		count = 1
	end
	lastAt = now
	local text = label
	if not text or count < 2 then
		return
	end
	token += 1
	local mine = token
	text.Text = string.format("COMBO x%d!", count)
	text.TextColor3 = colorFor(count)
	text.TextTransparency = 0
	if outline then
		outline.Transparency = 0
	end
	text.Rotation = if count % 2 == 0 then -4 else 4
	Tweens.play(text, Tweens.Ease.Pop, { Rotation = 0 })
	Tweens.pop(text, math.min(0.12 + count * 0.03, 0.45))
	FeelController.play("Combo", { count = count, pitch = math.min(1 + (count - 2) * 0.06, 1.6) })
	task.delay(Config.Rewards.comboWindowSeconds, function()
		if mine ~= token then
			return
		end
		Tweens.play(text, Tweens.Ease.Fade, { TextTransparency = 1 })
		if outline then
			Tweens.play(outline, Tweens.Ease.Fade, { Transparency = 1 })
		end
	end)
end

return ComboPopup
