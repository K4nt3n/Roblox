--!strict
--[[
	FairPanel: the three fairs (hourly, daily, weekly) side by side, the fair
	picker used by the Basket, and the results / replay card.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local FairMath = require(Shared.FairMath)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Modal = require(script.Parent.Modal)
local RibbonNames = require(script.Parent.RibbonNames)
local ArtSlot = require(script.Parent.ArtSlot)

local FairPanel = {}

local localPlayer = Players.LocalPlayer
local PERIODS = FairMath.sortedPeriods(Config.Fair.periods)

-- Tabs for the panel header (UIController builds them once, so the highlight can slide).
FairPanel.TABS = {} :: { UIKit.TabItem }
for _, period in PERIODS do
	table.insert(FairPanel.TABS, { id = period.id, text = period.displayName })
end
FairPanel.DEFAULT_TAB = if Config.Fair.periods.weekly then "weekly" else PERIODS[1].id

local function cropName(cropId: string?): string
	local crop = cropId and Config.Crops[cropId]
	return if crop then crop.displayName else (cropId or "")
end

local function currentEntry(data: { [string]: any }, fairName: string): any
	local info = data.fairs and data.fairs[fairName]
	local entries = data.fair and data.fair.entries and data.fair.entries[fairName]
	return info and entries and entries[tostring(info.id)]
end

local function muted(text: string, order: number, parent: Instance, props: { [string]: any }?): TextLabel
	local label = UIKit.paragraph(text, { LayoutOrder = order, TextColor3 = Theme.Colors.TextMuted, Parent = parent })
	for key, value in props or {} do
		(label :: any)[key] = value
	end
	return label
end

function FairPanel.render(body: ScrollingFrame, data: { [string]: any }, tab: string?)
	local selectedFair = if tab and Config.Fair.periods[tab] then tab else FairPanel.DEFAULT_TAB
	local period = Config.Fair.periods[selectedFair]
	local entry = currentEntry(data, selectedFair)

	-- Countdown: when the judges weigh in next.
	local hero = UIKit.card({
		Name = "Countdown",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = body,
	}, {
		UIKit.padding(14),
		UIKit.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center),
	})
	local heroEdge = hero:FindFirstChild("Edge") :: UIStroke
	heroEdge.Color = Theme.Colors.Gold
	heroEdge.Transparency = 0
	heroEdge.Thickness = 3
	UIKit.label(period.displayName, Theme.TextSize.Large, { LayoutOrder = 1 }).Parent = hero
	local countdown = UIKit.label("", Theme.TextSize.Huge, { LayoutOrder = 2, TextColor3 = Theme.Colors.Gold })
	countdown.Parent = hero
	UIKit.outlineText(countdown, Theme.Style.TitleOutline, true)
	local caption = UIKit.label(
		"",
		Theme.TextSize.Small,
		{ LayoutOrder = 3, Font = Theme.FontBody, TextColor3 = Theme.Colors.TextMuted }
	)
	caption.Parent = hero
	if RunService:IsStudio() then
		UIKit.button("Preview show (Studio)", function()
			task.spawn(NetClient.request, Net.Actions.DebugStartFairDay, { fair = selectedFair })
		end, { LayoutOrder = 10, Size = UDim2.fromOffset(220, 36), BackgroundColor3 = Theme.Colors.Accent }).Parent =
			hero
	end
	task.spawn(function()
		while countdown.Parent do
			local now = ClientState.now()
			local phase, _, at = FairMath.showPhase(now, period)
			if phase == "Live" then
				countdown.Text = "Live now!"
				caption.Text = "The weigh-in show is on at the Weigh-In Fair stand"
			else
				countdown.Text = Format.duration(at - now)
				caption.Text = "until the judges weigh in"
			end
			task.wait(1)
		end
	end)

	-- Your entry.
	local mine = UIKit.card({
		Name = "Entry",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = body,
	}, {
		UIKit.padding(12),
		UIKit.list(Enum.FillDirection.Vertical, 4),
	})
	if entry then
		local crop = Config.Crops[entry.cropId]
		local top = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 48),
			Parent = mine,
		})
		local c = crop and crop.placeholderColor
		ArtSlot.icon("Seed_" .. tostring(entry.cropId), {
			size = 48,
			round = true,
			color = if c then Color3.fromRGB(c[1], c[2], c[3]) else Theme.Colors.Primary,
			glyph = string.sub(cropName(entry.cropId), 1, 1),
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 0, 0.5, 0),
		}).Parent =
			top
		UIKit.label("Your entry: " .. cropName(entry.cropId), Theme.TextSize.Large, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 58, 0.5, 0),
			Parent = top,
		})
		UIKit.label(Format.weight(entry.weight), Theme.TextSize.Large, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.Colors.Gold,
			Parent = top,
		})
		local item = entry.item
		if item then
			local divisions = {}
			for _, division in FairMath.divisionsForEntry(item, entry.ctx or {}, period.divisions) do
				table.insert(divisions, FairMath.divisionName(division.id, Config.Fair.divisions, Config.Crops))
			end
			muted("Competing for: " .. table.concat(divisions, ", "), 2, mine)
		end
	else
		UIKit.label("No entry yet", Theme.TextSize.Large, { LayoutOrder = 1 }).Parent = mine
		muted("Talk to the Fair Judge at the Weigh-In Fair stand to enter a veggie.", 2, mine)
	end

	-- How it works.
	UIKit.steps("How the weigh-in works", {
		"Grow and harvest the heaviest veggie you can. Your champion grows the biggest.",
		"Bring it to the Fair Judge at the Weigh-In Fair stand and pick a fair.",
		"When the timer hits zero, the judges weigh every entry. The heaviest win ribbons and coins.",
		"Each veggie enters one fair. A heavier veggie replaces your old entry.",
	}, 3, body)

	-- What you can win.
	local divisionNames = {}
	for _, id in period.divisions do
		local name = if id == "crop"
			then "Best of each veggie"
			else FairMath.divisionName(id, Config.Fair.divisions, Config.Crops)
		table.insert(divisionNames, name)
	end
	UIKit.section("Ribbons to win", 4, body)
	muted(table.concat(divisionNames, "  ·  "), 5, body, { Size = UDim2.new(1, -8, 0, 0) })

	-- Leaderboard.
	UIKit.section("Top growers", 10, body)
	local board = ClientState.leaderboard
	local rows = board and board.fairs and board.fairs[selectedFair] and board.fairs[selectedFair].rows or {}
	if #rows == 0 then
		muted("No entries yet. Be the first!", 11, body)
	end
	local MEDALS = { Theme.Colors.Gold, Color3.fromRGB(205, 210, 220), Color3.fromRGB(215, 150, 95) }
	for i, row in rows do
		local isMe = row.userId == localPlayer.UserId
		local card = UIKit.card({
			Size = UDim2.new(1, -8, 0, 48),
			LayoutOrder = 20 + i,
			Parent = body,
		}, {
			UIKit.label(string.format("#%d  %s", row.rank, row.name), Theme.TextSize.Body, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, if row.rank <= 3 then 52 else 14, 0.5, 0),
			}),
			UIKit.label(Format.weight(row.weight), Theme.TextSize.Body, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		})
		if isMe then
			-- Your own row: gold edge instead of a bright fill, so the white text stays readable.
			local edge = card:FindFirstChild("Edge") :: UIStroke
			edge.Color = Theme.Colors.Gold
			edge.Transparency = 0
			edge.Thickness = 3
		end
		if row.rank <= 3 then
			ArtSlot.icon("Medal_" .. row.rank, {
				size = 32,
				round = true,
				color = MEDALS[row.rank],
				glyph = tostring(row.rank),
				anchor = Vector2.new(0, 0.5),
				position = UDim2.new(0, 12, 0.5, 0),
			}).Parent =
				card
		end
	end
