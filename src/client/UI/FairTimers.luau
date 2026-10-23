--!strict
--[[
	FairTimers: bottom right countdowns to the next weigh-in of each fair, one row
	per fair (hourly on top, weekly at the bottom): icon + "Hourly in 15m 57s".
	During a live show the row says "Live now!". Tapping a row opens that fair.

	Times come from Config.Fair.periods and the server clock, so they keep counting
	without a snapshot. Art slots: FairTimer_hourly, FairTimer_daily, FairTimer_weekly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local FairMath = require(Shared.FairMath)
local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local FeelController = require(script.Parent.Parent.Feel.FeelController)

local FairTimers = {}

local ROW_HEIGHT = 44
local WIDTH = 250

-- Short name and text colour per fair.
local STYLE: { [string]: { name: string, color: Color3, glyph: string } } = {
	hourly = { name = "Hourly", color = Theme.Colors.Text, glyph = "H" },
	daily = { name = "Daily", color = Theme.Colors.Accent, glyph = "D" },
	weekly = { name = "Weekly", color = Theme.Colors.Gold, glyph = "W" },
}

local holder: Frame
local rows: { { period: any, label: TextLabel, live: boolean? } } = {}

local function rowText(period: any, now: number): (string, boolean)
	local style = STYLE[period.id]
	local name = if style then style.name else period.displayName
	local phase, _, at = FairMath.showPhase(now, period)
	if phase == "Live" then
		return name .. " live now!", true
	end
	return string.format("%s in %s", name, Format.duration(at - now)), false
end

local function update()
	local now = ClientState.now()
	for _, row in rows do
		local text, live = rowText(row.period, now)
		row.label.Text = text
		if live ~= row.live then
			row.live = live
			local style = STYLE[row.period.id]
			row.label.TextColor3 = if live
				then Theme.Colors.Primary
				else (if style then style.color else Theme.Colors.Text)
			if live then
				Tweens.pop(row.label, 0.2)
			end
		end
	end
end

function FairTimers.mount(parent: Instance, onOpen: (fair: string) -> ())
	holder = UIKit.new("Frame", {
		Name = "FairTimers",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -14),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, { UIKit.list(Enum.FillDirection.Vertical, 2) })

	for i, period in FairMath.sortedPeriods(Config.Fair.periods) do
		local style = STYLE[period.id]
		local button = UIKit.new("TextButton", {
			Name = period.id,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Text = "",
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			Parent = holder,
		})
		ArtSlot.icon("FairTimer_" .. period.id, {
			size = ROW_HEIGHT,
			round = true,
			color = if style then style.color else Theme.Colors.Gold,
			glyph = if style then style.glyph else "?",
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 0, 0.5, 0),
		}).Parent =
			button
		local label = UIKit.label("", Theme.TextSize.Large, {
			Name = "Time",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, ROW_HEIGHT + 6, 0.5, 0),
			TextColor3 = if style then style.color else Theme.Colors.Text,
			Parent = button,
		})
		UIKit.outlineText(label, 2, true)
		button.Activated:Connect(function()
			FeelController.play("ButtonPress")
			Tweens.pop(button, 0.1)
			onOpen(period.id)
		end)
		table.insert(rows, { period = period, label = label })
	end

	update()
	task.spawn(function()
		while holder.Parent do
			-- Tick on the second, so all three change together.
			task.wait(1 - ClientState.now() % 1)
			update()
		end
	end)
end

-- Phones keep the bottom right corner free for the jump button.
function FairTimers.layout(phone: boolean)
	if holder then
		holder.Position = UDim2.new(1, -16, 1, if phone then -170 else -14)
	end
end

return FairTimers
