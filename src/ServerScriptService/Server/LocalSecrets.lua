--[[
	LocalSecrets  (ModuleScript)
	Locație: ServerScriptService > Server > LocalSecrets

	DOAR PENTRU TESTE ÎN STUDIO, dacă Roblox Secrets Store nu e disponibil în Studio.
	Este folosit numai când RunService:IsStudio() == true. ServerScriptService nu
	ajunge niciodată la clienți, dar cheia rămâne salvată în fișierul jocului:
	pentru LIVE folosește Secrets Store și lasă câmpul gol aici.
]]

return {
	TIKTOK_RELAY_KEY = "", -- lipește aici RELAY_KEY doar pentru teste locale
}
