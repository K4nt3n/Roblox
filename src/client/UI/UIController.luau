--!strict
--[[
	UIController: minimal, functional placeholder UI built in code.

	HUD:     coins (counts up), level bar (filled by XP essence), seed picker,
	         menu buttons, toasts.
	Panels:  Shop (seeds, upgrades, plots, honest skips), Basket (sell / enter a
	         fair), Fairs (hourly / daily / weekly), Champion, Ribbons.
	Modals:  fair picker, results / replay cards, co-grow invites, naming.

	Panels re-render from ClientState whenever a snapshot arrives. Every number
	the UI shows (prices, upgrade costs) comes from the server snapshot so the
	client never duplicates game rules. Replace any builder with art-backed UI
	later; the data flow stays the same.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local GrowthMath = require(Shared.GrowthMath)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local FeelController = require(script.Parent.Parent.Feel.FeelController)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local GardenController = require(script.Parent.Parent.Controllers.GardenController)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Modal = require(script.Parent.Modal)
local LevelBar = require(script.Parent.LevelBar)
local FairPanel = require(script.Parent.FairPanel)
local ChampionPanel = require(script.Parent.ChampionPanel)
local RibbonPanel = require(script.Parent.RibbonPanel)
local RibbonNames = require(script.Parent.RibbonNames)

local UIController = {}

local localPlayer = Players.LocalPlayer

-- Friendly words for server denial reasons. Keep these short and kind.
local REASONS: { [string]: string } = {
	NotEnoughCoins = "Not enough Coins yet!",
	NoSeeds = "Out of those seeds. Visit the Seed Shop!",
	LevelLocked = "Reach a higher level to unlock that!",
	Cooldown = "Already watered. Give it a moment!",
	Maxed = "That's as big as it gets!",
	BasketFull = "Your basket is full. Sell some veggies!",
	FriendLimit = "You've watered this garden a lot today!",
	NotFriends = "You can only water friends' gardens.",
	NotHeavier = "Your fair entry is already heavier!",
	NotRipe = "Not ripe yet!",
	TooFast = "Whoa, slow down!",
	ProductNotConfigured = "Skips aren't set up yet.",
	PlotLocked = "Buy this plot first!",
	SkipCapReached = "Champions can only be skipped once a week. Care for it instead!",
	ShowRunning = "The weigh-in show is on! Enter the next fair.",
	UnknownFair = "That fair isn't open.",
	NotCoGrower = "Only its growers can care for this champion.",
	NoCareNeeded = "Your champion is happy right now!",
	TeamFull = "This champion already has a full team.",
	AlreadyCoGrower = "They're already growing it with you!",
	PlayerNotHere = "That player isn't in this server.",
	InviteExpired = "That invite has expired.",
	BadName = "Try a different name (1-20 letters).",
	FilterFailed = "Couldn't check that name. Try another!",
	NotChampion = "That's not a champion plot.",
}

local CARE_DONE: { [string]: string } = {
	Water = "watered",
	Pests = "picked off the bugs on",
	Prop = "propped up",
}
local CARE_NEEDED: { [string]: string } = {
	Water = "is thirsty!",
	Pests = "has bugs on its leaves!",
	Prop = "is so heavy it's leaning!",
}

local gui: ScreenGui
local coinsLabel: TextLabel
local seedBar: Frame
local toastHolder: Frame
local panels: { [string]: CanvasGroup } = {}
local panelBodies: { [string]: ScrollingFrame } = {}
local openPanel: string? = nil
local shownCoins = 0

local function cropOrder(): { any }
	local list = {}
	for _, crop in Config.Crops do
		table.insert(list, crop)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

local function request(action: string, payload: { [string]: any }?)
	task.spawn(NetClient.request, action, payload)
end

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------

function UIController.toast(text: string, color: Color3?, duration: number?)
	local toast = UIKit.card({
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color or Theme.Colors.Surface,
		LayoutOrder = -os.clock() * 1000,
	}, {
		UIKit.padding(10),
		UIKit.label(text, Theme.TextSize.Body, {
			TextColor3 = if color then Theme.Colors.TextOnPrimary else Theme.Colors.Text,
		}),
	})
	local scale = Tweens.getScale(toast)
	scale.Scale = 0.6
	toast.Parent = toastHolder
	Tweens.play(scale, Tweens.Ease.Pop, { Scale = 1 })
	task.delay(duration or 2.6, function()
		local tween = Tweens.play(scale, Tweens.Ease.Fade, { Scale = 0 })
		if tween then
			tween.Completed:Wait()
		end
		toast:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

local renderers: { [string]: (body: ScrollingFrame, data: { [string]: any }) -> () } = {}

local function clearBody(body: ScrollingFrame)
	for _, child in body:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function renderPanel(name: string)
	local data = ClientState.data
	local body = panelBodies[name]
	if not data or not body then
		return
	end
	clearBody(body)
	renderers[name](body, data)
end

function UIController.open(name: string)
	if openPanel == name then
		return
	end
	if openPanel then
		UIController.close()
	end
	local panel = panels[name]
	if not panel then
		return
	end
	openPanel = name
	renderPanel(name)
	Tweens.openPanel(panel)
	FeelController.play("PanelOpen")
end

function UIController.close()
	if not openPanel then
		return
	end
	Tweens.closePanel(panels[openPanel])
	openPanel = nil
	FeelController.play("PanelClose")
end

local function section(body: ScrollingFrame, title: string, order: number)
	UIKit.label(title, Theme.TextSize.Large, { LayoutOrder = order }).Parent = body
end

renderers.Shop = function(body, data)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	section(body, "Seeds", nextOrder())
	for _, crop in cropOrder() do
		local locked = data.level < crop.unlockLevel
		local owned = data.seeds[crop.id] or 0
		local sub = if locked
			then "Unlocks at level " .. crop.unlockLevel
			else string.format("Ripe in %s · You have %s", Format.duration(crop.growSeconds), if crop.seedCost == 0 then "∞" else tostring(owned))
		local buy = UIKit.button(if crop.seedCost == 0 then "Free" else Format.coins(crop.seedCost), function()
			request(Net.Actions.BuySeed, { cropId = crop.id, amount = 1 })
		end)
		local buyFive = UIKit.button("x5", function()
			request(Net.Actions.BuySeed, { cropId = crop.id, amount = 5 })
		end, { BackgroundColor3 = Theme.Colors.Accent })
		UIKit.setEnabled(buy, not locked and crop.seedCost > 0 and data.coins >= crop.seedCost)
		UIKit.setEnabled(buyFive, not locked and crop.seedCost > 0 and data.coins >= crop.seedCost * 5, Theme.Colors.Accent)
		local row = UIKit.row(crop.displayName, sub, { buyFive, buy })
		row.LayoutOrder = nextOrder()
		row.Parent = body
	end

	section(body, "Upgrades", nextOrder())
	local upgradeIds = {}
	for id in Config.Upgrades do
		table.insert(upgradeIds, id)
	end
	table.sort(upgradeIds)
	for _, id in upgradeIds do
		local def = Config.Upgrades[id]
		local info = data.upgradeInfo and data.upgradeInfo[id]
		local level = if info then info.level else 0
		local cost = info and info.nextCost
		local button = UIKit.button(if cost then Format.coins(cost) else "MAX", function()
			request(Net.Actions.BuyUpgrade, { upgradeId = id })
		end)
		UIKit.setEnabled(button, cost ~= nil and data.coins >= cost)
		local row = UIKit.row(
			string.format("%s  (Lv %d/%d)", def.displayName, level, if info then info.maxLevel else #def.costs),
			def.description,
			{ button }
		)
		row.LayoutOrder = nextOrder()
		row.Parent = body
	end

	section(body, "Garden", nextOrder())
	local plotButton = UIKit.button(if data.nextPlotCost then Format.coins(data.nextPlotCost) else "MAX", function()
		request(Net.Actions.BuyPlot)
	end)
	UIKit.setEnabled(plotButton, data.nextPlotCost ~= nil and data.coins >= data.nextPlotCost)
	local plotRow = UIKit.row("New Plot", string.format("You own %d of %d", data.ownedPlots, Config.Plots.maxPlots), { plotButton })
	plotRow.LayoutOrder = nextOrder()
	plotRow.Parent = body

	-- Skip-the-wait (developer product) for anything still growing. The shop is
	-- honest about what a skip costs your champion.
	section(body, "Skip the wait", nextOrder())
	UIKit.label(
		string.format(
			"Champion skips left this week: %d. A skipped champion can't win Natural Grown, and care still beats skips.",
			data.championSkipsLeft or 0
		),
		Theme.TextSize.Small,
		{
			LayoutOrder = nextOrder(),
			Font = Theme.FontBody,
			TextColor3 = Theme.Colors.TextMuted,
			TextWrapped = true,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}
	).Parent = body
	local now = ClientState.now()
	local plotIds = {}
	for plotId in data.plots do
		table.insert(plotIds, plotId)
	end
	table.sort(plotIds, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	for _, plotId in plotIds do
		local plant = data.plots[plotId]
		local crop = Config.Crops[plant.cropId]
		if crop then
			local state = GrowthMath.evaluate(plant, crop, Config, now)
			local isChampion = plant.champion == true
			if not state.canHarvest then
				local skip = UIKit.button("Skip", function()
					local result = NetClient.request(Net.Actions.PromptSkip, { plotId = plotId })
					if not result.ok and result.err == "ProductNotConfigured" and RunService:IsStudio() then
						-- Stub product: simulate the purchase in Studio so the loop is testable.
						NetClient.request(Net.Actions.DebugSimulatePurchase, { product = "SkipGrowth", plotId = plotId })
					end
				end, { BackgroundColor3 = Theme.Colors.Gold, TextColor3 = Theme.Colors.Text })
				if isChampion then
					UIKit.setEnabled(skip, (data.championSkipsLeft or 0) > 0, Theme.Colors.Gold)
				end
				local row = UIKit.row(
					if isChampion
						then "Champion · " .. crop.displayName
						else string.format("Plot %s · %s", plotId, crop.displayName),
					"Ripe in "
						.. Format.duration(state.secondsToRipe)
						.. (if isChampion and (plant.paidSkips or 0) == 0 then " · skipping ends Natural Grown" else ""),
					{ skip }
				)
				row.LayoutOrder = nextOrder()
				row.Parent = body
			end
		end
	end
end

renderers.Market = function(body, data)
	local total = 0
	for _, price in data.producePrices or {} do
		total += price
	end
	local sellAll = UIKit.button("Sell All", function()
		request(Net.Actions.SellAll)
	end, { BackgroundColor3 = Theme.Colors.Accent })
	UIKit.setEnabled(sellAll, #data.produce > 0, Theme.Colors.Accent)
	local header = UIKit.row(
		string.format("Basket (%d/%d)", #data.produce, Config.Economy.maxProduceInventory),
		"Worth " .. Format.coins(total) .. " Coins",
		{ sellAll }
	)
	header.LayoutOrder = 0
	header.Parent = body

	-- Heaviest first so fair candidates are on top.
	local items = table.clone(data.produce)
	table.sort(items, function(a, b)
		return a.weight > b.weight
	end)
	for i, item in items do
		local crop = Config.Crops[item.cropId]
		local price = data.producePrices and data.producePrices[tostring(item.uid)] or 0
		local sell = UIKit.button(Format.coins(price), function()
			request(Net.Actions.SellProduce, { uid = item.uid })
		end)
		local enter = UIKit.button("Enter Fair", function()
			FairPanel.pick(item)
		end, { BackgroundColor3 = Theme.Colors.Gold, TextColor3 = Theme.Colors.Text })
		local tags = {}
		if item.isChampion then
			table.insert(tags, if item.name then "Champion \"" .. item.name .. "\"" else "Champion")
		end
		if item.isGiant then
			table.insert(tags, "GIANT")
		end
		if item.gene then
			table.insert(tags, "★ Giant gene")
		end
		local row = UIKit.row(
			string.format("%s · %s", if crop then crop.displayName else item.cropId, Format.weight(item.weight)),
			if #tags > 0 then table.concat(tags, " · ") else nil,
			{ enter, sell }
		)
		row.LayoutOrder = i
		row.Parent = body
	end
end

renderers.Fair = function(body, data)
	FairPanel.render(body, data, function()
		renderPanel("Fair")
	end)
end

renderers.Champion = ChampionPanel.render
renderers.Ribbons = RibbonPanel.render

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------

local function buildHud()
	gui = UIKit.new("ScreenGui", {
		Name = "GVF_UI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})

	-- Top-left: coins + level.
	local stats = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(260, 100),
		Parent = gui,
	}, { UIKit.list(Enum.FillDirection.Vertical, 8) })

	local coinCard = UIKit.card({ Size = UDim2.fromOffset(200, 44), BackgroundColor3 = Theme.Colors.Gold, LayoutOrder = 1 })
	coinsLabel = UIKit.label("0", Theme.TextSize.Large, { Position = UDim2.fromOffset(14, 8) })
	coinsLabel.Parent = coinCard
	coinCard.Parent = stats

	local levelCard = UIKit.card({ Size = UDim2.fromOffset(200, 30), LayoutOrder = 2, ClipsDescendants = true })
	local levelFill = UIKit.new("Frame", {
		BackgroundColor3 = Theme.Colors.Primary,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = levelCard,
	}, { UIKit.corner() })
	local levelLabel = UIKit.label("Lv 1", Theme.TextSize.Small, {
		Position = UDim2.fromOffset(10, 6),
		ZIndex = 2,
	})
	levelLabel.Parent = levelCard
	levelCard.Parent = stats
	LevelBar.mount(levelCard, levelFill, levelLabel)

	-- Right: menu buttons.
	local menu = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(120, 260),
		Parent = gui,
	}, { UIKit.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right) })
	local menuEntries = {
		{ "Shop", "Shop" },
		{ "Basket", "Market" },
		{ "Fairs", "Fair" },
		{ "Champion", "Champion" },
		{ "Ribbons", "Ribbons" },
	}
	for i, entry in menuEntries do
		local b = UIKit.button(entry[1], function()
			if openPanel == entry[2] then
				UIController.close()
			else
				UIController.open(entry[2])
			end
		end, { LayoutOrder = i })
		b.Parent = menu
	end

	-- Bottom: seed picker.
	seedBar = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(700, 48),
		Parent = gui,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })

	-- Top-center: toasts.
	toastHolder = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(500, 300),
		Parent = gui,
	}, { UIKit.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })

	local titles = { Shop = "Shop", Market = "Basket", Fair = "Weigh-In Fairs", Champion = "Your Champion", Ribbons = "Ribbon Shed" }
	for name, title in titles do
		local panel, body = UIKit.panel(title, UDim2.fromScale(0.6, 0.7), UIController.close)
		panel.Parent = gui
		panels[name] = panel
		panelBodies[name] = body
	end
