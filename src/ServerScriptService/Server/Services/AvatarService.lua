--[[
	AvatarService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > AvatarService

	Construiește avatarul ORIGINAL al concurentului (după Roblox UserId, cu
	hainele, accesoriile, corpul și culorile din contul lui) și îl așază pe mount.

	Avatarul NU este înlocuit de mount: este sudat deasupra lui, pe Body > Seat.
	Poza de „călare” și animațiile se fac pe client (MountAnimator), prin
	Motor6D.Transform, fără asset-uri de animație externe.
]]

local AvatarService = {}
AvatarService.__index = AvatarService

local DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Dead,
	Enum.HumanoidStateType.Physics,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.GettingUp,
}

-- deps = { users = RobloxUserService }
function AvatarService.new(deps)
	local self = setmetatable({}, AvatarService)
	self._users = deps.users
	return self
end

local function createNameTag(avatar, robloxName, displayName)
	local head = avatar:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(220, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.ResetOnSpawn = false

	local name = Instance.new("TextLabel")
	name.Name = "Username"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.62)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0
	name.TextStrokeColor3 = Color3.fromRGB(20, 20, 40)
	name.Text = robloxName
	name.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Name = "Display"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.62)
	sub.Size = UDim2.fromScale(1, 0.38)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 225, 120)
	sub.TextStrokeTransparency = 0.3
	sub.Text = (displayName and displayName ~= robloxName) and displayName or ""
	sub.Parent = gui

	gui.Parent = head
end

local function prepareModel(avatar)
	for _, d in ipairs(avatar:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.Anchored = false
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy() -- scripturile implicite (Animate, Health) nu sunt necesare
		end
	end
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		for _, state in ipairs(DISABLED_STATES) do
			humanoid:SetStateEnabled(state, false)
		end
		humanoid.PlatformStand = true
		humanoid.EvaluateStateMachine = false -- avatarul nu mai „gândește” fizic
	end
	local hrp = avatar:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Transparency = 1
		hrp.Anchored = true
		avatar.PrimaryPart = hrp
	end
end

--[[
	entry = intrarea din QueueService (robloxUserId, robloxName, displayName)
	Returnează Model-ul avatarului sau nil, codEroare.
]]
-- Avatar generat (testul de încărcare): fără cereri la Roblox, culori aleatorii.
local function testDescription()
	local d = Instance.new("HumanoidDescription")
	local rng = Random.new()
	local color = Color3.fromHSV(rng:NextNumber(), 0.6, 0.9)
	d.HeadColor = Color3.fromRGB(255, 220, 180)
	d.TorsoColor = color
	d.LeftArmColor = color
	d.RightArmColor = color
	d.LeftLegColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	d.RightLegColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	return d
end

function AvatarService:BuildAsync(entry)
	local description, err
	if entry.isTest then
		description = testDescription()
	else
		description, err = self._users.GetDescriptionAsync(entry.robloxUserId)
	end
	if not description then
		return nil, err
	end
	local avatar, buildErr = self._users.CreateAvatarModelAsync(description, entry.robloxName)
	if not avatar then
		return nil, buildErr
	end
	if not avatar:FindFirstChild("HumanoidRootPart") or not avatar:FindFirstChild("LowerTorso") then
		avatar:Destroy()
		return nil, "AVATAR_FAILED"
	end
	prepareModel(avatar)
	createNameTag(avatar, entry.robloxName, entry.displayName)
	avatar:SetAttribute("RobloxUserId", entry.robloxUserId)
	return avatar
end

-- Avatar în picioare pe sol (înainte de a primi mount-ul)
function AvatarService:PlaceStanding(avatar, groundCFrame)
	local hrp = avatar.PrimaryPart
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	local height = (humanoid and humanoid.HipHeight or 2) + hrp.Size.Y / 2
	hrp.Anchored = true
	avatar:PivotTo(groundCFrame * CFrame.new(0, height, 0))
end

--[[
	Așază avatarul pe Body > Seat și îl sudează de mount. Partea de jos a
	LowerTorso ajunge exact pe Seat, indiferent de mărimea avatarului.
]]
function AvatarService:AttachToMount(avatar, mount)
	local hrp = avatar.PrimaryPart
	local lowerTorso = avatar:FindFirstChild("LowerTorso")
	local body = mount:FindFirstChild("Body")
	local seat = body and body:FindFirstChild("Seat")
	assert(hrp and lowerTorso and seat, "Avatar sau mount incomplet")

	local old = hrp:FindFirstChild("MountWeld")
	if old then
		old:Destroy()
	end

	local torsoOffset = hrp.CFrame:ToObjectSpace(lowerTorso.CFrame).Position.Y
	local hipsBelowRoot = torsoOffset - lowerTorso.Size.Y / 2 -- negativ: șoldurile sunt sub HRP
	local seatCFrame = seat.WorldCFrame
	avatar:PivotTo(seatCFrame * CFrame.new(0, -hipsBelowRoot, 0))

	hrp.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Name = "MountWeld"
	weld.Part0 = body
	weld.Part1 = hrp
	weld.Parent = hrp
	avatar:SetAttribute("MountStyle", mount:GetAttribute("MountStyle"))
end

return AvatarService
