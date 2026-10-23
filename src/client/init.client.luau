--!strict
--[[
	Client entry point. Order: state -> feel (so it hears the first events) ->
	world visuals -> UI.
]]

local ClientState = require(script:WaitForChild("ClientState"))
local FeelController = require(script:WaitForChild("Feel"):WaitForChild("FeelController"))
local GardenController = require(script:WaitForChild("Controllers"):WaitForChild("GardenController"))
local FairDayController = require(script:WaitForChild("Controllers"):WaitForChild("FairDayController"))
local PlotPicker = require(script:WaitForChild("Controllers"):WaitForChild("PlotPicker"))
local ToolController = require(script:WaitForChild("Controllers"):WaitForChild("ToolController"))
local DialogueController = require(script:WaitForChild("Controllers"):WaitForChild("DialogueController"))
local UIController = require(script:WaitForChild("UI"):WaitForChild("UIController"))

FeelController.start()
GardenController.start()
UIController.start()
FairDayController.start()
ToolController.start()
DialogueController.start()
task.spawn(PlotPicker.start) -- waits for workspace.Gardens, so don't block the snapshot listener
-- Listen last: every controller is subscribed before the first snapshot arrives.
ClientState.start()
