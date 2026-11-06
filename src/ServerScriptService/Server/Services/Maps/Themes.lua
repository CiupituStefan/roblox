--[[
	Themes  (ModuleScript)
	Locație: ServerScriptService > Server > Services > Maps > Themes

	Aspectul fiecărei hărți: culori pistă, teren, lumină/atmosferă, decoruri.
	Decorurile sunt plasate de MapBuilder DOAR în afara pistei (verificare de
	distanță față de toată axa traseului), deci nu există obstacole pe circuit.

	Funcții de decor:
	  Decor(ctx, cf)      -> un obiect mic lângă pistă (cf = punct pe sol, rotit aleator)
	  Landmarks(ctx)      -> obiecte mari, departe de pistă (ctx:FindSpot)
	ctx:Part{...} creează o piesă ancorată, fără coliziune.
]]

local C = Color3.fromRGB
local V = Vector3.new
local M = Enum.Material

local Themes = {}

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

local function up(cf, y)
	return cf * CFrame.new(0, y, 0)
end

-- trunchi de con aproximat din cilindri suprapuși (Roblox nu are con nativ)
local function cone(ctx, cf, height, baseRadius, topRadius, steps, color, material, topColor)
	for i = 0, steps - 1 do
		local t = i / steps
		local r = baseRadius + (topRadius - baseRadius) * t
		local h = height / steps
		ctx:Part({
			size = V(h * 1.05, r * 2, r * 2),
			cf = up(cf, h * i + h / 2) * CFrame.Angles(0, 0, math.rad(90)),
			shape = "Cylinder",
			color = (topColor and i == steps - 1) and topColor or color,
			material = material,
		})
	end
end

