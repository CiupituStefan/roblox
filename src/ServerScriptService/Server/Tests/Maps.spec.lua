--[[
	Maps.spec  (ModuleScript)
	Locație: ServerScriptService > Server > Tests > Maps.spec

	Verifică geometria (fără a construi hărțile):
	  * TrackMath: lungime, orientare, distanța față de traseu
	  * fiecare traseu: lungimea țintă, nicio porțiune nu se apropie de alta,
	    grila de start încape pe pistă și este în spatele liniei de start
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local MapService = require(script.Parent.Parent.Services.MapService)

local Spec = {}
local tests = {}

tests["TrackMath: linie dreaptă"] = function(check)
	local track = TrackMath.new({ Vector3.new(0, 0, 0), Vector3.new(0, 0, -100), Vector3.new(0, 0, -200) })
	check(math.abs(track.length - 200) < 0.5, "lungime 200 (primit " .. track.length .. ")")
	local cf = track:CFrameAt(50, 10)
	check((cf.Position - Vector3.new(10, 0, -50)).Magnitude < 0.5, "poziție + lateral dreapta = +X")
	check(cf.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.999, "privește în direcția de mers")
	check(cf.UpVector:Dot(Vector3.yAxis) > 0.999, "sus = vertical")
	check((track:CFrameAt(-50).Position - Vector3.zero).Magnitude < 0.01, "distanța negativă e limitată la start")
	local dist, along = track:ClosestXZ(Vector3.new(30, 5, -120))
	check(math.abs(dist - 30) < 0.5 and math.abs(along - 120) < 0.5, "ClosestXZ")
end

tests["TrackMath: scalare la lungimea țintă"] = function(check)
	local track = TrackMath.new({ Vector3.new(0, 0, 0), Vector3.new(100, 0, -100), Vector3.new(0, 0, -300) }, { targetLength = 1000 })
	check(math.abs(track.length - 1000) / 1000 < 0.03, "lungime ~1000 (primit " .. math.floor(track.length) .. ")")
end

tests["Trasee: lungime, fără suprapuneri, grilă validă"] = function(check)
	local width = Config.Maps.TrackWidth
	for _, map in ipairs(Config.Maps.List) do
		local ok, track = pcall(MapService.BuildTrack, map.Id, Config)
		check(ok, map.Id .. ": " .. tostring(track))
		if ok then
			Spec.checkTrack(check, map.Id, track, width)
		end
	end
end

function Spec.checkTrack(check, mapId, track, width)
	local target = Config.Maps.TargetTrackLength
	check(math.abs(track.length - target) / target < 0.05, mapId .. ": lungime " .. math.floor(track.length))

	-- porțiuni ne-vecine pe traseu nu au voie să fie la mai puțin de 1.5 x lățimea pistei
	local step = 15
	local minGap = math.huge
	for a = 0, track.length, step do
		local pa = track:PositionAt(a)
		for b = a + 4 * width, track.length, step do
			local pb = track:PositionAt(b)
			local gap = Vector2.new(pa.X - pb.X, pa.Z - pb.Z).Magnitude
			minGap = math.min(minGap, gap)
		end
	end
	check(minGap > width * 1.5, string.format("%s: porțiuni prea apropiate (%.0f studs)", mapId, minGap))

	local startDistance = MapService.StartDistanceFor(Config)
	local finish = track.length - Config.Maps.FinishMargin
	check(finish > startDistance + 500, mapId .. ": finish prea aproape de start")
	local grid = {}
	local perRow = Config.Maps.GridPerRow
	for i = 1, Config.Race.MaxRacers do
		local row = (i - 1) // perRow
		grid[i] = startDistance - 6 - row * Config.Maps.GridRowSpacing
	end
	for i, distance in ipairs(grid) do
		check(distance > 0, mapId .. ": rândul grilei " .. i .. " e în afara pistei")
	end
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
	local summary = string.format("[Tests] Maps: %d trecute, %d eșuate", passed, failed)
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
	return failed == 0
end

return Spec
