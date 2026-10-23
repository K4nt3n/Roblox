--!strict
--[[
	ToolBar: the garden tools as slots in our own bottom hotbar, left of the seeds.
	Roblox's default Backpack hotbar is turned off so the two never overlap.

	  Equip / put away: tap or click a slot, keys 1 2 3, or gamepad L1 / R1.
	  Picking a seed puts the tool away (ToolBar.unequip), and while a tool is
	  held the seed highlight dims (Hud.setToolActive), so only one is ever active.
	  The Fertilizer slot shows how many bags are left.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Signal = require(ReplicatedStorage.Shared.Signal)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)
local Scale = require(script.Parent.Scale)
local Tweens = require(script.Parent.Parent.Feel.Tweens)

local ToolBar = {}

ToolBar.Changed = Signal.new() -- (equippedToolId: string?)

-- Share of the slot the tool icon fills.
local ICON_SCALE = 0.68

local ORDER = { "WateringBucket", "PestRemover", "Fertilizer" }
local SHORT_NAME: { [string]: string } = {
	WateringBucket = "Bucket",
	PestRemover = "Bug Spray",
	Fertilizer = "Fertilizer",
}
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }

type Slot = { holder: Frame, button: TextButton, edge: UIStroke, count: TextLabel?, equipped: boolean }

local localPlayer = Players.LocalPlayer
local slots: { [string]: Slot } = {}
local equippedId: string? = nil
local divider: Frame? = nil

local function findTool(toolId: string): Tool?
	for _, container in { localPlayer.Character, localPlayer:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in (container :: Instance):GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("GardenTool") == toolId then
					return child
				end
			end
		end
	end
	return nil
end

local function currentlyEquipped(): string?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			local id = child:GetAttribute("GardenTool")
			return if type(id) == "string" then id else nil
		end
	end
	return nil
end

local function paintSlot(slot: Slot, equipped: boolean)
	if slot.equipped == equipped then
		return
	end
	slot.equipped = equipped
	Tweens.play(slot.button, Tweens.Ease.PanelIn, {
		Position = UDim2.new(0.5, 0, 1, if equipped then -4 - Theme.Size.SlotLift else -4),
	})
	Tweens.play(slot.edge, Tweens.Ease.Hover, {
		Color = if equipped then Theme.Colors.Gold else Theme.Style.Outline,
		Thickness = if equipped then 5 else Theme.Style.OutlineThickness,
	})
	UIKit.paint(slot.button, if equipped then Theme.Colors.Info else Theme.Colors.Surface)
	if equipped then
		Tweens.pop(slot.button, 0.12)
	end
end

local function refresh()
	local now = currentlyEquipped()
	for id, slot in slots do
		paintSlot(slot, id == now)
	end
	if now ~= equippedId then
		equippedId = now
		ToolBar.Changed:Fire(now)
	end
end

-- Short name shown when the tool is picked.
function ToolBar.displayName(toolId: string): string
	local def = Config.Tools.items[toolId]
	return SHORT_NAME[toolId] or (def and def.displayName) or toolId
end

function ToolBar.equipped(): string?
	return equippedId
end

function ToolBar.unequip()
	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and currentlyEquipped() then
		humanoid:UnequipTools()
	end
end

-- Equips the tool, or puts it away when it is already in hand.
function ToolBar.toggle(toolId: string)
	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
	local tool = findTool(toolId)
	if not humanoid or not tool then
		return
	end
	if currentlyEquipped() == toolId then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

local function cycle(step: number)
	local index = table.find(ORDER, equippedId or "") or (if step > 0 then 0 else #ORDER + 1)
	local nextIndex = index + step
	if nextIndex < 1 or nextIndex > #ORDER then
		ToolBar.unequip()
	else
		ToolBar.toggle(ORDER[nextIndex])
	end
end

local function makeSlot(parent: Instance, toolId: string, index: number)
	local def = Config.Tools.items[toolId]
	local size = if Scale.isPhone() then Theme.Size.SeedSlotPhone else Theme.Size.SeedSlot
	local holder = UIKit.new("Frame", {
		Name = "Tool_" .. toolId,
		BackgroundTransparency = 1,
		LayoutOrder = -100 + index,
		Size = UDim2.fromOffset(size, size + Theme.Size.SlotHeadroom + 4),
		Parent = parent,
	})
	local button = UIKit.button("", function()
		ToolBar.toggle(toolId)
	end, {
		Name = "Slot",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.Surface,
		Parent = holder,
	})
	local icon = ArtSlot.icon("Tool_" .. toolId, {
		color = Theme.Colors.Info,
		glyph = string.sub(def and def.displayName or toolId, 1, 1),
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		zIndex = 3,
	})
	-- Big and centred, and it grows and shrinks with the slot (phone sizes).
	icon.Size = UDim2.fromScale(ICON_SCALE, ICON_SCALE)
	icon.Parent = button
	UIKit.slotKey(button, tostring(index))
	slots[toolId] = {
		holder = holder,
		button = button,
		edge = button:FindFirstChild("Edge") :: UIStroke,
		count = if def and def.supply then UIKit.slotCount(button) else nil,
		equipped = false,
	}
end

-- Turns off Roblox's default Backpack hotbar (it can fail while the core scripts load).
local function hideDefaultBackpack()
	for _ = 1, 40 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.25)
	end
end

-- Adds the tool slots (and a divider) to the start of the hotbar list.
function ToolBar.mount(hotbar: Instance)
	task.spawn(hideDefaultBackpack)
	for i, toolId in ORDER do
		makeSlot(hotbar, toolId, i)
	end
	divider = UIKit.new("Frame", {
		Name = "ToolDivider",
		LayoutOrder = -50,
		Size = UDim2.fromOffset(4, Theme.Size.SeedSlot - 14),
		BackgroundColor3 = Theme.Colors.TextOnPrimary,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = hotbar,
	}, { UIKit.corner(Theme.CornerRound) })

	local function watch(character: Model)
		character.ChildAdded:Connect(refresh)
		character.ChildRemoved:Connect(refresh)
		refresh()
	end
	localPlayer.CharacterAdded:Connect(watch)
	if localPlayer.Character then
		watch(localPlayer.Character)
	end

	ContextActionService:BindAction("GVF_ToolKeys", function(_, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local index = table.find(KEYS, input.KeyCode)
		if index then
			ToolBar.toggle(ORDER[index])
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			cycle(1)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			cycle(-1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
end

-- Keeps the fertilizer badge in sync with the snapshot.
function ToolBar.render(data: { [string]: any })
	for toolId, slot in slots do
		local def = Config.Tools.items[toolId]
		local count = slot.count
		if count and def and def.supply then
			local bags = if data.supplies then data.supplies[def.supply] or 0 else 0
			-- Show 0 too (in red), so players see they are out.
			count.Text = tostring(bags)
			count.TextColor3 = if bags > 0 then Theme.Colors.TextOnPrimary else Theme.Colors.Danger
			count.Visible = true
		end
	end
end

function ToolBar.resize(size: number)
	for _, slot in slots do
		slot.holder.Size = UDim2.fromOffset(size, size + Theme.Size.SlotHeadroom + 4)
		slot.button.Size = UDim2.fromOffset(size, size)
	end
	if divider then
		divider.Size = UDim2.fromOffset(4, size - 14)
	end
end

return ToolBar
