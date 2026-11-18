--!strict
-- HeroAnim: the heroes' core animations as data (overhaul plan step 2: idle, run, fly, combo, cast, hit), and
-- the maths that samples them. Roblox's default Animate keeps the ground idle, walk, run and jump; these
-- clips cover everything it has no animation for: flight, hover, glide, leaps, dashes, slides, swings, wall
-- runs, rides, swimming, the Downed kneel, every power cast, every weapon's combo and moves, the windup and
-- the flinch when hit. HeroAnimator (client) plays them on every hero by writing Motor6D.Transform after the
-- Animator, so nothing needs uploading and they work on the blocky R15 rig (and any R15 avatar).
-- A clip only moves the joints it lists (that is its mask): a cast moves the arms and torso and leaves the
-- legs to the walk or the flight pose underneath.
-- Angles are degrees in the joint's frame (the rig's attachments are axis-aligned): on a shoulder or hip +x
-- swings the limb forward and up; on an elbow +x bends the forearm forward, on a knee -x bends the shin
-- back; on the waist +x leans back and -x forward, +y turns the chest left; on the neck +x looks up. Left limbs
-- go outward with -z, right limbs with +z. The 5th number is a height offset in studs (Root only: kneeling).
-- PLACEHOLDER ANIMATION: hand-keyed poses until real animations are made and uploaded (Tasks.md).
-- Pure: no Roblox types, so Lune tests it.

local HeroAnim = {}

export type Key = { number } -- { t, rx, ry, rz, py? }
export type Clip = { dur: number, loop: boolean?, joints: { [string]: { Key } } }
export type Angles = { [string]: { number } } -- joint -> { rx, ry, rz, py }

-- MoveController's modes, as sent to the server (the Move attribute other devices read): never reorder
HeroAnim.MODES = {
	"ground",
	"air",
	"charge",
	"dash",
	"fly",
	"glide",
	"pound",
	"ride",
	"slide",
	"swing",
	"water",
	"wall",
	"wallrun",
}
HeroAnim.modeIndex = {} :: { [string]: number }
for i, m in HeroAnim.MODES do
	HeroAnim.modeIndex[m] = i
end

-- timing
HeroAnim.fadeIn = 0.06 -- an action blends in this fast
HeroAnim.fadeOut = 0.14 -- and out
HeroAnim.modeBlend = 0.2 -- a mode pose crossfades in this long
HeroAnim.hoverSpeed = 18 -- flying slower than this (studs a second) hovers
HeroAnim.range = 260 -- heroes further away are not animated
HeroAnim.nearRange = 90 -- past this they update every other frame

local function K(t: number, rx: number?, ry: number?, rz: number?, py: number?): Key
	return { t, rx or 0, ry or 0, rz or 0, py or 0 }
end

-- the same pose all through (a held pose)
local function hold(rx: number?, ry: number?, rz: number?, py: number?): { Key }
	return { K(0, rx, ry, rz, py) }
end

-- swap Left and Right and mirror the angles (y and z flip), for the other hand's version of a clip
function HeroAnim.mirror(clip: Clip): Clip
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

local C: { [string]: Clip } = {}

