--[[
	MapBuilder  (ModuleScript)
	Locație: ServerScriptService > Server > Services > Maps > MapBuilder

	Construiește procedural o hartă completă dintr-un traseu (TrackMath) și o temă:
	  * pista continuă, lată (Config.Maps.TrackWidth), fără găuri în viraje
	  * borduri colorate și linie centrală PICTATE pe asfalt (nu sunt bariere)
	  * terasament sub porțiunile ridicate, teren tematic
	  * linie de START și de FINISH (tablă de șah + arcadă cu stâlpii ÎN AFARA pistei)
	  * decoruri doar în afara pistei: fiecare poziție e verificată față de
	    TOATĂ axa traseului (ClosestXZ), deci nimic nu ajunge pe circuit
	Totul e ancorat și fără coliziuni: concurenții sunt mutați de server pe traseu.
]]

local MapBuilder = {}

local YIELD_EVERY = 400 -- face o pauză scurtă la fiecare N piese (serverul nu îngheață)

local function newCtx(model, theme, track, width, seed)
	local ctx = {
		model = model,
		theme = theme,
		track = track,
		width = width,
		rng = Random.new(seed),
		count = 0,
		folder = nil,
	}
	local minV, maxV = track:Bounds()
	ctx.minBounds, ctx.maxBounds = minV, maxV
	ctx.center = (minV + maxV) / 2
	ctx.groundY = minV.Y - 0.3

	function ctx:Folder(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = self.model
		self.folder = f
		return f
	end

	function ctx:Part(spec)
		local part
		if spec.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			if spec.shape == "Ball" then
				part.Shape = Enum.PartType.Ball
			elseif spec.shape == "Cylinder" then
				part.Shape = Enum.PartType.Cylinder
			end
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = spec.size
		part.CFrame = spec.cf
		part.Color = spec.color or Color3.new(1, 1, 1)
		part.Material = spec.neon and Enum.Material.Neon or (spec.material or Enum.Material.SmoothPlastic)
		part.Transparency = spec.transparency or 0
		part.CastShadow = spec.castShadow ~= false
		part.Parent = spec.parent or self.folder or self.model
		self.count += 1
		if self.count % YIELD_EVERY == 0 then
			task.wait()
		end
		return part
	end

	function ctx:Label(part, face, text, color)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color or Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Parent = gui
		gui.Parent = part
		return gui
	end

	-- Caută un punct pe teren aflat la cel puțin `clearance` studs de axa pistei
	function ctx:FindSpot(clearance)
		local margin = 350
		for _ = 1, 60 do
			local x = self.rng:NextNumber(self.minBounds.X - margin, self.maxBounds.X + margin)
			local z = self.rng:NextNumber(self.minBounds.Z - margin, self.maxBounds.Z + margin)
			local pos = Vector3.new(x, self.groundY, z)
			local distance, along = self.track:ClosestXZ(pos)
			if distance >= self.width / 2 + clearance then
				if self.theme.FloatingDecor then
					pos = Vector3.new(x, self.track:PositionAt(along).Y, z)
				end
				return pos
			end
		end
		return nil
	end

	return ctx
end

---------------------------------------------------------------------------
-- Pista
---------------------------------------------------------------------------
local ROAD_THICKNESS = 1.6
local SEGMENT = 6

-- piesă dreaptă exact între două puncte (pentru borduri / linii)
local function stripBetween(ctx, a, b, width, height, color, neon, upVector)
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	if length < 0.05 then
		return
	end
	ctx:Part({
		size = Vector3.new(width, height, length + 0.05),
		cf = CFrame.lookAt(mid, b, upVector or Vector3.yAxis),
		color = color,
		neon = neon,
		castShadow = false,
	})
end

local function buildRoad(ctx)
	local track, theme, width = ctx.track, ctx.theme, ctx.width
	ctx:Folder("Track")
	local half = width / 2
	local curbWidth = 2.4
	local index = 0
	local d = 0
	while d < track.length do
		local d1 = math.min(d + SEGMENT, track.length)
		local cf0, cf1 = track:CFrameAt(d, 0), track:CFrameAt(d1, 0)
		local l0, r0 = track:CFrameAt(d, -half).Position, track:CFrameAt(d, half).Position
		local l1, r1 = track:CFrameAt(d1, -half).Position, track:CFrameAt(d1, half).Position
		-- lungimea acoperă și marginea exterioară a virajului (fără găuri)
		local length = math.max((l1 - l0).Magnitude, (r1 - r0).Magnitude, (cf1.Position - cf0.Position).Magnitude) + 0.4
		local midCf = track:CFrameAt((d + d1) / 2, 0)
		local upVector = midCf.UpVector
		ctx:Part({
			size = Vector3.new(width, ROAD_THICKNESS, length),
			cf = midCf * CFrame.new(0, -ROAD_THICKNESS / 2, 0),
			color = theme.Road,
			material = theme.RoadMaterial,
			castShadow = false,
		})

		-- borduri pictate (alternând culorile), exact pe arcul lor
		local curbColor = index % 2 == 0 and theme.CurbA or theme.CurbB
		for _, side in ipairs({ -1, 1 }) do
			local lateral = side * (half - curbWidth / 2)
			local a = track:CFrameAt(d, lateral) * CFrame.new(0, 0.03, 0)
			local b = track:CFrameAt(d1, lateral) * CFrame.new(0, 0.03, 0)
			stripBetween(ctx, a.Position, b.Position, curbWidth, 0.1, curbColor, theme.NeonCurbs, upVector)
		end
		-- linie centrală întreruptă
		if index % 2 == 0 then
			local a = (track:CFrameAt(d, 0) * CFrame.new(0, 0.03, 0)).Position
			local b = (track:CFrameAt(d + SEGMENT * 0.6, 0) * CFrame.new(0, 0.03, 0)).Position
			stripBetween(ctx, a, b, 0.9, 0.1, theme.CenterLine, false, upVector)
		end

		-- sub pistă: terasament până la teren, sau lumină (spațiu)
		local roadBottom = midCf.Position.Y - ROAD_THICKNESS
		if theme.Ground and theme.Embankment and roadBottom > ctx.groundY + 0.5 then
			local h = roadBottom - ctx.groundY + 0.2
			local base = Vector3.new(midCf.Position.X, ctx.groundY + h / 2, midCf.Position.Z)
			local flatLook = Vector3.new(midCf.LookVector.X, 0, midCf.LookVector.Z)
			if flatLook.Magnitude > 1e-3 then
				ctx:Part({
					size = Vector3.new(width + 10, h, length),
					cf = CFrame.lookAt(base, base + flatLook),
					color = theme.Embankment.Color,
					material = theme.Embankment.Material,
				})
			end
		elseif theme.Underglow then
			ctx:Part({
				size = Vector3.new(width * 0.6, 0.4, length),
				cf = midCf * CFrame.new(0, -ROAD_THICKNESS - 0.3, 0),
				color = theme.Underglow,
				neon = true,
				castShadow = false,
			})
		end

		index += 1
		d = d1
	end
end

---------------------------------------------------------------------------
-- Start / Finish
---------------------------------------------------------------------------
local function buildLine(ctx, distance, text, bannerColor)
	local track, width = ctx.track, ctx.width
	local folder = ctx:Folder(text)
	local cell = 3.5
	local cols = math.floor(width / cell)
	local startLateral = -cols * cell / 2 + cell / 2
	for row = 0, 1 do
		for col = 0, cols - 1 do
			local cf = track:CFrameAt(distance + (row - 0.5) * cell, startLateral + col * cell) * CFrame.new(0, 0.06, 0)
			ctx:Part({
				size = Vector3.new(cell, 0.12, cell),
				cf = cf,
				color = (row + col) % 2 == 0 and Color3.new(1, 1, 1) or Color3.fromRGB(20, 20, 20),
				castShadow = false,
			})
		end
	end
	-- arcadă: stâlpii sunt în afara pistei, bara e la 26 studs deasupra
	local height = 26
	local lineCf = track:CFrameAt(distance, 0)
	for _, side in ipairs({ -1, 1 }) do
		local base = track:CFrameAt(distance, side * (width / 2 + 6))
		local groundY = ctx.theme.Ground and ctx.groundY or base.Position.Y - 4
		local bottom = math.min(groundY, base.Position.Y)
		local top = base.Position.Y + height
		local pillarHeight = top - bottom
		ctx:Part({
			size = Vector3.new(3, pillarHeight, 3),
			cf = CFrame.new(base.Position.X, bottom + pillarHeight / 2, base.Position.Z) * lineCf.Rotation,
			color = bannerColor,
			material = Enum.Material.Metal,
		})
	end
	local bar = ctx:Part({ size = Vector3.new(width + 15, 2.5, 2.5), cf = lineCf * CFrame.new(0, height, 0), color = Color3.fromRGB(30, 30, 30), material = Enum.Material.Metal })
	local banner = ctx:Part({ size = Vector3.new(width * 0.55, 8, 1), cf = lineCf * CFrame.new(0, height - 5.5, 0), color = bannerColor })
	ctx:Label(banner, Enum.NormalId.Back, text, Color3.new(1, 1, 1)) -- spre concurenții care vin
	ctx:Label(banner, Enum.NormalId.Front, text, Color3.new(1, 1, 1))
	folder:SetAttribute("Distance", distance)
	return bar
end

---------------------------------------------------------------------------
-- Teren și decor
---------------------------------------------------------------------------
local function buildGround(ctx)
	local ground = ctx.theme.Ground
	if not ground then
		return
	end
	ctx:Folder("Ground")
	local minV, maxV = ctx.minBounds, ctx.maxBounds
	local margin = 900
	-- piesele au maxim 2048 studs pe latură -> plăci
	local tile = 2000
	local x0, x1 = minV.X - margin, maxV.X + margin
	local z0, z1 = minV.Z - margin, maxV.Z + margin
	local x = x0
	while x < x1 do
		local z = z0
		local w = math.min(tile, x1 - x)
		while z < z1 do
			local dz = math.min(tile, z1 - z)
			ctx:Part({
				size = Vector3.new(w, 4, dz),
				cf = CFrame.new(x + w / 2, ctx.groundY - 2, z + dz / 2),
				color = ground.Color,
				material = ground.Material,
				castShadow = false,
			})
			z += dz
		end
		x += w
	end
end

local function buildDecor(ctx, density)
	local theme = ctx.theme
	if not theme.Decor then
		return
	end
	ctx:Folder("Decor")
	local spacing = (theme.DecorSpacing or 25) / math.max(density, 0.1)
	local minClear = ctx.width / 2 + 8
	local d = ctx.rng:NextNumber(0, spacing)
	while d < ctx.track.length do
		for _, side in ipairs({ -1, 1 }) do
			local lateral = side * (ctx.width / 2 + ctx.rng:NextNumber(12, 70))
			local cf = ctx.track:CFrameAt(d, lateral)
			local pos = cf.Position
			local distance = ctx.track:ClosestXZ(pos)
			if distance >= minClear then -- nu intră niciodată pe pistă (nici în alte porțiuni ale traseului)
				local y = theme.FloatingDecor and pos.Y or ctx.groundY
				local base = CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, ctx.rng:NextNumber(0, math.pi * 2), 0)
				local ok, err = pcall(theme.Decor, ctx, base)
				if not ok then
					warn("[MapBuilder] decor:", err)
				end
			end
		end
		d += spacing * ctx.rng:NextNumber(0.7, 1.3)
	end
	if theme.Landmarks then
		ctx:Folder("Landmarks")
		local ok, err = pcall(theme.Landmarks, ctx)
		if not ok then
			warn("[MapBuilder] landmarks:", err)
		end
	end
end

--[[
	opts = { id, displayName, track (TrackMath), theme, width, startDistance,
	         finishDistance, decorDensity, seed }
	Returnează Model-ul hărții (neparentat) și numărul de piese.
]]
function MapBuilder.Build(opts)
	local model = Instance.new("Model")
	model.Name = opts.id
	model:SetAttribute("DisplayName", opts.displayName)
	local ctx = newCtx(model, opts.theme, opts.track, opts.width, opts.seed or os.time())
	buildGround(ctx)
	buildRoad(ctx)
	buildLine(ctx, opts.startDistance, "START", Color3.fromRGB(40, 200, 90))
	buildLine(ctx, opts.finishDistance, "FINISH", Color3.fromRGB(230, 50, 60))
	buildDecor(ctx, opts.decorDensity or 1)
	return model, ctx.count
end

return MapBuilder
