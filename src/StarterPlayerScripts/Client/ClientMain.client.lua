--[[
	ClientMain  (LocalScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > ClientMain

	Pornește sistemele de pe client. Clientul tău (streamerul) este „camera”
	transmisă pe TikTok; nu controlează nimic din cursă (totul e pe server).

	Etapa 3: animații mount + roata norocului.
	Etapa 4: cameră care urmărește liderul pe traseu (sau lobby-ul între curse).
	Etapa 5: countdown / finish / podium (RaceUI) + camera pe faze.
	Etapa 7 va adăuga HUD-ul complet și regizorul de cameră.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent
local MountAnimator = require(Client:WaitForChild("MountAnimator"))
local WheelController = require(Client:WaitForChild("WheelController"))
local RaceUI = require(Client:WaitForChild("RaceUI"))

MountAnimator.Start()
WheelController.Start()
RaceUI.Start()

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

local function findLeader()
	local leader, best = nil, -math.huge
	for _, model in ipairs(CollectionService:GetTagged("Racer")) do
		if model:GetAttribute("OnTrack") and model.PrimaryPart then
			local distance = model:GetAttribute("Distance") or 0
			if distance > best then
				best = distance
				leader = model
			end
		end
	end
	return leader
end

RunService.RenderStepped:Connect(function(dt)
	if player.Character then
		return -- dacă ai personaj (Config.Stream.SpawnStreamerCharacter), camera rămâne normală
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local smooth = math.clamp(dt * 3, 0, 1)

	-- podium: privește treptele din lobby
	local lobbyModel = workspace:FindFirstChild("Lobby")
	if workspace:GetAttribute("PodiumActive") and lobbyModel and lobbyModel:FindFirstChild("Podium1") then
		local focus = lobbyModel.Podium1.Position + Vector3.new(0, 6, 0)
		local wanted = CFrame.lookAt(focus + Vector3.new(math.sin(os.clock() * 0.3) * 8, 6, -34), focus)
		camera.CFrame = camera.CFrame:Lerp(wanted, smooth)
		return
	end

	local leader = findLeader()
	if leader then
		local cf = leader.PrimaryPart.CFrame
		local flatLook = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		flatLook = flatLook.Magnitude > 1e-3 and flatLook.Unit or Vector3.new(0, 0, -1)
		local wanted
		if workspace:GetAttribute("RacePhase") == "Countdown" then
			-- pe grilă: din fața concurenților, ca să se vadă avatarurile
			local eye = cf.Position + flatLook * 45 + Vector3.new(0, 14, 0)
			wanted = CFrame.lookAt(eye, cf.Position - flatLook * 8 + Vector3.new(0, 3, 0))
		else
			-- în cursă: în spatele și deasupra liderului, privind înainte pe traseu
			local eye = cf.Position - flatLook * 38 + Vector3.new(0, 18, 0)
			wanted = CFrame.lookAt(eye, cf.Position + flatLook * 25 + Vector3.new(0, 3, 0))
		end
		camera.CFrame = camera.CFrame:Lerp(wanted, smooth)
		return
	end

	local lobby = workspace:FindFirstChild("Lobby")
	if lobby and lobby.PrimaryPart then
		-- lobby: privește concurenții din față (ei se uită spre -Z)
		local focus = lobby.PrimaryPart.Position + Vector3.new(0, 4, 0)
		local t = os.clock()
		local eye = focus + Vector3.new(math.sin(t * 0.15) * 12, 24, -58)
		camera.CFrame = CFrame.lookAt(eye, focus)
	end
end)
