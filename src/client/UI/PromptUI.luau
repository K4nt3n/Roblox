--!strict
--[[
	PromptUI: the game's own look for every ProximityPrompt (plants, plots,
	NPCs, stalls). Prompts are switched to Style = Custom on this client only,
	so the server scripts and their Triggered handlers are untouched.

	  [ E ]  Plant
	         Carrot

	The key cap shows the keyboard key, the gamepad button, or a tap hand on
	touch screens. Tapping / clicking the prompt also triggers it, so it works
	on phones. Prompts on the same part stack upwards instead of overlapping.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Icons = require(script.Parent.Icons)
local Scale = require(script.Parent.Scale)
local Tweens = require(script.Parent.Parent.Feel.Tweens)

local PromptUI = {}

type Shown = { gui: BillboardGui, fill: Frame, connections: { RBXScriptConnection } }

local shown: { [ProximityPrompt]: Shown } = {}
-- BillboardGuis only draw as direct children of PlayerGui (not inside a Folder).
local container: Instance

local SIZE = Vector2.new(230, 58)

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	local key = prompt.KeyboardKeyCode
	local text = UserInputService:GetStringForKeyCode(key)
	return if text ~= "" then string.upper(text) else key.Name
end

-- How many shown prompts sit on the same part (for stacking).
local function stackIndex(prompt: ProximityPrompt): number
	local index = 0
	for other in shown do
		if other ~= prompt and other.Parent == prompt.Parent then
			index += 1
		end
	end
	return index
end

local function hide(prompt: ProximityPrompt)
	local entry = shown[prompt]
	if not entry then
		return
	end
	shown[prompt] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.gui:Destroy()
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	hide(prompt)
	local adornee = prompt.Parent
	if not adornee or not (adornee:IsA("BasePart") or adornee:IsA("Attachment") or adornee:IsA("Model")) then
		return
	end
	local scale = Scale.value
	local gui: BillboardGui = UIKit.new("BillboardGui", {
		Name = "GVF_Prompt_" .. prompt.Name,
		Adornee = adornee,
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(SIZE.X * scale, SIZE.Y * scale),
		StudsOffset = Vector3.new(0, 1.5, 0),
		SizeOffset = Vector2.new(0.2, stackIndex(prompt) * 1.15),
		ResetOnSpawn = false,
	})
	-- Device scale lives on this frame; the pop animation scales `root` separately.
	local scaler = UIKit.new("Frame", {
		Name = "Scaler",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1 / scale, 1 / scale),
		Parent = gui,
	}, { UIKit.new("UIScale", { Scale = scale }) })
	local root = UIKit.new("TextButton", {
		Name = "Root",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = scaler,
	})

	-- Key cap.
	local key = UIKit.new("Frame", {
		Name = "Key",
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.fromOffset(0, 3),
		ZIndex = 2,
		Parent = root,
	}, { UIKit.corner(UDim.new(0, 12)) })
	UIKit.paint(key, Theme.Colors.Surface)
	UIKit.outline(key)
	local fill = UIKit.new("Frame", {
		Name = "HoldFill",
		BackgroundColor3 = Theme.Colors.Primary,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 2,
		Parent = key,
	}, { UIKit.corner(UDim.new(0, 12)) })
	if inputType == Enum.ProximityPromptInputType.Touch then
		local hand = Icons.make("Hand")
		hand.AnchorPoint = Vector2.new(0.5, 0.5)
		hand.Position = UDim2.fromScale(0.5, 0.5)
		hand.Size = UDim2.fromScale(0.7, 0.7)
		hand.ZIndex = 3
		hand.Parent = key
	elseif keyText(prompt, inputType) == "E" and Icons.get("KeyE") and (Icons.get("KeyE") :: any).image ~= "" then
		key.BackgroundTransparency = 1
		local edge = key:FindFirstChild("Edge") :: UIStroke?
		if edge then
			edge.Enabled = false
		end
		local keyImage = Icons.make("KeyE")
		keyImage.Size = UDim2.fromScale(1, 1)
		keyImage.ZIndex = 3
		keyImage.Parent = key
	else
		UIKit.label(keyText(prompt, inputType), Theme.TextSize.Large + 2, {
			Name = "KeyText",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
			Parent = key,
		})
	end

	-- Action pill.
	local pill = UIKit.new("Frame", {
		Name = "Action",
		Position = UDim2.fromOffset(44, 7),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 1,
		Parent = root,
	}, {
		UIKit.corner(UDim.new(0, 12)),
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14) }),
		UIKit.list(Enum.FillDirection.Vertical, -2),
	})
	UIKit.paint(pill, Theme.Colors.Chip)
	UIKit.outline(pill)
	local layout = pill:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local action = UIKit.label(prompt.ActionText, Theme.TextSize.Body + 2, {
		Name = "ActionText",
		LayoutOrder = 1,
		TextColor3 = Theme.Colors.TextOnPrimary,
		Parent = pill,
	})
	UIKit.outlineText(action, 2)
	local object = UIKit.label(prompt.ObjectText, Theme.TextSize.Small, {
		Name = "ObjectText",
		LayoutOrder = 2,
		Font = Theme.FontBody,
		TextColor3 = Theme.lighten(Theme.Colors.Info, 0.5),
		Visible = prompt.ObjectText ~= "",
		Parent = pill,
	})

	local connections = {
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			action.Text = prompt.ActionText
		end),
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			object.Text = prompt.ObjectText
			object.Visible = prompt.ObjectText ~= ""
		end),
		-- Tap / click the prompt itself to use it (phones have no E key).
		root.MouseButton1Down:Connect(function()
			prompt:InputHoldBegin()
		end),
		root.MouseButton1Up:Connect(function()
			prompt:InputHoldEnd()
		end),
	}
	gui.Parent = container
	shown[prompt] = { gui = gui, fill = fill, connections = connections }
	local popScale = Tweens.getScale(root)
	popScale.Scale = 0.6
	Tweens.play(popScale, Tweens.Ease.PanelIn, { Scale = 1 })
end

local function customize(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
end

function PromptUI.start(playerGui: Instance)
	container = playerGui
	for _, d in workspace:GetDescendants() do
		customize(d)
	end
	workspace.DescendantAdded:Connect(customize)

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local entry = shown[prompt]
		if entry then
			Tweens.pop(entry.gui:FindFirstChild("Root", true) :: GuiObject, 0.15)
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local entry = shown[prompt]
		if entry and prompt.HoldDuration > 0 then
			entry.fill.Size = UDim2.fromScale(1, 0)
			Tweens.play(entry.fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local entry = shown[prompt]
		if entry then
			Tweens.play(entry.fill, Tweens.Ease.Fade, { Size = UDim2.fromScale(1, 0) })
		end
	end)
end

return PromptUI
