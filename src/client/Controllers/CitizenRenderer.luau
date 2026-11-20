-- CitizenRenderer: draws the server's citizens from Citizen.Delta (4 Hz, unreliable; CitizenBuffer). Packets
-- are buffered by arrival time and drawn 0.3 s in the past, interpolated, so 4 Hz walks smoothly. Every
-- citizen is on the same blocky R15 rig as the heroes (nate, 2026-11-16: "literally everyone should be r15";
-- NpcRig): pooled by its 6 colour sets (shirt on the torso and sleeves, skin on the forearms, hands and head
-- with the classic face, pants and darker shoes), with blocky hair picked from its id, posed on its R15
-- joints in code: a walk swing, a standing idle, and a run with arms up when fleeing. Far citizens pose every
-- few frames. Citizens are never hurt or shown hurt (spec: Destruction); a hidden citizen (safe in a shelter)
-- is simply not sent. The device preset (QualityController) sets how many are drawn (the nearest) and how
-- often far ones pose (phone pass: low draws 30 of the 60, so half the bodies and clothes Textures).
-- Motion (2026-11-19, as the robots since 2026-11-18): the nearest citizens play Roblox's own R15 idle, walk and
-- run (Controllers.NpcLoco, Shared.LocoMath, Config.Destruction.citizens.loco), speed-matched to their drawn
-- motion, each with its own idle; the flee is the run with the arms thrown up, and the lore step 12 cheers and
-- flinches are arms written over the clips (NpcRig.over, so the feet keep walking). Only the nearest few per
-- preset animate (citizenAnimNear, citizenAnimMax; phones 8); farther ones keep the code poses below, stepped
-- every few frames. Drawn in PreSimulation, after the Animator, so the poses written over the clips show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CitizenBuffer = require(Shared:WaitForChild("CitizenBuffer"))
local Rng = require(Shared:WaitForChild("Rng"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local BodyShape = require(Shared:WaitForChild("BodyShape"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local ClothesMap = require(Shared:WaitForChild("ClothesMap"))
local QualityRules = require(Shared:WaitForChild("QualityRules"))
local NpcAnim = require(Shared:WaitForChild("NpcAnim")) -- pt-anims: idle gestures
local RepTiers = require(Shared:WaitForChild("RepTiers")) -- lore step 12: citizens cheer or flinch
local Players = game:GetService("Players")

local LocoMath = require(Shared:WaitForChild("LocoMath"))

local QualityController = require(script.Parent.QualityController)
local NpcLoco = require(script.Parent.NpcLoco)
local LifePlan = require(Shared:WaitForChild("LifePlan")) -- the living world: point, photo, cheer

local CitizenRenderer = {}
CitizenRenderer.hidden = false -- PrologueFx: true while the hero is in the prologue

local C = Config.Destruction.citizens
local LOCO = C.loco
local FLEE, PAUSE = 2, 1
local SIDES = { { "Left", -1 }, { "Right", 1 } }
-- one rig layout per body (C.bodies: gender and build), each in its body set's shape
local layouts: { [number]: RigMath.Layout } = {}
local function bodyLook(i: number): any
	local b = C.bodies[i] or C.bodies[1]
	return { gender = b[1], build = b[2], height = 3 }
end
local function layoutOf(i: number): RigMath.Layout
	local l = layouts[i]
	if not l then
		local factors = BodyShape.factors(Config, bodyLook(i))
		l = RigMath.layout(Config.HeroRig, factors, 1)
		layouts[i] = l
	end
	return l
end

-- The Roblox look (once the heroes' clothes are uploaded): the uploaded shirts, pants and faces citizens pick
-- from by their id
local function uploaded(map: { [string]: number }): { string }
	local out = {}
	for _, id in map do
		if id ~= 0 then
			table.insert(out, "rbxassetid://" .. id)
		end
	end
	table.sort(out) -- the same order on every device, so a citizen looks the same to everyone
	return out
end
local SHIRTS = uploaded(Config.Creator.clothes.shirts)
local PANTS = uploaded(Config.Creator.clothes.pants)
-- Roblox catalog faces (nate, 2026-11-19: NPCs should look like Roblox avatars); the old drawn faces only if none
local FACES: { string } = NpcRig.catalogFaces()
for _, fname in if #FACES > 0 then {} else Config.NpcLooks.faceOrder do
	local f = Config.NpcLooks.faces[fname]
	if f and f.human ~= 0 then
		table.insert(FACES, "rbxassetid://" .. f.human)
	end
end
local ROBLOX = Config.Creator.clothes.on and #SHIRTS > 0 and #PANTS > 0
local TINTS = C.clothesTints

type Body = {
	model: Model,
	rig: NpcRig.Rig,
	hair: BasePart,
	group: number, -- its hair group (keyOf)
	clothes: { [string]: { Texture } }?, -- the Roblox look's Textures by part
	shown: number, -- how much of them is drawn (ClothesMap.level)
	face: Decal?,
	color: number,
	key: number,
	pos: Vector3,
	yaw: number,
	phase: number,
	speed: number,
	state: number,
	-- Roblox's own idle, walk and run on this body (NpcLoco), loaded the first time it is near enough
	loco: NpcLoco.Loco?,
	locoTried: boolean,
	animated: boolean, -- the clips play on it this frame
}

local snapshots: { { t: number, rows: { [number]: CitizenBuffer.Row } } } = {}
local lastSeq = 0
local live: { [number]: Body } = {}
local pool: { [number]: { Body } } = {}
local folder: Folder
local frame = 0

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- A pool key: the colour set, the body and the hair group (a pooled body only goes back to a citizen with all
-- three the same). Each hair group's rigs wear the same few catalog hairs (NpcRig.showHair), so a citizen's
-- hair is the same on every device.
local HAIR_GROUPS = 6
local function keyOf(color: number, bodyIndex: number, group: number): number
	return (color * 16 + bodyIndex) * HAIR_GROUPS + group
end

local function newBody(color: number, bodyIndex: number, group: number): Body
	local set = C.colors[color] or C.colors[1]
	local rig = NpcRig.person(
		layoutOf(bodyIndex),
		"Citizen" .. group,
		rgb(set[1]),
		rgb(set[2]),
		rgb(set[3]),
		rgb(C.hair[1]),
		BodyShape.setKey(Config, bodyLook(bodyIndex))
	)
	rig.model.Parent = folder
	local clothes: { [string]: { Texture } }? = nil
	if ROBLOX then
		-- skin under the clothes (short sleeves, shorts and the hands show it); assign picks the outfit
		for _, p in rig.parts do
			p.Color = rgb(set[3])
		end
		clothes = NpcRig.dressPair(rig, SHIRTS[1], PANTS[1], Config.NpcLooks.offsetSign)
	end
	return {
		model = rig.model,
		rig = rig,
		hair = rig.model:FindFirstChild("Hair") :: BasePart,
		clothes = clothes,
		face = rig.parts.Head:FindFirstChild("face") :: Decal?,
		color = color,
		key = keyOf(color, bodyIndex, group),
		group = group,
		pos = Vector3.zero,
		yaw = 0,
		phase = 0,
		speed = 0,
		state = 0,
		shown = 2,
		loco = nil,
		locoTried = false,
		animated = false,
	}
end

local function acquire(color: number, bodyIndex: number, group: number): Body
	local list = pool[keyOf(color, bodyIndex, group)]
	local body = list and table.remove(list)
	if body then
		body.model.Parent = folder
		return body
	end
	return newBody(color, bodyIndex, group)
end

-- Back to the code poses: the clips stop and every joint is written again
local function unanimate(body: Body)
	if body.loco then
		NpcLoco.stop(body.loco)
	end
	if body.animated then
		body.animated = false
		NpcRig.overDone(body.rig)
		NpcRig.rest(body.rig)
	end
end

local function release(body: Body)
	unanimate(body)
	body.model.Parent = nil
	pool[body.key] = pool[body.key] or {}
	table.insert(pool[body.key], body)
end

-- The Roblox look: this citizen's shirt, pants, their colours and its face, all from its id
local function dress(body: Body, id: number)
	local clothes = body.clothes
	if not clothes then
		return
	end
	local h = Rng.hash(id, 6007)
	local shirt = SHIRTS[h % #SHIRTS + 1]
	local pants = PANTS[(h // 13) % #PANTS + 1]
	local top = rgb(TINTS.shirts[(h // 211) % #TINTS.shirts + 1])
	local bottom = rgb(TINTS.pants[(h // 4099) % #TINTS.pants + 1])
	NpcRig.redressPair(body.rig, clothes, shirt, pants, top, bottom)
	if body.face and #FACES > 0 then
		body.face.Texture = FACES[(h // 77777) % #FACES + 1]
	end
end

-- Its face and catalog hair, from its id (with or without the Roblox clothes)
local function looks(body: Body, id: number)
	local h = Rng.hash(id, 6007)
	if body.face and #FACES > 0 then
		body.face.Texture = FACES[(h // 77777) % #FACES + 1]
	end
	NpcRig.showHair(body.rig, body.group * 131, h // 1171)
end

-- The park's people (2026-11-20, Fx.ParkLife): a pooled citizen body for a jogger, a walker, a picnic or a busker,
-- dressed from its id like any citizen (catalog face and hair, the uploaded clothes); giveBack returns it to the pool.
-- The park poses and places it itself (this module's render never touches a borrowed body).
function CitizenRenderer.borrow(id: number): Body
	local h = Rng.hash(id, 4243)
	local color = h % #C.colors + 1
	local bodyIndex = (h // 7) % #C.bodies + 1
	local group = (h // 61) % HAIR_GROUPS
	local body = acquire(color, bodyIndex, group)
	dress(body, id)
	looks(body, id)
	return body
end

function CitizenRenderer.giveBack(body: Body)
	release(body)
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- Lore step 12 (the city remembers): heroes near enough with a reputation tier (their RepTier attribute) get a
-- reaction from walking and standing citizens: a cheer for the Vigil, a flinch for the Syndicate (Shared.RepTiers
-- .reaction). The heroes are scanned a few times a second; only citizens posed this frame react.
local R = Config.Remembers.citizens
local reactors: { { pos: Vector3, side: string, tier: number } } = {}
local lastScan = 0
-- the living world (2026-11-19): every hero near enough gets looked at (LifePlan.react: a point at one flying or
-- racing by, a phone held up at one standing near, a cheer after a big hit), Config.Life.citizens
local LC = Config.Life.citizens
local watched: { { pos: Vector3, speed: number, air: boolean } } = {}
local lastBang: () -> (Vector3, number) = function()
	return Vector3.zero, -math.huge
end
function CitizenRenderer.setBang(fn: () -> (Vector3, number))
	lastBang = fn
end
local function scanReactors(now: number)
	if now - lastScan < R.every then
		return
	end
	lastScan = now
	table.clear(reactors)
	table.clear(watched)
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			table.insert(watched, {
				pos = root.Position,
				speed = root.AssemblyLinearVelocity.Magnitude,
				air = hum ~= nil and hum.FloorMaterial == Enum.Material.Air,
			})
		end
	end
	for _, p in Players:GetPlayers() do
		local tier = p:GetAttribute("RepTier")
		local ch = p.Character
		local root = ch and ch.PrimaryPart
		if type(tier) == "number" and tier >= R.minTier and root then
			local side = p:GetAttribute("Side")
			table.insert(reactors, {
				pos = root.Position,
				side = if side == "villain" then "villain" else "hero",
				tier = tier,
			})
		end
	end
end

local function lookAt(pos: Vector3, key: number): string?
	local best, bestD = nil, math.huge
	for _, w in watched do
		local d = (w.pos - pos).Magnitude
		if d < bestD then
			best, bestD = w, d
		end
	end
	local at, when = lastBang()
	local since = if (at - pos).Magnitude <= LC.cheer then os.clock() - when else math.huge
	if not best then
		return if since <= LC.cheerFor then "cheer" else nil
	end
	return LifePlan.react(LC, bestD, best.speed, best.air, since, key)
end

local function reactionAt(pos: Vector3, fleeing: boolean, key: number?): string?
	if fleeing then
		return nil
	end
	if #reactors == 0 then
		return lookAt(pos, key or 0)
	end
	local best, bestD = nil, math.huge
	for _, r in reactors do
		local d = (r.pos - pos).Magnitude
		if d < bestD then
			best, bestD = r, d
		end
	end
	return (best and RepTiers.reaction(Config, best.side, best.tier, bestD, fleeing)) or lookAt(pos, key or 0)
end

-- The living world's point and photo poses over a walk or a clip (`over`: write over Roblox's clips)
local flashAt: { [any]: number } = {}
local function lifePose(body: any, react: string, over: boolean)
	local rig = body.rig
	local set = if over then NpcRig.over else NpcRig.turn
	if react == "point" then
		set(rig, "RightShoulder", CFrame.Angles(math.rad(-100), 0, math.rad(8)))
		set(rig, "RightElbow", CFrame.Angles(math.rad(5), 0, 0))
	elseif react == "photo" then
		-- both hands up in front of the face, a phone between them; a flash now and then
		for _, side in SIDES do
			local name, sign = side[1], side[2]
			set(rig, name .. "Shoulder", CFrame.Angles(math.rad(-95), 0, -sign * 0.5))
			set(rig, name .. "Elbow", CFrame.Angles(math.rad(70), 0, 0))
		end
		local now = os.clock()
		local hand = rig.parts and rig.parts.RightHand
		if hand and now >= (flashAt[body] or 0) then
			flashAt[body] = now + LC.flashEvery * (0.7 + (body.key % 7) * 0.1)
			local f = Instance.new("Part")
			f.Name = "PhotoFlash"
			f.Anchored = true
			f.CanCollide = false
			f.CanQuery = false
			f.CanTouch = false
			f.CastShadow = false
			f.Material = Enum.Material.Neon
			f.Color = Color3.new(1, 1, 1)
			f.Shape = Enum.PartType.Ball
			f.Size = Vector3.new(0.5, 0.5, 0.5)
			f.CFrame = hand.CFrame * CFrame.new(0, 0.4, -0.5)
			f.Parent = Workspace
			task.delay(0.08, function()
				f:Destroy()
			end)
		end
	end
end

-- A standing citizen's idle gesture (pt-anims, Shared.NpcAnim): every GESTURE_EVERY seconds, on its own beat
-- (from its key), one of the people clips plays over Roblox's idle on the upper body: a look round, a check of
-- the time, a bit of talk, a shrug, a point. Stateless: the beat and the pick come from the clock and the key.
local GESTURE_EVERY = 8
local gestureScratch: { [string]: { number } } = {}
local function gesture(body: Body)
	local now = os.clock() + (body.key % 97) * 0.83
	local cycle = math.floor(now / GESTURE_EVERY)
	local t = now - cycle * GESTURE_EVERY
	local r = ((body.key * 0.618 + cycle * 0.371) % 1)
	if r > 0.7 then
		return -- a beat with no gesture now and then, so a crowd is never all moving at once
	end
	local clip = NpcAnim.pick(NpcAnim.PEOPLE.citizen.idle, r / 0.7)
	local c = NpcAnim.CLIPS[clip]
	if t >= c.dur then
		return
	end
	local w = NpcAnim.weight(t, c.dur, NpcAnim.people.fade, false)
	local rig = body.rig
	for joint, a in NpcAnim.sample(clip, t, gestureScratch) do
		NpcRig.over(
			rig,
			joint,
			NpcRig.animBase(rig, joint):Lerp(CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3])), w)
		)
	end
end

-- Over Roblox's clips (an animated citizen): only what differs from a plain idle, walk or run, written every
-- frame after the Animator: the flee's arms thrown up, or a cheer's or flinch's arms (the legs keep the clip)
local function overClips(body: Body, react: string?)
	local rig = body.rig
	if body.state == FLEE then
		local flail = math.sin(os.clock() * 16 + body.phase) * 0.25
		for _, side in SIDES do
			local name, sign = side[1], side[2]
			NpcRig.over(rig, name .. "Shoulder", CFrame.Angles(LOCO.fleeArms + flail * sign, 0, sign * 0.2))
			NpcRig.over(rig, name .. "Elbow", CFrame.Angles(math.rad(20), 0, 0))
		end
	elseif react == "cheer" then
		local wave = math.sin(os.clock() * 9) * 0.35
		for _, side in SIDES do
			local name, sign = side[1], side[2]
			NpcRig.over(rig, name .. "Shoulder", CFrame.Angles(math.rad(-160) + wave * sign, 0, sign * 0.25))
			NpcRig.over(rig, name .. "Elbow", CFrame.Angles(math.rad(15), 0, 0))
		end
	elseif react == "flinch" then
		NpcRig.over(rig, "Waist", NpcRig.animBase(rig, "Waist") * CFrame.Angles(math.rad(14), 0, 0))
		for _, side in SIDES do
			local name, sign = side[1], side[2]
			NpcRig.over(rig, name .. "Shoulder", CFrame.Angles(math.rad(-85), 0, -sign * 0.35))
			NpcRig.over(rig, name .. "Elbow", CFrame.Angles(math.rad(95), 0, 0))
		end
	elseif react == "point" or react == "photo" then
		lifePose(body, react, true)
	elseif body.state == PAUSE and body.speed <= 0.8 then
		gesture(body)
	end
end

-- Pose one citizen (pos is the feet): the root goes on the BulkMoveTo lists, the R15 joints turn when
-- `joints` is true. `animated`: Roblox's clips play on it (NpcLoco), so only the root and overClips.
local function pose(
	body: Body,
	dt: number,
	roots: { BasePart },
	cframes: { CFrame },
	joints: boolean,
	animated: boolean
)
	local moving = body.speed > 0.8
	local fleeing = body.state == FLEE
	local react = if joints or animated then reactionAt(body.pos, fleeing, body.key) else nil
	body.phase += dt * (if fleeing then 14 else 8) * (if moving then 1 else 0)
	local bob = if moving and not animated then math.abs(math.sin(body.phase)) * 0.15 else 0
	if react == "cheer" then
		bob += math.abs(math.sin(os.clock() * 7)) * 0.35 -- little hops
	end
	table.insert(roots, body.rig.root)
	table.insert(
		cframes,
		CFrame.new(body.pos + Vector3.new(0, body.rig.layout.ground + bob, 0)) * CFrame.Angles(0, body.yaw, 0)
	)
	if animated then
		overClips(body, react)
		return
	end
	if not joints then
		return
	end
	local rig = body.rig
	local swing = if moving then math.sin(body.phase) * (if fleeing then 0.9 else 0.55) else 0
	NpcRig.turn(rig, "Waist", if fleeing then CFrame.Angles(math.rad(-12), 0, 0) else CFrame.identity)
	local armUp = if fleeing then math.rad(-150) else 0
	local idle = if body.state == PAUSE then math.sin(os.clock() * 1.5) * 0.05 else 0
	for _, side in SIDES do
		local name, sign = side[1], side[2]
		NpcRig.turn(rig, name .. "Hip", CFrame.Angles(swing * sign, 0, 0))
		NpcRig.turn(rig, name .. "Knee", CFrame.Angles(-math.max(0, swing * sign) * 0.6, 0, 0))
		NpcRig.turn(rig, name .. "Shoulder", CFrame.Angles(armUp - swing * sign * 0.8 - idle * sign, 0, 0))
		NpcRig.turn(rig, name .. "Elbow", CFrame.Angles(if moving then math.rad(20) else math.rad(5), 0, 0))
	end
	-- lore step 12: the reaction over the walk (arms only, so the feet keep walking)
	if react == "cheer" then
		local wave = math.sin(os.clock() * 9) * 0.35
		for _, side in SIDES do
			local name, sign = side[1], side[2]
			NpcRig.turn(rig, name .. "Shoulder", CFrame.Angles(math.rad(-160) + wave * sign, 0, sign * 0.25))
			NpcRig.turn(rig, name .. "Elbow", CFrame.Angles(math.rad(15), 0, 0))
		end
	elseif react == "flinch" then
		NpcRig.turn(rig, "Waist", CFrame.Angles(math.rad(14), 0, 0))
		for _, side in SIDES do
			local name, sign = side[1], side[2]
			NpcRig.turn(rig, name .. "Shoulder", CFrame.Angles(math.rad(-85), 0, -sign * 0.35))
			NpcRig.turn(rig, name .. "Elbow", CFrame.Angles(math.rad(95), 0, 0))
		end
	elseif react == "point" or react == "photo" then
		lifePose(body, react, false)
	end
end

local lastRender = os.clock()
local function render()
	local now = os.clock()
	local dt = math.min(0.1, now - lastRender)
	lastRender = now
	local n = #snapshots
	if n == 0 then
		return
	end
	scanReactors(now)
	local renderT = now - C.drawDelay
	local a, b = snapshots[1], snapshots[n]
	for i = n - 1, 1, -1 do
		if snapshots[i].t <= renderT then
			a, b = snapshots[i], snapshots[i + 1]
			break
		end
	end
	local alpha = if b.t > a.t then math.clamp((renderT - a.t) / (b.t - a.t), 0, 1) else 1
	local newest = snapshots[n].rows
	local cam = Workspace.CurrentCamera.CFrame.Position
	local Q = QualityController.preset
	-- the prologue's quiet world (PrologueFx): its own crowd only, no city citizens wandering through the story
	local most = if CitizenRenderer.hidden then 0 else Q.citizensDrawn or C.max
	local drawn = QualityRules.nearest(newest, cam.X, cam.Z, most, live)
	for id, body in live do
		local row = drawn[id]
		if not row or row.color ~= body.color then
			release(body)
			live[id] = nil
		end
	end
	local roots, cframes = {}, {}
	frame += 1
	-- the nearest few play Roblox's own clips (LocoMath.pickAnimated: a phone 8 within 50 studs)
	local animNear = if LOCO.on then Q.citizenAnimNear or LOCO.near else 0
	local rows = {}
	for id, rb in drawn do
		local dx, dz = rb.x - cam.X, rb.z - cam.Z
		table.insert(rows, { id = id, dist = math.sqrt(dx * dx + dz * dz) })
	end
	local current = {}
	for id, body in live do
		if body.animated then
			current[id] = true
		end
	end
	local anim = LocoMath.pickAnimated(rows, current, animNear, Q.citizenAnimMax or LOCO.max, LOCO.keep)
	-- chat partners (Everything Left 275): stopped citizens pair with the nearest other stopped one in reach
	local stopped = {}
	for id, rb in drawn do
		if rb.state == PAUSE then
			table.insert(stopped, { id = id, x = rb.x, z = rb.z })
		end
	end
	local partner: { [number]: number } = {}
	local reach = (LC.chat or 0) * (LC.chat or 0)
	for i, s0 in stopped do
		local best, bestD = nil, reach
		for j, s1 in stopped do
			if i ~= j then
				local dx, dz = s1.x - s0.x, s1.z - s0.z
				local d = dx * dx + dz * dz
				if d < bestD and d > 0.25 then
					best, bestD = j, d
				end
			end
		end
		if best then
			-- facing: the yaw whose look (-sin, -cos) points at the partner
			partner[s0.id] = math.atan2(-(stopped[best].x - s0.x), -(stopped[best].z - s0.z))
		end
	end
	for id, rb in drawn do
		local ra = a.rows[id] or b.rows[id] or rb
		local rbb = b.rows[id] or rb
		local pos = Vector3.new(ra.x, ra.y, ra.z):Lerp(Vector3.new(rbb.x, rbb.y, rbb.z), alpha)
		local body = live[id]
		if not body then
			body = acquire(rb.color, Rng.hash(id, 5113) % #C.bodies + 1, Rng.hash(id, 8761) % HAIR_GROUPS)
			body.hair.Color = rgb(C.hair[Rng.hash(id, 4409) % #C.hair + 1])
			dress(body, id)
			looks(body, id)
			NpcRig.rest(body.rig)
			live[id] = body
			body.pos = pos
			body.yaw = rb.yaw
		end
		local moved = Vector3.new(pos.X - body.pos.X, 0, pos.Z - body.pos.Z)
		body.speed += (moved.Magnitude / math.max(dt, 1e-3) - body.speed) * math.min(1, dt * 8)
		body.pos = pos
		local chatYaw = partner[id]
		body.yaw = if chatYaw
			then lerpAngle(body.yaw, chatYaw, math.min(1, dt * 4))
			else lerpAngle(body.yaw, rbb.yaw, math.min(1, dt * 10))
		body.state = rb.state
		local dist = (pos - cam).Magnitude
		if body.clothes then
			local level = ClothesMap.level(dist, Q.clothesNear or 25, Q.clothesFar or 80, body.shown)
			if level ~= body.shown then
				body.shown = level
				NpcRig.showClothes(body.rig, body.clothes, level)
			end
		end
		local animated = false
		if anim[id] then
			if not body.loco and not body.locoTried then
				body.locoTried = true
				local pick, rate, offset = LocoMath.idlePick(Rng.hash(id, 3301), LOCO.idles, LOCO.idleRate)
				local L = body.rig.layout
				body.loco = NpcLoco.new(body.model, L.ground, L.hip, LOCO, LOCO.idles[pick][1], rate, offset)
			end
			local loco = body.loco
			if loco and (loco.on or NpcLoco.ready(loco)) then
				NpcLoco.drive(loco, body.speed, false, LOCO)
				animated = true
			end
		end
		if not animated and body.animated then
			unanimate(body)
		end
		body.animated = animated
		local near = dist < (Q.citizenPoseNear or C.poseNear)
		pose(
			body,
			dt,
			roots,
			cframes,
			near or (frame + id) % (Q.citizenPoseEvery or C.poseEvery) == 0,
			animated
		)
	end
	if #roots > 0 then
		Workspace:BulkMoveTo(roots, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function CitizenRenderer.count(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

function CitizenRenderer.init()
	folder = Instance.new("Folder")
	folder.Name = "Citizens"
	folder.Parent = Workspace
	Net.listen("CitizenDelta", function(b: buffer)
		if type(b) ~= "buffer" then
			return
		end
		local seq, rows = CitizenBuffer.decode(b)
		if seq <= lastSeq then
			return -- unreliable: late packets are dropped
		end
		lastSeq = seq
		local byId = {}
		for _, r in rows do
			byId[r.id] = r
		end
		table.insert(snapshots, { t = os.clock(), rows = byId })
		while #snapshots > 6 do
			table.remove(snapshots, 1)
		end
	end)
	if LOCO.on then
		for _, e in LOCO.idles do
			NpcLoco.preload({ idle = e[1], walk = LOCO.walk, run = LOCO.run })
		end
	end
	-- PreSimulation, after the Animator, so the arms written over Roblox's clips show (NpcLoco, like the robots)
	RunService.PreSimulation:Connect(FrameProf.wrap("CitizenRenderer", render))
end

return CitizenRenderer
