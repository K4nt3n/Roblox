--!strict
--[[
	UIKit: tiny builders for consistent placeholder UI. Every interactive
	element gets hover/press motion and a ButtonPress feel event for free.
	When final UI art arrives, re-skin here (images, 9-slice via ArtSlot) and
	every screen updates.

	Buttons
	  UIKit.button(text, onClick, props)        springy button (hover lift, press squash, release pop)
	  UIKit.setEnabled(button, on, color, why)  disabled buttons go grey and shake when tapped;
	                                            `why` is shown as a toast so kids know what to do
	  UIKit.requestButton(text, action, payload, props)
	                                            calls the server, shows a busy state while waiting,
	                                            pops on success and shakes on a denial
	Layout
	  UIKit.card / row / label / list / padding / corner / stroke
	  UIKit.panel(title, size, onClose, options)  modal panel with header, art slot and body
	  UIKit.tabs(parent, items, selected, onSelect)  segmented control with a sliding highlight
	  UIKit.badge(parent)  + UIKit.setBadge(badge, value)  notification dot / count
	Finish (all tuned in Theme.Style)
	  UIKit.paint(gui, color)    candy gradient on a white base (call again to recolor)
	  UIKit.outlineText(text)    dark outline around white text
	  UIKit.gloss(gui)           glossy strip across the top half
	  UIKit.sweep(gui)           a shine that sweeps across now and then (key buttons)
	  UIKit.shadow(gui)          soft drop shadow (for things not inside a list layout)
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local ArtSlot = require(script.Parent.ArtSlot)
local Icons = require(script.Parent.Icons)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local EssenceFX = require(script.Parent.Parent.Feel.EssenceFX)
local FeelController = require(script.Parent.Parent.Feel.FeelController)
local NetClient = require(script.Parent.Parent.NetClient)

local UIKit = {}

type Props = { [string]: any }

-- Set by UIController: shows a toast when a disabled button is tapped.
UIKit.onDisabledPress = nil :: ((reason: string) -> ())?

-- Where the last button press happened (screen point), for effects that fly from it.
UIKit.lastPress = { point = Vector2.zero, at = 0 }

function UIKit.new(className: string, props: Props?, children: { Instance }?): any
	local inst = Instance.new(className)
	for key, value in props or {} do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	-- Parent last so the instance is fully built before it appears.
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UIKit.corner(radius: UDim?): UICorner
	return UIKit.new("UICorner", { CornerRadius = radius or Theme.Corner })
end

function UIKit.stroke(color: Color3?, thickness: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or Theme.StrokeThickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.padding(px: number?): UIPadding
	local p = UDim.new(0, px or Theme.Padding)
	return UIKit.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

function UIKit.list(direction: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return UIKit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})
end

-- Soft vertical shading: flat color, slightly lighter on top. Reads as "pressable".
function UIKit.shine(strength: number?): UIGradient
	local bottom = 1 - (strength or 0.12)
	return UIKit.new("UIGradient", {
		Name = "Shine",
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(bottom, bottom, bottom)),
	})
end

---------------------------------------------------------------------------
-- Finish: gradients, outlines, gloss, shine, shadows
---------------------------------------------------------------------------

-- Candy gradient for `color` on a white base. Calling it again recolors (disabled, selected...).
function UIKit.paint(gui: GuiObject, color: Color3)
	gui.BackgroundColor3 = Color3.new(1, 1, 1)
	gui:SetAttribute("PaintColor", color)
	local gradient = gui:FindFirstChild("Paint") :: UIGradient?
	if not gradient then
		local old = gui:FindFirstChild("Shine")
		if old then
			old:Destroy()
		end
		gradient = UIKit.new("UIGradient", { Name = "Paint", Rotation = 90, Parent = gui })
	end
	(gradient :: UIGradient).Color = Theme.gradient(color)
end

-- The thick dark outline around a shape.
function UIKit.outline(gui: GuiObject, thickness: number?, transparency: number?): UIStroke
	local edge = gui:FindFirstChild("Edge") :: UIStroke?
	if not edge then
		local created = UIKit.stroke(Theme.Style.Outline, thickness or Theme.Style.OutlineThickness)
		created.Name = "Edge"
		created.Parent = gui
		edge = created
	end
	local stroke = edge :: UIStroke
	stroke.Color = Theme.Style.Outline
	stroke.Thickness = thickness or Theme.Style.OutlineThickness
	stroke.Transparency = transparency or 0
	return stroke
end

-- Text properties the hole-filling layers copy from their label.
local TEXT_MIRROR = {
	"Text",
	"Font",
	"FontFace",
	"TextSize",
	"TextScaled",
	"TextWrapped",
	"TextTruncate",
	"TextXAlignment",
	"TextYAlignment",
	"RichText",
	"LineHeight",
	"TextTransparency",
	"MaxVisibleGraphemes",
}

-- Directions of the black copies that fill letter holes.
local FILL_OFFSETS = {
	Vector2.new(1, 0),
	Vector2.new(-1, 0),
	Vector2.new(0, 1),
	Vector2.new(0, -1),
	Vector2.new(0.7, 0.7),
	Vector2.new(-0.7, 0.7),
	Vector2.new(0.7, -0.7),
	Vector2.new(-0.7, -0.7),
}

--[[
	The stroke leaves a light dot in the middle of the holes in e, o, a, d, p, however thick
	it is. On top of the label (which keeps its own text, stroke, size and layout untouched)
	sit black copies nudged a little in each direction, whose solid letters cover those holes,
	and over them a copy in the label's colour that hides the black again everywhere except
	the holes and the outline. The copies follow the label's text, font, size and colour.
]]
local function fillLetterHoles(text: GuiObject, stroke: UIStroke)
	local label = text :: any
	local layers = UIKit.new("Frame", {
		Name = "TextFill",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = text,
	})
	local function copyLabel(name: string, zIndex: number): TextLabel
		return UIKit.new("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = zIndex,
			TextColor3 = Theme.Style.Outline,
			Parent = layers,
		})
	end
	local fills = {}
	for i in FILL_OFFSETS do
		fills[i] = copyLabel("Fill" .. i, 1)
	end
	local front = copyLabel("Front", 2)
	local all = table.clone(fills)
	table.insert(all, front)
	for _, property in TEXT_MIRROR do
		local function copy()
			for _, layer in all do
				(layer :: any)[property] = label[property]
			end
		end
		text:GetPropertyChangedSignal(property):Connect(copy)
		copy()
	end
	local function place()
		-- Inside the outline, so the copies never poke out past it.
		local distance = stroke.Thickness * 0.8
		for i, offset in FILL_OFFSETS do
			fills[i].Position = UDim2.fromOffset(offset.X * distance, offset.Y * distance)
		end
	end
	stroke:GetPropertyChangedSignal("Thickness"):Connect(place)
	place()
	local function sync()
		front.TextColor3 = label.TextColor3
		layers.Visible = stroke.Enabled
	end
	text:GetPropertyChangedSignal("TextColor3"):Connect(sync)
	stroke:GetPropertyChangedSignal("Enabled"):Connect(sync)
	sync()
