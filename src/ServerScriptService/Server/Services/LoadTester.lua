--[[
	LoadTester  (ModuleScript)
	Locație: ServerScriptService > Server > Services > LoadTester

	Test de încărcare din panoul de admin (implicit doar în Studio):
	  1. adaugă N concurenți de test în coadă (avatare generate, fără cereri la Roblox)
	  2. ridică temporar Config.Race.MaxRacers ca toți să intre în aceeași cursă
	  3. când cursa pornește, trimite o „furtună” de gift-uri prin GiftRouter
	     (exact drumul real: validare -> BoostService -> efecte), 70% de la
	     concurenți și 30% de la spectatori care nu sunt în cursă
	  4. raportează: rezultate pe coduri, boost-uri aplicate/respinse,
	     FPS server, cel mai lent cadru, memorie înainte/după

	Concurenții de test au ID-uri TikTok sintetice (77xxxxxxxx) și dispar la
	finalul cursei, ca oricare alți participanți.
]]

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local LoadTester = {}
LoadTester.__index = LoadTester

local TEST_ID_BASE = 7700000000

-- deps = { config, queue, giftRouter, raceState, boosts, log }
function LoadTester.new(deps)
	local self = setmetatable({}, LoadTester)
	for k, v in pairs(deps) do
		self["_" .. k] = v
	end
	self._log = deps.log or print
	self.running = false
	self.lastReport = nil
	return self
end

local function memory()
	local ok, mb = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	return ok and mb or 0
end

--[[
	opts = { racers = 40, giftsPerSecond = 20, seconds = 45 }
	Yield-uiește până la final. Returnează raportul (tabel) și textul.
]]
function LoadTester:RunAsync(opts)
	if self.running then
		return nil, "Un test rulează deja"
	end
	self.running = true
	local racers = math.clamp(math.floor(opts.racers or 40), 1, 60)
	local rate = math.clamp(opts.giftsPerSecond or 20, 1, 200)
	local seconds = math.clamp(opts.seconds or 45, 5, 300)
	local config = self._config
	local report = { racers = racers, giftsPerSecond = rate, seconds = seconds, codes = {}, applied = 0, dropped = 0 }
	local memBefore = memory()

	local previousMax = config.Race.MaxRacers
	config.Race.MaxRacers = math.max(previousMax, racers)

	-- 1) concurenții de test
	local runId = math.floor(os.clock() * 10) % 100000
	local tiktokIds = {}
	local added = 0
	for i = 1, racers do
		local tiktokUserId = tostring(TEST_ID_BASE + runId * 100 + i)
		local ok = self._queue:Enqueue({
			tiktokUserId = tiktokUserId,
			tiktokName = "LoadBot" .. i,
			robloxUserId = -(runId * 100 + i), -- negativ: nu poate coincide cu un cont real
			robloxName = "LoadBot" .. i,
			displayName = "Bot " .. i,
			isTest = true,
		})
		if ok then
			added += 1
			table.insert(tiktokIds, tiktokUserId)
		end
	end
	self._log(string.format("[LoadTest] %d concurenți de test adăugați în coadă; aștept startul cursei...", added))

	-- 2) așteaptă cursa
	local waited = 0
	while self._raceState.phase ~= "Racing" and waited < 240 do
		waited += task.wait(0.5)
	end
	config.Race.MaxRacers = previousMax
	if self._raceState.phase ~= "Racing" then
		self.running = false
		return nil, "Cursa nu a pornit în 4 minute (cursele sunt pornite?)"
	end

	-- 3) furtuna de gift-uri + măsurători
	local giftNames = {}
	for name in pairs(config.Gifts.ByName) do
		table.insert(giftNames, name)
	end
	local appliedConn = self._boosts.Applied:Connect(function()
		report.applied += 1
	end)
	local droppedConn = self._boosts.Dropped:Connect(function()
		report.dropped += 1
	end)
	local frames, worst = 0, 0
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		worst = math.max(worst, dt)
	end)

	local rng = Random.new()
	local sent = 0
	local started = os.clock()
	local carry = 0
	while os.clock() - started < seconds and self._raceState.phase == "Racing" do
		local dt = task.wait(0.05)
		carry += dt * rate
		while carry >= 1 do
			carry -= 1
			sent += 1
			local fromRacer = rng:NextNumber() < 0.7
			local tiktokUserId = fromRacer and tiktokIds[rng:NextInteger(1, #tiktokIds)] or tostring(TEST_ID_BASE - rng:NextInteger(1, 100000))
			local result = self._giftRouter:Handle({
				type = "gift",
				id = "loadtest:" .. sent,
				tiktokUserId = tiktokUserId,
				tiktokNickname = "Bot",
				gift = { id = 0, name = giftNames[rng:NextInteger(1, #giftNames)], diamonds = 1, count = rng:NextInteger(1, 4) },
			}, os.clock())
			report.codes[result.code] = (report.codes[result.code] or 0) + 1
		end
	end
	local elapsed = os.clock() - started
	heartbeat:Disconnect()
	task.wait(1) -- lasă coada de boost-uri să se golească parțial
	appliedConn:Disconnect()
	droppedConn:Disconnect()

	report.sent = sent
	report.elapsed = elapsed
	report.fps = frames / math.max(elapsed, 0.001)
	report.worstFrameMs = worst * 1000
	report.memoryBeforeMb = memBefore
	report.memoryAfterMb = memory()

	local codes = {}
	for code, count in pairs(report.codes) do
		table.insert(codes, code .. "=" .. count)
	end
	table.sort(codes)
	local text = string.format(
		"Test: %d concurenți, %d gift-uri în %.0fs (%.1f/s) · %s · boost-uri aplicate %d, respinse %d · FPS server %.0f, cel mai lent cadru %.0f ms · memorie %d -> %d MB",
		added, sent, elapsed, sent / math.max(elapsed, 0.001), table.concat(codes, ", "), report.applied, report.dropped,
		report.fps, report.worstFrameMs, report.memoryBeforeMb, report.memoryAfterMb)
	self._log("[LoadTest] " .. text)
	self.lastReport = text
	self.running = false
	return report, text
end

return LoadTester
