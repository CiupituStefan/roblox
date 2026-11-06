--[[
	HUD  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > HUD

	Interfața permanentă a transmisiei (construită din cod, gândită pentru
	ecran VERTICAL 9:16, dar se adaptează și la orizontal):

	  ┌──────────────────────────────┐
	  │ 🗺️ Hartă · faza · ⏱ timp      │  bara de sus
	  │ ┌ CLASAMENT ┐      ┌ COADA ┐ │
	  │ │ 🥇 avatar…│      │ #1 …  │ │  clasament live (stânga) / coadă (dreapta)
	  │ └───────────┘      └───────┘ │
	  │          (acțiunea)          │
	  │ ┌ anunțuri: donații, boost ┐ │  fluxul de anunțuri (jos)
	  └──────────────────────────────┘

	Clasament: poziție, avatar original (headshot), nume, mount, viteză curentă,
	boost activ, culoarea aurei; rândurile alunecă animat la depășiri.
	Coada: poziția fiecăruia, ⭐ = Skip Queue, total.
	Anunțuri: înscrieri, donații, boost-uri, Skip Queue, coduri !verify.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HUD = {}

local FONT = Enum.Font.FredokaOne
local BODY = Enum.Font.GothamBold
local GOLD = Color3.fromRGB(255, 210, 60)
local PANEL = Color3.fromRGB(22, 12, 48)
local MEDALS = { "🥇", "🥈", "🥉" }
local PHASE_TEXT = {
	Idle = "Înscrieri deschise",
	Lobby = "Se încarcă avatarurile",
	Wheel = "Roata mount-urilor",
	Countdown = "Pregătiți-vă!",
	Racing = "CURSĂ",
	Finished = "Final",
}
local FEED_STYLE = {
	join = { icon = "✅", color = Color3.fromRGB(140, 255, 160) },
	joinRejected = { icon = "⚠️", color = Color3.fromRGB(255, 170, 120) },
	boost = { icon = "🎁", color = GOLD },
	skip = { icon = "⭐", color = Color3.fromRGB(255, 230, 120) },
	giftThanks = { icon = "💖", color = Color3.fromRGB(255, 160, 210) },
	verify = { icon = "🔐", color = Color3.fromRGB(160, 220, 255) },
	verifyCode = { icon = "🔐", color = Color3.fromRGB(160, 220, 255) },
	map = { icon = "🗺️", color = Color3.new(1, 1, 1) },
	winner = { icon = "🏆", color = GOLD },
	racerDropped = { icon = "⚠️", color = Color3.fromRGB(255, 170, 120) },
}

local SoundPlayer = { Play = function() end }
local gui, topBar, topLabel, board, boardList, boardTitle, queuePanel, queueList, queueTitle, feed, verifyPanel
local rows = {} -- robloxUserId -> row
local queueRows = {}
local state = { queue = nil }
local mountIcons = {}

local function new(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function corner(parent, scale)
	return new("UICorner", { CornerRadius = UDim.new(scale or 0.2, 0) }, parent)
end

local function headshot(userId)
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

local function panel(name, parent)
	local frame = new("Frame", { Name = name, BackgroundColor3 = PANEL, BackgroundTransparency = 0.18 }, parent)
	corner(frame, 0.06)
	new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(120, 90, 220), Transparency = 0.2 }, frame)
	return frame
end

local function auraColor(ratio)
	local color = Config.Aura.Tiers[1].Color
	for _, tier in ipairs(Config.Aura.Tiers) do
		if ratio >= tier.MinMultiplier then
			color = tier.Color
		end
	end
	return color
end

local function formatTime(seconds)
	seconds = math.max(0, seconds or 0)
	return string.format("%d:%04.1f", seconds // 60, seconds % 60)
end

---------------------------------------------------------------------------
-- Construcție
---------------------------------------------------------------------------
local function build()
	for _, m in ipairs(Config.Mounts) do
		mountIcons[m.Id] = m.Icon
	end
	gui = new("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10 }, Players.LocalPlayer:WaitForChild("PlayerGui"))

	topBar = panel("TopBar", gui)
	topLabel = new("TextLabel", { Size = UDim2.fromScale(0.96, 0.8), Position = UDim2.fromScale(0.02, 0.1), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, Text = "" }, topBar)

	-- clasament
	board = panel("Leaderboard", gui)
	boardTitle = new("TextLabel", { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = GOLD, Text = "🏁 CLASAMENT" }, board)
	boardList = new("Frame", { Name = "Rows", BackgroundTransparency = 1, ClipsDescendants = true }, board)

	-- coada
	queuePanel = panel("Queue", gui)
	queueTitle = new("TextLabel", { BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = GOLD, Text = "🎟️ COADA" }, queuePanel)
	queueList = new("Frame", { Name = "Rows", BackgroundTransparency = 1 }, queuePanel)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0.01, 0) }, queueList)

	-- anunțuri
	feed = new("Frame", { Name = "Feed", BackgroundTransparency = 1 }, gui)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0.02, 0) }, feed)

	-- panoul pentru codul de verificare (mare, ca să poată fi copiat)
	verifyPanel = panel("VerifyCode", gui)
	verifyPanel.Visible = false
	new("TextLabel", { Name = "Body", Size = UDim2.fromScale(0.94, 0.9), Position = UDim2.fromScale(0.03, 0.05), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = Color3.fromRGB(180, 230, 255), TextWrapped = true, Text = "" }, verifyPanel)
