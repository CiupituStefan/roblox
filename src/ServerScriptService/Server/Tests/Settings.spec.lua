--[[
	Settings.spec  (ModuleScript)
	Locație: ServerScriptService > Server > Tests > Settings.spec

	Validarea setărilor din panoul de admin (fără DataStore, fără rețea):
	  * lista albă: căile nepermise (ex. Admin.UserIds) sunt respinse
	  * tipuri și limite, rotunjire pentru numere întregi
	  * boost-uri, gift-uri (inclusiv ștergere), mount-uri, hărți
	  * reguli de consistență (min. un mount/hartă activă, MinRacers <= MaxRacers)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigSync = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ConfigSync"))
local SettingsService = require(script.Parent.Parent.Services.SettingsService)

local Spec = {}
local tests = {}

local function makeConfig()
	return {
		Race = { MaxRacers = 12, MinRacers = 1, BaseSpeed = 40, SpeedNoisePercent = 4, MaxSpeedMultiplier = 4, LobbyWaitSeconds = 15, GridHoldSeconds = 2, CountdownSeconds = 3, FinishGraceSeconds = 8, PodiumSeconds = 10, MaxRaceSeconds = 180 },
		Queue = { MaxSize = 300, SkipCreditTTLSeconds = 900 },
		Registration = { PerUserCooldownSeconds = 8 },
		BoostRules = { PerRacerCooldownSeconds = 0.5, MaxQueuedBoostsPerRacer = 10 },
		Gifts = { ById = {}, ByName = { Rose = "SpeedBoost" }, MaxRepeatPerEvent = 20, ThankNonRacers = true, AcceptDuringCountdown = false, UseCoinFallback = true },
		Boosts = { SpeedBoost = { Kind = "Multiplier", Multiplier = 1.3, Duration = 4 }, RocketBoost = { Kind = "Impulse", Distance = 60, ImpulseTime = 1 } },
		Wheel = { AvoidDuplicates = true },
		Maps = { Rotation = "Sequential", DecorDensity = 1, List = { { Id = "A", Enabled = true }, { Id = "B", Enabled = true } } },
		Mounts = { { Id = "M1", Enabled = true, Weight = 1 }, { Id = "M2", Enabled = true, Weight = 1 } },
		Aura = { Enabled = true, BaseSize = 3 },
		UI = { ShotSeconds = 7, FocusSeconds = 3 },
		Admin = { UserIds = { 1 } },
		Bridge = { BaseUrl = "https://old.example.com" },
	}
end

local function make()
	local config = makeConfig()
	return SettingsService.new({ config = config, persist = false }), config
end

tests["Listă albă: căile nepermise sunt respinse"] = function(check)
	local s, config = make()
	check(not s:Set("Admin.UserIds", { 2 }), "Admin.UserIds respins")
	check(not s:Set("Admin", {}), "Admin respins")
	check(not s:Set("Race", {}), "tabel întreg respins")
	check(not s:Set("Boosts.SpeedBoost.Kind", "Impulse"), "Kind nu se poate schimba")
	check(not s:Set("Boosts.Inexistent.Duration", 3), "boost inexistent respins")
	check(not s:Set("Boosts.RocketBoost.Duration", 3), "câmp absent la acel boost respins")
	check(not s:Set(123, 1), "cale non-text respinsă")
	check(config.Admin.UserIds[1] == 1 and #config.Admin.UserIds == 1, "lista de admini neatinsă")
end

tests["Tipuri și limite"] = function(check)
	local s, config = make()
	check(s:Set("Race.BaseSpeed", 55), "număr valid")
	check(config.Race.BaseSpeed == 55, "aplicat în Config")
	check(not s:Set("Race.BaseSpeed", 9999), "peste limită respins")
	check(not s:Set("Race.BaseSpeed", "50"), "text în loc de număr respins")
	check(not s:Set("Race.BaseSpeed", 0 / 0), "NaN respins")
	check(s:Set("Race.MaxRacers", 7.6) and config.Race.MaxRacers == 8, "întreg rotunjit (7.6 -> 8)")
	check(not s:Set("Gifts.ThankNonRacers", 1), "număr în loc de bool respins")
	check(s:Set("Gifts.ThankNonRacers", false) and config.Gifts.ThankNonRacers == false, "bool aplicat")
	check(not s:Set("Maps.Rotation", "Haos"), "enum invalid respins")
	check(s:Set("Maps.Rotation", "Random"), "enum valid")
	check(s:Set("Boosts.SpeedBoost.Duration", 6) and config.Boosts.SpeedBoost.Duration == 6, "durata boost-ului")
	check(not s:Set("Boosts.SpeedBoost.Multiplier", 50), "multiplicator peste limită respins")
end

tests["Gift-uri: adăugare, schimbare, ștergere"] = function(check)
	local s, config = make()
	check(s:Set("Gifts.ByName.Galaxy", "RocketBoost") and config.Gifts.ByName.Galaxy == "RocketBoost", "gift nou")
	check(s:Set("Gifts.ByName.Rose", "SkipQueue") and config.Gifts.ByName.Rose == "SkipQueue", "SkipQueue permis")
	check(not s:Set("Gifts.ByName.Rose", "Teleportare"), "recompensă inexistentă respinsă")
	check(s:Set("Gifts.ByName.Rose", ConfigSync.NIL) and config.Gifts.ByName.Rose == nil, "gift șters")
	check(s:Set("Gifts.ById.5655", "SpeedBoost") and config.Gifts.ById["5655"] == "SpeedBoost", "după ID")
	check(not s:Set("Gifts.ById.abc", "SpeedBoost"), "ID nenumeric respins")
	check(s:GetOverrides()["Gifts.ByName.Rose"] == ConfigSync.NIL, "ștergerea e memorată pentru replicare")
end

tests["Mount-uri și hărți: cel puțin unul activ"] = function(check)
	local s, config = make()
	check(s:Set("Mounts.@M1.Enabled", false), "M1 oprit")
	check(not s:Set("Mounts.@M2.Enabled", false), "ultimul mount nu poate fi oprit")
	check(config.Mounts[2].Enabled == true, "M2 a rămas activ (revenire)")
	check(not s:Set("Mounts.@M2.Weight", 0), "ultimul mount nu poate avea șansă 0")
	check(s:Set("Mounts.@M1.Weight", 5) and config.Mounts[1].Weight == 5, "șansa schimbată")
	check(not s:Set("Mounts.@Nimic.Enabled", false), "mount necunoscut respins")
	check(s:Set("Maps.List.@A.Enabled", false), "harta A oprită")
	check(not s:Set("Maps.List.@B.Enabled", false), "ultima hartă nu poate fi oprită")
end

tests["MinRacers <= MaxRacers"] = function(check)
	local s, config = make()
	check(not s:Set("Race.MinRacers", 20), "MinRacers peste MaxRacers respins")
	check(config.Race.MinRacers == 1, "MinRacers neschimbat")
	s:Set("Race.MinRacers", 6)
	s:Set("Race.MaxRacers", 4)
	check(config.Race.MinRacers == 4, "MinRacers coborât automat la noul MaxRacers")
end

tests["Adresa relay-ului: doar https, fără cale"] = function(check)
	local s, config = make()
	check(s:Set("Bridge.BaseUrl", " https://abc-def.trycloudflare.com/ ") and config.Bridge.BaseUrl == "https://abc-def.trycloudflare.com", "tunel valid (curățat)")
	check(s:Set("Bridge.BaseUrl", "https://relay.domeniul-meu.ro:8443"), "cu port")
	check(not s:Set("Bridge.BaseUrl", "http://abc.com"), "http respins")
	check(not s:Set("Bridge.BaseUrl", "https://abc.com/events?x=1"), "cu cale respins")
	check(not s:Set("Bridge.BaseUrl", "https://localhost"), "fără domeniu respins")
	check(not s:Set("Bridge.BaseUrl", 42), "număr respins")
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
	local summary = string.format("[Tests] Settings: %d trecute, %d eșuate", passed, failed)
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
	return failed == 0
end

return Spec
