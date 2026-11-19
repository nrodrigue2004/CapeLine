--!strict
-- CarryPose: where a picked-up thing sits in the hero's hands (nate after gaps7, 2026-11-19: "when i pickup cars
-- or items or whatever i should actually hold them. Unless i have powers like telekinesis then i could make them
-- float"). Before this ThrowService welded every carried thing to the HumanoidRootPart 4.5 studs up, about 1.5
-- studs over the raised hands, and a held robot was a server position sent at 10 Hz with the renderer's
-- interpolation delay, tumbling: it floated and lagged.
-- A grip per carry (gripOf):
--   overhead  big things (cars, trucks, slabs, dumpsters, vending machines, wrecks, live robots): both hands up
--             under it (HeroAnim "carry"); welded to the UpperTorso so it sits on the two raised fists
--   hand      small things (bench, bin, mailbox, rubble): up on the right fist (HeroAnim "carryHand"); welded
--             to the RightHand
--   pole      a sign or a lamp post gripped upright in the right fist (the same pose); welded to the RightHand
--   mind      Gravity (Pulse) and Mind heroes: it floats over the head with a glow, both hands
--             raised to it (HeroAnim "carryMind"); welded to the HumanoidRootPart
-- The maths is forward kinematics of the R15 arm, the way Roblox and HeroAnimator pose it (a child part =
-- parent * C0 * CFrame.new(0, py, 0) * CFrame.Angles(rx, ry, rz) * C1:Inverse()), at the hold clip's first key,
-- from the character's own Motor6Ds at runtime (any body shape) or Config.HeroRig in the tests and previews.
-- Pure: no Roblox types (CFrames are { p, r } tables; GetComponents in and out), so Lune tests it.

local CarryPose = {}

export type V = { number }
export type M = { { number } }
export type CF = { p: V, r: M }
export type Joint = { name: string, part0: string, part1: string, c0: CF, c1: CF }
export type Body = { joints: { Joint }, sizes: { [string]: V } }
export type Hold = {
	grip: string,
	part: string, -- the part it is welded to (UpperTorso, RightHand or HumanoidRootPart)
	c0: CF, -- the box's centre in that part's frame
	box: CF, -- the box's centre in the root's frame at the clip's first key
	hand: CF, -- the box's centre in the RightHand's frame at that key (the lift and swings follow the hand)
	size: V, -- the box's extents in its own frame (as given)
	turn: M, -- how the box is turned in the hands (its frame to the hold's upright frame)
	ext: V, -- its extents in that upright frame (across, up, along)
}

local IDENT: M = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

-- the R15 joints, parent first (RigMath.JOINTS)
CarryPose.JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso" },
	{ "Waist", "LowerTorso", "UpperTorso" },
	{ "Neck", "UpperTorso", "Head" },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm" },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm" },
	{ "LeftWrist", "LeftLowerArm", "LeftHand" },
	{ "RightShoulder", "UpperTorso", "RightUpperArm" },
	{ "RightElbow", "RightUpperArm", "RightLowerArm" },
	{ "RightWrist", "RightLowerArm", "RightHand" },
}

