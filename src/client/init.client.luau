--!strict
--[[
	Client entry point. Order: state -> feel (so it hears the first events) ->
	world visuals -> UI.
]]

local ClientState = require(script:WaitForChild("ClientState"))
local FeelController = require(script:WaitForChild("Feel"):WaitForChild("FeelController"))
local GardenController = require(script:WaitForChild("Controllers"):WaitForChild("GardenController"))
local UIController = require(script:WaitForChild("UI"):WaitForChild("UIController"))

FeelController.start()
GardenController.start()
UIController.start()
-- Listen last: every controller is subscribed before the first snapshot arrives.
ClientState.start()
