--[[
	MountFactory  (ModuleScript)
	Locație: ServerScriptService > Server > Services > MountFactory

	Construiește mount-urile (o singură dată per tip, ca șablon în
	ServerStorage > MountTemplates) și returnează clone pentru fiecare concurent.

	Modele proprii (opțional): pune un Model în ServerStorage > CustomMounts cu
	numele egal cu Id-ul din Config.Mounts. Trebuie să respecte convenția:
	  * Root  (Part ANCORAT, PrimaryPart, la nivelul solului, fața spre -Z)
	  * Body  (Part legat de Root, de ex. cu Motor6D "Anim_Body")
	  * Body > Seat (Attachment unde stă avatarul)
	  * atribut MountStyle: Walker | Wheeled | Flyer | Crawler | Bouncer
	  * restul pieselor neancorate, sudate de Body
	Modelul propriu are prioritate față de cel procedural.
]]

local ServerStorage = game:GetService("ServerStorage")

local Builder = require(script.Parent:WaitForChild("Mounts"):WaitForChild("Builder"))
local Designs = require(script.Parent:WaitForChild("Mounts"):WaitForChild("Designs"))

local MountFactory = {}
MountFactory.__index = MountFactory

MountFactory.Styles = { Walker = true, Wheeled = true, Flyer = true, Crawler = true, Bouncer = true }

function MountFactory.new()
	local self = setmetatable({}, MountFactory)
	self._templates = ServerStorage:FindFirstChild("MountTemplates")
	if not self._templates then
		self._templates = Instance.new("Folder")
		self._templates.Name = "MountTemplates"
		self._templates.Parent = ServerStorage
	end
	return self
end

-- Verifică dacă un model respectă convenția. Returnează true sau false, motiv.
function MountFactory.Validate(model)
	if not model or not model:IsA("Model") then
		return false, "nu este Model"
	end
	local root = model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		return false, "lipsește Root"
	end
	if not root.Anchored then
		return false, "Root trebuie să fie ancorat"
	end
	if model.PrimaryPart ~= root then
		return false, "PrimaryPart trebuie să fie Root"
	end
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return false, "lipsește Body"
	end
	local seat = body:FindFirstChild("Seat")
	if not (seat and seat:IsA("Attachment")) then
		return false, "lipsește Body > Seat (Attachment)"
	end
	if not MountFactory.Styles[model:GetAttribute("MountStyle")] then
		return false, "MountStyle invalid: " .. tostring(model:GetAttribute("MountStyle"))
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root and d.Anchored then
			return false, "piesa " .. d:GetFullName() .. " este ancorată (doar Root poate fi)"
		end
	end
	return true
end

local function prepareCustom(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
end

function MountFactory:_buildTemplate(id)
	local custom = ServerStorage:FindFirstChild("CustomMounts")
	custom = custom and custom:FindFirstChild(id)
	if custom then
		local model = custom:Clone()
		prepareCustom(model)
		local ok, why = MountFactory.Validate(model)
		if ok then
			return model
		end
		warn(string.format("[MountFactory] Modelul propriu %s este invalid (%s); folosesc varianta procedurală", id, why))
		model:Destroy()
	end

	local design = Designs[id]
	if not design then
		return nil, "Nu există design pentru mount-ul " .. tostring(id)
	end
	local ok, modelOrErr = pcall(design, Builder.new(id))
	if not ok then
		return nil, "Eroare la construirea " .. id .. ": " .. tostring(modelOrErr)
	end
	local valid, why = MountFactory.Validate(modelOrErr)
	if not valid then
		modelOrErr:Destroy()
		return nil, id .. " invalid: " .. why
	end
	return modelOrErr
end

function MountFactory:GetTemplate(id)
	local template = self._templates:FindFirstChild(id)
	if template then
		return template
	end
	local model, err = self:_buildTemplate(id)
	if not model then
		return nil, err
	end
	model.Name = id
	model.Parent = self._templates
	return model
end

-- Returnează o clonă gata de folosit (nepoziționată) sau nil, eroare.
function MountFactory:Create(id)
	local template, err = self:GetTemplate(id)
	if not template then
		return nil, err
	end
	local clone = template:Clone()
	clone:SetAttribute("MountId", id)
	return clone
end

-- Construiește din timp toate șabloanele (la pornirea serverului). Returnează lista de erori.
function MountFactory:PrebuildAll(mounts)
	local errors = {}
	for _, mount in ipairs(mounts) do
		local ok, err = self:GetTemplate(mount.Id)
		if not ok then
			table.insert(errors, err)
		end
	end
	return errors
end

return MountFactory
