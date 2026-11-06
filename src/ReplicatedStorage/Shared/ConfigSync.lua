--[[
	ConfigSync  (ModuleScript)
	Locație: ReplicatedStorage > Shared > ConfigSync

	Citește/scrie o valoare din Config după o „cale” text, pe server și pe client:
	  "Race.BaseSpeed"            -> Config.Race.BaseSpeed
	  "Boosts.Turbo.Duration"     -> Config.Boosts.Turbo.Duration
	  "Mounts.@BlockPig.Enabled"  -> elementul cu Id = "BlockPig" din lista Config.Mounts
	  "Maps.List.@NeonCity.Enabled"
	  "Gifts.ByName.Rose"         -> recompensa gift-ului „Rose” (nil = șters)

	Serverul validează ORICE modificare (SettingsService) înainte să o aplice;
	acest modul doar aplică o valoare deja validată și o replică clienților.
]]

local ConfigSync = {}

-- valoarea „șterge” (o tabelă Luau nu poate păstra nil ca valoare)
ConfigSync.NIL = "__nil__"

function ConfigSync.split(path)
	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	return parts
end

local function step(container, key)
	if type(container) ~= "table" then
		return nil
	end
	if string.sub(key, 1, 1) == "@" then
		local id = string.sub(key, 2)
		for _, item in ipairs(container) do
			if type(item) == "table" and item.Id == id then
				return item
			end
		end
		return nil
	end
	local numeric = tonumber(key)
	if numeric and container[numeric] ~= nil then
		return container[numeric]
	end
	return container[key]
end

-- Returnează containerul părinte și ultima cheie (sau nil dacă drumul nu există)
function ConfigSync.resolve(config, path)
	local parts = ConfigSync.split(path)
	if #parts == 0 then
		return nil
	end
	local container = config
	for i = 1, #parts - 1 do
		container = step(container, parts[i])
		if container == nil then
			return nil
		end
	end
	return container, parts[#parts]
end

function ConfigSync.get(config, path)
	local container, key = ConfigSync.resolve(config, path)
	if not container then
		return nil
	end
	return step(container, key)
end

function ConfigSync.apply(config, path, value)
	local container, key = ConfigSync.resolve(config, path)
	if not container then
		return false
	end
	if value == ConfigSync.NIL then
		value = nil
	end
	container[key] = value
	return true
end

-- Aplică un set întreg de modificări { [path] = value } (ex. la conectarea clientului)
function ConfigSync.applyAll(config, overrides)
	for path, value in pairs(overrides or {}) do
		ConfigSync.apply(config, path, value)
	end
end

return ConfigSync