end

local function renderSeedBar(data: { [string]: any })
	for _, child in seedBar:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for i, crop in cropOrder() do
		local count = data.seeds[crop.id] or 0
		if data.level >= crop.unlockLevel and (count > 0 or crop.seedCost == 0) then
			local selected = data.selectedSeed == crop.id
			local text = crop.displayName .. "  " .. (if crop.seedCost == 0 then "∞" else "x" .. count)
			local button = UIKit.button(text, function()
				request(Net.Actions.SelectSeed, { cropId = crop.id })
			end, {
				LayoutOrder = i,
				Size = UDim2.fromOffset(130, 44),
				BackgroundColor3 = if selected then Theme.Colors.PrimaryDark else Theme.Colors.Surface,
				TextColor3 = if selected then Theme.Colors.TextOnPrimary else Theme.Colors.Text,
			})
			button.Parent = seedBar
		end
	end
end

local function onState(data: { [string]: any }, previous: { [string]: any }?)
	-- Coins count up/down smoothly instead of snapping.
	Tweens.countTo(coinsLabel, shownCoins, data.coins, function(n)
		return Format.coins(math.floor(n + 0.5))
	end)
	if previous and data.coins ~= previous.coins then
		Tweens.pop(coinsLabel.Parent :: GuiObject, if data.coins > previous.coins then 0.12 else 0.06)
	end
	shownCoins = data.coins

	-- The bar waits for any essence still in the air, then settles.
	LevelBar.setTarget(data.level, data.xp, data.xpToNext or 1)

	renderSeedBar(data)
	if openPanel then
		renderPanel(openPanel)
	end
