--!strict
--[[
	BackpackPanel: what the player owns, read from the server snapshot (no
	second inventory): seeds, and supplies with the garden tools (ToolsPanel).
	Buying happens at the Seed Shop stand and selling at the Selling Merchant,
	both in the middle of the map.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)
local ToolsPanel = require(script.Parent.ToolsPanel)
local Teleport = require(script.Parent.Parent.Controllers.Teleport)

local BackpackPanel = {}

BackpackPanel.TABS = {
	{ id = "seeds", text = "Seeds", icon = "Seeds", color = Theme.Colors.Primary },
	{ id = "supplies", text = "Supplies", icon = "Tools", color = Theme.Colors.Info },
} :: { UIKit.TabItem }

-- Set by UIController: closes the panel (before a teleport).
BackpackPanel.close = function() end

local function cropIcon(cropId: string): GuiObject
	local crop = Config.Crops[cropId]
	local c = crop and crop.placeholderColor
	return ArtSlot.icon("Seed_" .. cropId, {
		round = true,
		color = if c then Color3.fromRGB(c[1], c[2], c[3]) else nil,
		glyph = if crop then string.sub(crop.displayName, 1, 1) else "?",
	})
end

local function empty(body: ScrollingFrame, text: string)
	UIKit.paragraph(text, { LayoutOrder = 1, TextColor3 = Theme.Colors.TextMuted }).Parent = body
	UIKit.button("Go to the Shops", function()
		BackpackPanel.close()
		Teleport.toShops()
	end, { LayoutOrder = 2, Size = UDim2.fromOffset(200, 44), BackgroundColor3 = Theme.Colors.Primary }).Parent = body
end

local function renderSeeds(body: ScrollingFrame, data: { [string]: any })
	local crops = {}
	for _, crop in Config.Crops do
		local count = data.seeds[crop.id] or 0
		if crop.seedCost == 0 or count > 0 then
			table.insert(crops, crop)
		end
	end
	table.sort(crops, function(a, b)
		return a.order < b.order
	end)
	if #crops == 0 then
		empty(body, "No seeds yet. Buy them at the Seed Shop in the middle of the map!")
		return
	end
	local grid = UIKit.grid(1, body, Vector2.new(124, 140))
	for i, crop in crops do
		local free = crop.seedCost == 0
		local card = UIKit.itemCard({
			name = crop.displayName,
			icon = cropIcon(crop.id),
			sub = if free then "Always free" elseif data.selectedSeed == crop.id then "Selected" else nil,
			count = if free then nil else data.seeds[crop.id],
			order = i,
		})
		if free then
			local holder = card:FindFirstChild("IconHolder")
			local infinite = UIKit.label("∞", Theme.TextSize.Large, {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -6, 1, 0),
				TextColor3 = Theme.Colors.TextOnPrimary,
				ZIndex = 3,
				Parent = holder,
			})
			UIKit.outlineText(infinite, 2)
		end
		card.Parent = grid
	end
end

-- Garden tools first (equip from here), then any supplies no tool card already counts.
local function renderSupplies(body: ScrollingFrame, data: { [string]: any })
	ToolsPanel.render(body, data, 1)
	local onTool: { [string]: boolean } = {}
	for _, def in Config.Tools.items do
		if def.supply then
			onTool[def.supply] = true
		end
	end
	local ids = {}
	for id in Config.Supplies do
		if not onTool[id] then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return
	end
	table.sort(ids, function(a, b)
		return Config.Supplies[a].order < Config.Supplies[b].order
	end)
	local grid = UIKit.grid(3, body, Vector2.new(124, 140))
	for i, id in ids do
		local def = Config.Supplies[id]
		local owned = if data.supplies then data.supplies[id] or 0 else 0
		UIKit.itemCard({
			name = def.displayName,
			icon = ArtSlot.icon("Supply_" .. id, { color = Theme.Colors.Primary, glyph = string.sub(def.displayName, 1, 1) }),
			count = owned,
			order = i,
		}).Parent = grid
	end
end

function BackpackPanel.render(body: ScrollingFrame, data: { [string]: any }, tab: string?)
	if tab == "supplies" then
		renderSupplies(body, data)
	else
		renderSeeds(body, data)
	end
end

return BackpackPanel
