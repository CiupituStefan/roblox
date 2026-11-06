--[[
	Designs  (ModuleScript)
	Locație: ServerScriptService > Server > Services > Mounts > Designs

	Cele 16 mount-uri, construite procedural din Part-uri. Sunt modele ORIGINALE,
	doar inspirate de idei populare (porc cu morcov, kart, pasăre roșie etc.),
	fără să copieze modele sau personaje protejate.

	Coordonate: Y = 0 este solul, fața mount-ului este spre -Z.
	Stiluri de animație (pe client): Walker, Wheeled, Flyer, Crawler, Bouncer.

	Pentru a adăuga un mount nou:
	  1. scrie aici o funcție Designs.IdNou = function(b) ... return b:finish("Stil") end
	  2. adaugă { Id = "IdNou", ... } în Config.Mounts
	(sau pune un model propriu în ServerStorage > CustomMounts, vezi MountFactory)
]]

local V = Vector3.new
local C = Color3.fromRGB
local M = Enum.Material

local Designs = {}

---------------------------------------------------------------------------
-- Patrupede
---------------------------------------------------------------------------
Designs.BlockPig = function(b)
	local pink, darkPink = C(240, 160, 175), C(215, 115, 135)
	b:mainBody({ size = V(3.6, 3, 5), pos = V(0, 3.1, 0), color = pink })
	for name, p in pairs({ LegFL = V(-1.1, 1.6, -1.7), LegFR = V(1.1, 1.6, -1.7), LegBL = V(-1.1, 1.6, 1.7), LegBR = V(1.1, 1.6, 1.7) }) do
		b:leg(name, p, V(1.2, 1.6, 1.2), pink, darkPink)
	end
	local head = b:pivot("Head", V(0, 3.6, -2.5))
	b:part({ size = V(2.8, 2.6, 2.6), pos = V(0, 3.7, -3.7), color = pink, attach = head })
	b:part({ size = V(1.4, 1, 0.4), pos = V(0, 3.3, -5.15), color = darkPink, attach = head })
	b:part({ size = V(0.3, 0.3, 0.1), pos = V(-0.35, 3.35, -5.38), color = C(120, 60, 70), attach = head })
	b:part({ size = V(0.3, 0.3, 0.1), pos = V(0.35, 3.35, -5.38), color = C(120, 60, 70), attach = head })
	b:eyes(0.8, 4.25, -5.02, head)
	b:part({ size = V(0.7, 0.5, 0.3), pos = V(-1, 5.1, -3.2), color = darkPink, attach = head })
	b:part({ size = V(0.7, 0.5, 0.3), pos = V(1, 5.1, -3.2), color = darkPink, attach = head })
	-- șa
	b:part({ size = V(3.7, 0.4, 2.2), pos = V(0, 4.8, 0.3), color = C(120, 75, 40), material = M.Leather })
	-- undița cu morcov (se leagănă)
	local rod = b:pivot("Rod", V(0.9, 5.2, 0))
	b:part({ size = V(0.15, 0.15, 6), pos = V(0.9, 6.35, -2.75), rot = V(22.7, 0, 0), color = C(110, 70, 35), material = M.Wood, attach = rod })
	b:part({ size = V(0.06, 1.2, 0.06), pos = V(0.9, 6.9, -5.5), color = C(230, 230, 230), attach = rod })
	b:part({ size = V(0.45, 1, 0.45), pos = V(0.9, 5.9, -5.5), color = C(255, 130, 20), attach = rod })
	b:part({ size = V(0.55, 0.3, 0.55), pos = V(0.9, 6.5, -5.5), color = C(60, 170, 50), attach = rod })
	local tail = b:pivot("Tail", V(0, 3.8, 2.5))
	b:part({ size = V(0.4, 0.4, 0.6), pos = V(0, 3.9, 2.8), color = darkPink, attach = tail })
	b:seat(V(0, 5.0, 0.3))
	return b:finish("Walker")
end

