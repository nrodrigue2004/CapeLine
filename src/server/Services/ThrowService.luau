-- ThrowService: pick up and throw (spec: Hero MMO features > Pick up and throw; H3). Grab, carry, throw,
-- respawn. Anyone grabs light and medium things (benches, bins, mailboxes, signs, rubble, lamp posts,
-- dumpsters, vending machines); heavy things (cars, trucks, big slabs) only Powerhouse heroes or anyone
-- Awakened. Citizens and heroes are never in the list. The rules are Shared.ThrowMath.
-- Carry (fix-carry, nate after gaps7: "i should actually hold them"): the thing is welded into the hero's hands
-- (Shared.CarryPose): big things on both raised fists (a Weld to the UpperTorso), small ones up on the right fist
-- and poles in it (a Weld to the RightHand); Gravity and Mind heroes float it over the head with a glow (a Weld
-- to the HumanoidRootPart). A server Weld into the character joins its assembly: it is massless and never
-- collides, the hero's device owns the assembly, and every device draws it from the joints it poses itself
-- (HeroAnimator's carry poses on Motor6D.Transform), so it sits in the hands on every screen with no lag and no
-- extra traffic. Live robots are no parts: each device draws a held robot at its carrier's hands (ThrowClient,
-- EnemyRenderer.heldAt) and the server keeps its position for the hit checks (holdStep).
-- the hero moves at 80% (HeroService.speedHooks.carry, no boost) and cannot cast or block. Throw: the server
-- picks the landing (aim, range, walls, ground), tells every client to fly it on the same arc (ThrowFly; no
-- free physics), and when it lands CombatService.thrown hits robots (and heroes flagged against the thrower),
-- knocks props over and blasts the Structure grid for heavy things. Cars go home through VehicleService's
-- reset; props come back after 60 s once nobody is near (ThrowBack).
-- The server keeps each prop a plain coloured box (Config.Throw.kinds) for hits, carry and flight; every device dresses it
-- (Fx.ThrowFx: the street kit's meshes, or Art.Throwables' own meshes for the mailbox, sign, dumpster, slab and rubble).
-- Downed robots (WP6, gap G10): a robot a hero beats leaves its wreck where it fell (EnemyService.Killed), a
-- medium throwable with the usual carry rules, for Config.Throw.wreck.life seconds (a few seconds once thrown
-- or set down), then it falls apart (WreckGone: sparks and a pop on every screen, ThrowFx). At most
-- wreck.max at once: a new one clears the oldest nobody holds. Never fakes, twins, creatures, sea robots or
-- the small pack robots (Shared.ThrowMath.canWreck), nor a dressed villain (EnemyService.identity dress).
-- The wreck's look (gap-wrecks, 2026-11-19): art/blender/wrecks.py's heap per robot kind (Shared.WreckArtKit,
-- imported as ReplicatedStorage.Art.Wrecks) in the robot's colours, metal only where it broke, the metal
-- under-head (never a face). Its plain Body box stays the collider, hidden; a kind whose meshes are not all
-- imported builds today's plain parts (the Studio-friendly fallback).
-- Grab a robot and swing it (nate, 2026-11-19 13:18Z; Config.Throw.swing): a held wreck, or a live robot grabbed
-- while stunned (WorldGrabRobot; held overhead, it thinks no more: EnemyService.hold), swings with Basic
-- (WorldSwing): a wide arc in front that hits and throws the robots in it (CombatService.swung, knock "swing") and
-- breaks the wall it meets (ImpactService.swingWall, inside the impact caps). After `max` swings, or with a held
-- Basic, it is thrown; a live robot flies as knock "thrown" and smashes through the buildings it meets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local ThrowMath = require(Shared:WaitForChild("ThrowMath"))
local KnockRules = require(Shared:WaitForChild("KnockRules"))
local Status = require(Shared:WaitForChild("Status"))
local WreckArtKit = require(Shared:WaitForChild("WreckArtKit"))
local CarryPose = require(Shared:WaitForChild("CarryPose"))
local RigJoints = require(Shared:WaitForChild("RigJoints"))
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))

local BlockService = require(script.Parent.BlockService)
local CombatService = require(script.Parent.CombatService)
local EnemyService = require(script.Parent.EnemyService)
local HeroService = require(script.Parent.HeroService)
local VehicleService = require(script.Parent.VehicleService)
local ImpactService = require(script.Parent.ImpactService)

local ThrowService = {}

local T = Config.Throw
local VEH_BASE = 1000 -- item ids above this are VehicleService's vehicles (id - VEH_BASE)
local WRECK_BASE = 3000 -- downed robots' wrecks take ids WRECK_BASE + 1 .. WRECK_BASE + 999 (WP6)
local ROBOT_HOLD = 65000 -- ThrowState's id while a live robot is held (it is no item: hero.carry.robot)
local W = T.wreck

type It = {
	id: number,
	kind: string,
	weight: string,
	x: number,
	y: number,
	z: number,
	busy: boolean?,
	model: Model,
	home: CFrame,
	vehicle: number?,
	landedAt: number?,
	welds: { Instance }?,
	box: CFrame?, -- while carried: the thing's middle in the carrier's root frame (the throw starts there)
	collide: { [BasePart]: boolean }?,
	query: { [BasePart]: boolean }?, -- each part's CanQuery before the carry (a vehicle's look meshes take none)
	wreck: boolean?, -- a downed robot's wreck (WP6): it never goes home, it falls apart at endsAt
	born: number?,
	endsAt: number?,
}

local items: { [number]: It } = {}
local folder: Folder
local wreckTimer: (It, boolean) -> ()
local removeWreck: (It) -> ()
local wreckSeq = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

