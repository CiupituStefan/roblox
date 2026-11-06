--[[
	Config  (ModuleScript)
	Locație: ReplicatedStorage > Shared > Config

	Configurația CENTRALĂ a jocului. Tot ce vrei să modifici fără să atingi logica
	se află aici. Panoul de administrare (Etapa 8) va putea suprascrie valorile
	la runtime, dar acestea sunt valorile implicite la pornirea serverului.

	ATENȚIE: modulul este în ReplicatedStorage, deci clienții îl pot citi.
	NU pune aici secrete (chei API, token-uri). Secretele se țin în
	Roblox Secrets Store și se citesc pe server cu HttpService:GetSecret().
]]

local Config = {}

---------------------------------------------------------------------------
-- CURSĂ
---------------------------------------------------------------------------
Config.Race = {
	MaxRacers = 12, -- câți concurenți intră într-o cursă
	MinRacers = 1, -- sub acest număr cursa nu pornește (se așteaptă înscrieri)
	BaseSpeed = 40, -- studs/secundă, IDENTICĂ pentru toți, indiferent de mount
	-- Mică variație aleatorie simetrică (±%) ca să nu ajungă toți la egalitate
	-- când nu există donații. Media este 0 => nimeni nu e avantajat. 0 = dezactivat.
	SpeedNoisePercent = 4,
	MaxSpeedMultiplier = 4.0, -- plafon de siguranță pentru boost-uri cumulate
	LobbyWaitSeconds = 15, -- cât se așteaptă înscrieri înainte de start
	GridHoldSeconds = 2, -- concurenții stau pe grilă înainte de countdown
	CountdownSeconds = 3,
	FinishGraceSeconds = 8, -- după câștigător, ceilalți mai au atâtea secunde să termine
	PodiumSeconds = 10,
	MaxRaceSeconds = 180, -- siguranță: cursa se încheie forțat după acest timp
	AutoLoop = true, -- ciclul de curse pornește automat la pornirea serverului
}

---------------------------------------------------------------------------
-- QUEUE / ÎNSCRIERI
---------------------------------------------------------------------------
Config.Queue = {
	MaxSize = 300, -- câte persoane pot aștepta în total
	SkipCreditTTLSeconds = 900, -- un Skip Queue cumpărat înainte de înscriere rămâne valabil 15 min
	VisibleInUI = 15, -- câte poziții din coadă se afișează pe ecran
}

Config.Registration = {
	Enabled = true,
	JoinCommands = { "!join", "!intra", "!race" }, -- comenzi în chatul TikTok
	PerUserCooldownSeconds = 8, -- anti-spam: o încercare la X secunde per cont TikTok
	MaxConcurrentLookups = 4, -- câte căutări Roblox simultan
}

---------------------------------------------------------------------------
-- BOOST-URI  (valoare, durată și efecte configurabile separat)
---------------------------------------------------------------------------
-- Kind:
--   "Multiplier" -> înmulțește viteza pe durata Duration
--   "Impulse"    -> avansează instant/rapid Distance studs pe traseu
--   "Flight"     -> zbor deasupra traseului + multiplicator
Config.Boosts = {
	SpeedBoost = { DisplayName = "Speed Boost", Kind = "Multiplier", Multiplier = 1.35, Duration = 4, Vfx = "SpeedLines", Sound = "Boost", AuraBonus = 0.5 },
	SuperSpeed = { DisplayName = "Super Speed", Kind = "Multiplier", Multiplier = 2.2, Duration = 3, Vfx = "SuperSpeed", Sound = "SuperBoost", AuraBonus = 1.5 },
	Turbo = { DisplayName = "Turbo", Kind = "Multiplier", Multiplier = 1.8, Duration = 2, Vfx = "TurboFlames", Sound = "Turbo", AuraBonus = 1.0 },
	RocketBoost = { DisplayName = "Rocket Boost", Kind = "Impulse", Distance = 60, ImpulseTime = 1.2, Vfx = "Rocket", Sound = "Rocket", AuraBonus = 1.2 },
	Jetpack = { DisplayName = "Jetpack", Kind = "Flight", Multiplier = 1.5, Duration = 5, FlightHeight = 14, Vfx = "Jetpack", Sound = "Jetpack", AuraBonus = 1.0 },
	LightningBoost = { DisplayName = "Lightning Boost", Kind = "Multiplier", Multiplier = 2.0, Duration = 2.5, Vfx = "Lightning", Sound = "Thunder", AuraBonus = 2.0 },
	TeleportDash = { DisplayName = "Teleport Dash", Kind = "Impulse", Distance = 45, ImpulseTime = 0.15, Vfx = "Teleport", Sound = "Teleport", AuraBonus = 0.8 },
}

