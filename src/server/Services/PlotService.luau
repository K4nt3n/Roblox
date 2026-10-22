--!strict
--[[
	PlotService: owns the physical gardens in Workspace.

	* Assigns each player a garden slot and builds placeholder plot parts.
	* Mirrors each plant's growth inputs onto plot attributes. Clients compute
	  growth locally every frame from these, so crops swell smoothly with zero
	  network traffic while the server stays authoritative.
	* Creates ProximityPrompts; GardenService decides what a trigger does.

	Art seam: if Workspace.GardenSlots contains parts, gardens are centered on
	them instead of the generated grid. Everything visual about crops lives on
	the client (see client/Controllers/GardenController).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local PlotService = {}

PlotService.PromptTriggered = Signal.new() -- (player, ownerUserId, plotId, promptKind: "Main" | "Water")

local gardensFolder: Folder
local slotOwners: { [number]: Player } = {}
local playerSlots: { [Player]: number } = {}
local gardens: { [Player]: Model } = {}

local PLANT_ATTRIBUTES = {
	"cropId",
	"plantedAt",
	"speed",
	"bonusSeconds",
	"waterCount",
	"lastWateredAt",
	"sizeRoll",
	"gene",
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function slotCFrame(slot: number): CFrame
	local anchors = workspace:FindFirstChild("GardenSlots")
	local anchor = anchors and anchors:FindFirstChild(tostring(slot))
	if anchor and anchor:IsA("BasePart") then
		return anchor.CFrame
	end
	local w = Config.World
	local col = (slot - 1) % 4
	local row = (slot - 1) // 4
	return CFrame.new((col - 1.5) * w.gardenSpacing, 0, (row + 0.5) * w.gardenSpacing + 20)
end

local function makePrompt(parent: Instance, name: string, key: Enum.KeyCode, actionText: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.World.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default -- Swap to Custom when UI art lands.
	prompt.Parent = parent
	return prompt
end

local function buildGarden(player: Player, slot: number): Model
	local w = Config.World
	local model = Instance.new("Model")
	model.Name = "Garden_" .. player.UserId
	model:SetAttribute("OwnerUserId", player.UserId)

	local origin = slotCFrame(slot)
	local rows = math.ceil(Config.Plots.maxPlots / w.plotsPerRow)
	local width = w.plotsPerRow * (w.plotSize + w.plotGap) + w.plotGap
	local depth = rows * (w.plotSize + w.plotGap) + w.plotGap

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(width, 1, depth + 8)
	base.CFrame = origin * CFrame.new(0, 0.5, 0)
	base.Color = rgb(w.colors.garden)
	base.Material = Enum.Material.SmoothPlastic
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = model
	model.PrimaryPart = base

	-- Owner sign (placeholder text only).
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Transparency = 1
	sign.Size = Vector3.new(1, 1, 1)
	sign.CFrame = origin * CFrame.new(0, 6, -(depth / 2) - 2)
	sign.Parent = model
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 50)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 120
	billboard.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = player.DisplayName .. "'s Garden"
	label.Parent = billboard

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = model

	for i = 1, Config.Plots.maxPlots do
		local col = (i - 1) % w.plotsPerRow
		local row = (i - 1) // w.plotsPerRow
		local x = -width / 2 + w.plotGap + w.plotSize / 2 + col * (w.plotSize + w.plotGap)
		local z = -depth / 2 + w.plotGap + w.plotSize / 2 + row * (w.plotSize + w.plotGap)

		local plot = Instance.new("Part")
		plot.Name = tostring(i)
		plot.Anchored = true
		plot.Size = Vector3.new(w.plotSize, 0.6, w.plotSize)
		plot.CFrame = origin * CFrame.new(x, 1.3, z)
		plot.Material = Enum.Material.SmoothPlastic
		plot.Color = rgb(w.colors.soil)
		plot:SetAttribute("PlotId", tostring(i))
		plot:SetAttribute("OwnerUserId", player.UserId)
		plot.Parent = plots

		makePrompt(plot, "Main", Enum.KeyCode.E, "Plant")
		makePrompt(plot, "Water", Enum.KeyCode.R, "Water")
	end

	model.Parent = gardensFolder
	return model
end

function PlotService:Init()
	gardensFolder = Instance.new("Folder")
	gardensFolder.Name = "Gardens"
	gardensFolder.Parent = workspace
end

-- Placeholder stands for the shop, market and fair. Map art can replace these by
-- providing Workspace.Stands/<name> parts; we only add the prompt to them.
local function buildStands()
	local existing = workspace:FindFirstChild("Stands")
	local folder = existing or Instance.new("Folder")
	folder.Name = "Stands"
	for _, def in Config.World.stands do
		local part = folder:FindFirstChild(def.name)
		if not part then
			part = Instance.new("Part")
			part.Name = def.name
			part.Anchored = true
			part.Size = Vector3.new(10, 6, 4)
			part.Position = Vector3.new(def.position[1], def.position[2] + 3, def.position[3])
			part.Color = rgb(Config.World.colors.stand)
			part.Material = Enum.Material.SmoothPlastic
			part.Parent = folder

			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(220, 44)
			billboard.StudsOffset = Vector3.new(0, 5, 0)
			billboard.Parent = part
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.4
			label.Text = def.label
			label.Parent = billboard
		end
		part:SetAttribute("OpensPanel", def.panel)
		local prompt = makePrompt(part, "Open", Enum.KeyCode.E, "Open")
		prompt.ObjectText = def.label
	end
	folder.Parent = workspace
end

function PlotService:Start()
	-- Empty places get a placeholder ground so the prototype is playable anywhere.
	if not workspace:FindFirstChild("Baseplate") and not workspace:FindFirstChild("Map") then
		local ground = Instance.new("Part")
		ground.Name = "Baseplate"
		ground.Anchored = true
		ground.Size = Vector3.new(400, 2, 400)
		ground.Position = Vector3.new(0, -1, 40)
		ground.Color = rgb(Config.World.colors.garden)
		ground.Material = Enum.Material.SmoothPlastic
		ground.TopSurface = Enum.SurfaceType.Smooth
		ground.Parent = workspace
	end
	buildStands()

	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local plot = prompt.Parent
		if not plot or not plot:IsA("BasePart") or not plot:IsDescendantOf(gardensFolder) then
			return
		end
		local ownerUserId = plot:GetAttribute("OwnerUserId")
		local plotId = plot:GetAttribute("PlotId")
		if type(ownerUserId) ~= "number" or type(plotId) ~= "string" then
			return
		end
		local kind = if prompt.Name == "Water" then "Water" else "Main"
		self.PromptTriggered:Fire(player, ownerUserId, plotId, kind)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:ReleaseGarden(player)
	end)
end

function PlotService:AssignGarden(player: Player): Model?
	if gardens[player] then
		return gardens[player]
	end
	for slot = 1, Config.World.gardenSlots do
		if not slotOwners[slot] then
			slotOwners[slot] = player
			playerSlots[player] = slot
			local model = buildGarden(player, slot)
			gardens[player] = model
			return model
		end
	end
	warn("[PlotService] No free garden slot for " .. player.Name)
	return nil
end

function PlotService:ReleaseGarden(player: Player)
	local slot = playerSlots[player]
	if slot then
		slotOwners[slot] = nil
		playerSlots[player] = nil
	end
	if gardens[player] then
		gardens[player]:Destroy()
		gardens[player] = nil
	end
end

function PlotService:GetGarden(player: Player): Model?
	return gardens[player]
end

function PlotService:GetSpawnCFrame(player: Player): CFrame?
	local garden = gardens[player]
	if garden and garden.PrimaryPart then
		local depth = garden.PrimaryPart.Size.Z
		return garden.PrimaryPart.CFrame * CFrame.new(0, 4, depth / 2 + 4)
	end
	return nil
end

function PlotService:GetPlotPart(player: Player, plotId: string): BasePart?
	local garden = gardens[player]
	local plots = garden and garden:FindFirstChild("Plots")
	local part = plots and plots:FindFirstChild(plotId)
	return if part and part:IsA("BasePart") then part else nil
end

-- Writes everything a client needs to render a plot. `plant` may be nil.
function PlotService:SyncPlot(player: Player, plotId: string, plant: { [string]: any }?, locked: boolean)
	local part = self:GetPlotPart(player, plotId)
	if not part then
		return
	end
	part:SetAttribute("Locked", locked)
	part.Transparency = if locked then 0.6 else 0
	part.Color = rgb(if locked then Config.World.colors.lockedPlot else Config.World.colors.soil)
	for _, key in PLANT_ATTRIBUTES do
		part:SetAttribute(key, if plant then plant[key] else nil)
	end
end

function PlotService:SyncAll(player: Player, data: { [string]: any })
	for i = 1, Config.Plots.maxPlots do
		local plotId = tostring(i)
		self:SyncPlot(player, plotId, data.plots[plotId], i > data.ownedPlots)
	end
end

return PlotService
