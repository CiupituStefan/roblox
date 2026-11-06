--[[
	Mounts.spec  (ModuleScript)
	Locație: ServerScriptService > Server > Tests > Mounts.spec

	1) MountPicker: aleatoriu ponderat, fără duplicate cât se poate, ignoră
	   mount-urile dezactivate.
	2) MountFactory: TOATE mount-urile din Config se construiesc și respectă
	   convenția (Root ancorat, Body, Seat, stil valid, fără alte piese ancorate).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Services = script.Parent.Parent.Services
local MountPicker = require(Services.MountPicker)
local MountFactory = require(Services.MountFactory)

local Spec = {}
local tests = {}

local sample = {
	{ Id = "A", Weight = 1, Enabled = true },
	{ Id = "B", Weight = 1, Enabled = true },
	{ Id = "C", Weight = 1, Enabled = false },
	{ Id = "D", Weight = 0, Enabled = true },
	{ Id = "E", Weight = 3, Enabled = true },
}

tests["MountPicker: ignoră dezactivate și Weight 0"] = function(check)
	local picks = MountPicker.pick(sample, 300, Random.new(1), false)
	local seen = {}
	for _, id in ipairs(picks) do
		seen[id] = (seen[id] or 0) + 1
	end
	check(seen.C == nil and seen.D == nil, "C/D nu apar")
	check((seen.E or 0) > (seen.A or 0), "E (greutate 3) apare mai des decât A")
end

tests["MountPicker: fără duplicate cât timp ajung"] = function(check)
	local picks = MountPicker.pick(sample, 3, Random.new(7), true)
	check(#picks == 3, "3 rezultate")
	check(picks[1] ~= picks[2] and picks[2] ~= picks[3] and picks[1] ~= picks[3], "toate diferite")
	local more = MountPicker.pick(sample, 7, Random.new(7), true)
	check(#more == 7, "mai mulți concurenți decât mount-uri: se reia lista")
end

tests["MountFactory: toate mount-urile din Config sunt valide"] = function(check)
	local factory = MountFactory.new()
	for _, mount in ipairs(Config.Mounts) do
		local model, err = factory:Create(mount.Id)
		if not model then
			check(false, mount.Id .. ": " .. tostring(err))
		else
			local ok, why = MountFactory.Validate(model)
			check(ok, mount.Id .. ": " .. tostring(why))
			local seat = model.Body.Seat.WorldPosition
			check(seat.Y > 0.5 and seat.Y < 8, mount.Id .. ": înălțimea Seat neobișnuită " .. tostring(seat.Y))
			model:Destroy()
		end
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
	local summary = string.format("[Tests] Mounts: %d trecute, %d eșuate", passed, failed)
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
	return failed == 0
end

return Spec
