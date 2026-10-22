--!strict
--[[
	UIKit: tiny builders for consistent placeholder UI. Every interactive
	element gets hover/press motion and a ButtonPress feel event for free.
	When final UI art arrives, re-skin here (images, 9-slice) and every
	screen updates.
]]

local Theme = require(script.Parent.Theme)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local FeelController = require(script.Parent.Parent.Feel.FeelController)

local UIKit = {}

type Props = { [string]: any }

function UIKit.new(className: string, props: Props?, children: { Instance }?): any
	local inst = Instance.new(className)
	for key, value in props or {} do
		(inst :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = inst
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

function UIKit.card(props: Props?, children: { Instance }?): Frame
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Surface,
		BorderSizePixel = 0,
	}, children)
	UIKit.corner().Parent = frame
	UIKit.stroke().Parent = frame
	for key, value in props or {} do
		(frame :: any)[key] = value
	end
	return frame
end

-- A button with springy hover/press. `onClick` runs on activation.
function UIKit.button(text: string, onClick: () -> (), props: Props?): TextButton
	local color = (props and props.BackgroundColor3) or Theme.Colors.Primary
	local button = UIKit.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = Theme.Font,
		Text = text,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.TextOnPrimary,
		Size = UDim2.fromOffset(120, 40),
	})
	UIKit.corner(Theme.CornerSmall).Parent = button
	UIKit.stroke(nil, 2).Parent = button
	for key, value in props or {} do
		(button :: any)[key] = value
	end
	local scale = Tweens.getScale(button)
	button.MouseEnter:Connect(function()
		Tweens.play(scale, Tweens.Ease.Quick, { Scale = 1.05 })
	end)
	button.MouseLeave:Connect(function()
		Tweens.play(scale, Tweens.Ease.Quick, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		Tweens.play(scale, Tweens.Ease.Quick, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(function()
		Tweens.play(scale, Tweens.Ease.Pop, { Scale = 1.05 })
	end)
	button.Activated:Connect(function()
		FeelController.play("ButtonPress")
		onClick()
	end)
	return button
end

function UIKit.setEnabled(button: TextButton, enabled: boolean, color: Color3?)
	button.Active = enabled
	button.AutoButtonColor = false
	button.BackgroundColor3 = if enabled then (color or Theme.Colors.Primary) else Theme.Colors.Disabled
end

-- A centered modal panel (CanvasGroup so it can fade as one) with title and close button.
function UIKit.panel(title: string, size: UDim2, onClose: () -> ()): (CanvasGroup, ScrollingFrame)
	local panel = UIKit.new("CanvasGroup", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Theme.Colors.Background,
		BorderSizePixel = 0,
		Visible = false,
	})
	UIKit.corner().Parent = panel
	UIKit.stroke(nil, 3).Parent = panel
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(640, 520) }).Parent = panel

	UIKit.label(title, Theme.TextSize.Title, {
		Position = UDim2.fromOffset(18, 12),
	}).Parent = panel

	UIKit.button("X", onClose, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Theme.Colors.Danger,
	}).Parent = panel

	local body = UIKit.new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 1, -72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	UIKit.list(Enum.FillDirection.Vertical, 8).Parent = body
	body.Parent = panel
	return panel, body
end

-- A horizontal row card: left text, right buttons.
function UIKit.row(leftText: string, subText: string?, buttons: { TextButton }): Frame
	local row = UIKit.card({
		Size = UDim2.new(1, -8, 0, 64),
		BackgroundColor3 = Theme.Colors.Surface,
	})
	local textHolder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -260, 1, 0),
	})
	UIKit.list(Enum.FillDirection.Vertical, 2).Parent = textHolder
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 10) }).Parent = textHolder
	UIKit.label(leftText, Theme.TextSize.Body).Parent = textHolder
	if subText then
		UIKit.label(subText, Theme.TextSize.Small, { TextColor3 = Theme.Colors.TextMuted, Font = Theme.FontBody }).Parent =
			textHolder
	end
	textHolder.Parent = row

	local buttonHolder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 250, 1, -16),
	})
	local layout = UIKit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = buttonHolder
	for i, b in buttons do
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(110, 40)
		b.Parent = buttonHolder
	end
	buttonHolder.Parent = row
	return row
end

return UIKit