Designs.Horse = function(b)
	local brown, dark = C(135, 85, 45), C(40, 28, 20)
	b:mainBody({ size = V(2.6, 2.4, 5.6), pos = V(0, 4.2, 0), color = brown })
	for name, p in pairs({ LegFL = V(-0.8, 3, -2.1), LegFR = V(0.8, 3, -2.1), LegBL = V(-0.8, 3, 2.1), LegBR = V(0.8, 3, 2.1) }) do
		b:leg(name, p, V(0.8, 3, 0.8), brown, dark)
	end
	local head = b:pivot("Head", V(0, 5, -2.6))
	b:part({ size = V(1.2, 2.8, 1.2), pos = V(0, 6.0, -3.2), rot = V(-30, 0, 0), color = brown, attach = head })
	b:part({ size = V(0.3, 2.6, 0.9), pos = V(0, 6.4, -2.85), rot = V(-30, 0, 0), color = dark, attach = head })
	b:part({ size = V(1.2, 1.2, 2.6), pos = V(0, 7.2, -4.4), color = brown, attach = head })
	b:part({ size = V(1.0, 0.6, 0.3), pos = V(0, 6.85, -5.75), color = C(90, 55, 30), attach = head })
	b:eyes(0.62, 7.45, -4.6, head, 0.4)
	b:part({ size = V(0.3, 0.6, 0.3), pos = V(-0.4, 8.0, -3.6), color = brown, attach = head })
	b:part({ size = V(0.3, 0.6, 0.3), pos = V(0.4, 8.0, -3.6), color = brown, attach = head })
	b:part({ size = V(2.7, 0.4, 2), pos = V(0, 5.6, 0.2), color = C(190, 30, 40), material = M.Fabric })
	local tail = b:pivot("Tail", V(0, 5, 2.8))
	b:part({ size = V(0.5, 2.4, 0.5), pos = V(0, 3.9, 3.2), rot = V(-20, 0, 0), color = dark, attach = tail })
	b:seat(V(0, 5.8, 0.2))
	return b:finish("Walker")
end

Designs.Rhino = function(b)
	local grey, darkGrey, ivory = C(125, 125, 135), C(85, 85, 95), C(235, 225, 200)
	b:mainBody({ size = V(3.8, 3.2, 6), pos = V(0, 3.4, 0), color = grey, material = M.Slate })
	for name, p in pairs({ LegFL = V(-1.2, 1.8, -2), LegFR = V(1.2, 1.8, -2), LegBL = V(-1.2, 1.8, 2), LegBR = V(1.2, 1.8, 2) }) do
		b:leg(name, p, V(1.3, 1.8, 1.3), grey, darkGrey)
	end
	local head = b:pivot("Head", V(0, 3.6, -3))
	b:part({ size = V(2.4, 2.2, 2.6), pos = V(0, 3.4, -4.3), color = grey, material = M.Slate, attach = head })
	b:part({ size = V(0.8, 1.6, 1.2), pos = V(0, 5.2, -5.0), shape = "Wedge", color = ivory, attach = head })
	b:part({ size = V(0.5, 0.8, 0.7), pos = V(0, 4.85, -3.9), shape = "Wedge", color = ivory, attach = head })
	b:eyes(0.85, 3.9, -5.62, head, 0.4)
	b:part({ size = V(0.4, 0.7, 0.3), pos = V(-0.9, 4.8, -3.3), color = grey, attach = head })
	b:part({ size = V(0.4, 0.7, 0.3), pos = V(0.9, 4.8, -3.3), color = grey, attach = head })
	b:part({ size = V(4, 0.4, 2.4), pos = V(0, 5.2, 0.3), color = darkGrey, material = M.DiamondPlate })
	local tail = b:pivot("Tail", V(0, 4.2, 3))
	b:part({ size = V(0.25, 1.4, 0.25), pos = V(0, 3.6, 3.2), color = darkGrey, attach = tail })
	b:seat(V(0, 5.4, 0.3))
	return b:finish("Walker")
end

