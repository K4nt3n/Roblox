--!strict
--[[
	DialogueController: talk to the NPCs in Workspace.NPCs.

	* All text and answers come from ReplicatedStorage.Shared.DialogueConfig.
	* Press E / tap "Talk": the NPC turns to you and waves, its line types out,
	  and your answers appear as buttons. Each answer runs one action (ACTIONS
	  below), which opens the existing UI; anything that changes coins or items
	  still goes through the normal server-validated requests.
	* Only one dialogue can be open, answers can only be clicked once, and the
	  dialogue closes if you walk away or respawn.
	* NPCs idle with Roblox's default R15 idle animation (played locally).
	* The stall's own "Open" prompt is hidden where an NPC works, so players
	  talk to the NPC instead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DialogueConfig = require(Shared.DialogueConfig)
local Format = require(Shared.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local FeelController = require(script.Parent.Parent.Feel.FeelController)
local Tweens = require(script.Parent.Parent.Feel.Tweens)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Modal = require(script.Parent.Parent.UI.Modal)
local FairPanel = require(script.Parent.Parent.UI.FairPanel)
local UIController = require(script.Parent.Parent.UI.UIController)

local DialogueController = {}

local localPlayer = Players.LocalPlayer

-- Roblox's default R15 animations (usable in any game).
local ANIMATIONS = {
	Idle = "rbxassetid://507766666",
	Wave = "rbxassetid://507770239",
	Point = "rbxassetid://507770453",
}

type NpcState = {
	model: Model,
	id: string,
	root: BasePart,
	prompt: ProximityPrompt,
	homeCFrame: CFrame,
	tracks: { [string]: AnimationTrack },
}

local npcs: { NpcState } = {}
local gui: ScreenGui
local card: Frame
local nameLabel: TextLabel
local lineLabel: TextLabel
local buttonRow: Frame
local active: NpcState? = nil
local answered = false
local token = 0 -- bumps on every open/close so stale typewriters stop

---------------------------------------------------------------------------
-- Actions: what each response does. Add new ones here and use them in DialogueConfig.
---------------------------------------------------------------------------

local function startWeighIn()
	local data = ClientState.data
	local produce = if data then data.produce else {}
	if #produce == 0 then
		Modal.show({
			title = "Nothing to weigh yet",
			lines = { "Harvest a veggie from your garden, then come back to weigh it in!" },
			buttons = { { text = "Okay", color = Theme.Colors.Primary } },
		})
		return
	end
	local items = table.clone(produce)
	table.sort(items, function(a, b)
		return a.weight > b.weight
	end)
	Modal.show({
		title = "Which veggie are you weighing in?",
		lines = { "Your heaviest veggies are on top." },
		build = function(holder, close)
			for i = 1, math.min(#items, 5) do
				local item = items[i]
				local crop = Config.Crops[item.cropId]
				local button = UIKit.button("Weigh in", function()
					close()
					-- The existing fair picker sends the server-validated EnterFair request.
					FairPanel.pick(item)
				end, { BackgroundColor3 = Theme.Colors.Gold, TextColor3 = Theme.Colors.Text })
				local row = UIKit.row(
					string.format("%s · %s", if crop then crop.displayName else item.cropId, Format.weight(item.weight)),
					if item.isGiant then "GIANT" else nil,
					{ button }
				)
				row.LayoutOrder = i
				row.Size = UDim2.new(1, 0, 0, 64)
				row.Parent = holder
			end
		end,
		buttons = { { text = "Not now", color = Theme.Colors.Surface, textColor = Theme.Colors.Text } },
	})
end

local ACTIONS: { [string]: () -> () } = {
	OpenShop = function()
		UIController.open("Shop")
	end,
	OpenMarket = function()
		UIController.open("Market")
	end,
	StartWeighIn = startWeighIn,
	Close = function() end,
}

---------------------------------------------------------------------------
-- NPC animation
---------------------------------------------------------------------------

local function loadTracks(model: Model): { [string]: AnimationTrack }
	local tracks = {}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return tracks
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	for name, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = name == "Idle"
			track.Priority = if name == "Idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Action
			tracks[name] = track
		end
	end
	if tracks.Idle then
		tracks.Idle:Play(0.3)
	end
	return tracks
end

local function play(npc: NpcState, name: string)
	local track = npc.tracks[name]
	if track then
		track:Play(0.15)
	end
end

local function face(npc: NpcState, target: Vector3?)
	local goal = npc.homeCFrame
	if target then
		local from = npc.root.Position
		goal = CFrame.lookAt(from, Vector3.new(target.X, from.Y, target.Z))
	end
	TweenService:Create(npc.root, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { CFrame = goal }):Play()
end

---------------------------------------------------------------------------
-- Dialogue box
---------------------------------------------------------------------------

local function setPromptsEnabled(enabled: boolean)
	for _, npc in npcs do
		npc.prompt.Enabled = enabled
	end
end

local function close()
	local npc = active
	if not npc then
		return
	end
	active = nil
	token += 1
	face(npc, nil)
	local scale = Tweens.getScale(card)
	local tween = Tweens.play(scale, Tweens.Ease.Fade, { Scale = 0 })
	local myToken = token
	local function hide()
		if token == myToken then
			card.Visible = false
		end
	end
	if tween then
		tween.Completed:Once(hide)
	else
		hide()
	end
	setPromptsEnabled(true)
	FeelController.play("PanelClose")
end

local function clearButtons()
	for _, child in buttonRow:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

-- Types `text` into the line label; returns false if the dialogue changed meanwhile.
local function typeOut(text: string): boolean
	local myToken = token
	lineLabel.Text = text
	if DialogueConfig.TypeSpeed <= 0 then
		lineLabel.MaxVisibleGraphemes = -1
		return true
	end
	local length = utf8.len(text) or #text
	for i = 0, length do
		if token ~= myToken then
			return false
		end
		lineLabel.MaxVisibleGraphemes = i
		task.wait(DialogueConfig.TypeSpeed)
	end
	lineLabel.MaxVisibleGraphemes = -1
	return token == myToken
end

local function choose(npc: NpcState, response: DialogueConfig.Response)
	if answered or active ~= npc then
		return
	end
	answered = true -- one answer per dialogue, however fast the clicks come
	for _, child in buttonRow:GetChildren() do
		if child:IsA("GuiButton") then
			UIKit.setEnabled(child :: TextButton, false)
		end
	end
	local run = ACTIONS[response.action] or ACTIONS.Close
	if response.action ~= "Close" then
		play(npc, "Point")
	end
	if response.reply then
		clearButtons()
		if not typeOut(response.reply) then
			return
		end
		task.wait(1.2)
		if active ~= npc then
			return
		end
	end
	close()
	run()
end

local function open(npc: NpcState)
	if active then
		return
	end
	local def = DialogueConfig.Npcs[npc.id]
	if not def then
		return
	end
	active = npc
	answered = false
	token += 1
	local myToken = token
	setPromptsEnabled(false)
	UIController.close()

	local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	face(npc, if root then root.Position else nil)
	play(npc, "Wave")

	nameLabel.Text = def.displayName
	lineLabel.Text = ""
	clearButtons()
	card.Visible = true
	local scale = Tweens.getScale(card)
	scale.Scale = 0.8
	Tweens.play(scale, Tweens.Ease.Pop, { Scale = 1 })
	FeelController.play("PanelOpen")

	task.spawn(function()
		if not typeOut(def.line) or token ~= myToken then
			return
		end
		for i, response in def.responses do
			local button = UIKit.button(response.text, function()
				choose(npc, response)
			end, {
				Name = "Response" .. i,
				LayoutOrder = i,
				Size = UDim2.fromOffset(120, 48),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = if response.action == "Close" then Theme.Colors.Surface else Theme.Colors.Primary,
				TextColor3 = if response.action == "Close" then Theme.Colors.Text else Theme.Colors.TextOnPrimary,
			})
			UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }).Parent = button
			button.Parent = buttonRow
			Tweens.pop(button, 0.15)
		end
	end)
end

local function buildGui()
	gui = UIKit.new("ScreenGui", {
		Name = "GVF_Dialogue",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	-- Bottom centre, above the seed hotbar; scales down on phones.
	card = UIKit.card({
		Name = "Dialogue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.new(0.92, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Background,
		Visible = false,
		Parent = gui,
	}, {
		UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(640, math.huge) }),
		UIKit.padding(16),
		UIKit.list(Enum.FillDirection.Vertical, 10),
	})
	-- Header: NPC name on the left, close button on the right.
	local header = UIKit.new("Frame", {
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = card,
	})
	nameLabel = UIKit.label("", Theme.TextSize.Large, { TextColor3 = Theme.Colors.PrimaryDark })
	nameLabel.Parent = header
	UIKit.button("X", close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(36, 34),
		BackgroundColor3 = Theme.Colors.Danger,
	}).Parent = header
	lineLabel = UIKit.label("", Theme.TextSize.Body + 2, {
		LayoutOrder = 2,
		Font = Theme.FontBody,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	lineLabel.Parent = card
	buttonRow = UIKit.new("Frame", {
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	local layout = UIKit.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
	layout.Wraps = true
	layout.Parent = buttonRow
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local function hideStandPrompt(standName: string)
	local stands = workspace:WaitForChild("Stands", 30)
	local stand = stands and stands:WaitForChild(standName, 30)
	if not stand then
		return
	end
	local function check(child: Instance)
		if child:IsA("ProximityPrompt") and child.Name == "Open" then
			child.Enabled = false
		end
	end
	for _, child in stand:GetChildren() do
		check(child)
	end
	stand.ChildAdded:Connect(check)
end

local function register(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute("DialogueId")
	local def = type(id) == "string" and DialogueConfig.Npcs[id]
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local prompt = root and root:WaitForChild("Talk", 10) :: ProximityPrompt?
	if not def or not root or not prompt then
		return
	end
	prompt.ActionText = def.promptText
	prompt.ObjectText = def.displayName
	local tag = model:FindFirstChild("NameTag", true)
	local label = tag and tag:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = def.displayName
	end
	local npc: NpcState = {
		model = model,
		id = id :: string,
		root = root,
		prompt = prompt,
		homeCFrame = root.CFrame,
		tracks = loadTracks(model),
	}
	table.insert(npcs, npc)
	prompt.Triggered:Connect(function()
		open(npc)
	end)
	if def.stand then
		task.spawn(hideStandPrompt, def.stand)
	end
end

function DialogueController.start()
	buildGui()
	task.spawn(function()
		local folder = workspace:WaitForChild("NPCs", 60)
		if not folder then
			return
		end
		for _, model in folder:GetChildren() do
			task.spawn(register, model)
		end
		folder.ChildAdded:Connect(register)
	end)

	-- Walking away (or respawning) ends the conversation.
	RunService.Heartbeat:Connect(function()
		local npc = active
		if not npc then
			return
		end
		local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - npc.root.Position).Magnitude > DialogueConfig.MaxDistance then
			close()
		end
	end)
end

return DialogueController