-- Movement poses (loops). Flight: the body is already pitched along the travel direction (MoveController),
-- so "arm forward" is overhead: one fist leads, the other arm trails, legs together with a soft kick.
C.fly = {
	dur = 1.6,
	loop = true,
	joints = {
		RightShoulder = { K(0, 168, 0, 8), K(0.8, 172, 0, 6), K(1.6, 168, 0, 8) },
		RightElbow = hold(4),
		LeftShoulder = { K(0, 12, 0, -14), K(0.8, 18, 0, -12), K(1.6, 12, 0, -14) },
		LeftElbow = hold(14),
		Waist = hold(6),
		Neck = hold(32),
		RightHip = { K(0, -4), K(0.8, -10), K(1.6, -4) },
		RightKnee = { K(0, -10), K(0.8, -22), K(1.6, -10) },
		LeftHip = { K(0, -8), K(0.8, -2), K(1.6, -8) },
		LeftKnee = { K(0, -26), K(0.8, -12), K(1.6, -26) },
		RightAnkle = hold(-30),
		LeftAnkle = hold(-30),
	},
}
C.hover = {
	dur = 2.2,
	loop = true,
	joints = {
		RightShoulder = { K(0, 12, 0, 24), K(1.1, 18, 0, 30), K(2.2, 12, 0, 24) },
		LeftShoulder = { K(0, 12, 0, -24), K(1.1, 18, 0, -30), K(2.2, 12, 0, -24) },
		RightElbow = hold(18),
		LeftElbow = hold(18),
		RightHip = { K(0, 8), K(1.1, 2), K(2.2, 8) },
		LeftHip = { K(0, 0), K(1.1, 10), K(2.2, 0) },
		RightKnee = { K(0, -24), K(1.1, -12), K(2.2, -24) },
		LeftKnee = { K(0, -10), K(1.1, -28), K(2.2, -10) },
		RightAnkle = hold(-25),
		LeftAnkle = hold(-25),
		Neck = hold(-4),
	},
}
C.glide = {
	dur = 1.2,
	loop = true,
	joints = {
		RightShoulder = { K(0, -8, 0, 86), K(0.6, -4, 0, 82), K(1.2, -8, 0, 86) },
		LeftShoulder = { K(0, -8, 0, -86), K(0.6, -4, 0, -82), K(1.2, -8, 0, -86) },
		RightElbow = hold(4),
		LeftElbow = hold(4),
		Waist = hold(-8),
		Neck = hold(24),
		RightHip = hold(-6),
		LeftHip = hold(-6),
		RightKnee = hold(-6),
		LeftKnee = hold(-6),
		RightAnkle = hold(-35),
		LeftAnkle = hold(-35),
	},
}
C.air = {
	dur = 1.0,
	loop = true,
	joints = {
		RightShoulder = { K(0, 30, 0, 40), K(0.5, 40, 0, 46), K(1, 30, 0, 40) },
		LeftShoulder = { K(0, 30, 0, -40), K(0.5, 40, 0, -46), K(1, 30, 0, -40) },
		RightElbow = hold(30),
		LeftElbow = hold(30),
		RightHip = hold(38),
		LeftHip = hold(18),
		RightKnee = hold(-58),
		LeftKnee = hold(-36),
		Neck = hold(-6),
	},
}
C.dash = {
	dur = 0.5,
	loop = true,
	joints = {
		Waist = hold(-24),
		Neck = hold(18),
		RightShoulder = hold(-44, 0, 16),
		LeftShoulder = hold(-44, 0, -16),
		RightElbow = hold(10),
		LeftElbow = hold(10),
		RightHip = hold(34),
		LeftHip = hold(-30),
		RightKnee = hold(-20),
		LeftKnee = hold(-40),
	},
}
C.charge = { -- a shoulder barge
	dur = 0.5,
	loop = true,
	joints = {
		Waist = hold(-30, -20),
		Neck = hold(22),
		RightShoulder = hold(56, 0, 34),
		RightElbow = hold(70),
		LeftShoulder = hold(-30, 0, -20),
		LeftElbow = hold(30),
		RightHip = { K(0, 40), K(0.25, -30), K(0.5, 40) },
		LeftHip = { K(0, -30), K(0.25, 40), K(0.5, -30) },
		RightKnee = { K(0, -30), K(0.25, -70), K(0.5, -30) },
		LeftKnee = { K(0, -70), K(0.25, -30), K(0.5, -70) },
	},
}
C.pound = {
	dur = 0.6,
	loop = true,
	joints = {
		RightShoulder = hold(170, 0, 10),
		LeftShoulder = hold(170, 0, -10),
		RightElbow = hold(20),
		LeftElbow = hold(20),
		Waist = hold(-12),
		RightHip = hold(60),
		LeftHip = hold(60),
		RightKnee = hold(-80),
		LeftKnee = hold(-80),
	},
}
C.slide = {
	dur = 0.6,
	loop = true,
	joints = {
		Waist = hold(26),
		Neck = hold(-14),
		LeftHip = hold(72),
		LeftKnee = hold(-8),
		RightHip = hold(12),
		RightKnee = hold(-84),
		RightShoulder = hold(-20, 0, 40),
		LeftShoulder = hold(-20, 0, -40),
	},
}
C.swing = {
	dur = 1.4,
	loop = true,
	joints = {
		RightShoulder = hold(178, 0, 4),
		RightElbow = hold(6),
		LeftShoulder = { K(0, 20, 0, -50), K(0.7, 40, 0, -40), K(1.4, 20, 0, -50) },
		LeftElbow = hold(30),
		RightHip = { K(0, 30), K(0.7, 50), K(1.4, 30) },
		LeftHip = { K(0, 50), K(0.7, 24), K(1.4, 50) },
		RightKnee = { K(0, -40), K(0.7, -20), K(1.4, -40) },
		LeftKnee = { K(0, -20), K(0.7, -50), K(1.4, -20) },
		Neck = hold(10),
	},
}
C.wall = { -- climbing
	dur = 0.8,
	loop = true,
	joints = {
		RightShoulder = { K(0, 160, 0, 10), K(0.4, 110, 0, 14), K(0.8, 160, 0, 10) },
		LeftShoulder = { K(0, 110, 0, -14), K(0.4, 160, 0, -10), K(0.8, 110, 0, -14) },
		RightElbow = { K(0, 20), K(0.4, 70), K(0.8, 20) },
		LeftElbow = { K(0, 70), K(0.4, 20), K(0.8, 70) },
		RightHip = { K(0, 10), K(0.4, 50), K(0.8, 10) },
		LeftHip = { K(0, 50), K(0.4, 10), K(0.8, 50) },
		RightKnee = { K(0, -20), K(0.4, -80), K(0.8, -20) },
		LeftKnee = { K(0, -80), K(0.4, -20), K(0.8, -80) },
		Neck = hold(16),
	},
}
C.wallrun = { -- a sprint, leaning off the wall
	dur = 0.5,
	loop = true,
	joints = {
		Waist = hold(-16),
		RightShoulder = { K(0, -50, 0, 8), K(0.25, 60, 0, 8), K(0.5, -50, 0, 8) },
		LeftShoulder = { K(0, 60, 0, -8), K(0.25, -50, 0, -8), K(0.5, 60, 0, -8) },
		RightElbow = hold(80),
		LeftElbow = hold(80),
		RightHip = { K(0, 55), K(0.25, -30), K(0.5, 55) },
		LeftHip = { K(0, -30), K(0.25, 55), K(0.5, -30) },
		RightKnee = { K(0, -20), K(0.25, -90), K(0.5, -20) },
		LeftKnee = { K(0, -90), K(0.25, -20), K(0.5, -90) },
	},
}
C.ride = { -- standing on a jet, rock, board or rail: a surf stance
	dur = 2.0,
	loop = true,
	joints = {
		Waist = hold(-6, 30),
		Neck = hold(0, -30),
		RightShoulder = { K(0, 10, 0, 50), K(1, 16, 0, 56), K(2, 10, 0, 50) },
		LeftShoulder = { K(0, 10, 0, -50), K(1, 16, 0, -56), K(2, 10, 0, -50) },
		RightHip = hold(20, 0, 12),
		LeftHip = hold(-10, 0, -12),
		RightKnee = { K(0, -30), K(1, -38), K(2, -30) },
		LeftKnee = { K(0, -24), K(1, -32), K(2, -24) },
	},
}
C.water = { -- a front crawl
	dur = 1.4,
	loop = true,
	joints = {
		RightShoulder = { K(0, 180, 0, 10), K(0.7, 0, 0, 20), K(1.4, 180, 0, 10) },
		LeftShoulder = { K(0, 0, 0, -20), K(0.7, 180, 0, -10), K(1.4, 0, 0, -20) },
		RightElbow = hold(16),
		LeftElbow = hold(16),
		Neck = hold(34),
		RightHip = { K(0, 14), K(0.35, -14), K(0.7, 14), K(1.05, -14), K(1.4, 14) },
		LeftHip = { K(0, -14), K(0.35, 14), K(0.7, -14), K(1.05, 14), K(1.4, -14) },
		RightAnkle = hold(-40),
		LeftAnkle = hold(-40),
	},
}
-- Downed: kneeling on one knee (still), or slumped while crawling away (moving)
C.downed = {
	dur = 2.0,
	loop = true,
	joints = {
		Root = hold(0, 0, 0, -0.95),
		Waist = { K(0, -22), K(1, -26), K(2, -22) },
		Neck = hold(-16),
		RightHip = hold(88),
		RightKnee = hold(-88),
		LeftHip = hold(-4),
		LeftKnee = hold(-96),
		LeftAnkle = hold(-60),
		RightShoulder = hold(36, 0, 8),
		RightElbow = hold(40),
		LeftShoulder = hold(24, 0, -10),
		LeftElbow = hold(70),
	},
}
C.downedMove = {
	dur = 2.0,
	loop = true,
	joints = {
		Waist = { K(0, -26), K(1, -30), K(2, -26) },
		Neck = hold(-14),
		LeftShoulder = hold(36, 0, -6),
		LeftElbow = hold(80),
		RightShoulder = hold(10, 0, 14),
	},
}