Designs.Capybara = function(b)
	local fur, dark = C(160, 112, 70), C(90, 60, 40)
	b:mainBody({ size = V(3, 2.6, 4.6), pos = V(0, 2.3, 0), color = fur, material = M.Fabric })
	for name, p in pairs({ LegFL = V(-1, 1, -1.5), LegFR = V(1, 1, -1.5), LegBL = V(-1, 1, 1.5), LegBR = V(1, 1, 1.5) }) do
		b:leg(name, p, V(0.9, 1, 0.9), fur, dark)
	end
	local head = b:pivot("Head", V(0, 2.6, -2.3))
	b:part({ size = V(2.2, 2, 2.4), pos = V(0, 3.0, -3.3), color = fur, material = M.Fabric, attach = head })
	b:part({ size = V(1.6, 0.9, 0.4), pos = V(0, 2.8, -4.6), color = dark, attach = head })
	b:part({ size = V(0.55, 0.12, 0.1), pos = V(-0.6, 3.55, -4.52), color = C(20, 20, 20), attach = head }) -- ochi „zen”
	b:part({ size = V(0.55, 0.12, 0.1), pos = V(0.6, 3.55, -4.52), color = C(20, 20, 20), attach = head })
	b:part({ size = V(0.4, 0.35, 0.3), pos = V(-0.8, 4.1, -2.7), color = dark, attach = head })
	b:part({ size = V(0.4, 0.35, 0.3), pos = V(0.8, 4.1, -2.7), color = dark, attach = head })
	b:part({ size = V(0.9, 0.9, 0.9), pos = V(0, 4.45, -3.1), shape = "Ball", color = C(255, 150, 30), attach = head })
	b:part({ size = V(0.5, 0.12, 0.3), pos = V(0.15, 4.95, -3.1), rot = V(0, 0, 20), color = C(60, 160, 60), attach = head })
	b:part({ size = V(3.1, 0.3, 2), pos = V(0, 3.75, 0.3), color = C(40, 180, 170), material = M.Fabric })
	b:seat(V(0, 3.9, 0.3))
	return b:finish("Walker")
end

---------------------------------------------------------------------------
-- Pe roți
---------------------------------------------------------------------------
local function kartWheels(b, x, z, y, radius, width, color, hub)
	b:wheel("Wheel1", V(-x, y, -z), radius, width, color, hub)
	b:wheel("Wheel2", V(x, y, -z), radius, width, color, hub)
	b:wheel("Wheel3", V(-x, y, z), radius, width, color, hub)
	b:wheel("Wheel4", V(x, y, z), radius, width, color, hub)
end

Designs.ClassicKart = function(b)
	local red, black = C(220, 40, 40), C(25, 25, 25)
	b:mainBody({ size = V(4.4, 0.6, 7), pos = V(0, 0.9, 0), color = red, material = M.Metal })
	kartWheels(b, 2.5, 2.5, 0.9, 0.9, 0.8, black, C(230, 230, 230))
	b:part({ size = V(4.6, 0.6, 0.6), pos = V(0, 0.9, -3.7), color = C(240, 240, 240) })
	b:part({ size = V(3, 0.8, 1.6), pos = V(0, 1.6, -2.7), shape = "Wedge", color = red, material = M.Metal })
	b:part({ size = V(2.4, 0.4, 2), pos = V(0, 1.4, 0.6), color = black })
	b:part({ size = V(2.4, 2.2, 0.5), pos = V(0, 2.5, 1.7), color = black })
	b:part({ size = V(0.2, 1.4, 0.2), pos = V(0, 2.0, -1.0), rot = V(40, 0, 0), color = C(60, 60, 60) })
	b:part({ size = V(0.2, 1.4, 1.4), pos = V(0, 2.5, -0.6), rot = V(0, 90, 0), shape = "Cylinder", color = black })
	b:part({ size = V(0.3, 1.4, 0.3), pos = V(-1.5, 2.1, 3.3), color = black })
	b:part({ size = V(0.3, 1.4, 0.3), pos = V(1.5, 2.1, 3.3), color = black })
	b:part({ size = V(4.4, 0.2, 1.2), pos = V(0, 2.9, 3.3), color = red, material = M.Metal })
	for _, x in ipairs({ -0.8, 0.8 }) do
		b:part({ size = V(1.2, 0.45, 0.45), pos = V(x, 1.2, 3.8), rot = V(0, 90, 0), shape = "Cylinder", color = C(150, 150, 160), material = M.Metal })
	end
	b:seat(V(0, 1.6, 0.6))
	return b:finish("Wheeled")
end

