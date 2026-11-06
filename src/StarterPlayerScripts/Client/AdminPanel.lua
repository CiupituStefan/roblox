--[[
	AdminPanel  (ModuleScript)
	Locație: StarterPlayer > StarterPlayerScripts > Client > AdminPanel

	Panoul de administrare (construit din cod). Apare DOAR dacă serverul a
	marcat jucătorul ca admin (atributul IsAdmin). Atenție: drepturile reale
	sunt verificate de server la fiecare comandă; panoul doar trimite cereri.

	Deschidere/închidere: tasta din Config.Admin.PanelHotkey (implicit F2) sau
	butonul ⚙️ din colț. Sfat pentru LIVE: deschide panoul de pe un al doilea
	dispozitiv conectat la același server privat, ca să nu apară pe stream.

	Taburi: Control · Cursă · Boost-uri · Gift-uri · Coadă · Hărți & Mount-uri
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AdminPanel = {}

local FONT = Enum.Font.GothamBold
local TITLE = Enum.Font.FredokaOne
local BG = Color3.fromRGB(18, 14, 34)
local ROW = Color3.fromRGB(34, 28, 62)
local ACCENT = Color3.fromRGB(120, 90, 255)
local GREEN = Color3.fromRGB(60, 190, 110)
local RED = Color3.fromRGB(220, 70, 80)
local GOLD = Color3.fromRGB(255, 205, 70)
local NIL = "__nil__" -- ConfigSync.NIL

local player = Players.LocalPlayer
local gui, window, content, statusLabel, tabBar
local state = nil
local currentTab = "Control"
local confirmClearUntil = 0
local TABS = { "Control", "Cursă", "Boost-uri", "Gift-uri", "Coadă", "Hărți" }

local LABELS = {
	["Race.MaxRacers"] = "Concurenți / cursă (max)",
	["Race.MinRacers"] = "Concurenți minimi pentru start",
	["Race.BaseSpeed"] = "Viteza de bază (studs/s)",
	["Race.SpeedNoisePercent"] = "Variație aleatorie (%)",
	["Race.MaxSpeedMultiplier"] = "Plafon multiplicator viteză",
	["Race.LobbyWaitSeconds"] = "Așteptare înscrieri (s)",
	["Race.GridHoldSeconds"] = "Pauză pe grilă (s)",
	["Race.CountdownSeconds"] = "Countdown (s)",
	["Race.FinishGraceSeconds"] = "Timp după câștigător (s)",
	["Race.PodiumSeconds"] = "Podium (s)",
	["Race.MaxRaceSeconds"] = "Durata maximă a cursei (s)",
	["Queue.MaxSize"] = "Mărimea maximă a cozii",
	["Queue.SkipCreditTTLSeconds"] = "Valabilitate Skip Queue (s)",
	["Registration.PerUserCooldownSeconds"] = "Anti-spam !join (s)",
	["BoostRules.PerRacerCooldownSeconds"] = "Pauză între boost-uri (s)",
	["BoostRules.MaxQueuedBoostsPerRacer"] = "Boost-uri în așteptare (max)",
	["Gifts.MaxRepeatPerEvent"] = "Combo maxim per gift",
	["Gifts.ThankNonRacers"] = "Mulțumește spectatorilor (fără boost)",
	["Gifts.AcceptDuringCountdown"] = "Acceptă gift-uri în countdown",
	["Gifts.UseCoinFallback"] = "Recompensă după valoare (gift-uri nelistate)",
	["Wheel.AvoidDuplicates"] = "Roata: mount-uri diferite",
	["Maps.DecorDensity"] = "Densitate decoruri",
	["Aura.Enabled"] = "Aura activă",
	["Aura.BaseSize"] = "Mărimea aurei",
	["UI.ShotSeconds"] = "Cameră: schimbă unghiul la (s)",
	["UI.FocusSeconds"] = "Cameră: prim-plan la boost (s)",
}
local RACE_ORDER = {
	"Race.MaxRacers", "Race.MinRacers", "Race.BaseSpeed", "Race.SpeedNoisePercent", "Race.MaxSpeedMultiplier",
	"Race.LobbyWaitSeconds", "Race.GridHoldSeconds", "Race.CountdownSeconds", "Race.FinishGraceSeconds",
	"Race.PodiumSeconds", "Race.MaxRaceSeconds", "Queue.MaxSize", "Queue.SkipCreditTTLSeconds",
	"Registration.PerUserCooldownSeconds", "BoostRules.PerRacerCooldownSeconds", "BoostRules.MaxQueuedBoostsPerRacer",
	"Gifts.MaxRepeatPerEvent", "Gifts.ThankNonRacers", "Gifts.AcceptDuringCountdown", "Gifts.UseCoinFallback",
	"Wheel.AvoidDuplicates", "Maps.DecorDensity", "Aura.Enabled", "Aura.BaseSize", "UI.ShotSeconds", "UI.FocusSeconds",
}

local render -- forward

local function send(command, args)
	Remotes.AdminCommand:FireServer(command, args)
end

local function new(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function corner(parent, px)
	new("UICorner", { CornerRadius = UDim.new(0, px or 8) }, parent)
end

---------------------------------------------------------------------------
-- Widgeturi
---------------------------------------------------------------------------
local order = 0
local function nextOrder()
	order += 1
	return order
end

local function rowFrame(height)
	local frame = new("Frame", { LayoutOrder = nextOrder(), Size = UDim2.new(1, -8, 0, height or 34), BackgroundColor3 = ROW }, content)
	corner(frame, 6)
	return frame
end

local function label(parent, text, props)
	local l = new("TextLabel", { BackgroundTransparency = 1, Font = FONT, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, Text = text, TextTruncate = Enum.TextTruncate.AtEnd }, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function button(parent, text, color, onClick, props)
	local b = new("TextButton", { BackgroundColor3 = color or ACCENT, Font = FONT, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), Text = text, AutoButtonColor = true }, parent)
	corner(b, 6)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	b.MouseButton1Click:Connect(onClick)
	return b
end

local function header(text)
	local frame = new("Frame", { LayoutOrder = nextOrder(), Size = UDim2.new(1, -8, 0, 28), BackgroundTransparency = 1 }, content)
	label(frame, text, { Size = UDim2.fromScale(1, 1), Font = TITLE, TextSize = 18, TextColor3 = GOLD })
end

local function buttonsRow(list)
	local frame = rowFrame(38)
	frame.BackgroundTransparency = 1
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, frame)
	local width = 1 / #list
	for _, spec in ipairs(list) do
		button(frame, spec[1], spec[2], spec[3], { Size = UDim2.new(width, -6, 1, 0) })
	end
end

local function stepFor(path, value)
	if path:match("Multiplier$") or path:match("AuraBonus$") or path:match("DecorDensity$") then
		return 0.1
	end
	if math.floor(value) == value then
		return 1
	end
	return 0.5
end

local function numberRow(text, path, value, step)
	local frame = rowFrame()
	label(frame, text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.58, -10, 1, 0) })
	step = step or stepFor(path, value or 0)
	local box = new("TextBox", { Position = UDim2.new(0.58, 34, 0.12, 0), Size = UDim2.new(0.42, -76, 0.76, 0), BackgroundColor3 = BG, Font = FONT, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), Text = tostring(value), ClearTextOnFocus = false }, frame)
	corner(box, 6)
	local function submit(newValue)
		if newValue then
			send("set", { path = path, value = newValue })
		end
	end
	button(frame, "−", ROW:Lerp(Color3.new(1, 1, 1), 0.15), function()
		submit((tonumber(box.Text) or value or 0) - step)
	end, { Position = UDim2.new(0.58, 0, 0.12, 0), Size = UDim2.new(0, 30, 0.76, 0) })
	button(frame, "+", ROW:Lerp(Color3.new(1, 1, 1), 0.15), function()
		submit((tonumber(box.Text) or value or 0) + step)
	end, { Position = UDim2.new(1, -36, 0.12, 0), Size = UDim2.new(0, 30, 0.76, 0) })
	box.FocusLost:Connect(function(enter)
		if enter then
			submit(tonumber(box.Text))
		end
	end)
