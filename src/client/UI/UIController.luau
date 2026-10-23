--!strict
--[[
	UIController: owns the screens and routes game events to them.

	HUD:     UI/Hud (coins, level bar, menu with badges, seed hotbar, toasts).
	Panels:  Shop, Basket (Market), Fairs, Champion, Ribbons. One open at a
	         time, over a dimmed, blurred backdrop. Tap outside, press X or
	         gamepad B to close. Opening another panel cross-fades.
	Modals:  fair picker, results / replay cards, co-grow invites, naming (UI/Modal).

	Panels re-render from ClientState whenever a snapshot arrives, keeping
	their scroll position. Every number the UI shows comes from the server
	snapshot so the client never duplicates game rules.

	Extending: UIController.registerPanel("Settings", { title = ..., render = ... })
	adds a panel (G10 settings, M4 store, R4 streak) with the same open/close feel.
	Hooks for effects: UIController.target(name) returns the HUD element to fly
	things into, and Opened / Closed fire with the panel name.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local GrowthMath = require(Shared.GrowthMath)
local CareMath = require(Shared.CareMath)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local FeelController = require(script.Parent.Parent.Feel.FeelController)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local GardenController = require(script.Parent.Parent.Controllers.GardenController)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local Scale = require(script.Parent.Scale)
local Toasts = require(script.Parent.Toasts)
local Hud = require(script.Parent.Hud)
local Modal = require(script.Parent.Modal)
local LevelBar = require(script.Parent.LevelBar)
local ShopPanel = require(script.Parent.ShopPanel)
local BasketPanel = require(script.Parent.BasketPanel)
local BackpackPanel = require(script.Parent.BackpackPanel)
local ToolsPanel = require(script.Parent.ToolsPanel)
local SettingsPanel = require(script.Parent.SettingsPanel)
local Icons = require(script.Parent.Icons)
local PromptUI = require(script.Parent.PromptUI)
local FairPanel = require(script.Parent.FairPanel)
local ChampionPanel = require(script.Parent.ChampionPanel)
local RibbonPanel = require(script.Parent.RibbonPanel)
local RibbonNames = require(script.Parent.RibbonNames)

local UIController = {}

UIController.Opened = Signal.new() -- (panelName)
UIController.Closed = Signal.new() -- (panelName)

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
	PlotTaken = "Someone just took that plot. Pick another!",
	NoFreePlot = "Every plot is taken right now.",
	NothingPlanted = "Nothing is planted there yet.",
	NoPests = "No bugs on this one!",
	TooFar = "Get a little closer to the plant!",
	NoPlot = "Stand next to a plant to use that.",
	AlreadyFertilized = "This plant was already fertilized.",
	NoFertilizer = "Out of fertilizer. Buy more at the Seed Shop!",
	NotYourPlot = "You can only fertilize your own plants.",
	UseBucket = "Equip the Watering Bucket and click the plant to water it!",
	ClickCrop = "Click the crop you want to water.",
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

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------

-- Kept for existing callers. priority: "Low" | "Normal" | "High".
function UIController.toast(text: string, color: Color3?, duration: number?, priority: Toasts.Priority?)
	Toasts.push(text, { color = color, duration = duration, priority = priority })
end

-- A notification card: kind sets colour and icon (Success / Info / Reward / Warning / Error).
function UIController.notify(kind: Toasts.Kind, text: string, subtitle: string?, icon: string?, priority: Toasts.Priority?)
	Toasts.push(text, { kind = kind, subtitle = subtitle, icon = icon, priority = priority, duration = 3 })
end

local function plural(count: number, word: string): string
	return if count == 1 then word else word .. "s"
end

-- "You bought ..." card for a Purchased feedback event.
local function notifyPurchase(ctx: { [string]: any })
	local amount = ctx.amount or 1
	if ctx.kind == "Seed" then
		local crop = Config.Crops[ctx.cropId]
		local name = if crop then crop.displayName else ""
		UIController.notify(
			"Success",
			string.format("You bought %s %s!", name, plural(amount, "Seed")),
			string.format("+%d %s %s", amount, name, plural(amount, "Seed")),
			Icons.forSlot("Seed_" .. tostring(ctx.cropId))
		)
	elseif ctx.kind == "Supply" then
		local def = Config.Supplies[ctx.supplyId]
		local name = if def then def.displayName else "supplies"
		UIController.notify("Success", "You bought " .. name .. "!", "+" .. amount .. " " .. name, Icons.forSlot("Supply_" .. tostring(ctx.supplyId)))
	elseif ctx.kind == "Upgrade" then
		local def = Config.Upgrades[ctx.upgradeId]
		UIController.notify("Info", "Upgrade bought!", string.format("%s is now level %d", if def then def.displayName else "", ctx.level or 1), "Upgrades")
	elseif ctx.kind == "Plot" then
		UIController.notify("Success", "New plot unlocked!", "Plot " .. tostring(ctx.plotId) .. " is ready to plant", "Plot")
	elseif ctx.kind == "Coins" then
		UIController.notify("Reward", "+" .. Format.coins(amount) .. " Coins!", nil, "Coins", "High")
	end
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

export type PanelSpec = {
	title: string,
	glyph: string?,
	accent: Color3?,
	tabs: { UIKit.TabItem }?,
	defaultTab: string?,
	render: (body: ScrollingFrame, data: { [string]: any }, tab: string?) -> (),
}

type PanelState = {
	group: CanvasGroup,
	body: ScrollingFrame,
	tab: string?,
	tabs: UIKit.Tabs?,
}

local specs: { [string]: PanelSpec } = {}
local panels: { [string]: PanelState } = {}
local panelRoot: Frame? = nil
local backdrop: TextButton? = nil
local blur: BlurEffect? = nil
local openPanel: string? = nil
local seenRibbons: number? = nil

local CLOSE_ACTION = "GVF_ClosePanel"
local BLUR_SIZE = 12

local function clearBody(body: ScrollingFrame)
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function renderPanel(name: string, keepScroll: boolean?)
	local data = ClientState.data
	local state = panels[name]
	local spec = specs[name]
	if not data or not state or not spec then
		return
	end
	local scroll = state.body.CanvasPosition
	clearBody(state.body)
	spec.render(state.body, data, state.tab)
	if keepScroll then
		-- The canvas re-measures next frame; put the scroll back after it does.
		state.body.CanvasPosition = scroll
		task.defer(function()
			state.body.CanvasPosition = scroll
		end)
	end
end

local function buildPanel(name: string, spec: PanelSpec)
	local parent = panelRoot
	if not parent or panels[name] then
		return
	end
	local group, body = UIKit.panel(spec.title, UDim2.new(0.94, 0, 0.88, 0), UIController.close, {
		accent = spec.accent or Theme.PanelAccent[name],
		artSlot = "PanelIcon_" .. name,
		glyph = spec.glyph,
	})
	group.Name = name
	group.ZIndex = 2
	group.Parent = parent
	local state: PanelState = { group = group, body = body, tab = spec.defaultTab, tabs = nil }
	if spec.tabs then
		state.tab = spec.defaultTab or spec.tabs[1].id
		state.tabs = UIKit.panelTabs(group, spec.tabs, state.tab :: string, function(id)
			state.tab = id
			body.CanvasPosition = Vector2.zero
			renderPanel(name)
			local rows = {}
			for _, child in body:GetChildren() do
				if child:IsA("GuiObject") and #rows < 8 then
					table.insert(rows, child)
				end
			end
			Tweens.stagger(rows, 0.02, 0.94)
		end)
	end
	panels[name] = state
end

function UIController.registerPanel(name: string, spec: PanelSpec)
	specs[name] = spec
	buildPanel(name, spec)
end

local function setBackdrop(visible: boolean)
	local dim = backdrop
	if dim then
		if visible then
			dim.Visible = true
			Tweens.play(dim, Tweens.Ease.Fade, { BackgroundTransparency = 0.55 })
		else
			local tween = Tweens.play(dim, Tweens.Ease.PanelOut, { BackgroundTransparency = 1 })
			if tween then
				tween.Completed:Once(function()
					if not openPanel then
						dim.Visible = false
					end
				end)
			else
				dim.Visible = false
			end
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		if not blur or blur.Parent ~= camera then
			blur = UIKit.new("BlurEffect", { Name = "GVF_PanelBlur", Size = 0, Parent = camera })
		end
		Tweens.play(blur :: BlurEffect, if visible then Tweens.Ease.Slide else Tweens.Ease.PanelOut, {
			Size = if visible then BLUR_SIZE else 0,
		})
	end
end

local function firstSelectable(root: Instance): GuiObject?
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and d.Visible and d.Name ~= "Close" then
			return d
		end
	end
	return nil
end

function UIController.open(name: string, tab: string?)
	local state = panels[name]
	if not state then
		return
	end
	if openPanel == name then
		if tab and state.tabs and state.tab ~= tab then
			state.tab = tab
			state.tabs.select(tab)
			renderPanel(name)
		end
		return
	end
	local previous = openPanel
	if previous then
		-- Switching panels: the old one leaves, the backdrop and blur stay.
		Tweens.closePanel(panels[previous].group)
		UIController.Closed:Fire(previous)
	else
		setBackdrop(true)
		Hud.setDockHidden(true)
		ContextActionService:BindAction(CLOSE_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				UIController.close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB)
	end
	openPanel = name
	if tab and state.tabs then
		state.tab = tab
		state.tabs.select(tab, false)
	end
	state.body.CanvasPosition = Vector2.zero
	renderPanel(name)
	Tweens.openPanel(state.group)
	local rows = {}
	for _, child in state.body:GetChildren() do
		if child:IsA("GuiObject") and #rows < 10 then
			table.insert(rows, child)
		end
	end
	Tweens.stagger(rows, 0.03)
	FeelController.play("PanelOpen")

	if name == "Ribbons" and ClientState.data then
		local total = 0
		for _, count in ClientState.data.ribbons or {} do
			total += count
		end
		seenRibbons = total
		Hud.setBadge("Ribbons", false)
	end
	if UIKit.usingGamepad() then
		GuiService.SelectedObject = firstSelectable(state.group)
	end
	UIController.Opened:Fire(name)
end

function UIController.close()
	local name = openPanel
	if not name then
		return
	end
	openPanel = nil
	Tweens.closePanel(panels[name].group)
	setBackdrop(false)
	Hud.setDockHidden(false)
	ContextActionService:UnbindAction(CLOSE_ACTION)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panels[name].group) then
		GuiService.SelectedObject = nil
	end
	FeelController.play("PanelClose")
	UIController.Closed:Fire(name)
end

-- Opens a panel (on `tab` if given), or closes it when it is already showing that tab.
function UIController.toggle(name: string, tab: string?)
	local state = panels[name]
	if openPanel == name and (tab == nil or (state and state.tab == tab)) then
		UIController.close()
	else
		UIController.open(name, tab)
	end
end

function UIController.isOpen(name: string?): boolean
	return if name then openPanel == name else openPanel ~= nil
end

-- HUD element to fly effects into: "Coins", "Level", "Seeds" or a menu panel name.
function UIController.target(name: string): GuiObject?
	return Hud.target(name)
end

---------------------------------------------------------------------------
-- Built-in panels
---------------------------------------------------------------------------

local function registerBuiltIns()
	UIController.registerPanel("Shop", {
		title = "Shop",
		tabs = ShopPanel.TABS,
		defaultTab = "seeds",
		render = ShopPanel.render,
	})
	UIController.registerPanel("Market", {
		title = "Basket",
		glyph = "B",
		render = BasketPanel.render,
	})
	UIController.registerPanel("Fair", {
		title = "Weigh-In Fairs",
		glyph = "F",
		tabs = FairPanel.TABS,
		defaultTab = FairPanel.DEFAULT_TAB,
		render = FairPanel.render,
	})
	UIController.registerPanel("Champion", {
		title = "Your Champion",
		glyph = "C",
		render = ChampionPanel.render,
	})
	UIController.registerPanel("Ribbons", {
		title = "Ribbon Shed",
		glyph = "R",
		render = RibbonPanel.render,
	})
	UIController.registerPanel("Backpack", {
		title = "Backpack",
		glyph = "B",
		tabs = BackpackPanel.TABS,
		defaultTab = "seeds",
		render = BackpackPanel.render,
	})
	UIController.registerPanel("Tools", {
		title = "Garden Tools",
		glyph = "T",
		render = ToolsPanel.render,
	})
	UIController.registerPanel("Settings", {
		title = "Settings",
		glyph = "S",
		render = SettingsPanel.render,
	})
	BackpackPanel.open = UIController.open
	ToolsPanel.open = UIController.open
	ToolsPanel.close = UIController.close
	SettingsPanel.refresh = function()
		renderPanel("Settings", true)
	end
end

local function buildPanels(playerGui: Instance)
	local gui = UIKit.new("ScreenGui", {
		Name = "GVF_Panels",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layer.Panels,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	local root = Scale.root(gui, "Panels")
	backdrop = UIKit.new("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 1,
		Parent = root,
	});
	(backdrop :: TextButton).Activated:Connect(UIController.close)
	panelRoot = root
	for name, spec in specs do
		buildPanel(name, spec)
	end
end

---------------------------------------------------------------------------
-- State and badges
---------------------------------------------------------------------------

local function updateBadges()
	local data = ClientState.data
	if not data then
		return
	end
	-- Champion: something to care for right now.
	local champion = data.plots and data.plots[Config.Champion.plotId]
	local crop = champion and Config.Crops[champion.cropId]
	local needsCare = false
	if champion and crop then
		local need = CareMath.pendingNeed(champion, Config.Champion, ClientState.now(), function(t)
			return GrowthMath.evaluate(champion, crop, Config, t).canHarvest
		end)
		needsCare = need ~= nil
	end
	Hud.setBadge("Champion", needsCare)

	-- Fairs: a fair is waiting for an entry and you have something to enter.
	local fairWaiting = false
	if #(data.produce or {}) > 0 then
		for id, info in data.fairs or {} do
			local entries = data.fair and data.fair.entries and data.fair.entries[id]
			if not (entries and entries[tostring(info.id)]) then
				fairWaiting = true
			end
		end
	end
	Hud.setBadge("Fair", fairWaiting)

	-- Ribbons: how many arrived since the shed was last opened.
	local total = 0
	for _, count in data.ribbons or {} do
		total += count
	end
	if seenRibbons == nil then
		seenRibbons = total
	end
	Hud.setBadge("Ribbons", if openPanel == "Ribbons" then false else total - (seenRibbons :: number))
end

local function onState(data: { [string]: any }, _previous: { [string]: any }?)
	Hud.render(data)
	updateBadges()
	if openPanel then
		renderPanel(openPanel, true)
	end
end

-- Where a "flies from" effect starts: the button just pressed, else nil (bottom center).
local function pressOrigin(): Vector2?
	if os.clock() - UIKit.lastPress.at < 1.5 then
		return UIKit.lastPress.point
	end
	return nil
end

local function onFeel(name: string, ctx: { [string]: any })
	local C = Theme.Colors
	local toast = UIController.toast
	if name == Net.Feedback.Harvested then
		local crop = Config.Crops[ctx.cropId]
		local text = string.format(
			"%s%s %s!",
			if ctx.isGiant then "GIANT " else "",
			crop and crop.displayName or "",
			Format.weight(ctx.weight)
		)
		toast(text, if ctx.isGiant then C.Accent else C.Primary, nil, if ctx.isGiant then "High" else "Normal")
		if ctx.isRecord then
			toast("New personal record!", C.Gold, 3, "High")
		end
		if ctx.xp and ctx.xp > 0 then
			LevelBar.essence(ctx.position, ctx.xp)
		end
		Hud.celebrate("Market", nil, if ctx.isGiant then 0.25 else 0.12)
	elseif name == Net.Feedback.Sold then
		Hud.coinBurst(ctx.coins or 0, pressOrigin())
		UIController.notify("Reward", "You earned " .. Format.coins(ctx.coins or 0) .. " Coins!", "From selling your crops", "Coins")
	elseif name == Net.Feedback.Purchased then
		notifyPurchase(ctx)
	elseif name == Net.Feedback.PestsAppeared then
		local crop = Config.Crops[ctx.cropId]
		UIController.notify("Warning", string.format("Bugs on your %s!", crop and crop.displayName or "crop"), "Use the Pest Remover", "Bugs", "High")
	elseif name == Net.Feedback.PestsRemoved then
		local helped = ctx.helperName ~= nil and ctx.ownerUserId == localPlayer.UserId and ctx.helperName ~= localPlayer.DisplayName
		if helped then
			UIController.notify("Success", ctx.helperName .. " got rid of your bugs!", nil, "Bugs")
		else
			UIController.notify("Success", "Bugs gone!", if ctx.coins then "+" .. ctx.coins .. " Coins for helping" else nil, "Bugs")
			if ctx.xp and ctx.xp > 0 then
				LevelBar.essence(ctx.position, ctx.xp)
			end
		end
	elseif name == Net.Feedback.Fertilized then
		UIController.notify("Success", "Fertilized!", string.format("%d bag%s left", ctx.bagsLeft or 0, if ctx.bagsLeft == 1 then "" else "s"), "Fertilizer")
		if ctx.xp and ctx.xp > 0 then
			LevelBar.essence(ctx.position, ctx.xp)
		end
	elseif name == Net.Feedback.FriendWateredYou then
		toast(ctx.friendName .. " watered your garden!", C.Primary)
	elseif name == Net.Feedback.YouWateredFriend then
		toast(string.format("Watered %s's garden! +%d Coins", ctx.ownerName, ctx.coins), C.Primary)
		if ctx.xp and ctx.xp > 0 then
			LevelBar.essence(ctx.position, ctx.xp)
		end
	elseif name == Net.Feedback.LevelUp then
		toast("Level " .. ctx.level .. "!", C.Accent, 3.5, "High")
		Hud.celebrate("Level", C.Gold, 0.3)
	elseif name == Net.Feedback.FairEntered then
		local text = string.format("Entered the %s with %s!", ctx.fairName or "fair", Format.weight(ctx.weight))
		toast(text, C.Gold)
		if ctx.divisions and #ctx.divisions > 1 then
			toast("Competing in " .. table.concat(ctx.divisions, ", "), C.PrimaryDark, 3.5, "Low")
		end
	elseif name == Net.Feedback.FairReward then
		FairPanel.showResults(ctx)
	elseif name == Net.Feedback.ServerPrize then
		Hud.celebrate("Coins", C.Gold, 0.25)
		local places = { "1st", "2nd", "3rd" }
		toast(
			string.format(
				"%s place on the %s stage! +%s Coins",
				places[ctx.place] or "Top",
				ctx.fairName or "fair",
				Format.coins(ctx.coins)
			),
			C.Gold,
			5,
			"High"
		)
	elseif name == Net.Feedback.MailReceived then
		local text = ctx.note or "You got mail!"
		if ctx.coins and ctx.coins > 0 then
			text ..= " +" .. Format.coins(ctx.coins) .. " Coins"
		end
		toast(text, C.Gold, 5, "High")
		if ctx.ribbon then
			toast(RibbonNames.describe(ctx.ribbon), C.Accent, 5)
		end
	elseif name == Net.Feedback.CareNeeded then
		local crop = Config.Crops[ctx.cropId]
		local who = if ctx.ownerUserId == localPlayer.UserId then "Your champion" else "Your team's champion"
		toast(
			string.format("%s %s %s", who, crop and crop.displayName or "", CARE_NEEDED[ctx.kind] or "needs you!"),
			C.Accent,
			4,
			"High"
		)
		updateBadges()
		if openPanel == "Champion" then
			renderPanel("Champion", true)
		end
	elseif name == Net.Feedback.CareDone then
		local mine = ctx.carerUserId == localPlayer.UserId
		local who = if mine then "You" else (ctx.carerName or "A friend")
		local bonus = if ctx.credit and ctx.credit < 1 then " (a bit late, still counts!)" else "!"
		toast(string.format("%s %s the champion%s", who, CARE_DONE[ctx.kind] or "cared for", bonus), C.Primary)
		if mine and ctx.xp and ctx.xp > 0 then
			LevelBar.essence(ctx.position, ctx.xp)
		end
		updateBadges()
		if openPanel == "Champion" then
			renderPanel("Champion", true)
		end
	elseif name == Net.Feedback.ChampionNamed then
		toast("Say hello to " .. ctx.name .. "!", C.Accent)
	elseif name == Net.Feedback.CoGrowInvite then
		ChampionPanel.showInvite(ctx)
	elseif name == Net.Feedback.CoGrowJoined then
		local text = if ctx.ownerUserId == localPlayer.UserId
			then ctx.coGrowerName .. " is growing your champion with you!"
			else "You're growing " .. ctx.ownerName .. "'s champion together!"
		toast(text, C.Primary, 4, "High")
	elseif name == Net.Feedback.StageChanged and ctx.to == "Giant" then
		local crop = Config.Crops[ctx.cropId]
		toast("Your " .. (crop and crop.displayName or "crop") .. " became a GIANT!", C.Accent, nil, "High")
	elseif name == Net.Feedback.WelcomeBack then
		local readyCount = #(ctx.ready or {})
		toast(string.format("Welcome back! You were away %s.", Format.duration(ctx.offlineSeconds)), C.Primary, 4)
		if readyCount > 0 then
			toast(
				string.format(
					"%d crop%s ready to harvest%s!",
					readyCount,
					if readyCount == 1 then "" else "s",
					if ctx.giants > 0 then string.format(" (%d GIANT)", ctx.giants) else ""
				),
				C.Accent,
				5
			)
		end
	elseif name == Net.Feedback.Denied then
		local reason = REASONS[ctx.reason or ""]
		if reason then
			local extra = if ctx.wait and ctx.wait > 0 then " (" .. Format.duration(ctx.wait) .. ")" else ""
			Toasts.push(reason .. extra, { kind = "Error", duration = 2, priority = "Low" })
		end
	end
end

function UIController.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	Hud.build(playerGui, UIController.toggle, function(cropId)
		task.spawn(NetClient.request, Net.Actions.SelectSeed, { cropId = cropId })
	end)
	buildPanels(playerGui)
	registerBuiltIns()
	PromptUI.start(playerGui)
	Modal.parent = playerGui
	UIKit.onDisabledPress = function(reason)
		UIController.toast(reason, nil, 2, "Low")
	end

	ClientState.Changed:Connect(onState)
	ClientState.LeaderboardChanged:Connect(function()
		if openPanel == "Fair" then
			renderPanel("Fair", true)
		end
	end)
	FeelController.Played:Connect(onFeel)
	GardenController.PanelRequested:Connect(function(name)
		UIController.open(name)
	end)
	-- Care needs appear on a clock, so check the badges now and then.
	task.spawn(function()
		while true do
			task.wait(1)
			updateBadges()
		end
	end)
end

return UIController
