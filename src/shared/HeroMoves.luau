--!strict
-- HeroMoves: the animation pass's clips (nate's playtest 2026-11-19: "Animation for EVERYTHING. Every attack,
-- power, mobility, every button." and "A lot of weapons need a polish pass"). HeroAnim merges them into its
-- CLIPS and picks them (every power's own move, every weapon's 4-hit combo and Z X C V, the mobility poses and
-- their take-offs and landings, block, carry, revive, gadgets, interact, Awakening, the hit reactions).
-- Strikes come from one builder (strike) so every one has the same anatomy: a set stance, an anticipation
-- (the wind-up, the weight shifted back), the contact (the weight driven through, the root dipped), a
-- follow-through that carries past the contact, and a recovery back to the guard. The legs, the chest, the
-- head and the free arm all move with it, so a cast or a swing is whole-body. Angles follow HeroAnim's joint
-- frames (on a shoulder or hip +x swings the limb forward and up, right limbs go outward with +z; on the
-- waist -x leans forward, and a right-hand strike winds up with +y and lands with -y, like HeroAnim.punch).
-- PLACEHOLDER ANIMATION: hand-keyed (builder) poses until real animations are made and uploaded (Tasks.md).
-- Pure: no Roblox types, so Lune tests it.

local HeroMoves = {}

type Key = { number }
type Clip = { dur: number, loop: boolean?, joints: { [string]: { Key } } }

local function K(t: number, rx: number?, ry: number?, rz: number?, py: number?): Key
	return { t, rx or 0, ry or 0, rz or 0, py or 0 }
end

local function hold(rx: number?, ry: number?, rz: number?, py: number?): { Key }
	return { K(0, rx, ry, rz, py) }
end

local function mirror(clip: Clip): Clip
	local out: { [string]: { Key } } = {}
	for name, keys in clip.joints do
		local other = name
		if string.sub(name, 1, 4) == "Left" then
			other = "Right" .. string.sub(name, 5)
		elseif string.sub(name, 1, 5) == "Right" then
			other = "Left" .. string.sub(name, 6)
		end
		local list = {}
		for i, k in keys do
			list[i] = { k[1], k[2], -k[3], -k[4], k[5] }
		end
		out[other] = list
	end
	return { dur = clip.dur, loop = clip.loop, joints = out }
end
HeroMoves.mirror = mirror

-- the relaxed fighting guard the strikes start from and come back to
local REST_S = { R = { 30, 0, 14 }, L = { 30, 0, -14 } }
local REST_E = 70

local function lerp3(a: { number }, b: { number }, f: number): { number }
	return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end

-- Legs: each preset is the stance through the five beats (start, anticipation, contact, follow, end)
local LEGS: { [string]: { [string]: { { number } } } } = {
	-- feet set, knees soft, a little deeper on the hit
	set = {
		RightHip = { { -10, 0, 6 }, { -14, 0, 8 }, { -22, 0, 8 }, { -18, 0, 8 }, { -10, 0, 6 } },
		LeftHip = { { 14, 0, -6 }, { 20, 0, -8 }, { 28, 0, -8 }, { 24, 0, -8 }, { 14, 0, -6 } },
		RightKnee = { { -10 }, { -18 }, { -22 }, { -20 }, { -10 } },
		LeftKnee = { { -18 }, { -32 }, { -36 }, { -32 }, { -18 } },
	},
	-- the right foot steps in on the hit (a lunge), the left leg drives
	step = {
		RightHip = { { 0 }, { -10 }, { 46, 0, 4 }, { 40, 0, 4 }, { 0 } },
		RightKnee = { { 0 }, { -24 }, { -44 }, { -38 }, { 0 } },
		LeftHip = { { 0 }, { 14 }, { -26, 0, -4 }, { -22, 0, -4 }, { 0 } },
		LeftKnee = { { 0 }, { -34 }, { -12 }, { -16 }, { 0 } },
		RightAnkle = { { 0 }, { 0 }, { -10 }, { -8 }, { 0 } },
		LeftAnkle = { { 0 }, { 10 }, { 30 }, { 24 }, { 0 } },
	},
	-- a deep squat on the hit (both palms or fists into the ground)
	squat = {
		RightHip = { { 0 }, { 20, 0, 10 }, { 76, 0, 16 }, { 70, 0, 14 }, { 0 } },
		LeftHip = { { 0 }, { 20, 0, -10 }, { 76, 0, -16 }, { 70, 0, -14 }, { 0 } },
		RightKnee = { { 0 }, { -30 }, { -104 }, { -96 }, { 0 } },
		LeftKnee = { { 0 }, { -30 }, { -104 }, { -96 }, { 0 } },
		RightAnkle = { { 0 }, { 0 }, { 26 }, { 24 }, { 0 } },
		LeftAnkle = { { 0 }, { 0 }, { 26 }, { 24 }, { 0 } },
	},
	-- the right leg chambers on the anticipation and snaps out on the hit
	kick = {
		RightHip = { { 0 }, { 70, 0, 10 }, { 96, 0, 16 }, { 74, 0, 14 }, { 0 } },
		RightKnee = { { 0 }, { -110 }, { -4 }, { -40 }, { 0 } },
		LeftHip = { { 0 }, { -6 }, { -14 }, { -10 }, { 0 } },
		LeftKnee = { { 0 }, { -24 }, { -18 }, { -20 }, { 0 } },
		RightAnkle = { { 0 }, { -30 }, { -40 }, { -30 }, { 0 } },
	},
	-- a hook kick: the leg comes round from the side (pairs with a spin)
	roundKick = {
		RightHip = { { 0 }, { 50, 0, 40 }, { 84, 0, 70 }, { 60, 0, 50 }, { 0 } },
		RightKnee = { { 0 }, { -100 }, { -8 }, { -50 }, { 0 } },
		LeftHip = { { 0 }, { -4 }, { -10, 0, -6 }, { -8 }, { 0 } },
		LeftKnee = { { 0 }, { -30 }, { -16 }, { -20 }, { 0 } },
		RightAnkle = { { 0 }, { -20 }, { -40 }, { -20 }, { 0 } },
	},
	-- a hop: knees tuck in the air between the anticipation and the follow-through
	hop = {
		RightHip = { { 0 }, { 30 }, { 60 }, { 40 }, { 0 } },
		LeftHip = { { 0 }, { 30 }, { 50 }, { 30 }, { 0 } },
		RightKnee = { { 0 }, { -60 }, { -90 }, { -50 }, { 0 } },
		LeftKnee = { { 0 }, { -60 }, { -80 }, { -40 }, { 0 } },
		RightAnkle = { { 0 }, { 10 }, { -30 }, { 0 }, { 0 } },
		LeftAnkle = { { 0 }, { 10 }, { -30 }, { 0 }, { 0 } },
	},
	-- a wide horse stance that sinks on the hit
	wide = {
		RightHip = { { 0, 0, 6 }, { 24, 0, 22 }, { 40, 0, 30 }, { 36, 0, 28 }, { 0, 0, 6 } },
		LeftHip = { { 0, 0, -6 }, { 24, 0, -22 }, { 40, 0, -30 }, { 36, 0, -28 }, { 0, 0, -6 } },
		RightKnee = { { -10 }, { -40 }, { -60 }, { -56 }, { -10 } },
		LeftKnee = { { -10 }, { -40 }, { -60 }, { -56 }, { -10 } },
	},
	-- down on one knee on the hit (big slams, landings, the kneel)
	kneel = {
		RightHip = { { 0 }, { 30 }, { 86 }, { 82 }, { 0 } },
		RightKnee = { { 0 }, { -40 }, { -92 }, { -90 }, { 0 } },
		LeftHip = { { 0 }, { 10 }, { -6 }, { -4 }, { 0 } },
		LeftKnee = { { 0 }, { -40 }, { -100 }, { -96 }, { 0 } },
		LeftAnkle = { { 0 }, { 0 }, { -50 }, { -46 }, { 0 } },
	},
	-- a step back (a recoil, a shot, a dodge)
	back = {
		RightHip = { { 0 }, { 10 }, { -30 }, { -24 }, { 0 } },
		RightKnee = { { 0 }, { -16 }, { -30 }, { -24 }, { 0 } },
		LeftHip = { { 0 }, { 6 }, { 30 }, { 26 }, { 0 } },
		LeftKnee = { { 0 }, { -16 }, { -40 }, { -34 }, { 0 } },
	},
	-- up on the toes, the body stretched tall (raises, rising strikes)
	rise = {
		RightHip = { { 0 }, { 30 }, { -8 }, { -6 }, { 0 } },
		LeftHip = { { 0 }, { 30 }, { -8 }, { -6 }, { 0 } },
		RightKnee = { { 0 }, { -56 }, { 0 }, { -4 }, { 0 } },
		LeftKnee = { { 0 }, { -56 }, { 0 }, { -4 }, { 0 } },
		RightAnkle = { { 0 }, { 10 }, { -30 }, { -24 }, { 0 } },
		LeftAnkle = { { 0 }, { 10 }, { -30 }, { -24 }, { 0 } },
	},
}
HeroMoves.LEGS = LEGS

-- A whole-body strike. spec: dur; a, c, f the anticipation, contact and follow-through as fractions of dur;
-- R / L arms { w = wind, h = hit, f = follow (default: past the hit), e = { elbow wind, hit, follow },
-- wr = { wrist wind, hit, follow } }; waist / neck { wind, hit, follow } as { rx, ry, rz }; legs (a LEGS
-- preset, "set" by default, or "stepL" / "kickL"... for the left side's version); lift (the root's height on
-- the anticipation), dip (on the contact), spin and flip (whole turns of the root, in degrees, from the
-- anticipation to the follow-through: multiples of 360 so the hero ends facing the same way); extra: raw keys.
function HeroMoves.strike(spec: any): Clip
	local d = spec.dur
	local ta, tc = d * (spec.a or 0.3), d * (spec.c or 0.45)
	-- the follow-through always comes after the contact (a late contact pushes it toward the end)
	local tf = math.min(d * math.max(spec.f or 0.7, (spec.c or 0.45) + 0.1), d * 0.95)
	local times = { 0, ta, tc, tf, d }
	local joints: { [string]: { Key } } = {}
	local function arm(side: string, a: any?)
		local rest = REST_S[side]
		local full = if side == "R" then "Right" else "Left" -- the R15 joint names
		local sh, el = full .. "Shoulder", full .. "Elbow"
		if a then
			local w = a.w or lerp3(rest, a.h, -0.3)
			local f = a.f or lerp3(w, a.h, 1.15)
			joints[sh] = { K(0, rest[1], rest[2], rest[3]), K(ta, w[1], w[2], w[3]) }
			table.insert(joints[sh], K(tc, a.h[1], a.h[2], a.h[3]))
			table.insert(joints[sh], K(tf, f[1], f[2], f[3]))
			table.insert(joints[sh], K(d, rest[1], rest[2], rest[3]))
			local e = a.e or { 90, 4, 12 }
			joints[el] = { K(0, REST_E), K(ta, e[1]), K(tc, e[2]), K(tf, e[3]), K(d, REST_E) }
			if a.wr then
				joints[full .. "Wrist"] = { K(0), K(ta, a.wr[1]), K(tc, a.wr[2]), K(tf, a.wr[3]), K(d) }
			end
		else
			-- the free arm: up for balance on the wind-up, pulled back against the strike (the counter-turn)
			local z = rest[3]
			joints[sh] = {
				K(0, rest[1], 0, z),
				K(ta, rest[1] + 24, 0, z * 1.2),
				K(tc, rest[1] - 16, 0, z * 2),
				K(tf, rest[1] - 10, 0, z * 1.8),
				K(d, rest[1], 0, z),
			}
			joints[el] = { K(0, REST_E), K(ta, 84), K(tc, 104), K(tf, 98), K(d, REST_E) }
		end
	end
	arm("R", spec.R)
	arm("L", spec.L)
	-- the chest: leans and turns with the strike (a right hand winds with +y and lands with -y)
	local waist = spec.waist
	if not waist then
		if spec.R and spec.L then
			waist = { { 10, 0, 0 }, { -14, 0, 0 }, { -10, 0, 0 } }
		elseif spec.L then
			waist = { { 6, -24, 0 }, { -8, 26, 0 }, { -6, 18, 0 } }
		else
			waist = { { 6, 24, 0 }, { -8, -26, 0 }, { -6, -18, 0 } }
		end
	end
	joints.Waist = {
		K(0),
		K(ta, waist[1][1], waist[1][2], waist[1][3]),
		K(tc, waist[2][1], waist[2][2], waist[2][3]),
		K(tf, (waist[3] or waist[2])[1], (waist[3] or waist[2])[2], (waist[3] or waist[2])[3]),
		K(d),
	}
	-- the head keeps its eyes on the target: it counters the chest's turn and lean
	local neck = spec.neck
	if not neck then
		neck = {}
		for i = 1, 3 do
			local w = waist[i] or waist[2]
			neck[i] = { -w[1] * 0.5, -w[2] * 0.6, 0 }
		end
	end
	joints.Neck = {
		K(0),
		K(ta, neck[1][1], neck[1][2], neck[1][3]),
		K(tc, neck[2][1], neck[2][2], neck[2][3]),
		K(tf, (neck[3] or neck[2])[1], (neck[3] or neck[2])[2], (neck[3] or neck[2])[3]),
		K(d),
	}
	-- the legs (a preset, mirrored with an L suffix)
	local legName = spec.legs or "set"
	local flipLegs = false
	if string.sub(legName, -1) == "L" and LEGS[string.sub(legName, 1, -2)] then
		legName, flipLegs = string.sub(legName, 1, -2), true
	end
	local preset = LEGS[legName] or LEGS.set
	for joint, beats in preset do
		local name, sign = joint, 1
		if flipLegs then
			sign = -1
			if string.sub(joint, 1, 5) == "Right" then
				name = "Left" .. string.sub(joint, 6)
			else
				name = "Right" .. string.sub(joint, 5)
			end
		end
		local keys = {}
		for i, b in beats do
			keys[i] = K(times[i], b[1], (b[2] or 0) * sign, (b[3] or 0) * sign)
		end
		joints[name] = keys
	end
	-- the root: up on the anticipation, down into the contact, and any whole turns
	local lift, dip = spec.lift or 0.05, spec.dip or -0.25
	if legName == "squat" or legName == "kneel" then
		dip = spec.dip or -1.1
	elseif legName == "wide" then
		dip = spec.dip or -0.6
	elseif legName == "hop" then
		lift, dip = spec.lift or -0.3, spec.dip or 1.2
	end
	local spin, flip = spec.spin or 0, spec.flip or 0
	joints.Root = {
		K(0),
		K(ta, 0, 0, 0, lift),
		K(tc, flip * 0.5, spin * 0.5, 0, dip),
		K(tf, flip, spin, 0, dip * 0.6),
		K(d, flip, spin, 0, 0),
	}
	if spec.extra then
		for joint, keys in spec.extra do
			joints[joint] = keys
		end
	end
	return { dur = d, loop = spec.loop, joints = joints }
end
local S = HeroMoves.strike