Designs.BirdKart = function(b)
	local red, white, black, yellow = C(205, 30, 40), C(245, 235, 220), C(20, 20, 20), C(255, 190, 30)
	b:mainBody({ size = V(4.2, 0.6, 7), pos = V(0, 0.9, 0), color = C(110, 75, 45), material = M.Wood })
	kartWheels(b, 2.4, 2.5, 0.9, 0.9, 0.8, black, yellow)
	local head = b:pivot("Head", V(0, 2.4, -2.6))
	b:part({ size = V(4, 4, 4), pos = V(0, 2.8, -2.7), shape = "Ball", color = red, attach = head })
	b:part({ size = V(2.8, 2.8, 2.8), pos = V(0, 2.1, -3.7), shape = "Ball", color = white, attach = head })
	b:part({ size = V(1.2, 0.8, 1.1), pos = V(0, 2.75, -4.95), shape = "Wedge", color = yellow, attach = head })
	b:part({ size = V(1.2, 0.5, 1.1), pos = V(0, 2.1, -4.85), rot = V(0, 0, 180), shape = "Wedge", color = C(230, 160, 20), attach = head })
	for _, side in ipairs({ -1, 1 }) do
		b:part({ size = V(0.95, 0.95, 0.95), pos = V(side * 0.65, 3.35, -4.35), shape = "Ball", color = C(255, 255, 255), attach = head })
		b:part({ size = V(0.4, 0.4, 0.4), pos = V(side * 0.6, 3.3, -4.8), shape = "Ball", color = black, attach = head })
		b:part({ size = V(1.2, 0.3, 0.3), pos = V(side * 0.65, 4.0, -4.4), rot = V(0, 0, side * 20), color = black, attach = head })
		b:part({ size = V(0.3, 1.1, 0.3), pos = V(side * 0.2, 5.0, -2.4), rot = V(0, 0, side * 15), color = red, attach = head })
	end
	b:part({ size = V(2.4, 0.4, 1.8), pos = V(0, 1.4, 1.0), color = black })
	b:part({ size = V(2.4, 2, 0.5), pos = V(0, 2.4, 2.0), color = black })
	local tail = b:pivot("Tail", V(0, 2.2, 3.2))
	for i, x in ipairs({ -0.5, 0, 0.5 }) do
		b:part({ size = V(0.35, 1.6, 0.3), pos = V(x, 2.9, 3.4), rot = V(-25, 0, (i - 2) * 20), color = black, attach = tail })
	end
	b:seat(V(0, 1.6, 1.0))
	return b:finish("Wheeled")
end

Designs.ShoppingCart = function(b)
	local metal = C(190, 195, 205)
	b:mainBody({ size = V(3.6, 0.3, 5), pos = V(0, 1.0, 0), color = metal, material = M.Metal })
	local wall = { color = metal, material = M.Metal, transparency = 0.35 }
	local function w(size, pos)
		b:part({ size = size, pos = pos, color = wall.color, material = wall.material, transparency = wall.transparency })
	end
	w(V(0.15, 2.4, 5), V(-1.8, 2.35, 0))
	w(V(0.15, 2.4, 5), V(1.8, 2.35, 0))
	w(V(3.6, 2.4, 0.15), V(0, 2.35, -2.5))
	w(V(3.6, 2.4, 0.15), V(0, 2.35, 2.5))
	for _, x in ipairs({ -1.8, 1.8 }) do
		b:part({ size = V(0.25, 0.25, 5.2), pos = V(x, 3.6, 0), color = metal, material = M.Metal })
	end
	b:part({ size = V(3.8, 0.25, 0.25), pos = V(0, 3.6, -2.55), color = metal, material = M.Metal })
	b:part({ size = V(0.15, 0.9, 0.15), pos = V(-1.7, 3.55, 2.9), color = metal, material = M.Metal })
	b:part({ size = V(0.15, 0.9, 0.15), pos = V(1.7, 3.55, 2.9), color = metal, material = M.Metal })
	b:part({ size = V(3.8, 0.3, 0.3), pos = V(0, 4.0, 3.2), color = C(220, 40, 40) })
	for _, x in ipairs({ -1.4, 1.4 }) do
		for _, z in ipairs({ -2, 2 }) do
			b:part({ size = V(0.2, 0.5, 0.2), pos = V(x, 0.7, z), color = metal, material = M.Metal })
		end
	end
	b:wheel("Wheel1", V(-1.4, 0.4, -2), 0.4, 0.3)
	b:wheel("Wheel2", V(1.4, 0.4, -2), 0.4, 0.3)
	b:wheel("Wheel3", V(-1.4, 0.4, 2), 0.4, 0.3)
	b:wheel("Wheel4", V(1.4, 0.4, 2), 0.4, 0.3)
	b:seat(V(0, 1.2, 0.4))
	return b:finish("Wheeled")
