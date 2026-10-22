--!strict
--[[
	RibbonPanel: the ribbon shed. Every ribbon the player has won, grouped by
	color. Placeholder swatches; art seam for real ribbon images later.
]]

local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local RibbonNames = require(script.Parent.RibbonNames)

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
		local row = UIKit.card({ Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i, Parent = body })
		UIKit.new("Frame", {
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(12, 11),
			BackgroundColor3 = RibbonNames.Colors[ribbon.key],
			BorderSizePixel = 0,
			Parent = row,
		}, { UIKit.corner(UDim.new(1, 0)), UIKit.stroke(nil, 2) })
		UIKit.label(RibbonNames.describe(ribbon.id), Theme.TextSize.Body, {
			Position = UDim2.fromOffset(54, 14),
			Font = Theme.FontBody,
		}).Parent = row
		UIKit.label("x" .. ribbon.count, Theme.TextSize.Large, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 11),
			TextXAlignment = Enum.TextXAlignment.Right,
		}).Parent = row
	end
end

return RibbonPanel
