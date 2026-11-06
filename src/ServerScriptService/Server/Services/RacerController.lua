--[[
	RacerController  (ModuleScript)
	Locație: ServerScriptService > Server > Services > RacerController

	Simularea mișcării în cursă, 100% pe server (clienții nu pot influența nimic):
	  * fiecare concurent are „distanța parcursă” pe traseu și o bandă laterală fixă
	  * toți pornesc cu ACEEAȘI viteză de bază (mount-ul nu contează)
	  * variație mică, simetrică, cu media 0 (Config.Race.SpeedNoisePercent)
	  * modificatori de viteză (boost-uri), impulsuri (Rocket/Teleport) și zbor (Jetpack)
	    -> API folosit de BoostService în Etapa 6
	  * clasament live: cei ajunși la finish (după timp), apoi după distanță
	  * după finish concurentul încetinește și se oprește înainte de capătul pistei

	Poate rula și fără modele (root = nil) pentru teste.
]]

local RacerController = {}
RacerController.__index = RacerController

--[[
	opts = {
	  track (TrackMath), finishDistance, baseSpeed, noisePercent,
	  maxMultiplier, rng (Random)?
	}
]]
function RacerController.new(opts)
	local self = setmetatable({}, RacerController)
	self.track = opts.track
	self.finishDistance = opts.finishDistance
	self.baseSpeed = opts.baseSpeed
	self.noise = (opts.noisePercent or 0) / 100
	self.maxMultiplier = opts.maxMultiplier or 4
	self.rng = opts.rng or Random.new()
	self.racers = {} -- listă
	self.byEntry = {} -- entryId -> racer
	self.time = 0 -- timpul cursei (se oprește pe pauză)
	self.finishCount = 0
	self.paused = false
	self._publishTimer = 0
	return self
end

--[[
	racer = { entryId, distance, lateral, root?, model? }
]]
function RacerController:AddRacer(spec)
	local racer = {
		entryId = spec.entryId,
		model = spec.model,
		root = spec.root,
		distance = spec.distance,
		startDistance = spec.distance,
		lateral = spec.lateral,
		phase = self.rng:NextNumber(0, math.pi * 2),
		freq = self.rng:NextNumber(0.35, 0.8),
		modifiers = {}, -- key -> { multiplier, expires }
		impulses = {}, -- { remaining, rate }
		flight = nil, -- { height, expires }
		height = 0,
		speed = 0,
		multiplier = 1,
		finished = false,
		finishTime = nil,
		finishOrder = nil,
		position = 0,
	}
	table.insert(self.racers, racer)
	self.byEntry[spec.entryId] = racer
	return racer
end

function RacerController:GetRacer(entryId)
	return self.byEntry[entryId]
end

---------------------------------------------------------------------------
-- API pentru boost-uri (folosit de BoostService)
---------------------------------------------------------------------------
-- Multiplicator temporar. Aceeași cheie reîmprospătează durata; chei diferite -> se ia maximul.
function RacerController:AddModifier(entryId, key, multiplier, duration)
	local racer = self.byEntry[entryId]
	if not racer or racer.finished then
		return false
	end
	local existing = racer.modifiers[key]
	local expires = self.time + duration
	if existing then
		existing.multiplier = math.max(existing.multiplier, multiplier)
		existing.expires = math.max(existing.expires, expires)
	else
		racer.modifiers[key] = { multiplier = multiplier, expires = expires }
	end
	return true
end

-- Avans suplimentar de `distance` studs, distribuit pe `duration` secunde (0 = instant).
function RacerController:AddImpulse(entryId, distance, duration)
	local racer = self.byEntry[entryId]
	if not racer or racer.finished then
		return false
	end
	if duration <= 0 then
		racer.distance += distance
	else
		table.insert(racer.impulses, { remaining = distance, rate = distance / duration })
	end
	return true
end

-- Zbor deasupra traseului (Jetpack).
function RacerController:SetFlight(entryId, height, duration)
	local racer = self.byEntry[entryId]
	if not racer or racer.finished then
		return false
	end
	local expires = self.time + duration
	if racer.flight then
		racer.flight.height = math.max(racer.flight.height, height)
		racer.flight.expires = math.max(racer.flight.expires, expires)
	else
		racer.flight = { height = height, expires = expires }
	end
	return true
end

function RacerController:GetActiveBoosts(entryId)
	local racer = self.byEntry[entryId]
	local list = {}
	if not racer then
		return list
	end
	for key, m in pairs(racer.modifiers) do
		table.insert(list, { key = key, multiplier = m.multiplier, remaining = m.expires - self.time })
	end
	if racer.flight then
		table.insert(list, { key = "Flight", remaining = racer.flight.expires - self.time })
	end
	return list