---------------------------------------------------------------------------
Themes.CandyLand = {
	Road = C(255, 170, 200),
	RoadMaterial = M.SmoothPlastic,
	CurbA = C(255, 255, 255),
	CurbB = C(230, 40, 90),
	CenterLine = C(255, 255, 255),
	Ground = { Color = C(150, 230, 140), Material = M.Grass },
	Embankment = { Color = C(255, 230, 245), Material = M.SmoothPlastic },
	Lighting = { ClockTime = 14, Brightness = 3, Ambient = C(140, 110, 150), OutdoorAmbient = C(200, 170, 210), FogColor = C(255, 210, 235), FogEnd = 2500, Atmosphere = { Density = 0.25, Color = C(255, 200, 230), Decay = C(255, 170, 210), Haze = 1, Glare = 0.2 } },
	DecorSpacing = 26,
	Decor = function(ctx, cf)
		local rng = ctx.rng
		local kind = rng:NextInteger(1, 4)
		local candy = pick(rng, { C(255, 80, 120), C(120, 200, 255), C(255, 220, 60), C(170, 110, 255), C(90, 230, 150) })
		if kind == 1 then -- acadea
			local h = rng:NextNumber(8, 16)
			ctx:Part({ size = V(h, 0.8, 0.8), cf = up(cf, h / 2) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(250, 250, 250) })
			ctx:Part({ size = V(1.2, 7, 7), cf = up(cf, h + 2.5), shape = "Cylinder", color = candy })
			ctx:Part({ size = V(1.3, 4, 4), cf = up(cf, h + 2.5), shape = "Cylinder", color = C(255, 255, 255) })
		elseif kind == 2 then -- baston de bomboane
			for i = 0, 5 do
				ctx:Part({ size = V(1.5, 1.6, 1.6), cf = up(cf, 0.8 + i * 1.5) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = i % 2 == 0 and C(230, 30, 60) or C(255, 255, 255) })
			end
			ctx:Part({ size = V(1.6, 1.6, 4), cf = up(cf, 9.5) * CFrame.new(0, 0, -1.4), color = C(230, 30, 60) })
			ctx:Part({ size = V(1.6, 3, 1.6), cf = up(cf, 8.5) * CFrame.new(0, 0, -3.2), color = C(255, 255, 255) })
		elseif kind == 3 then -- jeleuri
			for _ = 1, rng:NextInteger(2, 4) do
				local s = rng:NextNumber(2.5, 5)
				ctx:Part({ size = V(s, s, s), cf = cf * CFrame.new(rng:NextNumber(-5, 5), s * 0.3, rng:NextNumber(-5, 5)), shape = "Ball", color = pick(rng, { C(255, 80, 120), C(120, 200, 255), C(255, 220, 60), C(90, 230, 150) }), material = M.Glass, transparency = 0.15 })
			end
		else -- brioșă uriașă
			ctx:Part({ size = V(4, 7, 7), cf = up(cf, 2) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(210, 150, 90) })
			ctx:Part({ size = V(7.5, 7.5, 7.5), cf = up(cf, 4.6), shape = "Ball", color = candy })
			ctx:Part({ size = V(1.6, 1.6, 1.6), cf = up(cf, 8.4), shape = "Ball", color = C(220, 20, 40) })
		end
	end,
	Landmarks = function(ctx)
		for _ = 1, 3 do -- torturi gigantice
			local spot = ctx:FindSpot(90)
			if spot then
				local cf = CFrame.new(spot)
				local layers = { { 60, 14, C(255, 200, 220) }, { 44, 12, C(255, 255, 255) }, { 28, 10, C(255, 150, 190) } }
				local y = 0
				for _, layer in ipairs(layers) do
					ctx:Part({ size = V(layer[2], layer[1], layer[1]), cf = up(cf, y + layer[2] / 2) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = layer[3] })
					y += layer[2]
				end
				ctx:Part({ size = V(8, 8, 8), cf = up(cf, y + 4), shape = "Ball", color = C(230, 20, 40) })
			end
		end
		local spot = ctx:FindSpot(160) -- curcubeu
		if spot then
			local colors = { C(255, 60, 60), C(255, 150, 40), C(255, 230, 50), C(80, 220, 90), C(70, 160, 255), C(150, 90, 255) }
			for band, color in ipairs(colors) do
				local radius = 120 - band * 7
				for k = 0, 18 do
					local a = math.pi * k / 18
					local at = V(math.cos(a) * radius, math.sin(a) * radius, 0)
					local tangent = V(-math.sin(a), math.cos(a), 0)
					ctx:Part({ size = V(7, 7, radius * math.pi / 18 + 1), cf = CFrame.new(spot) * CFrame.lookAt(at, at + tangent, Vector3.zAxis), color = color, neon = true })
				end
			end
		end
	end,
}

