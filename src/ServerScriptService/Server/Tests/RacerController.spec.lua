--[[
	RacerController.spec  (ModuleScript)
	Locație: ServerScriptService > Server > Tests > RacerController.spec

	Testează simularea cursei fără modele (pe un traseu drept de 1000 studs):
	  * toți pornesc cu aceeași viteză; fără boost-uri nimeni nu e avantajat sistematic
	  * modificatori: aceeași cheie reîmprospătează, chei diferite -> maximul, expiră
	  * plafonul MaxSpeedMultiplier
	  * impulsuri: distanța totală exactă
	  * ordinea la finish, clasamentul, pauza
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrackMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TrackMath"))
local RacerController = require(script.Parent.Parent.Services.RacerController)

local Spec = {}
local tests = {}

local function makeController(noise)
	local track = TrackMath.new({ Vector3.new(0, 0, 0), Vector3.new(0, 0, -500), Vector3.new(0, 0, -1000) })
	local controller = RacerController.new({
		track = track,
		finishDistance = 900,
		baseSpeed = 40,
		noisePercent = noise or 0,
		maxMultiplier = 3,
		rng = Random.new(42),
	})
	for i = 1, 4 do
		controller:AddRacer({ entryId = i, distance = 20, lateral = (i - 2.5) * 10 })
	end
	return controller
end

local function run(controller, seconds, dt)
	dt = dt or 1 / 60
	local finished = {}
	for _ = 1, math.floor(seconds / dt + 0.5) do
		for _, r in ipairs(controller:Step(dt)) do
			table.insert(finished, r)
		end
	end
	return finished
end

tests["Viteză egală pentru toți fără boost-uri"] = function(check)
	local c = makeController(0)
	run(c, 5)
	local d = c:GetRacer(1).distance
	for i = 2, 4 do
		check(math.abs(c:GetRacer(i).distance - d) < 1e-6, "concurentul " .. i .. " are aceeași distanță")
	end
	check(math.abs(d - (20 + 40 * 5)) < 0.5, "distanța = viteza de bază x timp (" .. d .. ")")
end

tests["Variația aleatorie are media ~0"] = function(check)
	local c = makeController(4)
	run(c, 20)
	for i = 1, 4 do
		local travelled = c:GetRacer(i).distance - 20
		check(math.abs(travelled - 800) / 800 < 0.03, "concurentul " .. i .. " a parcurs ~800 (" .. math.floor(travelled) .. ")")
	end
end

tests["Modificatori: maxim, reîmprospătare, expirare, plafon"] = function(check)
	local c = makeController(0)
	c:AddModifier(1, "SpeedBoost", 1.5, 2)
	c:AddModifier(1, "Turbo", 2.0, 1)
	run(c, 0.5)
	check(math.abs(c:GetRacer(1).speed - 80) < 0.5, "maximul (2.0) se aplică: " .. c:GetRacer(1).speed)
	run(c, 1)
	check(math.abs(c:GetRacer(1).speed - 60) < 0.5, "după expirarea Turbo rămâne SpeedBoost 1.5: " .. c:GetRacer(1).speed)
	c:AddModifier(1, "SpeedBoost", 1.5, 3) -- reîmprospătare
	run(c, 2)
	check(math.abs(c:GetRacer(1).speed - 60) < 0.5, "reîmprospătat, încă activ")
	run(c, 1.5)
	check(math.abs(c:GetRacer(1).speed - 40) < 0.5, "expirat -> viteza de bază")
	c:AddModifier(2, "Mega", 10, 2)
	run(c, 0.2)
	check(math.abs(c:GetRacer(2).speed - 120) < 0.5, "plafon MaxSpeedMultiplier = 3")
	check(math.abs(c:GetRacer(3).speed - 40) < 0.5, "boost-ul nu afectează alți concurenți")
end

tests["Impuls: distanța suplimentară exactă"] = function(check)
	local c = makeController(0)
	c:AddImpulse(1, 60, 1.2)
	run(c, 3)
	local diff = c:GetRacer(1).distance - c:GetRacer(2).distance
	check(math.abs(diff - 60) < 0.01, "avans exact de 60 studs (" .. diff .. ")")
end

tests["Zbor: urcă și coboară"] = function(check)
	local c = makeController(0)
	c:SetFlight(1, 14, 2)
	run(c, 1.5)
	check(c:GetRacer(1).height > 10, "în aer")
	run(c, 2.5)
	check(c:GetRacer(1).height < 1, "a aterizat")
end

tests["Finish: ordine, clasament, oprire după linie"] = function(check)
	local c = makeController(0)
	c:AddModifier(3, "Turbo", 2, 100)
	local finished = run(c, 30)
	check(#finished == 4, "toți au terminat")
	check(finished[1].entryId == 3, "cel cu boost a câștigat")
	check(c:AllFinished(), "AllFinished")
	local standings = c:GetStandings()
	check(standings[1].entryId == 3 and standings[1].position == 1, "clasament #1")
	check(standings[1].finishTime < standings[2].finishTime, "timpi crescători")
	check(c:GetRacer(3).distance <= 1000 - 3 + 1e-6, "s-a oprit înainte de capătul pistei")
	check(not c:AddModifier(3, "Turbo", 2, 5), "după finish nu se mai pot adăuga boost-uri")
end

tests["Pauză: nimic nu se mișcă"] = function(check)
	local c = makeController(0)
	run(c, 1)
	local before = c:GetRacer(1).distance
	local time = c.time
	c:SetPaused(true)
	run(c, 2)
	check(c:GetRacer(1).distance == before and c.time == time, "înghețat pe pauză")
	c:SetPaused(false)
	run(c, 1)
	check(c:GetRacer(1).distance > before, "continuă după pauză")
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
	local summary = string.format("[Tests] RacerController: %d trecute, %d eșuate", passed, failed)
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
	return failed == 0
end

return Spec
