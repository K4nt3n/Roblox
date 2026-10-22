--!strict
--[[
	GardenController: makes every garden in the server feel alive.

	* Reads plant inputs from plot attributes (set by the server) and runs the
	  same GrowthMath locally every frame, so crops swell continuously instead
	  of jumping when the server updates.
	* Visual size is spring-smoothed toward the true weight, with a bounce on
	  each stage change and on watering.
	* Rewrites prompt text locally per viewer: your plot says Plant / Harvest,
	  a friend's plot says "Water Sam's Pumpkin".
	* Shows a small floating label (weight + time left) above each crop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local GrowthMath = require(Shared.GrowthMath)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local FeelController = require(script.Parent.Parent.Feel.FeelController)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local CropVisuals = require(script.Parent.CropVisuals)

local GardenController = {}

local localPlayer = Players.LocalPlayer

type PlotView = {
	part: BasePart,
	visual: CropVisuals.Visual?,
	label: TextLabel,
	billboard: BillboardGui,
	shownScale: number,
	velocity: number,
	stage: string?,
	ownerUserId: number,
	plotId: string,
}

local views: { [BasePart]: PlotView } = {}
local LABEL_HZ = 4
local labelClock = 0

-- Critically damped-ish spring: smooth, slightly springy growth.
local SPRING_STIFFNESS = 60
local SPRING_DAMPING = 12

local function plantFromAttributes(part: BasePart): GrowthMath.Plant?
	local cropId = part:GetAttribute("cropId")
	if type(cropId) ~= "string" then
		return nil
	end
	return {
		cropId = cropId,
		plantedAt = part:GetAttribute("plantedAt") or 0,
		speed = part:GetAttribute("speed") or 1,
		bonusSeconds = part:GetAttribute("bonusSeconds") or 0,
		waterCount = part:GetAttribute("waterCount") or 0,
		lastWateredAt = part:GetAttribute("lastWateredAt") or 0,
		sizeRoll = part:GetAttribute("sizeRoll") or 1,
		gene = part:GetAttribute("gene") == true,
	} :: any
end

local function ownerName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else "Friend"
end

local function makeLabel(part: BasePart): (BillboardGui, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CropLabel"
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.MaxDistance = 45
	billboard.LightInfluence = 0
	billboard.Adornee = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.Parent = billboard
	billboard.Parent = part
	return billboard, label
end

local function track(part: BasePart)
	if views[part] then
		return
	end
	local billboard, label = makeLabel(part)
	views[part] = {
		part = part,
		visual = nil,
		label = label,
		billboard = billboard,
		shownScale = 0,
		velocity = 0,
		stage = nil,
		ownerUserId = part:GetAttribute("OwnerUserId") or 0,
		plotId = part:GetAttribute("PlotId") or part.Name,
	}
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			local view = views[part]
			if view and view.visual then
				view.visual.root:Destroy()
			end
			views[part] = nil
		end
	end)
end

local function updatePrompts(view: PlotView, plant: GrowthMath.Plant?, state: GrowthMath.GrowthState?, now: number)
	local main = view.part:FindFirstChild("Main") :: ProximityPrompt?
	local water = view.part:FindFirstChild("Water") :: ProximityPrompt?
	if not main or not water then
		return
	end
	local isMine = view.ownerUserId == localPlayer.UserId
	local data = ClientState.data
	local locked = view.part:GetAttribute("Locked") == true
	local crop = plant and Config.Crops[plant.cropId]
	local cropName = if crop then crop.displayName else ""

	if not isMine then
		main.Enabled = false
		local canWater = plant ~= nil and state ~= nil and not state.isMaxed
		water.Enabled = canWater
		water.ActionText = "Water"
		water.ObjectText = ownerName(view.ownerUserId) .. "'s " .. cropName
		return
	end

	if locked then
		local isNext = data ~= nil and tonumber(view.plotId) == data.ownedPlots + 1
		main.Enabled = isNext
		main.ActionText = "Buy Plot"
		main.ObjectText = if data and data.nextPlotCost then Format.coins(data.nextPlotCost) .. " Coins" else ""
		water.Enabled = false
		return
	end

	main.Enabled = true
	if not plant or not state then
		local seed = if data then Config.Crops[data.selectedSeed] else nil
		main.ActionText = "Plant"
		main.ObjectText = if seed then seed.displayName else ""
		water.Enabled = false
		return
	end

	local cooldown = if plant.lastWateredAt > 0 then plant.lastWateredAt + Config.Watering.plantCooldownSeconds - now else 0
	if state.canHarvest then
		main.ActionText = "Harvest"
		main.ObjectText = cropName .. " · " .. Format.weight(state.weight)
		-- Ripe crops can still be watered toward Giant size.
		water.Enabled = not state.isMaxed and cooldown <= 0
		water.ActionText = "Water"
		water.ObjectText = "Grow it bigger!"
	else
		main.ActionText = if cooldown > 0 then "Watered" else "Water"
		main.ObjectText = cropName
		main.Enabled = cooldown <= 0
		water.Enabled = false
	end
end

local function updateLabel(view: PlotView, plant: GrowthMath.Plant?, state: GrowthMath.GrowthState?)
	if not plant or not state then
		view.label.Text = ""
		return
	end
	local timeText
	if not state.canHarvest then
		timeText = Format.duration(state.secondsToRipe)
	elseif not state.isMaxed then
		timeText = if state.stage == "Giant" then "GIANT!" else "Ripe!"
	else
		timeText = "MAX!"
	end
	local gene = if plant.gene then " ★" else ""
	view.label.Text = Format.weight(state.weight) .. gene .. "\n" .. timeText
end

local function step(dt: number)
	local now = ClientState.now()
	labelClock += dt
	local refreshText = labelClock >= 1 / LABEL_HZ
	if refreshText then
		labelClock = 0
	end

	for part, view in views do
		local plant = plantFromAttributes(part)
		local crop = plant and Config.Crops[plant.cropId]
		local state = if plant and crop then GrowthMath.evaluate(plant, crop, Config, now) else nil

		if plant and state then
			if not view.visual or view.visual.cropId ~= plant.cropId then
				if view.visual then
					view.visual.root:Destroy()
				end
				view.visual = CropVisuals.create(plant.cropId)
				view.visual.root.Parent = part
				view.shownScale = 0
				view.velocity = 0
			end
			if view.stage ~= nil and view.stage ~= state.stage then
				-- Kick the spring for a satisfying "boing" on every stage change.
				view.velocity += 8
			end
			view.stage = state.stage

			local target = CropVisuals.targetScale(state.weight)
			local accel = (target - view.shownScale) * SPRING_STIFFNESS - view.velocity * SPRING_DAMPING
			view.velocity += accel * math.min(dt, 1 / 30)
			view.shownScale = math.max(0, view.shownScale + view.velocity * math.min(dt, 1 / 30))
			CropVisuals.apply(view.visual :: CropVisuals.Visual, part, view.shownScale, state.stage)
		elseif view.visual then
			view.visual.root:Destroy()
			view.visual = nil
			view.stage = nil
		end

		if refreshText then
			updateLabel(view, plant, state)
			updatePrompts(view, plant, state, now)
		end
	end
end

local function findView(ownerUserId: number, plotId: string): PlotView?
	for _, view in views do
		if view.ownerUserId == ownerUserId and view.plotId == plotId then
			return view
		end
	end
	return nil
end

local function onFeel(name: string, context: { [string]: any })
	local plotId = context.plotId
	if type(plotId) ~= "string" then
		return
	end
	local owner = context.ownerUserId or localPlayer.UserId
	local view = findView(owner, plotId)
	if not view then
		return
	end
	if name == Net.Feedback.Watered or name == Net.Feedback.FriendWateredYou or name == Net.Feedback.YouWateredFriend then
		local wet = Config.World.colors.soilWet
		local dry = Config.World.colors.soil
		view.part.Color = Color3.fromRGB(wet[1], wet[2], wet[3])
		Tweens.play(view.part, TweenInfo.new(2.5, Enum.EasingStyle.Sine), { Color = Color3.fromRGB(dry[1], dry[2], dry[3]) })
		view.velocity += 4
	elseif name == Net.Feedback.Planted then
		view.velocity += 6
	end
	Tweens.pop(view.label, 0.25)
end

function GardenController.start()
	local function scan(gardens: Instance)
		for _, d in gardens:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("PlotId") then
				track(d)
			end
		end
		gardens.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				-- Attributes replicate with the instance, but wait a frame to be safe.
				task.defer(function()
					if d:GetAttribute("PlotId") then
						track(d)
					end
				end)
			end
		end)
	end
	task.spawn(function()
		scan(workspace:WaitForChild("Gardens"))
	end)

	FeelController.Played:Connect(onFeel)
	-- Lets feel effects (particles) land on the right plot for events that only carry a plotId.
	FeelController.positionResolver = function(context)
		if type(context.plotId) ~= "string" then
			return nil
		end
		local view = findView(context.ownerUserId or localPlayer.UserId, context.plotId)
		return if view then view.part.Position + Vector3.new(0, 2, 0) else nil
	end

	-- Stand prompts open UI panels.
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
		local panel = prompt.Parent and prompt.Parent:GetAttribute("OpensPanel")
		if type(panel) == "string" then
			GardenController.PanelRequested:Fire(panel)
		end
	end)

	RunService.RenderStepped:Connect(step)
end

GardenController.PanelRequested = require(Shared.Signal).new() -- (panelName)

return GardenController
