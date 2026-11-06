--[[
	TrackMath  (ModuleScript)
	Locație: ReplicatedStorage > Shared > TrackMath

	Geometria traseului: o curbă netedă (Catmull-Rom) prin punctele de control,
	eșantionată și parametrizată după DISTANȚĂ. Totul în joc se raportează la
	„distanța parcursă pe traseu”:
	  * poziția concurentului    = CFrameAt(distanță, bandă laterală)
	  * clasamentul              = sortare după distanță
	  * finish                   = distanță >= FinishDistance
	Partajat (ReplicatedStorage) ca să-l poată folosi și clientul (cameră, minimap).

	Convenții: fața spre direcția de mers (LookVector = tangenta), lateral
	pozitiv = spre dreapta concurentului.
]]

local TrackMath = {}
TrackMath.__index = TrackMath

local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

-- Eșantionează curba deschisă prin `points` (capetele sunt duplicate).
function TrackMath.sampleSpline(points, samplesPerSegment)
	assert(#points >= 2, "Traseul are nevoie de cel puțin 2 puncte")
	local n = samplesPerSegment or 24
	local padded = { points[1] }
	for _, p in ipairs(points) do
		table.insert(padded, p)
	end
	table.insert(padded, points[#points])
	local out = {}
	for i = 2, #padded - 2 do
		for k = 0, n - 1 do
			table.insert(out, catmull(padded[i - 1], padded[i], padded[i + 1], padded[i + 2], k / n))
		end
	end
	table.insert(out, points[#points])
	return out
end

function TrackMath.polylineLength(samples)
	local total = 0
	for i = 1, #samples - 1 do
		total += (samples[i + 1] - samples[i]).Magnitude
	end
	return total
end

--[[
	opts = {
	  samplesPerSegment = 24,
	  targetLength = number?,  -- scalează traseul pe orizontală ca să aibă ~această lungime
	  offset = Vector3?,       -- mută tot traseul
	}
]]
function TrackMath.new(points, opts)
	opts = opts or {}
	local n = opts.samplesPerSegment or 24

	if opts.targetLength then
		local rawLength = TrackMath.polylineLength(TrackMath.sampleSpline(points, n))
		local k = opts.targetLength / rawLength
		local origin = points[1]
		local scaled = {}
		for i, p in ipairs(points) do
			scaled[i] = Vector3.new(origin.X + (p.X - origin.X) * k, p.Y, origin.Z + (p.Z - origin.Z) * k)
		end
		points = scaled
	end
	if opts.offset then
		local moved = {}
		for i, p in ipairs(points) do
			moved[i] = p + opts.offset
		end
		points = moved
	end

	local self = setmetatable({}, TrackMath)
	self.controlPoints = points
	self.samples = TrackMath.sampleSpline(points, n)
	-- elimină eșantioanele duplicate (lungime zero) ca să nu avem tangente nedefinite
	local clean = { self.samples[1] }
	for i = 2, #self.samples do
		if (self.samples[i] - clean[#clean]).Magnitude > 1e-3 then
			table.insert(clean, self.samples[i])
		end
	end
	self.samples = clean

	self.cumulative = { 0 }
	for i = 2, #self.samples do
		self.cumulative[i] = self.cumulative[i - 1] + (self.samples[i] - self.samples[i - 1]).Magnitude
	end
	self.length = self.cumulative[#self.cumulative]

	-- tangentă netezită pentru fiecare eșantion (diferență centrală)
	self.tangents = {}
	local count = #self.samples
	for i = 1, count do
		local a = self.samples[math.max(1, i - 1)]
		local b = self.samples[math.min(count, i + 1)]
		self.tangents[i] = (b - a).Unit
	end
	return self
end

-- index i și fracția alpha astfel încât distanța d este între eșantionul i și i+1
function TrackMath:_locate(d)
	d = math.clamp(d, 0, self.length)
	local lo, hi = 1, #self.cumulative
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if self.cumulative[mid] <= d then
			lo = mid
		else
			hi = mid
		end
	end
	local span = self.cumulative[hi] - self.cumulative[lo]
	local alpha = span > 0 and (d - self.cumulative[lo]) / span or 0
	return lo, hi, alpha
end

function TrackMath:PositionAt(d)
	local lo, hi, alpha = self:_locate(d)
	return self.samples[lo]:Lerp(self.samples[hi], alpha)
end

function TrackMath:TangentAt(d)
	local lo, hi, alpha = self:_locate(d)
	local t = self.tangents[lo]:Lerp(self.tangents[hi], alpha)
	if t.Magnitude < 1e-6 then
		return self.tangents[lo]
	end
	return t.Unit
end

-- Baza locală (dreapta, sus) pentru o tangentă; sus rămâne cât mai aproape de vertical.
function TrackMath.basis(tangent)
	local right = tangent:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(tangent).Unit
	return right, up
end

--[[
	CFrame pe traseu la distanța d, deplasat lateral (dreapta +) și în sus.
	Fața (LookVector) este spre direcția de mers.
]]
function TrackMath:CFrameAt(d, lateral, height)
	local pos = self:PositionAt(d)
	local tangent = self:TangentAt(d)
	local right, up = TrackMath.basis(tangent)
	local p = pos + right * (lateral or 0) + up * (height or 0)
	return CFrame.fromMatrix(p, right, up, -tangent)
end

--[[
	Cea mai mică distanță ORIZONTALĂ de la `pos` la axa traseului și distanța
	pe traseu a celui mai apropiat punct. Folosit ca decorurile să nu intre pe pistă.
]]
function TrackMath:ClosestXZ(pos)
	local best, bestAlong = math.huge, 0
	local px, pz = pos.X, pos.Z
	for i = 1, #self.samples - 1 do
		local a, b = self.samples[i], self.samples[i + 1]
		local abx, abz = b.X - a.X, b.Z - a.Z
		local lenSq = abx * abx + abz * abz
		local t = 0
		if lenSq > 0 then
			t = math.clamp(((px - a.X) * abx + (pz - a.Z) * abz) / lenSq, 0, 1)
		end
		local cx, cz = a.X + abx * t, a.Z + abz * t
		local dx, dz = px - cx, pz - cz
		local dist = math.sqrt(dx * dx + dz * dz)
		if dist < best then
			best = dist
			bestAlong = self.cumulative[i] + (self.cumulative[i + 1] - self.cumulative[i]) * t
		end
	end
	return best, bestAlong
end

-- Limitele traseului (pentru teren / cameră)
function TrackMath:Bounds()
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, p in ipairs(self.samples) do
		minV = minV:Min(p)
		maxV = maxV:Max(p)
	end
	return minV, maxV
end

return TrackMath
