--[[
	RaceService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > RaceService

	Ciclul AUTOMAT al curselor (pașii 1-23 din cerință), repetat cât timp jocul rulează:

	  Idle      așteaptă minim Config.Race.MinRacers în coadă, apoi LobbyWaitSeconds
	            pentru înscrieri suplimentare (sau pornește imediat dacă s-a umplut)
	  Lobby     concurenții sunt MUTAȚI din coadă în lista activă (TakeForRace);
	            înscrierile noi merg în coada următoare. Se încarcă avatarurile
	            originale și, în paralel, harta următoare.
	  Wheel     roata mount-urilor
	  Countdown concurenții pe grilă, 3-2-1-GO sincronizat cu clienții
	  Racing    toți pleacă simultan cu aceeași viteză; boost-urile sunt acceptate
	            DOAR acum (fereastra RaceState); primul la finish câștigă, ceilalți
	            mai au FinishGraceSeconds ca să termine
	  Finished  fereastra de boost-uri se închide, rezultate, podium cu confetti
	  -> participanții sunt șterși (EndRace, NU se reînscriu), harta se schimbă

	Control pentru panoul de admin (Etapa 8): Start, Stop, SetPaused, AbortCurrentRace.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))
local RacerController = require(script.Parent:WaitForChild("RacerController"))
local RaceState = require(script.Parent:WaitForChild("RaceState"))

local RaceService = {}
RaceService.__index = RaceService

local P = RaceState.Phases

-- deps = { config, queue, raceState, preRace, maps, staging, remotes, announce }
function RaceService.new(deps)
	local self = setmetatable({}, RaceService)
	self._config = deps.config
	self._queue = deps.queue
	self._raceState = deps.raceState
	self._preRace = deps.preRace
	self._maps = deps.maps
	self._staging = deps.staging
	self._remotes = deps.remotes
	self._announce = deps.announce or function() end

	self._running = false
	self._paused = false
	self._abort = false
	self._current = nil -- { raceId, map, handles, controller }

	self.RaceStarted = Signal.new() -- (raceInfo)
	self.RacerFinished = Signal.new() -- (raceInfo, racer, handle)
	self.RaceFinished = Signal.new() -- (raceInfo, results)
	return self
end

---------------------------------------------------------------------------
-- Control
---------------------------------------------------------------------------
function RaceService:Start()
	if self._running then
		return
	end
	self._running = true
	self._abort = false
	task.spawn(function()
		while self._running do
			local ok, err = pcall(self._runOneAsync, self)
			if not ok then
				warn("[RaceService] Eroare în cursă:", err)
				self:_emergencyCleanup()
			end
			self._abort = false
			task.wait(1)
		end
	end)
end

-- Oprește ciclul (cursa curentă este anulată curat).
function RaceService:Stop()
	self._running = false
	self:AbortCurrentRace()
end

function RaceService:IsRunning()
	return self._running
end

-- Pauză: mișcarea și cronometrele se opresc; nicio cursă nouă nu pornește.
function RaceService:SetPaused(paused)
	self._paused = paused == true
	if self._current and self._current.controller then
		self._current.controller:SetPaused(self._paused)
	end
	workspace:SetAttribute("RacePaused", self._paused)
end

function RaceService:IsPaused()
	return self._paused
end

function RaceService:AbortCurrentRace()
	if self._current then
		self._abort = true
	end
end

function RaceService:GetCurrent()
	return self._current
end

function RaceService:GetController()
	return self._current and self._current.controller or nil
end

---------------------------------------------------------------------------
-- Utilitare
---------------------------------------------------------------------------
-- Așteaptă `seconds` (timpul de pauză nu se pune). false dacă s-a cerut anularea.
function RaceService:_wait(seconds)
	local remaining = seconds
	while remaining > 0 do
		if self._abort then
			return false
		end
		local dt = task.wait(0.1)
		if not self._paused then
			remaining -= dt
		end
	end
	return not self._abort
end

function RaceService:_event(payload)
	self._remotes.RaceEvent:FireAllClients(payload)
end

local function racerSummary(handle)
	return {
		robloxUserId = handle.entry.robloxUserId,
		robloxName = handle.entry.robloxName,
		displayName = handle.entry.displayName,
		mountId = handle.mountId,
	}
end

function RaceService:_emergencyCleanup()
	local current = self._current
	self._current = nil
	if current and current.connection then
		current.connection:Disconnect()
	end
	self._preRace:CleanupAll()
	self._staging:SetConfetti(false)
	workspace:SetAttribute("PodiumActive", false)
	local activeId = self._queue:GetActiveRaceId()
	if activeId then
		self._queue:EndRace(activeId)
	end
	self._raceState:Set(P.Idle)
end

