--[[
	GiftRouter  (ModuleScript)
	Locație: ServerScriptService > Server > Services > GiftRouter

	Transformă un gift TikTok (venit prin BridgeService) într-o recompensă:
	  * un boost pentru PROPRIUL personaj al expeditorului, sau
	  * Skip Queue pentru PROPRIA înscriere.

	Regulile obligatorii aplicate aici:
	  1. Expeditorul e identificat prin tiktokUserId din eveniment (de la platformă).
	  2. Boost doar dacă expeditorul are un concurent în cursa ACTIVĂ (QueueService).
	  3. Boost doar cât fereastra de boost-uri e deschisă pentru acel raceId (RaceState),
	     iar gift-ul a fost primit DUPĂ deschidere (fără evenimente întârziate).
	  4. Nu există câmp „țintă”: e imposibil să afectezi personajul altcuiva.
	  5. Skip Queue nu poate introduce pe nimeni în cursa deja pornită.

	GiftRouter NU aplică efectul (asta face BoostService în Etapa 6); emite
	BoostRequested doar după ce toate verificările au trecut.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Validation = require(Shared:WaitForChild("Validation"))

local GiftRouter = {}
GiftRouter.__index = GiftRouter

GiftRouter.Codes = {
	BOOST = "BOOST",
	SKIP = "SKIP",
	INVALID_EVENT = "INVALID_EVENT",
	UNKNOWN_GIFT = "UNKNOWN_GIFT",
	BOOST_NOT_CONFIGURED = "BOOST_NOT_CONFIGURED",
	NOT_IN_RACE = "NOT_IN_RACE",
	RACE_NOT_RUNNING = "RACE_NOT_RUNNING",
	STALE_EVENT = "STALE_EVENT",
}
local C = GiftRouter.Codes

-- deps = { config, queue, raceState }
function GiftRouter.new(deps)
	local self = setmetatable({}, GiftRouter)
	self._config = deps.config
	self._queue = deps.queue
	self._raceState = deps.raceState
	self.BoostRequested = Signal.new() -- (request)
	self.SkipProcessed = Signal.new() -- (info)
	self.Rejected = Signal.new() -- (info) gift valid care nu activează nimic
	return self
end

-- Găsește recompensa pentru un gift: ById -> ByName (fără diferențe de majuscule) -> ByCoins
function GiftRouter:ResolveReward(gift)
	local cfg = self._config.Gifts
	-- cheile pot fi numere (Config) sau text (adăugate din panoul de admin)
	local byId = gift.id and (cfg.ById[gift.id] or cfg.ById[tostring(gift.id)])
	if byId then
		return byId
	end
	local wanted = string.lower(gift.name or "")
	if wanted ~= "" then
		for name, reward in pairs(cfg.ByName) do
			if string.lower(name) == wanted then
				return reward
			end
		end
	end
	if cfg.UseCoinFallback and (gift.diamonds or 0) > 0 then
		for _, tier in ipairs(cfg.ByCoins) do
			if gift.diamonds >= tier.MinCoins then
				return tier.Reward
			end
		end
	end
	return nil
end

local function parseGift(event)
	local g = event.gift
	if type(g) ~= "table" then
		return nil
	end
	local count = tonumber(g.count) or 1
	return {
		id = tonumber(g.id) or 0,
		name = Validation.sanitizeDisplayText(g.name, 40),
		diamonds = math.max(0, math.floor(tonumber(g.diamonds) or 0)),
		count = math.max(1, math.floor(count)),
	}
end

--[[
	event         : evenimentul "gift" din relay
	receivedClock : os.clock() la care evenimentul a fost primit de relay (ajustat cu ageMs)
	Returnează: { ok: boolean, code: string, reward?, count?, entry? }
]]
function GiftRouter:Handle(event, receivedClock)
	local tiktokUserId = Validation.normalizeTikTokUserId(event and event.tiktokUserId)
	local gift = event and parseGift(event)
	if not tiktokUserId or not gift then
		return { ok = false, code = C.INVALID_EVENT }
	end

	local senderName = Validation.sanitizeDisplayText(event.tiktokNickname ~= "" and event.tiktokNickname or event.tiktokUniqueId, 24)
	local info = { tiktokUserId = tiktokUserId, tiktokName = senderName, gift = gift }

	local reward = self:ResolveReward(gift)
	if not reward then
		info.code = C.UNKNOWN_GIFT
		self.Rejected:Fire(info)
		return { ok = false, code = C.UNKNOWN_GIFT }
	end
	info.reward = reward

	local count = math.min(gift.count, self._config.Gifts.MaxRepeatPerEvent)

	-- Skip Queue: doar pentru propria înscriere, doar pentru curse viitoare
	if reward == "SkipQueue" then
		local result, entry = self._queue:GrantSkip(tiktokUserId)
		info.code = C.SKIP
		info.skipResult = result
		info.entry = entry
		self.SkipProcessed:Fire(info)
		return { ok = true, code = C.SKIP, reward = reward, skipResult = result }
	end

	local boost = self._config.Boosts[reward]
	if not boost then
		warn("[GiftRouter] Recompensa „" .. tostring(reward) .. "” nu există în Config.Boosts")
		return { ok = false, code = C.BOOST_NOT_CONFIGURED }
	end

	local raceId = self._queue:GetActiveRaceId()
	local racer = raceId and self._queue:GetActiveRacerByTikTok(tiktokUserId, raceId)
	if not racer then
		info.code = C.NOT_IN_RACE
		self.Rejected:Fire(info)
		return { ok = false, code = C.NOT_IN_RACE }
	end

	local accepted, why = self._raceState:AcceptsBoostAt(raceId, receivedClock)
	if not accepted then
		info.code = why
		info.entry = racer
		self.Rejected:Fire(info)
		return { ok = false, code = why }
	end

	local request = {
		raceId = raceId,
		entry = racer, -- personajul EXPEDITORULUI, singurul posibil
		boostName = reward,
		boost = boost,
		count = count,
		gift = gift,
		tiktokName = senderName,
		eventId = event.id,
	}
	self.BoostRequested:Fire(request)
	return { ok = true, code = C.BOOST, reward = reward, count = count, entry = racer }
end

return GiftRouter
