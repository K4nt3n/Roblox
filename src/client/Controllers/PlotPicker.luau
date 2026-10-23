--!strict
--[[
	PlotPicker: on arrival, asks the player to claim a free garden slot.
	Walk to a "Free Plot" sign and press E (PlotService's Claim prompt), or
	press "Pick for me". The server picks one anyway after
	Config.World.autoPickSeconds. Hides itself once the player's garden exists.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local NetClient = require(script.Parent.Parent.NetClient)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local PlotPicker = {}

local localPlayer = Players.LocalPlayer

function PlotPicker.start()
	local gardens = workspace:WaitForChild("Gardens")
	local gardenName = "Garden_" .. localPlayer.UserId
	if gardens:FindFirstChild(gardenName) then
		return
	end

	local gui = UIKit.new("ScreenGui", {
		Name = "PlotPicker",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local card = UIKit.card({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Background,
	})
	UIKit.padding(14).Parent = card
	UIKit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center).Parent = card
	UIKit.label("Choose your garden!", Theme.TextSize.Large, { LayoutOrder = 1 }).Parent = card
	UIKit.label("Walk to a Free Plot sign and press E", Theme.TextSize.Small, {
		LayoutOrder = 2,
		Font = Theme.FontBody,
		TextColor3 = Theme.Colors.TextMuted,
	}).Parent = card

	local busy = false
	local button = UIKit.button("Pick for me", function()
		if busy then
			return
		end
		busy = true
		NetClient.request(NetClient.Actions.ClaimPlot, {})
		busy = false
	end, { LayoutOrder = 3, Size = UDim2.fromOffset(220, 44) })
	button.Parent = card
	card.Parent = gui
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		gui:Destroy()
	end
	gardens.ChildAdded:Connect(function(child)
		if child.Name == gardenName then
			finish()
		end
	end)
	if gardens:FindFirstChild(gardenName) then
		finish()
		return
	end

	-- Mirrors the server's auto-pick timer (close enough for a countdown).
	task.spawn(function()
		local deadline = os.clock() + Config.World.autoPickSeconds
		while not done do
			local left = math.max(0, math.ceil(deadline - os.clock()))
			button.Text = if left > 0 then string.format("Pick for me (%d)", left) else "Picking a plot..."
			task.wait(0.25)
		end
	end)
end

return PlotPicker