end

-- Dark outline around text. Only shown when the text is light, so dark text stays clean,
-- unless `always` (bright coloured text, like the fair timers).
function UIKit.outlineText(text: GuiObject, thickness: number?, always: boolean?): UIStroke
	local existing = text:FindFirstChild("TextOutline") :: UIStroke?
	if existing then
		existing.Thickness = thickness or Theme.Style.TextOutline
		return existing
	end
	local stroke: UIStroke = UIKit.new("UIStroke", {
		Name = "TextOutline",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = Theme.Style.Outline,
		LineJoinMode = Enum.LineJoinMode.Round,
		Thickness = thickness or Theme.Style.TextOutline,
		Parent = text,
	})
	local function sync()
		stroke.Enabled = always == true or Theme.wantsOutline((text :: any).TextColor3)
	end
	text:GetPropertyChangedSignal("TextColor3"):Connect(sync)
	sync()
	fillLetterHoles(text, stroke)
	return stroke
end

-- Glossy highlight across the top half (fades out downward).
function UIKit.gloss(gui: GuiObject)
	if not Theme.Style.Gloss or gui:FindFirstChild("Gloss") then
		return
	end
	local corner = gui:FindFirstChildOfClass("UICorner")
	UIKit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = Theme.Style.GlossTransparency,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.new(1, -8, 0.42, 0),
		ZIndex = 2,
		Active = false,
		Parent = gui,
	}, {
		UIKit.corner(if corner then corner.CornerRadius else Theme.CornerSmall),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 0.85),
			}),
		}),
	})
end

-- A diagonal shine that sweeps across the element every few seconds while it exists.
function UIKit.sweep(gui: GuiObject)
	if gui:FindFirstChild("Sweep") then
		return
	end
	local style = Theme.Style
	local corner = gui:FindFirstChildOfClass("UICorner")
	local band: UIGradient = UIKit.new("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, style.ShineTransparency),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	local overlay: Frame = UIKit.new("Frame", {
		Name = "Sweep",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Active = false,
		Parent = gui,
	}, { band, UIKit.corner(if corner then corner.CornerRadius else Theme.CornerSmall) })
	local rng = Random.new()
	task.spawn(function()
		task.wait(rng:NextNumber(0.3, style.ShineEvery[1]))
		while overlay.Parent do
			if not Tweens.reducedMotion and gui.Visible then
				band.Offset = Vector2.new(-1, 0)
				Tweens.play(band, TweenInfo.new(style.ShineTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Offset = Vector2.new(1, 0),
				})
			end
			task.wait(style.ShineTime + rng:NextNumber(style.ShineEvery[1], style.ShineEvery[2]))
		end
	end)