end

Designs.TurboToilet = function(b)
	local white = C(245, 248, 255)
	b:mainBody({ size = V(3.4, 0.5, 5), pos = V(0, 0.8, 0), color = C(60, 60, 70), material = M.Metal })
	kartWheels(b, 2, 1.8, 0.7, 0.7, 0.6, C(25, 25, 25), C(60, 160, 255))
	b:part({ size = V(1.8, 3, 3), pos = V(0, 1.95, -0.2), rot = V(0, 0, 90), shape = "Cylinder", color = white, material = M.Marble })
	b:part({ size = V(0.25, 3.3, 3.3), pos = V(0, 2.95, -0.2), rot = V(0, 0, 90), shape = "Cylinder", color = C(230, 230, 240) })
	b:part({ size = V(3, 3, 1.2), pos = V(0, 3.2, 1.9), color = white, material = M.Marble })
	b:part({ size = V(3.2, 0.3, 1.4), pos = V(0, 4.85, 1.9), color = C(230, 230, 240) })
	b:part({ size = V(0.6, 0.15, 0.15), pos = V(1.2, 4.3, 1.2), color = C(200, 200, 210), material = M.Metal })
	local flame = b:pivot("Flame", V(0, 1.4, 3.3))
	for _, x in ipairs({ -0.8, 0.8 }) do
		b:part({ size = V(1.2, 0.9, 0.9), pos = V(x, 1.4, 2.9), rot = V(0, 90, 0), shape = "Cylinder", color = C(90, 90, 100), material = M.Metal })
		b:part({ size = V(0.6, 0.6, 0.8), pos = V(x, 1.4, 3.75), color = C(80, 200, 255), neon = true, attach = flame })
	end
	b:seat(V(0, 3.05, -0.2))
	return b:finish("Wheeled")
end

Designs.Banana = function(b)
	local yellow, stem = C(250, 222, 55), C(95, 65, 30)
	b:mainBody({ size = V(2.2, 1.6, 3), pos = V(0, 1.8, 0), color = yellow })
	b:part({ size = V(2, 1.4, 2.4), pos = V(0, 2.25, -2.45), rot = V(20, 0, 0), color = yellow })
	b:part({ size = V(0.8, 0.8, 1), pos = V(0, 2.95, -3.85), rot = V(30, 0, 0), color = stem })
	b:part({ size = V(2, 1.4, 2.4), pos = V(0, 2.25, 2.45), rot = V(-20, 0, 0), color = yellow })
	b:part({ size = V(0.7, 0.7, 1.2), pos = V(0, 3.0, 3.9), rot = V(-35, 0, 0), color = stem })
	for _, z in ipairs({ -1.2, 0, 1.2 }) do
		b:part({ size = V(2.25, 0.08, 0.15), pos = V(0, 2.62, z), color = C(200, 175, 40) })
	end
	b:part({ size = V(3, 0.3, 0.3), pos = V(0, 0.7, -2.2), color = C(70, 70, 70), material = M.Metal })
	b:part({ size = V(3, 0.3, 0.3), pos = V(0, 0.7, 2.2), color = C(70, 70, 70), material = M.Metal })
	kartWheels(b, 1.55, 2.2, 0.7, 0.7, 0.5, C(30, 30, 30), C(250, 222, 55))
	b:seat(V(0, 2.6, 0))
	return b:finish("Wheeled")
end

