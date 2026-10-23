--!strict
--[[
	ToolController: the garden tools (Watering Bucket, Pest Remover, Fertilizer).

	* Activate an equipped tool (click / tap) to use it on the plot under the
	  cursor, or on the nearest planted plot within Config.Tools.useDistance.
	* The animation plays at once for the user; the server re-checks everything
	  (ToolService) and broadcasts Feedback.ToolUsed so other players see it too.
	* Animations are code-driven: the default tool arm swing (Animate's
	  "toolanim"), a tilt / shake of the tool via Tool.Grip, the tool's particle
	  emitter, and an effect on the plant.
	* The Fertilizer tool shows how many bags are left.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local FeelController = require(script.Parent.Parent.Feel.FeelController)
local GardenController = require(script.Parent.GardenController)

local ToolController = {}

local localPlayer = Players.LocalPlayer
local TOOLS = Config.Tools

-- How each tool moves. tilt = radians around the hand's X axis; shake = side wiggles.
local MOTION: { [string]: { tilt: number, shake: number, seconds: number, emitter: string, swing: string } } = {
	WateringBucket = { tilt = math.rad(-75), shake = 0, seconds = 1.1, emitter = "Pour", swing = "Lunge" },
	PestRemover = { tilt = math.rad(-15), shake = 3, seconds = 0.7, emitter = "Spray", swing = "Slash" },
	Fertilizer = { tilt = math.rad(-55), shake = 4, seconds = 1, emitter = "Sprinkle", swing = "Lunge" },
}

local connected: { [Tool]: boolean } = {}
local baseGrips: { [Tool]: CFrame } = {}
local busyTools: { [Tool]: boolean } = {}
local lastUse = 0

local function toolIdOf(tool: Instance): string?
	local id = tool:GetAttribute("GardenTool")
	return if type(id) == "string" and TOOLS.items[id] then id else nil
end

local function findTool(character: Model?, toolId: string): Tool?
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("GardenTool") == toolId then
			return child
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------

local function burst(position: Vector3, props: { [string]: any }, count: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = position
	holder.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = holder
	emitter:Emit(count)
	Debris:AddItem(holder, 2)
end

-- Bugs scatter off the plant and fade away.
local function bugsFlyAway(position: Vector3)
	for i = 1, 5 do
		local bug = Instance.new("Part")
		bug.Shape = Enum.PartType.Ball
		bug.Size = Vector3.one * 0.45
		bug.Color = if i % 2 == 0 then Color3.fromRGB(40, 35, 30) else Color3.fromRGB(70, 110, 40)
		bug.Anchored = true
		bug.CanCollide = false
		bug.CanQuery = false
		bug.CanTouch = false
		bug.Position = position + Vector3.new(0, 1.5, 0)
		bug.Parent = workspace
		local angle = i / 5 * math.pi * 2
		local target = bug.Position + Vector3.new(math.cos(angle) * 7, 6 + i, math.sin(angle) * 7)
		local tween = game:GetService("TweenService"):Create(bug, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = target,
			Transparency = 1,
			Size = Vector3.one * 0.15,
		})
		tween:Play()
		Debris:AddItem(bug, 1)
	end
end

local function plantEffect(toolId: string, position: Vector3)
	if toolId == "WateringBucket" then
		burst(position + Vector3.new(0, 1, 0), {
			Color = ColorSequence.new(Color3.fromRGB(130, 210, 255)),
			LightEmission = 0.3,
			Size = NumberSequence.new(0.3, 0.05),
			Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(6, 10),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, -35, 0),
			EmissionDirection = Enum.NormalId.Top,
		}, 25)
	elseif toolId == "PestRemover" then
		bugsFlyAway(position)
		burst(position + Vector3.new(0, 1.5, 0), {
			Color = ColorSequence.new(Color3.fromRGB(220, 255, 220)),
			Size = NumberSequence.new(0.6, 1.6),
			Transparency = NumberSequence.new(0.3, 1),
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(180, 180),
		}, 14)
	else
		burst(position + Vector3.new(0, 1.5, 0), {
			Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(130, 230, 100)),
			LightEmission = 0.6,
			Size = NumberSequence.new(0.35, 0),
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 4, 0),
		}, 20)
	end
end

