--[[
	Validation  (ModuleScript)
	Locație: ReplicatedStorage > Shared > Validation

	Validări pure (fără apeluri de rețea) pentru datele care vin din exterior.
	Orice text din chatul TikTok este considerat NESIGUR până trece pe aici.
]]

local Validation = {}

--[[
	Reguli oficiale pentru username Roblox:
	  - 3..20 caractere
	  - doar litere, cifre și underscore
	  - maxim un underscore
	  - nu începe și nu se termină cu underscore
	Returnează: username curățat  SAU  nil, codEroare
]]
function Validation.normalizeRobloxUsername(raw)
	if type(raw) ~= "string" then
		return nil, "INVALID_TYPE"
	end
	if #raw > 64 then
		return nil, "INVALID_FORMAT"
	end

	local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
	name = name:gsub("^@", "") -- mulți scriu "@nume"

	if #name < 3 or #name > 20 then
		return nil, "INVALID_LENGTH"
	end
	if not name:match("^[%w_]+$") then
		return nil, "INVALID_CHARACTERS"
	end
	local _, underscores = name:gsub("_", "")
	if underscores > 1 then
		return nil, "INVALID_FORMAT"
	end
	if name:sub(1, 1) == "_" or name:sub(-1) == "_" then
		return nil, "INVALID_FORMAT"
	end
	return name
end

--[[
	ID-ul numeric TikTok (userId) – identificatorul STABIL al spectatorului.
	Uniqueid-ul (@handle) se poate schimba, de aceea legăm totul de userId.
	Îl tratăm ca string ca să evităm pierderea de precizie la numere mari.
]]
function Validation.normalizeTikTokUserId(raw)
	if type(raw) == "number" then
		raw = string.format("%.0f", raw)
	end
	if type(raw) ~= "string" then
		return nil, "INVALID_TIKTOK_ID"
	end
	if #raw < 1 or #raw > 32 or not raw:match("^%d+$") then
		return nil, "INVALID_TIKTOK_ID"
	end
	return raw
end

-- Textul afișat (nume TikTok) – curățat și scurtat, folosit doar pentru afișare.
function Validation.sanitizeDisplayText(raw, maxLen)
	maxLen = maxLen or 24
	if type(raw) ~= "string" then
		return ""
	end
	local text = raw:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if utf8.len(text) == nil then
		return "" -- UTF-8 invalid
	end
	if utf8.len(text) > maxLen then
		local cut = utf8.offset(text, maxLen + 1)
		text = text:sub(1, cut - 1) .. "…"
	end
	return text
end

--[[
	Extrage username-ul dintr-un comentariu de tip "!join NumeRoblox".
	commands: listă de comenzi acceptate (ex: {"!join", "!intra"})
	Returnează username-ul brut sau nil dacă mesajul nu e o comandă de înscriere.
]]
function Validation.parseJoinCommand(comment, commands)
	if type(comment) ~= "string" then
		return nil
	end
	local lowered = comment:lower()
	for _, cmd in ipairs(commands) do
		local c = cmd:lower()
		if lowered:sub(1, #c) == c then
			local rest = comment:sub(#c + 1)
			if rest == "" or rest:match("^%s") then
				local arg = rest:match("^%s*(%S+)")
				return arg
			end
		end
	end
	return nil
end

return Validation
