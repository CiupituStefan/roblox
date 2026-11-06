--[[
	AuraRenderer  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > AuraRenderer

	Aura de energie a fiecărui concurent (efect ORIGINAL, inspirat de aurele
	din anime). Se construiește pe client din particule, lumini și fulgere,
	cu texturile încorporate în Roblox (Config.Aura.Textures).

	Nivelul aurei = viteza actuală / viteza de bază (+ bonusul boost-ului activ):
	  Calm      discretă, alb-albastră
	  Energie   mai mare, albastră, energie vizibilă
	  Supernova aurie, intensă, scântei
	  Divin     uriașă, aurie, scântei + fulgere care pâlpâie
	Culoarea, mărimea, luminozitatea și cantitatea de particule se
	interpolează LIN între niveluri (Config.Aura.TransitionSpeed). La urcarea
	într-un nivel nou apare o undă de energie.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local AuraRenderer = {}

local SoundPlayer -- injectat la Start
local states = {} -- model -> state
local APPLY_INTERVAL = 1 / 20 -- proprietățile particulelor se actualizează de 20 ori/s

local function findRootPart(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "HumanoidRootPart" and d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function numberSeq(points)
	local keys = {}
	for _, p in ipairs(points) do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function build(model, state)
	local root = findRootPart(model)
	if not root then
		return false
	end
	local tex = Config.Aura.Textures
	state.root = root

	-- învelișul de energie (rămâne lipit de corp)
	state.glow = emitter(root, {
		Name = "AuraGlow",
		Texture = tex.Glow,
		LockedToPart = true,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(25, 25),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Transparency = numberSeq({ { 0, 0.55 }, { 0.3, 0.35 }, { 1, 1 } }),
		ZOffset = -1,
	})
	-- flăcări de energie care urcă (și rămân în urmă la viteză mare)
	state.flame = emitter(root, {
		Name = "AuraFlame",
		Texture = tex.Flame,
		LockedToPart = false,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(5, 9),
		SpreadAngle = Vector2.new(15, 15),
		Acceleration = Vector3.new(0, 10, 0),
		Rotation = NumberRange.new(-20, 20),
		Transparency = numberSeq({ { 0, 0.3 }, { 0.6, 0.5 }, { 1, 1 } }),
	})
	-- scântei (nivelurile mari)
	state.spark = emitter(root, {
		Name = "AuraSpark",
		Texture = tex.Spark,
		LockedToPart = false,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(60, 60),
		Size = numberSeq({ { 0, 0.5 }, { 1, 0 } }),
		Transparency = numberSeq({ { 0, 0 }, { 1, 1 } }),
	})
	-- undă la creșterea nivelului
	state.shock = emitter(root, {
		Name = "AuraShock",
		Texture = tex.Shockwave,
		LockedToPart = true,
		Lifetime = NumberRange.new(0.45),
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01), -- viteză minimă în sus => inelul stă orizontal
		SpreadAngle = Vector2.zero,
		Size = numberSeq({ { 0, 2 }, { 1, 18 } }),
		Transparency = numberSeq({ { 0, 0.2 }, { 1, 1 } }),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
	})
	state.light = Instance.new("PointLight")
	state.light.Name = "AuraLight"
	state.light.Shadows = false
	state.light.Parent = root

	-- fulgere: 3 raze între puncte aleatorii din jurul corpului
	state.bolts = {}
	for i = 1, 3 do
		local a0 = Instance.new("Attachment")
		a0.Name = "BoltA" .. i
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "BoltB" .. i
		a1.Parent = root
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Config.Aura.LightningColor)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 8
		beam.Width0 = 0.35
		beam.Width1 = 0.08
		beam.Enabled = false
		beam.Parent = root
		table.insert(state.bolts, { a0 = a0, a1 = a1, beam = beam })
	end

	local first = Config.Aura.Tiers[1]
	state.color = first.Color
	state.size = first.Size
	state.brightness = first.Brightness
	state.rate = first.Particles
	state.tier = 1
	state.applyTimer = 0
	state.boltTimer = 0
	state.built = true
	return true
end

local function destroy(state)
	for _, name in ipairs({ "glow", "flame", "spark", "shock", "light" }) do
		if state[name] then
			state[name]:Destroy()
		end
	end
	for _, bolt in ipairs(state.bolts or {}) do
		bolt.beam:Destroy()
		bolt.a0:Destroy()
		bolt.a1:Destroy()
	end
end

-- Nivelul țintă: index de nivel + fracția spre nivelul următor
local function targetLevel(model)
	local base = Config.Race.BaseSpeed
	local ratio = 0
	if model:GetAttribute("OnTrack") and not model:GetAttribute("Finished") then
		ratio = (model:GetAttribute("Speed") or 0) / base
	end
	local untilTime = model:GetAttribute("AuraBoostUntil") or 0
	if untilTime > workspace:GetServerTimeNow() then
		ratio += (model:GetAttribute("AuraBoost") or 0) * Config.Aura.BoostBonusWeight
	end
	if model:GetAttribute("PodiumPlace") == 1 then
		ratio = math.max(ratio, 2.5) -- câștigătorul strălucește pe podium
	end
	local tiers = Config.Aura.Tiers
	local index = 1
	for i, tier in ipairs(tiers) do
		if ratio >= tier.MinMultiplier then
			index = i
		end
	end
	local frac = 0
	if tiers[index + 1] then
		local lo, hi = tiers[index].MinMultiplier, tiers[index + 1].MinMultiplier
		frac = math.clamp((ratio - lo) / (hi - lo), 0, 1)
	end
	return index, frac
end

local function update(model, state, dt)
	local tiers = Config.Aura.Tiers
	local index, frac = targetLevel(model)
	local tier, nextTier = tiers[index], tiers[index + 1] or tiers[index]

	-- valorile țintă (interpolate și între niveluri)
	local targetColor = tier.Color:Lerp(nextTier.Color, frac * 0.6)
	local targetSize = tier.Size + (nextTier.Size - tier.Size) * frac
	local targetBrightness = tier.Brightness + (nextTier.Brightness - tier.Brightness) * frac
	local targetRate = tier.Particles + (nextTier.Particles - tier.Particles) * frac

	local alpha = 1 - math.exp(-Config.Aura.TransitionSpeed * dt)
	state.color = state.color:Lerp(targetColor, alpha)
	state.size += (targetSize - state.size) * alpha
	state.brightness += (targetBrightness - state.brightness) * alpha
	state.rate += (targetRate - state.rate) * alpha

	if index > state.tier and index >= 2 then
		state.shock.Color = ColorSequence.new(targetColor)
		state.shock:Emit(1)
		state.spark:Emit(12 * index)
		if index == #tiers and SoundPlayer then
			SoundPlayer.Play("AuraPowerUp", 0.7)
		end
	end
	state.tier = index

	state.applyTimer += dt
	if state.applyTimer >= APPLY_INTERVAL then
		state.applyTimer = 0
		local s = Config.Aura.BaseSize * state.size
		local white = state.color:Lerp(Color3.new(1, 1, 1), 0.55)
		state.glow.Color = ColorSequence.new(white, state.color)
		state.glow.Size = numberSeq({ { 0, s * 0.9 }, { 0.5, s * 1.25 }, { 1, s * 1.5 } })
		state.glow.Rate = state.rate * 0.6
		state.flame.Color = ColorSequence.new(white, state.color)
		state.flame.Size = numberSeq({ { 0, s * 0.55 }, { 0.5, s * 0.75 }, { 1, 0 } })
		state.flame.Rate = state.rate
		state.flame.Speed = NumberRange.new(4 + state.size * 2, 7 + state.size * 4)
		state.spark.Color = ColorSequence.new(white)
		state.spark.Rate = index >= 3 and state.rate * 0.5 or 0
		state.light.Color = state.color
		state.light.Brightness = state.brightness
		state.light.Range = 6 + state.size * 7
	end

	-- fulgere (doar la nivelurile cu Lightning = true)
	local lightning = tier.Lightning or (nextTier.Lightning and frac > 0.7)
	state.boltTimer -= dt
	if state.boltTimer <= 0 then
		state.boltTimer = 0.06 + math.random() * 0.06
		local radius = 2.5 * state.size
		for _, bolt in ipairs(state.bolts) do
			local on = lightning and math.random() < 0.65
			bolt.beam.Enabled = on
			if on then
				bolt.a0.Position = Vector3.new((math.random() - 0.5) * radius, (math.random() - 0.3) * radius * 1.4, (math.random() - 0.5) * radius)
				bolt.a1.Position = Vector3.new((math.random() - 0.5) * radius, (math.random() - 0.3) * radius * 1.4, (math.random() - 0.5) * radius)
				bolt.beam.CurveSize0 = (math.random() - 0.5) * 6
				bolt.beam.CurveSize1 = (math.random() - 0.5) * 6
			end
		end
	end
end

local function track(model)
	if states[model] then
		return
	end
	states[model] = { built = false, retry = 0 }
end

local function untrack(model)
	local state = states[model]
	if state then
		if state.built then
			destroy(state)
		end
		states[model] = nil
	end
end

local function step(dt)
	for model, state in pairs(states) do
		if not model.Parent then
			untrack(model)
		elseif not state.built then
			state.retry -= dt
			if state.retry <= 0 then
				state.retry = 0.5 -- avatarul poate apărea puțin mai târziu
				build(model, state)
			end
		elseif not state.root.Parent then
			destroy(state)
			states[model] = { built = false, retry = 0 }
		else
			update(model, state, dt)
		end
	end
end

function AuraRenderer.Start(soundPlayer)
	if not Config.Aura.Enabled then
		return
	end
	SoundPlayer = soundPlayer
	for _, model in ipairs(CollectionService:GetTagged("Racer")) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal("Racer"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Racer"):Connect(untrack)
	RunService.RenderStepped:Connect(step)
end

return AuraRenderer
