--[[
	ClientMain  (LocalScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > ClientMain

	Pornește sistemele de pe client. Clientul tău (streamerul) este „camera”
	transmisă pe TikTok; nu controlează nimic din cursă (totul e pe server).

	  MountAnimator     animațiile mount-urilor + poza de călare a avatarului
	  WheelController   roata norocului
	  RaceUI            countdown, câștigător, rezultate
	  HUD               clasament live, coadă, anunțuri, bara de sus
	  AuraRenderer      aura de energie
	  BoostFxRenderer   efectele boost-urilor
	  CameraDirector    regizorul camerei
]]

local Client = script.Parent
local SoundPlayer = require(Client:WaitForChild("SoundPlayer"))

local function start(name, ...)
	local ok, err = pcall(function(...)
		require(Client:WaitForChild(name)).Start(...)
	end, ...)
	if not ok then
		warn("[ClientMain] " .. name .. " nu a pornit:", err)
	end
end

start("MountAnimator")
start("WheelController", SoundPlayer)
start("RaceUI", SoundPlayer)
start("HUD", SoundPlayer)
start("AuraRenderer", SoundPlayer)
start("BoostFxRenderer", SoundPlayer)
start("CameraDirector")
task.spawn(start, "AdminPanel") -- așteaptă confirmarea de admin de la server