end

local function layout()
	local view = workspace.CurrentCamera.ViewportSize
	local portrait = view.Y >= view.X
	if portrait then
		topBar.Position = UDim2.fromScale(0.02, 0.012)
		topBar.Size = UDim2.fromScale(0.96, 0.045)
		board.Position = UDim2.fromScale(0.02, 0.065)
		board.Size = UDim2.fromScale(0.52, 0.34)
		queuePanel.Position = UDim2.fromScale(0.56, 0.065)
		queuePanel.Size = UDim2.fromScale(0.42, 0.26)
		feed.Position = UDim2.fromScale(0.03, 0.66)
		feed.Size = UDim2.fromScale(0.94, 0.24)
		verifyPanel.Position = UDim2.fromScale(0.04, 0.5)
		verifyPanel.Size = UDim2.fromScale(0.92, 0.12)
	else
		topBar.Position = UDim2.fromScale(0.3, 0.012)
		topBar.Size = UDim2.fromScale(0.4, 0.06)
		board.Position = UDim2.fromScale(0.01, 0.1)
		board.Size = UDim2.fromScale(0.27, 0.6)
		queuePanel.Position = UDim2.fromScale(0.8, 0.1)
		queuePanel.Size = UDim2.fromScale(0.19, 0.5)
		feed.Position = UDim2.fromScale(0.3, 0.7)
		feed.Size = UDim2.fromScale(0.4, 0.2)
		verifyPanel.Position = UDim2.fromScale(0.3, 0.55)
		verifyPanel.Size = UDim2.fromScale(0.4, 0.12)
	end
	boardTitle.Size = UDim2.fromScale(0.9, 0.09)
	boardTitle.Position = UDim2.fromScale(0.05, 0.01)
	boardList.Position = UDim2.fromScale(0.03, 0.11)
	boardList.Size = UDim2.fromScale(0.94, 0.87)
	queueTitle.Size = UDim2.fromScale(0.9, 0.12)
	queueTitle.Position = UDim2.fromScale(0.05, 0.01)
	queueList.Position = UDim2.fromScale(0.04, 0.14)
	queueList.Size = UDim2.fromScale(0.92, 0.84)
end

