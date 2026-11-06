--[[
	HealthMonitor  (ModuleScript)
	Locație: ServerScriptService > Server > Services > HealthMonitor

	Siguranță pentru LIVE-uri de mai multe ore:
	  * măsoară FPS-ul serverului (Heartbeat), cel mai lent cadru și memoria
	    -> atribute în ReplicatedStorage (ServerFPS, ServerMemoryMb) pentru panoul admin
	  * scrie periodic o linie de sănătate în Output (Config.Debug.HealthLogMinutes)
	  * WATCHDOG: dacă o fază a cursei durează mult peste limita normală
	    (ex. încărcarea hărții s-a blocat), anulează cursa; dacă nici asta nu
	    ajută, repornește complet ciclul de curse (RaceService:Restart)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local HealthMonitor = {}
HealthMonitor.__index = HealthMonitor

-- deps = { config, raceState, race, log }
function HealthMonitor.new(deps)
	local self = setmetatable({}, HealthMonitor)
	self._config = deps.config
	self._raceState = deps.raceState
	self._race = deps.race
	self._log = deps.log or print
	self._startedAt = os.clock()
	self._phaseSince = os.clock()
	self._pausedTime = 0
	self._abortedAt = nil
	self._frames = 0
	self._worstFrame = 0
	self.fps = 60
	self.worstFrameMs = 0
	self.memoryMb = 0
	self.watchdogActions = 0
	return self
end

-- Limita (secunde) pentru fiecare fază; nil = fără limită
function HealthMonitor:_limitFor(phase)
	local cfg = self._config
	local wheel = cfg.Wheel
	if phase == "Lobby" then
		return wheel.PrepareTimeoutSeconds + 90 -- avatare + hartă
	elseif phase == "Wheel" then
		return wheel.IntroSeconds + wheel.MaxTotalSeconds + wheel.OutroSeconds + 45
	elseif phase == "Countdown" then
		return cfg.Race.GridHoldSeconds + cfg.Race.CountdownSeconds + 30
	elseif phase == "Racing" then
		return cfg.Race.MaxRaceSeconds + 45
	elseif phase == "Finished" then
		return cfg.Race.PodiumSeconds + 45
	end
	return nil
end

function HealthMonitor:GetStats()
	return {
		fps = math.floor(self.fps + 0.5),
		worstFrameMs = math.floor(self.worstFrameMs),
		memoryMb = math.floor(self.memoryMb),
		uptimeMin = math.floor((os.clock() - self._startedAt) / 60),
		watchdogActions = self.watchdogActions,
	}
end

function HealthMonitor:_checkWatchdog(dt)
	if self._race:IsPaused() then
		self._pausedTime += dt -- pauza nu se pune la socoteală
		return
	end
	local phase = self._raceState.phase
	local limit = self:_limitFor(phase)
	if not limit then
		return
	end
	local elapsed = os.clock() - self._phaseSince - self._pausedTime
	if elapsed > limit and not self._abortedAt then
		self.watchdogActions += 1
		self._abortedAt = os.clock()
		warn(string.format("[HealthMonitor] Faza %s durează de %ds (limită %ds) -> anulez cursa", phase, elapsed, limit))
		self._race:AbortCurrentRace()
	elseif self._abortedAt and os.clock() - self._abortedAt > 30 then
		self.watchdogActions += 1
		self._abortedAt = nil
		warn("[HealthMonitor] Cursa nu s-a putut anula -> repornesc ciclul de curse")
		self._race:Restart()
	end
end

function HealthMonitor:Start()
	self._raceState.Changed:Connect(function()
		self._phaseSince = os.clock()
		self._pausedTime = 0
		self._abortedAt = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._frames += 1
		if dt > self._worstFrame then
			self._worstFrame = dt
		end
	end)

	task.spawn(function()
		local window = 5
		local lastLog = os.clock()
		while true do
			task.wait(window)
			self.fps = self._frames / window
			self.worstFrameMs = self._worstFrame * 1000
			self._frames = 0
			self._worstFrame = 0
			local ok, memory = pcall(function()
				return Stats:GetTotalMemoryUsageMb()
			end)
			self.memoryMb = ok and memory or 0
			ReplicatedStorage:SetAttribute("ServerFPS", math.floor(self.fps + 0.5))
			ReplicatedStorage:SetAttribute("ServerMemoryMb", math.floor(self.memoryMb))

			local okWatch, err = pcall(self._checkWatchdog, self, window)
			if not okWatch then
				warn("[HealthMonitor] watchdog:", err)
			end

			local minutes = self._config.Debug.HealthLogMinutes or 5
			if os.clock() - lastLog >= minutes * 60 then
				lastLog = os.clock()
				local s = self:GetStats()
				local raceStats = self._race:GetStats()
				self._log(string.format("[Sănătate] %d min · FPS %d (cel mai lent cadru %d ms) · memorie %d MB · curse %d (anulate %d) · intervenții watchdog %d · racers în lume %d",
					s.uptimeMin, s.fps, s.worstFrameMs, s.memoryMb, raceStats.racesCompleted, raceStats.racesAborted, s.watchdogActions,
					workspace:FindFirstChild("Racers") and #workspace.Racers:GetChildren() or 0))
			end
		end
	end)
end

return HealthMonitor