end

--[[
	Soft drop shadow: a dark copy of the shape just below it. It is a sibling,
	so only use it for elements that are not inside a list layout (wrap them
	in a holder frame if they are).
]]
function UIKit.shadow(gui: GuiObject): Frame?
	local parent = gui.Parent
	if not parent then
		return nil
	end
	local style = Theme.Style
	local corner = gui:FindFirstChildOfClass("UICorner")
	return UIKit.new("Frame", {
		Name = gui.Name .. "Shadow",
		BackgroundColor3 = style.ShadowColor,
		BackgroundTransparency = style.ShadowTransparency,
		BorderSizePixel = 0,
		AnchorPoint = gui.AnchorPoint,
		Position = gui.Position + UDim2.fromOffset(0, style.ShadowOffset),
		Size = gui.Size,
		ZIndex = gui.ZIndex - 1,
		Parent = parent,
	}, { UIKit.corner(if corner then corner.CornerRadius else Theme.Corner) })
end

function UIKit.label(text: string, size: number?, props: Props?): TextLabel
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = text,
		TextSize = size or Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
	})
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	return label
end

-- Wrapped body text that fills the width of its parent.
function UIKit.paragraph(text: string, props: Props?): TextLabel
	local label = UIKit.label(text, Theme.TextSize.Body, {
		Font = Theme.FontBody,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	return label
end

function UIKit.card(props: Props?, children: { Instance }?): Frame
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Surface,
		BorderSizePixel = 0,
	}, children)
	UIKit.corner().Parent = frame
	local edge = UIKit.outline(frame, 2, Theme.Style.CardOutlineTransparency)
	edge.Color = Theme.Style.CardOutline
	UIKit.shine(0.08).Parent = frame
	for key, value in props or {} do
		(frame :: any)[key] = value
	end
	return frame
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

-- Shared gamepad selection ring (the engine clones it per selected button).
local selectionRing = UIKit.new("Frame", {
	Name = "SelectionRing",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 10, 1, 10),
	Position = UDim2.fromOffset(-5, -5),
}, {
	UIKit.corner(UDim.new(0, 14)),
	UIKit.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 4 }),
})

local function applyColors(button: TextButton, color: Color3, enabled: boolean)
	if ArtSlot.asset("ButtonFace") then
		return
	end
	UIKit.paint(button, if enabled then color else Theme.Colors.Disabled)
end

local function isEnabled(button: GuiButton): boolean
	return button:GetAttribute("Enabled") ~= false and button:GetAttribute("Busy") ~= true
end

