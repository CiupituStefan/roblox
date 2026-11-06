--[[
	BoostService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > BoostService

	Aplică boost-urile validate de GiftRouter pe personajul EXPEDITORULUI:
	  * verifică din nou că cererea este pentru cursa în desfășurare (raceId)
	  * cooldown scurt per concurent (Config.BoostRules.PerRacerCooldownSeconds);
	    gift-urile venite în rafală intră într-o coadă (max MaxQueuedBoostsPerRacer)
	    și se aplică pe rând, ca fiecare efect să fie vizibil pe stream
	  * Multiplier -> RacerController:AddModifier, Impulse -> AddImpulse,
	    Flight -> SetFlight + AddModifier
	  * trimite clienților BoostFx (efecte, sunet, bonus de aură)
	  * la finalul cursei coada se golește: nimic nu se aplică după finish

	Valorile (multiplicator, durată, distanță, efect, sunet) vin din Config.Boosts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local BoostService = {}
BoostService.__index = BoostService

--[[
	deps = {
	  config, getRace = function() -> { raceId, controller, byEntry }?,
	  remotes?, clock?, serverTime?
	}
]]
function BoostService.new(deps)
	local self = setmetatable({}, BoostService)
	self._config = deps.config
	self._getRace = deps.getRace
	self._remotes = deps.remotes
	self._clock = deps.clock or os.clock
	self._serverTime = deps.serverTime or function()
		return workspace:GetServerTimeNow()
	end
	self._queues = {} -- entryId -> { request, ... }
	self._lastApplied = {} -- entryId -> clock
	self._raceId = nil
	self.Applied = Signal.new() -- (request, fxPayload)
	self.Dropped = Signal.new() -- (request, reason)
	return self
end

-- Durata crește cu numărul de gift-uri (combo): fiecare bucată în plus adaugă 50%
local function scaledDuration(base, count)
	return base * (1 + 0.5 * (count - 1))
end

function BoostService:_apply(request, race)
	local controller = race.controller
	local boost, entryId, count = request.boost, request.entry.id, request.count
	local ok, duration = false, 0
	if boost.Kind == "Multiplier" then
		duration = scaledDuration(boost.Duration, count)
		ok = controller:AddModifier(entryId, request.boostName, boost.Multiplier, duration)
	elseif boost.Kind == "Impulse" then
		duration = boost.ImpulseTime
		ok = controller:AddImpulse(entryId, boost.Distance * count, boost.ImpulseTime)
	elseif boost.Kind == "Flight" then
		duration = scaledDuration(boost.Duration, count)
		ok = controller:SetFlight(entryId, boost.FlightHeight, duration)
		if ok then
			controller:AddModifier(entryId, request.boostName, boost.Multiplier, duration)
		end
	end
	if not ok then
		self.Dropped:Fire(request, "NOT_APPLICABLE") -- ex. a trecut deja de finish
		return false
	end

	local handle = race.byEntry and race.byEntry[entryId]
	local model = handle and handle.model
	local fx = {
		robloxUserId = request.entry.robloxUserId,
		robloxName = request.entry.robloxName,
		boostName = request.boostName,
		displayName = boost.DisplayName or request.boostName,
		kind = boost.Kind,
		vfx = boost.Vfx,
		sound = boost.Sound,
		duration = math.max(duration, 0.5),
		count = count,
		auraBonus = boost.AuraBonus or 0,
		tiktokName = request.tiktokName,
	}
	if model and model.Parent then
		-- bonusul de aură e citit de AuraRenderer (client) până la AuraBoostUntil
		local now = self._serverTime()
		local activeUntil = model:GetAttribute("AuraBoostUntil") or 0
		local activeBonus = activeUntil > now and (model:GetAttribute("AuraBoost") or 0) or 0
		model:SetAttribute("AuraBoost", math.max(fx.auraBonus, activeBonus))
		model:SetAttribute("AuraBoostUntil", math.max(now + fx.duration, activeUntil))
		model:SetAttribute("BoostCount", (model:GetAttribute("BoostCount") or 0) + count)
		model:SetAttribute("LastBoost", fx.displayName)
	end
	if self._remotes then
		self._remotes.BoostFx:FireAllClients(fx)
	end
	self.Applied:Fire(request, fx)
	return true
end

--[[
	Primește o cerere de la GiftRouter.BoostRequested.
	Returnează "APPLIED" | "QUEUED" | motivul respingerii.
]]
function BoostService:Request(request)
	local race = self._getRace()
	if not race or not race.controller or race.raceId ~= request.raceId then
		self.Dropped:Fire(request, "RACE_MISMATCH")
		return "RACE_MISMATCH"
	end
	if self._raceId ~= race.raceId then
		self:Reset()
		self._raceId = race.raceId
	end
	local entryId = request.entry.id
	local rules = self._config.BoostRules
	local queue = self._queues[entryId]
	local now = self._clock()
	local last = self._lastApplied[entryId]

	if (not queue or #queue == 0) and (not last or now - last >= rules.PerRacerCooldownSeconds) then
		if self:_apply(request, race) then
			self._lastApplied[entryId] = now
			return "APPLIED"
		end
		return "NOT_APPLICABLE"
	end

	queue = queue or {}
	self._queues[entryId] = queue
	if #queue >= rules.MaxQueuedBoostsPerRacer then
		self.Dropped:Fire(request, "QUEUE_FULL")
		return "QUEUE_FULL"
	end
	table.insert(queue, request)
	return "QUEUED"
end

-- Apelat periodic (ex. la 0.1s): aplică boost-urile din coadă după cooldown.
function BoostService:Update()
	local race = self._getRace()
	if not race or not race.controller or race.raceId ~= self._raceId then
		if next(self._queues) then
			self:Reset()
		end
		return
	end
	local now = self._clock()
	local cooldown = self._config.BoostRules.PerRacerCooldownSeconds
	for entryId, queue in pairs(self._queues) do
		local last = self._lastApplied[entryId]
		if #queue > 0 and (not last or now - last >= cooldown) then
			local request = table.remove(queue, 1)
			if self:_apply(request, race) then
				self._lastApplied[entryId] = now
			end
		end
		if #queue == 0 then
			self._queues[entryId] = nil
		end
	end
end

function BoostService:QueuedCount(entryId)
	local queue = self._queues[entryId]
	return queue and #queue or 0
end

-- Golește tot (la finalul cursei): niciun boost nu se aplică după finish.
function BoostService:Reset()
	self._queues = {}
	self._lastApplied = {}
	self._raceId = nil
end

return BoostService