-- Actions (one-shots). Power combos: alternate hands, the third hit lands harder.
C.punch = {
	dur = 0.28,
	joints = {
		RightShoulder = { K(0, 30, 0, 20), K(0.07, 92, 0, 6), K(0.16, 88, 0, 6), K(0.28, 30, 0, 20) },
		RightElbow = { K(0, 90), K(0.07, 4), K(0.16, 8), K(0.28, 90) },
		LeftShoulder = hold(56, 0, -8),
		LeftElbow = hold(110),
		Waist = { K(0, 0, 10), K(0.07, -6, -26), K(0.28, 0, 0) },
	},
}
C.uppercut = {
	dur = 0.36,
	joints = {
		RightShoulder = { K(0, -10, 0, 20), K(0.1, 150, 0, 10), K(0.22, 140, 0, 10), K(0.36, 20, 0, 20) },
		RightElbow = { K(0, 100), K(0.1, 40), K(0.36, 90) },
		LeftShoulder = hold(56, 0, -8),
		LeftElbow = hold(110),
		Waist = { K(0, -14, 14), K(0.1, 12, -20), K(0.36, 0, 0) },
		Neck = { K(0, 0), K(0.1, 14), K(0.36, 0) },
	},
}
C.kick = {
	dur = 0.4,
	joints = {
		RightHip = { K(0, 0), K(0.12, 92, 0, 10), K(0.24, 86, 0, 10), K(0.4, 0) },
		RightKnee = { K(0, -60), K(0.12, -4), K(0.24, -10), K(0.4, 0) },
		Waist = { K(0, 0), K(0.12, 18, -10), K(0.4, 0) },
		RightShoulder = hold(30, 0, 30),
		LeftShoulder = hold(40, 0, -30),
		LeftElbow = hold(90),
	},
}
-- an open palm thrust forward: bolts, beams, chains and cones
C.blast = {
	dur = 0.42,
	joints = {
		RightShoulder = { K(0, 60, 0, 20), K(0.08, 94, 0, 0), K(0.28, 92, 0, 0), K(0.42, 40, 0, 12) },
		RightElbow = { K(0, 60), K(0.08, 0), K(0.42, 30) },
		RightWrist = { K(0, 0), K(0.08, 60), K(0.42, 0) },
		LeftShoulder = hold(20, 0, -16),
		Waist = { K(0, 0, 14), K(0.08, -4, -22), K(0.42, 0, 0) },
	},
}
C.blast2 = { -- both hands: supers and big beams
	dur = 0.75,
	joints = {
		RightShoulder = { K(0, 40, 0, 40), K(0.18, 92, 0, 6), K(0.6, 92, 0, 6), K(0.75, 40, 0, 20) },
		LeftShoulder = { K(0, 40, 0, -40), K(0.18, 92, 0, -6), K(0.6, 92, 0, -6), K(0.75, 40, 0, -20) },
		RightElbow = { K(0, 90), K(0.18, 0), K(0.75, 30) },
		LeftElbow = { K(0, 90), K(0.18, 0), K(0.75, 30) },
		RightWrist = { K(0, 0), K(0.18, 60), K(0.75, 0) },
		LeftWrist = { K(0, 0), K(0.18, 60), K(0.75, 0) },
		Waist = { K(0, 10), K(0.18, -12), K(0.75, 0) },
		Neck = hold(6),
	},
}
C.channel = { -- a held beam (channels loop this until they end)
	dur = 1.0,
	loop = true,
	joints = {
		RightShoulder = { K(0, 92, 0, 2), K(0.5, 90, 0, 4), K(1, 92, 0, 2) },
		RightElbow = hold(2),
		RightWrist = hold(60),
		LeftShoulder = hold(80, 0, 20),
		LeftElbow = hold(40),
		Waist = hold(-4, -18),
	},
}
C.nova = { -- arms flung out: novas, bursts and areas around you
	dur = 0.55,
	joints = {
		RightShoulder = { K(0, 50, 0, 10), K(0.1, 10, 0, 96), K(0.4, 10, 0, 92), K(0.55, 0, 0, 20) },
		LeftShoulder = { K(0, 50, 0, -10), K(0.1, 10, 0, -96), K(0.4, 10, 0, -92), K(0.55, 0, 0, -20) },
		RightElbow = { K(0, 110), K(0.1, 4), K(0.55, 20) },
		LeftElbow = { K(0, 110), K(0.1, 4), K(0.55, 20) },
		Waist = { K(0, -16), K(0.1, 16), K(0.55, 0) },
		Neck = { K(0, -10), K(0.1, 18), K(0.55, 0) },
	},
}
C.slam = { -- both fists overhead, then down into the ground
	dur = 0.55,
	joints = {
		RightShoulder = { K(0, 170, 0, 10), K(0.16, 172, 0, 10), K(0.3, 50, 0, 10), K(0.55, 20, 0, 14) },
		LeftShoulder = { K(0, 170, 0, -10), K(0.16, 172, 0, -10), K(0.3, 50, 0, -10), K(0.55, 20, 0, -14) },
		RightElbow = { K(0, 30), K(0.3, 0), K(0.55, 20) },
		LeftElbow = { K(0, 30), K(0.3, 0), K(0.55, 20) },
		Waist = { K(0, 14), K(0.16, 16), K(0.3, -40), K(0.55, 0) },
		Neck = { K(0, 16), K(0.3, -10), K(0.55, 0) },
	},
}
C.buff = { -- the power-up flex: buffs, summons, fields, shields
	dur = 0.65,
	joints = {
		RightShoulder = { K(0, 20, 0, 20), K(0.15, 10, 0, 84), K(0.5, 10, 0, 84), K(0.65, 10, 0, 20) },
		LeftShoulder = { K(0, 20, 0, -20), K(0.15, 10, 0, -84), K(0.5, 10, 0, -84), K(0.65, 10, 0, -20) },
		RightElbow = { K(0, 20), K(0.15, 120), K(0.5, 124), K(0.65, 20) },
		LeftElbow = { K(0, 20), K(0.15, 120), K(0.5, 124), K(0.65, 20) },
		Waist = { K(0, 0), K(0.15, 8), K(0.65, 0) },
		Neck = { K(0, 0), K(0.15, 12), K(0.65, 0) },
	},
}
C.lunge = { -- dashes and leaps at a target
	dur = 0.45,
	joints = {
		Waist = { K(0, 10), K(0.1, -24), K(0.45, 0) },
		RightShoulder = { K(0, -20, 0, 20), K(0.1, 94, 0, 4), K(0.45, 20, 0, 14) },
		RightElbow = { K(0, 80), K(0.1, 4), K(0.45, 40) },
		LeftShoulder = { K(0, 20), K(0.1, -40, 0, -20), K(0.45, 0, 0, -14) },
		RightHip = { K(0, 0), K(0.1, 40), K(0.45, 0) },
		LeftHip = { K(0, 0), K(0.1, -36), K(0.45, 0) },
		RightKnee = { K(0, 0), K(0.1, -30), K(0.45, 0) },
		LeftKnee = { K(0, 0), K(0.1, -50), K(0.45, 0) },
	},
}
C.windup = { -- charging a cast: the hand drawn back, the chest turned away (held for the cast time)
	dur = 0.3,
	loop = true,
	joints = {
		RightShoulder = hold(-30, 0, 24),
		RightElbow = hold(96),
		LeftShoulder = hold(70, 0, -10),
		LeftElbow = hold(40),
		Waist = hold(-8, 32),
		Neck = hold(0, -24),
	},
}
C.flinch = { -- hit: knocked back a little
	dur = 0.34,
	joints = {
		Waist = { K(0, 0), K(0.06, 22), K(0.34, 0) },
		Neck = { K(0, 0), K(0.06, 22), K(0.34, 0) },
		RightShoulder = { K(0, 0, 0, 0), K(0.06, -20, 0, 34), K(0.34, 0, 0, 0) },
		LeftShoulder = { K(0, 0, 0, 0), K(0.06, -20, 0, -34), K(0.34, 0, 0, 0) },
	},
}