-- Reguli generale pentru boost-uri
Config.BoostRules = {
	StackMode = "RefreshAndMax", -- "RefreshAndMax": același boost reîmprospătează durata; boost-uri diferite -> se ia max
	PerRacerCooldownSeconds = 0.5, -- anti-spam pentru evenimente foarte dese
	MaxQueuedBoostsPerRacer = 10, -- boost-uri în așteptare (dacă vin mai multe deodată)
}

---------------------------------------------------------------------------
-- GIFT-URI TIKTOK -> RECOMPENSE  (modificabil de tine)
---------------------------------------------------------------------------
-- Reward poate fi numele unui boost din Config.Boosts SAU "SkipQueue".
-- Potrivirea se face în ordinea: ById -> ByName -> ByCoins (praguri).
-- Numele exacte ale gift-urilor vin de la sursa de evenimente (TikFinity /
-- tiktok-live-connector). Dacă un gift nu se potrivește, verifică log-ul relay-ului
-- (Etapa 2) – acolo apar numele și ID-urile primite.
Config.Gifts = {
	ById = {
		-- [5655] = "SpeedBoost",  -- exemplu: ID-ul gift-ului "Rose"
	},
	ByName = {
		["Rose"] = "SpeedBoost", -- gift mic
		["TikTok"] = "SpeedBoost",
		["Finger Heart"] = "Turbo", -- gift mediu
		["Doughnut"] = "Jetpack", -- gift special
		["Hand Hearts"] = "LightningBoost",
		["Corgi"] = "RocketBoost",
		["Confetti"] = "TeleportDash",
		["Galaxy"] = "SuperSpeed", -- gift mare
		["Perfume"] = "SkipQueue", -- alt gift = Skip Queue
	},
	-- Fallback pe valoare (diamante/coins per bucată), de la cel mai mare prag la cel mai mic
	ByCoins = {
		{ MinCoins = 1000, Reward = "SuperSpeed" },
		{ MinCoins = 100, Reward = "RocketBoost" },
		{ MinCoins = 30, Reward = "Jetpack" },
		{ MinCoins = 5, Reward = "Turbo" },
		{ MinCoins = 1, Reward = "SpeedBoost" },
	},
	UseCoinFallback = true,
	MaxRepeatPerEvent = 20, -- un combo x99 nu declanșează 99 de boost-uri, maxim 20
	-- Mulțumire pe ecran pentru gift-urile care NU activează nimic (spectator care nu e în cursă)
	ThankNonRacers = true,
	-- true = gift-urile trimise în timpul countdown-ului sunt acceptate și aplicate la START
	AcceptDuringCountdown = false,
}

