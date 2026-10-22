--!strict
--[[
	RibbonPanel: the ribbon shed. Every ribbon the player has won, grouped by
	color. Placeholder swatches; art slots "Ribbon_<Blue|Red|Yellow|Team|Entrant>"
	take Peter's ribbon images.
]]

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local RibbonNames = require(script.Parent.RibbonNames)
local ArtSlot = require(script.Parent.ArtSlot)

local RibbonPanel = {}

local ORDER = { Blue = 1, Red = 2, Yellow = 3, Team = 4, Entrant = 5 }

function RibbonPanel.render(body: ScrollingFrame, data: { [string]: any })
	local list = {}
	for id, count in data.ribbons or {} do
		table.insert(list, { id = id, count = count, key = RibbonNames.colorKey(id) })
	end
	table.sort(list, function(a, b)
		if ORDER[a.key] ~= ORDER[b.key] then
			return (ORDER[a.key] or 9) < (ORDER[b.key] or 9)
		end
		return a.id < b.id
	end)
	if #list == 0 then
		UIKit.label("No ribbons yet. Enter a fair to win your first!", Theme.TextSize.Body, {
			LayoutOrder = 1,
			Font = Theme.FontBody,
		}).Parent = body
		return
	end
	for i, ribbon in list do
		local row = UIKit.card({ Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i, Parent = body })
		ArtSlot.icon("Ribbon_" .. ribbon.key, {
			size = 36,
			round = true,
			color = RibbonNames.Colors[ribbon.key],
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 12, 0.5, 0),
		}).Parent = row
		UIKit.label(RibbonNames.describe(ribbon.id), Theme.TextSize.Body, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 58, 0.5, 0),
			Size = UDim2.new(1, -130, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			Font = Theme.FontBody,
		}).Parent = row
		UIKit.label("x" .. ribbon.count, Theme.TextSize.Large, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
		}).Parent = row
	end
end

return RibbonPanel