end

---------------------------------------------------------------------------
-- Simulare
---------------------------------------------------------------------------
function RacerController:SetPaused(paused)
	self.paused = paused
end

function RacerController:_stepRacer(racer, dt)
	local t = self.time
	local before = racer.distance

	if racer.finished then
		-- după finish: încetinește lin și se oprește înainte de capătul pistei
		racer.speed = math.max(0, racer.speed - self.baseSpeed * 0.8 * dt)
		racer.distance = math.min(racer.distance + racer.speed * dt, self.track.length - 3)
		racer.modifiers = {}
		racer.impulses = {}
	else
		local multiplier = 1
		for key, m in pairs(racer.modifiers) do
			if m.expires <= t then
				racer.modifiers[key] = nil
			else
				multiplier = math.max(multiplier, m.multiplier)
			end
		end
		multiplier = math.min(multiplier, self.maxMultiplier)
		racer.multiplier = multiplier

		local wobble = 1 + self.noise * math.sin(t * racer.freq + racer.phase)
		local speed = self.baseSpeed * wobble * multiplier
		local extra = 0
		for i = #racer.impulses, 1, -1 do
			local impulse = racer.impulses[i]
			local step = math.min(impulse.remaining, impulse.rate * dt)
			extra += step
			impulse.remaining -= step
			if impulse.remaining <= 1e-6 then
				table.remove(racer.impulses, i)
			end
		end
		racer.distance += speed * dt + extra
		racer.speed = dt > 0 and (racer.distance - before) / dt or speed

		if racer.distance >= self.finishDistance then
			self.finishCount += 1
			racer.finished = true
			racer.finishOrder = self.finishCount
			-- timpul exact al trecerii liniei (interpolat în cadrul pasului)
			local overshoot = racer.distance - self.finishDistance
			local travelled = math.max(racer.distance - before, 1e-6)
			racer.finishTime = t - dt * math.min(1, overshoot / travelled)
			racer.flight = nil
		end
	end

	-- înălțime (Jetpack): urcă/coboară lin
	local targetHeight = 0
	if racer.flight then
		if racer.flight.expires <= t then
			racer.flight = nil
		else
			targetHeight = racer.flight.height
		end
	end
	racer.height += (targetHeight - racer.height) * math.min(1, dt * 4)
end

-- Clasament: întâi cei ajunși (după ordinea la finish), apoi după distanță.
function RacerController:GetStandings()
	local list = table.clone(self.racers)
	table.sort(list, function(a, b)
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.finished then
			return a.finishOrder < b.finishOrder
		end
		if a.distance ~= b.distance then
			return a.distance > b.distance
		end
		return a.entryId < b.entryId
	end)
	for i, racer in ipairs(list) do
		racer.position = i
	end
	return list
end

function RacerController:AllFinished()
	for _, racer in ipairs(self.racers) do
		if not racer.finished then
			return false
		end
	end
	return #self.racers > 0
end

-- Avansează simularea. Returnează lista concurenților care au terminat ÎN acest pas.
function RacerController:Step(dt)
	if self.paused then
		return {}
	end
	self.time += dt
	local newlyFinished = {}
	for _, racer in ipairs(self.racers) do
		local wasFinished = racer.finished
		self:_stepRacer(racer, dt)
		if racer.finished and not wasFinished then
			table.insert(newlyFinished, racer)
		end
	end
	return newlyFinished
end

-- Aplică pozițiile pe modele (fiecare model are Root ancorat; restul e sudat de el).
function RacerController:ApplyTransforms()
	for _, racer in ipairs(self.racers) do
		if racer.root and racer.root.Parent then
			racer.root.CFrame = self.track:CFrameAt(racer.distance, racer.lateral, racer.height)
		end
	end
end

-- Publică atributele pentru clienți (UI, cameră, aură) de max 10 ori/secundă.
function RacerController:Publish(dt, force)
	self._publishTimer += dt
	if not force and self._publishTimer < 0.1 then
		return
	end
	self._publishTimer = 0
	self:GetStandings()
	for _, racer in ipairs(self.racers) do
		local model = racer.model
		if model and model.Parent then
			model:SetAttribute("Speed", math.floor(racer.speed * 10 + 0.5) / 10)
			model:SetAttribute("Multiplier", racer.multiplier)
			model:SetAttribute("Distance", math.floor(racer.distance * 10 + 0.5) / 10)
			model:SetAttribute("Position", racer.position)
			model:SetAttribute("Finished", racer.finished)
			model:SetAttribute("Flying", racer.flight ~= nil)
			model:SetAttribute("FinishTime", racer.finishTime)
		end
	end
end

return RacerController
