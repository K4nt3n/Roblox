--!strict
--[[
	MapService: makes sure the world has a map.

	* If the place has no Workspace.Map, builds the studded map (server/Map/MapBuilder)
	  during Init, so PlotService:Start sees it and skips its placeholder baseplate.
	* A hand-made Workspace.Map (no "StuddedMap" attribute) is never touched, and a
	  Workspace.GardenSlots folder (custom garden positions) skips the map.
	* Under a studded map, hides the default Baseplate and any other SpawnLocation
	  (they sit at the same height as its ground and spawn pad). Runtime only; the
	  saved place keeps them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MapBuilder = require(script.Parent.Parent.Map.MapBuilder)

local MapService = {}

local function hide(part: BasePart)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	for _, child in part:GetChildren() do
		if child:IsA("Decal") or child:IsA("Texture") then
			child.Transparency = 1
		end
	end
end

local function hideDefaults(map: Instance)
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		hide(baseplate)
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and not d:IsDescendantOf(map) then
			d.Enabled = false
			hide(d)
		end
	end
end

function MapService:Init()
	if not Config.Map.enabled then
		return
	end
	local map = workspace:FindFirstChild("Map")
	if not map then
		if workspace:FindFirstChild("GardenSlots") then
			-- Custom garden positions: the generated layout wouldn't line up with them.
			warn("[MapService] Workspace.GardenSlots found; skipping the studded map")
			return
		end
		map = MapBuilder.build()
	end
	if map:GetAttribute("StuddedMap") and Config.Map.hideBaseplate then
		hideDefaults(map)
	end
end

return MapService