end

local function toggleRow(text, value, onToggle)
	local frame = rowFrame()
	label(frame, text, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.7, -10, 1, 0) })
	button(frame, value and "DA" or "NU", value and GREEN or RED, function()
		onToggle(not value)
	end, { Position = UDim2.new(0.75, 0, 0.12, 0), Size = UDim2.new(0.25, -6, 0.76, 0) })
end

local function inputRow(placeholder, actions)
	local frame = rowFrame(38)
	local box = new("TextBox", { Position = UDim2.fromOffset(6, 4), Size = UDim2.new(0.48, -6, 1, -8), BackgroundColor3 = BG, Font = FONT, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), PlaceholderText = placeholder, Text = "", ClearTextOnFocus = false }, frame)
	corner(box, 6)
	local width = 0.52 / #actions
	for i, action in ipairs(actions) do
		button(frame, action[1], action[2], function()
			action[3](box.Text)
		end, { Position = UDim2.new(0.48 + (i - 1) * width, 4, 0, 4), Size = UDim2.new(width, -6, 1, -8) })
	end
	return box
end

local function cycleReward(current, rewards)
	local list = { NIL }
	for _, r in ipairs(rewards) do
		table.insert(list, r)
	end
	local index = table.find(list, current) or 1
	return list[index % #list + 1]
end

---------------------------------------------------------------------------
-- Taburi
---------------------------------------------------------------------------
local TAB = {}

TAB["Control"] = function(s)
	header("Stare")
	local info = string.format("Curse: %s%s · Faza: %s\nHartă: %s · Următoarea: %s\nBridge TikTok: %s · Înscrieri: %s · În coadă: %d",
		s.running and "PORNITE" or "OPRITE", s.paused and " (PAUZĂ)" or "", tostring(s.phase),
		tostring(s.currentMap or "-"), tostring(s.nextMap or "automat"),
		tostring(s.bridge or "?"), s.registrationOpen and "deschise" or "ÎNCHISE", s.queue.queuedTotal or 0)
	local frame = rowFrame(64)
	label(frame, info, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 1, -8), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None })
	if s.health then
		local h = s.health
		local healthFrame = rowFrame(46)
		label(healthFrame, string.format("Server: FPS %d (cel mai lent cadru %d ms) · memorie %d MB · pornit de %d min\nCurse terminate %d · anulate %d · intervenții watchdog %d",
			h.fps, h.worstFrameMs, h.memoryMb, h.uptimeMin, s.raceStats.racesCompleted, s.raceStats.racesAborted, h.watchdogActions),
			{ Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 1, -4), TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextColor3 = h.fps < 40 and RED or Color3.new(1, 1, 1) })
	end
	header("Curse")
	buttonsRow({
		{ "▶ Pornește", GREEN, function() send("race.start") end },
		{ "■ Oprește", RED, function() send("race.stop") end },
		{ "↻ Repornește ciclul", ACCENT, function() send("race.restart") end },
	})
	buttonsRow({
		{ "⏸ Pauză", ACCENT, function() send("race.pause") end },
		{ "⏵ Reia", ACCENT, function() send("race.resume") end },
		{ "✖ Anulează cursa", RED, function() send("race.abort") end },
	})
	header("Relay TikTok (adresa HTTPS)")
	local urlBox = inputRow(tostring(s.bridgeUrl or "https://..."), {
		{ "Salvează", GREEN, function(text)
			send("set", { path = "Bridge.BaseUrl", value = text })
		end },
	})
	urlBox.Text = tostring(s.bridgeUrl or "")
	header("Înscrieri")
	toggleRow("Înscrieri deschise", s.registrationOpen, function(v)
		send("queue.registration", { open = v })
	end)
	header("Test de încărcare" .. (s.isStudio and "" or " (doar în Studio)"))
	buttonsRow({
		{ s.loadTestRunning and "Rulează..." or "12 concurenți · 10 gift/s", ACCENT, function()
			send("debug.loadtest", { racers = 12, giftsPerSecond = 10, seconds = 30 })
		end },
		{ s.loadTestRunning and "Rulează..." or "40 concurenți · 30 gift/s", RED, function()
			send("debug.loadtest", { racers = 40, giftsPerSecond = 30, seconds = 45 })
		end },
	})
	if s.lastLoadTest then
		local reportFrame = rowFrame(70)
		label(reportFrame, s.lastLoadTest, { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 1, -4), TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextSize = 12 })
	end
	header("Setări salvate")
	buttonsRow({
		{ string.format("Șterge setările salvate (%d)", s.savedCount or 0), RED, function() send("settings.reset") end },
	})
