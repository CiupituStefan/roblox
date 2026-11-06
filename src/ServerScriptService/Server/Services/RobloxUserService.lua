--[[
	RobloxUserService  (ModuleScript)
	Locație: ServerScriptService > Server > Services > RobloxUserService

	Identifică un cont Roblox după username și îi preia avatarul ORIGINAL,
	folosind exclusiv API-urile oficiale Roblox:
	  * Players:GetUserIdFromNameAsync          -> username -> UserId
	  * UserService:GetUserInfosByUserIdsAsync  -> username canonic + DisplayName
	  * Players:GetHumanoidDescriptionFromUserId -> haine, accesorii, corp, culori, animații
	  * Players:CreateHumanoidModelFromDescription -> modelul R15 al avatarului
	  * rbxthumb://type=AvatarHeadShot          -> poza avatarului pentru UI

	UserId este identificatorul permanent; username-ul este folosit doar la căutare
	(un utilizator își poate schimba numele, UserId rămâne același).

	Include: cache cu TTL, cache negativ pentru conturi inexistente, deduplicarea
	căutărilor simultane pentru același nume, limită de concurență și retry
	cu backoff pentru erori temporare.
]]

local Players = game:GetService("Players")
local UserService = game:GetService("UserService")

local RobloxUserService = {}

local POSITIVE_TTL = 10 * 60 -- un cont găsit rămâne în cache 10 minute
local NEGATIVE_TTL = 60 -- un cont inexistent: 1 minut
local RETRY_DELAYS = { 0.5, 1.5, 3 }

RobloxUserService.Errors = {
	USER_NOT_FOUND = "USER_NOT_FOUND",
	LOOKUP_FAILED = "LOOKUP_FAILED", -- eroare temporară Roblox (rețea / rate limit)
	AVATAR_FAILED = "AVATAR_FAILED",
}
local E = RobloxUserService.Errors

local maxConcurrent = 4
local activeLookups = 0
local nameCache = {} -- lowerName -> { expires, result?, err? }
local inflight = {} -- lowerName -> { coroutine }
local descCache = {} -- userId -> { expires, description }

function RobloxUserService.SetMaxConcurrent(n)
	maxConcurrent = math.max(1, n)
end

local function log(...)
	print("[RobloxUserService]", ...)
end

local function isNotFoundError(message)
	message = string.lower(tostring(message))
	return message:find("unknown user", 1, true) ~= nil
		or message:find("not found", 1, true) ~= nil
		or message:find("does not exist", 1, true) ~= nil
		or message:find("invalid username", 1, true) ~= nil
end

-- Rulează fn cu retry. stopIf(err) -> true = eroare definitivă, nu mai încercăm.
local function withRetry(fn, stopIf)
	local lastErr
	for attempt = 1, #RETRY_DELAYS + 1 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if stopIf and stopIf(result) then
			break
		end
		if attempt <= #RETRY_DELAYS then
			task.wait(RETRY_DELAYS[attempt])
		end
	end
	return false, lastErr
end

local function acquireSlot()
	while activeLookups >= maxConcurrent do
		task.wait(0.1)
	end
	activeLookups += 1
end

local function releaseSlot()
	activeLookups -= 1
end

