--[[
	WheelController  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > WheelController

	Roata norocului pentru mount-uri. Serverul a decis deja rezultatele; aici
	doar le animăm, sincronizat cu workspace:GetServerTimeNow(), astfel încât
	roata se oprește exact când mount-ul apare sub avatar în lume.

	Interfața este construită din cod (nu trebuie creat nimic în StarterGui)
	și se adaptează la ecran vertical (TikTok 9:16) și orizontal.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local WheelController = {}

local player = Players.LocalPlayer
local gui, wheelHolder, spinner, card, cardImage, cardName, cardResult, strip, title
local currentToken = 0
local SoundPlayer = { Play = function() end } -- înlocuit la Start

local FONT = Enum.Font.FredokaOne
local BANDS = 7
local INNER = 0.13 -- raza butucului (fracție din lățimea roții)

local function headshot(userId)
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

local function new(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0.5, 0) }, parent)
end

local function stroke(parent, thickness, color)
	return new("UIStroke", { Thickness = thickness, Color = color or Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function buildGui()
	gui = new("ScreenGui", { Name = "WheelGui", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false, DisplayOrder = 20 }, player:WaitForChild("PlayerGui"))
	new("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 5, 30), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, gui)

	title = new("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.9, 0.07),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "🎡 ROATA MOUNT-URILOR 🎡",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 220, 70),
		TextStrokeTransparency = 0,
	}, gui)

	wheelHolder = new("Frame", { Name = "Wheel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), BackgroundTransparency = 1 }, gui)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, wheelHolder)
	local rim = new("Frame", { Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.06, 1.06), BackgroundColor3 = Color3.fromRGB(40, 20, 80), ZIndex = 1 }, wheelHolder)
	corner(rim)
	stroke(rim, 6, Color3.fromRGB(255, 220, 70))
	spinner = new("Frame", { Name = "Spinner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, wheelHolder)
	local hub = new("Frame", { Name = "Hub", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(INNER * 2.1, INNER * 2.1), BackgroundColor3 = Color3.fromRGB(255, 220, 70), ZIndex = 6 }, wheelHolder)
	corner(hub)
	stroke(hub, 4, Color3.fromRGB(40, 20, 80))
	new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "🏁", TextScaled = true, ZIndex = 7 }, hub)
	-- indicator (triunghi din pătrat rotit) deasupra roții
	local pointer = new("Frame", { Name = "Pointer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, -0.02), Size = UDim2.fromScale(0.09, 0.09), Rotation = 45, BackgroundColor3 = Color3.fromRGB(255, 60, 90), ZIndex = 8 }, wheelHolder)
	stroke(pointer, 3)

	card = new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(30, 15, 60), BackgroundTransparency = 0.1 }, gui)
	corner(card, UDim.new(0.2, 0))
	stroke(card, 3, Color3.fromRGB(255, 220, 70))
	cardImage = new("ImageLabel", { Name = "Headshot", Position = UDim2.fromScale(0.03, 0.1), Size = UDim2.fromScale(0.8, 0.8), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundColor3 = Color3.fromRGB(80, 60, 140) }, card)
	corner(cardImage)
	cardName = new("TextLabel", { Name = "Name", Position = UDim2.fromScale(0.3, 0.08), Size = UDim2.fromScale(0.67, 0.42), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.2 }, card)
	cardResult = new("TextLabel", { Name = "Result", Position = UDim2.fromScale(0.3, 0.52), Size = UDim2.fromScale(0.67, 0.4), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 220, 70), TextStrokeTransparency = 0.2 }, card)

	strip = new("Frame", { Name = "Revealed", AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, gui)
	new("UIGridLayout", { CellSize = UDim2.fromScale(0.155, 0.47), CellPadding = UDim2.fromScale(0.012, 0.04), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, strip)
end

-- Reașezare pentru ecran vertical / orizontal
local function layout()
	local view = workspace.CurrentCamera.ViewportSize
	local portrait = view.Y > view.X
	local size = math.min(view.X * (portrait and 0.82 or 0.5), view.Y * (portrait and 0.42 or 0.55))
	wheelHolder.Size = UDim2.fromOffset(size, size)
	wheelHolder.Position = UDim2.fromScale(0.5, portrait and 0.36 or 0.42)
	local cardWidth = portrait and 0.9 or 0.42
	card.Size = UDim2.new(cardWidth, 0, 0, math.max(60, size * 0.22))
	card.Position = UDim2.new(0.5, 0, wheelHolder.Position.Y.Scale, size / 2 + 24)
	strip.Size = UDim2.fromScale(portrait and 0.95 or 0.6, portrait and 0.17 or 0.16)
	strip.Position = UDim2.fromScale(0.5, 0.985)
end

local function buildSegments(segments)
	spinner:ClearAllChildren()
	spinner.Rotation = 0
	local n = #segments
	local half = math.pi / n
	for i, seg in ipairs(segments) do
		local slice = new("Frame", { Name = seg.id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = (i - 1) * 360 / n }, spinner)
		-- felie aproximată din benzi din ce în ce mai late spre margine
		for band = 1, BANDS do
			local rIn = INNER + (0.5 - INNER) * (band - 1) / BANDS
			local rOut = INNER + (0.5 - INNER) * band / BANDS
			local width = 2 * rOut * math.sin(half) + 0.004
			local color = seg.color or Color3.fromHSV((i - 1) / n, 0.7, 1)
			if i % 2 == 0 then
				color = color:Lerp(Color3.new(1, 1, 1), 0.12)
			end
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.5 - rIn),
				Size = UDim2.fromScale(width, rOut - rIn + 0.003),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, slice)
		end
		new("TextLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.08),
			Size = UDim2.fromScale(0.09, 0.09),
			BackgroundTransparency = 1,
			Text = seg.icon or "❓",
			TextScaled = true,
			ZIndex = 4,
		}, slice)
		new("TextLabel", {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.29),
			Size = UDim2.fromScale(0.3, 0.055),
			Rotation = 90,
			BackgroundTransparency = 1,
			Font = FONT,
			Text = seg.name,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.1,
			ZIndex = 4,
		}, slice)
	end
	-- linii de separare între felii
	for i = 1, n do
		local line = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = (i - 0.5) * 360 / n, ZIndex = 3 }, spinner)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = Color3.fromRGB(255, 245, 210), BorderSizePixel = 0, ZIndex = 3 }, line)
	end
