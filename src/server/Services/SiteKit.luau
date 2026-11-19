-- SiteKit: the pieces incidents, contracts and events are made of, so each of those services only says
-- what goes where (spec: Incidents; Rescue.Pick / Rescue.Drop; Radiant contracts; Random events).
-- * squad: robots for a site, tagged so their defeats count for it.
-- * citizen: a stranded citizen (or a cat) with a Rescue prompt. The prompt is the server's check (range
--   12, not already carrying, not carried by someone else), like the safehouse bank, so there is no
--   Rescue.Pick remote; carrying one into a drop circle is the drop. Citizens can never be hurt: if the
--   carrier is defeated the citizen is set down safely where they were.
-- * pad: a drop circle (a rescue boat, an ambulance pad or "any safehouse" for contracts).
-- * hold: a glowing ring; progress while heroes stand in it.
-- * object: a breakable or stoppable thing with HP (a tram, a relay, an engine, a generator) as a combat
--   target.
-- * pickup: a shard to touch.
-- Everything a site builds lives under Workspace.Sites and is removed with clear().
-- * look: tags a prop's model with its Blender look (Shared.ActivityKit kind); the device draws it over the parts
--   (Fx.ActivityProps) once Art.Activity is imported and hides them there. The parts here stay as they are.
-- The cat is a plain part; stranded citizens are R15 people (NpcRig.person) with the hero meshes once imported.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local RigMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigMath"))
local NpcRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcRig"))
local EnemyVariety = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EnemyVariety"))

local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)

local SiteKit = {}

local IC = Config.Incidents
local varietyRng = Random.new()
local folder: Folder? = nil

local function root(): Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Sites"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function SiteKit.part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end
local part = SiteKit.part

-- Tag a prop with its look (Shared.ActivityKit.KINDS); a model built in world studs (no Root) gets an unseen Root
-- at `foot`, the look's foot point. scale: a ring's LookScale.
function SiteKit.look(m: Model, kind: string, foot: CFrame?, scale: number?)
	if not m:FindFirstChild("Root") then
		local r = part(m, Vector3.new(1, 1, 1), foot or m:GetPivot(), Color3.new(1, 1, 1))
		r.Name = "Root"
		r.Transparency = 1
	end
	m:SetAttribute("Look", kind)
	if scale then
		m:SetAttribute("LookScale", scale)
	end
end