---------------------------------------------------------------------------
-- Clasament live
---------------------------------------------------------------------------
local function makeRow(model)
	local userId = model:GetAttribute("RobloxUserId")
	local row = { model = model }
	local frame = new("Frame", { BackgroundColor3 = Color3.fromRGB(45, 30, 90), BackgroundTransparency = 0.25, Size = UDim2.fromScale(1, 1 / Config.UI.LeaderboardRows - 0.01) }, boardList)
	corner(frame, 0.3)
	row.frame = frame
	row.stripe = new("Frame", { Size = UDim2.fromScale(0.025, 1), BackgroundColor3 = Config.Aura.Tiers[1].Color, BorderSizePixel = 0 }, frame)
	corner(row.stripe, 0.5)
	row.place = new("TextLabel", { Position = UDim2.fromScale(0.035, 0), Size = UDim2.fromScale(0.13, 1), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "" }, frame)
	row.image = new("ImageLabel", { Position = UDim2.fromScale(0.17, 0.08), Size = UDim2.fromScale(0.84, 0.84), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundColor3 = Color3.fromRGB(80, 60, 140), Image = headshot(userId) }, frame)
	corner(row.image, 0.5)
	row.name = new("TextLabel", { Position = UDim2.fromScale(0.33, 0.04), Size = UDim2.fromScale(0.42, 0.56), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), Text = model:GetAttribute("RobloxName") or "?" }, frame)
	row.detail = new("TextLabel", { Position = UDim2.fromScale(0.33, 0.58), Size = UDim2.fromScale(0.42, 0.38), BackgroundTransparency = 1, Font = BODY, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 200, 240), Text = "" }, frame)
	row.boost = new("TextLabel", { Position = UDim2.fromScale(0.77, 0.05), Size = UDim2.fromScale(0.21, 0.9), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = GOLD, Text = "" }, frame)
	rows[userId] = row
	return row
end

local BOOST_ICONS = { ["Speed Boost"] = "💨", ["Super Speed"] = "🌟", Turbo = "🔥", ["Rocket Boost"] = "🚀", Jetpack = "🎒", ["Lightning Boost"] = "⚡", ["Teleport Dash"] = "🌀" }