end

TAB["Cursă"] = function(s)
	header("Cursă, coadă, gift-uri, cameră")
	for _, path in ipairs(RACE_ORDER) do
		local value = s.settings[path]
		if type(value) == "boolean" then
			toggleRow(LABELS[path] or path, value, function(v)
				send("set", { path = path, value = v })
			end)
		elseif type(value) == "number" then
			numberRow(LABELS[path] or path, path, value)
		end
	end
	local rotation = s.settings["Maps.Rotation"]
	local frame = rowFrame()
	label(frame, "Rotația hărților", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.6, -10, 1, 0) })
	button(frame, rotation == "Random" and "Aleatorie" or "În ordine", ACCENT, function()
		send("set", { path = "Maps.Rotation", value = rotation == "Random" and "Sequential" or "Random" })
	end, { Position = UDim2.new(0.6, 0, 0.12, 0), Size = UDim2.new(0.4, -6, 0.76, 0) })
end

TAB["Boost-uri"] = function(s)
	local names = {}
	for name in pairs(s.boosts) do
		table.insert(names, name)
	end
	table.sort(names)
	local fieldLabels = { Multiplier = "Multiplicator viteză", Duration = "Durată (s)", Distance = "Distanță (studs)", ImpulseTime = "Timp impuls (s)", FlightHeight = "Înălțime zbor", AuraBonus = "Bonus aură" }
	for _, name in ipairs(names) do
		local boost = s.boosts[name]
		header(string.format("%s  (%s)", boost.displayName, boost.kind))
		local fields = {}
		for field in pairs(boost.fields) do
			table.insert(fields, field)
		end
		table.sort(fields)
		for _, field in ipairs(fields) do
			numberRow(fieldLabels[field] or field, string.format("Boosts.%s.%s", name, field), boost.fields[field])
		end
	end
