-- CityProps: the city kit's street props on this device (overhaul plan step 5; Config.City.kit.props, meshes from
-- ReplicatedStorage.Art.Street by art/blender/street.py). The server builds none: every device works out the same
-- list from the world seed (WorldMap.propsJob, pure and seeded, a few tiles a frame) and builds only what is near
-- its camera, within its preset's street-prop budget (Config.Presets <preset>.props: the highest tier, the
-- radius and a mesh-part cap, nearest first), so phones get fewer. Props are dressing: they collide for this
-- device's hero, and nothing on the server depends on them. None until Art.Street is imported (Tasks.md "City
-- kit: the whole city"). Client only.
-- smash(center, radius, max, fling) (2026-11-19, "more destruction everywhere"): a big impact nearby knocks the
-- props in reach loose (BuildingFx flings a copy of each piece as debris); the prop is gone from this device for
-- Config.Destruction.street.respawn seconds, then stands again. Every device hears the same impacts.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local QualityController = require(script.Parent.QualityController)

local KIT = Config.City.kit
local CELL = 140 -- props are bucketed like the hub's chunks
local PER_STEP = 40 -- props built per frame at most, so a district never hitches in
local TILES_PER_STEP = 4 -- outskirts tiles laid out per WorldMap.propsStep (about 0.1 ms on a PC)
local BUILD_SLICE = 0.002 -- seconds of each frame the prop list may take while it is worked out

local CityProps = {}
CityProps.built = 0 -- mesh parts built now (the Dev panel can show it)
CityProps.total = 0 -- props in the whole list
-- set by Fx.CityLife: called with (name, foot, tint, center) for every prop an impact knocks loose
CityProps.onSmash = nil :: ((string, Vector3, string?, Vector3) -> ())?

type Prop = {
	name: string,
	x: number,
	y: number,
	z: number,
	ry: number,
	d: string?,
	tint: string?, -- a palette key for its tinted pieces (pt-city: news boxes, food carts)
	model: Model?, -- built on this device now
	parts: number?,
	brokenUntil: number?, -- knocked loose by an impact: not built again before this
	bent: boolean?, -- bent over by a knock at its edge (destroy-all): straightened when its time is up
}
type Cell = { key: number, x: number, z: number, props: { Prop }, model: Model?, parts: number }

