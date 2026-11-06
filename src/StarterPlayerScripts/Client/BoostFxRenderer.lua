--[[
	BoostFxRenderer  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > BoostFxRenderer

	Efectele vizuale și sonore ale boost-urilor (eveniment BoostFx de la server).
	Totul e creat local, pe client, din particule/trail-uri/raze cu texturile
	încorporate în Roblox; nu modifică nimic pe server.

	  SpeedLines   linii de viteză albe în urma concurentului
	  SuperSpeed   linii aurii + undă de șoc + scântei
	  TurboFlames  flăcări mari din spate
	  Rocket       explozie la pornire + flacără de rachetă + dâră de fum
	  Jetpack      jeturi albastre sub avatar + fum
	  Lightning    fulgere care lovesc din cer + scântei electrice
	  Teleport     implozie violet + concurentul „clipește” (transparență locală)
	Peste concurent apare mereu un text mare: „⚡ TURBO x3”.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BoostFxRenderer = {}

local SoundPlayer
local TEX = Config.Aura.Textures

local ICONS = {
	SpeedBoost = "💨",
	SuperSpeed = "🌟",
	Turbo = "🔥",
	RocketBoost = "🚀",
	Jetpack = "🎒",
	LightningBoost = "⚡",
	TeleportDash = "🌀",
}

local COLORS = {
	SpeedLines = Color3.fromRGB(255, 255, 255),
	SuperSpeed = Color3.fromRGB(255, 215, 60),
	TurboFlames = Color3.fromRGB(255, 120, 30),
	Rocket = Color3.fromRGB(255, 90, 40),
	Jetpack = Color3.fromRGB(80, 170, 255),
	Lightning = Color3.fromRGB(150, 220, 255),
	Teleport = Color3.fromRGB(190, 90, 255),
}

local function findRacer(userId)
	for _, model in ipairs(CollectionService:GetTagged("Racer")) do
		if model:GetAttribute("RobloxUserId") == userId then
			return model
		end
	end
	return nil
end

local function findRootPart(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "HumanoidRootPart" and d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function attachment(parent, position, lifetime)
	local a = Instance.new("Attachment")
	a.Position = position
	a.Parent = parent
	Debris:AddItem(a, lifetime)
	return a
end

local function numberSeq(points)
	local keys = {}
	for _, p in ipairs(points) do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function emitter(parent, props, lifetime)
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 1
	e.LightInfluence = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	if lifetime then
		task.delay(lifetime, function()
			e.Enabled = false
		end)
		Debris:AddItem(e, lifetime + 2)
	end
	return e
end

local function burst(parent, texture, color, count, size, speed)
	local e = emitter(parent, {
		Texture = texture,
		Color = ColorSequence.new(color),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(speed * 0.6, speed),
		SpreadAngle = Vector2.new(180, 180),
		Size = numberSeq({ { 0, size }, { 1, size * 0.2 } }),
		Transparency = numberSeq({ { 0, 0 }, { 1, 1 } }),
		Rate = 0,
	})
	e:Emit(count)
	Debris:AddItem(e, 2)
end

local function shockwave(parent, color, size)
	local e = emitter(parent, {
		Texture = TEX.Shockwave,
		Color = ColorSequence.new(color),
		Lifetime = NumberRange.new(0.5),
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(0.01),
		SpreadAngle = Vector2.zero,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Size = numberSeq({ { 0, 2 }, { 1, size } }),
		Transparency = numberSeq({ { 0, 0.1 }, { 1, 1 } }),
		Rate = 0,
	})
	e:Emit(1)
	Debris:AddItem(e, 2)
end

-- dungi de viteză: trail-uri subțiri în părțile laterale
local function speedLines(base, color, duration)
	for _, p in ipairs({ Vector3.new(-3.5, 1.5, 0), Vector3.new(3.5, 1.5, 0), Vector3.new(-2, 4.5, 0), Vector3.new(2, 4.5, 0) }) do
		local a0 = attachment(base, p, duration + 1)
		local a1 = attachment(base, p + Vector3.new(0, 0.35, 0), duration + 1)
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(color)
		trail.LightEmission = 1
		trail.Lifetime = 0.3
		trail.Transparency = numberSeq({ { 0, 0.15 }, { 1, 1 } })
		trail.FaceCamera = true
		trail.Parent = base
		task.delay(duration, function()
			trail.Enabled = false
		end)
		Debris:AddItem(trail, duration + 1)
	end
end

local function flames(parent, position, direction, color, duration, size)
	local a = attachment(parent, position, duration + 2)
	emitter(a, {
		Texture = TEX.Flame,
		Color = ColorSequence.new(Color3.new(1, 1, 0.8), color),
		EmissionDirection = direction,
		Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(12, 18),
		SpreadAngle = Vector2.new(12, 12),
		Size = numberSeq({ { 0, size }, { 1, size * 0.2 } }),
		Transparency = numberSeq({ { 0, 0.1 }, { 1, 1 } }),
		Rate = 90,
	}, duration)
	return a
end

local function smokeTrail(parent, position, duration)
	local a = attachment(parent, position, duration + 4)
	emitter(a, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(220, 220, 220)),
		LightEmission = 0,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(30, 30),
		Size = numberSeq({ { 0, 1.5 }, { 1, 5 } }),
		Transparency = numberSeq({ { 0, 0.4 }, { 1, 1 } }),
		Rate = 40,
	}, duration)
end

local function lightningStrike(root, duration)
	local top = attachment(root, Vector3.new(0, 70, 0), duration + 1)
	local hit = attachment(root, Vector3.new(0, 0, 0), duration + 1)
	local beams = {}
	for i = 1, 2 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = top
		beam.Attachment1 = hit
		beam.Color = ColorSequence.new(Color3.new(1, 1, 1), COLORS.Lightning)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 12
		beam.Width0 = i == 1 and 1.4 or 0.6
		beam.Width1 = i == 1 and 0.6 or 0.3
		beam.Enabled = false
		beam.Parent = root
		Debris:AddItem(beam, duration + 1)
		table.insert(beams, beam)
	end
	local light = Instance.new("PointLight")
	light.Color = COLORS.Lightning
	light.Range = 40
	light.Brightness = 0
	light.Parent = root
	Debris:AddItem(light, duration + 1)
	task.spawn(function()
		for _ = 1, 4 do
			for _, beam in ipairs(beams) do
				beam.CurveSize0 = (math.random() - 0.5) * 30
				beam.CurveSize1 = (math.random() - 0.5) * 30
				beam.Enabled = true
			end
			light.Brightness = 8
			task.wait(0.07)
			for _, beam in ipairs(beams) do
				beam.Enabled = false
			end
			light.Brightness = 0
			task.wait(0.08 + math.random() * 0.1)
		end
	end)
	emitter(root, {
		Texture = TEX.Spark,
		Color = ColorSequence.new(COLORS.Lightning),
		Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(180, 180),
		Size = numberSeq({ { 0, 0.6 }, { 1, 0 } }),
		Rate = 60,
	}, duration)
end

local function teleportBlink(model, root)
	burst(root, TEX.Spark, COLORS.Teleport, 50, 1.4, 25)
	shockwave(root, COLORS.Teleport, 14)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	task.spawn(function()
		for i = 1, 3 do
			for _, p in ipairs(parts) do
				p.LocalTransparencyModifier = i % 2 == 1 and 0.75 or 0
			end
			task.wait(0.06)
		end
		for _, p in ipairs(parts) do
			p.LocalTransparencyModifier = 0
		end
	end)
end

local function popup(root, text, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(20, 10, 40)
	label.Parent = gui
	gui.Parent = root
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 12, 0) }):Play()
	task.delay(1.1, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(gui, 1.8)
end

local EFFECTS = {}

function EFFECTS.SpeedLines(model, root, base, fx)
	speedLines(base, COLORS.SpeedLines, fx.duration)
end

function EFFECTS.SuperSpeed(model, root, base, fx)
	speedLines(base, COLORS.SuperSpeed, fx.duration)
	shockwave(root, COLORS.SuperSpeed, 22)
	burst(root, TEX.Spark, COLORS.SuperSpeed, 40, 1.2, 20)
end

function EFFECTS.TurboFlames(model, root, base, fx)
	flames(base, Vector3.new(-1.2, 1.5, 3.5), Enum.NormalId.Back, COLORS.TurboFlames, fx.duration, 2.2)
	flames(base, Vector3.new(1.2, 1.5, 3.5), Enum.NormalId.Back, COLORS.TurboFlames, fx.duration, 2.2)
	speedLines(base, COLORS.TurboFlames, fx.duration)
end

function EFFECTS.Rocket(model, root, base, fx)
	local duration = math.max(fx.duration, 1.2)
	burst(base, TEX.Burst, COLORS.Rocket, 12, 6, 14)
	shockwave(root, COLORS.Rocket, 20)
	flames(base, Vector3.new(0, 2.5, 4), Enum.NormalId.Back, COLORS.Rocket, duration, 3.5)
	smokeTrail(base, Vector3.new(0, 2.5, 5), duration)
end

function EFFECTS.Jetpack(model, root, base, fx)
	flames(root, Vector3.new(-0.6, -1.2, 0.8), Enum.NormalId.Bottom, COLORS.Jetpack, fx.duration, 1.3)
	flames(root, Vector3.new(0.6, -1.2, 0.8), Enum.NormalId.Bottom, COLORS.Jetpack, fx.duration, 1.3)
	smokeTrail(root, Vector3.new(0, -2, 1), fx.duration)
end

function EFFECTS.Lightning(model, root, base, fx)
	lightningStrike(root, math.max(fx.duration, 1))
	speedLines(base, COLORS.Lightning, fx.duration)
end

function EFFECTS.Teleport(model, root, base, fx)
	teleportBlink(model, root)
end

local function onBoostFx(fx)
	if type(fx) ~= "table" then
		return
	end
	local model = findRacer(fx.robloxUserId)
	if not model then
		return
	end
	local root = findRootPart(model)
	local base = model.PrimaryPart
	if not root or not base then
		return
	end
	local effect = EFFECTS[fx.vfx]
	if effect then
		local ok, err = pcall(effect, model, root, base, fx)
		if not ok then
			warn("[BoostFx]", fx.vfx, err)
		end
	end
	local icon = ICONS[fx.boostName] or "⚡"
	local countText = (fx.count or 1) > 1 and (" x" .. fx.count) or ""
	popup(root, string.format("%s %s%s", icon, string.upper(fx.displayName or ""), countText), COLORS[fx.vfx] or Color3.new(1, 1, 1))
	if SoundPlayer then
		SoundPlayer.Play(fx.sound)
	end
end

function BoostFxRenderer.Start(soundPlayer)
	SoundPlayer = soundPlayer
	Remotes.BoostFx.OnClientEvent:Connect(onBoostFx)
end

-- folosit și pentru testare manuală din consola clientului
BoostFxRenderer.Play = onBoostFx

return BoostFxRenderer
