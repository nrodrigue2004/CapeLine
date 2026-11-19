-- placements.luau (fix-models, 2026-11-19): every MeshPart of a few assemblies as the GAME places it, for the
-- before/after renders (art/blender/fitshow.py). It runs the real code from a built place on tests/uisim.luau's
-- stand-ins (WorldFx's bosses, NpcRig's shell rigs, LookKit's kits, HqMeshes, SetPieceMeshes, CityProps), then
-- writes each part's mesh name, set, CFrame (12 numbers) and Size. fitshow.py draws each mesh from our FBX the way
-- Roblox's import stores it (turned 180 degrees about y, art/models/meshturns.json) at that CFrame, so the render
-- is what Studio shows. Run from the repo root (once per place: the build without the fix gives "before"):
--   ~/tools/lune run art/fit/placements.luau build/Capeline.rbxl build/fit/after.json
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Config = require("../../src/config")
local UiSim = require("../../tests/uisim")

local placePath, outPath = process.args[1], process.args[2]
local place = roblox.deserializePlace(fs.readFile(placePath))
local sim = UiSim.new(UiSim.load(place), { name = "PC", w = 1920, h = 1080, top = 36, left = 0, right = 0, bottom = 0 })
local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3

local groups = {}
local function grab(name: string, root: any, extra: { any }?, prefix: string?)
	local list = {}
	local function add(p: any)
		if p:IsA("MeshPart") then
			local set = p:GetAttribute("MeshSet")
			local cf = p.CFrame
			local c = { cf:GetComponents() }
			table.insert(list, {
				name = (prefix or "") .. p.Name,
				set = set,
				cf = c,
				size = { p.Size.X, p.Size.Y, p.Size.Z },
				color = { p.Color.R, p.Color.G, p.Color.B },
				neon = p.Material == roblox.Enum.Material.Neon,
				maps = p:FindFirstChildOfClass("SurfaceAppearance") ~= nil,
			})
		end
	end
	for _, d in root:GetDescendants() do
		add(d)
	end
	for _, d in extra or {} do
		add(d)
	end
	groups[name] = list
	print(name, #list)
end
local function folder(): any
	return UiSim.newInstance("Folder")
end
local MeshFix = sim:require("Shared.MeshFix")

-- the bosses
local WorldFx = sim:require("Client.Fx.WorldFx")
for _, id in { "LeviathanEngine", "LumenMaw", "RustjawPrime", "NullWarFrame" } do
	local sh = WorldFx._build(id, { x = 0, y = 0, z = 0, yaw = 0, state = "fight", id = id })
	grab(id, sh.model, nil, id .. "_") -- a boss piece is named for its row; its mesh is "<Boss>_<row>"
end

-- the shell rigs, standing on y = 0
local NpcRig = sim:require("Shared.NpcRig")
local RigMath = sim:require("Shared.RigMath")
for _, look in { "Trooper", "Bramblebeast", "Voidhound", "WindupGiant" } do
	local layout = RigMath.layout(Config.HeroRig, nil, 1.6)
	local rig = NpcRig.build(layout, look, {}, nil, nil, nil, look)
	-- the look's extras (EnemyRenderer: a Trooper's hair, a finale's mane, spines, key) fixed as the game does
	local cfg = if look == "Trooper" then Config.TrooperArt else Config.FinaleArt[look]
	local lib = sim.place.ReplicatedStorage.Art:FindFirstChild(look)
	for xname, x in cfg.extras or {} do
		local src = lib and lib:FindFirstChild(xname, true)
		if src then
			local p = MeshFix.clone(src)
			local ps = rig.parts[x.parent].Size
			p.Size = ps * Vector3.new(x.size[1], x.size[2], x.size[3])
			NpcRig.fix(rig, x.parent, p, CFrame.new(ps * Vector3.new(x.offset[1], x.offset[2], x.offset[3])))
		end
	end
	grab(look, rig.model)
end

-- creator kits on the hero body (one of each tab, and a cape)
local LookKit = sim:require("Shared.LookKit")
do
	local layout = RigMath.layout(Config.HeroRig, nil, 1)
	local rig = NpcRig.build(layout, "Body", {}, nil, nil, nil, nil)
	local colors = { p = Color3.new(0.8, 0.2, 0.2), s = Color3.new(0.2, 0.3, 0.8), a = Color3.new(1, 0.8, 0.2) }
	local f = folder()
	local pick = {
		head = "HeadArt",
		hands = "GloveArt",
		feet = "BootArt",
		belt = "BeltArt",
		shoulders = "ShoulderArt",
		hat = "HatArt",
	}
	for tab, cfgName in pick do
		local keys = {}
		for k, v in Config[cfgName] do
			if type(v) == "table" and v.pieces then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		local kit = keys[math.min(3, #keys)]
		local had = #f:GetChildren()
		LookKit._pieceMeshes(rig.model, f, tab, kit, colors, nil, nil)
		-- (the game names a worn piece for its slot; the render needs its mesh: the kit's rows, in order)
		for i, row in Config[cfgName][kit].pieces do
			local p = f:GetChildren()[had + i]
			if p then
				p.Name = row.mesh
			end
		end
	end
	local capes = {}
	for k, v in Config.CapeArt do
		if type(v) == "table" and v.pieces then
			table.insert(capes, k)
		end
	end
	table.sort(capes)
	local had = #f:GetChildren()
	LookKit._capeMeshes(rig.model, f, "cape:" .. capes[1], colors, nil)
	for i, row in Config.CapeArt[capes[1]].pieces do
		local p = f:GetChildren()[had + i]
		if p then
			p.Name = row.mesh
		end
	end
	grab("Creator", f, rig.model:GetChildren())
end

-- vehicles, HQ and set pieces, street props in a row
local HqMeshes = sim:require("Client.Fx.HqMeshes")
local m = UiSim.newInstance("ModuleScript")
m.Name = "SetPieceMeshes"
m._props.Source = fs.readFile("src/server/Services/SetPieceMeshes.luau")
m.Parent = sim.place.ReplicatedStorage
local SetPieceMeshes = sim:_requireInstance(m)
do
	local f = folder()
	local x = 0
	for _, look in { "FieldTripBus", "IceCreamTruck", "NewsVan" } do
		SetPieceMeshes.add(f, { look = look, x = 0, y = 0, z = 0 }, CFrame.new(x, 0, 0))
		x += 16
	end
	grab("Vehicles", f)
	f = folder()
	x = 0
	local hq = {}
	for k in Config.HqArt do
		table.insert(hq, k)
	end
	table.sort(hq)
	for i = 1, #hq, math.max(1, math.floor(#hq / 6)) do
		HqMeshes.place(f, hq[i], CFrame.new(x, 0, 0))
		x += 12
	end
	grab("Hq", f)
	local CityProps = sim:require("Client.Controllers.CityProps")
	CityProps.init()
	f = folder()
	x = 0
	local names = {}
	for k in Config.City.kit.props do
		table.insert(names, k)
	end
	table.sort(names)
	for _, k in names do
		if CityProps.make(k, CFrame.new(x, 0, 0), f) > 0 then
			x += 9
		end
	end
	grab("Street", f)
end

fs.writeDir("build/fit")
fs.writeFile(outPath, serde.encode("json", groups))
print("wrote", outPath)