end

TAB["Gift-uri"] = function(s)
	header("Gift TikTok → recompensă (apasă pe recompensă ca s-o schimbi)")
	local names = {}
	for name in pairs(s.giftsByName) do
		table.insert(names, name)
	end
	table.sort(names)
	local function mappingRow(display, path, reward)
		local frame = rowFrame()
		label(frame, display, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.45, -10, 1, 0) })
		button(frame, reward, ACCENT, function()
			send("set", { path = path, value = cycleReward(reward, s.rewards) })
		end, { Position = UDim2.new(0.45, 0, 0.12, 0), Size = UDim2.new(0.4, -6, 0.76, 0) })
		button(frame, "🗑", RED, function()
			send("set", { path = path, value = NIL })
		end, { Position = UDim2.new(0.85, 0, 0.12, 0), Size = UDim2.new(0.15, -6, 0.76, 0) })
	end
	for _, name in ipairs(names) do
		mappingRow("🎁 " .. name, "Gifts.ByName." .. name, s.giftsByName[name])
	end
	for id, reward in pairs(s.giftsById) do
		mappingRow("🆔 " .. id, "Gifts.ById." .. id, reward)
	end
	header("Adaugă gift (nume exact din TikFinity/relay sau ID numeric)")
	local defaultReward = s.rewards[1] or "SpeedBoost"
	inputRow("ex. Rose sau 5655", {
		{ "+ " .. defaultReward, GREEN, function(text)
			text = text:gsub("^%s+", ""):gsub("%s+$", "")
			if text == "" or text:find("%.") then
				return
			end
			local path = tonumber(text) and ("Gifts.ById." .. text) or ("Gifts.ByName." .. text)
			send("set", { path = path, value = defaultReward })
		end },
	})
	header("Recompense disponibile")
	local frame = rowFrame(44)
	label(frame, table.concat(s.rewards, ", "), { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 1, -4), TextWrapped = true, TextTruncate = Enum.TextTruncate.None })
