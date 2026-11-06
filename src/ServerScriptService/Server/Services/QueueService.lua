--[[
	QueueService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > QueueService

	Inima sistemului de participare. Logică PURĂ (fără rețea), deci complet testabilă.

	Modelul de date
	---------------
	  Entry = {
	      id            : number   -- ID intern unic al înscrierii
	      tiktokUserId  : string   -- identitatea TikTok STABILĂ (numeric) = PROPRIETARUL
	      tiktokName    : string   -- doar pentru afișare
	      robloxUserId  : number   -- identificatorul permanent Roblox
	      robloxName    : string   -- username canonic (de la Roblox, nu din chat)
	      displayName   : string
	      status        : "queued" | "racing"
	      lane          : "priority" | "normal"
	      enqueuedAt    : number
	      raceId        : number?  -- setat când intră în cursă
	  }

	Liste SEPARATE (niciodată amestecate):
	  _priority  -> coada cu prioritate (Skip Queue), FIFO după momentul acordării
	  _normal    -> coada normală, FIFO după ordinea înscrierii
	  _active    -> concurenții cursei în desfășurare (cu raceId propriu)

	Reguli garantate:
	  * un cont TikTok are maxim O înscriere (în coadă SAU în cursă)
	  * un cont Roblox apare maxim o dată (în coadă SAU în cursă)
	  * TakeForRace mută concurenții din coadă în cursă și îi ȘTERGE din coadă
	  * EndRace șterge complet participanții – NU sunt reintroduși automat
	  * Skip Queue schimbă doar ordinea în coada viitoare, niciodată cursa activă
	  * boost-urile se validează cu GetActiveRacerByTikTok(tiktokUserId, raceId):
	    proprietarul e stabilit de identitatea TikTok din eveniment, nu de text
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local QueueService = {}
QueueService.__index = QueueService

QueueService.Errors = {
	REGISTRATION_CLOSED = "REGISTRATION_CLOSED",
	INVALID_REQUEST = "INVALID_REQUEST",
	ALREADY_QUEUED = "ALREADY_QUEUED",
	ALREADY_RACING = "ALREADY_RACING",
	ROBLOX_ACCOUNT_TAKEN = "ROBLOX_ACCOUNT_TAKEN",
	QUEUE_FULL = "QUEUE_FULL",
	NOT_FOUND = "NOT_FOUND",
	RACE_ALREADY_ACTIVE = "RACE_ALREADY_ACTIVE",
	NO_ACTIVE_RACE = "NO_ACTIVE_RACE",
	RACE_ID_MISMATCH = "RACE_ID_MISMATCH",
	QUEUE_EMPTY = "QUEUE_EMPTY",
}
local E = QueueService.Errors

QueueService.SkipResults = {
	PROMOTED = "PROMOTED", -- era în coada normală, a fost mutat în coada prioritară
	ALREADY_PRIORITY = "ALREADY_PRIORITY", -- era deja prioritar
	CREDIT_STORED = "CREDIT_STORED", -- nu era înscris: prioritatea se aplică la următoarea înscriere
}

-- opts: { maxQueueSize, skipCreditTTL, now = function() -> number }
function QueueService.new(opts)
	opts = opts or {}
	local self = setmetatable({}, QueueService)
	self._now = opts.now or os.time
	self._maxSize = opts.maxQueueSize or 300
	self._skipCreditTTL = opts.skipCreditTTL or 900

	self._entries = {} -- entryId -> Entry
	self._byTikTok = {} -- tiktokUserId -> entryId
	self._byRoblox = {} -- robloxUserId -> entryId
	self._priority = {} -- { entryId }
	self._normal = {} -- { entryId }
	self._skipCredits = {} -- tiktokUserId -> expiresAt
	self._active = nil -- { raceId, entryIds = {}, set = { [entryId] = true } }

	self._nextEntryId = 0
	self._nextRaceId = 0
	self._registrationOpen = true

	self.Changed = Signal.new() -- (reason: string)
	return self
end

---------------------------------------------------------------------------
-- utilitare interne
---------------------------------------------------------------------------
local function removeValue(array, value)
	local index = table.find(array, value)
	if index then
		table.remove(array, index)
		return true
	end
	return false
end

local function copyEntry(entry)
	return entry and table.clone(entry) or nil
end

function QueueService:_queuedCount()
	return #self._priority + #self._normal
end

function QueueService:_purgeExpiredCredits()
	local now = self._now()
	for tiktokUserId, expiresAt in pairs(self._skipCredits) do
		if expiresAt <= now then
			self._skipCredits[tiktokUserId] = nil
		end
	end
end

function QueueService:_deleteEntry(entryId)
	local entry = self._entries[entryId]
	if not entry then
		return nil
	end
	self._entries[entryId] = nil
	if self._byTikTok[entry.tiktokUserId] == entryId then
		self._byTikTok[entry.tiktokUserId] = nil
	end
	if self._byRoblox[entry.robloxUserId] == entryId then
		self._byRoblox[entry.robloxUserId] = nil
	end
	return entry
end

---------------------------------------------------------------------------
-- Înscrieri
---------------------------------------------------------------------------
function QueueService:SetRegistrationOpen(isOpen)
	self._registrationOpen = isOpen == true
	self.Changed:Fire("registration")
end

function QueueService:IsRegistrationOpen()
	return self._registrationOpen
end

function QueueService:SetMaxSize(n)
	self._maxSize = math.max(1, math.floor(n))
end

-- Verificare rapidă ÎNAINTE de căutarea pe rețea (economisește request-uri).
-- Returnează nil dacă persoana se poate înscrie, altfel codul de eroare.
function QueueService:PrecheckTikTok(tiktokUserId)
	if not self._registrationOpen then
		return E.REGISTRATION_CLOSED
	end
	local entryId = self._byTikTok[tiktokUserId]
	if entryId then
		local entry = self._entries[entryId]
		return entry.status == "racing" and E.ALREADY_RACING or E.ALREADY_QUEUED
	end
	if self:_queuedCount() >= self._maxSize then
		return E.QUEUE_FULL
	end
	return nil
end

--[[
	req = { tiktokUserId: string, tiktokName: string, robloxUserId: number,
	        robloxName: string, displayName: string? }
	Returnează: true, entryCopy, position   SAU   false, errorCode
]]
function QueueService:Enqueue(req)
	if type(req) ~= "table"
		or type(req.tiktokUserId) ~= "string"
		or type(req.robloxUserId) ~= "number"
		or type(req.robloxName) ~= "string"
	then
		return false, E.INVALID_REQUEST
	end

	local precheck = self:PrecheckTikTok(req.tiktokUserId)
	if precheck then
		return false, precheck
	end

	local existingRoblox = self._byRoblox[req.robloxUserId]
	if existingRoblox then
		-- contul Roblox e deja în coadă/cursă (ales de altcineva sau de aceeași persoană)
		return false, E.ROBLOX_ACCOUNT_TAKEN
	end

	self:_purgeExpiredCredits()

	self._nextEntryId += 1
	local entry = {
		id = self._nextEntryId,
		tiktokUserId = req.tiktokUserId,
		tiktokName = req.tiktokName or "",
		robloxUserId = req.robloxUserId,
		robloxName = req.robloxName,
		displayName = req.displayName or req.robloxName,
		status = "queued",
		lane = "normal",
		enqueuedAt = self._now(),
		raceId = nil,
		isTest = req.isTest == true, -- participant generat de testul de încărcare
	}

	if self._skipCredits[req.tiktokUserId] then
		self._skipCredits[req.tiktokUserId] = nil
		entry.lane = "priority"
		table.insert(self._priority, entry.id)
	else
		table.insert(self._normal, entry.id)
	end

	self._entries[entry.id] = entry
	self._byTikTok[entry.tiktokUserId] = entry.id
	self._byRoblox[entry.robloxUserId] = entry.id

	self.Changed:Fire("enqueue")
	return true, copyEntry(entry), self:GetPosition(entry.id)
end

---------------------------------------------------------------------------
-- Skip Queue (prioritate doar pentru PROPRIA înscriere, doar pentru curse viitoare)
---------------------------------------------------------------------------
-- Returnează: resultCode, entryCopy?
function QueueService:GrantSkip(tiktokUserId)
	local entryId = self._byTikTok[tiktokUserId]
	local entry = entryId and self._entries[entryId]

	if entry and entry.status == "queued" then
		if entry.lane == "priority" then
			return QueueService.SkipResults.ALREADY_PRIORITY, copyEntry(entry)
		end
		removeValue(self._normal, entry.id)
		entry.lane = "priority"
		table.insert(self._priority, entry.id)
		self.Changed:Fire("skip")
		return QueueService.SkipResults.PROMOTED, copyEntry(entry)
	end

	-- Nu e în coadă (sau e deja în cursa activă): NU îl băgăm în cursa pornită.
	-- Păstrăm un credit pentru următoarea lui înscriere.
	self._skipCredits[tiktokUserId] = self._now() + self._skipCreditTTL
	self.Changed:Fire("skipCredit")
	return QueueService.SkipResults.CREDIT_STORED, copyEntry(entry)
end

function QueueService:HasSkipCredit(tiktokUserId)
	local expiresAt = self._skipCredits[tiktokUserId]
	return expiresAt ~= nil and expiresAt > self._now()
end

---------------------------------------------------------------------------
-- Eliminare (admin)
---------------------------------------------------------------------------
function QueueService:RemoveQueued(entryId)
	local entry = self._entries[entryId]
	if not entry or entry.status ~= "queued" then
		return false, E.NOT_FOUND
	end
	removeValue(self._priority, entryId)
	removeValue(self._normal, entryId)
	self:_deleteEntry(entryId)
	self.Changed:Fire("remove")
	return true, copyEntry(entry)
end

function QueueService:FindQueuedByRobloxName(robloxName)
	local wanted = string.lower(robloxName or "")
	for _, list in ipairs({ self._priority, self._normal }) do
		for _, entryId in ipairs(list) do
			local entry = self._entries[entryId]
			if string.lower(entry.robloxName) == wanted then
				return copyEntry(entry)
			end
		end
	end
	return nil
end

-- Admin: golește coada de așteptare (cursa activă nu este afectată)
function QueueService:ClearQueued()
	local removed = 0
	for _, list in ipairs({ self._priority, self._normal }) do
		for _, entryId in ipairs(list) do
			self:_deleteEntry(entryId)
			removed += 1
		end
		table.clear(list)
	end
	self.Changed:Fire("clear")
	return removed
end

function QueueService:SetSkipCreditTTL(seconds)
	self._skipCreditTTL = seconds
end

function QueueService:RemoveQueuedByRobloxName(robloxName)
	local wanted = string.lower(robloxName or "")
	for _, list in ipairs({ self._priority, self._normal }) do
		for _, entryId in ipairs(list) do
			local entry = self._entries[entryId]
			if string.lower(entry.robloxName) == wanted then
				return self:RemoveQueued(entryId)
			end
		end
	end
	return false, E.NOT_FOUND
end

---------------------------------------------------------------------------
-- Ciclul cursei
---------------------------------------------------------------------------
--[[
	Mută până la maxCount participanți din coadă (prioritari întâi) în lista
	concurenților activi. Aceștia sunt ELIMINAȚI din coadă. Cei rămași
	așteaptă cursa următoare, iar înscrierile noi intră tot în coada de așteptare,
	complet separată de lista activă.
	Returnează: raceId, { entryCopy }   SAU   nil, errorCode
]]
function QueueService:TakeForRace(maxCount)
	if self._active then
		return nil, E.RACE_ALREADY_ACTIVE
	end
	if self:_queuedCount() == 0 then
		return nil, E.QUEUE_EMPTY
	end

	self._nextRaceId += 1
	local raceId = self._nextRaceId
	local active = { raceId = raceId, entryIds = {}, set = {} }
	local racers = {}

	local function take(list)
		while #active.entryIds < maxCount and #list > 0 do
			local entryId = table.remove(list, 1)
			local entry = self._entries[entryId]
			entry.status = "racing"
			entry.raceId = raceId
			table.insert(active.entryIds, entryId)
			active.set[entryId] = true
			table.insert(racers, copyEntry(entry))
		end
	end
	take(self._priority)
	take(self._normal)

	self._active = active
	self.Changed:Fire("raceStart")
	return raceId, racers
end

-- Un concurent nu a putut fi pregătit (ex: avatarul nu s-a încărcat) -> îl scoatem din cursă.
function QueueService:DropFromActive(raceId, entryId)
	local active = self._active
	if not active or active.raceId ~= raceId or not active.set[entryId] then
		return false
	end
	active.set[entryId] = nil
	removeValue(active.entryIds, entryId)
	self:_deleteEntry(entryId)
	self.Changed:Fire("drop")
	return true
end

--[[
	Încheie cursa: participanții sunt șterși complet (legăturile TikTok/Roblox
	se eliberează). NU sunt reintroduși în coadă. Pentru o nouă cursă trebuie
	să se înscrie din nou.
]]
function QueueService:EndRace(raceId)
	local active = self._active
	if not active then
		return false, E.NO_ACTIVE_RACE
	end
	if active.raceId ~= raceId then
		return false, E.RACE_ID_MISMATCH
	end
	local finished = {}
	for _, entryId in ipairs(active.entryIds) do
		local entry = self:_deleteEntry(entryId)
		if entry then
			table.insert(finished, entry)
		end
	end
	self._active = nil
	self.Changed:Fire("raceEnd")
	return true, finished
end

function QueueService:GetActiveRaceId()
	return self._active and self._active.raceId or nil
end

--[[
	VALIDAREA CENTRALĂ PENTRU BOOST-URI.
	Returnează intrarea concurentului DOAR dacă:
	  * există o cursă activă
	  * raceId-ul cerut este exact cursa activă (evenimente vechi sunt respinse)
	  * contul TikTok care a trimis gift-ul deține un concurent în această cursă
	Nu există niciun parametru „țintă”: un gift poate afecta doar personajul
	expeditorului.
]]
function QueueService:GetActiveRacerByTikTok(tiktokUserId, raceId)
	local active = self._active
	if not active or active.raceId ~= raceId then
		return nil
	end
	local entryId = self._byTikTok[tiktokUserId]
	if not entryId or not active.set[entryId] then
		return nil
	end
	return copyEntry(self._entries[entryId])
end

---------------------------------------------------------------------------
-- Interogări pentru UI
---------------------------------------------------------------------------
function QueueService:GetPosition(entryId)
	local index = table.find(self._priority, entryId)
	if index then
		return index
	end
	index = table.find(self._normal, entryId)
	if index then
		return #self._priority + index
	end
	return nil
end

function QueueService:FindByTikTok(tiktokUserId)
	local entryId = self._byTikTok[tiktokUserId]
	return copyEntry(entryId and self._entries[entryId])
end

function QueueService:GetQueuedCount()
	return self:_queuedCount()
end

--[[
	Snapshot serializabil (trimis clienților prin RemoteEvent).
	Nu include tiktokUserId (date interne, nu e nevoie să ajungă la clienți).
]]
function QueueService:GetSnapshot(maxVisible)
	maxVisible = maxVisible or 15
	local queued = {}
	local position = 0
	for _, list in ipairs({ self._priority, self._normal }) do
		for _, entryId in ipairs(list) do
			position += 1
			if position <= maxVisible then
				local entry = self._entries[entryId]
				table.insert(queued, {
					position = position,
					robloxUserId = entry.robloxUserId,
					robloxName = entry.robloxName,
					displayName = entry.displayName,
					tiktokName = entry.tiktokName,
					priority = entry.lane == "priority",
				})
			end
		end
	end

	local active = {}
	if self._active then
		for _, entryId in ipairs(self._active.entryIds) do
			local entry = self._entries[entryId]
			table.insert(active, {
				robloxUserId = entry.robloxUserId,
				robloxName = entry.robloxName,
				displayName = entry.displayName,
				tiktokName = entry.tiktokName,
			})
		end
	end

	return {
		registrationOpen = self._registrationOpen,
		queuedTotal = self:_queuedCount(),
		queued = queued,
		raceId = self:GetActiveRaceId(),
		active = active,
	}
end

return QueueService