-- Weapons. One-handed slashes: high right to low left, backhand, then overhead.
C.slash = {
	dur = 0.32,
	joints = {
		RightShoulder = { K(0, 150, 0, 44), K(0.1, 60, 0, -24), K(0.2, 44, 0, -30), K(0.32, 60, 0, 20) },
		RightElbow = { K(0, 40), K(0.1, 4), K(0.32, 30) },
		LeftShoulder = hold(40, 0, -20),
		LeftElbow = hold(70),
		Waist = { K(0, 0, 30), K(0.1, -6, -30), K(0.32, 0, 0) },
	},
}
C.backslash = {
	dur = 0.32,
	joints = {
		RightShoulder = { K(0, 60, 0, -30), K(0.1, 100, 0, 70), K(0.2, 96, 0, 74), K(0.32, 60, 0, 20) },
		RightElbow = { K(0, 60), K(0.1, 4), K(0.32, 30) },
		LeftShoulder = hold(40, 0, -20),
		LeftElbow = hold(70),
		Waist = { K(0, 0, -26), K(0.1, -6, 30), K(0.32, 0, 0) },
	},
}
C.overhead = {
	dur = 0.4,
	joints = {
		RightShoulder = { K(0, 175, 0, 6), K(0.14, 178, 0, 6), K(0.24, 50, 0, 4), K(0.4, 50, 0, 16) },
		RightElbow = { K(0, 30), K(0.24, 0), K(0.4, 30) },
		LeftShoulder = hold(40, 0, -20),
		LeftElbow = hold(70),
		Waist = { K(0, 12), K(0.14, 14), K(0.24, -30), K(0.4, 0) },
	},
}
-- two-handed: both hands on the hilt, wide and slow
C.heavy = {
	dur = 0.55,
	joints = {
		RightShoulder = { K(0, 120, 0, 50), K(0.22, 120, 0, 52), K(0.34, 60, 0, -30), K(0.55, 50, 0, 10) },
		LeftShoulder = { K(0, 120, 0, 30), K(0.22, 120, 0, 32), K(0.34, 60, 0, -46), K(0.55, 50, 0, -10) },
		RightElbow = { K(0, 30), K(0.34, 4), K(0.55, 30) },
		LeftElbow = { K(0, 50), K(0.34, 10), K(0.55, 40) },
		Waist = { K(0, 4, 50), K(0.22, 4, 54), K(0.34, -10, -50), K(0.55, 0, 0) },
	},
}
C.heavyOver = {
	dur = 0.62,
	joints = {
		RightShoulder = { K(0, 176, 0, 4), K(0.28, 178, 0, 4), K(0.4, 40, 0, 4), K(0.62, 40, 0, 10) },
		LeftShoulder = { K(0, 176, 0, -4), K(0.28, 178, 0, -4), K(0.4, 40, 0, -4), K(0.62, 40, 0, -10) },
		RightElbow = { K(0, 30), K(0.4, 0), K(0.62, 30) },
		LeftElbow = { K(0, 30), K(0.4, 0), K(0.62, 30) },
		Waist = { K(0, 16), K(0.28, 18), K(0.4, -40), K(0.62, 0) },
		Neck = { K(0, 14), K(0.4, -10), K(0.62, 0) },
	},
}
C.thrust = { -- spears and staffs: a long poke
	dur = 0.36,
	joints = {
		RightShoulder = { K(0, 40, 0, 20), K(0.1, 92, 0, 0), K(0.2, 90, 0, 0), K(0.36, 40, 0, 16) },
		LeftShoulder = { K(0, 60, 0, 20), K(0.1, 86, 0, 10), K(0.36, 60, 0, 14) },
		RightElbow = { K(0, 100), K(0.1, 0), K(0.36, 80) },
		LeftElbow = { K(0, 60), K(0.1, 20), K(0.36, 60) },
		Waist = { K(0, 0, 20), K(0.1, -14, -10), K(0.36, 0, 0) },
	},
}
C.spin = { -- whirlwinds, spinning cleaves, spin volleys: the whole body turns once
	dur = 0.5,
	joints = {
		Root = { K(0, 0, 0), K(0.25, 0, 180), K(0.5, 0, 360) },
		RightShoulder = hold(10, 0, 88),
		LeftShoulder = hold(10, 0, -88),
		RightElbow = hold(4),
		LeftElbow = hold(4),
	},
}
C.bash = { -- the shield arm drives forward
	dur = 0.36,
	joints = {
		LeftShoulder = { K(0, 60, 0, -20), K(0.1, 88, 0, 10), K(0.22, 86, 0, 10), K(0.36, 60, 0, -14) },
		LeftElbow = { K(0, 90), K(0.1, 40), K(0.36, 80) },
		Waist = { K(0, 0, -16), K(0.1, -10, 22), K(0.36, 0, 0) },
		RightShoulder = hold(20, 0, 20),
	},
}
C.block = { -- shield or guard up, held
	dur = 0.8,
	joints = {
		LeftShoulder = { K(0, 30, 0, -10), K(0.1, 84, 0, 16), K(0.65, 84, 0, 16), K(0.8, 30, 0, -10) },
		LeftElbow = { K(0, 60), K(0.1, 80), K(0.8, 60) },
		RightShoulder = { K(0, 20, 0, 10), K(0.1, 60, 0, -10), K(0.65, 60, 0, -10), K(0.8, 20, 0, 10) },
		RightElbow = { K(0, 30), K(0.1, 100), K(0.8, 30) },
		Waist = { K(0, 0), K(0.1, -10), K(0.8, 0) },
	},
}
C.shoot = { -- pistols, rifles and cannons: aim with both hands and kick back
	dur = 0.3,
	joints = {
		RightShoulder = { K(0, 86, 0, 0), K(0.04, 98, 0, 0), K(0.3, 88, 0, 0) },
		RightElbow = hold(2),
		LeftShoulder = hold(80, 0, 30),
		LeftElbow = hold(40),
		Waist = hold(0, -14),
		Neck = hold(0, 8),
	},
}
C.bow = { -- draw and loose
	dur = 0.45,
	joints = {
		LeftShoulder = hold(90, 0, -6),
		LeftElbow = hold(2),
		RightShoulder = { K(0, 90, 0, 0), K(0.3, 90, 0, -16), K(0.36, 90, 0, 20), K(0.45, 80, 0, 10) },
		RightElbow = { K(0, 10), K(0.3, 140), K(0.36, 20), K(0.45, 30) },
		Waist = hold(0, 50),
		Neck = hold(0, -46),
	},
}
C.throw = { -- stars, boomerangs, thrown axes and shields
	dur = 0.36,
	joints = {
		RightShoulder = { K(0, 170, 0, 30), K(0.12, 60, 0, 0), K(0.24, 40, 0, -10), K(0.36, 30, 0, 14) },
		RightElbow = { K(0, 70), K(0.12, 4), K(0.36, 30) },
		LeftShoulder = hold(60, 0, -30),
		Waist = { K(0, 4, 30), K(0.12, -10, -24), K(0.36, 0, 0) },
	},
}
C.lash = { -- whips, rope darts, yo-yos: a wide fling from the shoulder
	dur = 0.42,
	joints = {
		RightShoulder = { K(0, 160, 0, 60), K(0.16, 150, 0, 70), K(0.28, 70, 0, -20), K(0.42, 40, 0, 14) },
		RightElbow = { K(0, 80), K(0.16, 90), K(0.28, 0), K(0.42, 30) },
		RightWrist = { K(0, 0), K(0.28, -40), K(0.42, 0) },
		LeftShoulder = hold(30, 0, -30),
		Waist = { K(0, 4, 36), K(0.28, -6, -30), K(0.42, 0, 0) },
	},
}

