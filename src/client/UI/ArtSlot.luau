--!strict
--[[
	ArtSlot: a named spot where Peter's art drops in.

	    ArtSlot.icon("CoinIcon", { size = 40, color = Theme.Colors.Gold, glyph = "C" })

	If Theme.Art[slot] has an asset id, an ImageLabel is drawn. Otherwise a
	flat placeholder shape (rounded square or circle, with a short glyph) is
	drawn in the same box, so swapping art never moves anything.

	Every slot instance is named "Art_<slot>" and carries an "ArtSlot"
	attribute, so they are easy to find in the Explorer. Set
	ArtSlot.showLabels = true (Studio) to print slot names on the placeholders.
]]

local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)

local ArtSlot = {}

ArtSlot.showLabels = false

export type IconOptions = {
	size: number?,
	color: Color3?,
	glyph: string?,
	round: boolean?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
}

function ArtSlot.asset(slot: string): string?
	local id = Theme.Art[slot]
	return if id and id ~= "" then id else nil
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

-- A square icon slot.
function ArtSlot.icon(slot: string, options: IconOptions?): GuiObject
	local opts = options or {}
	local size = opts.size or 36
	local asset = ArtSlot.asset(slot)
	local gui: GuiObject
	if asset then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = asset
		image.ScaleType = Enum.ScaleType.Fit
		gui = image
	else
		local frame = Instance.new("Frame")
		local color = opts.color or Theme.Colors.SurfaceAlt
		frame.BackgroundColor3 = color
		corner(frame, if opts.round then Theme.CornerRound else UDim.new(0.28, 0))
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.darken(color, 0.22)
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		-- Soft top highlight keeps flat placeholders from looking dead.
		local shine = Instance.new("UIGradient")
		shine.Rotation = 90
		shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(225, 225, 225))
		shine.Parent = frame
		local glyph = Instance.new("TextLabel")
		glyph.Name = "Glyph"
		glyph.BackgroundTransparency = 1
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Font = Theme.Font
		glyph.Text = opts.glyph or ""
		glyph.TextScaled = true
		glyph.TextColor3 = Theme.textOn(color)
		local pad = Instance.new("UIPadding")
		local inset = UDim.new(0.2, 0)
		pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = inset, inset, inset, inset
		pad.Parent = glyph
		glyph.Parent = frame
		if ArtSlot.showLabels and RunService:IsStudio() then
			local tag = Instance.new("TextLabel")
			tag.BackgroundTransparency = 1
			tag.AnchorPoint = Vector2.new(0.5, 0)
			tag.Position = UDim2.new(0.5, 0, 1, 2)
			tag.Size = UDim2.fromOffset(0, 12)
			tag.AutomaticSize = Enum.AutomaticSize.X
			tag.Font = Enum.Font.Code
			tag.TextSize = 10
			tag.Text = slot
			tag.TextColor3 = Theme.Colors.Danger
			tag.Parent = frame
		end
		gui = frame
	end
	gui.Name = "Art_" .. slot
	gui:SetAttribute("ArtSlot", slot)
	gui.BorderSizePixel = 0
	gui.Size = UDim2.fromOffset(size, size)
	gui.AnchorPoint = opts.anchor or Vector2.zero
	gui.Position = opts.position or UDim2.new()
	gui.LayoutOrder = opts.layoutOrder or 0
	if opts.zIndex then
		gui.ZIndex = opts.zIndex
	end
	return gui
end

--[[
	Skins a frame with 9-slice art if the slot is filled (e.g. "PanelFrame").
	Returns true when art was applied, so callers can skip placeholder strokes.
]]
function ArtSlot.skin(frame: GuiObject, slot: string): boolean
	local asset = ArtSlot.asset(slot)
	frame:SetAttribute("ArtSlot", slot)
	if not asset then
		return false
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Art_" .. slot
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = asset
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Theme.ArtSlice[slot] or Rect.new(0, 0, 0, 0)
	image.ZIndex = 0
	image.Parent = frame
	frame.BackgroundTransparency = 1
	return true
end

return ArtSlot
