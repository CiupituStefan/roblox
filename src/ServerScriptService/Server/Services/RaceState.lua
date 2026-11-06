--[[
	RaceState  (ModuleScript)
	Locație: ServerScriptService > Server > Services > RaceState

	Starea curentă a cursei, partajată între servicii. RaceService (Etapa 5) este
	singurul care o modifică; GiftRouter/BoostService doar o citesc.

	„Fereastra de boost-uri” se deschide explicit la START și se închide la
	FINISH. Orice gift primit în afara ferestrei (sau pentru alt raceId) e respins.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local RaceState = {}
RaceState.__index = RaceState

RaceState.Phases = {
	Idle = "Idle", -- nu există cursă
	Lobby = "Lobby", -- concurenții sunt aleși, se încarcă avatarurile
	Wheel = "Wheel", -- roata mount-urilor
	Countdown = "Countdown",
	Racing = "Racing",
	Finished = "Finished", -- podium
}

function RaceState.new(opts)
	opts = opts or {}
	local self = setmetatable({}, RaceState)
	self._clock = opts.clock or os.clock
	self.phase = RaceState.Phases.Idle
	self.raceId = nil
	self.phaseStartedAt = self._clock()
	self.boostWindowRaceId = nil
	self.boostWindowOpenedAt = nil
	self.Changed = Signal.new() -- (phase, raceId)
	return self
end

function RaceState:Set(phase, raceId)
	assert(RaceState.Phases[phase], "Fază necunoscută: " .. tostring(phase))
	self.phase = phase
	self.raceId = phase ~= RaceState.Phases.Idle and raceId or nil
	self.phaseStartedAt = self._clock()
	if phase == RaceState.Phases.Idle or phase == RaceState.Phases.Finished then
		self:CloseBoostWindow()
	end
	self.Changed:Fire(phase, self.raceId)
end

function RaceState:OpenBoostWindow(raceId)
	self.boostWindowRaceId = raceId
	self.boostWindowOpenedAt = self._clock()
end

function RaceState:CloseBoostWindow()
	self.boostWindowRaceId = nil
	self.boostWindowOpenedAt = nil
end

-- true dacă un eveniment primit la momentul `receivedClock` poate da boost în cursa raceId
function RaceState:AcceptsBoostAt(raceId, receivedClock)
	if self.boostWindowRaceId == nil or self.boostWindowRaceId ~= raceId then
		return false, "RACE_NOT_RUNNING"
	end
	if receivedClock < self.boostWindowOpenedAt then
		return false, "STALE_EVENT" -- trimis înainte de start (sau întârziat dintr-o cursă anterioară)
	end
	return true
end

function RaceState:Snapshot()
	return { phase = self.phase, raceId = self.raceId, boostsOpen = self.boostWindowRaceId ~= nil }
end

return RaceState