end

local function indexOf(segments, id)
	for i, seg in ipairs(segments) do
		if seg.id == id then
			return i
		end
	end
	return 1
end

local function waitUntil(serverTime, token)
	while workspace:GetServerTimeNow() < serverTime do
		if token ~= currentToken then
			return false
		end
		task.wait()
	end
	return token == currentToken
end

local function addRevealed(reveal, order)
	local item = new("Frame", { LayoutOrder = order, BackgroundColor3 = Color3.fromRGB(40, 20, 80), BackgroundTransparency = 0.1 }, strip)
	corner(item, UDim.new(0.2, 0))
	stroke(item, 2, Color3.fromRGB(255, 220, 70))
	local img = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.05), Size = UDim2.fromScale(0.62, 0.62), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundTransparency = 1, Image = headshot(reveal.robloxUserId) }, item)
	new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1.15, -0.05), Size = UDim2.fromScale(0.55, 0.55), BackgroundTransparency = 1, Text = reveal.mountIcon, TextScaled = true }, img)
	new("TextLabel", { Position = UDim2.fromScale(0.04, 0.68), Size = UDim2.fromScale(0.92, 0.3), BackgroundTransparency = 1, Font = FONT, Text = reveal.robloxName, TextScaled = true, TextColor3 = Color3.new(1, 1, 1) }, item)
end

local function play(payload)
	currentToken += 1
	local token = currentToken
	for _, child in ipairs(strip:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	buildSegments(payload.segments)
	layout()
	cardName.Text = ""
	cardResult.Text = ""
	cardImage.Image = ""
	gui.Enabled = true

	local n = #payload.segments
	local sliceAngle = 360 / n
	for i, reveal in ipairs(payload.reveals) do
		if not waitUntil(payload.startAt + reveal.start, token) then
			return
		end
		cardImage.Image = headshot(reveal.robloxUserId)
		cardName.Text = reveal.robloxName
		cardResult.Text = "Se învârte... 🎲"
		title.Text = string.format("🎡 ROATA MOUNT-URILOR  %d/%d", i, #payload.reveals)

		local spinTime = math.max(0.3, payload.startAt + reveal.landAt - workspace:GetServerTimeNow())
		local target = indexOf(payload.segments, reveal.mountId)
		local current = spinner.Rotation
		local jitter = (math.random() - 0.5) * sliceAngle * 0.6
		local wanted = -((target - 1) * sliceAngle) + jitter
		local delta = (wanted - current) % 360
		local spins = spinTime > 1.5 and 3 or 2
		local finalRotation = current + spins * 360 + delta
		TweenService:Create(spinner, TweenInfo.new(spinTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Rotation = finalRotation }):Play()
		-- „tic” la fiecare felie care trece prin dreptul indicatorului
		task.spawn(function()
			local lastSlice = math.floor(spinner.Rotation / sliceAngle)
			local stopAt = os.clock() + spinTime
			while os.clock() < stopAt and token == currentToken do
				local slice = math.floor(spinner.Rotation / sliceAngle)
				if slice ~= lastSlice then
					lastSlice = slice
					SoundPlayer.Play("WheelTick", 0.4)
				end
				task.wait()
			end
		end)

		if not waitUntil(payload.startAt + reveal.landAt, token) then
			return
		end
		cardResult.Text = string.format("%s %s!", reveal.mountIcon, reveal.mountName)
		SoundPlayer.Play("WheelResult")
		card.Rotation = -3
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		addRevealed(reveal, i)
	end

	if waitUntil(payload.startAt + payload.total, token) then
		gui.Enabled = false
		title.Text = "🎡 ROATA MOUNT-URILOR 🎡"
	end
end

function WheelController.Start(soundPlayer)
	if soundPlayer then
		SoundPlayer = soundPlayer
	end
	buildGui()
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	Remotes.RaceEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "wheel" then
			task.spawn(play, payload)
		end
	end)
end

return WheelController
