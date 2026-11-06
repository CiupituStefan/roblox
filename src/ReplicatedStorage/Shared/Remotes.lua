--[[
	Remotes  (ModuleScript)
	Locație: ReplicatedStorage > Shared > Remotes

	Creează (pe server) sau găsește (pe client) toate RemoteEvent/RemoteFunction.
	Astfel nu trebuie create manual în Studio și numele sunt într-un singur loc.

	REGULĂ DE SECURITATE: clienții NU pot trimite nimic care schimbă viteza,
	boost-uri sau coada. Singurul remote client->server cu efect este
	AdminCommand, iar serverul verifică de fiecare dată dacă expeditorul e admin.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	"StateUpdate", -- server -> clienți: snapshot coadă + cursă
	"Announce", -- server -> clienți: anunțuri (înscrieri, donații, boost-uri)
	"RaceEvent", -- server -> clienți: start, countdown, finish, podium (Etapa 5)
	"BoostFx", -- server -> clienți: efecte vizuale boost/aură (Etapa 6)
	"AdminCommand", -- client (admin) -> server: comenzi panou admin (validate pe server)
	"AdminResult", -- server -> client admin: răspuns la comandă + starea panoului
	"ConfigSync", -- server -> clienți: setări modificate din panoul de admin
}

local FUNCTIONS = {
	"GetState", -- client -> server: cere snapshot-ul complet (la intrare)
}

local Remotes = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(EVENTS) do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	end
	for _, name in ipairs(FUNCTIONS) do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	end
else
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	for _, name in ipairs(EVENTS) do
		Remotes[name] = folder:WaitForChild(name)
	end
	for _, name in ipairs(FUNCTIONS) do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes
