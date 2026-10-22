--!strict
--[[
	FairDayController: the live weigh-in show on the client.

	Listens to the FairDay remote (FairDayService) and plays each phase:
	  Announce  countdown banner
	  Gather    letterbox bars, camera glides to the stage, title card
	  Weigh     entry card with a weight count-up and a drumroll; the veggie
	            (placeholder ball) drops onto the scale
	  Awards    podium cards pop in one by one, winner last, confetti hook
	  Global    the top three across all servers
	  Empty     small-server card when nobody here entered
	  Idle      everything eases away, camera returns

	The daily and weekly shows take the camera; the hourly show is a compact
	overlay with a "Watch the stage" button so it never interrupts play.
	Anyone can step back with "Back to garden" at any time.

	Art seams: a pre-built Workspace.FairStage (Floor, Scale, CameraPoint) is
	used as-is; crop art from ReplicatedStorage.Assets.Crops appears on the
	scale via CropVisuals.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local NetClient = require(script.Parent.Parent.NetClient)
local FeelController = require(script.Parent.Parent.Feel.FeelController)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local CropVisuals = require(script.Parent.CropVisuals)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Scale = require(script.Parent.Parent.UI.Scale)

local FairDayController = {}

local localPlayer = Players.LocalPlayer
local PLACES = { "1st", "2nd", "3rd" }
local LETTERBOX = 0.09
local CAMERA_GLIDE = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local gui: ScreenGui
local topBar: Frame
local bottomBar: Frame
local banner: Frame
local bannerText: TextLabel
local stageCard: CanvasGroup
local watchButton: TextButton
local phase = "Idle"
local showFair: string? = nil
local watching = false -- camera is on the stage
local optedOut = false -- player chose "Back to garden" for this show
local stageVeggie: Model? = nil
local token = 0 -- bumps on every phase so stale loops stop

local function cropName(cropId: string?): string
	local crop = cropId and Config.Crops[cropId]
	return if crop then crop.displayName else ""
end

local function stagePart(name: string): BasePart?
	local stage = workspace:FindFirstChild("FairStage")
	local part = stage and stage:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

---------------------------------------------------------------------------
-- Camera and letterbox
---------------------------------------------------------------------------

local function setLetterbox(on: boolean)
	local h = if on then LETTERBOX else 0
	Tweens.play(topBar, Tweens.Ease.Slide, { Size = UDim2.fromScale(1, h) })
	Tweens.play(bottomBar, Tweens.Ease.Slide, { Size = UDim2.fromScale(1, h) })
end

local function updateWatchButton()
	watchButton.Visible = phase ~= "Idle" and phase ~= "Announce"
	watchButton.Text = if watching then "Back to garden" else "Watch the stage"
end

local function watchStage()
	local camera = workspace.CurrentCamera
	local point = stagePart("CameraPoint")
	if not camera or not point or watching then
		return
	end
	watching = true
	camera.CameraType = Enum.CameraType.Scriptable
	Tweens.play(camera, CAMERA_GLIDE, { CFrame = point.CFrame })
	setLetterbox(true)
	updateWatchButton()
end

local function leaveStage()
	if not watching then
		return
	end
	watching = false
	setLetterbox(false)
	updateWatchButton()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- Glide back behind the character before handing the camera back.
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tween = if root
		then Tweens.play(camera, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			CFrame = CFrame.lookAt(root.Position - root.CFrame.LookVector * 14 + Vector3.new(0, 7, 0), root.Position),
		})
		else nil
	local function release()
		if not watching then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
	if tween then
		tween.Completed:Once(release)
	else
		release()
	end
end

---------------------------------------------------------------------------
-- Stage veggie (placeholder ball or crop art)
---------------------------------------------------------------------------

local function clearVeggie()
	if stageVeggie then
		stageVeggie:Destroy()
		stageVeggie = nil
	end
end

local function placeVeggie(cropId: string, weight: number)
	clearVeggie()
	local scalePart = stagePart("Scale")
	if not scalePart then
		return
	end
	local visual = CropVisuals.create(cropId)
	local size = CropVisuals.targetScale(weight)
	local top = scalePart.Position.Y + math.min(scalePart.Size.X, scalePart.Size.Y) / 2
	-- The anchor sits beside the crop model (not inside it) so art scaling never moves it.
	local holder = Instance.new("Model")
	holder.Name = "FairStageVeggie"
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(4, 0.2, 4)
	anchor.CFrame = CFrame.new(scalePart.Position.X, top, scalePart.Position.Z)
	anchor.Parent = holder
	visual.root.Parent = holder
	holder.Parent = workspace
	stageVeggie = holder

	-- Drop in from above with a springy landing.
	local myToken = token
	task.spawn(function()
		local start = os.clock()
		local duration = if Tweens.reducedMotion then 0 else 0.7
		while stageVeggie == holder and token == myToken do
			local t = if duration > 0 then math.clamp((os.clock() - start) / duration, 0, 1) else 1
			-- Back-out ease: overshoot a touch, then settle.
			local c = 1.70158
			local eased = 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
			local drop = (1 - math.min(1, t * 1.4)) * 12
			CropVisuals.apply(visual, anchor, size * math.max(0.05, eased), "Ripe")
			if drop > 0 then
				visual.root:PivotTo(visual.root:GetPivot() + Vector3.new(0, drop, 0))
			end
			if t >= 1 then
				return
			end
			task.wait()
		end
	end)
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------

local function clearStageCard()
	for _, child in stageCard:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UICorner") and not child:IsA("UIStroke") and not child:IsA("UIScale") then
			child:Destroy()
		end
	end
end

local function showStageCard(build: (card: CanvasGroup) -> ())
	clearStageCard()
	build(stageCard)
	if not stageCard.Visible then
		Tweens.openPanel(stageCard)
	else
		Tweens.pop(stageCard, 0.06)
	end
end

local function hideStageCard()
	if stageCard.Visible then
		Tweens.closePanel(stageCard)
	end
end

local function line(text: string, size: number, order: number, props: { [string]: any }?): TextLabel
	local label = UIKit.label(text, size, {
		LayoutOrder = order,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	for k, v in props or {} do
		(label :: any)[k] = v
	end
	label.Parent = stageCard
	return label
end

local function entryTitle(entry: { [string]: any }): string
	local who = if entry.userId == localPlayer.UserId then "Your" else (entry.ownerName or "?") .. "'s"
	local name = if entry.championName then string.format(" \"%s\"", entry.championName) else ""
	return string.format("%s %s%s", who, cropName(entry.cropId), name)
end

local function showBanner(text: string)
	bannerText.Text = text
	if not banner.Visible then
		Tweens.openPanel(banner)
	end
end

local function hideBanner()
	if banner.Visible then
		Tweens.closePanel(banner)
	end
end

---------------------------------------------------------------------------
-- Phases
---------------------------------------------------------------------------

local function countdown(endsAt: number, format: (seconds: number) -> string)
	local myToken = token
	task.spawn(function()
		while token == myToken do
			showBanner(format(math.max(0, endsAt - ClientState.now())))
			task.wait(0.5)
		end
	end)
end

local function onGather(state: { [string]: any })
	FeelController.play("FairDayStart")
	if not optedOut and state.fair ~= "hourly" then
		watchStage()
	end
	showStageCard(function()
		line(state.fairName .. " is starting!", Theme.TextSize.Title, 1)
		line(
			if (state.count or 0) > 0
				then string.format("%d veggie%s from this server on the scale", state.count, if state.count == 1 then "" else "s")
				else "Gathering at the stage...",
			Theme.TextSize.Body,
			2,
			{ Font = Theme.FontBody }
		)
	end)
end

local function onWeigh(state: { [string]: any })
	local entry = state.entry or {}
	placeVeggie(entry.cropId, entry.weight or 0)
	local weightLabel: TextLabel
	showStageCard(function()
		line(string.format("Entry %d of %d", state.index or 1, state.total or 1), Theme.TextSize.Small, 1, {
			Font = Theme.FontBody,
			TextColor3 = Theme.Colors.TextMuted,
		})
		line(entryTitle(entry), Theme.TextSize.Large, 2)
		if entry.coGrowerNames and #entry.coGrowerNames > 0 then
			line("Grown with " .. table.concat(entry.coGrowerNames, " and "), Theme.TextSize.Small, 3, { Font = Theme.FontBody })
		end
		weightLabel = line(Format.weight(0), Theme.TextSize.Title + 10, 4)
	end)
	-- Drumroll while the scale settles, then the reveal.
	FeelController.play("FairDrumroll")
	local myToken = token
	local seconds = math.max(1, (state.endsAt or 0) - ClientState.now())
	local countSeconds = math.clamp(seconds * 0.55, 0.8, 3)
	Tweens.countTo(weightLabel, 0, entry.weight or 0, Format.weight, countSeconds)
	task.delay(countSeconds, function()
		if token ~= myToken then
			return
		end
		Tweens.pop(weightLabel, 0.3)
		local scalePart = stagePart("Scale")
		FeelController.play("FairWeighIn", {
			position = if scalePart then scalePart.Position else nil,
			isMine = entry.userId == localPlayer.UserId,
		})
	end)
end

local function onAwards(state: { [string]: any })
	clearVeggie()
	local podium = state.podium or {}
	showStageCard(function()
		line(state.fairName .. ": this server's podium", Theme.TextSize.Large, 0)
	end)
	-- Third place first, winner last.
	local myToken = token
	local gap = math.clamp(((state.endsAt or 0) - ClientState.now()) / (#podium + 2), 0.6, 2)
	task.spawn(function()
		for i = #podium, 1, -1 do
			task.wait(gap)
			if token ~= myToken then
				return
			end
			local entry = podium[i]
			local isMe = entry.userId == localPlayer.UserId
			local card = UIKit.card({
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = if i == 1 then Theme.Colors.Gold elseif isMe then Theme.Colors.SurfaceAlt else Theme.Colors.Surface,
			}, { UIKit.padding(10), UIKit.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center) })
			UIKit.label(string.format("%s  %s", PLACES[entry.place or i] or "", entryTitle(entry)), Theme.TextSize.Body, { LayoutOrder = 1 }).Parent = card
			UIKit.label(
				string.format("%s  ·  +%s Coins", Format.weight(entry.weight or 0), Format.coins(entry.prize and entry.prize.coins or 0)),
				Theme.TextSize.Small,
				{ LayoutOrder = 2, Font = Theme.FontBody }
			).Parent = card
			local scale = Tweens.getScale(card)
			scale.Scale = 0.4
			card.Parent = stageCard
			Tweens.play(scale, Tweens.Ease.Pop, { Scale = 1 })
			local scalePart = stagePart("Scale")
			FeelController.play(if i == 1 then "FairConfetti" else "FairPodiumPop", {
				position = if scalePart then scalePart.Position + Vector3.new(0, 6, 0) else nil,
				isMine = isMe,
			})
		end
	end)
end

local function onGlobal(state: { [string]: any })
	local rows = state.rows or {}
	showStageCard(function()
		line("Top across every server", Theme.TextSize.Large, 0)
		if #rows == 0 then
			line("The global board is still counting. Check the Fairs board soon!", Theme.TextSize.Body, 1, { Font = Theme.FontBody })
		end
		for i, row in rows do
			local isMe = row.userId == localPlayer.UserId
			line(
				string.format("#%d  %s  ·  %s", row.rank or i, row.name or "?", Format.weight(row.weight or 0)),
				Theme.TextSize.Body,
				i,
				{ TextColor3 = if isMe then Theme.Colors.PrimaryDark else Theme.Colors.Text }
			)
		end
	end)
end

local function onEmpty(state: { [string]: any })
	showStageCard(function()
		line("No entries from this server this time", Theme.TextSize.Large, 1)
		line(
			"Enter a veggie from your Basket for the next " .. (state.fairName or "fair") .. "!",
			Theme.TextSize.Body,
			2,
			{ Font = Theme.FontBody }
		)
	end)
end

local function onIdle()
	clearVeggie()
	hideStageCard()
	hideBanner()
	leaveStage()
	optedOut = false
	showFair = nil
end

local function onState(state: { [string]: any })
	if type(state) ~= "table" then
		return
	end
	token += 1
	local previous = phase
	phase = state.phase or "Idle"
	if showFair ~= state.fair and phase ~= "Idle" and phase ~= "Announce" then
		-- A new show starts fresh.
		showFair = state.fair
		optedOut = false
	end

	if phase == "Announce" then
		FeelController.play("FairDayAnnounce", { fair = state.fair })
		local startsAt = state.startsAt or 0
		countdown(startsAt, function(seconds)
			return string.format("%s weigh-in starts in %s", state.fairName or "The fair", Format.duration(seconds))
		end)
	elseif phase == "Idle" then
		onIdle()
	else
		local endsAt = state.endsAt or 0
		countdown(endsAt, function()
			return string.format("%s%s · live", state.fairName or "Fair", if state.preview then " (preview)" else "")
		end)
		if phase == "Gather" then
			onGather(state)
		elseif phase == "Weigh" then
			if previous == "Announce" or previous == "Idle" then
				-- Joined mid-show: catch up.
				onGather(state)
			end
			onWeigh(state)
		elseif phase == "Awards" then
			onAwards(state)
		elseif phase == "Global" then
			onGlobal(state)
		elseif phase == "Empty" then
			onEmpty(state)
		end
	end
	updateWatchButton()
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function build()
	gui = UIKit.new("ScreenGui", {
		Name = "GVF_FairDay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layer.FairDay,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	topBar = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		Parent = gui,
	})
	bottomBar = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		Parent = gui,
	})

	-- Cards and buttons live in a scaled root so they size up and down with the screen.
	local root = Scale.root(gui, "Show")

	banner = UIKit.card({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Gold,
		Visible = false,
		Parent = root,
	}, { UIKit.padding(8) })
	bannerText = UIKit.label("", Theme.TextSize.Body, { Parent = banner })

	stageCard = UIKit.new("CanvasGroup", {
		Name = "StageCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1 - LETTERBOX, -16),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Background,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}, {
		UIKit.corner(),
		UIKit.stroke(Theme.Colors.Gold, 3),
		UIKit.padding(14),
		UIKit.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center),
	})

	watchButton = UIKit.button("Watch the stage", function()
		if watching then
			optedOut = true
			leaveStage()
		else
			optedOut = false
			watchStage()
		end
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1 - LETTERBOX, -16),
		Size = UDim2.fromOffset(170, 40),
		BackgroundColor3 = Theme.Colors.Accent,
		Visible = false,
		Parent = root,
	})
end

function FairDayController.start()
	build()
	NetClient.remote(Net.Remotes.FairDay).OnClientEvent:Connect(onState)
	localPlayer.CharacterAdded:Connect(function()
		-- Respawning mid-show resets the camera; keep watching if we were.
		if watching then
			watching = false
			task.defer(watchStage)
		end
	end)
end

return FairDayController
