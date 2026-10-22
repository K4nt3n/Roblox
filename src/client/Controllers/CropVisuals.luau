--!strict
--[[
	CropVisuals: builds and scales the thing that sits on a plot.

	Art seam: put a Model named after the crop id (e.g. "pumpkin") in
	ReplicatedStorage.Assets.Crops and it is used automatically, scaled with
	Model:ScaleTo. Optional children "Seed", "Sprout", "Growing", "Ripe",
	"Giant" models are swapped per stage. Until then a smooth placeholder ball
	is used.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CropVisuals = {}

export type Visual = {
	root: Model,
	isPlaceholder: boolean,
	cropId: string,
	stage: string?,
	scale: number,
}

-- Studs of diameter per cube-root kg. Volume tracks weight, so a 8x heavier crop looks 2x wider.
local STUDS_PER_CBRT_KG = 2.4
local MIN_SCALE = 0.35
local MAX_SCALE = 7
local STAGES = { Seed = true, Sprout = true, Growing = true, Ripe = true, Giant = true }

local function template(cropId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local crops = assets and assets:FindFirstChild("Crops")
	local model = crops and crops:FindFirstChild(cropId)
	return if model and model:IsA("Model") then model else nil
end

function CropVisuals.targetScale(weight: number): number
	return math.clamp(STUDS_PER_CBRT_KG * weight ^ (1 / 3), MIN_SCALE, MAX_SCALE)
end

function CropVisuals.create(cropId: string): Visual
	local art = template(cropId)
	if art then
		local root = art:Clone()
		return { root = root, isPlaceholder = false, cropId = cropId, stage = nil, scale = 1 }
	end

	local root = Instance.new("Model")
	root.Name = cropId
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	local crop = Config.Crops[cropId]
	local c = if crop then crop.placeholderColor else { 255, 255, 255 }
	body.Color = Color3.fromRGB(c[1], c[2], c[3])
	body.Size = Vector3.one
	body.Parent = root
	root.PrimaryPart = body
	return { root = root, isPlaceholder = true, cropId = cropId, stage = nil, scale = 1 }
end

-- Places the visual on the plot at the given (already smoothed) scale.
function CropVisuals.apply(visual: Visual, plot: BasePart, scale: number, stage: string)
	local root = visual.root
	if visual.isPlaceholder then
		local body = root.PrimaryPart :: BasePart
		-- Seeds and sprouts read as small and earthy; colour fades in as it ripens.
		body.Size = Vector3.one * scale
		body.CFrame = plot.CFrame * CFrame.new(0, plot.Size.Y / 2 + scale / 2 - scale * 0.1, 0)
		local crop = Config.Crops[visual.cropId]
		local c = if crop then crop.placeholderColor else { 255, 255, 255 }
		local ripeColor = Color3.fromRGB(c[1], c[2], c[3])
		local sprout = Color3.fromRGB(120, 190, 90)
		local t = if stage == "Seed" then 0 elseif stage == "Sprout" then 0.15 elseif stage == "Growing" then 0.55 else 1
		body.Color = sprout:Lerp(ripeColor, t)
	else
		-- Art models declare their natural diameter with a "BaseDiameter" attribute (default 2.4 studs).
		local factor = scale / (root:GetAttribute("BaseDiameter") or STUDS_PER_CBRT_KG)
		if math.abs(visual.scale - factor) > 0.001 then
			root:ScaleTo(math.max(factor, 0.05))
			visual.scale = factor
		end
		local _, size = root:GetBoundingBox()
		root:PivotTo(plot.CFrame * CFrame.new(0, plot.Size.Y / 2 + size.Y / 2, 0))
		if stage ~= visual.stage then
			for _, child in root:GetChildren() do
				local isStageModel = child:IsA("Model") and STAGES[child.Name] == true
				if isStageModel then
					for _, d in child:GetDescendants() do
						if d:IsA("BasePart") then
							d.LocalTransparencyModifier = if child.Name == stage then 0 else 1
						end
					end
				end
			end
		end
	end
	visual.stage = stage
end

return CropVisuals