-- A button with springy hover/press. `onClick` runs on activation.
function UIKit.button(text: string, onClick: () -> (), props: Props?): TextButton
	local color: Color3 = (props and props.BackgroundColor3) or Theme.Colors.Primary
	local button = UIKit.new("TextButton", {
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = Theme.Font,
		Text = text,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.textOn(color),
		-- The button's own text is hidden; a child label draws it above the gloss.
		TextTransparency = 1,
		Size = UDim2.fromOffset(120, Theme.Size.Touch),
		Selectable = true,
		SelectionImageObject = selectionRing,
	})
	UIKit.corner(Theme.CornerSmall).Parent = button
	UIKit.outline(button)
	button:SetAttribute("BaseColor", color)
	for key, value in props or {} do
		if key ~= "Parent" and key ~= "BackgroundColor3" then
			(button :: any)[key] = value
		end
	end
	if not (props and props.TextColor3) then
		button.TextColor3 = Theme.textOn(color)
	end
	if not ArtSlot.skin(button, "ButtonFace") then
		UIKit.paint(button, color)
		UIKit.gloss(button)
	end

	-- Text above the gloss, mirrored from the button so callers can keep setting button.Text.
	local label: TextLabel = UIKit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Active = false,
		TextWrapped = true,
		Parent = button,
	}, { UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
	local function mirror()
		label.Text = button.Text
		label.Font = button.Font
		label.TextSize = button.TextSize
		label.TextColor3 = button.TextColor3
	end
	mirror()
	for _, property in { "Text", "Font", "TextSize", "TextColor3" } do
		button:GetPropertyChangedSignal(property):Connect(mirror)
	end
	UIKit.outlineText(label)

	local scale = Tweens.getScale(button)
	local hovered = false
	local function rest()
		Tweens.play(scale, Tweens.Ease.Hover, { Scale = if hovered and isEnabled(button) then 1.05 else 1 })
	end
	button.MouseEnter:Connect(function()
		hovered = true
		rest()
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		rest()
	end)
	button.SelectionGained:Connect(function()
		hovered = true
		rest()
	end)
	button.SelectionLost:Connect(function()
		hovered = false
		rest()
	end)
	button.MouseButton1Down:Connect(function()
		if isEnabled(button) then
			Tweens.play(scale, Tweens.Ease.Press, { Scale = 0.92 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		if isEnabled(button) then
			scale.Scale = math.min(scale.Scale, 0.95)
			Tweens.play(scale, Tweens.Ease.Release, { Scale = if hovered then 1.05 else 1 })
		end
	end)
	button.Activated:Connect(function()
		UIKit.lastPress = { point = EssenceFX.screenPoint(button), at = os.clock() }
		if button:GetAttribute("Busy") then
			return
		end
		if button:GetAttribute("Enabled") == false then
			Tweens.shake(button)
			FeelController.play("Denied")
			local reason = button:GetAttribute("DisabledReason")
			if type(reason) == "string" and reason ~= "" and UIKit.onDisabledPress then
				UIKit.onDisabledPress(reason)
			end
			return
		end
		FeelController.play("ButtonPress")
		onClick()
	end)
	if props and props.Parent then
		button.Parent = props.Parent
	end
	return button
end

--[[
	Puts an icon in a darker square on the left of a button (reference UI kit
	look: [icon] Buy). The text shifts right to make room.
]]
function UIKit.withIcon(button: TextButton, iconName: string): TextButton
	local tile = button:FindFirstChild("IconTile") :: Frame?
	if tile then
		tile:Destroy()
	end
	local holder: Frame = UIKit.new("Frame", {
		Name = "IconTile",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
		Size = UDim2.new(1, 0, 1, -10),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.8,
		ZIndex = 3,
		Active = false,
		Parent = button,
	}, {
		UIKit.corner(UDim.new(0, 8)),
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }),
	})
	local icon = Icons.make(iconName)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.86, 0.86)
	icon.ZIndex = 4
	icon.Parent = holder
	local label = button:FindFirstChild("Label") :: TextLabel?
	local padding = label and label:FindFirstChildOfClass("UIPadding")
	if padding then
		local height = if button.Size.Y.Offset > 0 then button.Size.Y.Offset
			elseif button.AbsoluteSize.Y > 0 then button.AbsoluteSize.Y
			else 40
		padding.PaddingLeft = UDim.new(0, math.floor(height * 0.9) + 2)
	end
	return button
end

--[[
	The reference UI kit button: a saturated colour with a top-to-bottom
	gradient, a darker outline in the same hue, a darker "lip" under it (3D
	look), an icon in a darker square on the left and bold white outlined text.
	Returns the holder (put this in layouts) and the button.
]]
function UIKit.actionButton(text: string, iconName: string?, color: Color3, onClick: () -> (), size: Vector2?): (Frame, TextButton)
	local s = size or Theme.Size.ActionButton
	local holder: Frame = UIKit.new("Frame", {
		Name = text,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(s.X, s.Y + 5),
	})
	UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = Theme.darken(color, 0.42),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.fromOffset(s.X, s.Y),
		ZIndex = 1,
		Parent = holder,
	}, {
		UIKit.corner(UDim.new(0, 12)),
		UIKit.stroke(Theme.darken(color, 0.6), Theme.Style.OutlineThickness),
	})
	local button = UIKit.button(text, onClick, {
		Name = "Button",
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(s.X, s.Y),
		TextSize = Theme.TextSize.Large - 2,
		ZIndex = 2,
		Parent = holder,
	})
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 12)
	end
	local edge = button:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Color = Theme.darken(color, 0.6)
	end
	if iconName then
		UIKit.withIcon(button, iconName)
	end
	button:SetAttribute("ActionColor", color)
	return holder, button
end

-- Resizes a holder made by UIKit.actionButton (phones use a smaller size).
function UIKit.setActionSize(holder: Frame, size: Vector2, textSize: number?)
	holder.Size = UDim2.fromOffset(size.X, size.Y + 5)
	local lip = holder:FindFirstChild("Lip") :: Frame?
	if lip then
		lip.Size = UDim2.fromOffset(size.X, size.Y)
	end
	local button = holder:FindFirstChild("Button") :: TextButton?
	if button then
		button.Size = UDim2.fromOffset(size.X, size.Y)
		if textSize then
			button.TextSize = textSize
		end
		local label = button:FindFirstChild("Label") :: TextLabel?
		local padding = label and label:FindFirstChildOfClass("UIPadding")
		if padding and button:FindFirstChild("IconTile") then
			padding.PaddingLeft = UDim.new(0, math.floor(size.Y * 0.9) + 2)
		end
	end
