--!strict
--[[
	MapBuilder: turns shared/MapLayout's pieces into Parts under Workspace.Map.

	MapService calls build() at runtime when the place has no Workspace.Map.
	To bake the map into the place so it can be seen and edited in Studio, run this in
	the Studio command bar (edit mode), then save:

	    require(game.ServerScriptService.Server.Map.MapBuilder).build()

	A baked (or hand-made) Workspace.Map is left alone at runtime.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local Studs = require(script.Parent.Studs)

local MapBuilder = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function addText(part: BasePart, text: string)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Label" .. face.Name
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = text
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(30, 30, 40)
		stroke.Parent = label
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(0.12, 0)
		pad.Parent = label
	end
end

local function makePart(piece: MapLayout.Piece): BasePart
	local part: BasePart
	if piece.name == "Spawn" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Neutral = true
		spawn.Duration = 0
		part = spawn
	elseif piece.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if piece.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Name = piece.name
	part.Anchored = true
	part.Size = Vector3.new(piece.size[1], piece.size[2], piece.size[3])
	local cf = CFrame.new(piece.pos[1], piece.pos[2], piece.pos[3]) * CFrame.Angles(0, math.rad(piece.yaw or 0), 0)
	if piece.shape == "Cylinder" then
		-- Cylinders run along X; stand them up so the flat face points up.
		cf *= CFrame.Angles(0, 0, math.rad(90))
	end
	part.CFrame = cf
	part.Color = rgb(piece.color)
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if piece.studs then
		Studs.apply(part)
	end
	if piece.collide == false then
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end
	if piece.kind == "ground" or piece.kind == "path" then
		part.CastShadow = false
	end
	if piece.neon then
		part.Material = Enum.Material.Neon
	end
	if piece.light then
		local light = Instance.new("PointLight")
		light.Color = part.Color
		light.Range = 18
		light.Brightness = 1.2
		light.Parent = part
	end
	if piece.text then
		addText(part, piece.text)
	end
	return part
end

-- Builds a fresh Workspace.Map (replacing an older generated one). Returns the model.
function MapBuilder.build(parent: Instance?): Model
	local target = parent or workspace
	local old = target:FindFirstChild("Map")
	if old and old:GetAttribute("StuddedMap") then
		old:Destroy()
	end

	local layout = MapLayout.build(Config)
	local map = Instance.new("Model")
	map.Name = "Map"
	map:SetAttribute("StuddedMap", true)

	local groups: { [string]: Folder } = {}
	for _, piece in layout.pieces do
		local folder = groups[piece.group]
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = piece.group
			folder.Parent = map
			groups[piece.group] = folder
		end
		makePart(piece).Parent = folder
	end

	local ground = groups.Ground and groups.Ground:FindFirstChild("Grass")
	if ground and ground:IsA("BasePart") then
		map.PrimaryPart = ground
	end
	map.Parent = target
	return map
end

return MapBuilder