local function updateBoard()
	local models = CollectionService:GetTagged("Racer")
	local list = {}
	local seen = {}
	for _, model in ipairs(models) do
		local userId = model:GetAttribute("RobloxUserId")
		if userId and model.Parent then
			seen[userId] = true
			table.insert(list, model)
		end
	end
	for userId, row in pairs(rows) do
		if not seen[userId] then
			row.frame:Destroy()
			rows[userId] = nil
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = a:GetAttribute("Position"), b:GetAttribute("Position")
		if pa and pb and pa ~= pb then
			return pa < pb
		end
		if (pa ~= nil) ~= (pb ~= nil) then
			return pa ~= nil
		end
		return (a:GetAttribute("RobloxName") or "") < (b:GetAttribute("RobloxName") or "")
	end)

	local phase = workspace:GetAttribute("RacePhase")
	board.Visible = #list > 0 and phase ~= "Idle" and not workspace:GetAttribute("PodiumActive")
	boardTitle.Text = string.format("🏁 CLASAMENT · %d", #list)
	local maxRows = Config.UI.LeaderboardRows
	local rowHeight = 1 / maxRows
	local now = workspace:GetServerTimeNow()
	for index, model in ipairs(list) do
		local userId = model:GetAttribute("RobloxUserId")
		local row = rows[userId] or makeRow(model)
		row.frame.Visible = index <= maxRows
		local target = UDim2.fromScale(0, (index - 1) * rowHeight)
		if row.frame.Position ~= target then
			TweenService:Create(row.frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
		end
		row.place.Text = MEDALS[index] or ("#" .. index)
		local mountIcon = mountIcons[model:GetAttribute("MountId")] or ""
		row.name.Text = mountIcon .. " " .. (model:GetAttribute("RobloxName") or "?")
		local speed = model:GetAttribute("Speed") or 0
		if model:GetAttribute("Finished") then
			row.detail.Text = "🏁 " .. formatTime(model:GetAttribute("FinishTime"))
			row.detail.TextColor3 = GOLD
		elseif model:GetAttribute("OnTrack") then
			row.detail.Text = string.format("%d %s", math.floor(speed * Config.UI.SpeedUnitFactor), Config.UI.SpeedUnit)
			row.detail.TextColor3 = Color3.fromRGB(200, 200, 240)
		else
			row.detail.Text = "pregătire..."
		end
		local ratio = model:GetAttribute("OnTrack") and speed / Config.Race.BaseSpeed or 0
		row.stripe.BackgroundColor3 = auraColor(ratio)
		local boostActive = (model:GetAttribute("AuraBoostUntil") or 0) > now
		local last = model:GetAttribute("LastBoost")
		row.boost.Text = (boostActive and last) and (BOOST_ICONS[last] or "⚡") or ""
		row.frame.BackgroundColor3 = boostActive and Color3.fromRGB(90, 60, 20) or Color3.fromRGB(45, 30, 90)
	end
end

---------------------------------------------------------------------------
-- Coada
---------------------------------------------------------------------------
local function updateQueue()
	local snapshot = state.queue
	if not snapshot then
		return
	end
	local phase = workspace:GetAttribute("RacePhase")
	local racing = phase and phase ~= "Idle"
	queueTitle.Text = string.format("🎟️ %s · %d", racing and "URMĂTOAREA CURSĂ" or "COADA", snapshot.queuedTotal or 0)
	for _, row in ipairs(queueRows) do
		row:Destroy()
	end
	table.clear(queueRows)
	local rowHeight = 1 / (Config.UI.QueueRows + 1) - 0.01
	if not snapshot.registrationOpen then
		table.insert(queueRows, new("TextLabel", { LayoutOrder = 0, Size = UDim2.fromScale(1, rowHeight), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = Color3.fromRGB(255, 140, 140), Text = "🔒 Înscrieri închise" }, queueList))
	end
	for i, item in ipairs(snapshot.queued or {}) do
		if i > Config.UI.QueueRows then
			break
		end
		local frame = new("Frame", { LayoutOrder = i, Size = UDim2.fromScale(1, rowHeight), BackgroundColor3 = item.priority and Color3.fromRGB(90, 70, 20) or Color3.fromRGB(45, 30, 90), BackgroundTransparency = 0.3 }, queueList)
		corner(frame, 0.3)
		new("TextLabel", { Size = UDim2.fromScale(0.2, 1), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = GOLD, Text = "#" .. item.position }, frame)
		local img = new("ImageLabel", { Position = UDim2.fromScale(0.2, 0.08), Size = UDim2.fromScale(0.84, 0.84), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundTransparency = 1, Image = headshot(item.robloxUserId) }, frame)
		corner(img, 0.5)
		new("TextLabel", { Position = UDim2.fromScale(0.36, 0), Size = UDim2.fromScale(0.62, 1), BackgroundTransparency = 1, Font = BODY, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), Text = (item.priority and "⭐ " or "") .. item.robloxName }, frame)
		table.insert(queueRows, frame)
	end
	if (snapshot.queuedTotal or 0) == 0 then
		table.insert(queueRows, new("TextLabel", { LayoutOrder = 99, Size = UDim2.fromScale(1, rowHeight * 2), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 200, 240), Text = "Scrie !join NumeRoblox" }, queueList))
	elseif snapshot.queuedTotal > Config.UI.QueueRows then
		table.insert(queueRows, new("TextLabel", { LayoutOrder = 98, Size = UDim2.fromScale(1, rowHeight), BackgroundTransparency = 1, Font = BODY, TextScaled = true, TextColor3 = Color3.fromRGB(200, 200, 240), Text = string.format("+%d în așteptare", snapshot.queuedTotal - Config.UI.QueueRows) }, queueList))
	end
end

