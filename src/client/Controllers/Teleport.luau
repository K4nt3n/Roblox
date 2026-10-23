--!strict
--[[
	Teleport: the two HUD travel buttons.

	  Teleport.toGarden()  in front of your champion pad, facing your garden
	                       (same spot the server spawns you at)
	  Teleport.toShops()   the shop area in the middle (Seed Shop, Sell, Weigh-In Fair),
	                       on the side you came from, facing the stands

	The client owns its character, so PivotTo replicates. A short fade hides the jump.
]]

local Players = game:GetService("Players")

local Tweens = require(script.Parent.Parent.Feel.Tweens)
local FeelController = require(script.Parent.Parent.Feel.FeelController)

local Teleport = {}

local localPlayer = Players.LocalPlayer

local COOLDOWN = 1.5
local SHOP_DISTANCE = 16 -- studs from the middle of the stands
local FADE_TIME = 0.15

local lastAt = -math.huge
local fade: Frame? = nil

local function rootPart(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function gardenCFrame(): CFrame?
	local gardens = workspace:FindFirstChild("Gardens")
	local garden = gardens and gardens:FindFirstChild("Garden_" .. localPlayer.UserId)
	local pad = garden and garden:FindFirstChild("ChampionPad")
	if not pad or not pad:IsA("BasePart") then
		return nil
	end
	-- Mirrors PlotService:GetSpawnCFrame.
	return CFrame.lookAt(
		pad.Position + pad.CFrame.LookVector * -(pad.Size.Z / 2 + 4) + Vector3.new(0, 4, 0),
		pad.Position + Vector3.new(0, 4, 0)
	)
end

local function groundBelow(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character :: Instance }
	local hit = workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position + Vector3.new(0, 4, 0) else position
end

local function shopCFrame(): CFrame?
	local stands = workspace:FindFirstChild("Stands")
	if not stands then
		return nil
	end
	local sum, count = Vector3.zero, 0
	for _, child in stands:GetChildren() do
		if child:IsA("PVInstance") then
			sum += child:GetPivot().Position
			count += 1
		end
	end
	if count == 0 then
		return nil
	end
	local center = sum / count
	-- Arrive on the side the player is coming from, so the stands are in front of them.
	local root = rootPart()
	local away = if root then root.Position - center else Vector3.new(0, 0, 1)
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	local spot = groundBelow(center + away * SHOP_DISTANCE)
	return CFrame.lookAt(spot, Vector3.new(center.X, spot.Y, center.Z))
end

local function fadeFrame(): Frame?
	if fade and fade.Parent then
		return fade
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GVF_TeleportFade"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	gui.Parent = playerGui
	fade = frame
	return frame
end

local function go(target: CFrame?)
	local character = localPlayer.Character
	if not target or not character or os.clock() - lastAt < COOLDOWN then
		return
	end
	lastAt = os.clock()
	FeelController.play("PanelOpen")
	local frame = fadeFrame()
	if frame then
		frame.BackgroundTransparency = 1
		local tween = Tweens.play(frame, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 0.15 })
		if tween then
			tween.Completed:Wait()
		end
	end
	character:PivotTo(target)
	local root = rootPart()
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	if frame then
		Tweens.play(frame, TweenInfo.new(FADE_TIME * 2), { BackgroundTransparency = 1 })
	end
end

function Teleport.toGarden()
	go(gardenCFrame())
end

function Teleport.toShops()
	go(shopCFrame())
end

return Teleport
