--[[
	CameraDirector  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > CameraDirector

	„Regizorul” camerei transmise pe TikTok. Alege automat unghiul după faza cursei:

	  Lobby / Roată   lobby-ul din față, cu o mișcare lentă
	  Countdown       grila de start din fața concurenților (se văd avatarurile)
	  Cursă           alternează la fiecare Config.UI.ShotSeconds între:
	                    • urmărire din spatele liderului
	                    • lateral, pe grupul din frunte
	                    • de sus, peste lider
	                  + prim-plan de Config.UI.FocusSeconds pe cine primește un boost
	                  + la final, camera trece la linia de FINISH și privește liderul
	  Podium          treptele cu câștigătorii

	Toate tranzițiile sunt line (interpolare). Dacă ai personaj în joc
	(Config.Stream.SpawnStreamerCharacter), camera rămâne cea normală.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CameraDirector = {}

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

local SHOTS = { "chase", "side", "high", "chase" }
local shotIndex = 1
local shotUntil = 0
local focusUserId, focusUntil = nil, 0
local currentFov = 70

local function racersOnTrack()
	local list = {}
	for _, model in ipairs(CollectionService:GetTagged("Racer")) do
		if model:GetAttribute("OnTrack") and model.PrimaryPart then
			table.insert(list, model)
		end
	end
	table.sort(list, function(a, b)
		return (a:GetAttribute("Distance") or 0) > (b:GetAttribute("Distance") or 0)
	end)
	return list
end

local function flatBasis(cf)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis).Unit
	return look, right
end

local function finishBar()
	local map = workspace:FindFirstChild("Map")
	local finish = map and map:FindFirstChild("FINISH")
	if not finish then
		return nil
	end
	-- bara arcadei este cea mai lată piesă din folder
	local best
	for _, part in ipairs(finish:GetChildren()) do
		if part:IsA("BasePart") and (not best or part.Size.X > best.Size.X) and part.Size.Y > 2 and part.Size.Y < 3 then
			best = part
		end
	end
	return best
end

local function chase(model, back, height, side)
	local cf = model.PrimaryPart.CFrame
	local look, right = flatBasis(cf)
	local pos = cf.Position
	local eye = pos - look * back + Vector3.new(0, height, 0) + right * (side or 0)
	return CFrame.lookAt(eye, pos + look * 20 + Vector3.new(0, 3, 0))
end

local function raceShot(list, now)
	local leader = list[1]
	local mapModel = workspace:FindFirstChild("Map")
	local finishDistance = mapModel and mapModel:GetAttribute("FinishDistance")

	-- finalul cursei: camera la linia de finish
	local leaderDistance = leader:GetAttribute("Distance") or 0
	if finishDistance and not leader:GetAttribute("Finished") and finishDistance - leaderDistance < Config.UI.FinishCamDistance then
		local bar = finishBar()
		if bar then
			local look = Vector3.new(bar.CFrame.LookVector.X, 0, bar.CFrame.LookVector.Z).Unit
			local base = bar.Position - Vector3.new(0, 18, 0)
			local eye = base + look * 30 + Vector3.new(0, 4, 0)
			return CFrame.lookAt(eye, leader.PrimaryPart.Position + Vector3.new(0, 3, 0)), 62
		end
	end

	-- prim-plan pe cine a primit un boost
	if focusUserId and now < focusUntil then
		for _, model in ipairs(list) do
			if model:GetAttribute("RobloxUserId") == focusUserId then
				return chase(model, 18, 8, 7), 60
			end
		end
	end

	if now >= shotUntil then
		shotIndex = shotIndex % #SHOTS + 1
		shotUntil = now + Config.UI.ShotSeconds
	end
	local shot = SHOTS[shotIndex]
	if shot == "side" then
		local count = math.min(3, #list)
		local center = Vector3.zero
		for i = 1, count do
			center += list[i].PrimaryPart.Position
		end
		center /= count
		local look, right = flatBasis(leader.PrimaryPart.CFrame)
		local eye = center + right * 48 + look * 10 + Vector3.new(0, 14, 0)
		return CFrame.lookAt(eye, center + Vector3.new(0, 3, 0)), 70
	elseif shot == "high" then
		local cf = leader.PrimaryPart.CFrame
		local look = flatBasis(cf)
		local eye = cf.Position - look * 25 + Vector3.new(0, 65, 0)
		return CFrame.lookAt(eye, cf.Position + look * 30), 70
	end
	return chase(leader, 38, 18), 70
end

local function step(dt)
	if player.Character then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local now = os.clock()
	local smooth = math.clamp(dt * 2.5, 0, 1)
	local wanted, fov

	local lobby = workspace:FindFirstChild("Lobby")
	local phase = workspace:GetAttribute("RacePhase")
	local list = racersOnTrack()

	if workspace:GetAttribute("PodiumActive") and lobby and lobby:FindFirstChild("Podium1") then
		local focus = lobby.Podium1.Position + Vector3.new(0, 6, 0)
		wanted = CFrame.lookAt(focus + Vector3.new(math.sin(now * 0.3) * 8, 6, -34), focus)
		fov = 65
	elseif #list > 0 and phase == "Countdown" then
		local cf = list[1].PrimaryPart.CFrame
		local look = flatBasis(cf)
		local eye = cf.Position + look * 45 + Vector3.new(math.sin(now * 0.5) * 6, 14, 0)
		wanted = CFrame.lookAt(eye, cf.Position - look * 8 + Vector3.new(0, 3, 0))
		fov = 70
	elseif #list > 0 then
		wanted, fov = raceShot(list, now)
	elseif lobby and lobby.PrimaryPart then
		local focus = lobby.PrimaryPart.Position + Vector3.new(0, 4, 0)
		wanted = CFrame.lookAt(focus + Vector3.new(math.sin(now * 0.15) * 12, 24, -58), focus)
		fov = 70
	end

	if wanted then
		-- salt direct dacă distanța e foarte mare (ex. din lobby pe pistă)
		if (camera.CFrame.Position - wanted.Position).Magnitude > 400 then
			camera.CFrame = wanted
		else
			camera.CFrame = camera.CFrame:Lerp(wanted, smooth)
		end
		currentFov += ((fov or 70) - currentFov) * smooth
		camera.FieldOfView = currentFov
	end
end

-- Prim-plan pe un concurent (apelat automat la fiecare boost)
function CameraDirector.Focus(userId, seconds)
	focusUserId = userId
	focusUntil = os.clock() + (seconds or Config.UI.FocusSeconds)
end

function CameraDirector.Start()
	Remotes.BoostFx.OnClientEvent:Connect(function(fx)
		if type(fx) == "table" and fx.robloxUserId then
			CameraDirector.Focus(fx.robloxUserId)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return CameraDirector
