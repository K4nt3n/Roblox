--!strict
--[[
	ToolsPanel: the garden tools (StarterPack Tools with a "GardenTool"
	attribute, see Config.Tools), shown in Backpack > Supplies. Each card equips
	or puts away that tool, so players on any device can pick a tool without
	the Roblox hotbar. More fertilizer is bought at the Seed Shop stand.
	Using a tool is handled by Controllers/ToolController (server-validated).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)

local ToolsPanel = {}

-- Set by UIController: closes the panel (after equipping, so the tool can be used right away).
ToolsPanel.close = function() end

local ORDER = { "WateringBucket", "PestRemover", "Fertilizer" }
local BLURB: { [string]: string } = {
	WateringBucket = "Water a plant so it grows faster",
	PestRemover = "Spray the bugs off a plant",
	Fertilizer = "One growth boost per plant",
}

local localPlayer = Players.LocalPlayer

-- The tool instance and whether it is in the character's hand.
local function findTool(toolId: string): (Tool?, boolean)
	local character = localPlayer.Character
	for _, container in { character, localPlayer:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in (container :: Instance):GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("GardenTool") == toolId then
					return child, container == character
				end
			end
		end
	end
	return nil, false
end

-- Renders the tool cards and a hint into `body`, using LayoutOrder `order` and `order + 1`.
function ToolsPanel.render(body: ScrollingFrame, data: { [string]: any }, order: number?)
	local first = order or 1
	local grid = UIKit.grid(first, body, Vector2.new(170, 186))
	for i, toolId in ORDER do
		local def = Config.Tools.items[toolId]
		if def then
			local tool, equipped = findTool(toolId)
			local bags: number? = nil
			if def.supply then
				bags = if data.supplies then data.supplies[def.supply] or 0 else 0
			end
			local outOfBags = bags ~= nil and bags == 0
			local label = if outOfBags then "Empty" elseif equipped then "Put away" else "Equip"
			local color = if equipped then Theme.Colors.Accent else Theme.Colors.Info
			local button = UIKit.button(label, function()
				local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
				if not humanoid or not tool then
					return
				end
				if equipped then
					humanoid:UnequipTools()
				else
					humanoid:EquipTool(tool)
				end
				ToolsPanel.close()
			end, { BackgroundColor3 = color })
			UIKit.setEnabled(
				button,
				not outOfBags and tool ~= nil,
				nil,
				if outOfBags then "Buy more at the Seed Shop in the middle!" else "Respawn to get your tools back!"
			)
			local card = UIKit.itemCard({
				name = def.displayName,
				icon = ArtSlot.icon("Tool_" .. toolId, { color = Theme.Colors.Info, glyph = string.sub(def.displayName, 1, 1) }),
				sub = if bags then string.format("%d bag%s left", bags, if bags == 1 then "" else "s") else BLURB[toolId],
				button = button,
				count = bags,
				order = i,
			})
			card.Parent = grid
		end
	end
	UIKit.paragraph("Equip a tool, then click or tap the plant. Plants can only be watered with the Watering Bucket.", {
		LayoutOrder = first + 1,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextMuted,
		Size = UDim2.new(1, -8, 0, 0),
	}).Parent = body
end

return ToolsPanel
