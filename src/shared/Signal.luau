--!strict
--[[
	Signal: a tiny synchronous event, used for in-process events on either side.
]]

export type Connection = { Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { [number]: (...any) -> () }, _nextId: number }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _nextId = 0 }, Signal)
end

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	self._nextId += 1
	local id = self._nextId
	self._handlers[id] = handler
	local handlers = self._handlers
	return {
		Disconnect = function()
			handlers[id] = nil
		end,
	} :: any
end

function Signal.Fire(self: Signal, ...: any)
	-- Copy so handlers may disconnect while firing.
	local list = {}
	for id, handler in self._handlers do
		table.insert(list, { id, handler })
	end
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	for _, entry in list do
		local ok, err = pcall(entry[2], ...)
		if not ok then
			warn("[Signal] handler error: " .. tostring(err))
		end
	end
end

return Signal
