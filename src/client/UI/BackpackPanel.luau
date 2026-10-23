--!strict
--[[
	BackpackPanel: everything the player owns, read from the server snapshot
	(no second inventory): seeds, supplies and harvested veggies (the Basket).
	Selling still happens in the Basket panel; this view links to it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)

local BackpackPanel = {}

BackpackPanel.TABS = {
	{ id = "seeds", text = "Seeds", icon = "Seeds", color = Theme.Colors.Primary },
	{ id = "supplies", text = "Supplies", icon = "Tools", color = Theme.Colors.Info },
	{ id = "harvest", text = "Harvest", icon = "Basket", color = Theme.Colors.Accent },
} :: { UIKit.TabItem }

-- Set by UIController: opens another panel (Basket to sell, Shop to buy).
BackpackPanel.open = function(_name: string, _tab: string?) end

-- Most veggies shown at once (heaviest first); the Basket lists them all.
local MAX_HARVEST = 24

local function cropIcon(cropId: string): GuiObject
	local crop = Config.Crops[cropId]
	local c = crop and crop.placeholderColor
	return ArtSlot.icon("Seed_" .. cropId, {
		round = true,
		color = if c then Color3.fromRGB(c[1], c[2], c[3]) else nil,
		glyph = if crop then string.sub(crop.displayName, 1, 1) else "?",
	})
end

local function empty(body: ScrollingFrame, text: string, buttonText: string, panel: string, tab: string?)
	UIKit.paragraph(text, { LayoutOrder = 1, TextColor3 = Theme.Colors.TextMuted }).Parent = body
	UIKit.button(buttonText, function()
		BackpackPanel.open(panel, tab)
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
		empty(body, "No seeds yet.", "Buy seeds", "Shop", "seeds")
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

local function renderSupplies(body: ScrollingFrame, data: { [string]: any })
	local ids = {}
	for id in Config.Supplies do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return Config.Supplies[a].order < Config.Supplies[b].order
	end)
	local grid = UIKit.grid(1, body, Vector2.new(124, 140))
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
	UIKit.button("Buy more supplies", function()
		BackpackPanel.open("Shop", "supplies")
	end, { LayoutOrder = 2, Size = UDim2.fromOffset(220, 44), BackgroundColor3 = Theme.Colors.Primary }).Parent = body
end

local function renderHarvest(body: ScrollingFrame, data: { [string]: any })
	local produce = data.produce or {}
	if #produce == 0 then
		empty(body, "Your basket is empty. Harvest ripe veggies from your garden!", "Open Basket", "Market")
		return
	end
	local sell = UIKit.button("Sell", function()
		BackpackPanel.open("Market")
	end, { BackgroundColor3 = Theme.Colors.Accent })
	local header = UIKit.row(
		string.format("Basket %d/%d", #produce, Config.Economy.maxProduceInventory),
		"Sell veggies or enter them in a fair",
		{ sell }
	)
	header.LayoutOrder = 1
	header.Parent = body
	local items = table.clone(produce)
	table.sort(items, function(a, b)
		return a.weight > b.weight
	end)
	local grid = UIKit.grid(2, body, Vector2.new(124, 140))
	for i = 1, math.min(#items, MAX_HARVEST) do
		local item = items[i]
		local crop = Config.Crops[item.cropId]
		UIKit.itemCard({
			name = if crop then crop.displayName else item.cropId,
			icon = cropIcon(item.cropId),
			sub = Format.weight(item.weight) .. (if item.isGiant then " · GIANT" else ""),
			order = i,
		}).Parent = grid
	end
end

function BackpackPanel.render(body: ScrollingFrame, data: { [string]: any }, tab: string?)
	if tab == "supplies" then
		renderSupplies(body, data)
	elseif tab == "harvest" then
		renderHarvest(body, data)
	else
		renderSeeds(body, data)
	end
end

return BackpackPanel