-- Weapon holds (2026-11-18, the weapon meshes): while the weapon is held (key 2) and the hero stands, runs or
-- jumps with no action playing, the arms take the weapon's ready stance over the Animator's arm swing (the legs
-- keep walking). Each weapon's meshes (art/blender/weapons.py, Config.WeaponArt) are posed for its stance and
-- its swings: blades held up and forward, blasters and spears along the arm so they aim where the arm points,
-- shields on the back of the forearm so they face forward with the forearm raised, the bow upright with the
-- arm out. tests/weapon_art_test.luau poses the rig and checks every weapon clears the ground and the head.
C.holdFists = { -- a boxer's guard
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(52, 0, -14),
		RightElbow = hold(100),
		LeftShoulder = hold(60, 0, 14),
		LeftElbow = hold(108),
	},
}
C.holdOne = { -- the blade up and forward, the free hand relaxed
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(14, 0, 6),
		RightElbow = hold(48),
		LeftShoulder = hold(10, 0, -8),
		LeftElbow = hold(28),
	},
}
C.holdTwo = { -- both hands forward on the hilt, the blade raised
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(30, 0, -16),
		RightElbow = hold(46),
		LeftShoulder = hold(36, 0, 22),
		LeftElbow = hold(50),
	},
}
C.holdDual = { -- a blade in each hand, both up and forward
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(14, 0, 8),
		RightElbow = hold(48),
		LeftShoulder = hold(14, 0, -8),
		LeftElbow = hold(48),
	},
}
C.holdShield = { -- the shield arm up in front of the chest (the shield faces forward), the sword arm ready
	dur = 1,
	loop = true,
	joints = {
		LeftShoulder = hold(35, 0, 20),
		LeftElbow = hold(125),
		RightShoulder = hold(14, 0, 6),
		RightElbow = hold(48),
	},
}
C.holdRanged = { -- low ready: the blaster forward and a little down
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(30, 0, -6),
		RightElbow = hold(34),
		LeftShoulder = hold(10, 0, -6),
		LeftElbow = hold(20),
	},
}
C.holdLong = { -- rifles and crossbows: low ready, the other hand forward under the barrel
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(30, 0, -10),
		RightElbow = hold(34),
		LeftShoulder = hold(40, 0, 26),
		LeftElbow = hold(50),
	},
}
C.holdTwin = { -- a blaster in each hand at low ready
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(30, 0, -6),
		RightElbow = hold(34),
		LeftShoulder = hold(30, 0, 6),
		LeftElbow = hold(34),
	},
}
C.holdBow = { -- the bow upright in the left hand, a little forward
	dur = 1,
	loop = true,
	joints = {
		LeftShoulder = hold(40, 0, -8),
		LeftElbow = hold(30),
		RightShoulder = hold(10, 0, 6),
		RightElbow = hold(20),
	},
}
C.holdPole = { -- spears and staffs levelled forward, the left hand back along the shaft
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(26, 0, 0),
		RightElbow = hold(64),
		LeftShoulder = hold(36, 0, 26),
		LeftElbow = hold(54),
	},
}
C.holdExotic = { -- whips, yo-yos and rope darts hang from the hand, held out a little
	dur = 1,
	loop = true,
	joints = {
		RightShoulder = hold(16, 0, 8),
		RightElbow = hold(40),
		LeftShoulder = hold(10, 0, -8),
		LeftElbow = hold(28),
	},
}

-- the left hand's versions
C.punchL = HeroAnim.mirror(C.punch)
C.blastL = HeroAnim.mirror(C.blast)
C.slashL = HeroAnim.mirror(C.slash)