end

TAB["Coadă"] = function(s)
	header("Adaugă / scoate manual")
	inputRow("Username Roblox", {
		{ "Adaugă", GREEN, function(text) send("queue.add", { robloxName = text }) end },
		{ "Scoate", RED, function(text) send("queue.remove", { robloxName = text }) end },
		{ "⭐ Prioritar", ACCENT, function(text) send("queue.priority", { robloxName = text }) end },
	})
	local clearText = os.clock() < confirmClearUntil and "Apasă din nou pentru confirmare" or "Golește coada"
	buttonsRow({
		{ clearText, RED, function()
			if os.clock() < confirmClearUntil then
				confirmClearUntil = 0
				send("queue.clear")
			else
				confirmClearUntil = os.clock() + 4
				render()
			end
		end },
	})
	header(string.format("Coada (%d)", s.queue.queuedTotal or 0))
	for _, item in ipairs(s.queue.queued or {}) do
		local frame = rowFrame()
		label(frame, string.format("#%d %s%s  (%s)", item.position, item.priority and "⭐ " or "", item.robloxName, item.tiktokName or ""), { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.66, -10, 1, 0) })
		button(frame, "⭐", ACCENT, function()
			send("queue.priority", { robloxName = item.robloxName })
		end, { Position = UDim2.new(0.68, 0, 0.12, 0), Size = UDim2.new(0.15, -4, 0.76, 0) })
		button(frame, "✖", RED, function()
			send("queue.remove", { robloxName = item.robloxName })
		end, { Position = UDim2.new(0.84, 0, 0.12, 0), Size = UDim2.new(0.16, -6, 0.76, 0) })
	end
	if #(s.queue.active or {}) > 0 then
		header("În cursa curentă")
		for _, item in ipairs(s.queue.active) do
			local frame = rowFrame(28)
			label(frame, "🏁 " .. item.robloxName, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0) })
		end
	end
end

