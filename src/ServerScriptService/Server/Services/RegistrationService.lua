--[[
	RegistrationService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > RegistrationService

	Leagă o cerere de înscriere (venită din TikTok prin bridge, sau manual din
	panoul de admin) de QueueService:

	  cerere  ->  validare format  ->  anti-spam  ->  verificare duplicat (fără rețea)
	          ->  căutare cont Roblox + avatar  ->  QueueService:Enqueue

	Proprietarul înscrierii este tiktokUserId din EVENIMENTUL TikTok (identitatea
	expeditorului, furnizată de platformă), nu un nume scris în comentariu.
	Doar acel cont TikTok va putea activa boost-uri pentru acest concurent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Validation = require(Shared:WaitForChild("Validation"))

local RegistrationService = {}
RegistrationService.__index = RegistrationService

RegistrationService.Errors = {
	COOLDOWN = "COOLDOWN",
	PENDING = "PENDING", -- o cerere a aceleiași persoane e deja în procesare
}

-- Mesaje afișate pe ecran (pot fi traduse/modificate)
RegistrationService.Messages = {
	OK = "%s a intrat în coadă pe locul #%d",
	OK_PRIORITY = "%s a intrat în coadă cu PRIORITATE pe locul #%d",
	REGISTRATION_CLOSED = "Înscrierile sunt închise momentan",
	ALREADY_QUEUED = "%s, ești deja în coadă",
	ALREADY_RACING = "%s, ești deja în cursă",
	ROBLOX_ACCOUNT_TAKEN = "Contul Roblox %s este deja înscris",
	QUEUE_FULL = "Coada este plină, încearcă mai târziu",
	USER_NOT_FOUND = "Contul Roblox „%s” nu există",
	AVATAR_FAILED = "Avatarul lui %s nu a putut fi încărcat",
	LOOKUP_FAILED = "Roblox nu răspunde, încearcă din nou",
	INVALID_LENGTH = "Username Roblox invalid (3-20 caractere)",
	INVALID_CHARACTERS = "Username Roblox invalid (doar litere, cifre, _)",
	INVALID_FORMAT = "Username Roblox invalid",
	INVALID_TYPE = "Username Roblox invalid",
	INVALID_TIKTOK_ID = "Identitate TikTok invalidă",
	COOLDOWN = "",
	PENDING = "",
	-- coduri venite de la relay (verificare TikTok <-> Roblox)
	ROBLOX_BOUND_TO_OTHER = "Contul Roblox %s este verificat de alt cont TikTok",
	NOT_VERIFIED = "%s: verifică-ți întâi contul cu !verify NumeRoblox",
	MISSING_USERNAME = "Scrie !join urmat de username-ul tău Roblox",
	INVALID_USERNAME = "Username Roblox invalid: %s",
	ACCOUNT_MISMATCH = "Contul %s nu mai corespunde verificării, refă !verify",
}

--[[
	deps = { queue, userService, config }
]]
function RegistrationService.new(deps)
	local self = setmetatable({}, RegistrationService)
	self._queue = deps.queue
	self._users = deps.userService
	self._config = deps.config
	self._lastAttempt = {} -- tiktokUserId -> os.clock()
	self._pending = {} -- tiktokUserId -> true
	self._pendingRoblox = {} -- lowerRobloxName -> true (evită două cereri simultane pt același cont)
	-- (result) result = { ok, code, message, tiktokUserId, tiktokName, robloxName, entry?, position? }
	self.Processed = Signal.new()
	return self
end

function RegistrationService:_finish(result)
	local template = RegistrationService.Messages[result.code] or result.code
	if template ~= "" then
		local who = result.robloxName or result.tiktokName or "?"
		if result.ok then
			result.message = string.format(template, who, result.position or 0)
		else
			result.message = string.format(template, who)
		end
	end
	self.Processed:Fire(result)
	return result
end

--[[
	req = {
	    tiktokUserId : string|number  -- ID numeric stabil din evenimentul TikTok
	    tiktokName   : string         -- nume afișat (doar UI)
	    robloxName   : string         -- textul introdus de spectator
	    source       : "tiktok" | "admin" | "debug"
	    bypassCooldown : boolean?     -- doar pentru admin
	    expectedRobloxUserId : number? -- de la relay, când contul e verificat
	}
	Yield-uiește (face cereri la Roblox). Apelează-l într-un task.spawn.
]]
function RegistrationService:RequestJoinAsync(req)
	local result = {
		ok = false,
		tiktokName = Validation.sanitizeDisplayText(req.tiktokName, 24),
		source = req.source,
	}

	local tiktokUserId, idErr = Validation.normalizeTikTokUserId(req.tiktokUserId)
	if not tiktokUserId then
		result.code = idErr
		return self:_finish(result)
	end
	result.tiktokUserId = tiktokUserId

	-- anti-spam per cont TikTok
	local now = os.clock()
	local cooldown = self._config.Registration.PerUserCooldownSeconds
	if not req.bypassCooldown then
		local last = self._lastAttempt[tiktokUserId]
		if last and now - last < cooldown then
			result.code = RegistrationService.Errors.COOLDOWN
			return self:_finish(result)
		end
	end
	self._lastAttempt[tiktokUserId] = now

	if self._pending[tiktokUserId] then
		result.code = RegistrationService.Errors.PENDING
		return self:_finish(result)
	end

	local robloxName, nameErr = Validation.normalizeRobloxUsername(req.robloxName)
	if not robloxName then
		result.code = nameErr
		return self:_finish(result)
	end
	result.robloxName = robloxName

	-- verificare fără rețea (închis / deja în coadă / deja în cursă / plin)
	local precheck = self._queue:PrecheckTikTok(tiktokUserId)
	if precheck then
		result.code = precheck
		return self:_finish(result)
	end

	local robloxKey = string.lower(robloxName)
	if self._pendingRoblox[robloxKey] then
		result.code = "ROBLOX_ACCOUNT_TAKEN"
		return self:_finish(result)
	end

	self._pending[tiktokUserId] = true
	self._pendingRoblox[robloxKey] = true

	local account, lookupErr = self._users.ResolveAsync(robloxName)

	self._pending[tiktokUserId] = nil
	self._pendingRoblox[robloxKey] = nil

	if not account then
		result.code = lookupErr
		return self:_finish(result)
	end
	result.robloxName = account.username -- numele canonic de la Roblox

	-- Cont verificat de relay: UserId-ul trebuie să fie exact cel verificat
	-- (protecție dacă username-ul a fost schimbat și preluat de altcineva).
	if req.expectedRobloxUserId and tonumber(req.expectedRobloxUserId) ~= account.userId then
		result.code = "ACCOUNT_MISMATCH"
		return self:_finish(result)
	end

	local ok, entryOrErr, position = self._queue:Enqueue({
		tiktokUserId = tiktokUserId,
		tiktokName = result.tiktokName,
		robloxUserId = account.userId,
		robloxName = account.username,
		displayName = account.displayName,
	})
	if not ok then
		result.code = entryOrErr
		return self:_finish(result)
	end

	result.ok = true
	result.entry = entryOrErr
	result.position = position
	result.code = entryOrErr.lane == "priority" and "OK_PRIORITY" or "OK"
	return self:_finish(result)
end

-- Curăță periodic tabela de cooldown ca să nu crească la infinit în LIVE-uri lungi.
function RegistrationService:Cleanup()
	local now = os.clock()
	local cooldown = self._config.Registration.PerUserCooldownSeconds
	for id, last in pairs(self._lastAttempt) do
		if now - last > cooldown * 4 then
			self._lastAttempt[id] = nil
		end
	end
end

return RegistrationService
