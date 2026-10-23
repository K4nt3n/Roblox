--!strict
--[[
	Studs: gives a part the classic Roblox studded top. Used by MapBuilder and by
	PlotService for the gardens, stands and stage. Off when Config.Map.studs is false.

	Default: Plastic material + Studs top surface (built in, no upload needed).
	With Config.Map.studTexture set: a tiled Texture on the top face instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Studs = {}

function Studs.apply(part: BasePart)
	local m = Config.Map
	if not m.studs then
		return
	end
	if m.studTexture ~= "" then
		local texture = Instance.new("Texture")
		texture.Name = "Studs"
		texture.Texture = m.studTexture
		texture.Face = Enum.NormalId.Top
		texture.StudsPerTileU = m.studTextureTile
		texture.StudsPerTileV = m.studTextureTile
		texture.Parent = part
		return
	end
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Inlet
end

return Studs