-- The power paths' signature casts (nate's playtest 2026-11-18: "animations for all attacks/powers... my character
-- should have an animation"). Every one moves the whole body: a set stance (hips and knees), an anticipation
-- before the release, the release itself, then a follow-through. HeroAnim.castClip picks them by path and shape.
C.palmPush = { -- Pulse, Tide: both palms driven forward from the hip
	dur = 0.55,
	joints = {
		RightShoulder = {
			K(0, 10, 0, 30),
			K(0.14, -10, 0, 40),
			K(0.24, 90, 0, 8),
			K(0.42, 88, 0, 8),
			K(0.55, 30, 0, 20),
		},
		LeftShoulder = {
			K(0, 10, 0, -30),
			K(0.14, -10, 0, -40),
			K(0.24, 90, 0, -8),
			K(0.42, 88, 0, -8),
			K(0.55, 30, 0, -20),
		},
		RightElbow = { K(0, 60), K(0.14, 110), K(0.24, 0), K(0.55, 30) },
		LeftElbow = { K(0, 60), K(0.14, 110), K(0.24, 0), K(0.55, 30) },
		RightWrist = { K(0, 0), K(0.24, 70), K(0.55, 0) },
		LeftWrist = { K(0, 0), K(0.24, 70), K(0.55, 0) },
		Waist = { K(0, 0), K(0.14, 14), K(0.24, -16), K(0.55, 0) },
		RightHip = { K(0, 0), K(0.24, -24), K(0.55, 0) },
		LeftHip = { K(0, 0), K(0.24, 34), K(0.55, 0) },
		LeftKnee = { K(0, 0), K(0.24, -30), K(0.55, 0) },
		RightKnee = { K(0, 0), K(0.24, -16), K(0.55, 0) },
		Root = { K(0, 0, 0, 0, 0), K(0.24, 0, 0, 0, -0.35), K(0.55, 0, 0, 0, 0) },
	},
}
C.hurl = { -- Fire, Volt, Gadgeteer: a pitcher's wind-up and throw, the off arm pointing at the target
	dur = 0.55,
	joints = {
		RightShoulder = { K(0, 0, 0, 20), K(0.16, 160, 0, 40), K(0.28, 70, 0, 4), K(0.55, 20, 0, 16) },
		RightElbow = { K(0, 30), K(0.16, 90), K(0.28, 0), K(0.55, 30) },
		LeftShoulder = { K(0, 20, 0, -10), K(0.16, 88, 0, -6), K(0.28, 30, 0, -30), K(0.55, 10, 0, -14) },
		Waist = { K(0, 0), K(0.16, 10, 36), K(0.28, -18, -30), K(0.55, 0, 0) },
		Neck = { K(0, 0), K(0.16, 0, -30), K(0.28, 0, 20), K(0.55, 0, 0) },
		LeftHip = { K(0, 0), K(0.16, 50), K(0.28, 30), K(0.55, 0) },
		LeftKnee = { K(0, 0), K(0.16, -60), K(0.28, -20), K(0.55, 0) },
		RightHip = { K(0, 0), K(0.28, -30), K(0.55, 0) },
		Root = { K(0, 0, 0, 0, 0), K(0.28, 0, 0, 0, -0.3), K(0.55, 0, 0, 0, 0) },
	},
}
C.stomp = { -- Earth, Titan, Colossus: knee up high, then the foot and both fists come down together
	dur = 0.6,
	joints = {
		RightHip = { K(0, 0), K(0.2, 100, 0, 10), K(0.32, 10, 0, 14), K(0.6, 0) },
		RightKnee = { K(0, 0), K(0.2, -100), K(0.32, -10), K(0.6, 0) },
		LeftKnee = { K(0, 0), K(0.2, -10), K(0.32, -50), K(0.6, 0) },
		LeftHip = { K(0, 0), K(0.32, 40), K(0.6, 0) },
		RightShoulder = { K(0, 20, 0, 20), K(0.2, 150, 0, 30), K(0.32, -10, 0, 40), K(0.6, 10, 0, 20) },
		LeftShoulder = { K(0, 20, 0, -20), K(0.2, 150, 0, -30), K(0.32, -10, 0, -40), K(0.6, 10, 0, -20) },
		RightElbow = { K(0, 40), K(0.2, 60), K(0.32, 10), K(0.6, 30) },
		LeftElbow = { K(0, 40), K(0.2, 60), K(0.32, 10), K(0.6, 30) },
		Waist = { K(0, 0), K(0.2, 16), K(0.32, -30), K(0.6, 0) },
		Root = { K(0, 0, 0, 0, 0), K(0.2, 0, 0, 0, 0.4), K(0.32, 0, 0, 0, -0.8), K(0.6, 0, 0, 0, 0) },
	},
}
C.sweep = { -- Frost, Spirit: a wide arm sweep from one side to the other, turning the whole body
	dur = 0.6,
	joints = {
		RightShoulder = { K(0, 30, 0, 20), K(0.16, 70, 0, 90), K(0.4, 80, 0, -10), K(0.6, 20, 0, 20) },
		RightElbow = { K(0, 60), K(0.16, 10), K(0.4, 10), K(0.6, 40) },
		LeftShoulder = { K(0, 20, 0, -20), K(0.16, 40, 0, -10), K(0.4, 60, 0, -80), K(0.6, 10, 0, -20) },
		LeftElbow = { K(0, 40), K(0.4, 10), K(0.6, 40) },
		Waist = { K(0, 0), K(0.16, 0, -40), K(0.4, -8, 40), K(0.6, 0, 0) },
		Neck = { K(0, 0), K(0.16, 0, 20), K(0.4, 0, -20), K(0.6, 0, 0) },
		RightHip = { K(0, 0), K(0.4, -20, 0, 14), K(0.6, 0) },
		LeftHip = { K(0, 0), K(0.4, 26, 0, -14), K(0.6, 0) },
		LeftKnee = { K(0, 0), K(0.4, -34), K(0.6, 0) },
		Root = { K(0, 0, 0, 0, 0), K(0.4, 0, 0, 0, -0.4), K(0.6, 0, 0, 0, 0) },
	},
}
C.quickDraw = { -- Gunslinger: the hand snaps to the hip, up and fires, with a recoil kick and a step back
	dur = 0.45,
	joints = {
		RightShoulder = {
			K(0, 0, 0, 10),
			K(0.08, -10, 0, 20),
			K(0.16, 92, 0, 0),
			K(0.24, 110, 0, 0),
			K(0.45, 40, 0, 12),
		},
		RightElbow = { K(0, 30), K(0.08, 90), K(0.16, 0), K(0.24, 20), K(0.45, 40) },
		LeftShoulder = { K(0, 20), K(0.16, 84, 0, 10), K(0.45, 20) },
		LeftElbow = { K(0, 60), K(0.16, 40), K(0.45, 60) },
		Waist = { K(0, 0), K(0.16, 0, -30), K(0.24, 10, -30), K(0.45, 0, 0) },
		Neck = { K(0, 0), K(0.16, 0, 26), K(0.45, 0, 0) },
		RightHip = { K(0, 0), K(0.16, -26), K(0.45, 0) },
		LeftHip = { K(0, 0), K(0.16, 20), K(0.45, 0) },
		LeftKnee = { K(0, 0), K(0.16, -24), K(0.45, 0) },
	},
}
C.vanish = { -- Shadow: a low crouch, the cloak arm across the face, then a spring up and out
	dur = 0.6,
	joints = {
		RightShoulder = { K(0, 20), K(0.2, 100, 0, -40), K(0.4, 60, 0, 60), K(0.6, 20, 0, 20) },
		RightElbow = { K(0, 40), K(0.2, 120), K(0.4, 10), K(0.6, 40) },
		LeftShoulder = { K(0, 20), K(0.2, -30, 0, -30), K(0.4, 40, 0, -70), K(0.6, 20, 0, -20) },
		Waist = { K(0, 0), K(0.2, -30), K(0.4, 6), K(0.6, 0) },
		Neck = { K(0, 0), K(0.2, -14), K(0.6, 0) },
		RightHip = { K(0, 0), K(0.2, 60), K(0.4, 10), K(0.6, 0) },
		LeftHip = { K(0, 0), K(0.2, 40), K(0.4, -10), K(0.6, 0) },
		RightKnee = { K(0, 0), K(0.2, -90), K(0.4, -10), K(0.6, 0) },
		LeftKnee = { K(0, 0), K(0.2, -80), K(0.4, -10), K(0.6, 0) },
		Root = { K(0, 0, 0, 0, 0), K(0.2, 0, 0, 0, -1.1), K(0.4, 0, 0, 0, 0.2), K(0.6, 0, 0, 0, 0) },
	},
}
C.combo3 = { -- Martial: jab, cross, and a spinning back kick
	dur = 0.75,
	joints = {
		LeftShoulder = { K(0, 50, 0, -10), K(0.08, 92, 0, -4), K(0.16, 50, 0, -10), K(0.75, 40, 0, -14) },
		LeftElbow = { K(0, 100), K(0.08, 4), K(0.16, 100), K(0.75, 90) },
		RightShoulder = {
			K(0, 50, 0, 10),
			K(0.16, 50, 0, 10),
			K(0.24, 92, 0, 4),
			K(0.34, 40, 0, 30),
			K(0.75, 30, 0, 20),
		},
		RightElbow = { K(0, 100), K(0.24, 4), K(0.34, 90), K(0.75, 90) },
		Waist = { K(0, 0, 10), K(0.08, 0, 20), K(0.24, -6, -26), K(0.4, 0, 60), K(0.75, 0, 0) },
		RightHip = { K(0, 0), K(0.4, 20), K(0.52, 90, 0, 30), K(0.62, 80, 0, 30), K(0.75, 0) },
		RightKnee = { K(0, 0), K(0.4, -60), K(0.52, -4), K(0.75, 0) },
		LeftKnee = { K(0, -10), K(0.52, -24), K(0.75, 0) },
		Root = { K(0, 0, 0, 0, 0), K(0.34, 0, 0, 0, 0), K(0.62, 0, -180, 0, 0), K(0.75, 0, -360, 0, 0) },
	},
}
C.charge2 = { -- Juggernaut: the shoulder dropped, a heavy run-in step and a ram
	dur = 0.55,
	joints = {
		Waist = { K(0, 0), K(0.16, -34, 20), K(0.34, -30, 30), K(0.55, 0, 0) },
		RightShoulder = { K(0, 20, 0, 10), K(0.16, 40, 0, 50), K(0.34, 60, 0, 70), K(0.55, 20, 0, 20) },
		RightElbow = { K(0, 60), K(0.16, 100), K(0.55, 60) },
		LeftShoulder = { K(0, 20, 0, -10), K(0.16, -30, 0, -20), K(0.55, 10, 0, -14) },
		LeftElbow = hold(90),
		RightHip = { K(0, 0), K(0.16, 50), K(0.34, -30), K(0.55, 0) },
		LeftHip = { K(0, 0), K(0.16, -30), K(0.34, 50), K(0.55, 0) },
		RightKnee = { K(0, 0), K(0.16, -50), K(0.34, -10), K(0.55, 0) },
		LeftKnee = { K(0, 0), K(0.16, -10), K(0.34, -60), K(0.55, 0) },
		Root = { K(0, 0, 0, 0, 0), K(0.16, 0, 0, 0, -0.4), K(0.55, 0, 0, 0, 0) },
	},
}
C.temple = { -- Mind: two fingers to the temple, then the other hand thrust out at the target
	dur = 0.65,
	joints = {
		RightShoulder = { K(0, 20, 0, 20), K(0.18, 120, 0, 60), K(0.65, 30, 0, 20) },
		RightElbow = { K(0, 40), K(0.18, 140), K(0.5, 140), K(0.65, 40) },
		LeftShoulder = {
			K(0, 20, 0, -20),
			K(0.18, 30, 0, -30),
			K(0.3, 92, 0, -4),
			K(0.52, 92, 0, -4),
			K(0.65, 20, 0, -20),
		},
		LeftElbow = { K(0, 40), K(0.18, 90), K(0.3, 0), K(0.65, 40) },
		LeftWrist = { K(0, 0), K(0.3, 60), K(0.65, 0) },
		Waist = { K(0, 0), K(0.18, 10, -10), K(0.3, -6, 20), K(0.65, 0, 0) },
		Neck = { K(0, 0), K(0.18, -20), K(0.3, 10), K(0.65, 0) },
		LeftHip = { K(0, 0), K(0.3, 24), K(0.65, 0) },
		LeftKnee = { K(0, 0), K(0.3, -20), K(0.65, 0) },
	},
}
C.raise =
	{ -- Light, Spirit's supers and every Mystic buff: arms rise overhead, the chest lifts, up on the toes
		dur = 0.75,
		joints = {
			RightShoulder = {
				K(0, 10, 0, 20),
				K(0.25, 70, 0, 60),
				K(0.45, 170, 0, 20),
				K(0.62, 170, 0, 20),
				K(0.75, 20, 0, 20),
			},
			LeftShoulder = {
				K(0, 10, 0, -20),
				K(0.25, 70, 0, -60),
				K(0.45, 170, 0, -20),
				K(0.62, 170, 0, -20),
				K(0.75, 20, 0, -20),
			},
			RightElbow = { K(0, 30), K(0.45, 10), K(0.75, 30) },
			LeftElbow = { K(0, 30), K(0.45, 10), K(0.75, 30) },
			Waist = { K(0, 0), K(0.25, -10), K(0.45, 18), K(0.75, 0) },
			Neck = { K(0, 0), K(0.45, 26), K(0.75, 0) },
			RightHip = { K(0, 0), K(0.25, 20), K(0.45, -6), K(0.75, 0) },
			LeftHip = { K(0, 0), K(0.25, 20), K(0.45, -6), K(0.75, 0) },
			RightKnee = { K(0, 0), K(0.25, -40), K(0.45, 0), K(0.75, 0) },
			LeftKnee = { K(0, 0), K(0.25, -40), K(0.45, 0), K(0.75, 0) },
			Root = {
				K(0, 0, 0, 0, 0),
				K(0.25, 0, 0, 0, -0.4),
				K(0.45, 0, 0, 0, 0.5),
				K(0.62, 0, 0, 0, 0.5),
				K(0.75, 0, 0, 0, 0),
			},
		},
	}