---------------------------------------------------------------------------
-- AURĂ (inspirată de transformările din anime, efecte originale)
---------------------------------------------------------------------------
-- Nivelul se alege după multiplicatorul de viteză curent (viteza / BaseSpeed).
Config.Aura = {
	Enabled = true,
	TransitionSpeed = 4, -- cât de repede se interpolează culoarea/mărimea (mai mare = mai rapid)
	BaseSize = 3.2, -- mărimea particulelor de aură la nivelul „Calm” (studs)
	BoostBonusWeight = 0.5, -- cât adaugă AuraBonus-ul unui boost activ la nivelul aurei
	LightningColor = Color3.fromRGB(150, 220, 255),
	-- Texturi încorporate în Roblox (nu necesită upload). Le poți înlocui cu
	-- "rbxassetid://ID" din Creator Store pentru un stil diferit.
	Textures = {
		Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
		Flame = "rbxasset://textures/particles/fire_main.dds",
		Spark = "rbxasset://textures/particles/sparkles_main.dds",
		Smoke = "rbxasset://textures/particles/smoke_main.dds",
		Shockwave = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
		Burst = "rbxasset://textures/particles/explosion01_core_main.dds",
	},
	Tiers = {
		{ Name = "Calm", MinMultiplier = 0, Color = Color3.fromRGB(170, 215, 255), Size = 1.0, Brightness = 1.0, Particles = 8, Lightning = false },
		{ Name = "Energie", MinMultiplier = 1.15, Color = Color3.fromRGB(80, 170, 255), Size = 1.35, Brightness = 2.0, Particles = 25, Lightning = false },
		{ Name = "Supernova", MinMultiplier = 1.6, Color = Color3.fromRGB(255, 215, 60), Size = 1.8, Brightness = 3.5, Particles = 55, Lightning = false },
		{ Name = "Divin", MinMultiplier = 2.3, Color = Color3.fromRGB(255, 240, 120), Size = 2.4, Brightness = 5.0, Particles = 90, Lightning = true },
	},
}

---------------------------------------------------------------------------
-- SUNETE
---------------------------------------------------------------------------
-- Pune ID-uri de sunete din Creator Store ("rbxassetid://123456") pe care ai
-- dreptul să le folosești. Un câmp gol = fără sunet (jocul merge oricum).
-- Câteva sunete încorporate în Roblox ("rbxasset://sounds/...") sunt folosite implicit.
Config.Sounds = {
	Volume = 0.6,
	CountdownBeep = "rbxasset://sounds/electronicpingshort.wav",
	Go = "rbxasset://sounds/electronicpingshort.wav",
	Finish = "",
	Winner = "", -- fanfară / voce „Avem un câștigător!” (încărcată de tine)
	Gift = "", -- la fiecare donație anunțată
	WheelTick = "rbxasset://sounds/clickfast.wav",
	WheelResult = "",
	Boost = "rbxasset://sounds/swoosh.wav",
	SuperBoost = "rbxasset://sounds/swoosh.wav",
	Turbo = "rbxasset://sounds/swoosh.wav",
	Rocket = "",
	Jetpack = "",
	Thunder = "",
	Teleport = "",
	AuraPowerUp = "", -- la trecerea în nivelul „Divin”
}

---------------------------------------------------------------------------
-- MOUNT-URI (modele originale construite procedural în Etapa 3)
---------------------------------------------------------------------------
-- Enabled poate fi schimbat din panoul de admin. Weight = șansa pe roată.
-- Mount-ul NU influențează viteza (doar aspect + animație).
Config.Mounts = {
	{ Id = "BlockPig", DisplayName = "Porcul cu Morcov", Icon = "🐷", Color = Color3.fromRGB(240, 150, 170), Weight = 1, Enabled = true },
	{ Id = "ClassicKart", DisplayName = "Kart Clasic", Icon = "🏎️", Color = Color3.fromRGB(225, 50, 50), Weight = 1, Enabled = true },
	{ Id = "BirdKart", DisplayName = "Kart Pasăre Furioasă", Icon = "🐦", Color = Color3.fromRGB(200, 30, 40), Weight = 1, Enabled = true },
	{ Id = "Plane", DisplayName = "Avion", Icon = "✈️", Color = Color3.fromRGB(70, 140, 230), Weight = 1, Enabled = true },
	{ Id = "Horse", DisplayName = "Cal", Icon = "🐴", Color = Color3.fromRGB(140, 90, 50), Weight = 1, Enabled = true },
	{ Id = "Rhino", DisplayName = "Rinocer", Icon = "🦏", Color = Color3.fromRGB(130, 130, 140), Weight = 1, Enabled = true },
	{ Id = "Crocodile", DisplayName = "Crocodil", Icon = "🐊", Color = Color3.fromRGB(60, 140, 60), Weight = 1, Enabled = true },
	{ Id = "RubberDuck", DisplayName = "Rața Gigantică", Icon = "🦆", Color = Color3.fromRGB(255, 215, 40), Weight = 1, Enabled = true },
	{ Id = "Capybara", DisplayName = "Capybara Zen", Icon = "🍊", Color = Color3.fromRGB(170, 120, 70), Weight = 1, Enabled = true },
	{ Id = "ShoppingCart", DisplayName = "Cărucior de Cumpărături", Icon = "🛒", Color = Color3.fromRGB(150, 160, 175), Weight = 1, Enabled = true },
	{ Id = "TurboToilet", DisplayName = "Toaleta Turbo", Icon = "🚽", Color = Color3.fromRGB(235, 240, 250), Weight = 1, Enabled = true },
	{ Id = "Rocket", DisplayName = "Racheta de Carton", Icon = "🚀", Color = Color3.fromRGB(255, 120, 40), Weight = 1, Enabled = true },
	{ Id = "Snail", DisplayName = "Melcul Nitro", Icon = "🐌", Color = Color3.fromRGB(150, 200, 90), Weight = 1, Enabled = true },
	{ Id = "Banana", DisplayName = "Banana pe Roți", Icon = "🍌", Color = Color3.fromRGB(250, 225, 60), Weight = 1, Enabled = true },
	{ Id = "FlyingCouch", DisplayName = "Canapeaua Zburătoare", Icon = "🛋️", Color = Color3.fromRGB(140, 70, 190), Weight = 1, Enabled = true },
	{ Id = "Shark", DisplayName = "Rechinul pe Skateboard", Icon = "🦈", Color = Color3.fromRGB(90, 130, 175), Weight = 1, Enabled = true },
}

