--[[
	SettingsService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > SettingsService

	Modificarea setărilor în timpul jocului (din panoul de admin), în siguranță:
	  * LISTĂ ALBĂ: doar căile definite aici pot fi schimbate, fiecare cu tip
	    și limite (ex. viteza de bază 5..200). Orice altceva este respins.
	  * aplică valoarea în Config pe server și o trimite tuturor clienților
	    (ConfigSync), ca UI-ul și aura să folosească aceleași valori
	  * opțional salvează modificările în DataStore și le reîncarcă la
	    pornirea serverului (Config.Admin.PersistSettings)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConfigSync = require(Shared:WaitForChild("ConfigSync"))
local Signal = require(Shared:WaitForChild("Signal"))

local SettingsService = {}
SettingsService.__index = SettingsService

local DATASTORE_NAME = "TikTokRaceAdminSettings"
local DATASTORE_KEY = "settings_v1"

local function int(min, max)
	return { kind = "number", integer = true, min = min, max = max }
end
local function num(min, max)
	return { kind = "number", min = min, max = max }
end
local BOOL = { kind = "boolean" }

-- Setări fixe (cale exactă -> regulă)
SettingsService.Rules = {
	["Race.MaxRacers"] = int(1, 40),
	["Race.MinRacers"] = int(1, 40),
	["Race.BaseSpeed"] = num(5, 200),
	["Race.SpeedNoisePercent"] = num(0, 20),
	["Race.MaxSpeedMultiplier"] = num(1, 10),
	["Race.LobbyWaitSeconds"] = num(0, 180),
	["Race.GridHoldSeconds"] = num(0, 15),
	["Race.CountdownSeconds"] = int(1, 10),
	["Race.FinishGraceSeconds"] = num(0, 60),
	["Race.PodiumSeconds"] = num(3, 60),
	["Race.MaxRaceSeconds"] = num(30, 900),
	["Queue.MaxSize"] = int(1, 2000),
	["Queue.SkipCreditTTLSeconds"] = num(30, 7200),
	["Registration.PerUserCooldownSeconds"] = num(0, 120),
	["BoostRules.PerRacerCooldownSeconds"] = num(0, 5),
	["BoostRules.MaxQueuedBoostsPerRacer"] = int(0, 50),
	["Gifts.MaxRepeatPerEvent"] = int(1, 200),
	["Gifts.ThankNonRacers"] = BOOL,
	["Gifts.AcceptDuringCountdown"] = BOOL,
	["Gifts.UseCoinFallback"] = BOOL,
	["Wheel.AvoidDuplicates"] = BOOL,
	["Maps.Rotation"] = { kind = "enum", values = { Sequential = true, Random = true } },
	["Maps.DecorDensity"] = num(0.2, 3),
	["Aura.Enabled"] = BOOL,
	["Aura.BaseSize"] = num(0.5, 10),
	["UI.ShotSeconds"] = num(2, 30),
	["UI.FocusSeconds"] = num(0, 10),
	-- adresa relay-ului (ex. tunel Cloudflare nou). Cheia secretă e trimisă de Roblox
	-- DOAR către domeniul permis în Secrets Store, deci o adresă greșită nu o expune.
	["Bridge.BaseUrl"] = { kind = "url" },
}

-- Câmpurile modificabile ale boost-urilor (doar dacă boost-ul are deja câmpul)
SettingsService.BoostFieldRules = {
	Multiplier = num(1, 6),
	Duration = num(0.5, 30),
	Distance = num(1, 400),
	ImpulseTime = num(0, 5),
	FlightHeight = num(2, 40),
	AuraBonus = num(0, 4),
}

-- deps = { config, remotes, persist (bool), onChanged? }
function SettingsService.new(deps)
	local self = setmetatable({}, SettingsService)
	self._config = deps.config
	self._remotes = deps.remotes
	self._persist = deps.persist and true or false
	self._overrides = {} -- path -> value (ConfigSync.NIL pentru ștergere)
	self._saveScheduled = false
	self.Changed = Signal.new() -- (path, value)
	return self
end

local function validNumber(rule, value)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil, "trebuie să fie un număr"
	end
	if rule.integer then
		value = math.floor(value + 0.5)
	end
	if value < rule.min or value > rule.max then
		return nil, string.format("trebuie să fie între %s și %s", tostring(rule.min), tostring(rule.max))
	end
	return value
end

local function checkRule(rule, value)
	if rule.kind == "number" then
		return validNumber(rule, value)
	elseif rule.kind == "boolean" then
		if type(value) ~= "boolean" then
			return nil, "trebuie să fie da/nu"
		end
		return value
	elseif rule.kind == "url" then
		if type(value) ~= "string" then
			return nil, "trebuie să fie text"
		end
		value = value:gsub("%s", ""):gsub("/+$", "")
		if #value > 200 or not value:match("^https://[%w%-%.]+%.[%a][%w%-]*[:%d]*$") then
			return nil, "adresa trebuie să fie de forma https://domeniu.exemplu (fără cale)"
		end
		return value
	elseif rule.kind == "enum" then
		if not rule.values[value] then
			return nil, "valoare nepermisă"
		end
		return value
	end
	return nil, "regulă necunoscută"
end

function SettingsService:_validRewards()
	local rewards = { SkipQueue = true }
	for name in pairs(self._config.Boosts) do
		rewards[name] = true
	end
	return rewards
end

local function findById(list, id)
	for _, item in ipairs(list) do
		if item.Id == id then
			return item
		end
	end
	return nil
end

--[[
	Validează (path, value). Returnează valoarea normalizată sau nil, motiv.
	Căi dinamice acceptate:
	  Boosts.<Nume>.<Câmp>            (câmpuri din BoostFieldRules)
	  Gifts.ByName.<Gift>             (= recompensă validă sau ConfigSync.NIL)
	  Gifts.ById.<număr>              (idem)
	  Mounts.@<Id>.Enabled | .Weight
	  Maps.List.@<Id>.Enabled
]]
function SettingsService:Validate(path, value)
	if type(path) ~= "string" or #path > 80 then
		return nil, "cale invalidă"
	end
	local rule = SettingsService.Rules[path]
	if rule then
		return checkRule(rule, value)
	end
	local parts = ConfigSync.split(path)
	local config = self._config

	if parts[1] == "Boosts" and #parts == 3 then
		local boost = config.Boosts[parts[2]]
		local fieldRule = SettingsService.BoostFieldRules[parts[3]]
		if not boost or not fieldRule or boost[parts[3]] == nil then
			return nil, "boost sau câmp necunoscut"
		end
		return checkRule(fieldRule, value)
	end

	if parts[1] == "Gifts" and (parts[2] == "ByName" or parts[2] == "ById") and #parts == 3 then
		if parts[2] == "ByName" then
			local name = parts[3]
			if #name < 1 or #name > 40 or name:find("[%c]") then
				return nil, "nume de gift invalid"
			end
		elseif not tonumber(parts[3]) then
			return nil, "ID de gift invalid"
		end
		if value == ConfigSync.NIL then
			return value
		end
		if type(value) ~= "string" or not self:_validRewards()[value] then
			return nil, "recompensă necunoscută"
		end
		return value
	end

	if parts[1] == "Mounts" and #parts == 3 and parts[2]:sub(1, 1) == "@" then
		if not findById(config.Mounts, parts[2]:sub(2)) then
			return nil, "mount necunoscut"
		end
		if parts[3] == "Enabled" then
			return checkRule(BOOL, value)
		elseif parts[3] == "Weight" then
			return checkRule(num(0, 100), value)
		end
		return nil, "câmp necunoscut"
	end

	if parts[1] == "Maps" and parts[2] == "List" and #parts == 4 and parts[3]:sub(1, 1) == "@" and parts[4] == "Enabled" then
		if not findById(config.Maps.List, parts[3]:sub(2)) then
			return nil, "hartă necunoscută"
		end
		return checkRule(BOOL, value)
	end

	return nil, "setarea nu poate fi modificată"
end

-- Reguli de consistență între setări (după aplicare)
function SettingsService:_guard(path, value)
	local config = self._config
	if path:match("^Mounts%.") and (value == false or value == 0) then
		local enabled = 0
		for _, m in ipairs(config.Mounts) do
			if m.Enabled ~= false and (m.Weight or 1) > 0 then
				enabled += 1
			end
		end
		if enabled == 0 then
			return false, "trebuie să rămână cel puțin un mount activ"
		end
	end
	if path:match("^Maps%.List%.") and value == false then
		local enabled = 0
		for _, m in ipairs(config.Maps.List) do
			if m.Enabled ~= false then
				enabled += 1
			end
		end
		if enabled == 0 then
			return false, "trebuie să rămână cel puțin o hartă activă"
		end
	end
	return true
end

--[[
	Validează și aplică. Returnează true, valoare  sau  false, motiv.
]]
function SettingsService:Set(path, value)
	local normalized, err = self:Validate(path, value)
	if normalized == nil then
		return false, err
	end
	local previous = ConfigSync.get(self._config, path)
	if not ConfigSync.apply(self._config, path, normalized) then
		return false, "calea nu există"
	end
	local ok, why = self:_guard(path, normalized)
	if not ok then
		ConfigSync.apply(self._config, path, previous == nil and ConfigSync.NIL or previous)
		return false, why
	end
	-- MinRacers nu poate depăși MaxRacers
	if self._config.Race.MinRacers > self._config.Race.MaxRacers then
		if path == "Race.MinRacers" then
			ConfigSync.apply(self._config, path, previous)
			return false, "MinRacers nu poate fi mai mare decât MaxRacers"
		end
		self:Set("Race.MinRacers", self._config.Race.MaxRacers)
	end

	self._overrides[path] = normalized
	if self._remotes then
		self._remotes.ConfigSync:FireAllClients({ [path] = normalized })
	end
	self.Changed:Fire(path, normalized)
	self:_scheduleSave()
	return true, normalized
end

function SettingsService:GetOverrides()
	return table.clone(self._overrides)
end

-- Revine la valorile din fișierul Config (necesită repornirea serverului pentru efect complet)
function SettingsService:ClearSaved()
	self._overrides = {}
	self:_scheduleSave()
end

function SettingsService:_scheduleSave()
	if not self._persist or self._saveScheduled then
		return
	end
	self._saveScheduled = true
	task.delay(5, function()
		self._saveScheduled = false
		local ok, err = pcall(function()
			DataStoreService:GetDataStore(DATASTORE_NAME):SetAsync(DATASTORE_KEY, self._overrides)
		end)
		if not ok then
			warn("[SettingsService] Salvarea setărilor a eșuat (în Studio activează 'Enable Studio Access to API Services'):", err)
		end
	end)
end

-- Salvare imediată (la oprirea serverului)
function SettingsService:SaveNow()
	if not self._persist then
		return
	end
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(DATASTORE_NAME):SetAsync(DATASTORE_KEY, self._overrides)
	end)
	if not ok then
		warn("[SettingsService] Salvarea finală a eșuat:", err)
	end
end

-- La pornire: reîncarcă setările salvate (fiecare e validată din nou).
function SettingsService:LoadSavedAsync()
	if not self._persist then
		return 0
	end
	local ok, saved = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME):GetAsync(DATASTORE_KEY)
	end)
	if not ok then
		warn("[SettingsService] Nu pot citi setările salvate:", saved)
		return 0
	end
	local count = 0
	if type(saved) == "table" then
		local persist = self._persist
		self._persist = false -- nu salvăm înapoi în timpul încărcării
		for path, value in pairs(saved) do
			local applied = self:Set(path, value)
			if applied then
				count += 1
			end
		end
		self._persist = persist
	end
	return count
end

return SettingsService