end

-- Basket "Enter Fair": pick which fair this veggie goes to.
function FairPanel.pick(item: { [string]: any })
	local data = ClientState.data
	if not data then
		return
	end
	Modal.show({
		title = "Enter " .. cropName(item.cropId) .. " · " .. Format.weight(item.weight),
		lines = { "Each veggie can go to one fair. Heavier entries replace lighter ones." },
		build = function(holder, close)
			for i, period in PERIODS do
				local entry = currentEntry(data, period.id)
				local fairInfo = data.fairs and data.fairs[period.id]
				local left = if fairInfo then Format.duration(fairInfo.endsAt - ClientState.now()) else ""
				local status = if entry
					then (if entry.weight >= item.weight
						then "Your entry is heavier (" .. Format.weight(entry.weight) .. ")"
						else "Replaces " .. Format.weight(entry.weight))
					else "No entry yet"
				local canEnter = not entry or entry.weight < item.weight
				local button = UIKit.button("Enter", function()
					task.spawn(NetClient.request, Net.Actions.EnterFair, { uid = item.uid, fair = period.id })
					close()
				end, { BackgroundColor3 = Theme.Colors.Gold })
				UIKit.setEnabled(button, canEnter, nil, "Your entry there is already heavier!")
				local row =
					UIKit.row(period.displayName, string.format("Judging in %s · %s", left, status), { button })
				row.LayoutOrder = i
				row.Size = UDim2.new(1, 0, 0, 64)
				row.Parent = holder
			end
		end,
		buttons = { { text = "Not now", color = Theme.Colors.Surface, textColor = Theme.Colors.Text } },
	})
end

-- Results after a show, or a replay card for a show the player missed.
function FairPanel.showResults(ctx: { [string]: any })
	local lines = {}
	if ctx.weight then
		local who = if ctx.championName
			then string.format("%s the %s", ctx.championName, cropName(ctx.cropId))
			else cropName(ctx.cropId)
		table.insert(lines, string.format("%s weighed %s", who, Format.weight(ctx.weight)))
	end
	if ctx.coGrowerNames and #ctx.coGrowerNames > 0 then
		table.insert(lines, "Grown together with " .. table.concat(ctx.coGrowerNames, " and "))
	end
	for _, ribbon in ctx.ribbons or {} do
		local place = if ribbon.rank then " (#" .. ribbon.rank .. ")" else ""
		table.insert(lines, RibbonNames.describe(ribbon.ribbon) .. place)
	end
	if #(ctx.ribbons or {}) == 0 then
		table.insert(lines, "No ribbon this time. Keep growing!")
	end
	if (ctx.coins or 0) > 0 then
		table.insert(lines, "+" .. Format.coins(ctx.coins) .. " Coins")
	end
	Modal.show({
		title = if ctx.missedShow
			then "You missed the " .. ctx.fairName .. "! Here's the replay"
			else ctx.fairName .. " results",
		lines = lines,
		accent = Theme.Colors.Gold,
		buttons = { { text = "Hooray!", color = Theme.Colors.Gold, textColor = Theme.Colors.Text } },
	})
end

return FairPanel