Designs.Shark = function(b)
	local blue, belly = C(105, 140, 175), C(235, 240, 245)
	b:mainBody({ size = V(2.4, 0.3, 6.5), pos = V(0, 0.9, 0), color = C(130, 60, 190), material = M.Wood })
	for _, z in ipairs({ -2.4, 2.4 }) do
		b:part({ size = V(1.8, 0.3, 0.4), pos = V(0, 0.65, z), color = C(170, 170, 180), material = M.Metal })
	end
	b:wheel("Wheel1", V(-0.9, 0.4, -2.4), 0.4, 0.4, C(70, 255, 120), C(255, 255, 255))
	b:wheel("Wheel2", V(0.9, 0.4, -2.4), 0.4, 0.4, C(70, 255, 120), C(255, 255, 255))
	b:wheel("Wheel3", V(-0.9, 0.4, 2.4), 0.4, 0.4, C(70, 255, 120), C(255, 255, 255))
	b:wheel("Wheel4", V(0.9, 0.4, 2.4), 0.4, 0.4, C(70, 255, 120), C(255, 255, 255))
	b:part({ size = V(2, 1.8, 5.5), pos = V(0, 2.0, 0), color = blue })
	b:part({ size = V(1.8, 0.6, 5), pos = V(0, 1.35, 0), color = belly })
	b:part({ size = V(1.8, 1.4, 1.4), pos = V(0, 2.0, -3.45), shape = "Wedge", color = blue })
	b:part({ size = V(1.6, 0.2, 0.1), pos = V(0, 1.55, -2.78), color = C(255, 255, 255) })
	b:eyes(0.92, 2.45, -2.4, nil, 0.4)
	b:part({ size = V(0.25, 1.5, 1.4), pos = V(0, 3.6, 1.9), shape = "Wedge", color = blue })
	b:part({ size = V(1.2, 0.15, 0.8), pos = V(-1.4, 1.7, -1), color = blue })
	b:part({ size = V(1.2, 0.15, 0.8), pos = V(1.4, 1.7, -1), color = blue })
	local tail = b:pivot("Tail", V(0, 2.0, 2.75))
	b:part({ size = V(0.25, 2.2, 1), pos = V(0, 2.2, 3.4), color = blue, attach = tail })
	b:seat(V(0, 2.9, 0))
	return b:finish("Wheeled")
end

---------------------------------------------------------------------------
-- Zburătoare
---------------------------------------------------------------------------
Designs.Plane = function(b)
	local white, blue, red = C(235, 238, 245), C(60, 130, 230), C(220, 50, 50)
	b:mainBody({ size = V(6.5, 2, 2), pos = V(0, 3, 0), rot = V(0, 90, 0), shape = "Cylinder", color = white, material = M.Metal })
	b:part({ size = V(2, 2, 2), pos = V(0, 3, -3.2), shape = "Ball", color = red })
	local prop = b:pivot("Prop", V(0, 3, -4.3))
	b:part({ size = V(0.3, 3.6, 0.15), pos = V(0, 3, -4.3), color = C(40, 40, 40), attach = prop })
	b:part({ size = V(3.6, 0.3, 0.15), pos = V(0, 3, -4.3), color = C(40, 40, 40), attach = prop })
	b:part({ size = V(9, 0.3, 1.8), pos = V(0, 2.6, -0.5), color = blue, material = M.Metal })
	b:part({ size = V(3.4, 0.25, 1), pos = V(0, 3.3, 3.0), color = blue, material = M.Metal })
	b:part({ size = V(0.25, 1.6, 1.2), pos = V(0, 4.1, 3.0), shape = "Wedge", color = red })
	b:part({ size = V(6.6, 0.3, 0.2), pos = V(0, 3.2, 0), rot = V(0, 90, 0), color = blue })
	b:seat(V(0, 3.95, 0.6))
	return b:finish("Flyer")
end

Designs.Rocket = function(b)
	local card = C(195, 155, 105)
	b:mainBody({ size = V(6, 2.2, 2.2), pos = V(0, 2.8, 0), rot = V(0, 90, 0), shape = "Cylinder", color = card, material = M.Cardboard })
	b:part({ size = V(2.2, 2.2, 2.2), pos = V(0, 2.8, -3.0), shape = "Ball", color = C(220, 50, 50) })
	b:part({ size = V(0.2, 1.4, 1.4), pos = V(0, 4.3, 2.4), shape = "Wedge", color = C(220, 50, 50) })
	b:part({ size = V(1.4, 0.2, 1.4), pos = V(-1.6, 2.8, 2.4), color = C(220, 50, 50) })
	b:part({ size = V(1.4, 0.2, 1.4), pos = V(1.6, 2.8, 2.4), color = C(220, 50, 50) })
	for _, z in ipairs({ -1.5, 1.2 }) do
		b:part({ size = V(0.3, 2.3, 2.3), pos = V(0, 2.8, z), rot = V(0, 90, 0), shape = "Cylinder", color = C(150, 150, 150), material = M.Fabric })
	end
	b:part({ size = V(0.2, 0.9, 0.9), pos = V(-1.1, 2.9, -1.3), shape = "Cylinder", color = C(120, 200, 255), transparency = 0.2 })
	local flame = b:pivot("Flame", V(0, 2.8, 3.0))
	b:part({ size = V(1.4, 1.4, 1.6), pos = V(0, 2.8, 3.8), color = C(255, 120, 30), neon = true, attach = flame })
	b:part({ size = V(0.8, 0.8, 1.2), pos = V(0, 2.8, 4.4), color = C(255, 230, 80), neon = true, attach = flame })
	b:seat(V(0, 3.9, 0.3))
	return b:finish("Flyer")
