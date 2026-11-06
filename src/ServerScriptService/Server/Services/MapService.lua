--[[
	MapService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > MapService

	Gestionează hărțile:
	  * rotație automată după fiecare cursă (Sequential / Random fără repetare)
	  * încărcare/descărcare (o singură hartă în workspace la un moment dat)
	  * lumina și atmosfera temei
	  * grila de start (bandă laterală pentru fiecare concurent)

	MapInstance = {
	  id, displayName, model, track (TrackMath), width,
	  startDistance, finishDistance,
	  GetGrid(count) -> { { distance, lateral, cframe } }
	}
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrackMath = require(Shared:WaitForChild("TrackMath"))
local Signal = require(Shared:WaitForChild("Signal"))

local Maps = script.Parent:WaitForChild("Maps")
local MapLayouts = require(Maps:WaitForChild("MapLayouts"))
local Themes = require(Maps:WaitForChild("Themes"))
local MapBuilder = require(Maps:WaitForChild("MapBuilder"))

local MapService = {}
MapService.__index = MapService

-- deps = { config }
function MapService.new(deps)
	local self = setmetatable({}, MapService)
	self._config = deps.config
	self._current = nil
	self._rotationIndex = 0
	self._lastId = nil
	self._rng = Random.new()
	self._loading = false
	self._overrideNext = nil
	self.Loaded = Signal.new() -- (mapInstance)
	return self
end

function MapService:GetEnabledMaps()
	local list = {}
	for _, map in ipairs(self._config.Maps.List) do
		if map.Enabled ~= false and MapLayouts[map.Id] and Themes[map.Id] then
			table.insert(list, map)
		end
	end
	return list
end

-- Construiește geometria traseului (fără să construiască harta). Folosit și de teste.
function MapService.BuildTrack(mapId, config)
	local points = MapLayouts[mapId]
	assert(points, "Nu există traseu pentru " .. tostring(mapId))
	return TrackMath.new(points, { targetLength = config.Maps.TargetTrackLength, samplesPerSegment = 24 })
end

-- Distanța liniei de start: destul loc în spate pentru toate rândurile grilei.
function MapService.StartDistanceFor(config)
	local rows = math.ceil(config.Race.MaxRacers / config.Maps.GridPerRow)
	return 12 + rows * config.Maps.GridRowSpacing
end

local function applyLighting(theme)
	local l = theme.Lighting
	if not l then
		return
	end
	Lighting.ClockTime = l.ClockTime
	Lighting.Brightness = l.Brightness
	Lighting.Ambient = l.Ambient
	Lighting.OutdoorAmbient = l.OutdoorAmbient
	Lighting.FogColor = l.FogColor
	Lighting.FogEnd = l.FogEnd
	Lighting.FogStart = 0
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if l.Atmosphere then
		if not atmosphere then
			atmosphere = Instance.new("Atmosphere")
			atmosphere.Parent = Lighting
		end
		for key, value in pairs(l.Atmosphere) do
			atmosphere[key] = value
		end
	elseif atmosphere then
		atmosphere.Density = 0
	end
end

local function makeInstance(mapInfo, model, track, config, startDistance, finishDistance)
	local width = config.Maps.TrackWidth
	local instance = {
		id = mapInfo.Id,
		displayName = mapInfo.DisplayName,
		model = model,
		track = track,
		width = width,
		startDistance = startDistance,
		finishDistance = finishDistance,
	}
	-- grila: rânduri de câte GridPerRow, în spatele liniei de start, benzi egale pe lățime
	function instance.GetGrid(count)
		local perRow = math.min(count, config.Maps.GridPerRow)
		local usable = width - 16
		local spacing = usable / math.max(perRow, 1)
		local grid = {}
		for i = 1, count do
			local row = (i - 1) // perRow
			local col = (i - 1) % perRow
			local inRow = math.min(perRow, count - row * perRow)
			-- centrează rândurile incomplete
			local offset = (perRow - inRow) * spacing / 2
			local lateral = -usable / 2 + spacing * (col + 0.5) + offset
			local distance = math.max(1, startDistance - 6 - row * config.Maps.GridRowSpacing)
			grid[i] = { distance = distance, lateral = lateral, cframe = track:CFrameAt(distance, lateral) }
		end
		return grid
	end
	return instance
end

function MapService:Unload()
	if self._current and self._current.model then
		self._current.model:Destroy()
	end
	self._current = nil
	workspace:SetAttribute("CurrentMap", nil)
end

--[[
	Încarcă harta `mapId` (yield-uiește câteva cadre cât se construiește).
	Returnează MapInstance sau nil, eroare.
]]
function MapService:LoadAsync(mapId)
	local mapInfo
	for _, map in ipairs(self._config.Maps.List) do
		if map.Id == mapId then
			mapInfo = map
		end
	end
	if not mapInfo or not MapLayouts[mapId] or not Themes[mapId] then
		return nil, "Hartă necunoscută: " .. tostring(mapId)
	end
	while self._loading do
		task.wait(0.1)
	end
	self._loading = true

	local ok, result, err = pcall(function()
		local config = self._config
		local track = MapService.BuildTrack(mapId, config)
		local startDistance = MapService.StartDistanceFor(config)
		local finishDistance = track.length - config.Maps.FinishMargin
		local started = os.clock()
		local model, parts = MapBuilder.Build({
			id = mapId,
			displayName = mapInfo.DisplayName,
			track = track,
			theme = Themes[mapId],
			width = config.Maps.TrackWidth,
			startDistance = startDistance,
			finishDistance = finishDistance,
			decorDensity = config.Maps.DecorDensity,
			seed = self._rng:NextInteger(1, 1e9),
		})
		self:Unload()
		model.Name = "Map"
		model:SetAttribute("MapId", mapId)
		model:SetAttribute("TrackLength", track.length)
		model:SetAttribute("StartDistance", startDistance)
		model:SetAttribute("FinishDistance", finishDistance)
		model.Parent = workspace
		applyLighting(Themes[mapId])
		print(string.format("[MapService] %s construită: %d piese, traseu %.0f studs, %.2fs", mapId, parts, track.length, os.clock() - started))
		return makeInstance(mapInfo, model, track, config, startDistance, finishDistance)
	end)
	self._loading = false
	if not ok then
		return nil, tostring(result)
	end
	if not result then
		return nil, err
	end
	self._current = result
	self._lastId = mapId
	workspace:SetAttribute("CurrentMap", mapId)
	workspace:SetAttribute("CurrentMapName", result.displayName)
	self.Loaded:Fire(result)
	return result
end

-- Admin: următoarea hartă va fi aceasta (Etapa 8)
function MapService:SetNext(mapId)
	self._overrideNext = mapId
end

function MapService:GetNextOverride()
	return self._overrideNext
end

function MapService:ChooseNextId()
	if self._overrideNext then
		local id = self._overrideNext
		self._overrideNext = nil
		return id
	end
	local list = self:GetEnabledMaps()
	assert(#list > 0, "Nicio hartă activă în Config.Maps.List")
	if #list == 1 then
		return list[1].Id
	end
	if self._config.Maps.Rotation == "Random" then
		local choice
		repeat
			choice = list[self._rng:NextInteger(1, #list)].Id
		until choice ~= self._lastId
		return choice
	end
	self._rotationIndex = self._rotationIndex % #list + 1
	return list[self._rotationIndex].Id
end

function MapService:LoadNextAsync()
	return self:LoadAsync(self:ChooseNextId())
end

function MapService:GetCurrent()
	return self._current
end

return MapService
