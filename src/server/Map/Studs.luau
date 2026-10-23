--!strict
--[[
	Studs: gives parts the classic Roblox studded look. Used by MapService for the
	island (Workspace.Map, Stands, FairStage) and by PlotService for the gardens.
	Off when Config.Map.studs is false.

	* Studs go on whichever face points up (StudMath.upFace), because the island
	  is built from rotated wedges. Walls and steep rocks get none.
	* Blocks and wedges use the built-in Studs surface (needs Plastic). Cylinders
	  can't show surfaces, so they only get studs from Config.Map.studTexture.
	* Colours get a little more vivid; Wood/SmoothPlastic become Plastic.
	* Balls (leaves, bushes) and invisible parts only get the colour and material.
	Each part is styled once (attribute "Studded"), so running it twice is harmless.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local StudMath = require(Shared.StudMath)

local Studs = {}

local KEEP_MATERIAL = {
	[Enum.Material.Neon] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.ForceField] = true,
}

local function addTexture(part: BasePart, face: Enum.NormalId)
	local m = Config.Map
	local texture = Instance.new("Texture")
	texture.Name = "Studs"
	texture.Texture = m.studTexture
	texture.Face = face
	texture.StudsPerTileU = m.studTextureTile
	texture.StudsPerTileV = m.studTextureTile
	texture.Parent = part
end

function Studs.apply(part: BasePart)
	local m = Config.Map
	if not m.studs or part:GetAttribute("Studded") then
		return
	end
	part:SetAttribute("Studded", true)
	if part.Transparency >= 1 then
		return
	end

	if m.saturation ~= 1 or m.brightness ~= 1 then
		local c = part.Color
		part.Color = Color3.new(StudMath.vivid(c.R, c.G, c.B, m.saturation, m.brightness))
	end
	if m.plastic and not KEEP_MATERIAL[part.Material] then
		part.Material = Enum.Material.Plastic
	end

	local shape = if part:IsA("Part") then part.Shape else nil
	if shape == Enum.PartType.Ball then
		return
	end
	local cf = part.CFrame
	local faceName = StudMath.upFace(cf.RightVector.Y, cf.UpVector.Y, cf.LookVector.Y)
	if not faceName then
		return
	end
	local face = (Enum.NormalId :: any)[faceName] :: Enum.NormalId
	if m.studTexture ~= "" then
		addTexture(part, face)
	elseif shape ~= Enum.PartType.Cylinder then
		part.Material = Enum.Material.Plastic -- surfaces only render on Plastic
		local surface = Enum.SurfaceType.Studs
		if faceName == "Top" then
			part.TopSurface = surface
		elseif faceName == "Bottom" then
			part.BottomSurface = surface
		elseif faceName == "Right" then
			part.RightSurface = surface
		elseif faceName == "Left" then
			part.LeftSurface = surface
		elseif faceName == "Front" then
			part.FrontSurface = surface
		else
			part.BackSurface = surface
		end
	end
end

-- Styles every part under `root` and any part added to it later.
function Studs.applyTree(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			Studs.apply(d)
		end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			Studs.apply(d)
		end
	end)
end

return Studs