end

--[[
	Greys a button out (or back in). Disabled buttons still react to a tap
	with a shake and, if given, a reason toast ("Reach level 3 first!").
]]
function UIKit.setEnabled(button: TextButton, enabled: boolean, color: Color3?, reason: string?)
	local base: Color3 = color or (button:GetAttribute("BaseColor") :: Color3?) or Theme.Colors.Primary
	button:SetAttribute("BaseColor", base)
	button:SetAttribute("Enabled", enabled)
	button:SetAttribute("DisabledReason", if enabled then nil else reason)
	button.AutoButtonColor = false
	applyColors(button, base, enabled)
	button.TextColor3 = if enabled then Theme.textOn(base) else Theme.Colors.DisabledText
end

-- Busy: dims the button and ignores taps while a server request is in flight.
function UIKit.setBusy(button: TextButton, busy: boolean)
	button:SetAttribute("Busy", busy)
	Tweens.play(button, Tweens.Ease.Fade, { BackgroundTransparency = if busy then 0.35 else 0 })
	local label = button:FindFirstChild("Label")
	if label then
		Tweens.play(label, Tweens.Ease.Fade, { TextTransparency = if busy then 0.4 else 0 })
	end
end

-- A button with the shine sweep. Use for the few buttons that matter most.
function UIKit.keyButton(text: string, onClick: () -> (), props: Props?): TextButton
	local button = UIKit.button(text, onClick, props)
	UIKit.sweep(button)
	return button
end

--[[
	A button that sends one server action. Busy while waiting, a happy pop
	when it worked, a shake when the server said no (the Denied toast explains why).
]]
function UIKit.requestButton(text: string, action: string, payload: { [string]: any }?, props: Props?): TextButton
	local button: TextButton
	button = UIKit.button(text, function()
		UIKit.setBusy(button, true)
		task.spawn(function()
			local result = NetClient.request(action, payload)
			if not button.Parent then
				return
			end
			UIKit.setBusy(button, false)
			if result.ok then
				Tweens.pop(button, 0.12)
				Tweens.flash(button, Theme.Style.Flash, 0.25, 0.3)
			else
				-- The server's Denied feedback already shows a toast saying why.
				Tweens.shake(button)
			end
		end)
	end, props)
	return button
end

-- A small round notification badge in the top-right corner of `parent`.
function UIKit.badge(parent: GuiObject, color: Color3?): Frame
	local badge = UIKit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		-- Width grows with the text from 0 (the size constraint keeps it at least a 24px circle);
		-- a 24px base width here would be added to the text and make "!" a wide pill.
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color or Theme.Colors.Danger,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	}, {
		UIKit.corner(Theme.CornerRound),
		UIKit.stroke(Theme.Style.Outline, 2.5),
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
		UIKit.new("UISizeConstraint", { MinSize = Vector2.new(24, 24) }),
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	UIKit.label("", Theme.TextSize.Small, {
		Name = "Count",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextColor3 = Theme.Colors.TextOnPrimary,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
		Parent = badge,
	})
	UIKit.paint(badge, color or Theme.Colors.Danger)
	UIKit.outlineText(badge:FindFirstChild("Count") :: TextLabel, 2)
	return badge
end

-- Hotbar slot corners: the keybind top left, the quantity bottom right (a bit smaller).
function UIKit.slotKey(slot: GuiObject, text: string): TextLabel
	local key = UIKit.label(text, Theme.TextSize.Small + 2, {
		Name = "Key",
		Position = UDim2.fromOffset(5, 2),
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 5,
		Parent = slot,
	})
	UIKit.outlineText(key, 2, true)
	return key
end

function UIKit.slotCount(slot: GuiObject): TextLabel
	local count = UIKit.label("", Theme.TextSize.Small - 2, {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -5, 1, -3),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 5,
		Visible = false,
		Parent = slot,
	})
	UIKit.outlineText(count, 2, true)
	return count
end

-- value: a number (0 hides), true for a "!" dot, false/nil hides. Pops on change.
function UIKit.setBadge(badge: Frame, value: number | boolean | nil)
	local text = if value == true
		then "!"
		elseif type(value) == "number" and value > 0 then (if value > 99 then "99+" else tostring(value))
		else nil
	local label = badge:FindFirstChild("Count") :: TextLabel
	local scale = Tweens.getScale(badge)
	if text then
		local changed = not badge.Visible or label.Text ~= text
		label.Text = text
		if changed then
			if not badge.Visible then
				scale.Scale = 0
			end
			badge.Visible = true
			Tweens.pop(badge, 0.25)
		end
	elseif badge.Visible then
		local tween = Tweens.play(scale, Tweens.Ease.Fade, { Scale = 0 })
		if tween then
			tween.Completed:Once(function()
				if scale.Scale < 0.05 then
					badge.Visible = false
				end
			end)
		else
			badge.Visible = false
		end
	end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

