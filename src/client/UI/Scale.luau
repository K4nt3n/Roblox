--!strict
--[[
	Scale: one responsive scale for every screen.

	UI is laid out in design pixels at a 1280x720 reference. Scale.root(gui)
	gives a ScreenGui a full-screen root frame whose UIScale maps design pixels
	to the real screen, so a 44 px button stays thumb sized on a phone and
	does not look tiny on a 1440p monitor.

	The curve is softened (square-root-ish) so phones shrink less than the raw
	ratio would and big monitors grow less. Scale.device tells layouts whether
	they are on a Phone, Tablet or Desktop; Scale.Changed fires when it or the
	scale changes (rotation, window resize).

	Settings hook (G10): set Scale.setUserMultiplier(0.9..1.2) for a UI size slider.

	Studio preview: set a Workspace attribute UIPreviewDevice = "Phone" (or
	"Tablet") before pressing Play to see that layout on a PC. Ignored in live games.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local Scale = {}

export type Device = "Phone" | "Tablet" | "Desktop"

Scale.REFERENCE = Vector2.new(1280, 720)
Scale.MIN = 0.62
Scale.MAX = 1.4
-- Phones never go below this, so touch targets stay at least ~32 pt.
Scale.PHONE_MIN = 0.72

Scale.value = 1
Scale.device = "Desktop" :: Device
Scale.Changed = Signal.new() -- (scale, device)

local userMultiplier = 1
local roots: { [Frame]: UIScale } = {}

local function viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Scale.REFERENCE
end

local function classify(size: Vector2): Device
	local preview = workspace:GetAttribute("UIPreviewDevice")
	if RunService:IsStudio() and (preview == "Phone" or preview == "Tablet") then
		return preview
	end
	if not UserInputService.TouchEnabled then
		return "Desktop"
	end
	if math.min(size.X, size.Y) < 500 then
		return "Phone"
	end
	return "Tablet"
end

function Scale.compute(size: Vector2, device: Device): number
	local raw = math.min(size.X / Scale.REFERENCE.X, size.Y / Scale.REFERENCE.Y)
	local soft = raw ^ 0.55
	local minimum = if device == "Phone" then Scale.PHONE_MIN else Scale.MIN
	return math.clamp(soft, minimum, Scale.MAX) * userMultiplier
end

local function apply(root: Frame, uiScale: UIScale)
	local s = Scale.value
	uiScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end

local function refresh()
	local size = viewport()
	if size.X < 2 or size.Y < 2 then
		return
	end
	local device = classify(size)
	local value = Scale.compute(size, device)
	if math.abs(value - Scale.value) < 0.001 and device == Scale.device then
		return
	end
	Scale.value = value
	Scale.device = device
	for root, uiScale in roots do
		if root.Parent then
			apply(root, uiScale)
		else
			roots[root] = nil
		end
	end
	Scale.Changed:Fire(value, device)
end

function Scale.isPhone(): boolean
	return Scale.device == "Phone"
end

function Scale.setUserMultiplier(multiplier: number)
	userMultiplier = math.clamp(multiplier, 0.75, 1.3)
	Scale.value = 0 -- force a refresh
	refresh()
end

-- Converts design pixels to screen pixels (for code that draws outside a root, like EssenceFX).
function Scale.px(designPixels: number): number
	return designPixels * Scale.value
end

--[[
	Adds a full-screen, scaled root frame to a ScreenGui and returns it.
	Parent everything to the root and size it in design pixels.
]]
function Scale.root(screenGui: ScreenGui, name: string?): Frame
	local root = Instance.new("Frame")
	root.Name = name or "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ResponsiveScale"
	uiScale.Parent = root
	roots[root] = uiScale
	apply(root, uiScale)
	root.Parent = screenGui
	return root
end

local cameraConnection: RBXScriptConnection? = nil
local function watchCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

return Scale
