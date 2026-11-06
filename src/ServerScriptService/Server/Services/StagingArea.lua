--[[
	StagingArea  (ModuleScript)
	Locație: ServerScriptService > Server > Services > StagingArea

	Zona de pregătire (lobby) unde concurenții apar și primesc mount-ul de la
	roata norocului. În Etapa 4 hărțile vor avea propria linie de start; lobby-ul
	rămâne locul unde se face prezentarea și roata.
]]

local StagingArea = {}
StagingArea.__index = StagingArea

local ORIGIN = Vector3.new(0, 0, -2600) -- departe de hărți (traseele ocupă ~[-700,1100] x [-700,600])
local PER_ROW = 6
local SPACING_X = 11
local SPACING_Z = 15

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

function StagingArea.new()
	local self = setmetatable({}, StagingArea)
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Lobby"
	local base = part(model, {
		Name = "Floor",
		Size = Vector3.new(90, 1, 90),
		CFrame = CFrame.new(ORIGIN + Vector3.new(0, -0.5, 0)),
		Color = Color3.fromRGB(70, 60, 120),
		Material = Enum.Material.SmoothPlastic,
	})
	model.PrimaryPart = base
	-- dale colorate (aspect de scenă de concurs)
	local colors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 200, 60), Color3.fromRGB(80, 200, 255), Color3.fromRGB(120, 230, 120) }
	for row = 0, 2 do
		for col = 0, PER_ROW - 1 do
			local slot = self:_slotPosition(row * PER_ROW + col + 1)
			part(model, {
				Name = "Pad",
				Size = Vector3.new(8, 0.2, 10),
				CFrame = CFrame.new(slot + Vector3.new(0, 0.05, 0)),
				Color = colors[(row + col) % #colors + 1],
				Material = Enum.Material.Neon,
				Transparency = 0.35,
				CanCollide = false,
			})
		end
	end
	-- arcadă decorativă în spate
	part(model, { Name = "Arch", Size = Vector3.new(80, 3, 2), CFrame = CFrame.new(ORIGIN + Vector3.new(0, 22, 40)), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Neon })
	part(model, { Name = "PillarL", Size = Vector3.new(3, 22, 3), CFrame = CFrame.new(ORIGIN + Vector3.new(-40, 11, 40)), Color = Color3.fromRGB(255, 90, 120) })
	part(model, { Name = "PillarR", Size = Vector3.new(3, 22, 3), CFrame = CFrame.new(ORIGIN + Vector3.new(40, 11, 40)), Color = Color3.fromRGB(255, 90, 120) })
	model.Parent = workspace
	self.model = model
	self.origin = ORIGIN
	return self
end

function StagingArea:_slotPosition(index)
	local row = math.floor((index - 1) / PER_ROW)
	local col = (index - 1) % PER_ROW
	local x = (col - (PER_ROW - 1) / 2) * SPACING_X
	local z = row * SPACING_Z - SPACING_Z
	return ORIGIN + Vector3.new(x, 0, z)
end

-- CFrame-ul slotului `index` (la nivelul solului; fața spre camera, adică spre -Z)
function StagingArea:GetSlot(index)
	return CFrame.new(self:_slotPosition(index))
end

-- punct spre care să privească o cameră
function StagingArea:GetFocus()
	return ORIGIN + Vector3.new(0, 3, 0)
end

return StagingArea
