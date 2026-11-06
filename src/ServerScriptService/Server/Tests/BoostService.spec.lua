--[[
	BoostService.spec  (ModuleScript)
	Locație: ServerScriptService > Server > Tests > BoostService.spec

	  * boost aplicat imediat pe personajul expeditorului (și doar pe al lui)
	  * rafale: cooldown + coadă, aplicate pe rând; coadă plină -> respins
	  * cerere pentru altă cursă / după închiderea ferestrei -> respinsă
	  * combo x3 -> durată / distanță mai mari
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrackMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TrackMath"))
local Services = script.Parent.Parent.Services
local RacerController = require(Services.RacerController)
local BoostService = require(Services.BoostService)

local Spec = {}
local tests = {}

local BOOSTS = {
	SpeedBoost = { DisplayName = "Speed Boost", Kind = "Multiplier", Multiplier = 1.5, Duration = 2, AuraBonus = 0.5 },
	RocketBoost = { DisplayName = "Rocket", Kind = "Impulse", Distance = 50, ImpulseTime = 1, AuraBonus = 1 },
	Jetpack = { DisplayName = "Jetpack", Kind = "Flight", Multiplier = 1.4, Duration = 3, FlightHeight = 12, AuraBonus = 1 },
}

local function setup()
	local clock = { t = 0 }
	local track = TrackMath.new({ Vector3.new(0, 0, 0), Vector3.new(0, 0, -1000) })
	local controller = RacerController.new({ track = track, finishDistance = 950, baseSpeed = 40, noisePercent = 0, maxMultiplier = 4 })
	controller:AddRacer({ entryId = 1, distance = 10, lateral = -5 })
	controller:AddRacer({ entryId = 2, distance = 10, lateral = 5 })
	local race = { raceId = 7, controller = controller, byEntry = {} }
	local open = { value = true }
	local service = BoostService.new({
		config = { BoostRules = { PerRacerCooldownSeconds = 0.5, MaxQueuedBoostsPerRacer = 3 } },
		getRace = function()
			return open.value and race or nil
		end,
		clock = function()
			return clock.t
		end,
		serverTime = function()
			return clock.t
		end,
	})
	return service, controller, clock, race, open
end

local function request(entryId, name, count, raceId)
	return {
		raceId = raceId or 7,
		entry = { id = entryId, robloxUserId = 100 + entryId, robloxName = "P" .. entryId },
		boostName = name,
		boost = BOOSTS[name],
		count = count or 1,
		tiktokName = "tt",
		gift = { name = "Rose" },
	}
end

tests["Aplicare imediată, doar pe expeditor"] = function(check)
	local service, controller = setup()
	check(service:Request(request(1, "SpeedBoost")) == "APPLIED", "aplicat")
	controller:Step(0.1)
	check(math.abs(controller:GetRacer(1).speed - 60) < 0.5, "concurentul 1 accelerat")
	check(math.abs(controller:GetRacer(2).speed - 40) < 0.5, "concurentul 2 neafectat")
end

tests["Rafală: cooldown, coadă, coadă plină"] = function(check)
	local service, _, clock = setup()
	check(service:Request(request(1, "SpeedBoost")) == "APPLIED", "primul aplicat")
	check(service:Request(request(1, "SpeedBoost")) == "QUEUED", "al doilea în coadă")
	check(service:Request(request(1, "SpeedBoost")) == "QUEUED", "al treilea în coadă")
	check(service:Request(request(1, "SpeedBoost")) == "QUEUED", "al patrulea în coadă")
	check(service:Request(request(1, "SpeedBoost")) == "QUEUE_FULL", "al cincilea respins (coadă max 3)")
	check(service:Request(request(2, "SpeedBoost")) == "APPLIED", "alt concurent nu e afectat de coada primului")
	service:Update()
	check(service:QueuedCount(1) == 3, "nimic aplicat înainte de cooldown")
	clock.t = 0.6
	service:Update()
	check(service:QueuedCount(1) == 2, "unul aplicat după cooldown")
	clock.t = 1.2
	service:Update()
	clock.t = 1.8
	service:Update()
	check(service:QueuedCount(1) == 0, "coada golită pe rând")
end

tests["Altă cursă / fereastră închisă -> respins, coada se golește"] = function(check)
	local service, _, _, _, open = setup()
	check(service:Request(request(1, "SpeedBoost", 1, 99)) == "RACE_MISMATCH", "raceId greșit respins")
	service:Request(request(1, "SpeedBoost"))
	service:Request(request(1, "SpeedBoost"))
	check(service:QueuedCount(1) == 1, "unul în coadă")
	open.value = false -- cursa s-a terminat
	service:Update()
	check(service:QueuedCount(1) == 0, "coada golită la închiderea ferestrei")
	check(service:Request(request(1, "SpeedBoost")) == "RACE_MISMATCH", "după final nu se mai aplică nimic")
end

tests["Combo: impuls și zbor scalate"] = function(check)
	local service, controller = setup()
	service:Request(request(1, "RocketBoost", 3))
	for _ = 1, 120 do
		controller:Step(1 / 60)
	end
	local diff = controller:GetRacer(1).distance - controller:GetRacer(2).distance
	check(math.abs(diff - 150) < 0.01, "Rocket x3 = 150 studs în plus (" .. diff .. ")")
	service:Request(request(2, "Jetpack", 1))
	for _ = 1, 60 do
		controller:Step(1 / 60)
	end
	check(controller:GetRacer(2).height > 8, "Jetpack: zboară")
end

function Spec.run()
	local passed, failed = 0, 0
	for name, fn in pairs(tests) do
		local failures = {}
		local ok, err = pcall(fn, function(cond, label)
			if not cond then
				table.insert(failures, label)
			end
		end)
		if not ok then
			table.insert(failures, "EROARE: " .. tostring(err))
		end
		if #failures == 0 then
			passed += 1
		else
			failed += 1
			warn("[TEST EȘUAT] " .. name .. " -> " .. table.concat(failures, "; "))
		end
	end
	local summary = string.format("[Tests] BoostService: %d trecute, %d eșuate", passed, failed)
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
	return failed == 0
end

return Spec