end

Designs.FlyingCouch = function(b)
	local purple = C(130, 60, 180)
	b:mainBody({ size = V(5, 1, 2.6), pos = V(0, 2.5, 0), color = purple, material = M.Fabric })
	b:part({ size = V(2.3, 0.5, 2.2), pos = V(-1.2, 3.25, -0.1), color = C(160, 90, 210), material = M.Fabric })
	b:part({ size = V(2.3, 0.5, 2.2), pos = V(1.2, 3.25, -0.1), color = C(160, 90, 210), material = M.Fabric })
	b:part({ size = V(5, 2, 0.7), pos = V(0, 3.9, 1.1), color = purple, material = M.Fabric })
	b:part({ size = V(0.7, 1.6, 2.6), pos = V(-2.8, 3.1, 0), color = purple, material = M.Fabric })
	b:part({ size = V(0.7, 1.6, 2.6), pos = V(2.8, 3.1, 0), color = purple, material = M.Fabric })
	for _, p in ipairs({ V(-1.8, 1.4, 0), V(0, 1.2, 0.3), V(1.8, 1.4, -0.2), V(-0.9, 1.5, -0.8), V(1, 1.5, 0.9) }) do
		b:part({ size = V(2, 2, 2), pos = p, shape = "Ball", color = C(250, 250, 255), material = M.SmoothPlastic, transparency = 0.1 })
	end
	b:seat(V(0, 3.5, -0.1))
	return b:finish("Flyer")
end

---------------------------------------------------------------------------
-- Târâtoare
---------------------------------------------------------------------------
Designs.Crocodile = function(b)
	local green, dark = C(60, 125, 50), C(40, 85, 35)
	b:mainBody({ size = V(2.6, 1.4, 6.5), pos = V(0, 1.5, 0), color = green, material = M.Slate })
	b:part({ size = V(0.6, 0.4, 6), pos = V(0, 2.35, 0), color = dark })
	for name, p in pairs({ LegFL = V(-1.5, 1.2, -2), LegFR = V(1.5, 1.2, -2), LegBL = V(-1.5, 1.2, 2), LegBR = V(1.5, 1.2, 2) }) do
		b:leg(name, p, V(0.8, 1.2, 0.8), green)
	end
	local head = b:pivot("Head", V(0, 1.6, -3.25))
	b:part({ size = V(2.2, 0.7, 3), pos = V(0, 1.9, -4.7), color = green, material = M.Slate, attach = head })
	b:part({ size = V(1.8, 0.25, 0.15), pos = V(0, 1.5, -6.12), color = C(255, 255, 255), attach = head })
	for _, side in ipairs({ -1, 1 }) do
		b:part({ size = V(0.6, 0.6, 0.6), pos = V(side * 0.6, 2.45, -3.6), shape = "Ball", color = C(240, 220, 60), attach = head })
		b:part({ size = V(0.15, 0.4, 0.1), pos = V(side * 0.6, 2.45, -3.92), color = C(10, 10, 10), attach = head })
	end
	local jaw = b:pivot("Jaw", V(0, 1.4, -3.3), head)
	b:part({ size = V(2, 0.5, 2.8), pos = V(0, 1.15, -4.65), color = C(80, 140, 65), attach = jaw })
	local tail = b:pivot("Tail", V(0, 1.5, 3.25))
	b:part({ size = V(1.6, 0.9, 3), pos = V(0, 1.4, 4.7), color = green, material = M.Slate, attach = tail })
	b:part({ size = V(0.8, 0.5, 2), pos = V(0, 1.3, 7.1), color = green, attach = tail })
	b:part({ size = V(2.7, 0.3, 2), pos = V(0, 2.5, 0.2), color = C(120, 75, 40), material = M.Leather })
	b:seat(V(0, 2.65, 0.2))
	return b:finish("Crawler")
