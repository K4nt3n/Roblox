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
	* Champion plot: the label carries the champion's name and its current care
	  need, and the Care prompt (F) lights up when a need is open. Co-growers
	  get the same prompts on a friend's champion.
	* Bugs (Config.Pests) crawl around a crop while it has pests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local GrowthMath = require(Shared.GrowthMath)
local CareMath = require(Shared.CareMath)
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
	isChampion: boolean,
	needK: number?,
	bugs: Model?,
}

local CHAMPION = Config.Champion
local CARE_ACTION: { [string]: string } = {
	Water = "Water",
	Pests = "Pick off bugs",
	Prop = "Prop it up",
}
local CARE_LABEL: { [string]: string } = {
	Water = "Thirsty!",
	Pests = "Bugs!",
	Prop = "Leaning!",
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
		champion = part:GetAttribute("champion") == true,
		careInterval = part:GetAttribute("careInterval"),
		careScore = part:GetAttribute("careScore") or 0,
		care = CareMath.decodeDone(part:GetAttribute("careDone")),
		name = part:GetAttribute("name"),
		paidSkips = part:GetAttribute("paidSkips") or 0,
		pestSince = part:GetAttribute("pestSince"),
		pestMaxPause = part:GetAttribute("pestMaxPause"),
		fertilized = part:GetAttribute("fertilized") == true,
	} :: any
end

local function coGrowersOf(part: BasePart): { number }
	local list = {}
	local text = part:GetAttribute("coGrowers")
	for id in string.gmatch(if type(text) == "string" then text else "", "[^,]+") do
		table.insert(list, tonumber(id) :: number)
	end
	return list
end

local function pendingNeed(plant: GrowthMath.Plant?, now: number): CareMath.Need?
	local crop = plant and Config.Crops[plant.cropId]
	if not plant or not crop or not (plant :: any).champion then
		return nil
	end
	return CareMath.pendingNeed(plant :: any, CHAMPION, now, function(t)
		return GrowthMath.evaluate(plant :: GrowthMath.Plant, crop, Config, t).canHarvest
	end)
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
	local isChampion = part:GetAttribute("IsChampionPlot") == true
	if isChampion then
		-- Bigger, higher label: name + weight + care need.
		billboard.Size = UDim2.fromOffset(220, 66)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
		billboard.MaxDistance = 70
	end
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
		isChampion = isChampion,
		needK = nil,
		bugs = nil,
	}
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			local view = views[part]
			if view and view.visual then
				view.visual.root:Destroy()
			end
			if view and view.bugs then
				view.bugs:Destroy()
			end
			views[part] = nil
		end
	end)
end

local function updatePrompts(view: PlotView, plant: GrowthMath.Plant?, state: GrowthMath.GrowthState?, now: number)
	local main = view.part:FindFirstChild("Main") :: ProximityPrompt?
	local water = view.part:FindFirstChild("Water") :: ProximityPrompt?
	local care = view.part:FindFirstChild("Care") :: ProximityPrompt?
	if not main or not water then
		return
	end
	local isMine = view.ownerUserId == localPlayer.UserId
	local data = ClientState.data
	local locked = view.part:GetAttribute("Locked") == true
	local crop = plant and Config.Crops[plant.cropId]
	local cropName = if crop then crop.displayName else ""
	local championName = plant and (plant :: any).name
	if view.isChampion and championName then
		cropName = championName .. " the " .. cropName
	end

	-- Champion care: owners and co-growers see the Care prompt when a need is open.
	local canTend = isMine or table.find(coGrowersOf(view.part), localPlayer.UserId) ~= nil
	local need = if view.isChampion and canTend then pendingNeed(plant, now) else nil
	if care then
		care.Enabled = need ~= nil and need.kind ~= "Water"
		care.ActionText = if need then CARE_ACTION[need.kind] or "Care" else "Care"
		care.ObjectText = cropName
	end

	-- Watering is only done with the Watering Bucket (equip it, click the crop), so
	-- the Water prompt stays off everywhere.
	water.Enabled = false

	if not isMine then
		main.Enabled = false
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
		main.ActionText = if view.isChampion then "Plant Champion" else "Plant"
		main.ObjectText = if seed then seed.displayName else ""
		water.Enabled = false
		return
	end
	if state.canHarvest then
		main.ActionText = "Harvest"
		main.ObjectText = cropName .. " · " .. Format.weight(state.weight)
	else
		-- Growing: nothing to press. Water it with the bucket.
		main.Enabled = false
	end