-- Plays the whole use animation on `character` (anyone's; the arm swing only on our own).
function ToolController.animate(character: Model?, toolId: string, position: Vector3?)
	local motion = MOTION[toolId]
	local tool = findTool(character, toolId)
	if tool and motion and not busyTools[tool] then
		busyTools[tool] = true
		local activeTool = tool :: Tool
		if character == localPlayer.Character then
			-- Animate plays the default tool slash/lunge, and it replicates from our own character.
			local swing = Instance.new("StringValue")
			swing.Name = "toolanim"
			swing.Value = motion.swing
			swing.Parent = activeTool
			Debris:AddItem(swing, 0.3)
		end
		local base = baseGrips[activeTool] or activeTool.Grip
		baseGrips[activeTool] = base
		local handle = activeTool:FindFirstChild("Handle")
		local emitter = handle and handle:FindFirstChild(motion.emitter, true) :: ParticleEmitter?
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - started) / motion.seconds
			if t >= 1 or not activeTool.Parent then
				connection:Disconnect()
				activeTool.Grip = base
				if emitter then
					emitter.Enabled = false
				end
				busyTools[activeTool] = nil
				return
			end
			-- Ease in, hold, ease out.
			local amount = math.sin(math.min(t * 3, 1) * math.pi / 2) * math.sin(math.min((1 - t) * 3, 1) * math.pi / 2)
			local wiggle = math.sin(t * math.pi * 2 * motion.shake) * 0.35 * amount
			activeTool.Grip = base * CFrame.Angles(motion.tilt * amount, 0, wiggle)
			if emitter then
				emitter.Enabled = amount > 0.6
			end
		end)
	end
	if position then
		task.delay(if toolId == "WateringBucket" then 0.35 else 0.2, plantEffect, toolId, position)
	end
end

---------------------------------------------------------------------------
-- Using a tool
---------------------------------------------------------------------------

-- The planted plot to use a tool on. The bucket only waters the crop that was
-- clicked / tapped; the other tools may fall back to the nearest planted plot.
local function targetPlot(toolId: string): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local mouse = localPlayer:GetMouse()
	local aimed = GardenController.plotFor(mouse.Target)
	-- An empty plot under the cursor doesn't count; fall back to the nearest plant.
	if aimed and aimed:GetAttribute("cropId") and (aimed.Position - root.Position).Magnitude <= TOOLS.useDistance then
		return aimed
	end
	if toolId == "WateringBucket" then
		return nil
	end
	return GardenController.nearestPlot(root.Position, TOOLS.useDistance)
end

-- True when the click / tap landed on a button or panel, not on the world.
local function clickedUi(): boolean
	local mouse = localPlayer:GetMouse()
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	for _, gui in playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y) do
		if gui:IsA("GuiButton") or (gui.Active and gui.BackgroundTransparency < 1) then
			return true
		end
	end
	return false
end

local function onActivated(tool: Tool)
	local toolId = toolIdOf(tool)
	if not toolId or os.clock() - lastUse < TOOLS.cooldownSeconds or clickedUi() then
		return
	end
	lastUse = os.clock()
	local plot = targetPlot(toolId)
	if not plot then
		FeelController.play(Net.Feedback.Denied, { reason = if toolId == "WateringBucket" then "ClickCrop" else "NoPlot" })
		return
	end
	ToolController.animate(localPlayer.Character, toolId, plot.Position)
	task.spawn(NetClient.request, Net.Actions.UseTool, {
		toolId = toolId,
		ownerUserId = plot:GetAttribute("OwnerUserId"),
		plotId = plot:GetAttribute("PlotId"),
	})
end

local function refreshLabels()
	local data = ClientState.data
	local bags = if data and data.supplies then data.supplies[TOOLS.items.Fertilizer.supply] or 0 else 0
	for tool in connected do
		if toolIdOf(tool) == "Fertilizer" then
			-- Local rename only: the hotbar shows the name, the server matches the attribute.
			tool.Name = string.format("Fertilizer x%d", bags)
		end
	end
end

local function hook(tool: Instance)
	if not tool:IsA("Tool") or connected[tool] or not toolIdOf(tool) then
		return
	end
	connected[tool] = true
	tool.Activated:Connect(function()
		onActivated(tool)
	end)
	tool.AncestryChanged:Connect(function()
		if not tool.Parent then
			connected[tool] = nil
			baseGrips[tool] = nil
		end
	end)
	refreshLabels()
end

local function watch(container: Instance)
	for _, child in container:GetChildren() do
		hook(child)
	end
	container.ChildAdded:Connect(hook)
end

function ToolController.start()
	localPlayer.CharacterAdded:Connect(watch)
	if localPlayer.Character then
		watch(localPlayer.Character)
	end
	task.spawn(function()
		local backpack = localPlayer:WaitForChild("Backpack")
		watch(backpack)
		localPlayer.ChildAdded:Connect(function(child)
			if child:IsA("Backpack") then
				watch(child)
			end
		end)
	end)

	ClientState.Changed:Connect(refreshLabels)

	-- Other players' tool uses: play their animation here too.
	FeelController.Played:Connect(function(name, ctx)
		if name ~= Net.Feedback.ToolUsed or ctx.userId == localPlayer.UserId then
			return
		end
		local user = Players:GetPlayerByUserId(ctx.userId)
		ToolController.animate(user and user.Character, ctx.toolId, ctx.position)
	end)
end

return ToolController
