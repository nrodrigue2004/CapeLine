--!strict
-- BossAnim: the world bosses and the War-Frame in motion (the boss pass, 2026-11-19). WorldFx builds a boss from its
-- meshes (or the part-built look) with each piece tagged by its rig segment (Config.BossArt seg and rig); this poses
-- the segments from Shared.BossPose every frame: the idle breathing (bigger and faster each phase), Rustjaw's walk,
-- each attack's wind-up timed to its warning so the strike lands on the hit, the recover, a flinch on a big hit,
-- the weak points exposed after a hazard or a broken shield, the plate break stagger and the enrage roar at 66% and
-- 33%, the defeat collapse and the entrance. The Leviathan's gears, turbine and tide wheel turn all the time.
-- Draw only: BossSim's hit boxes, shapes and times never change (the model's visual moves a few studs at most).
-- Cheap: one BulkMoveTo for every piece; 60 Hz near on high, 30 Hz on low, less far away (QualityController).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local BossPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BossPose"))
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local BossAnim = {}

type Piece = { part: BasePart, seg: string, rest: CFrame }
type Action = { clip: BossPose.Clip, start: number, w: number }
export type Anim = {
	id: string,
	set: BossPose.Set,
	root: BasePart,
	rig: { { name: string, parent: string, pivot: Vector3 } },
	pieces: { Piece },
	byPart: { [BasePart]: Piece },
	actions: { Action },
	attack: { id: string, start: number, warn: number, hazard: boolean, weak: boolean? }?,
	clock: number,
	idleT: number,
	walkW: number,
	phase: number,
	acc: number,
	lastHp: number?,
	lastFlinch: number,
	spinT: number,
	pose: BossPose.Pose,
	parts: { BasePart },
	cfs: { CFrame },
	conns: { RBXScriptConnection },
	dead: boolean,
}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Start animating a built boss model (its Root part is the feet's frame, every other BasePart a piece). Parts with
-- no Seg attribute ride on the Body (objectives on the body, the War-Frame's shield bubble).
function BossAnim.attach(id: string, model: Model): Anim?
	local set = BossPose.SETS[id]
	local fit = Config.BossArt[id]
	local root = model:FindFirstChild("Root") :: BasePart?
	if not (set and fit and fit.rig and root) then
		return nil
	end
	local rig = {}
	for _, r in fit.rig do
		table.insert(rig, { name = r.name, parent = r.parent, pivot = v3(r.pivot) })
	end
	local a: Anim = {
		id = id,
		set = set,
		root = root,
		rig = rig,
		pieces = {},
		byPart = {},
		actions = {},
		attack = nil,
		clock = 0,
		idleT = 0,
		walkW = 0,
		phase = 1,
		acc = 0,
		lastHp = nil,
		lastFlinch = 0,
		spinT = 0,
		pose = {},
		parts = {},
		cfs = {},
		conns = {},
		dead = false,
	}
	local function add(p: Instance)
		if not p:IsA("BasePart") or p == root or a.byPart[p] then
			return
		end
		local seg = p:GetAttribute("Seg")
		local piece: Piece = {
			part = p,
			seg = if type(seg) == "string" then seg else "Body",
			rest = root.CFrame:ToObjectSpace(p.CFrame),
		}
		a.byPart[p] = piece
		table.insert(a.pieces, piece)
	end
	for _, p in model:GetChildren() do
		add(p)
	end
	-- a plate that breaks off (WorldFx moves it out of the model) stops following; a late part (the shield) joins
	table.insert(a.conns, model.ChildAdded:Connect(add))
	table.insert(
		a.conns,
		model.ChildRemoved:Connect(function(p)
			local piece = p:IsA("BasePart") and a.byPart[p :: BasePart]
			if piece then
				a.byPart[p :: BasePart] = nil
				local i = table.find(a.pieces, piece)
				if i then
					table.remove(a.pieces, i)
				end
			end
		end)
	)
	return a
end

function BossAnim.detach(a: Anim)
	for _, c in a.conns do
		c:Disconnect()
	end
	table.clear(a.conns)
end

-- A one-shot clip (flinch, weak, stagger, enrage, defeat, land, shot), optionally after a delay
function BossAnim.play(a: Anim, name: string, delay: number?, weight: number?)
	local c = a.set.clips[name]
	if not c or a.dead then
		return
	end
	if name == "defeat" then
		a.dead = true
		a.attack = nil
		table.clear(a.actions)
	end
	table.insert(a.actions, { clip = c, start = a.clock + (delay or 0), w = weight or 1 })
end

-- An attack's warning began (Boss.Attack warn from the boss itself): the wind-up runs over the warning
function BossAnim.attack(a: Anim, attackId: string, warn: number)
	if a.dead or not a.set.attacks[attackId] then
		return
	end
	local hazard = false
	for _, atk in Config.Boss.bosses[a.id].attacks do
		if atk.id == attackId then
			hazard = atk.hazard == true
		end
	end
	a.attack = { id = attackId, start = a.clock, warn = warn, hazard = hazard, weak = false }
end

-- The strike arrived from the server: snap the clip to its hit if the client ran early or late
function BossAnim.strike(a: Anim, attackId: string)
	local atk = a.attack
	if atk and atk.id == attackId then
		atk.start = a.clock - atk.warn
	end
end

-- A Boss.State: a big hp drop flinches it; the phase grows the idle
function BossAnim.state(a: Anim, hp: number?, max: number?, phase: number?)
	a.phase = math.clamp(phase or a.phase, 1, 3)
	if hp and max and a.lastHp then
		if BossPose.bigHit(a.lastHp - hp, max) and a.clock - a.lastFlinch >= BossPose.flinchGap then
			a.lastFlinch = a.clock
			BossAnim.play(a, "flinch", 0, if a.attack then 0.5 else 1)
		end
	end
	a.lastHp = hp
end

-- The phase changed: plates break (stagger), then the enrage roar
function BossAnim.phase(a: Anim, phase: number)
	a.phase = math.clamp(phase, 1, 3)
	BossAnim.play(a, "stagger")
	local st = a.set.clips.stagger
	BossAnim.play(a, "enrage", if st then st.dur * 0.75 else 1)
end

local function rateNow(a: Anim): number
	local q = QualityController.name
	local cam = Workspace.CurrentCamera
	local d = if cam then (cam.CFrame.Position - a.root.Position).Magnitude else 0
	local hz = if q == "low" then 30 elseif q == "medium" then 45 else 60
	if d > 900 then
		hz = math.min(hz, 8)
	elseif d > 500 then
		hz = math.min(hz, 20)
	end
	return 1 / hz
end

local function angles(v: { number }, extra: CFrame?): CFrame
	local r = CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
	return if extra then r * extra else r
end

local AXIS = { x = Vector3.xAxis, y = Vector3.yAxis, z = Vector3.zAxis }

-- One frame: rootCF is where the boss's feet are now (WorldFx's eased position and yaw, plus its lift); moving says
-- it walks this frame. Writes every piece's CFrame (and the Root part's).
function BossAnim.step(a: Anim, rootCF: CFrame, dt: number, moving: boolean?)
	a.clock += dt
	a.spinT += dt * BossPose.spinScale(a.phase, a.attack ~= nil)
	a.walkW = math.clamp(a.walkW + (if moving and not a.dead then dt else -dt) * 2.5, 0, 1)
	a.idleT += dt * BossPose.idleRate[a.phase]
	a.acc += dt
	if a.acc < rateNow(a) then
		return
	end
	a.acc = 0
	-- the layers: idle (and the walk), then the attack and the one-shots on top
	local pose = a.pose
	for _, v in pose do
		table.clear(v)
	end
	table.clear(pose)
	local busy = a.attack ~= nil or a.dead
	local idleW = (if busy then 0.5 else 1) * (1 - a.walkW * 0.5) * (if a.dead then 0 else 1)
	BossPose.add(pose, BossPose.sample(a.set.clips.idle, a.idleT), idleW * BossPose.idleScale[a.phase])
	local walk = a.set.clips.walk
	if walk and a.walkW > 0 then
		BossPose.add(pose, BossPose.sample(walk, a.clock), a.walkW)
	end
	local atk = a.attack
	if atk then
		local p, stage = BossPose.attack(a.id, atk.id, a.clock - atk.start, atk.warn)
		if p then
			BossPose.add(pose, p, 1)
		else
			a.attack = nil
		end
		if
			stage == "recover"
			and atk.hazard
			and not atk.weak
			and a.clock - atk.start - atk.warn >= BossPose.weakAfter
		then
			-- after a hazard it is spent for a moment: the weak points show (blending in as the recover fades out)
			atk.weak = true
			BossAnim.play(a, "weak")
		end
	end
	for i = #a.actions, 1, -1 do
		local act = a.actions[i]
		local t = a.clock - act.start
		if t >= 0 then
			if t > act.clip.dur and act.clip ~= a.set.clips.defeat then
				table.remove(a.actions, i)
			else
				BossPose.add(pose, BossPose.sample(act.clip, t), act.w)
			end
		end
	end
	-- the segments, parents first: each turns about its pivot in its parent's frame
	local xf: { [string]: CFrame } = {}
	local r = pose.Root
	xf.Root = if r then CFrame.new(r[4], r[5], r[6]) * angles(r) else CFrame.identity
	local spin = a.set.spin
	for _, seg in a.rig do
		local v = pose[seg.name]
		local s = spin and spin[seg.name]
		local local_ = CFrame.identity
		if v or s then
			local extra = if s
				then CFrame.fromAxisAngle(AXIS[s.axis], math.rad(BossPose.spinAngle(s.rate, a.spinT, 1)))
				else nil
			local vv = v or { 0, 0, 0, 0, 0, 0 }
			local p = seg.pivot
			local_ = CFrame.new(p.X + vv[4], p.Y + vv[5], p.Z + vv[6]) * angles(vv, extra) * CFrame.new(-p)
		end
		xf[seg.name] = (xf[seg.parent] or xf.Root) * local_
	end
	local parts, cfs = a.parts, a.cfs
	table.clear(parts)
	table.clear(cfs)
	table.insert(parts, a.root)
	table.insert(cfs, rootCF)
	for _, piece in a.pieces do
		table.insert(parts, piece.part)
		table.insert(cfs, rootCF * (xf[piece.seg] or xf.Root) * piece.rest)
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

return BossAnim
