--!strict
--[[
	Counter: a number on screen that never snaps.

	    local coins = Counter.new(label, Format.coins, { popTarget = pill, floatParent = pill, tick = "CoinTick" })
	    coins:set(1250)             -- rolls up from whatever is showing now, pops, floats "+250"
	    coins:set(0, { instant = true })

	Interrupting a roll is smooth: the next roll starts from the number that is
	on screen at that moment. Bigger jumps roll a little longer so they feel
	bigger. `tick` names a FeelHooks sound that plays softly while it rolls.
]]

local Theme = require(script.Parent.Theme)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local FeelController = require(script.Parent.Parent.Feel.FeelController)

local Counter = {}
Counter.__index = Counter

export type Options = {
	popTarget: GuiObject?,
	-- Where the "+250" floats up from (a frame without a layout); nil = no float.
	floatParent: GuiObject?,
	floatPosition: UDim2?,
	floatFormat: ((delta: number) -> string)?,
	gainColor: Color3?,
	lossColor: Color3?,
	tick: string?,
	minDelta: number?,
}

export type SetOptions = { instant: boolean?, quiet: boolean? }

export type Counter = typeof(setmetatable(
	{} :: {
		label: TextLabel,
		format: (number) -> string,
		options: Options,
		value: number,
		shown: number,
		started: boolean,
	},
	Counter
))

function Counter.new(label: TextLabel, format: (number) -> string, options: Options?): Counter
	local self = setmetatable({
		label = label,
		format = format,
		options = options or {},
		value = 0,
		shown = 0,
		started = false,
	}, Counter)
	label.Text = format(0)
	return self
end

local function rollTime(delta: number): number
	return 0.35 + math.min(0.65, math.log10(math.abs(delta) + 1) * 0.16)
end

function Counter.float(self: Counter, delta: number)
	local opts = self.options
	local parent = opts.floatParent
	if not parent or delta == 0 then
		return
	end
	local text = if opts.floatFormat
		then opts.floatFormat(delta)
		else (if delta > 0 then "+" else "-") .. self.format(math.abs(delta))
	local float = Instance.new("TextLabel")
	float.Name = "Delta"
	float.BackgroundTransparency = 1
	float.AnchorPoint = Vector2.new(0, 0.5)
	float.Position = opts.floatPosition or UDim2.new(1, 8, 0.5, 0)
	float.Size = UDim2.fromOffset(0, 24)
	float.AutomaticSize = Enum.AutomaticSize.X
	float.Font = Theme.Font
	float.TextSize = Theme.TextSize.Large
	float.Text = text
	float.TextColor3 = if delta > 0
		then (opts.gainColor or Theme.Colors.Primary)
		else (opts.lossColor or Theme.Colors.Danger)
	float.TextStrokeColor3 = Theme.Style.Outline
	float.TextStrokeTransparency = 0
	float.ZIndex = 10
	float.Parent = parent
	local start = float.Position
	local scale = Tweens.getScale(float)
	scale.Scale = 0.5
	Tweens.play(scale, Tweens.Ease.Pop, { Scale = 1 })
	Tweens.play(float, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = start + UDim2.fromOffset(0, -26),
	})
	local fade =
		Tweens.play(float, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0.55), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
	if fade then
		fade.Completed:Once(function()
			float:Destroy()
		end)
	else
		float:Destroy()
	end
end

function Counter.set(self: Counter, value: number, setOptions: SetOptions?)
	local opts = self.options
	local delta = value - self.value
	self.value = value
	if not self.started or (setOptions and setOptions.instant) then
		-- First value (or a forced jump) shows immediately.
		self.started = true
		self.shown = value
		Tweens.countTo(self.label, value, value, self.format, 0)
		return
	end
	if math.abs(delta) < (opts.minDelta or 1e-6) then
		return
	end
	local from = self.shown
	local lastTick = 0
	Tweens.countTo(self.label, from, value, function(n)
		self.shown = n
		if opts.tick then
			local now = os.clock()
			if now - lastTick > 0.06 then
				lastTick = now
				FeelController.play(opts.tick)
			end
		end
		return self.format(n)
	end, rollTime(value - from))
	if setOptions and setOptions.quiet then
		return
	end
	if opts.popTarget then
		Tweens.pop(opts.popTarget, if delta > 0 then 0.1 else 0.05)
	end
	self:float(delta)
end

-- Moves part of the way to a value without the pop/float (used while orbs land).
function Counter.step(self: Counter, value: number)
	self:set(value, { quiet = true })
end

return Counter