function SiteKit.model(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = root()
	return m
end

-- Heroes standing within r of pos (players and bots)
function SiteKit.heroesIn(pos: Vector3, r: number): { any }
	local out = {}
	for _, h in HeroService.all() do
		local p = h.alive and HeroService.position(h)
		if p and (p - pos).Magnitude <= r then
			table.insert(out, h)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Robots
---------------------------------------------------------------------------

-- Spawn robots in a ring around pos; returns their ids
function SiteKit.squad(
	list: { { kind: string, n: number } },
	pos: Vector3,
	level: number,
	tag: number,
	ring: number?
): { number }
	-- the new robot types swap in as heroes level (Shared.EnemyVariety; each type's switch in Config.Enemies)
	local rows = EnemyVariety.squad(Config, list, level, function()
		return varietyRng:NextNumber()
	end)
	local ids = {}
	local total = 0
	for _, row in rows do
		total += row.n
	end
	local k = 0
	for _, row in rows do
		local cfg = Config.Enemies[row.kind]
		for _ = 1, row.n do
			k += 1
			local a = k / math.max(total, 1) * math.pi * 2
			local r = (ring or 16) + (k % 3) * 4
			local y = pos.Y + (if cfg and cfg.flies then (cfg.hover and cfg.hover.min or 14) else 0)
			-- a Swarmer brings its pack and a Captain its escort: every robot counts for the site
			for _, id in
				EnemyService.spawnGroup(
					row.kind,
					Vector3.new(pos.X + math.cos(a) * r, y, pos.Z + math.sin(a) * r),
					level,
					tag
				)
			do
				table.insert(ids, id)
			end
		end
	end
	return ids
end

---------------------------------------------------------------------------
-- Citizens and the carry
---------------------------------------------------------------------------

export type Citizen = {
	model: Model,
	home: Vector3,
	state: string, -- stuck, carried, safe
	carrier: any?,
	weld: WeldConstraint?,
	prompt: ProximityPrompt,
	onPick: ((hero: any) -> ())?,
	onSafe: (hero: any, pad: any) -> (),
	pads: { any }?, -- where it may be dropped; nil = any pad
	anySafehouse: boolean?,
	cat: boolean?,
}

local carried: { [number]: Citizen } = {} -- hero id -> the citizen they carry
local citizens: { Citizen } = {}
local pads: { any } = {}
SiteKit.safehouses = {} :: { { x: number, z: number } } -- set by the server (SafehouseService.list)

local SHIRTS = Config.Destruction.citizens.colors
local HAIR = Config.Destruction.citizens.hair
local personLayout = RigMath.layout(Config.HeroRig, nil, 1)

-- person (optional): makes the rig instead of a random citizen (a side quest's named helper, PeopleLooks)
local function citizenModel(pos: Vector3, cat: boolean?, person: (() -> any)?): (Model, BasePart)
	local m = SiteKit.model(if cat then "Cat" else "StrandedCitizen")
	local body: BasePart
	if cat then
		body = part(
			m,
			Vector3.new(1.4, 1, 2.2),
			CFrame.new(pos + Vector3.new(0, 0.5, 0)),
			Color3.fromRGB(240, 150, 60)
		)
		part(
			m,
			Vector3.new(1.1, 1, 1),
			CFrame.new(pos + Vector3.new(0, 1.2, -1.2)),
			Color3.fromRGB(240, 150, 60)
		)
		for _, s in { -0.35, 0.35 } do
			part(
				m,
				Vector3.new(0.3, 0.5, 0.2),
				CFrame.new(pos + Vector3.new(s, 1.9, -1.2)),
				Color3.fromRGB(240, 150, 60)
			)
		end
		part(
			m,
			Vector3.new(0.25, 0.25, 1.6),
			CFrame.new(pos + Vector3.new(0, 1.2, 1.6)) * CFrame.Angles(math.rad(-40), 0, 0),
			Color3.fromRGB(220, 130, 50)
		)
	else
		-- a person on the heroes' blocky R15 rig (nate, 2026-11-16: "literally everyone should be r15"), both
		-- arms up, waving for help; the root is the body that is carried
		local set = SHIRTS[math.random(1, #SHIRTS)]
		local hair = HAIR[math.random(1, #HAIR)]
		local rig = if person
			then person()
			else NpcRig.person(personLayout, m.Name, rgb(set[1]), rgb(set[2]), rgb(set[3]), rgb(hair))
		rig.model.Name = m.Name
		rig.model.Parent = m.Parent
		m:Destroy()
		m = rig.model
		NpcRig.place(rig, CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
		NpcRig.bend(rig, "LeftShoulder", CFrame.Angles(math.rad(165), 0, math.rad(-12)))
		NpcRig.bend(rig, "RightShoulder", CFrame.Angles(math.rad(165), 0, math.rad(12)))
		body = rig.root
	end
	m.PrimaryPart = body
	return m, body
end

-- A citizen who only stands there (a crowd at an incident, a huddle under a barrage): no prompt, nothing to
-- carry (they wave like the stranded ones and run off when the step ends). Cleared with clear().
function SiteKit.bystander(pos: Vector3): Model
	local m = citizenModel(pos, false)
	m.Name = "Bystander"
	return m
end

-- A stranded citizen at pos. onSafe(hero, pad) when carried into a pad (or a safehouse when anySafehouse).
function SiteKit.citizen(
	pos: Vector3,
	opts: {
		onSafe: (any, any) -> (),
		onPick: ((any) -> ())?,
		pads: { any }?,
		anySafehouse: boolean?,
		cat: boolean?,
		who: ((any) -> boolean)?, -- only these heroes may pick them up (a story scene's own citizen)
		person: (() -> any)?, -- makes the rig (a side quest's named helper in their own look)
	}
): Citizen
	local m, body = citizenModel(pos, opts.cat, opts.person)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if opts.cat then "Rescue the cat" else "Rescue"
	prompt.ObjectText = if opts.cat then "Cat" else "Citizen"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = IC.rescueRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.B -- E is Skill 2 (as at the safehouse terminals)
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = body
	local c: Citizen = {
		model = m,
		home = pos,
		state = "stuck",
		carrier = nil,
		weld = nil,
		prompt = prompt,
		onPick = opts.onPick,
		onSafe = opts.onSafe,
		pads = opts.pads,
		anySafehouse = opts.anySafehouse,
		cat = opts.cat,
	}
	prompt.Triggered:Connect(function(player)
		local hero = HeroService.get(player)
		local hrp = hero and HeroService.rootPart(hero)
		if not hero or not hrp or not hero.alive or c.state ~= "stuck" or carried[hero.id] then
			return
		end
		if opts.who and not opts.who(hero) then
			return
		end
		if (hrp.Position - body.Position).Magnitude > IC.rescueRange + 4 then
			return
		end
		c.state = "carried"
		c.carrier = hero
		carried[hero.id] = c
		prompt.Enabled = false
		-- ride on the hero's back
		local offset = hrp.CFrame * CFrame.new(0, if c.cat then 2.2 else 0.6, 1.4)
		m:PivotTo(offset * CFrame.new(0, -(body.Position.Y - m:GetPivot().Position.Y), 0))
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.Massless = true
				p.CanCollide = false
				if p ~= body then
					local w = Instance.new("WeldConstraint")
					w.Part0, w.Part1 = body, p
					w.Parent = body
				end
			end
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = hrp, body
		weld.Parent = body
		c.weld = weld
		pcall(function()
			body:SetNetworkOwner(player)
		end)
		if c.onPick then
			c.onPick(hero)
		end
	end)
	table.insert(citizens, c)
	return c
end

local function setDown(c: Citizen, at: Vector3)
	if c.weld then
		c.weld:Destroy()
		c.weld = nil
	end
	if c.carrier then
		carried[c.carrier.id] = nil
	end
	c.carrier = nil
	for _, p in c.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
		elseif p:IsA("WeldConstraint") then
			p:Destroy()
		end
	end
	local pivot = c.model:GetPivot()
	c.model:PivotTo(CFrame.new(at) * pivot.Rotation)
end

function SiteKit.removeCitizen(c: Citizen)
	if c.carrier then
		carried[c.carrier.id] = nil
	end
	c.state = "safe"
	c.model:Destroy()
	local i = table.find(citizens, c)
	if i then
		table.remove(citizens, i)
	end
end

function SiteKit.carrying(hero: any): boolean
	return carried[hero.id] ~= nil
end

-- A drop circle
function SiteKit.pad(pos: Vector3, label: string?): any
	local m = SiteKit.model("RescuePad")
	local disc = part(
		m,
		Vector3.new(0.4, IC.dropRadius * 2, IC.dropRadius * 2),
		CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(80, 220, 140),
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	disc.Transparency = 0.55
	disc.Name = "Disc"
	part(m, Vector3.new(1, 10, 1), CFrame.new(pos + Vector3.new(0, 5, 0)), Color3.fromRGB(240, 240, 240))
	part(
		m,
		Vector3.new(4, 2.4, 0.3),
		CFrame.new(pos + Vector3.new(0, 9.5, 0)),
		Color3.fromRGB(80, 220, 140),
		Enum.Material.Neon
	)
	SiteKit.look(m, "RescuePad", CFrame.new(pos))
	local pad = { pos = pos, model = m, label = label }
	table.insert(pads, pad)
	return pad
end

function SiteKit.removePad(pad: any)
	pad.model:Destroy()
	local i = table.find(pads, pad)
	if i then
		table.remove(pads, i)
	end
end

local function carryStep()
	for heroId, c in carried do
		local hero = c.carrier
		local pos = hero and hero.alive and HeroService.position(hero)
		if not pos or HeroService.byId(heroId) ~= hero then
			-- the carrier fell or left: the citizen is set down safely where they were found
			setDown(c, c.home)
			c.state = "stuck"
			c.prompt.Enabled = true
		else
			local dropped: any = nil
			for _, pad in (c.pads or pads) do
				if
					(Vector3.new(pad.pos.X, pos.Y, pad.pos.Z) - pos).Magnitude <= IC.dropRadius
					and math.abs(pos.Y - pad.pos.Y) < 30
				then
					dropped = pad
					break
				end
			end
			if not dropped and c.anySafehouse then
				for i, s in SiteKit.safehouses do
					if
						(Vector3.new(s.x, pos.Y, s.z) - pos).Magnitude <= Config.World.safehouse.safeRadius
					then
						dropped = { safehouse = i, pos = Vector3.new(s.x, pos.Y, s.z) }
						break
					end
				end
			end
			if dropped then
				carried[heroId] = nil
				c.carrier = nil
				SiteKit.removeCitizen(c)
				c.onSafe(hero, dropped)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Holds, objects and pickups
---------------------------------------------------------------------------

function SiteKit.ring(pos: Vector3, radius: number, color: Color3?): Model
	local m = SiteKit.model("HoldRing")
	local disc = part(
		m,
		Vector3.new(0.3, radius * 2, radius * 2),
		CFrame.new(pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color or Color3.fromRGB(255, 210, 70),
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	disc.Transparency = 0.6
	disc.Name = "Ring"
	SiteKit.look(m, "HoldRing", CFrame.new(pos), radius / 10) -- (ActivityKit.RING)
	return m
end

-- A breakable thing: build(model) makes its parts around the origin (the model's pivot is the origin, at
-- its feet) and it becomes a combat target `lift` studs above its feet. onBroken(heroId) when its HP runs
-- out. Returns the handle { model, target, hp, maxHp, pos }; place it with moveObject.
function SiteKit.object(
	name: string,
	pos: Vector3,
	lift: number,
	radius: number,
	hp: number,
	build: (Model) -> (),
	onHit: ((number?, number) -> ())?,
	onBroken: (number?) -> ()
): any
	local m = SiteKit.model(name)
	local base = part(m, Vector3.new(1, 1, 1), CFrame.new(), Color3.new(1, 1, 1))
	base.Name = "Root"
	base.Transparency = 1
	m.PrimaryPart = base
	build(m)
	local h: any = { model = m, hp = hp, maxHp = hp, target = 0, pos = pos, lift = lift }
	h.target = EnemyService.addTarget({
		x = pos.X,
		y = pos.Y + lift,
		z = pos.Z,
		r = radius,
		hit = function(amount: number, heroId: number?)
			if h.hp <= 0 then
				return 0, true
			end
			-- allow (lore step 12, a side event's objective): only some heroes' hits count
			if h.allow and not h.allow(heroId) then
				return 0, false
			end
			-- perHit: a story object that takes a set number of hits (the shard crates, the runaway train)
			local dealt = math.min(h.hp, if h.perHit then 1 else amount)
			h.hp -= dealt
			if onHit then
				onHit(heroId, dealt)
			end
			if h.hp <= 0 then
				task.defer(onBroken, heroId)
				return dealt, true
			end
			return dealt, false
		end,
	})
	m:SetAttribute("Hp", 1)
	return h
end

-- Move an object (and its target) to a new spot
function SiteKit.moveObject(h: any, pos: Vector3, yaw: number?)
	h.pos = pos
	local t = EnemyService.target(h.target)
	if t then
		t.x, t.y, t.z = pos.X, pos.Y + h.lift, pos.Z
	end
	h.model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0))
	h.model:SetAttribute("Hp", math.max(0, h.hp / h.maxHp))
end

-- A prop that is not a target (the escort truck): parts built around the origin, placed with place()
function SiteKit.prop(name: string, build: (Model) -> ()): Model
	local m = SiteKit.model(name)
	local base = part(m, Vector3.new(1, 1, 1), CFrame.new(), Color3.new(1, 1, 1))
	base.Name = "Root"
	base.Transparency = 1
	m.PrimaryPart = base
	build(m)
	return m
end

function SiteKit.place(m: Model, pos: Vector3, yaw: number?)
	m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0))
end

function SiteKit.removeObject(h: any)
	EnemyService.removeTarget(h.target)
	h.model:Destroy()
end

local pickups: { any } = {}

-- A shard (or any touch pickup): onGrab(hero) for the first hero within range; returns the handle
function SiteKit.pickup(
	pos: Vector3,
	range: number,
	color: Color3,
	onGrab: (any) -> (),
	readyAt: number?,
	who: ((any) -> boolean)?
): any
	local m = SiteKit.model("Shard")
	local crystal = part(
		m,
		Vector3.new(2, 4, 2),
		CFrame.new(pos + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, math.rad(45), math.rad(20)),
		color,
		Enum.Material.Neon
	)
	crystal.Name = "Crystal"
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 14
	glow.Brightness = 2
	glow.Parent = crystal
	SiteKit.look(m, "Shard", CFrame.new(pos))
	local h = {
		model = m,
		pos = pos,
		range = range,
		onGrab = onGrab,
		readyAt = readyAt or 0,
		taken = false,
		who = who,
	}
	table.insert(pickups, h)
	return h
end

function SiteKit.removePickup(h: any)
	h.taken = true
	h.model:Destroy()
	local i = table.find(pickups, h)
	if i then
		table.remove(pickups, i)
	end
end

local function pickupStep()
	local now = os.clock()
	for i = #pickups, 1, -1 do
		local h = pickups[i]
		if not h.taken and now >= h.readyAt then
			local list = SiteKit.heroesIn(h.pos + Vector3.new(0, 2, 0), h.range)
			for _, hero in list do
				if not h.who or h.who(hero) then
					table.remove(pickups, i)
					h.taken = true
					h.model:Destroy()
					h.onGrab(hero)
					break
				end
			end
		end
	end
end

-- Destroy a list of site things (models, citizens, pads, objects, pickups, robot ids)
function SiteKit.clear(things: { any })
	for _, t in things do
		if type(t) == "number" then
			EnemyService.remove(t)
		elseif typeof(t) == "Instance" then
			t:Destroy()
		elseif type(t) == "table" then
			if t.prompt then
				SiteKit.removeCitizen(t)
			elseif t.target then
				SiteKit.removeObject(t)
			elseif t.onGrab then
				SiteKit.removePickup(t)
			elseif t.model and t.pos then
				SiteKit.removePad(t)
			end
		end
	end
	table.clear(things)
end

function SiteKit.init()
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("SiteKit", function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		carryStep()
		pickupStep()
	end))
	Players.PlayerRemoving:Connect(function(player)
		local hero = HeroService.get(player)
		local c = hero and carried[hero.id]
		if c then
			setDown(c, c.home)
			c.state = "stuck"
			c.prompt.Enabled = true
		end
	end)
end

return SiteKit
