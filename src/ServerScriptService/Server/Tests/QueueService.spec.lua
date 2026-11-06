--[[
	QueueService.spec  (ModuleScript)
	Locație: ServerScriptService > Server > Tests > QueueService.spec

	Teste automate pentru regulile obligatorii ale cozii. Rulate de Main la
	pornire în Studio (Config.Debug.RunSelfTests = true). Nu fac cereri pe rețea.
]]

local QueueService = require(script.Parent.Parent.Services.QueueService)
local E = QueueService.Errors
local S = QueueService.SkipResults

local Spec = {}

local function makeQueue(maxSize)
	local clock = { t = 1000 }
	local q = QueueService.new({
		maxQueueSize = maxSize or 100,
		skipCreditTTL = 60,
		now = function()
			return clock.t
		end,
	})
	return q, clock
end

local function req(n)
	return {
		tiktokUserId = tostring(1000 + n),
		tiktokName = "tt" .. n,
		robloxUserId = 500 + n,
		robloxName = "Player" .. n,
	}
end

local tests = {}

tests["înscriere în ordine + poziții corecte"] = function(check)
	local q = makeQueue()
	for i = 1, 3 do
		local ok, entry, pos = q:Enqueue(req(i))
		check(ok, "enqueue " .. i)
		check(pos == i, "poziția " .. i .. " (primit " .. tostring(pos) .. ")")
		check(entry.status == "queued", "status queued")
	end
end

tests["respinge duplicat TikTok și cont Roblox deja luat"] = function(check)
	local q = makeQueue()
	q:Enqueue(req(1))
	local ok, err = q:Enqueue(req(1))
	check(not ok and err == E.ALREADY_QUEUED, "duplicat TikTok -> ALREADY_QUEUED")

	local other = req(2)
	other.robloxUserId = req(1).robloxUserId -- alt TikTok, același cont Roblox
	ok, err = q:Enqueue(other)
	check(not ok and err == E.ROBLOX_ACCOUNT_TAKEN, "cont Roblox luat -> ROBLOX_ACCOUNT_TAKEN")
end

tests["coadă plină și înscrieri închise"] = function(check)
	local q = makeQueue(2)
	q:Enqueue(req(1))
	q:Enqueue(req(2))
	local ok, err = q:Enqueue(req(3))
	check(not ok and err == E.QUEUE_FULL, "QUEUE_FULL")

	q:SetRegistrationOpen(false)
	local q2 = makeQueue()
	q2:SetRegistrationOpen(false)
	ok, err = q2:Enqueue(req(1))
	check(not ok and err == E.REGISTRATION_CLOSED, "REGISTRATION_CLOSED")
end

