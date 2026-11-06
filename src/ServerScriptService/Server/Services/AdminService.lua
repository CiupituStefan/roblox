--[[
	AdminService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > AdminService

	Comenzile panoului de administrare. SECURITATE:
	  * doar administratorii autorizați (Config.Admin.UserIds, proprietarul
	    jocului, rangul minim în grup sau oricine în Studio dacă e permis)
	  * verificarea se face pe SERVER la FIECARE comandă (atributul IsAdmin de
	    pe client doar afișează panoul, nu dă drepturi)
	  * limită de comenzi pe secundă; argumentele sunt validate
	  * setările trec prin lista albă din SettingsService

	Comenzi (Remotes.AdminCommand:FireServer(command, args)):
	  state                                  -> doar trimite starea
	  race.start | race.stop | race.pause | race.resume | race.abort | race.restart
	  set { path, value }                    -> modifică o setare (listă albă)
	  queue.add { robloxName }               -> adaugă manual în coadă
	  queue.remove { robloxName }            -> scoate din coadă
	  queue.priority { robloxName }          -> mută în coada prioritară
	  queue.clear                            -> golește coada de așteptare
	  queue.registration { open }            -> deschide/închide înscrierile
	  map.next { mapId }                     -> harta următoarei curse
	  settings.reset                         -> uită setările salvate
	  debug.loadtest { racers, giftsPerSecond, seconds } -> test de încărcare (Studio)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigSync = require(Shared:WaitForChild("ConfigSync"))
local Validation = require(Shared:WaitForChild("Validation"))

local AdminService = {}
AdminService.__index = AdminService

--[[
	deps = { config, remotes, queue, registration, race (RaceService), maps,
	         settings (SettingsService), log }
]]
function AdminService.new(deps)
	local self = setmetatable({}, AdminService)
	for k, v in pairs(deps) do
		self["_" .. k] = v
	end
	self._log = deps.log or print
	self._adminCache = {} -- player -> bool
	self._buckets = {} -- player -> { tokens, last }
	self._manualCounter = 0
	return self
end

---------------------------------------------------------------------------
-- Autorizare
---------------------------------------------------------------------------
function AdminService:IsAdmin(player)
	local cached = self._adminCache[player]
	if cached ~= nil then
		return cached
	end
	local cfg = self._config.Admin
	local isAdmin = false
	if table.find(cfg.UserIds, player.UserId) then
		isAdmin = true
	elseif game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and player.UserId == game.CreatorId then
		isAdmin = true
	elseif game.CreatorType == Enum.CreatorType.Group and game.CreatorId ~= 0 then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		isAdmin = ok and rank >= (cfg.GroupMinRank or 255)
	end
	if not isAdmin and RunService:IsStudio() and cfg.AllowAllInStudio then
		isAdmin = true
	end
	self._adminCache[player] = isAdmin
	return isAdmin
end

function AdminService:_allow(player)
	local bucket = self._buckets[player]
	local now = os.clock()
	if not bucket then
		bucket = { tokens = 15, last = now }
		self._buckets[player] = bucket
	end
	bucket.tokens = math.min(15, bucket.tokens + (now - bucket.last) * 8)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

---------------------------------------------------------------------------
-- Starea pentru panou
---------------------------------------------------------------------------
function AdminService:BuildState()
	local config = self._config
	local race = self._race
	local settings = {}
	for path in pairs(self._settings.Rules) do
		settings[path] = ConfigSync.get(config, path)
	end
	local boosts = {}
	for name, boost in pairs(config.Boosts) do
		local fields = {}
		for field in pairs(self._settings.BoostFieldRules) do
			if boost[field] ~= nil then
				fields[field] = boost[field]
			end
		end
		boosts[name] = { displayName = boost.DisplayName or name, kind = boost.Kind, fields = fields }
	end
	local rewards = { "SkipQueue" }
	for name in pairs(config.Boosts) do
		table.insert(rewards, name)
	end
	table.sort(rewards)
	local byId = {}
	for id, reward in pairs(config.Gifts.ById) do
		byId[tostring(id)] = reward
	end
	local mounts = {}
	for _, m in ipairs(config.Mounts) do
		table.insert(mounts, { id = m.Id, name = m.DisplayName, icon = m.Icon, enabled = m.Enabled ~= false, weight = m.Weight or 1 })
	end
	local savedCount = 0
	for _ in pairs(self._settings:GetOverrides()) do
		savedCount += 1
	end
	local maps = {}
	for _, m in ipairs(config.Maps.List) do
		table.insert(maps, { id = m.Id, name = m.DisplayName, enabled = m.Enabled ~= false })
	end
	return {
		running = race:IsRunning(),
		paused = race:IsPaused(),
		phase = workspace:GetAttribute("RacePhase"),
		currentMap = workspace:GetAttribute("CurrentMapName"),
		nextMap = self._maps:GetNextOverride(),
		bridge = ReplicatedStorage:GetAttribute("BridgeStatus"),
		bridgeUrl = config.Bridge.BaseUrl,
		registrationOpen = self._queue:IsRegistrationOpen(),
		queue = self._queue:GetSnapshot(60),
		settings = settings,
		boosts = boosts,
		rewards = rewards,
		giftsByName = table.clone(config.Gifts.ByName),
		giftsById = byId,
		mounts = mounts,
		maps = maps,
		savedCount = savedCount,
		health = self._health and self._health:GetStats() or nil,
		raceStats = race:GetStats(),
		loadTestRunning = self._loadTester and self._loadTester.running or false,
		lastLoadTest = self._loadTester and self._loadTester.lastReport or nil,
		isStudio = RunService:IsStudio(),
	}
end

---------------------------------------------------------------------------
-- Comenzi
---------------------------------------------------------------------------
local function argName(args)
	local name = type(args) == "table" and args.robloxName
	return Validation.normalizeRobloxUsername(name)
end

local COMMANDS = {}

COMMANDS["state"] = function()
	return true, nil
end

COMMANDS["race.start"] = function(self)
	self._race:SetPaused(false)
	self._race:Start()
	return true, "Cursele au pornit"
end

COMMANDS["race.stop"] = function(self)
	self._race:Stop()
	return true, "Cursele se opresc (cursa curentă e anulată)"
end

COMMANDS["race.pause"] = function(self)
	self._race:SetPaused(true)
	return true, "Pauză"
end

COMMANDS["race.resume"] = function(self)
	self._race:SetPaused(false)
	return true, "Reluat"
end

COMMANDS["race.restart"] = function(self)
	self._race:Restart()
	return true, "Ciclul de curse a fost repornit"
end

COMMANDS["debug.loadtest"] = function(self, args)
	if not self._loadTester then
		return false, "Testul de încărcare nu este disponibil"
	end
	if not RunService:IsStudio() and not self._config.Debug.AllowLoadTestLive then
		return false, "Testul de încărcare e permis doar în Studio (Config.Debug.AllowLoadTestLive)"
	end
	if self._loadTester.running then
		return false, "Un test rulează deja"
	end
	args = type(args) == "table" and args or {}
	local opts = {
		racers = tonumber(args.racers) or 40,
		giftsPerSecond = tonumber(args.giftsPerSecond) or 20,
		seconds = tonumber(args.seconds) or 45,
	}
	task.spawn(function()
		local _, text = self._loadTester:RunAsync(opts)
		self._log("[Admin] Test de încărcare terminat: " .. tostring(text))
	end)
	return true, string.format("Test pornit: %d concurenți, %d gift-uri/s, %ds (rezultatul apare în Output și aici)", opts.racers, opts.giftsPerSecond, opts.seconds)
end

COMMANDS["race.abort"] = function(self)
	if not self._race:GetCurrent() then
		return false, "Nu există o cursă în desfășurare"
	end
	self._race:AbortCurrentRace()
	return true, "Cursa curentă este anulată"
end

COMMANDS["set"] = function(self, args)
	if type(args) ~= "table" then
		return false, "argumente invalide"
	end
	local ok, result = self._settings:Set(args.path, args.value)
	if not ok then
		return false, tostring(args.path) .. ": " .. tostring(result)
	end
	return true, string.format("%s = %s", args.path, tostring(result == ConfigSync.NIL and "(șters)" or result))
end

COMMANDS["queue.add"] = function(self, args)
	local name, err = argName(args)
	if not name then
		return false, "Username invalid (" .. tostring(err) .. ")"
	end
	-- identitate TikTok sintetică, unică: participantul adăugat manual nu poate primi boost-uri din gift-uri
	self._manualCounter += 1
	local syntheticId = string.format("9%012d%03d", os.time() % 1e12, self._manualCounter % 1000)
	task.spawn(function()
		self._registration:RequestJoinAsync({
			tiktokUserId = syntheticId,
			tiktokName = "Admin",
			robloxName = name,
			source = "admin",
			bypassCooldown = true,
		})
	end)
	return true, "Se adaugă " .. name .. "..."
end

COMMANDS["queue.remove"] = function(self, args)
	local name = argName(args)
	if not name then
		return false, "Username invalid"
	end
	local ok = self._queue:RemoveQueuedByRobloxName(name)
	return ok, ok and (name .. " a fost scos din coadă") or (name .. " nu este în coadă")
end

COMMANDS["queue.priority"] = function(self, args)
	local name = argName(args)
	local entry = name and self._queue:FindQueuedByRobloxName(name)
	if not entry then
		return false, tostring(name) .. " nu este în coadă"
	end
	local result = self._queue:GrantSkip(entry.tiktokUserId)
	return true, name .. ": " .. tostring(result)
end

COMMANDS["queue.clear"] = function(self)
	local removed = self._queue:ClearQueued()
	return true, removed .. " persoane scoase din coadă"
end

COMMANDS["queue.registration"] = function(self, args)
	local open = type(args) == "table" and args.open == true
	self._queue:SetRegistrationOpen(open)
	return true, open and "Înscrieri deschise" or "Înscrieri închise"
end

COMMANDS["map.next"] = function(self, args)
	local mapId = type(args) == "table" and args.mapId
	for _, map in ipairs(self._config.Maps.List) do
		if map.Id == mapId then
			self._maps:SetNext(mapId)
			return true, "Următoarea hartă: " .. map.DisplayName
		end
	end
	return false, "Hartă necunoscută"
end

COMMANDS["settings.reset"] = function(self)
	self._settings:ClearSaved()
	return true, "Setările salvate au fost șterse (valorile din Config revin după repornirea serverului)"
end

function AdminService:_handle(player, command, args)
	if not self:IsAdmin(player) then
		self._log("[Admin] Comandă respinsă (nu e admin):", player.Name, tostring(command))
		return
	end
	if not self:_allow(player) then
		return
	end
	local handler = type(command) == "string" and COMMANDS[command]
	local ok, message
	if not handler then
		ok, message = false, "Comandă necunoscută"
	else
		local success, a, b = pcall(handler, self, args)
		if success then
			ok, message = a, b
		else
			ok, message = false, "Eroare: " .. tostring(a)
		end
	end
	if command ~= "state" then
		self._log(string.format("[Admin] %s: %s -> %s %s", player.Name, tostring(command), ok and "OK" or "RESPINS", tostring(message or "")))
	end
	self._remotes.AdminResult:FireClient(player, {
		command = command,
		ok = ok,
		message = message,
		state = self:BuildState(),
	})
end

function AdminService:Start()
	local function onPlayer(player)
		if self:IsAdmin(player) then
			player:SetAttribute("IsAdmin", true) -- doar pentru afișarea panoului
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		self._adminCache[player] = nil
		self._buckets[player] = nil
	end)
	self._remotes.AdminCommand.OnServerEvent:Connect(function(player, command, args)
		self:_handle(player, command, args)
	end)
end

return AdminService