end

local function onFeel(name: string, ctx: { [string]: any })
	local C = Theme.Colors
	if name == Net.Feedback.Harvested then
		local crop = Config.Crops[ctx.cropId]
		local text = string.format("%s%s %s!", if ctx.isGiant then "GIANT " else "", crop and crop.displayName or "", Format.weight(ctx.weight))
		UIController.toast(text, if ctx.isGiant then C.Accent else C.Primary)
		if ctx.isRecord then
			UIController.toast("New personal record!", C.Gold)
		end
		if ctx.xp and ctx.xp > 0 then
			LevelBar.essence(ctx.position, ctx.xp)
		end
	elseif name == Net.Feedback.Sold then
		UIController.toast("+" .. Format.coins(ctx.coins) .. " Coins", C.Gold)
	elseif name == Net.Feedback.FriendWateredYou then
		UIController.toast(ctx.friendName .. " watered your garden!", C.Primary)
	elseif name == Net.Feedback.YouWateredFriend then
		UIController.toast(string.format("Watered %s's garden! +%d Coins", ctx.ownerName, ctx.coins), C.Primary)
		if ctx.xp and ctx.xp > 0 then
			LevelBar.essence(ctx.position, ctx.xp)
		end
	elseif name == Net.Feedback.LevelUp then
		UIController.toast("Level " .. ctx.level .. "!", C.Accent, 3.5)
	elseif name == Net.Feedback.FairEntered then
		local text = string.format("Entered the %s with %s!", ctx.fairName or "fair", Format.weight(ctx.weight))
		UIController.toast(text, C.Gold)
		if ctx.divisions and #ctx.divisions > 1 then
			UIController.toast("Competing in " .. table.concat(ctx.divisions, ", "), C.PrimaryDark, 3.5)
		end
	elseif name == Net.Feedback.FairReward then
		FairPanel.showResults(ctx)
	elseif name == Net.Feedback.ServerPrize then
		local places = { "1st", "2nd", "3rd" }
		UIController.toast(
			string.format("%s place on the %s stage! +%s Coins", places[ctx.place] or "Top", ctx.fairName or "fair", Format.coins(ctx.coins)),
			C.Gold,
			5
		)
	elseif name == Net.Feedback.MailReceived then
		local text = ctx.note or "You got mail!"
		if ctx.coins and ctx.coins > 0 then
			text ..= " +" .. Format.coins(ctx.coins) .. " Coins"
		end
		UIController.toast(text, C.Gold, 5)
		if ctx.ribbon then
			UIController.toast(RibbonNames.describe(ctx.ribbon), C.Accent, 5)
		end
	elseif name == Net.Feedback.CareNeeded then
		local crop = Config.Crops[ctx.cropId]
		local who = if ctx.ownerUserId == localPlayer.UserId then "Your champion" else "Your team's champion"
		UIController.toast(string.format("%s %s %s", who, crop and crop.displayName or "", CARE_NEEDED[ctx.kind] or "needs you!"), C.Accent, 4)
		if openPanel == "Champion" then
			renderPanel("Champion")
		end
	elseif name == Net.Feedback.CareDone then
		local mine = ctx.carerUserId == localPlayer.UserId
		local who = if mine then "You" else (ctx.carerName or "A friend")
		local bonus = if ctx.credit and ctx.credit < 1 then " (a bit late, still counts!)" else "!"
		UIController.toast(string.format("%s %s the champion%s", who, CARE_DONE[ctx.kind] or "cared for", bonus), C.Primary)
		if mine and ctx.xp and ctx.xp > 0 then
			LevelBar.essence(ctx.position, ctx.xp)
		end
		if openPanel == "Champion" then
			renderPanel("Champion")
		end
	elseif name == Net.Feedback.ChampionNamed then
		UIController.toast("Say hello to " .. ctx.name .. "!", C.Accent)
	elseif name == Net.Feedback.CoGrowInvite then
		ChampionPanel.showInvite(ctx)
	elseif name == Net.Feedback.CoGrowJoined then
		local text = if ctx.ownerUserId == localPlayer.UserId
			then ctx.coGrowerName .. " is growing your champion with you!"
			else "You're growing " .. ctx.ownerName .. "'s champion together!"
		UIController.toast(text, C.Primary, 4)
	elseif name == Net.Feedback.StageChanged and ctx.to == "Giant" then
		local crop = Config.Crops[ctx.cropId]
		UIController.toast("Your " .. (crop and crop.displayName or "crop") .. " became a GIANT!", C.Accent)
	elseif name == Net.Feedback.WelcomeBack then
		local readyCount = #(ctx.ready or {})
		local text = string.format("Welcome back! You were away %s.", Format.duration(ctx.offlineSeconds))
		UIController.toast(text, C.Primary, 4)
		if readyCount > 0 then
			UIController.toast(
				string.format("%d crop%s ready to harvest%s!", readyCount, if readyCount == 1 then "" else "s", if ctx.giants > 0 then string.format(" (%d GIANT)", ctx.giants) else ""),
				C.Accent,
				5
			)
		end
	elseif name == Net.Feedback.Denied then
		local reason = REASONS[ctx.reason or ""]
		if reason then
			local extra = if ctx.wait and ctx.wait > 0 then " (" .. Format.duration(ctx.wait) .. ")" else ""
			UIController.toast(reason .. extra, nil, 2)
		end
	end
end

function UIController.start()
	buildHud()
	Modal.parent = localPlayer:WaitForChild("PlayerGui")
	ClientState.Changed:Connect(onState)
	ClientState.LeaderboardChanged:Connect(function()
		if openPanel == "Fair" then
			renderPanel("Fair")
		end
	end)
	FeelController.Played:Connect(onFeel)
	GardenController.PanelRequested:Connect(UIController.open)
end

return UIController
