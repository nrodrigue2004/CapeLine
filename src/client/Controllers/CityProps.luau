-- CityProps: the city kit's street props on this device (overhaul plan step 5; Config.City.kit.props, meshes from
-- ReplicatedStorage.Art.Street by art/blender/street.py). The server builds none: every device works out the same
-- list from the world seed (WorldMap.propsJob, pure and seeded, a few tiles a frame) and builds only what is near
-- its camera, within its preset's street-prop budget (Config.Presets <preset>.props: the highest tier, the
-- radius and a mesh-part cap, nearest first), so phones get fewer. Props are dressing: they collide for this
-- device's hero, and nothing on the server depends on them. None until Art.Street is imported (Tasks.md "City
-- kit: the whole city"). Client only.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local QualityController = require(script.Parent.QualityController)

local KIT = Config.City.kit
local CELL = 140 -- props are bucketed like the hub's chunks
local PER_STEP = 40 -- props built per frame at most, so a district never hitches in
local TILES_PER_STEP = 4 -- outskirts tiles laid out per WorldMap.propsStep (about 0.1 ms on a PC)
local BUILD_SLICE = 0.002 -- seconds of each frame the prop list may take while it is worked out

local CityProps = {}
CityProps.built = 0 -- mesh parts built now (the Dev panel can show it)
CityProps.total = 0 -- props in the whole list

type Prop = { name: string, x: number, y: number, z: number, ry: number, d: string? }
type Cell = { key: number, x: number, z: number, props: { Prop }, model: Model?, parts: number }

local cells: { [number]: Cell } = {}
local street: Instance? = nil
local folder: Folder? = nil
local looks: {
	[string]: {
		{
			piece: string,
			src: MeshPart,
			color: Color3,
			material: Enum.Material,
			collide: boolean,
			see: number,
			fit: any,
		}
	},
} =
	{}

local function cellKey(x: number, z: number): number
	return math.floor(x / CELL) * 4096 + math.floor(z / CELL)
end

-- Each prop's pieces once: the source mesh, its colour and how it is placed (Config.StreetArt)
local function piecesOf(name: string)
	local list = looks[name]
	if list then
		return list
	end
	list = {}
	local def = KIT.props[name]
	local fit = Config.StreetArt[name]
	if def and fit and street then
		for piece, look in def.pieces do
			local src = street:FindFirstChild(piece, true)
			if src and src:IsA("MeshPart") and fit[piece] then
				table.insert(list, {
					piece = piece,
					src = src,
					color = Color3.fromRGB(look[1][1], look[1][2], look[1][3]),
					material = (Enum.Material :: any)[look[2]],
					collide = look[3],
					see = look[4] or 0,
					fit = fit[piece],
				})
			end
		end
	end
	looks[name] = list
	return list
end

local function partsOf(name: string): number
	return #piecesOf(name)
end

local function makeProp(pr: Prop, parent: Instance): number
	local at = CFrame.new(pr.x, pr.y, pr.z) * CFrame.Angles(0, math.rad(pr.ry), 0)
	local model = Instance.new("Model")
	model.Name = pr.name
	local made = 0
	for _, pc in piecesOf(pr.name) do
		local p = pc.src:Clone()
		for _, c in p:GetChildren() do
			if not c:IsA("SurfaceAppearance") then
				c:Destroy()
			end
		end
		local f = pc.fit
		p.Name = pc.piece
		p.Anchored = true
		p.Size = Vector3.new(f.size[1], f.size[2], f.size[3])
		p.CFrame = at * CFrame.new(f.offset[1], f.offset[2], f.offset[3])
		p.Color = pc.color
		p.Material = pc.material
		p.Transparency = pc.see
		p.CanCollide = pc.collide
		p.CanQuery = pc.collide
		p.CanTouch = false
		p.CastShadow = pc.material ~= Enum.Material.Neon and pc.see == 0
		p.Parent = model
		made += 1
	end
	model.Parent = parent
	return made
end

local function clearCell(c: Cell)
	if c.model then
		c.model:Destroy()
		c.model = nil
		CityProps.built -= c.parts
		c.parts = 0
	end
end