end

Designs.Snail = function(b)
	local slime = C(150, 205, 95)
	b:mainBody({ size = V(2.2, 1, 6), pos = V(0, 0.6, 0), color = slime })
	local head = b:pivot("Head", V(0, 1.2, -2.8))
	b:part({ size = V(1.6, 1.6, 1.4), pos = V(0, 1.4, -2.9), color = slime, attach = head })
	for _, side in ipairs({ -1, 1 }) do
		b:part({ size = V(0.2, 1.6, 0.2), pos = V(side * 0.5, 2.9, -2.9), color = slime, attach = head })
		b:part({ size = V(0.55, 0.55, 0.55), pos = V(side * 0.5, 3.8, -2.9), shape = "Ball", color = C(255, 255, 255), attach = head })
		b:part({ size = V(0.25, 0.25, 0.25), pos = V(side * 0.5, 3.8, -3.15), shape = "Ball", color = C(15, 15, 15), attach = head })
	end
	b:part({ size = V(3.6, 3.6, 3.6), pos = V(0, 2.6, 0.6), shape = "Ball", color = C(175, 100, 50) })
	b:part({ size = V(2.4, 2.4, 2.4), pos = V(-0.8, 2.6, 0.6), shape = "Ball", color = C(215, 150, 80) })
	b:part({ size = V(2.4, 2.4, 2.4), pos = V(0.8, 2.6, 0.6), shape = "Ball", color = C(215, 150, 80) })
	local flame = b:pivot("Flame", V(0, 3.0, 3.5))
	for _, x in ipairs({ -1.2, 1.2 }) do
		b:part({ size = V(2.2, 0.6, 0.6), pos = V(x, 3.0, 2.4), rot = V(0, 90, 0), shape = "Cylinder", color = C(40, 120, 255), neon = true })
		b:part({ size = V(0.5, 0.5, 0.8), pos = V(x, 3.0, 3.8), color = C(120, 220, 255), neon = true, attach = flame })
	end
	b:seat(V(0, 4.35, 0.6))
	return b:finish("Crawler")
end

---------------------------------------------------------------------------
-- Săritoare
---------------------------------------------------------------------------
Designs.RubberDuck = function(b)
	local yellow, orange = C(255, 220, 40), C(255, 140, 20)
	b:mainBody({ size = V(4.4, 4.4, 4.4), pos = V(0, 2.4, 0.3), shape = "Ball", color = yellow })
	b:part({ size = V(1.6, 1, 1.4), pos = V(0, 3.4, 2.6), rot = V(0, 180, 0), shape = "Wedge", color = yellow })
	local head = b:pivot("Head", V(0, 3.8, -1.6))
	b:part({ size = V(2.8, 2.8, 2.8), pos = V(0, 5.0, -2.0), shape = "Ball", color = yellow, attach = head })
	b:part({ size = V(1.4, 0.6, 1.2), pos = V(0, 4.7, -3.45), color = orange, attach = head })
	b:part({ size = V(0.45, 0.45, 0.45), pos = V(-0.7, 5.5, -3.15), shape = "Ball", color = C(15, 15, 15), attach = head })
	b:part({ size = V(0.45, 0.45, 0.45), pos = V(0.7, 5.5, -3.15), shape = "Ball", color = C(15, 15, 15), attach = head })
	local wingL = b:pivot("WingL", V(-2.05, 3.2, 0.4))
	b:part({ size = V(0.5, 1.4, 2.2), pos = V(-2.2, 2.6, 0.4), color = yellow, attach = wingL })
	local wingR = b:pivot("WingR", V(2.05, 3.2, 0.4))
	b:part({ size = V(0.5, 1.4, 2.2), pos = V(2.2, 2.6, 0.4), color = yellow, attach = wingR })
	b:seat(V(0, 4.45, 0.9))
	return b:finish("Bouncer")
end

return Designs