---------------------------------------------------------------------------
-- 1) Așteptarea concurenților
---------------------------------------------------------------------------
function RaceService:_waitForRacersAsync()
	local cfg = self._config.Race
	self._raceState:Set(P.Idle)
	while self._running do
		-- așteaptă minimul de concurenți (și să nu fie pauză)
		while self._running and (self._paused or self._queue:GetQueuedCount() < cfg.MinRacers) do
			task.wait(0.5)
		end
		if not self._running then
			return false
		end
		-- fereastră pentru înscrieri suplimentare
		local startsAt = workspace:GetServerTimeNow() + cfg.LobbyWaitSeconds
		self:_event({ type = "lobby", startsAt = startsAt })
		local ready = true
		while workspace:GetServerTimeNow() < startsAt do
			if not self._running then
				return false
			end
			if self._paused or self._queue:GetQueuedCount() < cfg.MinRacers then
				ready = false -- cineva a fost scos din coadă sau pauză -> reluăm
				break
			end
			if self._queue:GetQueuedCount() >= cfg.MaxRacers then
				break -- s-a umplut: pornim imediat
			end
			task.wait(0.25)
		end
		if ready then
			return true
		end
		self:_event({ type = "lobby", startsAt = nil })
	end
	return false
end

---------------------------------------------------------------------------
-- 2) O cursă completă
---------------------------------------------------------------------------
function RaceService:_runOneAsync()
	if not self:_waitForRacersAsync() then
		return
	end
	local cfg = self._config
	local queue, raceState = self._queue, self._raceState

	-- pașii 1-4: concurenții trec din coadă în lista activă; coada lor se golește
	local raceId, racers = queue:TakeForRace(cfg.Race.MaxRacers)
	if not raceId then
		return
	end
	local current = { raceId = raceId, handles = {} }
	self._current = current
	raceState:Set(P.Lobby, raceId)

	-- pasul 20 (pregătit în avans): harta nouă se construiește în paralel cu avatarurile
	local mapResult = { done = false }
	task.spawn(function()
		local ok, map, err = pcall(function()
			return self._maps:LoadAsync(cfg.Debug.ForceMap or self._maps:ChooseNextId())
		end)
		mapResult.map = ok and map or nil
		mapResult.err = ok and err or map
		mapResult.done = true
	end)

	-- pașii 5, 8: avatarurile originale în lobby
	local handles = self._preRace:PrepareAsync(raceId, racers)
	current.handles = handles
	while not mapResult.done do
		task.wait(0.1)
	end
	local map = mapResult.map
	current.map = map
	if not map then
		warn("[RaceService] Harta nu s-a putut încărca:", mapResult.err)
	end
	if self._abort or #handles == 0 or not map then
		self:_finishCleanup(current)
		return
	end
	self._announce("map", "🗺️ Harta: " .. map.displayName)

	-- pasul 10: prezentarea concurenților
	local lineup = {}
	for _, handle in ipairs(handles) do
		table.insert(lineup, racerSummary(handle))
	end
	self:_event({ type = "lineup", raceId = raceId, mapName = map.displayName, racers = lineup })

	-- pașii 6-9: roata mount-urilor; fiecare avatar ajunge pe mount-ul lui
	raceState:Set(P.Wheel, raceId)
	self._preRace:RunWheelAsync(raceId, handles)
	if self._abort then
		self:_finishCleanup(current)
		return
	end

	-- grila de start + controllerul de mișcare (aceeași viteză pentru toți)
	local controller = RacerController.new({
		track = map.track,
		finishDistance = map.finishDistance,
		baseSpeed = cfg.Race.BaseSpeed,
		noisePercent = cfg.Race.SpeedNoisePercent,
		maxMultiplier = cfg.Race.MaxSpeedMultiplier,
	})
	controller:SetPaused(self._paused)
	current.controller = controller
	local mounted = {}
	for _, handle in ipairs(handles) do
		if handle.mount then
			table.insert(mounted, handle)
		end
	end
	local grid = map.GetGrid(#mounted)
	current.byEntry = {}
	for i, handle in ipairs(mounted) do
		local slot = grid[i]
		controller:AddRacer({
			entryId = handle.entry.id,
			model = handle.model,
			root = handle.mount.PrimaryPart,
			distance = slot.distance,
			lateral = slot.lateral,
		})
		current.byEntry[handle.entry.id] = handle
		handle.model:SetAttribute("OnTrack", true)
		handle.model:SetAttribute("Lane", slot.lateral)
	end
	controller:ApplyTransforms()
	controller:Publish(0, true)
	if #mounted == 0 then
		self:_finishCleanup(current)
		return
	end

	-- pașii 11-12: countdown, apoi start simultan
	raceState:Set(P.Countdown, raceId)
	if cfg.Gifts.AcceptDuringCountdown then
		raceState:OpenBoostWindow(raceId)
	end
	local holdSeconds = cfg.Race.GridHoldSeconds + cfg.Race.CountdownSeconds
	self:_event({ type = "countdown", raceId = raceId, goAt = workspace:GetServerTimeNow() + holdSeconds, seconds = cfg.Race.CountdownSeconds })
	if not self:_wait(holdSeconds) then
		self:_finishCleanup(current)
		return
	end

	raceState:Set(P.Racing, raceId)
	raceState:OpenBoostWindow(raceId) -- pasul 13: DOAR acum se pot activa boost-uri
	self:_event({ type = "go", raceId = raceId })
	self.RaceStarted:Fire(current)

	-- pașii 14-15: mișcare, clasament, finish
	local winner = nil
	local graceUntil = nil
	current.connection = RunService.Heartbeat:Connect(function(dt)
		if self._paused then
			return
		end
		local newlyFinished = controller:Step(dt)
		controller:ApplyTransforms()
		controller:Publish(dt)
		for _, racer in ipairs(newlyFinished) do
			local handle = current.byEntry[racer.entryId]
			if handle then
				if not winner then
					winner = handle
					graceUntil = controller.time + cfg.Race.FinishGraceSeconds
					self._announce("winner", string.format("🏆 %s câștigă cursa!", handle.entry.robloxName), { robloxUserId = handle.entry.robloxUserId })
				end
				self:_event({
					type = "finish",
					raceId = raceId,
					robloxUserId = handle.entry.robloxUserId,
					robloxName = handle.entry.robloxName,
					place = racer.finishOrder,
					time = racer.finishTime,
				})
				self.RacerFinished:Fire(current, racer, handle)
			end
		end
	end)

	while true do
		if self._abort then
			break
		end
		if controller:AllFinished() then
			break
		end
		if graceUntil and controller.time >= graceUntil then
			break
		end
		if controller.time >= cfg.Race.MaxRaceSeconds then
			break
		end
		task.wait(0.1)
	end
	current.connection:Disconnect()
	current.connection = nil

	-- pașii 16-17: fereastra de boost-uri se închide, rezultate
	raceState:Set(P.Finished, raceId) -- închide automat fereastra de boost-uri
	controller:Publish(0, true)
	if self._abort then
		self:_finishCleanup(current)
		return
	end
	local results = self:_buildResults(controller, current)
	current.results = results
	self:_event({ type = "results", raceId = raceId, mapName = map.displayName, results = results, podiumSeconds = cfg.Race.PodiumSeconds })
	self.RaceFinished:Fire(current, results)
	if not winner and results[1] then
		self._announce("winner", string.format("⏱️ Timpul a expirat! %s era în frunte", results[1].robloxName), { robloxUserId = results[1].robloxUserId })
	end

	-- podium
	self:_showPodium(current, results)
	self:_wait(cfg.Race.PodiumSeconds)
	self._staging:SetConfetti(false)
	workspace:SetAttribute("PodiumActive", false)

	-- pașii 18-21: participanții sunt eliminați, coada cursei e închisă
	self:_finishCleanup(current)
end

function RaceService:_buildResults(controller, current)
	local results = {}
	for _, racer in ipairs(controller:GetStandings()) do
		local handle = current.byEntry[racer.entryId]
		if handle then
			table.insert(results, {
				position = racer.position,
				robloxUserId = handle.entry.robloxUserId,
				robloxName = handle.entry.robloxName,
				displayName = handle.entry.displayName,
				mountId = handle.mountId,
				finished = racer.finished,
				time = racer.finishTime and math.floor(racer.finishTime * 100 + 0.5) / 100 or nil,
				distance = math.floor(racer.distance),
			})
		end
	end
	return results
end

function RaceService:_showPodium(current, results)
	for _, handle in ipairs(current.handles) do
		handle.model:SetAttribute("OnTrack", false)
		handle.model:SetAttribute("Speed", 0)
	end
	local onPodium = {}
	for place = 1, math.min(3, #results) do
		local entry = results[place]
		for _, handle in ipairs(current.handles) do
			if handle.entry.robloxUserId == entry.robloxUserId and handle.mount then
				handle.mount.PrimaryPart.CFrame = self._staging:GetPodiumSlot(place)
				handle.model:SetAttribute("PodiumPlace", place)
				onPodium[handle] = true
			end
		end
	end
	-- ceilalți dispar de pe pistă (nu mai sunt în cursă)
	for _, handle in ipairs(current.handles) do
		if not onPodium[handle] then
			handle.model:Destroy()
		end
	end
	self._staging:SetConfetti(true)
	workspace:SetAttribute("PodiumActive", true)
end

function RaceService:_finishCleanup(current)
	if current.connection then
		current.connection:Disconnect()
		current.connection = nil
	end
	self._preRace:Cleanup(current.handles)
	self._staging:SetConfetti(false)
	workspace:SetAttribute("PodiumActive", false)
	self._queue:EndRace(current.raceId) -- NU sunt reintroduși în coadă
	self._raceState:Set(P.Idle)
	self._current = nil
	if self._abort then
		self:_event({ type = "aborted", raceId = current.raceId })
	end
end

return RaceService
