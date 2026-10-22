--!strict
-- Minimal test harness for the pure modules. Runs under the standalone `luau` CLI.

local TestKit = {}

local results = { passed = 0, failed = 0, failures = {} :: { string } }
local currentSuite = ""

function TestKit.describe(name: string, fn: () -> ())
	currentSuite = name
	fn()
end

function TestKit.it(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, string.format("%s > %s\n    %s", currentSuite, name, tostring(err)))
	end
end

function TestKit.eq(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", if msg then msg .. ": " else "", tostring(expected), tostring(actual)), 2)
	end
end

function TestKit.near(actual: number, expected: number, tolerance: number?, msg: string?)
	if math.abs(actual - expected) > (tolerance or 1e-6) then
		error(string.format("%sexpected ~%s, got %s", if msg then msg .. ": " else "", tostring(expected), tostring(actual)), 2)
	end
end

function TestKit.truthy(value: any, msg: string?)
	if not value then
		error(msg or "expected truthy value", 2)
	end
end

function TestKit.report(): boolean
	for _, failure in results.failures do
		print("FAIL " .. failure)
	end
	print(string.format("\n%d passed, %d failed", results.passed, results.failed))
	return results.failed == 0
end

return TestKit
