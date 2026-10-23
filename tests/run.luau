--!strict
--[[
	Runs every pure-logic spec. From the repo root:
	    luau tests/run.luau
	Exits non-zero (via error) when anything fails.
]]

local TestKit = require("./TestKit")

require("./GrowthMath.spec")
require("./EconomyMath.spec")
require("./FairMath.spec")
require("./CareMath.spec")
require("./Format.spec")
require("./Schema.spec")
require("./StudMath.spec")

if not TestKit.report() then
	error("tests failed")
end