---------------------------------------------------------------------------
-- ROATA NOROCULUI (alegerea mount-urilor)
---------------------------------------------------------------------------
Config.Wheel = {
	AvoidDuplicates = true, -- mount-uri diferite cât timp există destule
	IntroSeconds = 1.5, -- roata apare pe ecran
	PerRacerSeconds = 2.5, -- timpul maxim de rotire + afișare per concurent
	MinPerRacerSeconds = 1.0, -- cu mulți concurenți se rotește mai repede...
	MaxTotalSeconds = 24, -- ...ca toată roata să nu depășească acest timp
	SpinFraction = 0.7, -- din timpul per concurent: 70% rotire, 30% rezultat
	OutroSeconds = 1.5,
	PrepareTimeoutSeconds = 25, -- avatarurile neîncărcate până atunci sunt eliminate din cursă
}

---------------------------------------------------------------------------
-- INTERFAȚĂ (HUD) ȘI CAMERĂ
---------------------------------------------------------------------------
Config.UI = {
	LeaderboardRows = 8, -- câte rânduri în clasamentul live
	QueueRows = 8, -- câte persoane din coadă se văd pe ecran
	FeedSize = 5, -- câte anunțuri simultan
	FeedSeconds = 7, -- cât stă un anunț pe ecran
	VerifyCodeSeconds = 25, -- cât stă pe ecran codul de verificare !verify
	SpeedUnitFactor = 3, -- viteza afișată = studs/s x factor (40 studs/s => 120 km/h)
	SpeedUnit = "km/h",
	ShotSeconds = 7, -- camera schimbă unghiul la fiecare X secunde în cursă
	FocusSeconds = 3, -- camera se uită la cine primește un boost
	FinishCamDistance = 110, -- camera trece la linia de finish când liderul e la X studs de ea
}

---------------------------------------------------------------------------
-- TRANSMISIE
---------------------------------------------------------------------------
Config.Stream = {
	-- Personajul tău (streamerul) nu apare în joc: clientul tău e doar „camera”.
	SpawnStreamerCharacter = false,
}

