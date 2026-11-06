--[[
	Signal  (ModuleScript)
	Locație: ReplicatedStorage > Shared > Signal

	Implementare minimală de eveniment (Connect / Fire / Once / Wait).
	Folosită de servicii ca să notifice alte sisteme (UI, broadcaster etc.)
	fără dependențe circulare.
]]

local Signal = {}
Signal.__index = Signal

local spawnFn = (task and task.spawn) or function(fn, ...)
	fn(...)
end

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect necesită o funcție")
	local handler = { fn = fn, connected = true }
	table.insert(self._handlers, handler)

	local connection = {}
	function connection.Disconnect()
		if not handler.connected then
			return
		end
		handler.connected = false
		local index = table.find(self._handlers, handler)
		if index then
			table.remove(self._handlers, index)
		end
	end
	connection.disconnect = connection.Disconnect
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	-- copie, ca un handler să se poată deconecta în timpul Fire fără probleme
	for _, handler in ipairs(table.clone(self._handlers)) do
		if handler.connected then
			spawnFn(handler.fn, ...)
		end
	end
end

-- Doar în Roblox (necesită coroutine yield din task scheduler)
function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, handler in ipairs(self._handlers) do
		handler.connected = false
	end
	table.clear(self._handlers)
end

return Signal
