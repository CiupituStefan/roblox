--[[
	PreRaceService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > PreRaceService

	Pregătirea unei curse (pașii 5-10 din fluxul cursei):
	  1. PrepareAsync: încarcă avatarurile ORIGINALE ale concurenților în paralel și
	     le pune în lobby. Cine nu se încarcă la timp e scos din cursă (DropFromActive).
	  2. RunWheelAsync: serverul alege mount-urile (aleator, ponderat), anunță
	     clienții (care animează roata) și, exact când roata se oprește pentru un
	     concurent, îi construiește mount-ul și îl urcă pe el.
	  3. Cleanup: șterge modelele la finalul cursei.

	Handle (un concurent pregătit) = {
	  entry, model (Model "Racer_<UserId>", tag "Racer"), avatar, mount?, slotIndex
	}
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Signal"))
local MountPicker = require(script.Parent:WaitForChild("MountPicker"))

local PreRaceService = {}
PreRaceService.__index = PreRaceService

PreRaceService.RACER_TAG = "Racer"

-- deps = { config, queue, avatars (AvatarService), mounts (MountFactory), staging, remotes, users }
function PreRaceService.new(deps)
	local self = setmetatable({}, PreRaceService)
	self._config = deps.config
	self._queue = deps.queue
	self._avatars = deps.avatars
	self._mounts = deps.mounts
	self._staging = deps.staging
	self._remotes = deps.remotes
	self._users = deps.users
	self._rng = Random.new()
	self.Dropped = Signal.new() -- (entry, reason)
	self.Mounted = Signal.new() -- (handle, mountInfo)

	local folder = workspace:FindFirstChild("Racers")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Racers"
		folder.Parent = workspace
	end
	self._folder = folder
	return self
end

function PreRaceService:_newRacerModel(entry, raceId)
	local model = Instance.new("Model")
	model.Name = "Racer_" .. entry.robloxUserId
	model:SetAttribute("RobloxUserId", entry.robloxUserId)
	model:SetAttribute("RobloxName", entry.robloxName)
	model:SetAttribute("DisplayName", entry.displayName)
	model:SetAttribute("RaceId", raceId)
	model:SetAttribute("Speed", 0)
	return model
end

--[[
	Încarcă avatarurile în paralel. Returnează lista de handle-uri reușite,
	în ordinea concurenților. Cei eșuați sunt scoși din cursă.
]]
function PreRaceService:PrepareAsync(raceId, racers)
	local results = {}
	local pending = #racers
	local timeout = self._config.Wheel.PrepareTimeoutSeconds

	for index, entry in ipairs(racers) do
		task.spawn(function()
			local ok, avatar, err = pcall(function()
				return self._avatars:BuildAsync(entry)
			end)
			if not ok then
				avatar, err = nil, tostring(avatar)
			end
			results[index] = avatar and { avatar = avatar } or { err = err or "AVATAR_FAILED" }
			pending -= 1
		end)
	end

	local started = os.clock()
	while pending > 0 and os.clock() - started < timeout do
		task.wait(0.1)
	end

	local handles = {}
	for index, entry in ipairs(racers) do
		local result = results[index]
		if result and result.avatar then
			local slotIndex = #handles + 1
			local model = self:_newRacerModel(entry, raceId)
			result.avatar.Parent = model
			self._avatars:PlaceStanding(result.avatar, self._staging:GetSlot(slotIndex))
			model.PrimaryPart = result.avatar.PrimaryPart
			model.Parent = self._folder
			CollectionService:AddTag(model, PreRaceService.RACER_TAG)
			table.insert(handles, { entry = entry, model = model, avatar = result.avatar, slotIndex = slotIndex })
		else
			local reason = result and result.err or "TIMEOUT"
			self._queue:DropFromActive(raceId, entry.id)
			self.Dropped:Fire(entry, reason)
			-- un avatar care a sosit după timeout e șters când apare
			if not result then
				task.spawn(function()
					local waited = 0
					while not results[index] and waited < 60 do
						waited += task.wait(1)
					end
					if results[index] and results[index].avatar then
						results[index].avatar:Destroy()
					end
				end)
			end
		end
	end
	return handles
end

-- Calculează programul roții (același pentru server și clienți).
function PreRaceService:_schedule(count)
	local cfg = self._config.Wheel
	local per = math.clamp(cfg.MaxTotalSeconds / math.max(count, 1), cfg.MinPerRacerSeconds, cfg.PerRacerSeconds)
	local reveals = {}
	for i = 1, count do
		local start = cfg.IntroSeconds + (i - 1) * per
		reveals[i] = { start = start, landAt = start + per * cfg.SpinFraction }
	end
	local total = cfg.IntroSeconds + count * per + cfg.OutroSeconds
	return reveals, total, per
end

local function poof(position)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = CFrame.new(position)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.new(1, 1, 1))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(0.5, 0.9)
	smoke.Speed = NumberRange.new(8, 14)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = holder
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 80), Color3.fromRGB(255, 120, 200))
	sparkles.Size = NumberSequence.new(1.2)
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Speed = NumberRange.new(10, 20)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.LightEmission = 1
	sparkles.Rate = 0
	sparkles.Parent = holder
	holder.Parent = workspace
	smoke:Emit(30)
	sparkles:Emit(40)
	Debris:AddItem(holder, 2)
