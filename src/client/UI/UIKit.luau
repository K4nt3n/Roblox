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
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local ArtSlot = require(script.Parent.ArtSlot)
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
	UIKit.stroke(Theme.Colors.SurfaceAlt, 2).Parent = frame
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
	UIKit.new("UIStroke", { Color = Theme.Colors.Gold, Thickness = 4 }),
})

local function applyColors(button: TextButton, color: Color3, enabled: boolean)
	local stroke = button:FindFirstChild("Edge") :: UIStroke?
	if enabled then
		button.BackgroundColor3 = color
		if stroke then
			stroke.Color = Theme.darken(color, 0.28)
		end
	else
		button.BackgroundColor3 = Theme.Colors.Disabled
		if stroke then
			stroke.Color = Theme.darken(Theme.Colors.Disabled, 0.18)
		end
	end
end

local function isEnabled(button: GuiButton): boolean
	return button:GetAttribute("Enabled") ~= false and button:GetAttribute("Busy") ~= true
end

-- A button with springy hover/press. `onClick` runs on activation.
function UIKit.button(text: string, onClick: () -> (), props: Props?): TextButton
	local color: Color3 = (props and props.BackgroundColor3) or Theme.Colors.Primary
	local button = UIKit.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = Theme.Font,
		Text = text,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.textOn(color),
		Size = UDim2.fromOffset(120, Theme.Size.Touch),
		Selectable = true,
		SelectionImageObject = selectionRing,
	})
	UIKit.corner(Theme.CornerSmall).Parent = button
	local edge = UIKit.stroke(Theme.darken(color, 0.28), 2)
	edge.Name = "Edge"
	edge.Parent = button
	UIKit.shine().Parent = button
	button:SetAttribute("BaseColor", color)
	for key, value in props or {} do
		if key ~= "Parent" then
			(button :: any)[key] = value
		end
	end
	if props and props.TextColor3 == nil then
		button.TextColor3 = Theme.textOn(button.BackgroundColor3)
	end
	ArtSlot.skin(button, "ButtonFace")

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
	Tweens.play(button, Tweens.Ease.Fade, { TextTransparency = if busy then 0.4 else 0 })
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
		Size = UDim2.fromOffset(24, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color or Theme.Colors.Danger,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	}, {
		UIKit.corner(Theme.CornerRound),
		UIKit.stroke(Color3.new(1, 1, 1), 2),
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
		UIKit.new("UISizeConstraint", { MinSize = Vector2.new(24, 24) }),
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
	return badge
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

export type TabItem = { id: string, text: string }
export type Tabs = { frame: Frame, select: (id: string, animate: boolean?) -> () }

--[[
	A segmented control. The highlight slides between tabs instead of
	jumping. Persistent: build it once and call tabs.select(id) to sync.
]]
function UIKit.tabs(parent: GuiObject, items: { TabItem }, selected: string, onSelect: (id: string) -> ()): Tabs
	local frame = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = Theme.Colors.SurfaceAlt,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = parent,
	}, { UIKit.corner(Theme.CornerRound) })
	local highlight = UIKit.new("Frame", {
		Name = "Highlight",
		BackgroundColor3 = Theme.Colors.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1 / #items, -8, 1, -8),
		Position = UDim2.new(0, 4, 0, 4),
		Parent = frame,
	}, { UIKit.corner(Theme.CornerRound), UIKit.stroke(Theme.Colors.Disabled, 2) })

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
		local goal = UDim2.new((index - 1) / #items, 4, 0, 4)
		if animate == false then
			highlight.Position = goal
		else
			Tweens.play(highlight, Tweens.Ease.Slide, { Position = goal })
		end
		for itemId, b in buttons do
			b.TextColor3 = if itemId == id then Theme.Colors.Text else Theme.Colors.TextMuted
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
			ZIndex = 2,
			Selectable = true,
			SelectionImageObject = selectionRing,
			Parent = frame,
		})
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
		BackgroundColor3 = Theme.Colors.Background,
		BorderSizePixel = 0,
		Visible = false,
	})
	UIKit.corner(UDim.new(0, 20)).Parent = panel
	if not ArtSlot.skin(panel, "PanelFrame") then
		UIKit.stroke(Theme.darken(accent, 0.25), 3).Parent = panel
	end
	UIKit.new("UISizeConstraint", { MaxSize = Theme.Size.PanelMax }).Parent = panel

	local header = UIKit.new("Frame", {
		Name = "Header",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = panel,
	}, { UIKit.shine(0.1) })
	ArtSlot.icon(opts.artSlot or ("PanelIcon_" .. title), {
		size = 44,
		color = Theme.lighten(accent, 0.35),
		glyph = opts.glyph or string.sub(title, 1, 1),
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, 14, 0.5, 0),
	}).Parent =
		header
	UIKit.label(title, Theme.TextSize.Title, {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 68, 0.5, 0),
		TextColor3 = Theme.textOn(accent),
		Parent = header,
	})
	local close = UIKit.button("X", onClose, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Theme.Colors.Danger,
		Parent = header,
	})
	local closeCorner = close:FindFirstChildOfClass("UICorner")
	if closeCorner then
		closeCorner.CornerRadius = Theme.CornerRound
	end

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
	return UIKit.tabs(slot, items, selected, onSelect)
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

-- Section heading inside a panel body.
function UIKit.section(text: string, order: number, parent: Instance): TextLabel
	local label = UIKit.label(text, Theme.TextSize.Large, { LayoutOrder = order, Name = "Section" })
	label.Parent = parent
	return label
end

-- True on the frame the last input came from a gamepad (for showing selection).
function UIKit.usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

return UIKit
