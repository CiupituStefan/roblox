--[[
	RaceUI  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > RaceUI

	Interfața desfășurării cursei (construită din cod, lizibilă pe ecran vertical):
	  * lobby: „Următoarea cursă în X s” / „Scrie !join NumeRoblox”
	  * prezentarea hărții
	  * countdown 3-2-1-GO! sincronizat cu serverul (workspace:GetServerTimeNow)
	  * cine trece linia de finish (#1, #2...)
	  * câștigătorul
	  * panoul cu rezultate (podium cu pozele avatarurilor + restul clasamentului)
	Clasamentul live, coada și anunțurile sunt în HUD (Etapa 7).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local RaceUI = {}

local FONT = Enum.Font.FredokaOne
local GOLD = Color3.fromRGB(255, 210, 60)
local MEDALS = { "🥇", "🥈", "🥉" }

local gui, center, subtitle, lobbyLabel, results
local SoundPlayer = { Play = function() end } -- înlocuit la Start
local lobbyStartsAt = nil
local token = 0

local function new(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function headshot(userId)
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

local function pop(label, text, color, duration)
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Visible = true
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0
	local scale = label:FindFirstChildOfClass("UIScale") or new("UIScale", {}, label)
	scale.Scale = 1.8
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if duration then
		local my = token
		task.delay(duration, function()
			if my == token then
				TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end
end

local function build()
	gui = new("ScreenGui", { Name = "RaceGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 15 }, Players.LocalPlayer:WaitForChild("PlayerGui"))

	center = new("TextLabel", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.9, 0.16),
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(30, 10, 60),
		Visible = false,
	}, gui)

	subtitle = new("TextLabel", {
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.06),
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
		Visible = false,
	}, gui)

	lobbyLabel = new("TextLabel", {
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.92, 0.055),
		BackgroundColor3 = Color3.fromRGB(30, 15, 60),
		BackgroundTransparency = 0.2,
		Font = FONT,
		TextScaled = true,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.3,
		Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, lobbyLabel)

	results = new("Frame", {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.94, 0.5),
		BackgroundColor3 = Color3.fromRGB(25, 12, 55),
		BackgroundTransparency = 0.15,
		Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0.05, 0) }, results)
	new("UIStroke", { Thickness = 3, Color = GOLD }, results)
	new("UISizeConstraint", { MaxSize = Vector2.new(720, 99999) }, results)
end

local function formatTime(seconds)
	if not seconds then
		return ""
	end
	return string.format("%d:%05.2f", seconds // 60, seconds % 60)
end

local function showResults(payload)
	results:ClearAllChildren()
	new("UICorner", { CornerRadius = UDim.new(0.05, 0) }, results)
	new("UIStroke", { Thickness = 3, Color = GOLD }, results)
	new("UISizeConstraint", { MaxSize = Vector2.new(720, 99999) }, results)
	new("TextLabel", { Position = UDim2.fromScale(0.05, 0.02), Size = UDim2.fromScale(0.9, 0.1), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = GOLD, Text = "🏁 REZULTATE · " .. (payload.mapName or "") }, results)

	-- podium: 2 | 1 | 3
	local order = { 2, 1, 3 }
	local heights = { [1] = 0.34, [2] = 0.28, [3] = 0.24 }
	for column, place in ipairs(order) do
		local r = payload.results[place]
		if r then
			local x = 0.05 + (column - 1) * 0.31
			local box = new("Frame", { Position = UDim2.fromScale(x, 0.14 + (0.34 - heights[place])), Size = UDim2.fromScale(0.28, heights[place] + 0.12), BackgroundTransparency = 1 }, results)
			local img = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.62, 0.62), SizeConstraint = Enum.SizeConstraint.RelativeXX, BackgroundColor3 = Color3.fromRGB(70, 50, 130), Image = headshot(r.robloxUserId) }, box)
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, img)
			new("UIStroke", { Thickness = 3, Color = place == 1 and GOLD or Color3.fromRGB(200, 200, 210) }, img)
			new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1.15, -0.1), Size = UDim2.fromScale(0.45, 0.45), BackgroundTransparency = 1, Text = MEDALS[place], TextScaled = true }, img)
			new("TextLabel", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.24), BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, Text = r.robloxName }, box)
		end
	end

	-- restul clasamentului
	local list = new("Frame", { Position = UDim2.fromScale(0.05, 0.62), Size = UDim2.fromScale(0.9, 0.36), BackgroundTransparency = 1 }, results)
	new("UIGridLayout", { CellSize = UDim2.fromScale(0.49, 0.18), CellPadding = UDim2.fromScale(0.02, 0.02), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i = 4, math.min(#payload.results, 13) do
		local r = payload.results[i]
		local detail = r.time and formatTime(r.time) or (r.distance .. " studs")
		new("TextLabel", { LayoutOrder = i, BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(230, 230, 255), Text = string.format("#%d %s  %s", r.position, r.robloxName, detail) }, list)
	end

	results.Visible = true
	results.Position = UDim2.fromScale(0.5, -0.6)
	TweenService:Create(results, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.05) }):Play()
	local my = token
	task.delay(payload.podiumSeconds or 10, function()
		if my == token then
			results.Visible = false
		end
	end)
end

local function runCountdown(payload)
	token += 1
	local my = token
	local goAt = payload.goAt
	local seconds = payload.seconds or 3
	-- așteaptă până la începutul numărătorii
	while workspace:GetServerTimeNow() < goAt - seconds do
		if my ~= token then
			return
		end
		task.wait()
	end
	for n = seconds, 1, -1 do
		if my ~= token then
			return
		end
		pop(center, tostring(n), n == 1 and Color3.fromRGB(255, 90, 90) or GOLD)
		SoundPlayer.Play("CountdownBeep")
		while workspace:GetServerTimeNow() < goAt - (n - 1) do
			if my ~= token then
				return
			end
			task.wait()
		end
	end
	if my == token then
		pop(center, "GO!", Color3.fromRGB(90, 255, 120), 1.2)
		SoundPlayer.Play("Go", 1, 1.5)
	end
end

local handlers = {}

function handlers.lobby(payload)
	lobbyStartsAt = payload.startsAt
end

function handlers.lineup(payload)
	lobbyStartsAt = nil
	token += 1
	results.Visible = false
	pop(center, "🗺️ " .. (payload.mapName or ""), Color3.new(1, 1, 1), 3)
	subtitle.Text = string.format("%d concurenți · roata mount-urilor urmează!", #payload.racers)
	subtitle.Visible = true
	task.delay(3, function()
		subtitle.Visible = false
	end)
end

function handlers.countdown(payload)
	task.spawn(runCountdown, payload)
end

function handlers.finish(payload)
	SoundPlayer.Play("Finish", payload.place == 1 and 1 or 0.6)
	if payload.place == 1 then
		token += 1
		pop(center, "🏆 " .. payload.robloxName .. " CÂȘTIGĂ!", GOLD, 3)
		SoundPlayer.Play("Winner")
	end
end

function handlers.results(payload)
	token += 1
	center.Visible = false
	showResults(payload)
end

function handlers.aborted()
	token += 1
	center.Visible = false
	results.Visible = false
end

function RaceUI.Start(soundPlayer)
	if soundPlayer then
		SoundPlayer = soundPlayer
	end
	build()
	Remotes.RaceEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and handlers[payload.type] then
			handlers[payload.type](payload)
		end
	end)
	-- banda de jos din lobby
	task.spawn(function()
		while true do
			local phase = workspace:GetAttribute("RacePhase")
			if workspace:GetAttribute("RacePaused") then
				lobbyLabel.Text = "⏸️ Pauză"
				lobbyLabel.Visible = true
			elseif phase == "Idle" or phase == nil then
				if lobbyStartsAt then
					local left = math.max(0, math.ceil(lobbyStartsAt - workspace:GetServerTimeNow()))
					lobbyLabel.Text = string.format("⏳ Următoarea cursă în %ds · scrie !join NumeRoblox", left)
				else
					lobbyLabel.Text = "✍️ Scrie !join NumeRoblox în chat ca să intri în cursă!"
				end
				lobbyLabel.Visible = true
			else
				lobbyLabel.Visible = false
			end
			task.wait(0.25)
		end
	end)
end

return RaceUI
