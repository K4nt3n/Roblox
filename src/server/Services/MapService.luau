--!strict
--[[
	MapService: gives the island the studded look at server start.

	The island (Workspace.Map: grass, beach, paths, plaza, fences, trees), the
	stands and the fair stage are hand-built in the place. This only restyles the
	live copy (studs, Plastic, brighter colours; see server/Map/Studs): nothing is
	moved, and the saved place is unchanged. Gardens get studs from PlotService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Studs = require(script.Parent.Parent.Map.Studs)

local MapService = {}

function MapService:Init()
	if not Config.Map.studs then
		return
	end
	for _, name in Config.Map.folders do
		local root = workspace:FindFirstChild(name)
		if root then
			Studs.applyTree(root)
		end
	end
end

return MapService