C.ground = { -- Earth, Tide and Colossus areas: a crouch, both palms slapped to the ground
	dur = 0.6,
	joints = {
		RightShoulder = { K(0, 20, 0, 20), K(0.2, 150, 0, 20), K(0.34, 60, 0, 30), K(0.6, 20, 0, 20) },
		LeftShoulder = { K(0, 20, 0, -20), K(0.2, 150, 0, -20), K(0.34, 60, 0, -30), K(0.6, 20, 0, -20) },
		RightElbow = { K(0, 30), K(0.34, 0), K(0.6, 30) },
		LeftElbow = { K(0, 30), K(0.34, 0), K(0.6, 30) },
		Waist = { K(0, 0), K(0.2, 10), K(0.34, -50), K(0.6, 0) },
		RightHip = { K(0, 0), K(0.34, 70), K(0.6, 0) },
		LeftHip = { K(0, 0), K(0.34, 20, 0, -20), K(0.6, 0) },
		RightKnee = { K(0, 0), K(0.34, -100), K(0.6, 0) },
		LeftKnee = { K(0, 0), K(0.34, -60), K(0.6, 0) },
		Root = { K(0, 0, 0, 0, 0), K(0.34, 0, 0, 0, -1.3), K(0.6, 0, 0, 0, 0) },
	},
}

-- The standing brace under any cast that leaves the legs alone (HeroAnimator adds it only while the hero
-- stands: a running hero's legs stay the Animator's): feet set apart, knees soft, a small dip
C.brace = {
	dur = 1,
	loop = true,
	joints = {
		RightHip = hold(-16, 0, 8),
		LeftHip = hold(22, 0, -8),
		RightKnee = hold(-14),
		LeftKnee = hold(-26),
		Root = hold(0, 0, 0, -0.3),
	},
}

HeroAnim.CLIPS = C

-- the mode pose for a hero: nil means the Animator's own (ground walk, idle and jump). current: the pose it
-- has now, so hover and fly (and the Downed kneel and crawl) switch with a margin instead of flickering.
function HeroAnim.modeClip(mode: string?, speed: number, downed: boolean, current: string?): string?
	if downed then
		local still = if current == "downedMove" then speed < 1.5 else speed < 3
		return if still then "downed" else "downedMove"
	end
	if mode == nil or mode == "ground" then
		return nil
	end
	if mode == "fly" then
		local limit = if current == "hover" then HeroAnim.hoverSpeed + 4 else HeroAnim.hoverSpeed - 4
		return if speed < limit then "hover" else "fly"
	end
	if C[mode] then
		return mode
	end
	return "air"
end

local HOLD_CLIPS = { -- per weapon family: the M1 combo, then what its skills use by shape
	fists = { combo = { "punch", "punchL", "kick" } },
	one = { combo = { "slash", "backslash", "overhead" } },
	two = { combo = { "heavy", "heavy", "heavyOver" } },
	dual = { combo = { "slash", "slashL", "spin" } },
	shield = { combo = { "slash", "bash", "overhead" } },
	ranged = { combo = { "shoot", "shoot", "shoot" } },
	exotic = { combo = { "lash", "lash", "lash" } },
}
HeroAnim.HOLD_CLIPS = HOLD_CLIPS

-- spears and staffs thrust, bows draw, stars and boomerangs are thrown (by weapon id)
local WEAPON_CLIPS: { [number]: { string } } = {
	[14] = { "thrust", "thrust", "heavyOver" }, -- Spear
	[16] = { "thrust", "spin", "heavyOver" }, -- Bo Staff
	[28] = { "bow", "bow", "bow" }, -- Bow
	[29] = { "shoot", "shoot", "shoot" }, -- Crossbow
	[31] = { "throw", "throw", "throw" }, -- Throwing Stars
	[33] = { "slash", "backslash", "spin" }, -- War Fan
	[36] = { "throw", "throw", "throw" }, -- Boomerang
}
HeroAnim.WEAPON_CLIPS = WEAPON_CLIPS

-- the held weapon's ready stance: by family, with the weapons that stand their own way (by weapon id)
local HOLD_FAMILY: { [string]: string } = {
	fists = "holdFists",
	one = "holdOne",
	two = "holdTwo",
	dual = "holdDual",
	shield = "holdShield",
	ranged = "holdRanged",
	exotic = "holdExotic",
}
local HOLD_WEAPON: { [number]: string } = {
	[14] = "holdPole", -- Spear
	[16] = "holdPole", -- Bo Staff
	[26] = "holdTwin", -- Twin Blasters
	[27] = "holdLong", -- Blaster Rifle
	[28] = "holdBow", -- Bow
	[29] = "holdLong", -- Crossbow
	[31] = "holdOne", -- Throwing Stars
	[33] = "holdOne", -- War Fan
	[36] = "holdOne", -- Boomerang
}
HeroAnim.HOLD_FAMILY = HOLD_FAMILY
HeroAnim.HOLD_WEAPON = HOLD_WEAPON

-- the stance clip for a held weapon (nil: none), by its id and family
function HeroAnim.holdClip(weaponId: number?, family: string?): string?
	local own = weaponId and HOLD_WEAPON[weaponId]
	if own then
		return own
	end
	return if family then HOLD_FAMILY[family] else nil
end

-- the mode poses a weapon stance shows over: standing, running and jumping (the Animator's own poses, and
-- the air pose); flying, gliding, swimming, wall runs, rides and the Downed poses keep their own arms
function HeroAnim.holdsIn(modeClip: string?): boolean
	return modeClip == nil or modeClip == "air"