ThrowService.items = items
ThrowService.Thrown = Signal.new() -- (hero, kind, weight, hits) a throw landed (badges count throws; H7)
ThrowService.Grabbed = Signal.new() -- (hero, kind)

local function skip(): { Instance }
	local list: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local vehicles = (Workspace:FindFirstChild("City") or Workspace):FindFirstChild("Vehicles")
	if vehicles then
		table.insert(list, vehicles)
	end
	local fx = Workspace:FindFirstChild("AbilityParts")
	if fx then
		table.insert(list, fx)
	end
	return list
end

local function ground(x: number, y: number, z: number, depth: number): number?
	rayParams.FilterDescendantsInstances = skip()
	local hit = Workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, -depth, 0), rayParams)
	return hit and hit.Position.Y
end

local function busy(it: It): boolean
	if it.vehicle then
		return it.busy == true or not VehicleService.free(it.vehicle)
	end
	return it.busy == true
end

local function sizeOf(it: It): Vector3
	return it.model:GetExtentsSize()
end

local function toCF(c: CarryPose.CF): CFrame
	return CFrame.new(table.unpack(CarryPose.components(c)))
end

-- A character's R15 arm for CarryPose, from its own Motor6Ds (any body shape), and its parts by name; nil when
-- it is not an R15 body (a bot's box)
function ThrowService.bodyOf(char: Instance?): (CarryPose.Body?, { [string]: BasePart })
	local parts: { [string]: BasePart } = {}
	if not char then
		return nil, parts
	end
	local body: CarryPose.Body = { joints = {}, sizes = {} }
	local root = char:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil, parts
	end
	parts.HumanoidRootPart = root
	-- Motor6Ds or AnimationConstraints (Avatar Joint Upgrade rigs): both read C0 and C1 (Shared.RigJoints)
	local joints = RigJoints.of(char)
	for _, j in CarryPose.JOINTS do
		local p1 = char:FindFirstChild(j[3])
		local m = joints[j[1]]
		if not (p1 and p1:IsA("BasePart") and m) then
			return nil, parts
		end
		parts[j[3]] = p1
		local c0, c1 = (m :: any).C0, (m :: any).C1
		table.insert(body.joints, {
			name = j[1],
			part0 = j[2],
			part1 = j[3],
			c0 = CarryPose.fromComponents({ c0:GetComponents() }),
			c1 = CarryPose.fromComponents({ c1:GetComponents() }),
		})
	end
	for name, p in parts do
		body.sizes[name] = { p.Size.X, p.Size.Y, p.Size.Z }
	end
	return body, parts
end

-- The hero's grip on a kind: Gravity and Mind heroes float it, others hold it (Shared.CarryPose.gripOf)
local function gripFor(hero: any, kind: string): string
	return CarryPose.gripOf(T, kind, hero.setId)
end

-- The telekinesis glow in the path's colour (Config.Throw.mind.glow): an outline and a light, server parts so
-- every device sees them
local function glow(it: It, hero: any)
	local M = T.mind
	local rgb = M.glow[hero.setId] or M.glow.Mind
	local c = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	local h = Instance.new("Highlight")
	h.Name = "CarryGlow"
	h.FillColor = c
	h.FillTransparency = 0.75
	h.OutlineColor = c
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = it.model
	h.Parent = it.model
	local main = it.model.PrimaryPart
	if main then
		local l = Instance.new("PointLight")
		l.Name = "CarryGlow"
		l.Color = c
		l.Brightness = M.light.brightness
		l.Range = M.light.range
		l.Parent = main
	end
end

-- Every part of the thing: welded to its main part, and the main part welded into the hero's hands (or over
-- the head for telekinesis) where Shared.CarryPose puts it for the hold pose's first key. The Weld carries
-- what each device needs to move it during the lift and the swings (ThrowClient): CarryBase (the box's middle
-- in the weld part's frame), CarryHand (the same in the RightHand's frame), CarryOffset (box to main part).
local function attach(it: It, hero: any, root: BasePart): string
	local main = it.model.PrimaryPart :: BasePart
	local welds: { Instance } = {}
	local collide: { [BasePart]: boolean } = {}
	local query: { [BasePart]: boolean } = {}
	for _, p in it.model:GetDescendants() do
		if p:IsA("BasePart") then
			collide[p] = p.CanCollide
			query[p] = p.CanQuery
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
			if p ~= main then
				local w = Instance.new("WeldConstraint")
				w.Part0 = main
				w.Part1 = p
				w.Parent = main
				table.insert(welds, w)
			end
		end
	end
	local grip = gripFor(hero, it.kind)
	local bbCF, bbSize = it.model:GetBoundingBox()
	local body, parts = ThrowService.bodyOf(root.Parent)
	local hold = body
		and CarryPose.hold(
			T,
			body,
			grip,
			HeroAnim.sample(CarryPose.CLIP[grip], 0),
			{ bbSize.X, bbSize.Y, bbSize.Z },
			nil,
			it.vehicle ~= nil
		)
	local part0 = hold and parts[hold.part]
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part1 = main
	if hold and part0 then
		local offset = (main.CFrame:Inverse() * bbCF):Inverse() -- the box's middle to the main part
		local base = toCF(hold.c0)
		weld.Part0 = part0
		weld.C0 = base * offset
		weld:SetAttribute("CarryBase", base)
		weld:SetAttribute("CarryHand", toCF(hold.hand))
		weld:SetAttribute("CarryOffset", offset)
		weld:SetAttribute("CarryGrip", grip)
		weld.Parent = part0
		it.box = toCF(hold.box)
	else
		-- not an R15 body (a bot): over the root as before
		grip = "overhead"
		weld.Part0 = root
		weld.C0 = CFrame.new(0, T.overhead + bbSize.Y / 2, 0)
		weld.Parent = root
		it.box = weld.C0
	end
	table.insert(welds, weld)
	for p in collide do
		p.Anchored = false
	end
	if grip == "mind" then
		glow(it, hero)
	end
	it.welds, it.collide, it.query = welds, collide, query
	return grip
