--[[
	BridgeService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > BridgeService

	Comunicarea cu relay-ul extern (care primește evenimentele TikTok LIVE).
	Roblox nu poate primi conexiuni de intrare, așa că serverul INTEROGHEAZĂ
	relay-ul (polling) prin HttpService:

	    GET {BaseUrl}/events?cursor=<N|resume>&limit=100
	    Authorization: Bearer <cheia din Roblox Secrets Store>

	* cursor = ultimul eveniment procesat -> trimiterea lui confirmă (ack) procesarea
	* la pornire cursor = "resume" -> relay-ul continuă de unde a rămas și omite
	  gift-urile prea vechi
	* deduplicare locală după event.id (protecție dublă, pe lângă relay)
	* backoff exponențial la erori, status vizibil în atributul
	  ReplicatedStorage.BridgeStatus (pentru panoul de admin)
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BridgeService = {}
BridgeService.__index = BridgeService

local function log(...)
	print("[BridgeService]", ...)
end

-- deps = { config, onEvent = function(event, receivedClock), localSecrets = ModuleScript? }
function BridgeService.new(deps)
	local self = setmetatable({}, BridgeService)
	self._config = deps.config
	self._onEvent = deps.onEvent
	self._localSecrets = deps.localSecrets
	self._cursor = "resume"
	self._running = false
	self._failures = 0
	self._status = "stopped"
	self._seenIds = {} -- id -> true
	self._seenOrder = {} -- FIFO pentru limitarea memoriei
	self._seenHead = 1
	self.stats = { requests = 0, events = 0, duplicates = 0, errors = 0 }
	return self
end

function BridgeService:_setStatus(status, detail)
	if self._status ~= status then
		self._status = status
		log("status:", status, detail or "")
	end
	ReplicatedStorage:SetAttribute("BridgeStatus", status)
end

function BridgeService:GetStatus()
	return self._status
end

--[[
	Cheia se citește din Roblox Secrets Store (Creator Hub -> joc -> Secrets).
	Obiectul Secret nu poate fi citit ca text de scripturi, doar trimis în header.
	În Studio, dacă secretul nu e disponibil, se poate folosi modulul LocalSecrets
	(ServerScriptService, nu ajunge niciodată la clienți).
]]
function BridgeService:_resolveAuth()
	local name = self._config.Bridge.SecretName
	local ok, secretOrErr = pcall(function()
		return HttpService:GetSecret(name)
	end)
	if ok and secretOrErr then
		return secretOrErr:AddPrefix("Bearer ")
	end
	if RunService:IsStudio() and self._localSecrets then
		local okReq, secrets = pcall(require, self._localSecrets)
		if okReq and type(secrets) == "table" and type(secrets[name]) == "string" and #secrets[name] >= 32 then
			warn("[BridgeService] Folosesc cheia din LocalSecrets (doar Studio).")
			return "Bearer " .. secrets[name]
		end
	end
	warn("[BridgeService] Secretul „" .. name .. "” nu este configurat: " .. tostring(secretOrErr))
	return nil
end

function BridgeService:_remember(id)
	if self._seenIds[id] then
		return false
	end
	self._seenIds[id] = true
	table.insert(self._seenOrder, id)
	local limit = self._config.Bridge.DedupeMemory
	if #self._seenOrder - self._seenHead + 1 > limit then
		local old = self._seenOrder[self._seenHead]
		self._seenOrder[self._seenHead] = nil
		self._seenIds[old] = nil
		self._seenHead += 1
	end
	return true
end

function BridgeService:_processBatch(body)
	local events = body.events
	if type(events) ~= "table" then
		return 0
	end
	local now = os.clock()
	for _, event in ipairs(events) do
		if type(event) == "table" and type(event.type) == "string" then
			local id = type(event.id) == "string" and event.id or ("seq:" .. tostring(event.seq))
			if self:_remember(id) then
				self.stats.events += 1
				local ageSeconds = math.clamp((tonumber(event.ageMs) or 0) / 1000, 0, 3600)
				local ok, err = pcall(self._onEvent, event, now - ageSeconds)
				if not ok then
					warn("[BridgeService] Eroare la procesarea evenimentului", event.type, err)
				end
			else
				self.stats.duplicates += 1
			end
		end
	end
	-- avansăm cursorul chiar dacă un eveniment a dat eroare (nu blocăm coada)
	if tonumber(body.cursor) then
		self._cursor = tostring(math.floor(tonumber(body.cursor)))
	end
	return #events
end

function BridgeService:_pollOnce(auth)
	local cfg = self._config.Bridge
	local url = string.format("%s/events?cursor=%s&limit=%d", cfg.BaseUrl, self._cursor, cfg.BatchLimit)
	self.stats.requests += 1
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = { Authorization = auth },
		})
	end)
	if not ok then
		return false, "HTTP_ERROR", tostring(response)
	end
	if response.StatusCode == 401 then
		return false, "UNAUTHORIZED", "cheie greșită (RELAY_KEY ≠ secretul Roblox)"
	end
	if not response.Success then
		return false, "HTTP_" .. tostring(response.StatusCode), response.StatusMessage
	end
	local decoded, body = pcall(HttpService.JSONDecode, HttpService, response.Body)
	if not decoded or type(body) ~= "table" then
		return false, "BAD_RESPONSE", "JSON invalid"
	end
	local count = self:_processBatch(body)
	return true, count, body.source
end

function BridgeService:Start()
	if self._running then
		return
	end
	local cfg = self._config.Bridge
	if not cfg.Enabled then
		self:_setStatus("disabled")
		return
	end
	if string.find(cfg.BaseUrl, "example.com", 1, true) then
		warn("[BridgeService] Config.Bridge.BaseUrl nu este setat. Bridge-ul nu pornește.")
		self:_setStatus("notConfigured")
		return
	end
	if not HttpService.HttpEnabled then
		warn("[BridgeService] Activează Game Settings > Security > Allow HTTP Requests.")
		self:_setStatus("httpDisabled")
		return
	end
	local auth = self:_resolveAuth()
	if not auth then
		self:_setStatus("noSecret")
		return
	end

	self._running = true
	self._generation = (self._generation or 0) + 1
	local generation = self._generation
	self:_setStatus("connecting")
	task.spawn(function()
		while self._running and self._generation == generation do
			local ok, countOrCode, detail = self:_pollOnce(auth)
			if ok then
				self._failures = 0
				self:_setStatus("connected", detail and ("sursă " .. tostring(detail)) or nil)
				ReplicatedStorage:SetAttribute("BridgeSource", tostring(detail))
				if countOrCode >= cfg.BatchLimit then
					-- mai sunt evenimente: continuăm repede, dar sub limita Roblox de
					-- 500 cereri HTTP/minut (0.15s => max ~400/minut)
					task.wait(0.15)
				else
					task.wait(cfg.PollIntervalSeconds)
				end
			else
				self._failures += 1
				self.stats.errors += 1
				local backoff = cfg.FailureBackoff[math.min(self._failures, #cfg.FailureBackoff)]
				self:_setStatus(countOrCode == "UNAUTHORIZED" and "unauthorized" or "error", tostring(detail))
				task.wait(backoff)
			end
		end
	end)
end

function BridgeService:Stop()
	self._running = false
	self._generation = (self._generation or 0) + 1
	self:_setStatus("stopped")
end

-- Repornire (ex. adresa relay-ului a fost schimbată din panoul de admin).
-- Cursorul se păstrează: nu se pierd și nu se dublează evenimente.
function BridgeService:Restart()
	self:Stop()
	self._failures = 0
	self:Start()
end

return BridgeService
