--!strict
--[[
	BasketPanel: everything you've harvested, heaviest first, so fair
	candidates sit on top. Sell one, sell all, or enter one in a fair.
	The total value rolls up instead of snapping when the basket changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local ArtSlot = require(script.Parent.ArtSlot)
local Counter = require(script.Parent.Counter)
local FairPanel = require(script.Parent.FairPanel)

local BasketPanel = {}

-- Remembered between renders so the worth counter rolls from the last value.
local lastWorth = 0

function BasketPanel.render(body: ScrollingFrame, data: { [string]: any })
	local total = 0
	for _, price in data.producePrices or {} do
		total += price
	end

	local sellAll =
		UIKit.requestButton("Sell All", Net.Actions.SellAll, nil, { BackgroundColor3 = Theme.Colors.Accent })
	UIKit.setEnabled(sellAll, #data.produce > 0, nil, "Your basket is empty. Harvest something!")
	local header = UIKit.row(
		string.format("Basket (%d/%d)", #data.produce, Config.Economy.maxProduceInventory),
		"Worth 0 Coins",
		{ sellAll },
		ArtSlot.icon("MenuMarket", { color = Theme.Colors.Accent, glyph = "B" })
	)
	header.LayoutOrder = 0
	header.BackgroundColor3 = Theme.lighten(Theme.Colors.Accent, 0.82)
	header.Parent = body
	local worthLabel = header:FindFirstChild("Sub", true) :: TextLabel?
	if worthLabel then
		local worth = Counter.new(worthLabel, function(n)
			return "Worth " .. Format.coins(math.floor(n + 0.5)) .. " Coins"
		end)
		worth:set(lastWorth, { instant = true })
		worth:set(total, { quiet = true })
	end
	lastWorth = total

	if #data.produce == 0 then
		UIKit.paragraph("Nothing in your basket yet. Harvest a ripe veggie to fill it!", {
			LayoutOrder = 1,
			TextColor3 = Theme.Colors.TextMuted,
		}).Parent =
			body
		return
	end

	local items = table.clone(data.produce)
	table.sort(items, function(a, b)
		return a.weight > b.weight
	end)
	for i, item in items do
		local crop = Config.Crops[item.cropId]
		local price = data.producePrices and data.producePrices[tostring(item.uid)] or 0
		local sell = UIKit.requestButton(Format.coins(price), Net.Actions.SellProduce, { uid = item.uid })
		local enter = UIKit.button("Enter Fair", function()
			FairPanel.pick(item)
		end, { BackgroundColor3 = Theme.Colors.Gold })
		local tags = {}
		if item.isChampion then
			table.insert(tags, if item.name then 'Champion "' .. item.name .. '"' else "Champion")
		end
		if item.isGiant then
			table.insert(tags, "GIANT")
		end
		if item.gene then
			table.insert(tags, "★ Giant gene")
		end
		local c = crop and crop.placeholderColor
		local row = UIKit.row(
			string.format("%s · %s", if crop then crop.displayName else item.cropId, Format.weight(item.weight)),
			if #tags > 0 then table.concat(tags, " · ") else nil,
			{ enter, sell },
			ArtSlot.icon("Seed_" .. item.cropId, {
				round = true,
				color = if c then Color3.fromRGB(c[1], c[2], c[3]) else nil,
				glyph = if crop then string.sub(crop.displayName, 1, 1) else "?",
			})
		)
		row.LayoutOrder = i
		if item.isChampion or item.isGiant then
			row.BackgroundColor3 = Theme.lighten(Theme.Colors.Gold, 0.75)
		end
		row.Parent = body
	end
end

return BasketPanel
