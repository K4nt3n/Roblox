--!strict
--[[
	ToolsPanel: the garden tools (StarterPack Tools with a "GardenTool"
	attribute, see Config.Tools), shown in Backpack > Supplies. Equip puts the
	tool on the hotbar and Unequip takes it off (saved as data.hotbar); the tool
	itself is picked from the hotbar. More fertilizer is bought at the Seed Shop stand.
	Using a tool is handled by Controllers/ToolController (server-validated).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared.Net)
local NetClient = require(script.Parent.Parent.NetClient)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)
local ToolBar = require(script.Parent.ToolBar)

local ToolsPanel = {}

-- Set by UIController: closes the panel.
ToolsPanel.close = function() end

local ORDER = { "WateringBucket", "PestRemover", "Fertilizer" }
local BLURB: { [string]: string } = {
	WateringBucket = "Water a plant so it grows faster",
	PestRemover = "Spray the bugs off a plant",
	Fertilizer = "One growth boost per plant",
}

-- Renders the tool cards and a hint into `body`, using LayoutOrder `order` and `order + 1`.
function ToolsPanel.render(body: ScrollingFrame, data: { [string]: any }, order: number?)
	local first = order or 1
	local grid = UIKit.grid(first, body, Vector2.new(170, 186))
	for i, toolId in ORDER do
		local def = Config.Tools.items[toolId]
		if def then
			local bags: number? = nil
			if def.supply then
				bags = if data.supplies then data.supplies[def.supply] or 0 else 0
			end
			local onHotbar = ToolBar.onHotbar(data, toolId)
			local color = if onHotbar then Theme.Colors.Accent else Theme.Colors.Info
			local button = UIKit.button(if onHotbar then "Unequip" else "Equip", function()
				task.spawn(NetClient.request, Net.Actions.SetHotbarTool, { toolId = toolId, on = not onHotbar })
			end, { BackgroundColor3 = color })
			local card = UIKit.itemCard({
				name = def.displayName,
				icon = ArtSlot.icon(
					"Tool_" .. toolId,
					{ color = Theme.Colors.Info, glyph = string.sub(def.displayName, 1, 1) }
				),
				sub = if bags
					then string.format("%d bag%s left", bags, if bags == 1 then "" else "s")
					else BLURB[toolId],
				button = button,
				count = bags,
				order = i,
			})
			card.Parent = grid
		end
	end
	UIKit.paragraph(
		"Equip puts a tool on your hotbar. Pick it there (or press its number), then click or tap the plant. Plants can only be watered with the Watering Bucket.",
		{
			LayoutOrder = first + 1,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextMuted,
			Size = UDim2.new(1, -8, 0, 0),
		}
	).Parent =
		body
end

return ToolsPanel