---------------------------------------------------------------------------
Themes.VolcanoRun = {
	Road = C(60, 55, 55),
	RoadMaterial = M.Asphalt,
	CurbA = C(255, 140, 20),
	CurbB = C(30, 30, 30),
	CenterLine = C(255, 200, 40),
	Ground = { Color = C(70, 50, 45), Material = M.Basalt },
	Embankment = { Color = C(50, 40, 38), Material = M.Basalt },
	Lighting = { ClockTime = 18.2, Brightness = 2, Ambient = C(120, 60, 40), OutdoorAmbient = C(160, 80, 50), FogColor = C(120, 50, 30), FogEnd = 1800, Atmosphere = { Density = 0.4, Color = C(255, 120, 60), Decay = C(120, 40, 20), Haze = 2.5, Glare = 0.5 } },
	DecorSpacing = 30,
	Decor = function(ctx, cf)
		local rng = ctx.rng
		local kind = rng:NextInteger(1, 3)
		if kind == 1 then -- stânci
			for _ = 1, rng:NextInteger(1, 3) do
				local s = rng:NextNumber(3, 9)
				ctx:Part({ size = V(s, s * 0.8, s * 1.1), cf = cf * CFrame.new(rng:NextNumber(-4, 4), s * 0.3, rng:NextNumber(-4, 4)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)), color = C(45, 35, 35), material = M.Basalt })
			end
		elseif kind == 2 then -- baltă de lavă cu foc
			local r = rng:NextNumber(8, 14)
			ctx:Part({ size = V(0.4, r, r), cf = up(cf, 0.1) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(255, 110, 20), neon = true })
			local fire = Instance.new("Fire")
			fire.Size = 8
			fire.Heat = 12
			fire.Color = C(255, 120, 30)
			fire.SecondaryColor = C(255, 40, 0)
			fire.Parent = ctx:Part({ size = V(1, 1, 1), cf = up(cf, 1), transparency = 1 })
		else -- copac carbonizat
			ctx:Part({ size = V(10, 1.2, 1.2), cf = up(cf, 5) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(30, 25, 25), material = M.Wood })
			ctx:Part({ size = V(5, 0.6, 0.6), cf = up(cf, 8) * CFrame.Angles(0, 0, math.rad(40)) * CFrame.new(2, 0, 0), color = C(30, 25, 25), material = M.Wood })
		end
	end,
	Landmarks = function(ctx)
		for i = 1, 2 do
			local spot = ctx:FindSpot(i == 1 and 200 or 140)
			if spot then
				local cf = CFrame.new(spot)
				local height = i == 1 and 160 or 100
				cone(ctx, cf, height, i == 1 and 150 or 95, i == 1 and 30 or 20, 10, C(60, 45, 40), M.Basalt)
				ctx:Part({ size = V(2, (i == 1 and 30 or 20) * 1.8, (i == 1 and 30 or 20) * 1.8), cf = up(cf, height + 0.5) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(255, 100, 10), neon = true })
				local smoke = Instance.new("Smoke")
				smoke.Size = 40
				smoke.RiseVelocity = 20
				smoke.Opacity = 0.25
				smoke.Color = C(80, 70, 70)
				smoke.Parent = ctx:Part({ size = V(1, 1, 1), cf = up(cf, height + 4), transparency = 1 })
			end
		end
	end,
}

---------------------------------------------------------------------------
Themes.NeonCity = {
	Road = C(25, 25, 35),
	RoadMaterial = M.Asphalt,
	CurbA = C(0, 255, 230),
	CurbB = C(255, 0, 200),
	CenterLine = C(255, 255, 255),
	NeonCurbs = true,
	Ground = { Color = C(20, 20, 30), Material = M.Concrete },
	Embankment = { Color = C(30, 30, 45), Material = M.Concrete },
	Lighting = { ClockTime = 0.5, Brightness = 1, Ambient = C(70, 60, 110), OutdoorAmbient = C(90, 80, 140), FogColor = C(40, 20, 70), FogEnd = 2000, Atmosphere = { Density = 0.3, Color = C(120, 60, 200), Decay = C(40, 20, 80), Haze = 1.5, Glare = 1 } },
	DecorSpacing = 28,
	Decor = function(ctx, cf)
		local rng = ctx.rng
		local neon = pick(rng, { C(0, 255, 230), C(255, 0, 200), C(255, 230, 0), C(80, 140, 255) })
		if rng:NextNumber() < 0.6 then -- clădire
			local w, d, h = rng:NextNumber(14, 24), rng:NextNumber(14, 24), rng:NextNumber(30, 90)
			local building = up(cf, h / 2) * CFrame.new(0, 0, 0)
			ctx:Part({ size = V(w, h, d), cf = building, color = C(30, 30, 45), material = M.Glass, transparency = 0.05 })
			for y = 6, h - 4, 9 do
				ctx:Part({ size = V(w + 0.3, 0.8, d + 0.3), cf = up(cf, y), color = neon, neon = true })
			end
			ctx:Part({ size = V(w * 0.6, 3, d * 0.6), cf = up(cf, h + 1.5), color = neon, neon = true })
		else -- stâlp de iluminat
			ctx:Part({ size = V(14, 0.7, 0.7), cf = up(cf, 7) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(60, 60, 70), material = M.Metal })
			local lamp = ctx:Part({ size = V(2.2, 2.2, 2.2), cf = up(cf, 14.5), shape = "Ball", color = neon, neon = true })
			local light = Instance.new("PointLight")
			light.Color = neon
			light.Range = 24
			light.Brightness = 2
			light.Parent = lamp
		end
	end,
	Landmarks = function(ctx)
		local texts = { "TIKTOK RACE", "BOOST!", "GO GO GO", "TURBO", "#1" }
		for i = 1, 5 do
			local spot = ctx:FindSpot(70)
			if spot then
				local h = 140 + i * 15
				local cf = CFrame.new(spot)
				ctx:Part({ size = V(30, h, 30), cf = up(cf, h / 2), color = C(25, 25, 40), material = M.Glass })
				ctx:Part({ size = V(32, 4, 32), cf = up(cf, h), color = C(255, 0, 200), neon = true })
				local board = ctx:Part({ size = V(40, 14, 1), cf = up(cf, h * 0.7) * CFrame.new(0, 0, -16), color = C(10, 10, 20) })
				ctx:Label(board, Enum.NormalId.Front, texts[i], C(0, 255, 230))
				ctx:Label(board, Enum.NormalId.Back, texts[i], C(255, 0, 200))
			end
		end
	end,
}