tests["Skip Queue: de pe locul 25 intră în următoarea cursă"] = function(check)
	local q = makeQueue()
	for i = 1, 30 do
		q:Enqueue(req(i))
	end
	local entry25 = q:FindByTikTok(req(25).tiktokUserId)
	check(q:GetPosition(entry25.id) == 25, "inițial pe 25")

	local result = q:GrantSkip(req(25).tiktokUserId)
	check(result == S.PROMOTED, "PROMOTED")
	check(q:GetPosition(entry25.id) == 1, "după skip pe locul 1")

	local raceId, racers = q:TakeForRace(12)
	check(raceId ~= nil, "cursa pornește")
	check(racers[1].tiktokUserId == req(25).tiktokUserId, "primul concurent e cel cu skip")
	check(#racers == 12, "12 concurenți")
	check(q:GetQueuedCount() == 18, "18 rămân în coadă")
end

tests["Skip înainte de înscriere = credit, nu intră în cursa activă"] = function(check)
	local q, clock = makeQueue()
	q:Enqueue(req(1))
	local raceId = q:TakeForRace(12)

	local result = q:GrantSkip(req(9).tiktokUserId)
	check(result == S.CREDIT_STORED, "credit stocat")
	check(q:GetActiveRacerByTikTok(req(9).tiktokUserId, raceId) == nil, "nu e în cursa activă")

	q:Enqueue(req(5))
	local ok, entry = q:Enqueue(req(9))
	check(ok and entry.lane == "priority", "creditul se aplică la înscriere")
	check(q:GetPosition(entry.id) == 1, "prioritar înaintea celor normali")

	-- creditul expiră
	q:GrantSkip(req(10).tiktokUserId)
	clock.t += 61
	local _, e10 = q:Enqueue(req(10))
	check(e10.lane == "normal", "credit expirat -> coadă normală")
end

tests["TakeForRace golește coada folosită; înscrierile noi merg separat"] = function(check)
	local q = makeQueue()
	for i = 1, 3 do
		q:Enqueue(req(i))
	end
	local raceId, racers = q:TakeForRace(12)
	check(#racers == 3, "3 concurenți")
	check(q:GetQueuedCount() == 0, "coada folosită e goală")

	local ok = q:Enqueue(req(4))
	check(ok, "înscriere nouă în timpul cursei")
	check(q:GetQueuedCount() == 1, "noul participant e în coada următoare")
	check(q:GetActiveRacerByTikTok(req(4).tiktokUserId, raceId) == nil, "nu e amestecat în cursa activă")

	local again, err = q:Enqueue(req(1))
	check(not again and err == E.ALREADY_RACING, "un concurent activ nu se poate reînscrie în timpul cursei")

	local nilRace, err2 = q:TakeForRace(12)
	check(nilRace == nil and err2 == E.RACE_ALREADY_ACTIVE, "nu pornește a doua cursă simultan")
end

tests["Boost-uri: doar propriul personaj, doar cursa activă"] = function(check)
	local q = makeQueue()
	q:Enqueue(req(1))
	q:Enqueue(req(2))
	local raceId = q:TakeForRace(12)
	q:Enqueue(req(3)) -- așteaptă cursa următoare

	local r1 = q:GetActiveRacerByTikTok(req(1).tiktokUserId, raceId)
	check(r1 and r1.robloxUserId == req(1).robloxUserId, "gift-ul lui 1 afectează doar personajul lui 1")
	check(q:GetActiveRacerByTikTok(req(3).tiktokUserId, raceId) == nil, "cel din coadă nu poate da boost")
	check(q:GetActiveRacerByTikTok("999999", raceId) == nil, "spectatorul neînscris nu poate da boost")
	check(q:GetActiveRacerByTikTok(req(1).tiktokUserId, raceId + 1) == nil, "raceId greșit respins")

	q:EndRace(raceId)
	check(q:GetActiveRacerByTikTok(req(1).tiktokUserId, raceId) == nil, "după final nu se mai pot da boost-uri")
end

tests["EndRace: participanții NU sunt reintroduși automat"] = function(check)
	local q = makeQueue()
	q:Enqueue(req(1))
	local raceId = q:TakeForRace(12)
	local ok, finished = q:EndRace(raceId)
	check(ok and #finished == 1, "cursa încheiată")
	check(q:GetQueuedCount() == 0, "nimeni reintrodus")
	check(q:FindByTikTok(req(1).tiktokUserId) == nil, "legătura TikTok eliberată")

	local again = q:Enqueue(req(1))
	check(again, "se poate înscrie din nou manual")

	local bad, err = q:EndRace(raceId)
	check(not bad and err == E.NO_ACTIVE_RACE, "EndRace dublu respins")
end

tests["Admin: eliminare din coadă și DropFromActive"] = function(check)
	local q = makeQueue()
	q:Enqueue(req(1))
	q:Enqueue(req(2))
	q:Enqueue(req(3))
	local ok = q:RemoveQueuedByRobloxName("player2")
	check(ok, "eliminat după nume (case-insensitive)")
	check(q:GetQueuedCount() == 2, "2 rămași")
	local e3 = q:FindByTikTok(req(3).tiktokUserId)
	check(q:GetPosition(e3.id) == 2, "pozițiile se recalculează")

	local raceId, racers = q:TakeForRace(12)
	check(q:DropFromActive(raceId, racers[1].id), "drop din cursă")
	check(q:GetActiveRacerByTikTok(racers[1].tiktokUserId, raceId) == nil, "cel eliminat nu mai e activ")
	check(#q:GetSnapshot().active == 1, "snapshot actualizat")
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
	local summary = string.format("[Tests] QueueService: %d trecute, %d eșuate", passed, failed)
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
	return failed == 0
end

return Spec
