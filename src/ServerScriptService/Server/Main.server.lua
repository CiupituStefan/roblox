--[[
	Main  (Script)
	Locație: ServerScriptService > Server > Main

	Punctul de pornire al serverului. Creează serviciile, le conectează între ele
	și transmite starea către clienți (UI).

	Etapa 1: Queue + identificare Roblox + înscriere
	Etapa 2: BridgeService (relay TikTok) + GiftRouter + RaceState
	Etapa 3: AvatarService + MountFactory + PreRaceService (roata norocului)
	Etapa 4: MapService + MapBuilder + TrackMath (6 hărți, start/finish, grilă)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Validation = require(Shared:WaitForChild("Validation"))

local Server = script.Parent
local Services = Server:WaitForChild("Services")
local QueueService = require(Services:WaitForChild("QueueService"))
local RobloxUserService = require(Services:WaitForChild("RobloxUserService"))
local RegistrationService = require(Services:WaitForChild("RegistrationService"))
local RaceState = require(Services:WaitForChild("RaceState"))
local GiftRouter = require(Services:WaitForChild("GiftRouter"))
local BridgeService = require(Services:WaitForChild("BridgeService"))
local AvatarService = require(Services:WaitForChild("AvatarService"))
local MountFactory = require(Services:WaitForChild("MountFactory"))
local StagingArea = require(Services:WaitForChild("StagingArea"))
local PreRaceService = require(Services:WaitForChild("PreRaceService"))
local MapService = require(Services:WaitForChild("MapService"))

local Players = game:GetService("Players")
-- Streamerul nu are personaj: clientul lui este doar camera transmisă pe TikTok.
Players.CharacterAutoLoads = Config.Stream.SpawnStreamerCharacter

local function log(...)
	if Config.Debug.VerboseLogs then
		print("[Main]", ...)
	end
end

---------------------------------------------------------------------------
-- 0) Teste automate (doar în Studio)
---------------------------------------------------------------------------
if RunService:IsStudio() and Config.Debug.RunSelfTests then
	local tests = Server:FindFirstChild("Tests")
	for _, specName in ipairs({ "QueueService.spec", "GiftRouter.spec", "Mounts.spec", "Maps.spec" }) do
		local module = tests and tests:FindFirstChild(specName)
		if module then
			local ok, err = pcall(function()
				require(module).run()
			end)
			if not ok then
				warn("[Main] Testul " .. specName .. " nu a putut rula:", err)
			end
		else
			warn("[Main] Lipsește testul Tests/" .. specName)
		end
	end
end

---------------------------------------------------------------------------
-- 1) Servicii
---------------------------------------------------------------------------
RobloxUserService.SetMaxConcurrent(Config.Registration.MaxConcurrentLookups)

local queue = QueueService.new({
	maxQueueSize = Config.Queue.MaxSize,
	skipCreditTTL = Config.Queue.SkipCreditTTLSeconds,
	now = os.time,
})
queue:SetRegistrationOpen(Config.Registration.Enabled)

local registration = RegistrationService.new({
	queue = queue,
	userService = RobloxUserService,
	config = Config,
})

local raceState = RaceState.new()

local giftRouter = GiftRouter.new({
	config = Config,
	queue = queue,
	raceState = raceState,
})

local mountFactory = MountFactory.new()
local mountErrors = mountFactory:PrebuildAll(Config.Mounts) -- toate șabloanele, o singură dată
for _, err in ipairs(mountErrors) do
	warn("[Main] Mount:", err)
end

local staging = StagingArea.new()
local maps = MapService.new({ config = Config })
local avatars = AvatarService.new({ users = RobloxUserService })
local preRace = PreRaceService.new({
	config = Config,
	queue = queue,
	avatars = avatars,
	mounts = mountFactory,
	staging = staging,
	remotes = Remotes,
	users = RobloxUserService,
})

-- Registru partajat între servicii. Etapele următoare primesc `App` explicit
-- (nu folosim _G, ca să nu existe stare globală ascunsă).
local App = {
	Config = Config,
	Remotes = Remotes,
	Queue = queue,
	Users = RobloxUserService,
	Registration = registration,
	RaceState = raceState,
	Gifts = giftRouter,
	Mounts = mountFactory,
	Avatars = avatars,
	Staging = staging,
	PreRace = preRace,
	Maps = maps,
}

---------------------------------------------------------------------------
-- 2) Transmiterea stării către clienți (throttled: max ~4 actualizări/secundă)
---------------------------------------------------------------------------
local dirty = true
local lastSent = 0
local SEND_INTERVAL = 0.25