---------------------------------------------------------------------------
-- Anunțuri
---------------------------------------------------------------------------
local feedOrder = 0
local function addFeed(payload)
	local style = FEED_STYLE[payload.kind] or { icon = "📣", color = Color3.new(1, 1, 1) }
	feedOrder += 1
	local item = new("Frame", { LayoutOrder = feedOrder, Size = UDim2.fromScale(1, 1 / Config.UI.FeedSize - 0.02), BackgroundColor3 = PANEL, BackgroundTransparency = 0.15 }, feed)
	corner(item, 0.3)
	new("UIStroke", { Thickness = 2, Color = style.color, Transparency = 0.3 }, item)
	local textX = 0.03
	if payload.robloxUserId then
		local img = new("ImageLabel", { Position = UDim2.fromScale(0.015, 0.1), Size = UDim2.fromScale(0.8, 0.8), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundTransparency = 1, Image = headshot(payload.robloxUserId) }, item)
		corner(img, 0.5)
		textX = 0.13
	end
	local label = new("TextLabel", { Position = UDim2.fromScale(textX, 0.08), Size = UDim2.fromScale(0.97 - textX, 0.84), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = style.color, TextStrokeTransparency = 0.4, Text = style.icon .. " " .. tostring(payload.text or "") }, item)

	-- intrare animată
	local scale = new("UIScale", { Scale = 0.6 }, item)
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local items = {}
	for _, child in ipairs(feed:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #items - Config.UI.FeedSize do
		items[i]:Destroy()
	end
	task.delay(Config.UI.FeedSeconds, function()
		if item.Parent then
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(item, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			task.wait(0.45)
			item:Destroy()
		end
	end)
end

local verifyToken = 0
local function showVerifyCode(payload)
	verifyToken += 1
	local my = verifyToken
	verifyPanel.Body.Text = "🔐 " .. tostring(payload.text or "")
	verifyPanel.Visible = true
	task.delay(Config.UI.VerifyCodeSeconds, function()
		if my == verifyToken then
			verifyPanel.Visible = false
		end
	end)
end

local function onAnnounce(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "verifyCode" then
		showVerifyCode(payload)
	end
	addFeed(payload)
	if payload.kind == "boost" or payload.kind == "giftThanks" or payload.kind == "skip" then
		SoundPlayer.Play("Gift", 0.7)
	end
end

---------------------------------------------------------------------------
-- Bara de sus
---------------------------------------------------------------------------
local function updateTop()
	local phase = workspace:GetAttribute("RacePhase") or "Idle"
	local parts = {}
	local mapName = workspace:GetAttribute("CurrentMapName")
	if mapName and phase ~= "Idle" then
		table.insert(parts, "🗺️ " .. mapName)
	end
	if workspace:GetAttribute("RacePaused") then
		table.insert(parts, "⏸️ PAUZĂ")
	else
		table.insert(parts, PHASE_TEXT[phase] or phase)
	end
	local raceTime = workspace:GetAttribute("RaceTime")
	if raceTime and (phase == "Racing" or phase == "Finished") then
		table.insert(parts, "⏱ " .. formatTime(raceTime))
	end
	topLabel.Text = table.concat(parts, "  ·  ")
end

function HUD.Start(soundPlayer)
	if soundPlayer then
		SoundPlayer = soundPlayer
	end
	build()
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	Remotes.Announce.OnClientEvent:Connect(onAnnounce)
	Remotes.StateUpdate.OnClientEvent:Connect(function(snapshot)
		if type(snapshot) == "table" then
			state.queue = snapshot.queue
			updateQueue()
		end
	end)
	task.spawn(function()
		local ok, snapshot = pcall(function()
			return Remotes.GetState:InvokeServer()
		end)
		if ok and type(snapshot) == "table" then
			state.queue = snapshot.queue
			updateQueue()
		end
	end)
	task.spawn(function()
		local lastPhase = nil
		while true do
			updateBoard()
			updateTop()
			local phase = workspace:GetAttribute("RacePhase")
			if phase ~= lastPhase then
				lastPhase = phase
				updateQueue()
			end
			task.wait(0.15)
		end
	end)
end

return HUD