TAB["Hărți"] = function(s)
	header("Hărți (activă / următoarea cursă)")
	for _, map in ipairs(s.maps) do
		local frame = rowFrame()
		label(frame, map.name, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.5, -10, 1, 0) })
		button(frame, map.enabled and "Activă" or "Oprită", map.enabled and GREEN or RED, function()
			send("set", { path = "Maps.List.@" .. map.id .. ".Enabled", value = not map.enabled })
		end, { Position = UDim2.new(0.5, 0, 0.12, 0), Size = UDim2.new(0.24, -4, 0.76, 0) })
		button(frame, s.nextMap == map.id and "✔ Următoarea" or "Următoarea", ACCENT, function()
			send("map.next", { mapId = map.id })
		end, { Position = UDim2.new(0.75, 0, 0.12, 0), Size = UDim2.new(0.25, -6, 0.76, 0) })
	end
	header("Mount-uri (activ / șansă pe roată)")
	for _, mount in ipairs(s.mounts) do
		local frame = rowFrame()
		label(frame, mount.icon .. " " .. mount.name, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.5, -10, 1, 0) })
		button(frame, mount.enabled and "Activ" or "Oprit", mount.enabled and GREEN or RED, function()
			send("set", { path = "Mounts.@" .. mount.id .. ".Enabled", value = not mount.enabled })
		end, { Position = UDim2.new(0.5, 0, 0.12, 0), Size = UDim2.new(0.2, -4, 0.76, 0) })
		local weight = mount.weight
		button(frame, "−", ROW:Lerp(Color3.new(1, 1, 1), 0.15), function()
			send("set", { path = "Mounts.@" .. mount.id .. ".Weight", value = math.max(0, weight - 1) })
		end, { Position = UDim2.new(0.71, 0, 0.12, 0), Size = UDim2.new(0.08, -2, 0.76, 0) })
		label(frame, "x" .. weight, { Position = UDim2.new(0.79, 0, 0, 0), Size = UDim2.new(0.12, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
		button(frame, "+", ROW:Lerp(Color3.new(1, 1, 1), 0.15), function()
			send("set", { path = "Mounts.@" .. mount.id .. ".Weight", value = weight + 1 })
		end, { Position = UDim2.new(0.91, 0, 0.12, 0), Size = UDim2.new(0.09, -6, 0.76, 0) })
	end
end

---------------------------------------------------------------------------
-- Fereastra
---------------------------------------------------------------------------
render = function()
	if not window.Visible then
		return
	end
	local scroll = content.CanvasPosition
	for _, child in ipairs(content:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	order = 0
	for _, b in ipairs(tabBar:GetChildren()) do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = b.Name == currentTab and ACCENT or ROW
		end
	end
	if not state then
		header("Se încarcă...")
		return
	end
	local ok, err = pcall(TAB[currentTab], state)
	if not ok then
		header("Eroare la afișare: " .. tostring(err))
	end
	content.CanvasPosition = scroll
end

local function layout()
	local view = workspace.CurrentCamera.ViewportSize
	if view.Y >= view.X then
		window.Position = UDim2.fromScale(0.03, 0.12)
		window.Size = UDim2.fromScale(0.94, 0.72)
	else
		window.Position = UDim2.fromScale(0.56, 0.08)
		window.Size = UDim2.fromScale(0.42, 0.84)
	end
end

local function setVisible(visible)
	window.Visible = visible
	if visible then
		send("state")
		render()
	end
end

local function build()
	gui = new("ScreenGui", { Name = "AdminPanel", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50 }, player:WaitForChild("PlayerGui"))
	if Config.Admin.ShowToggleButton then
		local toggle = button(gui, "⚙️", Color3.fromRGB(20, 20, 30), function()
			setVisible(not window.Visible)
		end, { Position = UDim2.new(0, 6, 1, -40), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 0.6, TextSize = 18 })
		toggle.Name = "Toggle"
	end
	window = new("Frame", { Name = "Window", BackgroundColor3 = BG, BackgroundTransparency = 0.04, Visible = false }, gui)
	corner(window, 12)
	new("UIStroke", { Thickness = 2, Color = ACCENT }, window)

	local title = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 }, window)
	label(title, "⚙️ Panou de administrare", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -60, 1, 0), Font = TITLE, TextSize = 20, TextColor3 = GOLD })
	button(title, "✕", RED, function()
		setVisible(false)
	end, { Position = UDim2.new(1, -40, 0, 4), Size = UDim2.fromOffset(32, 28) })

	tabBar = new("Frame", { Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, -16, 0, 30), BackgroundTransparency = 1 }, window)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, tabBar)
	for _, name in ipairs(TABS) do
		local b = button(tabBar, name, ROW, function()
			currentTab = name
			content.CanvasPosition = Vector2.zero
			render()
		end, { Size = UDim2.new(1 / #TABS, -4, 1, 0), TextSize = 12 })
		b.Name = name
	end

	content = new("ScrollingFrame", { Position = UDim2.fromOffset(8, 74), Size = UDim2.new(1, -16, 1, -112), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, window)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, content)
	new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 4) }, content)

	statusLabel = label(window, "", { Position = UDim2.new(0, 12, 1, -34), Size = UDim2.new(1, -24, 0, 28), TextWrapped = true })
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end

function AdminPanel.Start()
	-- așteaptă confirmarea serverului (IsAdmin); fără ea panoul nu există deloc
	if not player:GetAttribute("IsAdmin") then
		player:GetAttributeChangedSignal("IsAdmin"):Wait()
	end
	build()
	Remotes.AdminResult.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.state then
			state = payload.state
		end
		if payload.message then
			statusLabel.Text = (payload.ok and "✔ " or "✖ ") .. tostring(payload.message)
			statusLabel.TextColor3 = payload.ok and GREEN or RED
		end
		render()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Config.Admin.PanelHotkey then
			setVisible(not window.Visible)
		end
	end)
	-- reîmprospătare automată cât panoul e deschis
	task.spawn(function()
		while true do
			task.wait(3)
			if window.Visible and not UserInputService:GetFocusedTextBox() then
				send("state")
			end
		end
	end)
end

return AdminPanel