-- `color` and `icon` (Icons name) give a tab the reference look: its own colour and an icon.
export type TabItem = { id: string, text: string, color: Color3?, icon: string? }
export type Tabs = { frame: Frame, select: (id: string, animate: boolean?) -> () }

--[[
	A segmented control. The highlight slides between tabs instead of
	jumping. Persistent: build it once and call tabs.select(id) to sync.
]]
function UIKit.tabs(
	parent: GuiObject,
	items: { TabItem },
	selected: string,
	onSelect: (id: string) -> (),
	color: Color3?
): Tabs
	local frame = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = Theme.darken(Theme.Colors.SurfaceAlt, 0.06),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = parent,
	}, { UIKit.corner(Theme.CornerRound) })
	UIKit.outline(frame, 3)
	local highlight = UIKit.new("Frame", {
		Name = "Highlight",
		BorderSizePixel = 0,
		Size = UDim2.new(1 / #items, -8, 1, -8),
		Position = UDim2.new(0, 4, 0, 4),
		Parent = frame,
	}, { UIKit.corner(Theme.CornerRound) })
	UIKit.paint(highlight, color or Theme.Colors.Primary)
	UIKit.outline(highlight, 2.5)
	UIKit.gloss(highlight)

	local buttons: { [string]: TextButton } = {}
	local current = ""
	local function select(id: string, animate: boolean?)
		local index = 1
		for i, item in items do
			if item.id == id then
				index = i
			end
		end
		current = id
		UIKit.paint(highlight, items[index].color or color or Theme.Colors.Primary)
		local goal = UDim2.new((index - 1) / #items, 4, 0, 4)
		if animate == false then
			highlight.Position = goal
		else
			Tweens.play(highlight, Tweens.Ease.Slide, { Position = goal })
		end
		for itemId, b in buttons do
			b.TextColor3 = if itemId == id then Theme.Colors.TextOnPrimary else Theme.Colors.TextMuted
		end
	end

	for i, item in items do
		local b = UIKit.new("TextButton", {
			Name = item.id,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = Theme.Font,
			Text = item.text,
			TextSize = Theme.TextSize.Body,
			TextColor3 = Theme.Colors.TextMuted,
			Size = UDim2.new(1 / #items, 0, 1, 0),
			Position = UDim2.fromScale((i - 1) / #items, 0),
			ZIndex = 3,
			Selectable = true,
			SelectionImageObject = selectionRing,
			Parent = frame,
		})
		UIKit.outlineText(b, 2)
		if item.icon then
			local icon = Icons.make(item.icon)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 10, 0.5, 0)
			icon.Size = UDim2.fromOffset(28, 28)
			icon.ZIndex = 4
			icon.Parent = b
			UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 30) }).Parent = b
		end
		b.Activated:Connect(function()
			if current == item.id then
				return
			end
			FeelController.play("ButtonPress")
			select(item.id)
			Tweens.pop(b, 0.08)
			onSelect(item.id)
		end)
		buttons[item.id] = b
	end
	select(selected, false)
	return { frame = frame, select = select }
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

export type PanelOptions = {
	accent: Color3?,
	artSlot: string?,
	glyph: string?,
}