end

local function detach(it: It)
	if it.welds then
		for _, w in it.welds do
			w:Destroy()
		end
	end
	for _, g in it.model:GetDescendants() do
		if g.Name == "CarryGlow" then
			g:Destroy()
		end
	end
	it.box = nil
	if it.collide then
		for p, c in it.collide do
			p.Anchored = true
			p.Massless = false
			p.CanCollide = c
			p.CanQuery = if it.query then it.query[p] ~= false else true
		end
	end
	it.welds, it.collide, it.query = nil, nil, nil
end

-- The carried thing's middle in the world now (the throw starts there)
local function heldAt(it: It, root: BasePart): Vector3
	return if it.box then (root.CFrame * it.box).Position else root.Position + Vector3.new(0, T.overhead, 0)
end

-- Put a prop down at a spot (upright or knocked over), or a vehicle through VehicleService
local function place(it: It, at: Vector3, tumble: boolean, push: Vector3?)
	local size = sizeOf(it)
	if it.vehicle then
		-- a thrown car lands on its roof and VehicleService's reset brings it home in 30 s
		local look = if push and push.Magnitude > 0.1 then push.Unit else Vector3.new(0, 0, -1)
		local base = CFrame.lookAt(at, at + look)
		local root = if tumble
			then base * CFrame.new(0, size.Y + 1, 0) * CFrame.Angles(0, 0, math.pi)
			else base
		VehicleService.drop(it.vehicle, root)
		it.x, it.y, it.z = at.X, at.Y, at.Z
		return
	end
	local cf = CFrame.new(at + Vector3.new(0, size.Y / 2, 0))
	if tumble then
		-- knocked over: lying on its side, turned a little
		local yaw = if push then math.atan2(-push.X, -push.Z) else 0
		cf = CFrame.new(at + Vector3.new(0, math.min(size.X, size.Z) / 2 + 0.1, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(math.pi / 2, 0, 0)
	end
	it.model:PivotTo(cf)
	it.x, it.y, it.z = at.X, at.Y, at.Z
end

-- A wreck's window: `life` once it falls, `after` once it was thrown or set down (WreckEnds is the server
-- time it ends, for the flicker every screen shows near the end; none while it is held)
wreckTimer = function(it: It, handled: boolean)
	local now = os.clock()
	it.endsAt = ThrowMath.wreckEnds(T, now, handled)
	it.model:SetAttribute("WreckEnds", Workspace:GetServerTimeNow() + (it.endsAt :: number - now))
end

local function sendState(hero: any)
	if hero.player then
		local c = hero.carry
		local it = c and items[c.id]
		local kind = if c and c.robot then "robot" elseif it then it.kind else nil
		Net.fire("ThrowState", hero.player, {
			id = if c and c.robot then ROBOT_HOLD elseif c then c.id else 0,
			kind = kind,
			since = c and c.since,
			swings = if c then T.swing.max - (c.swings or 0) else 0,
		})
		-- the grip picks the hold pose every device shows (HeroAnimator: carry, carryHand, carryMind) and, for a
		-- live robot, where each device draws it (CarryRobot: its id; ThrowClient)
		hero.player:SetAttribute("CarryGrip", c and c.grip or nil)
		hero.player:SetAttribute("CarryRobot", if c and c.robot then c.robot else nil)
		hero.player:SetAttribute("Carrying", kind) -- after the grip, so the pose's edge reads it
	end
end

local function release(hero: any)
	hero.carry = nil
	HeroService.applyWalkSpeed(hero)
	sendState(hero)
end

-- Set down in front of the hero (Grab again, the 8 s limit, a stun, death or travel)
local function setDown(hero: any)
	local c = hero.carry
	if c and c.robot then
		-- a held robot is let go in front of the hero, still dazed
		local id = c.robot
		EnemyService.hold(id, nil)
		local root = HeroService.rootPart(hero)
		if root and EnemyService.alive(id) then
			EnemyService.place(id, root.Position + root.CFrame.LookVector * 4)
			EnemyService.applyStatus(id, "stun", 0.6)
		end
		release(hero)
		return
	end
	local it = c and items[c.id]
	if not it then
		release(hero)
		return
	end
	detach(it)
	local root = HeroService.rootPart(hero)
	local at: Vector3
	if root then
		local front = root.Position + root.CFrame.LookVector * 4
		local gy = ground(front.X, front.Y + 4, front.Z, 40)
		at = Vector3.new(front.X, gy or (root.Position.Y - 3), front.Z)
	else
		at = it.home.Position
	end
	it.busy = false
	place(it, at, false)
	it.model:SetAttribute("ThrowBusy", nil)
	if it.wreck then
		wreckTimer(it, true)
	elseif not it.vehicle then
		it.landedAt = os.clock() -- out of place: it goes home later, once nobody is near
	end
	release(hero)
end

-- Fly a thing on the shared arc and call `landed` when it lands (the server's pose waits for the landing;
-- every client flies it from the ThrowFly)
local function fly(
	it: It,
	from: Vector3,
	to: Vector3,
	time: number,
	peak: number,
	by: any?,
	landed: (() -> ())?
)
	it.busy = true
	it.model:SetAttribute("ThrowBusy", true)
	if not it.vehicle then
		it.model:PivotTo(CFrame.new(from))
	end
	Net.fireAll("ThrowFly", it.id, from, to, time, peak, if by and by.player then by.player.UserId else 0)
	CombatService.after(time, function()
		it.busy = false
		it.model:SetAttribute("ThrowBusy", nil)
		place(it, to, true, to - from)
		if it.wreck then
			wreckTimer(it, true)
		elseif not it.vehicle then
			it.landedAt = os.clock()
		end
		if landed then
			landed()
		end
	end)
end

-- Props knocked over by a landing next to them (they come back with the rest)
local function scatter(at: Vector3, radius: number, except: number)
	for _, it in items do
		if it.id ~= except and not it.vehicle and not busy(it) then
			local d = Vector3.new(it.x - at.X, 0, it.z - at.Z)
			if d.Magnitude <= radius then
				local dir = if d.Magnitude > 0.1 then d.Unit else Vector3.new(1, 0, 0)
				local from = Vector3.new(it.x, it.y + 1, it.z)
				fly(it, from, Vector3.new(it.x, it.y, it.z) + dir * 6, 0.4, 3, nil)
			end
		end
	end
end

local function land(hero: any, it: It, from: Vector3, to: Vector3, titan: boolean?)
	local hit = ThrowMath.hit(T, it.weight, titan)
	local n = CombatService.thrown(hero, to, from, hit)
	scatter(to, hit.radius, it.id)
	ThrowService.Thrown:Fire(hero, it.kind, it.weight, n)
end

-- Where a throw from `from` toward `aim` comes down: the weight's range, stopped by a wall, on the ground
-- (and where it met a wall in flight, if it did: destroy-all round 4, ImpactService.throwWall breaks it there)
local function landing(
	it: It,
	from: Vector3,
	aim: Vector3,
	rangeMult: number?
): (Vector3, number, number, Vector3?)
	local tx, ty, tz = ThrowMath.arc(T, it.weight, from.X, from.Y, from.Z, aim.X, aim.Y, aim.Z, rangeMult)
	local to = Vector3.new(tx, ty, tz)
	rayParams.FilterDescendantsInstances = skip()
	local wall = Workspace:Raycast(from, to - from, rayParams)
	local wallAt: Vector3? = nil
	if wall then
		to = wall.Position + wall.Normal * 1.5
		if math.abs(wall.Normal.Y) < 0.5 then
			wallAt = wall.Position
		end
	end
	local gy = ground(to.X, to.Y + 2, to.Z, 300)
	to = Vector3.new(to.X, gy or Config.City.ground.y, to.Z)
	local _, _, _, time, peak = ThrowMath.arc(T, it.weight, from.X, from.Y, from.Z, to.X, to.Y, to.Z, 10)
	return to, time, peak, wallAt
end

local function canGrab(hero: any): boolean
	return hero.alive
		and not hero.carry
		and not hero.traveling
		and not hero.channel
		and not HeroService.disabled(hero)
		and not BlockService.blocking(hero)
end

local function grab(hero: any, id: number, yanked: boolean?, taken: boolean?)
	if id == 0 then
		if hero.carry then
			setDown(hero)
		end
		return
	end
	if hero.carry then
		if hero.carry.id == id then
			setDown(hero) -- Grab again: set it down
		end
		return
	end
	local it = items[id]
	local root = HeroService.rootPart(hero)
	if not it or not root or busy(it) or not canGrab(hero) then
		return
	end
	-- (Yank, the Swing's earned rank 3 move: whatever it pulls in, it holds; it never comes from Robux)
	if not yanked and not ThrowMath.canLift(T, it.kind, hero.classId, HeroService.awakened(hero)) then
		return
	end
	local p = root.Position
	local d = Vector3.new(it.x - p.X, 0, it.z - p.Z).Magnitude
	local reach = T.reach + (if yanked then 12 else 3) -- a little slack for lag (a yank: for the pull's end)
	if d > reach or math.abs(it.y - p.Y) > reach then
		return
	end
	if it.vehicle and not taken and not VehicleService.take(it.vehicle) then
		return
	end
	it.busy = true
	it.landedAt = nil
	it.model:SetAttribute("ThrowBusy", true)
	if it.wreck then
		it.model:SetAttribute("WreckEnds", nil) -- held: no flicker, it waits for its landing
	end
	local grip = attach(it, hero, root)
	hero.carry = { id = id, since = os.clock(), grip = grip }
	HeroService.applyWalkSpeed(hero)
	sendState(hero)
	ThrowService.Grabbed:Fire(hero, it.kind)
end

-- Throw a held live robot along the aim: it flies as knock "thrown" and smashes through what it meets
local function throwRobot(hero: any, aim: Vector3)
	local c = hero.carry
	local root = HeroService.rootPart(hero)
	if not c or not root or not ThrowMath.lifted(T, c.since, os.clock()) or HeroService.disabled(hero) then
		return
	end
	local id = c.robot
	local from = if c.box
		then (root.CFrame * c.box).Position
		else root.Position + Vector3.new(0, T.overhead, 0)
	local dir = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
	if dir.Magnitude < 0.5 then
		dir = root.CFrame.LookVector
	end
	EnemyService.hold(id, nil)
	release(hero)
	hero.lastCast = os.clock()
	if EnemyService.alive(id) then
		local e = EnemyService.get(id)
		if e then
			e.x, e.y, e.z = from.X, from.Y, from.Z
		end
		local plan = KnockRules.plan(Config.Combat.knock, "thrown")
		EnemyService.launch(id, dir.Unit, plan.dist, plan.lift, plan.speed, hero.id)
		EnemyService.applyStatus(id, "stun", plan.dist / math.max(plan.speed, 1) + 0.5)
	end
	ThrowService.Thrown:Fire(hero, "robot", "medium", 0)
end

local function throw(hero: any, aim: Vector3)
	local c = hero.carry
	if c and c.robot then
		throwRobot(hero, aim)
		return
	end
	local it = c and items[c.id]
	local root = HeroService.rootPart(hero)
	if not it or not root or not ThrowMath.lifted(T, c.since, os.clock()) or HeroService.disabled(hero) then
		return
	end
	local from = heldAt(it, root)
	if (aim - from).Magnitude > 1000 then
		return
	end
	detach(it)
	hero.carry = nil
	HeroService.applyWalkSpeed(hero)
	sendState(hero)
	hero.lastCast = os.clock()
	local to, time, peak, wallAt = landing(it, from, aim)
	fly(it, from, to, time, peak, hero, function()
		if wallAt then
			ImpactService.throwWall(hero, it.weight, wallAt, wallAt - from) -- it smashes into the wall it met
		end
		land(hero, it, from, to)
	end)
end

-- Lift and Throw with nothing in its grip: the nearest thing in the Titan's reach, any weight
local function titanLift(hero: any, origin: Vector3, to: Vector3, delay: number): boolean
	local id = ThrowMath.nearest(items, origin.X, origin.Y, origin.Z, T.titan.reach, function(kind)
		return ThrowMath.canLift(T, kind, hero.classId, true, true)
	end)
	local it = id and items[id]
	if not it or busy(it) or (it.vehicle and not VehicleService.take(it.vehicle)) then
		return false
	end
	local from = Vector3.new(it.x, it.y + 2, it.z)
	fly(it, from, to, delay, 14, hero, function()
		scatter(to, T.weights[it.weight].radius, it.id)
		ThrowService.Thrown:Fire(hero, it.kind, it.weight, 0)
	end)
	return true
end

function ThrowService.carrying(hero: any): string?
	local c = hero.carry
	if c and c.robot then
		return "robot"
	end
	local it = c and items[c.id]
	return it and it.kind
end

---------------------------------------------------------------------------
-- Grab a robot and swing it (Config.Throw.swing)
---------------------------------------------------------------------------

local S = T.swing
local swinging: { [any]: { start: number, yaw: number } } = {} -- hero -> the swing being drawn (a live robot's whirl)

-- Grab a live robot that is stunned (or flying from a hit): it is held overhead and thinks no more
local function grabRobot(hero: any, id: number, yanked: boolean?)
	if hero.carry or not canGrab(hero) then
		return
	end
	local root = HeroService.rootPart(hero)
	local e = EnemyService.get(id)
	-- (never a robot of another run: a private mission run's are its party's alone, PhaseService)
	if not root or not e or not e.alive or e.held or not EnemyService.reaches(id, hero) then
		return
	end
	local now = EnemyService.now()
	local st = Status.get(e.status, "stun", now)
	local left = if st then st.untilT - now else 0
	if e.launch then
		left = math.max(left, S.robot.stunAtLeast)
	end
	if not ThrowMath.canHoldRobot(T, e.cfg, left) then
		return
	end
	local p = root.Position
	if (Vector3.new(e.x, e.y, e.z) - p).Magnitude > S.robot.reach + (if yanked then 12 else 4) then -- lag slack
		return
	end
	EnemyService.hold(id, hero.id)
	-- held like any big thing: overhead on both fists (or floated by a Gravity or Mind hero); every device draws it
	-- there from the same CarryPose sums (ThrowClient), the server keeps its middle for the hits
	local grip = gripFor(hero, "robot")
	local body = ThrowService.bodyOf(root.Parent)
	local h = (e.cfg.body and e.cfg.body.height) or 5
	local hold = body
		and CarryPose.hold(
			T,
			body,
			grip,
			HeroAnim.sample(CarryPose.CLIP[grip], 0),
			CarryPose.robotSize(h),
			true
		)
	hero.carry = {
		id = ROBOT_HOLD,
		robot = id,
		since = os.clock(),
		swings = 0,
		swingAt = -math.huge,
		grip = if hold then grip else "overhead",
		box = if hold then toCF(hold.box) else nil,
	}
	HeroService.applyWalkSpeed(hero)
	sendState(hero)
	ThrowService.Grabbed:Fire(hero, "robot")
end

-- Yank (the Swing's rank 3 move, nate 2026-11-20; MoveActService checks the move, cooldown and aim first): pull a
-- robot (kind 1) or a liftable thing (kind 2) to the hero over `time` s, then it is held like any grab, so Basic
-- swings it and a throw throws it. A robot is pulled (its pull status) and dazed `stun` s, then held; a prop flies in
-- on the shared arc (ThrowFly) and lands in the hands; a car comes straight to the hands. True when it began.
function ThrowService.yank(
	hero: any,
	kind: number,
	id: number,
	range: number,
	time: number,
	stun: number
): boolean
	local root = HeroService.rootPart(hero)
	if not root or hero.carry or not canGrab(hero) then
		return false
	end
	local p = root.Position
	if kind == 1 then
		local e = EnemyService.get(id)
		if
			not e
			or not e.alive
			or e.held
			or not EnemyService.reaches(id, hero)
			or not ThrowMath.canHoldRobot(T, e.cfg, stun)
		then
			return false
		end
		local d = (Vector3.new(e.x, e.y, e.z) - p).Magnitude
		if d > range + 6 then
			return false
		end
		EnemyService.applyStatus(id, "pull", time, {
			x = p.X,
			y = p.Y,
			z = p.Z,
			speed = math.max(Config.Abilities.status.pullSpeed, d / time),
			src = hero.id,
		})
		CombatService.after(time, function()
			if hero.alive and not hero.carry then
				EnemyService.applyStatus(id, "stun", stun, { src = hero.id })
				grabRobot(hero, id, true)
			end
		end)
		return true
	elseif kind == 2 then
		local it = items[id]
		if not it or busy(it) then
			return false
		end
		local at = Vector3.new(it.x, it.y, it.z)
		if (at - p).Magnitude > range + 6 then
			return false
		end
		local look = root.CFrame.LookVector
		local to = p + Vector3.new(look.X, 0, look.Z) * 3
		if it.vehicle then
			-- a car flies in on the shared arc (every device flies it from ThrowFly), out of the traffic, and
			-- lands in the hands; if the hero cannot hold it by then it is set down there (home in 30 s)
			if not VehicleService.take(it.vehicle) then
				return false
			end
			it.busy = true
			it.model:SetAttribute("ThrowBusy", true)
			Net.fireAll("ThrowFly", it.id, at, to, time, 4, if hero.player then hero.player.UserId else 0)
			CombatService.after(time, function()
				it.busy = false
				it.model:SetAttribute("ThrowBusy", nil)
				it.x, it.y, it.z = to.X, to.Y, to.Z
				if hero.alive and not hero.carry then
					grab(hero, id, true, true)
				end
				if not hero.carry or hero.carry.id ~= id then
					place(it, to, false)
				end
			end)
			return true
		end
		fly(it, at, to, time, 4, hero, function()
			if hero.alive and not hero.carry then
				grab(hero, id, true)
			end
		end)
		return true
	end
	return false
end

-- One swing of what the hero holds toward the aim: hits and throws the robots in the arc, breaks the wall in reach
local function swing(hero: any, aim: Vector3)
	local c = hero.carry
	local root = HeroService.rootPart(hero)
	if not c or not root or HeroService.disabled(hero) then
		return
	end
	local kind = if c.robot then "robot" else (items[c.id] and items[c.id].kind)
	if not ThrowMath.swingable(T, kind) then
		return
	end
	local now = os.clock()
	if
		not ThrowMath.lifted(T, c.since, now)
		or not ThrowMath.swingReady(T, c.swings or 0, c.swingAt or -math.huge, now)
	then
		return
	end
	c.swings = (c.swings or 0) + 1
	c.swingAt = now
	hero.lastCast = now
	local center = root.Position
	local dir = Vector3.new(aim.X - center.X, 0, aim.Z - center.Z)
	if dir.Magnitude < 0.5 then
		dir = root.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z).Unit
	CombatService.swung(hero, center, dir, S.arc, S.radius, S.coeff, c.robot)
	ImpactService.swingWall(hero, center + Vector3.new(0, 1.5, 0), dir, S.radius, S.struct)
	if c.robot then
		local e = EnemyService.get(c.robot)
		if e and e.alive then
			EnemyService.damage(c.robot, e.maxHealth * S.self, hero.id, nil)
		end
		swinging[hero] = { start = now, yaw = math.atan2(-dir.X, -dir.Z) }
	end
	-- a held prop swings on every device (ThrowClient): in the hands it follows the swing clip's right hand, a
	-- floated one whirls round the hero (CarryPose.whirl); the server's hits above do not wait for it
	for _, p in Players:GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - center).Magnitude <= 150 then
			Net.fire("SwingFx", p, {
				u = if hero.player then hero.player.UserId else 0,
				x = center.X,
				y = center.Y,
				z = center.Z,
				dx = dir.X,
				dz = dir.Z,
				arc = S.arc,
				r = S.radius,
				t = S.time,
				n = c.swings, -- the swing count, for the alternating swing clips
				slam = c.swings >= T.swing.max or nil, -- the last swing brings it down overhead
			})
		end
	end
	sendState(hero)
end

-- Held robots ride overhead (or whirl round the hero during a swing), every frame
local function holdStep()
	local now = os.clock()
	for _, hero in HeroService.all() do
		local c = hero.carry
		if c and c.robot then
			local e = EnemyService.get(c.robot)
			local root = HeroService.rootPart(hero)
			if not e or not e.alive or not root then
				EnemyService.hold(c.robot, nil)
				release(hero)
				swinging[hero] = nil
			else
				local pos = if c.box
					then (root.CFrame * c.box).Position
					else root.Position + Vector3.new(0, T.overhead, 0)
				local sw = swinging[hero]
				if sw then
					local u = (now - sw.start) / S.time
					if u >= 1 then
						swinging[hero] = nil
					else
						local a = sw.yaw + math.rad(S.arc / 2) * (1 - 2 * u)
						pos = root.Position + Vector3.new(-math.sin(a) * 5, 1, -math.cos(a) * 5)
					end
				end
				e.x, e.y, e.z = pos.X, pos.Y, pos.Z
			end
		end
	end
	for hero in swinging do
		if not hero.carry then
			swinging[hero] = nil
		end
	end
end

-- Props come home 60 s after landing once nobody is near; carriers drop at the limit or when stopped
local function step()
	local now = os.clock()
	for _, hero in HeroService.all() do
		local c = hero.carry
		if c then
			local root = HeroService.rootPart(hero)
			if
				not root
				or not hero.alive
				or hero.traveling
				or HeroService.disabled(hero)
				or ThrowMath.carryOver(T, c.since, now)
			then
				setDown(hero)
			end
		end
	end
	local spots: { Vector3 } = {}
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(spots, root.Position)
		end
	end
	for _, it in items do
		if it.vehicle and not it.busy and VehicleService.free(it.vehicle) then
			-- VehicleService's reset took it home
			local hp = it.home.Position
			it.x, it.y, it.z = hp.X, hp.Y, hp.Z
		end
		if it.wreck then
			if ThrowMath.wreckGone(it.endsAt or 0, now, busy(it)) then
				removeWreck(it)
			end
		elseif it.landedAt and not busy(it) then
			local near = math.huge
			for _, pos in spots do
				near = math.min(
					near,
					(pos - Vector3.new(it.x, it.y, it.z)).Magnitude,
					(pos - it.home.Position).Magnitude
				)
			end
			if ThrowMath.respawnReady(T, it.landedAt, now, near) then
				it.landedAt = nil
				it.model:PivotTo(it.home)
				local hp = it.home.Position
				it.x, it.y, it.z = hp.X, hp.Y - sizeOf(it).Y / 2, hp.Z
				Net.fireAll("ThrowBack", it.id)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Downed robots (WP6)
---------------------------------------------------------------------------

-- Falls apart: every screen pops it in sparks (WreckGone, ThrowFx) just before the parts go
removeWreck = function(it: It)
	items[it.id] = nil
	local m = it.model
	m:SetAttribute("WreckGone", true)
	task.delay(0.15, function()
		m:Destroy()
	end)
end

local function rgbOf(t: { number }?, fallback: Color3): Color3
	return if t then Color3.fromRGB(t[1], t[2], t[3]) else fallback
end

-- The wrecks' meshes (ReplicatedStorage.Art.Wrecks), looked up by name
local wreckFound: { [string]: MeshPart } = {}
local function wreckSource(name: string): MeshPart?
	local hit = wreckFound[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local root = art and art:FindFirstChild("Wrecks")
	local src = root and root:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		wreckFound[name] = src
		return src
	end
	return nil
end

-- The look's meshes on the heap's middle (visual only: no collisions, queries or touches, so the carry and the
-- landing see only the Body box); the dead eyes are named so ThrowFx flickers them
local function wreckMeshes(m: Model, kind: string, sx: number, sy: number, sz: number, base: CFrame)
	local mid = base * CFrame.new(0, sy / 2, 0)
	for _, mm in WreckArtKit.meshes(Config, kind, sx, sy, sz) do
		local src = wreckSource(mm.name)
		if not src then
			continue
		end
		local p = MeshFix.clone(src)
		for _, c in p:GetChildren() do
			if mm.maps and c:IsA("SurfaceAppearance") then
				c.AlphaMode = Enum.AlphaMode.Overlay
			else
				c:Destroy()
			end
		end
		p.Name = if WreckArtKit.isEyes(mm.name) then "Eyes" else mm.name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = Vector3.new(mm.size[1], mm.size[2], mm.size[3])
		p.CFrame = mid * CFrame.new(mm.offset[1], mm.offset[2], mm.offset[3]) * MeshFix.of(p) -- the import's turn
		p.Color = Color3.fromRGB(mm.color[1], mm.color[2], mm.color[3])
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[mm.mat]
		end)
		p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
		p.Transparency = mm.alpha
		p.Parent = m
	end
end

-- The heap: the chassis on its side in the suit colour, the head dropped beside it with its eyes dark, and an
-- arm across the top in the trim colour; or, once Art.Wrecks has every mesh of this kind's look, that look over
-- the hidden Body box (WreckArtKit)
local function wreckModel(kind: string, cfg: any, at: Vector3, yaw: number): Model
	local body = cfg.body or {}
	local sx, sy, sz = ThrowMath.wreckSize(T, cfg)
	local metal = rgbOf(body.metal, Color3.fromRGB(90, 90, 100))
	local function piece(
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanTouch = false
		p.CanCollide = name == "Body"
		p.Size = size
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = cf
		return p
	end
	local m = Instance.new("Model")
	m.Name = "Throwable_wreck"
	local base = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	local main = piece(
		"Body",
		Vector3.new(sx, sy, sz),
		base * CFrame.new(0, sy / 2, 0) * CFrame.Angles(0, 0, math.rad(8)),
		rgbOf(body.suit, metal),
		Enum.Material.Metal
	)
	main.Parent = m
	m:SetAttribute("ThrowKind", "wreck")
	m:SetAttribute("WreckOf", kind)
	-- the colours ThrowFx's sparks, eye blink and pop use
	m:SetAttribute("WreckSuit", main.Color)
	m:SetAttribute("WreckMetal", metal)
	m:SetAttribute("WreckEye", rgbOf(body.eye, Color3.fromRGB(255, 220, 80)))
	m.PrimaryPart = main
	if
		WreckArtKit.ready(Config, kind, function(name: string): boolean
			return wreckSource(name) ~= nil
		end)
	then
		main.Transparency = 1
		main.CastShadow = false
		wreckMeshes(m, kind, sx, sy, sz, base)
		return m
	end
	local hs = math.max(0.9, sy * 0.8)
	local head = piece(
		"Head",
		Vector3.new(hs, hs, hs),
		base
			* CFrame.new(sx * 0.55, hs / 2, -sz * 0.2)
			* CFrame.Angles(math.rad(20), math.rad(35), math.rad(70)),
		metal,
		Enum.Material.Metal
	)
	head.Parent = m
	local eye = piece(
		"Eyes",
		Vector3.new(hs * 0.7, hs * 0.18, 0.12),
		head.CFrame * CFrame.new(0, hs * 0.1, -hs / 2 - 0.05),
		rgbOf(body.eye, Color3.fromRGB(255, 220, 80)):Lerp(Color3.new(0.1, 0.1, 0.1), 0.6), -- powered down
		Enum.Material.SmoothPlastic
	)
	eye.Parent = m
	local arm = piece(
		"Arm",
		Vector3.new(sx * 0.9, math.max(0.5, sy * 0.3), math.max(0.5, sy * 0.3)),
		base * CFrame.new(-sx * 0.1, sy + 0.2, sz * 0.15) * CFrame.Angles(0, math.rad(25), math.rad(-6)),
		rgbOf(body.trim, metal),
		Enum.Material.Metal
	)
	arm.Parent = m
	return m
end

-- A robot a hero beat leaves its wreck where it fell, if it is a kind that does and there is room
local function spawnWreck(kind: string, pos: Vector3)
	local cfg = Config.Enemies[kind]
	if not ThrowMath.canWreck(cfg) or pos.Y < Config.World.coast.waterY then
		return
	end
	local gy = ground(pos.X, pos.Y + 2, pos.Z, W.maxDrop)
	if not gy then
		return
	end
	local list = {}
	for _, it in items do
		if it.wreck then
			table.insert(list, { id = it.id, busy = busy(it), born = it.born or 0 })
		end
	end
	local ok, evict = ThrowMath.wreckRoom(list, W.max)
	if not ok then
		return
	end
	if evict and items[evict] then
		removeWreck(items[evict])
	end
	local id = 0
	for _ = 1, 999 do
		wreckSeq = wreckSeq % 999 + 1
		if not items[WRECK_BASE + wreckSeq] then
			id = WRECK_BASE + wreckSeq
			break
		end
	end
	if id == 0 then
		return
	end
	local at = Vector3.new(pos.X, gy, pos.Z)
	local m = wreckModel(kind, cfg, at, math.rad((id * 137) % 360))
	m:SetAttribute("ThrowId", id)
	m.Parent = folder
	local it: It = {
		id = id,
		kind = "wreck",
		weight = T.kinds.wreck.weight,
		x = at.X,
		y = at.Y,
		z = at.Z,
		model = m,
		home = m:GetPivot(),
		wreck = true,
		born = os.clock(),
	}
	items[id] = it
	wreckTimer(it, false)
end

-- How many wrecks lie about now (tests and the Dev panel)
function ThrowService.wreckCount(): number
	local n = 0
	for _, it in items do
		if it.wreck then
			n += 1
		end
	end
	return n
end

local function buildProp(spot: ThrowMath.Spot, gy: number): It?
	local K = T.kinds[spot.kind]
	local size = Vector3.new(K.size[1], K.size[2], K.size[3])
	local cf = CFrame.new(spot.x, gy + size.Y / 2, spot.z) * CFrame.Angles(0, math.rad(spot.ry), 0)
	-- keep clear of anything already standing there (a kit lamp, a planter, a parked car's door)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { folder }
	if #Workspace:GetPartBoundsInBox(cf, size - Vector3.new(0.3, 0.6, 0.3), op) > 0 then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Throwable_" .. spot.kind
	local p = Instance.new("Part")
	p.Name = "Body"
	p.Anchored = true
	p.CanTouch = false
	p.Size = size
	p.Color = Color3.fromRGB(K.color[1], K.color[2], K.color[3])
	p.Material = (Enum.Material :: any)[K.material] or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = cf
	p.Parent = m
	m.PrimaryPart = p
	m:SetAttribute("ThrowId", spot.id)
	m:SetAttribute("ThrowKind", spot.kind)
	m.Parent = folder
	return {
		id = spot.id,
		kind = spot.kind,
		weight = K.weight,
		x = spot.x,
		y = gy,
		z = spot.z,
		model = m,
		home = cf,
	}
end

function ThrowService.init()
	folder = Instance.new("Folder")
	folder.Name = "Throwables"
	folder.Parent = Workspace
	local gy0 = Config.City.ground.y
	for _, spot in ThrowMath.place(T, Config) do
		local gy = ground(spot.x, gy0 + 60, spot.z, 120)
		-- only on the street level (a sidewalk or a kerb), never on a roof or a ledge
		if gy and gy < gy0 + 3 then
			local it = buildProp(spot, gy)
			if it then
				items[it.id] = it
			end
		end
	end
	for _, v in VehicleService.list do
		if T.kinds[v.kind] and T.kinds[v.kind].vehicle then
			local m = VehicleService.model(v.id)
			if m and m.PrimaryPart then
				local id = VEH_BASE + v.id
				m:SetAttribute("ThrowId", id)
				m:SetAttribute("ThrowKind", v.kind)
				items[id] = {
					id = id,
					kind = v.kind,
					weight = T.kinds[v.kind].weight,
					x = v.x,
					y = v.y,
					z = v.z,
					model = m,
					home = m:GetPivot(),
					vehicle = v.id,
				}
			end
		end
	end
	-- WP6: a robot a hero beat leaves its wreck (a kill with nobody behind it, a clear, leaves none)
	EnemyService.Killed:Connect(function(kind: string, by: number?, pos: Vector3, enemyId: number?)
		-- a dressed villain (a side quest finale's, WP5's Suspicious Hero costumes) is a person in its suit
		-- kind's rig: it leaves no robot wreck (review 2026-11-18; the Rogues File skips it the same way)
		local ident = enemyId and EnemyService.identity(enemyId)
		if by and typeof(pos) == "Vector3" and not (ident and ident.dress) then
			spawnWreck(kind, pos)
		end
	end)
	HeroService.speedHooks.carry = function(hero: any): number
		return if hero.carry then T.carrySpeed else 1
	end
	CombatService.titanLift = titanLift
	Net.on("WorldGrab", function(player: Player, id: number)
		local hero = HeroService.get(player)
		if hero then
			grab(hero, id)
		end
	end)
	Net.on("WorldThrow", function(player: Player, aim: Vector3)
		local hero = HeroService.get(player)
		if hero and hero.carry then
			throw(hero, aim)
		end
	end)
	Net.on("WorldGrabRobot", function(player: Player, id: number)
		local hero = HeroService.get(player)
		if hero then
			grabRobot(hero, id)
		end
	end)
	Net.on("WorldSwing", function(player: Player, aim: Vector3)
		local hero = HeroService.get(player)
		if hero and hero.carry then
			swing(hero, aim)
		end
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("ThrowHold", holdStep))
	HeroService.Removed:Connect(function(hero: any)
		if hero.carry then
			setDown(hero)
		end
	end)
	HeroService.Defeated:Connect(function(hero: any)
		if hero.carry then
			setDown(hero)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			step()
		end
	end)
end

return ThrowService
