--!strict
--[[
	EssenceFX: glowing XP "essence" orbs.

	When XP is earned, orbs pop out of the crop, tumble down for a moment
	under gravity, then get pulled along a curved path into the level bar,
	speeding up as they go. Each arrival calls onArrive so the bar can fill in
	steps and pulse; onDone runs after the last one lands.

	Placeholder look: soft round frames with a glow stroke. Art seam: set
	EssenceFX.template to a GuiObject (e.g. an ImageLabel with a sparkle) and
	it is cloned for each orb instead.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Tweens = require(script.Parent.Tweens)

local EssenceFX = {}

EssenceFX.template = nil :: GuiObject?
EssenceFX.color = Color3.fromRGB(150, 235, 120)
EssenceFX.glow = Color3.fromRGB(255, 245, 160)

-- Timings (seconds) and physics (pixels).
local DROP_TIME = { 0.32, 0.5 }
local FLY_TIME = { 0.5, 0.8 }
local STAGGER = 0.035
local GRAVITY = 1400
local POP_SPEED = { 220, 380 }
local ORB_SIZE = { 12, 18 }

type Orb = {
	gui: GuiObject,
	scale: UIScale,
	startAt: number,
	dropTime: number,
	flyTime: number,
	p0: Vector2,
	v0: Vector2,
	p1: Vector2?,
	control: Vector2?,
	arrived: boolean,
}

type Burst = {
	orbs: { Orb },
	target: GuiObject,
	arrivedCount: number,
	onArrive: ((index: number, total: number) -> ())?,
	onDone: (() -> ())?,
}

local bursts: { Burst } = {}
local layer: ScreenGui? = nil
local rng = Random.new()
local connection: RBXScriptConnection? = nil

local function getLayer(): ScreenGui
	if layer and layer.Parent then
		return layer
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GVF_Essence"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	layer = gui
	return gui
end

local function between(range: { number }): number
	return rng:NextNumber(range[1], range[2])
end

-- Center of a GuiObject in the essence layer's coordinates (which ignore the top-bar inset).
local function targetPoint(target: GuiObject): Vector2
	local center = target.AbsolutePosition + target.AbsoluteSize / 2
	local screenGui = target:FindFirstAncestorOfClass("ScreenGui")
	if screenGui and not screenGui.IgnoreGuiInset then
		local inset = GuiService:GetGuiInset()
		center += inset
	end
	return center
end

local function makeOrb(): GuiObject
	if EssenceFX.template then
		return EssenceFX.template:Clone()
	end
	local size = between(ORB_SIZE)
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Size = UDim2.fromOffset(size, size)
	orb.BackgroundColor3 = EssenceFX.color
	orb.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = orb
	local stroke = Instance.new("UIStroke")
	stroke.Color = EssenceFX.glow
	stroke.Thickness = 3
	stroke.Transparency = 0.35
	stroke.Parent = orb
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.45, 0.45)
	core.BackgroundColor3 = Color3.new(1, 1, 1)
	core.BackgroundTransparency = 0.15
	core.BorderSizePixel = 0
	local coreCorner = corner:Clone()
	coreCorner.Parent = core
	core.Parent = orb
	return orb
end

local function quadBezier(a: Vector2, c: Vector2, b: Vector2, t: number): Vector2
	local u = 1 - t
	return a * (u * u) + c * (2 * u * t) + b * (t * t)
end

local function step()
	local now = os.clock()
	for bi = #bursts, 1, -1 do
		local burst = bursts[bi]
		local goal = targetPoint(burst.target)
		for _, orb in burst.orbs do
			if orb.arrived then
				continue
			end
			local t = now - orb.startAt
			if t < 0 then
				continue
			end
			orb.gui.Visible = true
			if t < orb.dropTime then
				-- Pop out and tumble down.
				local pos = orb.p0 + orb.v0 * t + Vector2.new(0, 0.5 * GRAVITY * t * t)
				orb.gui.Position = UDim2.fromOffset(pos.X, pos.Y)
				orb.scale.Scale = math.min(1, t / 0.08)
			else
				if not orb.p1 then
					local d = orb.dropTime
					orb.p1 = orb.p0 + orb.v0 * d + Vector2.new(0, 0.5 * GRAVITY * d * d)
					-- Curve sideways so the stream fans out instead of flying in a straight line.
					local p1 = orb.p1 :: Vector2
					local mid = (p1 + goal) / 2
					local dir = goal - p1
					local normal = Vector2.new(-dir.Y, dir.X).Unit
					orb.control = mid + normal * rng:NextNumber(-0.35, 0.35) * dir.Magnitude + Vector2.new(0, -60)
				end
				local f = math.clamp((t - orb.dropTime) / orb.flyTime, 0, 1)
				-- Ease in: slow start, then sucked into the bar.
				local eased = f * f * (1.6 - 0.6 * f)
				local pos = quadBezier(orb.p1 :: Vector2, orb.control :: Vector2, goal, eased)
				orb.gui.Position = UDim2.fromOffset(pos.X, pos.Y)
				orb.scale.Scale = 1 - 0.45 * f
				if f >= 1 then
					orb.arrived = true
					orb.gui:Destroy()
					burst.arrivedCount += 1
					if burst.onArrive then
						task.spawn(burst.onArrive, burst.arrivedCount, #burst.orbs)
					end
				end
			end
		end
		if burst.arrivedCount >= #burst.orbs then
			table.remove(bursts, bi)
			if burst.onDone then
				task.spawn(burst.onDone)
			end
		end
	end
	if #bursts == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- How many orbs are still in the air.
function EssenceFX.active(): number
	local count = 0
	for _, burst in bursts do
		count += #burst.orbs - burst.arrivedCount
	end
	return count
end

function EssenceFX.countFor(xp: number): number
	return math.clamp(math.floor(xp / 4) + 3, 4, 16)
end

--[[
	from: world position (Vector3) or screen position (Vector2); nil = bottom center.
	target: the GuiObject to fly into (the level bar).
]]
function EssenceFX.burst(
	from: Vector3 | Vector2 | nil,
	target: GuiObject,
	count: number,
	onArrive: ((index: number, total: number) -> ())?,
	onDone: (() -> ())?
)
	local gui = getLayer()
	local camera = workspace.CurrentCamera
	local origin: Vector2
	if typeof(from) == "Vector3" and camera then
		local point = camera:WorldToViewportPoint(from)
		origin = Vector2.new(point.X, point.Y)
	elseif typeof(from) == "Vector2" then
		origin = from
	else
		origin = gui.AbsoluteSize * Vector2.new(0.5, 0.8)
	end

	if Tweens.reducedMotion then
		-- No flying orbs: just fill the bar.
		for i = 1, count do
			if onArrive then
				onArrive(i, count)
			end
		end
		if onDone then
			onDone()
		end
		return
	end

	local orbs = {}
	local now = os.clock()
	for i = 1, count do
		local orbGui = makeOrb()
		orbGui.Visible = false
		orbGui.Position = UDim2.fromOffset(origin.X, origin.Y)
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = orbGui
		orbGui.Parent = gui
		-- Mostly upward, fanned out.
		local angle = math.rad(rng:NextNumber(-150, -30))
		local speed = between(POP_SPEED)
		table.insert(orbs, {
			gui = orbGui,
			scale = scale,
			startAt = now + (i - 1) * STAGGER,
			dropTime = between(DROP_TIME),
			flyTime = between(FLY_TIME),
			p0 = origin + Vector2.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)),
			v0 = Vector2.new(math.cos(angle), math.sin(angle)) * speed,
			p1 = nil,
			control = nil,
			arrived = false,
		})
	end
	table.insert(bursts, { orbs = orbs, target = target, arrivedCount = 0, onArrive = onArrive, onDone = onDone })
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

return EssenceFX
