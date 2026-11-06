--[[
	MapLayouts  (ModuleScript)
	Locație: ServerScriptService > Server > Services > Maps > MapLayouts

	Punctele de control ale fiecărui traseu (X, înălțime, Z). Traseul este o
	curbă netedă prin aceste puncte, scalată automat la Config.Maps.TargetTrackLength.

	Toate traseele au fost verificate (script de analiză):
	  * lungime ~2000 studs după scalare
	  * raza minimă a virajelor >= 56 studs (pistă lată de 70 -> fără colțuri)
	  * porțiunile ne-vecine ale traseului sunt la > 230 studs una de alta
	  * pantă maximă < 5°
	Dacă modifici punctele, păstrează distanțe de ~200-300 studs între ele.
]]

local V = Vector3.new

return {
	CandyLand = { V(0, 0, 0), V(0, 0, -260), V(120, 4, -480), V(330, 8, -560), V(520, 6, -450), V(560, 2, -220), V(720, 0, -60), V(930, 4, -120), V(1000, 6, -360), V(900, 4, -580) },
	VolcanoRun = { V(0, 0, 0), V(0, 0, -250), V(-150, 6, -480), V(-420, 14, -560), V(-680, 20, -460), V(-760, 24, -200), V(-640, 20, 40), V(-400, 12, 120), V(-260, 6, 330), V(-340, 2, 560) },
	NeonCity = { V(0, 0, 0), V(0, 0, -280), V(70, 0, -430), V(260, 0, -470), V(420, 0, -450), V(480, 0, -320), V(480, 0, -130), V(580, 0, 0), V(760, 0, 10), V(840, 0, -130), V(830, 0, -400) },
	JungleLoop = { V(0, 0, 0), V(-40, 6, -240), V(80, 16, -440), V(300, 10, -500), V(420, 22, -680), V(640, 14, -700), V(760, 4, -520), V(700, 10, -300), V(840, 18, -120), V(1060, 8, -160) },
	SnowPeaks = { V(0, 60, 0), V(0, 56, -240), V(150, 50, -410), V(100, 42, -620), V(-130, 34, -720), V(-300, 26, -570), V(-300, 20, -340), V(-420, 12, -220), V(-620, 6, -290), V(-700, 0, -540) },
	SpaceStation = { V(0, 40, 0), V(0, 46, -260), V(160, 60, -460), V(400, 52, -500), V(560, 40, -360), V(520, 30, -140), V(660, 36, 60), V(900, 50, 60), V(1000, 44, -180), V(900, 36, -400) },
}
