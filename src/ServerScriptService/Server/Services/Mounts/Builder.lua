--[[
	Builder  (ModuleScript)
	Locație: ServerScriptService > Server > Services > Mounts > Builder

	Mini-API pentru construirea mount-urilor din Part-uri (modele originale,
	fără asset-uri externe). Convenții pentru fiecare mount:

	  Model (Name = Id, atribut MountStyle)
	  ├─ Root   : Part invizibil, ANCORAT, la nivelul solului. Se mută doar el.
	  ├─ Body   : piesa principală, legată de Root prin Motor6D "Anim_Body"
	  │   └─ Seat (Attachment): unde stă avatarul (fața spre -Z = înainte)
	  └─ pivoturi animate: Motor6D "Anim_<Nume>" (LegFL, Wheel1, Prop, Tail...)

	Toate piesele sunt neancorate, sudate în lanț până la Root: mutând Root,
	se mută tot. Animațiile se fac pe client prin Motor6D.Transform (nu se
	replică, deci nu încarcă rețeaua).
]]

local Builder = {}
Builder.__index = Builder

local function configurePart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	return part
end

local SHAPES = {
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

function Builder.new(id)
	local self = setmetatable({}, Builder)
	self.model = Instance.new("Model")
	self.model.Name = id
	local root = configurePart(Instance.new("Part"))
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CFrame = CFrame.new()
	root.Parent = self.model
	self.model.PrimaryPart = root
	self.root = root
	self.body = nil
	self._count = 0
	return self
end

local function toCFrame(pos, rot)
	rot = rot or Vector3.zero
	return CFrame.new(pos) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

--[[
	spec = {
	  name?, size: Vector3, pos: Vector3 (față de sol, centrul mount-ului),
	  rot?: Vector3 (grade), color: Color3, material?: Enum.Material,
	  shape?: "Ball"|"Cylinder"|"Wedge"|"CornerWedge",
	  attach?: Part (implicit Body), transparency?, neon?: boolean
	}
]]
function Builder:part(spec)
	local part
	if spec.shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif spec.shape == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		part = Instance.new("Part")
		if spec.shape then
			part.Shape = SHAPES[spec.shape]
		end
	end
	configurePart(part)
	self._count += 1
	part.Name = spec.name or ("Part" .. self._count)
	part.Size = spec.size
	part.CFrame = toCFrame(spec.pos, spec.rot)
	part.Color = spec.color or Color3.new(1, 1, 1)
	if spec.neon then
		part.Material = Enum.Material.Neon
	elseif spec.material then
		part.Material = spec.material
	end
	part.Transparency = spec.transparency or 0
	part.Parent = self.model

	local attach = spec.attach or self.body
	if attach then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = attach
		weld.Part1 = part
		weld.Parent = part
	end
	return part
end

-- Piesa principală: legată de Root printr-un Motor6D animabil ("Anim_Body")
function Builder:mainBody(spec)
	assert(self.body == nil, "Body există deja")
	spec.name = "Body"
	local savedBody = self.body
	self.body = nil
	local part = self:part(spec)
	self.body = savedBody
	local motor = Instance.new("Motor6D")
	motor.Name = "Anim_Body"
	motor.Part0 = self.root
	motor.Part1 = part
	motor.C0 = self.root.CFrame:ToObjectSpace(part.CFrame)
	motor.C1 = CFrame.new()
	motor.Parent = part
	self.body = part
	return part
end

-- Pivot animat: un punct de articulație (invizibil) legat prin Motor6D "Anim_<name>"
function Builder:pivot(name, pos, attach, rot)
	attach = attach or self.body
	local pivot = configurePart(Instance.new("Part"))
	pivot.Name = "Pivot_" .. name
	pivot.Size = Vector3.new(0.2, 0.2, 0.2)
	pivot.Transparency = 1
	pivot.CFrame = toCFrame(pos, rot)
	pivot.Parent = self.model
	local motor = Instance.new("Motor6D")
	motor.Name = "Anim_" .. name
	motor.Part0 = attach
	motor.Part1 = pivot
	motor.C0 = attach.CFrame:ToObjectSpace(pivot.CFrame)
	motor.C1 = CFrame.new()
	motor.Parent = pivot
	return pivot
end

-- Roată: pivot "Anim_<name>" + cilindru (axa pe X). Raza e salvată pentru animație.
function Builder:wheel(name, pos, radius, width, color, hubColor)
	local pivot = self:pivot(name, pos)
	pivot:SetAttribute("Radius", radius)
	self:part({ size = Vector3.new(width, radius * 2, radius * 2), pos = pos, shape = "Cylinder", color = color or Color3.fromRGB(30, 30, 30), attach = pivot })
	self:part({ size = Vector3.new(width + 0.1, radius * 0.9, radius * 0.9), pos = pos, shape = "Cylinder", color = hubColor or Color3.fromRGB(200, 200, 200), attach = pivot })
	-- o spiță, ca rotirea să fie vizibilă
	self:part({ size = Vector3.new(width + 0.15, radius * 1.6, 0.2), pos = pos, color = hubColor or Color3.fromRGB(200, 200, 200), attach = pivot })
	return pivot
end

-- Picior: pivot la șold + bloc până la sol (+ copită opțională)
function Builder:leg(name, hipPos, size, color, hoofColor)
	local pivot = self:pivot(name, hipPos)
	self:part({ size = size, pos = hipPos - Vector3.new(0, size.Y / 2, 0), color = color, attach = pivot })
	if hoofColor then
		self:part({ size = Vector3.new(size.X + 0.1, 0.35, size.Z + 0.1), pos = Vector3.new(hipPos.X, hipPos.Y - size.Y + 0.17, hipPos.Z), color = hoofColor, attach = pivot })
	end
	return pivot
end

-- Ochi desenați din blocuri (alb + pupilă)
function Builder:eyes(xOffset, y, z, attach, size)
	size = size or 0.55
	for _, side in ipairs({ -1, 1 }) do
		self:part({ size = Vector3.new(size, size, 0.12), pos = Vector3.new(side * xOffset, y, z), color = Color3.new(1, 1, 1), attach = attach })
		self:part({ size = Vector3.new(size * 0.5, size * 0.5, 0.14), pos = Vector3.new(side * xOffset, y - size * 0.1, z - 0.03), color = Color3.new(0.05, 0.05, 0.05), attach = attach })
	end
end

function Builder:seat(pos)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Seat"
	attachment.CFrame = self.body.CFrame:ToObjectSpace(CFrame.new(pos))
	attachment.Parent = self.body
	return attachment
end

function Builder:finish(style)
	assert(self.body, "Mount fără Body")
	assert(self.body:FindFirstChild("Seat"), "Mount fără Seat")
	self.model:SetAttribute("MountStyle", style)
	return self.model
end

return Builder
