--[[
	MountAnimator  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > MountAnimator

	Animează pe CLIENT toți concurenții (tag "Racer"):
	  * mount-ul: picioare, roți, elice, aripi, coadă, flăcări, săritură
	    (Motor6D "Anim_*" construite de MountFactory)
	  * avatarul: poză de călare / șezut, aplecare după viteză
	Folosește Motor6D.Transform, care NU se replică: zero trafic de rețea și
	fără asset-uri de animație externe. Viteza vine din atributul "Speed" al
	concurentului (setat de server).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MountAnimator = {}

local RACER_TAG = "Racer"
local rad, sin, abs, min = math.rad, math.sin, math.abs, math.min

local RIDER_JOINTS = {
	LeftHip = true, RightHip = true, LeftKnee = true, RightKnee = true,
	LeftShoulder = true, RightShoulder = true, LeftElbow = true, RightElbow = true,
	Waist = true, Neck = true,
}

-- Poze de bază pentru fiecare stil: { hipX, hipZ, kneeX, shoulderX, elbowX }
local POSES = {
	Wheeled = { hipX = rad(80), hipZ = rad(6), kneeX = -rad(30), shoulderX = rad(60), elbowX = rad(20) },
	Flyer = { hipX = rad(90), hipZ = rad(4), kneeX = -rad(90), shoulderX = rad(45), elbowX = rad(30) },
	Walker = { hipX = rad(45), hipZ = rad(32), kneeX = -rad(70), shoulderX = rad(55), elbowX = rad(30) },
	Crawler = { hipX = rad(50), hipZ = rad(35), kneeX = -rad(60), shoulderX = rad(50), elbowX = rad(25) },
	Bouncer = { hipX = rad(50), hipZ = rad(30), kneeX = -rad(75), shoulderX = rad(120), elbowX = rad(10) },
}

local states = {} -- model -> state

local function rebuild(model, state)
	state.motors = {}
	state.wheels = {}
	state.rider = {}
	state.style = model:GetAttribute("MountStyle")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			if d.Name:sub(1, 5) == "Anim_" then
				local key = d.Name:sub(6)
				if key:match("^Wheel") then
					local radius = d.Part1 and d.Part1:GetAttribute("Radius") or 1
					table.insert(state.wheels, { motor = d, radius = math.max(radius, 0.1), angle = 0 })
				else
					state.motors[key] = d
				end
			elseif RIDER_JOINTS[d.Name] and d.Parent and d.Parent.Parent and d.Parent.Parent:FindFirstChildOfClass("Humanoid") then
				state.rider[d.Name] = d
			end
		end
	end
	state.dirty = false
end

local function track(model)
	if states[model] then
		return
	end
	local state = { t = math.random() * 10, phase = math.random() * 6, prop = 0, dirty = true, connections = {} }
	table.insert(state.connections, model.DescendantAdded:Connect(function()
		state.dirty = true
	end))
	table.insert(state.connections, model.DescendantRemoving:Connect(function()
		state.dirty = true
	end))
	table.insert(state.connections, model:GetAttributeChangedSignal("MountStyle"):Connect(function()
		state.dirty = true
	end))
	states[model] = state
end

local function untrack(model)
	local state = states[model]
	if state then
		for _, c in ipairs(state.connections) do
			c:Disconnect()
		end
		states[model] = nil
	end
end

local function setMotor(state, key, cf)
	local motor = state.motors[key]
	if motor and motor.Parent then
		motor.Transform = cf
	end
end

-- Body poate fi rotit în model (ex. avionul): exprimăm mișcarea în spațiul mount-ului
local function setBody(state, rootSpaceCF)
	local motor = state.motors.Body
	if motor and motor.Parent then
		local rot = motor.C0.Rotation
		motor.Transform = rot:Inverse() * rootSpaceCF * rot
	end
end

local function legs(state, phase, amplitude)
	local s = sin(phase) * amplitude
	setMotor(state, "LegFL", CFrame.Angles(s, 0, 0))
	setMotor(state, "LegBR", CFrame.Angles(s, 0, 0))
	setMotor(state, "LegFR", CFrame.Angles(-s, 0, 0))
	setMotor(state, "LegBL", CFrame.Angles(-s, 0, 0))
end

local STYLE = {}

function STYLE.Walker(state, sf, t, phase)
	local m = min(sf, 1)
	legs(state, phase, rad(35) * m)
	setBody(state, CFrame.new(0, abs(sin(phase)) * 0.35 * m + sin(t * 2) * 0.05, 0))
	setMotor(state, "Head", CFrame.Angles(sin(phase * 2) * rad(5) * m + sin(t * 1.5) * rad(3), sin(t * 0.7) * rad(4), 0))
end

function STYLE.Wheeled(state, sf, t, _phase, dt, speed)
	local m = min(sf, 1)
	for _, wheel in ipairs(state.wheels) do
		wheel.angle = (wheel.angle - dt * speed / wheel.radius) % (math.pi * 2)
		if wheel.motor.Parent then
			wheel.motor.Transform = CFrame.Angles(wheel.angle, 0, 0)
		end
	end
	setBody(state, CFrame.new(0, sin(t * 40) * 0.03 * m, 0) * CFrame.Angles(0, 0, sin(t * 3) * rad(1.5) * m))
	setMotor(state, "Head", CFrame.Angles(0, sin(t * 0.8) * rad(5), 0))
end

function STYLE.Flyer(state, sf, t, _phase, dt)
	state.prop = (state.prop + dt * (15 + 25 * min(sf, 2))) % (math.pi * 2)
	setMotor(state, "Prop", CFrame.Angles(0, 0, state.prop))
	setBody(state, CFrame.new(0, 0.8 + sin(t * 2) * 0.4, 0) * CFrame.Angles(sin(t * 1.1) * rad(3), 0, sin(t * 1.3) * rad(6)))
end

function STYLE.Crawler(state, sf, t, phase)
	local m = min(sf, 1)
	legs(state, phase * 1.4, rad(25) * m)
	setBody(state, CFrame.Angles(0, sin(phase) * rad(6) * m, 0))
	setMotor(state, "Jaw", CFrame.Angles(-abs(sin(t * 2.5)) * rad(18), 0, 0))
	setMotor(state, "Head", CFrame.Angles(0, sin(phase) * rad(5) * m, 0))
end

function STYLE.Bouncer(state, sf, t, phase)
	local m = min(sf, 1)
	local hop = abs(sin(phase * 0.8)) * 1.4 * m + sin(t * 2) * 0.08
	setBody(state, CFrame.new(0, hop, 0) * CFrame.Angles(sin(phase * 0.8) * rad(6) * m, 0, 0))
	local flap = abs(sin(t * (6 + 6 * m))) * rad(35)
	setMotor(state, "WingL", CFrame.Angles(0, 0, -flap))
	setMotor(state, "WingR", CFrame.Angles(0, 0, flap))
	setMotor(state, "Head", CFrame.Angles(sin(t * 3) * rad(4), 0, 0))
end

local function common(state, sf, t, phase)
	setMotor(state, "Tail", CFrame.Angles(0, sin(t * (4 + 4 * min(sf, 2))) * rad(25), 0))
	setMotor(state, "Rod", CFrame.Angles(sin(phase) * rad(6) + sin(t * 2) * rad(2), 0, 0))
	if state.motors.Flame then
		setMotor(state, "Flame", CFrame.new(0, 0, (math.random() - 0.5) * 0.25) * CFrame.Angles(0, 0, (math.random() - 0.5) * 0.3))
	end
end

local function riderPose(state, sf, t)
	local pose = POSES[state.style]
	local r = state.rider
	if not pose or not r.LeftHip then
		return
	end
	local m = min(sf, 1.5)
	r.LeftHip.Transform = CFrame.Angles(pose.hipX, 0, -pose.hipZ)
	r.RightHip.Transform = CFrame.Angles(pose.hipX, 0, pose.hipZ)
	if r.LeftKnee then
		r.LeftKnee.Transform = CFrame.Angles(pose.kneeX, 0, 0)
	end
	if r.RightKnee then
		r.RightKnee.Transform = CFrame.Angles(pose.kneeX, 0, 0)
	end
	local armWave = sin(t * 2.2) * rad(4)
	if r.LeftShoulder then
		r.LeftShoulder.Transform = CFrame.Angles(pose.shoulderX + armWave, 0, -rad(8))
	end
	if r.RightShoulder then
		r.RightShoulder.Transform = CFrame.Angles(pose.shoulderX - armWave, 0, rad(8))
	end
	if r.LeftElbow then
		r.LeftElbow.Transform = CFrame.Angles(pose.elbowX, 0, 0)
	end
	if r.RightElbow then
		r.RightElbow.Transform = CFrame.Angles(pose.elbowX, 0, 0)
	end
	if r.Waist then
		r.Waist.Transform = CFrame.Angles(-rad(14) * m + sin(t * 1.7) * rad(1.5), 0, 0)
	end
	if r.Neck then
		r.Neck.Transform = CFrame.Angles(rad(8) * m, sin(t * 0.6) * rad(10), 0)
	end
end

local function step(dt)
	local base = Config.Race.BaseSpeed
	for model, state in pairs(states) do
		if model.Parent then
			if state.dirty then
				rebuild(model, state)
			end
			local speed = model:GetAttribute("Speed") or 0
			local sf = speed / base
			state.t += dt
			state.phase += dt * (2 + 6 * min(sf, 2))
			local styleFn = STYLE[state.style]
			if styleFn then
				styleFn(state, sf, state.t, state.phase, dt, speed)
			end
			common(state, sf, state.t, state.phase)
			riderPose(state, sf, state.t)
		end
	end
end

function MountAnimator.Start()
	for _, model in ipairs(CollectionService:GetTagged(RACER_TAG)) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(RACER_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(RACER_TAG):Connect(untrack)
	RunService.PreSimulation:Connect(step)
end

return MountAnimator
