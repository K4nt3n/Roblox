--!strict
--[[
	LevelBar: the XP bar, driven by essence.

	XP from the server never snaps the bar. When essence orbs are flying, the
	new target waits; each orb that lands nudges the fill a step and pulses the
	bar, and the last one settles it. A level-up fills to the end, flashes,
	then rolls over and fills again from zero.
]]

local Theme = require(script.Parent.Theme)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local EssenceFX = require(script.Parent.Parent.Feel.EssenceFX)
local FeelController = require(script.Parent.Parent.Feel.FeelController)

local LevelBar = {}

type Target = { level: number, xp: number, need: number }

local card: Frame
local fill: Frame
local label: TextLabel
local levelNumber: TextLabel? = nil
local shownLevel = 0
local shownFraction = 0
local pending: Target? = nil
local current: Target? = nil

local STEP = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setFill(fraction: number, info: TweenInfo?)
	shownFraction = math.clamp(fraction, 0, 1)
	Tweens.play(fill, info or Tweens.Ease.Slide, { Size = UDim2.fromScale(shownFraction, 1) })
end

local function setLabel(target: Target)
	if levelNumber then
		local changed = levelNumber.Text ~= tostring(target.level)
		levelNumber.Text = tostring(target.level)
		label.Text = string.format("%d / %d XP", target.xp, target.need)
		local badge = levelNumber.Parent
		if changed and shownLevel ~= 0 and badge and badge:IsA("GuiObject") then
			Tweens.pop(badge, 0.35)
		end
	else
		label.Text = string.format("Lv %d  ·  %d / %d XP", target.level, target.xp, target.need)
	end
end

local function flash()
	fill.BackgroundColor3 = Theme.Colors.Gold
	Tweens.play(fill, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { BackgroundColor3 = Theme.Colors.Primary })
end

-- Moves the bar to the target, rolling over through a level-up if needed.
local function settle(target: Target)
	local fraction = target.xp / math.max(1, target.need)
	if shownLevel ~= 0 and target.level > shownLevel then
		local tween = Tweens.play(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, 1) })
		flash()
		Tweens.pop(card, 0.12)
		local done = function()
			fill.Size = UDim2.fromScale(0, 1)
			shownFraction = 0
			setFill(fraction)
			setLabel(target)
		end
		if tween then
			tween.Completed:Once(done)
		else
			done()
		end
	else
		setFill(fraction)
		setLabel(target)
	end
	shownLevel = target.level
end

-- levelText (optional): a separate label for the level number, e.g. inside a level badge.
function LevelBar.mount(levelCard: Frame, levelFill: Frame, levelLabel: TextLabel, levelText: TextLabel?)
	card, fill, label, levelNumber = levelCard, levelFill, levelLabel, levelText
end

-- The GuiObject essence flies into (a fly-to target for other effects too).
function LevelBar.target(): GuiObject?
	return card
end

-- Called with every server snapshot.
function LevelBar.setTarget(level: number, xp: number, need: number)
	local target = { level = level, xp = xp, need = math.max(1, need) }
	current = target
	if shownLevel == 0 then
		-- First snapshot: no animation from zero.
		shownLevel = level
		fill.Size = UDim2.fromScale(xp / target.need, 1)
		shownFraction = xp / target.need
		setLabel(target)
		return
	end
	if EssenceFX.active() > 0 then
		pending = target
	else
		settle(target)
	end
end

-- Fires essence from a world position into the bar for `xp` points.
function LevelBar.essence(from: Vector3?, xp: number)
	if not card then
		return
	end
	local count = EssenceFX.countFor(xp)
	FeelController.play("EssenceBurst", { position = from })
	EssenceFX.burst(from, card, count, function(index, total)
		FeelController.play("EssenceTick")
		Tweens.pop(card, 0.05)
		local target = pending or current
		if target then
			local goal = if target.level > shownLevel then 1 else target.xp / target.need
			setFill(shownFraction + (goal - shownFraction) * (1 / math.max(1, total - index + 1)), STEP)
		end
	end, function()
		if EssenceFX.active() == 0 then
			local target = pending or current
			pending = nil
			if target then
				settle(target)
			end
		end
	end)
end

return LevelBar