local function doResolve(username)
	-- 1) username -> UserId
	local ok, userIdOrErr = withRetry(function()
		return Players:GetUserIdFromNameAsync(username)
	end, isNotFoundError)
	if not ok then
		if isNotFoundError(userIdOrErr) then
			return nil, E.USER_NOT_FOUND
		end
		log("GetUserIdFromNameAsync a eșuat pentru", username, "-", userIdOrErr)
		-- Roblox aruncă eroare și pentru conturi inexistente cu mesaje variabile;
		-- dacă după toate încercările tot nu merge, tratăm ca „negăsit” doar dacă
		-- mesajul o spune, altfel ca eroare temporară.
		return nil, E.LOOKUP_FAILED
	end
	local userId = userIdOrErr
	if type(userId) ~= "number" or userId <= 0 then
		return nil, E.USER_NOT_FOUND
	end

	-- 2) username canonic + display name (nu folosim textul din chat)
	local canonicalName, displayName = username, username
	local infoOk, infos = withRetry(function()
		return UserService:GetUserInfosByUserIdsAsync({ userId })
	end)
	if infoOk and infos and infos[1] then
		canonicalName = infos[1].Username or canonicalName
		displayName = infos[1].DisplayName or canonicalName
	else
		local nameOk, name = withRetry(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if nameOk and name then
			canonicalName, displayName = name, name
		end
	end

	-- 3) avatarul original (HumanoidDescription)
	local descOk, descOrErr = withRetry(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if not descOk or typeof(descOrErr) ~= "Instance" then
		log("Avatarul nu a putut fi încărcat pentru", canonicalName, userId, "-", descOrErr)
		return nil, E.AVATAR_FAILED
	end

	descCache[userId] = { expires = os.clock() + POSITIVE_TTL, description = descOrErr }
	return {
		userId = userId,
		username = canonicalName,
		displayName = displayName,
		description = descOrErr,
	}
end

local function cloneResult(result)
	return {
		userId = result.userId,
		username = result.username,
		displayName = result.displayName,
		description = result.description:Clone(),
	}
end

--[[
	Rezolvă un username (deja validat ca format) într-un cont Roblox + avatar.
	Yield-uiește. Returnează: result  SAU  nil, errorCode
	result = { userId, username, displayName, description: HumanoidDescription }
]]
function RobloxUserService.ResolveAsync(username)
	local key = string.lower(username)
	local now = os.clock()

	local cached = nameCache[key]
	if cached and cached.expires > now then
		if cached.result then
			return cloneResult(cached.result)
		end
		return nil, cached.err
	end

	-- Dacă altcineva caută deja același nume, așteptăm rezultatul lui.
	if inflight[key] then
		table.insert(inflight[key], coroutine.running())
		local result, err = coroutine.yield()
		if result then
			return cloneResult(result)
		end
		return nil, err
	end

	inflight[key] = {}
	acquireSlot()
	local okCall, result, err = pcall(doResolve, username)
	releaseSlot()
	if not okCall then
		log("Eroare neașteptată:", result)
		result, err = nil, E.LOOKUP_FAILED
	end

	if result then
		nameCache[key] = { expires = os.clock() + POSITIVE_TTL, result = result }
	elseif err == E.USER_NOT_FOUND then
		nameCache[key] = { expires = os.clock() + NEGATIVE_TTL, err = err }
	end
	-- LOOKUP_FAILED / AVATAR_FAILED nu se pun în cache: se poate reîncerca imediat

	local waiters = inflight[key]
	inflight[key] = nil
	for _, thread in ipairs(waiters) do
		task.spawn(thread, result, err)
	end

	if result then
		return cloneResult(result)
	end
	return nil, err
end

--[[
	Avatarul original după UserId (identificatorul permanent). Folosit la
	construirea concurentului: nu mai depinde de username. Returnează o clonă
	HumanoidDescription sau nil, err.
]]
function RobloxUserService.GetDescriptionAsync(userId)
	local cached = descCache[userId]
	if cached and cached.expires > os.clock() then
		return cached.description:Clone()
	end
	acquireSlot()
	local ok, descOrErr = withRetry(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	releaseSlot()
	if not ok or typeof(descOrErr) ~= "Instance" then
		log("GetHumanoidDescriptionFromUserId a eșuat pentru", userId, "-", descOrErr)
		return nil, E.AVATAR_FAILED
	end
	descCache[userId] = { expires = os.clock() + POSITIVE_TTL, description = descOrErr }
	return descOrErr:Clone()
end

--[[
	Construiește modelul R15 al avatarului original (folosit în Etapa 3,
	când avatarul e pus pe mount). Returnează Model sau nil, err.
]]
function RobloxUserService.CreateAvatarModelAsync(description, modelName)
	local ok, modelOrErr = withRetry(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		log("CreateHumanoidModelFromDescription a eșuat:", modelOrErr)
		return nil, E.AVATAR_FAILED
	end
	modelOrErr.Name = modelName or "Avatar"
	return modelOrErr
end

function RobloxUserService.GetHeadshotImage(userId, size)
	size = size or 150
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=%d&h=%d", userId, size, size)
end

-- Curăță intrările expirate și limitează mărimea cache-ului (LIVE-uri de ore întregi).
function RobloxUserService.Prune(maxEntries)
	maxEntries = maxEntries or 2000
	local now = os.clock()
	local function prune(cache)
		local count = 0
		for key, item in pairs(cache) do
			if item.expires <= now then
				cache[key] = nil
			else
				count += 1
			end
		end
		if count > maxEntries then
			table.clear(cache) -- foarte rar: e mai simplu să pornim de la zero
		end
	end
	prune(nameCache)
	prune(descCache)
end

function RobloxUserService.ClearCache()
	table.clear(nameCache)
	table.clear(descCache)
end

return RobloxUserService
