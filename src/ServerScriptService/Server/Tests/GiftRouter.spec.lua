--[[
	GiftRouter.spec  (ModuleScript)
	Locație: ServerScriptService > Server > Tests > GiftRouter.spec

	Testează regulile obligatorii pentru donații (fără rețea):
	doar concurenții activi, doar propriul personaj, doar în timpul cursei.
]]

local Services = script.Parent.Parent.Services
local QueueService = require(Services.QueueService)
local RaceState = require(Services.RaceState)
local GiftRouter = require(Services.GiftRouter)

local Spec = {}

local function makeConfig()
	return {
		Boosts = {
			SpeedBoost = { Kind = "Multiplier", Multiplier = 1.3, Duration = 3 },
			Turbo = { Kind = "Multiplier", Multiplier = 1.8, Duration = 2 },
			SuperSpeed = { Kind = "Multiplier", Multiplier = 2.2, Duration = 3 },
		},
		Gifts = {
			ById = { [999] = "SuperSpeed" },
			ByName = { ["Rose"] = "SpeedBoost", ["Finger Heart"] = "Turbo", ["Perfume"] = "SkipQueue", ["Broken"] = "NuExista" },
			ByCoins = { { MinCoins = 100, Reward = "SuperSpeed" }, { MinCoins = 1, Reward = "SpeedBoost" } },
			UseCoinFallback = true,
			MaxRepeatPerEvent = 5,
		},
	}
end

local function setup()
	local clock = { t = 100 }
	local now = function()
		return clock.t
	end
	local queue = QueueService.new({ now = now })
	local raceState = RaceState.new({ clock = now })
	local config = makeConfig()
	local router = GiftRouter.new({ config = config, queue = queue, raceState = raceState })
	for i = 1, 3 do
		queue:Enqueue({ tiktokUserId = tostring(i), tiktokName = "t" .. i, robloxUserId = 100 + i, robloxName = "P" .. i })
	end
	return router, queue, raceState, clock, config
end

local function gift(tiktokUserId, name, extra)
	local g = { id = 0, name = name, diamonds = 1, count = 1 }
	for k, v in pairs(extra or {}) do
		g[k] = v
	end
	return { type = "gift", id = "e" .. math.random(1, 1e9), tiktokUserId = tiktokUserId, tiktokNickname = "N", gift = g }
end

local function startRace(queue, raceState, clock, max)
	local raceId = queue:TakeForRace(max or 2) -- P1, P2 în cursă, P3 rămâne în coadă
	raceState:Set("Racing", raceId)
	raceState:OpenBoostWindow(raceId)
	clock.t += 1
	return raceId
end

local tests = {}

tests["ResolveReward: ById > ByName (fără majuscule) > ByCoins"] = function(check)
	local router = setup()
	check(router:ResolveReward({ id = 999, name = "Rose", diamonds = 1 }) == "SuperSpeed", "ById are prioritate")
	check(router:ResolveReward({ id = 0, name = "finger heart", diamonds = 5 }) == "Turbo", "ByName case-insensitive")
	check(router:ResolveReward({ id = 0, name = "Necunoscut", diamonds = 150 }) == "SuperSpeed", "ByCoins prag mare")
	check(router:ResolveReward({ id = 0, name = "Necunoscut", diamonds = 3 }) == "SpeedBoost", "ByCoins prag mic")
	check(router:ResolveReward({ id = 0, name = "Necunoscut", diamonds = 0 }) == nil, "fără potrivire")
end

tests["Concurent activ: boost doar pentru propriul personaj, count plafonat"] = function(check)
	local router, queue, raceState, clock = setup()
	startRace(queue, raceState, clock)
	local result = router:Handle(gift("1", "Rose", { count = 50 }), clock.t)
	check(result.ok and result.code == "BOOST", "boost acceptat")
	check(result.entry.robloxUserId == 101, "ținta este personajul expeditorului (P1)")
	check(result.count == 5, "count plafonat la MaxRepeatPerEvent")
end

tests["Spectator neînscris / în coadă: niciun boost"] = function(check)
	local router, queue, raceState, clock = setup()
	startRace(queue, raceState, clock)
	check(router:Handle(gift("777", "Rose"), clock.t).code == "NOT_IN_RACE", "neînscris respins")
	check(router:Handle(gift("3", "Rose"), clock.t).code == "NOT_IN_RACE", "cel din coadă (P3) respins")
end

tests["Fereastră închisă / eveniment întârziat / după final"] = function(check)
	local router, queue, raceState, clock = setup()
	local raceId = queue:TakeForRace(2)
	raceState:Set("Countdown", raceId)
	check(router:Handle(gift("1", "Rose"), clock.t).code == "RACE_NOT_RUNNING", "în countdown respins")

	clock.t += 5
	raceState:Set("Racing", raceId)
	raceState:OpenBoostWindow(raceId)
	check(router:Handle(gift("1", "Rose"), clock.t - 3).code == "STALE_EVENT", "trimis înainte de start respins")
	check(router:Handle(gift("1", "Rose"), clock.t + 1).ok, "trimis după start acceptat")

	raceState:Set("Finished", raceId)
	check(router:Handle(gift("1", "Rose"), clock.t + 2).code == "RACE_NOT_RUNNING", "după finish respins")
	queue:EndRace(raceId)
	raceState:Set("Idle")
	check(router:Handle(gift("1", "Rose"), clock.t + 3).code == "NOT_IN_RACE", "după EndRace respins")
end

tests["Skip Queue: doar propria înscriere, nu intră în cursa pornită"] = function(check)
	local router, queue, raceState, clock = setup()
	startRace(queue, raceState, clock, 1) -- P1 în cursă; P2, P3 în coadă
	local e3 = queue:FindByTikTok("3")
	check(queue:GetPosition(e3.id) == 2, "P3 inițial pe locul 2")

	local r = router:Handle(gift("3", "Perfume"), clock.t)
	check(r.ok and r.skipResult == "PROMOTED", "P3 promovat")
	check(queue:GetPosition(e3.id) == 1, "P3 acum primul")

	r = router:Handle(gift("1", "Perfume"), clock.t)
	check(r.skipResult == "CREDIT_STORED", "concurentul activ primește doar credit pentru viitor")
	check(queue:GetQueuedCount() == 2, "nimeni nu a fost mutat în/din cursă")
end

tests["Evenimente invalide / boost neconfigurat"] = function(check)
	local router, queue, raceState, clock = setup()
	startRace(queue, raceState, clock)
	check(router:Handle({ type = "gift", tiktokUserId = "abc", gift = {} }, clock.t).code == "INVALID_EVENT", "ID TikTok invalid")
	check(router:Handle({ type = "gift", tiktokUserId = "1" }, clock.t).code == "INVALID_EVENT", "fără gift")
	check(router:Handle(gift("1", "Broken", { diamonds = 0 }), clock.t).code == "BOOST_NOT_CONFIGURED", "recompensă inexistentă")
end

function Spec.run()
	local passed, failed = 0, 0
	for name, fn in pairs(tests) do
		local failures = {}
		local function check(cond, label)
			if not cond then
				table.insert(failures, label)
			end
		end
		local ok, err = pcall(fn, check)
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
	local summary = string.format("[Tests] GiftRouter: %d trecute, %d eșuate", passed, failed)
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
	return failed == 0
end

return Spec