---------------------------------------------------------------------------
Themes.JungleLoop = {
	Road = C(150, 110, 70),
	RoadMaterial = M.Ground,
	CurbA = C(255, 220, 60),
	CurbB = C(60, 140, 50),
	CenterLine = C(240, 230, 200),
	Ground = { Color = C(70, 150, 60), Material = M.Grass },
	Embankment = { Color = C(110, 80, 50), Material = M.Ground },
	Lighting = { ClockTime = 10, Brightness = 2.5, Ambient = C(80, 110, 70), OutdoorAmbient = C(130, 170, 120), FogColor = C(170, 210, 160), FogEnd = 2000, Atmosphere = { Density = 0.35, Color = C(190, 230, 180), Decay = C(100, 140, 90), Haze = 1.5, Glare = 0.3 } },
	DecorSpacing = 18,
	Decor = function(ctx, cf)
		local rng = ctx.rng
		local kind = rng:NextInteger(1, 4)
		if kind <= 2 then -- copac
			local h = rng:NextNumber(14, 26)
			ctx:Part({ size = V(h, 2, 2), cf = up(cf, h / 2) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(100, 70, 40), material = M.Wood })
			for _ = 1, 3 do
				local s = rng:NextNumber(8, 13)
				ctx:Part({ size = V(s, s, s), cf = up(cf, h + rng:NextNumber(-1, 3)) * CFrame.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)), shape = "Ball", color = pick(rng, { C(50, 140, 50), C(70, 170, 60), C(40, 120, 45) }), material = M.Grass })
			end
		elseif kind == 3 then -- tufiș cu flori
			local s = rng:NextNumber(4, 7)
			ctx:Part({ size = V(s, s, s), cf = up(cf, s * 0.3), shape = "Ball", color = C(60, 150, 55), material = M.Grass })
			for _ = 1, 3 do
				ctx:Part({ size = V(1, 1, 1), cf = up(cf, s * 0.6) * CFrame.new(rng:NextNumber(-2, 2), rng:NextNumber(0, 1), rng:NextNumber(-2, 2)), shape = "Ball", color = pick(rng, { C(255, 80, 150), C(255, 220, 60), C(255, 120, 40) }), neon = true })
			end
		else -- stâncă cu mușchi
			local s = rng:NextNumber(4, 8)
			ctx:Part({ size = V(s * 1.3, s, s), cf = up(cf, s * 0.35) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), color = C(110, 120, 100), material = M.Slate })
		end
	end,
	Landmarks = function(ctx)
		local spot = ctx:FindSpot(130) -- templu în trepte
		if spot then
			local cf = CFrame.new(spot)
			for i = 0, 6 do
				local s = 90 - i * 12
				ctx:Part({ size = V(s, 8, s), cf = up(cf, 4 + i * 8), color = C(150, 150, 120), material = M.Cobblestone })
			end
			ctx:Part({ size = V(12, 10, 12), cf = up(cf, 61), color = C(200, 170, 60), material = M.Cobblestone })
		end
		for _ = 1, 4 do -- copaci gigantici
			local giant = ctx:FindSpot(70)
			if giant then
				local cf = CFrame.new(giant)
				ctx:Part({ size = V(80, 8, 8), cf = up(cf, 40) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(90, 60, 35), material = M.Wood })
				for _ = 1, 4 do
					ctx:Part({ size = V(34, 34, 34), cf = up(cf, 80) * CFrame.new(ctx.rng:NextNumber(-12, 12), ctx.rng:NextNumber(-4, 8), ctx.rng:NextNumber(-12, 12)), shape = "Ball", color = C(45, 130, 50), material = M.Grass })
				end
			end
		end
	end,
}