-- The older hand-keyed attacks the weapons and powers still use (Shared.HeroAnim's slash, overhead, heavy...)
-- moved only the arms and chest: HeroAnim gives each the legs of a preset (only the joints it lacks) and a root
-- dip into the hit, timed on the strike's own beats, so every attack is whole-body.
HeroMoves.LEGS_FOR = {
	slash = "step",
	slashL = "stepL",
	thrust = "step",
	nova = "wide",
	heavy = "wide",
	slam = "kneel",
	overhead = "step",
	throw = "step",
	blast2 = "back",
	lunge = "step",
	backslash = "stepL",
	heavyOver = "kneel",
	uppercut = "rise",
	bow = "wide",
} :: { [string]: string }

-- Old clips too bare to extend (the spin held its arms out and turned the root, nothing else): HeroAnim swaps
-- in these whole-body versions under the same name, so every move that used them keeps working.
HeroMoves.UPGRADES = {
	spin = S({
		dur = 0.55,
		a = 0.22,
		c = 0.5,
		f = 0.78,
		R = { w = { 20, 0, 60 }, h = { 14, 0, 92 }, f = { 20, 0, 80 }, e = { 40, 4, 10 } },
		L = { w = { 20, 0, -60 }, h = { 14, 0, -92 }, f = { 20, 0, -80 }, e = { 40, 4, 10 } },
		waist = { { 8, 34, 0 }, { -10, -16, 0 }, { -6, -8, 0 } },
		legs = "wide",
		dip = -0.5,
		spin = 360,
	}),
} :: { [string]: Clip }
function HeroMoves.addLegs(clip: Clip, legs: string): Clip
	local d = clip.dur
	local times = { 0, d * 0.3, d * 0.45, d * 0.7, d }
	local name, flip = legs, false
	if string.sub(name, -1) == "L" and LEGS[string.sub(name, 1, -2)] then
		name, flip = string.sub(name, 1, -2), true
	end
	local preset = LEGS[name] or LEGS.set
	local joints = table.clone(clip.joints)
	for joint, beats in preset do
		local to, sign = joint, 1
		if flip then
			sign = -1
			to = if string.sub(joint, 1, 5) == "Right"
				then "Left" .. string.sub(joint, 6)
				else "Right" .. string.sub(joint, 5)
		end
		if not joints[to] then
			local keys = {}
			for i, b in beats do
				keys[i] = K(times[i], b[1], (b[2] or 0) * sign, (b[3] or 0) * sign)
			end
			joints[to] = keys
		end
	end
	if not joints.Root then
		local dip = if name == "kneel" then -1.1 elseif name == "wide" then -0.6 else -0.25
		joints.Root = {
			K(0),
			K(times[2], 0, 0, 0, 0.05),
			K(times[3], 0, 0, 0, dip),
			K(times[4], 0, 0, 0, dip * 0.6),
			K(d),
		}
	end
	return { dur = d, loop = clip.loop, joints = joints }
end

local C: { [string]: Clip } = {}
HeroMoves.CLIPS = C

-- the left-hand (and left-foot) version of a clip, named name .. "L"
local function both(name: string, clip: Clip)
	C[name] = clip
	C[name .. "L"] = mirror(clip)
end

---------------------------------------------------------------------------
-- Power basics: each path's quick attack alternates hands (HeroAnimator counts the steps)
---------------------------------------------------------------------------
both(
	"flick",
	S({ dur = 0.34, R = { w = { 60, 0, 40 }, h = { 94, 0, 2 }, e = { 100, 0, 10 }, wr = { -30, 50, 20 } } })
)
both(
	"pistol",
	S({
		dur = 0.3,
		a = 0.2,
		c = 0.32,
		R = { w = { 70, 0, 10 }, h = { 92, 0, 0 }, f = { 112, 0, 0 }, e = { 30, 0, 20 }, wr = { 0, -10, 20 } },
		legs = "back",
	})
)
both(
	"kunai",
	S({
		dur = 0.32,
		R = {
			w = { 140, 0, -30 },
			h = { 70, 0, 20 },
			f = { 50, 0, 30 },
			e = { 120, 0, 10 },
			wr = { 40, -40, 0 },
		},
		waist = { { 4, 28, 0 }, { -12, -30, 0 }, { -8, -24, 0 } },
	})
)
both(
	"lance",
	S({
		dur = 0.42,
		R = { w = { 160, 0, 50 }, h = { 80, 0, 4 }, f = { 50, 0, 10 }, e = { 80, 2, 20 } },
		waist = { { 14, 36, 0 }, { -16, -28, 0 }, { -10, -20, 0 } },
		legs = "step",
	})
)
both(
	"smash",
	S({
		dur = 0.42,
		R = { w = { 120, 0, 50 }, h = { 70, 0, -10 }, f = { 50, 0, -20 }, e = { 110, 10, 20 } },
		waist = { { 10, 34, 0 }, { -20, -30, 0 }, { -14, -24, 0 } },
		legs = "step",
		dip = -0.45,
	})
)
both(
	"swipe",
	S({
		dur = 0.46,
		R = { w = { 70, 0, 96 }, h = { 84, 0, -20 }, f = { 70, 0, -46 }, e = { 20, 6, 10 } },
		waist = { { 6, 40, 0 }, { -10, -40, 0 }, { -8, -46, 0 } },
		legs = "wide",
	})
)
both(
	"spiritJab",
	S({
		dur = 0.32,
		R = { w = { 40, 0, 30 }, h = { 92, 0, 4 }, e = { 110, 0, 8 }, wr = { 0, 40, 0 } },
		legs = "step",
	})
)
both(
	"psiFlick",
	S({
		dur = 0.4,
		R = { w = { 150, 0, 40 }, h = { 94, 0, 4 }, e = { 140, 6, 14 }, wr = { 0, 50, 10 } },
		neck = { { -10, 0, 0 }, { 6, 0, 0 } },
	})
)
both(
	"pushPalm",
	S({
		dur = 0.36,
		R = { w = { 10, 0, 30 }, h = { 92, 0, 0 }, e = { 110, 0, 8 }, wr = { 0, 70, 30 } },
		legs = "step",
	})
)

---------------------------------------------------------------------------
-- Power skills and supers (HeroAnim.ABILITY_CLIPS names one per ability: no two in a path share one)
---------------------------------------------------------------------------
-- Volt
C.boltRide = S({
	dur = 0.5,
	a = 0.35,
	c = 0.5,
	R = { w = { -40, 0, 20 }, h = { 100, 0, 0 }, e = { 90, 0, 0 } },
	L = { w = { -40, 0, -20 }, h = { -50, 0, -20 }, e = { 90, 20, 20 } },
	waist = { { 16, 0, 0 }, { -36, 0, 0 }, { -30, 0, 0 } },
	legs = "step",
	lift = -0.6,
})
C.fistDown = S({
	dur = 0.6,
	R = { w = { 170, 0, 20 }, h = { 30, 0, 10 }, f = { 24, 0, 12 }, e = { 40, 0, 0 } },
	waist = { { 16, 10, 0 }, { -44, 0, 0 }, { -40, 0, 0 } },
	legs = "kneel",
})
C.palmFan = S({
	dur = 0.5,
	R = { w = { 40, 0, 60 }, h = { 88, 0, 30 }, e = { 100, 0, 6 }, wr = { 0, 60, 40 } },
	L = { w = { 40, 0, -60 }, h = { 88, 0, -30 }, e = { 100, 0, 6 }, wr = { 0, 60, 40 } },
	legs = "wide",
})
C.powerUp = S({
	dur = 0.8,
	a = 0.45,
	c = 0.6,
	f = 0.8,
	R = { w = { -20, 0, 30 }, h = { 30, 0, 80 }, f = { 30, 0, 84 }, e = { 120, 110, 110 } },
	L = { w = { -20, 0, -30 }, h = { 30, 0, -80 }, f = { 30, 0, -84 }, e = { 120, 110, 110 } },
	waist = { { -24, 0, 0 }, { 16, 0, 0 }, { 14, 0, 0 } },
	neck = { { -20, 0, 0 }, { 30, 0, 0 }, { 26, 0, 0 } },
	legs = "wide",
})
C.groundSwipe = S({
	dur = 0.55,
	R = { w = { 60, 0, 90 }, h = { 30, 0, -30 }, f = { 30, 0, -50 }, e = { 20, 0, 10 }, wr = { 0, 60, 60 } },
	waist = { { -20, 40, 0 }, { -40, -40, 0 }, { -36, -50, 0 } },
	legs = "squat",
	dip = -0.8,
})
C.thunderDrop = S({
	dur = 0.95,
	a = 0.3,
	c = 0.62,
	f = 0.8,
	R = { w = { 175, 0, 10 }, h = { 20, 0, 20 }, e = { 10, 0, 0 } },
	L = { w = { 175, 0, -10 }, h = { 20, 0, -20 }, e = { 10, 0, 0 } },
	waist = { { 20, 0, 0 }, { -50, 0, 0 }, { -44, 0, 0 } },
	legs = "kneel",
	lift = 1.4,
	dip = -1.2,
})
-- Frost
C.rampCast = S({
	dur = 0.6,
	R = { w = { -30, 0, 30 }, h = { 60, 0, 20 }, f = { 120, 0, 20 }, e = { 40, 0, 0 }, wr = { 0, -60, -40 } },
	L = {
		w = { -30, 0, -30 },
		h = { 60, 0, -20 },
		f = { 120, 0, -20 },
		e = { 40, 0, 0 },
		wr = { 0, -60, -40 },
	},
	waist = { { 20, 0, 0 }, { -20, 0, 0 }, { 8, 0, 0 } },
	legs = "step",
})
C.wallRaise = S({
	dur = 0.7,
	a = 0.35,
	c = 0.6,
	R = { w = { 10, 0, 20 }, h = { 150, 0, 14 }, e = { 20, 0, 0 }, wr = { 0, -60, -40 } },
	L = { w = { 10, 0, -20 }, h = { 150, 0, -14 }, e = { 20, 0, 0 }, wr = { 0, -60, -40 } },
	waist = { { -30, 0, 0 }, { 14, 0, 0 }, { 10, 0, 0 } },
	neck = { { -20, 0, 0 }, { 20, 0, 0 } },
	legs = "squat",
	dip = 0.2,
	lift = -0.9,
})
C.armorUp = S({
	dur = 0.7,
	R = { w = { 80, 0, -60 }, h = { 10, 0, 40 }, f = { 14, 0, 44 }, e = { 120, 60, 70 } },
	L = { w = { 80, 0, 60 }, h = { 10, 0, -40 }, f = { 14, 0, -44 }, e = { 120, 60, 70 } },
	waist = { { -14, 0, 0 }, { 10, 0, 0 } },
	legs = "wide",
})
C.grip = S({
	dur = 0.6,
	a = 0.35,
	c = 0.55,
	R = { w = { 94, 0, 6 }, h = { 70, 0, 20 }, f = { 50, 0, 30 }, e = { 0, 90, 100 }, wr = { 40, -30, -40 } },
	waist = { { -10, -10, 0 }, { 14, 20, 0 }, { 10, 16, 0 } },
	legs = "back",
})
C.blizzard = S({
	dur = 1.0,
	a = 0.25,
	c = 0.6,
	f = 0.8,
	R = { w = { 170, 0, 30 }, h = { 100, 0, 90 }, e = { 10, 0, 10 } },
	L = { w = { 170, 0, -30 }, h = { 100, 0, -90 }, e = { 10, 0, 10 } },
	waist = { { 14, 0, 0 }, { -10, 0, 0 } },
	neck = { { 30, 0, 0 }, { 0, 0, 0 } },
	legs = "wide",
	spin = 360,
})
-- Titan
C.heave = S({
	dur = 0.75,
	a = 0.4,
	c = 0.58,
	R = { w = { 175, 0, 20 }, h = { 80, 0, 14 }, f = { 50, 0, 20 }, e = { 70, 0, 10 } },
	L = { w = { 175, 0, -20 }, h = { 80, 0, -14 }, f = { 50, 0, -20 }, e = { 70, 0, 10 } },
	waist = { { 24, 0, 0 }, { -30, 0, 0 }, { -24, 0, 0 } },
	legs = "step",
	lift = -0.4,
})
C.braceUp = S({
	dur = 0.7,
	R = { w = { 60, 0, 10 }, h = { 40, 0, -30 }, f = { 40, 0, -34 }, e = { 120, 100, 100 } },
	L = { w = { 60, 0, -10 }, h = { 40, 0, 30 }, f = { 40, 0, 34 }, e = { 120, 100, 100 } },
	waist = { { 10, 0, 0 }, { -16, 0, 0 } },
	legs = "wide",
})
C.haymaker = S({
	dur = 0.7,
	a = 0.42,
	c = 0.56,
	R = { w = { 50, 0, 110 }, h = { 92, 0, -20 }, f = { 70, 0, -50 }, e = { 120, 30, 50 } },
	waist = { { 10, 60, 0 }, { -16, -50, 0 }, { -12, -60, 0 } },
	legs = "step",
	dip = -0.5,
})
C.roar = S({
	dur = 0.85,
	a = 0.3,
	c = 0.5,
	f = 0.8,
	R = { w = { 30, 0, 30 }, h = { -10, 0, 70 }, f = { -10, 0, 74 }, e = { 100, 80, 80 } },
	L = { w = { 30, 0, -30 }, h = { -10, 0, -70 }, f = { -10, 0, -74 }, e = { 100, 80, 80 } },
	waist = { { -20, 0, 0 }, { 26, 0, 0 }, { 24, 0, 0 } },
	neck = { { -20, 0, 0 }, { 40, 0, 0 }, { 36, 0, 0 } },
	legs = "wide",
})
C.meteorLeap = S({
	dur = 0.9,
	a = 0.3,
	c = 0.55,
	f = 0.8,
	R = { w = { -30, 0, 20 }, h = { 176, 0, 6 }, e = { 60, 0, 0 } },
	L = { w = { -30, 0, -20 }, h = { 60, 0, -40 }, e = { 60, 60, 60 } },
	waist = { { 30, 0, 0 }, { 10, 0, 0 } },
	neck = { { -20, 0, 0 }, { 30, 0, 0 } },
	legs = "hop",
	lift = -1.0,
	dip = 1.6,
})
-- Pulse
C.pull = S({
	dur = 0.55,
	a = 0.3,
	c = 0.6,
	R = { w = { 96, 0, 4 }, h = { 40, 0, 30 }, f = { 30, 0, 34 }, e = { 0, 110, 116 }, wr = { 60, -20, -30 } },
	waist = { { -14, -14, 0 }, { 16, 24, 0 }, { 12, 20, 0 } },
	legs = "back",
})
C.liftPalm = S({
	dur = 0.6,
	R = { w = { 50, 0, 20 }, h = { 130, 0, 14 }, e = { 70, 20, 20 }, wr = { -60, 60, 30 } },
	waist = { { -16, 10, 0 }, { 10, -14, 0 } },
	neck = { { -14, 0, 0 }, { 24, 0, 0 } },
	legs = "rise",
})
C.wellPlant = S({
	dur = 0.75,
	R = { w = { 120, 0, 60 }, h = { 60, 0, 20 }, e = { 40, 10, 10 }, wr = { 0, -60, -50 } },
	L = { w = { 120, 0, -60 }, h = { 60, 0, -20 }, e = { 40, 10, 10 }, wr = { 0, -60, -50 } },
	waist = { { 10, 0, 0 }, { -30, 0, 0 } },
	legs = "squat",
})
C.singularity = S({
	dur = 1.0,
	a = 0.45,
	c = 0.65,
	f = 0.85,
	R = { w = { 80, 0, 50 }, h = { 160, 0, -6 }, e = { 90, 60, 50 }, wr = { 0, 40, 60 } },
	L = { w = { 80, 0, -50 }, h = { 160, 0, 6 }, e = { 90, 60, 50 }, wr = { 0, 40, 60 } },
	waist = { { -10, 0, 0 }, { 20, 0, 0 } },
	neck = { { 0, 0, 0 }, { 30, 0, 0 } },
	legs = "rise",
	lift = -0.5,
	dip = 0.6,
})
-- Blade
C.iaiDash = S({
	dur = 0.5,
	a = 0.4,
	c = 0.55,
	R = { w = { 30, 0, -50 }, h = { 90, 0, 80 }, f = { 80, 0, 96 }, e = { 100, 0, 6 } },
	L = { w = { 20, 0, 20 }, h = { -30, 0, -30 }, e = { 90, 30, 30 } },
	waist = { { 10, -30, 0 }, { -30, 34, 0 }, { -24, 40, 0 } },
	legs = "step",
	lift = -0.7,
	dip = -0.7,
})
C.crescent = S({
	dur = 0.55,
	R = { w = { 20, 0, -40 }, h = { 150, 0, 60 }, f = { 170, 0, 70 }, e = { 70, 0, 4 } },
	waist = { { 20, -30, 0 }, { -20, 30, 0 }, { -10, 36, 0 } },
	legs = "step",
})
C.risingCut = S({
	dur = 0.6,
	R = { w = { -20, 0, 30 }, h = { 170, 0, 20 }, e = { 40, 0, 0 } },
	waist = { { 20, 20, 0 }, { -10, -16, 0 } },
	neck = { { -14, 0, 0 }, { 30, 0, 0 } },
	legs = "hop",
	lift = -0.6,
	dip = 1.0,
})
C.parryStance = S({
	dur = 0.6,
	R = { w = { 30, 0, 60 }, h = { 84, 0, -24 }, f = { 84, 0, -26 }, e = { 90, 60, 60 }, wr = { 0, 0, 80 } },
	L = { w = { 30, 0, -30 }, h = { 70, 0, 20 }, f = { 70, 0, 22 }, e = { 90, 90, 90 } },
	waist = { { 4, 20, 0 }, { -6, -20, 0 } },
	legs = "wide",
})
C.heavenSplit = S({
	dur = 1.1,
	a = 0.45,
	c = 0.62,
	f = 0.82,
	R = { w = { 178, 0, 4 }, h = { 40, 0, 4 }, f = { 24, 0, 6 }, e = { 20, 0, 0 } },
	L = { w = { 178, 0, -4 }, h = { 40, 0, -4 }, f = { 24, 0, -6 }, e = { 20, 0, 0 } },
	waist = { { 24, 0, 0 }, { -50, 0, 0 }, { -46, 0, 0 } },
	neck = { { 24, 0, 0 }, { -10, 0, 0 } },
	legs = "kneel",
	lift = 1.0,
})
-- Fire
C.jetLift = S({
	dur = 0.6,
	R = { w = { 40, 0, 20 }, h = { -30, 0, 20 }, e = { 80, 0, 0 }, wr = { 0, -80, 0 } },
	L = { w = { 40, 0, -20 }, h = { -30, 0, -20 }, e = { 80, 0, 0 }, wr = { 0, -80, 0 } },
	waist = { { 16, 0, 0 }, { -6, 0, 0 } },
	neck = { { -10, 0, 0 }, { 20, 0, 0 } },
	legs = "hop",
	dip = 0.8,
})
C.fireWhip = S({
	dur = 0.55,
	a = 0.38,
	c = 0.5,
	R = { w = { 160, 0, 70 }, h = { 70, 0, -30 }, f = { 40, 0, -40 }, e = { 90, 0, 20 }, wr = { 0, -50, 10 } },
	waist = { { 6, 40, 0 }, { -10, -36, 0 }, { -6, -40, 0 } },
	legs = "step",
})
C.ringSpin = S({
	dur = 0.7,
	R = { w = { 40, 0, 90 }, h = { 60, 0, 90 }, e = { 10, 4, 10 } },
	L = { w = { 40, 0, -90 }, h = { 60, 0, -90 }, e = { 10, 4, 10 } },
	waist = { { 6, 0, 0 }, { -6, 0, 0 } },
	legs = "wide",
	spin = 360,
})
C.hazeWave = S({
	dur = 0.65,
	R = { w = { 30, 0, -20 }, h = { 80, 0, 70 }, e = { 60, 20, 20 }, wr = { 0, 40, 40 } },
	L = { w = { 30, 0, 20 }, h = { 80, 0, -70 }, e = { 60, 20, 20 }, wr = { 0, 40, 40 } },
	waist = { { 10, 0, 0 }, { -10, 0, 0 } },
	legs = "back",
})
C.phoenixDive = S({
	dur = 0.65,
	R = { w = { 20, 0, 100 }, h = { -40, 0, 70 }, e = { 20, 10, 10 } },
	L = { w = { 20, 0, -100 }, h = { -40, 0, -70 }, e = { 20, 10, 10 } },
	waist = { { 20, 0, 0 }, { -40, 0, 0 } },
	neck = { { 0, 0, 0 }, { 30, 0, 0 } },
	legs = "hop",
	dip = 0.6,
})
C.sunfall = S({
	dur = 1.1,
	a = 0.5,
	c = 0.68,
	f = 0.85,
	R = { w = { 170, 0, 30 }, h = { 60, 0, 10 }, e = { 50, 0, 10 }, wr = { 0, 60, 30 } },
	L = { w = { 170, 0, -30 }, h = { 60, 0, -10 }, e = { 50, 0, 10 }, wr = { 0, 60, 30 } },
	waist = { { 24, 0, 0 }, { -36, 0, 0 } },
	neck = { { 36, 0, 0 }, { -10, 0, 0 } },
	legs = "squat",
	lift = 0.6,
})
-- Earth and Tide
C.summonRise = S({
	dur = 0.7,
	R = { w = { 20, 0, 20 }, h = { 120, 0, 20 }, e = { 60, 30, 30 }, wr = { -50, -50, -40 } },
	L = { w = { 20, 0, -20 }, h = { 120, 0, -20 }, e = { 60, 30, 30 }, wr = { -50, -50, -40 } },
	waist = { { -30, 0, 0 }, { 10, 0, 0 } },
	legs = "squat",
	lift = -1.0,
	dip = 0.1,
})
C.earthPush = S({
	dur = 0.6,
	R = { w = { -20, 0, 30 }, h = { 80, 0, 10 }, e = { 110, 0, 6 }, wr = { 0, 70, 30 } },
	L = { w = { -20, 0, -30 }, h = { 80, 0, -10 }, e = { 110, 0, 6 }, wr = { 0, 70, 30 } },
	waist = { { 10, 0, 0 }, { -24, 0, 0 } },
	legs = "wide",
})
C.rootGrab = S({
	dur = 0.65,
	a = 0.3,
	c = 0.45,
	R = { w = { 140, 0, 20 }, h = { 30, 0, 14 }, f = { 90, 0, 14 }, e = { 40, 0, 70 }, wr = { 0, -40, -60 } },
	waist = { { 10, 10, 0 }, { -40, 0, 0 }, { -10, 0, 0 } },
	legs = "kneel",
})
C.overgrowth = S({
	dur = 1.1,
	a = 0.3,
	c = 0.5,
	f = 0.85,
	R = { w = { 30, 0, 20 }, h = { 30, 0, 10 }, f = { 170, 0, 20 }, e = { 20, 0, 10 }, wr = { 0, -60, 0 } },
	L = { w = { 30, 0, -20 }, h = { 30, 0, -10 }, f = { 170, 0, -20 }, e = { 20, 0, 10 }, wr = { 0, -60, 0 } },
	waist = { { -10, 0, 0 }, { -44, 0, 0 }, { 16, 0, 0 } },
	neck = { { 0, 0, 0 }, { -10, 0, 0 }, { 30, 0, 0 } },
	legs = "kneel",
})
C.bubbleCup = S({
	dur = 0.6,
	R = { w = { 40, 0, 40 }, h = { 86, 0, 26 }, e = { 120, 40, 40 }, wr = { 0, 50, 40 } },
	L = { w = { 40, 0, -40 }, h = { 86, 0, -26 }, e = { 120, 40, 40 }, wr = { 0, 50, 40 } },
	waist = { { -8, 0, 0 }, { -12, 0, 0 } },
	legs = "step",
})
C.tsunami = S({
	dur = 1.05,
	a = 0.4,
	c = 0.62,
	f = 0.82,
	R = { w = { -40, 0, 30 }, h = { 150, 0, 30 }, f = { 70, 0, 20 }, e = { 20, 0, 10 } },
	L = { w = { -40, 0, -30 }, h = { 150, 0, -30 }, f = { 70, 0, -20 }, e = { 20, 0, 10 } },
	waist = { { -30, 30, 0 }, { 16, -10, 0 }, { -30, 0, 0 } },
	neck = { { 0, -20, 0 }, { 20, 10, 0 }, { 0, 0, 0 } },
	legs = "step",
	lift = -0.6,
})
-- Gunslinger
C.recoilJump = S({
	dur = 0.6,
	R = { w = { 30, 0, 10 }, h = { -10, 0, 10 }, f = { 10, 0, 10 }, e = { 20, 0, 10 } },
	L = { w = { 30, 0, -10 }, h = { -10, 0, -10 }, f = { 10, 0, -10 }, e = { 20, 0, 10 } },
	waist = { { -20, 0, 0 }, { 10, 0, 0 } },
	neck = { { -40, 0, 0 }, { -30, 0, 0 } },
	legs = "hop",
	dip = 1.4,
})
C.trickShot = S({
	dur = 0.7,
	a = 0.25,
	c = 0.7,
	f = 0.82,
	R = { w = { 30, 0, 20 }, h = { 90, 0, 0 }, e = { 80, 0, 0 } },
	waist = { { 0, 0, 0 }, { -8, -20, 0 } },
	legs = "set",
	spin = 360,
})
C.bulletTime = S({
	dur = 0.85,
	a = 0.3,
	c = 0.55,
	f = 0.8,
	R = { w = { 60, 0, 30 }, h = { 100, 0, 60 }, e = { 40, 10, 10 } },
	L = { w = { 60, 0, -30 }, h = { 100, 0, -60 }, e = { 40, 10, 10 } },
	waist = { { 0, 0, 0 }, { 40, 0, 0 }, { 36, 0, 0 } },
	neck = { { 0, 0, 0 }, { 10, 0, 0 } },
	legs = "wide",
	dip = -0.8,
})
C.roll = S({
	dur = 0.6,
	a = 0.2,
	c = 0.5,
	f = 0.8,
	R = { w = { 60, 0, 20 }, h = { 100, 0, 30 }, e = { 100, 110, 100 } },
	L = { w = { 60, 0, -20 }, h = { 100, 0, -30 }, e = { 100, 110, 100 } },
	waist = { { -20, 0, 0 }, { -50, 0, 0 }, { -30, 0, 0 } },
	legs = "hop",
	lift = -0.6,
	dip = -1.0,
	flip = 360,
})
C.aimDown = S({
	dur = 0.75,
	a = 0.4,
	c = 0.6,
	R = { w = { 60, 0, 10 }, h = { 92, 0, 0 }, f = { 92, 0, 0 }, e = { 40, 0, 0 } },
	L = { w = { 50, 0, -10 }, h = { 86, 0, 30 }, f = { 86, 0, 30 }, e = { 60, 40, 40 } },
	waist = { { 0, 10, 0 }, { -6, -16, 0 } },
	neck = { { 0, 0, 0 }, { 0, 10, 10 } },
	legs = "step",
})
C.highNoon = S({
	dur = 1.2,
	a = 0.55,
	c = 0.65,
	f = 0.88,
	R = { w = { -10, 0, 16 }, h = { 92, 0, 0 }, f = { 104, 0, 0 }, e = { 60, 0, 10 } },
	L = { w = { 20, 0, -10 }, h = { 84, 0, 20 }, f = { 84, 0, 30 }, e = { 70, 40, 30 }, wr = { 0, 40, 40 } },
	waist = { { 4, 0, 0 }, { -4, -20, 0 } },
	legs = "wide",
	dip = -0.4,
})
-- Gadgeteer
C.hopOn = S({
	dur = 0.6,
	R = { w = { 60, 0, 30 }, h = { 10, 0, 60 }, e = { 40, 20, 20 } },
	L = { w = { 60, 0, -30 }, h = { 10, 0, -60 }, e = { 40, 20, 20 } },
	waist = { { -20, 0, 0 }, { -6, 30, 0 } },
	legs = "hop",
	dip = 0.9,
})
C.toss = S({
	dur = 0.55,
	R = { w = { -50, 0, 16 }, h = { 70, 0, 4 }, f = { 90, 0, 4 }, e = { 10, 20, 30 }, wr = { 40, -30, 0 } },
	waist = { { 10, 20, 0 }, { -14, -14, 0 } },
	legs = "step",
})
C.grappleFire = S({
	dur = 0.55,
	a = 0.25,
	c = 0.4,
	R = {
		w = { 80, 0, 10 },
		h = { 110, 0, 0 },
		f = { 60, 0, 20 },
		e = { 30, 0, 100 },
		wr = { -40, -60, -20 },
	},
	L = { w = { 40, 0, -20 }, h = { 90, 0, 20 }, e = { 80, 60, 70 } },
	waist = { { 0, 10, 0 }, { 10, -10, 0 }, { 16, 10, 0 } },
	legs = "back",
})
C.minePlant = S({
	dur = 0.6,
	R = { w = { 60, 0, 20 }, h = { 20, 0, 10 }, e = { 80, 10, 40 }, wr = { 0, -60, -30 } },
	waist = { { 0, 10, 0 }, { -50, 0, 0 } },
	legs = "kneel",
})
C.droneLaunch = S({
	dur = 0.55,
	R = { w = { 30, 0, 20 }, h = { 160, 0, 14 }, e = { 80, 10, 10 }, wr = { 0, 50, 0 } },
	waist = { { 10, 10, 0 }, { 10, -10, 0 } },
	neck = { { -10, 0, 0 }, { 40, 0, 0 } },
	legs = "rise",
})
C.decoyTap = S({
	dur = 0.6,
	R = { w = { 50, 0, -40 }, h = { 60, 0, -50 }, e = { 120, 110, 100 } },
	L = { w = { 70, 0, 30 }, h = { 76, 0, 34 }, e = { 120, 110, 110 } },
	waist = { { 0, 20, 0 }, { -6, -20, 0 } },
	neck = { { -30, 10, 0 }, { -20, 10, 0 } },
	legs = "back",
	dip = -0.1,
})
C.mechUp = S({
	dur = 1.1,
	a = 0.4,
	c = 0.6,
	f = 0.85,
	R = { w = { 80, 0, -50 }, h = { 20, 0, 70 }, e = { 110, 100, 100 } },
	L = { w = { 80, 0, 50 }, h = { 20, 0, -70 }, e = { 110, 100, 100 } },
	waist = { { -20, 0, 0 }, { 14, 0, 0 } },
	neck = { { -20, 0, 0 }, { 20, 0, 0 } },
	legs = "wide",
	dip = -0.9,
})
-- Shadow
C.smokeSlam = S({
	dur = 0.55,
	R = { w = { 150, 0, 30 }, h = { 20, 0, 10 }, e = { 80, 10, 10 }, wr = { 0, -50, 0 } },
	waist = { { 14, 20, 0 }, { -40, 0, 0 } },
	legs = "squat",
})
C.handSign = S({
	dur = 0.7,
	a = 0.25,
	c = 0.55,
	R = {
		w = { 70, 0, -30 },
		h = { 76, 0, -36 },
		f = { 80, 0, -30 },
		e = { 120, 124, 126 },
		wr = { 0, 30, -30 },
	},
	L = { w = { 70, 0, 30 }, h = { 76, 0, 36 }, f = { 80, 0, 30 }, e = { 120, 124, 126 }, wr = { 0, 30, 30 } },
	waist = { { 0, 0, 0 }, { -10, 0, 0 } },
	neck = { { -14, 0, 0 }, { -10, 0, 0 } },
	legs = "wide",
})
C.markPoint = S({
	dur = 0.55,
	R = { w = { 140, 0, 30 }, h = { 94, 0, 0 }, f = { 94, 0, 0 }, e = { 100, 0, 0 }, wr = { 0, 20, 0 } },
	waist = { { 0, 20, 0 }, { -10, -24, 0 } },
	legs = "step",
})
C.flipStrike = S({
	dur = 0.7,
	a = 0.2,
	c = 0.6,
	f = 0.78,
	R = { w = { 170, 0, 20 }, h = { 50, 0, -20 }, e = { 40, 0, 10 } },
	waist = { { 20, 0, 0 }, { -30, 0, 0 } },
	legs = "hop",
	flip = 360,
	dip = 0.6,
})
C.eclipse = S({
	dur = 1.1,
	a = 0.45,
	c = 0.6,
	f = 0.85,
	R = { w = { 80, 0, -60 }, h = { 40, 0, 100 }, e = { 130, 10, 10 } },
	L = { w = { 80, 0, 60 }, h = { 40, 0, -100 }, e = { 130, 10, 10 } },
	waist = { { -36, 0, 0 }, { 24, 0, 0 }, { 20, 0, 0 } },
	neck = { { -30, 0, 0 }, { 30, 0, 0 } },
	legs = "squat",
	lift = -1.0,
	dip = 0.4,
})
-- Martial
C.skyStep = S({
	dur = 0.6,
	R = { w = { -20, 0, 20 }, h = { 140, 0, 20 }, e = { 80, 20, 20 } },
	L = { w = { 60, 0, -20 }, h = { -30, 0, -20 }, e = { 80, 40, 40 } },
	waist = { { 16, 0, 0 }, { -4, 0, 0 } },
	legs = "kick",
	lift = -0.4,
	dip = 1.2,
})
C.kiBlast = S({
	dur = 0.9,
	a = 0.55,
	c = 0.66,
	R = { w = { -10, 0, -10 }, h = { 92, 0, 6 }, f = { 94, 0, 6 }, e = { 110, 0, 0 }, wr = { 60, 70, 70 } },
	L = { w = { -10, 0, 10 }, h = { 92, 0, -6 }, f = { 94, 0, -6 }, e = { 110, 0, 0 }, wr = { 60, 70, 70 } },
	waist = { { 4, 50, 0 }, { -10, 0, 0 } },
	neck = { { 0, -40, 0 }, { 0, 0, 0 } },
	legs = "wide",
})
C.counterStance = S({
	dur = 0.6,
	R = { w = { 30, 0, 30 }, h = { 86, 0, 4 }, f = { 86, 0, 4 }, e = { 90, 20, 20 }, wr = { 0, 70, 30 } },
	L = { w = { 30, 0, -30 }, h = { 50, 0, 20 }, f = { 50, 0, 20 }, e = { 90, 110, 110 } },
	waist = { { 0, 20, 0 }, { -4, -10, 0 } },
	legs = "back",
	dip = -0.5,
})
C.dragonRise = S({
	dur = 0.75,
	R = { w = { -20, 0, 20 }, h = { 176, 0, 10 }, e = { 110, 20, 10 } },
	waist = { { 30, 30, 0 }, { -10, -20, 0 } },
	neck = { { -10, 0, 0 }, { 40, 0, 0 } },
	legs = "hop",
	lift = -0.8,
	dip = 1.4,
	spin = 360,
})
C.focusBreath = S({
	dur = 0.85,
	a = 0.4,
	c = 0.6,
	f = 0.8,
	R = { w = { 60, 0, -10 }, h = { 50, 0, -24 }, e = { 110, 100, 100 }, wr = { 0, 0, -40 } },
	L = { w = { 60, 0, 10 }, h = { 50, 0, 24 }, e = { 110, 100, 100 }, wr = { 0, 0, 40 } },
	waist = { { 10, 0, 0 }, { -6, 0, 0 } },
	neck = { { 20, 0, 0 }, { -14, 0, 0 } },
	legs = "wide",
	dip = -0.5,
})
C.heavenfall = S({
	dur = 1.15,
	a = 0.45,
	c = 0.62,
	f = 0.85,
	R = { w = { 30, 0, -10 }, h = { 60, 0, 4 }, e = { 120, 0, 0 }, wr = { 60, 70, 70 } },
	L = { w = { 30, 0, 10 }, h = { 60, 0, -4 }, e = { 120, 0, 0 }, wr = { 60, 70, 70 } },
	waist = { { 20, 50, 0 }, { -30, 0, 0 } },
	neck = { { 0, -40, 0 }, { -20, 0, 0 } },
	legs = "hop",
	lift = -0.8,
	dip = 1.8,
})
-- Juggernaut and Colossus
C.girderSwing = S({
	dur = 0.75,
	a = 0.42,
	c = 0.58,
	R = { w = { 90, 0, 100 }, h = { 80, 0, -50 }, e = { 40, 10, 20 } },
	L = { w = { 90, 0, 60 }, h = { 80, 0, -80 }, e = { 70, 30, 40 } },
	waist = { { 4, 64, 0 }, { -10, -60, 0 }, { -8, -70, 0 } },
	legs = "step",
	dip = -0.5,
})
C.bulldoze = S({
	dur = 0.6,
	R = { w = { 40, 0, 30 }, h = { 84, 0, 20 }, e = { 100, 60, 60 } },
	L = { w = { 40, 0, -30 }, h = { 84, 0, -20 }, e = { 100, 60, 60 } },
	waist = { { 10, 0, 0 }, { -40, 0, 0 } },
	neck = { { -10, 0, 0 }, { 30, 0, 0 } },
	legs = "step",
	dip = -0.5,
})
C.challenge = S({
	dur = 0.8,
	a = 0.25,
	c = 0.55,
	f = 0.75,
	R = { w = { 80, 0, 20 }, h = { 90, 0, 10 }, f = { 90, 0, 10 }, e = { 10, 100, 20 }, wr = { 0, -40, 0 } },
	L = { w = { 30, 0, -30 }, h = { -10, 0, -50 }, e = { 90, 90, 90 } },
	waist = { { -6, 0, 0 }, { 14, 10, 0 } },
	neck = { { 0, 0, 0 }, { 14, 0, 10 } },
	legs = "wide",
})
C.siege = S({
	dur = 1.1,
	a = 0.4,
	c = 0.6,
	f = 0.85,
	R = { w = { 160, 0, 30 }, h = { 30, 0, 30 }, e = { 60, 0, 0 } },
	L = { w = { 160, 0, -30 }, h = { 30, 0, -30 }, e = { 60, 0, 0 } },
	waist = { { 20, 0, 0 }, { -40, 0, 0 } },
	legs = "squat",
	lift = 0.5,
})
C.giantStep = S({
	dur = 0.75,
	R = { w = { -40, 0, 20 }, h = { 70, 0, 20 }, e = { 40, 30, 30 } },
	L = { w = { 70, 0, -20 }, h = { -40, 0, -20 }, e = { 40, 30, 30 } },
	waist = { { 10, -20, 0 }, { -14, 20, 0 } },
	legs = "kick",
	dip = 0.6,
})
C.clap = S({
	dur = 0.65,
	a = 0.4,
	c = 0.55,
	R = { w = { 80, 0, 100 }, h = { 90, 0, -6 }, f = { 90, 0, -10 }, e = { 10, 0, 10 }, wr = { 0, 80, 0 } },
	L = { w = { 80, 0, -100 }, h = { 90, 0, 6 }, f = { 90, 0, 10 }, e = { 10, 0, 10 }, wr = { 0, 80, 0 } },
	waist = { { -14, 0, 0 }, { -10, 0, 0 } },
	legs = "wide",
})
C.duck = S({
	dur = 0.55,
	a = 0.2,
	c = 0.4,
	f = 0.7,
	R = { w = { 60, 0, 20 }, h = { 100, 0, -20 }, e = { 120, 130, 130 } },
	L = { w = { 60, 0, -20 }, h = { 100, 0, 20 }, e = { 120, 130, 130 } },
	waist = { { 0, 0, 0 }, { -40, 0, 0 } },
	legs = "squat",
	dip = -1.4,
})
C.titanRise = S({
	dur = 1.2,
	a = 0.35,
	c = 0.65,
	f = 0.85,
	R = { w = { 30, 0, -20 }, h = { 150, 0, 40 }, e = { 120, 110, 100 } },
	L = { w = { 30, 0, 20 }, h = { 150, 0, -40 }, e = { 120, 110, 100 } },
	waist = { { -40, 0, 0 }, { 20, 0, 0 } },
	neck = { { -30, 0, 0 }, { 30, 0, 0 } },
	legs = "rise",
	lift = -1.2,
	dip = 0.4,
})
-- Mind, Spirit and Light
C.levitate = S({
	dur = 0.7,
	R = { w = { 20, 0, 30 }, h = { 30, 0, 70 }, e = { 40, 20, 20 }, wr = { 0, -70, 0 } },
	L = { w = { 20, 0, -30 }, h = { 30, 0, -70 }, e = { 40, 20, 20 }, wr = { 0, -70, 0 } },
	waist = { { -10, 0, 0 }, { 6, 0, 0 } },
	legs = "hop",
	dip = 0.8,
})
C.mindLock = S({
	dur = 0.8,
	a = 0.4,
	c = 0.6,
	R = { w = { 120, 0, 60 }, h = { 94, 0, 6 }, e = { 140, 10, 10 }, wr = { 0, 30, 10 } },
	L = { w = { 120, 0, -60 }, h = { 94, 0, -6 }, e = { 140, 10, 10 }, wr = { 0, 30, 10 } },
	waist = { { 10, 0, 0 }, { -10, 0, 0 } },
	neck = { { -20, 0, 0 }, { 6, 0, 0 } },
	legs = "step",
})
C.barrierPush = S({
	dur = 0.65,
	R = { w = { 50, 0, -20 }, h = { 90, 0, 16 }, f = { 92, 0, 18 }, e = { 120, 20, 20 }, wr = { 0, 80, 40 } },
	L = { w = { 50, 0, 20 }, h = { 90, 0, -16 }, f = { 92, 0, -18 }, e = { 120, 20, 20 }, wr = { 0, 80, 40 } },
	waist = { { 6, 0, 0 }, { -10, 0, 0 } },
	legs = "wide",
})
C.linkReach = S({
	dur = 0.75,
	R = { w = { 30, 0, 30 }, h = { 60, 0, 90 }, f = { 60, 0, 94 }, e = { 40, 4, 4 }, wr = { 0, 40, 0 } },
	L = { w = { 30, 0, -20 }, h = { 140, 0, 40 }, e = { 120, 140, 140 } },
	waist = { { 0, 10, 0 }, { 4, -24, 0 } },
	neck = { { -10, 0, 0 }, { 0, -30, 0 } },
	legs = "set",
})
C.psiStorm = S({
	dur = 1.15,
	a = 0.45,
	c = 0.62,
	f = 0.85,
	R = { w = { 120, 0, 40 }, h = { 60, 0, 100 }, e = { 140, 10, 10 }, wr = { 0, 60, 20 } },
	L = { w = { 120, 0, -40 }, h = { 60, 0, -100 }, e = { 140, 10, 10 }, wr = { 0, 60, 20 } },
	waist = { { -10, 0, 0 }, { 24, 0, 0 } },
	neck = { { -20, 0, 0 }, { 44, 0, 0 } },
	legs = "hop",
	lift = 0.4,
	dip = 1.4,
})
C.totemPlant = S({
	dur = 0.7,
	a = 0.4,
	c = 0.55,
	R = { w = { 160, 0, 10 }, h = { 40, 0, 10 }, e = { 40, 70, 70 } },
	L = { w = { 150, 0, 20 }, h = { 50, 0, 20 }, e = { 50, 80, 80 } },
	waist = { { 16, 0, 0 }, { -30, 0, 0 } },
	legs = "squat",
	lift = 0.4,
})
C.ascend = S({
	dur = 1.2,
	a = 0.45,
	c = 0.68,
	f = 0.88,
	R = { w = { 60, 0, -14 }, h = { 150, 0, 70 }, e = { 120, 10, 10 } },
	L = { w = { 60, 0, 14 }, h = { 150, 0, -70 }, e = { 120, 10, 10 } },
	waist = { { -30, 0, 0 }, { 24, 0, 0 } },
	neck = { { -30, 0, 0 }, { 40, 0, 0 } },
	legs = "kneel",
	dip = 0.6,
})
C.flash = S({
	dur = 0.65,
	a = 0.35,
	c = 0.5,
	R = { w = { 110, 0, -40 }, h = { 60, 0, 100 }, e = { 130, 10, 10 }, wr = { 0, 60, 0 } },
	L = { w = { 110, 0, 40 }, h = { 60, 0, -100 }, e = { 130, 10, 10 }, wr = { 0, 60, 0 } },
	waist = { { -20, 0, 0 }, { 20, 0, 0 } },
	neck = { { -30, 0, 0 }, { 20, 0, 0 } },
	legs = "rise",
})
C.dawnburst = S({
	dur = 1.15,
	a = 0.5,
	c = 0.64,
	f = 0.86,
	R = { w = { 70, 0, -50 }, h = { 140, 0, 110 }, e = { 130, 0, 6 } },
	L = { w = { 70, 0, 50 }, h = { 140, 0, -110 }, e = { 130, 0, 6 } },
	waist = { { -40, 0, 0 }, { 26, 0, 0 } },
	neck = { { -30, 0, 0 }, { 40, 0, 0 } },
	legs = "hop",
	lift = -1.0,
	dip = 1.6,
})

-- Channels: held loops (HeroAnimator plays them for the channel's length)
C.flurry = { -- Hundred Fists: alternating straight punches, fast, from a wide stance
	dur = 0.24,
	loop = true,
	joints = {
		RightShoulder = { K(0, 50, 0, 14), K(0.06, 92, 0, 4), K(0.12, 50, 0, 14), K(0.24, 50, 0, 14) },
		RightElbow = { K(0, 100), K(0.06, 4), K(0.12, 100), K(0.24, 100) },
		LeftShoulder = { K(0, 50, 0, -14), K(0.12, 50, 0, -14), K(0.18, 92, 0, -4), K(0.24, 50, 0, -14) },
		LeftElbow = { K(0, 100), K(0.12, 100), K(0.18, 4), K(0.24, 100) },
		Waist = { K(0, -8, 14), K(0.06, -10, -16), K(0.12, -8, 0), K(0.18, -10, 16), K(0.24, -8, 14) },
		Neck = hold(4),
		RightHip = hold(30, 0, 24),
		LeftHip = hold(30, 0, -24),
		RightKnee = hold(-56),
		LeftKnee = hold(-56),
		Root = { K(0, 0, 0, 0, -0.6), K(0.12, 0, 0, 0, -0.66), K(0.24, 0, 0, 0, -0.6) },
	},
}
C.bladeFlurry = { -- Thousand Cuts: the blade cuts back and forth, the body turning with each cut
	dur = 0.3,
	loop = true,
	joints = {
		RightShoulder = { K(0, 130, 0, 60), K(0.15, 70, 0, -30), K(0.3, 130, 0, 60) },
		RightElbow = { K(0, 30), K(0.15, 4), K(0.3, 30) },
		LeftShoulder = hold(40, 0, -30),
		LeftElbow = hold(80),
		Waist = { K(0, -10, 30), K(0.15, -14, -30), K(0.3, -10, 30) },
		Neck = { K(0, 0, -16), K(0.15, 0, 16), K(0.3, 0, -16) },
		RightHip = hold(40, 0, 4),
		RightKnee = hold(-44),
		LeftHip = hold(-20),
		LeftKnee = hold(-20),
		Root = hold(0, 0, 0, -0.4),
	},
}
C.guardianPush = { -- Guardian Rush: both palms pump forward as the guardian strikes
	dur = 0.4,
	loop = true,
	joints = {
		RightShoulder = { K(0, 60, 0, 30), K(0.1, 92, 0, 10), K(0.2, 60, 0, 30), K(0.4, 60, 0, 30) },
		LeftShoulder = { K(0, 60, 0, -30), K(0.2, 60, 0, -30), K(0.3, 92, 0, -10), K(0.4, 60, 0, -30) },
		RightElbow = { K(0, 90), K(0.1, 10), K(0.2, 90), K(0.4, 90) },
		LeftElbow = { K(0, 90), K(0.2, 90), K(0.3, 10), K(0.4, 90) },
		RightWrist = hold(60),
		LeftWrist = hold(60),
		Waist = { K(0, -6, 10), K(0.1, -10, -12), K(0.2, -6, 0), K(0.3, -10, 12), K(0.4, -6, 10) },
		RightHip = hold(30, 0, 10),
		LeftHip = hold(-14, 0, -8),
		RightKnee = hold(-40),
		LeftKnee = hold(-20),
		Root = hold(0, 0, 0, -0.35),
	},
}

---------------------------------------------------------------------------
-- Weapons (HeroAnim.WEAPON_MOVES: each weapon's 4-hit combo and its Z X C V)
---------------------------------------------------------------------------
-- Fists
both(
	"jab",
	S({ dur = 0.26, a = 0.25, c = 0.38, L = { w = { 50, 0, -10 }, h = { 92, 0, -4 }, e = { 110, 2, 20 } } })
)
C.cross = S({
	dur = 0.32,
	R = { w = { 46, 0, 20 }, h = { 92, 0, -6 }, e = { 116, 2, 14 } },
	legs = "step",
	dip = -0.3,
})
C.hook = S({
	dur = 0.36,
	L = { w = { 60, 0, -60 }, h = { 86, 0, 20 }, f = { 80, 0, 40 }, e = { 90, 90, 90 } },
	waist = { { 4, -30, 0 }, { -6, 34, 0 }, { -4, 40, 0 } },
	legs = "set",
})
C.launchUpper = S({
	dur = 0.42,
	R = { w = { -10, 0, 20 }, h = { 156, 0, 10 }, e = { 110, 50, 60 } },
	waist = { { 16, 20, 0 }, { -8, -20, 0 } },
	neck = { { -10, 0, 0 }, { 24, 0, 0 } },
	legs = "rise",
	lift = -0.5,
	dip = 0.3,
})
C.grabSlam = S({
	dur = 0.75,
	a = 0.3,
	c = 0.62,
	f = 0.8,
	R = { w = { 92, 0, 10 }, h = { 30, 0, 10 }, e = { 20, 0, 10 } },
	L = { w = { 92, 0, -10 }, h = { 30, 0, -10 }, e = { 20, 0, 10 } },
	waist = { { 20, 0, 0 }, { -50, 0, 0 } },
	legs = "kneel",
	lift = 0.5,
	extra = {
		RightShoulder = {
			K(0, 30, 0, 14),
			K(0.16, 92, 0, 10),
			K(0.32, 170, 0, 10),
			K(0.46, 30, 0, 10),
			K(0.6, 26, 0, 12),
			K(0.75, 30, 0, 14),
		},
		LeftShoulder = {
			K(0, 30, 0, -14),
			K(0.16, 92, 0, -10),
			K(0.32, 170, 0, -10),
			K(0.46, 30, 0, -10),
			K(0.6, 26, 0, -12),
			K(0.75, 30, 0, -14),
		},
	},
})
C.rush = S({
	dur = 0.55,
	a = 0.2,
	c = 0.5,
	R = { w = { 50, 0, 20 }, h = { 92, 0, 0 }, e = { 110, 0, 10 } },
	L = { w = { 92, 0, 0 }, h = { 50, 0, -20 }, e = { 0, 110, 100 } },
	waist = { { -14, 20, 0 }, { -24, -24, 0 } },
	legs = "step",
	dip = -0.5,
})
C.groundPound = S({
	dur = 0.8,
	a = 0.35,
	c = 0.6,
	f = 0.8,
	R = { w = { 175, 0, 14 }, h = { 30, 0, 14 }, e = { 50, 0, 0 } },
	L = { w = { 175, 0, -14 }, h = { 30, 0, -14 }, e = { 50, 0, 0 } },
	waist = { { 24, 0, 0 }, { -50, 0, 0 } },
	legs = "kneel",
	lift = 1.2,
})
-- Martial Arts and Strikers
C.palmJab =
	S({ dur = 0.28, R = { w = { 30, 0, 20 }, h = { 92, 0, 0 }, e = { 120, 0, 6 }, wr = { 0, 70, 40 } } })
both(
	"roundhouse",
	S({
		dur = 0.5,
		R = { w = { 40, 0, 30 }, h = { 20, 0, 60 }, e = { 90, 80, 80 } },
		L = { w = { 50, 0, -20 }, h = { 60, 0, -40 }, e = { 100, 90, 90 } },
		waist = { { 6, 30, 0 }, { 20, -50, 0 }, { 10, -40, 0 } },
		legs = "roundKick",
	})
)
C.spinKick = S({
	dur = 0.6,
	a = 0.2,
	c = 0.6,
	f = 0.78,
	R = { w = { 40, 0, 40 }, h = { 20, 0, 70 }, e = { 90, 60, 60 } },
	L = { w = { 40, 0, -40 }, h = { 20, 0, -70 }, e = { 90, 60, 60 } },
	waist = { { 0, 20, 0 }, { 24, -20, 0 } },
	legs = "roundKick",
	spin = 360,
})
both(
	"frontKick",
	S({
		dur = 0.42,
		R = { w = { 50, 0, 30 }, h = { 30, 0, 40 }, e = { 100, 80, 80 } },
		L = { w = { 50, 0, -30 }, h = { 60, 0, -30 }, e = { 100, 90, 90 } },
		waist = { { -6, 0, 0 }, { 20, 0, 0 } },
		legs = "kick",
	})
)
C.kneeStrike = S({
	dur = 0.42,
	R = { w = { 90, 0, 20 }, h = { 50, 0, 20 }, e = { 90, 120, 110 } },
	L = { w = { 90, 0, -20 }, h = { 50, 0, -20 }, e = { 90, 120, 110 } },
	waist = { { 4, 0, 0 }, { -24, 0, 0 } },
	legs = "hop",
	lift = 0,
	dip = 0.5,
	extra = {
		RightHip = { K(0), K(0.13, 30), K(0.19, 110), K(0.3, 90), K(0.42) },
		RightKnee = { K(0), K(0.13, -40), K(0.19, -120), K(0.3, -110), K(0.42) },
	},
})
C.sweepKick = S({
	dur = 0.6,
	a = 0.25,
	c = 0.55,
	f = 0.8,
	R = { w = { 30, 0, 30 }, h = { -20, 0, 50 }, e = { 40, 10, 10 }, wr = { 0, -60, 0 } },
	L = { w = { 60, 0, -20 }, h = { 20, 0, -40 }, e = { 60, 40, 40 } },
	waist = { { -20, 0, 0 }, { -40, 0, 0 } },
	legs = "squat",
	spin = 360,
	extra = {
		RightHip = { K(0), K(0.15, 60, 0, 20), K(0.33, 20, 0, 80), K(0.48, 30, 0, 60), K(0.6) },
		RightKnee = { K(0), K(0.15, -100), K(0.33, -6), K(0.48, -40), K(0.6) },
	},
})
C.flyingKick = S({
	dur = 0.6,
	R = { w = { 40, 0, 40 }, h = { -10, 0, 50 }, e = { 80, 30, 30 } },
	L = { w = { 40, 0, -40 }, h = { 90, 0, -20 }, e = { 80, 90, 90 } },
	waist = { { 10, 0, 0 }, { 16, 0, 0 } },
	legs = "kick",
	lift = -0.5,
	dip = 1.2,
})
C.flurryBurst = S({
	dur = 0.7,
	a = 0.15,
	c = 0.6,
	R = { w = { 50, 0, 14 }, h = { 92, 0, 4 }, e = { 100, 4, 10 } },
	L = { w = { 92, 0, -4 }, h = { 92, 0, -4 }, e = { 4, 4, 10 } },
	waist = { { -6, 14, 0 }, { -10, -14, 0 } },
	legs = "wide",
	extra = {
		RightShoulder = {
			K(0, 50, 0, 14),
			K(0.1, 92, 0, 4),
			K(0.18, 50, 0, 14),
			K(0.26, 92, 0, 4),
			K(0.34, 50, 0, 14),
			K(0.44, 96, 0, 0),
			K(0.7, 30, 0, 14),
		},
		LeftShoulder = {
			K(0, 50, 0, -14),
			K(0.06, 50, 0, -14),
			K(0.14, 92, 0, -4),
			K(0.22, 50, 0, -14),
			K(0.3, 92, 0, -4),
			K(0.38, 50, 0, -14),
			K(0.7, 30, 0, -14),
		},
		RightElbow = { K(0, 100), K(0.1, 4), K(0.18, 100), K(0.26, 4), K(0.34, 100), K(0.44, 0), K(0.7, 70) },
		LeftElbow = { K(0, 100), K(0.14, 4), K(0.22, 100), K(0.3, 4), K(0.38, 100), K(0.7, 70) },
	},
})
C.axeKick = S({
	dur = 0.65,
	a = 0.4,
	c = 0.6,
	R = { w = { 40, 0, 40 }, h = { 20, 0, 40 }, e = { 80, 60, 60 } },
	L = { w = { 40, 0, -40 }, h = { 20, 0, -40 }, e = { 80, 60, 60 } },
	waist = { { 16, 0, 0 }, { -24, 0, 0 } },
	legs = "set",
	extra = {
		RightHip = { K(0), K(0.26, 150, 0, 10), K(0.39, 20, 0, 6), K(0.5, 10), K(0.65) },
		RightKnee = { K(0), K(0.26, -4), K(0.39, -10), K(0.5, -20), K(0.65) },
	},
})
C.kneeRush = S({
	dur = 0.55,
	R = { w = { 30, 0, 30 }, h = { 92, 0, 30 }, e = { 90, 60, 60 } },
	L = { w = { 30, 0, -30 }, h = { 92, 0, -30 }, e = { 90, 60, 60 } },
	waist = { { 10, 0, 0 }, { -30, 0, 0 } },
	legs = "hop",
	dip = 0.6,
	extra = {
		RightHip = { K(0), K(0.16, 20), K(0.25, 110), K(0.38, 100), K(0.55) },
		RightKnee = { K(0), K(0.16, -40), K(0.25, -124), K(0.38, -110), K(0.55) },
	},
})
C.tornadoKick = S({
	dur = 0.85,
	a = 0.25,
	c = 0.6,
	f = 0.82,
	R = { w = { 40, 0, 60 }, h = { 20, 0, 80 }, e = { 60, 40, 40 } },
	L = { w = { 40, 0, -60 }, h = { 20, 0, -80 }, e = { 60, 40, 40 } },
	waist = { { 10, 30, 0 }, { 20, -30, 0 } },
	legs = "roundKick",
	lift = -0.4,
	dip = 1.4,
	spin = 360,
})
-- Gauntlets
C.heavyJab = S({
	dur = 0.34,
	L = { w = { 50, 0, -10 }, h = { 92, 0, -4 }, e = { 110, 2, 20 } },
	legs = "stepL",
	dip = -0.35,
})
C.heavyCross = S({
	dur = 0.4,
	R = { w = { 40, 0, 30 }, h = { 92, 0, -6 }, e = { 120, 2, 14 } },
	waist = { { 10, 34, 0 }, { -16, -34, 0 }, { -12, -30, 0 } },
	legs = "step",
	dip = -0.5,
})
C.hammerFist = S({
	dur = 0.5,
	R = { w = { 170, 0, 20 }, h = { 50, 0, 10 }, f = { 36, 0, 10 }, e = { 70, 10, 20 } },
	waist = { { 20, 20, 0 }, { -34, -10, 0 } },
	legs = "step",
	dip = -0.6,
})
C.powerPunch = S({
	dur = 0.65,
	a = 0.45,
	c = 0.56,
	R = { w = { 30, 0, 40 }, h = { 94, 0, -4 }, e = { 130, 0, 6 } },
	L = { w = { 70, 0, -20 }, h = { 10, 0, -30 }, e = { 70, 100, 100 } },
	waist = { { 14, 50, 0 }, { -20, -40, 0 } },
	legs = "step",
	lift = -0.4,
	dip = -0.6,
})
C.doubleFist = S({
	dur = 0.6,
	R = { w = { 60, 0, 70 }, h = { 92, 0, 6 }, e = { 120, 4, 10 } },
	L = { w = { 60, 0, -70 }, h = { 92, 0, -6 }, e = { 120, 4, 10 } },
	legs = "step",
	dip = -0.5,
})
-- One-handed blades and clubs
C.thrustOne = S({
	dur = 0.34,
	R = { w = { 50, 0, 30 }, h = { 92, 0, -4 }, e = { 110, 0, 6 }, wr = { 40, 0, 0 } },
	waist = { { 4, 30, 0 }, { -14, -20, 0 } },
	legs = "step",
})
C.iaiDraw = S({
	dur = 0.4,
	a = 0.35,
	c = 0.48,
	R = { w = { 20, 0, -40 }, h = { 86, 0, 70 }, f = { 80, 0, 84 }, e = { 100, 4, 6 } },
	L = { w = { 10, 0, 10 }, h = { -10, 0, -10 }, e = { 80, 60, 60 } },
	waist = { { 4, -30, 0 }, { -10, 34, 0 } },
	legs = "step",
	lift = -0.4,
})
C.finisherCut = S({
	dur = 0.55,
	a = 0.35,
	c = 0.5,
	R = { w = { 176, 0, 30 }, h = { 40, 0, -20 }, f = { 30, 0, -24 }, e = { 40, 0, 4 } },
	L = { w = { 176, 0, 10 }, h = { 50, 0, 10 }, e = { 40, 20, 20 } },
	waist = { { 20, 20, 0 }, { -30, -20, 0 } },
	legs = "step",
	dip = -0.6,
})
C.sheathe = S({
	dur = 0.8,
	a = 0.3,
	c = 0.55,
	f = 0.8,
	R = { w = { 80, 0, 70 }, h = { 10, 0, -30 }, f = { 10, 0, -34 }, e = { 10, 90, 90 } },
	L = { w = { 20, 0, -10 }, h = { 10, 0, 10 }, e = { 80, 80, 80 } },
	waist = { { -6, 20, 0 }, { 4, -10, 0 } },
	neck = { { 0, 0, 0 }, { -10, 30, 0 } },
	legs = "back",
	dip = -0.4,
})
C.cutStorm = S({
	dur = 0.8,
	a = 0.15,
	c = 0.6,
	f = 0.8,
	R = { w = { 150, 0, 60 }, h = { 60, 0, -30 }, e = { 30, 4, 10 } },
	waist = { { -10, 30, 0 }, { -14, -30, 0 } },
	legs = "step",
	extra = {
		RightShoulder = {
			K(0, 30, 0, 14),
			K(0.12, 150, 0, 60),
			K(0.22, 70, 0, -30),
			K(0.32, 130, 0, 70),
			K(0.42, 60, 0, -40),
			K(0.52, 170, 0, 10),
			K(0.62, 40, 0, 0),
			K(0.8, 30, 0, 14),
		},
	},
})
C.stab = S({
	dur = 0.28,
	R = { w = { 40, 0, 30 }, h = { 86, 0, -6 }, e = { 120, 10, 20 }, wr = { -40, -40, -20 } },
})
C.stabRise = S({
	dur = 0.36,
	R = { w = { 0, 0, 20 }, h = { 120, 0, 0 }, e = { 120, 40, 50 }, wr = { -40, -60, -40 } },
	legs = "rise",
})
C.backstab = S({
	dur = 0.55,
	a = 0.3,
	c = 0.5,
	R = { w = { 160, 0, 20 }, h = { 60, 0, -10 }, e = { 120, 60, 70 }, wr = { -60, -60, -50 } },
	L = { w = { 80, 0, -20 }, h = { 70, 0, 20 }, e = { 90, 100, 100 } },
	waist = { { 14, 20, 0 }, { -30, -20, 0 } },
	legs = "step",
	lift = -0.3,
	dip = -0.5,
})
C.recall = S({
	dur = 0.55,
	a = 0.3,
	c = 0.55,
	R = { w = { 94, 0, 10 }, h = { 60, 0, -30 }, f = { 40, 0, -40 }, e = { 0, 30, 20 }, wr = { 0, -60, 0 } },
	waist = { { -6, -10, 0 }, { -10, -30, 0 } },
	legs = "back",
})
C.rend = S({
	dur = 0.7,
	a = 0.35,
	c = 0.58,
	R = { w = { 178, 0, 10 }, h = { 30, 0, 0 }, e = { 40, 0, 10 } },
	waist = { { 24, 10, 0 }, { -44, -10, 0 } },
	legs = "hop",
	lift = -0.4,
	dip = 0.7,
})
C.spinThrow = S({
	dur = 0.7,
	a = 0.25,
	c = 0.65,
	f = 0.8,
	R = { w = { 30, 0, 90 }, h = { 70, 0, 0 }, e = { 20, 4, 30 } },
	waist = { { 0, 30, 0 }, { -14, -30, 0 } },
	legs = "step",
	spin = 360,
})
both(
	"blunt",
	S({
		dur = 0.4,
		R = { w = { 100, 0, 90 }, h = { 80, 0, -30 }, f = { 66, 0, -50 }, e = { 70, 10, 20 } },
		waist = { { 6, 36, 0 }, { -10, -34, 0 } },
		legs = "step",
	})
)
C.bluntUpper = S({
	dur = 0.46,
	R = { w = { -30, 0, 30 }, h = { 150, 0, 20 }, e = { 40, 10, 20 } },
	waist = { { 20, 20, 0 }, { -6, -20, 0 } },
	legs = "rise",
	lift = -0.4,
})
C.smashDown = S({
	dur = 0.75,
	a = 0.42,
	c = 0.58,
	R = { w = { 178, 0, 30 }, h = { 30, 0, 0 }, e = { 70, 0, 10 } },
	L = { w = { 120, 0, -40 }, h = { 20, 0, -30 }, e = { 70, 60, 60 } },
	waist = { { 24, 30, 0 }, { -44, -10, 0 } },
	legs = "kneel",
	lift = 0.4,
})
C.guardSmash = S({
	dur = 0.6,
	a = 0.4,
	c = 0.55,
	R = { w = { 60, 0, -60 }, h = { 92, 0, 40 }, f = { 80, 0, 70 }, e = { 80, 4, 10 } },
	waist = { { 6, -30, 0 }, { -14, 40, 0 } },
	legs = "step",
	dip = -0.5,
})
C.batonTap = S({
	dur = 0.4,
	a = 0.3,
	c = 0.42,
	R = { w = { 110, 0, 20 }, h = { 70, 0, 6 }, e = { 70, 20, 30 }, wr = { -40, 30, 0 } },
	legs = "step",
})
-- Two-handed
C.heavyBack = S({
	dur = 0.55,
	R = { w = { 100, 0, -40 }, h = { 110, 0, 70 }, f = { 100, 0, 80 }, e = { 30, 4, 10 } },
	L = { w = { 100, 0, -60 }, h = { 110, 0, 40 }, f = { 100, 0, 50 }, e = { 50, 10, 20 } },
	waist = { { 4, -50, 0 }, { -10, 50, 0 } },
	legs = "stepL",
	dip = -0.4,
})
C.heavyRise = S({
	dur = 0.6,
	R = { w = { -30, 0, 30 }, h = { 160, 0, 14 }, e = { 30, 10, 10 } },
	L = { w = { -30, 0, 10 }, h = { 160, 0, 30 }, e = { 50, 20, 20 } },
	waist = { { 30, 20, 0 }, { -10, -10, 0 } },
	neck = { { -10, 0, 0 }, { 30, 0, 0 } },
	legs = "rise",
	lift = -0.7,
})
C.wideSweep = S({
	dur = 0.7,
	a = 0.4,
	c = 0.55,
	R = { w = { 90, 0, 120 }, h = { 80, 0, -60 }, f = { 70, 0, -90 }, e = { 20, 4, 10 } },
	L = { w = { 90, 0, 90 }, h = { 80, 0, -90 }, f = { 70, 0, -110 }, e = { 40, 10, 20 } },
	waist = { { 6, 70, 0 }, { -10, -70, 0 }, { -8, -80, 0 } },
	legs = "wide",
})
C.chargedOver = S({
	dur = 0.95,
	a = 0.55,
	c = 0.68,
	R = { w = { 178, 0, 4 }, h = { 30, 0, 4 }, e = { 50, 0, 0 } },
	L = { w = { 178, 0, -4 }, h = { 30, 0, -4 }, e = { 50, 0, 0 } },
	waist = { { 30, 0, 0 }, { -50, 0, 0 } },
	neck = { { 30, 0, 0 }, { -14, 0, 0 } },
	legs = "kneel",
	lift = 0.2,
})
C.groundSplit = S({
	dur = 0.8,
	a = 0.45,
	c = 0.6,
	R = { w = { 178, 0, 30 }, h = { 20, 0, -6 }, e = { 50, 0, 0 } },
	L = { w = { 178, 0, 10 }, h = { 20, 0, -20 }, e = { 50, 0, 0 } },
	waist = { { 24, 30, 0 }, { -54, -10, 0 } },
	legs = "squat",
	lift = 0.3,
})
C.leapChop = S({
	dur = 0.8,
	a = 0.3,
	c = 0.65,
	R = { w = { 30, 0, 20 }, h = { 30, 0, 4 }, e = { 50, 0, 10 } },
	L = { w = { 30, 0, -20 }, h = { 30, 0, -4 }, e = { 50, 0, 10 } },
	waist = { { 20, 0, 0 }, { -50, 0, 0 } },
	legs = "hop",
	dip = 1.4,
	extra = {
		RightShoulder = {
			K(0, 30, 0, 14),
			K(0.24, 30, 0, 20),
			K(0.4, 178, 0, 6),
			K(0.52, 30, 0, 4),
			K(0.8, 30, 0, 14),
		},
		LeftShoulder = {
			K(0, 30, 0, -14),
			K(0.24, 30, 0, -20),
			K(0.4, 178, 0, -6),
			K(0.52, 30, 0, -4),
			K(0.8, 30, 0, -14),
		},
	},
})
C.executioner = S({
	dur = 1.0,
	a = 0.5,
	c = 0.66,
	R = { w = { 160, 0, 90 }, h = { 40, 0, -20 }, e = { 40, 0, 10 } },
	L = { w = { 160, 0, 60 }, h = { 40, 0, -40 }, e = { 50, 10, 20 } },
	waist = { { 30, 50, 0 }, { -44, -30, 0 } },
	legs = "step",
	lift = 0.4,
	dip = -0.8,
})
C.uplift = S({
	dur = 0.65,
	R = { w = { -40, 0, 30 }, h = { 150, 0, 30 }, e = { 40, 10, 10 } },
	L = { w = { -40, 0, 10 }, h = { 150, 0, 50 }, e = { 60, 20, 20 } },
	waist = { { 30, 40, 0 }, { -10, -20, 0 } },
	legs = "squat",
	dip = 0.2,
	lift = -0.8,
})
C.hammerToss = S({
	dur = 0.75,
	a = 0.35,
	c = 0.6,
	R = { w = { 40, 0, 110 }, h = { 80, 0, -10 }, e = { 10, 4, 20 } },
	L = { w = { 40, 0, 80 }, h = { 80, 0, -30 }, e = { 30, 20, 30 } },
	waist = { { 6, 60, 0 }, { -14, -40, 0 } },
	legs = "step",
	spin = 360,
})
C.meteorHammer = S({
	dur = 1.0,
	a = 0.3,
	c = 0.65,
	f = 0.82,
	R = { w = { 178, 0, 6 }, h = { 30, 0, 6 }, e = { 40, 0, 0 } },
	L = { w = { 178, 0, -6 }, h = { 30, 0, -6 }, e = { 40, 0, 0 } },
	waist = { { 30, 0, 0 }, { -54, 0, 0 } },
	legs = "hop",
	lift = -0.6,
	dip = 1.6,
	extra = {
		Root = {
			K(0),
			K(0.3, 0, 0, 0, -0.6),
			K(0.5, 0, 0, 0, 1.6),
			K(0.65, 0, 0, 0, -1.2),
			K(0.82, 0, 0, 0, -1.0),
			K(1.0),
		},
	},
})
C.poleSweep = S({
	dur = 0.6,
	R = { w = { 60, 0, 90 }, h = { 30, 0, -50 }, f = { 20, 0, -70 }, e = { 40, 10, 20 } },
	L = { w = { 60, 0, 60 }, h = { 30, 0, -70 }, f = { 20, 0, -90 }, e = { 50, 20, 30 } },
	waist = { { -10, 50, 0 }, { -30, -50, 0 } },
	legs = "squat",
	dip = -0.8,
})
C.thrustLunge = S({
	dur = 0.5,
	a = 0.35,
	c = 0.5,
	R = { w = { 40, 0, 30 }, h = { 92, 0, 0 }, e = { 110, 0, 10 } },
	L = { w = { 50, 0, 30 }, h = { 86, 0, 10 }, e = { 70, 20, 30 } },
	waist = { { 10, 40, 0 }, { -30, -10, 0 } },
	legs = "step",
	lift = -0.4,
	dip = -0.8,
})
C.vault = S({
	dur = 0.75,
	a = 0.3,
	c = 0.55,
	R = { w = { 60, 0, 10 }, h = { 30, 0, 10 }, f = { -20, 0, 10 }, e = { 30, 10, 10 } },
	L = { w = { 60, 0, 30 }, h = { 30, 0, 30 }, f = { -20, 0, 30 }, e = { 50, 20, 20 } },
	waist = { { -10, 0, 0 }, { -20, 0, 0 }, { 10, 0, 0 } },
	legs = "hop",
	dip = 1.8,
	flip = 360,
})
C.pierce = S({
	dur = 0.7,
	a = 0.5,
	c = 0.62,
	R = { w = { 30, 0, 30 }, h = { 94, 0, -4 }, e = { 120, 0, 6 } },
	L = { w = { 40, 0, 40 }, h = { 90, 0, 0 }, e = { 80, 10, 20 } },
	waist = { { 14, 50, 0 }, { -24, -14, 0 } },
	neck = { { 0, -30, 0 }, { 0, 10, 0 } },
	legs = "step",
	lift = -0.5,
	dip = -0.8,
})
C.reap = S({
	dur = 0.6,
	a = 0.35,
	c = 0.55,
	R = { w = { 140, 0, -40 }, h = { 60, 0, 80 }, f = { 40, 0, 90 }, e = { 40, 30, 50 } },
	L = { w = { 140, 0, -60 }, h = { 60, 0, 50 }, f = { 40, 0, 60 }, e = { 50, 40, 60 } },
	waist = { { 10, -50, 0 }, { -10, 50, 0 } },
	legs = "back",
})
C.grimSpin = S({
	dur = 0.75,
	a = 0.2,
	c = 0.6,
	f = 0.8,
	R = { w = { 60, 0, 90 }, h = { 60, 0, 90 }, e = { 20, 10, 10 } },
	L = { w = { 60, 0, 60 }, h = { 60, 0, 70 }, e = { 40, 20, 20 } },
	waist = { { 0, 0, 0 }, { -10, 0, 0 } },
	legs = "wide",
	spin = 360,
})
C.soulHook = S({
	dur = 0.7,
	a = 0.3,
	c = 0.5,
	R = { w = { 160, 0, 30 }, h = { 80, 0, 10 }, f = { 40, 0, 30 }, e = { 40, 10, 80 } },
	L = { w = { 160, 0, 10 }, h = { 80, 0, 20 }, f = { 40, 0, 40 }, e = { 60, 20, 90 } },
	waist = { { 20, 20, 0 }, { -24, -10, 0 }, { 20, 20, 0 } },
	legs = "back",
})
C.harvest = S({
	dur = 1.05,
	a = 0.35,
	c = 0.66,
	f = 0.85,
	R = { w = { 170, 0, 40 }, h = { 30, 0, 70 }, e = { 40, 20, 10 } },
	L = { w = { 170, 0, 20 }, h = { 30, 0, 40 }, e = { 50, 20, 10 } },
	waist = { { 24, 0, 0 }, { -30, 0, 0 } },
	legs = "squat",
	spin = 360,
	lift = 0.4,
})
C.staffSpin = S({
	dur = 0.7,
	a = 0.2,
	c = 0.5,
	f = 0.8,
	R = { w = { 90, 0, 30 }, h = { 100, 0, -40 }, f = { 90, 0, 40 }, e = { 60, 60, 60 }, wr = { 0, 0, 80 } },
	L = { w = { 90, 0, 30 }, h = { 100, 0, 40 }, f = { 90, 0, -40 }, e = { 60, 60, 60 } },
	waist = { { 0, 20, 0 }, { 0, -20, 0 }, { 0, 20, 0 } },
	legs = "wide",
})
C.staffOver = S({
	dur = 0.5,
	R = { w = { 176, 0, 20 }, h = { 60, 0, 6 }, e = { 50, 10, 10 } },
	L = { w = { 176, 0, 30 }, h = { 60, 0, 20 }, e = { 60, 20, 20 } },
	waist = { { 20, 0, 0 }, { -30, 0, 0 } },
	legs = "step",
})
C.dragonStaff = S({
	dur = 0.9,
	a = 0.3,
	c = 0.62,
	f = 0.82,
	R = { w = { 30, 0, 90 }, h = { 92, 0, 0 }, e = { 40, 0, 10 } },
	L = { w = { 30, 0, 60 }, h = { 86, 0, 20 }, e = { 60, 10, 20 } },
	waist = { { 0, 0, 0 }, { -24, -10, 0 } },
	legs = "step",
	spin = 360,
	dip = -0.6,
})
-- Dual wield
C.crossCut = S({
	dur = 0.42,
	R = { w = { 150, 0, 40 }, h = { 60, 0, -30 }, e = { 40, 4, 10 } },
	L = { w = { 150, 0, -40 }, h = { 60, 0, 30 }, e = { 40, 4, 10 } },
	waist = { { 16, 0, 0 }, { -20, 0, 0 } },
	legs = "step",
})
both(
	"rake",
	S({
		dur = 0.34,
		R = {
			w = { 150, 0, 30 },
			h = { 50, 0, -10 },
			f = { 30, 0, -20 },
			e = { 80, 10, 20 },
			wr = { 40, -40, 0 },
		},
		waist = { { 10, 20, 0 }, { -20, -20, 0 } },
	})
)
C.pounce = S({
	dur = 0.6,
	R = { w = { 30, 0, 30 }, h = { 140, 0, 20 }, f = { 60, 0, 10 }, e = { 90, 40, 20 }, wr = { 40, -40, 0 } },
	L = {
		w = { 30, 0, -30 },
		h = { 140, 0, -20 },
		f = { 60, 0, -10 },
		e = { 90, 40, 20 },
		wr = { 40, -40, 0 },
	},
	waist = { { 24, 0, 0 }, { -30, 0, 0 } },
	legs = "hop",
	lift = -0.8,
	dip = 1.0,
})
C.frenzy = S({
	dur = 0.75,
	a = 0.3,
	c = 0.5,
	R = { w = { 60, 0, 30 }, h = { 30, 0, 80 }, e = { 120, 100, 100 }, wr = { 40, -40, 0 } },
	L = { w = { 60, 0, -30 }, h = { 30, 0, -80 }, e = { 120, 100, 100 }, wr = { 40, -40, 0 } },
	waist = { { -30, 0, 0 }, { 20, 0, 0 } },
	neck = { { -20, 0, 0 }, { 40, 0, 0 } },
	legs = "wide",
})
C.saiCatch = S({
	dur = 0.6,
	R = { w = { 40, 0, 30 }, h = { 80, 0, -30 }, f = { 80, 0, -34 }, e = { 90, 90, 90 }, wr = { 0, 0, 80 } },
	L = { w = { 40, 0, -30 }, h = { 80, 0, 30 }, f = { 80, 0, 34 }, e = { 90, 90, 90 }, wr = { 0, 0, -80 } },
	waist = { { 0, 0, 0 }, { -6, 0, 0 } },
	legs = "back",
})
C.disarm = S({
	dur = 0.55,
	R = { w = { 84, 0, -40 }, h = { 60, 0, 60 }, e = { 70, 20, 20 }, wr = { 0, 0, 90 } },
	waist = { { 0, -30, 0 }, { -10, 30, 0 } },
	legs = "step",
	spin = 0,
})
C.twinToss = S({
	dur = 0.6,
	R = { w = { 160, 0, 40 }, h = { 70, 0, -10 }, e = { 80, 4, 20 } },
	L = { w = { 160, 0, -40 }, h = { 70, 0, 10 }, e = { 80, 4, 20 } },
	waist = { { 16, 0, 0 }, { -20, 0, 0 } },
	legs = "step",
})
C.pinStorm = S({
	dur = 0.8,
	a = 0.25,
	c = 0.6,
	f = 0.8,
	R = { w = { 120, 0, 70 }, h = { 60, 0, -20 }, e = { 80, 4, 10 } },
	L = { w = { 120, 0, -70 }, h = { 60, 0, 20 }, e = { 80, 4, 10 } },
	waist = { { 10, 0, 0 }, { -24, 0, 0 } },
	legs = "hop",
	dip = 1.2,
	spin = 360,
})
both(
	"tonfaJab",
	S({
		dur = 0.3,
		R = { w = { 50, 0, 20 }, h = { 92, 0, -4 }, e = { 120, 60, 70 } },
		legs = "step",
		dip = -0.3,
	})
)
C.tonfaGuard = S({
	dur = 0.6,
	R = { w = { 30, 0, 30 }, h = { 84, 0, -20 }, f = { 84, 0, -20 }, e = { 90, 100, 100 } },
	L = { w = { 30, 0, -30 }, h = { 84, 0, 20 }, f = { 84, 0, 20 }, e = { 90, 100, 100 } },
	waist = { { 0, 0, 0 }, { -10, 0, 0 } },
	legs = "wide",
})
C.twinHammer = S({
	dur = 0.65,
	a = 0.4,
	c = 0.58,
	R = { w = { 178, 0, 20 }, h = { 50, 0, 10 }, e = { 60, 40, 40 } },
	L = { w = { 178, 0, -20 }, h = { 50, 0, -10 }, e = { 60, 40, 40 } },
	waist = { { 24, 0, 0 }, { -40, 0, 0 } },
	legs = "kneel",
	lift = 0.4,
})
both(
	"chuck",
	S({
		dur = 0.32,
		R = {
			w = { 140, 0, 60 },
			h = { 70, 0, -30 },
			f = { 50, 0, -40 },
			e = { 60, 10, 20 },
			wr = { 0, 70, 0 },
		},
		waist = { { 6, 30, 0 }, { -10, -30, 0 } },
	})
)
C.chuckOver = S({
	dur = 0.4,
	R = { w = { 178, 0, 10 }, h = { 50, 0, 4 }, e = { 30, 4, 10 }, wr = { 0, 80, 0 } },
	waist = { { 16, 0, 0 }, { -24, 0, 0 } },
	legs = "step",
})
C.juggle = S({
	dur = 0.6,
	R = { w = { 20, 0, 30 }, h = { 170, 0, 20 }, f = { 120, 0, 40 }, e = { 70, 10, 20 }, wr = { 0, 80, 0 } },
	waist = { { 20, 20, 0 }, { -6, -10, 0 } },
	neck = { { -10, 0, 0 }, { 40, 0, 0 } },
	legs = "rise",
})
C.whirlChain = S({
	dur = 0.75,
	a = 0.15,
	c = 0.5,
	f = 0.8,
	R = { w = { 160, 0, 30 }, h = { 170, 0, 20 }, f = { 160, 0, 30 }, e = { 20, 10, 20 }, wr = { 0, 80, 0 } },
	waist = { { 0, 0, 0 }, { -6, 0, 0 } },
	legs = "wide",
	spin = 360,
})
-- Shields
both(
	"shieldBash",
	S({
		dur = 0.36,
		L = { w = { 40, 0, 20 }, h = { 88, 0, 10 }, f = { 86, 0, 10 }, e = { 120, 60, 70 } },
		waist = { { 4, -20, 0 }, { -14, 22, 0 } },
		legs = "stepL",
	})
)
C.shieldOver = S({
	dur = 0.55,
	L = { w = { 170, 0, 10 }, h = { 60, 0, 10 }, e = { 90, 80, 80 } },
	waist = { { 20, 0, 0 }, { -30, 0, 0 } },
	legs = "kneelL",
	lift = 0.3,
})
C.shove = S({
	dur = 0.45,
	R = { w = { 40, 0, 30 }, h = { 88, 0, 10 }, e = { 120, 50, 50 } },
	L = { w = { 40, 0, -10 }, h = { 88, 0, 20 }, e = { 120, 80, 80 } },
	waist = { { 10, 0, 0 }, { -24, 0, 0 } },
	legs = "step",
	dip = -0.5,
})
C.shieldUp = S({
	dur = 0.6,
	L = { w = { 30, 0, -20 }, h = { 84, 0, 20 }, f = { 84, 0, 20 }, e = { 80, 90, 90 } },
	waist = { { 0, 0, 0 }, { -10, 10, 0 } },
	legs = "wide",
})
C.shieldCharge = S({
	dur = 0.6,
	L = { w = { 60, 0, 10 }, h = { 88, 0, 20 }, e = { 110, 90, 90 } },
	waist = { { 10, -20, 0 }, { -34, 20, 0 } },
	legs = "step",
	dip = -0.6,
})
C.shieldThrow = S({
	dur = 0.6,
	L = { w = { 60, 0, 80 }, h = { 80, 0, -50 }, f = { 70, 0, -70 }, e = { 120, 10, 20 } },
	waist = { { 6, -50, 0 }, { -14, 40, 0 } },
	legs = "stepL",
})
C.bulwarkSlam = S({
	dur = 0.8,
	a = 0.35,
	c = 0.6,
	L = { w = { 170, 0, 10 }, h = { 40, 0, 10 }, e = { 90, 80, 80 } },
	R = { w = { 170, 0, 10 }, h = { 40, 0, 10 }, e = { 70, 40, 40 } },
	waist = { { 24, 0, 0 }, { -44, 0, 0 } },
	legs = "kneel",
	lift = 1.0,
})
C.coverAllies = S({
	dur = 0.75,
	L = { w = { 30, 0, -40 }, h = { 84, 0, 50 }, f = { 84, 0, 54 }, e = { 90, 80, 80 } },
	R = { w = { 30, 0, 30 }, h = { 30, 0, 90 }, f = { 30, 0, 94 }, e = { 40, 10, 10 } },
	waist = { { 0, -20, 0 }, { -6, 20, 0 } },
	legs = "wide",
})
-- Ranged
both(
	"shot",
	S({
		dur = 0.3,
		a = 0.15,
		c = 0.3,
		R = { w = { 86, 0, 0 }, h = { 92, 0, 0 }, f = { 104, 0, 0 }, e = { 6, 2, 10 } },
		L = { w = { 80, 0, 30 }, h = { 82, 0, 30 }, e = { 40, 40, 40 } },
		waist = { { 0, -10, 0 }, { 4, -14, 0 } },
		neck = { { 0, 8, 0 }, { 0, 10, 0 } },
		legs = "set",
	})
)
C.hipShot = S({
	dur = 0.3,
	a = 0.15,
	c = 0.3,
	R = { w = { 50, 0, 10 }, h = { 70, 0, 4 }, f = { 84, 0, 4 }, e = { 40, 30, 40 } },
	waist = { { 0, 6, 0 }, { -4, -10, 0 } },
	legs = "set",
})
C.chargeShot = S({
	dur = 0.75,
	a = 0.6,
	c = 0.66,
	R = { w = { 92, 0, 0 }, h = { 94, 0, 0 }, f = { 120, 0, 0 }, e = { 4, 2, 20 } },
	L = { w = { 84, 0, 30 }, h = { 84, 0, 30 }, f = { 100, 0, 30 }, e = { 40, 40, 50 } },
	waist = { { 0, -14, 0 }, { 14, -14, 0 } },
	legs = "back",
	dip = -0.4,
})
C.spreadShot = S({
	dur = 0.45,
	R = { w = { 92, 0, 40 }, h = { 92, 0, -20 }, e = { 4, 4, 10 } },
	L = { w = { 80, 0, 30 }, h = { 80, 0, 0 }, e = { 40, 40, 40 } },
	waist = { { 0, 30, 0 }, { -4, -30, 0 } },
	legs = "wide",
})
C.spinVolley = S({
	dur = 0.75,
	a = 0.15,
	c = 0.5,
	f = 0.8,
	R = { w = { 30, 0, 90 }, h = { 30, 0, 90 }, e = { 4, 4, 4 } },
	L = { w = { 30, 0, -90 }, h = { 30, 0, -90 }, e = { 4, 4, 4 } },
	waist = { { 0, 0, 0 }, { -6, 0, 0 } },
	legs = "wide",
	spin = 360,
})
C.runGun = S({
	dur = 0.55,
	R = { w = { 86, 0, 10 }, h = { 92, 0, -10 }, e = { 4, 4, 10 } },
	L = { w = { 86, 0, -10 }, h = { 92, 0, 10 }, e = { 4, 4, 10 } },
	waist = { { -14, 0, 0 }, { -20, 0, 0 } },
	legs = "step",
})
C.crossfire = S({
	dur = 0.5,
	R = { w = { 92, 0, -30 }, h = { 92, 0, -40 }, f = { 104, 0, -40 }, e = { 4, 2, 10 } },
	L = { w = { 92, 0, 30 }, h = { 92, 0, 40 }, f = { 104, 0, 40 }, e = { 4, 2, 10 } },
	legs = "wide",
})
C.bulletStorm = S({
	dur = 0.95,
	a = 0.2,
	c = 0.55,
	f = 0.85,
	R = { w = { 92, 0, 40 }, h = { 120, 0, 60 }, e = { 4, 4, 4 } },
	L = { w = { 92, 0, -40 }, h = { 120, 0, -60 }, e = { 4, 4, 4 } },
	waist = { { 0, 0, 0 }, { 20, 0, 0 } },
	legs = "hop",
	dip = 1.2,
	spin = 360,
})
C.rifleShot = S({
	dur = 0.4,
	a = 0.2,
	c = 0.28,
	R = { w = { 88, 0, -4 }, h = { 92, 0, -4 }, f = { 106, 0, -4 }, e = { 20, 14, 30 } },
	L = { w = { 90, 0, 26 }, h = { 92, 0, 26 }, f = { 104, 0, 26 }, e = { 40, 30, 40 } },
	waist = { { 0, -16, 0 }, { 6, -16, 0 } },
	neck = { { 0, 16, 10 }, { 0, 16, 10 } },
	legs = "back",
})
C.rifleCycle = S({
	dur = 0.45,
	a = 0.2,
	c = 0.5,
	R = { w = { 92, 0, -4 }, h = { 70, 0, 30 }, f = { 86, 0, 0 }, e = { 20, 90, 30 } },
	L = { w = { 90, 0, 26 }, h = { 90, 0, 26 }, e = { 40, 40, 40 } },
	waist = { { 4, -16, 0 }, { 0, -10, 0 } },
	legs = "set",
})
C.railshot = S({
	dur = 1.0,
	a = 0.6,
	c = 0.68,
	R = { w = { 92, 0, -4 }, h = { 94, 0, -4 }, f = { 130, 0, -4 }, e = { 20, 14, 40 } },
	L = { w = { 92, 0, 26 }, h = { 92, 0, 26 }, f = { 120, 0, 26 }, e = { 40, 30, 50 } },
	waist = { { 0, -16, 0 }, { 20, -16, 0 } },
	legs = "back",
	dip = -0.6,
})
C.bowDraw = S({
	dur = 0.5,
	a = 0.6,
	c = 0.7,
	L = { w = { 90, 0, -6 }, h = { 90, 0, -6 }, f = { 92, 0, -6 }, e = { 2, 2, 2 } },
	R = { w = { 90, 0, -16 }, h = { 90, 0, 24 }, f = { 80, 0, 30 }, e = { 140, 20, 30 } },
	waist = { { 0, 50, 0 }, { 0, 46, 0 } },
	neck = { { 0, -46, 0 }, { 0, -44, 0 } },
	legs = "wide",
})
C.powerDraw = S({
	dur = 0.9,
	a = 0.7,
	c = 0.78,
	L = { w = { 96, 0, -6 }, h = { 96, 0, -6 }, f = { 100, 0, -6 }, e = { 2, 2, 2 } },
	R = { w = { 96, 0, -20 }, h = { 96, 0, 30 }, f = { 86, 0, 40 }, e = { 150, 20, 30 } },
	waist = { { 10, 54, 0 }, { -6, 46, 0 } },
	neck = { { 0, -50, 0 }, { 0, -44, 0 } },
	legs = "wide",
	dip = -0.8,
})
C.splitArrow = S({
	dur = 0.55,
	a = 0.55,
	c = 0.66,
	L = { w = { 90, 0, -6 }, h = { 90, 0, 30 }, f = { 90, 0, -30 }, e = { 2, 2, 2 } },
	R = { w = { 90, 0, -16 }, h = { 90, 0, 24 }, e = { 140, 20, 30 } },
	waist = { { 0, 50, 0 }, { 0, 30, 0 }, { 0, 60, 0 } },
	neck = { { 0, -46, 0 }, { 0, -30, 0 } },
	legs = "wide",
})
C.arrowRain = S({
	dur = 0.8,
	a = 0.55,
	c = 0.66,
	L = { w = { 150, 0, -6 }, h = { 150, 0, -6 }, f = { 150, 0, -6 }, e = { 2, 2, 2 } },
	R = { w = { 150, 0, -20 }, h = { 140, 0, 30 }, e = { 140, 20, 30 } },
	waist = { { 20, 40, 0 }, { 24, 40, 0 } },
	neck = { { 30, -30, 0 }, { 40, -30, 0 } },
	legs = "wide",
})
C.crossShot = S({
	dur = 0.38,
	a = 0.2,
	c = 0.28,
	R = { w = { 90, 0, -6 }, h = { 92, 0, -6 }, f = { 110, 0, -6 }, e = { 20, 20, 30 } },
	L = { w = { 90, 0, 26 }, h = { 92, 0, 26 }, f = { 106, 0, 26 }, e = { 40, 40, 50 } },
	waist = { { 0, -14, 0 }, { 10, -14, 0 } },
	legs = "back",
})
C.crossReload = S({
	dur = 0.5,
	a = 0.3,
	c = 0.6,
	R = { w = { 40, 0, 10 }, h = { 60, 0, 30 }, f = { 50, 0, 20 }, e = { 90, 120, 90 } },
	L = { w = { 60, 0, 30 }, h = { 40, 0, 20 }, e = { 50, 60, 50 } },
	waist = { { -10, 0, 0 }, { -16, 0, 0 } },
	legs = "set",
})
C.cannonShot = S({
	dur = 0.5,
	a = 0.2,
	c = 0.3,
	R = { w = { 88, 0, 0 }, h = { 92, 0, 0 }, f = { 120, 0, 0 }, e = { 4, 2, 30 } },
	L = { w = { 60, 0, 30 }, h = { 60, 0, 40 }, f = { 50, 0, 40 }, e = { 90, 90, 90 } },
	waist = { { 0, -6, 0 }, { 16, -6, 0 } },
	legs = "back",
	dip = -0.5,
})
C.cannonBrace = S({
	dur = 0.75,
	a = 0.45,
	c = 0.55,
	R = { w = { 92, 0, 0 }, h = { 92, 0, 0 }, f = { 130, 0, 0 }, e = { 4, 2, 40 } },
	L = { w = { 80, 0, 20 }, h = { 80, 0, 20 }, f = { 80, 0, 20 }, e = { 80, 80, 80 } },
	waist = { { -10, 0, 0 }, { 24, 0, 0 } },
	legs = "wide",
	dip = -0.8,
})
C.cannonGround = S({
	dur = 0.7,
	R = { w = { 140, 0, 20 }, h = { 20, 0, 10 }, e = { 20, 0, 0 } },
	waist = { { 20, 0, 0 }, { -40, 0, 0 } },
	legs = "kneel",
	lift = 0.6,
})
C.megaBeam = S({
	dur = 1.1,
	a = 0.5,
	c = 0.6,
	f = 0.9,
	R = { w = { 60, 0, 30 }, h = { 92, 0, 0 }, f = { 96, 0, 0 }, e = { 90, 0, 0 } },
	L = { w = { 60, 0, -30 }, h = { 84, 0, 20 }, f = { 84, 0, 20 }, e = { 90, 40, 40 } },
	waist = { { -14, 30, 0 }, { 16, -10, 0 } },
	legs = "wide",
	dip = -0.9,
})
both(
	"starToss",
	S({
		dur = 0.3,
		R = {
			w = { 60, 0, -50 },
			h = { 86, 0, 40 },
			f = { 80, 0, 60 },
			e = { 100, 4, 6 },
			wr = { 0, -60, 40 },
		},
		waist = { { 4, -24, 0 }, { -8, 20, 0 } },
	})
)
C.sideThrow = S({
	dur = 0.4,
	R = { w = { 30, 0, 110 }, h = { 70, 0, -10 }, e = { 40, 4, 20 }, wr = { 0, 60, 0 } },
	waist = { { 0, 50, 0 }, { -10, -30, 0 } },
	legs = "step",
})
C.fanThrow = S({
	dur = 0.55,
	R = { w = { 70, 0, -60 }, h = { 84, 0, 70 }, f = { 80, 0, 90 }, e = { 110, 4, 6 }, wr = { 0, -60, 40 } },
	L = { w = { 70, 0, 60 }, h = { 84, 0, -70 }, f = { 80, 0, -90 }, e = { 110, 4, 6 }, wr = { 0, -60, 40 } },
	waist = { { 10, 0, 0 }, { -10, 0, 0 } },
	legs = "step",
})
C.starStorm = S({
	dur = 0.9,
	a = 0.2,
	c = 0.55,
	f = 0.82,
	R = { w = { 60, 0, -50 }, h = { 84, 0, 60 }, e = { 100, 4, 6 } },
	L = { w = { 60, 0, 50 }, h = { 84, 0, -60 }, e = { 100, 4, 6 } },
	waist = { { 0, 0, 0 }, { -10, 0, 0 } },
	legs = "hop",
	dip = 1.6,
	spin = 360,
})
C.rangCatch = S({
	dur = 0.5,
	a = 0.3,
	c = 0.6,
	R = { w = { 90, 0, 40 }, h = { 100, 0, 30 }, f = { 40, 0, 20 }, e = { 10, 60, 90 } },
	waist = { { -6, 10, 0 }, { 8, 20, 0 } },
	neck = { { 10, 0, 0 }, { 10, 0, 0 } },
	legs = "back",
})
-- Exotic: whips, fans, yo-yos, rope darts (TetherFx swings their lines along these arm paths)
both(
	"whipLash",
	S({
		dur = 0.48,
		a = 0.38,
		c = 0.52,
		R = {
			w = { 170, 0, 50 },
			h = { 70, 0, -10 },
			f = { 30, 0, -20 },
			e = { 90, 4, 30 },
			wr = { 0, -50, 10 },
		},
		waist = { { 10, 40, 0 }, { -14, -30, 0 } },
		legs = "step",
	})
)
C.whipSide = S({
	dur = 0.5,
	R = { w = { 60, 0, 120 }, h = { 70, 0, -40 }, f = { 60, 0, -60 }, e = { 40, 4, 20 }, wr = { 0, 50, 0 } },
	waist = { { 4, 60, 0 }, { -10, -50, 0 } },
	legs = "wide",
})
C.whipCrack = S({
	dur = 0.6,
	a = 0.45,
	c = 0.58,
	R = {
		w = { 178, 0, 10 },
		h = { 60, 0, 4 },
		f = { 120, 0, 10 },
		e = { 120, 4, 60 },
		wr = { -40, -60, 20 },
	},
	waist = { { 24, 10, 0 }, { -20, -10, 0 } },
	legs = "step",
})
C.whipPull = S({
	dur = 0.6,
	a = 0.25,
	c = 0.4,
	f = 0.75,
	R = { w = { 150, 0, 30 }, h = { 90, 0, 0 }, f = { 30, 0, 40 }, e = { 60, 4, 110 }, wr = { 0, -40, -50 } },
	waist = { { 10, 20, 0 }, { -10, -14, 0 }, { 16, 30, 0 } },
	legs = "back",
})
C.whipCyclone = S({
	dur = 0.85,
	a = 0.2,
	c = 0.55,
	f = 0.82,
	R = { w = { 170, 0, 30 }, h = { 160, 0, 40 }, e = { 20, 10, 20 } },
	waist = { { 0, 0, 0 }, { -10, 0, 0 } },
	neck = { { 20, 0, 0 }, { 10, 0, 0 } },
	legs = "wide",
	spin = 360,
})
both(
	"fanCut",
	S({
		dur = 0.36,
		R = {
			w = { 120, 0, -40 },
			h = { 80, 0, 80 },
			f = { 70, 0, 96 },
			e = { 70, 6, 10 },
			wr = { 0, -60, 60 },
		},
		waist = { { 6, -30, 0 }, { -10, 34, 0 } },
		legs = "step",
	})
)
C.fanSpin = S({
	dur = 0.55,
	a = 0.2,
	c = 0.55,
	R = { w = { 60, 0, 90 }, h = { 60, 0, 90 }, e = { 10, 10, 10 }, wr = { 0, 0, 60 } },
	L = { w = { 40, 0, -60 }, h = { 40, 0, -80 }, e = { 50, 30, 30 } },
	legs = "rise",
	spin = 360,
})
C.gust = S({
	dur = 0.6,
	a = 0.4,
	c = 0.52,
	R = { w = { 160, 0, -30 }, h = { 60, 0, 60 }, f = { 40, 0, 80 }, e = { 40, 4, 10 }, wr = { 0, -70, 80 } },
	waist = { { 16, -40, 0 }, { -16, 40, 0 } },
	legs = "step",
})
C.fanGlide = S({
	dur = 0.65,
	R = { w = { 40, 0, 40 }, h = { 160, 0, 20 }, e = { 50, 10, 10 }, wr = { 0, 0, 80 } },
	L = { w = { 40, 0, -40 }, h = { 10, 0, -80 }, e = { 50, 10, 10 } },
	waist = { { -10, 0, 0 }, { 8, 0, 0 } },
	legs = "hop",
	dip = 1.0,
})
C.typhoon = S({
	dur = 1.05,
	a = 0.25,
	c = 0.6,
	f = 0.85,
	R = { w = { 120, 0, 60 }, h = { 170, 0, 20 }, e = { 30, 10, 10 }, wr = { 0, 0, 80 } },
	L = { w = { 120, 0, -60 }, h = { 60, 0, -100 }, e = { 30, 10, 10 } },
	waist = { { 0, 0, 0 }, { 10, 0, 0 } },
	neck = { { 0, 0, 0 }, { 30, 0, 0 } },
	legs = "rise",
	spin = 360,
})
C.yoyoThrow = S({
	dur = 0.44,
	R = { w = { 50, 0, 20 }, h = { 92, 0, 4 }, f = { 60, 0, 14 }, e = { 120, 4, 90 }, wr = { -50, 30, -40 } },
	waist = { { 4, 20, 0 }, { -10, -20, 0 } },
	legs = "step",
})
C.yoyoSide = S({
	dur = 0.44,
	R = { w = { 40, 0, -40 }, h = { 70, 0, 90 }, f = { 50, 0, 60 }, e = { 110, 4, 70 }, wr = { 0, 40, 0 } },
	waist = { { 4, -30, 0 }, { -6, 30, 0 } },
	legs = "set",
})
C.yoyoUp = S({
	dur = 0.44,
	R = {
		w = { 10, 0, 20 },
		h = { 160, 0, 10 },
		f = { 100, 0, 10 },
		e = { 120, 10, 90 },
		wr = { -50, 40, -40 },
	},
	waist = { { 10, 10, 0 }, { -6, -10, 0 } },
	neck = { { -6, 0, 0 }, { 30, 0, 0 } },
	legs = "rise",
})
C.yoyoBack = S({
	dur = 0.5,
	R = { w = { 160, 0, 30 }, h = { 50, 0, 10 }, f = { 10, 0, 20 }, e = { 70, 4, 60 }, wr = { -50, 40, 0 } },
	waist = { { 16, 20, 0 }, { -20, -10, 0 } },
	legs = "step",
})
C.walkDog = S({
	dur = 0.6,
	R = { w = { 50, 0, 20 }, h = { 30, 0, 10 }, f = { 50, 0, 14 }, e = { 120, 10, 60 }, wr = { -40, 40, 0 } },
	waist = { { 0, 10, 0 }, { -30, 0, 0 } },
	legs = "step",
	dip = -0.6,
})
C.aroundWorld = S({
	dur = 0.75,
	a = 0.15,
	c = 0.5,
	f = 0.85,
	R = { w = { 60, 0, 90 }, h = { 170, 0, 30 }, f = { 60, 0, 90 }, e = { 10, 10, 10 } },
	waist = { { -6, 20, 0 }, { 10, -10, 0 }, { -6, 20, 0 } },
	legs = "wide",
})
C.tetherSnag = S({
	dur = 0.6,
	a = 0.25,
	c = 0.4,
	f = 0.75,
	R = { w = { 60, 0, 20 }, h = { 94, 0, 0 }, f = { 40, 0, 30 }, e = { 100, 4, 110 }, wr = { -40, 40, -40 } },
	waist = { { 4, 20, 0 }, { -8, -20, 0 }, { 14, 30, 0 } },
	legs = "back",
})
C.cradle = S({
	dur = 0.9,
	a = 0.35,
	c = 0.6,
	R = { w = { 70, 0, -20 }, h = { 84, 0, 40 }, f = { 84, 0, 44 }, e = { 100, 80, 80 } },
	L = { w = { 70, 0, 20 }, h = { 84, 0, -40 }, f = { 84, 0, -44 }, e = { 100, 80, 80 } },
	waist = { { 0, 0, 0 }, { -8, 0, 0 } },
	neck = { { -10, 0, 0 }, { 0, 0, 0 } },
	legs = "wide",
})
C.dartSpin = S({
	dur = 0.5,
	a = 0.2,
	c = 0.5,
	R = { w = { 120, 0, 60 }, h = { 150, 0, 40 }, f = { 90, 0, 20 }, e = { 40, 10, 20 } },
	waist = { { 0, 30, 0 }, { -6, -30, 0 } },
	legs = "set",
	spin = 360,
})
C.dartThrow = S({
	dur = 0.44,
	R = { w = { 160, 0, 30 }, h = { 86, 0, 0 }, f = { 70, 0, 10 }, e = { 80, 2, 20 } },
	waist = { { 10, 30, 0 }, { -14, -20, 0 } },
	legs = "step",
})
C.dartKick = S({
	dur = 0.5,
	R = { w = { 60, 0, 60 }, h = { 30, 0, 60 }, e = { 60, 40, 40 } },
	L = { w = { 40, 0, -30 }, h = { 60, 0, -40 }, e = { 90, 80, 80 } },
	waist = { { 6, 20, 0 }, { 14, -30, 0 } },
	legs = "kick",
})
C.dartWrap = S({
	dur = 0.65,
	a = 0.3,
	c = 0.45,
	f = 0.8,
	R = { w = { 150, 0, 30 }, h = { 92, 0, 0 }, f = { 30, 0, -40 }, e = { 60, 4, 110 } },
	L = { w = { 40, 0, -20 }, h = { 80, 0, -20 }, f = { 40, 0, 30 }, e = { 80, 20, 110 } },
	waist = { { 10, 20, 0 }, { -10, -10, 0 }, { 16, 40, 0 } },
	legs = "back",
})
C.dartSnap = S({
	dur = 0.55,
	a = 0.4,
	c = 0.52,
	R = { w = { 40, 0, 20 }, h = { 94, 0, 0 }, f = { 104, 0, 0 }, e = { 120, 0, 20 } },
	waist = { { 0, 40, 0 }, { -16, -20, 0 } },
	legs = "step",
	dip = -0.6,
})
C.serpent = S({
	dur = 0.95,
	a = 0.2,
	c = 0.6,
	f = 0.85,
	R = { w = { 150, 0, 60 }, h = { 92, 0, 0 }, e = { 30, 0, 20 } },
	L = { w = { 40, 0, -40 }, h = { 30, 0, -70 }, e = { 70, 30, 30 } },
	waist = { { 0, 0, 0 }, { -14, -10, 0 } },
	legs = "hop",
	dip = 1.0,
	spin = 360,
})

---------------------------------------------------------------------------
-- Every button: block, carry, revive, interact, catch, gadgets, Awakening, hit reactions, windups
---------------------------------------------------------------------------
C.guard = { -- Block, held: forearms crossed high in front of the face, chin down, knees bent
	dur = 1.2,
	loop = true,
	joints = {
		RightShoulder = { K(0, 84, 0, -26), K(0.6, 86, 0, -24), K(1.2, 84, 0, -26) },
		LeftShoulder = { K(0, 84, 0, 26), K(0.6, 86, 0, 24), K(1.2, 84, 0, 26) },
		RightElbow = hold(110),
		LeftElbow = hold(110),
		Waist = hold(-12),
		Neck = hold(-12),
		RightHip = hold(-10, 0, 10),
		LeftHip = hold(26, 0, -10),
		RightKnee = hold(-26),
		LeftKnee = hold(-40),
		Root = { K(0, 0, 0, 0, -0.4), K(0.6, 0, 0, 0, -0.45), K(1.2, 0, 0, 0, -0.4) },
	},
}
C.guardShield = { -- Block with a shield: the shield arm squared in front, the weapon arm cocked behind it
	dur = 1.2,
	loop = true,
	joints = {
		LeftShoulder = { K(0, 60, 0, 30), K(0.6, 62, 0, 30), K(1.2, 60, 0, 30) },
		LeftElbow = hold(110),
		RightShoulder = hold(40, 0, 10),
		RightElbow = hold(90),
		Waist = hold(-14, -16),
		Neck = hold(-8, 14),
		RightHip = hold(-16, 0, 10),
		LeftHip = hold(30, 0, -10),
		RightKnee = hold(-30),
		LeftKnee = hold(-50),
		Root = hold(0, 0, 0, -0.55),
	},
}
C.blockHit = S({ -- a hit lands on the guard: the arms jolt back, the feet slide
	dur = 0.3,
	a = 0.1,
	c = 0.3,
	f = 0.6,
	R = { w = { 84, 0, -26 }, h = { 100, 0, -20 }, f = { 90, 0, -24 }, e = { 110, 130, 116 } },
	L = { w = { 84, 0, 26 }, h = { 100, 0, 20 }, f = { 90, 0, 24 }, e = { 110, 130, 116 } },
	waist = { { -12, 0, 0 }, { 10, 0, 0 }, { -6, 0, 0 } },
	legs = "back",
})
C.parry = S({ -- a perfect block: the guard snaps outward and knocks the blow aside
	dur = 0.45,
	a = 0.15,
	c = 0.35,
	R = { w = { 84, 0, -26 }, h = { 100, 0, 70 }, f = { 90, 0, 80 }, e = { 110, 20, 30 } },
	L = { w = { 84, 0, 26 }, h = { 60, 0, -30 }, e = { 110, 90, 90 } },
	waist = { { -10, 10, 0 }, { -6, -40, 0 } },
	legs = "step",
})
C.guardBreak = S({ -- SHATTER: the guard is knocked open, the hero reels back, arms flung wide
	dur = 0.8,
	a = 0.1,
	c = 0.3,
	f = 0.65,
	R = { w = { 84, 0, -26 }, h = { 40, 0, 90 }, f = { 20, 0, 70 }, e = { 110, 10, 30 } },
	L = { w = { 84, 0, 26 }, h = { 40, 0, -90 }, f = { 20, 0, -70 }, e = { 110, 10, 30 } },
	waist = { { -10, 0, 0 }, { 30, 0, 0 }, { 20, 0, 0 } },
	neck = { { 0, 0, 0 }, { 30, 0, 0 }, { 10, 0, 0 } },
	legs = "back",
	dip = -0.4,
})
C.interrupted = S({ -- a charge or wind-up cut off: the energy fizzles, the hero stumbles
	dur = 0.55,
	a = 0.1,
	c = 0.3,
	R = { w = { 60, 0, 30 }, h = { 20, 0, 60 }, e = { 90, 40, 50 } },
	L = { w = { 60, 0, -30 }, h = { 20, 0, -50 }, e = { 90, 40, 50 } },
	waist = { { 0, 0, 0 }, { 24, 10, 0 }, { 10, 0, 0 } },
	neck = { { 0, 0, 0 }, { 20, 20, 0 } },
	legs = "back",
})
C.carry = { -- carrying a robot, a car or a prop over the head (the Carrying attribute): both arms straight up, the
	-- fists just over the head so the thing rests on them (fix-carry, Shared.CarryPose welds it there); a slow bob
	dur = 1.0,
	loop = true,
	joints = {
		RightShoulder = { K(0, 172, 0, 12), K(0.5, 169, 0, 13), K(1, 172, 0, 12) },
		LeftShoulder = { K(0, 172, 0, -12), K(0.5, 169, 0, -13), K(1, 172, 0, -12) },
		RightElbow = { K(0, 8), K(0.5, 12), K(1, 8) },
		LeftElbow = { K(0, 8), K(0.5, 12), K(1, 8) },
		RightWrist = hold(0),
		LeftWrist = hold(0),
		Waist = { K(0, 6), K(0.5, 8), K(1, 6) },
		Neck = hold(-6),
	},
}
C.carryHand = { -- a small thing up on the right fist (CarryGrip "hand" or "pole"), the free arm out for balance
	dur = 1.0,
	loop = true,
	joints = {
		RightShoulder = { K(0, 166, 0, 14), K(0.5, 163, 0, 15), K(1, 166, 0, 14) },
		RightElbow = { K(0, 20), K(0.5, 24), K(1, 20) },
		RightWrist = hold(0),
		LeftShoulder = { K(0, 24, 0, -24), K(0.5, 28, 0, -26), K(1, 24, 0, -24) },
		LeftElbow = hold(36),
		Waist = { K(0, 4, -6, -4), K(0.5, 6, -6, -4), K(1, 4, -6, -4) },
		Neck = hold(8, 6),
	},
}
C.carryMind = { -- telekinesis (CarryGrip "mind"): both hands raised to the floating thing, fingers spread, swaying
	dur = 2.0,
	loop = true,
	joints = {
		RightShoulder = { K(0, 150, 0, 26), K(1, 156, 0, 22), K(2, 150, 0, 26) },
		LeftShoulder = { K(0, 150, 0, -26), K(1, 144, 0, -30), K(2, 150, 0, -26) },
		RightElbow = { K(0, 18), K(1, 26), K(2, 18) },
		LeftElbow = { K(0, 26), K(1, 18), K(2, 26) },
		RightWrist = hold(-50),
		LeftWrist = hold(-50),
		Waist = { K(0, 6), K(1, 9), K(2, 6) },
		Neck = hold(16),
	},
}
C.lift = S({ -- picking it up: squat, both hands under it, drive up with the legs
	dur = 0.6,
	a = 0.3,
	c = 0.7,
	f = 0.85,
	R = { w = { 40, 0, 20 }, h = { 168, 0, 20 }, f = { 168, 0, 20 }, e = { 20, 40, 40 } },
	L = { w = { 40, 0, -20 }, h = { 168, 0, -20 }, f = { 168, 0, -20 }, e = { 20, 40, 40 } },
	waist = { { -40, 0, 0 }, { 8, 0, 0 } },
	legs = "squat",
	dip = 0.1,
	lift = -1.1,
})
C.catch = S({ -- B: reach out with both hands and pull it in to the chest
	dur = 0.5,
	a = 0.35,
	c = 0.6,
	R = {
		w = { 96, 0, 30 },
		h = { 60, 0, -10 },
		f = { 50, 0, -14 },
		e = { 10, 100, 110 },
		wr = { -30, 0, 0 },
	},
	L = { w = { 96, 0, -30 }, h = { 60, 0, 10 }, f = { 50, 0, 14 }, e = { 10, 100, 110 }, wr = { -30, 0, 0 } },
	waist = { { -14, 0, 0 }, { 8, 0, 0 } },
	legs = "back",
})
C.interact = S({ -- a terminal, a door, a prompt: reach out and press it
	dur = 0.5,
	a = 0.3,
	c = 0.5,
	R = { w = { 50, 0, 20 }, h = { 86, 0, 4 }, f = { 84, 0, 4 }, e = { 90, 20, 30 }, wr = { -20, 30, 0 } },
	waist = { { 0, 10, 0 }, { -10, -10, 0 } },
	neck = { { -6, 0, 0 }, { -10, 0, 0 } },
	legs = "step",
	dip = -0.1,
})
C.interactHold = { -- holding a prompt (a hacking terminal, a slow door): both hands working at it
	dur = 0.8,
	loop = true,
	joints = {
		RightShoulder = { K(0, 80, 0, 6), K(0.2, 76, 0, 10), K(0.4, 82, 0, 4), K(0.8, 80, 0, 6) },
		LeftShoulder = { K(0, 76, 0, -6), K(0.4, 82, 0, -10), K(0.6, 74, 0, -4), K(0.8, 76, 0, -6) },
		RightElbow = { K(0, 40), K(0.2, 54), K(0.4, 36), K(0.8, 40) },
		LeftElbow = { K(0, 50), K(0.4, 36), K(0.6, 56), K(0.8, 50) },
		Waist = hold(-12),
		Neck = hold(-14),
	},
}
C.revive = { -- reviving a Downed ally: kneeling beside them, both hands pumping on their chest
	dur = 0.9,
	loop = true,
	joints = {
		Root = { K(0, 0, 0, 0, -1.0), K(0.45, 0, 0, 0, -1.1), K(0.9, 0, 0, 0, -1.0) },
		RightHip = hold(86),
		RightKnee = hold(-92),
		LeftHip = hold(-4),
		LeftKnee = hold(-100),
		LeftAnkle = hold(-50),
		Waist = { K(0, -34), K(0.45, -44), K(0.9, -34) },
		Neck = hold(-10),
		RightShoulder = { K(0, 60, 0, 6), K(0.45, 44, 0, 6), K(0.9, 60, 0, 6) },
		LeftShoulder = { K(0, 60, 0, -6), K(0.45, 44, 0, -6), K(0.9, 60, 0, -6) },
		RightElbow = hold(10),
		LeftElbow = hold(10),
	},
}
C.giveUp = { -- Give Up: the kneel slumps over, head down, hands on the ground
	dur = 2.4,
	loop = true,
	joints = {
		Root = hold(0, 0, 0, -1.2),
		RightHip = hold(96),
		RightKnee = hold(-110),
		LeftHip = hold(96),
		LeftKnee = hold(-110),
		RightAnkle = hold(-40),
		LeftAnkle = hold(-40),
		Waist = { K(0, -40), K(1.2, -44), K(2.4, -40) },
		Neck = { K(0, -30), K(1.2, -34), K(2.4, -30) },
		RightShoulder = hold(40, 0, 10),
		LeftShoulder = hold(40, 0, -10),
		RightElbow = hold(10),
		LeftElbow = hold(10),
	},
}
C.awaken = S({ -- Awakening: curl in and gather, then the power bursts out, arms flung wide, head back
	dur = 1.2,
	a = 0.45,
	c = 0.58,
	f = 0.85,
	R = { w = { 40, 0, -20 }, h = { 40, 0, 110 }, f = { 50, 0, 100 }, e = { 130, 20, 30 } },
	L = { w = { 40, 0, 20 }, h = { 40, 0, -110 }, f = { 50, 0, -100 }, e = { 130, 20, 30 } },
	waist = { { -34, 0, 0 }, { 26, 0, 0 }, { 20, 0, 0 } },
	neck = { { -30, 0, 0 }, { 44, 0, 0 }, { 30, 0, 0 } },
	legs = "wide",
	lift = -0.8,
	dip = 0.4,
})
C.powerCharge = { -- someone else's charge-up (the Charging attribute): crouched, fists trembling at the hips
	dur = 0.3,
	loop = true,
	joints = {
		RightShoulder = { K(0, -10, 0, 30), K(0.15, -12, 0, 32), K(0.3, -10, 0, 30) },
		LeftShoulder = { K(0, -10, 0, -30), K(0.15, -12, 0, -32), K(0.3, -10, 0, -30) },
		RightElbow = hold(100),
		LeftElbow = hold(100),
		Waist = { K(0, -14), K(0.15, -16), K(0.3, -14) },
		Neck = hold(-6),
		RightHip = hold(30, 0, 20),
		LeftHip = hold(30, 0, -20),
		RightKnee = hold(-60),
		LeftKnee = hold(-60),
		Root = { K(0, 0, 0, 0, -0.6), K(0.15, 0, 0, 0, -0.64), K(0.3, 0, 0, 0, -0.6) },
	},
}
C.windupBoth = { -- charging with both hands: cupped together at the hip, the chest turned away
	dur = 0.3,
	loop = true,
	joints = {
		RightShoulder = hold(-20, 0, -10),
		LeftShoulder = hold(-20, 0, 10),
		RightElbow = hold(110),
		LeftElbow = hold(110),
		RightWrist = hold(60),
		LeftWrist = hold(60),
		Waist = { K(0, -4, 44), K(0.15, -6, 46), K(0.3, -4, 44) },
		Neck = hold(0, -36),
		RightHip = hold(20, 0, 20),
		LeftHip = hold(20, 0, -20),
		RightKnee = hold(-40),
		LeftKnee = hold(-40),
		Root = hold(0, 0, 0, -0.45),
	},
}
C.windupHeavy = { -- a heavy wind-up: the weapon or both fists raised high behind the head
	dur = 0.3,
	loop = true,
	joints = {
		RightShoulder = { K(0, 170, 0, 30), K(0.15, 172, 0, 32), K(0.3, 170, 0, 30) },
		LeftShoulder = hold(150, 0, 10),
		RightElbow = hold(60),
		LeftElbow = hold(70),
		Waist = hold(16, 30),
		Neck = hold(-10, -20),
		RightHip = hold(-14, 0, 10),
		LeftHip = hold(30, 0, -10),
		RightKnee = hold(-20),
		LeftKnee = hold(-40),
		Root = hold(0, 0, 0, -0.3),
	},
}
C.flinchL = S({ -- hit from the left: the chest twists away
	dur = 0.36,
	a = 0.08,
	c = 0.25,
	f = 0.6,
	R = { w = { 30, 0, 20 }, h = { -10, 0, 50 }, e = { 70, 40, 50 } },
	L = { w = { 30, 0, -20 }, h = { 60, 0, -10 }, e = { 70, 110, 90 } },
	waist = { { 0, 0, 0 }, { 14, -30, 10 }, { 6, -14, 0 } },
	neck = { { 0, 0, 0 }, { 10, -20, 10 } },
	legs = "back",
})
C.flinchR = mirror(C.flinchL)
C.flinchHeavy = S({ -- a big hit: knocked off balance, the arms flail
	dur = 0.6,
	a = 0.06,
	c = 0.25,
	f = 0.6,
	R = { w = { 30, 0, 20 }, h = { 60, 0, 90 }, f = { 30, 0, 50 }, e = { 70, 20, 40 } },
	L = { w = { 30, 0, -20 }, h = { 60, 0, -90 }, f = { 30, 0, -50 }, e = { 70, 20, 40 } },
	waist = { { 0, 0, 0 }, { 34, 0, 0 }, { 16, 0, 0 } },
	neck = { { 0, 0, 0 }, { 30, 0, 0 } },
	legs = "back",
	dip = -0.5,
})
C.emoteBob = { -- under an emote's held pose (EmoteFx): it breathes and bounces instead of freezing
	dur = 1.6,
	loop = true,
	joints = {
		Root = {
			K(0, 0, 0, 0, 0),
			K(0.4, 0, 0, 0, -0.12),
			K(0.8, 0, 0, 0, 0),
			K(1.2, 0, 0, 0, -0.12),
			K(1.6),
		},
		Waist = { K(0, 0, 0, 0), K(0.8, 3, 4, 0), K(1.6, 0, 0, 0) },
		Neck = { K(0, 0, 0, 0), K(0.8, 4, -6, 0), K(1.6, 0, 0, 0) },
	},
}

---------------------------------------------------------------------------
-- Mobility: the mode poses the first pass did not have, and every take-off and landing
---------------------------------------------------------------------------
C.leapCrouch = { -- Leap held (the "charge" mode): coiled low, arms swung back, trembling as it builds
	dur = 0.4,
	loop = true,
	joints = {
		RightShoulder = { K(0, -50, 0, 16), K(0.2, -54, 0, 18), K(0.4, -50, 0, 16) },
		LeftShoulder = { K(0, -50, 0, -16), K(0.2, -54, 0, -18), K(0.4, -50, 0, -16) },
		RightElbow = hold(20),
		LeftElbow = hold(20),
		Waist = { K(0, -40), K(0.2, -42), K(0.4, -40) },
		Neck = hold(30),
		RightHip = hold(80, 0, 10),
		LeftHip = hold(80, 0, -10),
		RightKnee = hold(-110),
		LeftKnee = hold(-110),
		RightAnkle = hold(30),
		LeftAnkle = hold(30),
		Root = { K(0, 0, 0, 0, -1.2), K(0.2, 0, 0, 0, -1.25), K(0.4, 0, 0, 0, -1.2) },
	},
}
C.waterRun = { -- Super-speed across water: a flat-out sprint, arms back like blades, the body low
	dur = 0.3,
	loop = true,
	joints = {
		Waist = hold(-34),
		Neck = hold(30),
		RightShoulder = hold(-70, 0, 14),
		LeftShoulder = hold(-70, 0, -14),
		RightElbow = hold(10),
		LeftElbow = hold(10),
		RightHip = { K(0, 70), K(0.15, -40), K(0.3, 70) },
		LeftHip = { K(0, -40), K(0.15, 70), K(0.3, -40) },
		RightKnee = { K(0, -30), K(0.15, -100), K(0.3, -30) },
		LeftKnee = { K(0, -100), K(0.15, -30), K(0.3, -100) },
		Root = {
			K(0, 0, 0, 0, -0.2),
			K(0.075, 0, 0, 0, 0),
			K(0.15, 0, 0, 0, -0.2),
			K(0.225, 0, 0, 0, 0),
			K(0.3, 0, 0, 0, -0.2),
		},
	},
}
C.sprint = { -- Super-speed on the ground: leaning hard into the run, arms pumping
	dur = 0.36,
	loop = true,
	joints = {
		Waist = hold(-22),
		Neck = hold(18),
		RightShoulder = { K(0, -60, 0, 8), K(0.18, 70, 0, 8), K(0.36, -60, 0, 8) },
		LeftShoulder = { K(0, 70, 0, -8), K(0.18, -60, 0, -8), K(0.36, 70, 0, -8) },
		RightElbow = hold(90),
		LeftElbow = hold(90),
		RightHip = { K(0, 70), K(0.18, -40), K(0.36, 70) },
		LeftHip = { K(0, -40), K(0.18, 70), K(0.36, -40) },
		RightKnee = { K(0, -20), K(0.09, -60), K(0.18, -110), K(0.27, -60), K(0.36, -20) },
		LeftKnee = { K(0, -110), K(0.09, -60), K(0.18, -20), K(0.27, -60), K(0.36, -110) },
		Root = {
			K(0, 0, 0, 0, -0.1),
			K(0.09, 0, 0, 0, 0.1),
			K(0.18, 0, 0, 0, -0.1),
			K(0.27, 0, 0, 0, 0.1),
			K(0.36, 0, 0, 0, -0.1),
		},
	},
}
C.flyFast = { -- boosting: both fists forward, body locked straight, legs tight together
	dur = 0.6,
	loop = true,
	joints = {
		RightShoulder = { K(0, 176, 0, 4), K(0.3, 178, 0, 3), K(0.6, 176, 0, 4) },
		LeftShoulder = { K(0, 176, 0, -4), K(0.3, 178, 0, -3), K(0.6, 176, 0, -4) },
		RightElbow = hold(0),
		LeftElbow = hold(0),
		Waist = hold(2),
		Neck = hold(40),
		RightHip = { K(0, -2), K(0.3, -4), K(0.6, -2) },
		LeftHip = { K(0, -2), K(0.3, 0), K(0.6, -2) },
		RightKnee = hold(-4),
		LeftKnee = hold(-6),
		RightAnkle = hold(-40),
		LeftAnkle = hold(-40),
	},
}
C.dive = { -- flying straight down: arms swept back along the sides, head first
	dur = 0.8,
	loop = true,
	joints = {
		RightShoulder = { K(0, -20, 0, 20), K(0.4, -24, 0, 24), K(0.8, -20, 0, 20) },
		LeftShoulder = { K(0, -20, 0, -20), K(0.4, -24, 0, -24), K(0.8, -20, 0, -20) },
		RightElbow = hold(4),
		LeftElbow = hold(4),
		Waist = hold(-6),
		Neck = hold(44),
		RightHip = hold(-4),
		LeftHip = hold(-4),
		RightKnee = { K(0, -4), K(0.4, -14), K(0.8, -4) },
		LeftKnee = { K(0, -14), K(0.4, -4), K(0.8, -14) },
		RightAnkle = hold(-40),
		LeftAnkle = hold(-40),
	},
}
C.arc = { -- a zip, a grapple, a launch arc: one arm up the line, knees tucked, body leading
	dur = 0.6,
	loop = true,
	joints = {
		RightShoulder = { K(0, 170, 0, 6), K(0.3, 172, 0, 4), K(0.6, 170, 0, 6) },
		RightElbow = hold(10),
		LeftShoulder = { K(0, 30, 0, -40), K(0.3, 40, 0, -46), K(0.6, 30, 0, -40) },
		LeftElbow = hold(40),
		Waist = hold(-10),
		Neck = hold(20),
		RightHip = hold(60),
		LeftHip = hold(30),
		RightKnee = hold(-90),
		LeftKnee = hold(-60),
	},
}
C.swim = { -- swimming (in the water, not running on it): a breaststroke with a frog kick
	dur = 1.4,
	loop = true,
	joints = {
		RightShoulder = { K(0, 170, 0, 10), K(0.5, 90, 0, 80), K(0.9, 20, 0, 20), K(1.4, 170, 0, 10) },
		LeftShoulder = { K(0, 170, 0, -10), K(0.5, 90, 0, -80), K(0.9, 20, 0, -20), K(1.4, 170, 0, -10) },
		RightElbow = { K(0, 10), K(0.5, 30), K(0.9, 110), K(1.4, 10) },
		LeftElbow = { K(0, 10), K(0.5, 30), K(0.9, 110), K(1.4, 10) },
		Waist = hold(-10),
		Neck = hold(40),
		RightHip = { K(0, 0, 0, 10), K(0.7, 40, 0, 40), K(1.0, -4, 0, 6), K(1.4, 0, 0, 10) },
		LeftHip = { K(0, 0, 0, -10), K(0.7, 40, 0, -40), K(1.0, -4, 0, -6), K(1.4, 0, 0, -10) },
		RightKnee = { K(0, -10), K(0.7, -100), K(1.0, -4), K(1.4, -10) },
		LeftKnee = { K(0, -10), K(0.7, -100), K(1.0, -4), K(1.4, -10) },
		RightAnkle = hold(-40),
		LeftAnkle = hold(-40),
	},
}
-- ride poses by the path's travel power (HeroAnim.rideClip): the jets, the rock, the board, the platform,
-- the guardian, the rail (Tide keeps the surf stance, HeroAnim.ride)
C.rideJet = {
	dur = 1.2,
	loop = true,
	joints = {
		RightShoulder = { K(0, -24, 0, 24), K(0.6, -28, 0, 26), K(1.2, -24, 0, 24) },
		LeftShoulder = { K(0, -24, 0, -24), K(0.6, -28, 0, -26), K(1.2, -24, 0, -24) },
		RightElbow = hold(6),
		LeftElbow = hold(6),
		RightWrist = hold(0, -80),
		LeftWrist = hold(0, -80),
		Waist = hold(-8),
		Neck = hold(10),
		RightHip = { K(0, 10), K(0.6, 4), K(1.2, 10) },
		LeftHip = { K(0, 0), K(0.6, 8), K(1.2, 0) },
		RightKnee = hold(-20),
		LeftKnee = hold(-30),
		RightAnkle = hold(-30),
		LeftAnkle = hold(-30),
	},
}
C.rideRock = {
	dur = 1.6,
	loop = true,
	joints = {
		Waist = hold(-16, 20),
		Neck = hold(10, -20),
		RightShoulder = { K(0, 30, 0, 40), K(0.8, 36, 0, 46), K(1.6, 30, 0, 40) },
		LeftShoulder = { K(0, 30, 0, -40), K(0.8, 36, 0, -46), K(1.6, 30, 0, -40) },
		RightElbow = hold(70),
		LeftElbow = hold(70),
		RightHip = hold(46, 0, 18),
		LeftHip = hold(10, 0, -18),
		RightKnee = { K(0, -70), K(0.8, -76), K(1.6, -70) },
		LeftKnee = { K(0, -50), K(0.8, -56), K(1.6, -50) },
		Root = { K(0, 0, 0, 0, -0.6), K(0.8, 0, 0, 0, -0.66), K(1.6, 0, 0, 0, -0.6) },
	},
}
C.rideBoard = {
	dur = 1.4,
	loop = true,
	joints = {
		Waist = { K(0, -14, 50, 0), K(0.7, -16, 54, 6), K(1.4, -14, 50, 0) },
		Neck = hold(0, -50),
		RightShoulder = { K(0, 20, 0, 70), K(0.7, 30, 0, 76), K(1.4, 20, 0, 70) },
		LeftShoulder = { K(0, 20, 0, -70), K(0.7, 10, 0, -64), K(1.4, 20, 0, -70) },
		RightElbow = hold(20),
		LeftElbow = hold(20),
		RightHip = hold(30, 0, 20),
		LeftHip = hold(30, 0, -20),
		RightKnee = { K(0, -60), K(0.7, -70), K(1.4, -60) },
		LeftKnee = { K(0, -60), K(0.7, -66), K(1.4, -60) },
		Root = hold(0, 0, 0, -0.5),
	},
}
C.ridePlatform = { -- floating cross-legged on a psychic disc, palms up
	dur = 2.4,
	loop = true,
	joints = {
		RightHip = hold(90, 0, 50),
		LeftHip = hold(90, 0, -50),
		RightKnee = hold(-130),
		LeftKnee = hold(-130),
		Waist = { K(0, 4), K(1.2, 8), K(2.4, 4) },
		Neck = hold(6),
		RightShoulder = hold(20, 0, 30),
		LeftShoulder = hold(20, 0, -30),
		RightElbow = hold(80),
		LeftElbow = hold(80),
		RightWrist = hold(0, 0, 80),
		LeftWrist = hold(0, 0, -80),
		Root = { K(0, 0, 0, 0, -0.8), K(1.2, 0, 0, 0, -0.6), K(2.4, 0, 0, 0, -0.8) },
	},
}
C.rideSpirit = { -- astride the guardian: seated, one hand forward on its neck, the other up in a wave
	dur = 1.6,
	loop = true,
	joints = {
		RightHip = hold(80, 0, 30),
		LeftHip = hold(80, 0, -30),
		RightKnee = hold(-80),
		LeftKnee = hold(-80),
		Waist = { K(0, -10), K(0.8, -14), K(1.6, -10) },
		Neck = hold(14),
		RightShoulder = { K(0, 130, 0, 40), K(0.8, 140, 0, 50), K(1.6, 130, 0, 40) },
		RightElbow = hold(30),
		LeftShoulder = hold(60, 0, -10),
		LeftElbow = hold(40),
		Root = {
			K(0, 0, 0, 0, -0.6),
			K(0.4, 0, 0, 0, -0.4),
			K(0.8, 0, 0, 0, -0.6),
			K(1.2, 0, 0, 0, -0.4),
			K(1.6, 0, 0, 0, -0.6),
		},
	},
}
C.rideRail = { -- grinding the light rail: side-on, knees bent, arms out wide for balance
	dur = 1.2,
	loop = true,
	joints = {
		Waist = hold(-6, 60),
		Neck = hold(0, -60),
		RightShoulder = { K(0, 0, 0, 86), K(0.6, 6, 0, 80), K(1.2, 0, 0, 86) },
		LeftShoulder = { K(0, 0, 0, -86), K(0.6, -6, 0, -92), K(1.2, 0, 0, -86) },
		RightElbow = hold(10),
		LeftElbow = hold(10),
		RightHip = hold(30, 0, 14),
		LeftHip = hold(20, 0, -14),
		RightKnee = { K(0, -50), K(0.6, -56), K(1.2, -50) },
		LeftKnee = { K(0, -40), K(0.6, -46), K(1.2, -40) },
		Root = hold(0, 0, 0, -0.4),
	},
}

-- Transitions: one-shots HeroAnimator plays on a mode change (every device sees them: they come from the mode)
C.takeoff = S({ -- off the ground into flight: a dip, then the spring, one fist punched to the sky
	dur = 0.55,
	a = 0.25,
	c = 0.45,
	f = 0.75,
	R = { w = { -30, 0, 20 }, h = { 176, 0, 6 }, f = { 176, 0, 6 }, e = { 80, 0, 0 } },
	L = { w = { -30, 0, -20 }, h = { -20, 0, -20 }, e = { 80, 10, 10 } },
	waist = { { 20, 0, 0 }, { 6, 0, 0 } },
	neck = { { -10, 0, 0 }, { 40, 0, 0 } },
	legs = "hop",
	lift = -0.8,
	dip = 0.3,
})
C.flyStop = S({ -- out of flight: the body swings upright, arms flare to brake
	dur = 0.45,
	R = { w = { 160, 0, 10 }, h = { 60, 0, 80 }, e = { 10, 20, 20 } },
	L = { w = { 20, 0, -20 }, h = { 60, 0, -80 }, e = { 20, 20, 20 } },
	waist = { { 0, 0, 0 }, { 20, 0, 0 } },
	legs = "hop",
	dip = 0,
	lift = 0,
})
C.land = S({ -- a normal landing: knees absorb it, arms come down
	dur = 0.4,
	a = 0.05,
	c = 0.3,
	f = 0.55,
	R = { w = { 40, 0, 40 }, h = { 20, 0, 30 }, e = { 40, 30, 30 } },
	L = { w = { 40, 0, -40 }, h = { 20, 0, -30 }, e = { 40, 30, 30 } },
	waist = { { 0, 0, 0 }, { -24, 0, 0 }, { -10, 0, 0 } },
	legs = "squat",
	lift = 0,
	dip = -0.7,
})
C.landHard = S({ -- the superhero landing: one knee and one fist into the ground, the other arm out
	dur = 0.9,
	a = 0.05,
	c = 0.25,
	f = 0.7,
	R = { w = { 60, 0, 20 }, h = { 30, 0, 10 }, f = { 30, 0, 10 }, e = { 20, 0, 0 } },
	L = { w = { 60, 0, -40 }, h = { 20, 0, -70 }, f = { 20, 0, -70 }, e = { 20, 20, 20 } },
	waist = { { 0, 0, 0 }, { -40, 0, 0 }, { -36, 0, 0 } },
	neck = { { 0, 0, 0 }, { 30, 0, 0 }, { 30, 0, 0 } },
	legs = "kneel",
	lift = 0,
	dip = -1.2,
})
C.landRoll = S({ -- a fast landing on the move: tuck and roll through it
	dur = 0.6,
	a = 0.05,
	c = 0.45,
	f = 0.8,
	R = { w = { 60, 0, 20 }, h = { 100, 0, 30 }, e = { 100, 110, 100 } },
	L = { w = { 60, 0, -20 }, h = { 100, 0, -30 }, e = { 100, 110, 100 } },
	waist = { { -20, 0, 0 }, { -50, 0, 0 }, { -30, 0, 0 } },
	legs = "hop",
	lift = 0,
	dip = -1.0,
	flip = 360,
})
C.poundLand = S({ -- a ground pound hits: both fists and a knee in, the body sunk into the crater
	dur = 0.8,
	a = 0.05,
	c = 0.2,
	f = 0.65,
	R = { w = { 170, 0, 10 }, h = { 30, 0, 14 }, f = { 30, 0, 14 }, e = { 20, 0, 0 } },
	L = { w = { 170, 0, -10 }, h = { 30, 0, -14 }, f = { 30, 0, -14 }, e = { 20, 0, 0 } },
	waist = { { 10, 0, 0 }, { -50, 0, 0 }, { -44, 0, 0 } },
	legs = "kneel",
	lift = 0,
	dip = -1.4,
})
C.leapOff = S({ -- the crouch released: arms thrown up, legs snap straight
	dur = 0.45,
	a = 0.05,
	c = 0.3,
	f = 0.7,
	R = { w = { -50, 0, 16 }, h = { 160, 0, 20 }, e = { 20, 10, 20 } },
	L = { w = { -50, 0, -16 }, h = { 160, 0, -20 }, e = { 20, 10, 20 } },
	waist = { { -40, 0, 0 }, { 10, 0, 0 } },
	neck = { { 30, 0, 0 }, { 30, 0, 0 } },
	legs = "rise",
	lift = -1.2,
	dip = 0.3,
})
C.airFlip = S({ -- a jump in the air (Acrobat) or a wall bounce (Leaping): a tucked front flip
	dur = 0.55,
	a = 0.1,
	c = 0.5,
	f = 0.85,
	R = { w = { 60, 0, 30 }, h = { 100, 0, 20 }, e = { 90, 110, 60 } },
	L = { w = { 60, 0, -30 }, h = { 100, 0, -20 }, e = { 90, 110, 60 } },
	waist = { { -10, 0, 0 }, { -40, 0, 0 }, { -10, 0, 0 } },
	legs = "hop",
	lift = 0,
	dip = 0,
	flip = 360,
})
C.wallKick = S({ -- off a wall: the legs drive, the arms swing through
	dur = 0.45,
	a = 0.1,
	c = 0.35,
	R = { w = { 140, 0, 20 }, h = { -30, 0, 30 }, e = { 40, 10, 10 } },
	L = { w = { 140, 0, -20 }, h = { -30, 0, -30 }, e = { 40, 10, 10 } },
	waist = { { -20, 0, 0 }, { 20, 0, 0 } },
	legs = "rise",
	lift = 0,
	dip = 0,
})
C.wallGrab = S({ -- onto a wall: hands slap on, knees come up
	dur = 0.35,
	a = 0.1,
	c = 0.4,
	R = { w = { 120, 0, 20 }, h = { 160, 0, 14 }, e = { 40, 30, 30 } },
	L = { w = { 120, 0, -20 }, h = { 130, 0, -14 }, e = { 40, 60, 60 } },
	waist = { { 0, 0, 0 }, { 14, 0, 0 } },
	legs = "hop",
	lift = 0,
	dip = 0,
})
C.swingCatch = S({ -- the line fires and catches: arm whipped up, the body jerked under it
	dur = 0.45,
	a = 0.2,
	c = 0.35,
	R = { w = { 120, 0, 20 }, h = { 178, 0, 4 }, f = { 178, 0, 4 }, e = { 60, 0, 6 }, wr = { -40, -60, 0 } },
	L = { w = { 40, 0, -40 }, h = { 20, 0, -60 }, e = { 40, 30, 30 } },
	waist = { { 10, 0, 0 }, { -10, 0, 0 } },
	legs = "hop",
	lift = 0,
	dip = 0,
})
C.swingRelease = S({ -- letting go of the line at the top: a forward flip out of it
	dur = 0.6,
	a = 0.1,
	c = 0.5,
	f = 0.85,
	R = { w = { 178, 0, 4 }, h = { 100, 0, 30 }, e = { 6, 110, 60 } },
	L = { w = { 30, 0, -40 }, h = { 100, 0, -30 }, e = { 40, 110, 60 } },
	waist = { { 0, 0, 0 }, { -40, 0, 0 }, { -10, 0, 0 } },
	legs = "hop",
	lift = 0,
	dip = 0,
	flip = 360,
})
C.glideOpen = S({ -- the glide opens: arms snap out wide, the chest arches
	dur = 0.4,
	a = 0.1,
	c = 0.4,
	R = { w = { 60, 0, 30 }, h = { -10, 0, 96 }, e = { 60, 4, 4 } },
	L = { w = { 60, 0, -30 }, h = { -10, 0, -96 }, e = { 60, 4, 4 } },
	waist = { { -10, 0, 0 }, { 12, 0, 0 } },
	legs = "rise",
	lift = 0,
	dip = 0,
})
C.dashStart = S({ -- into a dash: a quick lean and a push off the back foot
	dur = 0.3,
	a = 0.1,
	c = 0.3,
	R = { w = { 30, 0, 20 }, h = { -50, 0, 20 }, e = { 60, 20, 20 } },
	L = { w = { 30, 0, -20 }, h = { -50, 0, -20 }, e = { 60, 20, 20 } },
	waist = { { 0, 0, 0 }, { -30, 0, 0 } },
	legs = "step",
	lift = 0,
	dip = 0,
})

-- pt-anims (nate's playtest 2026-11-19, with pt-combat's ground pound and robot swing): the heavy ground-pound
-- landing and a grabbed robot swung as a two-handed weapon (both hands on its legs, the robot as the club head)
C.poundLandHeavy = S({ -- a big ground pound: both fists driven into the crater, a wide squat, held, then up
	dur = 1.1,
	a = 0.04,
	c = 0.16,
	f = 0.75,
	R = { w = { 175, 0, 8 }, h = { 20, 0, 24 }, f = { 22, 0, 24 }, e = { 10, 0, 0 }, wr = { 0, 0, 0 } },
	L = { w = { 175, 0, -8 }, h = { 20, 0, -24 }, f = { 22, 0, -24 }, e = { 10, 0, 0 } },
	waist = { { 14, 0, 0 }, { -56, 0, 0 }, { -50, 0, 0 } },
	neck = { { 0, 0, 0 }, { 34, 0, 0 }, { 30, 0, 0 } },
	legs = "squat",
	lift = 0,
	dip = -1.5,
})
C.robotHold = { -- a grabbed robot held like a club: both hands together by the right shoulder, cocked back
	dur = 1.2,
	loop = true,
	joints = {
		RightShoulder = { K(0, 120, 0, 30), K(0.6, 124, 0, 32), K(1.2, 120, 0, 30) },
		RightElbow = { K(0, 70), K(0.6, 74), K(1.2, 70) },
		LeftShoulder = { K(0, 110, 0, 46), K(0.6, 114, 0, 48), K(1.2, 110, 0, 46) },
		LeftElbow = { K(0, 86), K(0.6, 90), K(1.2, 86) },
		RightWrist = hold(-20),
		LeftWrist = hold(-20),
		Waist = { K(0, 6, 26), K(0.6, 8, 28), K(1.2, 6, 26) },
		Neck = hold(0, -20),
	},
}
C.robotSwing = S({ -- the grabbed robot swung flat round the body, right to left, both hands on it
	dur = 0.75,
	a = 0.35,
	c = 0.55,
	f = 0.78,
	R = { w = { 110, 0, 70 }, h = { 92, 0, -20 }, f = { 84, 0, -50 }, e = { 50, 10, 16 } },
	L = { w = { 100, 0, 80 }, h = { 92, 0, -6 }, f = { 84, 0, -36 }, e = { 70, 14, 22 } },
	waist = { { 8, 60, 0 }, { -10, -50, 0 }, { -8, -70, 0 } },
	legs = "wide",
	dip = -0.5,
})
C.robotSwingBack = S({ -- the backhand return: the robot comes back left to right, lower
	dur = 0.7,
	a = 0.32,
	c = 0.52,
	f = 0.76,
	R = { w = { 84, 0, -50 }, h = { 70, 0, 60 }, f = { 64, 0, 80 }, e = { 50, 10, 16 } },
	L = { w = { 84, 0, -36 }, h = { 70, 0, 74 }, f = { 64, 0, 94 }, e = { 70, 14, 22 } },
	waist = { { 4, -60, 0 }, { -14, 46, 0 }, { -10, 60, 0 } },
	legs = "stepL",
	dip = -0.4,
})
C.robotSlam = S({ -- the robot raised overhead in both hands and slammed down in front
	dur = 0.9,
	a = 0.45,
	c = 0.62,
	f = 0.8,
	R = { w = { 176, 0, 14 }, h = { 40, 0, 4 }, e = { 30, 10, 10 } },
	L = { w = { 176, 0, -14 }, h = { 40, 0, -4 }, e = { 30, 10, 10 } },
	waist = { { 26, 0, 0 }, { -48, 0, 0 } },
	neck = { { 24, 0, 0 }, { -10, 0, 0 } },
	legs = "kneel",
	lift = 0.3,
})

return HeroMoves