-- the held pose each grip shows (HeroAnimator's state pose, by the CarryGrip attribute)
CarryPose.CLIP = { overhead = "carry", hand = "carryHand", pole = "carryHand", mind = "carryMind" }
-- the part each grip welds to
CarryPose.PART =
	{ overhead = "UpperTorso", hand = "RightHand", pole = "RightHand", mind = "HumanoidRootPart" }
-- the one-shots during which the held thing follows the right hand (the lift, the swings and the slam)
CarryPose.FOLLOW = { lift = true, robotSwing = true, robotSwingBack = true, robotSlam = true }

---------------------------------------------------------------------------
-- CFrame maths on plain tables
---------------------------------------------------------------------------

local function mm(a: M, b: M): M
	local o = {}
	for i = 1, 3 do
		o[i] = {}
		for j = 1, 3 do
			o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return o
end
local function mv(m: M, v: V): V
	return {
		m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
		m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
		m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
	}
end
local function tr(m: M): M
	return {
		{ m[1][1], m[2][1], m[3][1] },
		{ m[1][2], m[2][2], m[3][2] },
		{ m[1][3], m[2][3], m[3][3] },
	}
end

function CarryPose.cf(x: number, y: number, z: number, r: M?): CF
	return { p = { x, y, z }, r = r or IDENT }
end

function CarryPose.mul(a: CF, b: CF): CF
	local q = mv(a.r, b.p)
	return { p = { a.p[1] + q[1], a.p[2] + q[2], a.p[3] + q[3] }, r = mm(a.r, b.r) }
end

function CarryPose.inv(a: CF): CF
	local rt = tr(a.r)
	local q = mv(rt, a.p)
	return { p = { -q[1], -q[2], -q[3] }, r = rt }
end

function CarryPose.point(a: CF, v: V): V
	local q = mv(a.r, v)
	return { a.p[1] + q[1], a.p[2] + q[2], a.p[3] + q[3] }
end

-- CFrame.Angles(rx, ry, rz) in degrees: Rx * Ry * Rz
function CarryPose.angles(rx: number, ry: number, rz: number): M
	local x, y, z = math.rad(rx), math.rad(ry), math.rad(rz)
	local cx, sx, cy, sy, cz, sz =
		math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
	local X = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local Y = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local Z = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	return mm(mm(X, Y), Z)
end

-- a clip key { rx, ry, rz, py } as HeroAnimator writes it: CFrame.new(0, py, 0) * CFrame.Angles(rx, ry, rz)
function CarryPose.key(a: { number }?): CF
	if not a then
		return CarryPose.cf(0, 0, 0)
	end
	return CarryPose.cf(0, a[4] or 0, 0, CarryPose.angles(a[1] or 0, a[2] or 0, a[3] or 0))
end

-- CFrame:GetComponents() order (x, y, z, R00, R01, R02, R10, ...) in and out
function CarryPose.fromComponents(c: { number }): CF
	return {
		p = { c[1], c[2], c[3] },
		r = { { c[4], c[5], c[6] }, { c[7], c[8], c[9] }, { c[10], c[11], c[12] } },
	}
end
function CarryPose.components(a: CF): { number }
	local r = a.r
	return {
		a.p[1],
		a.p[2],
		a.p[3],
		r[1][1],
		r[1][2],
		r[1][3],
		r[2][1],
		r[2][2],
		r[2][3],
		r[3][1],
		r[3][2],
		r[3][3],
	}
end

---------------------------------------------------------------------------
-- The body
---------------------------------------------------------------------------

-- A body from a Config.HeroRig-shaped table (the tests and the previews): every joint meets at its
-- "<name>RigAttachment" on both parts, axis-aligned
function CarryPose.bodyFromRig(rig: any): Body
	local out: Body = { joints = {}, sizes = {} }
	for name, def in rig.parts do
		out.sizes[name] = { def.size[1], def.size[2], def.size[3] }
	end
	out.sizes.HumanoidRootPart = { rig.root.size[1], rig.root.size[2], rig.root.size[3] }
	for _, j in CarryPose.JOINTS do
		local key = j[1] .. "RigAttachment"
		local a0 = (if j[2] == "HumanoidRootPart" then rig.root else rig.parts[j[2]]).attachments[key]
		local a1 = rig.parts[j[3]].attachments[key]
		assert(a0 and a1, "CarryPose: missing " .. key)
		table.insert(out.joints, {
			name = j[1],
			part0 = j[2],
			part1 = j[3],
			c0 = CarryPose.cf(a0[1], a0[2], a0[3]),
			c1 = CarryPose.cf(a1[1], a1[2], a1[3]),
		})
	end
	return out
end

-- Every part's CFrame in the root's frame for one pose (joint name -> clip key; a joint left out rests)
function CarryPose.parts(body: Body, pose: { [string]: { number } }): { [string]: CF }
	local out: { [string]: CF } = { HumanoidRootPart = CarryPose.cf(0, 0, 0) }
	for _, j in body.joints do
		local parent = out[j.part0]
		if parent then
			out[j.part1] = CarryPose.mul(
				CarryPose.mul(CarryPose.mul(parent, j.c0), CarryPose.key(pose[j.name])),
				CarryPose.inv(j.c1)
			)
		end
	end
	return out
end

-- The end of a hand (its -Y face, away from the wrist: on top of a raised fist), in the root's frame
function CarryPose.tip(body: Body, parts: { [string]: CF }, side: string): V
	local name = side .. "Hand"
	local s = body.sizes[name] or { 1, 0.3, 1 }
	return CarryPose.point(parts[name], { 0, -s[2] / 2, 0 })
end

---------------------------------------------------------------------------
-- Grips and holds
---------------------------------------------------------------------------

-- Which grip a hero uses on a kind: the mind paths float everything; otherwise the kind's own grip, else small
-- (light) things in one hand and the rest overhead
function CarryPose.gripOf(T: any, kind: string?, setId: string?): string
	local mind = T.mind
	if setId and mind and mind.paths[setId] then
		return "mind"
	end
	local k = kind and T.kinds[kind]
	if k and k.grip then
		return k.grip
	end
	return if k and k.weight == "light" then "hand" else "overhead"
end

-- A robot lying face up across the hands, its head to the hero's right: local up to +x, its face (-z) to +y
CarryPose.ROBOT = { { 0, 1, 0 }, { 0, 0, -1 }, { -1, 0, 0 } }
local YAW90: M = { { 0, 0, 1 }, { 0, 1, 0 }, { -1, 0, 0 } } -- CFrame.Angles(0, pi/2, 0)
local ROLL: M = { { 0, 1, 0 }, { -1, 0, 0 }, { 0, 0, 1 } } -- CFrame.Angles(0, 0, -pi/2): local up to +x

-- How the box turns in the hands: its rotation and its extents in the hero's frame. Overhead the long side runs
-- across the shoulders (a tall prop is laid down; a vehicle stays on its wheels); in one hand it runs forward,
-- clear of the head; a pole stands up
local function fit(size: V, grip: string, upright: boolean?): (M, V)
	local x, y, z = size[1], size[2], size[3]
	if grip == "pole" then
		return IDENT, { x, y, z }
	end
	local r = IDENT
	if grip ~= "hand" and not upright and y > math.max(x, z) then
		r, x, y = ROLL, y, x
	end
	local wantX = grip ~= "hand"
	if (wantX and z > x) or (not wantX and x > z) then
		r, x, z = mm(YAW90, r), z, x
	end
	return r, { x, y, z }
end

-- Where a carried box sits for a grip. pose: the grip's clip (HeroAnim.sample(CarryPose.CLIP[grip], 0)); size:
-- the box's extents in its own frame (a prop's bounding box, or a robot's CarryPose.robotSize with `robot`,
-- laid as CarryPose.ROBOT); upright: never laid down (vehicles)
function CarryPose.hold(
	T: any,
	body: Body,
	grip: string,
	pose: { [string]: { number } },
	size: V,
	robot: boolean?,
	upright: boolean?
): Hold
	local H = T.hold
	local P = CarryPose.parts(body, pose)
	local r: M, ext: V
	if robot then
		r = CarryPose.ROBOT
		ext = {}
		for i = 1, 3 do
			ext[i] = math.abs(r[i][1]) * size[1] + math.abs(r[i][2]) * size[2] + math.abs(r[i][3]) * size[3]
		end
	else
		r, ext = fit(size, grip, upright)
	end
	local box: CF
	if grip == "mind" then
		local M_ = T.mind
		local head = P.Head
		local hs = body.sizes.Head or { 1.2, 1.2, 1.2 }
		local top = if head then head.p[2] + hs[2] / 2 else 2.25
		box = CarryPose.cf(0, top + M_.gap + ext[2] / 2, M_.fwd, r)
	elseif grip == "overhead" then
		local ut = P.UpperTorso
		local iu = CarryPose.inv(ut)
		local a = CarryPose.point(iu, CarryPose.tip(body, P, "Right"))
		local b = CarryPose.point(iu, CarryPose.tip(body, P, "Left"))
		local inUt =
			CarryPose.cf((a[1] + b[1]) / 2, math.max(a[2], b[2]) + H.palm + ext[2] / 2, (a[3] + b[3]) / 2, r)
		box = CarryPose.mul(ut, inUt)
	elseif grip == "pole" then
		-- gripped in the fist a share of the way up from its foot, standing straight up in the torso's frame
		local ut = P.UpperTorso
		local hs = body.sizes.RightHand or { 1, 0.3, 1 }
		local g = CarryPose.point(P.RightHand, { 0, -hs[2] * 0.15, 0 })
		local up = mv(ut.r, { 0, 1, 0 })
		local k = ext[2] * (0.5 - H.poleAt)
		box = { p = { g[1] + up[1] * k, g[2] + up[2] * k, g[3] + up[3] * k }, r = mm(ut.r, r) }
	else
		-- hand: resting on top of the raised right fist, upright in the torso's frame
		local ut = P.UpperTorso
		local t = CarryPose.tip(body, P, "Right")
		local up = mv(ut.r, { 0, 1, 0 })
		local k = H.palm + ext[2] / 2
		box = { p = { t[1] + up[1] * k, t[2] + up[2] * k, t[3] + up[3] * k }, r = mm(ut.r, r) }
	end
	local part = CarryPose.PART[grip]
	return {
		grip = grip,
		part = part,
		c0 = CarryPose.mul(CarryPose.inv(P[part]), box),
		box = box,
		hand = CarryPose.mul(CarryPose.inv(P.RightHand), box),
		size = { size[1], size[2], size[3] },
		turn = r,
		ext = ext,
	}