--[[
	A centered modal panel (CanvasGroup so it fades as one) with a colored
	header, an art slot for the panel icon, a round close button and a
	scrolling body. Sizes are design pixels (see UI/Scale).
	The header has a "TabSlot" frame; UIKit.panelTabs fills it.
]]
function UIKit.panel(
	title: string,
	size: UDim2,
	onClose: () -> (),
	options: PanelOptions?
): (CanvasGroup, ScrollingFrame)
	local opts = options or {}
	local accent = opts.accent or Theme.Colors.Primary
	local panel = UIKit.new("CanvasGroup", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Visible = false,
	})
	panel:SetAttribute("Accent", accent)
	UIKit.corner(UDim.new(0, 22)).Parent = panel
	if not ArtSlot.skin(panel, "PanelFrame") then
		UIKit.outline(panel, Theme.Style.PanelOutlineThickness)
		-- Dark navy body with a faint tint of the panel's colour (reference UI kit).
		-- The gradient sits on a child frame: a UIGradient on a CanvasGroup would
		-- tint everything inside the panel.
		panel.BackgroundColor3 = Theme.Colors.Background
		UIKit.new("Frame", {
			Name = "Fill",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			Parent = panel,
		}, {
			UIKit.corner(UDim.new(0, 22)),
			UIKit.new("UIGradient", {
				Name = "Paint",
				Rotation = 90,
				Color = ColorSequence.new(
					Theme.Colors.Background:Lerp(accent, 0.08),
					Theme.darken(Theme.Colors.Background, 0.18)
				),
			}),
		})
	end
	UIKit.new("UISizeConstraint", { MaxSize = Theme.Size.PanelMax }).Parent = panel

	local header = UIKit.new("Frame", {
		Name = "Header",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = panel,
	})
	UIKit.paint(header, accent)
	UIKit.gloss(header)
	-- Dark line under the header, as if the outline runs across the panel.
	UIKit.new("Frame", {
		Name = "HeaderLine",
		BackgroundColor3 = Theme.Style.Outline,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 3),
		ZIndex = 3,
		Parent = header,
	})
	ArtSlot.icon(opts.artSlot or ("PanelIcon_" .. title), {
		size = 44,
		color = Theme.lighten(accent, 0.35),
		glyph = opts.glyph or string.sub(title, 1, 1),
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, 14, 0.5, 0),
		zIndex = 3,
	}).Parent =
		header
	local titleLabel = UIKit.label(title, Theme.TextSize.Title, {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 68, 0.5, 0),
		TextColor3 = Theme.Colors.TextOnPrimary,
		ZIndex = 3,
		Parent = header,
	})
	UIKit.outlineText(titleLabel, Theme.Style.TitleOutline)
	-- Red Close button with the X icon (reference UI kit).
	local close = UIKit.button("", onClose, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = Theme.Colors.Danger,
		ZIndex = 3,
		Parent = header,
	})
	local closeCorner = close:FindFirstChildOfClass("UICorner")
	if closeCorner then
		closeCorner.CornerRadius = UDim.new(0, 12)
	end
	local closeEdge = close:FindFirstChild("Edge") :: UIStroke?
	if closeEdge then
		closeEdge.Color = Theme.darken(Theme.Colors.Danger, 0.6)
	end
	local closeIcon = Icons.make("Close")
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.Size = UDim2.fromScale(0.72, 0.72)
	closeIcon.ZIndex = 4
	closeIcon.Parent = close

	-- Optional persistent tab bar between header and body.
	UIKit.new("Frame", {
		Name = "TabSlot",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 74),
		Size = UDim2.new(1, -28, 0, 0),
		Visible = false,
		Parent = panel,
	})

	local body = UIKit.new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(12, 76),
		Size = UDim2.new(1, -24, 1, -88),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.TextMuted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
	})
	UIKit.list(Enum.FillDirection.Vertical, 8).Parent = body
	UIKit.new(
		"UIPadding",
		{ PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8) }
	).Parent =
		body
	body.Parent = panel
	return panel, body
end

-- Adds a persistent tab bar to a panel built by UIKit.panel.
function UIKit.panelTabs(panel: CanvasGroup, items: { TabItem }, selected: string, onSelect: (id: string) -> ()): Tabs
	local slot = panel:FindFirstChild("TabSlot") :: Frame
	local body = panel:FindFirstChild("Body") :: ScrollingFrame
	slot.Visible = true
	slot.Size = UDim2.new(1, -28, 0, 44)
	body.Position = UDim2.fromOffset(12, 128)
	body.Size = UDim2.new(1, -24, 1, -140)
	local accent = panel:GetAttribute("Accent")
	return UIKit.tabs(slot, items, selected, onSelect, if typeof(accent) == "Color3" then accent else nil)
end

-- A horizontal row card: optional icon, left text, right buttons.
function UIKit.row(leftText: string, subText: string?, buttons: { TextButton }, icon: GuiObject?): Frame
	local row = UIKit.card({
		Size = UDim2.new(1, -8, 0, Theme.Size.RowHeight),
		BackgroundColor3 = Theme.Colors.Surface,
	})
	local textLeft = 14
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)
		icon.Size = UDim2.fromOffset(44, 44)
		icon.Parent = row
		textLeft = 66
	end
	local buttonWidth = #buttons * (Theme.Size.RowButton.X + 8)
	local textHolder = UIKit.new("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, textLeft, 0.5, 0),
		Size = UDim2.new(1, -(textLeft + buttonWidth + 16), 1, -12),
		ClipsDescendants = true,
	})
	local layout = UIKit.list(Enum.FillDirection.Vertical, 2)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = textHolder
	UIKit.label(leftText, Theme.TextSize.Body, { Name = "Title", LayoutOrder = 1 }).Parent = textHolder
	if subText then
		UIKit.label(subText, Theme.TextSize.Small, {
			Name = "Sub",
			LayoutOrder = 2,
			TextColor3 = Theme.Colors.TextMuted,
			Font = Theme.FontBody,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
		}).Parent =
			textHolder
	end
	textHolder.Parent = row

	local buttonHolder = UIKit.new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, buttonWidth, 1, -12),
	})
	local buttonLayout = UIKit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right)
	buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	buttonLayout.Parent = buttonHolder
	for i, b in buttons do
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(Theme.Size.RowButton.X, Theme.Size.RowButton.Y)
		b.Parent = buttonHolder
	end
	buttonHolder.Parent = row
	return row