-- Build or drop cells around the camera: nearest first, up to the preset's tier, radius and part cap. A build
-- yields between frames; when the preset changes meanwhile (generation), a cell built under the old budget is
-- dropped and the pass ends, so no cell keeps the old preset's props (audit 2026-11-18)
local building = false
local generation = 0
local function refresh()
	if building or not folder then
		return
	end
	building = true
	local gen = generation
	local budget = QualityController.preset.props or Config.Presets.low.props
	local cam = Workspace.CurrentCamera
	local focus = if cam then cam.Focus.Position else Vector3.zero
	local reach = budget.radius + CELL * 0.71
	local want: { { c: Cell, d: number } } = {}
	for _, c in cells do
		local d = math.sqrt((c.x - focus.X) ^ 2 + (c.z - focus.Z) ^ 2)
		if d <= reach then
			table.insert(want, { c = c, d = d })
		elseif d > reach * 1.15 then
			clearCell(c) -- a little slack so a cell on the edge doesn't flicker
		end
	end
	table.sort(want, function(a, b)
		return a.d < b.d
	end)
	-- the cap counts the cells in reach nearest first; a far cell that no longer fits is dropped
	local used = 0
	local steps = 0
	for _, w in want do
		local c = w.c
		local need = c.parts
		if not c.model then
			for _, pr in c.props do
				if KIT.props[pr.name].tier <= budget.tier then
					need += partsOf(pr.name)
				end
			end
		end
		if used + need > budget.parts then
			clearCell(c)
			continue
		end
		if not c.model then
			local m = Instance.new("Model")
			m.Name = "Props_" .. c.key
			for _, pr in c.props do
				if KIT.props[pr.name].tier <= budget.tier then
					c.parts += makeProp(pr, m)
					steps += 1
					if steps % PER_STEP == 0 then
						RunService.Heartbeat:Wait()
					end
				end
			end
			if gen ~= generation then
				m:Destroy() -- the preset changed while it was built
				c.parts = 0
				break
			end
			m.Parent = folder
			c.model = m
			CityProps.built += c.parts
		end
		used += c.parts
	end
	building = false
	if gen ~= generation then
		task.spawn(refresh) -- build again under the new preset
	end
end

-- A new preset: drop everything and build again under its budget
local function rebuild()
	generation += 1
	for _, c in cells do
		clearCell(c)
	end
	task.spawn(refresh)
end

local function seedOf(): number?
	local value = ReplicatedStorage:WaitForChild("WorldInfo", 60)
	if not (value and value:IsA("StringValue")) then
		return nil
	end
	while value.Value == "" do
		value.Changed:Wait()
	end
	local ok, info = pcall(HttpService.JSONDecode, HttpService, value.Value)
	if ok and type(info) == "table" and type(info.seed) == "number" then
		return info.seed
	end
	return nil
end

function CityProps.init()
	task.spawn(function()
		local art = ReplicatedStorage:FindFirstChild("Art")
		street = art and art:FindFirstChild("Street")
		if not street then
			return -- the props wait for nate's import of Art.Street (until then the city keeps today's look)
		end
		local seed = seedOf()
		if not seed then
			return
		end
		-- the props alone, a few tiles at a time under a small slice of each frame (the whole world at once
		-- froze phones for several hundred ms); the list is WorldMap.build's props exactly
		local job = WorldMap.propsJob(Config, seed)
		local slice = os.clock()
		while not WorldMap.propsStep(job, TILES_PER_STEP) do
			if os.clock() - slice > BUILD_SLICE then
				RunService.Heartbeat:Wait()
				slice = os.clock()
			end
		end
		local props = job.props
		for _, pr in props do
			local key = cellKey(pr.x, pr.z)
			local c = cells[key]
			if not c then
				c = {
					key = key,
					x = (math.floor(pr.x / CELL) + 0.5) * CELL,
					z = (math.floor(pr.z / CELL) + 0.5) * CELL,
					props = {},
					parts = 0,
				}
				cells[key] = c
			end
			table.insert(c.props, pr)
		end
		CityProps.total = #props
		local f = Instance.new("Folder")
		f.Name = "CityProps"
		f.Parent = Workspace
		folder = f
		QualityController.Changed:Connect(rebuild)
		while true do
			refresh()
			task.wait(0.5)
		end
	end)
end

return CityProps