---------------------------------------------------------------------------
Themes.SnowPeaks = {
	Road = C(200, 215, 230),
	RoadMaterial = M.Ice,
	CurbA = C(255, 255, 255),
	CurbB = C(40, 120, 220),
	CenterLine = C(40, 120, 220),
	Ground = { Color = C(240, 245, 255), Material = M.Snow },
	Embankment = { Color = C(225, 235, 250), Material = M.Snow },
	Lighting = { ClockTime = 12.5, Brightness = 3, Ambient = C(140, 150, 180), OutdoorAmbient = C(190, 200, 230), FogColor = C(220, 230, 255), FogEnd = 2200, Atmosphere = { Density = 0.35, Color = C(220, 230, 255), Decay = C(160, 180, 220), Haze = 2, Glare = 0.6 } },
	DecorSpacing = 22,
	Decor = function(ctx, cf)
		local rng = ctx.rng
		local kind = rng:NextInteger(1, 4)
		if kind <= 2 then -- brad înzăpezit
			local h = rng:NextNumber(14, 24)
			ctx:Part({ size = V(4, 1.6, 1.6), cf = up(cf, 2) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(90, 60, 40), material = M.Wood })
			cone(ctx, up(cf, 3), h, h * 0.32, 0.6, 5, C(40, 100, 60), M.Grass, C(250, 250, 255))
		elseif kind == 3 then -- om de zăpadă
			ctx:Part({ size = V(5, 5, 5), cf = up(cf, 2.3), shape = "Ball", color = C(250, 250, 255), material = M.Snow })
			ctx:Part({ size = V(3.6, 3.6, 3.6), cf = up(cf, 6), shape = "Ball", color = C(250, 250, 255), material = M.Snow })
			ctx:Part({ size = V(2.6, 2.6, 2.6), cf = up(cf, 8.7), shape = "Ball", color = C(250, 250, 255), material = M.Snow })
			ctx:Part({ size = V(0.4, 0.4, 1.4), cf = up(cf, 8.7) * CFrame.new(0, 0, -1.6), color = C(255, 130, 20) })
			ctx:Part({ size = V(2.8, 0.4, 2.8), cf = up(cf, 9.9), color = C(30, 30, 30) })
			ctx:Part({ size = V(1.8, 1.6, 1.8), cf = up(cf, 10.9), color = C(30, 30, 30) })
		else -- cristale de gheață
			for _ = 1, 3 do
				local h = rng:NextNumber(4, 9)
				ctx:Part({ size = V(1.6, h, 1.6), cf = up(cf, h / 2) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), color = C(150, 220, 255), material = M.Glass, transparency = 0.25 })
			end
		end
	end,
	Landmarks = function(ctx)
		for i = 1, 4 do -- munți
			local spot = ctx:FindSpot(160)
			if spot then
				local h = 180 + i * 30
				cone(ctx, CFrame.new(spot), h, 150, 15, 9, C(130, 135, 150), M.Rock, C(250, 250, 255))
				ctx:Part({ size = V(h * 0.35, 120, 120), cf = CFrame.new(spot) * CFrame.new(0, h * 0.82, 0) * CFrame.Angles(0, 0, math.rad(90)), shape = "Cylinder", color = C(250, 250, 255), material = M.Snow })
			end
		end
		local igloo = ctx:FindSpot(60)
		if igloo then
			ctx:Part({ size = V(22, 22, 22), cf = CFrame.new(igloo), shape = "Ball", color = C(235, 245, 255), material = M.Ice })
		end
	end,
}