end

-- A wrapping grid of equal cells (item cards) inside a panel body.
function UIKit.grid(order: number, parent: Instance, cell: Vector2?): Frame
	local size = cell or Theme.Size.ItemCard
	return UIKit.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		UIKit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(size.X, size.Y),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6) }),
	})
end

export type ItemCardOptions = {
	name: string,
	icon: GuiObject,
	sub: string?,
	button: TextButton?,
	count: number?,
	locked: boolean?,
	order: number?,
}

--[[
	An item card for grids: big icon, name, a short line (price, owned...)
	and an optional action button along the bottom. `count` shows a quantity
	badge ("x3") in the corner.
]]
function UIKit.itemCard(opts: ItemCardOptions): Frame
	local card = UIKit.card({
		Name = opts.name,
		LayoutOrder = opts.order or 0,
		BackgroundColor3 = if opts.locked then Theme.Colors.SurfaceAlt else Theme.Colors.Surface,
	})
	local iconHolder = UIKit.new("Frame", {
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(1, -16, 0, 74),
		BackgroundColor3 = Theme.Colors.SurfaceAlt,
		BorderSizePixel = 0,
		Parent = card,
	}, { UIKit.corner(Theme.CornerSmall) })
	local icon = opts.icon
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(60, 60)
	icon.Parent = iconHolder
	if opts.locked then
		iconHolder.BackgroundTransparency = 0.3
	end
	if opts.count then
		local count = UIKit.label("x" .. tostring(opts.count), Theme.TextSize.Small + 2, {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -6, 1, -4),
			TextColor3 = Theme.Colors.TextOnPrimary,
			ZIndex = 3,
			Parent = iconHolder,
		})
		UIKit.outlineText(count, 2)
	end
	UIKit.label(opts.name, Theme.TextSize.Body, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 86),
		Size = UDim2.new(1, -12, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	if opts.sub then
		UIKit.label(opts.sub, Theme.TextSize.Small, {
			Name = "Sub",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 108),
			Size = UDim2.new(1, -12, 0, 18),
			AutomaticSize = Enum.AutomaticSize.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Theme.FontBody,
			TextColor3 = Theme.Colors.TextMuted,
			Parent = card,
		})
	end
	if opts.button then
		local button = opts.button
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.new(0.5, 0, 1, -8)
		button.Size = UDim2.new(1, -16, 0, 40)
		button.Parent = card
	end
	return card
end

-- Section heading inside a panel body.
function UIKit.section(text: string, order: number, parent: Instance): TextLabel
	local label = UIKit.label(text, Theme.TextSize.Large, { LayoutOrder = order, Name = "Section" })
	label.Parent = parent
	return label
end

-- A "how it works" card: a heading and numbered steps, each in a coloured circle.
function UIKit.steps(title: string, steps: { string }, order: number, parent: Instance, color: Color3?): Frame
	local accent = color or Theme.Colors.Gold
	local card = UIKit.card({
		Name = "Guide",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		BackgroundColor3 = Theme.Colors.SurfaceAlt,
		Parent = parent,
	}, {
		UIKit.padding(12),
		UIKit.list(Enum.FillDirection.Vertical, 8),
	})
	UIKit.label(title, Theme.TextSize.Large, { LayoutOrder = 0, TextColor3 = accent }).Parent = card
	for i, text in steps do
		local row = UIKit.new("Frame", {
			Name = "Step" .. i,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		})
		local circle = UIKit.new("Frame", {
			Name = "Number",
			BackgroundColor3 = accent,
			Size = UDim2.fromOffset(30, 30),
			Parent = row,
		}, { UIKit.corner(Theme.CornerRound) })
		UIKit.outline(circle, 2)
		local number = UIKit.label(tostring(i), Theme.TextSize.Body, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextColor3 = Theme.Colors.TextOnPrimary,
			Parent = circle,
		})
		UIKit.outlineText(number, 2, true)
		UIKit.label(text, Theme.TextSize.Body, {
			Font = Theme.FontBody,
			TextWrapped = true,
			Position = UDim2.fromOffset(42, 4),
			Size = UDim2.new(1, -42, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = row,
		})
	end
	return card
end

-- True on the frame the last input came from a gamepad (for showing selection).
function UIKit.usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

return UIKit