end

-- A robot's box in its own frame (shoulders' width, height, chest depth); held, its height lies across the hands
function CarryPose.robotSize(height: number): V
	return { height * 0.4, height, height * 0.2 }
end

-- The 8 corners of a held box (root frame), for the checks and the previews
function CarryPose.corners(box: CF, ext: V): { V }
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, CarryPose.point(box, { sx * ext[1] / 2, sy * ext[2] / 2, sz * ext[3] / 2 }))
			end
		end
	end
	return out
end

-- A point's height below a held box's underside and how far outside its footprint it lies, in the hold's
-- upright frame: (gap: > 0 below the bottom face, outside: < 0 inside the edge)
function CarryPose.under(box: CF, h: Hold, pt: V): (number, number)
	local q = mv(h.turn, CarryPose.point(CarryPose.inv(box), pt))
	local ext = h.ext
	local gap = -ext[2] / 2 - q[2]
	local out = math.max(math.abs(q[1]) - ext[1] / 2, math.abs(q[3]) - ext[3] / 2)
	return gap, out
end

-- A point inside a held box grown by `margin` on every side
function CarryPose.inside(box: CF, h: Hold, pt: V, margin: number): boolean
	local q = mv(h.turn, CarryPose.point(CarryPose.inv(box), pt))
	local e = h.ext
	return math.abs(q[1]) < e[1] / 2 + margin
		and math.abs(q[2]) < e[2] / 2 + margin
		and math.abs(q[3]) < e[3] / 2 + margin
end

-- The mind swing's whirl (ThrowService's old tween path, now drawn on every device): the box's centre in the
-- root's frame u of the way through a swing toward `yaw` (radians, root-relative)
function CarryPose.whirl(T: any, yaw: number, u: number): V
	local S = T.swing
	local a = yaw + math.rad(S.arc / 2) * (1 - 2 * math.clamp(u, 0, 1))
	local r = T.mind.whirl
	return { -math.sin(a) * r, T.mind.whirlY, -math.cos(a) * r }
end

return CarryPose