end

local function updateLabel(view: PlotView, plant: GrowthMath.Plant?, state: GrowthMath.GrowthState?, now: number)
	if not plant or not state then
		view.label.Text = if view.isChampion and view.ownerUserId == localPlayer.UserId then "Champion plot\nPlant your best seed!" else ""
		view.needK = nil
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
	if view.isChampion then
		local need = pendingNeed(plant, now)
		local name = (plant :: any).name or "Champion"
		local needText = if need then "  ·  " .. (CARE_LABEL[need.kind] or "Needs care") else ""
		view.label.Text = string.format("%s\n%s%s\n%s%s", name, Format.weight(state.weight), gene, timeText, needText)
		local k = if need then need.k else nil
		if k ~= view.needK then
			view.needK = k
			if k then
				-- A fresh need: make the label hop so it's noticed.
				Tweens.pop(view.label, 0.35)
			end
		end
		return
	end
	if plant.pestSince then
		timeText = "Bugs! Growth paused"
	end
	view.label.Text = Format.weight(state.weight) .. gene .. "\n" .. timeText
end

local BUG_COUNT = 4

-- Small dark bugs circling the crop while it has pests.
local function updateBugs(view: PlotView, hasPests: boolean, t: number)
	if not hasPests then
		if view.bugs then
			view.bugs:Destroy()
			view.bugs = nil
		end
		return
	end
	local bugs = view.bugs
	if not bugs then
		local model = Instance.new("Model")
		model.Name = "Bugs"
		for i = 1, BUG_COUNT do
			local bug = Instance.new("Part")
			bug.Name = "Bug"
			bug.Shape = Enum.PartType.Ball
			bug.Size = Vector3.one * 0.45
			bug.Color = if i % 2 == 0 then Color3.fromRGB(40, 35, 30) else Color3.fromRGB(70, 110, 40)
			bug.Material = Enum.Material.SmoothPlastic
			bug.Anchored = true
			bug.CanCollide = false
			bug.CanQuery = false
			bug.CanTouch = false
			bug.CastShadow = false
			bug.Parent = model
		end
		model.Parent = view.part
		view.bugs = model
		bugs = model
	end
	local radius = math.max(0.9, view.shownScale * 0.55)
	local height = view.part.Size.Y / 2 + view.shownScale * 0.7
	for i, bug in (bugs :: Model):GetChildren() do
		local a = t * 2.5 + i * (math.pi * 2 / BUG_COUNT)
		local offset = Vector3.new(math.cos(a) * radius, height + math.sin(t * 7 + i) * 0.25, math.sin(a) * radius)
		local bugPart = bug :: BasePart
		bugPart.CFrame = CFrame.new(view.part.Position + offset)
	end
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

		updateBugs(view, plant ~= nil and (plant :: any).pestSince ~= nil, os.clock())

		if refreshText then
			updateLabel(view, plant, state, now)
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
	elseif name == Net.Feedback.CareDone or name == Net.Feedback.PestsRemoved then
		view.velocity += 5
	elseif name == Net.Feedback.Fertilized then
		view.velocity += 7
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

-- The plot part `instance` belongs to (a plot or anything on it), if any.
function GardenController.plotFor(instance: Instance?): BasePart?
	local current = instance
	while current and current ~= workspace do
		if current:IsA("BasePart") and views[current] then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- The closest plot with something planted within `range` studs of `position`.
function GardenController.nearestPlot(position: Vector3, range: number): BasePart?
	local best, bestDistance = nil, range
	for part in views do
		if part:GetAttribute("cropId") then
			local distance = (part.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

return GardenController
