--[[
	MountPicker  (ModuleScript)
	Locație: ServerScriptService > Server > Services > MountPicker

	Alegerea aleatorie, ponderată, a mount-urilor (logică pură, testabilă).
	Serverul decide rezultatul; roata de pe ecran doar îl ANIMEAZĂ.
	Mount-ul nu influențează viteza (doar aspectul și animația).
]]

local MountPicker = {}

function MountPicker.enabledMounts(mounts)
	local list = {}
	for _, mount in ipairs(mounts) do
		if mount.Enabled ~= false and (mount.Weight or 1) > 0 then
			table.insert(list, mount)
		end
	end
	return list
end

local function weightedIndex(list, rng)
	local total = 0
	for _, mount in ipairs(list) do
		total += mount.Weight or 1
	end
	local roll = rng:NextNumber() * total
	for index, mount in ipairs(list) do
		roll -= mount.Weight or 1
		if roll <= 0 then
			return index
		end
	end
	return #list
end

--[[
	mounts          : Config.Mounts
	count           : câți concurenți
	rng             : Random
	avoidDuplicates : true = mount-uri diferite cât timp ajung (apoi se reia lista)
	Returnează: { mountId, ... } (câte unul per concurent)
]]
function MountPicker.pick(mounts, count, rng, avoidDuplicates)
	local enabled = MountPicker.enabledMounts(mounts)
	assert(#enabled > 0, "Niciun mount activ în Config.Mounts")
	local result = {}
	local pool = table.clone(enabled)
	for _ = 1, count do
		if avoidDuplicates then
			if #pool == 0 then
				pool = table.clone(enabled)
			end
			local index = weightedIndex(pool, rng)
			table.insert(result, pool[index].Id)
			table.remove(pool, index)
		else
			table.insert(result, enabled[weightedIndex(enabled, rng)].Id)
		end
	end
	return result
end

function MountPicker.findById(mounts, id)
	for _, mount in ipairs(mounts) do
		if mount.Id == id then
			return mount
		end
	end
	return nil
end

return MountPicker