end
HeroAnim.holdBlend = 0.18 -- the stance fades in and out this long (a swap to or from the weapon)
HeroAnim.holdWeight = 0.92 -- and shows this much over the Animator's arm swing (a little sway stays)

-- a power's skill or super by its shape
local SHAPE_CLIPS: { [string]: string } = {
	bolt = "blast",
	line = "blast",
	chain = "blast",
	cone = "blast",
	arc = "punch",
	nova = "nova",
	area = "slam",
	field = "buff",
	buff = "buff",
	summon = "buff",
	place = "buff",
	decoy = "buff",
	dash = "lunge",
	leap = "lunge",
	ride = "buff",
	launch = "uppercut",
	throw = "throw",
	wall = "slam",
	ramp = "slam",
}
HeroAnim.SHAPE_CLIPS = SHAPE_CLIPS

-- Shapes in four groups for the paths' own moves: aimed (at a target), around (an area round the hero),
-- self (a buff, a field, a summon) and move (a dash, a leap)
local SHAPE_GROUP: { [string]: string } = {
	bolt = "aimed",
	line = "aimed",
	chain = "aimed",
	cone = "aimed",
	arc = "aimed",
	throw = "aimed",
	launch = "aimed",
	nova = "around",
	area = "around",
	wall = "around",
	ramp = "around",
	field = "self",
	buff = "self",
	summon = "self",
	place = "self",
	decoy = "self",
	ride = "self",
	dash = "move",
	leap = "move",
}
HeroAnim.SHAPE_GROUP = SHAPE_GROUP

-- Each path's signature moves by shape group (nate's playtest 2026-11-18); "other" covers the rest. Blade keeps
-- its sword swings (castClip below) and weapons their own sets.
local PATH_CLIPS: { [string]: { [string]: string } } = {
	Volt = { aimed = "hurl", around = "nova", self = "raise", move = "lunge" },
	Frost = { aimed = "sweep", around = "ground", self = "raise", move = "lunge" },
	Fire = { aimed = "hurl", around = "nova", self = "raise", move = "lunge" },
	Earth = { aimed = "stomp", around = "ground", self = "raise", move = "charge2" },
	Tide = { aimed = "palmPush", around = "ground", self = "sweep", move = "lunge" },
	Gunslinger = { aimed = "quickDraw", around = "spin", self = "quickDraw", move = "lunge" },
	Gadgeteer = { aimed = "hurl", around = "throw", self = "buff", move = "lunge" },
	Shadow = { aimed = "vanish", around = "spin", self = "vanish", move = "vanish" },
	Titan = { aimed = "uppercut", around = "stomp", self = "buff", move = "charge2" },
	Martial = { aimed = "combo3", around = "kick", self = "buff", move = "lunge" },
	Juggernaut = { aimed = "charge2", around = "slam", self = "buff", move = "charge2" },
	Colossus = { aimed = "stomp", around = "ground", self = "buff", move = "charge2" },
	Pulse = { aimed = "palmPush", around = "nova", self = "raise", move = "lunge" },
	Mind = { aimed = "temple", around = "nova", self = "raise", move = "lunge" },
	Spirit = { aimed = "sweep", around = "raise", self = "raise", move = "lunge" },
	Light = { aimed = "blast2", around = "raise", self = "raise", move = "lunge" },
}
HeroAnim.PATH_CLIPS = PATH_CLIPS

-- Whether a clip moves the legs itself (else HeroAnimator sets the standing brace under it)
function HeroAnim.movesLegs(name: string): boolean
	local clip = C[name]
	return clip ~= nil and (clip.joints.RightHip ~= nil or clip.joints.LeftHip ~= nil)
end

-- The clip an ability row plays when cast. row: a Config.Abilities row (shape, slot, set, sword, channel,
-- weapon); family: the weapon's family id when row.weapon is set; step: the combo step (1, 2, 3...).
function HeroAnim.castClip(row: any, family: string?, step: number?): string
	local s = math.max(1, step or 1)
	local shape = row.shape or ""
	if row.channel and shape == "bolt" then
		return "channel"
	end
	if row.weapon and family then
		local per = WEAPON_CLIPS[row.weapon] or (HOLD_CLIPS[family] or HOLD_CLIPS.fists).combo
		if row.slot == "basic" or row.weaponKey == "M1" then
			return per[(s - 1) % #per + 1]
		end
		if shape == "dash" or shape == "leap" then
			return "lunge"
		elseif shape == "nova" then
			return if family == "ranged" then "nova" else "spin"
		elseif shape == "area" then
			return if family == "ranged"
				then "shoot"
				else (if family == "two" then "heavyOver" else "overhead")
		elseif shape == "buff" or shape == "field" then
			return if family == "shield" then "block" else "buff"
		end
		return per[3]
	end
	-- the power path's own move for its skills and supers (the basic attack keeps its quick combo)
	local sig = PATH_CLIPS[row.set or ""]
	if sig and row.slot ~= "basic" then
		local pick = sig[SHAPE_GROUP[shape] or "other"] or sig.other
		if pick then
			return pick
		end
	end
	if row.slot == "super" then
		return if shape == "bolt"
				or shape == "line"
				or shape == "cone"
			then "blast2"
			else (SHAPE_CLIPS[shape] or "nova")
	end
	if row.slot == "basic" then
		if row.sword or row.set == "Blade" then
			local seq = { "slash", "backslash", "overhead" }
			return seq[(s - 1) % 3 + 1]
		end
		if shape == "arc" then
			local seq = { "punch", "punchL", "uppercut" }
			return seq[(s - 1) % 3 + 1]
		end
		return if s % 2 == 0 then "blastL" else "blast"
	end
	if (row.sword or row.set == "Blade") and (shape == "arc" or shape == "line") then
		return "overhead"
	end
	return SHAPE_CLIPS[shape] or "blast"
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

-- one joint's angles at time t (seconds into the clip)
function HeroAnim.sampleKeys(keys: { Key }, t: number, dur: number, loop: boolean?): { number }
	local n = #keys
	if n == 1 then
		local k = keys[1]
		return { k[2], k[3], k[4], k[5] }
	end
	if loop then
		t = t % dur
	else
		t = math.clamp(t, 0, dur)
	end
	if t <= keys[1][1] then
		local k = keys[1]
		return { k[2], k[3], k[4], k[5] }
	end
	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local span = b[1] - a[1]
			local f = if span > 0 then smooth((t - a[1]) / span) else 1
			return {
				a[2] + (b[2] - a[2]) * f,
				a[3] + (b[3] - a[3]) * f,
				a[4] + (b[4] - a[4]) * f,
				a[5] + (b[5] - a[5]) * f,
			}
		end
	end
	local k = keys[n]
	return { k[2], k[3], k[4], k[5] }
end

function HeroAnim.sample(name: string, t: number): Angles
	local clip = C[name]
	local out: Angles = {}
	if not clip then
		return out
	end
	for joint, keys in clip.joints do
		out[joint] = HeroAnim.sampleKeys(keys, t, clip.dur, clip.loop)
	end
	return out
end

-- how much of an action shows at time t (fades in, holds, fades out; 0 once it is over)
function HeroAnim.actionWeight(t: number, dur: number): number
	if t < 0 or t >= dur then
		return 0
	end
	local fin = math.min(1, t / HeroAnim.fadeIn)
	local fout = math.min(1, (dur - t) / HeroAnim.fadeOut)
	return math.clamp(math.min(fin, fout), 0, 1)
end

return HeroAnim