---------------------------------------------------------------------------
Themes.SpaceStation = {
	Road = C(40, 45, 70),
	RoadMaterial = M.DiamondPlate,
	CurbA = C(80, 200, 255),
	CurbB = C(170, 80, 255),
	CenterLine = C(255, 255, 255),
	NeonCurbs = true,
	Ground = nil, -- spațiu: pista plutește
	Underglow = C(120, 90, 255),
	Lighting = { ClockTime = 0, Brightness = 1.5, Ambient = C(100, 100, 150), OutdoorAmbient = C(120, 120, 170), FogColor = C(10, 5, 30), FogEnd = 5000, Atmosphere = { Density = 0, Color = C(40, 20, 80), Decay = C(20, 10, 40), Haze = 0, Glare = 0 } },
	DecorSpacing = 34,
	FloatingDecor = true, -- decorurile stau la înălțimea pistei
	Decor = function(ctx, cf)
		local rng = ctx.rng
		local kind = rng:NextInteger(1, 3)
		local floatCf = cf * CFrame.new(0, rng:NextNumber(-12, 14), 0)
		if kind == 1 then -- asteroid
			local s = rng:NextNumber(5, 14)
			ctx:Part({ size = V(s, s, s), cf = floatCf, shape = "Ball", color = C(110, 100, 95), material = M.Slate })
			ctx:Part({ size = V(s * 0.5, s * 0.5, s * 0.5), cf = floatCf * CFrame.new(s * 0.45, s * 0.2, 0), shape = "Ball", color = C(90, 85, 80), material = M.Slate })
		elseif kind == 2 then -- inel de energie
			local color = pick(rng, { C(80, 200, 255), C(170, 80, 255), C(255, 80, 200) })
			local ringCf = floatCf * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
			for k = 0, 11 do
				local a = k / 12 * math.pi * 2
				local at = V(math.cos(a) * 6, math.sin(a) * 6, 0)
				local tangent = V(-math.sin(a), math.cos(a), 0)
				ctx:Part({ size = V(1, 1, 3.4), cf = ringCf * CFrame.lookAt(at, at + tangent, Vector3.zAxis), color = color, neon = true })
			end
		else -- satelit
			ctx:Part({ size = V(3, 3, 4), cf = floatCf, color = C(200, 200, 210), material = M.Metal })
			ctx:Part({ size = V(10, 0.2, 3), cf = floatCf, color = C(40, 80, 200), material = M.Glass })
			ctx:Part({ size = V(0.3, 4, 0.3), cf = floatCf * CFrame.new(0, 3, 0), color = C(220, 220, 220), material = M.Metal })
		end
	end,
	Landmarks = function(ctx)
		local planets = {
			{ size = 300, color = C(230, 120, 60), dist = 900, ring = true },
			{ size = 160, color = C(80, 140, 255), dist = 700 },
			{ size = 90, color = C(200, 90, 255), dist = 600 },
		}
		local center = ctx.center
		for i, planet in ipairs(planets) do
			local a = i * 2.1
			local pos = center + Vector3.new(math.cos(a) * planet.dist, 120 + i * 60, math.sin(a) * planet.dist)
			ctx:Part({ size = V(planet.size, planet.size, planet.size), cf = CFrame.new(pos), shape = "Ball", color = planet.color, material = M.SmoothPlastic })
			if planet.ring then
				ctx:Part({ size = V(4, planet.size * 1.9, planet.size * 1.9), cf = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(80)), shape = "Cylinder", color = C(240, 200, 150), transparency = 0.4 })
			end
		end
	end,
}

return Themes