---------------------------------------------------------------------------
-- HĂRȚI (fără obstacole pe traseu, doar decor în afara pistei)
---------------------------------------------------------------------------
Config.Maps = {
	Rotation = "Sequential", -- "Sequential" sau "Random" (Random nu repetă harta anterioară)
	List = {
		{ Id = "CandyLand", DisplayName = "Țara Bomboanelor", Enabled = true },
		{ Id = "VolcanoRun", DisplayName = "Vulcanul Nebun", Enabled = true },
		{ Id = "NeonCity", DisplayName = "Orașul Neon", Enabled = true },
		{ Id = "JungleLoop", DisplayName = "Jungla Sălbatică", Enabled = true },
		{ Id = "SnowPeaks", DisplayName = "Piscurile Înghețate", Enabled = true },
		{ Id = "SpaceStation", DisplayName = "Stația Spațială", Enabled = true },
	},
	TrackWidth = 70, -- lățimea pistei în studs (suficient de lată pentru 12+ concurenți)
	TargetTrackLength = 2000, -- lungimea traseului (la viteza de bază 40 => ~50s de cursă)
	GridPerRow = 6, -- câți concurenți pe un rând la start
	GridRowSpacing = 13, -- distanța dintre rânduri
	FinishMargin = 40, -- linia de finish este cu atâția studs înainte de capătul pistei
	DecorDensity = 1.0, -- 0.5 = jumătate din decoruri (pentru PC-uri slabe), 2 = dublu
}

---------------------------------------------------------------------------
-- BRIDGE (serviciul extern care primește evenimentele TikTok) – Etapa 2
---------------------------------------------------------------------------
Config.Bridge = {
	Enabled = true, -- false = jocul nu contactează relay-ul (ex. teste offline)
	-- URL-ul public HTTPS al relay-ului (Cloudflare Tunnel / hosting), FĂRĂ "/" la final
	BaseUrl = "https://YOUR-RELAY-DOMAIN.example.com",
	PollIntervalSeconds = 1.0, -- HttpService permite max 500 cereri/minut; 1s = 60/min
	BatchLimit = 200, -- câte evenimente pe cerere (maxim 200; cu rafale => până la ~1300 evenimente/s)
	SecretName = "TIKTOK_RELAY_KEY", -- numele secretului din Roblox Secrets Store
	FailureBackoff = { 1, 2, 4, 8, 15, 30 }, -- secunde de așteptare după erori consecutive
	DedupeMemory = 3000, -- câte ID-uri de evenimente procesate ținem minte
}

---------------------------------------------------------------------------
-- ADMIN
---------------------------------------------------------------------------
Config.Admin = {
	-- Roblox UserId-urile care au acces la panoul de administrare.
	-- Proprietarul jocului (game.CreatorId) are acces automat dacă jocul e pe contul tău.
	UserIds = {
		-- 123456789,
	},
	GroupMinRank = 255, -- dacă jocul e al unui grup: rangul minim pentru admin (255 = proprietar)
	AllowAllInStudio = true, -- în Studio oricine e admin (pentru teste)
	PersistSettings = true, -- modificările din panou se păstrează și după repornirea serverului (DataStore)
	PanelHotkey = Enum.KeyCode.F2, -- tasta care arată/ascunde panoul
	ShowToggleButton = true, -- butonul ⚙️ mic din colț (ascunde-l dacă panoul apare pe stream)
}

---------------------------------------------------------------------------
-- DEBUG / TESTARE ÎN STUDIO
---------------------------------------------------------------------------
Config.Debug = {
	RunSelfTests = true, -- rulează testele automate la pornire (doar în Studio)
	FakeJoinsInStudio = true, -- simulează înscrieri în Studio (fără TikTok)
	-- Username-uri Roblox reale folosite pentru simulare. Adaugă și username-ul tău.
	FakeUsernames = { "Roblox", "builderman", "qz9NoSuchUser7k", "nume invalid!" },
	VerboseLogs = true,
	-- Etapa 2: pornește o „cursă de test” în Studio (fără mișcare) ca să poți testa
	-- gift-urile din simulator. Va fi înlocuită de RaceService în Etapa 5.
	ForceMap = nil, -- ex. "NeonCity": cursele folosesc mereu această hartă (teste)
	AllowLoadTestLive = false, -- testul de încărcare din panoul de admin merge doar în Studio, dacă e false
	HealthLogMinutes = 5, -- la câte minute scrie serverul o linie de sănătate în Output
}

return Config
