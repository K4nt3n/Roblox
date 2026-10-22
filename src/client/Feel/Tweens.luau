--!strict
--[[
	Tweens: reusable motion presets. Everything that moves on screen should go
	through these so timing and easing stay consistent across the game.

	All functions are fire-and-forget and safe to call on destroyed instances.
]]

local TweenService = game:GetService("TweenService")

local Tweens = {}

-- Global toggle for players who prefer less motion (wire to a settings menu later).
Tweens.reducedMotion = false

Tweens.Ease = {
	-- Snappy and friendly: UI pops, buttons.
	Pop = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- Smooth panel movement.
	Slide = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	-- Gentle fades.
	Fade = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	-- Bouncy world objects (crops growing a stage).
	Bounce = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
	Quick = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

function Tweens.play(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween?
	if not instance or not instance.Parent then
		return nil
	end
	if Tweens.reducedMotion then
		info = TweenInfo.new(0)
	end
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

local function getScale(gui: GuiObject): UIScale
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = gui
	end
	return scale :: UIScale
end
Tweens.getScale = getScale

-- Squash then spring back. Use on any button or label that just changed.
function Tweens.pop(gui: GuiObject, strength: number?)
	local scale = getScale(gui)
	scale.Scale = 1 + (strength or 0.15)
	Tweens.play(scale, Tweens.Ease.Pop, { Scale = 1 })
end

-- Panel entrance: grow from 0.85 and fade in.
function Tweens.openPanel(gui: GuiObject)
	gui.Visible = true
	local scale = getScale(gui)
	scale.Scale = 0.85
	Tweens.play(scale, Tweens.Ease.Pop, { Scale = 1 })
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = 1
		Tweens.play(gui, Tweens.Ease.Fade, { GroupTransparency = 0 })
	end
end

function Tweens.closePanel(gui: GuiObject)
	local scale = getScale(gui)
	local tween = Tweens.play(scale, Tweens.Ease.Fade, { Scale = 0.9 })
	if gui:IsA("CanvasGroup") then
		Tweens.play(gui, Tweens.Ease.Fade, { GroupTransparency = 1 })
	end
	if tween then
		tween.Completed:Once(function()
			gui.Visible = false
		end)
	else
		gui.Visible = false
	end
end

-- Animates a number in a TextLabel from its current value to `target`.
local counting: { [TextLabel]: number } = {}
function Tweens.countTo(label: TextLabel, from: number, target: number, format: (number) -> string, duration: number?)
	local token = (counting[label] or 0) + 1
	counting[label] = token
	local d = if Tweens.reducedMotion then 0 else (duration or 0.6)
	task.spawn(function()
		local start = os.clock()
		while true do
			if counting[label] ~= token or not label.Parent then
				return
			end
			local t = if d > 0 then math.clamp((os.clock() - start) / d, 0, 1) else 1
			local eased = 1 - (1 - t) ^ 3
			label.Text = format(from + (target - from) * eased)
			if t >= 1 then
				counting[label] = nil
				return
			end
			task.wait()
		end
	end)
end

-- Small FOV kick for impactful moments (harvesting a giant).
function Tweens.cameraPunch(amount: number?)
	if Tweens.reducedMotion then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local base = camera:GetAttribute("BaseFov") or camera.FieldOfView
	camera:SetAttribute("BaseFov", base)
	camera.FieldOfView = base - (amount or 4)
	Tweens.play(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base })
end

-- World part bounce (crop changed stage, got watered).
function Tweens.bouncePart(part: BasePart, fromScale: number?)
	local target = part.Size
	part.Size = target * (fromScale or 0.8)
	Tweens.play(part, Tweens.Ease.Bounce, { Size = target })
end

return Tweens
