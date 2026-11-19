--!strict
-- AnimIK: two-handed holds for the hand-keyed clips (pt-anims, nate's playtest 2026-11-19: "Some of them might
-- need two handed animations"). A two-handed weapon's moves were keyed arm by arm, so the off hand only roughly
-- followed the hilt. pin() rewrites a clip's left arm so the left hand sits on the weapon at every key of the
-- right arm: forward kinematics finds the right hand's grip and the weapon's line in the upper torso's frame
-- (both shoulders hang off the UpperTorso, so the waist, root and legs never matter), the left hand's spot is
-- a set gap along that line (behind the right hand on a hilt, in front of it on a shaft or a barrel), and a
-- two-bone solve (elbow down, out and back) gives the left shoulder and elbow angles. It runs once when
-- HeroAnim loads (data in, data out); nothing is solved per frame.
-- Joint maths as HeroAnimator writes it: a child part = parent * C0 * CFrame.Angles(rx, ry, rz) * C1:Inverse(),
-- with the rig's axis-aligned attachments as C0 and C1. Angles in degrees.
-- Pure: no Roblox types, so Lune tests it.

local AnimIK = {}

type V = { number }
type M = { { number } }
type Key = { number } -- { t, rx, ry, rz, py, linear? }
type Clip = { dur: number, loop: boolean?, joints: { [string]: { Key } } }

local function mul(a: M, b: M): M
	local o = {}
	for i = 1, 3 do
		o[i] = {}
		for j = 1, 3 do
			o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return o
end
local function ap(m: M, v: V): V
	return {
		m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
		m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
		m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
	}
end
local function add(a: V, b: V): V
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end
local function sub(a: V, b: V): V
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function scl(a: V, s: number): V
	return { a[1] * s, a[2] * s, a[3] * s }
end
local function dot(a: V, b: V): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function cross(a: V, b: V): V
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function len(a: V): number
	return math.sqrt(dot(a, a))
end
local function unit(a: V): V
	local l = len(a)
	return if l > 1e-9 then scl(a, 1 / l) else { 0, -1, 0 }
end
AnimIK.len = len
AnimIK.sub = sub

-- CFrame.Angles(rx, ry, rz) in degrees: Rx * Ry * Rz
function AnimIK.angles(a: { number }?): M
	local rx, ry, rz = math.rad(a and a[1] or 0), math.rad(a and a[2] or 0), math.rad(a and a[3] or 0)
	local cx, sx, cy, sy, cz, sz =
		math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local X = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local Y = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local Z = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	return mul(mul(X, Y), Z)
end

-- a rotation's XYZ angles (degrees), the inverse of angles()
local function euler(R: M): V
	local sy = math.clamp(R[1][3], -1, 1)
	local y = math.asin(sy)
	local x, z
	if math.abs(sy) < 0.9999 then
		x = math.atan2(-R[2][3], R[3][3])
		z = math.atan2(-R[1][2], R[1][1])
	else
		x = math.atan2(R[3][2], R[2][2])
		z = 0
	end
	return { math.deg(x), math.deg(y), math.deg(z) }
end

-- The arm's rig numbers from a Config.HeroRig-shaped table: attachments by part
export type Arm = {
	shoulder: { L: V, R: V }, -- the shoulder joints on the UpperTorso
	upper: { L: { V }, R: { V } }, -- the upper arm's shoulder and elbow attachments
	lower: { L: { V }, R: { V } }, -- the lower arm's elbow and wrist attachments
	hand: { L: { V }, R: { V } }, -- the hand's wrist and grip attachments
}
function AnimIK.arm(rig: any): Arm
	local P = rig.parts
	local function at(part: string, name: string): V
		local v = P[part].attachments[name]
		assert(v, "AnimIK: missing " .. part .. "." .. name)
		return { v[1], v[2], v[3] }
	end
	local out: any = { shoulder = {}, upper = {}, lower = {}, hand = {} }
	for _, s in { "Left", "Right" } do
		local k = string.sub(s, 1, 1)
		out.shoulder[k] = at("UpperTorso", s .. "ShoulderRigAttachment")
		out.upper[k] = {
			at(s .. "UpperArm", s .. "ShoulderRigAttachment"),
			at(s .. "UpperArm", s .. "ElbowRigAttachment"),
		}
		out.lower[k] =
			{ at(s .. "LowerArm", s .. "ElbowRigAttachment"), at(s .. "LowerArm", s .. "WristRigAttachment") }
		out.hand[k] = { at(s .. "Hand", s .. "WristRigAttachment"), at(s .. "Hand", s .. "GripAttachment") }
	end
	return out :: Arm
end

-- One hand's grip point and the hand's rotation in the UpperTorso's frame, from shoulder, elbow and wrist angles
function AnimIK.hand(arm: Arm, side: string, sh: V?, el: V?, wr: V?): (V, M)
	local R1 = AnimIK.angles(sh)
	local cU = sub(arm.shoulder[side], ap(R1, arm.upper[side][1]))
	local R2 = mul(R1, AnimIK.angles(el))
	local cL = sub(add(cU, ap(R1, arm.upper[side][2])), ap(R2, arm.lower[side][1]))
	local R3 = mul(R2, AnimIK.angles(wr))
	local cH = sub(add(cL, ap(R2, arm.lower[side][2])), ap(R3, arm.hand[side][1]))
	return add(cH, ap(R3, arm.hand[side][2])), R3
end

-- One arm's shoulder and elbow angles that put its grip on `target` (UpperTorso frame); the elbow points
-- down, out and back. An out-of-reach target is reached for along the same line. The shoulder joint sits at
-- the upper arm's inner top corner (v1, shoulder to elbow, is not straight down), so the bend comes from the
-- distance and the shoulder from mapping the arm's own frame (reach line, elbow side) onto the wanted one.
local POLE = { L = unit({ -0.55, -1, 0.45 }), R = unit({ 0.55, -1, 0.45 }) }
local MAX_BEND = 150
local function frame(a: V, b: V): M -- columns: a, b made perpendicular to a, and a x b
	local x = unit(a)
	local y = sub(b, scl(x, dot(b, x)))
	if len(y) < 1e-6 then
		y = if math.abs(x[2]) < 0.9 then { 0, 1, 0 } else { 1, 0, 0 }
		y = sub(y, scl(x, dot(y, x)))
	end
	y = unit(y)
	local z = cross(x, y)
	return { { x[1], y[1], z[1] }, { x[2], y[2], z[2] }, { x[3], y[3], z[3] } }
end
local function transpose(m: M): M
	return { { m[1][1], m[2][1], m[3][1] }, { m[1][2], m[2][2], m[3][2] }, { m[1][3], m[2][3], m[3][3] } }
end
local function segs(arm: Arm, side: string, toWrist: boolean?): (V, number)
	local v1 = sub(arm.upper[side][2], arm.upper[side][1]) -- shoulder joint to elbow, in the upper arm's frame
	local b = len(sub(arm.lower[side][2], arm.lower[side][1]))
	if not toWrist then
		b += len(sub(arm.hand[side][2], arm.hand[side][1]))
	end
	return v1, b
end
local function reachOf(v1: V, b: number, e: number): V -- shoulder joint to grip with the elbow bent e degrees
	local r = math.rad(e)
	return add(v1, { 0, -b * math.cos(r), -b * math.sin(r) })
end
-- the furthest an arm's grip reaches from its shoulder joint
function AnimIK.reach(arm: Arm, side: string): number
	local v1, b = segs(arm, side)
	return len(reachOf(v1, b, 0))
end
-- returns the shoulder and elbow angles and the forearm's rotation (for the wrist). toWrist: the target is
-- the wrist joint, not the grip (the hand then turns on its own)
-- pole: where the elbow should point (default down, out and back)
function AnimIK.solve(arm: Arm, side: string, target: V, toWrist: boolean?, pole: V?): (V, V, M)
	local S = arm.shoulder[side]
	local v1, b = segs(arm, side, toWrist)
	local d = sub(target, S)
	local L = len(d)
	-- the bend that gives this reach (|reach(e)| falls as e grows), by bisection: cheap and always defined
	local lo, hi = 0, MAX_BEND
	if L >= len(reachOf(v1, b, 0)) then
		hi = 0
	elseif L <= len(reachOf(v1, b, MAX_BEND)) then
		lo = MAX_BEND
	else
		for _ = 1, 30 do
			local mid = (lo + hi) * 0.5
			if len(reachOf(v1, b, mid)) > L then
				lo = mid
			else
				hi = mid
			end
		end
	end
	local e = (lo + hi) * 0.5
	-- map the arm's (reach line, elbow side) frame onto (the target line, the pole side)
	local R = mul(frame(d, pole or POLE[side]), transpose(frame(reachOf(v1, b, e), v1)))
	return euler(R), { e, 0, 0 }, mul(R, AnimIK.angles({ e, 0, 0 }))
end
function AnimIK.solveLeft(arm: Arm, target: V): (V, V)
	local s, e = AnimIK.solve(arm, "L", target)
	return s, e
end

-- the left hand's spot for one pose of the right arm: `gap` studs along the weapon's line (aim: the weapon's
-- pointing direction in the right hand's frame) from the right grip
function AnimIK.target(arm: Arm, angs: { [string]: V }, aim: V, gap: number): V
	local grip, R3 = AnimIK.hand(arm, "R", angs.RightShoulder, angs.RightElbow, angs.RightWrist)
	return add(grip, scl(ap(R3, unit(aim)), gap))
end

-- keep an angle close to the one before it (no 350-degree swings between keys)
local function near(v: number, prev: number?): number
	if not prev then
		return v
	end
	while v - prev > 180 do
		v -= 360
	end
	while v - prev < -180 do
		v += 360
	end
	return v
end

-- A point within `r` of `c` (the closest one to p)
local function into(p: V, c: V, r: number): V
	local d = sub(p, c)
	local l = len(d)
	return if l <= r then p else add(c, scl(d, r / l))
end

-- A copy of `clip` that holds the weapon in both hands, re-keyed at every key time of the right arm. The
-- weapon keeps its line (the right hand's turn) and as much of its place as both arms can reach: the blocky
-- body's shoulders are wide and its arms short, so the grip is drawn in toward the chest until the left
-- hand's spot (gap studs along the weapon) is within the left arm's reach too; then both arms are solved
-- onto it and the wrists turn so both hands keep the weapon's line. sample(clip, t) gives the joint angles.
function AnimIK.pin(
	clip: Clip,
	arm: Arm,
	aim: V,
	gap: number,
	sample: (Clip, number) -> { [string]: V }
): Clip
	local times: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, j in { "RightShoulder", "RightElbow", "RightWrist" } do
		for _, k in clip.joints[j] or {} do
			local t = math.floor(k[1] * 1000 + 0.5) / 1000
			if not seen[t] then
				seen[t] = true
				table.insert(times, t)
			end
		end
	end
	if #times == 0 then
		times = { 0 }
	end
	-- and every frame between (the arms' keys are linear between these, so the ease is the original clip's)
	local step = 1 / 30
	local n = math.max(1, math.floor(clip.dur / step + 0.5))
	for i = 0, n do
		local t = math.floor(clip.dur * i / n * 1000 + 0.5) / 1000
		if not seen[t] then
			seen[t] = true
			table.insert(times, t)
		end
	end
	if #clip.joints.RightShoulder == 1 and #(clip.joints.RightElbow or {}) <= 1 then
		times = { 0 } -- a held pose (a stance) stays one key
	end
	table.sort(times)
	local rL, rR = AnimIK.reach(arm, "L") * 0.96, AnimIK.reach(arm, "R") * 0.96
	local out: { [string]: { Key } } = {
		RightShoulder = {},
		RightElbow = {},
		RightWrist = {},
		LeftShoulder = {},
		LeftElbow = {},
		LeftWrist = {},
	}
	local prev: { [string]: V } = {}
	local function put(joint: string, t: number, a: V)
		local p = prev[joint]
		if p then
			-- the same turn has two XYZ angle sets: keep the one nearer the last key (no flip near 90 degrees)
			local x = { near(a[1], p[1]), near(a[2], p[2]), near(a[3], p[3]) }
			local y = { near(a[1] + 180, p[1]), near(180 - a[2], p[2]), near(a[3] + 180, p[3]) }
			local dx = math.abs(x[1] - p[1]) + math.abs(x[2] - p[2]) + math.abs(x[3] - p[3])
			local dy = math.abs(y[1] - p[1]) + math.abs(y[2] - p[2]) + math.abs(y[3] - p[3])
			a = if dy < dx then y else x
		end
		prev[joint] = a
		table.insert(out[joint], { t, a[1], a[2], a[3], 0, 1 }) -- the 6th: linear to the next key
	end
	local elbowAt: { [string]: V } = {}
	local function elbowPole(side: string): V
		local last = elbowAt[side]
		return if last then unit(add(POLE[side], scl(unit(last), 2))) else POLE[side]
	end
	for _, t in times do
		local angs = sample(clip, t)
		local G, R3 = AnimIK.hand(arm, "R", angs.RightShoulder, angs.RightElbow, angs.RightWrist)
		local off = scl(ap(R3, unit(aim)), gap)
		-- draw the grip in until both hands reach (alternate the two reach spheres; a few rounds settle it)
		for _ = 1, 8 do
			G = sub(into(add(G, off), arm.shoulder.L, rL), off)
			G = into(G, arm.shoulder.R, rR)
		end
		-- both hands take the weapon's turn (R3), so aim each arm at its wrist joint behind its grip
		local wR = sub(G, ap(R3, sub(arm.hand.R[2], arm.hand.R[1])))
		local wL = sub(add(G, off), ap(R3, sub(arm.hand.L[2], arm.hand.L[1])))
		-- the elbows lean toward where they were a frame ago, so the solve never flips sides mid-swing
		local sR, eR, R2R = AnimIK.solve(arm, "R", wR, true, elbowPole("R"))
		local sL, eL, R2L = AnimIK.solve(arm, "L", wL, true, elbowPole("L"))
		elbowAt.R = ap(AnimIK.angles(sR), sub(arm.upper.R[2], arm.upper.R[1]))
		elbowAt.L = ap(AnimIK.angles(sL), sub(arm.upper.L[2], arm.upper.L[1]))
		put("RightShoulder", t, sR)
		put("RightElbow", t, eR)
		put("RightWrist", t, euler(mul(transpose(R2R), R3)))
		put("LeftShoulder", t, sL)
		put("LeftElbow", t, eL)
		put("LeftWrist", t, euler(mul(transpose(R2L), R3)))
	end
	local joints = table.clone(clip.joints)
	for j, keys in out do
		-- a loop ends where it starts (no pop); angles stay within a turn either way
		if clip.loop and #keys > 1 then
			local a = keys[1]
			keys[#keys] = { keys[#keys][1], a[2], a[3], a[4], 0, 1 }
		end
		-- the unwrapped angles drift by whole turns: shift each channel by whole turns toward 0 (the same
		-- rotation at every key, so no pop)
		for i = 2, 4 do
			local lo, hi = math.huge, -math.huge
			for _, k in keys do
				lo, hi = math.min(lo, k[i]), math.max(hi, k[i])
			end
			local turn = 360 * math.floor((lo + hi) / 720 + 0.5)
			if turn ~= 0 then
				for _, k in keys do
					k[i] -= turn
				end
			end
		end
		joints[j] = keys
	end
	return { dur = clip.dur, loop = clip.loop, joints = joints }
end

-- how far apart the two grips are from the weapon's gap in a pose (studs), for the tests: the left grip's
-- distance from its spot along the weapon from the right grip
function AnimIK.miss(arm: Arm, angs: { [string]: V }, aim: V, gap: number): number
	local want = AnimIK.target(arm, angs, aim, gap)
	local got = AnimIK.hand(arm, "L", angs.LeftShoulder, angs.LeftElbow, angs.LeftWrist)
	return len(sub(want, got))
end

return AnimIK
