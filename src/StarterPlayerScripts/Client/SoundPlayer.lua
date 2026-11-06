--[[
	SoundPlayer  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > SoundPlayer

	Redă sunetele din Config.Sounds (pe clientul tău = în transmisie).
	Sunetele sunt 2D (aceeași intensitate oriunde e camera), ca să se audă
	clar pe TikTok. Un ID gol = nimic (fără erori). Același sunet nu se
	repetă mai des de o dată la 80 ms (evită zgomotul la combo-uri mari).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SoundPlayer = {}

local lastPlayed = {}
local cache = {}

local function getSound(name)
	local id = Config.Sounds[name]
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local sound = cache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "Sfx_" .. name
		sound.SoundId = id
		sound.Parent = SoundService
		cache[name] = sound
	end
	return sound
end

-- Redă sunetul `name`. volumeScale și pitch sunt opționale.
function SoundPlayer.Play(name, volumeScale, pitch)
	if not name then
		return
	end
	local now = os.clock()
	if lastPlayed[name] and now - lastPlayed[name] < 0.08 then
		return
	end
	lastPlayed[name] = now
	local template = getSound(name)
	if not template then
		return
	end
	local sound = template:Clone()
	sound.Volume = (Config.Sounds.Volume or 0.6) * (volumeScale or 1)
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(15, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return SoundPlayer