end

-- Construiește mount-ul și urcă avatarul pe el. Returnează true sau false, err.
function PreRaceService:MountRacer(handle, mountId, groundCFrame)
	local mount, err = self._mounts:Create(mountId)
	if not mount then
		return false, err
	end
	if handle.mount then
		handle.mount:Destroy()
	end
	groundCFrame = groundCFrame or self._staging:GetSlot(handle.slotIndex)
	mount:PivotTo(groundCFrame)
	mount.Name = "Mount"
	mount.Parent = handle.model
	self._avatars:AttachToMount(handle.avatar, mount)
	handle.model.PrimaryPart = mount.PrimaryPart -- de acum se mută doar Root-ul mount-ului
	handle.model:SetAttribute("MountId", mountId)
	handle.model:SetAttribute("MountStyle", mount:GetAttribute("MountStyle"))
	handle.mount = mount
	handle.mountId = mountId
	return true
end

--[[
	Roata norocului. Serverul decide toate rezultatele ÎNAINTE de animație și le
	trimite clienților cu un orar sincronizat (workspace:GetServerTimeNow()).
	Yield-uiește până la finalul roții. Returnează { [handle] = mountId }.
]]
function PreRaceService:RunWheelAsync(raceId, handles)
	local mountsConfig = self._config.Mounts
	local picks = MountPicker.pick(mountsConfig, #handles, self._rng, self._config.Wheel.AvoidDuplicates)
	local reveals, total, per = self:_schedule(#handles)

	local segments = {}
	for _, mount in ipairs(MountPicker.enabledMounts(mountsConfig)) do
		table.insert(segments, { id = mount.Id, name = mount.DisplayName, icon = mount.Icon, color = mount.Color })
	end

	local startAt = workspace:GetServerTimeNow() + 0.5
	local payload = {
		type = "wheel",
		raceId = raceId,
		startAt = startAt,
		total = total,
		perRacer = per,
		spinFraction = self._config.Wheel.SpinFraction,
		segments = segments,
		reveals = {},
	}
	for i, handle in ipairs(handles) do
		local info = MountPicker.findById(mountsConfig, picks[i])
		payload.reveals[i] = {
			robloxUserId = handle.entry.robloxUserId,
			robloxName = handle.entry.robloxName,
			displayName = handle.entry.displayName,
			mountId = picks[i],
			mountName = info and info.DisplayName or picks[i],
			mountIcon = info and info.Icon or "",
			start = reveals[i].start,
			landAt = reveals[i].landAt,
		}
	end
	self._remotes.RaceEvent:FireAllClients(payload)

	local assignments = {}
	for i, handle in ipairs(handles) do
		local waitFor = startAt + reveals[i].landAt - workspace:GetServerTimeNow()
		if waitFor > 0 then
			task.wait(waitFor)
		end
		local ok, err = self:MountRacer(handle, picks[i])
		if ok then
			assignments[handle] = picks[i]
			poof(handle.mount.PrimaryPart.Position + Vector3.new(0, 2, 0))
			self.Mounted:Fire(handle, payload.reveals[i])
		else
			warn("[PreRaceService] Mount eșuat pentru", handle.entry.robloxName, err)
		end
	end

	local remaining = startAt + total - workspace:GetServerTimeNow()
	if remaining > 0 then
		task.wait(remaining)
	end
	return assignments
end

function PreRaceService:Cleanup(handles)
	for _, handle in ipairs(handles) do
		if handle.model then
			handle.model:Destroy()
		end
	end
end

-- Siguranță: șterge orice concurent rămas (ex. după o eroare)
function PreRaceService:CleanupAll()
	for _, child in ipairs(self._folder:GetChildren()) do
		child:Destroy()
	end
end

return PreRaceService