local cells: { [number]: Cell } = {}
local street: Instance? = nil
local lifeRoot: Instance? = nil -- ReplicatedStorage.Art.Life (the living world, 2026-11-19)
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
			tinted: boolean,
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
	-- the living world's street props (vending machines) are Art.Life meshes (MeshFix.of turns them back)
	local life = Config.LifeArt[name] ~= nil and Config.StreetArt[name] == nil
	local fit = Config.StreetArt[name] or Config.LifeArt[name]
	local root = if life then lifeRoot else street
	if def and fit and root then
		for piece, look in def.pieces do
			local src = root:FindFirstChild(piece, true)
			if src and src:IsA("MeshPart") and fit[piece] then
				table.insert(list, {
					piece = piece,
					src = src,
					color = Color3.fromRGB(look[1][1], look[1][2], look[1][3]),
					material = (Enum.Material :: any)[look[2]],
					collide = look[3],
					see = look[4] or 0,
					fit = fit[piece],
					tinted = look[5] == true,
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
		local p = MeshFix.clone(pc.src)
		for _, c in p:GetChildren() do
			if not c:IsA("SurfaceAppearance") then
				c:Destroy()
			end
		end
		local f = pc.fit
		p.Name = pc.piece
		p.Anchored = true
		p.Size = Vector3.new(f.size[1], f.size[2], f.size[3])
		p.CFrame = at * CFrame.new(f.offset[1], f.offset[2], f.offset[3]) * MeshFix.of(p) -- the import's turn
		local tint = if pc.tinted and pr.tint then Config.City.palette[pr.tint] else nil
		p.Color = if tint then Color3.fromRGB(tint[1], tint[2], tint[3]) else pc.color
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
	pr.model = model
	pr.parts = made
	return made
end

-- One street prop's meshes at `at` under parent, outside the city's cells (the pockets' dressing, PocketDecor);
-- returns the mesh parts made (0 until Art.Street is imported)
function CityProps.make(name: string, at: CFrame, parent: Instance): number
	if not KIT.props[name] or not street then
		return 0
	end
	local pos = at.Position
	local _, ry = at:ToOrientation()
	local pr: Prop = { name = name, x = pos.X, y = pos.Y, z = pos.Z, ry = math.deg(ry) }
	return makeProp(pr, parent)
end

-- A throwable's look (item 154, ThrowFx): the street prop `name`'s meshes welded onto `body` (the server's
-- plain box), scaled as one so the prop stands `height` studs tall with its foot at the box's bottom. Loose,
-- massless, no collision or queries: the box keeps the hits and the carry. Returns the parts made (0 until the
-- art is imported; the box then shows as today). `out` collects the parts, for a caller that fades them.
function CityProps.dress(name: string, body: BasePart, height: number, out: { BasePart }?): number
	if not street then
		local art = ReplicatedStorage:FindFirstChild("Art")
		street = art and art:FindFirstChild("Street")
		lifeRoot = art and art:FindFirstChild(Config.Life.set)
	end
	local list = piecesOf(name)
	if #list == 0 then
		return 0
	end
	local top = 0
	for _, pc in list do
		top = math.max(top, pc.fit.offset[2] + pc.fit.size[2] / 2)
	end
	local k = if top > 0 then height / top else 1
	local foot = body.CFrame * CFrame.new(0, -body.Size.Y / 2, 0)
	for _, pc in list do
		local p = MeshFix.clone(pc.src)
		for _, c in p:GetChildren() do
			if not c:IsA("SurfaceAppearance") then
				c:Destroy()
			end
		end
		local f = pc.fit
		p.Name = "Dress_" .. pc.piece
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = Vector3.new(f.size[1], f.size[2], f.size[3]) * k
		p.CFrame = foot * CFrame.new(f.offset[1] * k, f.offset[2] * k, f.offset[3] * k) * MeshFix.of(p)
		p.Color = pc.color
		p.Material = pc.material
		p.Transparency = pc.see
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = p
		weld.Parent = p
		p.Parent = body.Parent
		if out then
			table.insert(out, p)
		end
	end
	return #list
end

local function dressPart(body: BasePart, spec: any): BasePart
	local p = Instance.new("Part")
	p.Name = "Dress"
	if spec.shape then
		p.Shape = (Enum.PartType :: any)[spec.shape]
	end
	p.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
	local r = spec.rot or { 0, 0, 0 }
	p.CFrame = body.CFrame
		* CFrame.new(spec.at[1], spec.at[2], spec.at[3])
		* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	p.Color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	p.Material = (Enum.Material :: any)[spec.mat] or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = body.Parent
	return p
end

-- A throwable's small part build (Config.Throw.dress parts) welded onto its box; returns the parts made
function CityProps.dressParts(body: BasePart, specs: { any }): number
	for _, spec in specs do
		dressPart(body, spec)
	end
	return #specs
end

local function clearCell(c: Cell)
	for _, pr in c.props do
		pr.model = nil
	end
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
			local now = os.clock()
			for _, pr in c.props do
				if KIT.props[pr.name].tier <= budget.tier and (pr.brokenUntil or 0) <= now then
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

-- Knock up to `max` built props within `radius` of center loose: fling(part, center) makes each piece's debris,
-- then the prop goes until its respawn time. Returns how many props it knocked loose.
-- destroy-all (2026-11-20): a street lamp or traffic light at the edge of a knock bends instead of flying: it leans
-- away from the hit about its foot (Config.Destruction.street.bend), its lamp goes dark, and it stands straight again
-- (built anew) after the street's respawn. Nearer the hit it flies off as before.
local BEND = { StreetLamp = true, TrafficLight = true }
local function bend(pr: Prop, m: Model, center: Vector3, c: Cell, respawn: number)
	local B = Config.Destruction.street.bend or { from = 0.45, angle = { 24, 42 }, time = 0.18 }
	local foot = Vector3.new(pr.x, pr.y, pr.z)
	local away = Vector3.new(pr.x - center.X, 0, pr.z - center.Z)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
	local axis = Vector3.yAxis:Cross(away) -- tip over away from the hit
	local deg = B.angle[1] + math.random() * (B.angle[2] - B.angle[1])
	local start = m:GetPivot()
	local rel = CFrame.new(foot):Inverse() * start -- the model's pivot from its foot
	local t = Instance.new("NumberValue")
	t.Changed:Connect(function(k: number)
		if m.Parent then
			m:PivotTo(CFrame.new(foot) * CFrame.fromAxisAngle(axis, math.rad(deg) * k) * rel)
		end
	end)
	local tw = TweenService:Create(
		t,
		TweenInfo.new(B.time, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	tw.Completed:Connect(function()
		t:Destroy()
	end)
	tw:Play()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			d.Material = Enum.Material.SmoothPlastic -- the lamp goes out
			d.Color = d.Color:Lerp(Color3.new(0.2, 0.2, 0.22), 0.6)
		elseif d:IsA("Light") then
			d.Enabled = false
		end
	end
	pr.bent = true
	pr.brokenUntil = os.clock() + respawn
	task.delay(respawn, function()
		if pr.model == m then
			m:Destroy()
			pr.model = nil
			pr.bent = nil
			c.parts -= pr.parts or 0
			CityProps.built -= pr.parts or 0
			local cm = c.model
			if cm then
				local made = makeProp(pr, cm)
				c.parts += made
				CityProps.built += made
			end
		end
	end)
end

function CityProps.smash(
	center: Vector3,
	radius: number,
	max: number,
	fling: (BasePart, Vector3) -> ()
): number
	if max <= 0 then
		return 0
	end
	local n = 0
	local now = os.clock()
	local respawn = Config.Destruction.street.respawn
	local r2 = radius * radius
	for cx = math.floor((center.X - radius) / CELL), math.floor((center.X + radius) / CELL) do
		for cz = math.floor((center.Z - radius) / CELL), math.floor((center.Z + radius) / CELL) do
			local c = cells[cx * 4096 + cz]
			if c and c.model then
				for _, pr in c.props do
					local m = pr.model
					local d2 = (pr.x - center.X) ^ 2 + (pr.z - center.Z) ^ 2
					local B = Config.Destruction.street.bend
					if
						m
						and not pr.bent
						and BEND[pr.name]
						and B
						and d2 <= r2
						and d2 > r2 * B.from * B.from
						and math.abs(pr.y - center.Y) <= radius + 6
					then
						bend(pr, m, center, c, respawn)
						n += 1
						if n >= max then
							return n
						end
					elseif m and d2 <= r2 and math.abs(pr.y - center.Y) <= radius + 6 then
						pr.bent = nil -- (a bent lamp hit again close by flies off)
						for _, p in m:GetChildren() do
							if p:IsA("BasePart") then
								fling(p, center)
							end
						end
						local hook = CityProps.onSmash
						if hook then
							-- the living world (Fx.CityLife): a hydrant sprays, a machine spills its cans
							task.spawn(hook, pr.name, Vector3.new(pr.x, pr.y, pr.z), pr.tint, center)
						end
						m:Destroy()
						pr.model = nil
						c.parts -= pr.parts or 0
						CityProps.built -= pr.parts or 0
						pr.brokenUntil = now + respawn
						task.delay(respawn, function()
							local cm = c.model
							if cm and not pr.model and (pr.brokenUntil or 0) <= os.clock() then
								local made = makeProp(pr, cm)
								c.parts += made
								CityProps.built += made
							end
						end)
						n += 1
						if n >= max then
							return n
						end
					end
				end
			end
		end
	end
	return n
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
		lifeRoot = art and art:FindFirstChild(Config.Life.set)
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