local function buildState()
	return {
		queue = queue:GetSnapshot(Config.Queue.VisibleInUI),
		race = raceState:Snapshot(),
		bridge = ReplicatedStorage:GetAttribute("BridgeStatus"),
		serverTime = workspace:GetServerTimeNow(),
	}
end

local function markDirty()
	dirty = true
end
queue.Changed:Connect(markDirty)
raceState.Changed:Connect(markDirty)
ReplicatedStorage:GetAttributeChangedSignal("BridgeStatus"):Connect(markDirty)

RunService.Heartbeat:Connect(function()
	if dirty and os.clock() - lastSent >= SEND_INTERVAL then
		dirty = false
		lastSent = os.clock()
		Remotes.StateUpdate:FireAllClients(buildState())
	end
end)

Remotes.GetState.OnServerInvoke = function(_player)
	return buildState()
end

local function announce(kind, text, extra)
	local payload = extra or {}
	payload.kind = kind
	payload.text = text
	Remotes.Announce:FireAllClients(payload)
	log("📣", kind, text)
end

local function formatMessage(code, name)
	local template = RegistrationService.Messages[code]
	if not template or template == "" then
		return nil
	end
	return string.format(template, name or "?")
end

---------------------------------------------------------------------------
-- 3) Rezultatele înscrierilor
---------------------------------------------------------------------------
registration.Processed:Connect(function(result)
	if result.message and result.message ~= "" then
		announce(result.ok and "join" or "joinRejected", result.message, {
			robloxName = result.robloxName,
			robloxUserId = result.entry and result.entry.robloxUserId or nil,
			priority = result.entry and result.entry.lane == "priority" or nil,
		})
	end
end)

task.spawn(function()
	while true do
		task.wait(60)
		registration:Cleanup()
	end
end)

---------------------------------------------------------------------------
-- 4) Gift-uri: rezultate
---------------------------------------------------------------------------
-- Etapa 6 (BoostService) va aplica efectul real. Până atunci doar anunțăm.
giftRouter.BoostRequested:Connect(function(request)
	local boostName = request.boost.DisplayName or request.boostName
	local countText = request.count > 1 and (" x" .. request.count) or ""
	announce("boost", string.format("%s a activat %s%s pentru %s!", request.tiktokName, boostName, countText, request.entry.robloxName), {
		robloxUserId = request.entry.robloxUserId,
		boostName = request.boostName,
		count = request.count,
		giftName = request.gift.name,
	})
end)

local SKIP_TEXT = {
	PROMOTED = "%s a sărit coada! Intră în cursa următoare",
	ALREADY_PRIORITY = "%s este deja prioritar în coadă",
	CREDIT_STORED = "%s are Skip Queue pentru următoarea înscriere",
}
giftRouter.SkipProcessed:Connect(function(info)
	local name = info.entry and info.entry.robloxName or info.tiktokName
	announce("skip", string.format(SKIP_TEXT[info.skipResult] or "%s: Skip Queue", name))
end)

giftRouter.Rejected:Connect(function(info)
	-- Gift valid care nu activează nimic: mulțumim, fără boost.
	if Config.Gifts.ThankNonRacers then
		announce("giftThanks", string.format("Mulțumim %s pentru %s!", info.tiktokName, info.gift.name), {
			reason = info.code,
		})
	end
end)

---------------------------------------------------------------------------
-- 5) Evenimente din relay (TikTok LIVE)
---------------------------------------------------------------------------
local function displayNameOf(event)
	local nick = Validation.sanitizeDisplayText(event.tiktokNickname, 24)
	if nick == "" then
		nick = Validation.sanitizeDisplayText(event.tiktokUniqueId, 24)
	end
	return nick
end

local eventHandlers = {}

function eventHandlers.join(event)
	task.spawn(function()
		registration:RequestJoinAsync({
			tiktokUserId = event.tiktokUserId,
			tiktokName = displayNameOf(event),
			robloxName = event.robloxName,
			source = "tiktok",
			expectedRobloxUserId = (event.verified == true) and tonumber(event.robloxUserId) or nil,
		})
	end)
end

function eventHandlers.joinRejected(event)
	local text = formatMessage(event.code, Validation.sanitizeDisplayText(event.robloxName, 24))
	if text then
		announce("joinRejected", text)
	end
end

function eventHandlers.gift(event, receivedClock)
	giftRouter:Handle(event, receivedClock)
end

