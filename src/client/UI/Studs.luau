--!strict
--[[
	Studs: the subtle square-stud texture on colored faces (buttons, pills,
	panel headers), like the big "studded" Roblox games.

	    Studs.apply(button)

	The texture is a tile with one stud, repeated over the face and laid on
	top of its color, so one tile works on every color. Where it comes from:
	  1. Theme.Art.StudTile, if Peter uploads his own tile.
	  2. Otherwise a tile drawn in code (EditableImage), made once and shared.
	If neither is available nothing is drawn, and the faces stay flat.
	Size and strength: Theme.Style.StudSize / StudTransparency / Studs.
]]

local AssetService = game:GetService("AssetService")

local Theme = require(script.Parent.Theme)
local ArtSlot = require(script.Parent.ArtSlot)

local Studs = {}

-- Texture pixels per stud. The tile is drawn bigger than it shows, so edges stay soft.
local TILE = 32
local INSET = 3 -- gap between studs
local EDGE = 2 -- width of the light and dark bevel
local RADIUS = 5

type Pixel = { number } -- r, g, b, a (0-255)

local GROUT: Pixel = { 0, 0, 0, 46 }
local LIGHT: Pixel = { 255, 255, 255, 120 }
local SHADE: Pixel = { 0, 0, 0, 90 }
local FACE: Pixel = { 255, 255, 255, 22 }

-- Distance outside the rounded stud square (0 or less is inside).
local function outside(x: number, y: number): number
	local lo, hi = INSET + RADIUS, TILE - 1 - INSET - RADIUS
	local dx = math.max(lo - x, 0, x - hi)
	local dy = math.max(lo - y, 0, y - hi)
	return math.sqrt(dx * dx + dy * dy) - RADIUS
end

-- One pixel of the stud tile: grout between studs, a bevel (light top-left,
-- dark bottom-right) and a faint face.
function Studs.pixel(x: number, y: number): Pixel
	local d = outside(x + 0.5, y + 0.5)
	if d > 0.5 then
		return GROUT
	end
	if d > -EDGE then
		-- On the bevel: light where it faces up-left, dark where it faces down-right.
		local center = (TILE - 1) / 2
		return if (x - center) + (y - center) < 0 then LIGHT else SHADE
	end
	return FACE
end

local tile: any = nil
local triedTile = false

local function makeTile(): any
	local ok, image = pcall(function()
		return (AssetService :: any):CreateEditableImage({ Size = Vector2.new(TILE, TILE) })
	end)
	if not ok or not image then
		return nil
	end
	local pixels = buffer.create(TILE * TILE * 4)
	for y = 0, TILE - 1 do
		for x = 0, TILE - 1 do
			local p = Studs.pixel(x, y)
			local i = (y * TILE + x) * 4
			buffer.writeu8(pixels, i, p[1])
			buffer.writeu8(pixels, i + 1, p[2])
			buffer.writeu8(pixels, i + 2, p[3])
			buffer.writeu8(pixels, i + 3, p[4])
		end
	end
	local wrote = pcall(function()
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(TILE, TILE), pixels)
	end)
	return if wrote then image else nil
end

-- Points `label` at the stud tile. False when there is no tile to show.
local function setTexture(label: ImageLabel): boolean
	local asset = ArtSlot.asset("StudTile")
	if asset then
		label.Image = asset
		return true
	end
	if not triedTile then
		triedTile = true
		tile = makeTile()
	end
	if not tile then
		return false
	end
	return pcall(function()
		(label :: any).ImageContent = (Content :: any).fromObject(tile)
	end)
end

--[[
	Lays the stud texture over `gui`'s face (under its text and icons).
	Skipped when studs are off, already there, or `gui` arranges its children
	with a layout (the texture would be laid out like a child).
]]
function Studs.apply(gui: GuiObject, transparency: number?): ImageLabel?
	local style = Theme.Style
	if not style.Studs or gui:FindFirstChild("Studs") or gui:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return nil
	end
	local label = Instance.new("ImageLabel")
	label.Name = "Studs"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ScaleType = Enum.ScaleType.Tile
	label.TileSize = UDim2.fromOffset(style.StudSize, style.StudSize)
	label.ImageTransparency = transparency or style.StudTransparency
	label.ZIndex = 1
	label.Active = false
	if not setTexture(label) then
		label:Destroy()
		return nil
	end
	local corner = gui:FindFirstChildOfClass("UICorner")
	if corner then
		-- Follow the face's corner, also when a caller rounds it more later.
		local round = Instance.new("UICorner")
		round.CornerRadius = corner.CornerRadius
		round.Parent = label
		corner:GetPropertyChangedSignal("CornerRadius"):Connect(function()
			round.CornerRadius = corner.CornerRadius
		end)
	end
	label.Parent = gui
	return label
end

return Studs
