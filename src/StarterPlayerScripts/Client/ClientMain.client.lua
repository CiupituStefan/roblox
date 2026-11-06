--[[
	ClientMain  (LocalScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > ClientMain

	Pornește sistemele de pe client. Clientul tău (streamerul) este „camera”
	transmisă pe TikTok; nu controlează nimic din cursă (totul e pe server).

	Etapa 3: animații mount + roata norocului + o cameră simplă spre lobby.
	Etapa 7 va adăuga HUD-ul complet și regizorul de cameră.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent
local MountAnimator = require(Client:WaitForChild("MountAnimator"))
local WheelController = require(Client:WaitForChild("WheelController"))

MountAnimator.Start()
WheelController.Start()

-- Cameră temporară: privește lobby-ul din față (concurenții se uită spre -Z)
local camera = workspace.CurrentCamera
local player = Players.LocalPlayer
RunService.RenderStepped:Connect(function()
	if player.Character then
		return -- dacă ai personaj (Config.Stream.SpawnStreamerCharacter), camera rămâne normală
	end
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby and lobby.PrimaryPart then
		local focus = lobby.PrimaryPart.Position + Vector3.new(0, 4, 0)
		local t = os.clock()
		local eye = focus + Vector3.new(math.sin(t * 0.15) * 12, 24, -58)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(eye, focus)
	end
end)