function eventHandlers.verifyCode(event)
	local code = tostring(event.code or ""):match("^RACE%-%u+$")
	if not code then
		return
	end
	announce("verifyCode", string.format("%s: pune codul %s în descrierea (About) profilului Roblox %s, apoi scrie !verify", displayNameOf(event), code, Validation.sanitizeDisplayText(event.robloxName, 24)), {
		code = code,
	})
end

local VERIFY_TEXT = {
	VERIFIED = "✅ %s este acum verificat. Scrie !join ca să intri în cursă",
	ALREADY_VERIFIED = "%s este deja verificat",
	CODE_NOT_FOUND = "Codul nu apare încă în profilul %s (încearcă din nou în câteva secunde)",
	CODE_EXPIRED = "Codul a expirat, scrie din nou !verify NumeRoblox",
	USER_NOT_FOUND = "Contul Roblox %s nu există",
	INVALID_USERNAME = "Username Roblox invalid: %s",
	LOOKUP_FAILED = "Roblox nu răspunde, încearcă din nou",
	MISSING_USERNAME = "Scrie !verify urmat de username-ul tău Roblox",
}
function eventHandlers.verifyResult(event)
	local template = VERIFY_TEXT[event.code]
	if template then
		announce("verify", string.format(template, Validation.sanitizeDisplayText(event.robloxName or displayNameOf(event), 24)))
	end
end

local bridge = BridgeService.new({
	config = Config,
	localSecrets = Server:FindFirstChild("LocalSecrets"),
	onEvent = function(event, receivedClock)
		local handler = eventHandlers[event.type]
		if handler then
			handler(event, receivedClock)
		elseif Config.Debug.VerboseLogs then
			log("Eveniment necunoscut din relay:", event.type)
		end
	end,
})
App.Bridge = bridge
bridge:Start()

