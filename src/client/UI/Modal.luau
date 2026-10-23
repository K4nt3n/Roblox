--!strict
--[[
	Modal: one centered card at a time, queued, with a soft backdrop.
	Used for the fair picker, replay cards, co-grow invites and naming.

	    Modal.show({
	        title = "Fair Day results",
	        lines = { "Pumpkin · 54.2 kg", "Blue ribbon · Best Pumpkin" },
	        buttons = { { text = "Yay!", color = Theme.Colors.Primary, onClick = function() end } },
	        build = function(body) ... end, -- optional extra content
	    })
]]

local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Scale = require(script.Parent.Scale)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local FeelController = require(script.Parent.Parent.Feel.FeelController)

local Modal = {}

export type Button = { text: string, color: Color3?, textColor: Color3?, onClick: (() -> ())?, keepOpen: boolean? }
export type Spec = {
	title: string,
	lines: { string }?,
	buttons: { Button }?,
	build: ((body: Frame, close: () -> ()) -> ())?,
	accent: Color3?,
}

local root: Frame? = nil
local queue: { Spec } = {}
local showing = false

local function getRoot(parent: Instance): Frame
	if root and root.Parent and root.Parent.Parent then
		return root
	end
	local screenGui = UIKit.new("ScreenGui", {
		Name = "GVF_Modal",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layer.Modal,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})
	root = Scale.root(screenGui, "Modal")
	return root :: Frame
end

Modal.parent = nil :: Instance?

local function showNext()
	if showing or #queue == 0 or not Modal.parent then
		return
	end
	showing = true
	local spec = table.remove(queue, 1) :: Spec
	local accent = spec.accent or Theme.Colors.Primary
	local gui = getRoot(Modal.parent :: Instance)

	local backdrop = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})
	Tweens.play(backdrop, Tweens.Ease.Fade, { BackgroundTransparency = 0.55 })

	local card = UIKit.new("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.Size.ModalWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		-- Flat colour: a UIGradient on a CanvasGroup would tint everything inside it.
		BackgroundColor3 = Theme.Colors.Background:Lerp(accent, 0.08),
		BorderSizePixel = 0,
		Parent = backdrop,
	}, {
		UIKit.corner(UDim.new(0, 22)),
		UIKit.padding(18),
		UIKit.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center),
	})
	UIKit.outline(card, Theme.Style.PanelOutlineThickness)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(card) then
			GuiService.SelectedObject = nil
		end
		Tweens.play(backdrop, Tweens.Ease.Fade, { BackgroundTransparency = 1 })
		local tween = Tweens.play(Tweens.getScale(card), Tweens.Ease.Fade, { Scale = 0.85 })
		Tweens.play(card, Tweens.Ease.Fade, { GroupTransparency = 1 })
		task.delay(if tween then 0.22 else 0, function()
			backdrop:Destroy()
			showing = false
			showNext()
		end)
	end

	local title = UIKit.label(spec.title, Theme.TextSize.Title, {
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextColor3 = Theme.Colors.TextOnPrimary,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	})
	UIKit.outlineText(title, Theme.Style.TitleOutline)
	title.Parent = card

	for i, line in spec.lines or {} do
		UIKit.label(line, Theme.TextSize.Body, {
			LayoutOrder = 1 + i,
			Font = Theme.FontBody,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
		}).Parent = card
	end

	if spec.build then
		local holder = UIKit.new("Frame", {
			LayoutOrder = 50,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		}, { UIKit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })
		spec.build(holder, close)
	end

	local row = UIKit.new("Frame", {
		LayoutOrder = 100,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = card,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	local buttons = spec.buttons or { { text = "OK" } }
	local first: TextButton? = nil
	for i, b in buttons do
		local button = UIKit.button(b.text, function()
			if b.onClick then
				b.onClick()
			end
			if not b.keepOpen then
				close()
			end
		end, {
			LayoutOrder = i,
			Size = UDim2.fromOffset(150, 44),
			BackgroundColor3 = b.color or Theme.Colors.Primary,
			TextColor3 = b.textColor,
		})
		button.Parent = row
		if not first then
			-- The main choice shines.
			UIKit.sweep(button)
			first = button
		end
	end

	if first and UIKit.usingGamepad() then
		GuiService.SelectedObject = first
	end
	Tweens.openPanel(card)
	if spec.accent then
		-- Accent modals are moments (results, invites): bounce once more.
		task.delay(0.28, function()
			Tweens.pop(card, 0.06)
		end)
	end
	FeelController.play("PanelOpen")
end

function Modal.show(spec: Spec)
	table.insert(queue, spec)
	showNext()
end

return Modal
