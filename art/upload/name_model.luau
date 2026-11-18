-- Names a pulled art model and writes it into the repo (art/upload/pull_models.py runs this).
--   lune run art/upload/name_model.luau IN.rbxm SetName
-- IN is rbxfix.py's output (Lune-readable, ids kept). Writes art/models/<SetName>.rbxm (the one Model,
-- renamed to SetName, as Rojo maps it under ReplicatedStorage.Art) and art/models/<setname>_meshids.json
-- (each MeshPart's path inside the set -> mesh id; SurfaceAppearance maps under "<path>#maps").
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local src, set = process.args[1], process.args[2]
assert(src and set, "usage: name_model.luau IN.rbxm SetName")
local top = roblox.deserializeModel(fs.readFile(src))
assert(#top == 1 and top[1]:IsA("Model"), src .. " should hold exactly one Model")
local model = top[1]
model.Name = set

local function num(s: string?): number
	return tonumber(string.match(s or "", "(%d+)$") or "0") :: number
end

-- Blender's duplicate-name suffix (".001") rides along on some sets' mesh names; the game looks pieces up
-- by the plain name, as Studio's 3D import names them, so it comes off (a clash would be a real error)
for _, d in model:GetDescendants() do
	local plain = string.gsub(d.Name, "%.%d%d%d$", "")
	if plain ~= d.Name then
		local clash = d.Parent and d.Parent:FindFirstChild(plain)
		assert(clash == nil, set .. ": both " .. d.Name .. " and " .. plain)
		d.Name = plain
	end
end

local ids, missing = {}, 0
for _, d in model:GetDescendants() do
	local rel = string.sub(d:GetFullName(), #model:GetFullName() + 2)
	if d:IsA("MeshPart") then
		local id = num(d.MeshId)
		if id == 0 then
			missing += 1
		end
		ids[rel] = id
	elseif d:IsA("SurfaceAppearance") then
		ids[rel .. "#maps"] = { num(d.ColorMap), num(d.NormalMap), num(d.RoughnessMap), num(d.MetalnessMap) }
	end
end
assert(missing == 0, set .. ": " .. missing .. " MeshParts have no mesh id")
fs.writeFile("art/models/" .. set .. ".rbxm", roblox.serializeModel({ model }))
local keys = {}
for k in ids do
	table.insert(keys, k)
end
table.sort(keys)
local lines = {}
for _, k in keys do
	local v = ids[k]
	local text = if type(v) == "table"
		then "[" .. string.format("%d, %d, %d, %d", v[1], v[2], v[3], v[4]) .. "]"
		else string.format("%d", v)
	table.insert(lines, string.format(' "%s": %s', k, text))
end
fs.writeFile("art/models/" .. string.lower(set) .. "_meshids.json", "{\n" .. table.concat(lines, ",\n") .. "\n}\n")
local n = 0
for _ in ids do
	n += 1
end
print(set, n, "entries")