---------------------------------------------------------------------------
-- 6) Simulare în Studio (fără TikTok)
---------------------------------------------------------------------------
if RunService:IsStudio() and Config.Debug.FakeJoinsInStudio then
	task.spawn(function()
		task.wait(2)
		log("Simulez înscrieri:", table.concat(Config.Debug.FakeUsernames, ", "))
		for index, name in ipairs(Config.Debug.FakeUsernames) do
			task.spawn(function()
				local result = registration:RequestJoinAsync({
					tiktokUserId = tostring(900000000 + index), -- ID TikTok fals, doar pentru test
					tiktokName = "Spectator" .. index,
					robloxName = name,
					source = "debug",
				})
				if result.ok then
					log(string.format("  ✔ %s -> UserId %d, poziția #%d (TikTok ID %s)", result.robloxName, result.entry.robloxUserId, result.position, result.tiktokUserId))
				else
					log(string.format("  ✖ %s -> %s", tostring(name), tostring(result.code)))
				end
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- 7) Anunțuri din pregătirea cursei
---------------------------------------------------------------------------
preRace.Dropped:Connect(function(entry, reason)
	announce("racerDropped", string.format("Avatarul lui %s nu s-a putut încărca, nu intră în cursă", entry.robloxName), {
		robloxUserId = entry.robloxUserId,
		reason = reason,
	})
end)

preRace.Mounted:Connect(function(handle, reveal)
	log(string.format("   🎡 %s -> %s %s", handle.entry.robloxName, reveal.mountIcon, reveal.mountName))
end)

--[[
	Ciclu de test (Studio): hartă nouă + coadă -> lobby (avatare originale) ->
	roata mount-urilor -> grila de start -> deplasare de previzualizare pe traseu
	la viteza de bază (fereastra de boost-uri deschisă pentru simulator) ->
	primul la finish câștigă -> curățare. Harta se schimbă la fiecare ciclu.
	Va fi înlocuit de RaceService (countdown, clasament, podium, boost-uri) în Etapa 5.
	    npm run sim -- gift 900000001 Rose   -> boost pentru concurentul 1
]]
local function previewDriveAsync(raceId, handles, map)
	local grid = map.GetGrid(#handles)
	local racers = {}
	local rng = Random.new()
	for i, handle in ipairs(handles) do
		if handle.mount then
			local slot = grid[i]
			handle.mount.PrimaryPart.CFrame = slot.cframe
			handle.model:SetAttribute("OnTrack", true)
			handle.model:SetAttribute("Distance", slot.distance)
			handle.model:SetAttribute("Lane", slot.lateral)
			table.insert(racers, {
				handle = handle,
				root = handle.mount.PrimaryPart,
				distance = slot.distance,
				lateral = slot.lateral,
				phase = rng:NextNumber(0, math.pi * 2),
				freq = rng:NextNumber(0.4, 0.9),
			})
		end
	end
	if #racers == 0 then
		return nil
	end

	task.wait(3) -- pe grilă (countdown-ul real vine în Etapa 5)
	raceState:Set(RaceState.Phases.Racing, raceId)
	raceState:OpenBoostWindow(raceId)

	local base = Config.Race.BaseSpeed
	local noise = Config.Race.SpeedNoisePercent / 100
	local finishDistance = map.finishDistance
	local winner = nil
	local clock = 0
	local lastAttributes = 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		clock += dt
		local publish = clock - lastAttributes >= 0.1
		if publish then
			lastAttributes = clock
		end
		for _, r in ipairs(racers) do
			-- variație simetrică (media 0): nimeni nu e avantajat pe termen lung
			local speed = base * (1 + noise * math.sin(clock * r.freq + r.phase))
			r.distance += speed * dt
			r.root.CFrame = map.track:CFrameAt(r.distance, r.lateral)
			if publish then
				r.handle.model:SetAttribute("Speed", speed)
				r.handle.model:SetAttribute("Distance", r.distance)
			end
			if not winner and r.distance >= finishDistance then
				winner = r.handle
			end
		end
	end)

	local started = os.clock()
	while not winner and os.clock() - started < Config.Debug.TestRaceSeconds do
		task.wait(0.2)
	end
	connection:Disconnect()
	for _, r in ipairs(racers) do
		r.handle.model:SetAttribute("Speed", 0)
	end
	return winner
end

local function runTestRaceAsync()
	if queue:GetQueuedCount() == 0 then
		return false
	end
	local raceId, racers = queue:TakeForRace(Config.Race.MaxRacers)
	if not raceId then
		return false
	end
	log(string.format("🏁 Cursă de test #%d: %d concurenți, încarc avatarurile și harta...", raceId, #racers))
	raceState:Set(RaceState.Phases.Lobby, raceId)

	-- harta se construiește în paralel cu încărcarea avatarurilor
	local map, mapErr
	local mapDone = false
	task.spawn(function()
		local ok, result, err = pcall(function()
			return maps:LoadAsync(Config.Debug.ForceMap or maps:ChooseNextId())
		end)
		if ok then
			map, mapErr = result, err
		else
			mapErr = result
		end
		mapDone = true
	end)

	local handles = preRace:PrepareAsync(raceId, racers)
	while not mapDone do
		task.wait(0.1)
	end
	if not map then
		warn("[Main] Harta nu s-a putut încărca:", mapErr)
	end
	if #handles == 0 or not map then
		preRace:Cleanup(handles)
		queue:EndRace(raceId)
		raceState:Set(RaceState.Phases.Idle)
		return true
	end
	announce("map", "🗺️ Harta: " .. map.displayName)

	raceState:Set(RaceState.Phases.Wheel, raceId)
	preRace:RunWheelAsync(raceId, handles)

	for _, handle in ipairs(handles) do
		log(string.format("    %s  <- gift-urile contului TikTok %s", handle.entry.robloxName, handle.entry.tiktokUserId))
	end
	local winner = previewDriveAsync(raceId, handles, map)
	raceState:Set(RaceState.Phases.Finished, raceId)
	if winner then
		announce("winner", "🏆 " .. winner.entry.robloxName .. " a câștigat pe " .. map.displayName .. "!", { robloxUserId = winner.entry.robloxUserId })
	end
	task.wait(4)
	preRace:Cleanup(handles)
	queue:EndRace(raceId)
	raceState:Set(RaceState.Phases.Idle)
	log("🏁 Cursa de test s-a încheiat; participanții NU au fost reintroduși în coadă. Următoarea cursă = hartă nouă.")
	return true
end

if RunService:IsStudio() and Config.Debug.StartTestRaceInStudio then
	task.spawn(function()
		task.wait(10) -- lăsăm timp înscrierilor simulate
		while true do
			local ok, ranOrErr = pcall(runTestRaceAsync)
			if not ok then
				warn("[Main] Eroare în cursa de test:", ranOrErr)
				preRace:CleanupAll()
				local activeId = queue:GetActiveRaceId()
				if activeId then
					queue:EndRace(activeId)
				end
				raceState:Set(RaceState.Phases.Idle)
			end
			task.wait((ok and ranOrErr) and 5 or 3) -- coadă goală: verificăm din nou peste 3s
		end
	end)
end

log("Server pornit. Etape active: 1 (Queue), 2 (Bridge + Gift-uri), 3 (Avatar + Mount-uri + Roată), 4 (Hărți). Bridge:", bridge:GetStatus(), "| în coadă:", App.Queue:GetQueuedCount())
